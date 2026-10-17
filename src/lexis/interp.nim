# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - évaluateur de Lexis+
#
# Interpréteur par parcours d'arbre. Points notables :
#   - les variables locales sont les cases du cadre d'appel ; les autres noms
#     sont cherchés à l'exécution : champ de la zone courante, variable
#     globale (table SESSION), procédure ;
#   - un appel par nom cherche une procédure, puis une globale appelable,
#     puis une fonction intégrée ;
#   - les tâches (coroutines) s'exécutent chacune sur un thread, avec passage
#     de relais par sémaphores : une seule s'exécute à la fois ;
#   - un « verrou global » (gil) sérialise l'accès à l'interpréteur entre le
#     programme principal et les gestionnaires d'événements de l'interface ;
#   - le débogueur est appelé avant chaque instruction (points d'arrêt,
#     pas à pas, pas principal, sortie de procédure).

import std/[tables, sets, locks, atomics, math, strutils, times, os, algorithm]
from std/unicode import runeLen, toUpper
import core, parser, lexer, zones, duck

export core

type
  ExecResult = enum erNormal, erBreak, erContinue, erReturn

#
# Erreurs
#

proc ctx*(): Ctx =
  if curCtx.isNil: curCtx = Ctx()
  curCtx

proc position*(): (string, int) =
  ## (fichier, ligne) de l'instruction Lexis+ en cours.
  let c = ctx()
  for i in countdown(c.frames.high, 0):
    let f = c.frames[i]
    if not f.proto.isNil: return (f.proto.source, f.line)
  ("", 0)

proc where*(): string =
  let (s, l) = position()
  if s.len > 0: s & ":" & $l & ": " else: ""

proc traceback*(c: Ctx = nil): string =
  let c = if c.isNil: ctx() else: c
  result = "pile d'appels :"
  var n = 0
  for i in countdown(c.frames.high, 0):
    let f = c.frames[i]
    if f.proto.isNil:
      result.add "\n  [intégrée] " & f.fnName
    else:
      result.add "\n  " & f.proto.source & ":" & $f.line & " dans " &
        (if f.fnName.len > 0: f.fnName else: f.proto.name)
    inc n
    if n > 30:
      result.add "\n  ..."
      break

proc raiseValue*(v: Value) {.noreturn.} =
  ## Lève une erreur Lexis+ ; v est ce que reçoit « capturer ».
  let (s, l) = position()
  var e = newException(LexisError, (if s.len > 0: s & ":" & $l & ": " else: "") & display(v))
  e.value = v
  e.source = s
  e.line = l
  e.traceback = traceback()
  raise e

proc rtError*(msg: string) {.noreturn.} =
  ## Erreur d'exécution, avec la position de l'instruction en cours.
  raiseValue(strV(msg))

#
# Interpréteur
#

proc newInterp*(): Interp =
  result = Interp(globals: newLTable(), loaded: newLTable(), registry: newLTable(),
                  builtins: newLTable(), procs: initTable[string, Value](),
                  maxDepth: 200, gil: newSem(1),
                  ext: initTable[string, RootRef](), startTime: epochTime())
  result.output = proc (s: string) = stdout.write s
  result.errput = proc (s: string) = stderr.write s
  result.input = proc (prompt: string): (bool, string) =
    if prompt.len > 0: stdout.write prompt
    try: (true, stdin.readLine()) except EOFError, IOError: (false, "")
  result.onError = proc (msg: string) = stderr.writeLine msg

proc enter*(L: Interp) = L.gil.wait()
proc leave*(L: Interp) = L.gil.post()

template blocking*(L: Interp, body: untyped) =
  # Libère l'interpréteur pendant une attente (pause, réseau, boucle de l'interface...).
  L.leave()
  try:
    body
  finally:
    L.enter()

proc stopRequested*(L: Interp): bool {.inline.} =
  L.stopFlag.load(moRelaxed) or (not L.parentStop.isNil and L.parentStop[].load(moRelaxed))

proc requestStop*(L: Interp) =
  ## Demande l'arrêt du programme (vérifié avant chaque instruction).
  L.stopFlag.store(true)

proc checkStop*(L: Interp) {.inline.} =
  if L.stopRequested(): raise newException(LexisStop, "exécution arrêtée")

#
# Métatables
#

proc getMeta*(L: Interp, v: Value): LTable =
  case v.kind
  of vkTable: v.t.meta
  of vkUser: v.u.meta
  else: nil

proc metaField*(L: Interp, v: Value, name: string): Value =
  ## name en majuscules (« __INDEX ») ; « __index » est aussi accepté.
  let m = L.getMeta(v)
  if m.isNil: return nilV
  result = m.rawGet(name)
  if result.kind == vkNil: result = m.rawGet(name.toLowerAscii)

proc call*(L: Interp, f: Value, args: seq[Value]): seq[Value]

proc keyText(k: Value): string =
  if k.kind == vkStr: k.s.toLowerAscii else: display(k)

proc index*(L: Interp, obj, key: Value): Value =
  var o = obj
  for loop in 0 ..< 100:
    case o.kind
    of vkTable:
      let v = o.t.rawGet(key)
      if v.kind != vkNil: return v
      if o.t.meta.isNil: return nilV
      let h = L.metaField(o, "__INDEX")
      case h.kind
      of vkNil: return nilV
      of vkFunc: return first(L.call(h, @[o, key]))
      else: o = h
    of vkUser:
      let h = L.metaField(o, "__INDEX")
      if h.kind == vkNil: rtError("l'objet " & o.u.tname & " n'a pas de champ « " & keyText(key) & " »")
      if h.kind == vkFunc: return first(L.call(h, @[o, key]))
      o = h
    of vkNil:
      rtError("indexation d'une valeur nulle (clef « " & keyText(key) & " »)")
    else:
      rtError("indexation impossible d'une valeur de type " & typeName(o) & " (clef « " & keyText(key) & " »)")
  rtError("__index : chaîne de métatables trop longue (cycle ?)")

