# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - pilote Firebird natif : protocole réseau ("wire protocol")
#
# Implémentation en Nim pur du protocole distant de Firebird, sur le modèle du
# pilote "pure Java" de Jaybird (org.firebirdsql.gds.ng.wire) : aucune
# bibliothèque cliente (fbclient) n'est nécessaire, seulement une connexion TCP
# vers un serveur Firebird 3, 4 ou 5 (protocoles 13 à 17).
#
#   - négociation op_connect / op_cond_accept, authentification SRP
#     ("Srp256", "Srp") et chiffrement du flux "Arc4" ;
#   - attache / création de base, transactions, DSQL (préparation, description
#     par éléments d'information, exécution, lecture par lots), blobs ;
#   - messages décrits en BLR, valeurs codées en XDR (gros-boutiste, alignement
#     sur 4 octets), indicateurs NULL en bitmap (protocole 13+).
#
# Non pris en charge : serveurs Firebird 2.5 et antérieurs (authentification
# "Legacy_Auth"), connexion embarquée sans serveur, compression du flux,
# greffons de chiffrement autres qu'Arc4, chiffrement de base par rappel de clé.

import std/[net, nativesockets, os, strutils]
import fbcrypto

const
  # opérations
  op_connect = 1'i32
  op_accept = 3'i32
  op_reject = 4'i32
  op_disconnect = 6'i32
  op_response = 9'i32
  op_attach = 19'i32
  op_create = 20'i32
  op_detach = 21'i32
  op_transaction = 29'i32
  op_commit = 30'i32
  op_rollback = 31'i32
  op_get_segment = 36'i32
  op_put_segment = 37'i32
  op_close_blob = 39'i32
  op_open_blob2 = 56'i32
  op_create_blob2 = 57'i32
  op_allocate_statement = 62'i32
  op_execute = 63'i32
  op_fetch = 65'i32
  op_fetch_response = 66'i32
  op_free_statement = 67'i32
  op_prepare_statement = 68'i32
  op_info_sql = 70'i32
  op_dummy = 71'i32
  op_execute2 = 76'i32
  op_sql_response = 78'i32
  op_cont_auth = 92'i32
  op_accept_data = 94'i32
  op_crypt = 96'i32
  op_crypt_key_callback = 97'i32
  op_cond_accept = 98'i32

  CONNECT_VERSION3 = 3'i32
  arch_generic = 1'i32
  ptype_rpc = 2'i32
  ptype_batch_send = 3'i32
  FB_PROTOCOL_FLAG = 0x8000'i32
  FB_PROTOCOL_MASK = 0x7FFF'i32
  PROTOCOL_STMT_TOUT = 16

  # paramètres d'identification (op_connect)
  CNCT_user = 1'u8
  CNCT_host = 4'u8
  CNCT_user_verification = 6'u8
  CNCT_specific_data = 7'u8
  CNCT_plugin_name = 8'u8
  CNCT_login = 9'u8
  CNCT_plugin_list = 10'u8
  CNCT_client_crypt = 11'u8

  # bloc de paramètres de base (DPB)
  isc_dpb_version1 = 1'u8
  isc_dpb_page_size = 4'u8
  isc_dpb_user_name = 28'u8
  isc_dpb_lc_ctype = 48'u8
  isc_dpb_sql_role_name = 60'u8
  isc_dpb_sql_dialect = 63'u8
  isc_dpb_set_db_charset = 68'u8
  isc_dpb_process_id = 71'u8
  isc_dpb_process_name = 74'u8
  isc_dpb_utf8_filename = 77'u8
  isc_dpb_specific_auth_data = 84'u8
  isc_dpb_auth_plugin_list = 85'u8
  isc_dpb_auth_plugin_name = 86'u8

  # éléments d'information DSQL
  isc_info_end = 1'u8
  isc_info_truncated = 2'u8
  isc_info_sql_select = 4'u8
  isc_info_sql_bind = 5'u8
  isc_info_sql_describe_vars = 7'u8
  isc_info_sql_describe_end = 8'u8
  isc_info_sql_sqlda_seq = 9'u8
  isc_info_sql_type = 11'u8
  isc_info_sql_sub_type = 12'u8
  isc_info_sql_scale = 13'u8
  isc_info_sql_length = 14'u8
  isc_info_sql_field = 16'u8
  isc_info_sql_relation = 17'u8
  isc_info_sql_owner = 18'u8
  isc_info_sql_alias = 19'u8
  isc_info_sql_sqlda_start = 20'u8
  isc_info_sql_stmt_type = 21'u8
  isc_info_sql_records = 23'u8
  isc_info_req_insert_count = 14'u8
  isc_info_req_update_count = 15'u8
  isc_info_req_delete_count = 16'u8

  # BLR
  blr_version5 = 5'u8
  blr_begin = 2'u8
  blr_message = 4'u8
  blr_short = 7'u8
  blr_long = 8'u8
  blr_quad = 9'u8
  blr_float = 10'u8
  blr_sql_date = 12'u8
  blr_sql_time = 13'u8
  blr_text2 = 15'u8
  blr_int64 = 16'u8
  blr_bool = 23'u8
  blr_double = 27'u8
  blr_timestamp = 35'u8
  blr_varying2 = 38'u8
  blr_end = 255'u8
  blr_eoc = 76'u8

  DSQL_drop = 2'i32
  SQL_DIALECT_V6 = 3'i32
  FetchSize = 200
  InfoBufferLen = 32767
  SegmentMax = 32000

  # types SQL (XSQLVAR.sqltype sans le bit "nullable")
  SQL_TEXT* = 452
  SQL_VARYING* = 448
  SQL_SHORT* = 500
  SQL_LONG* = 496
  SQL_FLOAT* = 482
  SQL_DOUBLE* = 480
  SQL_D_FLOAT* = 530
  SQL_TIMESTAMP* = 510
  SQL_BLOB* = 520
  SQL_ARRAY* = 540
  SQL_QUAD* = 550
  SQL_TYPE_TIME* = 560
  SQL_TYPE_DATE* = 570
  SQL_INT64* = 580
  SQL_TIMESTAMP_TZ_EX* = 32748
  SQL_TIME_TZ_EX* = 32750
  SQL_INT128* = 32752
  SQL_TIMESTAMP_TZ* = 32754
  SQL_TIME_TZ* = 32756
  SQL_DEC16* = 32760
  SQL_DEC34* = 32762
  SQL_BOOLEAN* = 32764
  SQL_NULL* = 32766

  StmtSelect* = 1
  StmtSelectForUpdate* = 12
  StmtExecProcedure* = 8

  DriverVersion* = "fbwire 1.0 (Nim, protocole Firebird 13-17, Srp256/Srp, Arc4)"

