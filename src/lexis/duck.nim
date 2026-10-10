# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - accès à DuckDB, bibliothèque chargée à l'exécution
#
# La bibliothèque (libduckdb.dylib / .so / duckdb.dll) est cherchée :
#   1. dans la variable d'environnement WDLEXIS_DUCKDB (chemin complet) ;
#   2. dans <dossier de l'exécutable>/macOS (linOS, winOS), puis à côté de
#      l'exécutable, puis dans ../Frameworks et ../Resources (application macOS) ;
#   3. dans <dossier courant>/macOS (linOS, winOS) et dans les dossiers donnés
#      (dossier du programme) ;
#   4. parmi les bibliothèques du système.
# Rien n'est chargé tant qu'un programme n'utilise pas la base : l'atelier et
# le runtime démarrent même sans DuckDB.
#
# Une base (fichier) n'est ouverte qu'une fois par processus (DuckDB verrouille
# le fichier) ; chaque interpréteur a sa propre connexion.

import std/[dynlib, os, locks, tables, strutils, unicode]

const
  osDir* = when defined(windows): "winOS" elif defined(macosx): "macOS" else: "linOS"
  libName* = when defined(windows): "duckdb.dll" elif defined(macosx): "libduckdb.dylib" else: "libduckdb.so"

type
  DuckState = cint
  PDatabase = pointer
  PConnection = pointer
  PPrepared = pointer
  DuckResult* = object
    columnCount, rowCount, rowsChanged: uint64
    columns: pointer
    errorMessage: cstring
    internalData: pointer
  DuckBlob = object
    data: pointer
    size: uint64

  Api = object
    open: proc (path: cstring, db: ptr PDatabase): DuckState {.cdecl, gcsafe.}
    close: proc (db: ptr PDatabase) {.cdecl, gcsafe.}
    connect: proc (db: PDatabase, c: ptr PConnection): DuckState {.cdecl, gcsafe.}
    disconnect: proc (c: ptr PConnection) {.cdecl, gcsafe.}
    query: proc (c: PConnection, sql: cstring, r: ptr DuckResult): DuckState {.cdecl, gcsafe.}
    destroyResult: proc (r: ptr DuckResult) {.cdecl, gcsafe.}
    columnName: proc (r: ptr DuckResult, col: uint64): cstring {.cdecl, gcsafe.}
    columnType: proc (r: ptr DuckResult, col: uint64): cint {.cdecl, gcsafe.}
    columnCount: proc (r: ptr DuckResult): uint64 {.cdecl, gcsafe.}
    rowCount: proc (r: ptr DuckResult): uint64 {.cdecl, gcsafe.}
    rowsChanged: proc (r: ptr DuckResult): uint64 {.cdecl, gcsafe.}
    resultError: proc (r: ptr DuckResult): cstring {.cdecl, gcsafe.}
    prepare: proc (c: PConnection, sql: cstring, p: ptr PPrepared): DuckState {.cdecl, gcsafe.}
    destroyPrepare: proc (p: ptr PPrepared) {.cdecl, gcsafe.}
    prepareError: proc (p: PPrepared): cstring {.cdecl, gcsafe.}
    nparams: proc (p: PPrepared): uint64 {.cdecl, gcsafe.}
    bindBoolean: proc (p: PPrepared, i: uint64, v: bool): DuckState {.cdecl, gcsafe.}
    bindInt64: proc (p: PPrepared, i: uint64, v: int64): DuckState {.cdecl, gcsafe.}
    bindDouble: proc (p: PPrepared, i: uint64, v: cdouble): DuckState {.cdecl, gcsafe.}
    bindVarcharLength: proc (p: PPrepared, i: uint64, v: cstring, n: uint64): DuckState {.cdecl, gcsafe.}
    bindBlob: proc (p: PPrepared, i: uint64, v: pointer, n: uint64): DuckState {.cdecl, gcsafe.}
    bindNull: proc (p: PPrepared, i: uint64): DuckState {.cdecl, gcsafe.}
    executePrepared: proc (p: PPrepared, r: ptr DuckResult): DuckState {.cdecl, gcsafe.}
    valueIsNull: proc (r: ptr DuckResult, col, row: uint64): bool {.cdecl, gcsafe.}
    valueVarchar: proc (r: ptr DuckResult, col, row: uint64): cstring {.cdecl, gcsafe.}
    valueInt64: proc (r: ptr DuckResult, col, row: uint64): int64 {.cdecl, gcsafe.}
    valueDouble: proc (r: ptr DuckResult, col, row: uint64): cdouble {.cdecl, gcsafe.}
    valueBoolean: proc (r: ptr DuckResult, col, row: uint64): bool {.cdecl, gcsafe.}
    valueBlob: proc (r: ptr DuckResult, col, row: uint64): DuckBlob {.cdecl, gcsafe.}
    free: proc (p: pointer) {.cdecl, gcsafe.}
    interrupt: proc (c: PConnection) {.cdecl, gcsafe.}
    libraryVersion: proc (): cstring {.cdecl, gcsafe.}

  DuckError* = object of CatchableError

  DbCellKind* = enum ckNull, ckBool, ckInt, ckFloat, ckText
  DbCell* = object
    case kind*: DbCellKind
    of ckNull: discard
    of ckBool: b*: bool
    of ckInt: i*: int64
    of ckFloat: f*: float64
    of ckText: s*: string

  QueryResult* = object
    columns*: seq[string]
    rows*: seq[seq[DbCell]]
    changed*: int64

  SharedDb = ref object
    db: PDatabase
    refs: int

  Connection* = ref object
    path*: string                 # chemin absolu, ou ":memoire:"
    conn: PConnection
    shared: SharedDb

