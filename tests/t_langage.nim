## Tests de non-régression du langage Lexis+ (sans interface graphique).
## Chaque tests/langage/*.prg définit une procédure TEST dont la sortie est
## comparée au fichier .attendu correspondant (base DuckDB en mémoire).
##   nim c -r tests/t_langage.nim          (vérifie)
##   nim c -r tests/t_langage.nim --maj    (régénère les .attendu)

import std/[os, strutils, algorithm]
import ../src/lexis/[api, zones]
import ../src/paquets/tous_sans_interface
from ../src/lexis/lexer import SyntaxError

proc executerTest(fichier: string): string =
  let tmp = getTempDir() / "wdlexis_test_" & $getCurrentProcessId()
  removeDir(tmp)
  createDir(tmp)
  let prg = tmp / "test.prg"
  copyFile(fichier, prg)
  var sortie = ""
  let L = newFullInterp()
  L.scriptPath = prg
  L.output = proc (s: string) = sortie.add s
  L.enter()
  curCtx = Ctx()
  try:
    L.openBase(":memoire:")
    discard L.loadProgram(prg)
    discard L.callName("TEST", @[])
  except LexisError as e:
    sortie.add "ERREUR " & e.source.extractFilename & ":" & $e.line & " " & display(e.value) & "\n"
  except SyntaxError as e:
    sortie.add "ERREUR SYNTAXE " & $e.line & " " & e.msg0 & "\n"
  except DuckError as e:
    sortie.add "ERREUR BASE " & e.msg & "\n"
  L.shutdown()
  L.leave()
  removeDir(tmp)
  sortie

when isMainModule:
  let maj = "--maj" in commandLineParams()
  var echecs = 0
  var fichiers: seq[string]
  for f in walkFiles(currentSourcePath.parentDir / "langage" / "*.prg"): fichiers.add f
  fichiers.sort()
  for f in fichiers:
    let sortie = executerTest(f)
    let attendu = f.changeFileExt("attendu")
    if maj or not fileExists(attendu):
      writeFile(attendu, sortie)
      echo "écrit ", f.extractFilename
    elif readFile(attendu) == sortie:
      echo "ok    ", f.extractFilename
    else:
      inc echecs
      echo "ÉCHEC ", f.extractFilename, "\n--- obtenu :\n", sortie
  if echecs > 0: quit(1)
