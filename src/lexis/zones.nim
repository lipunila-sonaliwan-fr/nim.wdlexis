# Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr
#   wdlexis+ - base de données DuckDB et zones de travail (façon dBase)
#
# La base du programme est ouverte à la première requête : par défaut le
# fichier « donnees.duckdb » du dossier du programme ; ouvrirbase(chemin)
# en choisit une autre (":memoire:" pour une base en mémoire).
#
# Une zone est une table SQL ouverte par « utiliser », parcourue
# enregistrement par enregistrement dans l'ordre et selon le filtre donnés.

import std/[tables, os, strutils]
from std/unicode import toUpper
import core, duck

export duck.DuckError, duck.QueryResult

type
  ZoneError* = object of CatchableError

  Base* = ref object of RootObj
    conn*: Connection
    path*: string

  Zone* = ref object
    alias*, table*: string
    keyCol*: string            # colonne clef (clef primaire) ou rowid
    columns*: seq[string]      # noms réels
    upCols*: seq[string]       # noms en majuscules
    order*, filter*: string
    keys*: seq[Value]
    pos*: int                  # 0..keys.len (keys.len = fin de fichier)
    bof*, found*, deleted*: bool
    cache: seq[Value]
    cacheOk: bool
    locCond*: Expr             # condition du dernier « localiser »

  ZoneState* = ref object of RootObj
    zones*: OrderedTable[string, Zone]
    current*: string

proc zerr(msg: string) {.noreturn.} = raise newException(ZoneError, msg)

# ------------------------------------------------------------------ base

proc programDir(L: Interp): string =
  if L.scriptPath.len > 0: L.scriptPath.parentDir else: getCurrentDir()

proc baseOf(L: Interp): Base =
  let r = L.ext.getOrDefault("base")
  if r.isNil:
    result = Base()
    L.ext["base"] = result
    let b = result
    L.closers.add proc () =
      if not b.conn.isNil:
        b.conn.close()
        b.conn = nil
  else: result = Base(r)

proc openBase*(L: Interp, path: string) =
  ## Ouvre la base `path` (relative au dossier du programme) à la place de la base courante.
  let b = L.baseOf
  let full = if path in [":memoire:", ":memory:"] or isAbsolute(path): path else: L.programDir / path
  let c = openConnection(full, [L.programDir])
  if not b.conn.isNil: b.conn.close()
  b.conn = c
  b.path = c.path

proc closeBase*(L: Interp) =
  let b = L.baseOf
  if not b.conn.isNil:
    b.conn.close()
    b.conn = nil
    b.path = ""

proc basePath*(L: Interp): string =
  let b = L.baseOf
  if b.conn.isNil: "" else: b.path

proc connection(L: Interp): Connection =
  let b = L.baseOf
  if b.conn.isNil: L.openBase(L.programDir / "donnees.duckdb")
  b.conn

proc toCell(v: Value): DbCell =
  case v.kind
  of vkNil: DbCell(kind: ckNull)
  of vkBool: DbCell(kind: ckBool, b: v.b)
  of vkInt: DbCell(kind: ckInt, i: v.i)
  of vkNum: DbCell(kind: ckFloat, f: v.n)
  of vkStr: DbCell(kind: ckText, s: v.s)
  else: zerr("sql : valeur de type " & typeName(v) & " non prise en charge en paramètre")

proc fromCell(c: DbCell): Value =
  case c.kind
  of ckNull: nilV
  of ckBool: boolV(c.b)
  of ckInt: intV(c.i)
  of ckFloat: numV(c.f)
  of ckText: strV(c.s)

proc query*(L: Interp, sql: string, params: openArray[Value] = []): QueryResult =
  var cells: seq[DbCell]
  for p in params: cells.add toCell(p)
  try: L.connection.exec(sql, cells)
  except DuckError as e: zerr("sql : " & e.msg)

proc valueRows*(r: QueryResult): seq[seq[Value]] =
  for row in r.rows:
    var l = newSeq[Value](row.len)
    for i, c in row: l[i] = fromCell(c)
    result.add l

