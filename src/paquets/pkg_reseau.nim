# Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr
#   wdlexis+ - paquets réseau
#
#   reseau   sockets TCP (avec TLS) et UDP, résolution DNS
#   http     client HTTP/HTTPS (std/httpclient ; HTTPS demande -d:ssl et OpenSSL)
#   ftp      client FTP (mode passif) écrit sur les sockets de « reseau »
#   ssh      exécution distante, et sftp : transferts de fichiers, via le client
#            OpenSSH installé (ssh, scp, sftp), authentification par clef ;
#            mot de passe possible si « sshpass » est installé.
#
# Les opérations bloquantes libèrent l'interpréteur : les fenêtres et les
# gestionnaires d'événements restent réactifs pendant un transfert.
# Un échec lève une erreur Lexis+ (à intercepter avec essayer ... capturer).

import std/[net, httpclient, strutils, os, osproc, tables, uri, nativesockets, streams, strtabs]
import ../lexis/api

#
# reseau
#

type
  LSocket* = ref object of LUser
    sock*: Socket
    closed*: bool
    timeout*: int          # ms, -1 = aucun
    udp*: bool

var sockMethods {.threadvar.}: LTable

proc checkSock(L: Interp, a: seq[Value], fname: string): LSocket =
  result = checkUser[LSocket](L, a, 1, fname, "socket")
  if result.closed: rtError("socket fermé")

proc wrapSock(L: Interp, s: LSocket): Value =
  L.closers.add proc () =
    if not s.closed:
      s.closed = true
      try: s.sock.close() except CatchableError: discard
  L.wrap(s, "socket", sockMethods)

when defined(ssl):
  var sslCtx {.threadvar.}: SslContext
  proc tlsContext(): SslContext =
    if sslCtx.isNil: sslCtx = newContext(verifyMode = CVerifyPeer)
    sslCtx

proc tcpConnect*(L: Interp, host: string, port: int, tls: bool, timeout: int): Socket =
  result = newSocket()
  try:
    L.blocking:
      if timeout > 0: result.connect(host, Port(port), timeout)
      else: result.connect(host, Port(port))
    if tls:
      when defined(ssl):
        tlsContext().wrapConnectedSocket(result, handshakeAsClient, host)
      else:
        rtError("TLS indisponible : compilez avec -d:ssl")
  except OSError, TimeoutError:
    result.close()
    raise

proc recvLine(L: Interp, s: LSocket): (bool, string) =
  var line = ""
  L.blocking:
    if s.timeout > 0: s.sock.readLine(line, s.timeout)
    else: s.sock.readLine(line)
  if line.len == 0: return (false, "")       # connexion fermée
  if line == "\r\n": return (true, "")
  (true, line)