proc setIndex*(L: Interp, obj, key, val: Value) =
  var o = obj
  for loop in 0 ..< 100:
    case o.kind
    of vkTable:
      if o.t.meta.isNil or o.t.rawGet(key).kind != vkNil:
        try: o.t.rawSet(key, val)
        except ValueError as e: rtError(e.msg)
        return
      let h = L.metaField(o, "__NEWINDEX")
      case h.kind
      of vkNil:
        try: o.t.rawSet(key, val)
        except ValueError as e: rtError(e.msg)
        return
      of vkFunc:
        discard L.call(h, @[o, key, val])
        return
      else: o = h
    of vkUser:
      let h = L.metaField(o, "__NEWINDEX")
      if h.kind == vkNil: rtError("l'objet " & o.u.tname & " ne peut pas être modifié (champ « " & keyText(key) & " »)")
      if h.kind == vkFunc:
        discard L.call(h, @[o, key, val])
        return
      o = h
    else:
      rtError("affectation indexée sur une valeur de type " & typeName(o) & " (table attendue)")
  rtError("__newindex : chaîne de métatables trop longue (cycle ?)")

proc tostr*(L: Interp, v: Value): string =
  ## Texte d'une valeur (utilise __tostring) ; nul donne "".
  if v.kind in {vkTable, vkUser}:
    let h = L.metaField(v, "__TOSTRING")
    if h.kind != vkNil: return rawToString(first(L.call(h, @[v])))
  rawToString(v)

#
# Opérations
#

proc wrapAdd(a, b: int64): int64 {.inline.} = cast[int64](cast[uint64](a) + cast[uint64](b))
proc wrapSub(a, b: int64): int64 {.inline.} = cast[int64](cast[uint64](a) - cast[uint64](b))
proc wrapMul(a, b: int64): int64 {.inline.} = cast[int64](cast[uint64](a) * cast[uint64](b))

const metaNames: array[BinOp, string] = ["__ADD", "__SUB", "__MUL", "__DIV", "__MOD", "__POW",
  "__CONCAT", "__EQ", "", "__LT", "__LE", "", "", ""]

proc tryMeta(L: Interp, a, b: Value, ev: string, res: var Value): bool =
  var h = L.metaField(a, ev)
  if h.kind == vkNil: h = L.metaField(b, ev)
  if h.kind == vkNil: return false
  res = first(L.call(h, @[a, b]))
  true

proc toNumber*(v: Value, ok: var bool): Value =
  ## Nombre d'une valeur : nombres, chaînes numériques (virgule décimale admise), logiques (1 / 0).
  ok = true
  case v.kind
  of vkInt, vkNum: v
  of vkBool: intV(if v.b: 1 else: 0)
  of vkStr:
    let (good, n) = str2number(v.s)
    if good: n
    else:
      ok = false
      nilV
  else:
    ok = false
    nilV

proc numArg(v: Value, op: string): Value =
  var ok: bool
  result = toNumber(v, ok)
  if not ok:
    rtError("opération « " & op & " » : nombre attendu, " & typeName(v) &
            (if v.kind == vkStr: " \"" & v.s & "\"" else: "") & " reçu")

proc arith*(L: Interp, op: BinOp, a, b: Value): Value =
  if a.kind in {vkTable, vkUser} or b.kind in {vkTable, vkUser}:
    var r: Value
    if L.tryMeta(a, b, metaNames[op], r): return r
    if op == opConcat and a.kind != vkTable and b.kind != vkTable and
       (L.metaField(a, "__TOSTRING").kind != vkNil or L.metaField(b, "__TOSTRING").kind != vkNil):
      return strV(L.tostr(a) & L.tostr(b))
    rtError("opération « " & $op & " » impossible sur une " & (if a.kind in {vkTable, vkUser}: typeName(a) else: typeName(b)) &
            " (métaméthode " & metaNames[op].toLowerAscii & " absente)")
  if op == opConcat or (op == opAdd and (a.kind == vkStr or b.kind == vkStr)):
    return strV(rawToString(a) & rawToString(b))
  let x = numArg(a, $op)
  let y = numArg(b, $op)
  if x.kind == vkInt and y.kind == vkInt:
    case op
    of opAdd: return intV(wrapAdd(x.i, y.i))
    of opSub: return intV(wrapSub(x.i, y.i))
    of opMul: return intV(wrapMul(x.i, y.i))
    of opMod:
      if y.i == 0: rtError("modulo par zéro")
      var r = x.i mod y.i
      if r != 0 and ((r < 0) != (y.i < 0)): r += y.i
      return intV(r)
    of opDiv:
      if y.i == 0: rtError("division par zéro")
      if x.i mod y.i == 0: return intV(x.i div y.i)
      return numV(float64(x.i) / float64(y.i))
    else: discard
  let fx = if x.kind == vkInt: float64(x.i) else: x.n
  let fy = if y.kind == vkInt: float64(y.i) else: y.n
  case op
  of opAdd: numV(fx + fy)
  of opSub: numV(fx - fy)
  of opMul: numV(fx * fy)
  of opDiv:
    if fy == 0: rtError("division par zéro")
    numV(fx / fy)
  of opMod:
    if fy == 0: rtError("modulo par zéro")
    numV(fx - floor(fx / fy) * fy)
  of opPow: numV(pow(fx, fy))
  else: rtError("opérateur inconnu " & $op)

