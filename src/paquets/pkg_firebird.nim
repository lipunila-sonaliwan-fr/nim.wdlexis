# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet firebird : bases Firebird (serveur ou fichier local)
#
# Liaison directe à la bibliothèque cliente Firebird (libfbclient.so /
# libfbclient.dylib / fbclient.dll), chargée à l'exécution, sans dépendance
# Nimble ni ODBC. API C native (interface ISC / DSQL), Firebird 2.5 à 5.
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
# La bibliothèque est cherchée : variable WDLEXIS_FIREBIRD (chemin complet),
# dossier linOS / macOS / winOS à côté de l'exécutable, du dossier courant
# ou du programme, puis bibliothèques du système.

import std/[dynlib, os, strutils, times, math]
import ../lexis/api
from std/unicode import toUpper
from ../lexis/duck import osDir

when defined(windows):
  {.pragma: fbcall, stdcall, gcsafe.}
  const FbNames = ["fbclient.dll", "gds32.dll"]
elif defined(macosx):
  {.pragma: fbcall, cdecl, gcsafe.}
  const FbNames = ["libfbclient.dylib", "/Library/Frameworks/Firebird.framework/Libraries/libfbclient.dylib",
                   "/Library/Frameworks/Firebird.framework/Firebird",
                   "/opt/homebrew/lib/libfbclient.dylib", "/usr/local/lib/libfbclient.dylib"]
else:
  {.pragma: fbcall, cdecl, gcsafe.}
  const FbNames = ["libfbclient.so.2", "libfbclient.so", "/opt/firebird/lib/libfbclient.so",
                   "/usr/lib/x86_64-linux-gnu/libfbclient.so.2"]

const
  LibFile = when defined(windows): "fbclient.dll" elif defined(macosx): "libfbclient.dylib" else: "libfbclient.so"

  SQL_DIALECT_V6 = 3'u16
  SQLDA_VERSION1 = 1'i16
  DSQL_drop = 2'u16

  SQL_TEXT = 452
  SQL_VARYING = 448
  SQL_SHORT = 500
  SQL_LONG = 496
  SQL_FLOAT = 482
  SQL_DOUBLE = 480
  SQL_D_FLOAT = 530
  SQL_TIMESTAMP = 510
  SQL_BLOB = 520
  SQL_ARRAY = 540
  SQL_QUAD = 550
  SQL_TYPE_TIME = 560
  SQL_TYPE_DATE = 570
  SQL_INT64 = 580
  SQL_TIMESTAMP_TZ_EX = 32748
  SQL_TIME_TZ_EX = 32750
  SQL_INT128 = 32752
  SQL_TIMESTAMP_TZ = 32754
  SQL_TIME_TZ = 32756
  SQL_DEC16 = 32760
  SQL_DEC34 = 32762
  SQL_BOOLEAN = 32764
  SQL_NULL = 32766

  CS_OCTETS = 1

  isc_info_end = 1'u8
  isc_info_truncated = 2'u8
  isc_info_sql_stmt_type = 21'u8
  isc_info_sql_records = 23'u8
  isc_info_req_select_count = 13'u8
  isc_info_req_insert_count = 14'u8
  isc_info_req_update_count = 15'u8
  isc_info_req_delete_count = 16'u8
  isc_info_sql_stmt_select = 1
  isc_info_sql_stmt_select_for_upd = 12

  isc_segment = 335544366
  isc_segstr_eof = 335544367

  isc_dpb_version1 = 1'u8
  isc_dpb_user_name = 28'u8
  isc_dpb_password = 29'u8
  isc_dpb_lc_ctype = 48'u8
  isc_dpb_sql_role_name = 60'u8

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

