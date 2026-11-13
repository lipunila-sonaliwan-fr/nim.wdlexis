# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet mqtt : protocole MQTT 3.1.1, en Nim pur
#
#   Client : connexion (TCP ou TLS), publication QoS 0, 1 et 2, messages retenus,
#   abonnements avec jokers (+ et #), testament, identifiants, session
#   persistante, maintien de la connexion (PINGREQ), reconnexion automatique.
#
#     c = mqtt.connecter("localhost", 1883, {id = "capteur-1", reconnecter = vrai})
#     c:abonner("maison/+/temperature", 1, @RECU)
#     c:publier("maison/salon/temperature", "21.5", {qos = 1, retenu = vrai})
#     c:traiter(0.1)              && reçoit et distribue aux procédures (minuterie)
#     m = c:recevoir(5)           && ou : attend un message (sans procédure)
#
#   Serveur (« broker ») intégré, sur son propre fil d'exécution : retenus,
#   testaments, QoS 0 à 2, sessions persistantes, utilisateurs et mots de passe.
#
#     s = mqtt.serveur(1883)
#     ? s:clients(), s:statistiques(), s:journal()
#
# Les attentes réseau libèrent l'interpréteur : les fenêtres restent réactives.
# Un client doit être « traité » régulièrement (c:traiter, c:recevoir ou
# c:attendre) pour recevoir ses messages et maintenir sa connexion.

import std/[net, nativesockets, os, strutils, tables, sets, times, locks, atomics,
            json, selectors, sysrand, deques]
import ../lexis/api
from ../lexis/fonctions import toJsonNode, fromJsonNode

when defined(windows):
  from std/winlean import WSAEWOULDBLOCK
else:
  from std/posix import EAGAIN, EWOULDBLOCK, EINTR

type MqttError = object of CatchableError

proc merr(msg: string) {.noreturn.} =
  raise newException(MqttError, msg)

#
# codage
#

const
  CONNECT = 1
  CONNACK = 2
  PUBLISH = 3
  PUBACK = 4
  PUBREC = 5
  PUBREL = 6
  PUBCOMP = 7
  SUBSCRIBE = 8
  SUBACK = 9
  UNSUBSCRIBE = 10
  UNSUBACK = 11
  PINGREQ = 12
  PINGRESP = 13
  DISCONNECT = 14

type Packet = object
  kind: int
  flags: int
  body: string

proc u16(v: int): string = $char((v shr 8) and 0xFF) & $char(v and 0xFF)
proc mstr(s: string): string = u16(s.len) & s

proc encodeLen(n: int): string =
  var x = n
  while true:
    var b = x mod 128
    x = x div 128
    if x > 0: b = b or 128
    result.add char(b)
    if x == 0: break

proc packet(kind, flags: int, body: string): string =
  result = $char((kind shl 4) or (flags and 15))
  result.add encodeLen(body.len)
  result.add body

proc takePacket(buf: var string, p: var Packet): bool =
  ## Extrait un paquet complet du tampon (faux s'il en manque une partie).
  if buf.len < 2: return false
  var mult = 1
  var length = 0
  var i = 1
  while true:
    if i >= buf.len: return false
    let b = ord(buf[i])
    length += (b and 127) * mult
    mult *= 128
    inc i
    if (b and 128) == 0: break
    if i > 4: merr("paquet MQTT invalide (longueur)")
  if buf.len < i + length: return false
  p.kind = ord(buf[0]) shr 4
  p.flags = ord(buf[0]) and 15
  p.body = buf[i ..< i + length]
  buf = buf[i + length .. ^1]
  true

proc rd16(s: string, i: int): int = (ord(s[i]) shl 8) or ord(s[i + 1])

proc rdStr(s: string, i: var int): string =
  if i + 2 > s.len: merr("paquet MQTT tronqué")
  let n = rd16(s, i)
  if i + 2 + n > s.len: merr("paquet MQTT tronqué")
  result = s[i + 2 ..< i + 2 + n]
  i += 2 + n

proc topicMatch*(filter, topic: string): bool =
  ## Correspondance d'un filtre d'abonnement (+ : un niveau, # : la suite).
  if topic.len > 0 and topic[0] == '$' and filter.len > 0 and filter[0] in {'+', '#'}: return false
  let f = filter.split('/')
  let t = topic.split('/')
  var i = 0
  while i < f.len:
    if f[i] == "#": return true
    if i >= t.len: return false
    if f[i] != "+" and f[i] != t[i]: return false
    inc i
  i == t.len

proc validFilter(f: string): bool =
  if f.len == 0 or f.len > 65535: return false
  let parts = f.split('/')
  for k, p in parts:
    if '#' in p and (p != "#" or k != parts.high): return false
    if '+' in p and p != "+": return false
  true

proc validTopic(t: string): bool =
  t.len > 0 and t.len <= 65535 and '+' notin t and '#' notin t

proc randomId(prefix: string): string =
  var b: array[6, byte]
  try:
    discard urandom(b)
  except CatchableError: discard
  result = prefix
  for x in b: result.add toHex(int(x), 2).toLowerAscii

proc connackText(code: int): string =
  case code
  of 1: "version du protocole refusée"
  of 2: "identifiant de client refusé"
  of 3: "serveur indisponible"
  of 4: "utilisateur ou mot de passe incorrect"
  of 5: "connexion non autorisée"
  else: "refus inconnu (" & $code & ")"

#
# client
#

type
  Msg = object
    topic, payload: string
    qos: int
    retain, dup: bool
    time: float

  Sub = object
    filter: string
    qos: int
    handler: Value

  MqttClient* = ref object of LUser
    host: string
    port: int
    tls: bool
    id: string
    user, pass: string
    hasAuth, hasPass: bool
    keepalive: int
    clean: bool
    will: tuple[has: bool, topic, payload: string, qos: int, retain: bool]
    timeout: float
    autoReconnect: bool
    sock: Socket
    connected: bool
    closedByUser: bool
    buf: string
    nextId: int
    lastSend, lastRecv: float
    pingSent: float
    inbox: Deque[Msg]
    subs: seq[Sub]
    acks: Table[int, int]        # identifiant -> type d'accusé reçu (PUBACK, PUBREC...)
    subacks: Table[int, string]  # identifiant -> codes retournés
    inQos2: HashSet[int]
    onMessage: Value
    onState: Value
    received, sent: int
    lastError: string
    lastTry: float
    sessionPresent: bool