var
  api: Api
  loaded = false
  loadError = ""
  libLock: Lock
  dbs: Table[string, SharedDb]
initLock(libLock)

proc candidates(extraDirs: openArray[string]): seq[string] =
  let env = getEnv("WDLEXIS_DUCKDB")
  if env.len > 0: result.add env
  let exe = getAppDir()
  result.add exe / osDir / libName
  result.add exe / libName
  when defined(macosx):
    result.add exe / ".." / "Frameworks" / libName
    result.add exe / ".." / "Resources" / osDir / libName
  result.add getCurrentDir() / osDir / libName
  for d in extraDirs:
    if d.len > 0:
      result.add d / osDir / libName
      result.add d / libName
  when defined(macosx):
    result.add ["libduckdb.dylib", "/opt/homebrew/lib/libduckdb.dylib", "/usr/local/lib/libduckdb.dylib"]
  elif defined(windows):
    result.add "duckdb.dll"
  else:
    result.add ["libduckdb.so", "/usr/local/lib/libduckdb.so", "/usr/lib/libduckdb.so"]

proc loadDuck*(extraDirs: openArray[string] = []): bool =
  ## Charge la bibliothèque DuckDB (une seule fois par processus).
  acquire(libLock)
  defer: release(libLock)
  block:
    if loaded: return true
    var lib: LibHandle = nil
    let cands = candidates(extraDirs)
    for c in cands:
      lib = loadLib(c)
      if not lib.isNil: break
    if lib.isNil:
      loadError = "bibliothèque DuckDB (" & libName & ") introuvable ; placez-la dans le dossier « " &
                  osDir & " » à côté de l'exécutable ou du programme, ou indiquez son chemin dans " &
                  "la variable WDLEXIS_DUCKDB"
      return false
    template sym(field: untyped, name: string) =
      let p = lib.symAddr(name)
      if p.isNil:
        loadError = "symbole DuckDB manquant : " & name
        return false
      api.field = cast[typeof(api.field)](p)
    sym(open, "duckdb_open")
    sym(close, "duckdb_close")
    sym(connect, "duckdb_connect")
    sym(disconnect, "duckdb_disconnect")
    sym(query, "duckdb_query")
    sym(destroyResult, "duckdb_destroy_result")
    sym(columnName, "duckdb_column_name")
    sym(columnType, "duckdb_column_type")
    sym(columnCount, "duckdb_column_count")
    sym(rowCount, "duckdb_row_count")
    sym(rowsChanged, "duckdb_rows_changed")
    sym(resultError, "duckdb_result_error")
    sym(prepare, "duckdb_prepare")
    sym(destroyPrepare, "duckdb_destroy_prepare")
    sym(prepareError, "duckdb_prepare_error")
    sym(nparams, "duckdb_nparams")
    sym(bindBoolean, "duckdb_bind_boolean")
    sym(bindInt64, "duckdb_bind_int64")
    sym(bindDouble, "duckdb_bind_double")
    sym(bindVarcharLength, "duckdb_bind_varchar_length")
    sym(bindBlob, "duckdb_bind_blob")
    sym(bindNull, "duckdb_bind_null")
    sym(executePrepared, "duckdb_execute_prepared")
    sym(valueIsNull, "duckdb_value_is_null")
    sym(valueVarchar, "duckdb_value_varchar")
    sym(valueInt64, "duckdb_value_int64")
    sym(valueDouble, "duckdb_value_double")
    sym(valueBoolean, "duckdb_value_boolean")
    sym(valueBlob, "duckdb_value_blob")
    sym(free, "duckdb_free")
    sym(interrupt, "duckdb_interrupt")
    sym(libraryVersion, "duckdb_library_version")
    loaded = true
    return true