type
  IscStatus = int                         # intptr_t
  StatusVector = array[20, IscStatus]
  # Les handles sont des entiers 32 bits (Firebird >= 2.5) ; un entier de la
  # taille d'un pointeur, initialisé à zéro, convient aussi (petit-boutiste).
  FbHandle = uint

  IscQuad {.pure.} = object
    high: int32
    low: uint32

  XSqlVar {.pure.} = object
    sqltype: int16
    sqlscale: int16
    sqlsubtype: int16
    sqllen: int16
    sqldata: ptr UncheckedArray[uint8]
    sqlind: ptr int16
    sqlname_length: int16
    sqlname: array[32, char]
    relname_length: int16
    relname: array[32, char]
    ownname_length: int16
    ownname: array[32, char]
    aliasname_length: int16
    aliasname: array[32, char]

  XSqlDA {.pure.} = object
    version: int16
    sqldaid: array[8, char]
    sqldabc: int32
    sqln: int16
    sqld: int16
    sqlvar: array[1, XSqlVar]

  PXSqlDA = ptr XSqlDA

  Teb {.pure.} = object
    db: ptr FbHandle
    tpbLen: int
    tpb: ptr uint8

  Api = object
    attach_database: proc (st: ptr IscStatus, n: int16, name: cstring, db: ptr FbHandle,
                           dpbLen: int16, dpb: pointer): IscStatus {.fbcall.}
    detach_database: proc (st: ptr IscStatus, db: ptr FbHandle): IscStatus {.fbcall.}
    start_multiple: proc (st: ptr IscStatus, tr: ptr FbHandle, n: int16, teb: pointer): IscStatus {.fbcall.}
    commit_transaction: proc (st: ptr IscStatus, tr: ptr FbHandle): IscStatus {.fbcall.}
    rollback_transaction: proc (st: ptr IscStatus, tr: ptr FbHandle): IscStatus {.fbcall.}
    dsql_allocate_statement: proc (st: ptr IscStatus, db: ptr FbHandle, stmt: ptr FbHandle): IscStatus {.fbcall.}
    dsql_prepare: proc (st: ptr IscStatus, tr: ptr FbHandle, stmt: ptr FbHandle, n: uint16, sql: cstring,
                        dialect: uint16, da: PXSqlDA): IscStatus {.fbcall.}
    dsql_describe: proc (st: ptr IscStatus, stmt: ptr FbHandle, v: uint16, da: PXSqlDA): IscStatus {.fbcall.}
    dsql_describe_bind: proc (st: ptr IscStatus, stmt: ptr FbHandle, v: uint16, da: PXSqlDA): IscStatus {.fbcall.}
    dsql_execute: proc (st: ptr IscStatus, tr: ptr FbHandle, stmt: ptr FbHandle, v: uint16, da: PXSqlDA): IscStatus {.fbcall.}
    dsql_execute2: proc (st: ptr IscStatus, tr: ptr FbHandle, stmt: ptr FbHandle, v: uint16,
                         inDa, outDa: PXSqlDA): IscStatus {.fbcall.}
    dsql_execute_immediate: proc (st: ptr IscStatus, db: ptr FbHandle, tr: ptr FbHandle, n: uint16,
                                  sql: cstring, dialect: uint16, da: PXSqlDA): IscStatus {.fbcall.}
    dsql_fetch: proc (st: ptr IscStatus, stmt: ptr FbHandle, v: uint16, da: PXSqlDA): IscStatus {.fbcall.}
    dsql_free_statement: proc (st: ptr IscStatus, stmt: ptr FbHandle, opt: uint16): IscStatus {.fbcall.}
    dsql_sql_info: proc (st: ptr IscStatus, stmt: ptr FbHandle, itemsLen: int16, items: pointer,
                         bufLen: int16, buf: pointer): IscStatus {.fbcall.}
    open_blob2: proc (st: ptr IscStatus, db: ptr FbHandle, tr: ptr FbHandle, blob: ptr FbHandle,
                      id: ptr IscQuad, bpbLen: uint16, bpb: pointer): IscStatus {.fbcall.}
    create_blob2: proc (st: ptr IscStatus, db: ptr FbHandle, tr: ptr FbHandle, blob: ptr FbHandle,
                        id: ptr IscQuad, bpbLen: int16, bpb: pointer): IscStatus {.fbcall.}
    get_segment: proc (st: ptr IscStatus, blob: ptr FbHandle, actual: ptr uint16, bufLen: uint16,
                       buf: pointer): IscStatus {.fbcall.}
    put_segment: proc (st: ptr IscStatus, blob: ptr FbHandle, n: uint16, buf: pointer): IscStatus {.fbcall.}
    close_blob: proc (st: ptr IscStatus, blob: ptr FbHandle): IscStatus {.fbcall.}
    interpret: proc (buf: cstring, n: cuint, st: ptr ptr IscStatus): int32 {.fbcall.}        # fb_interpret
    interprete: proc (buf: cstring, st: ptr ptr IscStatus): int32 {.fbcall.}               # isc_interprete (ancien)
    sqlcode: proc (st: ptr IscStatus): int32 {.fbcall.}
    client_version: proc (buf: cstring) {.fbcall.}

var fb: Api
var loaded = false
var loadError = ""

proc candidates(extra: openArray[string]): seq[string] =
  let env = getEnv("WDLEXIS_FIREBIRD")
  if env.len > 0: result.add env
  let exe = getAppDir()
  result.add exe / osDir / LibFile
  result.add exe / LibFile
  when defined(macosx):
    result.add exe / ".." / "Frameworks" / LibFile
    result.add exe / ".." / "Resources" / osDir / LibFile
  result.add getCurrentDir() / osDir / LibFile
  for d in extra:
    if d.len > 0:
      result.add d / osDir / LibFile
      result.add d / LibFile
  for n in FbNames: result.add n