type
  FbError* = object of CatchableError
    codes*: seq[int]                  # codes GDS (isc_*) de l'erreur
    sqlCode*: int

  FbVar* = object
    ## Colonne de sortie ou paramètre, tel que décrit par le serveur.
    sqltype*, subtype*, scale*, length*: int
    nullable*: bool
    field*, relation*, owner*, alias*: string
    wtype, wsub, wlen, wscale: int    # format demandé sur le réseau (BLR)

  FbValKind* = enum fvNull, fvInt, fvFloat, fvText, fvBool, fvDate, fvTime, fvStamp, fvBlob

  FbVal* = object
    ## Valeur lue (colonne) ou à envoyer (paramètre).
    kind*: FbValKind
    i*: int64                         # fvInt (avec scale), fvDate (jours), fvTime / fvStamp (heure)
    scale*: int
    f*: float
    s*: string                        # fvText ; identifiant de blob (8 octets) pour fvBlob
    sub*: int                         # jeu de caractères d'un paramètre texte
    b*: bool
    days*: int32                      # fvStamp

  FbConn* = ref object
    sock: Socket
    rbuf, wbuf: string
    rpos: int
    crypted: bool
    rin, rout: Rc4
    protocol*: int
    db: int32
    closed*: bool
    host*, path*: string
    srp: SrpClient
    user, password: string
    authPlugin, pluginList: string
    sessionKey: seq[byte]
    serverKeys: string

  FbStmt* = ref object
    h: int32
    kind*: int
    outs*, ins*: seq[FbVar]
    outBlr: string
    rows: seq[seq[FbVal]]
    rowPos: int
    eof, open: bool

proc fbFail*(msg: string, codes: seq[int] = @[], sqlCode = 0) {.noreturn.} =
  var e = newException(FbError, msg)
  e.codes = codes
  e.sqlCode = sqlCode
  raise e

proc newVal*(k: FbValKind): FbVal = FbVal(kind: k)

#
# Messages d'erreur : principaux codes du serveur (gabarits @1, @2...).
# Les autres codes sont rendus par leur numéro et leurs arguments.
#

const ErrTemplates = [
  (335544321, "arithmetic exception, numeric overflow, or string truncation"),
  (335544323, "file @1 is not a valid database"),
  (335544324, "invalid database handle (no active connection)"),
  (335544325, "bad parameters on attach or create database"),
  (335544326, "unrecognized database parameter block"),
  (335544334, "conversion error from string \"@1\""),
  (335544336, "deadlock"),
  (335544344, "I/O error during \"@1\" operation for file \"@2\""),
  (335544345, "lock conflict on no wait transaction"),
  (335544347, "validation error for column @1, value \"@2\""),
  (335544349, "attempt to store duplicate value (visible to active transactions) in unique index \"@1\""),
  (335544351, "unsuccessful metadata update"),
  (335544352, "no permission for @1 access to @2 @3"),
  (335544366, "segment buffer length shorter than expected"),
  (335544382, "@1"),
  (335544421, "connection rejected by remote interface"),
  (335544436, ""),                            # isc_sqlerr : SQLCODE, rendu à part
  (335544451, "update conflicts with concurrent update"),
  (335544466, "violation of FOREIGN KEY constraint \"@1\" on table \"@2\""),
  (335544509, "CHARACTER SET @1 is not defined"),
  (335544472, "Your user name and password are not defined. Ask your database administrator to set up a Firebird login."),
  (335544558, "Operation violates CHECK constraint @1 on view or table @2"),
  (335544569, "Dynamic SQL Error"),
  (335544570, "Invalid command"),
  (335544578, "Column unknown"),
  (335544580, "Table unknown"),
  (335544581, "Procedure unknown"),
  (335544634, "Token unknown - line @1, column @2"),
  (335544665, "violation of PRIMARY or UNIQUE KEY constraint \"@1\" on table \"@2\""),
  (335544721, "Unable to complete network request to host \"@1\""),
  (335544734, "@1"),
  (335544851, "Unknown or invalid data type"),
  (335544914, "string right truncation"),
  (335545017, "Expected length @1, actual @2"),
  (335545106, "Error occurred during login, please check server firebird.log for details"),
  (335545118, "Unknown or invalid data type")]

proc errTemplate(code: int): (bool, string) =
  for (c, t) in ErrTemplates:
    if c == code: return (true, t)
  (false, "")

#
# Lecture / écriture XDR
#

proc pad4(n: int): int {.inline.} = (4 - (n and 3)) and 3

proc netFail(e: ref Exception) {.noreturn.} =
  fbFail("erreur réseau : " & e.msg)

proc fill(c: FbConn, n: int) =
  while c.rbuf.len - c.rpos < n:
    if c.rpos > 0:
      c.rbuf = c.rbuf[c.rpos .. ^1]
      c.rpos = 0
    var tmp = newString(65536)
    var got: int
    try: got = c.sock.recv(addr tmp[0], tmp.len)
    except OSError as e: netFail(e)
    if got <= 0:
      c.closed = true
      fbFail("connexion fermée par le serveur")
    tmp.setLen(got)
    if c.crypted: c.rin.apply(tmp)
    c.rbuf.add tmp