proc equals*(L: Interp, a, b: Value): bool =
  if rawEquals(a, b): return true
  if a.kind == b.kind and a.kind in {vkTable, vkUser}:
    var r: Value
    if L.tryMeta(a, b, "__EQ", r): return truthy(r)
  false

proc lessThan*(L: Interp, a, b: Value, orEqual: bool, opText: string): bool =
  if a.isNumber and b.isNumber:
    if a.kind == vkInt and b.kind == vkInt: return (if orEqual: a.i <= b.i else: a.i < b.i)
    let x = if a.kind == vkInt: float64(a.i) else: a.n
    let y = if b.kind == vkInt: float64(b.i) else: b.n
    return (if orEqual: x <= y else: x < y)
  if a.kind == vkStr and b.kind == vkStr:
    return (if orEqual: a.s <= b.s else: a.s < b.s)
  var r: Value
  if L.tryMeta(a, b, (if orEqual: "__LE" else: "__LT"), r): return truthy(r)
  rtError("comparaison « " & opText & " » impossible entre " & typeName(a) & " et " & typeName(b))

proc length*(L: Interp, v: Value): Value =
  case v.kind
  of vkStr: intV(v.s.runeLen)
  of vkTable, vkUser:
    let h = L.metaField(v, "__LEN")
    if h.kind != vkNil: return first(L.call(h, @[v]))
    if v.kind == vkTable: return intV(v.t.rawLen)
    rtError("« # » : table ou chaîne attendue, objet reçu")
  else: rtError("« # » : table ou chaîne attendue, " & typeName(v) & " reçu")

proc negate(L: Interp, v: Value): Value =
  if v.kind in {vkTable, vkUser}:
    let h = L.metaField(v, "__UNM")
    if h.kind == vkNil: rtError("négation impossible d'une table (__unm absente)")
    return first(L.call(h, @[v, v]))
  let x = numArg(v, "-")
  if x.kind == vkInt: intV(wrapSub(0, x.i)) else: numV(-x.n)

#
# Débogueur
#

proc newDebugger*(): Debugger =
  result = Debugger(breakpoints: initTable[string, HashSet[int]]())
  initLock(result.lock)
  initCond(result.cond)

proc setBreakpoints*(d: Debugger, source: string, lines: seq[int]) =
  withLock d.lock:
    d.breakpoints[source] = toHashSet(lines)

proc command*(d: Debugger, mode: StepMode) =
  ## Reprise après une pause (smRun, smInto, smOver, smOut).
  withLock d.lock:
    d.cmd = mode
    d.resumed = true
    broadcast(d.cond)

proc requestPause*(d: Debugger) =
  withLock d.lock: d.mode = smPause

proc debugLine(L: Interp, fr: Frame, s: Stmt) =
  let d = L.dbg
  let c = ctx()
  let depth = c.frames.len
  let src = fr.proto.source
  var pause = false
  withLock d.lock:
    let sp = cast[pointer](s)
    let fresh = fr.line != d.lastLine or depth != d.lastDepth or src != d.lastSource or sp == d.lastStmt
    d.lastStmt = sp
    if fresh:
      d.lastLine = fr.line
      d.lastDepth = depth
      d.lastSource = src
      let bp = d.breakpoints.hasKey(src) and fr.line in d.breakpoints[src]
      case d.mode
      of smRun: pause = bp
      of smInto, smPause: pause = true
      of smOver: pause = bp or depth <= d.depth
      of smOut: pause = bp or depth < d.depth
  if not pause or L.stopRequested(): return     # arrêt demandé : ne plus se mettre en pause.
  if not d.onPause.isNil: d.onPause(L, c)
  withLock d.lock:
    d.resumed = false
    while not d.resumed and not L.stopRequested(): wait(d.cond, d.lock)
    d.mode = d.cmd
    d.depth = depth
  L.checkStop()

#
# Noms et appels
#

template zoneGuard(body: untyped) =
  ## Les erreurs de base et de zone deviennent des erreurs Lexis+ positionnées.
  try:
    body
  except ZoneError as e: rtError(e.msg)
  except DuckError as e: rtError("sql : " & e.msg)

proc lookupName*(L: Interp, name: string): Value =
  ## Lecture d'un nom non local : champ de la zone courante, globale, procédure.
  if name == "SESSION": return tableV(L.globals)
  let z = L.currentZone
  if not z.isNil:
    let i = z.fieldIndex(name)
    if i >= 0:
      zoneGuard: return L.field(z, i)
  result = L.globals.rawGet(name)
  if result.kind == vkNil: result = L.procs.getOrDefault(name, nilV)
  if result.kind == vkNil and not L.autoload.isNil: result = L.autoload(L, name)

proc aliasField(L: Interp, alias, name: string): Value =
  ## alias->champ ; m->nom désigne une variable (comme en dBase) s'il n'y a pas de zone M.
  if alias == "M" and not L.zoneState.zones.hasKey("M"):
    if name == "SESSION": return tableV(L.globals)
    return L.globals.rawGet(name)
  zoneGuard:
    let z = L.zoneByAlias(alias)
    let i = z.fieldIndex(name)
    if i < 0: rtError("champ inconnu " & alias & "->" & name)
    return L.field(z, i)