proc openReseau(L: Interp): Value =
  sockMethods = newLib()
  let sm = sockMethods
  sm.fn "envoyer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSock(a, "envoyer")
    let data = L.checkStr(a, 2, "envoyer")
    try:
      L.blocking: s.sock.send(data)
      @[intV(data.len)]
    except OSError as e: fail(e.msg)
  sm.fn "recevoir", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSock(a, "recevoir")
    let what = arg(a, 2)
    try:
      if what.kind in {vkInt, vkNum}:
        var ok: bool
        let n = int(toInteger(what, ok))
        var data = ""
        L.blocking:
          discard s.sock.recv(data, n, (if s.timeout > 0: s.timeout else: -1))
        if data.len == 0: return @[nilV]
        return @[strV(data)]
      let mode = if what.kind == vkStr: what.s.strip(chars = {'*'}) else: "l"
      if mode in ["t", "a", "tout"]:
        var all = ""
        L.blocking:
          while true:
            let chunk = s.sock.recv(4096, (if s.timeout > 0: s.timeout else: -1))
            if chunk.len == 0: break
            all.add chunk
        return @[strV(all)]
      let (ok, line) = L.recvLine(s)
      if not ok: return @[nilV]
      @[strV(line)]
    except TimeoutError: fail("délai dépassé")
    except OSError as e: fail(e.msg)
  sm.fn "delai", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSock(a, "delai")
    let v = arg(a, 2)
    s.timeout = if v.kind == vkNil: -1 else: int(L.checkNum(a, 2, "delai") * 1000)
  sm.fn "accepter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSock(a, "accepter")
    var client: Socket
    new(client)
    var address = ""
    try:
      L.blocking: s.sock.acceptAddr(client, address)
    except OSError as e: return fail(e.msg)
    @[L.wrapSock(LSocket(sock: client, timeout: -1))]
  sm.fn "envoyervers", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSock(a, "envoyervers")
    try:
      s.sock.sendTo(L.checkStr(a, 4, "envoyervers"), Port(L.checkInt(a, 3, "envoyervers")), L.checkStr(a, 2, "envoyervers"))
      @[boolV(true)]
    except OSError as e: fail(e.msg)
  sm.fn "recevoirde", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSock(a, "recevoirde")
    let size = int(L.optInt(a, 2, "recevoirde", 8192))
    var data = ""
    var address = ""
    var port: Port
    try:
      L.blocking: discard s.sock.recvFrom(data, size, address, port)
    except OSError as e: return fail(e.msg)
    @[record({"donnees": strV(data), "adresse": strV(address), "port": intV(int(port))})]
  sm.fn "distant", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSock(a, "distant")
    try:
      let (address, port) = s.sock.getPeerAddr()
      @[record({"adresse": strV(address), "port": intV(int(port))})]
    except OSError as e: fail(e.msg)
  sm.fn "fermer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = checkUser[LSocket](L, a, 1, "fermer", "socket")
    if not s.closed:
      s.closed = true
      s.sock.close()
    @[boolV(true)]

  let m = newLib()
  m.fn "connecter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let host = L.checkStr(a, 1, "connecter")
    let port = int(L.checkInt(a, 2, "connecter"))
    let opts = if arg(a, 3).kind == vkTable: a[2].t else: nil
    try:
      let sock = L.tcpConnect(host, port, optField(opts, "tls", false),
                              int(optField(opts, "delai", 0.0) * 1000))
      @[L.wrapSock(LSocket(sock: sock, timeout: int(optField(opts, "delai", -0.001) * 1000)))]
    except OSError, TimeoutError: fail(host & ":" & $port & " : " & getCurrentExceptionMsg())
  m.fn "ecouter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let port = int(L.checkInt(a, 1, "ecouter"))
    let host = L.optStr(a, 2, "ecouter", "0.0.0.0")
    try:
      let s = newSocket()
      s.setSockOpt(OptReuseAddr, true)
      s.bindAddr(Port(port), host)
      s.listen()
      @[L.wrapSock(LSocket(sock: s, timeout: -1))]
    except OSError as e: fail(e.msg)
  m.fn "udp", proc (L: Interp, a: seq[Value]): seq[Value] =
    try:
      let s = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
      if arg(a, 1).kind != vkNil:
        s.bindAddr(Port(L.checkInt(a, 1, "udp")), L.optStr(a, 2, "udp", "0.0.0.0"))
      @[L.wrapSock(LSocket(sock: s, timeout: -1, udp: true))]
    except OSError as e: fail(e.msg)
  m.fn "resoudre", proc (L: Interp, a: seq[Value]): seq[Value] =
    let host = L.checkStr(a, 1, "resoudre")
    try:
      var ip = ""
      L.blocking: ip = getHostByName(host).addrList[0]
      @[strV(ip)]
    except OSError, IndexDefect: fail(host & " : nom introuvable")
  m.fn "nomhote", proc (L: Interp, a: seq[Value]): seq[Value] = @[strV(getHostname())]
  tableV(m)

