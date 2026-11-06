# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - atelier : session d'exécution et de débogage
#
# Une session exécute un programme Lexis+ (fichier principal et autres
# fichiers .prg du dossier) dans un interpréteur neuf, avec tous les paquets. Elle tourne sur le thread du gestionnaire qui l'a lancée (étape 6
# du tutoriel wdgui : un gestionnaire peut durer longtemps) ; les commandes
# Continuer / Pas à pas / Pause / Arrêter arrivent par d'autres gestionnaires.
#
# Les fenêtres créées par le programme (paquet interface) vivent dans l'application
# de l'IDE ; la session reste active tant qu'elles sont ouvertes.

import std/[locks, strutils, tables, sets, os, algorithm, atomics]
import ../lexis/[api, fonctions, zones]
import ../paquets/tous
from ../lexis/lexer import SyntaxError

type
  VarInfo* = object
    name*, value*, kind*, scope*: string

  FrameInfo* = object
    name*, source*: string
    line*: int                   # 1-based.
    vars*: seq[VarInfo]

  PauseInfo* = object
    source*: string
    line*: int                   # 1-based.
    frames*: seq[FrameInfo]      # [0] = cadre courant.
    globals*: seq[VarInfo]

  SessionHooks* = object
    output*: proc (s: string) {.closure, gcsafe.}
    input*: proc (prompt: string): (bool, string) {.closure, gcsafe.}
    paused*: proc (info: PauseInfo) {.closure, gcsafe.}
    finished*: proc (ok: bool, msg, source: string, line: int) {.closure, gcsafe.}
    sourceProvider*: proc (path: string): (bool, string) {.closure, gcsafe.}
    breakpoints*: proc (): seq[(string, seq[int])] {.closure, gcsafe.}

var sLock: Lock
var current: Interp
var pausedCtx: Ctx                 # contexte arrêté (débogueur en pause), pour modifier les variables.
initLock(sLock)

proc active*(): bool =
  {.cast(gcsafe).}:
    withLock sLock: result = not current.isNil

proc withCurrent(body: proc (L: Interp) {.closure.}) =
  {.cast(gcsafe).}:
    var L: Interp
    withLock sLock: L = current
    if not L.isNil: body(L)

#
# Instantané des variables
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

proc frameVars(L: Interp, f: Frame): seq[VarInfo] =
  if f.proto.isNil: return
  for i, c in f.slots:
    if not c.isNil and i < f.proto.slotNames.len:
      result.add VarInfo(name: f.proto.slotNames[i], value: L.short(c.v), kind: kindOf(c.v),
                         scope: (if i < f.proto.nparams: "paramètre" else: "locale"))

proc snapshot(L: Interp, c: Ctx, builtin: HashSet[string]): PauseInfo =
  for i in countdown(c.frames.high, 0):
    let f = c.frames[i]
    if f.proto.isNil: continue
    result.frames.add FrameInfo(name: (if f.fnName.len > 0: f.fnName else: f.proto.name),
                                source: f.proto.source, line: f.line, vars: L.frameVars(f))
  if result.frames.len > 0:
    result.source = result.frames[0].source
    result.line = result.frames[0].line
  for k, v in L.globals.pairs:
    if k.kind == vkStr and k.s notin builtin:
      result.globals.add VarInfo(name: k.s.toLowerAscii, value: L.short(v), kind: kindOf(v), scope: "globale")
  let z = L.currentZoneInfo()
  if z.len > 0:
    result.globals.add VarInfo(name: "zone", value: z, kind: "zone", scope: "base")
  result.globals.sort(proc (a, b: VarInfo): int = cmp(a.name, b.name))

#
# Commandes
#

proc parseLike(old: Value, text: string): (bool, Value, string) =
  # Nouvelle valeur du même type que l'ancienne (chaîne, entier ; aussi décimal et booléen).
  let t = text.strip
  case old.kind
  of vkStr:
    var s = text
    if s.len >= 2 and s[0] == '"' and s[^1] == '"': s = s[1 .. ^2].replace("\\n", "\n")
    (true, strV(s), "")
  of vkInt:
    try: (true, intV(parseBiggestInt(t)), "")
    except ValueError: (false, old, "entier attendu : « " & t & " »")
  of vkNum:
    try: (true, numV(parseFloat(t.replace(',', '.'))), "")
    except ValueError: (false, old, "nombre décimal attendu : « " & t & " »")
  of vkBool:
    case t.toLowerAscii
    of "vrai", "true", "1", "oui": (true, boolV(true), "")
    of "faux", "false", "0", "non": (true, boolV(false), "")
    else: (false, old, "vrai ou faux attendu")
  else: (false, old, "seules les chaînes, les entiers, les décimaux et les booléens se modifient ici")