proc duckLoadError*(): string = loadError

proc duckVersion*(): string =
  if loaded: $api.libraryVersion() else: ""

proc fail(msg: string) {.noreturn.} = raise newException(DuckError, msg)

proc openConnection*(path: string, extraDirs: openArray[string] = []): Connection =
  ## Ouvre (ou partage) la base `path` et crée une connexion. ":memoire:" : base en mémoire.
  if not loadDuck(extraDirs): fail(loadError)
  let mem = path in [":memoire:", ":memory:", ""]
  let key = if mem: ":memoire:" else: absolutePath(path)
  var sh: SharedDb
  withLock libLock:
    sh = dbs.getOrDefault(key)
    if sh.isNil:
      var db: PDatabase = nil
      if api.open((if mem: nil else: key.cstring), addr db) != 0:
        fail("ouverture de la base impossible : " & key)
      sh = SharedDb(db: db)
      if not mem: dbs[key] = sh
    inc sh.refs
  var c: PConnection = nil
  if api.connect(sh.db, addr c) != 0:
    withLock libLock:
      dec sh.refs
    fail("connexion à la base impossible : " & key)
  Connection(path: (if mem: ":memoire:" else: key), conn: c, shared: sh)

proc close*(c: Connection) =
  if c.isNil or c.conn.isNil: return
  api.disconnect(addr c.conn)
  c.conn = nil
  withLock libLock:
    dec c.shared.refs
    if c.shared.refs <= 0:
      api.close(addr c.shared.db)
      var gone: seq[string]
      for k, v in dbs:
        if v == c.shared: gone.add k
      for k in gone: dbs.del k

proc interrupt*(c: Connection) =
  if not c.isNil and not c.conn.isNil: api.interrupt(c.conn)

const numericAsText = {6, 7, 8, 9, 16, 19, 32}   # entiers non signés, hugeint, decimal, uhugeint

