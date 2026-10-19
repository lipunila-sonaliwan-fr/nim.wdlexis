# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet sqlite (la base native de Lexis+ est DuckDB : voir sql, utiliser...)
#
# Liaison directe à la bibliothèque SQLite 3, chargée à l'exécution
# (libsqlite3.so / libsqlite3.dylib / sqlite3.dll), sans dépendance Nimble.
#
#   sq = paquet("sqlite")
#   db = sq.ouvrir("base.db")                     && ":memoire:" possible
#   db:executer("create table t(id integer primary key, nom text)")
#   db:executer("insert into t(nom) values (?)", "Ada")
#   pour chaque r dans db:requete("select * from t where id > ?", 0)
#     ? r.id, r.nom
#   suivant
#   db:fermer()

import std/[dynlib, strutils]
import ../lexis/api
from std/unicode import toUpper

when defined(windows):
  const SqliteNames = ["sqlite3.dll", "winsqlite3.dll"]
elif defined(macosx):
  const SqliteNames = ["libsqlite3.dylib", "/usr/lib/libsqlite3.dylib",
                       "/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib"]
else:
  const SqliteNames = ["libsqlite3.so.0", "libsqlite3.so"]

const
  SQLITE_OK = 0
  SQLITE_ROW = 100
  SQLITE_DONE = 101
  SQLITE_INTEGER = 1
  SQLITE_FLOAT = 2
  SQLITE_TEXT = 3
  SQLITE_BLOB = 4
  SQLITE_NULL = 5
  SQLITE_OPEN_READWRITE = 0x02
  SQLITE_OPEN_CREATE = 0x04
  SQLITE_OPEN_FULLMUTEX = 0x10000

type
  PDb = pointer
  PStmt = pointer
  Destructor = pointer

  Api = object
    open_v2: proc (f: cstring, db: ptr PDb, flags: cint, vfs: cstring): cint {.cdecl, gcsafe.}
    close_v2: proc (db: PDb): cint {.cdecl, gcsafe.}
    errmsg: proc (db: PDb): cstring {.cdecl, gcsafe.}
    prepare_v2: proc (db: PDb, sql: cstring, n: cint, st: ptr PStmt, tail: ptr cstring): cint {.cdecl, gcsafe.}
    step: proc (st: PStmt): cint {.cdecl, gcsafe.}
    finalize: proc (st: PStmt): cint {.cdecl, gcsafe.}
    bind_parameter_count: proc (st: PStmt): cint {.cdecl, gcsafe.}
    bind_int64: proc (st: PStmt, i: cint, v: int64): cint {.cdecl, gcsafe.}
    bind_double: proc (st: PStmt, i: cint, v: cdouble): cint {.cdecl, gcsafe.}
    bind_text: proc (st: PStmt, i: cint, v: cstring, n: cint, d: Destructor): cint {.cdecl, gcsafe.}
    bind_null: proc (st: PStmt, i: cint): cint {.cdecl, gcsafe.}
    column_count: proc (st: PStmt): cint {.cdecl, gcsafe.}
    column_name: proc (st: PStmt, i: cint): cstring {.cdecl, gcsafe.}
    column_type: proc (st: PStmt, i: cint): cint {.cdecl, gcsafe.}
    column_int64: proc (st: PStmt, i: cint): int64 {.cdecl, gcsafe.}
    column_double: proc (st: PStmt, i: cint): cdouble {.cdecl, gcsafe.}
    column_text: proc (st: PStmt, i: cint): cstring {.cdecl, gcsafe.}
    column_blob: proc (st: PStmt, i: cint): pointer {.cdecl, gcsafe.}
    column_bytes: proc (st: PStmt, i: cint): cint {.cdecl, gcsafe.}
    changes: proc (db: PDb): cint {.cdecl, gcsafe.}
    last_insert_rowid: proc (db: PDb): int64 {.cdecl, gcsafe.}
    libversion: proc (): cstring {.cdecl, gcsafe.}

