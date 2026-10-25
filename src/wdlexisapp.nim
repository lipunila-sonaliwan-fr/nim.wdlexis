# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - runtime des applications générées (menu Exécuter > Générer l'application)
#
# Ce module n'est pas compilé chez l'utilisateur : il est transpilé en C une
# fois pour toutes, pour chaque cible, par `nimble rtc` (outils/rtc.nims) avec
# `--noMain:on`, puis livré dans le dossier `rtc/` de wdlexis+. Lors de la
# génération d'une application, wdlexis+ écrit un fichier C (`projet.c`) qui
# contient le projet (sources .prg, type d'application) et la fonction main(),
# et Zig compile et lie l'ensemble pour chaque cible.
#
# Deux variantes :
#   -d:wdlxGui   avec l'interface graphique wdgui (paquet « interface »)
#   (défaut)     sans interface graphique : console, service, bibliothèque
#
# Fonctions fournies par projet.c (C) :
#   wdlx_bundle_data() / wdlx_bundle_size()   le projet embarqué
#   wdlx_base_dir()                           dossier des ressources de l'application
# Fonctions exportées vers projet.c :
#   wdlx_main()                               point d'entrée des exécutables
#   wdlx_lib_*                                API des bibliothèques, publiée par projet.c
#                                             sous les noms wdlexis_initialiser,
#                                             wdlexis_appeler, wdlexis_liberer,
#                                             wdlexis_derniere_erreur, wdlexis_terminer,
#                                             wdlexis_version (après NimMain, une fois)

import std/[os, strutils, atomics, json, locks, tables]
when defined(wdlxGui):
  import wdgui
  import paquets/tous
else:
  import paquets/tous_sans_interface
import lexis/api
from lexis/lexer import SyntaxError
from lexis/fonctions import toJsonNode, fromJsonNode

const WdlxVersion* = "1.7.3"

proc wdlx_bundle_data(): ptr UncheckedArray[uint8] {.importc, cdecl.}
proc wdlx_bundle_size(): csize_t {.importc, cdecl.}
proc wdlx_base_dir(): cstring {.importc, cdecl.}

type
  AppKind = enum akConsole, akGraphique, akService, akBibliotheque
  Bundle = object
    kind: AppKind
    name, main, target: string
    files: seq[tuple[rel, src: string]]

#
# Projet embarqué
#
# Format (après désembrouillage, voir ide/toolchain.nim : bundleBytes) :
#   "WDLXB1" u32 n  puis n fois : u32 lgNom, nom, u32 lgDonnées, données
#   Entrées « @type », « @nom », « @principal », « @cible », puis « prg:<chemin relatif> ».
#

proc unscramble(data: var seq[uint8]) =
  # Embrouillage léger (les sources n'apparaissent pas en clair dans le binaire) ;
  # ce n'est pas un chiffrement.
  var k = 0x5EED1234'u32
  for i in 0 ..< data.len:
    k = k xor (k shl 13)
    k = k xor (k shr 17)
    k = k xor (k shl 5)
    data[i] = data[i] xor uint8(k and 0xFF)

proc readBundle(): Bundle =
  let n = int(wdlx_bundle_size())
  let p = wdlx_bundle_data()
  var data = newSeq[uint8](n)
  for i in 0 ..< n: data[i] = p[i]
  unscramble(data)
  var pos = 0
  proc u32(): int =
    if pos + 4 > data.len: raise newException(ValueError, "projet embarqué tronqué")
    result = int(data[pos]) or (int(data[pos+1]) shl 8) or (int(data[pos+2]) shl 16) or (int(data[pos+3]) shl 24)
    pos += 4
  proc str(): string =
    let l = u32()
    if pos + l > data.len: raise newException(ValueError, "projet embarqué tronqué")
    result = newString(l)
    for i in 0 ..< l: result[i] = char(data[pos + i])
    pos += l
  if n < 10 or cast[string](data[0 ..< 6]) != "WDLXB1":
    raise newException(ValueError, "projet embarqué invalide")
  pos = 6
  let count = u32()
  result.main = "principal.prg"
  for _ in 0 ..< count:
    let key = str()
    let val = str()
    case key
    of "@type":
      result.kind = case val
        of "graphique": akGraphique
        of "service": akService
        of "bibliotheque": akBibliotheque
        else: akConsole
    of "@nom": result.name = val
    of "@principal": result.main = val
    of "@cible": result.target = val
    else:
      if key.startsWith("prg:"): result.files.add (key[4 .. ^1], val)

