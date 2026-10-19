# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet lexis : le langage vu depuis Lexis+ (outils d'atelier)
#
#   pbs = lexis.verifier(source, {nom = "principal.prg", projet = dossier})
#   pour chaque p dans pbs : ? p.ligne, p.genre, p.message
#
#   x = lexis.executer("principal.prg", {sursortie = @SORTIE, surfin = @FIN})
#   x:envoyer("réponse")          && pour saisir() / es.lire() du programme
#   x:arreter()
#
# lexis.executer lance le programme dans un interpréteur neuf, sur son propre fil :
# l'appelant reste libre (fenêtres réactives). Sa sortie, ses demandes de saisie
# et sa fin sont transmises par un fil « répartiteur » qui appelle les procédures
# sursortie(texte), surdemande(invite) et surfin(ev) sous le verrou de
# l'interpréteur appelant, comme les gestionnaires de l'interface ; sans
# sursortie, la sortie s'accumule et se lit avec x:lire().
#
# Les fenêtres créées par le programme exécuté vivent dans la même application.
#
# Débogage : lexis.executer(chemin, {deboguer = vrai, pasapas = vrai,
# pointsarret = {{source = chemin, lignes = {12, 30}}}, surpause = @PAUSE}).
# À chaque pause, surpause(ev) reçoit {source, ligne, pile, globales} : pile[1] est
# le cadre courant {nom, source, ligne, variables}, chaque variable {nom, valeur,
# genre, portee}. Le programme attend alors x:continuer(), x:pas(), x:passer() ou
# x:sortir() ; x:pause() l'interrompt à la prochaine instruction.

import std/[locks, strutils, os, sets, algorithm]
from std/unicode import runeLen
import ../lexis/[api, zones]
from ../lexis/lexer import SyntaxError
import ../ide/[lexislang, lexislint, langdocs]
from pkg_systeme import LexisExit
import pkg_interface    # openWindows, closeAllWindows : fenêtres du programme exécuté.

type
  EvKind = enum ekOut, ekAsk, ekEnd, ekPause

  VarData = object
    name, value, kind, scope: string

  FrameData = object
    name, source: string
    line: int                      # 1-based.
    vars: seq[VarData]

  PauseData = object
    source: string
    line: int
    frames: seq[FrameData]         # [0] = cadre courant.
    globals: seq[VarData]

  ExecEvent = object
    kind: EvKind
    text: string
    ok: bool
    source: string
    line: int
    pause: PauseData

  LExec* = ref object of LUser
    path: string
    args: seq[string]
    owner: Interp                  # interpréteur appelant (l'atelier).
    child: Interp                  # interpréteur du programme exécuté.
    lock: Lock
    cond: Cond                     # nouvel événement, nouvelle saisie ou arrêt.
    events: seq[ExecEvent]
    inputs: seq[string]
    pending: string                # sortie non lue (sans sursortie).
    running, waiting, stopping, ended: bool
    ownerClosed: bool              # l'appelant s'est terminé : plus aucun appel vers lui.
    endEv: ExecEvent
    hOut, hAsk, hEnd, hPause: Value
    debug, stepFirst, paused: bool
    breakpoints: seq[(string, seq[int])]    # posés avant le lancement.
    dbg: Debugger
    runner, dispatcher: ptr Thread[LExec]   # détachés : se terminent avec le programme.

var execMethods {.threadvar.}: LTable

#
# Analyse
#

proc lintOpts(o: LTable): LintOptions =
  LintOptions(flagGlobals: optField(o, "globales", true), unknownCalls: optField(o, "appelsinconnus", true))

proc sevName(s: Severity): string =
  case s
  of sevError: "erreur"
  of sevWarning: "avertissement"
  of sevInfo: "info"

proc verify(source, name, project: string, opts: LintOptions): seq[Value] =
  let lines = source.replace("\r\n", "\n").split('\n')
  let (toks, _) = lexAll(lines)
  let (_, local) = collectSymbols(lines, toks)
  var known = local
  if project.len > 0: known = indexProject(project).knownNamesFor(local)
  for d in lint(lines, toks, known, opts, name):
    # colonnes en caractères (1-based) pour Lexis+.
    let l = if d.line < lines.len: lines[d.line] else: ""
    let col = l[0 ..< min(d.col, l.len)].runeLen + 1
    result.add record({"ligne": intV(d.line + 1), "colonne": intV(col), "longueur": intV(d.len),
                       "genre": strV(sevName(d.sev)), "message": strV(d.msg)})

