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

import std/[dynlib, os, locks, tables, strutils, unicode, math, algorithm, times]

const
  osDir* = when defined(windows): "winOS" elif defined(macosx): "macOS" else: "linOS"
  libName* = when defined(windows): "duckdb.dll" elif defined(macosx): "libduckdb.dylib" else: "libduckdb.so"

type
  DuckState = cint
  PDatabase = pointer
  PConnection = pointer
  PPrepared = pointer
  DuckResult* {.bycopy.} = object
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
    # lecture par blocs (API vectorielle) : tous les types, y compris UUID, horodatages
    # avec fuseau, listes, structures... (facultatif : sinon, lecture valeur par valeur)
    resultChunkCount: proc (r: DuckResult): uint64 {.cdecl, gcsafe.}
    resultGetChunk: proc (r: DuckResult, i: uint64): pointer {.cdecl, gcsafe.}
    destroyChunk: proc (c: ptr pointer) {.cdecl, gcsafe.}
    chunkSize: proc (c: pointer): uint64 {.cdecl, gcsafe.}
    chunkVector: proc (c: pointer, col: uint64): pointer {.cdecl, gcsafe.}
    vectorType: proc (v: pointer): pointer {.cdecl, gcsafe.}
    vectorData: proc (v: pointer): pointer {.cdecl, gcsafe.}
    vectorValidity: proc (v: pointer): pointer {.cdecl, gcsafe.}
    listChild: proc (v: pointer): pointer {.cdecl, gcsafe.}
    structChild: proc (v: pointer, i: uint64): pointer {.cdecl, gcsafe.}
    arrayChild: proc (v: pointer): pointer {.cdecl, gcsafe.}
    typeId: proc (lt: pointer): cint {.cdecl, gcsafe.}
    destroyType: proc (lt: ptr pointer) {.cdecl, gcsafe.}
    decimalScale: proc (lt: pointer): uint8 {.cdecl, gcsafe.}
    decimalInternal: proc (lt: pointer): cint {.cdecl, gcsafe.}
    enumInternal: proc (lt: pointer): cint {.cdecl, gcsafe.}
    enumSize: proc (lt: pointer): uint32 {.cdecl, gcsafe.}
    enumValue: proc (lt: pointer, i: uint64): cstring {.cdecl, gcsafe.}
    structCount: proc (lt: pointer): uint64 {.cdecl, gcsafe.}
    structName: proc (lt: pointer, i: uint64): cstring {.cdecl, gcsafe.}
    unionCount: proc (lt: pointer): uint64 {.cdecl, gcsafe.}
    unionName: proc (lt: pointer, i: uint64): cstring {.cdecl, gcsafe.}
    arraySize: proc (lt: pointer): uint64 {.cdecl, gcsafe.}

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
    types*: seq[string]           # types DuckDB des colonnes (INTEGER, VARCHAR, LIST...)
    rows*: seq[seq[DbCell]]
    changed*: int64

  SharedDb = ref object
    db: PDatabase
    refs: int

  Connection* = ref object
    path*: string                 # chemin absolu, ou ":memoire:"
    conn: PConnection
    shared: SharedDb
    lk: Lock                      # une requête à la fois sur une connexion (plusieurs fils)