var clientMethods {.threadvar.}: LTable

proc wouldBlock(err: OSErrorCode): bool =
  when defined(windows): int(err) == WSAEWOULDBLOCK
  else: int(err) in [int(EAGAIN), int(EWOULDBLOCK), int(EINTR)]

proc dropConnection(c: MqttClient, why: string) =
  if c.connected:
    c.lastError = why
  c.connected = false
  if not c.sock.isNil:
    try: c.sock.close() except CatchableError: discard
    c.sock = nil
  c.buf = ""

proc sendRaw(c: MqttClient, data: string) =
  if not c.connected or c.sock.isNil: merr("client MQTT non connecté" & (if c.lastError.len > 0: " (" & c.lastError & ")" else: ""))
  try:
    c.sock.send(data)
  except CatchableError as e:
    c.dropConnection("envoi impossible : " & e.msg)
    merr("connexion MQTT perdue : " & e.msg)
  c.lastSend = epochTime()

proc newPacketId(c: MqttClient): int =
  c.nextId = (c.nextId mod 65535) + 1
  c.nextId

proc handlePacket(c: MqttClient, p: Packet) =
  c.lastRecv = epochTime()
  case p.kind
  of PUBLISH:
    let qos = (p.flags shr 1) and 3
    var i = 0
    let topic = rdStr(p.body, i)
    var pid = 0
    if qos > 0:
      pid = rd16(p.body, i)
      i += 2
    let m = Msg(topic: topic, payload: p.body[i .. ^1], qos: qos, retain: (p.flags and 1) != 0,
                dup: (p.flags and 8) != 0, time: epochTime())
    case qos
    of 0:
      c.inbox.addLast m
    of 1:
      c.inbox.addLast m
      c.sendRaw packet(PUBACK, 0, u16(pid))
    else:
      if pid notin c.inQos2:
        c.inQos2.incl pid
        c.inbox.addLast m
      c.sendRaw packet(PUBREC, 0, u16(pid))
    inc c.received
  of PUBACK, PUBCOMP:
    c.acks[rd16(p.body, 0)] = p.kind
  of PUBREC:
    let pid = rd16(p.body, 0)
    c.acks[pid] = PUBREC
    c.sendRaw packet(PUBREL, 2, u16(pid))
  of PUBREL:
    let pid = rd16(p.body, 0)
    c.inQos2.excl pid
    c.sendRaw packet(PUBCOMP, 0, u16(pid))
  of SUBACK:
    c.subacks[rd16(p.body, 0)] = p.body[2 .. ^1]
  of UNSUBACK:
    c.subacks[rd16(p.body, 0)] = ""
  of PINGRESP:
    c.pingSent = 0
  else: discard

proc pump(L: Interp, c: MqttClient, timeoutMs: int): bool =
  ## Attend des données au plus timeoutMs, lit ce qui est arrivé et traite les
  ## paquets complets. Faux si rien n'est arrivé.
  if not c.connected: return false
  # paquets déjà reçus (arrivés avec le CONNACK, par exemple)
  var p0: Packet
  var had = false
  while takePacket(c.buf, p0):
    c.handlePacket(p0)
    had = true
  if had: return true
  let now = epochTime()
  if c.keepalive > 0:
    if c.pingSent > 0 and now - c.pingSent > float(c.keepalive):
      c.dropConnection("le serveur ne répond plus (PINGRESP)")
      return false
    if now - c.lastSend >= float(c.keepalive) * 0.75 and c.pingSent == 0:
      c.sendRaw packet(PINGREQ, 0, "")
      c.pingSent = epochTime()
  var ready = c.sock.hasDataBuffered
  if not ready:
    var fds = @[c.sock.getFd]
    var n = 0
    if timeoutMs > 0:
      L.blocking: n = selectRead(fds, timeoutMs)
    else:
      n = selectRead(fds, 0)
    ready = n > 0
  if not ready: return false
  var chunk = newString(16384)
  var got = 0
  try:
    got = c.sock.recv(addr chunk[0], chunk.len)
  except CatchableError as e:
    c.dropConnection("réception impossible : " & e.msg)
    return false
  if got <= 0:
    if got < 0 and wouldBlock(osLastError()): return false
    c.dropConnection("connexion fermée par le serveur")
    return false
  chunk.setLen(got)
  c.buf.add chunk
  var p: Packet
  while takePacket(c.buf, p):
    c.handlePacket(p)
  true

proc waitFor(L: Interp, c: MqttClient, cond: proc (): bool, what: string) =
  let deadline = epochTime() + c.timeout
  while not cond():
    if not c.connected: merr("connexion MQTT perdue pendant " & what & (if c.lastError.len > 0: " : " & c.lastError else: ""))
    let left = deadline - epochTime()
    if left <= 0: merr("délai dépassé pendant " & what)
    L.checkStop()
    discard L.pump(c, max(1, min(200, int(left * 1000))))

