# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet firebird : bases Firebird (serveur 3, 4 ou 5)
#
# Pilote natif écrit en Nim (firebird/fbwire.nim), sur le modèle du pilote
# « pure Java » de Jaybird : le protocole réseau de Firebird est parlé
# directement, sans bibliothèque cliente (fbclient) ni autre dépendance.
# Authentification SRP (Srp256 / Srp), chiffrement du flux Arc4.
#
#   fb = paquet("firebird")
#   db = fb.connecter("localhost:/data/test.fdb", "SYSDBA", "masterkey")
#   db:executer("insert into client(nom) values (?)", "Dupont")
#   pour chaque r dans db:requete("select id, nom from client where id > ?", 10)
#     ? r.id, r.nom
#   suivant
#   db:transaction(@VIREMENT)                    && validée, ou annulée en cas d'erreur
#   db:fermer()
#
# Sans transaction explicite, chaque instruction est validée automatiquement
# (« autocommit »). db:debut() ... db:valider() / db:annuler() ou
# db:transaction(@proc) regroupent plusieurs instructions.
#
# Une base désignée sans hôte (« /data/test.fdb », « C:\base.fdb », alias)
# est ouverte par le serveur local (localhost, port 3050).

import std/[os, strutils, times, math]
import ../lexis/api
from std/unicode import toUpper
import firebird/fbwire

const
  CS_OCTETS = 1

  isc_tpb_version3 = 3'u8
  isc_tpb_consistency = 1'u8
  isc_tpb_concurrency = 2'u8
  isc_tpb_wait = 6'u8
  isc_tpb_nowait = 7'u8
  isc_tpb_read = 8'u8
  isc_tpb_write = 9'u8
  isc_tpb_read_committed = 15'u8
  isc_tpb_rec_version = 17'u8
  isc_tpb_lock_timeout = 21'u8

#
# Erreurs
#

template fbTry(what: string, body: untyped) =
  try:
    body
  except FbError as e:
    rtError("firebird : " & what & " : " & e.msg)

#
# Connexion
#

type
  LFbDb = ref object of LUser
    conn: FbConn
    tr: int32                     # transaction explicite en cours (0 = aucune).
    tpb: seq[uint8]               # options des transactions automatiques.
    closed: bool
    changes: int

var dbMethods {.threadvar.}: LTable

proc buildTpb(o: LTable): seq[uint8] =
  ## Options : isolation ("lecturevalidee" par défaut, "instantane", "serialisable"),
  ## lecture (vrai = lecture seule), attente (vrai, faux ou secondes).
  result = @[isc_tpb_version3]
  result.add(if o.optField("lecture", false): isc_tpb_read else: isc_tpb_write)
  let iso = o.optField("isolation", "lecturevalidee").toLowerAscii.multiReplace(("_", ""), (" ", ""), ("é", "e"))
  case iso
  of "instantane", "snapshot", "concurrency": result.add isc_tpb_concurrency
  of "serialisable", "consistency", "serializable": result.add isc_tpb_consistency
  else:
    result.add isc_tpb_read_committed
    result.add isc_tpb_rec_version
  let att = if o.isNil: nilV else: o.field("attente")
  if att.kind == vkBool and not att.b:
    result.add isc_tpb_nowait
  else:
    result.add isc_tpb_wait
    if att.kind in {vkInt, vkNum}:
      var ok: bool
      let secs = int32(toInteger(att, ok))
      if secs > 0:
        result.add isc_tpb_lock_timeout
        result.add 4'u8
        for k in 0 .. 3: result.add uint8((secs shr (8 * k)) and 0xff)

proc startTr(L: Interp, d: LFbDb, tpb: seq[uint8]): int32 =
  fbTry("début de transaction"):
    L.blocking: result = d.conn.startTransaction(tpb)

proc ouvrirConnexion(L: Interp, quoi, base, user, pw, role, jeu: string, create: bool,
                     page, crypt: int): FbConn =
  ## Connexion au serveur (interpréteur libéré pendant l'attente réseau).
  fbTry(quoi):
    L.blocking: result = fbConnect(base, user, pw, role, jeu, create, page, crypt)

