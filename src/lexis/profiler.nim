# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - profileur de Lexis+ (temps et mémoire)
#
# Branché sur l'interpréteur par deux crochets (L.profCall, L.profLine) qui ne
# coûtent qu'un test de nullité quand le profileur est arrêté.
#   - procédures : appels, temps total (procédures appelées comprises) et temps
#     propre, tables créées (inclusif) ;
#   - lignes : passages et temps propre (jusqu'à l'instruction suivante) ;
#   - mémoire : mémoire résidente du processus au départ, à la fin, pic (échantillons
#     toutes les 20 ms), et tables créées.
# Les tâches (coroutines) ont chacune leur pile de mesures.

import std/[monotimes, times, tables, algorithm, strutils, os]
import core
from interp import ctx

when defined(windows):
  type ProcMemCounters {.pure.} = object
    cb: uint32
    pageFaultCount: uint32
    peakWorkingSetSize, workingSetSize, quotaPeakPagedPoolUsage, quotaPagedPoolUsage,
      quotaPeakNonPagedPoolUsage, quotaNonPagedPoolUsage, pagefileUsage, peakPagefileUsage: uint
  proc getCurrentProcess(): pointer {.importc: "GetCurrentProcess", stdcall, dynlib: "kernel32".}
  proc k32GetProcessMemoryInfo(p: pointer, c: ptr ProcMemCounters, cb: uint32): int32 {.
    importc: "K32GetProcessMemoryInfo", stdcall, dynlib: "kernel32".}
elif defined(macosx):
  type RUsage {.importc: "struct rusage", header: "<sys/resource.h>".} = object
    ru_maxrss: clong
  proc getrusage(who: cint, r: ptr RUsage): cint {.importc, header: "<sys/resource.h>".}

proc residentKb*(): int =
  ## Mémoire résidente du processus (Ko) ; 0 si inconnue.
  when defined(linux):
    try:
      let parts = readFile("/proc/self/statm").splitWhitespace()
      if parts.len > 1: return parseInt(parts[1]) * 4
    except CatchableError: discard
  elif defined(windows):
    var c: ProcMemCounters
    c.cb = uint32(sizeof(c))
    if k32GetProcessMemoryInfo(getCurrentProcess(), addr c, c.cb) != 0:
      return int(c.workingSetSize div 1024)
  elif defined(macosx):
    var r: RUsage
    if getrusage(0, addr r) == 0: return int(r.ru_maxrss div 1024)    # pic (octets sous macOS)
  0

type
  FnStat* = object
    name*, source*: string
    line*: int
    calls*: int
    total*, self*: float          # secondes
    tables*: int                  # tables créées pendant l'appel (procédures appelées comprises)

  LineStat* = object
    source*: string
    line*: int
    hits*: int
    time*: float

  Entry = object
    key: int
    start: MonoTime
    child: float
    tables: int

  CtxState = ref object
    stack: seq[Entry]
    lineStack: seq[(int, int)]    # ligne de l'appelant, reprise au retour
    lastKey: (int, int)           # (proto, ligne)
    lastT: MonoTime
    hasLast: bool

  Profiler* = ref object of RootObj
    running*: bool
    fnsByProto: Table[int, FnStat]
    linesByKey: Table[(int, int), LineStat]
    ctxs: Table[pointer, CtxState]
    lastCtx: pointer
    lastState: CtxState
    t0*, t1*: MonoTime
    rss0*, rss1*, rssPeak*: int
    tables0*, tables1*: int
    lastSample: MonoTime
    samples*: seq[(float, int)]   # (secondes, Ko)

proc sample(p: Profiler, now: MonoTime) =
  if (now - p.lastSample).inMilliseconds >= 20:
    p.lastSample = now
    let r = residentKb()
    if r > p.rssPeak: p.rssPeak = r
    if p.samples.len < 5000: p.samples.add ((now - p.t0).inNanoseconds.float / 1e9, r)

proc secs(d: Duration): float {.inline.} = d.inNanoseconds.float / 1e9

proc stateOf(p: Profiler): CtxState {.inline.} =
  let c = cast[pointer](ctx())
  if c == p.lastCtx and not p.lastState.isNil: return p.lastState
  result = p.ctxs.getOrDefault(c)
  if result.isNil:
    result = CtxState()
    p.ctxs[c] = result
  p.lastCtx = c
  p.lastState = result

proc addLineTime(p: Profiler, cs: CtxState, now: MonoTime) {.inline.} =
  if cs.hasLast:
    p.linesByKey.withValue(cs.lastKey, ls):
      ls.time += secs(now - cs.lastT)
  cs.lastT = now