var
  api: Api
  loaded = false
  chunked = false               # API vectorielle disponible : lecture de tous les types
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
    template optsym(field: untyped, name: string) =
      api.field = cast[typeof(api.field)](lib.symAddr(name))
    optsym(resultChunkCount, "duckdb_result_chunk_count")
    optsym(resultGetChunk, "duckdb_result_get_chunk")
    optsym(destroyChunk, "duckdb_destroy_data_chunk")
    optsym(chunkSize, "duckdb_data_chunk_get_size")
    optsym(chunkVector, "duckdb_data_chunk_get_vector")
    optsym(vectorType, "duckdb_vector_get_column_type")
    optsym(vectorData, "duckdb_vector_get_data")
    optsym(vectorValidity, "duckdb_vector_get_validity")
    optsym(listChild, "duckdb_list_vector_get_child")
    optsym(structChild, "duckdb_struct_vector_get_child")
    optsym(arrayChild, "duckdb_array_vector_get_child")
    optsym(typeId, "duckdb_get_type_id")
    optsym(destroyType, "duckdb_destroy_logical_type")
    optsym(decimalScale, "duckdb_decimal_scale")
    optsym(decimalInternal, "duckdb_decimal_internal_type")
    optsym(enumInternal, "duckdb_enum_internal_type")
    optsym(enumSize, "duckdb_enum_dictionary_size")
    optsym(enumValue, "duckdb_enum_dictionary_value")
    optsym(structCount, "duckdb_struct_type_child_count")
    optsym(structName, "duckdb_struct_type_child_name")
    optsym(unionCount, "duckdb_union_type_member_count")
    optsym(unionName, "duckdb_union_type_member_name")
    optsym(arraySize, "duckdb_array_type_array_size")
    chunked = not api.resultChunkCount.isNil and
                   not api.resultGetChunk.isNil and
                   not api.destroyChunk.isNil and
                   not api.chunkSize.isNil and
                   not api.chunkVector.isNil and
                   not api.vectorType.isNil and
                   not api.vectorData.isNil and
                   not api.vectorValidity.isNil and
                   not api.listChild.isNil and
                   not api.structChild.isNil and
                   not api.arrayChild.isNil and
                   not api.typeId.isNil and
                   not api.destroyType.isNil and
                   not api.decimalScale.isNil and
                   not api.decimalInternal.isNil and
                   not api.enumInternal.isNil and
                   not api.enumSize.isNil and
                   not api.enumValue.isNil and
                   not api.structCount.isNil and
                   not api.structName.isNil and
                   not api.unionCount.isNil and
                   not api.unionName.isNil and
                   not api.arraySize.isNil
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
  result = Connection(path: (if mem: ":memoire:" else: key), conn: c, shared: sh)
  initLock(result.lk)

proc newSession*(c: Connection): Connection =
  ## Nouvelle connexion sur la même base (même catalogue, mêmes bases attachées,
  ## mais USE, SET et tables temporaires propres) : requêtes simultanées.
  if c.isNil or c.conn.isNil: fail("base fermée")
  var p: PConnection = nil
  if api.connect(c.shared.db, addr p) != 0: fail("connexion à la base impossible")
  withLock libLock:
    inc c.shared.refs
  result = Connection(path: c.path, conn: p, shared: c.shared)
  initLock(result.lk)

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

proc typeNameOf(id: int): string =
  const names = ["INVALID", "BOOLEAN", "TINYINT", "SMALLINT", "INTEGER", "BIGINT", "UTINYINT", "USMALLINT",
                 "UINTEGER", "UBIGINT", "FLOAT", "DOUBLE", "TIMESTAMP", "DATE", "TIME", "INTERVAL", "HUGEINT",
                 "VARCHAR", "BLOB", "DECIMAL", "TIMESTAMP_S", "TIMESTAMP_MS", "TIMESTAMP_NS", "ENUM", "LIST",
                 "STRUCT", "MAP", "UUID", "UNION", "BIT", "TIME_TZ", "TIMESTAMP_TZ", "UHUGEINT", "ARRAY",
                 "ANY", "BIGNUM", "SQLNULL"]
  if id >= 0 and id < names.len: names[id] else: "INCONNU"

proc readResultLegacy(r: var DuckResult): QueryResult =
  let nc = int(api.columnCount(addr r))
  let nr = int(api.rowCount(addr r))
  result.changed = int64(api.rowsChanged(addr r))
  for c in 0 ..< nc: result.columns.add $api.columnName(addr r, uint64(c))
  var types = newSeq[int](nc)
  for c in 0 ..< nc: types[c] = int(api.columnType(addr r, uint64(c)))
  for c in 0 ..< nc: result.types.add typeNameOf(types[c])
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