proc callable*(L: Interp, v: Value): bool =
  v.kind == vkFunc or (v.kind in {vkTable, vkUser} and L.metaField(v, "__CALL").kind != vkNil)

proc callName*(L: Interp, name: string, args: seq[Value]): seq[Value] =
  ## Appel par nom : procédure, puis globale appelable, puis fonction intégrée.
  let p = L.procs.getOrDefault(name, nilV)
  if p.kind != vkNil: return L.call(p, args)
  let g = L.globals.rawGet(name)
  if L.callable(g): return L.call(g, args)
  let b = L.builtins.rawGet(name)
  if b.kind != vkNil: return L.call(b, args)
  rtError("procédure ou fonction inconnue : " & name.toLowerAscii)

proc procRef*(L: Interp, name: string): Value =
  result = L.procs.getOrDefault(name, nilV)
  if result.kind == vkNil: result = L.builtins.rawGet(name)
  if result.kind == vkNil: rtError("procédure inconnue : " & name)

#
# Évaluation
#

proc eval(L: Interp, fr: Frame, e: Expr): Value
proc execBlock(L: Interp, fr: Frame, body: seq[Stmt]): ExecResult

proc callLexis(L: Interp, fn: LFunc, args: seq[Value]): seq[Value] =
  let c = ctx()
  if c.frames.len >= L.maxDepth: rtError("profondeur d'appel maximale atteinte (récursion infinie ?)")
  let p = fn.proto
  let fr = Frame(proto: p, fnName: fn.name, slots: newSeq[Cell](p.nslots), line: p.line)
  for i in 0 ..< p.nparams:
    fr.slots[i] = Cell(v: (if i < args.len: args[i] else: nilV))
  if p.usesArgs: fr.args = args
  c.frames.add fr
  try:
    if L.execBlock(fr, p.body) == erReturn: result = @[fr.ret]
  finally:
    discard c.frames.pop()

proc call*(L: Interp, f: Value, args: seq[Value]): seq[Value] =
  if f.kind == vkFunc:
    if f.f.native:
      let c = ctx()
      if c.frames.len >= L.maxDepth: rtError("profondeur d'appel maximale atteinte")
      c.frames.add Frame(fnName: f.f.name, line: 0)
      try:
        result = f.f.nfn(L, args)
      finally:
        discard c.frames.pop()
    else:
      result = L.callLexis(f.f, args)
    return
  if f.kind in {vkTable, vkUser}:
    let h = L.metaField(f, "__CALL")
    if h.kind != vkNil: return L.call(h, @[f] & args)
  rtError("appel impossible d'une valeur de type " & typeName(f))

proc evalArgs(L: Interp, fr: Frame, exprs: seq[Expr]): seq[Value] =
  for e in exprs: result.add L.eval(fr, e)

proc callExpr(L: Interp, fr: Frame, e: Expr): seq[Value] =
  if e.kind == ekMethod:
    let o = L.eval(fr, e.mobj)
    let m = L.index(o, strV(e.mname))
    if m.kind == vkNil: rtError("méthode inconnue : " & e.mname.toLowerAscii)
    var args = @[o]
    for a in e.margs: args.add L.eval(fr, a)
    return L.call(m, args)
  let f = e.fn
  case f.kind
  of ekName:
    return L.callName(f.gname, L.evalArgs(fr, e.args))
  of ekLocal:
    let c = fr.slots[f.slot]
    let v = if c.isNil: nilV else: c.v
    if L.callable(v): return L.call(v, L.evalArgs(fr, e.args))
    return L.callName(cle(f.vname), L.evalArgs(fr, e.args))
  else:
    let fv = L.eval(fr, f)
    return L.call(fv, L.evalArgs(fr, e.args))

proc eval(L: Interp, fr: Frame, e: Expr): Value =
  case e.kind
  of ekNil: nilV
  of ekTrue: boolV(true)
  of ekFalse: boolV(false)
  of ekInt: intV(e.ival)
  of ekNum: numV(e.nval)
  of ekStr: strV(e.sval)
  of ekLocal:
    let c = fr.slots[e.slot]
    if c.isNil: nilV else: c.v
  of ekName: L.lookupName(e.gname)
  of ekProcRef: L.procRef(e.gname)
  of ekField: L.aliasField(e.alias, e.field)
  of ekIndex: L.index(L.eval(fr, e.obj), L.eval(fr, e.key))
  of ekCall, ekMethod: first(L.callExpr(fr, e))
  of ekParen: L.eval(fr, e.e)
  of ekAnd:
    let a = L.eval(fr, e.a)
    if not truthy(a): a else: L.eval(fr, e.b)
  of ekOr:
    let a = L.eval(fr, e.a)
    if truthy(a): a else: L.eval(fr, e.b)
  of ekIif:
    if truthy(L.eval(fr, e.cnd)): L.eval(fr, e.yes) else: L.eval(fr, e.no)
  of ekNot: boolV(not truthy(L.eval(fr, e.e)))
  of ekNeg: L.negate(L.eval(fr, e.e))
  of ekLen: L.length(L.eval(fr, e.e))
  of ekBin:
    let a = L.eval(fr, e.lhs)
    let b = L.eval(fr, e.rhs)
    case e.op
    of opEq: boolV(L.equals(a, b))
    of opNe: boolV(not L.equals(a, b))
    of opLt: boolV(L.lessThan(a, b, false, "<"))
    of opLe: boolV(L.lessThan(a, b, true, "<="))
    of opGt: boolV(L.lessThan(b, a, false, ">"))
    of opGe: boolV(L.lessThan(b, a, true, ">="))
    of opIn: boolV(L.tostr(b).contains(L.tostr(a)))
    else: L.arith(e.op, a, b)
  of ekTable:
    let t = newLTable()
    var n = 1
    for it in e.items:
      if it.keyed:
        let k = L.eval(fr, it.key)
        if k.kind == vkNil: rtError("clef de table nulle")
        try: t.rawSet(k, L.eval(fr, it.val))
        except ValueError as ex: rtError(ex.msg)
      else:
        let v = L.eval(fr, it.val)
        if v.kind != vkNil: t.rawSet(intV(n), v)
        inc n
    tableV(t)