proc readInt(c: FbConn): int32 =
  c.fill(4)
  let p = c.rpos
  result = cast[int32]((uint32(c.rbuf[p]) shl 24) or (uint32(c.rbuf[p + 1]) shl 16) or
                       (uint32(c.rbuf[p + 2]) shl 8) or uint32(c.rbuf[p + 3]))
  c.rpos += 4

proc readInt64(c: FbConn): int64 =
  let hi = uint64(cast[uint32](c.readInt))
  let lo = uint64(cast[uint32](c.readInt))
  cast[int64]((hi shl 32) or lo)

proc readOpaque(c: FbConn, n: int): string =
  ## n octets suivis du remplissage jusqu'à un multiple de 4.
  if n < 0: fbFail("réponse du serveur invalide (longueur négative)")
  let total = n + pad4(n)
  c.fill(total)
  result = c.rbuf[c.rpos ..< c.rpos + n]
  c.rpos += total

proc readBuf(c: FbConn): string = c.readOpaque(int(c.readInt))

proc wInt(c: FbConn, x: int32) =
  let u = cast[uint32](x)
  c.wbuf.add char((u shr 24) and 0xff)
  c.wbuf.add char((u shr 16) and 0xff)
  c.wbuf.add char((u shr 8) and 0xff)
  c.wbuf.add char(u and 0xff)

proc wInt(c: FbConn, x: int) = c.wInt(int32(x))

proc wOpaque(c: FbConn, s: string) =
  c.wbuf.add s
  for _ in 0 ..< pad4(s.len): c.wbuf.add '\0'

proc wBuf(c: FbConn, s: string) =
  c.wInt(s.len)
  c.wOpaque(s)

proc flush(c: FbConn) =
  if c.wbuf.len == 0: return
  if c.crypted: c.rout.apply(c.wbuf)
  try: c.sock.send(c.wbuf)
  except OSError as e:
    c.wbuf.setLen(0)
    netFail(e)
  c.wbuf.setLen(0)

proc readOp(c: FbConn): int32 =
  c.flush()
  while true:
    result = c.readInt
    if result != op_dummy: return

#
# Vecteur d'état et réponse générique
#

proc readStatus(c: FbConn) =
  ## Lit le vecteur d'état ; lève FbError s'il signale une erreur.
  type Entry = object
    code: int
    args: seq[string]
  var entries: seq[Entry]
  var warning = false
  var sqlCode = 0
  var sqlState = ""
  while true:
    let arg = c.readInt
    case arg
    of 0: break
    of 1:                                   # isc_arg_gds
      let code = int(c.readInt)
      if code != 0 and not warning: entries.add Entry(code: code)
    of 18:                                  # isc_arg_warning
      discard c.readInt
      warning = true
    of 2, 3, 5:                             # chaîne, chaîne C, message déjà interprété
      let s = c.readBuf
      if not warning:
        if arg == 5: entries.add Entry(code: -1, args: @[s])
        elif entries.len > 0: entries[^1].args.add "\"" & s & "\""
    of 19:                                  # isc_arg_sql_state
      let s = c.readBuf
      if not warning: sqlState = s
    of 4:                                   # isc_arg_number
      let n = int(c.readInt)
      if not warning and entries.len > 0:
        if entries[^1].code == 335544436 and sqlCode == 0: sqlCode = n
        else: entries[^1].args.add $n
    else:
      discard c.readInt
  if entries.len == 0: return
  var parts: seq[string]
  var codes: seq[int]
  for e in entries:
    if e.code > 0: codes.add e.code
    if e.code == 335544436: continue
    if e.code == -1:
      parts.add e.args.join(" ")
      continue
    let (known, t) = errTemplate(e.code)
    if known:
      var m = t
      for k in countdown(e.args.len, 1):
        m = m.replace("\"@" & $k & "\"", e.args[k - 1]).replace("@" & $k, e.args[k - 1])
      if m.len > 0: parts.add m
    else:
      var m = "erreur " & $e.code
      if e.args.len > 0: m.add " : " & e.args.join(", ")
      parts.add m
  var msg = parts.join(" ; ")
  if msg.len == 0: msg = "erreur Firebird"
  if sqlCode != 0: msg.add " (SQLCODE " & $sqlCode & ")"
  if sqlState.len > 0: msg.add " [SQLSTATE " & sqlState & "]"
  fbFail(msg, codes, sqlCode)

type Response = tuple[obj: int32, blobId: string, data: string]

proc readResponseBody(c: FbConn): Response =
  result.obj = c.readInt
  result.blobId = c.readOpaque(8)
  result.data = c.readBuf
  c.readStatus()

proc response(c: FbConn): Response =
  let op = c.readOp
  if op != op_response: fbFail("réponse inattendue du serveur (opération " & $op & ")")
  c.readResponseBody()

#
# Adresse de connexion
#

proc parseTarget*(base: string): tuple[host: string, port: int, path: string] =
  ## "hote:chemin", "hote/port:chemin", "[ipv6]/port:chemin",
  ## "inet://hote:port/chemin" ; sans hôte : localhost.
  result.port = 3050
  var s = base.strip
  for pre in ["inet://", "inet4://", "inet6://"]:
    if s.toLowerAscii.startsWith(pre):
      let rest = s[pre.len .. ^1]
      let slash = rest.find('/')
      if slash < 0: return (rest, 3050, "")
      var hp = rest[0 ..< slash]
      result.path = rest[slash + 1 .. ^1]
      if result.path.len > 2 and result.path[1] == ':': discard        # inet://h/C:\x.fdb
      elif result.path.len > 0 and result.path[0] != '/' and '/' in result.path:
        result.path = "/" & result.path                              # inet://h//abs -> /abs
      let colon = hp.rfind(':')
      if colon > 0 and not hp.endsWith("]"):
        try: result.port = parseInt(hp[colon + 1 .. ^1])
        except ValueError: discard
        hp = hp[0 ..< colon]
      result.host = hp.strip(chars = {'[', ']'})
      return
  var hostPart = ""
  if s.startsWith("["):
    let close = s.find(']')
    let colon = s.find(':', max(close, 0))
    if close > 0 and colon > close:
      hostPart = s[0 ..< colon]
      result.path = s[colon + 1 .. ^1]
  else:
    let colon = s.find(':')
    if colon > 1:                                # "C:\..." : chemin local Windows
      hostPart = s[0 ..< colon]
      result.path = s[colon + 1 .. ^1]
  if hostPart.len == 0:
    return ("localhost", 3050, s)
  let slash = hostPart.rfind('/')
  if slash > 0:
    let p = hostPart[slash + 1 .. ^1]
    hostPart = hostPart[0 ..< slash]
    try: result.port = parseInt(p)
    except ValueError:
      if p.toLowerAscii notin ["gds_db", "fb_db"]: result.port = 3050
  result.host = hostPart.strip(chars = {'[', ']'})

