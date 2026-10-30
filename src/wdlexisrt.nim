# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - runtime autonome du langage Lexis+
#
#   wdlexisrt programme.prg [arguments...]   exécute un programme (et les .prg de son dossier)
#   wdlexisrt --verifier programme.prg       vérifie la syntaxe sans exécuter
#   wdlexisrt --paquets                      liste les paquets disponibles
#   wdlexisrt -e "code"                      exécute du code
#
# Même interpréteur et mêmes paquets que l'atelier. Si le programme a ouvert
# des fenêtres (paquet interface) sans appeler interface.executer(), la boucle
# de wdgui est lancée à la fin du programme, jusqu'à la fermeture des fenêtres.

import std/[os, strutils]
import wdgui
import ide/appicon
import lexis/api
import paquets/tous
from lexis/lexer import SyntaxError
from lexis/parser import parseChunk

proc usage() =
  echo "wdlexis+ [RT] 1.8.0 - runtime du langage Lexis+"
  echo "Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr"
  echo "  wdlexisrt programme.prg [arguments...]"
  echo "  wdlexisrt --verifier programme.prg"
  echo "  wdlexisrt -e \"code\""
  echo "  wdlexisrt --paquets"

proc main(): int =
  if paramCount() < 1:
    usage()
    return 1
  let first = paramStr(1)
  case first
  of "-h", "--aide", "--help":
    usage()
    return 0
  of "--paquets":
    for p in packages():
      echo alignLeft(p.name, 12), (if p.global or p.name == "base": "toujours  " else: "par nom   "), p.description
    return 0
  of "--verifier":
    if paramCount() < 2:
      usage()
      return 1
    let path = paramStr(2)
    try:
      discard parseChunk(readFile(path), path)
      echo path, " : syntaxe correcte"
      return 0
    except SyntaxError as e:
      stderr.writeLine e.msg
      return 2
    except IOError, OSError:
      stderr.writeLine "lecture impossible : ", path
      return 1
  else: discard

  var src, name: string
  var argStart = 2
  var args: seq[string]
  if first == "-e":
    if paramCount() < 2:
      usage()
      return 1
    src = paramStr(2)
    name = "(ligne de commande)"
    argStart = 3
  else:
    name = absolutePath(first)
  for i in argStart .. paramCount(): args.add paramStr(i)

  var code = 0
  let L = newInterp()
  L.args = args
  if src.len == 0:
    L.scriptPath = name
    L.searchDirs.add name.parentDir
  openGlobals(L)
  L.enter()
  curCtx = Ctx()
  try:
    var vargs: seq[Value]
    for a in args: vargs.add strV(a)
    if src.len > 0: discard L.runMain(L.load(src, name), vargs)
    else: discard L.runFile(name, vargs)
    if L.loopNeeded():
      L.uiState.loopRunning = true
      L.blocking: runApplication()
  except SyntaxError as e:
    stderr.writeLine e.msg
    code = 2
  except LexisExit as e:
    code = e.code
  except LexisStop:
    discard
  except LexisError as e:
    stderr.writeLine e.msg
    stderr.writeLine e.traceback
    code = 1
  except IOError, OSError:
    stderr.writeLine "lecture impossible : ", name
    code = 1
  except CatchableError as e:
    stderr.writeLine "erreur : ", e.msg
    code = 1
  L.shutdown()
  L.leave()
  code

when isMainModule:
  useLexisIcon()      # icône par défaut ; un programme peut la changer (interface.icone)
  quit main()