registerPackage PackageDef(name: "reseau", open: openReseau,
  description: "Sockets TCP/UDP",
  docs: docs("reseau", [
    "reseau.connecter(hote, port, [options])", "Connexion TCP. options : tls (vrai pour TLS, -d:ssl), delai (secondes).",
    "reseau.ecouter(port, [hote])", "Socket serveur TCP.",
    "reseau.udp([port], [hote])", "Socket UDP, éventuellement lié à un port.",
    "reseau.resoudre(hote)", "Adresse IP d'un nom.",
    "reseau.nomhote()", "Nom de la machine.",
    "s:envoyer(donnees)", "Envoie des octets ; renvoie le nombre envoyé.",
    "s:recevoir([mode])", "Reçoit : \"l\" une ligne (défaut), \"t\" tout jusqu'à la fermeture, ou un nombre d'octets ; nul si la connexion est fermée.",
    "s:delai(secondes)", "Délai maximal des réceptions (nul = aucun).",
    "s:accepter()", "Attend un client (socket serveur) ; renvoie son socket.",
    "s:envoyervers(donnees, port, hote)", "Envoi UDP.",
    "s:recevoirde([taille])", "Réception UDP : {donnees, adresse, port}.",
    "s:distant()", "{adresse, port} de l'autre extrémité.",
    "s:fermer()", "Ferme le socket."]))

#
# http
#

proc httpRequest(L: Interp, meth, url, body: string, headers: LTable, timeout: int,
                 saveTo = ""): LTable =
  var client: HttpClient
  try:
    when defined(ssl):
      client = newHttpClient(timeout = timeout, sslContext = newContext(verifyMode = CVerifyPeer))
    else:
      if url.toLowerAscii.startsWith("https"):
        rtError("HTTPS indisponible : compilez avec -d:ssl")
      client = newHttpClient(timeout = timeout)
    var hdrs = newHttpHeaders()
    if not headers.isNil:
      for k, v in headers.pairs:
        if k.kind == vkStr: hdrs[k.s] = L.tostr(v)
    client.headers = hdrs
    var resp: Response
    L.blocking:
      resp = client.request(url, httpMethod = meth.toUpperAscii, body = body)
    let respBody = resp.body
    if saveTo.len > 0: writeFile(saveTo, respBody)
    result = newLTable()
    result.set "statut", intV(resp.code.int)
    result.set "raison", strV(resp.status)
    result.set "corps", strV(if saveTo.len > 0: "" else: respBody)
    let h = newLTable()
    for k, v in resp.headers.pairs: h.rawSet(strV(k.toLowerAscii), strV(v))
    result.set "entetes", tableV(h)
  except LexisError, LexisStop:
    raise
  except CatchableError as e:
    rtError(url & " : " & e.msg)
  finally:
    if not client.isNil: client.close()

proc openHttp(L: Interp): Value =
  let m = newLib()
  m.fn "lire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let r = L.httpRequest("GET", L.checkStr(a, 1, "lire"), "",
                          (if arg(a, 2).kind == vkTable: a[1].t else: nil), -1)
    @[r.get("corps")]
  m.fn "envoyer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let r = L.httpRequest("POST", L.checkStr(a, 1, "envoyer"), L.optStr(a, 2, "envoyer", ""),
                          (if arg(a, 3).kind == vkTable: a[2].t else: nil), -1)
    @[r.get("corps")]
  m.fn "requete", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = L.checkTable(a, 1, "requete")
    let hv = o.field("entetes")
    @[tableV(L.httpRequest(optField(o, "methode", "GET"), optField(o, "url", ""), optField(o, "corps", ""),
                           (if hv.kind == vkTable: hv.t else: nil), int(optField(o, "delai", -0.001) * 1000)))]
  m.fn "telecharger", proc (L: Interp, a: seq[Value]): seq[Value] =
    let r = L.httpRequest("GET", L.checkStr(a, 1, "telecharger"), "", nil, -1, L.checkStr(a, 2, "telecharger"))
    @[r.get("statut")]
  m.fn "encoder", proc (L: Interp, a: seq[Value]): seq[Value] =
    let v = arg(a, 1)
    if v.kind == vkTable:
      var parts: seq[string]
      for k, x in v.t.pairs: parts.add encodeUrl(rawToString(k).toLowerAscii) & "=" & encodeUrl(L.tostr(x))
      return @[strV(parts.join("&"))]
    @[strV(encodeUrl(L.checkStr(a, 1, "encoder")))]
  m.fn "decoder", proc (L: Interp, a: seq[Value]): seq[Value] = @[strV(decodeUrl(L.checkStr(a, 1, "decoder")))]
  tableV(m)