#
# Connexion, authentification, chiffrement
#

proc addCnct(b: var string, code: uint8, v: string) =
  if code == CNCT_specific_data:
    # données découpées en morceaux de 254 octets précédés de leur numéro
    var i = 0
    var step = 0
    while i < v.len or (v.len == 0 and step == 0):
      let part = v[i ..< min(i + 254, v.len)]
      b.add char(code)
      b.add char(part.len + 1)
      b.add char(step)
      b.add part
      i += 254
      inc step
      if v.len == 0: break
  else:
    let x = v[0 ..< min(v.len, 255)]
    b.add char(code)
    b.add char(x.len)
    b.add x

proc addDpb(b: var string, code: uint8, v: string) =
  if v.len > 255: fbFail("paramètre de connexion trop long (" & $code & ")")
  b.add char(code)
  b.add char(v.len)
  b.add v

proc addDpbInt(b: var string, code: uint8, v: int) =
  b.add char(code)
  b.add char(4)
  for k in 0 .. 3: b.add char((v shr (8 * k)) and 0xff)

proc le16(s: string, p: int): int = int(uint8(s[p])) or (int(uint8(s[p + 1])) shl 8)

proc authProof(c: FbConn, plugin, data: string): string =
  ## Données du serveur : sel (longueur sur 2 octets, petit-boutiste), puis clé
  ## publique B en hexadécimal (même codage de longueur). Renvoie la preuve M en
  ## hexadécimal et retient la clé de session.
  if data.len < 4: fbFail("authentification : réponse du serveur incomplète")
  let saltLen = le16(data, 0)
  if 2 + saltLen + 2 > data.len: fbFail("authentification : réponse du serveur invalide")
  let salt = toBytes(data[2 ..< 2 + saltLen])
  let keyLen = le16(data, 2 + saltLen)
  let keyHex = data[4 + saltLen ..< min(data.len, 4 + saltLen + keyLen)]
  let B = bigFromHex(keyHex)
  let (proof, key) = c.srp.clientProof(normalizeUser(c.user), c.password, salt, B,
                                       plugin == "Srp256")
  c.sessionKey = key
  hexOf(proof)

proc sendContAuth(c: FbConn, data, plugin: string) =
  c.wInt op_cont_auth
  c.wBuf data
  c.wBuf plugin
  c.wBuf c.pluginList
  c.wBuf ""

proc checkPlugin(plugin: string) =
  if plugin notin ["Srp256", "Srp"]:
    fbFail("greffon d'authentification \"" & plugin & "\" non pris en charge " &
           "(Srp256 ou Srp requis : AuthServer du serveur Firebird 3+)")

proc startCrypt(c: FbConn, wireCrypt: int) =
  ## Chiffrement Arc4 du flux, avec la clé de session SRP.
  let possible = c.sessionKey.len > 0 and "Arc4" in c.serverKeys
  if wireCrypt == 0 or c.crypted: return
  if not possible:
    if wireCrypt == 2: fbFail("chiffrement Arc4 indisponible sur ce serveur")
    return
  c.wInt op_crypt
  c.wBuf "Arc4"
  c.wBuf "Symmetric"
  c.flush()
  c.rin = initRc4(c.sessionKey)
  c.rout = initRc4(c.sessionKey)
  c.crypted = true
  discard c.response()

proc connectWire(c: FbConn, wireCrypt: int): tuple[authDone: bool, pendingProof: string] =
  var uid = ""
  uid.addCnct(CNCT_login, c.user)
  uid.addCnct(CNCT_plugin_name, c.authPlugin)
  uid.addCnct(CNCT_plugin_list, c.pluginList)
  uid.addCnct(CNCT_specific_data, c.srp.publicKeyHex)
  var cc = ""
  for k in 0 .. 3: cc.add char((wireCrypt shr (8 * k)) and 0xff)
  uid.addCnct(CNCT_client_crypt, cc)
  uid.addCnct(CNCT_user, getEnv("USER", getEnv("USERNAME", "lexis")))
  var hn = "localhost"
  try: hn = getHostname()
  except CatchableError: discard
  uid.addCnct(CNCT_host, hn)
  uid.addCnct(CNCT_user_verification, "")
  c.wInt op_connect
  c.wInt op_attach
  c.wInt CONNECT_VERSION3
  c.wInt arch_generic
  c.wBuf c.path
  const versions = [13, 14, 15, 16, 17]
  c.wInt versions.len
  c.wBuf uid
  for i, v in versions:
    c.wInt(FB_PROTOCOL_FLAG or int32(v))
    c.wInt arch_generic
    c.wInt ptype_rpc
    c.wInt ptype_batch_send
    c.wInt(2 * (i + 1))
  let op = c.readOp
  case op
  of op_reject:
    fbFail("connexion refusée par le serveur (Firebird 3.0 ou plus récent requis)", @[335544421])
  of op_response:
    discard c.readResponseBody()
    fbFail("connexion refusée par le serveur")
  of op_accept, op_accept_data, op_cond_accept:
    let version = c.readInt
    discard c.readInt                         # architecture
    discard c.readInt                         # type de protocole (et compression)
    c.protocol = int(version and FB_PROTOCOL_MASK)
    if (version and FB_PROTOCOL_FLAG) == 0 or c.protocol < 13:
      fbFail("protocole " & $c.protocol & " non pris en charge (Firebird 3.0 ou plus récent requis)")
    if op == op_accept: return (false, "")
    var data = c.readBuf
    var plugin = c.readBuf
    let complete = c.readInt != 0
    c.serverKeys.add c.readBuf
    if complete: return (true, "")
    if plugin.len == 0: return (false, "")
    checkPlugin(plugin)
    c.authPlugin = plugin
    if data.len == 0:
      # le serveur a choisi un autre greffon : il redemande la clé publique
      c.sendContAuth(c.srp.publicKeyHex, plugin)
      let op2 = c.readOp
      if op2 == op_response:
        discard c.readResponseBody()
        fbFail("authentification refusée")
      if op2 != op_cont_auth: fbFail("authentification : réponse inattendue (" & $op2 & ")")
      data = c.readBuf
      plugin = c.readBuf
      discard c.readBuf                         # liste des greffons
      c.serverKeys.add c.readBuf
      checkPlugin(plugin)
      c.authPlugin = plugin
    let proof = c.authProof(plugin, data)
    if op == op_cond_accept:
      c.sendContAuth(proof, plugin)
      let r = c.response()
      c.serverKeys.add r.data
      c.startCrypt(wireCrypt)
      return (true, "")
    return (false, proof)
  else:
    fbFail("réponse inattendue du serveur à la connexion (opération " & $op & ")")