proc loadFirebird(extra: openArray[string]): bool =
  if loaded: return true
  var lib: LibHandle = nil
  for n in candidates(extra):
    lib = loadLib(n)
    if not lib.isNil: break
  if lib.isNil:
    loadError = "bibliothèque cliente Firebird (" & LibFile & ") introuvable ; installez le client " &
                "Firebird, placez la bibliothèque dans le dossier « " & osDir & " » à côté de " &
                "l'exécutable ou du programme, ou indiquez son chemin dans la variable WDLEXIS_FIREBIRD"
    return false
  template sym(field: untyped, name: string) =
    let p = lib.symAddr(name)
    if p.isNil:
      loadError = "symbole Firebird manquant : " & name
      return false
    fb.field = cast[typeof(fb.field)](p)
  template symOpt(field: untyped, name: string) =
    fb.field = cast[typeof(fb.field)](lib.symAddr(name))
  sym(attach_database, "isc_attach_database")
  sym(detach_database, "isc_detach_database")
  sym(start_multiple, "isc_start_multiple")
  sym(commit_transaction, "isc_commit_transaction")
  sym(rollback_transaction, "isc_rollback_transaction")
  sym(dsql_allocate_statement, "isc_dsql_allocate_statement")
  sym(dsql_prepare, "isc_dsql_prepare")
  sym(dsql_describe, "isc_dsql_describe")
  sym(dsql_describe_bind, "isc_dsql_describe_bind")
  sym(dsql_execute, "isc_dsql_execute")
  sym(dsql_execute2, "isc_dsql_execute2")
  sym(dsql_execute_immediate, "isc_dsql_execute_immediate")
  sym(dsql_fetch, "isc_dsql_fetch")
  sym(dsql_free_statement, "isc_dsql_free_statement")
  sym(dsql_sql_info, "isc_dsql_sql_info")
  sym(open_blob2, "isc_open_blob2")
  sym(create_blob2, "isc_create_blob2")
  sym(get_segment, "isc_get_segment")
  sym(put_segment, "isc_put_segment")
  sym(close_blob, "isc_close_blob")
  symOpt(interpret, "fb_interpret")
  symOpt(interprete, "isc_interprete")
  symOpt(sqlcode, "isc_sqlcode")
  symOpt(client_version, "isc_get_client_version")
  loaded = true
  true

#
# Erreurs
#

proc failed(st: StatusVector): bool {.inline.} = st[0] == 1 and st[1] > 0

proc statusText(st: var StatusVector): string =
  var p = addr st[0]
  var buf: array[1024, char]
  var lines: seq[string]
  for _ in 0 ..< 20:
    var n: int32
    if not fb.interpret.isNil: n = fb.interpret(cast[cstring](addr buf[0]), cuint(buf.len), addr p)
    elif not fb.interprete.isNil: n = fb.interprete(cast[cstring](addr buf[0]), addr p)
    else: break
    if n <= 0: break
    lines.add $cast[cstring](addr buf[0])
  result = lines.join(" ; ")
  if result.len == 0: result = "erreur " & $st[1]
  if not fb.sqlcode.isNil:
    let code = fb.sqlcode(addr st[0])
    if code != 0 and code != -999: result.add " (SQLCODE " & $code & ")"

proc fbError(st: var StatusVector, what: string) {.noreturn.} =
  rtError("firebird : " & what & " : " & statusText(st))

template check(st: var StatusVector, what: string, call: untyped) =
  discard call
  if failed(st): fbError(st, what)

#
# Connexion
#

type
  LFbDb = ref object of LUser
    db: FbHandle
    tr: FbHandle                  # transaction explicite en cours (0 = aucune).
    tpb: seq[uint8]               # options des transactions automatiques.
    closed: bool
    changes: int

var dbMethods {.threadvar.}: LTable

proc addItem(b: var seq[uint8], code: uint8, s: string) =
  if s.len > 255: rtError("firebird : paramètre de connexion trop long")
  b.add code
  b.add uint8(s.len)
  for c in s: b.add uint8(c)

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

proc startTr(d: LFbDb, tpb: seq[uint8]): FbHandle =
  var st: StatusVector
  var t = Teb(db: addr d.db, tpbLen: tpb.len, tpb: unsafeAddr tpb[0])
  check(st, "début de transaction", fb.start_multiple(addr st[0], addr result, 1, addr t))

proc commitTr(tr: var FbHandle) =
  var st: StatusVector
  check(st, "validation", fb.commit_transaction(addr st[0], addr tr))
  tr = 0

proc rollbackTr(tr: var FbHandle) =
  var st: StatusVector
  discard fb.rollback_transaction(addr st[0], addr tr)
  tr = 0

#
# Descripteurs (XSQLDA)
#

type
  Da = object
    p: PXSqlDA
    bufs: seq[pointer]
    orig: seq[int]                # type d'origine de chaque colonne de sortie.