proc connectNow(L: Interp, c: MqttClient) =
  c.dropConnection("")
  var s = newSocket(buffered = false)
  try:
    L.blocking:
      s.connect(c.host, Port(c.port), int(c.timeout * 1000))
    if c.tls:
      when defined(ssl):
        let ctx = newContext(verifyMode = CVerifyPeer)
        ctx.wrapConnectedSocket(s, handshakeAsClient, c.host)
      else:
        merr("TLS indisponible : compilez avec -d:ssl")
  except MqttError:
    s.close()
    raise
  except CatchableError as e:
    s.close()
    merr(c.host & ":" & $c.port & " : " & e.msg)
  c.sock = s
  c.connected = true
  c.buf = ""
  c.pingSent = 0
  var flags = 0
  var payload = mstr(c.id)
  if c.clean: flags = flags or 2
  if c.will.has:
    flags = flags or 4 or (c.will.qos shl 3) or (if c.will.retain: 32 else: 0)
    payload.add mstr(c.will.topic)
    payload.add mstr(c.will.payload)
  if c.hasAuth:
    flags = flags or 128
    payload.add mstr(c.user)
    if c.hasPass:
      flags = flags or 64
      payload.add mstr(c.pass)
  let body = mstr("MQTT") & $char(4) & $char(flags) & u16(c.keepalive) & payload
  c.sendRaw packet(CONNECT, 0, body)
  # CONNACK
  let deadline = epochTime() + c.timeout
  while true:
    var p: Packet
    if takePacket(c.buf, p):
      if p.kind != CONNACK or p.body.len < 2:
        c.dropConnection("réponse inattendue")
        merr("réponse inattendue du serveur MQTT")
      let code = ord(p.body[1])
      if code != 0:
        c.dropConnection(connackText(code))
        merr("connexion MQTT refusée : " & connackText(code))
      c.sessionPresent = (ord(p.body[0]) and 1) != 0
      break
    if epochTime() > deadline:
      c.dropConnection("pas de CONNACK")
      merr("le serveur MQTT ne répond pas (CONNACK)")
    var fds = @[c.sock.getFd]
    var n = 0
    if c.sock.hasDataBuffered: n = 1
    else:
      L.blocking: n = selectRead(fds, 200)
    if n > 0:
      var chunk = newString(4096)
      let got = c.sock.recv(addr chunk[0], chunk.len)
      if got <= 0:
        c.dropConnection("connexion fermée")
        merr("connexion MQTT fermée par le serveur")
      chunk.setLen(got)
      c.buf.add chunk
  c.lastRecv = epochTime()
  c.lastError = ""

proc subscribeNow(L: Interp, c: MqttClient, filters: seq[(string, int)]): string =
  var body = ""
  let pid = c.newPacketId()
  body.add u16(pid)
  for (f, q) in filters:
    body.add mstr(f)
    body.add char(q)
  c.subacks.del pid
  c.sendRaw packet(SUBSCRIBE, 2, body)
  L.waitFor(c, proc (): bool = pid in c.subacks, "l'abonnement")
  result = c.subacks[pid]
  c.subacks.del pid

proc resubscribe(L: Interp, c: MqttClient) =
  if c.subs.len == 0 or (not c.clean and c.sessionPresent): return
  var fs: seq[(string, int)]
  var seen = initHashSet[string]()
  for s in c.subs:
    if s.filter notin seen:
      seen.incl s.filter
      fs.add (s.filter, s.qos)
  discard L.subscribeNow(c, fs)

proc ensureConnected(L: Interp, c: MqttClient): bool =
  ## Reconnexion automatique (au plus une tentative toutes les 2 secondes).
  if c.connected: return true
  if not c.autoReconnect or c.closedByUser: return false
  if epochTime() - c.lastTry < 2.0: return false
  c.lastTry = epochTime()
  try:
    L.connectNow(c)
    L.resubscribe(c)
    if c.onState.kind != vkNil:
      discard L.call(c.onState, @[strV("reconnecte")])
    true
  except MqttError:
    false

proc msgValue(m: Msg): Value =
  let t = newLTable()
  t.set "sujet", strV(m.topic)
  t.set "message", strV(m.payload)
  t.set "qos", intV(m.qos)
  t.set "retenu", boolV(m.retain)
  t.set "doublon", boolV(m.dup)
  t.set "horodatage", numV(m.time)
  tableV(t)

proc payloadOf(L: Interp, v: Value): string =
  case v.kind
  of vkNil: ""
  of vkTable: $L.toJsonNode(v)
  else: L.tostr(v)

proc dispatch(L: Interp, c: MqttClient, wait: float): int =
  ## Reçoit pendant au plus `wait` secondes (s'arrête au premier lot) et appelle
  ## les procédures des abonnements concernés ; renvoie le nombre de messages
  ## distribués. Les messages sans procédure restent pour c:recevoir().
  let wasConnected = c.connected
  if not L.ensureConnected(c): return 0
  discard L.pump(c, int(wait * 1000))
  while L.pump(c, 0): discard
  if wasConnected and not c.connected and c.onState.kind != vkNil:
    discard L.call(c.onState, @[strV("deconnecte")])
  var keep: Deque[Msg]
  while c.inbox.len > 0:
    let m = c.inbox.popFirst()
    var handlers: seq[Value]
    for s in c.subs:
      if s.handler.kind != vkNil and topicMatch(s.filter, m.topic):
        var dupl = false
        for h in handlers:
          if rawEquals(h, s.handler): dupl = true
        if not dupl: handlers.add s.handler
    if handlers.len == 0 and c.onMessage.kind != vkNil: handlers.add c.onMessage
    if handlers.len == 0:
      keep.addLast m
      continue
    let v = msgValue(m)
    for h in handlers: discard L.call(h, @[v])
    inc result
  c.inbox = keep

proc checkClient(L: Interp, a: seq[Value], fname: string): MqttClient =
  checkUser[MqttClient](L, a, 1, fname, "client MQTT")

template mq(body: untyped): untyped =
  try:
    body
  except MqttError as e:
    rtError(e.msg)

proc publishNow(L: Interp, c: MqttClient, topic, payload: string, qos: int, retain, wait: bool) =
  if not validTopic(topic): merr("sujet de publication invalide : « " & topic & " » (pas de + ni de #)")
  if qos notin 0 .. 2: merr("qos : 0, 1 ou 2")
  if not L.ensureConnected(c): merr("client MQTT non connecté" & (if c.lastError.len > 0: " (" & c.lastError & ")" else: ""))
  var body = mstr(topic)
  var pid = 0
  if qos > 0:
    pid = c.newPacketId()
    body.add u16(pid)
    c.acks.del pid
  body.add payload
  c.sendRaw packet(PUBLISH, (qos shl 1) or (if retain: 1 else: 0), body)
  inc c.sent
  if qos > 0 and wait:
    let final = if qos == 1: PUBACK else: PUBCOMP
    L.waitFor(c, proc (): bool = c.acks.getOrDefault(pid) == final,
              "la publication (QoS " & $qos & ")")
    c.acks.del pid
  # lecture opportuniste : accusés et messages en attente
  while L.pump(c, 0): discard

