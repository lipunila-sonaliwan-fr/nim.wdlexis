# Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr
#   wdlexis+ - multitâche
#
#   tache   tâches coopératives dans le même interpréteur : tache.lancer,
#           tache.attendre, tache.ceder, tache.executer, canaux tache.canal() ;
#           idéal pour les automates et les entrées / sorties.
#   fil     vrais fils d'exécution du système : chaque fil a son propre
#           interpréteur et communique par messages (valeurs converties en JSON).

import std/[tables, times, os, locks, deques, json, strutils, atomics]
import ../lexis/[api, fonctions]
from ../lexis/lexer import SyntaxError

#
# task
#

type
  Task* = ref object of LUser
    co: Coroutine
    wakeAt: float
    result: seq[Value]
    error: Value
    failed: bool

  LChannel* = ref object of LUser
    items: Deque[Value]
    capacity: int

  Scheduler = ref object of RootObj
    tasks: seq[Task]
    current: Task

var taskMethods {.threadvar.}: LTable
var chanMethods {.threadvar.}: LTable

proc sched(L: Interp): Scheduler =
  let r = L.ext.getOrDefault("task")
  if r.isNil:
    result = Scheduler()
    L.ext["task"] = result
  else:
    result = Scheduler(r)

proc inTask(L: Interp): Task =
  let co = ctx().co
  if co.isNil: return nil
  for t in L.sched.tasks:
    if t.co == co: return t
  nil

proc waitUntil(L: Interp, cond: proc (): bool) =
  # Dans une tâche : rend la main jusqu'à ce que cond() soit vraie.
  # Hors tâche : fait tourner les autres tâches en attendant.
  let t = L.inTask()
  if not t.isNil:
    while not cond():
      discard L.yieldCo(@[])
    return
  while not cond():
    var progressed = false
    for tk in L.sched.tasks:
      if tk.co.status == csSuspended and epochTime() >= tk.wakeAt:
        progressed = true
        L.sched.current = tk
        let (ok, vals) = L.resume(tk.co, @[])
        L.sched.current = nil
        if not ok:
          tk.failed = true
          tk.error = first(vals)
          L.onError("tâche : " & L.tostr(tk.error))
        elif tk.co.status == csDead:
          tk.result = vals
    if not progressed:
      L.blocking: sleep(5)
    L.checkStop()

proc runAll(L: Interp) =
  L.waitUntil(proc (): bool =
    for t in L.sched.tasks:
      if t.co.status != csDead: return false
    true)

proc openTask(L: Interp): Value =
  taskMethods = newLib()
  chanMethods = newLib()
  taskMethods.fn "etat", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = checkUser[Task](L, a, 1, "etat", "tâche")
    @[strV(if t.failed: "erreur" else: $t.co.status)]
  taskMethods.fn "attendre", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = checkUser[Task](L, a, 1, "attendre", "tâche")
    L.waitUntil(proc (): bool = t.co.status == csDead)
    if t.failed: raiseValue(t.error)
    @[first(t.result)]
  taskMethods.fn "annuler", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = checkUser[Task](L, a, 1, "annuler", "tâche")
    if t.co.status == csSuspended: closeCoroutine(t.co)
  chanMethods.fn "envoyer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = checkUser[LChannel](L, a, 1, "envoyer", "canal")
    L.waitUntil(proc (): bool = c.capacity <= 0 or c.items.len < c.capacity)
    c.items.addLast arg(a, 2)
  chanMethods.fn "recevoir", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = checkUser[LChannel](L, a, 1, "recevoir", "canal")
    let timeout = L.optNum(a, 2, "recevoir", -1)
    let deadline = if timeout >= 0: epochTime() + timeout else: Inf
    L.waitUntil(proc (): bool = c.items.len > 0 or epochTime() >= deadline)
    if c.items.len == 0: return @[nilV]
    @[c.items.popFirst()]
  chanMethods.fn "nombre", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(checkUser[LChannel](L, a, 1, "nombre", "canal").items.len)]

  let m = newLib()
  m.fn "lancer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let f = L.checkFunc(a, 1, "lancer")
    let args = if a.len > 1: a[1 .. ^1] else: @[]
    let body = fnV("tache", proc (L: Interp, x: seq[Value]): seq[Value] = L.call(f, args))
    let t = Task(co: L.newCoroutine(body))
    L.sched.tasks.add t
    @[L.wrap(t, "tache", taskMethods)]
  m.fn "attendre", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.optNum(a, 1, "attendre", 0)
    let t = L.inTask()
    if t.isNil:
      let until = epochTime() + s
      L.waitUntil(proc (): bool = epochTime() >= until)
    else:
      t.wakeAt = epochTime() + s
      discard L.yieldCo(@[])
  m.fn "ceder", proc (L: Interp, a: seq[Value]): seq[Value] =
    if not L.inTask().isNil: discard L.yieldCo(@[])
  m.fn "executer", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.runAll()
  m.fn "canal", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = LChannel(capacity: int(L.optInt(a, 1, "canal", 0)), items: initDeque[Value]())
    @[L.wrap(c, "canal", chanMethods)]
  m.fn "maintenant", proc (L: Interp, a: seq[Value]): seq[Value] = @[numV(epochTime())]
  m.fn "nombre", proc (L: Interp, a: seq[Value]): seq[Value] =
    var n = 0
    for t in L.sched.tasks:
      if t.co.status != csDead: inc n
    @[intV(n)]
  tableV(m)