var
  gBundle: Bundle
  gBase: string                  # dossier où se trouvent les ressources du projet.
  gStop: ptr Atomic[bool]        # drapeau d'arrêt de l'interpréteur principal (signaux, service).

proc baseDir(): string =
  let b = $wdlx_base_dir()
  if b.len > 0 and dirExists(b): b else: getAppDir()

proc installBundle() =
  gBundle = readBundle()
  gBase = normalizedPath(absolutePath(baseDir()))
  {.cast(gcsafe).}:
    for f in gBundle.files:
      embeddedSources.add (normalizedPath(gBase / f.rel.replace('/', DirSep)), f.src)

proc mainPath(): string = normalizedPath(gBase / gBundle.main.replace('/', DirSep))

proc newAppInterp(args: seq[string]): Interp =
  result = newInterp()
  result.args = args
  result.scriptPath = mainPath()
  result.searchDirs.add gBase
  if getAppDir() != gBase: result.searchDirs.add getAppDir()
  openGlobals(result)

#
# Messages d'erreur (une application graphique Windows n'a pas de console)
#

when defined(windows):
  proc MessageBoxW(h: pointer, text, caption: WideCString, flags: uint32): int32 {.
    stdcall, dynlib: "user32.dll", importc.}
  proc GetStdHandle(n: int32): pointer {.stdcall, dynlib: "kernel32.dll", importc.}