proc structureOf(source: string): seq[Value] =
  let lines = source.replace("\r\n", "\n").split('\n')
  let (toks, _) = lexAll(lines)
  let (syms, _) = collectSymbols(lines, toks)
  for s in syms:
    result.add record({"nom": strV(s.display), "genre": strV($s.kind),
                       "ligne": intV(s.line + 1), "colonne": intV(s.col + 1)})

proc listV(items: seq[Value]): Value =
  let t = newLTable(items.len)
  for v in items: t.arr.add v
  tableV(t)

#
# Exécution
#

proc push(x: LExec, e: ExecEvent) =
  withLock x.lock:
    if e.kind == ekOut and x.events.len > 0 and x.events[^1].kind == ekOut:
      x.events[^1].text.add e.text      # regroupe les sorties rapprochées.
    else:
      x.events.add e
    broadcast(x.cond)

proc locate(msg: string): (string, int) =
  ## « source.prg:ligne: message » -> (source, ligne)
  let i = msg.toLowerAscii.find(".prg:")
  if i < 0: return ("", 0)
  var k = i + 5
  var n = 0
  while k < msg.len and msg[k] in Digits:
    n = n * 10 + (ord(msg[k]) - ord('0'))
    inc k
  (msg[0 ..< i + 4], n)

#
# Instantané des variables (comme ide/session.nim, en données Nim : il est pris
# sur le fil du programme et converti en tables Lexis+ par le répartiteur).
#

proc short(L: Interp, v: Value, depth = 0): string =
  case v.kind
  of vkStr:
    var s = v.s
    if s.len > 80: s = s[0 ..< 80] & "…"
    "\"" & s.replace("\n", "\\n") & "\""
  of vkTable:
    if depth > 0: return "{…}"
    var parts: seq[string]
    var n = 0
    for k, x in v.t.pairs:
      inc n
      if parts.len < 8:
        let ks = if k.kind == vkStr: k.s else: "[" & rawToString(k) & "]"
        parts.add ks & "=" & L.short(x, depth + 1)
    "{" & parts.join(", ") & (if n > 8: ", … (" & $n & ")" else: "") & "}"
  of vkFunc:
    if v.f.native: "fonction intégrée " & v.f.name else: "@" & v.f.name
  of vkUser: rawToString(v)
  else: display(v)

proc kindOf(v: Value): string =
  case v.kind
  of vkInt: "entier"
  of vkNum: "décimal"
  else: typeName(v)

proc frameVars(L: Interp, f: Frame): seq[VarData] =
  if f.proto.isNil: return
  for i, c in f.slots:
    if not c.isNil and i < f.proto.slotNames.len:
      result.add VarData(name: f.proto.slotNames[i], value: L.short(c.v), kind: kindOf(c.v),
                         scope: (if i < f.proto.nparams: "paramètre" else: "locale"))

proc snapshot(L: Interp, c: Ctx, builtin: HashSet[string]): PauseData =
  for i in countdown(c.frames.high, 0):
    let f = c.frames[i]
    if f.proto.isNil: continue
    result.frames.add FrameData(name: (if f.fnName.len > 0: f.fnName else: f.proto.name),
                                source: f.proto.source, line: f.line, vars: L.frameVars(f))
  if result.frames.len > 0:
    result.source = result.frames[0].source
    result.line = result.frames[0].line
  for k, v in L.globals.pairs:
    if k.kind == vkStr and k.s notin builtin:
      result.globals.add VarData(name: k.s.toLowerAscii, value: L.short(v), kind: kindOf(v), scope: "globale")
  let z = L.currentZoneInfo()
  if z.len > 0:
    result.globals.add VarData(name: "zone", value: z, kind: "zone", scope: "base")
  result.globals.sort(proc (a, b: VarData): int = cmp(a.name, b.name))

proc varsV(vs: seq[VarData]): Value =
  let t = newLTable(vs.len)
  for v in vs:
    t.arr.add record({"nom": strV(v.name), "valeur": strV(v.value), "genre": strV(v.kind),
                      "portee": strV(v.scope)})
  tableV(t)