proc commitTr(L: Interp, d: LFbDb, tr: var int32) =
  fbTry("validation"):
    L.blocking: d.conn.commit(tr)
  tr = 0

proc rollbackTr(L: Interp, d: LFbDb, tr: var int32) =
  try:
    L.blocking: d.conn.rollback(tr)
  except FbError: discard
  tr = 0

#
# Conversion des valeurs
#

proc pow10(n: int): float = pow(10.0, float(n))

proc scaled(x: int64, scale: int): Value =
  if scale >= 0: intV(x) else: numV(float(x) / pow10(-scale))

let dateOrigine = dateTime(1858, mNov, 17, zone = utc())

proc dateTexte(days: int32): string =
  (dateOrigine + initDuration(days = days)).format("yyyy-MM-dd")

proc heureTexte(t: uint32): string =
  let h = t div 36_000_000
  let m = (t div 600_000) mod 60
  let s = (t div 10_000) mod 60
  let f = t mod 10_000
  result = align($h, 2, '0') & ":" & align($m, 2, '0') & ":" & align($s, 2, '0')
  if f != 0: result.add "." & align($f, 4, '0')

proc parseDate(s: string, ok: var bool): int32 =
  ## "AAAA-MM-JJ" -> jours depuis le 17/11/1858.
  ok = false
  if s.len < 10 or s[4] != '-' or s[7] != '-': return
  var y, mo, j: int
  try:
    y = parseInt(s[0..3])
    mo = parseInt(s[5..6])
    j = parseInt(s[8..9])
  except ValueError: return
  if mo < 1 or mo > 12 or j < 1 or j > getDaysInMonth(Month(mo), y): return
  let d = dateTime(y, Month(mo), MonthdayRange(j), zone = utc())
  result = int32((d - dateOrigine).inDays)
  ok = true

proc colName(v: FbVar): string =
  toUpper((if v.alias.len > 0: v.alias else: v.field).strip())

proc decode(L: Interp, d: LFbDb, tr: int32, v: FbVar, x: FbVal): Value =
  case x.kind
  of fvNull: nilV
  of fvText:
    var s = x.s
    if v.sqltype == SQL_TEXT and (x.sub and 0xff) != CS_OCTETS: s = s.strip(leading = false)
    var r = strV(s)
    # INT128 / DECFLOAT (convertis en texte par le serveur) : rendus comme nombres.
    if v.sqltype in [SQL_INT128, SQL_DEC16, SQL_DEC34]:
      let t = s.strip
      try:
        if t.contains({'.', 'E', 'e'}): r = numV(parseFloat(t))
        else: r = intV(parseBiggestInt(t))
      except ValueError:
        try: r = numV(parseFloat(t))
        except ValueError: discard
    r
  of fvInt: scaled(x.i, x.scale)
  of fvFloat: numV(x.f)
  of fvBool: boolV(x.b)
  of fvDate: strV(dateTexte(int32(x.i)))
  of fvTime: strV(heureTexte(uint32(x.i)))
  of fvStamp: strV(dateTexte(x.days) & " " & heureTexte(uint32(x.i)))
  of fvBlob:
    var data: string
    fbTry("lecture du blob"):
      L.blocking: data = d.conn.readBlob(tr, x.s)
    strV(data)

proc rowTable(L: Interp, d: LFbDb, tr: int32, s: FbStmt, row: seq[FbVal]): LTable =
  result = newLTable()
  for i in 0 ..< min(row.len, s.outs.len):
    let x = L.decode(d, tr, s.outs[i], row[i])
    if x.kind != vkNil: result.rawSet(colName(s.outs[i]), x)

