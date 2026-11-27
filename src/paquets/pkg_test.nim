# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet test : tests unitaires de Lexis+
#
#   && fichier test_calcul.prg (ou calcul_test.prg, ou dans un dossier tests/)
#   procedure TEST_ADDITION()
#     test.egal(ADDITIONNER(2, 3), 5)
#   procedure TEST_ERREUR()
#     test.erreur(@DIVISER, 1, 0)
#
# Lanceur : wdlexisrt --tests [dossier|fichier.prg]   (atelier : Exécuter › Lancer les tests)
# Chaque fichier de test s'exécute dans un interpréteur neuf, avec les procédures
# des autres fichiers .prg du projet (sans leur programme principal). Les
# procédures TEST_… (ou TEST…) sont lancées dans l'ordre du fichier ; AVANT_TEST
# et APRES_TEST, si elles existent, encadrent chacune. Les instructions en tête du
# fichier de test sont exécutées une fois, avant les tests (préparation).
#
# Une assertion qui échoue lève une erreur « [échec] … » : le test est « échec » ;
# toute autre erreur le met en « erreur » ; test.ignorer(raison) : « ignoré ».

import std/[strutils, tables, os, algorithm, monotimes, times]
import ../lexis/api
from ../lexis/lexer import SyntaxError
from ../lexis/parser import Program, parseChunk

const
  FailTag* = "[échec] "
  SkipTag* = "[ignoré] "

type
  TestStatus* = enum tsPass = "réussi", tsFail = "échec", tsError = "erreur", tsSkip = "ignoré"

  TestResult* = object
    name*, file*: string
    line*: int                    # ligne de la procédure de test (1-based)
    status*: TestStatus
    message*: string
    errLine*: int                 # ligne de l'échec (1-based), 0 sinon
    errSource*: string            # fichier de l'échec
    ms*: float
    assertions*: int

  TestCounter = ref object of RootObj
    n: int

proc counter(L: Interp): TestCounter =
  let r = L.ext.getOrDefault("test")
  if r.isNil or not (r of TestCounter):
    let c = TestCounter()
    L.ext["test"] = c
    return c
  TestCounter(r)

proc show(L: Interp, v: Value): string =
  case v.kind
  of vkStr: "\"" & v.s & "\""
  of vkTable:
    var parts: seq[string]
    var n = 0
    for k, x in v.t.pairs:
      inc n
      if parts.len < 10:
        parts.add (if k.kind == vkStr: k.s.toLowerAscii else: "[" & rawToString(k) & "]") & " = " & L.show(x)
    "{" & parts.join(", ") & (if n > 10: ", …" else: "") & "}"
  else: L.tostr(v)

proc deepEqual(L: Interp, a, b: Value, depth = 0): bool =
  if L.equals(a, b): return true
  if a.isNumber and b.isNumber:
    var ok1, ok2: bool
    return toFloat(a, ok1) == toFloat(b, ok2)
  if a.kind == vkTable and b.kind == vkTable and depth < 50:
    var na = 0
    for k, x in a.t.pairs:
      inc na
      if not L.deepEqual(x, b.t.rawGet(k), depth + 1): return false
    var nb = 0
    for _, _ in b.t.pairs: inc nb
    return na == nb
  false

proc failWith(msg, user: string) {.noreturn.} =
  rtError(FailTag & (if user.len > 0: user & " : " else: "") & msg)

proc assertion(L: Interp) = inc L.counter.n

#
# Exécution des tests
#

proc isTestProc*(name: string): bool =
  let n = name.toUpperAscii
  n.startsWith("TEST") and n notin ["TEST"]

proc runOne(L: Interp, name, file: string, line: int): TestResult =
  result = TestResult(name: name, file: file, line: line)
  let c = L.counter
  c.n = 0
  let t0 = getMonoTime()
  try:
    let before = L.procs.getOrDefault("AVANT_TEST", nilV)
    if before.kind != vkNil: discard L.call(before, @[])
    try:
      discard L.call(L.procs[name], @[])
    finally:
      let after = L.procs.getOrDefault("APRES_TEST", nilV)
      if after.kind != vkNil: discard L.call(after, @[])
    result.status = tsPass
  except LexisStop:
    result.status = tsError
    result.message = "arrêté"
  except LexisError as e:
    let m = if e.value.kind == vkStr: e.value.s else: e.msg
    result.errLine = e.line
    result.errSource = e.source
    if m.startsWith(FailTag):
      result.status = tsFail
      result.message = m[FailTag.len .. ^1]
    elif m.startsWith(SkipTag):
      result.status = tsSkip
      result.message = m[SkipTag.len .. ^1]
    else:
      result.status = tsError
      result.message = m
  except CatchableError as e:
    result.status = tsError
    result.message = e.msg
  result.ms = (getMonoTime() - t0).inNanoseconds.float / 1e6
  result.assertions = c.n