proc pauseV(p: PauseData): Value =
  let pile = newLTable(p.frames.len)
  for f in p.frames:
    pile.arr.add record({"nom": strV(f.name), "source": strV(f.source), "ligne": intV(f.line),
                         "variables": varsV(f.vars)})
  record({"source": strV(p.source), "ligne": intV(p.line), "pile": tableV(pile),
          "globales": varsV(p.globals)})

proc normSource(p: string): string =
  if p.len == 0: "" else: absolutePath(p).normalizedPath

proc runChild(x: LExec) {.thread.} =
  {.cast(gcsafe).}:
    let L = newInterp()
    L.hosted = true
    L.scriptPath = x.path
    L.args = x.args
    L.searchDirs = @[x.path.parentDir]
    openGlobals(L)
    var builtin = initHashSet[string]()
    for k, _ in L.globals.pairs:
      if k.kind == vkStr: builtin.incl k.s
    if x.debug:
      let d = newDebugger()
      d.active = true
      d.mode = if x.stepFirst: smInto else: smRun
      for (src, lines) in x.breakpoints: d.setBreakpoints(src, lines)
      d.onPause = proc (L: Interp, c: Ctx) =
        withLock x.lock: x.paused = true
        x.push(ExecEvent(kind: ekPause, pause: snapshot(L, c, builtin)))
      L.dbg = d
      withLock x.lock: x.dbg = d
    L.output = proc (s: string) = x.push(ExecEvent(kind: ekOut, text: s))
    L.errput = L.output
    L.onError = proc (msg: string) = x.push(ExecEvent(kind: ekOut, text: "\n[erreur] " & msg & "\n"))
    L.input = proc (prompt: string): (bool, string) =
      if prompt.len > 0: x.push(ExecEvent(kind: ekOut, text: prompt))
      x.push(ExecEvent(kind: ekAsk, text: prompt))
      L.blocking:
        withLock x.lock:
          x.waiting = true
          while x.inputs.len == 0 and not x.stopping: wait(x.cond, x.lock)
          x.waiting = false
          if x.inputs.len > 0:
            result = (true, x.inputs[0])
            x.inputs.delete(0)
          else: result = (false, "")
    withLock x.lock: x.child = L
    var ev = ExecEvent(kind: ekEnd, ok: true)
    L.enter()
    curCtx = Ctx()
    try:
      var vargs: seq[Value]
      for a in x.args: vargs.add strV(a)
      discard L.runFile(x.path, vargs)
      if L.openWindows() > 0:
        L.blocking:
          while L.openWindows() > 0 and not L.stopRequested(): sleep(30)
      ev.text = if L.stopRequested(): "arrêté" else: "terminé"
    except SyntaxError as e:
      ev = ExecEvent(kind: ekEnd, ok: false, text: e.msg, source: e.source, line: e.line)
    except LexisExit as e:
      ev.text = "systeme.quitter(" & $e.code & ")"
    except LexisStop:
      ev.text = "arrêté"
    except LexisError as e:
      ev = ExecEvent(kind: ekEnd, ok: false, text: e.msg & "\n" & e.traceback, source: e.source, line: e.line)
      if e.source.len == 0: (ev.source, ev.line) = locate(e.msg)
    except IOError, OSError:
      ev = ExecEvent(kind: ekEnd, ok: false, text: "lecture impossible : " & x.path)
    except Exception as e:
      ev = ExecEvent(kind: ekEnd, ok: false, text: "erreur interne : " & e.msg)
    try: L.closeAllWindows()
    except Exception: discard
    try: L.shutdown()
    except Exception: discard
    L.leave()
    withLock x.lock:
      x.child = nil
      x.running = false
    x.push(ev)

proc deliver(x: LExec, h: Value, args: seq[Value]) =
  ## Appelle un gestionnaire de l'interpréteur appelant (fil répartiteur).
  let L = x.owner
  template closed(): bool =
    (block:
      var c = false
      withLock x.lock: c = x.ownerClosed
      c)
  if h.kind == vkNil or closed() or L.stopRequested(): return
  L.enter()
  try:
    if closed(): return
    curCtx = Ctx()
    discard L.call(h, args)
  except LexisStop: discard
  except LexisError as e: L.onError(e.msg & "\n" & e.traceback)
  except Exception as e: L.onError("erreur interne dans un gestionnaire de lexis.executer : " & e.msg)
  finally:
    L.leave()