registerPackage PackageDef(name: "http", open: openHttp,
  description: "Client HTTP/HTTPS",
  docs: docs("http", [
    "http.lire(url, [entetes])", "Requête GET ; renvoie le corps de la réponse.",
    "http.envoyer(url, corps, [entetes])", "Requête POST ; renvoie le corps de la réponse.",
    "http.requete{methode=, url=, entetes=, corps=, delai=}", "Requête quelconque ; renvoie {statut, raison, corps, entetes} (en-têtes en minuscules : r.entetes[\"content-type\"]).",
    "http.telecharger(url, chemin)", "Télécharge dans un fichier ; renvoie le statut.",
    "http.encoder(texte | table)", "Encodage d'URL (une table devient a=1&b=2).",
    "http.decoder(texte)", "Décodage d'URL."]))

#
# ftp (RFC 959, mode passif)
#

type
  FtpConn* = ref object of LUser
    ctrl: Socket
    closed: bool
    host: string

var ftpMethods {.threadvar.}: LTable

proc ftpReply(L: Interp, c: FtpConn): (int, string) =
  var all = ""
  var line = ""
  L.blocking:
    c.ctrl.readLine(line, 30_000)
    all = line
    if line.len >= 4 and line[3] == '-':
      let code = line[0 .. 2]
      while true:
        c.ctrl.readLine(line, 30_000)
        all.add "\n" & line
        if line.len >= 4 and line.startsWith(code) and line[3] == ' ': break
        if line.len == 0: break
  if all.len < 3: rtError("ftp : réponse invalide du serveur")
  var code = 0
  try: code = parseInt(all[0 .. 2])
  except ValueError: rtError("ftp : réponse invalide « " & all & " »")
  (code, all)

proc ftpCmd(L: Interp, c: FtpConn, cmd: string, expect: set[char] = {'2'}): (int, string) =
  L.blocking: c.ctrl.send(cmd & "\r\n")
  result = L.ftpReply(c)
  if result[1][0] notin expect:
    let shown = if cmd.startsWith("PASS"): "PASS ****" else: cmd
    rtError("ftp : " & shown & " → " & result[1])

proc ftpData(L: Interp, c: FtpConn): Socket =
  let (_, msg) = L.ftpCmd(c, "PASV")
  let a = msg.find('(')
  let b = msg.find(')', a + 1)
  if a < 0 or b < 0: rtError("ftp : réponse PASV invalide")
  let parts = msg[a + 1 ..< b].split(',')
  if parts.len != 6: rtError("ftp : réponse PASV invalide")
  let port = parseInt(parts[4].strip()) * 256 + parseInt(parts[5].strip())
  L.tcpConnect(c.host, port, false, 30_000)

proc ftpTransfer(L: Interp, c: FtpConn, cmd: string, upload = "", isUpload = false): string =
  discard L.ftpCmd(c, "TYPE I")
  let data = L.ftpData(c)
  discard L.ftpCmd(c, cmd, {'1', '2'})
  try:
    L.blocking:
      if isUpload:
        data.send(upload)
      else:
        while true:
          let chunk = data.recv(65536, 60_000)
          if chunk.len == 0: break
          result.add chunk
  finally:
    data.close()
  discard L.ftpReply(c)

proc checkFtp(L: Interp, a: seq[Value], fname: string): FtpConn =
  result = checkUser[FtpConn](L, a, 1, fname, "connexion ftp")
  if result.closed: rtError("connexion ftp fermée")