proc rowsToValue*(r: QueryResult): Value =
  ## Liste de lignes ; chaque ligne est une table colonne (majuscules) -> valeur.
  let t = newLTable(r.rows.len)
  var ups: seq[string]
  for c in r.columns: ups.add toUpper(c)
  for row in r.rows:
    let l = newLTable()
    for i, c in row:
      if c.kind != ckNull: l.rawSet(ups[i], fromCell(c))
    t.arr.add tableV(l)
  tableV(t)

proc firstValue*(r: QueryResult): Value =
  if r.rows.len > 0 and r.rows[0].len > 0: fromCell(r.rows[0][0]) else: nilV

# ------------------------------------------------------------------ zones

proc zoneState*(L: Interp): ZoneState =
  let r = L.ext.getOrDefault("zones")
  if r.isNil:
    result = ZoneState()
    L.ext["zones"] = result
  else: result = ZoneState(r)

proc currentZone*(L: Interp): Zone =
  let s = L.zoneState
  if s.current != "" and s.zones.hasKey(s.current): s.zones[s.current] else: nil

proc requireZone*(L: Interp): Zone =
  result = L.currentZone
  if result.isNil: zerr("aucune table ouverte dans la zone courante (instruction « utiliser »)")

proc zoneByAlias*(L: Interp, alias: string): Zone =
  let s = L.zoneState
  let a = toUpper(alias)
  if not s.zones.hasKey(a): zerr("alias inconnu : " & a)
  s.zones[a]

proc keySql(z: Zone): string =
  if z.keyCol == "rowid": "rowid" else: quoteIdent(z.keyCol)

proc reload*(L: Interp, z: Zone) =
  var sql = "select " & keySql(z) & " from " & quoteIdent(z.table)
  if z.filter != "": sql &= " where " & z.filter
  sql &= " order by " & (if z.order != "": z.order else: keySql(z))
  let r = L.query(sql)
  z.keys.setLen(0)
  for row in r.rows: z.keys.add fromCell(row[0])
  z.cacheOk = false
  if z.pos > z.keys.len: z.pos = z.keys.len

proc openZone*(L: Interp, table, alias, order, filter: string) =
  if not validIdent(table): zerr("nom de table invalide : " & table)
  let info = L.query("select name, pk from pragma_table_info('" & table.replace("'", "''") & "')")
  if info.rows.len == 0: zerr("table inconnue : " & table)
  let z = Zone(table: table, alias: alias, order: order, filter: filter)
  var pks: seq[string]
  for row in info.rows:
    let name = row[0].s
    z.columns.add name
    z.upCols.add toUpper(name)
    if row[1].kind == ckBool and row[1].b: pks.add name
  z.keyCol = if pks.len == 1: pks[0] else: "rowid"
  L.reload(z)
  let s = L.zoneState
  s.zones[alias] = z
  s.current = alias

proc closeZone*(L: Interp, alias: string) =
  let s = L.zoneState
  if alias == "*":
    s.zones.clear()
    s.current = ""
  else:
    let a = if alias == "": s.current else: alias
    s.zones.del(a)
    if s.current == a: s.current = ""

proc selectZone*(L: Interp, alias: string) =
  let s = L.zoneState
  let a = toUpper(alias)
  if not s.zones.hasKey(a): zerr("alias inconnu : " & a)
  s.current = a

proc record*(L: Interp, z: Zone): seq[Value] =
  if z.pos < 0 or z.pos >= z.keys.len: return newSeq[Value](z.columns.len)
  if not z.cacheOk:
    var cols: seq[string]
    for c in z.columns: cols.add quoteIdent(c)
    let r = L.query("select " & cols.join(", ") & " from " & quoteIdent(z.table) &
                    " where " & keySql(z) & " = ?", [z.keys[z.pos]])
    z.cache = if r.rows.len > 0: r.valueRows()[0] else: newSeq[Value](z.columns.len)
    z.cacheOk = true
  z.cache

proc fieldIndex*(z: Zone, upName: string): int = z.upCols.find(upName)