proc bindParams(L: Interp, d: LFbDb, tr: int32, s: FbStmt, params: seq[Value]): seq[FbVal] =
  for i in 0 ..< s.ins.len:
    let x = params[i]
    let v = s.ins[i]
    let orig = v.sqltype
    case x.kind
    of vkNil: result.add newVal(fvNull)
    of vkBool:
      if orig == SQL_BOOLEAN: result.add FbVal(kind: fvBool, b: x.b)
      else: result.add FbVal(kind: fvInt, i: (if x.b: 1 else: 0))
    of vkInt: result.add FbVal(kind: fvInt, i: x.i)
    of vkNum: result.add FbVal(kind: fvFloat, f: x.n)
    of vkStr:
      if orig == SQL_BLOB:
        var id: string
        fbTry("écriture du blob"):
          L.blocking: id = d.conn.writeBlob(tr, x.s)
        result.add FbVal(kind: fvBlob, s: id)
      elif orig == SQL_TYPE_DATE and x.s.len == 10:
        var ok: bool
        let days = parseDate(x.s, ok)
        if ok: result.add FbVal(kind: fvDate, i: days)
        else: result.add FbVal(kind: fvText, s: x.s)
      else:
        if x.s.len > 32767:
          rtError("firebird : paramètre " & $(i + 1) & " trop long (" & $x.s.len & " octets) ; utilisez une colonne BLOB")
        result.add FbVal(kind: fvText, s: x.s, sub: (if orig in [SQL_TEXT, SQL_VARYING]: v.subtype else: 0))
    else:
      rtError("firebird : type de paramètre non pris en charge (" & typeName(x) & ")")

#
# Instructions
#

type
  Stmt = object
    s: FbStmt
    d: LFbDb
    args: seq[FbVal]

proc close(L: Interp, s: var Stmt) =
  if not s.s.isNil and not s.d.isNil and not s.d.conn.closed:
    try:
      L.blocking: s.d.conn.free(s.s)
    except FbError: discard
  s.s = nil

proc isSelect(s: Stmt): bool = s.s.isSelect
proc outCount(s: Stmt): int = s.s.outs.len

proc prepare(L: Interp, d: LFbDb, tr: int32, sql: string, params: seq[Value]): Stmt =
  result.d = d
  fbTry("requête invalide"):
    L.blocking: result.s = d.conn.prepare(tr, sql)
  try:
    var vals = params
    if vals.len == 1 and vals[0].kind == vkTable:        # paramètres dans une table.
      let t = vals[0].t
      vals = @[]
      for i in 1 .. t.rawLen: vals.add t.rawGet(intV(i))
    let n = result.s.ins.len
    if vals.len < n:
      rtError("firebird : " & $n & " paramètre(s) attendu(s), " & $vals.len & " fourni(s)")
    result.args = L.bindParams(d, tr, result.s, vals)
  except CatchableError as e:
    L.close(result)
    raise e

proc execute(L: Interp, d: LFbDb, tr: int32, s: var Stmt): seq[LTable] =
  ## Exécute ; pour une instruction qui renvoie une seule ligne (EXECUTE
  ## PROCEDURE, INSERT ... RETURNING), renvoie cette ligne.
  var direct: seq[seq[FbVal]]
  fbTry("exécution"):
    L.blocking: direct = d.conn.execute(tr, s.s, s.args)
  for r in direct: result.add L.rowTable(d, tr, s.s, r)
  if not s.isSelect:
    try:
      L.blocking: d.changes = d.conn.affectedRows(s.s)
    except FbError: d.changes = 0

proc fetch(L: Interp, d: LFbDb, tr: int32, s: var Stmt): LTable =
  ## Ligne suivante d'un SELECT, nil à la fin.
  var row: seq[FbVal]
  var ok: bool
  fbTry("lecture"):
    L.blocking: ok = d.conn.fetch(s.s, row)
  if not ok: return nil
  L.rowTable(d, tr, s.s, row)

proc checkDb(L: Interp, a: seq[Value], fname: string): LFbDb =
  result = checkUser[LFbDb](L, a, 1, fname, "base firebird")
  if result.closed: rtError("base firebird fermée")

template withTr(d: LFbDb, tr: untyped, body: untyped) =
  ## Transaction explicite en cours, ou transaction automatique validée à la
  ## fin (annulée en cas d'erreur).
  let auto = d.tr == 0
  var tr = if auto: L.startTr(d, d.tpb) else: d.tr
  try:
    body
    if auto: L.commitTr(d, tr)
  except CatchableError as e:
    if auto: L.rollbackTr(d, tr)
    raise e