var sq: Api       # fonctions SQLite chargées dynamiquement.
var loaded = false
var loadError = ""

proc loadSqlite(): bool =
  if loaded: return true
  var lib: LibHandle = nil
  for n in SqliteNames:
    lib = loadLib(n)
    if not lib.isNil: break
  if lib.isNil:
    loadError = "bibliothèque SQLite introuvable (" & SqliteNames.join(", ") & ")"
    return false
  template sym(field: untyped, name: string) =
    let p = lib.symAddr(name)
    if p.isNil:
      loadError = "symbole SQLite manquant : " & name
      return false
    sq.field = cast[typeof(sq.field)](p)
  sym(open_v2, "sqlite3_open_v2")
  sym(close_v2, "sqlite3_close_v2")
  sym(errmsg, "sqlite3_errmsg")
  sym(prepare_v2, "sqlite3_prepare_v2")
  sym(step, "sqlite3_step")
  sym(finalize, "sqlite3_finalize")
  sym(bind_parameter_count, "sqlite3_bind_parameter_count")
  sym(bind_int64, "sqlite3_bind_int64")
  sym(bind_double, "sqlite3_bind_double")
  sym(bind_text, "sqlite3_bind_text")
  sym(bind_null, "sqlite3_bind_null")
  sym(column_count, "sqlite3_column_count")
  sym(column_name, "sqlite3_column_name")
  sym(column_type, "sqlite3_column_type")
  sym(column_int64, "sqlite3_column_int64")
  sym(column_double, "sqlite3_column_double")
  sym(column_text, "sqlite3_column_text")
  sym(column_blob, "sqlite3_column_blob")
  sym(column_bytes, "sqlite3_column_bytes")
  sym(changes, "sqlite3_changes")
  sym(last_insert_rowid, "sqlite3_last_insert_rowid")
  sym(libversion, "sqlite3_libversion")
  loaded = true
  true

let SQLITE_TRANSIENT = cast[Destructor](-1)

type
  LDb* = ref object of LUser
    db: PDb
    closed: bool

var dbMethods {.threadvar.}: LTable

proc sqlErr(d: LDb, what: string) {.noreturn.} =
  rtError("sqlite : " & what & " : " & $sq.errmsg(d.db))

proc checkDb(L: Interp, a: seq[Value], fname: string): LDb =
  result = checkUser[LDb](L, a, 1, fname, "base sqlite")
  if result.closed: rtError("base sqlite fermée")

proc prepare(L: Interp, d: LDb, sql: string, params: seq[Value]): PStmt =
  var st: PStmt = nil
  if sq.prepare_v2(d.db, sql.cstring, cint(sql.len), addr st, nil) != SQLITE_OK:
    sqlErr(d, "requête invalide")
  if st.isNil: return nil         # requête vide (commentaire seul...).
  var vals = params
  # une table unique peut contenir les paramètres positionnels.
  if vals.len == 1 and vals[0].kind == vkTable:
    let t = vals[0].t
    vals = @[]
    for i in 1 .. t.rawLen: vals.add t.rawGet(intV(i))
  let n = int(sq.bind_parameter_count(st))
  if vals.len < n:
    discard sq.finalize(st)
    rtError("sqlite : " & $n & " paramètre(s) attendu(s), " & $vals.len & " fourni(s)")
  for i in 0 ..< n:
    let v = vals[i]
    let idx = cint(i + 1)
    let rc = case v.kind
      of vkNil: sq.bind_null(st, idx)
      of vkBool: sq.bind_int64(st, idx, (if v.b: 1 else: 0))
      of vkInt: sq.bind_int64(st, idx, v.i)
      of vkNum: sq.bind_double(st, idx, v.n)
      of vkStr: sq.bind_text(st, idx, v.s.cstring, cint(v.s.len), SQLITE_TRANSIENT)
      else:
        discard sq.finalize(st)
        rtError("sqlite : type de paramètre non pris en charge (" & typeName(v) & ")")
    if rc != SQLITE_OK:
      discard sq.finalize(st)
      sqlErr(d, "liaison du paramètre " & $(i + 1))
  st