proc openClientMethods() =
  clientMethods = newLib()
  let cm = clientMethods
  cm.fn "publier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkClient(a, "publier")
    let topic = L.checkStr(a, 2, "publier")
    let payload = L.payloadOf(arg(a, 3))
    var qos = 0
    var retain = false
    var wait = true
    let o = arg(a, 4)
    if o.kind == vkTable:
      qos = optField(o.t, "qos", 0)
      retain = optField(o.t, "retenu", false)
      wait = optField(o.t, "attendre", true)
    elif o.kind in {vkInt, vkNum}:
      qos = int(L.checkInt(a, 4, "publier"))
      retain = optBool(a, 5, false)
    mq: L.publishNow(c, topic, payload, qos, retain, wait)
    @[boolV(true)]
  cm.fn "abonner", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkClient(a, "abonner")
    var filters: seq[string]
    let f = arg(a, 2)
    if f.kind == vkStr: filters.add f.s
    elif f.kind == vkTable:
      for i in 1 .. f.t.rawLen: filters.add L.tostr(f.t.rawGet(i))
    else: argError(2, "abonner", "filtre ou liste de filtres attendu")
    var qos = 0
    var handler = nilV
    var k = 3
    if arg(a, k).kind in {vkInt, vkNum}:
      qos = int(L.checkInt(a, k, "abonner"))
      inc k
    if arg(a, k).kind == vkFunc: handler = a[k - 1]
    elif arg(a, k).kind != vkNil: argError(k, "abonner", "procédure attendue (@NOM)")
    for x in filters:
      if not validFilter(x): rtError("filtre d'abonnement invalide : « " & x & " »")
    if qos notin 0 .. 2: rtError("qos : 0, 1 ou 2")
    var codes = ""
    mq:
      if not L.ensureConnected(c): merr("client MQTT non connecté")
      var fs: seq[(string, int)]
      for x in filters: fs.add (x, qos)
      codes = L.subscribeNow(c, fs)
    for i, x in filters:
      var replaced = false
      for s in c.subs.mitems:
        if s.filter == x:
          s.qos = qos
          s.handler = handler
          replaced = true
      if not replaced: c.subs.add Sub(filter: x, qos: qos, handler: handler)
    if filters.len == 1:
      let g = if codes.len > 0: ord(codes[0]) else: 128
      return @[if g == 128: boolV(false) else: intV(g)]
    let t = newLTable()
    for ch in codes: t.arr.add(if ord(ch) == 128: boolV(false) else: intV(ord(ch)))
    @[tableV(t)]
  cm.fn "desabonner", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkClient(a, "desabonner")
    var filters: seq[string]
    let f = arg(a, 2)
    if f.kind == vkStr: filters.add f.s
    elif f.kind == vkTable:
      for i in 1 .. f.t.rawLen: filters.add L.tostr(f.t.rawGet(i))
    mq:
      if c.connected:
        var body = ""
        let pid = c.newPacketId()
        body.add u16(pid)
        for x in filters: body.add mstr(x)
        c.subacks.del pid
        c.sendRaw packet(UNSUBSCRIBE, 2, body)
        L.waitFor(c, proc (): bool = pid in c.subacks, "le désabonnement")
        c.subacks.del pid
    var kept: seq[Sub]
    for s in c.subs:
      if s.filter notin filters: kept.add s
    c.subs = kept
    @[boolV(true)]
  cm.fn "abonnements", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkClient(a, "abonnements")
    let t = newLTable()
    for s in c.subs:
      t.arr.add record({"filtre": strV(s.filter), "qos": intV(s.qos),
                        "procedure": boolV(s.handler.kind != vkNil)})
    @[tableV(t)]
  cm.fn "recevoir", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkClient(a, "recevoir")
    let wait = if arg(a, 2).kind == vkNil: -1.0 else: L.checkNum(a, 2, "recevoir")
    let deadline = epochTime() + wait
    mq:
      while c.inbox.len == 0:
        if not L.ensureConnected(c):
          if not c.autoReconnect or c.closedByUser: break
        L.checkStop()
        let left = if wait < 0: 0.5 else: deadline - epochTime()
        if left <= 0 and wait >= 0: break
        if c.connected: discard L.pump(c, max(0, min(500, int(left * 1000))))
        else:
          L.blocking: sleep(100)
        if wait == 0: break
    if c.inbox.len == 0: return @[nilV]
    @[msgValue(c.inbox.popFirst())]
  cm.fn "traiter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkClient(a, "traiter")
    let wait = L.optNum(a, 2, "traiter", 0)
    var n = 0
    mq: n = L.dispatch(c, wait)
    @[intV(n)]
  cm.fn "attendre", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkClient(a, "attendre")
    let secs = L.checkNum(a, 2, "attendre")
    let deadline = epochTime() + secs
    var n = 0
    mq:
      while epochTime() < deadline:
        L.checkStop()
        n += L.dispatch(c, min(0.2, max(0.0, deadline - epochTime())))
        if not c.connected and not c.autoReconnect: break
        if not c.connected:
          L.blocking: sleep(50)
    @[intV(n)]
  cm.fn "enattente", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkClient(a, "enattente")
    mq:
      if c.connected:
        while L.pump(c, 0): discard
    @[intV(c.inbox.len)]
  cm.fn "surmessage", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkClient(a, "surmessage")
    c.onMessage = arg(a, 2)
    @[boolV(true)]
  cm.fn "suretat", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkClient(a, "suretat")
    c.onState = arg(a, 2)
    @[boolV(true)]
  cm.fn "connecte", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkClient(a, "connecte")
    if c.connected:
      try:
        while L.pump(c, 0): discard
      except MqttError: discard
    @[boolV(c.connected)]
  cm.fn "reconnecter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkClient(a, "reconnecter")
    c.closedByUser = false
    mq:
      L.connectNow(c)
      L.resubscribe(c)
    @[boolV(true)]
  cm.fn "deconnecter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkClient(a, "deconnecter")
    c.closedByUser = true
    if c.connected:
      try: c.sendRaw packet(DISCONNECT, 0, "")
      except MqttError: discard
    c.dropConnection("déconnecté")
    @[boolV(true)]
  cm.fn "ping", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkClient(a, "ping")
    let t0 = epochTime()
    mq:
      if not L.ensureConnected(c): merr("client MQTT non connecté")
      c.sendRaw packet(PINGREQ, 0, "")
      c.pingSent = epochTime()
      L.waitFor(c, proc (): bool = c.pingSent == 0, "le ping")
    @[numV(epochTime() - t0)]
  cm.fn "infos", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.checkClient(a, "infos")
    @[record({"id": strV(c.id), "hote": strV(c.host), "port": intV(c.port), "tls": boolV(c.tls),
              "connecte": boolV(c.connected), "recus": intV(c.received), "envoyes": intV(c.sent),
              "enattente": intV(c.inbox.len), "abonnements": intV(c.subs.len),
              "session": boolV(c.sessionPresent), "erreur": strV(c.lastError)})]