proc newDa(n: int): Da =
  let size = sizeof(XSqlDA) + max(0, n - 1) * sizeof(XSqlVar)
  result.p = cast[PXSqlDA](alloc0(size))
  result.p.version = SQLDA_VERSION1
  result.p.sqln = int16(max(n, 1))

proc vars(d: Da): ptr UncheckedArray[XSqlVar] =
  cast[ptr UncheckedArray[XSqlVar]](addr d.p.sqlvar[0])

proc count(d: Da): int = (if d.p.isNil: 0 else: int(d.p.sqld))

proc keep(d: var Da, n: int): pointer =
  result = alloc0(max(n, 1))
  d.bufs.add result

proc free(d: var Da) =
  for b in d.bufs: dealloc(b)
  d.bufs.setLen(0)
  if not d.p.isNil:
    dealloc(d.p)
    d.p = nil

proc baseType(v: XSqlVar): int = int(v.sqltype) and not 1

proc colName(v: XSqlVar): string =
  let n = if v.aliasname_length > 0: int(v.aliasname_length) else: int(v.sqlname_length)
  let src = if v.aliasname_length > 0: v.aliasname else: v.sqlname
  result = newString(min(n, 32))
  for i in 0 ..< result.len: result[i] = src[i]
  result = toUpper(result.strip())

proc allocOutput(d: var Da) =
  ## Tampons de sortie ; les types que l'on ne décode pas directement
  ## (INT128, DECFLOAT, fuseaux horaires, tableaux) sont convertis en texte
  ## par le serveur.
  let v = d.vars
  d.orig.setLen(0)
  for i in 0 ..< d.count:
    d.orig.add v[i].baseType
    case v[i].baseType
    of SQL_INT128, SQL_DEC16, SQL_DEC34, SQL_TIME_TZ, SQL_TIMESTAMP_TZ, SQL_TIME_TZ_EX,
       SQL_TIMESTAMP_TZ_EX, SQL_ARRAY, SQL_NULL:
      v[i].sqltype = int16(SQL_VARYING + 1)
      v[i].sqllen = 64
      v[i].sqlsubtype = 0
    else: discard
    let n = if v[i].baseType == SQL_VARYING: int(v[i].sqllen) + 2 else: int(v[i].sqllen)
    v[i].sqldata = cast[ptr UncheckedArray[uint8]](d.keep(n))
    v[i].sqlind = cast[ptr int16](d.keep(sizeof(int16)))

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

proc readBlob(d: LFbDb, tr: var FbHandle, id: IscQuad): string =
  var st: StatusVector
  var bh: FbHandle = 0
  var q = id
  check(st, "ouverture du blob", fb.open_blob2(addr st[0], addr d.db, addr tr, addr bh, addr q, 0, nil))
  var buf: array[32768, uint8]
  while true:
    var actual: uint16 = 0
    discard fb.get_segment(addr st[0], addr bh, addr actual, uint16(buf.len), addr buf[0])
    if actual > 0:
      let start = result.len
      result.setLen(start + int(actual))
      copyMem(addr result[start], addr buf[0], int(actual))
    if st[0] == 1 and st[1] == isc_segment: continue
    if st[0] == 1 and st[1] == isc_segstr_eof: break
    if failed(st):
      var st2: StatusVector
      discard fb.close_blob(addr st2[0], addr bh)
      fbError(st, "lecture du blob")
    if actual == 0: break
  discard fb.close_blob(addr st[0], addr bh)

proc writeBlob(d: LFbDb, tr: var FbHandle, data: string): IscQuad =
  var st: StatusVector
  var bh: FbHandle = 0
  check(st, "création du blob", fb.create_blob2(addr st[0], addr d.db, addr tr, addr bh, addr result, 0, nil))
  var pos = 0
  while pos < data.len:
    let n = min(16384, data.len - pos)
    discard fb.put_segment(addr st[0], addr bh, uint16(n), unsafeAddr data[pos])
    if failed(st):
      var st2: StatusVector
      discard fb.close_blob(addr st2[0], addr bh)
      fbError(st, "écriture du blob")
    pos += n
  check(st, "fermeture du blob", fb.close_blob(addr st[0], addr bh))

