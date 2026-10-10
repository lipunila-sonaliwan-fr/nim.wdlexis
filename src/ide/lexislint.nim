# Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr
#   wdlexis+ - atelier : diagnostics, structure et index des symboles
#
# Les erreurs de syntaxe viennent du vrai analyseur de l'interpréteur
# (lexis/parser.nim) : ce que l'atelier signale est exactement ce qui
# empêcherait l'exécution. S'y ajoutent des contrôles heuristiques :
#   - appel d'une procédure ou fonction définie nulle part (projet, fonctions
#     intégrées, paquets) ;
#   - option : affectation, dans une procédure, d'une variable non déclarée
#     (elle devient une variable globale : piège classique, voir « locale »).

import std/[strutils, sets, tables, os, algorithm]
import lexislang, langdocs
from ../lexis/parser import parseChunk
from ../lexis/lexer import SyntaxError

type
  Severity* = enum sevError = "Erreur", sevWarning = "Avertissement", sevInfo = "Info"

  Diagnostic* = object
    line*, col*, len*: int      # 0-based.
    sev*: Severity
    msg*: string

  SymKind* = enum symProc = "procédure", symFunc = "fonction", symGlobal = "globale", symLocal = "locale"

  Symbol* = object
    name*: string               # majuscules
    display*: string
    kind*: SymKind
    line*, col*: int

  LintOptions* = object
    flagGlobals*: bool          # signaler les variables non déclarées dans les procédures.
    unknownCalls*: bool         # signaler les appels inconnus.

  Sig = object
    kind: TokKind
    text: string
    line, col: int

proc significant(lines: openArray[string], toks: openArray[seq[Token]]): seq[seq[Sig]] =
  ## Jetons significatifs, ligne par ligne.
  result = newSeq[seq[Sig]](min(lines.len, toks.len))
  for li in 0 ..< result.len:
    for t in toks[li]:
      if t.kind notin {tkSpace, tkComment, tkPod}:
        result[li].add Sig(kind: t.kind, text: tokText(lines[li], t), line: li, col: t.start)

proc isName(s: Sig): bool {.inline.} = s.kind in {tkIdent, tkBuiltin, tkCallback}
proc isKw(s: Sig, w: string): bool {.inline.} = s.kind == tkKeyword and s.text == w

proc collectSymbols*(lines: openArray[string], toks: openArray[seq[Token]]):
    (seq[Symbol], HashSet[string]) =
  ## Définitions affichables et ensemble de tous les noms définis (majuscules).
  let rows = significant(lines, toks)
  var syms: seq[Symbol]
  var names = initHashSet[string]()
  var seenGlobals = initHashSet[string]()
  var inProc = false
  var locals = initHashSet[string]()
  for row in rows:
    if row.len == 0: continue
    let s = row[0]
    if s.isKw("procedure") or s.isKw("fonction"):
      inProc = true
      locals = initHashSet[string]()
      if row.len > 1 and row[1].isName:
        let nm = upper(row[1].text)
        var params: seq[string]
        var i = 2
        if i < row.len and row[i].text == "(":
          inc i
          while i < row.len and row[i].text != ")":
            if row[i].isName:
              params.add row[i].text
              names.incl upper(row[i].text)
              locals.incl upper(row[i].text)
            inc i
        names.incl nm
        syms.add Symbol(name: nm, display: row[1].text & "(" & params.join(", ") & ")",
                        kind: (if s.text == "procedure": symProc else: symFunc),
                        line: s.line, col: s.col)
      continue
    if s.isKw("finprocedure") or s.isKw("finfonction"):
      inProc = false
      continue
    # déclarations
    if s.isKw("locale") or s.isKw("local") or s.isKw("parametres") or s.isKw("globale"):
      var i = 1
      var depth = 0
      while i < row.len:
        if row[i].text in ["(", "[", "{"]: inc depth
        elif row[i].text in [")", "]", "}"]: dec depth
        elif depth == 0 and row[i].isName and (i == 1 or row[i - 1].text == ","):
          let nm = upper(row[i].text)
          names.incl nm
          if not s.isKw("globale"): locals.incl nm
          if not inProc or s.isKw("globale"):
            if nm notin seenGlobals and not inProc:
              seenGlobals.incl nm
              syms.add Symbol(name: nm, display: row[i].text, kind: symGlobal, line: row[i].line, col: row[i].col)
        inc i
      continue
    if s.isKw("pour"):
      var i = 1
      if i < row.len and row[i].isKw("chaque"): inc i
      while i < row.len and (row[i].isName or row[i].text == ","):
        if row[i].isName:
          names.incl upper(row[i].text)
          locals.incl upper(row[i].text)
        inc i
      continue
    if s.isKw("capturer") and row.len > 1 and row[1].isName:
      names.incl upper(row[1].text)
      locals.incl upper(row[1].text)
      continue
    if s.isKw("stocker") or s.isKw("compter") or s.isKw("sql") or s.isKw("retirer"):
      # stocker v dans x, y / compter ... dans x / sql ... dans x
      var after = false
      for x in row:
        if x.isKw("dans"):
          after = true
        elif after and x.isName:
          names.incl upper(x.text)
      continue
    # affectation « nom = ... » en tête de ligne
    if s.isName and row.len > 1 and row[1].text in ["=", "+=", "-="]:
      let nm = upper(s.text)
      names.incl nm
      if not inProc and nm notin seenGlobals:
        seenGlobals.incl nm
        syms.add Symbol(name: nm, display: s.text, kind: symGlobal, line: s.line, col: s.col)
    if s.isKw("nouvelle") and row.len > 2 and row[2].isName:
      names.incl upper(row[2].text)
  (syms, names)