proc fbConnect*(base, user, password: string, role = "", charset = "UTF8",
                create = false, pageSize = 8192, wireCrypt = 1): FbConn =
  ## Connexion (create = vrai : création de la base). wireCrypt : 0 désactivé,
  ## 1 si le serveur le propose, 2 exigé.
  let (host, port, path) = parseTarget(base)
  if path.len == 0: fbFail("chemin ou alias de la base attendu")
  let c = FbConn(host: host, path: path, user: user, password: password,
                 authPlugin: "Srp256", pluginList: "Srp256,Srp")
  c.srp = newSrpClient()
  try:
    c.sock = dial(host, Port(port), buffered = false)
  except OSError, IOError, ValueError:
    fbFail("impossible de joindre le serveur Firebird " & host & ":" & $port & " (" &
           getCurrentExceptionMsg() & ")", @[335544721])
  try:
    try: c.sock.setSockOpt(OptNoDelay, true, level = IPPROTO_TCP.cint)
    except CatchableError: discard
    let (authDone, proof) = c.connectWire(wireCrypt)
    # bloc de paramètres
    var dpb = $char(isc_dpb_version1)
    dpb.addDpb(isc_dpb_utf8_filename, "")
    dpb.addDpb(isc_dpb_lc_ctype, charset)
    if user.len > 0: dpb.addDpb(isc_dpb_user_name, user)
    if role.len > 0: dpb.addDpb(isc_dpb_sql_role_name, role)
    dpb.addDpbInt(isc_dpb_process_id, getCurrentProcessId())
    dpb.addDpb(isc_dpb_process_name, "wdlexis")
    if create:
      dpb.addDpbInt(isc_dpb_page_size, pageSize)
      dpb.addDpb(isc_dpb_set_db_charset, charset)
      dpb.addDpbInt(isc_dpb_sql_dialect, 3)
    if not authDone:
      dpb.addDpb(isc_dpb_auth_plugin_name, c.authPlugin)
      dpb.addDpb(isc_dpb_auth_plugin_list, c.pluginList)
      if proof.len > 0: dpb.addDpb(isc_dpb_specific_auth_data, proof)
    c.wInt(if create: op_create else: op_attach)
    c.wInt 0
    c.wBuf path
    c.wBuf dpb
    while true:
      let op = c.readOp
      case op
      of op_response:
        let r = c.readResponseBody()
        c.db = r.obj
        break
      of op_cont_auth:
        let data = c.readBuf
        var plugin = c.readBuf
        discard c.readBuf
        c.serverKeys.add c.readBuf
        if plugin.len == 0: plugin = c.authPlugin
        checkPlugin(plugin)
        c.authPlugin = plugin
        if data.len == 0: c.sendContAuth(c.srp.publicKeyHex, plugin)
        else: c.sendContAuth(c.authProof(plugin, data), plugin)
      of op_crypt_key_callback:
        fbFail("base chiffrée : rappel de clé non pris en charge")
      else:
        fbFail("réponse inattendue du serveur à l'attache (opération " & $op & ")")
    if not c.crypted and wireCrypt == 2: c.startCrypt(wireCrypt)
  except CatchableError as e:
    try: c.sock.close()
    except CatchableError: discard
    c.closed = true
    raise e
  c

proc close*(c: FbConn) =
  ## Détache la base et ferme la connexion (sans erreur si elle est déjà rompue).
  if c.closed: return
  c.closed = true
  try:
    c.wInt op_detach
    c.wInt c.db
    discard c.response()
    c.wInt op_disconnect
    c.flush()
  except CatchableError: discard
  try: c.sock.close()
  except CatchableError: discard

proc ensureOpen(c: FbConn) =
  if c.closed: fbFail("connexion fermée")

#
# Transactions
#

proc startTransaction*(c: FbConn, tpb: openArray[uint8]): int32 =
  c.ensureOpen
  var s = newString(tpb.len)
  for i, x in tpb: s[i] = char(x)
  c.wInt op_transaction
  c.wInt c.db
  c.wBuf s
  c.response().obj

proc commit*(c: FbConn, tr: int32) =
  c.ensureOpen
  c.wInt op_commit
  c.wInt tr
  discard c.response()

proc rollback*(c: FbConn, tr: int32) =
  c.ensureOpen
  c.wInt op_rollback
  c.wInt tr
  discard c.response()

#
# Blobs
#