proc paramsOf(a: seq[Value]): seq[Value] = (if a.len > 2: a[2 .. ^1] else: @[])

proc runAll(L: Interp, d: LFbDb, sql: string, params: seq[Value], limit = -1): seq[Value] =
  ## Lignes d'une requête (ou ligne renvoyée par RETURNING / EXECUTE PROCEDURE).
  withTr(d, tr):
    var s = L.prepare(d, tr, sql, params)
    try:
      let direct = L.execute(d, tr, s)
      for r in direct: result.add tableV(r)
      if s.isSelect:
        while limit < 0 or result.len < limit:
          let r = L.fetch(d, tr, s)
          if r.isNil: break
          result.add tableV(r)
    finally:
      L.close(s)

proc splitScript(sql: string): seq[string] =
  ## Découpe un script en instructions (« ; » hors chaînes et commentaires).
  ## Les blocs PSQL (CREATE PROCEDURE...) s'exécutent un par un avec executer().
  var cur = ""
  var i = 0
  while i < sql.len:
    let c = sql[i]
    if c == '\'':
      let j = sql.find('\'', i + 1)
      let e = if j < 0: sql.len - 1 else: j
      cur.add sql[i .. e]
      i = e + 1
      continue
    if c == '-' and i + 1 < sql.len and sql[i + 1] == '-':
      let j = sql.find('\n', i)
      i = if j < 0: sql.len else: j
      continue
    if c == '/' and i + 1 < sql.len and sql[i + 1] == '*':
      let j = sql.find("*/", i + 2)
      i = if j < 0: sql.len else: j + 2
      continue
    if c == ';':
      if cur.strip.len > 0: result.add cur.strip
      cur = ""
    else: cur.add c
    inc i
  if cur.strip.len > 0: result.add cur.strip