proc syntaxCheck*(text, source: string): (bool, int, string) =
  ## (ok, ligne 0-based, message) avec le vrai analyseur.
  try:
    discard parseChunk(text, source)
    result = (true, 0, "")
  except SyntaxError as e:
    result = (false, max(0, e.line - 1), e.msg0)

proc lint*(lines: openArray[string], toks: openArray[seq[Token]],
           knownNames: HashSet[string], opts: LintOptions, source = "fichier"): seq[Diagnostic] =
  var diags: seq[Diagnostic]
  template report(l, c, n: int, s: Severity, m: string) =
    diags.add Diagnostic(line: l, col: c, len: max(1, n), sev: s, msg: m)

  # 1. syntaxe : selon l'analyseur de l'interpréteur.
  let (ok, eline, emsg) = syntaxCheck(lines.join("\n"), source)
  if not ok:
    var col = 0
    var n = 1
    if eline < lines.len:
      col = lines[eline].len - lines[eline].strip(trailing = false).len
      n = max(1, lines[eline].strip().len)
    report(eline, col, n, sevError, emsg)

  let rows = significant(lines, toks)

  # 2. variables non déclarées dans les procédures (deviennent globales).
  if opts.flagGlobals:
    var inProc = false
    var declared = initHashSet[string]()
    for row in rows:
      if row.len == 0: continue
      let s = row[0]
      if s.isKw("procedure") or s.isKw("fonction"):
        inProc = true
        declared = initHashSet[string]()
        for x in row[1 .. ^1]:
          if x.isName: declared.incl upper(x.text)
      elif s.isKw("finprocedure") or s.isKw("finfonction"): inProc = false
      elif s.isKw("locale") or s.isKw("local") or s.isKw("parametres") or s.isKw("globale") or
           s.isKw("pour") or s.isKw("capturer"):
        for x in row:
          if x.isName: declared.incl upper(x.text)
      elif inProc and s.isName and row.len > 1 and row[1].text in ["=", "+=", "-="] and
           upper(s.text) notin declared:
        report(s.line, s.col, s.text.len, sevInfo,
          "« " & s.text & " » n'est pas déclarée dans la procédure : c'est une variable globale (« locale " &
          s.text & " » pour une variable locale, « globale " & s.text & " » pour l'assumer)")
        declared.incl upper(s.text)

  # 3. appels inconnus (seulement si la syntaxe est correcte).
  if ok and opts.unknownCalls:
    for row in rows:
      for i, s in row:
        var target = false
        if s.isName and i + 1 < row.len and row[i + 1].text == "(" and
           (i == 0 or row[i - 1].text notin [".", ":", "->"]) and
           not (i > 0 and (row[i - 1].isKw("procedure") or row[i - 1].isKw("fonction"))):
          target = true
        if s.isName and i > 0 and row[i - 1].isKw("faire") and i == 1: target = true
        if target and upper(s.text) notin knownNames and not isBuiltin(s.text):
          report(s.line, s.col, s.text.len, sevWarning,
            "« " & s.text & " » n'est défini ni dans le projet, ni parmi les fonctions intégrées et les paquets")

  diags.sort(proc (a, b: Diagnostic): int =
    result = cmp(a.line, b.line)
    if result == 0: result = cmp(a.col, b.col))
  diags

#
# Index de projet
#

type
  Location* = object
    file*: string
    line*, col*: int

  ProjectIndex* = object
    defs*: Table[string, seq[Location]]    # nom (majuscules) -> définitions
    names*: HashSet[string]

proc initProjectIndex*(): ProjectIndex =
  ProjectIndex(defs: initTable[string, seq[Location]](), names: initHashSet[string]())

proc indexFile*(idx: var ProjectIndex, path: string, text: string) =
  let lines = text.splitLines()
  let (toks, _) = lexAll(lines)
  let (syms, names) = collectSymbols(lines, toks)
  for n in names: idx.names.incl n
  for s in syms:
    if s.kind in {symProc, symFunc}:
      idx.defs.mgetOrPut(s.name, @[]).add Location(file: path, line: s.line, col: s.col)

proc indexProject*(root: string): ProjectIndex =
  result = initProjectIndex()
  if root.len == 0 or not dirExists(root): return
  for f in walkDirRec(root):
    if f.toLowerAscii.endsWith(".prg"):
      try: result.indexFile(f, readFile(f))
      except IOError, OSError: discard

proc knownNamesFor*(idx: ProjectIndex, local: HashSet[string]): HashSet[string] =
  result = local
  for n in idx.names: result.incl n