proc setVariable*(frameIdx: int, name, scope, text: string): (bool, string) =
  # Modifie une variable du programme arrêté (débogueur en pause). frameIdx : cadre de
  # la pile (0 = courant, comme PauseInfo.frames) ; scope "globale" pour une globale.
  # Rend (vrai, nouvelle valeur affichée) ou (faux, message).
  {.cast(gcsafe).}:
    var L: Interp
    var c: Ctx
    withLock sLock:
      L = current
      c = pausedCtx
    if L.isNil or c.isNil or L.dbg.isNil: return (false, "le programme n'est pas en pause")
    if scope == "globale":
      for k, v in L.globals.pairs:
        if k.kind == vkStr and cmpIgnoreCase(k.s, name) == 0:
          let (ok, nv, msg) = parseLike(v, text)
          if not ok: return (false, msg)
          L.globals.rawSet(k, nv)
          return (true, L.short(nv))
      return (false, "variable globale introuvable : " & name)
    var n = 0
    for i in countdown(c.frames.high, 0):
      let f = c.frames[i]
      if f.proto.isNil: continue
      if n == frameIdx:
        for j, cell in f.slots:
          if not cell.isNil and j < f.proto.slotNames.len and cmpIgnoreCase(f.proto.slotNames[j], name) == 0:
            let (ok, nv, msg) = parseLike(cell.v, text)
            if not ok: return (false, msg)
            cell.v = nv
            return (true, L.short(nv))
        return (false, "variable introuvable : " & name)
      inc n
    (false, "cadre de pile introuvable")

proc debugCommand*(mode: StepMode) =
  withCurrent(proc (L: Interp) =
    if not L.dbg.isNil: L.dbg.command(mode))

proc pauseProgram*() =
  withCurrent(proc (L: Interp) =
    if not L.dbg.isNil:
      L.dbg.active = true
      L.dbg.requestPause())

proc stopProgram*() =
  withCurrent(proc (L: Interp) =
    L.requestStop()
    if not L.dbg.isNil: L.dbg.command(smRun)
    L.closeAllWindows())

proc updateBreakpoints*(source: string, lines: seq[int]) =
  # lines : 1-based.
  withCurrent(proc (L: Interp) =
    if not L.dbg.isNil: L.dbg.setBreakpoints(source, lines))

#
# Exécution
#

proc locate(msg: string): (string, int) =
  # « source:ligne: message » -> (source, ligne)
  var i = msg.toLowerAscii.find(".prg:")
  if i < 0:
    # source sans extension (document non enregistré) : chercher " :N: ".
    var j = 0
    while j < msg.len:
      let c = msg.find(':', j)
      if c < 0: break
      var k = c + 1
      var n = 0
      while k < msg.len and msg[k] in Digits:
        n = n * 10 + (ord(msg[k]) - ord('0'))
        inc k
      if k > c + 1 and k < msg.len and msg[k] == ':': return (msg[0 ..< c], n)
      j = c + 1
    return ("", 0)
  var k = i + 5
  var n = 0
  while k < msg.len and msg[k] in Digits:
    n = n * 10 + (ord(msg[k]) - ord('0'))
    inc k
  (msg[0 ..< i + 4], n)

proc runProgram*(path: string, args: seq[string], debug: bool, stepFirst: bool,
                 hooks: SessionHooks) =
  # Exécute `path` (bloquant). debug = débogueur actif ; stepFirst = pause
  # sur la première instruction.
  {.cast(gcsafe).}:
    var builtin = initHashSet[string]()
    let L = newInterp()
    L.hosted = true
    L.scriptPath = path
    L.args = args
    L.searchDirs = @[path.parentDir]
    openGlobals(L)
    for k, _ in L.globals.pairs:
      if k.kind == vkStr: builtin.incl k.s
    L.output = hooks.output
    L.errput = hooks.output
    L.input = hooks.input
    L.sourceProvider = hooks.sourceProvider
    L.onError = proc (msg: string) = hooks.output("\n[erreur] " & msg & "\n")
    if debug:
      let d = newDebugger()
      d.active = true
      d.mode = if stepFirst: smInto else: smRun
      for (src, lines) in hooks.breakpoints(): d.setBreakpoints(src, lines)
      d.onPause = proc (L: Interp, c: Ctx) =
        withLock sLock: pausedCtx = c
        hooks.paused(snapshot(L, c, builtin))
      L.dbg = d
    withLock sLock: current = L
    var ok = true
    var msg = ""
    var src = ""
    var line = 0
    L.enter()
    curCtx = Ctx()
    try:
      var vargs: seq[Value]
      for a in args: vargs.add strV(a)
      discard L.runFile(path, vargs)
      if L.openWindows() > 0:
        hooks.output("[le programme attend la fermeture de ses fenêtres]\n")
        L.blocking:
          while L.openWindows() > 0 and not L.stopRequested(): sleep(30)
      msg = if L.stopRequested(): "arrêté" else: "terminé"
    except SyntaxError as e:
      ok = false
      msg = e.msg
      src = e.source
      line = e.line
    except LexisExit as e:
      msg = "systeme.quitter(" & $e.code & ")"
    except LexisStop:
      msg = "arrêté"
    except LexisError as e:
      ok = false
      msg = e.msg & "\n" & e.traceback
      if e.source.len > 0: (src, line) = (e.source, e.line)
      else: (src, line) = locate(e.msg)
    except IOError, OSError:
      ok = false
      msg = "lecture impossible : " & path
    except CatchableError as e:
      ok = false
      msg = e.msg
    except Exception as e:
      # Defect de Nim (index, nil...) : sans cela, finished n'était jamais
      # appelé et l'atelier restait « en cours » avec les boutons figés.
      ok = false
      msg = "erreur interne : " & e.msg
    # La fin est TOUJOURS signalée à l'atelier, même si le nettoyage échoue.
    try: L.closeAllWindows()
    except Exception: discard
    try: L.shutdown()
    except Exception: discard
    L.leave()
    withLock sLock:
      current = nil
      pausedCtx = nil
    hooks.finished(ok, msg, src, line)