proc testProcsOf*(L: Interp, file: string): seq[(string, int)] =
  ## Procédures de test d'un fichier, dans l'ordre du fichier.
  for name, v in L.procs:
    if v.kind == vkFunc and not v.f.native and isTestProc(name) and
       (file.len == 0 or v.f.proto.source == file):
      result.add (name, v.f.proto.line)
  result.sort(proc (a, b: (string, int)): int = cmp(a[1], b[1]))

proc runTestProcs*(L: Interp, file, filter: string): seq[TestResult] =
  for (name, line) in L.testProcsOf(file):
    if filter.len > 0 and filter.toUpperAscii notin name: continue
    let src = L.procs[name].f.proto.source
    result.add L.runOne(name, src, line)

proc isTestFile*(rel: string): bool = isTestSource(rel)

proc discoverTests*(target: string): (string, seq[string]) =
  ## (dossier du projet, fichiers de test) pour un dossier ou un fichier.
  if fileExists(target):
    return (target.parentDir, @[absolutePath(target).normalizedPath])
  let root = absolutePath(target).normalizedPath
  var files: seq[string]
  if dirExists(root):
    for f in walkDirRec(root, relative = true):
      var hidden = false
      for part in f.split({'/', '\\'}):
        if part.startsWith("."): hidden = true
      if not hidden and isTestFile(f): files.add root / f
  files.sort()
  (root, files)

proc projectSources(root: string, tests: seq[string]): seq[string] =
  # Fichiers .prg du projet qui ne sont pas des tests (procédures chargées).
  if not dirExists(root): return
  for f in walkDirRec(root, relative = true):
    var hidden = false
    for part in f.split({'/', '\\'}):
      if part.startsWith("."): hidden = true
    if hidden or not f.toLowerAscii.endsWith(".prg") or isTestFile(f): continue
    result.add root / f
  result.sort()

proc runTestFile*(path, root: string, filter = "",
                  output: proc (s: string) {.closure, gcsafe.} = nil): seq[TestResult] =
  ## Exécute un fichier de test dans un interpréteur neuf.
  {.cast(gcsafe).}:
    let L = newInterp()
    L.scriptPath = path
    L.searchDirs = @[path.parentDir, root]
    openGlobals(L)
    var buf = ""
    L.output = if output.isNil: (proc (s: string) = buf.add s) else: output
    L.errput = L.output
    L.input = proc (prompt: string): (bool, string) = (false, "")
    L.enter()
    curCtx = Ctx()
    try:
      try:
        for f in projectSources(root, @[path]):
          if f == path: continue
          discard L.registerProgram(parseChunk(L.readSource(f), f), true)
        let main = L.load(L.readSource(path), path)
        if main.f.proto.body.len > 0: discard L.call(main, @[])
        result = L.runTestProcs(path, filter)
        if result.len == 0:
          result.add TestResult(name: "(aucun test)", file: path, status: tsSkip,
                                message: "aucune procédure TEST_… dans ce fichier")
      except SyntaxError as e:
        result.add TestResult(name: "(chargement)", file: path, status: tsError, message: e.msg, errLine: e.line)
      except LexisError as e:
        result.add TestResult(name: "(préparation)", file: path, status: tsError, message: e.msg, errLine: e.line)
      except CatchableError as e:
        result.add TestResult(name: "(chargement)", file: path, status: tsError, message: e.msg)
    finally:
      try: L.shutdown()
      except Exception: discard
      L.leave()

proc summary*(rs: seq[TestResult]): (int, int, int, int) =
  for r in rs:
    case r.status
    of tsPass: inc result[0]
    of tsFail: inc result[1]
    of tsError: inc result[2]
    of tsSkip: inc result[3]