proc openFirebirdLib(L: Interp): Value =
  dbMethods = newLib()
  let dm = dbMethods
  dm.fn "executer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "executer")
    let sql = L.checkStr(a, 2, "executer")
    let params = paramsOf(a)
    var total = 0
    var parts = @[sql]
    let lower = sql.toLowerAscii
    if params.len == 0 and sql.count(';') > 0 and "begin" notin lower:
      parts = splitScript(sql)
    withTr(d, tr):
      for part in parts:
        var s = L.prepare(d, tr, part, params)
        try:
          discard L.execute(d, tr, s)
          total += d.changes
        finally:
          L.close(s)
    d.changes = total
    @[intV(total)]
  dm.fn "requete", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "requete")
    let rows = newLTable()
    for r in L.runAll(d, L.checkStr(a, 2, "requete"), paramsOf(a)): rows.arr.add r
    @[tableV(rows)]
  dm.fn "resultat", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Résultat complet d'une instruction : {colonnes = {noms dans l'ordre}, lignes = {tables},
    ## modifications = n, genre = "selection" | "procedure" | "modification" | "definition" | "autre",
    ## tronque = vrai si plus de 100 000 lignes (les suivantes ne sont pas lues).
    let d = L.checkDb(a, "resultat")
    let sql = L.checkStr(a, 2, "resultat")
    let cols = newLTable()
    let rows = newLTable()
    var kind = 0
    var truncated = false
    var changes = 0
    withTr(d, tr):
      var s = L.prepare(d, tr, sql, paramsOf(a))
      try:
        kind = s.s.kind
        for v in s.s.outs: cols.arr.add strV(colName(v))
        let direct = L.execute(d, tr, s)
        for r in direct: rows.arr.add tableV(r)
        if s.isSelect:
          while true:
            if rows.arr.len >= 100_000:
              truncated = true
              break
            let r = L.fetch(d, tr, s)
            if r.isNil: break
            rows.arr.add tableV(r)
        else:
          changes = d.changes
      finally:
        L.close(s)
    let res = newLTable()
    res.rawSet("COLONNES", tableV(cols))
    res.rawSet("LIGNES", tableV(rows))
    res.rawSet("MODIFICATIONS", intV(changes))
    res.rawSet("GENRE", strV(case kind
      of StmtSelect, StmtSelectForUpdate: "selection"
      of StmtExecProcedure: "procedure"
      of 2, 3, 4: "modification"
      of 5: "definition"
      else: "autre"))
    res.rawSet("TRONQUE", boolV(truncated))
    @[tableV(res)]
  dm.fn "premier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "premier")
    let rows = L.runAll(d, L.checkStr(a, 2, "premier"), paramsOf(a), 1)
    @[(if rows.len > 0: rows[0] else: nilV)]
  dm.fn "valeur", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Première colonne de la première ligne (ou nul).
    let d = L.checkDb(a, "valeur")
    let sql = L.checkStr(a, 2, "valeur")
    var res = nilV
    withTr(d, tr):
      var s = L.prepare(d, tr, sql, paramsOf(a))
      try:
        var row: LTable
        let direct = L.execute(d, tr, s)
        if direct.len > 0: row = direct[0]
        elif s.isSelect: row = L.fetch(d, tr, s)
        if not row.isNil and s.outCount > 0:
          res = row.rawGet(colName(s.s.outs[0]))
      finally:
        L.close(s)
    @[res]
  dm.fn "lignes", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Itérateur : les lignes sont lues au fur et à mesure.
    let d = L.checkDb(a, "lignes")
    let sql = L.checkStr(a, 2, "lignes")
    let auto = d.tr == 0
    var tr = if auto: L.startTr(d, d.tpb) else: d.tr
    var s: Stmt
    var done = false
    var pending: seq[LTable]
    try:
      s = L.prepare(d, tr, sql, paramsOf(a))
      pending = L.execute(d, tr, s)
    except CatchableError as e:
      L.close(s)
      if auto: L.rollbackTr(d, tr)
      raise e
    let finish = proc (ok: bool) =
      if not done:
        done = true
        L.close(s)
        if auto:
          if ok: L.commitTr(d, tr) else: L.rollbackTr(d, tr)
    L.closers.add proc () =
      try: finish(false)
      except CatchableError: discard
    @[fnV("lignes", proc (L: Interp, x: seq[Value]): seq[Value] =
      if done: return @[nilV]
      if pending.len > 0:
        let r = pending[0]
        pending.delete(0)
        return @[tableV(r)]
      if not s.isSelect:
        finish(true)
        return @[nilV]
      var r: LTable
      try:
        r = L.fetch(d, tr, s)
      except CatchableError as e:
        finish(false)
        raise e
      if r.isNil:
        finish(true)
        return @[nilV]
      @[tableV(r)])]
  dm.fn "modifications", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(L.checkDb(a, "modifications").changes)]
  dm.fn "sequence", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Valeur suivante d'une séquence (générateur) : GEN_ID(nom, pas).
    let d = L.checkDb(a, "sequence")
    let nom = L.checkStr(a, 2, "sequence")
    for c in nom:
      if not (c.isAlphaNumeric or c in {'_', '$'}): rtError("sequence : nom invalide : " & nom)
    let pas = L.optInt(a, 3, "sequence", 1)
    let rows = L.runAll(d, "SELECT GEN_ID(" & nom & ", " & $pas & ") AS V FROM RDB$DATABASE", @[], 1)
    @[(if rows.len > 0: rows[0].t.rawGet("V") else: nilV)]
  dm.fn "debut", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "debut")
    if d.tr != 0: rtError("firebird : une transaction est déjà en cours")
    d.tr = L.startTr(d, (if arg(a, 2).kind == vkTable: buildTpb(a[1].t) else: d.tpb))
    @[boolV(true)]
  dm.fn "valider", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "valider")
    if d.tr == 0: rtError("firebird : aucune transaction en cours")
    L.commitTr(d, d.tr)
    @[boolV(true)]
  dm.fn "annuler", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "annuler")
    if d.tr == 0: rtError("firebird : aucune transaction en cours")
    L.rollbackTr(d, d.tr)
    @[boolV(true)]
  dm.fn "entransaction", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[boolV(L.checkDb(a, "entransaction").tr != 0)]
  dm.fn "transaction", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "transaction")
    let f = L.checkFunc(a, 2, "transaction")
    if d.tr != 0: rtError("firebird : une transaction est déjà en cours")
    d.tr = L.startTr(d, (if arg(a, 3).kind == vkTable: buildTpb(a[2].t) else: d.tpb))
    try:
      result = L.call(f, @[a[0]])
      if d.tr != 0: L.commitTr(d, d.tr)
    except CatchableError as e:
      if d.tr != 0: L.rollbackTr(d, d.tr)
      raise e
  dm.fn "tables", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "tables")
    var res: seq[Value]
    for r in L.runAll(d, "SELECT TRIM(RDB$RELATION_NAME) AS N FROM RDB$RELATIONS " &
                         "WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 AND RDB$VIEW_BLR IS NULL ORDER BY 1", @[]):
      res.add r.t.rawGet("N")
    let t = newLTable()
    for v in res: t.arr.add v
    @[tableV(t)]
  dm.fn "colonnes", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "colonnes")
    let tbl = L.checkStr(a, 2, "colonnes").toUpperAscii
    let rows = L.runAll(d, "SELECT TRIM(RF.RDB$FIELD_NAME) AS NOM, F.RDB$FIELD_TYPE AS TYPE, " &
      "F.RDB$FIELD_LENGTH AS LONGUEUR, F.RDB$FIELD_SCALE AS ECHELLE, " &
      "COALESCE(RF.RDB$NULL_FLAG, 0) AS OBLIGATOIRE FROM RDB$RELATION_FIELDS RF " &
      "JOIN RDB$FIELDS F ON F.RDB$FIELD_NAME = RF.RDB$FIELD_SOURCE " &
      "WHERE RF.RDB$RELATION_NAME = ? ORDER BY RF.RDB$FIELD_POSITION", @[strV(tbl)])
    let t = newLTable()
    for r in rows: t.arr.add r
    @[tableV(t)]
  dm.fn "serveur", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "serveur")
    let rows = L.runAll(d, "SELECT RDB$GET_CONTEXT('SYSTEM', 'ENGINE_VERSION') AS V FROM RDB$DATABASE", @[], 1)
    @[(if rows.len > 0: rows[0].t.rawGet("V") else: nilV)]
  dm.fn "fermer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = checkUser[LFbDb](L, a, 1, "fermer", "base firebird")
    if not d.closed:
      if d.tr != 0: L.rollbackTr(d, d.tr)
      d.closed = true
      L.blocking: d.conn.close()
    @[boolV(true)]

  proc connectArgs(L: Interp, a: seq[Value], fname: string): (string, string, string, LTable) =
    ## (base, utilisateur, motdepasse, options) : arguments positionnels ou table.
    if arg(a, 1).kind == vkTable:
      let o = a[0].t
      var base = o.optField("base", "")
      let hote = o.optField("hote", "")
      if hote.len > 0:
        let port = o.optField("port", "")
        base = hote & (if port.len > 0: "/" & port else: "") & ":" & base
      return (base, o.optField("utilisateur", getEnv("ISC_USER")),
              o.optField("motdepasse", getEnv("ISC_PASSWORD")), o)
    (L.checkStr(a, 1, fname), L.optStr(a, 2, fname, getEnv("ISC_USER")),
     L.optStr(a, 3, fname, getEnv("ISC_PASSWORD")), (if arg(a, 4).kind == vkTable: a[3].t else: nil))

  proc cryptMode(o: LTable): int =
    ## chiffrement = vrai (si le serveur le propose, par défaut), faux, ou "exige".
    let v = if o.isNil: nilV else: o.field("chiffrement")
    if v.kind == vkBool: return (if v.b: 1 else: 0)
    if v.kind == vkStr and v.s.toLowerAscii.replace("é", "e") in ["exige", "requis", "required"]: return 2
    1

  proc attach(L: Interp, base, user, pw: string, o: LTable, create: bool): Value =
    if base.len > 32767: rtError("firebird : nom de base trop long")
    let role = o.optField("role", "")
    let jeu = o.optField("jeu", "UTF8")
    let page = o.optField("taillepage", 8192)
    let crypt = cryptMode(o)
    let quoi = (if create: "création de " else: "connexion à ") & base
    let conn = L.ouvrirConnexion(quoi, base, user, pw, role, jeu, create, page, crypt)
    let d = LFbDb(conn: conn, tpb: buildTpb(o))
    L.closers.add proc () =
      if not d.closed:
        d.closed = true
        if d.tr != 0:
          try: d.conn.rollback(d.tr)
          except FbError: discard
        d.conn.close()
    L.wrap(d, "firebird", dbMethods)

  # Métatables inscrites dès l'ouverture : les tables de méthodes sont propres au
  # fil courant ; un objet créé ensuite dans un gestionnaire (autre fil) les retrouve.
  discard L.userMeta("firebird", dbMethods)
  let m = newLib()
  m.fn "connecter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let (base, user, pw, o) = L.connectArgs(a, "connecter")
    if base.len == 0: rtError("connecter : nom de la base attendu")
    @[L.attach(base, user, pw, o, false)]
  m.fn "creer", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Crée une base (fichier .fdb) puis s'y connecte.
    let (base, user, pw, o) = L.connectArgs(a, "creer")
    if base.len == 0: rtError("creer : nom de la base attendu")
    @[L.attach(base, user, pw, o, true)]
  m.fn "version", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(DriverVersion)]
  m.fn "disponible", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[boolV(true)]
  tableV(m)