proc readBlob*(c: FbConn, tr: int32, id: string): string =
  c.wInt op_open_blob2
  c.wBuf ""
  c.wInt tr
  c.wOpaque id
  let h = c.response().obj
  try:
    while true:
      c.wInt op_get_segment
      c.wInt h
      c.wInt SegmentMax
      c.wBuf ""
      let r = c.response()
      var p = 0
      while p + 2 <= r.data.len:
        let n = le16(r.data, p)
        result.add r.data[p + 2 ..< min(p + 2 + n, r.data.len)]
        p += 2 + n
      if r.obj == 2: break                    # fin du blob
  finally:
    c.wInt op_close_blob
    c.wInt h
    discard c.response()

proc writeBlob*(c: FbConn, tr: int32, data: string): string =
  ## Crée un blob ; renvoie son identifiant (8 octets).
  c.wInt op_create_blob2
  c.wBuf ""
  c.wInt tr
  c.wOpaque newString(8)
  let r = c.response()
  result = r.blobId
  var pos = 0
  while pos < data.len:
    let n = min(SegmentMax, data.len - pos)
    c.wInt op_put_segment
    c.wInt r.obj
    c.wInt n
    c.wBuf data[pos ..< pos + n]
    discard c.response()
    pos += n
  c.wInt op_close_blob
  c.wInt r.obj
  discard c.response()

#
# Description des instructions
#

const
  selectItems = [isc_info_sql_select, isc_info_sql_describe_vars, isc_info_sql_sqlda_seq,
                 isc_info_sql_type, isc_info_sql_sub_type, isc_info_sql_scale, isc_info_sql_length,
                 isc_info_sql_field, isc_info_sql_relation, isc_info_sql_owner, isc_info_sql_alias,
                 isc_info_sql_describe_end]
  bindItems = [isc_info_sql_bind, isc_info_sql_describe_vars, isc_info_sql_sqlda_seq,
               isc_info_sql_type, isc_info_sql_sub_type, isc_info_sql_scale, isc_info_sql_length,
               isc_info_sql_describe_end]

proc itemsStr(parts: varargs[seq[uint8]]): string =
  for p in parts:
    for x in p: result.add char(x)