proc dispatch(x: LExec) {.thread.} =
  {.cast(gcsafe).}:
    var done = false
    while not done:
      var evs: seq[ExecEvent]
      withLock x.lock:
        while x.events.len == 0: wait(x.cond, x.lock)
        evs = x.events
        x.events.setLen(0)
      for e in evs:
        case e.kind
        of ekOut:
          if x.hOut.kind != vkNil: x.deliver(x.hOut, @[strV(e.text)])
          else:
            withLock x.lock: x.pending.add e.text
        of ekAsk: x.deliver(x.hAsk, @[strV(e.text)])
        of ekPause: x.deliver(x.hPause, @[pauseV(e.pause)])
        of ekEnd:
          withLock x.lock:
            x.endEv = e
            x.ended = true
          let t = newLTable()
          t.set "ok", boolV(e.ok)
          t.set "message", strV(e.text)
          t.set "source", strV(e.source)
          t.set "ligne", intV(e.line)
          x.deliver(x.hEnd, @[tableV(t)])
          done = true

proc resume(x: LExec, mode: StepMode) =
  var d: Debugger
  withLock x.lock:
    d = x.dbg
    x.paused = false
  if not d.isNil: d.command(mode)

proc stopExec(x: LExec) =
  var d: Debugger
  withLock x.lock:
    x.stopping = true
    d = x.dbg
    if not x.child.isNil:
      x.child.requestStop()
      try: x.child.closeAllWindows()
      except Exception: discard
    broadcast(x.cond)
  if not d.isNil: x.resume(smRun)    # débloque un programme en pause.

proc breakpointsOf(L: Interp, v: Value): seq[(string, seq[int])] =
  ## {{source = chemin, lignes = {…}}, …} ou {["chemin"] = {…}, …}
  proc lines(L: Interp, lv: Value): seq[int] =
    if lv.kind != vkTable: return
    for i in 1 .. lv.t.rawLen:
      var ok: bool
      let n = int(toInteger(lv.t.rawGet(intV(i)), ok))
      if ok: result.add n
  if v.kind != vkTable: return
  for i in 1 .. v.t.rawLen:
    let e = v.t.rawGet(intV(i))
    if e.kind == vkTable:
      result.add (normSource(optField(e.t, "source", "")), L.lines(e.t.rawGet(cle("lignes"))))
  for k, e in v.t.pairs:
    if k.kind == vkStr: result.add (normSource(k.s), L.lines(e))

proc checkExec(L: Interp, a: seq[Value], fname: string): LExec =
  checkUser[LExec](L, a, 1, fname, "exécution")

proc handlerOf(L: Interp, o: LTable, name: string): Value =
  if o.isNil: return nilV
  let v = o.rawGet(cle(name))
  if v.kind != vkNil and not L.callable(v):
    rtError("lexis.executer : « " & name & " » doit être une procédure (@NOM)")
  v

proc startExec(L: Interp, path: string, o: LTable): Value =
  var p = path
  if not p.isAbsolute:
    p = (if L.scriptPath.len > 0: L.scriptPath.parentDir else: getCurrentDir()) / p
  p = absolutePath(p).normalizedPath
  if not fileExists(p): rtError("lexis.executer : fichier introuvable « " & p & " »")
  let x = LExec(path: p, owner: L, running: true)
  if not o.isNil:
    let av = o.rawGet(cle("arguments"))
    if av.kind == vkTable:
      for i in 1 .. av.t.rawLen: x.args.add L.tostr(av.t.rawGet(intV(i)))
    elif av.kind != vkNil: x.args = L.tostr(av).splitWhitespace()
  x.hOut = L.handlerOf(o, "sursortie")
  x.hAsk = L.handlerOf(o, "surdemande")
  x.hEnd = L.handlerOf(o, "surfin")
  x.hPause = L.handlerOf(o, "surpause")
  x.debug = optField(o, "deboguer", false) or x.hPause.kind != vkNil
  x.stepFirst = optField(o, "pasapas", false)
  if not o.isNil: x.breakpoints = L.breakpointsOf(o.rawGet(cle("pointsarret")))
  initLock(x.lock)
  initCond(x.cond)
  x.runner = createShared(Thread[LExec])
  x.dispatcher = createShared(Thread[LExec])
  createThread(x.dispatcher[], dispatch, x)
  createThread(x.runner[], runChild, x)
  L.closers.add proc () =
    # Pas d'attente ici (l'appelant tient son verrou) : le programme est arrêté
    # et ses fils se terminent seuls.
    withLock x.lock: x.ownerClosed = true
    x.stopExec()
  L.wrap(x, "execution", execMethods)