proc newClient(L: Interp, host: string, port: int, o: LTable): MqttClient =
  result = MqttClient(host: host, port: port)
  result.tls = optField(o, "tls", false)
  if port <= 0: result.port = if result.tls: 8883 else: 1883
  result.id = optField(o, "id", "")
  if result.id.len == 0: result.id = randomId("lexis-")
  let u = o.field("utilisateur")
  if u.kind != vkNil:
    result.hasAuth = true
    result.user = L.tostr(u)
  let p = o.field("motdepasse")
  if p.kind != vkNil:
    result.hasPass = true
    result.pass = L.tostr(p)
    if not result.hasAuth:
      result.hasAuth = true
  result.keepalive = max(0, min(65535, optField(o, "maintien", 60)))
  result.clean = optField(o, "propre", true)
  result.timeout = optField(o, "delai", 10.0)
  result.autoReconnect = optField(o, "reconnecter", false)
  result.inbox = initDeque[Msg]()
  result.onMessage = nilV
  result.onState = nilV
  let w = o.field("testament")
  if w.kind == vkTable:
    result.will.has = true
    result.will.topic = optField(w.t, "sujet", "")
    result.will.payload = L.payloadOf(w.t.field("message"))
    result.will.qos = max(0, min(2, optField(w.t, "qos", 0)))
    result.will.retain = optField(w.t, "retenu", false)
    if not validTopic(result.will.topic): rtError("testament : sujet invalide")

#
# serveur
#

type
  BrokerShared = object
    lock: Lock
    stop: Atomic[bool]
    running: Atomic[bool]
    fd: int
    port: int
    users: seq[(string, string)]
    anonymous: bool
    maxQueue: int
    log: seq[string]
    logRead: int
    clientsJson: string
    received, delivered, connections: int
    retained: int
    started: float
    error: string

  Session = ref object
    id: string
    subs: OrderedTable[string, int]
    queue: seq[string]
    conn: Conn
    clean: bool

  Conn = ref object
    sock: Socket
    fd: int
    peer: string
    inbuf, outbuf: string
    gotConnect: bool
    id: string
    keepalive: int
    lastIn: float
    will: tuple[has: bool, topic, payload: string, qos: int, retain: bool]
    session: Session
    nextId: int
    inQos2: HashSet[int]
    closing: bool
    dead: bool
    user: string

proc blog(sh: ptr BrokerShared, msg: string) =
  withLock sh.lock:
    sh.log.add times.format(now(), "HH:mm:ss") & "  " & msg
    if sh.log.len > 1000:
      let cut = sh.log.len - 800
      sh.log = sh.log[cut .. ^1]
      sh.logRead = max(0, sh.logRead - cut)