proc decode(d: LFbDb, tr: var FbHandle, v: XSqlVar): Value =
  if (v.sqltype and 1) != 0 and v.sqlind[] < 0: return nilV
  let p = v.sqldata
  case v.baseType
  of SQL_TEXT:
    var s = newString(int(v.sqllen))
    if s.len > 0: copyMem(addr s[0], p, s.len)
    if (int(v.sqlsubtype) and 0xff) != CS_OCTETS: s = s.strip(leading = false)
    strV(s)
  of SQL_VARYING:
    let n = int(cast[ptr uint16](p)[])
    var s = newString(n)
    if n > 0: copyMem(addr s[0], addr p[2], n)
    strV(s)
  of SQL_SHORT: scaled(int64(cast[ptr int16](p)[]), v.sqlscale)
  of SQL_LONG: scaled(int64(cast[ptr int32](p)[]), v.sqlscale)
  of SQL_INT64: scaled(cast[ptr int64](p)[], v.sqlscale)
  of SQL_FLOAT: numV(float(cast[ptr float32](p)[]))
  of SQL_DOUBLE, SQL_D_FLOAT: numV(cast[ptr float64](p)[])
  of SQL_BOOLEAN: boolV(p[0] != 0)
  of SQL_TYPE_DATE: strV(dateTexte(cast[ptr int32](p)[]))
  of SQL_TYPE_TIME: strV(heureTexte(cast[ptr uint32](p)[]))
  of SQL_TIMESTAMP:
    strV(dateTexte(cast[ptr int32](p)[]) & " " & heureTexte(cast[ptr uint32](addr p[4])[]))
  of SQL_BLOB, SQL_QUAD:
    strV(d.readBlob(tr, cast[ptr IscQuad](p)[]))
  else: nilV

proc rowTable(d: LFbDb, tr: var FbHandle, o: Da): LTable =
  result = newLTable()
  let v = o.vars
  for i in 0 ..< o.count:
    var x = d.decode(tr, v[i])
    # INT128 / DECFLOAT (convertis en texte par le serveur) : rendus comme nombres.
    if x.kind == vkStr and i < o.orig.len and o.orig[i] in [SQL_INT128, SQL_DEC16, SQL_DEC34]:
      let t = x.s.strip
      try:
        if t.contains({'.', 'E', 'e'}): x = numV(parseFloat(t))
        else: x = intV(parseBiggestInt(t))
      except ValueError:
        try: x = numV(parseFloat(t))
        except ValueError: discard
    if x.kind != vkNil: result.rawSet(colName(v[i]), x)

proc bindParams(L: Interp, d: LFbDb, tr: var FbHandle, inp: var Da, params: seq[Value]) =
  let v = inp.vars
  for i in 0 ..< inp.count:
    let x = params[i]
    let orig = v[i].baseType
    var ind = cast[ptr int16](inp.keep(sizeof(int16)))
    v[i].sqlind = ind
    case x.kind
    of vkNil:
      v[i].sqltype = int16(SQL_TEXT + 1)
      v[i].sqllen = 1
      v[i].sqlsubtype = 0
      v[i].sqldata = cast[ptr UncheckedArray[uint8]](inp.keep(1))
      ind[] = -1
      continue
    of vkBool:
      if orig == SQL_BOOLEAN:
        v[i].sqltype = int16(SQL_BOOLEAN + 1)
        v[i].sqllen = 1
        v[i].sqldata = cast[ptr UncheckedArray[uint8]](inp.keep(1))
        v[i].sqldata[0] = (if x.b: 1'u8 else: 0'u8)
      else:
        v[i].sqltype = int16(SQL_INT64 + 1)
        v[i].sqllen = 8
        v[i].sqlscale = 0
        v[i].sqldata = cast[ptr UncheckedArray[uint8]](inp.keep(8))
        cast[ptr int64](v[i].sqldata)[] = (if x.b: 1 else: 0)
    of vkInt:
      v[i].sqltype = int16(SQL_INT64 + 1)
      v[i].sqllen = 8
      v[i].sqlscale = 0
      v[i].sqlsubtype = 0
      v[i].sqldata = cast[ptr UncheckedArray[uint8]](inp.keep(8))
      cast[ptr int64](v[i].sqldata)[] = x.i
    of vkNum:
      v[i].sqltype = int16(SQL_DOUBLE + 1)
      v[i].sqllen = 8
      v[i].sqlscale = 0
      v[i].sqlsubtype = 0
      v[i].sqldata = cast[ptr UncheckedArray[uint8]](inp.keep(8))
      cast[ptr float64](v[i].sqldata)[] = x.n
    of vkStr:
      if orig == SQL_BLOB:
        v[i].sqltype = int16(SQL_BLOB + 1)
        v[i].sqllen = 8
        v[i].sqldata = cast[ptr UncheckedArray[uint8]](inp.keep(8))
        cast[ptr IscQuad](v[i].sqldata)[] = d.writeBlob(tr, x.s)
      elif orig == SQL_TYPE_DATE:
        var ok: bool
        let days = parseDate(x.s, ok)
        if ok and x.s.len == 10:
          v[i].sqltype = int16(SQL_TYPE_DATE + 1)
          v[i].sqllen = 4
          v[i].sqldata = cast[ptr UncheckedArray[uint8]](inp.keep(4))
          cast[ptr int32](v[i].sqldata)[] = days
        else:
          if x.s.len > 32767: rtError("firebird : paramètre " & $(i + 1) & " trop long")
          v[i].sqltype = int16(SQL_TEXT + 1)
          v[i].sqllen = int16(x.s.len)
          v[i].sqlsubtype = 0
          v[i].sqldata = cast[ptr UncheckedArray[uint8]](inp.keep(x.s.len))
          if x.s.len > 0: copyMem(v[i].sqldata, unsafeAddr x.s[0], x.s.len)
      else:
        if x.s.len > 32767:
          rtError("firebird : paramètre " & $(i + 1) & " trop long (" & $x.s.len & " octets) ; utilisez une colonne BLOB")
        if orig notin [SQL_TEXT, SQL_VARYING]: v[i].sqlsubtype = 0
        v[i].sqltype = int16(SQL_TEXT + 1)
        v[i].sqllen = int16(x.s.len)
        v[i].sqldata = cast[ptr UncheckedArray[uint8]](inp.keep(x.s.len))
        if x.s.len > 0: copyMem(v[i].sqldata, unsafeAddr x.s[0], x.s.len)
    else:
      rtError("firebird : type de paramètre non pris en charge (" & typeName(x) & ")")
    ind[] = 0

