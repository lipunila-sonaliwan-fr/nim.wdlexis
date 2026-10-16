## CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
## Test du paquet webview sans affichage ni moteur web : la bibliothèque
## factice tests/webview/wvmock.c remplace webview.dll / .dylib / .so et
## rejoue tests/webview/scenario.txt (appels JavaScript simulés).
##   nim c -r tests/t_webview.nim          (vérifie)
##   nim c -r tests/t_webview.nim --maj    (régénère principal.attendu)

import std/[os, osproc, strutils]
import ../src/lexis/api
import ../src/paquets/[tous_sans_interface, pkg_webview]

const ici = currentSourcePath.parentDir / "webview"

proc executer(prg: string): int =
  # Mode enfant : exécute le programme, sortie directe sur stdout (mêlée,
  # dans l'ordre, à celle de la bibliothèque factice).
  let L = newFullInterp()
  L.scriptPath = prg
  L.searchDirs.add prg.parentDir
  L.onError = proc (msg: string) =
    stdout.write "[erreur] " & msg.splitLines()[0].replace(prg.parentDir & DirSep, "") & "\n"
    stdout.flushFile
  L.output = proc (s: string) =
    stdout.write s
    stdout.flushFile
  L.enter()
  curCtx = Ctx()
  try:
    discard L.runFile(prg)
  except LexisExit as e:
    echo "systeme.quitter(", e.code, ")"
    result = e.code
  except LexisStop:
    echo "arrêté"
  except LexisError as e:
    echo "ERREUR ", display(e.value)
    result = 1
  L.shutdown()
  L.leave()

when isMainModule:
  let p = commandLineParams()
  if p.len >= 2 and p[0] == "--executer":
    quit executer(p[1])
  let maj = "--maj" in p
  let tmp = getTempDir() / "wdlexis_webview_" & $getCurrentProcessId()
  createDir(tmp)
  let lib = tmp / (when defined(windows): "webview.dll" elif defined(macosx): "webview.dylib" else: "webview.so")
  let cc = "gcc -shared -fPIC -o " & quoteShell(lib) & " " & quoteShell(ici / "wvmock.c")
  if execShellCmd(cc) != 0: quit "compilation de wvmock.c impossible"
  putEnv("WDLEXIS_WEBVIEW", lib)
  putEnv("WVMOCK_SCRIPT", ici / "scenario.txt")
  let (sortie, code) = execCmdEx(quoteShell(getAppFilename()) & " --executer " & quoteShell(ici / "principal.prg"))
  removeDir(tmp)
  let attendu = ici / "principal.attendu"
  if maj or not fileExists(attendu):
    writeFile(attendu, sortie & "code de sortie " & $code & "\n")
    echo "écrit principal.attendu (code ", code, ")"
  elif readFile(attendu) == sortie & "code de sortie " & $code & "\n":
    echo "ok    webview"
  else:
    echo "ÉCHEC webview\n--- obtenu :\n", sortie
    quit 1
