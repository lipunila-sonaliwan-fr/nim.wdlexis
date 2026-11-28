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

import std/[os, strutils, json]
import wdgui
import ide/appicon
import lexis/[api, profiler]
import paquets/tous
import paquets/pkg_test
import ide/[lspserver, formateur, lexislint, lexislang, langdocs]
from lexis/lexer import SyntaxError
from lexis/parser import parseChunk

proc usage() =
  echo "wdlexis+ [RT] 2.1.3 - runtime du langage Lexis+"
  echo "Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr"
  echo "  wdlexisrt programme.prg [arguments...]"
  echo "  wdlexisrt --verifier fichier.prg...        syntaxe, collisions de noms, types déclarés"
  echo "  wdlexisrt --formater [--ecrire] fichier.prg|dossier...   (conventions : .lexisformat)"
  echo "  wdlexisrt --tests [dossier|fichier.prg] [--filtre nom] [--json]"
  echo "  wdlexisrt --profil programme.prg [arguments...]"
  echo "  wdlexisrt --lsp                             serveur LSP (entrée/sortie standard)"
  echo "  wdlexisrt -e \"code\""
  echo "  wdlexisrt --paquets"

proc prgFiles(args: seq[string]): seq[string] =
  for a in args:
    if dirExists(a):
      for f in walkDirRec(a):
        if f.toLowerAscii.endsWith(".prg") and "/." notin f.replace('\\', '/'): result.add f
    else: result.add a

proc cmdVerify(args: seq[string]): int =
  initLangDocs()
  for path in prgFiles(args):
    var text = ""
    try: text = readFile(path)
    except IOError, OSError:
      stderr.writeLine "lecture impossible : ", path
      result = max(result, 1)
      continue
    let lines = text.replace("\r\n", "\n").split('\n')
    let (toks, _) = lexAll(lines)
    let (_, local) = collectSymbols(lines, toks)
    let idx = indexProject(absolutePath(path).parentDir)
    var errs = 0
    for d in lint(lines, toks, idx.knownNamesFor(local),
                  LintOptions(flagGlobals: true, unknownCalls: true), absolutePath(path), idx):
      echo path, ":", d.line + 1, ":", d.col + 1, ": ", ($d.sev).toLowerAscii, " : ", d.msg
      if d.sev == sevError: inc errs
    if errs > 0: result = 2

proc cmdFormat(args: seq[string]): int =
  var write = false
  var files: seq[string]
  for a in args:
    if a in ["--ecrire", "-w"]: write = true
    else: files.add a
  for path in prgFiles(files):
    try:
      let text = readFile(path)
      let r = formatText(text, loadFormatOptions(absolutePath(path).parentDir))
      if not r.safe:
        stderr.writeLine path, " : ", r.message
        result = 2
      elif write:
        if r.changed:
          writeFile(path, r.text)
          echo "formaté : ", path
      else: stdout.write r.text
    except IOError, OSError:
      stderr.writeLine "lecture impossible : ", path
      result = 1

proc cmdTests(args: seq[string]): int =
  var target = getCurrentDir()
  var filter = ""
  var asJson = false
  var i = 0
  while i < args.len:
    case args[i]
    of "--filtre":
      inc i
      if i < args.len: filter = args[i]
    of "--json": asJson = true
    else: target = args[i]
    inc i
  let (root, files) = discoverTests(target)
  var rs: seq[TestResult]
  for f in files: rs.add runTestFile(f, root, filter)
  if asJson:
    var arr = newJArray()
    for r in rs:
      arr.add %*{"nom": r.name.toLowerAscii, "fichier": r.file, "ligne": r.line, "statut": $r.status,
                 "message": r.message, "ligneerreur": r.errLine, "sourceerreur": r.errSource, "ms": r.ms, "assertions": r.assertions}
    echo $arr
  else:
    if files.len == 0: echo "aucun fichier de test (test_*.prg, *_test.prg, dossier tests/) dans ", root
    stdout.write textReport(rs, root)
  let (_, f, e, _) = summary(rs)
  if f + e > 0: 1 else: 0

proc main(): int =
  if paramCount() < 1:
    usage()
    return 1
  var first = paramStr(1)
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
    return cmdVerify(commandLineParams()[1 .. ^1])
  of "--formater":
    return cmdFormat(commandLineParams()[1 .. ^1])
  of "--tests":
    return cmdTests(commandLineParams()[1 .. ^1])
  of "--lsp":
    runLspServer()
    return 0
  else: discard
  var profile = false
  var shift = 0
  if first == "--profil":
    if paramCount() < 2:
      usage()
      return 1
    profile = true
    shift = 1

  var src, name: string
  var argStart = 2
  var args: seq[string]
  first = paramStr(1 + shift)
  if first == "-e":
    if paramCount() < 2 + shift:
      usage()
      return 1
    src = paramStr(2 + shift)
    name = "(ligne de commande)"
    argStart = 3
  else:
    name = absolutePath(first)
  for i in argStart + shift .. paramCount(): args.add paramStr(i)

  var code = 0
  let L = newInterp()
  L.args = args
  if src.len == 0:
    L.scriptPath = name
    L.searchDirs.add name.parentDir
  openGlobals(L)
  L.enter()
  curCtx = Ctx()
  if profile: discard L.startProfiler()
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
  if profile:
    let p = L.stopProfiler()
    if not p.isNil: stderr.write "\n" & p.report()
  L.shutdown()
  L.leave()
  code

when isMainModule:
  useLexisIcon()      # icône par défaut ; un programme peut la changer (interface.icone)
  quit main()