# ---------------------------------------------------------------- lecture par blocs
# Chaque colonne d'un bloc est décodée d'après son type logique, sans passer par
# les fonctions duckdb_value_* (dépréciées) qui ne savent pas lire UUID, TIMESTAMP
# WITH TIME ZONE, BIT, LIST, STRUCT... (types fournis notamment par les extensions
# mssql, postgres, sqlite...). Les valeurs simples restent des nombres, booléens
# et textes ; les autres deviennent du texte au format de DuckDB.

type
  Dec = ref object
    tid: int                       # identifiant de type DuckDB
    data: pointer
    valid: ptr UncheckedArray[uint64]
    kids: seq[Dec]
    names: seq[string]
    scale: int                     # DECIMAL
    inner: int                     # type interne de DECIMAL / ENUM
    dict: seq[string]              # ENUM
    arrSize: int                   # ARRAY

template at[T](p: pointer, i: int): T = cast[ptr UncheckedArray[T]](p)[i]

proc mkDec(vec: pointer): Dec =
  result = Dec(data: api.vectorData(vec), valid: cast[ptr UncheckedArray[uint64]](api.vectorValidity(vec)))
  var lt = api.vectorType(vec)
  if lt.isNil:
    result.tid = 0
    return
  defer: api.destroyType(addr lt)
  result.tid = int(api.typeId(lt))
  case result.tid
  of 19:
    result.scale = int(api.decimalScale(lt))
    result.inner = int(api.decimalInternal(lt))
  of 23:
    result.inner = int(api.enumInternal(lt))
    for i in 0 ..< int(api.enumSize(lt)):
      let p = api.enumValue(lt, uint64(i))
      result.dict.add(if p.isNil: "" else: $p)
      if not p.isNil: api.free(p)
  of 24, 26:                       # LIST, MAP (liste de structures clé / valeur)
    result.kids.add mkDec(api.listChild(vec))
  of 33:
    result.arrSize = int(api.arraySize(lt))
    result.kids.add mkDec(api.arrayChild(vec))
  of 25:
    for i in 0 ..< int(api.structCount(lt)):
      let p = api.structName(lt, uint64(i))
      result.names.add(if p.isNil: "" else: $p)
      if not p.isNil: api.free(p)
      result.kids.add mkDec(api.structChild(vec, uint64(i)))
  of 28:                           # UNION : enfant 0 = étiquette, puis les membres
    let n = int(api.unionCount(lt))
    for i in 0 ..< n:
      let p = api.unionName(lt, uint64(i))
      result.names.add(if p.isNil: "" else: $p)
      if not p.isNil: api.free(p)
    for i in 0 .. n: result.kids.add mkDec(api.structChild(vec, uint64(i)))
  else: discard