#
# Paquet
#

proc openLexis(L: Interp): Value =
  initLangDocs()
  execMethods = newLib()
  let em = execMethods
  em.fn "envoyer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkExec(a, "envoyer")
    let s = L.optStr(a, 2, "envoyer", "")
    withLock x.lock:
      x.inputs.add s
      broadcast(x.cond)
  em.fn "lire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkExec(a, "lire")
    var s = ""
    withLock x.lock:
      s = x.pending
      x.pending = ""
    @[strV(s)]
  em.fn "actif", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkExec(a, "actif")
    var r = false
    withLock x.lock: r = not x.ended
    @[boolV(r)]
  em.fn "attentesaisie", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkExec(a, "attentesaisie")
    var r = false
    withLock x.lock: r = x.waiting
    @[boolV(r)]
  em.fn "arreter", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.checkExec(a, "arreter").stopExec()
  em.fn "attendre", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkExec(a, "attendre")
    L.blocking:
      while true:
        var e = false
        withLock x.lock: e = x.ended
        if e or L.stopRequested(): break
        sleep(10)
    var ok = false
    withLock x.lock: ok = x.endEv.ok
    @[boolV(ok)]
  em.fn "chemin", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(L.checkExec(a, "chemin").path)]
  # débogage
  em.fn "continuer", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.checkExec(a, "continuer").resume(smRun)
  em.fn "pas", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.checkExec(a, "pas").resume(smInto)
  em.fn "passer", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.checkExec(a, "passer").resume(smOver)
  em.fn "sortir", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.checkExec(a, "sortir").resume(smOut)
  em.fn "pause", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkExec(a, "pause")
    var d: Debugger
    withLock x.lock: d = x.dbg
    if d.isNil: rtError("x:pause : programme lancé sans « deboguer = vrai »")
    d.active = true
    d.requestPause()
  em.fn "enpause", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkExec(a, "enpause")
    var r = false
    withLock x.lock: r = x.paused
    @[boolV(r)]
  em.fn "pointsarret", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkExec(a, "pointsarret")
    let src = normSource(L.checkStr(a, 2, "pointsarret"))
    var lines: seq[int]
    let lv = arg(a, 3)
    if lv.kind == vkTable:
      for i in 1 .. lv.t.rawLen:
        var ok: bool
        let n = int(toInteger(lv.t.rawGet(intV(i)), ok))
        if ok: lines.add n
    var d: Debugger
    withLock x.lock: d = x.dbg
    if not d.isNil: d.setBreakpoints(src, lines)
  # Métatable enregistrée dès maintenant dans l'interpréteur : execMethods est
  # propre au fil courant, et lexis.executer est souvent appelé depuis un
  # gestionnaire d'événement (autre fil), où il serait vide.
  discard L.userMeta("execution", execMethods)

  let m = newLib()
  m.fn "verifier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let src = L.checkStr(a, 1, "verifier")
    let o = if arg(a, 2).kind == vkTable: a[1].t else: nil
    @[listV(verify(src, optField(o, "nom", "fichier"), optField(o, "projet", ""), lintOpts(o)))]
  m.fn "structure", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[listV(structureOf(L.checkStr(a, 1, "structure")))]
  m.fn "documentation", proc (L: Interp, a: seq[Value]): seq[Value] =
    let only = L.optStr(a, 1, "documentation", "")
    var items: seq[Value]
    for e in apiEntries():
      if only.len > 0 and cmpIgnoreCase(e.section, only) != 0: continue
      items.add record({"paquet": strV(e.section), "signature": strV(e.signature), "nom": strV(e.name),
                        "proprietaire": strV(e.owner), "methode": boolV(e.isMethod),
                        "description": strV(e.doc)})
    @[listV(items)]
  m.fn "paquets", proc (L: Interp, a: seq[Value]): seq[Value] =
    var items: seq[Value]
    for p in packages():
      items.add record({"nom": strV(p.name), "description": strV(p.description), "global": boolV(p.global)})
    @[listV(items)]
  m.fn "motscles", proc (L: Interp, a: seq[Value]): seq[Value] =
    var ks: seq[string]
    for k in Keywords: ks.add k
    @[toV(ks)]
  m.fn "outil", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Chemin d'un outil livré à côté du runtime (wdlexisgen...), nul s'il est absent.
    let n = L.checkStr(a, 1, "outil")
    for dir in [getAppDir(), getAppDir().parentDir]:
      for cand in [dir / n, dir / n.addFileExt(ExeExt)]:
        if fileExists(cand): return @[strV(cand)]
    @[nilV]
  m.fn "executer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.checkStr(a, 1, "executer")
    let o = if arg(a, 2).kind == vkTable: a[1].t else: nil
    @[L.startExec(path, o)]
  tableV(m)