proc assign(L: Interp, fr: Frame, target: Expr, v: Value) =
  case target.kind
  of ekLocal:
    if fr.slots[target.slot].isNil: fr.slots[target.slot] = Cell(v: v)
    else: fr.slots[target.slot].v = v
  of ekName:
    if target.gname == "SESSION": rtError("la table SESSION ne peut pas être remplacée")
    L.globals.rawSet(target.gname, v)
  of ekIndex: L.setIndex(L.eval(fr, target.obj), L.eval(fr, target.key), v)
  else: rtError("cible d'affectation invalide")

proc setLocal(fr: Frame, slot: int, v: Value) {.inline.} =
  if fr.slots[slot].isNil: fr.slots[slot] = Cell(v: v) else: fr.slots[slot].v = v

proc getLocal(fr: Frame, slot: int): Value {.inline.} =
  let c = fr.slots[slot]
  if c.isNil: nilV else: c.v

proc loopStep(L: Interp, fr: Frame, body: seq[Stmt], stop: var bool): bool =
  ## Un tour de boucle ; vrai s'il faut remonter un « retourner ».
  case L.execBlock(fr, body)
  of erBreak: stop = true
  of erReturn:
    stop = true
    return true
  else: discard
  false

proc searchFrom(L: Interp, fr: Frame, z: Zone, start: int, cond: Expr) =
  var p = start
  while p < z.keys.len:
    moveTo(z, p)
    if truthy(L.eval(fr, cond)):
      z.found = true
      return
    inc p
  moveTo(z, z.keys.len)
  z.found = false

proc execZone(L: Interp, fr: Frame, s: Stmt): ExecResult =
  case s.zk
  of zkUse:
    if s.e[0].isNil:
      let zs = L.zoneState
      if zs.current != "": L.closeZone(zs.current)
    else:
      let table = L.tostr(L.eval(fr, s.e[0]))
      let alias = if s.name != "": s.name else: toUpper(table)
      let order = if s.e[1].isNil: "" else: L.tostr(L.eval(fr, s.e[1]))
      let filter = if s.e[2].isNil: "" else: L.tostr(L.eval(fr, s.e[2]))
      zoneGuard: L.openZone(table, alias, order, filter)
  of zkSelect:
    let a = L.tostr(L.eval(fr, s.e[0]))
    zoneGuard: L.selectZone(a)
  of zkClose: L.closeZone(s.name)
  of zkGo:
    zoneGuard:
      let z = L.requireZone
      case s.name
      of "haut": moveTo(z, 0)
      of "bas": moveTo(z, max(0, z.keys.len - 1))
      else:
        var ok: bool
        let p = int(toInteger(numArg(L.eval(fr, s.e[0]), "aller"), ok))
        moveTo(z, (if p < 1 or p > z.keys.len: z.keys.len else: p - 1))
  of zkSkip:
    zoneGuard:
      let z = L.requireZone
      var d = 1
      if s.e.len > 0:
        var ok: bool
        d = int(toInteger(numArg(L.eval(fr, s.e[0]), "sauter"), ok))
      moveTo(z, z.pos + d)
  of zkAppend, zkReplace:
    var vals: seq[Value]
    for x in s.e: vals.add L.eval(fr, x)
    zoneGuard:
      let z = L.requireZone
      if s.zk == zkAppend: L.appendRecord(z, s.names, vals)
      else: L.replaceRecord(z, s.names, vals)
  of zkDelete:
    zoneGuard: L.deleteRecord(L.requireZone)
  of zkLocate:
    var z: Zone
    zoneGuard: z = L.requireZone
    z.locCond = s.e[0]
    zoneGuard: L.searchFrom(fr, z, 0, s.e[0])
  of zkContinue:
    var z: Zone
    zoneGuard: z = L.requireZone
    if z.locCond.isNil: rtError("« continuer » sans « localiser » préalable")
    zoneGuard: L.searchFrom(fr, z, z.pos + 1, z.locCond)
  of zkSeek:
    let v = L.eval(fr, s.e[0])
    zoneGuard: L.seekRecord(L.requireZone, v)
  of zkScan:
    var z: Zone
    zoneGuard: z = L.requireZone
    moveTo(z, 0)
    var stop = false
    let zs = L.zoneState
    while not stop and z.pos < z.keys.len:
      var ok = true
      if not s.e[0].isNil:
        let saved = zs.current
        zs.current = z.alias
        try: ok = truthy(L.eval(fr, s.e[0]))
        finally: zs.current = saved
      if ok:
        if L.loopStep(fr, s.body, stop): return erReturn
        if stop: break
      if z.deleted:
        z.deleted = false
        moveTo(z, z.pos)
      else: moveTo(z, z.pos + 1)
  of zkCount:
    var z: Zone
    zoneGuard: z = L.requireZone
    var total = 0
    if s.e[0].isNil: total = z.keys.len
    else:
      let saved = z.pos
      for p in 0 ..< z.keys.len:
        moveTo(z, p)
        if truthy(L.eval(fr, s.e[0])): inc total
      moveTo(z, saved)
    L.assign(fr, s.e[1], intV(total))
  of zkRefresh:
    zoneGuard: L.reload(L.requireZone)
  erNormal