#
# Instructions
#

type
  Stmt = object
    h: FbHandle
    inp, outp: Da
    kind: int

proc close(s: var Stmt) =
  if s.h != 0:
    var st: StatusVector
    discard fb.dsql_free_statement(addr st[0], addr s.h, DSQL_drop)
    s.h = 0
  s.inp.free()
  s.outp.free()

proc infoInt(buf: openArray[uint8], pos, len: int): int =
  for k in 0 ..< len: result = result or (int(buf[pos + k]) shl (8 * k))

proc stmtType(s: var Stmt): int =
  var st: StatusVector
  var items = [isc_info_sql_stmt_type]
  var buf: array[16, uint8]
  check(st, "information", fb.dsql_sql_info(addr st[0], addr s.h, 1, addr items[0], int16(buf.len), addr buf[0]))
  if buf[0] == isc_info_sql_stmt_type:
    let n = infoInt(buf, 1, 2)
    return infoInt(buf, 3, n)
  0

proc affectedRows(s: var Stmt): int =
  var st: StatusVector
  var items = [isc_info_sql_records]
  var buf: array[64, uint8]
  discard fb.dsql_sql_info(addr st[0], addr s.h, 1, addr items[0], int16(buf.len), addr buf[0])
  if failed(st) or buf[0] != isc_info_sql_records: return 0
  var pos = 3
  while pos < buf.len and buf[pos] != isc_info_end and buf[pos] != isc_info_truncated:
    let code = buf[pos]
    let n = infoInt(buf, pos + 1, 2)
    if pos + 3 + n > buf.len: break
    let val = infoInt(buf, pos + 3, n)
    if code in [isc_info_req_insert_count, isc_info_req_update_count, isc_info_req_delete_count]:
      result += val
    pos += 3 + n

proc prepare(L: Interp, d: LFbDb, tr: var FbHandle, sql: string, params: seq[Value]): Stmt =
  var st: StatusVector
  if sql.len > 65535: rtError("firebird : requête trop longue")
  check(st, "allocation", fb.dsql_allocate_statement(addr st[0], addr d.db, addr result.h))
  try:
    check(st, "requête invalide", fb.dsql_prepare(addr st[0], addr tr, addr result.h, uint16(sql.len),
                                                    sql.cstring, SQL_DIALECT_V6, nil))
    result.kind = result.stmtType()
    # colonnes de sortie
    result.outp = newDa(1)
    check(st, "description", fb.dsql_describe(addr st[0], addr result.h, 1, result.outp.p))
    if result.outp.p.sqld > result.outp.p.sqln:
      let n = int(result.outp.p.sqld)
      result.outp.free()
      result.outp = newDa(n)
      check(st, "description", fb.dsql_describe(addr st[0], addr result.h, 1, result.outp.p))
    result.outp.allocOutput()
    # paramètres
    result.inp = newDa(1)
    check(st, "description des paramètres", fb.dsql_describe_bind(addr st[0], addr result.h, 1, result.inp.p))
    if result.inp.p.sqld > result.inp.p.sqln:
      let n = int(result.inp.p.sqld)
      result.inp.free()
      result.inp = newDa(n)
      check(st, "description des paramètres", fb.dsql_describe_bind(addr st[0], addr result.h, 1, result.inp.p))
    var vals = params
    if vals.len == 1 and vals[0].kind == vkTable:        # paramètres dans une table.
      let t = vals[0].t
      vals = @[]
      for i in 1 .. t.rawLen: vals.add t.rawGet(intV(i))
    let n = result.inp.count
    if vals.len < n:
      rtError("firebird : " & $n & " paramètre(s) attendu(s), " & $vals.len & " fourni(s)")
    L.bindParams(d, tr, result.inp, vals)
  except CatchableError as e:
    result.close()
    raise e