proc rowTable(st: PStmt): LTable =
  result = newLTable()
  for i in 0 ..< int(sq.column_count(st)):
    let ci = cint(i)
    let name = $sq.column_name(st, ci)
    let v = case int(sq.column_type(st, ci))
      of SQLITE_INTEGER: intV(sq.column_int64(st, ci))
      of SQLITE_FLOAT: numV(sq.column_double(st, ci))
      of SQLITE_NULL: nilV
      of SQLITE_BLOB:
        let n = int(sq.column_bytes(st, ci))
        var s = newString(n)
        if n > 0: copyMem(addr s[0], sq.column_blob(st, ci), n)
        strV(s)
      else:
        let p = sq.column_text(st, ci)
        let n = int(sq.column_bytes(st, ci))
        var s = newString(n)
        if n > 0: copyMem(addr s[0], p, n)
        strV(s)
    if v.kind != vkNil: result.rawSet(toUpper(name), v)

proc openSqliteLib(L: Interp): Value =
  dbMethods = newLib()
  let dm = dbMethods
  dm.fn "executer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "executer")
    let sql = L.checkStr(a, 2, "executer")
    let params = if a.len > 2: a[2 .. ^1] else: @[]
    if params.len == 0 and sql.count(';') > 1:
      # plusieurs instructions sans paramètres : exécutées l'une après l'autre.
      var rest = sql
      while rest.strip().len > 0:
        var st: PStmt = nil
        var tail: cstring = nil
        if sq.prepare_v2(d.db, rest.cstring, cint(rest.len), addr st, addr tail) != SQLITE_OK:
          sqlErr(d, "requête invalide")
        let consumed = if tail.isNil: rest.len else: cast[int](tail) - cast[int](rest.cstring)
        if not st.isNil:
          var rc: cint
          L.blocking: rc = sq.step(st)
          discard sq.finalize(st)
          if rc notin [cint(SQLITE_DONE), cint(SQLITE_ROW)]: sqlErr(d, "exécution")
        rest = rest[consumed .. ^1]
      return @[intV(sq.changes(d.db))]
    let st = L.prepare(d, sql, params)
    if st.isNil: return @[intV(0)]
    var rc: cint
    L.blocking:
      rc = sq.step(st)
      while rc == SQLITE_ROW: rc = sq.step(st)
    discard sq.finalize(st)
    if rc != SQLITE_DONE: sqlErr(d, "exécution")
    @[intV(sq.changes(d.db))]
  dm.fn "requete", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "requete")
    let st = L.prepare(d, L.checkStr(a, 2, "requete"), (if a.len > 2: a[2 .. ^1] else: @[]))
    let rows = newLTable()
    if st.isNil: return @[tableV(rows)]
    while true:
      var rc: cint
      L.blocking: rc = sq.step(st)
      if rc == SQLITE_ROW: rows.arr.add tableV(rowTable(st))
      elif rc == SQLITE_DONE: break
      else:
        discard sq.finalize(st)
        sqlErr(d, "lecture")
    discard sq.finalize(st)
    @[tableV(rows)]
  dm.fn "premier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "premier")
    let st = L.prepare(d, L.checkStr(a, 2, "premier"), (if a.len > 2: a[2 .. ^1] else: @[]))
    if st.isNil: return @[nilV]
    var rc: cint
    L.blocking: rc = sq.step(st)
    result = if rc == SQLITE_ROW: @[tableV(rowTable(st))] else: @[nilV]
    discard sq.finalize(st)
  dm.fn "lignes", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "lignes")
    let st = L.prepare(d, L.checkStr(a, 2, "lignes"), (if a.len > 2: a[2 .. ^1] else: @[]))
    var done = st.isNil
    L.closers.add proc () =
      if not done:
        done = true
        discard sq.finalize(st)
    @[fnV("lignes", proc (L: Interp, x: seq[Value]): seq[Value] =
      if done: return @[nilV]
      var rc: cint
      L.blocking: rc = sq.step(st)
      if rc == SQLITE_ROW: return @[tableV(rowTable(st))]
      done = true
      discard sq.finalize(st)
      if rc != SQLITE_DONE: sqlErr(d, "lecture")
      @[nilV])]
  dm.fn "dernierid", proc (L: Interp, a: seq[Value]): seq[Value] =
    result = @[intV(sq.last_insert_rowid(L.checkDb(a, "dernierid").db))]
  dm.fn "modifications", proc (L: Interp, a: seq[Value]): seq[Value] =
    result = @[intV(sq.changes(L.checkDb(a, "modifications").db))]
  dm.fn "transaction", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "transaction")
    let f = L.checkFunc(a, 2, "transaction")
    template run(sql: string) =
      let st = L.prepare(d, sql, @[])
      discard sq.step(st)
      discard sq.finalize(st)
    run("BEGIN")
    try:
      result = L.call(f, @[a[0]])
      run("COMMIT")
    except CatchableError as e:
      run("ROLLBACK")
      raise e
  dm.fn "fermer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = checkUser[LDb](L, a, 1, "fermer", "base sqlite")
    if not d.closed:
      d.closed = true
      discard sq.close_v2(d.db)
    @[boolV(true)]

  # Métatables inscrites dès l'ouverture : les tables de méthodes sont propres au
  # fil courant ; un objet créé ensuite dans un gestionnaire (autre fil) les retrouve.
  discard L.userMeta("sqlite", dbMethods)
  let m = newLib()
  m.fn "ouvrir", proc (L: Interp, a: seq[Value]): seq[Value] =
    if not loadSqlite(): return fail(loadError)
    var path = L.checkStr(a, 1, "ouvrir")
    if path == ":memoire:": path = ":memory:"
    var db: PDb = nil
    let flags = cint(SQLITE_OPEN_READWRITE or SQLITE_OPEN_CREATE or SQLITE_OPEN_FULLMUTEX)
    if sq.open_v2(path.cstring, addr db, flags, nil) != SQLITE_OK:
      let msg = if db.isNil: "ouverture impossible" else: $sq.errmsg(db)
      if not db.isNil: discard sq.close_v2(db)
      return fail(path & " : " & msg)
    let d = LDb(db: db)
    L.closers.add proc () =
      if not d.closed:
        d.closed = true
        discard sq.close_v2(d.db)
    @[L.wrap(d, "sqlite", dbMethods)]
  m.fn "version", proc (L: Interp, a: seq[Value]): seq[Value] =
    if not loadSqlite(): return fail(loadError)
    @[strV($sq.libversion())]
  tableV(m)

registerPackage PackageDef(name: "sqlite", open: openSqliteLib,
  description: "Bases SQLite",
  docs: docs("sqlite", [
    "sqlite.ouvrir(chemin)", "Ouvre (ou crée) une base ; \":memoire:\" pour une base en mémoire.",
    "sqlite.version()", "Version de la bibliothèque SQLite.",
    "db:executer(sql, ...)", "Exécute une instruction avec paramètres « ? » ; renvoie le nombre de lignes modifiées. Sans paramètre, accepte plusieurs instructions séparées par « ; ».",
    "db:requete(sql, ...)", "Liste des lignes ; chaque ligne est une table colonne (majuscules) -> valeur.",
    "db:premier(sql, ...)", "Première ligne ou nul.",
    "db:lignes(sql, ...)", "Itérateur sur les lignes : pour chaque r dans db:lignes(sql) ... suivant.",
    "db:dernierid()", "Identifiant de la dernière ligne insérée.",
    "db:modifications()", "Lignes modifiées par la dernière instruction.",
    "db:transaction(@proc)", "Appelle proc(db) dans une transaction (annulée en cas d'erreur).",
    "db:fermer()", "Ferme la base."]))