proc textReport*(rs: seq[TestResult], root = ""): string =
  var o = ""
  var file = ""
  for r in rs:
    if r.file != file:
      file = r.file
      o.add "\n" & (if root.len > 0 and file.startsWith(root): relativePath(file, root) else: file) & "\n"
    let mark = case r.status
      of tsPass: "  ✓ "
      of tsFail: "  ✗ "
      of tsError: "  ! "
      of tsSkip: "  - "
    o.add mark & r.name.toLowerAscii & "  (" & formatFloat(r.ms, ffDecimal, 1) & " ms" &
          (if r.assertions > 0: ", " & $r.assertions & " assertion" & (if r.assertions > 1: "s" else: "") else: "") & ")"
    if r.status != tsPass:
      let at = if r.errLine <= 0: ""
               elif r.errSource.len > 0 and r.errSource != r.file: " " & extractFilename(r.errSource) & ":" & $r.errLine
               else: " ligne " & $r.errLine
      o.add "\n      " & $r.status & at & " : " & r.message
    o.add "\n"
  let (p, f, e, s) = summary(rs)
  o.add "\n" & $p & " réussi(s), " & $f & " échec(s), " & $e & " erreur(s), " & $s & " ignoré(s)\n"
  o

proc resultV(r: TestResult): Value =
  record({"nom": strV(r.name.toLowerAscii), "fichier": strV(r.file), "ligne": intV(r.line),
          "statut": strV($r.status), "message": strV(r.message), "ligneerreur": intV(r.errLine),
          "sourceerreur": strV(r.errSource),
          "ms": numV(r.ms), "assertions": intV(r.assertions)})

proc resultsV*(rs: seq[TestResult]): Value =
  let t = newLTable(rs.len)
  for r in rs: t.arr.add resultV(r)
  let (p, f, e, s) = summary(rs)
  record({"resultats": tableV(t), "reussis": intV(p), "echecs": intV(f), "erreurs": intV(e),
          "ignores": intV(s), "total": intV(rs.len), "ok": boolV(f == 0 and e == 0)})

#
# Paquet
#

proc msgArg(L: Interp, a: seq[Value], i: int): string =
  if arg(a, i).kind == vkNil: "" else: L.tostr(a[i - 1])

proc openTest(L: Interp): Value =
  let m = newLib()
  m.fn "vrai", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.assertion
    if not truthy(arg(a, 1)): failWith("vrai attendu, " & L.show(arg(a, 1)) & " obtenu", L.msgArg(a, 2))
  m.fn "verifier", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.assertion
    if not truthy(arg(a, 1)): failWith("condition fausse", L.msgArg(a, 2))
  m.fn "faux", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.assertion
    if truthy(arg(a, 1)): failWith("faux attendu, " & L.show(arg(a, 1)) & " obtenu", L.msgArg(a, 2))
  m.fn "egal", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.assertion
    if not L.deepEqual(arg(a, 1), arg(a, 2)):
      failWith("attendu " & L.show(arg(a, 2)) & ", obtenu " & L.show(arg(a, 1)), L.msgArg(a, 3))
  m.fn "different", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.assertion
    if L.deepEqual(arg(a, 1), arg(a, 2)):
      failWith("valeurs égales : " & L.show(arg(a, 1)), L.msgArg(a, 3))
  m.fn "proche", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.assertion
    let x = L.checkNum(a, 1, "test.proche")
    let y = L.checkNum(a, 2, "test.proche")
    let eps = L.optNum(a, 3, "test.proche", 1e-9)
    if abs(x - y) > eps:
      failWith("attendu " & $y & " (à " & $eps & " près), obtenu " & $x, L.msgArg(a, 4))
  m.fn "nul", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.assertion
    if arg(a, 1).kind != vkNil: failWith("nul attendu, " & L.show(arg(a, 1)) & " obtenu", L.msgArg(a, 2))
  m.fn "nonnul", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.assertion
    if arg(a, 1).kind == vkNil: failWith("valeur attendue, nul obtenu", L.msgArg(a, 2))
  m.fn "contient", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.assertion
    let c = arg(a, 1)
    let x = arg(a, 2)
    var found = false
    if c.kind == vkStr: found = L.tostr(x) in c.s
    elif c.kind == vkTable:
      for _, v in c.t.pairs:
        if L.deepEqual(v, x): found = true
    if not found: failWith(L.show(c) & " ne contient pas " & L.show(x), L.msgArg(a, 3))
  m.fn "type", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.assertion
    let want = L.checkStr(a, 2, "test.type")
    let ty = TypeSpec(kind: typeKindOf(want), name: want)
    if not typeMatches(arg(a, 1), ty):
      failWith("type " & want & " attendu, " & typeName(arg(a, 1)) & " obtenu", L.msgArg(a, 3))
  m.fn "erreur", proc (L: Interp, a: seq[Value]): seq[Value] =
    # test.erreur(@PROC, arguments...) : l'appel doit échouer ; renvoie le message.
    L.assertion
    let f = L.checkFunc(a, 1, "test.erreur")
    var raised = false
    var msg = ""
    try:
      discard L.call(f, (if a.len > 1: a[1 .. ^1] else: @[]))
    except LexisError as e:
      raised = true
      msg = if e.value.kind == vkStr: e.value.s else: e.msg
    if not raised: failWith("erreur attendue, l'appel a réussi", "")
    @[strV(msg)]
  m.fn "echec", proc (L: Interp, a: seq[Value]): seq[Value] =
    failWith(L.msgArg(a, 1), "")
  m.fn "ignorer", proc (L: Interp, a: seq[Value]): seq[Value] =
    rtError(SkipTag & L.msgArg(a, 1))
  m.fn "executer", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Tests TEST_… du programme en cours (tous les fichiers chargés).
    let filter = L.optStr(a, 1, "test.executer", "")
    @[resultsV(L.runTestProcs("", filter))]
  m.fn "rapport", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkTable(a, 1, "test.rapport")
    let lst = t.rawGet(cle("resultats"))
    var rs: seq[TestResult]
    if lst.kind == vkTable:
      for i in 1 .. lst.t.rawLen:
        let r = lst.t.rawGet(intV(i))
        if r.kind != vkTable: continue
        var st = tsPass
        case optField(r.t, "statut", "réussi")
        of "échec": st = tsFail
        of "erreur": st = tsError
        of "ignoré": st = tsSkip
        else: discard
        rs.add TestResult(name: optField(r.t, "nom", ""), file: optField(r.t, "fichier", ""),
                          line: optField(r.t, "ligne", 0), status: st, message: optField(r.t, "message", ""),
                          errLine: optField(r.t, "ligneerreur", 0), ms: optField(r.t, "ms", 0.0),
                          assertions: optField(r.t, "assertions", 0))
    @[strV(textReport(rs))]
  m.fn "lancer", proc (L: Interp, a: seq[Value]): seq[Value] =
    # test.lancer(dossier ou fichier, [filtre]) : lanceur complet (interpréteurs neufs).
    let target = L.checkStr(a, 1, "test.lancer")
    let filter = L.optStr(a, 2, "test.lancer", "")
    let (root, files) = discoverTests(target)
    var rs: seq[TestResult]
    L.blocking:
      for f in files: rs.add runTestFile(f, root, filter)
    @[resultsV(rs)]
  tableV(m)