proc isSelect(s: Stmt): bool =
  s.kind in [isc_info_sql_stmt_select, isc_info_sql_stmt_select_for_upd]

proc inPtr(s: Stmt): PXSqlDA = (if s.inp.count > 0: s.inp.p else: nil)

proc execute(L: Interp, d: LFbDb, tr: var FbHandle, s: var Stmt): seq[LTable] =
  ## Exécute ; pour une instruction qui renvoie une seule ligne (EXECUTE
  ## PROCEDURE, INSERT ... RETURNING), renvoie cette ligne.
  var st: StatusVector
  if s.isSelect:
    L.blocking: discard fb.dsql_execute(addr st[0], addr tr, addr s.h, 1, s.inPtr)
    if failed(st): fbError(st, "exécution")
  elif s.outp.count > 0:
    L.blocking: discard fb.dsql_execute2(addr st[0], addr tr, addr s.h, 1, s.inPtr, s.outp.p)
    if failed(st): fbError(st, "exécution")
    result.add d.rowTable(tr, s.outp)
    d.changes = s.affectedRows()
  else:
    L.blocking: discard fb.dsql_execute(addr st[0], addr tr, addr s.h, 1, s.inPtr)
    if failed(st): fbError(st, "exécution")
    d.changes = s.affectedRows()

proc fetch(L: Interp, d: LFbDb, tr: var FbHandle, s: var Stmt): LTable =
  ## Ligne suivante d'un SELECT, nil à la fin.
  var st: StatusVector
  var rc: IscStatus
  L.blocking: rc = fb.dsql_fetch(addr st[0], addr s.h, 1, s.outp.p)
  if rc == 100: return nil
  if failed(st): fbError(st, "lecture")
  d.rowTable(tr, s.outp)

proc checkDb(L: Interp, a: seq[Value], fname: string): LFbDb =
  result = checkUser[LFbDb](L, a, 1, fname, "base firebird")
  if result.closed: rtError("base firebird fermée")

template withTr(d: LFbDb, tr: untyped, body: untyped) =
  ## Transaction explicite en cours, ou transaction automatique validée à la
  ## fin (annulée en cas d'erreur).
  let auto = d.tr == 0
  var tr = if auto: startTr(d, d.tpb) else: d.tr
  try:
    body
    if auto: commitTr(tr)
  except CatchableError as e:
    if auto: rollbackTr(tr)
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
      s.close()

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