proc openFtp(L: Interp): Value =
  ftpMethods = newLib()
  let fm = ftpMethods
  fm.fn "liste", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkFtp(a, "liste")
    let path = L.optStr(a, 2, "liste", "")
    let txt = L.ftpTransfer(c, (if optBool(a, 3, false): "LIST " else: "NLST ") & path)
    let t = newLTable()
    for l in txt.splitLines():
      if l.strip().len > 0: t.arr.add strV(l)
    @[tableV(t)]
  fm.fn "lire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkFtp(a, "lire")
    let data = L.ftpTransfer(c, "RETR " & L.checkStr(a, 2, "lire"))
    if arg(a, 3).kind != vkNil:
      writeFile(L.checkStr(a, 3, "lire"), data)
      return @[boolV(true)]
    @[strV(data)]
  fm.fn "envoyer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkFtp(a, "envoyer")
    let src = L.checkStr(a, 2, "envoyer")
    let remote = L.optStr(a, 3, "envoyer", extractFilename(src))
    let content = if fileExists(src) and not optBool(a, 4, false): readFile(src) else: src
    discard L.ftpTransfer(c, "STOR " & remote, content, true)
    @[boolV(true)]
  fm.fn "dossier", proc (L: Interp, a: seq[Value]): seq[Value] =
    discard L.ftpCmd(L.checkFtp(a, "dossier"), "CWD " & L.checkStr(a, 2, "dossier"))
    @[boolV(true)]
  fm.fn "courant", proc (L: Interp, a: seq[Value]): seq[Value] =
    let (_, msg) = L.ftpCmd(L.checkFtp(a, "courant"), "PWD")
    let q1 = msg.find('"')
    let q2 = msg.find('"', q1 + 1)
    @[strV(if q1 >= 0 and q2 > q1: msg[q1 + 1 ..< q2] else: msg)]
  fm.fn "creerdossier", proc (L: Interp, a: seq[Value]): seq[Value] =
    discard L.ftpCmd(L.checkFtp(a, "creerdossier"), "MKD " & L.checkStr(a, 2, "creerdossier"))
    @[boolV(true)]
  fm.fn "supprimer", proc (L: Interp, a: seq[Value]): seq[Value] =
    discard L.ftpCmd(L.checkFtp(a, "supprimer"), "DELE " & L.checkStr(a, 2, "supprimer"))
    @[boolV(true)]
  fm.fn "supprimerdossier", proc (L: Interp, a: seq[Value]): seq[Value] =
    discard L.ftpCmd(L.checkFtp(a, "supprimerdossier"), "RMD " & L.checkStr(a, 2, "supprimerdossier"))
    @[boolV(true)]
  fm.fn "renommer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkFtp(a, "renommer")
    discard L.ftpCmd(c, "RNFR " & L.checkStr(a, 2, "renommer"), {'3'})
    discard L.ftpCmd(c, "RNTO " & L.checkStr(a, 3, "renommer"))
    @[boolV(true)]
  fm.fn "fermer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = checkUser[FtpConn](L, a, 1, "fermer", "connexion ftp")
    if not c.closed:
      try: discard L.ftpCmd(c, "QUIT")
      except LexisError: discard
      c.ctrl.close()
      c.closed = true
    @[boolV(true)]

  let m = newLib()
  m.fn "connecter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = L.checkTable(a, 1, "connecter")
    let host = optField(o, "hote", "")
    let port = optField(o, "port", 21)
    var c: FtpConn
    try:
      c = FtpConn(ctrl: L.tcpConnect(host, port, false, 30_000), host: host)
    except OSError, TimeoutError: return fail(host & " : " & getCurrentExceptionMsg())
    discard L.ftpReply(c)
    let (code, _) = L.ftpCmd(c, "USER " & optField(o, "utilisateur", "anonymous"), {'2', '3'})
    if code == 331: discard L.ftpCmd(c, "PASS " & optField(o, "motdepasse", ""))
    L.closers.add proc () =
      if not c.closed:
        c.closed = true
        try: c.ctrl.close() except CatchableError: discard
    @[L.wrap(c, "ftp", ftpMethods)]
  tableV(m)