const testDocs = [
  "test.egal(obtenu, attendu, [message])", "Échec si les valeurs diffèrent (tables comparées en profondeur, 2 = 2.0).",
  "test.different(a, b, [message])", "Échec si les valeurs sont égales.",
  "test.vrai(valeur, [message])", "Échec si la valeur est fausse ou nulle.",
  "test.faux(valeur, [message])", "Échec si la valeur est vraie.",
  "test.verifier(condition, [message])", "Échec si la condition est fausse.",
  "test.proche(obtenu, attendu, [ecart], [message])", "Nombres égaux à l'écart près (1e-9 par défaut).",
  "test.nul(valeur, [message])", "Échec si la valeur n'est pas nulle.",
  "test.nonnul(valeur, [message])", "Échec si la valeur est nulle.",
  "test.contient(chaine_ou_table, element, [message])", "Sous-chaîne, ou élément d'une table.",
  "test.type(valeur, type, [message])", "Type déclaré attendu : nombre, entier, chaine, table, logique…",
  "test.erreur(@PROC, arguments...)", "L'appel doit lever une erreur ; renvoie son message.",
  "test.echec(message)", "Fait échouer le test.",
  "test.ignorer(raison)", "Arrête le test, compté « ignoré ».",
  "test.executer([filtre])", "Lance les procédures TEST_… du programme en cours ; renvoie {reussis, echecs, erreurs, ignores, total, ok, resultats}.",
  "test.lancer(dossier_ou_fichier, [filtre])", "Lanceur complet : chaque fichier de test (test_*.prg, *_test.prg, tests/) dans un interpréteur neuf, avec les procédures du projet.",
  "test.rapport(resultats)", "Rapport texte d'un résultat de test.executer ou test.lancer."]

registerPackage PackageDef(name: "test", open: openTest,
  description: "Tests unitaires : assertions et lanceur de procédures TEST_…",
  docs: docs("test", testDocs))