proc readResult(r: var DuckResult): QueryResult =
  let nc = int(api.columnCount(addr r))
  let nr = int(api.rowCount(addr r))
  result.changed = int64(api.rowsChanged(addr r))
  for c in 0 ..< nc: result.columns.add $api.columnName(addr r, uint64(c))
  var types = newSeq[int](nc)
  for c in 0 ..< nc: types[c] = int(api.columnType(addr r, uint64(c)))
  for row in 0 ..< nr:
    var line = newSeq[DbCell](nc)
    for c in 0 ..< nc:
      let cu = uint64(c)
      let ru = uint64(row)
      if api.valueIsNull(addr r, cu, ru): continue
      case types[c]
      of 1: line[c] = DbCell(kind: ckBool, b: api.valueBoolean(addr r, cu, ru))
      of 2, 3, 4, 5: line[c] = DbCell(kind: ckInt, i: api.valueInt64(addr r, cu, ru))
      of 10, 11: line[c] = DbCell(kind: ckFloat, f: float64(api.valueDouble(addr r, cu, ru)))
      of 18:
        let b = api.valueBlob(addr r, cu, ru)
        var s = newString(int(b.size))
        if b.size > 0: copyMem(addr s[0], b.data, int(b.size))
        if not b.data.isNil: api.free(b.data)
        line[c] = DbCell(kind: ckText, s: s)
      else:
        let p = api.valueVarchar(addr r, cu, ru)
        let s = if p.isNil: "" else: $p
        if not p.isNil: api.free(p)
        if types[c] in numericAsText:
          try:
            let x = parseFloat(s)
            if x == float64(int64(x)) and '.' notin s and 'e' notin s.toLowerAscii:
              line[c] = DbCell(kind: ckInt, i: int64(x))
            else: line[c] = DbCell(kind: ckFloat, f: x)
          except ValueError: line[c] = DbCell(kind: ckText, s: s)
        else:
          line[c] = DbCell(kind: ckText, s: s)
    result.rows.add line

proc exec*(c: Connection, sql: string, params: openArray[DbCell] = []): QueryResult =
  ## Exécute une requête (paramètres « ? »). Lève DuckError.
  if c.isNil or c.conn.isNil: fail("base fermée")
  var r: DuckResult
  if params.len == 0:
    if api.query(c.conn, sql.cstring, addr r) != 0:
      let msg = $api.resultError(addr r)
      api.destroyResult(addr r)
      fail(msg)
  else:
    var p: PPrepared = nil
    if api.prepare(c.conn, sql.cstring, addr p) != 0:
      let msg = if p.isNil: "requête invalide" else: $api.prepareError(p)
      api.destroyPrepare(addr p)
      fail(msg)
    let n = int(api.nparams(p))
    if params.len != n:
      api.destroyPrepare(addr p)
      fail($n & " paramètre(s) attendu(s), " & $params.len & " fourni(s)")
    for k, v in params:
      let i = uint64(k + 1)
      let st = case v.kind
        of ckNull: api.bindNull(p, i)
        of ckBool: api.bindBoolean(p, i, v.b)
        of ckInt: api.bindInt64(p, i, v.i)
        of ckFloat: api.bindDouble(p, i, cdouble(v.f))
        of ckText:
          if validateUtf8(v.s) < 0: api.bindVarcharLength(p, i, v.s.cstring, uint64(v.s.len))
          else: api.bindBlob(p, i, (if v.s.len > 0: unsafeAddr v.s[0] else: nil), uint64(v.s.len))
      if st != 0:
        api.destroyPrepare(addr p)
        fail("impossible de lier le paramètre " & $(k + 1))
    let st = api.executePrepared(p, addr r)
    api.destroyPrepare(addr p)
    if st != 0:
      let msg = $api.resultError(addr r)
      api.destroyResult(addr r)
      fail(msg)
  result = readResult(r)
  api.destroyResult(addr r)

proc quoteIdent*(s: string): string = "\"" & s.replace("\"", "\"\"") & "\""

proc validIdent*(s: string): bool =
  ## Nom de table acceptable (lettres, chiffres, _, et un éventuel schéma).
  if s.len == 0 or s.len > 128: return false
  for c in s:
    if c notin {'a'..'z', 'A'..'Z', '0'..'9', '_', '.'} and ord(c) < 128: return false
  true