proc field*(L: Interp, z: Zone, i: int): Value = L.record(z)[i]

proc realColumn(z: Zone, name: string): string =
  let i = z.upCols.find(toUpper(name))
  if i < 0: zerr("champ inconnu dans " & z.table & " : " & name)
  z.columns[i]

proc moveTo*(z: Zone, pos: int) =
  z.deleted = false
  z.cacheOk = false
  z.bof = false
  if pos < 0:
    z.pos = 0
    z.bof = true
  elif pos > z.keys.len: z.pos = z.keys.len
  else: z.pos = pos

proc eof*(z: Zone): bool = z.pos >= z.keys.len

proc appendRecord*(L: Interp, z: Zone, names: seq[string], vals: seq[Value]) =
  var cols, marks: seq[string]
  for n in names:
    cols.add quoteIdent(realColumn(z, n))
    marks.add "?"
  var sql = "insert into " & quoteIdent(z.table) &
            (if cols.len == 0: " default values"
             else: " (" & cols.join(", ") & ") values (" & marks.join(", ") & ")")
  var key: Value
  if z.keyCol != "rowid":
    sql &= " returning " & quoteIdent(z.keyCol)
    key = L.query(sql, vals).firstValue
  else:
    discard L.query(sql, vals)
    key = L.query("select max(rowid) from " & quoteIdent(z.table)).firstValue
  z.keys.add key
  moveTo(z, z.keys.len - 1)

proc replaceRecord*(L: Interp, z: Zone, names: seq[string], vals: seq[Value]) =
  if z.eof: zerr("« remplacer » en fin de fichier (aucun enregistrement courant)")
  var sets: seq[string]
  var params = vals
  var newKey = nilV
  for i, n in names:
    let col = realColumn(z, n)
    sets.add quoteIdent(col) & " = ?"
    if col == z.keyCol: newKey = vals[i]
  params.add z.keys[z.pos]
  discard L.query("update " & quoteIdent(z.table) & " set " & sets.join(", ") &
                  " where " & keySql(z) & " = ?", params)
  if newKey.kind != vkNil: z.keys[z.pos] = newKey
  z.cacheOk = false

proc deleteRecord*(L: Interp, z: Zone) =
  if z.eof: zerr("« effacer » en fin de fichier (aucun enregistrement courant)")
  discard L.query("delete from " & quoteIdent(z.table) & " where " & keySql(z) & " = ?", [z.keys[z.pos]])
  z.keys.delete(z.pos)
  z.cacheOk = false
  z.deleted = true

proc seekRecord*(L: Interp, z: Zone, v: Value) =
  ## « chercher » : premier enregistrement dont la première colonne de l'ordre vaut v.
  if z.order == "": zerr("« chercher » nécessite une table ouverte avec « ordre »")
  var col = z.order.split(',')[0].strip
  let low = col.toLowerAscii
  if low.endsWith(" desc"): col = col[0 ..< col.len - 5].strip
  elif low.endsWith(" asc"): col = col[0 ..< col.len - 4].strip
  var sql = "select " & keySql(z) & " from " & quoteIdent(z.table) & " where (" & col & ") = ?"
  if z.filter != "": sql &= " and (" & z.filter & ")"
  sql &= " order by " & z.order & " limit 1"
  let r = L.query(sql, [v])
  z.found = false
  if r.rows.len > 0:
    let key = fromCell(r.rows[0][0])
    for i, k in z.keys:
      if rawEquals(k, key):
        moveTo(z, i)
        z.found = true
        break
  if not z.found: moveTo(z, z.keys.len)

proc currentZoneInfo*(L: Interp): string =
  ## Résumé de la zone courante pour le débogueur (« ALIAS : table, enregistrement n / total »).
  let r = L.ext.getOrDefault("zones")
  if r.isNil: return ""
  let z = L.currentZone
  if z.isNil: return ""
  z.alias & " : " & z.table & ", enregistrement " &
    (if z.eof: "fin de fichier" else: $(z.pos + 1)) & " / " & $z.keys.len