proc brokerMain(sh: ptr BrokerShared) {.thread.} =
  var server = newSocket(SocketHandle(sh.fd), AF_INET, SOCK_STREAM, IPPROTO_TCP, buffered = false)
  let sfd = int(server.getFd)
  server.getFd.setBlocking(false)
  var sel = newSelector[int]()
  sel.registerHandle(server.getFd, {Event.Read}, 0)
  var conns = initTable[int, Conn]()
  var sessions = initTable[string, Session]()
  var retained = initOrderedTable[string, (string, int)]()
  var anon = 0

  proc snapshot() =
    var arr = newJArray()
    for id, s in sessions:
      if s.conn.isNil and s.clean: continue
      var subs = newJArray()
      for f, q in s.subs: subs.add %*{"filtre": f, "qos": q}
      arr.add %*{"id": id, "adresse": (if s.conn.isNil: "" else: s.conn.peer),
                 "connecte": not s.conn.isNil, "abonnements": subs,
                 "enattente": s.queue.len,
                 "utilisateur": (if s.conn.isNil: "" else: s.conn.user)}
    withLock sh.lock:
      sh.clientsJson = $arr
      sh.retained = retained.len

  proc queueOut(c: Conn, data: string) =
    if c.dead: return
    c.outbuf.add data
    try:
      while c.outbuf.len > 0:
        let n = c.sock.send(addr c.outbuf[0], c.outbuf.len)
        if n < 0:
          if wouldBlock(osLastError()): break
          c.dead = true
          return
        c.outbuf = c.outbuf[n .. ^1]
    except CatchableError:
      c.dead = true
      return
    try:
      if c.outbuf.len > 0: sel.updateHandle(SocketHandle(c.fd), {Event.Read, Event.Write})
    except CatchableError: discard

  proc publishTo(c: Conn, topic, payload: string, qos: int, retain: bool) =
    var body = mstr(topic)
    if qos > 0:
      c.nextId = (c.nextId mod 65535) + 1
      body.add u16(c.nextId)
    body.add payload
    c.queueOut packet(PUBLISH, (qos shl 1) or (if retain: 1 else: 0), body)
    withLock sh.lock: inc sh.delivered

  proc route(topic, payload: string, qos: int) =
    for id, s in sessions:
      var best = -1
      for f, q in s.subs:
        if topicMatch(f, topic): best = max(best, q)
      if best < 0: continue
      let q = min(best, qos)
      if not s.conn.isNil and not s.conn.dead:
        s.conn.publishTo(topic, payload, q, false)
      elif not s.clean and q > 0 and s.queue.len < sh.maxQueue:
        var body = mstr(topic)
        body.add u16(1)                     # identifiant attribué à l'envoi
        body.add payload
        s.queue.add $char(q) & body

  proc closeConn(c: Conn, why: string, sendWill: bool) =
    if conns.hasKey(c.fd):
      conns.del c.fd
      try: sel.unregister(SocketHandle(c.fd))
      except CatchableError: discard
    try: c.sock.close()
    except CatchableError: discard
    if not c.session.isNil and c.session.conn == c:
      c.session.conn = nil
      if c.session.clean: sessions.del c.session.id
    if sendWill and c.will.has:
      sh.blog("testament de " & c.id & " publié sur " & c.will.topic)
      if c.will.retain:
        if c.will.payload.len == 0: retained.del c.will.topic
        else: retained[c.will.topic] = (c.will.payload, c.will.qos)
      route(c.will.topic, c.will.payload, c.will.qos)
    if c.gotConnect: sh.blog("déconnexion de " & c.id & " (" & why & ")")
    snapshot()

  proc handle(c: Conn, p: Packet) =
    c.lastIn = epochTime()
    if not c.gotConnect and p.kind != CONNECT:
      c.dead = true
      return
    case p.kind
    of CONNECT:
      if c.gotConnect:
        c.dead = true
        return
      var i = 0
      let proto = rdStr(p.body, i)
      let level = ord(p.body[i])
      let flags = ord(p.body[i + 1])
      c.keepalive = rd16(p.body, i + 2)
      i += 4
      if not ((proto == "MQTT" and level == 4) or (proto == "MQIsdp" and level == 3)):
        c.queueOut packet(CONNACK, 0, "\x00\x01")
        c.closing = true
        return
      var id = rdStr(p.body, i)
      let clean = (flags and 2) != 0
      if (flags and 4) != 0:
        c.will.has = true
        c.will.topic = rdStr(p.body, i)
        c.will.payload = rdStr(p.body, i)
        c.will.qos = (flags shr 3) and 3
        c.will.retain = (flags and 32) != 0
      var user, pass = ""
      var hasUser = false
      if (flags and 128) != 0:
        user = rdStr(p.body, i)
        hasUser = true
      if (flags and 64) != 0: pass = rdStr(p.body, i)
      if id.len == 0:
        if not clean:
          c.queueOut packet(CONNACK, 0, "\x00\x02")
          c.closing = true
          return
        inc anon
        id = randomId("auto-")
      var ok = sh.users.len == 0 or (not hasUser and sh.anonymous)
      if hasUser:
        for (u, pw) in sh.users:
          if u == user and pw == pass: ok = true
        if sh.users.len == 0: ok = true
      if not ok:
        sh.blog("refus de " & c.peer & " : utilisateur ou mot de passe incorrect")
        c.queueOut packet(CONNACK, 0, "\x00\x04")
        c.closing = true
        return
      c.id = id
      c.user = user
      c.gotConnect = true
      # prise de contrôle : un client déjà connecté avec le même identifiant est fermé
      var present = false
      if sessions.hasKey(id):
        let old = sessions[id]
        if not old.conn.isNil and old.conn != c:
          let oc = old.conn
          oc.will.has = false
          oc.closeConn("remplacé par une nouvelle connexion", false)
        if clean or old.clean:
          sessions.del id
        else:
          present = true
      var s: Session
      if present:
        s = sessions[id]
      else:
        s = Session(id: id, subs: initOrderedTable[string, int]())
        sessions[id] = s
      s.clean = clean
      s.conn = c
      c.session = s
      c.queueOut packet(CONNACK, 0, $char(if present: 1 else: 0) & "\x00")
      withLock sh.lock: inc sh.connections
      sh.blog("connexion de " & id & " (" & c.peer & (if user.len > 0: ", " & user else: "") &
              (if present: ", session reprise" else: "") & ")")
      # messages gardés pendant l'absence
      for q in s.queue:
        let qos = ord(q[0])
        var body = q[1 .. ^1]
        var j = 0
        discard rdStr(body, j)
        c.nextId = (c.nextId mod 65535) + 1
        body[j] = char((c.nextId shr 8) and 0xFF)
        body[j + 1] = char(c.nextId and 0xFF)
        c.queueOut packet(PUBLISH, qos shl 1, body)
      s.queue.setLen(0)
      snapshot()
    of PUBLISH:
      let qos = (p.flags shr 1) and 3
      let retain = (p.flags and 1) != 0
      var i = 0
      let topic = rdStr(p.body, i)
      var pid = 0
      if qos > 0:
        pid = rd16(p.body, i)
        i += 2
      if qos == 3 or not validTopic(topic):
        c.dead = true
        return
      let payload = p.body[i .. ^1]
      withLock sh.lock: inc sh.received
      var fresh = true
      if qos == 2:
        if pid in c.inQos2: fresh = false
        else: c.inQos2.incl pid
      if fresh:
        if retain:
          if payload.len == 0: retained.del topic
          else: retained[topic] = (payload, qos)
          withLock sh.lock: sh.retained = retained.len
        route(topic, payload, qos)
      if qos == 1: c.queueOut packet(PUBACK, 0, u16(pid))
      elif qos == 2: c.queueOut packet(PUBREC, 0, u16(pid))
    of PUBREL:
      let pid = rd16(p.body, 0)
      c.inQos2.excl pid
      c.queueOut packet(PUBCOMP, 0, u16(pid))
    of PUBREC:
      c.queueOut packet(PUBREL, 2, u16(rd16(p.body, 0)))
    of PUBACK, PUBCOMP: discard
    of SUBSCRIBE:
      let pid = rd16(p.body, 0)
      var i = 2
      var codes = ""
      var added: seq[(string, int)]
      while i < p.body.len:
        let f = rdStr(p.body, i)
        let q = ord(p.body[i]) and 3
        inc i
        if not validFilter(f) or q > 2:
          codes.add char(0x80)
        else:
          c.session.subs[f] = q
          codes.add char(q)
          added.add (f, q)
      c.queueOut packet(SUBACK, 0, u16(pid) & codes)
      for (f, q) in added:
        sh.blog(c.id & " s'abonne à " & f & " (QoS " & $q & ")")
        for t, v in retained:
          if topicMatch(f, t): c.publishTo(t, v[0], min(q, v[1]), true)
      snapshot()
    of UNSUBSCRIBE:
      let pid = rd16(p.body, 0)
      var i = 2
      while i < p.body.len:
        let f = rdStr(p.body, i)
        c.session.subs.del f
        sh.blog(c.id & " se désabonne de " & f)
      c.queueOut packet(UNSUBACK, 0, u16(pid))
      snapshot()
    of PINGREQ:
      c.queueOut packet(PINGRESP, 0, "")
    of DISCONNECT:
      c.will.has = false
      c.closing = true
    else:
      c.dead = true

  sh.blog("serveur MQTT à l'écoute sur le port " & $sh.port)
  var lastCheck = epochTime()
  while not sh.stop.load:
    var events: seq[ReadyKey]
    try: events = sel.select(100)
    except CatchableError: events = @[]
    for ev in events:
      if ev.fd == sfd:
        while true:
          var client: Socket
          var address = ""
          try:
            server.acceptAddr(client, address)
          except CatchableError:
            break
          if client.isNil: break
          client.getFd.setBlocking(false)
          let c = Conn(sock: client, fd: int(client.getFd), peer: address, lastIn: epochTime(),
                       inQos2: initHashSet[int]())
          conns[c.fd] = c
          sel.registerHandle(client.getFd, {Event.Read}, c.fd)
        continue
      if not conns.hasKey(ev.fd): continue
      let c = conns[ev.fd]
      if Event.Error in ev.events:
        c.dead = true
      if Event.Write in ev.events and c.outbuf.len > 0:
        c.queueOut("")
        if c.outbuf.len == 0:
          try: sel.updateHandle(SocketHandle(c.fd), {Event.Read})
          except CatchableError: discard
      if Event.Read in ev.events and not c.dead:
        var chunk = newString(16384)
        var n = -1
        try: n = c.sock.recv(addr chunk[0], chunk.len)
        except CatchableError: n = -1
        if n == 0: c.dead = true
        elif n < 0:
          if not wouldBlock(osLastError()): c.dead = true
        else:
          chunk.setLen(n)
          c.inbuf.add chunk
          try:
            var p: Packet
            while not c.dead and not c.closing and takePacket(c.inbuf, p):
              c.handle(p)
          except CatchableError:
            c.dead = true
    # fermetures et maintien de connexion
    let now = epochTime()
    var toClose: seq[(Conn, string, bool)]
    for fd, c in conns:
      if c.dead: toClose.add (c, "connexion perdue", true)
      elif c.closing and c.outbuf.len == 0: toClose.add (c, "fin de session", c.will.has)
      elif c.gotConnect and c.keepalive > 0 and now - c.lastIn > float(c.keepalive) * 1.5:
        toClose.add (c, "délai de maintien dépassé", true)
      elif not c.gotConnect and now - c.lastIn > 30: toClose.add (c, "pas de CONNECT", false)
    for (c, why, will) in toClose: c.closeConn(why, will)
    if now - lastCheck > 2:
      lastCheck = now
  for fd, c in conns:
    try: c.sock.close() except CatchableError: discard
  try: sel.close() except CatchableError: discard
  try: server.close() except CatchableError: discard
  sh.blog("serveur arrêté")
  sh.running.store(false)