proc execStmt(L: Interp, fr: Frame, s: Stmt): ExecResult =
  fr.line = s.line
  if not L.dbg.isNil and L.dbg.active: L.debugLine(fr, s)
  if L.stopRequested(): raise newException(LexisStop, "exécution arrêtée")
  case s.kind
  of skLocal:
    let v = if s.e.len > 0: L.eval(fr, s.e[0]) else: nilV
    fr.slots[s.slots[0]] = Cell(v: v)
  of skAssign:
    L.assign(fr, s.e[0], L.eval(fr, s.e[1]))
  of skStore:
    let v = L.eval(fr, s.e[0])
    for i in 1 ..< s.e.len: L.assign(fr, s.e[i], v)
  of skCompound:
    let t = s.e[0]
    if t.kind == ekIndex:
      let o = L.eval(fr, t.obj)
      let k = L.eval(fr, t.key)
      let old = L.index(o, k)
      let rhs = L.eval(fr, s.e[1])
      L.setIndex(o, k, L.arith(s.op, old, rhs))
    else:
      let old = L.eval(fr, t)
      let rhs = L.eval(fr, s.e[1])
      L.assign(fr, t, L.arith(s.op, old, rhs))
  of skCall:
    discard L.callExpr(fr, s.e[0])
  of skPrint:
    var parts: seq[string]
    for x in s.e: parts.add L.tostr(L.eval(fr, x))
    L.output(parts.join(" ") & (if s.flag: "\n" else: ""))
  of skIf:
    for i, c in s.e:
      if truthy(L.eval(fr, c)): return L.execBlock(fr, s.blocks[i])
    if s.blocks.len > s.e.len: return L.execBlock(fr, s.blocks[^1])
  of skWhile:
    var stop = false
    while not stop and truthy(L.eval(fr, s.e[0])):
      if L.loopStep(fr, s.body, stop): return erReturn
      fr.line = s.line
  of skNumFor:
    let a = numArg(L.eval(fr, s.e[0]), "pour")
    let b = numArg(L.eval(fr, s.e[1]), "pour")
    let st = if s.e.len > 2: numArg(L.eval(fr, s.e[2]), "pour") else: intV(1)
    let slot = s.slots[0]
    if a.kind == vkInt and st.kind == vkInt:
      if st.i == 0: rtError("pas nul dans « pour »")
      let lim = if b.kind == vkInt: float64(b.i) else: b.n
      fr.setLocal(slot, a)
      var stop = false
      while not stop:
        var ok: bool
        let cur = toNumber(fr.getLocal(slot), ok)
        if not ok: rtError("la variable de « pour » doit rester un nombre")
        let x = if cur.kind == vkInt: float64(cur.i) else: cur.n
        if (st.i > 0 and x > lim) or (st.i < 0 and x < lim): break
        if L.loopStep(fr, s.body, stop): return erReturn
        if stop: break
        let now = toNumber(fr.getLocal(slot), ok)
        if not ok: rtError("la variable de « pour » doit rester un nombre")
        fr.setLocal(slot, (if now.kind == vkInt: intV(wrapAdd(now.i, st.i)) else: numV(now.n + float64(st.i))))
        fr.line = s.line
    else:
      let x0 = if a.kind == vkInt: float64(a.i) else: a.n
      let x1 = if b.kind == vkInt: float64(b.i) else: b.n
      let dx = if st.kind == vkInt: float64(st.i) else: st.n
      if dx == 0: rtError("pas nul dans « pour »")
      fr.setLocal(slot, numV(x0))
      var stop = false
      while not stop:
        var ok: bool
        let cur = toNumber(fr.getLocal(slot), ok)
        if not ok: rtError("la variable de « pour » doit rester un nombre")
        let x = if cur.kind == vkInt: float64(cur.i) else: cur.n
        if (dx > 0 and x > x1) or (dx < 0 and x < x1): break
        if L.loopStep(fr, s.body, stop): return erReturn
        if stop: break
        let now = toNumber(fr.getLocal(slot), ok)
        let nx = if now.kind == vkInt: float64(now.i) else: now.n
        fr.setLocal(slot, numV(nx + dx))
        fr.line = s.line
  of skForEach:
    let v = L.eval(fr, s.e[0])
    var stop = false
    case v.kind
    of vkNil: discard
    of vkTable:
      for (k, x) in v.t.snapshotPairs:
        if s.slots.len == 1: fr.setLocal(s.slots[0], x)
        else:
          fr.setLocal(s.slots[0], k)
          fr.setLocal(s.slots[1], x)
        if L.loopStep(fr, s.body, stop): return erReturn
        if stop: break
        fr.line = s.line
    of vkFunc, vkUser:
      # itérateur : appelé jusqu'à ce qu'il renvoie nul
      while not stop:
        let r = L.call(v, @[])
        if first(r).kind == vkNil: break
        if s.slots.len == 1: fr.setLocal(s.slots[0], r[0])
        else:
          fr.setLocal(s.slots[0], r[0])
          fr.setLocal(s.slots[1], (if r.len > 1: r[1] else: nilV))
        if L.loopStep(fr, s.body, stop): return erReturn
        fr.line = s.line
    else: rtError("« pour chaque » : table attendue, " & typeName(v) & " reçu")
  of skBreak: return erBreak
  of skContinue: return erContinue
  of skReturn:
    fr.ret = if s.e.len > 0: L.eval(fr, s.e[0]) else: nilV
    return erReturn
  of skTry:
    let c = ctx()
    let depth = c.frames.len
    try:
      return L.execBlock(fr, s.blocks[0])
    except LexisStop:
      raise
    except LexisError as e:
      c.frames.setLen(depth)
      if s.blocks.len > 1:
        if s.slots[0] >= 0: fr.setLocal(s.slots[0], (if e.value.kind == vkNil: strV(e.msg) else: e.value))
        return L.execBlock(fr, s.blocks[1])
    except CatchableError as e:
      c.frames.setLen(depth)
      if s.blocks.len > 1:
        if s.slots[0] >= 0: fr.setLocal(s.slots[0], strV(e.msg))
        return L.execBlock(fr, s.blocks[1])
  of skError:
    let v = L.eval(fr, s.e[0])
    raiseValue(if v.kind in {vkTable, vkUser}: v else: strV(L.tostr(v)))
  of skParams:
    for i, slot in s.slots:
      fr.setLocal(slot, (if i < fr.args.len: fr.args[i] else: nilV))
  of skGlobal:
    if s.e.len > 0: L.globals.rawSet(s.name, L.eval(fr, s.e[0]))
  of skFree:
    for t in s.e:
      if t.kind == ekName and t.gname == "SESSION": rtError("la table SESSION ne peut pas être supprimée")
      L.assign(fr, t, nilV)
  of skNewTable:
    var v = tableV(newLTable())
    if s.e.len > 1:
      v = L.eval(fr, s.e[1])
      if v.kind != vkTable: rtError("« nouvelle table » : la valeur initiale doit être une table")
    L.assign(fr, s.e[0], v)
  of skInsert:
    let v = L.eval(fr, s.e[0])
    let t = L.eval(fr, s.e[1])
    if t.kind != vkTable: rtError("« inserer » : table attendue, " & typeName(t) & " reçu")
    case s.name
    of "position":
      var ok: bool
      let p = int(toInteger(numArg(L.eval(fr, s.e[2]), "position"), ok))
      try: t.t.insertAt(p, v)
      except ValueError as e: rtError(e.msg)
    of "clef": L.setIndex(t, L.eval(fr, s.e[2]), v)
    else:
      if v.kind != vkNil: t.t.rawSet(intV(t.t.rawLen + 1), v)
  of skRemove:
    let t = L.eval(fr, s.e[0])
    if t.kind != vkTable: rtError("« retirer » : table attendue, " & typeName(t) & " reçu")
    var r: Value
    case s.name
    of "position":
      var ok: bool
      let p = int(toInteger(numArg(L.eval(fr, s.e[1]), "position"), ok))
      try: r = t.t.removeAt(p)
      except ValueError as e: rtError(e.msg)
    of "clef":
      let k = L.eval(fr, s.e[1])
      r = t.t.rawGet(k)
      if k.kind != vkNil: t.t.rawSet(k, nilV)
    else:
      try: r = t.t.removeAt(t.t.rawLen)
      except ValueError as e: rtError(e.msg)
    if not s.e[2].isNil: L.assign(fr, s.e[2], r)
  of skAssoc:
    let t = L.eval(fr, s.e[0])
    if t.kind != vkTable: rtError("association de procédure : table attendue, " & typeName(t) & " reçu")
    let p = L.procs.getOrDefault(s.name, nilV)
    if p.kind == vkNil: rtError("procédure inconnue : " & s.name)
    t.t.rawSet(s.name2, p)
  of skSetMeta:
    let t = L.eval(fr, s.e[0])
    let m = L.eval(fr, s.e[1])
    if t.kind != vkTable: rtError("fixermetatable : table attendue")
    if m.kind == vkNil: t.t.meta = nil
    elif m.kind == vkTable: t.t.meta = m.t
    else: rtError("fixermetatable : la métatable doit être une table ou nul")
  of skSql:
    let sql = L.tostr(L.eval(fr, s.e[0]))
    var params: seq[Value]
    for i in 2 ..< s.e.len: params.add L.eval(fr, s.e[i])
    var r: QueryResult
    zoneGuard: r = L.query(sql, params)
    if not s.e[1].isNil: L.assign(fr, s.e[1], rowsToValue(r))
  of skZone:
    return L.execZone(fr, s)
  erNormal