registerPackage PackageDef(name: "ftp", open: openFtp,
  description: "Client FTP",
  docs: docs("ftp", [
    "ftp.connecter{hote=, port=21, utilisateur=\"anonymous\", motdepasse=\"\"}", "Ouvre une session FTP (mode passif).",
    "c:liste([chemin], [detail])", "Noms des fichiers (detail = vrai : format détaillé).",
    "c:lire(distant, [local])", "Télécharge : renvoie les données, ou les écrit dans le fichier local.",
    "c:envoyer(local_ou_donnees, [distant], [sontdesdonnees])", "Envoie un fichier local (ou des données).",
    "c:dossier(chemin)", "Change de dossier distant.", "c:courant()", "Dossier distant courant.",
    "c:creerdossier(chemin)", "Crée un dossier.", "c:supprimerdossier(chemin)", "Supprime un dossier.",
    "c:supprimer(chemin)", "Supprime un fichier.", "c:renommer(ancien, nouveau)", "Renomme.",
    "c:fermer()", "Ferme la session."]))

#
# ssh / sftp (client OpenSSH)
#

type
  SshSession* = ref object of LUser
    host, user, key, password: string
    port: int
    extra: seq[string]

var sshMethods {.threadvar.}: LTable

proc target(s: SshSession): string =
  if s.user.len > 0: s.user & "@" & s.host else: s.host

proc baseOpts(s: SshSession, portFlag: string): seq[string] =
  result = @["-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=20"]
  if s.password.len == 0: result.add ["-o", "BatchMode=yes"]
  if s.port > 0: result.add [portFlag, $s.port]
  if s.key.len > 0: result.add ["-i", s.key]
  result.add s.extra

proc runTool(L: Interp, s: SshSession, tool: string, args: seq[string], input = ""): (string, int) =
  var exe = findExe(tool)
  if exe.len == 0: rtError(tool & " introuvable : installez le client OpenSSH")
  var fullArgs = args
  var env: StringTableRef = nil
  if s.password.len > 0:
    let sp = findExe("sshpass")
    if sp.len == 0: rtError("authentification par mot de passe : installez « sshpass », ou utilisez une clef (clef=)")
    fullArgs = @["-e", exe] & args
    exe = sp
    env = newStringTable()
    for k, v in envPairs(): env[k] = v
    env["SSHPASS"] = s.password
  var output = ""
  var code = 0
  L.blocking:
    let p = startProcess(exe, args = fullArgs, env = env, options = {poStdErrToStdOut})
    if input.len > 0:
      p.inputStream.write(input)
    p.inputStream.close()
    output = p.outputStream.readAll()
    code = p.waitForExit()
    p.close()
  (output, code)

proc checkSsh(L: Interp, a: seq[Value], fname: string): SshSession =
  checkUser[SshSession](L, a, 1, fname, "session ssh")

proc sshFromOpts(o: LTable): SshSession =
  result = SshSession(host: optField(o, "hote", ""), user: optField(o, "utilisateur", ""),
                      key: optField(o, "clef", ""), password: optField(o, "motdepasse", ""),
                      port: optField(o, "port", 0))
  let ex = o.field("options")
  if ex.kind == vkTable:
    for i in 1 .. ex.t.rawLen: result.extra.add rawToString(ex.t.rawGet(intV(i)))
  if result.host.len == 0: rtError("ssh : champ hote manquant")

proc sftpBatch(L: Interp, s: SshSession, commands: string): (string, int) =
  L.runTool(s, "sftp", s.baseOpts("-P") & @["-b", "-", s.target], commands)

proc quoteRemote(p: string): string = "\"" & p.replace("\"", "\\\"") & "\""

proc resultTable(outp: string, code: int): Value =
  record({"sortie": strV(outp), "code": intV(code)})

