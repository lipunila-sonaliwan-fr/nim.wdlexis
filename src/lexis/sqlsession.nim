# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - sessions SQL : requêtes simultanées, en arrière-plan, interruptibles
#
#   s = sessionsql()                    nouvelle connexion sur la base du programme
#   r = s:requete(sql, ...)             comme requete(), l'interpréteur reste libre
#   s:lancer(sql, @FIN, [params])       en arrière-plan ; FIN(ev) à la fin :
#                                       ev.ok, ev.lignes, ev.colonnes, ev.types,
#                                       ev.message, ev.duree, ev.changees, ev.sql
#   s:annuler()  s:occupee()  s:duree()  s:sql()  s:fermer()
#   interromprebase()                   interrompt la requête en cours de la base
#
# Chaque session a sa propre connexion DuckDB sur la même base : mêmes tables et
# mêmes bases attachées, mais USE, SET et tables temporaires propres. Une session
# exécute une requête à la fois ; plusieurs sessions travaillent en même temps.

import std/[locks, times, tables, strutils]
import core, interp, api, duck, zones

type
  SqlSession* = ref object of LUser
    owner: Interp
    conn: Connection
    lock: Lock
    cv: Cond
    busy, closed, pending: bool
    started: float
    sql: string
    params: seq[DbCell]
    handler: Value
    thr: ptr Thread[SqlSession]

var sessionMethods {.threadvar.}: LTable

proc resultValue(L: Interp, r: QueryResult, ev: LTable) =
  ev.set "lignes", rowsToValue(r)
  let cols = newLTable()
  for i, c in r.columns: cols.rawSet(intV(i + 1), strV(c))
  ev.set "colonnes", tableV(cols)
  let tys = newLTable()
  for i, t in r.types: tys.rawSet(intV(i + 1), strV(t))
  ev.set "types", tableV(tys)
  ev.set "changees", intV(r.changed)

proc runJob(s: SqlSession) {.thread.} =
  ## Fil de la session : attend une requête, l'exécute, appelle le gestionnaire de fin.
  {.cast(gcsafe).}:
    while true:
      withLock s.lock:
        while not s.pending and not s.closed: wait(s.cv, s.lock)
        if s.closed: return
        s.pending = false
      var ok = true
      var msg = ""
      var r: QueryResult
      try:
        r = s.conn.exec(s.sql, s.params)
      except CatchableError as e:
        ok = false
        msg = e.msg
      let duree = epochTime() - s.started
      let L = s.owner
      if L.stopRequested() or s.closed:
        withLock s.lock: s.busy = false
        continue
      L.enter()
      try:
        var h: Value
        withLock s.lock:
          s.busy = false
          h = s.handler
          s.handler = nilV
        if h.kind != vkNil and not s.closed:
          curCtx = Ctx()
          let ev = newLTable()
          ev.set "ok", boolV(ok)
          ev.set "message", strV(msg)
          ev.set "duree", numV(duree)
          ev.set "sql", strV(s.sql)
          if ok: L.resultValue(r, ev)
          discard L.call(h, @[tableV(ev)])
      except LexisStop: discard
      except LexisError as e: L.onError(e.msg & "\n" & e.traceback)
      except Exception as e: L.onError("erreur interne dans une fin de requête (sessionsql) : " & e.msg)
      finally:
        L.leave()

proc checkSession(L: Interp, a: seq[Value], fname: string): SqlSession =
  let v = arg(a, 1)
  if v.kind != vkUser or not (v.u of SqlSession): rtError("« " & fname & " » : appelez-la avec « : » (session:" & fname & "(...))")
  result = SqlSession(v.u)
  if result.closed: rtError("session SQL fermée")

proc reserve(s: SqlSession, sql: string) =
  withLock s.lock:
    if s.busy: rtError("session SQL occupée : une requête est déjà en cours")
    s.busy = true
    s.started = epochTime()
    s.sql = sql

proc defineSessionMethods() =
  sessionMethods = newLib()
  let m = sessionMethods
  m.fn "requete", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSession(a, "requete")
    let sql = L.checkStr(a, 2, "requete")
    var cells: seq[DbCell]
    for i in 3 .. a.len: cells.add toCell(a[i - 1])
    s.reserve(sql)
    var r: QueryResult
    var err = ""
    L.blocking:
      try: r = s.conn.exec(sql, cells)
      except CatchableError as e: err = e.msg
    withLock s.lock: s.busy = false
    if err.len > 0: rtError("sql : " & err)
    @[rowsToValue(r)]
  m.fn "lancer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSession(a, "lancer")
    let sql = L.checkStr(a, 2, "requete")
    var cells: seq[DbCell]
    if arg(a, 4).kind == vkTable:
      let t = a[3].t
      for i in 1 .. t.rawLen: cells.add toCell(t.rawGet(intV(i)))
    s.reserve(sql)
    withLock s.lock:
      s.params = cells
      s.handler = arg(a, 3)
      s.pending = true
    if s.thr.isNil:
      s.thr = createShared(Thread[SqlSession])
      createThread(s.thr[], runJob, s)
    signal(s.cv)
    @[boolV(true)]
  m.fn "annuler", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSession(a, "annuler")
    var b = false
    withLock s.lock: b = s.busy
    if b: s.conn.interrupt()
    @[boolV(b)]
  m.fn "occupee", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSession(a, "occupee")
    var b = false
    withLock s.lock: b = s.busy
    @[boolV(b)]
  m.fn "duree", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSession(a, "duree")
    var d = 0.0
    withLock s.lock:
      if s.busy: d = epochTime() - s.started
    @[numV(d)]
  m.fn "sql", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkSession(a, "sql")
    var t = ""
    withLock s.lock: t = s.sql
    @[strV(t)]
  m.fn "fermer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let v = arg(a, 1)
    if v.kind != vkUser or not (v.u of SqlSession): rtError("session:fermer() attendu")
    let s = SqlSession(v.u)
    if s.closed: return @[]
    withLock s.lock: s.closed = true
    s.conn.interrupt()
    signal(s.cv)
    L.blocking:
      if not s.thr.isNil: joinThread(s.thr[])
    s.conn.close()

proc newSqlSession*(L: Interp): Value =
  if sessionMethods.isNil: defineSessionMethods()
  let s = SqlSession(owner: L, conn: L.connection.newSession())
  initLock(s.lock)
  initCond(s.cv)
  L.closers.add proc () =
    {.cast(gcsafe).}:
      withLock s.lock: s.closed = true
      s.conn.interrupt()
      signal(s.cv)
  L.wrap(s, "sessionsql", sessionMethods)

proc interruptBase*(L: Interp) =
  L.connection.interrupt()

proc queryReleased*(L: Interp, sql: string, params: openArray[Value]): QueryResult =
  ## Comme L.query, mais l'interpréteur est libéré pendant que DuckDB travaille :
  ## l'interface et les autres gestionnaires restent réactifs.
  var cells: seq[DbCell]
  for p in params: cells.add toCell(p)
  let c = L.connection
  var err = ""
  L.blocking:
    try: result = c.exec(sql, cells)
    except CatchableError as e: err = e.msg
  if err.len > 0: raise newException(ZoneError, "sql : " & err)