proc hasConsole(): bool =
  when defined(windows):
    let h = GetStdHandle(-11'i32)      # STD_OUTPUT_HANDLE
    h != nil and cast[int](h) != -1
  else: true

proc fatal(msg: string) =
  when defined(windows):
    if gBundle.kind == akGraphique and not hasConsole():
      discard MessageBoxW(nil, newWideCString(msg), newWideCString(gBundle.name), 0x10)
      return
  try: stderr.writeLine msg except IOError: discard

#
# Exécution du programme principal
#

proc runProgram(L: Interp, args: seq[string]): int =
  var vargs: seq[Value]
  for a in args: vargs.add strV(a)
  L.enter()
  curCtx = Ctx()
  try:
    discard L.runFile(mainPath(), vargs)
    when defined(wdlxGui):
      if L.loopNeeded():
        L.uiState.loopRunning = true
        L.blocking: runApplication()
  except SyntaxError as e:
    fatal(e.msg)
    result = 2
  except LexisExit as e:
    result = e.code
  except LexisStop:
    discard
  except LexisError as e:
    fatal(e.msg & "\n" & e.traceback)
    result = 1
  except CatchableError as e:
    fatal("erreur : " & e.msg)
    result = 1
  L.shutdown()
  L.leave()

proc programArgs(): seq[string] =
  for i in 1 .. paramCount(): result.add paramStr(i)

#
# Service : arrêt propre (SIGTERM sous Linux / macOS, gestionnaire de services Windows)
#

when not defined(windows):
  import std/posix
  proc onSignal(sig: cint) {.noconv.} =
    if not gStop.isNil: gStop[].store(true)

when defined(windows):
  type
    ServiceStatus {.pure.} = object
      serviceType, currentState, controlsAccepted, win32ExitCode,
        serviceSpecificExitCode, checkPoint, waitHint: uint32
    ServiceMainProc = proc (argc: uint32, argv: ptr WideCString) {.stdcall.}
    ServiceTableEntry {.pure.} = object
      name: WideCString
      main: ServiceMainProc
    HandlerEx = proc (control, eventType: uint32, eventData, context: pointer): uint32 {.stdcall.}

  proc StartServiceCtrlDispatcherW(t: ptr ServiceTableEntry): int32 {.
    stdcall, dynlib: "advapi32.dll", importc.}
  proc RegisterServiceCtrlHandlerExW(name: WideCString, h: HandlerEx, ctx: pointer): pointer {.
    stdcall, dynlib: "advapi32.dll", importc.}
  proc SetServiceStatus(h: pointer, s: ptr ServiceStatus): int32 {.
    stdcall, dynlib: "advapi32.dll", importc.}
  proc GetLastError(): uint32 {.stdcall, dynlib: "kernel32.dll", importc.}

  var
    svcHandle: pointer
    svcStatus: ServiceStatus
    svcName: WideCString
    svcExit: int

  proc report(state: uint32, exitCode = 0'u32) =
    svcStatus.serviceType = 0x10                                  # SERVICE_WIN32_OWN_PROCESS.
    svcStatus.currentState = state
    svcStatus.controlsAccepted = (if state == 4: 0x1'u32 or 0x4'u32 else: 0'u32)  # STOP | SHUTDOWN.
    svcStatus.win32ExitCode = exitCode
    if state == 4 or state == 1: svcStatus.checkPoint = 0 else: inc svcStatus.checkPoint
    svcStatus.waitHint = (if state == 3: 10_000'u32 else: 0'u32)
    if svcHandle != nil: discard SetServiceStatus(svcHandle, addr svcStatus)

  proc svcHandler(control, eventType: uint32, eventData, context: pointer): uint32 {.stdcall.} =
    case control
    of 1, 5:                                                      # SERVICE_CONTROL_STOP / SHUTDOWN
      report(3)                                                   # SERVICE_STOP_PENDING
      if not gStop.isNil: gStop[].store(true)
      when defined(wdlxGui): discard
      0
    of 4: 0                                                       # SERVICE_CONTROL_INTERROGATE.
    else: 120                                                     # ERROR_CALL_NOT_IMPLEMENTED.

  proc svcMain(argc: uint32, argv: ptr WideCString) {.stdcall.} =
    {.cast(gcsafe).}:
      svcHandle = RegisterServiceCtrlHandlerExW(svcName, svcHandler, nil)
      report(2)                                                   # SERVICE_START_PENDING.
      let L = newAppInterp(programArgs())
      let logPath = gBase / (gBundle.name & ".log")
      L.output = proc (s: string) =
        try:
          let f = open(logPath, fmAppend)
          f.write s
          f.close()
        except IOError: discard
      L.errput = L.output
      L.input = proc (prompt: string): (bool, string) = (false, "")
      gStop = addr L.stopFlag
      report(4)                                                   # SERVICE_RUNNING.
      svcExit = runProgram(L, programArgs())
      gStop = nil
      report(1, uint32(svcExit))                                  # SERVICE_STOPPED.

  proc runWindowsService(): (bool, int) =
    # (true, code) si le programme a tourné comme service ; (false, 0) s'il a
    # été lancé depuis une console (exécution normale).
    svcName = newWideCString(gBundle.name)
    var table = [ServiceTableEntry(name: svcName, main: svcMain), ServiceTableEntry()]
    if StartServiceCtrlDispatcherW(addr table[0]) != 0: return (true, svcExit)
    if GetLastError() == 1063: return (false, 0)                  # ERROR_FAILED_SERVICE_CONTROLLER_CONNECT.
    (false, 0)

#
# Point d'entrée des exécutables (appelé par main() de projet.c, après NimMain)
#

proc wdlx_main(): cint {.exportc, cdecl.} =
  try:
    installBundle()
  except CatchableError as e:
    fatal("wdlexis+ : " & e.msg)
    return 70
  let args = programArgs()
  when defined(windows):
    if gBundle.kind == akService:
      let (asService, code) = runWindowsService()
      if asService: return cint(code)
  let L = newAppInterp(args)
  when defined(windows):
    if gBundle.kind == akGraphique and not hasConsole():
      L.output = proc (s: string) = discard
      L.errput = proc (s: string) = discard
      L.onError = proc (msg: string) {.closure.} = fatal(msg)
  if gBundle.kind == akService:
    gStop = addr L.stopFlag
    when not defined(windows):
      signal(SIGTERM, onSignal)
      signal(SIGINT, onSignal)
      signal(SIGHUP, onSignal)
  cint(runProgram(L, args))

#
# Bibliothèque : API C (voir l'en-tête <nom>.h généré à côté de la bibliothèque)
#

var
  libInterp: Interp
  libLock: Lock
  libError {.threadvar.}: string
  libErrorC {.threadvar.}: cstring
initLock(libLock)

proc dupC(s: string): cstring =
  result = cast[cstring](allocShared0(s.len + 1))
  if s.len > 0: copyMem(result, unsafeAddr s[0], s.len)

proc setError(msg: string) =
  libError = msg
  if not libErrorC.isNil: deallocShared(libErrorC)
  libErrorC = dupC(msg)

proc wdlx_lib_initialiser(): cint {.exportc, cdecl.} =
  # Charge le projet embarqué et exécute les instructions en tête du fichier
  # principal (initialisation). Renvoie 0 si tout va bien.
  {.cast(gcsafe).}:
    withLock libLock:
      if not libInterp.isNil: return 0
      try:
        installBundle()
        let L = newAppInterp(@[])
        L.enter()
        curCtx = Ctx()
        try:
          let main = L.loadProgram(mainPath())
          if main.f.proto.body.len > 0: discard L.call(main, @[])
        finally:
          L.leave()
        libInterp = L
        return 0
      except LexisError as e:
        setError(e.msg)
      except SyntaxError as e:
        setError(e.msg)
      except CatchableError as e:
        setError(e.msg)
      return 1

proc wdlx_lib_appeler(procedure, argsJson: cstring): cstring {.exportc, cdecl.} =
  # Appelle une procédure ou fonction du projet. `argsJson` : tableau JSON des
  # arguments (ou NULL). Renvoie le résultat en JSON (à libérer avec
  # wdlexis_liberer), ou NULL en cas d'erreur (voir wdlexis_derniere_erreur).
  {.cast(gcsafe).}:
    if libInterp.isNil and wdlx_lib_initialiser() != 0: return nil
    let L = libInterp
    withLock libLock:
      L.enter()
      curCtx = Ctx()
      try:
        let name = cle($procedure)
        let f = L.procs.getOrDefault(name, nilV)
        if f.kind == vkNil:
          setError("procédure inconnue : " & $procedure)
          return nil
        var args: seq[Value]
        if not argsJson.isNil and ($argsJson).strip.len > 0:
          let j = parseJson($argsJson)
          if j.kind == JArray:
            for e in j: args.add fromJsonNode(e, upperKeys = false)
          else: args.add fromJsonNode(j, upperKeys = false)
        let r = L.call(f, args)
        let res = if r.len == 0: newJNull() elif r.len == 1: L.toJsonNode(r[0])
                  else: (var a = newJArray(); (for v in r: a.add L.toJsonNode(v)); a)
        return dupC($res)
      except LexisError as e:
        setError(e.msg)
      except SyntaxError as e:
        setError(e.msg)
      except CatchableError as e:
        setError(e.msg)
      finally:
        L.leave()
      return nil

proc wdlx_lib_liberer(s: cstring) {.exportc, cdecl.} =
  # Libère une chaîne renvoyée par wdlexis_appeler.
  if not s.isNil: deallocShared(s)

proc wdlx_lib_erreur(): cstring {.exportc, cdecl.} =
  # Dernière erreur du fil appelant (chaîne gérée par la bibliothèque).
  if libErrorC.isNil: "" else: libErrorC

proc wdlx_lib_terminer() {.exportc, cdecl.} =
  # Libère l'interpréteur (tâches, connexions...).
  {.cast(gcsafe).}:
    withLock libLock:
      if libInterp.isNil: return
      libInterp.enter()
      libInterp.shutdown()
      libInterp.leave()
      libInterp = nil

proc wdlx_lib_version(): cstring {.exportc, cdecl.} =
  WdlxVersion