registerPackage PackageDef(name: "firebird", open: openFirebirdLib,
  description: "Bases Firebird 3 à 5 (pilote réseau natif, sans fbclient)",
  docs: docs("firebird", [
    "firebird.connecter(base, utilisateur, motdepasse[, options])", "Connexion : \"serveur:/chemin/base.fdb\", \"serveur/3050:alias\" ou fichier local. Accepte aussi une table {base=, hote=, port=, utilisateur=, motdepasse=, role=, jeu=\"UTF8\", isolation=, attente=, chiffrement=vrai|faux|\"exige\"}. Sans hôte, le serveur local (localhost:3050) est utilisé.",
    "firebird.creer(base, utilisateur, motdepasse[, {taillepage=8192, jeu=\"UTF8\"}])", "Crée une base puis s'y connecte.",
    "firebird.version()", "Version du pilote natif.",
    "firebird.disponible()", "Toujours vrai : le pilote est intégré (aucune bibliothèque cliente requise).",
    "db:executer(sql, ...)", "Exécute une instruction avec paramètres « ? » ; renvoie le nombre de lignes modifiées. Sans paramètre, accepte un script d'instructions séparées par « ; » (hors blocs PSQL).",
    "db:requete(sql, ...)", "Liste des lignes ; chaque ligne est une table colonne (majuscules) -> valeur. Accepte INSERT ... RETURNING et EXECUTE PROCEDURE.",
    "db:premier(sql, ...)", "Première ligne ou nul.",
    "db:valeur(sql, ...)", "Première colonne de la première ligne ou nul.",
    "db:resultat(sql, ...)", "Résultat complet d'une instruction : {colonnes = noms dans l'ordre, lignes, modifications, genre = \"selection\", \"procedure\", \"modification\", \"definition\" ou \"autre\", tronque}.",
    "db:lignes(sql, ...)", "Itérateur sur les lignes : pour chaque r dans db:lignes(sql) ... suivant.",
    "db:modifications()", "Lignes modifiées par le dernier executer().",
    "db:sequence(nom[, pas=1])", "Valeur suivante d'une séquence (générateur).",
    "db:transaction(@proc[, options])", "Appelle proc(db) dans une transaction (validée, ou annulée en cas d'erreur).",
    "db:debut([{isolation=\"lecturevalidee\"|\"instantane\"|\"serialisable\", lecture=faux, attente=vrai|faux|secondes}])", "Commence une transaction explicite.",
    "db:valider()", "Valide la transaction explicite.",
    "db:annuler()", "Annule la transaction explicite.",
    "db:entransaction()", "Vrai si une transaction explicite est en cours.",
    "db:tables()", "Tables de l'utilisateur.",
    "db:colonnes(table)", "Colonnes d'une table : {nom=, type=, longueur=, echelle=, obligatoire=}.",
    "db:serveur()", "Version du serveur.",
    "db:fermer()", "Ferme la connexion (une transaction explicite non validée est annulée)."]))