type
  MqttServer* = ref object of LUser
    sh: ptr BrokerShared
    th: Thread[ptr BrokerShared]
    stopped: bool

var serverMethods {.threadvar.}: LTable

proc stopServer(s: MqttServer) =
  if s.stopped: return
  s.stopped = true
  s.sh.stop.store(true)
  joinThread(s.th)

proc checkServer(L: Interp, a: seq[Value], fname: string): MqttServer =
  checkUser[MqttServer](L, a, 1, fname, "serveur MQTT")

proc openServerMethods() =
  serverMethods = newLib()
  let sm = serverMethods
  sm.fn "arreter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkServer(a, "arreter")
    L.blocking: s.stopServer()
    @[boolV(true)]
  sm.fn "actif", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[boolV(L.checkServer(a, "actif").sh.running.load)]
  sm.fn "port", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(L.checkServer(a, "port").sh.port)]
  sm.fn "clients", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkServer(a, "clients")
    var js = ""
    withLock s.sh.lock: js = s.sh.clientsJson
    if js.len == 0: js = "[]"
    @[fromJsonNode(parseJson(js), upperKeys = true)]
  sm.fn "statistiques", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkServer(a, "statistiques")
    var r, d, c, ret = 0
    var clients = 0
    withLock s.sh.lock:
      r = s.sh.received
      d = s.sh.delivered
      c = s.sh.connections
      ret = s.sh.retained
      try:
        for x in parseJson(if s.sh.clientsJson.len > 0: s.sh.clientsJson else: "[]"):
          if x["connecte"].getBool: inc clients
      except CatchableError: discard
    @[record({"clients": intV(clients), "recus": intV(r), "distribues": intV(d),
              "connexions": intV(c), "retenus": intV(ret),
              "duree": numV(epochTime() - s.sh.started), "actif": boolV(s.sh.running.load)})]
  sm.fn "journal", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkServer(a, "journal")
    let all = optBool(a, 2, false)
    let t = newLTable()
    withLock s.sh.lock:
      let start = if all: 0 else: s.sh.logRead
      for i in start ..< s.sh.log.len: t.arr.add strV(s.sh.log[i])
      s.sh.logRead = s.sh.log.len
    @[tableV(t)]

proc startServer(L: Interp, port: int, o: LTable): MqttServer =
  let host = optField(o, "hote", "0.0.0.0")
  let lsock = newSocket(buffered = false)
  try:
    lsock.setSockOpt(OptReuseAddr, true)
    lsock.bindAddr(Port(port), host)
    lsock.listen()
  except OSError as e:
    lsock.close()
    rtError("serveur MQTT : port " & $port & " : " & e.msg)
  let actual = int(lsock.getLocalAddr()[1])
  let sh = createShared(BrokerShared)
  initLock(sh.lock)
  sh.fd = int(lsock.getFd)
  sh.port = actual
  sh.anonymous = optField(o, "anonymes", true)
  sh.maxQueue = max(0, optField(o, "file", 1000))
  sh.started = epochTime()
  let u = o.field("utilisateurs")
  if u.kind == vkTable:
    for k, v in u.t.pairs:
      sh.users.add (rawToString(k).toLowerAscii, L.tostr(v))
  sh.running.store(true)
  result = MqttServer(sh: sh)
  createThread(result.th, brokerMain, sh)
  let s = result
  L.closers.add proc () = s.stopServer()