proc onCall(p: Profiler, fr: Frame, enter: bool) =
  if fr.proto.isNil: return
  let now = getMonoTime()
  let cs = p.stateOf()
  let key = cast[int](fr.proto)
  if enter:
    p.addLineTime(cs, now)                       # la ligne de l'appel s'arrête ici
    cs.lineStack.add cs.lastKey
    p.fnsByProto.withValue(key, f):
      f.calls.inc
    do:
      p.fnsByProto[key] = FnStat(name: fr.fnName, source: fr.proto.source, line: fr.proto.line, calls: 1)
    {.cast(gcsafe).}:
      cs.stack.add Entry(key: key, start: now, tables: tablesCreated)
  elif cs.stack.len > 0:
    let e = cs.stack.pop()
    let dt = secs(now - e.start)
    var recursive = false
    for x in cs.stack:
      if x.key == e.key:
        recursive = true
        break
    p.fnsByProto.withValue(e.key, f):
      if not recursive: f.total += dt          # pas de double compte en récursion
      f.self += dt - e.child
      {.cast(gcsafe).}: f.tables += tablesCreated - e.tables
    if cs.stack.len > 0: cs.stack[^1].child += dt
    p.addLineTime(cs, now)                       # dernière ligne de la procédure
    if cs.lineStack.len > 0: cs.lastKey = cs.lineStack.pop()   # reprise sur la ligne de l'appel
  p.sample(now)

proc onLine(p: Profiler, fr: Frame, line: int) =
  let now = getMonoTime()
  let cs = p.stateOf()
  p.addLineTime(cs, now)
  let k = (cast[int](fr.proto), line)
  p.linesByKey.withValue(k, ls):
    ls.hits.inc
  do:
    p.linesByKey[k] = LineStat(source: (if fr.proto.isNil: "" else: fr.proto.source), line: line, hits: 1)
  cs.lastKey = k
  cs.hasLast = true
  if (now - p.lastSample).inMilliseconds >= 20: p.sample(now)

proc startProfiler*(L: Interp): Profiler =
  let p = Profiler(running: true, fnsByProto: initTable[int, FnStat](),
                   linesByKey: initTable[(int, int), LineStat](), ctxs: initTable[pointer, CtxState]())
  p.t0 = getMonoTime()
  p.lastSample = p.t0
  p.rss0 = residentKb()
  p.rssPeak = p.rss0
  {.cast(gcsafe).}: p.tables0 = tablesCreated
  L.prof = p
  L.profCall = proc (L: Interp, fr: Frame, enter: bool) =
    {.cast(gcsafe).}: p.onCall(fr, enter)
  L.profLine = proc (L: Interp, fr: Frame, line: int) =
    {.cast(gcsafe).}: p.onLine(fr, line)
  p

proc stopProfiler*(L: Interp): Profiler =
  if L.prof.isNil or not (L.prof of Profiler): return nil
  let p = Profiler(L.prof)
  L.profCall = nil
  L.profLine = nil
  L.prof = nil
  if p.running:
    p.running = false
    p.t1 = getMonoTime()
    p.rss1 = residentKb()
    if p.rss1 > p.rssPeak: p.rssPeak = p.rss1
    {.cast(gcsafe).}: p.tables1 = tablesCreated
    # dernière ligne de chaque fil
    for c, cs in p.ctxs: p.addLineTime(cs, p.t1)
  p

proc duration*(p: Profiler): float =
  secs((if p.running: getMonoTime() else: p.t1) - p.t0)

proc functionsByTime*(p: Profiler): seq[FnStat] =
  for _, f in p.fnsByProto: result.add f
  result.sort(proc (a, b: FnStat): int = cmp(b.self, a.self))

proc linesByTime*(p: Profiler, limit = 50): seq[LineStat] =
  for _, l in p.linesByKey: result.add l
  result.sort(proc (a, b: LineStat): int = cmp(b.time, a.time))
  if result.len > limit: result.setLen(limit)

proc ms(x: float): string = formatFloat(x * 1000, ffDecimal, 3)

proc sourceLine(path: string, line: int): string =
  try:
    var i = 0
    for l in lines(path):
      inc i
      if i == line: return l.strip
  except CatchableError: discard
  ""

proc report*(p: Profiler, top = 25): string =
  ## Rapport texte (temps en millisecondes).
  var o = "Profil Lexis+ - durée " & ms(p.duration) & " ms\n"
  o.add "Mémoire résidente : départ " & $p.rss0 & " Ko, fin " & $p.rss1 & " Ko, pic " & $p.rssPeak &
        " Ko ; tables créées : " & $(p.tables1 - p.tables0) & "\n\n"
  o.add alignLeft("procédure", 28) & align("appels", 9) & align("total ms", 13) & align("propre ms", 13) &
        align("% propre", 10) & align("tables", 9) & "  source\n"
  let d = max(p.duration, 1e-9)
  var n = 0
  for f in p.functionsByTime:
    inc n
    if n > top: break
    o.add alignLeft(f.name.toLowerAscii, 28) & align($f.calls, 9) & align(ms(f.total), 13) &
          align(ms(f.self), 13) & align(formatFloat(100 * f.self / d, ffDecimal, 1), 10) &
          align($f.tables, 9) & "  " & extractFilename(f.source) & ":" & $f.line & "\n"
  o.add "\nLignes les plus coûteuses :\n"
  o.add align("ms", 12) & align("passages", 10) & "  ligne\n"
  for l in p.linesByTime(top):
    o.add align(ms(l.time), 12) & align($l.hits, 10) & "  " & extractFilename(l.source) & ":" & $l.line &
          "  " & sourceLine(l.source, l.line) & "\n"
  o