proc openSsh(L: Interp): Value =
  sshMethods = newLib()
  let sm = sshMethods
  sm.fn "executer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSsh(a, "executer")
    let (outp, code) = L.runTool(s, "ssh", s.baseOpts("-p") & @[s.target, L.checkStr(a, 2, "executer")])
    @[resultTable(outp, code)]
  sm.fn "lire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSsh(a, "lire")
    let remote = L.checkStr(a, 2, "lire")
    let local = L.optStr(a, 3, "lire", extractFilename(remote))
    let (outp, code) = L.runTool(s, "scp", s.baseOpts("-P") & @["-r", s.target & ":" & remote, local])
    if code != 0: return fail(outp.strip())
    @[boolV(true)]
  sm.fn "envoyer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSsh(a, "envoyer")
    let local = L.checkStr(a, 2, "envoyer")
    let remote = L.optStr(a, 3, "envoyer", extractFilename(local))
    let (outp, code) = L.runTool(s, "scp", s.baseOpts("-P") & @["-r", local, s.target & ":" & remote])
    if code != 0: return fail(outp.strip())
    @[boolV(true)]
  sm.fn "liste", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSsh(a, "liste")
    let (outp, code) = L.sftpBatch(s, "ls -1 " & quoteRemote(L.optStr(a, 2, "liste", ".")) & "\n")
    if code != 0: return fail(outp.strip())
    let t = newLTable()
    for l in outp.splitLines():
      let x = l.strip()
      if x.len > 0 and not x.startsWith("sftp>"): t.arr.add strV(x)
    @[tableV(t)]
  template sftpSimple(name, cmd: string, nargs: int) =
    sm.fn name, proc (L: Interp, a: seq[Value]): seq[Value] =
      let s = L.checkSsh(a, name)
      var line = cmd
      for i in 2 .. nargs + 1: line.add " " & quoteRemote(L.checkStr(a, i, name))
      let (outp, code) = L.sftpBatch(s, line & "\n")
      if code != 0: return fail(outp.strip())
      @[boolV(true)]
  sftpSimple("creerdossier", "mkdir", 1)
  sftpSimple("supprimerdossier", "rmdir", 1)
  sftpSimple("supprimer", "rm", 1)
  sftpSimple("renommer", "rename", 2)

  let m = newLib()
  m.fn "connecter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = sshFromOpts(L.checkTable(a, 1, "connecter"))
    if optBool(a, 2, true):
      let (outp, code) = L.runTool(s, "ssh", s.baseOpts("-p") & @[s.target, "exit"])
      if code != 0: return fail(outp.strip())
    @[L.wrap(s, "ssh", sshMethods)]
  m.fn "executer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = L.checkTable(a, 1, "executer")
    let s = sshFromOpts(o)
    let (outp, code) = L.runTool(s, "ssh", s.baseOpts("-p") & @[s.target, optField(o, "commande", "")])
    @[resultTable(outp, code)]
  tableV(m)

proc openSftp(L: Interp): Value =
  # « sftp » partage les sessions de « ssh » (transferts lire / envoyer / liste...).
  L.openPackage("ssh")

const sshDocs = [
  "ssh.connecter{hote=, utilisateur=, port=22, clef=, motdepasse=, options={}}", "Ouvre une session (vérifie la connexion). Authentification par clef ; motdepasse demande sshpass.",
  "ssh.executer{hote=, utilisateur=, commande=, ...}", "Exécute une commande sans garder de session : {sortie, code}.",
  "session:executer(commande)", "Exécute une commande distante : {sortie, code}.",
  "session:lire(distant, [local])", "Télécharge un fichier ou dossier (scp).",
  "session:envoyer(local, [distant])", "Envoie un fichier ou dossier (scp).",
  "session:liste([chemin])", "Noms d'un dossier distant (sftp).",
  "session:creerdossier(chemin)", "Crée un dossier distant (sftp).", "session:supprimerdossier(chemin)", "Supprime un dossier distant (sftp).",
  "session:supprimer(chemin)", "Supprime un fichier distant (sftp).", "session:renommer(ancien, nouveau)", "Renomme (sftp)."]

registerPackage PackageDef(name: "ssh", open: openSsh,
  description: "SSH (client OpenSSH)", docs: docs("ssh", sshDocs))
registerPackage PackageDef(name: "sftp", open: openSftp,
  description: "SFTP : mêmes sessions que ssh", docs: docs("sftp", [
    "sftp.connecter{hote=, utilisateur=, port=22, clef=, motdepasse=}", "Ouvre une session de transfert (identique à ssh.connecter)."]))