proc ok(d: Dec, i: int): bool =
  d.valid.isNil or ((d.valid[i shr 6] shr uint64(i and 63)) and 1'u64) == 1'u64

proc strAt(p: pointer, i: int): string =
  ## duckdb_string_t : longueur sur 4 octets, puis 12 octets en ligne ou préfixe + pointeur.
  let base = cast[uint](p) + uint(i * 16)
  let n = int(cast[ptr uint32](base)[])
  result = newString(n)
  if n == 0: return
  if n <= 12: copyMem(addr result[0], cast[pointer](base + 4), n)
  else: copyMem(addr result[0], cast[ptr pointer](base + 8)[], n)

proc u128str(hi, lo: uint64): string =
  if hi == 0: return $lo
  var limbs = [uint32(hi shr 32), uint32(hi and 0xFFFFFFFF'u64), uint32(lo shr 32), uint32(lo and 0xFFFFFFFF'u64)]
  while limbs != [0'u32, 0, 0, 0]:
    var rem = 0'u64
    for k in 0 .. 3:
      let cur = (rem shl 32) or uint64(limbs[k])
      limbs[k] = uint32(cur div 10)
      rem = cur mod 10
    result.add char(ord('0') + int(rem))
  result.reverse()

proc i128str(hi: int64, lo: uint64): string =
  if hi >= 0: return u128str(uint64(hi), lo)
  let nlo = (not lo) + 1
  let nhi = (not uint64(hi)) + (if nlo == 0: 1'u64 else: 0'u64)
  "-" & u128str(nhi, nlo)

proc p2(n: int64): string = (if n < 10: "0" else: "") & $n

proc civil(z0: int64): (int64, int, int) =
  ## jours depuis 1970-01-01 -> (année, mois, jour), calendrier grégorien proleptique
  let z = z0 + 719468
  let era = (if z >= 0: z else: z - 146096) div 146097
  let doe = z - era * 146097
  let yoe = (doe - doe div 1460 + doe div 36524 - doe div 146096) div 365
  let doy = doe - (365 * yoe + yoe div 4 - yoe div 100)
  let mp = (5 * doy + 2) div 153
  let d = int(doy - (153 * mp + 2) div 5 + 1)
  let m = int(if mp < 10: mp + 3 else: mp - 9)
  (yoe + era * 400 + (if m <= 2: 1 else: 0), m, d)

proc fmtDate(days: int64): string =
  let (y, m, d) = civil(days)
  if y <= 0: return align($(1 - y), 4, '0') & "-" & p2(m) & "-" & p2(d) & " (BC)"
  align($y, 4, '0') & "-" & p2(m) & "-" & p2(d)

proc fmtClock(units, perSec: int64): string =
  ## durée dans la journée (en unités de 1/perSec s) -> HH:MM:SS[.fraction]
  let secs = units div perSec
  let frac = units mod perSec
  result = p2(secs div 3600) & ":" & p2((secs div 60) mod 60) & ":" & p2(secs mod 60)
  if frac != 0:
    let w = (if perSec == 1_000_000_000: 9 elif perSec == 1000: 3 else: 6)
    result.add "." & align($frac, w, '0').strip(leading = false, chars = {'0'})

proc fmtStamp(v: int64, perSec: int64): string =
  if v == high(int64): return "infinity"
  if v == -high(int64): return "-infinity"
  let perDay = 86400 * perSec
  let days = floorDiv(v, perDay)
  fmtDate(days) & " " & fmtClock(v - days * perDay, perSec)

proc fmtInterval(months, days: int32, us: int64): string =
  var parts: seq[string]
  let y = months div 12
  let mo = months mod 12
  if y != 0: parts.add $y & (if abs(y) == 1: " year" else: " years")
  if mo != 0: parts.add $mo & (if abs(mo) == 1: " month" else: " months")
  if days != 0: parts.add $days & (if abs(days) == 1: " day" else: " days")
  if us != 0 or parts.len == 0:
    parts.add (if us < 0: "-" else: "") & fmtClock(abs(us), 1_000_000)
  parts.join(" ")

proc fmtOffset(sec: int): string =
  let a = abs(sec)
  result = (if sec < 0: "-" else: "+") & p2(a div 3600)
  if (a div 60) mod 60 != 0 or a mod 60 != 0: result.add ":" & p2((a div 60) mod 60)
  if a mod 60 != 0: result.add ":" & p2(a mod 60)

proc fmtUuid(hi: int64, lo: uint64): string =
  let h = toHex(uint64(hi) xor 0x8000000000000000'u64, 16).toLowerAscii & toHex(lo, 16).toLowerAscii
  h[0 .. 7] & "-" & h[8 .. 11] & "-" & h[12 .. 15] & "-" & h[16 .. 19] & "-" & h[20 .. 31]

proc fmtBits(s: string): string =
  if s.len == 0: return ""
  let pad = ord(s[0])
  for b in pad ..< (s.len - 1) * 8:
    result.add(if ((ord(s[1 + b div 8]) shr (7 - b mod 8)) and 1) == 1: '1' else: '0')

proc fmtBlob(s: string): string =
  for ch in s:
    if ord(ch) >= 32 and ord(ch) < 127 and ch != '\\': result.add ch
    else: result.add "\\x" & toHex(ord(ch), 2)

proc fmtFloat(f: float64): string =
  if f == trunc(f) and abs(f) < 1e15: $int64(f) & ".0" else: $f

proc decimalDigits(d: Dec, i: int): string =
  let raw = case d.inner
    of 3: $at[int16](d.data, i)
    of 4: $at[int32](d.data, i)
    of 5: $at[int64](d.data, i)
    else: i128str(at[int64](d.data, 2 * i + 1), at[uint64](d.data, 2 * i))
  if d.scale <= 0: return raw
  let neg = raw.startsWith("-")
  var digits = (if neg: raw[1 .. ^1] else: raw)
  if digits.len <= d.scale: digits = align(digits, d.scale + 1, '0')
  (if neg: "-" else: "") & digits[0 ..< digits.len - d.scale] & "." & digits[digits.len - d.scale .. ^1]

proc enumIndex(d: Dec, i: int): int =
  case d.inner
  of 6: int(at[uint8](d.data, i))
  of 7: int(at[uint16](d.data, i))
  else: int(at[uint32](d.data, i))

proc textOf(d: Dec, i: int, nested = false): string

proc nestedText(d: Dec, i: int): string =
  if not d.ok(i): "NULL" else: textOf(d, i, true)

proc textOf(d: Dec, i: int, nested = false): string =
  ## valeur en texte, au format de DuckDB
  case d.tid
  of 1: (if at[bool](d.data, i): "true" else: "false")
  of 2: $at[int8](d.data, i)
  of 3: $at[int16](d.data, i)
  of 4: $at[int32](d.data, i)
  of 5: $at[int64](d.data, i)
  of 6: $at[uint8](d.data, i)
  of 7: $at[uint16](d.data, i)
  of 8: $at[uint32](d.data, i)
  of 9: $at[uint64](d.data, i)
  of 10: fmtFloat(float64(at[float32](d.data, i)))
  of 11: fmtFloat(at[float64](d.data, i))
  of 12: fmtStamp(at[int64](d.data, i), 1_000_000)
  of 31:                           # avec fuseau : heure locale du poste, comme DuckDB par défaut
    let v = at[int64](d.data, i)
    if v == high(int64) or v == -high(int64): fmtStamp(v, 1_000_000)
    else:
      var off = 0
      try: off = -fromUnix(floorDiv(v, 1_000_000)).local.utcOffset
      except CatchableError: off = 0
      fmtStamp(v + int64(off) * 1_000_000, 1_000_000) & fmtOffset(off)
  of 20: fmtStamp(at[int64](d.data, i), 1)
  of 21: fmtStamp(at[int64](d.data, i), 1000)
  of 22: fmtStamp(at[int64](d.data, i), 1_000_000_000)
  of 13:
    let v = at[int32](d.data, i)
    if v == high(int32): "infinity" elif v == -high(int32): "-infinity" else: fmtDate(int64(v))
  of 14: fmtClock(at[int64](d.data, i), 1_000_000)
  of 30:
    let bits = at[uint64](d.data, i)
    fmtClock(int64(bits shr 24), 1_000_000) & fmtOffset(57599 - int(bits and 0xFFFFFF'u64))
  of 15:
    let base = cast[uint](d.data) + uint(i * 16)
    fmtInterval(cast[ptr int32](base)[], cast[ptr int32](base + 4)[], cast[ptr int64](base + 8)[])
  of 16: i128str(at[int64](d.data, 2 * i + 1), at[uint64](d.data, 2 * i))
  of 32: u128str(at[uint64](d.data, 2 * i + 1), at[uint64](d.data, 2 * i))
  of 27: fmtUuid(at[int64](d.data, 2 * i + 1), at[uint64](d.data, 2 * i))
  of 17: strAt(d.data, i)
  of 18: (if nested: fmtBlob(strAt(d.data, i)) else: strAt(d.data, i))
  of 29: fmtBits(strAt(d.data, i))
  of 19: decimalDigits(d, i)
  of 23:
    let k = enumIndex(d, i)
    if k < d.dict.len: d.dict[k] else: $k
  of 24, 26:
    let off = int(at[uint64](d.data, 2 * i))
    let n = int(at[uint64](d.data, 2 * i + 1))
    var parts: seq[string]
    let kid = d.kids[0]
    for j in off ..< off + n:
      if d.tid == 26 and kid.kids.len >= 2:
        parts.add nestedText(kid.kids[0], j) & "=" & nestedText(kid.kids[1], j)
      else:
        parts.add nestedText(kid, j)
    if d.tid == 26: "{" & parts.join(", ") & "}" else: "[" & parts.join(", ") & "]"
  of 33:
    var parts: seq[string]
    for j in i * d.arrSize ..< (i + 1) * d.arrSize: parts.add nestedText(d.kids[0], j)
    "[" & parts.join(", ") & "]"
  of 25:
    var parts: seq[string]
    for k in 0 ..< d.kids.len:
      parts.add "'" & d.names[k] & "': " & nestedText(d.kids[k], i)
    "{" & parts.join(", ") & "}"
  of 28:
    let tag = int(at[uint8](d.kids[0].data, i))
    if tag + 1 < d.kids.len: nestedText(d.kids[tag + 1], i) else: ""
  else: ""

proc numCell(s: string): DbCell =
  ## nombre exact si possible ; texte si un nombre Lexis+ perdrait des chiffres
  ## (entiers au-delà de 64 bits, décimaux de plus de 15 chiffres significatifs).
  var sig = 0
  for ch in s.strip(chars = {'-', '0', '.'}):
    if ch in Digits: inc sig
  try:
    if '.' notin s:
      return DbCell(kind: ckInt, i: parseBiggestInt(s))
    if sig > 15: return DbCell(kind: ckText, s: s)
    DbCell(kind: ckFloat, f: parseFloat(s))
  except ValueError: DbCell(kind: ckText, s: s)

proc cellOf(d: Dec, i: int): DbCell =
  if not d.ok(i) or d.tid == 36: return DbCell(kind: ckNull)
  case d.tid
  of 1: DbCell(kind: ckBool, b: at[bool](d.data, i))
  of 2: DbCell(kind: ckInt, i: int64(at[int8](d.data, i)))
  of 3: DbCell(kind: ckInt, i: int64(at[int16](d.data, i)))
  of 4: DbCell(kind: ckInt, i: int64(at[int32](d.data, i)))
  of 5: DbCell(kind: ckInt, i: at[int64](d.data, i))
  of 6: DbCell(kind: ckInt, i: int64(at[uint8](d.data, i)))
  of 7: DbCell(kind: ckInt, i: int64(at[uint16](d.data, i)))
  of 8: DbCell(kind: ckInt, i: int64(at[uint32](d.data, i)))
  of 10: DbCell(kind: ckFloat, f: float64(at[float32](d.data, i)))
  of 11: DbCell(kind: ckFloat, f: at[float64](d.data, i))
  of 9, 16, 32, 19: numCell(textOf(d, i))
  else: DbCell(kind: ckText, s: textOf(d, i))

proc readResult(r: var DuckResult): QueryResult =
  if not chunked: return readResultLegacy(r)
  let nc = int(api.columnCount(addr r))
  result.changed = int64(api.rowsChanged(addr r))
  for c in 0 ..< nc:
    result.columns.add $api.columnName(addr r, uint64(c))
    result.types.add typeNameOf(int(api.columnType(addr r, uint64(c))))
  let nch = int(api.resultChunkCount(r))
  for k in 0 ..< nch:
    var ch = api.resultGetChunk(r, uint64(k))
    if ch.isNil: continue
    try:
      let n = int(api.chunkSize(ch))
      var decs = newSeq[Dec](nc)
      for c in 0 ..< nc: decs[c] = mkDec(api.chunkVector(ch, uint64(c)))
      for row in 0 ..< n:
        var line = newSeq[DbCell](nc)
        for c in 0 ..< nc: line[c] = cellOf(decs[c], row)
        result.rows.add line
    finally:
      api.destroyChunk(addr ch)

proc exec*(c: Connection, sql: string, params: openArray[DbCell] = []): QueryResult =
  ## Exécute une requête (paramètres « ? »). Lève DuckError. Sûr entre fils : les
  ## requêtes d'une même connexion passent l'une après l'autre.
  if c.isNil or c.conn.isNil: fail("base fermée")
  acquire(c.lk)
  defer: release(c.lk)
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