proc execBlock(L: Interp, fr: Frame, body: seq[Stmt]): ExecResult =
  for s in body:
    let r = L.execStmt(fr, s)
    if r != erNormal: return r
  erNormal

#
# Chargement des programmes
#

proc readSource*(L: Interp, path: string): string =
  if not L.sourceProvider.isNil:
    let (ok, s) = L.sourceProvider(path)
    if ok: return s
  readFile(path)

proc registerProgram*(L: Interp, prog: Program, allowMain: bool): Value =
  ## Enregistre les procédures d'un fichier ; renvoie le programme principal.
  for p in prog.procs:
    let old = L.procs.getOrDefault(p.name, nilV)
    if old.kind == vkFunc and not old.f.native and old.f.proto.source != p.source:
      synErr(p.source, p.line, "procédure " & p.name & " définie deux fois (" &
             old.f.proto.source & ":" & $old.f.proto.line & ")")
    L.procs[p.name] = funcV(LFunc(name: p.name, native: false, proto: p))
  if not allowMain and prog.main.body.len > 0:
    synErr(prog.main.source, prog.main.body[0].line,
           "instruction hors procédure : seul le fichier principal peut contenir des instructions en tête")
  funcV(LFunc(name: "programme principal", native: false, proto: prog.main))

proc load*(L: Interp, src, source: string): Value =
  ## Compile du code (et enregistre ses procédures) ; lève SyntaxError.
  L.registerProgram(parseChunk(src, source), true)