#
# paquet
#

proc openMqtt(L: Interp): Value =
  openClientMethods()
  openServerMethods()
  discard L.userMeta("client MQTT", clientMethods)
  discard L.userMeta("serveur MQTT", serverMethods)
  let m = newLib()
  m.fn "connecter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let host = L.optStr(a, 1, "connecter", "localhost")
    var port = 0
    var o: LTable = nil
    if arg(a, 2).kind in {vkInt, vkNum}: port = int(L.checkInt(a, 2, "connecter"))
    elif arg(a, 2).kind == vkTable: o = a[1].t
    if arg(a, 3).kind == vkTable: o = a[2].t
    let c = L.newClient(host, port, o)
    try:
      L.connectNow(c)
    except MqttError as e:
      if not c.autoReconnect: rtError(e.msg)
      c.lastTry = epochTime()
    L.closers.add proc () =
      if c.connected:
        try: c.sendRaw packet(DISCONNECT, 0, "")
        except CatchableError: discard
      c.dropConnection("fin du programme")
    @[L.wrap(c, "client MQTT", clientMethods)]
  m.fn "serveur", proc (L: Interp, a: seq[Value]): seq[Value] =
    var port = 1883
    var o: LTable = nil
    if arg(a, 1).kind in {vkInt, vkNum}: port = int(L.checkInt(a, 1, "serveur"))
    elif arg(a, 1).kind == vkTable: o = a[0].t
    if arg(a, 2).kind == vkTable: o = a[1].t
    if o != nil and o.field("port").kind != vkNil: port = optField(o, "port", 1883)
    @[L.wrap(L.startServer(port, o), "serveur MQTT", serverMethods)]
  m.fn "correspond", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[boolV(topicMatch(L.checkStr(a, 1, "correspond"), L.checkStr(a, 2, "correspond")))]
  tableV(m)

registerPackage PackageDef(name: "mqtt", open: openMqtt,
  description: "Protocole MQTT 3.1.1 : client et serveur (Nim pur)",
  docs: docs("mqtt", [
    "mqtt.connecter([hote], [port], [{id=, utilisateur=, motdepasse=, tls=, maintien=60, propre=vrai, testament=, reconnecter=, delai=10}])", "Connexion à un serveur MQTT (port 1883, 8883 en TLS) ; renvoie un client. id : identifiant (aléatoire par défaut) ; maintien : secondes entre deux signes de vie ; propre = faux : session persistante (abonnements et messages QoS 1-2 gardés par le serveur) ; testament = {sujet=, message=, qos=, retenu=} : publié par le serveur si la connexion se perd ; reconnecter = vrai : reconnexion et réabonnement automatiques ; delai : attente maximale des réponses (secondes).",
    "mqtt.serveur([port=1883], [{hote=\"0.0.0.0\", utilisateurs={nom=motdepasse}, anonymes=vrai, file=1000}])", "Démarre un serveur MQTT (broker) sur son propre fil d'exécution : messages retenus, testaments, QoS 0 à 2, sessions persistantes (file : messages gardés par client absent), comptes (anonymes = faux : compte obligatoire). Port 0 : port libre choisi par le système. Arrêté à la fin du programme.",
    "mqtt.correspond(filtre, sujet)", "Vrai si le sujet correspond au filtre (+ : un niveau, # : tous les niveaux suivants).",
    "c:publier(sujet, message, [{qos=0, retenu=faux, attendre=vrai}])", "Publie un message (texte, octets ; une table est encodée en JSON). QoS 1 et 2 : attend l'accusé du serveur (attendre = faux : sans attendre). retenu : le serveur garde le dernier message du sujet pour les futurs abonnés (message vide : l'efface). Aussi c:publier(sujet, message, qos, retenu).",
    "c:abonner(filtre | {filtres}, [qos], [@procedure])", "S'abonne (jokers + et #) ; la procédure reçoit chaque message {sujet, message, qos, retenu, doublon, horodatage} lors de c:traiter() ou c:attendre(). Renvoie la QoS accordée (faux si refusé), une liste pour plusieurs filtres.",
    "c:desabonner(filtre | {filtres})", "Se désabonne.",
    "c:abonnements()", "Liste de {filtre, qos, procedure}.",
    "c:traiter([delai=0])", "Reçoit les messages arrivés (attente au plus delai secondes) et les distribue aux procédures des abonnements (ou à c:surmessage) ; maintient la connexion. Renvoie le nombre de messages distribués. À appeler régulièrement, par exemple par une minuterie.",
    "c:attendre(secondes)", "Traite les messages pendant la durée donnée (programmes sans fenêtre) ; renvoie le nombre distribué.",
    "c:recevoir([delai])", "Message suivant sans procédure associée (attente au plus delai secondes ; sans délai : jusqu'à l'arrivée d'un message) ; nul sinon.",
    "c:enattente()", "Nombre de messages reçus non encore lus.",
    "c:surmessage(@procedure)", "Procédure appelée pour les messages qu'aucune procédure d'abonnement ne prend.",
    "c:suretat(@procedure)", "Procédure appelée avec \"deconnecte\" ou \"reconnecte\" quand la connexion change.",
    "c:connecte()", "Vrai si la connexion est ouverte.",
    "c:reconnecter()", "Rouvre la connexion et rétablit les abonnements.",
    "c:deconnecter()", "Ferme proprement la connexion (sans testament).",
    "c:ping()", "Aller-retour avec le serveur, en secondes.",
    "c:infos()", "{id, hote, port, tls, connecte, recus, envoyes, enattente, abonnements, session, erreur}.",
    "s:arreter()", "Arrête le serveur.",
    "s:actif()", "Vrai tant que le serveur fonctionne.",
    "s:port()", "Port d'écoute.",
    "s:clients()", "Clients et sessions : liste de {id, adresse, connecte, utilisateur, enattente, abonnements = {{filtre, qos}}}.",
    "s:statistiques()", "{clients, recus, distribues, connexions, retenus, duree, actif}.",
    "s:journal([tout])", "Lignes du journal (connexions, abonnements, testaments) apparues depuis le dernier appel ; tout = vrai : tout le journal."]))