proc quoteLit(s: string): string = "'" & s.replace("'", "''") & "'"

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
          s.close()
    d.changes = total
    @[intV(total)]
  dm.fn "requete", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "requete")
    let rows = newLTable()
    for r in L.runAll(d, L.checkStr(a, 2, "requete"), paramsOf(a)): rows.arr.add r
    @[tableV(rows)]
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
        if not row.isNil and s.outp.count > 0:
          res = row.rawGet(colName(s.outp.vars[0]))
      finally:
        s.close()
    @[res]
  dm.fn "lignes", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Itérateur : les lignes sont lues au fur et à mesure.
    let d = L.checkDb(a, "lignes")
    let sql = L.checkStr(a, 2, "lignes")
    let auto = d.tr == 0
    var tr = if auto: startTr(d, d.tpb) else: d.tr
    var s: Stmt
    var done = false
    var pending: seq[LTable]
    try:
      s = L.prepare(d, tr, sql, paramsOf(a))
      pending = L.execute(d, tr, s)
    except CatchableError as e:
      s.close()
      if auto: rollbackTr(tr)
      raise e
    let finish = proc (ok: bool) =
      if not done:
        done = true
        s.close()
        if auto:
          if ok: commitTr(tr) else: rollbackTr(tr)
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
    d.tr = startTr(d, (if arg(a, 2).kind == vkTable: buildTpb(a[1].t) else: d.tpb))
    @[boolV(true)]
  dm.fn "valider", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "valider")
    if d.tr == 0: rtError("firebird : aucune transaction en cours")
    commitTr(d.tr)
    @[boolV(true)]
  dm.fn "annuler", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "annuler")
    if d.tr == 0: rtError("firebird : aucune transaction en cours")
    rollbackTr(d.tr)
    @[boolV(true)]
  dm.fn "entransaction", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[boolV(L.checkDb(a, "entransaction").tr != 0)]
  dm.fn "transaction", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkDb(a, "transaction")
    let f = L.checkFunc(a, 2, "transaction")
    if d.tr != 0: rtError("firebird : une transaction est déjà en cours")
    d.tr = startTr(d, (if arg(a, 3).kind == vkTable: buildTpb(a[2].t) else: d.tpb))
    try:
      result = L.call(f, @[a[0]])
      if d.tr != 0: commitTr(d.tr)
    except CatchableError as e:
      if d.tr != 0: rollbackTr(d.tr)
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
      if d.tr != 0: rollbackTr(d.tr)
      d.closed = true
      var st: StatusVector
      discard fb.detach_database(addr st[0], addr d.db)
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

  proc attach(L: Interp, base, user, pw: string, o: LTable): Value =
    var dpb = @[isc_dpb_version1]
    if user.len > 0: dpb.addItem(isc_dpb_user_name, user)
    if pw.len > 0: dpb.addItem(isc_dpb_password, pw)
    dpb.addItem(isc_dpb_lc_ctype, o.optField("jeu", "UTF8"))
    let role = o.optField("role", "")
    if role.len > 0: dpb.addItem(isc_dpb_sql_role_name, role)
    var st: StatusVector
    var db: FbHandle = 0
    if base.len > 32767: rtError("firebird : nom de base trop long")
    L.blocking:
      discard fb.attach_database(addr st[0], int16(base.len), base.cstring, addr db,
                                 int16(dpb.len), addr dpb[0])
    if failed(st): rtError("firebird : connexion à " & base & " : " & statusText(st))
    let d = LFbDb(db: db, tpb: buildTpb(o))
    L.closers.add proc () =
      if not d.closed:
        d.closed = true
        var st2: StatusVector
        if d.tr != 0: discard fb.rollback_transaction(addr st2[0], addr d.tr)
        discard fb.detach_database(addr st2[0], addr d.db)
    L.wrap(d, "firebird", dbMethods)

  let m = newLib()
  m.fn "connecter", proc (L: Interp, a: seq[Value]): seq[Value] =
    if not loadFirebird(L.searchDirs): return fail(loadError)
    let (base, user, pw, o) = L.connectArgs(a, "connecter")
    if base.len == 0: rtError("connecter : nom de la base attendu")
    @[L.attach(base, user, pw, o)]
  m.fn "creer", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Crée une base (fichier .fdb) puis s'y connecte.
    if not loadFirebird(L.searchDirs): return fail(loadError)
    let (base, user, pw, o) = L.connectArgs(a, "creer")
    if base.len == 0: rtError("creer : nom de la base attendu")
    var sql = "CREATE DATABASE " & quoteLit(base)
    if user.len > 0: sql.add " USER " & quoteLit(user)
    if pw.len > 0: sql.add " PASSWORD " & quoteLit(pw)
    sql.add " PAGE_SIZE " & $o.optField("taillepage", 8192)
    sql.add " DEFAULT CHARACTER SET " & o.optField("jeu", "UTF8")
    var st: StatusVector
    var db: FbHandle = 0
    var tr: FbHandle = 0
    L.blocking:
      discard fb.dsql_execute_immediate(addr st[0], addr db, addr tr, uint16(sql.len), sql.cstring,
                                        SQL_DIALECT_V6, nil)
    if failed(st): rtError("firebird : création de " & base & " : " & statusText(st))
    discard fb.detach_database(addr st[0], addr db)
    @[L.attach(base, user, pw, o)]
  m.fn "version", proc (L: Interp, a: seq[Value]): seq[Value] =
    if not loadFirebird(L.searchDirs): return fail(loadError)
    if fb.client_version.isNil: return @[nilV]
    var buf: array[256, char]
    fb.client_version(cast[cstring](addr buf[0]))
    @[strV($cast[cstring](addr buf[0]))]
  m.fn "disponible", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[boolV(loadFirebird(L.searchDirs))]
  tableV(m)

registerPackage PackageDef(name: "firebird", open: openFirebirdLib,
  description: "Bases Firebird (client natif fbclient)",
  docs: docs("firebird", [
    "firebird.connecter(base, utilisateur, motdepasse[, options])", "Connexion : \"serveur:/chemin/base.fdb\", \"serveur/3050:alias\" ou fichier local. Accepte aussi une table {base=, hote=, port=, utilisateur=, motdepasse=, role=, jeu=\"UTF8\", isolation=, attente=}.",
    "firebird.creer(base, utilisateur, motdepasse[, {taillepage=8192, jeu=\"UTF8\"}])", "Crée une base puis s'y connecte.",
    "firebird.version()", "Version de la bibliothèque cliente.",
    "firebird.disponible()", "Vrai si la bibliothèque cliente est trouvée.",
    "db:executer(sql, ...)", "Exécute une instruction avec paramètres « ? » ; renvoie le nombre de lignes modifiées. Sans paramètre, accepte un script d'instructions séparées par « ; » (hors blocs PSQL).",
    "db:requete(sql, ...)", "Liste des lignes ; chaque ligne est une table colonne (majuscules) -> valeur. Accepte INSERT ... RETURNING et EXECUTE PROCEDURE.",
    "db:premier(sql, ...)", "Première ligne ou nul.",
    "db:valeur(sql, ...)", "Première colonne de la première ligne ou nul.",
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