proc projectFiles*(mainPath: string): seq[string] =
  ## Fichiers .prg du dossier du programme (sous-dossiers compris, sauf cachés).
  let dir = mainPath.parentDir
  if dir.len == 0 or not dirExists(dir): return
  for f in walkDirRec(dir):
    let rel = relativePath(f, dir).replace('\\', '/')
    if rel.startsWith(".") or "/." in rel: continue
    if f.toLowerAscii.endsWith(".prg") and normalizedPath(absolutePath(f)) != normalizedPath(absolutePath(mainPath)):
      result.add f
  result.sort()

proc loadProgram*(L: Interp, mainPath: string): Value =
  ## Charge le fichier principal et les autres fichiers .prg de son dossier.
  let main = L.load(L.readSource(mainPath), mainPath)
  for f in projectFiles(mainPath):
    discard L.registerProgram(parseChunk(L.readSource(f), f), false)
  main

proc runMain*(L: Interp, main: Value, args: seq[Value]): seq[Value] =
  ## Exécute le programme principal, ou la procédure PRINCIPAL s'il est vide.
  if main.f.proto.body.len > 0: return L.call(main, args)
  let p = L.procs.getOrDefault("PRINCIPAL", nilV)
  if p.kind != vkNil: return L.call(p, args)
  raise newException(LexisError, main.f.proto.source & ":1: rien à exécuter : écrivez des " &
                     "instructions en tête du fichier principal, ou une procédure PRINCIPAL")

proc runFile*(L: Interp, path: string, args: seq[Value] = @[]): seq[Value] =
  ## Exécute un programme (le verrou global doit être détenu).
  L.runMain(L.loadProgram(path), args)

#
# Tâches (coroutines : une par thread, une seule active à la fois)
#

proc coMain(co: Coroutine) {.thread.} =
  {.cast(gcsafe).}:
    curCtx = co.ctx
    try:
      co.transfer = co.L.call(co.fn, co.transfer)
    except LexisStop:
      co.killed = true
    except LexisError as e:
      co.errored = true
      co.errVal = strV(e.msg)
    except SyntaxError as e:
      co.errored = true
      co.errVal = strV(e.msg)
    except CatchableError as e:
      co.errored = true
      co.errVal = strV(e.msg)
    co.status = csDead
    co.yieldSem.post()

proc newCoroutine*(L: Interp, fn: Value): Coroutine =
  result = Coroutine(L: L, fn: fn, status: csSuspended, tname: "tache",
                     resumeSem: newSem(), yieldSem: newSem())
  result.ctx = Ctx(co: result)
  L.coroutines.add result

proc resume*(L: Interp, co: Coroutine, args: seq[Value]): (bool, seq[Value]) =
  if co.status == csDead: return (false, @[strV("impossible de reprendre une tâche terminée")])
  if co.status != csSuspended: return (false, @[strV("impossible de reprendre une tâche non suspendue")])
  let caller = ctx()
  if not caller.co.isNil: caller.co.status = csNormal
  co.status = csRunning
  co.transfer = args
  if not co.started:
    co.started = true
    co.thr = createShared(Thread[Coroutine])
    createThread(co.thr[], coMain, co)
  else:
    co.resumeSem.post()
  co.yieldSem.wait()
  if not caller.co.isNil: caller.co.status = csRunning
  if co.killed: raise newException(LexisStop, "exécution arrêtée")
  if co.errored:
    co.errored = false
    return (false, @[co.errVal])
  (true, move co.transfer)

proc yieldCo*(L: Interp, vals: seq[Value]): seq[Value] =
  let co = ctx().co
  if co.isNil: rtError("céder la main n'est possible que dans une tâche")
  co.transfer = vals
  co.status = csSuspended
  co.yieldSem.post()
  co.resumeSem.wait()
  if co.killed or L.stopRequested(): raise newException(LexisStop, "tâche fermée")
  co.status = csRunning
  move co.transfer

proc closeCoroutine*(co: Coroutine) =
  ## Termine le thread d'une tâche suspendue.
  if co.started and co.status == csSuspended:
    co.killed = true
    co.resumeSem.post()
    co.yieldSem.wait()
  if not co.thr.isNil:
    joinThread(co.thr[])
    deallocShared(co.thr)
    co.thr = nil
  co.status = csDead

proc shutdown*(L: Interp) =
  ## Libère tâches et ressources des paquets (fin d'exécution).
  for co in L.coroutines: closeCoroutine(co)
  L.coroutines.setLen(0)
  for c in L.closers:
    try: c() except CatchableError: discard
  L.closers.setLen(0)

proc elapsed*(L: Interp): float = epochTime() - L.startTime