registerPackage PackageDef(name: "tache", open: openTask,
  description: "Tâches coopératives",
  docs: docs("tache", [
    "tache.lancer(@proc, ...)", "Crée une tâche qui exécutera proc(...) ; elle démarre au prochain tache.executer(), tache.attendre() ou attente.",
    "tache.executer()", "Fait tourner les tâches jusqu'à ce qu'elles soient toutes terminées.",
    "tache.attendre(secondes)", "Dans une tâche : la suspend ; ailleurs : attend en faisant tourner les tâches.",
    "tache.ceder()", "Rend la main aux autres tâches.",
    "tache.canal([capacite])", "Canal de communication (capacité 0 = illimitée).",
    "tache.nombre()", "Nombre de tâches en cours.",
    "tache.maintenant()", "Heure en secondes (avec décimales).",
    "t:attendre()", "Attend la fin d'une tâche et renvoie son résultat.",
    "t:etat()", "\"suspendue\", \"en cours\", \"terminee\" ou \"erreur\".",
    "t:annuler()", "Arrête une tâche suspendue.",
    "c:envoyer(valeur)", "Envoie une valeur (attend si le canal est plein).",
    "c:recevoir([delai])", "Reçoit une valeur (attend si vide) ; nul après le délai.",
    "c:nombre()", "Nombre de valeurs en attente."]))

#
# thread
#

type
  MsgQueue = ref object
    lock: Lock
    cond: Cond
    items: Deque[string]

  ThreadData = object
    code, path: string
    args: seq[string]
    toChild, toParent: MsgQueue
    output, errput: proc (s: string) {.closure.}
    stop: ptr Atomic[bool]
    done: ptr Atomic[bool]
    error: ptr string

  LThread* = ref object of LUser
    thr: ptr Thread[ThreadData]
    toChild, toParent: MsgQueue
    stop: ptr Atomic[bool]
    done: ptr Atomic[bool]
    error: ptr string
    joined: bool

  ChildLink = ref object of RootObj
    toChild, toParent: MsgQueue

var threadMethods {.threadvar.}: LTable

proc newQueue(): MsgQueue =
  result = MsgQueue(items: initDeque[string]())
  initLock(result.lock)
  initCond(result.cond)

proc push(q: MsgQueue, s: string) =
  withLock q.lock:
    q.items.addLast s
    signal(q.cond)

proc pop(L: Interp, q: MsgQueue, timeout: float): (bool, string) =
  let deadline = if timeout >= 0: epochTime() + timeout else: Inf
  L.blocking:
    while true:
      acquire(q.lock)
      if q.items.len > 0:
        let s = q.items.popFirst()
        release(q.lock)
        return (true, s)
      release(q.lock)
      if epochTime() >= deadline or L.stopRequested(): break
      sleep(5)
  (false, "")

proc encodeMsg(L: Interp, v: Value): string = $L.toJsonNode(v)
proc decodeMsg(L: Interp, s: string): Value = fromJsonNode(parseJson(s), upperKeys = false)

proc threadMain(d: ThreadData) {.thread.} =
  {.cast(gcsafe).}:
    let L = newFullInterp()
    L.output = d.output
    L.errput = d.errput
    L.args = d.args
    L.scriptPath = d.path
    L.ext["thread.link"] = ChildLink(toChild: d.toChild, toParent: d.toParent)
    L.parentStop = d.stop          # th:stop() et l'arrêt du parent se propagent
    L.enter()
    try:
      var args: seq[Value]
      for s in d.args: args.add strV(s)
      if d.path.len > 0: discard L.runFile(d.path, args)
      else: discard L.runMain(L.load(d.code, "fil"), args)
    except LexisError as e:
      d.error[] = e.msg
    except SyntaxError as e:
      d.error[] = e.msg
    except LexisStop:
      discard
    except CatchableError as e:
      d.error[] = e.msg
    L.shutdown()
    L.leave()
    d.done[].store(true)