proc infoInt(s: string, p, n: int): int =
  ## Entier petit-boutiste signé de n octets.
  var u = 0'u64
  for k in 0 ..< n: u = u or (uint64(uint8(s[p + k])) shl (8 * k))
  if n > 0 and n < 8 and (u and (1'u64 shl (8 * n - 1))) != 0: u = u or (not 0'u64 shl (8 * n))
  cast[int64](u).int

type DescState = object
  selDone, bindDone: bool
  selSeen, bindSeen: bool
  selLast, bindLast: int

proc parseDescribe(st: FbStmt, buf: string, ds: var DescState) =
  var p = 0
  var section = 0                              # 1 = sortie, 2 = paramètres
  var idx = 0
  template vars(): untyped = (if section == 1: st.outs else: st.ins)
  while p < buf.len:
    let item = uint8(buf[p])
    inc p
    case item
    of isc_info_end: break
    of isc_info_truncated: return
    of isc_info_sql_select:
      section = 1
      ds.selSeen = true
    of isc_info_sql_bind:
      section = 2
      ds.bindSeen = true
    of isc_info_sql_describe_end:
      if section == 1:
        ds.selLast = idx
        if idx >= st.outs.len: ds.selDone = true
      elif section == 2:
        ds.bindLast = idx
        if idx >= st.ins.len: ds.bindDone = true
    else:
      if p + 2 > buf.len: return
      let n = le16(buf, p)
      p += 2
      if p + n > buf.len: return
      let v = buf[p ..< p + n]
      case item
      of isc_info_sql_stmt_type: st.kind = infoInt(buf, p, n)
      of isc_info_sql_describe_vars:
        let count = infoInt(buf, p, n)
        if section == 1:
          if st.outs.len != count: st.outs.setLen(count)
          if count == 0: ds.selDone = true
        elif section == 2:
          if st.ins.len != count: st.ins.setLen(count)
          if count == 0: ds.bindDone = true
      of isc_info_sql_sqlda_seq: idx = infoInt(buf, p, n)
      else:
        if section in [1, 2] and idx >= 1 and idx <= vars().len:
          let k = idx - 1
          case item
          of isc_info_sql_type:
            let t = infoInt(buf, p, n)
            if section == 1:
              st.outs[k].sqltype = t and not 1
              st.outs[k].nullable = (t and 1) != 0
            else:
              st.ins[k].sqltype = t and not 1
              st.ins[k].nullable = (t and 1) != 0
          of isc_info_sql_sub_type:
            if section == 1: st.outs[k].subtype = infoInt(buf, p, n)
            else: st.ins[k].subtype = infoInt(buf, p, n)
          of isc_info_sql_scale:
            if section == 1: st.outs[k].scale = infoInt(buf, p, n)
            else: st.ins[k].scale = infoInt(buf, p, n)
          of isc_info_sql_length:
            if section == 1: st.outs[k].length = infoInt(buf, p, n)
            else: st.ins[k].length = infoInt(buf, p, n)
          of isc_info_sql_field: (if section == 1: st.outs[k].field = v)
          of isc_info_sql_relation: (if section == 1: st.outs[k].relation = v)
          of isc_info_sql_owner: (if section == 1: st.outs[k].owner = v)
          of isc_info_sql_alias: (if section == 1: st.outs[k].alias = v)
          else: discard
      p += n

proc infoSql(c: FbConn, st: FbStmt, items: string, size = InfoBufferLen): string =
  c.wInt op_info_sql
  c.wInt st.h
  c.wInt 0
  c.wBuf items
  c.wInt size
  c.response().data

proc startItem(i: int): seq[uint8] =
  @[isc_info_sql_sqlda_start, 2'u8, uint8(i and 0xff), uint8((i shr 8) and 0xff)]

#
# Messages (BLR + données XDR)
#

proc setWire(v: var FbVar) =
  ## Format de sortie demandé : les types que l'on ne décode pas directement
  ## (INT128, DECFLOAT, fuseaux horaires, tableaux) sont convertis en texte par
  ## le serveur, comme le faisait la version fbclient du paquet.
  v.wtype = v.sqltype
  v.wsub = v.subtype
  v.wlen = v.length
  v.wscale = v.scale
  case v.sqltype
  of SQL_INT128, SQL_DEC16, SQL_DEC34, SQL_TIME_TZ, SQL_TIMESTAMP_TZ, SQL_TIME_TZ_EX,
     SQL_TIMESTAMP_TZ_EX, SQL_ARRAY, SQL_NULL:
    v.wtype = SQL_VARYING
    v.wlen = 64
    v.wsub = 0
    v.wscale = 0
  of SQL_D_FLOAT: v.wtype = SQL_DOUBLE
  else: discard

proc blrType(b: var string, wtype, wsub, wlen, wscale: int) =
  template u16(x: int) =
    b.add char(x and 0xff)
    b.add char((x shr 8) and 0xff)
  case wtype
  of SQL_TEXT:
    b.add char(blr_text2); u16(wsub); u16(wlen)
  of SQL_VARYING:
    b.add char(blr_varying2); u16(wsub); u16(wlen)
  of SQL_SHORT: b.add char(blr_short); b.add char(wscale and 0xff)
  of SQL_LONG: b.add char(blr_long); b.add char(wscale and 0xff)
  of SQL_INT64: b.add char(blr_int64); b.add char(wscale and 0xff)
  of SQL_FLOAT: b.add char(blr_float)
  of SQL_DOUBLE: b.add char(blr_double)
  of SQL_TYPE_DATE: b.add char(blr_sql_date)
  of SQL_TYPE_TIME: b.add char(blr_sql_time)
  of SQL_TIMESTAMP: b.add char(blr_timestamp)
  of SQL_BOOLEAN: b.add char(blr_bool)
  of SQL_BLOB, SQL_QUAD: b.add char(blr_quad); b.add '\0'
  else: fbFail("type SQL " & $wtype & " non pris en charge")

proc buildMessageBlr(items: seq[tuple[t, sub, len, scale: int]]): string =
  if items.len == 0: return ""
  result = char(blr_version5) & char(blr_begin) & char(blr_message) & '\0'
  let n = items.len * 2
  result.add char(n and 0xff)
  result.add char((n shr 8) and 0xff)
  for it in items:
    result.blrType(it.t, it.sub, it.len, it.scale)
    result.add char(blr_short)
    result.add '\0'
  result.add char(blr_end)
  result.add char(blr_eoc)

proc outputBlr(st: FbStmt): string =
  var items: seq[tuple[t, sub, len, scale: int]]
  for v in st.outs: items.add (v.wtype, v.wsub, v.wlen, v.wscale)
  buildMessageBlr(items)

proc readFloat32(c: FbConn): float =
  let u = cast[uint32](c.readInt)
  float(cast[float32](u))

proc readRow(c: FbConn, st: FbStmt): seq[FbVal] =
  let n = st.outs.len
  let nb = (n + 7) div 8
  let bitmap = c.readOpaque(nb)
  for k in 0 ..< n:
    if (uint8(bitmap[k div 8]) and (1'u8 shl (k mod 8))) != 0:
      result.add newVal(fvNull)
      continue
    let v = st.outs[k]
    var x: FbVal
    case v.wtype
    of SQL_TEXT:
      x = FbVal(kind: fvText, s: c.readOpaque(v.wlen), sub: v.wsub)
    of SQL_VARYING: x = FbVal(kind: fvText, s: c.readBuf, sub: v.wsub)
    of SQL_SHORT, SQL_LONG: x = FbVal(kind: fvInt, i: int64(c.readInt), scale: v.wscale)
    of SQL_INT64: x = FbVal(kind: fvInt, i: c.readInt64, scale: v.wscale)
    of SQL_FLOAT: x = FbVal(kind: fvFloat, f: c.readFloat32)
    of SQL_DOUBLE: x = FbVal(kind: fvFloat, f: cast[float64](c.readInt64))
    of SQL_TYPE_DATE: x = FbVal(kind: fvDate, i: int64(c.readInt))
    of SQL_TYPE_TIME: x = FbVal(kind: fvTime, i: int64(cast[uint32](c.readInt)))
    of SQL_TIMESTAMP:
      let d = c.readInt
      x = FbVal(kind: fvStamp, days: d, i: int64(cast[uint32](c.readInt)))
    of SQL_BOOLEAN: x = FbVal(kind: fvBool, b: c.readOpaque(1)[0] != '\0')
    of SQL_BLOB, SQL_QUAD: x = FbVal(kind: fvBlob, s: c.readOpaque(8))
    else: fbFail("type SQL " & $v.wtype & " non pris en charge")
    result.add x

proc paramFormat(p: FbVal): tuple[t, sub, len, scale: int] =
  case p.kind
  of fvNull: (SQL_TEXT, 0, 1, 0)
  of fvInt: (SQL_INT64, 0, 8, p.scale)
  of fvFloat: (SQL_DOUBLE, 0, 8, 0)
  of fvText: (SQL_TEXT, p.sub, p.s.len, 0)
  of fvBool: (SQL_BOOLEAN, 0, 1, 0)
  of fvDate: (SQL_TYPE_DATE, 0, 4, 0)
  of fvTime: (SQL_TYPE_TIME, 0, 4, 0)
  of fvStamp: (SQL_TIMESTAMP, 0, 8, 0)
  of fvBlob: (SQL_BLOB, 0, 8, 0)

proc writeParams(c: FbConn, params: seq[FbVal]) =
  let nb = (params.len + 7) div 8
  var bitmap = newString(nb)
  for k, p in params:
    if p.kind == fvNull: bitmap[k div 8] = char(uint8(bitmap[k div 8]) or (1'u8 shl (k mod 8)))
  c.wOpaque bitmap
  for p in params:
    case p.kind
    of fvNull: discard
    of fvInt:
      c.wInt int32(cast[uint64](p.i) shr 32)
      c.wInt cast[int32](cast[uint64](p.i) and 0xffffffff'u64)
    of fvFloat:
      let u = cast[uint64](p.f)
      c.wInt cast[int32](u shr 32)
      c.wInt cast[int32](u and 0xffffffff'u64)
    of fvText: c.wOpaque p.s
    of fvBool: c.wOpaque(if p.b: "\1" else: "\0")
    of fvDate: c.wInt int32(p.i)
    of fvTime: c.wInt cast[int32](uint32(p.i))
    of fvStamp:
      c.wInt p.days
      c.wInt cast[int32](uint32(p.i))
    of fvBlob: c.wOpaque p.s

#
# Instructions
#

proc isSelect*(st: FbStmt): bool = st.kind in [StmtSelect, StmtSelectForUpdate]

proc prepare*(c: FbConn, tr: int32, sql: string): FbStmt =
  c.ensureOpen
  if sql.len > 10_000_000: fbFail("requête trop longue")
  let st = FbStmt()
  c.wInt op_allocate_statement
  c.wInt c.db
  st.h = c.response().obj
  try:
    c.wInt op_prepare_statement
    c.wInt tr
    c.wInt st.h
    c.wInt SQL_DIALECT_V6
    c.wBuf sql
    c.wBuf itemsStr(@[isc_info_sql_stmt_type], @selectItems, @bindItems)
    c.wInt InfoBufferLen
    var ds: DescState
    st.parseDescribe(c.response().data, ds)
    # réponse tronquée (nombreuses colonnes) : suite demandée par morceaux
    var guard = 0
    while not ds.selDone and guard < 10_000:
      inc guard
      let items = if ds.selSeen and st.outs.len > 0: itemsStr(startItem(ds.selLast + 1), @selectItems)
                  else: itemsStr(@selectItems)
      let before = ds.selLast
      st.parseDescribe(c.infoSql(st, items), ds)
      if not ds.selDone and ds.selLast == before and ds.selSeen and st.outs.len > 0:
        fbFail("description des colonnes incomplète")
    guard = 0
    while not ds.bindDone and guard < 10_000:
      inc guard
      let items = if ds.bindSeen and st.ins.len > 0: itemsStr(startItem(ds.bindLast + 1), @bindItems)
                  else: itemsStr(@bindItems)
      let before = ds.bindLast
      st.parseDescribe(c.infoSql(st, items), ds)
      if not ds.bindDone and ds.bindLast == before and ds.bindSeen and st.ins.len > 0:
        fbFail("description des paramètres incomplète")
    for v in st.outs.mitems: v.setWire
    st.outBlr = st.outputBlr
  except CatchableError as e:
    try:
      c.wInt op_free_statement
      c.wInt st.h
      c.wInt DSQL_drop
      discard c.response()
    except CatchableError: discard
    raise e
  st

proc free*(c: FbConn, st: FbStmt) =
  if st.isNil or st.h == 0 or c.closed: return
  let h = st.h
  st.h = 0
  c.wInt op_free_statement
  c.wInt h
  c.wInt DSQL_drop
  discard c.response()

proc execute*(c: FbConn, tr: int32, st: FbStmt, params: seq[FbVal]): seq[seq[FbVal]] =
  ## Exécute l'instruction ; renvoie la ligne unique d'un EXECUTE PROCEDURE ou
  ## d'un INSERT ... RETURNING. Pour un SELECT, les lignes se lisent par fetch().
  c.ensureOpen
  var fmt: seq[tuple[t, sub, len, scale: int]]
  for p in params: fmt.add p.paramFormat
  let singleton = not st.isSelect and st.outs.len > 0
  c.wInt(if singleton: op_execute2 else: op_execute)
  c.wInt st.h
  c.wInt tr
  c.wBuf buildMessageBlr(fmt)
  c.wInt 0
  c.wInt(if params.len > 0: 1 else: 0)
  if params.len > 0: c.writeParams(params)
  if singleton:
    c.wBuf st.outBlr
    c.wInt 0
  if c.protocol >= PROTOCOL_STMT_TOUT: c.wInt 0      # délai : celui de la connexion
  if singleton:
    let op = c.readOp
    if op == op_sql_response:
      let count = c.readInt
      if count > 0: result.add c.readRow(st)
      discard c.response()
    elif op == op_response:
      discard c.readResponseBody()
    else: fbFail("réponse inattendue du serveur (opération " & $op & ")")
  else:
    discard c.response()
  if st.isSelect:
    st.open = true
    st.eof = false
    st.rows.setLen(0)
    st.rowPos = 0

proc fetch*(c: FbConn, st: FbStmt, row: var seq[FbVal]): bool =
  ## Ligne suivante d'un SELECT (faux à la fin). Lecture par lots de 200 lignes.
  if st.rowPos < st.rows.len:
    row = st.rows[st.rowPos]
    inc st.rowPos
    return true
  if st.eof or not st.open: return false
  st.rows.setLen(0)
  st.rowPos = 0
  c.wInt op_fetch
  c.wInt st.h
  c.wBuf st.outBlr
  c.wInt 0
  c.wInt FetchSize
  while true:
    let op = c.readOp
    if op == op_fetch_response:
      let status = c.readInt
      let count = c.readInt
      if count > 0:
        st.rows.add c.readRow(st)
      else:
        if status == 100: st.eof = true
        break
    elif op == op_response:
      discard c.readResponseBody()
      st.eof = true
      break
    else:
      fbFail("réponse inattendue du serveur (opération " & $op & ")")
  if st.rows.len == 0:
    st.eof = true
    return false
  row = st.rows[0]
  st.rowPos = 1
  true

proc affectedRows*(c: FbConn, st: FbStmt): int =
  let buf = c.infoSql(st, $char(isc_info_sql_records) & $char(isc_info_end), 128)
  if buf.len < 3 or uint8(buf[0]) != isc_info_sql_records: return 0
  var p = 3
  while p + 3 <= buf.len:
    let code = uint8(buf[p])
    if code == isc_info_end or code == isc_info_truncated: break
    let n = le16(buf, p + 1)
    if p + 3 + n > buf.len: break
    if code in [isc_info_req_insert_count, isc_info_req_update_count, isc_info_req_delete_count]:
      result += infoInt(buf, p + 3, n)
    p += 3 + n