const lexisDocs = [
  "lexis.verifier(source, [{nom=, projet=, globales=, appelsinconnus=}])", "Analyse un texte Lexis+ comme l'atelier (syntaxe, variables non déclarées, appels inconnus) ; renvoie la liste des problèmes {ligne, colonne, longueur, genre, message}. genre : erreur, avertissement, info ; projet : dossier dont les procédures sont connues.",
  "lexis.structure(source)", "Procédures, fonctions et variables globales définies dans un texte : liste de {nom, genre, ligne, colonne}.",
  "lexis.documentation([paquet])", "Documentation des fonctions intégrées et des paquets : liste de {paquet, signature, nom, proprietaire, methode, description}.",
  "lexis.paquets()", "Paquets disponibles : liste de {nom, description, global}.",
  "lexis.motscles()", "Mots-clés du langage.",
  "lexis.executer(chemin, [{arguments=, sursortie=, surdemande=, surfin=, deboguer=, pasapas=, pointsarret=, surpause=}])", "Exécute un programme .prg dans un interpréteur séparé, sans bloquer l'appelant ; renvoie l'exécution. sursortie : reçoit le texte écrit ; surdemande : reçoit l'invite d'une saisie ; surfin : reçoit {ok, message, source, ligne}. deboguer : active le débogueur ; pasapas : pause sur la première instruction ; pointsarret : {{source=, lignes={…}}} ; surpause : reçoit {source, ligne, pile, globales}.",
  "lexis.outil(nom)", "Chemin d'un outil livré à côté du runtime (wdlexisgen…) ; nul s'il est absent.",
  "x:envoyer(texte)", "Fournit une ligne à la saisie en attente du programme exécuté.",
  "x:lire()", "Sortie accumulée depuis la dernière lecture (sans sursortie).",
  "x:actif()", "Vrai tant que le programme s'exécute.",
  "x:attentesaisie()", "Vrai si le programme attend une saisie.",
  "x:arreter()", "Demande l'arrêt du programme (et ferme ses fenêtres).",
  "x:attendre()", "Attend la fin du programme ; renvoie vrai s'il s'est terminé sans erreur.",
  "x:chemin()", "Chemin du programme exécuté.",
  "x:continuer()", "Reprend l'exécution jusqu'au prochain point d'arrêt.",
  "x:pas()", "Pas à pas : exécute l'instruction et entre dans les procédures appelées.",
  "x:passer()", "Pas principal : exécute l'instruction sans entrer dans les procédures.",
  "x:sortir()", "Termine la procédure en cours puis s'arrête.",
  "x:pause()", "Interrompt le programme à la prochaine instruction.",
  "x:enpause()", "Vrai si le programme est en pause.",
  "x:pointsarret(source, lignes)", "Remplace les points d'arrêt d'un fichier pendant l'exécution."]

registerPackage PackageDef(name: "lexis", open: openLexis,
  description: "Le langage depuis Lexis+ : analyse, documentation et exécution de programmes",
  docs: docs("lexis", lexisDocs))