proc checkThread(L: Interp, a: seq[Value], fname: string): LThread =
  checkUser[LThread](L, a, 1, fname, "fil")

proc joinThreadObj(t: LThread) =
  if not t.joined:
    joinThread(t.thr[])
    deallocShared(t.thr)
    t.joined = true

proc openThread(L: Interp): Value =
  threadMethods = newLib()
  let tm = threadMethods
  tm.fn "envoyer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkThread(a, "envoyer")
    t.toChild.push(L.encodeMsg(arg(a, 2)))
  tm.fn "recevoir", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkThread(a, "recevoir")
    let (ok, s) = L.pop(t.toParent, L.optNum(a, 2, "recevoir", -1))
    if not ok: return @[nilV]
    @[L.decodeMsg(s)]
  tm.fn "actif", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[boolV(not L.checkThread(a, "actif").done[].load())]
  tm.fn "joindre", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkThread(a, "joindre")
    L.blocking:
      while not t.done[].load(): sleep(5)
    t.joinThreadObj()
    if t.error[].len > 0: rtError("fil : " & t.error[])
    @[boolV(true)]
  tm.fn "arreter", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.checkThread(a, "arreter").stop[].store(true)

  let m = newLib()
  proc startThread(L: Interp, code, path: string, args: seq[string]): Value =
    let t = LThread(toChild: newQueue(), toParent: newQueue())
    t.stop = createShared(Atomic[bool])
    t.done = createShared(Atomic[bool])
    t.error = createShared(string)
    t.thr = createShared(Thread[ThreadData])
    let d = ThreadData(code: code, path: path, args: args, toChild: t.toChild, toParent: t.toParent,
                       output: L.output, errput: L.errput, stop: t.stop, done: t.done, error: t.error)
    createThread(t.thr[], threadMain, d)
    L.closers.add proc () =
      t.stop[].store(true)
      t.joinThreadObj()
    L.wrap(t, "fil", threadMethods)
  m.fn "demarrer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let src = L.checkStr(a, 1, "demarrer")
    var args: seq[string]
    for i in 2 .. a.len: args.add L.tostr(a[i - 1])
    if src.toLowerAscii.endsWith(".prg") and '\n' notin src:
      let p = if isAbsolute(src) or L.scriptPath.len == 0: src else: L.scriptPath.parentDir / src
      return @[startThread(L, "", p, args)]
    @[startThread(L, src, "", args)]
  # côté enfant : communication avec le parent
  m.fn "envoyer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let link = L.ext.getOrDefault("thread.link")
    if link.isNil: rtError("fil.envoyer : à utiliser dans un fil (sinon f:envoyer)")
    ChildLink(link).toParent.push(L.encodeMsg(arg(a, 1)))
  m.fn "recevoir", proc (L: Interp, a: seq[Value]): seq[Value] =
    let link = L.ext.getOrDefault("thread.link")
    if link.isNil: rtError("fil.recevoir : à utiliser dans un fil (sinon f:recevoir)")
    let (ok, s) = L.pop(ChildLink(link).toChild, L.optNum(a, 1, "recevoir", -1))
    if not ok: return @[nilV]
    @[L.decodeMsg(s)]
  m.fn "estenfant", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[boolV(not L.ext.getOrDefault("thread.link").isNil)]
  tableV(m)

registerPackage PackageDef(name: "fil", open: openThread,
  description: "Fils d'exécution du système (interpréteurs séparés, messages)",
  docs: docs("fil", [
    "fil.demarrer(code_ou_fichier, ...)", "Lance un fil qui exécute du code Lexis+ (chaîne) ou un fichier .prg, avec ses propres variables ; renvoie le fil.",
    "fil.envoyer(valeur)", "Dans le fil : envoie une valeur au programme qui l'a lancé.",
    "fil.recevoir([delai])", "Dans le fil : reçoit une valeur (nul après le délai).",
    "fil.estenfant()", "Vrai dans un fil lancé par fil.demarrer.",
    "f:envoyer(valeur)", "Envoie une valeur au fil (tables, chaînes, nombres, logiques).",
    "f:recevoir([delai])", "Reçoit une valeur du fil ; nul après le délai.",
    "f:actif()", "Vrai tant que le fil s'exécute.",
    "f:joindre()", "Attend la fin du fil ; son erreur éventuelle est relevée.",
    "f:arreter()", "Demande l'arrêt du fil."]))
