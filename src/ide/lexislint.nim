# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - atelier : diagnostics, structure et index des symboles
#
# Les erreurs de syntaxe viennent du vrai analyseur de l'interpréteur
# (lexis/parser.nim) : ce que l'atelier signale est exactement ce qui
# empêcherait l'exécution. S'y ajoutent des contrôles heuristiques :
#   - appel d'une procédure ou fonction définie nulle part (projet, fonctions
#     intégrées, paquets) ;
#   - option : affectation, dans une procédure, d'une variable non déclarée
#     (elle devient une variable globale : piège classique, voir « locale »).

import std/[strutils, sets, tables, os, algorithm, sequtils]
import lexislang, langdocs, lexisanalyse
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
    skipCollisions*: bool       # ne pas signaler les collisions de noms.
    skipTypes*: bool            # ne pas contrôler les types déclarés.

  Location* = object
    file*: string
    line*, col*: int

  ProcSig* = object              # signature d'une procédure du projet (types déclarés compris)
    name*, display*, file*, doc*, ret*, kind*: string
    params*, paramTypes*: seq[string]
    line*, col*: int

  ProjectIndex* = object
    defs*: Table[string, seq[Location]]    # nom (majuscules) -> définitions
    names*: HashSet[string]
    sigs*: Table[string, seq[ProcSig]]     # procédures et fonctions (majuscules)
    globals*: Table[string, seq[Location]] # variables globales (globale x, affectation hors procédure)

proc collectSymbols*(lines: openArray[string], toks: openArray[seq[Token]]):
    (seq[Symbol], HashSet[string]) =
  # Définitions affichables et ensemble de tous les noms définis (majuscules).
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
            if (row[i].isName or (row[i].kind == tkKeyword and row[i - 1].text in ["(", ","])) and
               row[i - 1].text != ":":
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
  # (ok, ligne 0-based, message) avec le vrai analyseur.
  try:
    discard parseChunk(text, source)
    result = (true, 0, "")
  except SyntaxError as e:
    result = (false, max(0, e.line - 1), e.msg0)

proc initProjectIndex*(): ProjectIndex =
  ProjectIndex(defs: initTable[string, seq[Location]](), names: initHashSet[string](),
               sigs: initTable[string, seq[ProcSig]](), globals: initTable[string, seq[Location]]())

proc sigsOf*(fa: FileAnalysis, path: string): seq[ProcSig] =
  for sc in fa.scopes[1 .. ^1]:
    if sc.name.len == 0: continue
    result.add ProcSig(name: sc.name, display: sc.display, file: path, doc: sc.doc, ret: sc.ret,
                       kind: sc.kind, params: sc.params, paramTypes: sc.paramTypes, line: sc.line, col: sc.col)

proc globalsOf*(fa: FileAnalysis): seq[(string, int, int)] =
  ## Variables globales définies : globale x, ou affectation hors procédure.
  var seen = initHashSet[string]()
  for o in fa.occs:
    if (o.kind == okGlobalDecl or (o.kind == okAssign and o.scope == 0 and not o.local)) and o.name notin seen:
      seen.incl o.name
      result.add (o.name, o.line, o.col)

proc sameFile(a, b: string): bool =
  if a == b: return true
  if a.len == 0 or b.len == 0: return false
  if a.isAbsolute and b.isAbsolute: return normalizedPath(a) == normalizedPath(b)
  extractFilename(a).toLowerAscii == extractFilename(b).toLowerAscii

proc where(file: string, line: int, source: string): string =
  if sameFile(file, source): "ligne " & $(line + 1)
  else: extractFilename(file) & ":" & $(line + 1)

proc splitArgs(row: seq[Sig], a, b: int): seq[(int, int)] =
  # Arguments d'un appel row[a ..< b] (sans les parenthèses), séparés au premier niveau.
  var depth = 0
  var start = a
  for i in a ..< b:
    let t = row[i].text
    if t in ["(", "[", "{"]: inc depth
    elif t in [")", "]", "}"]: dec depth
    elif t == "," and depth == 0:
      result.add (start, i)
      start = i + 1
  if b > a: result.add (start, b)

proc closing(row: seq[Sig], open: int): int =
  var depth = 0
  for i in open ..< row.len:
    if row[i].text in ["(", "[", "{"]: inc depth
    elif row[i].text in [")", "]", "}"]:
      dec depth
      if depth == 0: return i
  row.len

proc namesAndTypes(fa: FileAnalysis, project: ProjectIndex, source: string, opts: LintOptions,
                   diags: var seq[Diagnostic]) =
  ## Collisions de noms et contrôle statique des types déclarés.
  template report(o: Occ, s: Severity, m: string) =
    diags.add Diagnostic(line: o.line, col: o.col, len: max(1, o.text.len), sev: s, msg: m)
  # procédures connues : celles du fichier, puis celles des autres fichiers du projet.
  var procs = initTable[string, seq[ProcSig]]()
  for sg in sigsOf(fa, source): procs.mgetOrPut(sg.name, @[]).add sg
  for n, lst in project.sigs:
    for sg in lst:
      if not sameFile(sg.file, source): procs.mgetOrPut(n, @[]).add sg
  var globals = initTable[string, Location]()
  for (n, l, c) in globalsOf(fa): globals[n] = Location(file: source, line: l, col: c)
  for n, lst in project.globals:
    if n notin globals:
      for g in lst:
        if not sameFile(g.file, source):
          globals[n] = g
          break

  if not opts.skipCollisions:
    # 1. même variable écrite avec des casses différentes (S et s).
    var firstSpelling = initTable[string, int]()
    var reported = initHashSet[string]()
    for i, o in fa.occs:
      if not o.isVariableOcc: continue
      let key = fa.symbolKey(o)
      if key.len == 0: continue
      if key.startsWith("G:") and o.kind == okUse and builtinKind(o.name).len > 0: continue
      if key notin firstSpelling:
        firstSpelling[key] = i
        continue
      let f = fa.occs[firstSpelling[key]]
      if f.text != o.text and (key & "|" & o.text) notin reported:
        reported.incl key & "|" & o.text
        report(o, sevWarning, "« " & o.text & " » désigne la même variable que « " & f.text & " » (ligne " &
               $(f.line + 1) & ") : Lexis+ ne distingue pas les majuscules des minuscules")
    # 2-4. déclarations qui masquent une procédure, un paquet, une fonction intégrée, une globale.
    var seenDecl = initHashSet[string]()
    for o in fa.occs:
      if o.kind notin {okParam, okLocalDecl, okGlobalDecl, okForVar, okCatchVar, okAssign}: continue
      let tag = $o.scope & ":" & o.name
      if tag in seenDecl: continue
      seenDecl.incl tag
      let isLocal = o.local or o.kind in {okParam, okLocalDecl, okForVar, okCatchVar}
      if o.name in procs:
        let p = procs[o.name][0]
        if isLocal:
          report(o, sevWarning, "« " & o.text & " » (" & $o.kind & ") porte le nom de la " & p.kind & " " &
                 p.display & " (" & where(p.file, p.line, source) & ") : ici, « " & o.text &
                 " » sans parenthèses désigne la variable")
        else:
          report(o, sevWarning, "la variable globale « " & o.text & " » porte le nom de la " & p.kind & " " &
                 p.display & " (" & where(p.file, p.line, source) & ") : « " & o.text &
                 " » sans parenthèses (ou @" & o.text & " dans un appel indirect) peut désigner l'une ou l'autre")
        continue
      let bk = builtinKind(o.name)
      if bk == "paquet":
        report(o, sevWarning, "« " & o.text & " » masque le paquet " & o.text.toLowerAscii & " : " &
               o.text & ".xxx(...) utilisera la variable" &
               (if not isLocal: " partout" elif o.scope == 0: " dans le programme principal" else: " dans cette procédure"))
        continue
      elif bk.len > 0 and not isTypeName(o.name):
        report(o, sevInfo, "« " & o.text & " » porte le nom d'une fonction intégrée : préférer un autre nom")
        continue
      if isLocal and o.scope > 0 and o.name in globals:
        let g = globals[o.name]
        report(o, sevInfo, "« " & o.text & " » (" & $o.kind & ") masque la variable globale du même nom (" &
               where(g.file, g.line, source) & ")")
    # 5-6. procédures : nom d'une fonction intégrée ou d'un paquet ; définitions multiples.
    var defined = initTable[string, Occ]()
    for o in fa.occs:
      if o.kind != okProcDef: continue
      let bk = builtinKind(o.name)
      if bk == "paquet":
        report(o, sevWarning, "la procédure « " & o.text & " » porte le nom du paquet " & o.text.toLowerAscii)
      elif bk.len > 0:
        report(o, sevWarning, "la procédure « " & o.text & " » remplace la fonction intégrée du même nom")
      if o.name in defined:
        let f = defined[o.name]
        report(o, sevWarning, "« " & o.text & " » est déjà définie ligne " & $(f.line + 1) &
               " : la dernière définition l'emporte")
      else:
        defined[o.name] = o
        for sg in procs.getOrDefault(o.name):
          if not sameFile(sg.file, source):
            report(o, sevError, "« " & o.text & " » est aussi définie dans " & where(sg.file, sg.line, source) &
                   " : erreur au chargement du programme")
            break

  if not opts.skipTypes:
    # types inconnus
    for o in fa.occs:
      if o.kind == okType and not isTypeName(o.name):
        report(o, sevInfo, "« " & o.text & " » n'est pas un type de base (nombre, entier, decimal, chaine, " &
               "logique, table, liste, procedure, objet, tache, quelconque) : contrôlé à l'exécution " &
               "comme nom d'objet natif")
    # types déclarés visibles : locales (par portée) et globales du fichier
    var gtypes = initTable[string, string]()
    for o in fa.occs:
      if o.kind == okGlobalDecl and o.typ.len > 0: gtypes[o.name] = o.typ
    proc declType(fa: FileAnalysis, sc: int, name: string, line: int): string =
      if name in fa.scopes[sc].locals:
        let d = fa.occs[fa.scopes[sc].locals[name]]
        if d.line <= line: return d.typ
        return ""
      gtypes.getOrDefault(name, "")
    proc check(diags: var seq[Diagnostic], row: seq[Sig], a, b: int, typ, what: string) =
      if typ.len == 0 or a >= b: return
      let lk = literalKind(row, a, b)
      if lk.len > 0 and not typeCompatible(typ, lk):
        diags.add Diagnostic(line: row[a].line, col: row[a].col,
                             len: max(1, row[b - 1].col + row[b - 1].text.len - row[a].col),
                             sev: sevWarning, msg: what & " : attendu " & typ & ", reçoit " &
                             (case lk
                              of "chaine": "une chaîne"
                              of "entier": "un entier"
                              of "decimal": "un décimal"
                              of "logique": "un logique"
                              of "table": "une table"
                              else: "nul") & " (erreur à l'exécution)")
    for row in fa.rows:
      if row.len == 0: continue
      let s = row[0]
      let sc = fa.scopeAt(s.line)
      if s.isKw("locale") or s.isKw("local") or s.isKw("globale"):
        for (a, b) in splitArgs(row, 1, row.len):
          if a < b and row[a].isName:
            var j = a + 1
            var typ = ""
            if j < b and row[j].text == ":" and j + 1 < b:
              typ = row[j + 1].text
              j += 2
              if j < b and row[j].text == "?":
                typ.add "?"
                inc j
            if j < b and row[j].text == "=":
              check(diags, row, j + 1, b, typ, "« " & row[a].text & " »")
      elif s.isName and row.len > 2 and row[1].text == "=":
        check(diags, row, 2, row.len, fa.declType(sc, upper(s.text), s.line), "« " & s.text & " »")
      elif (s.isKw("retourner") or s.isKw("retour")) and sc > 0 and fa.scopes[sc].ret.len > 0:
        if row.len == 1:
          if not typeCompatible(fa.scopes[sc].ret, "nul"):
            diags.add Diagnostic(line: s.line, col: s.col, len: s.text.len, sev: sevWarning,
                                 msg: "résultat attendu : " & fa.scopes[sc].ret)
        else:
          check(diags, row, 1, row.len, fa.scopes[sc].ret, "résultat de " & fa.scopes[sc].display)
      # appels avec arguments littéraux
      for i in 0 ..< row.len - 1:
        let x = row[i]
        if not x.isName or row[i + 1].text != "(": continue
        if i > 0 and (row[i - 1].text in [".", ":", "->"] or row[i - 1].isKw("procedure") or
                      row[i - 1].isKw("fonction")): continue
        let nm = upper(x.text)
        if nm in fa.scopes[sc].locals or nm notin procs: continue
        let sg = procs[nm][0]
        let close = closing(row, i + 1)
        let args = splitArgs(row, i + 2, close)
        if args.len > sg.params.len:
          diags.add Diagnostic(line: x.line, col: x.col, len: x.text.len, sev: sevWarning,
                               msg: $args.len & " arguments pour " & sg.display & " (" & $sg.params.len &
                               " paramètre" & (if sg.params.len > 1: "s" else: "") & ")")
        for k, (a, b) in args:
          if k < sg.paramTypes.len:
            check(diags, row, a, b, sg.paramTypes[k], "argument « " & sg.params[k] & " » de " & sg.display)
        for k in args.len ..< sg.paramTypes.len:
          let t = sg.paramTypes[k]
          if t.len > 0 and not typeCompatible(t, "nul"):
            diags.add Diagnostic(line: x.line, col: x.col, len: x.text.len, sev: sevWarning,
                                 msg: "argument « " & sg.params[k] & " : " & t & " » manquant pour " &
                                 sg.display & " (nul reçu : erreur à l'exécution)")
            break

proc lint*(lines: openArray[string], toks: openArray[seq[Token]],
           knownNames: HashSet[string], opts: LintOptions, source = "fichier",
           project: ProjectIndex = initProjectIndex()): seq[Diagnostic] =
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

  # 4-5. collisions de noms et types déclarés (sur la structure analysée).
  if ok and not (opts.skipCollisions and opts.skipTypes):
    namesAndTypes(analyse(lines, toks), project, source, opts, diags)

  diags.sort(proc (a, b: Diagnostic): int =
    result = cmp(a.line, b.line)
    if result == 0: result = cmp(a.col, b.col))
  diags

#
# Index de projet
#

proc indexFile*(idx: var ProjectIndex, path: string, text: string) =
  let lines = text.splitLines()
  let (toks, _) = lexAll(lines)
  let (syms, names) = collectSymbols(lines, toks)
  for n in names: idx.names.incl n
  for s in syms:
    if s.kind in {symProc, symFunc}:
      idx.defs.mgetOrPut(s.name, @[]).add Location(file: path, line: s.line, col: s.col)
  let fa = analyse(lines, toks)
  for sg in sigsOf(fa, path): idx.sigs.mgetOrPut(sg.name, @[]).add sg
  for (n, l, c) in globalsOf(fa): idx.globals.mgetOrPut(n, @[]).add Location(file: path, line: l, col: c)

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

#
# Graphe du projet (vue projet de l'atelier et lexis.graphe)
#

type
  PgEntity* = object
    name*: string                # majuscules
    display*: string             # nom(paramètres)
    kind*: SymKind               # symProc ou symFunc
    line*, lastLine*: int        # 0-based
    calls*: seq[string]          # procédures du projet appelées ou référencées (@NOM), majuscules

  PgFile* = object
    path*, rel*: string
    lines*: int
    entities*: seq[PgEntity]
    calls*: seq[string]          # appels du code de premier niveau (hors procédures)

  ProjectGraph* = object
    root*: string
    files*: seq[PgFile]

proc addOnce(s: var seq[string], v: string) =
  if v notin s: s.add v

proc graphFile*(path, rel, text: string): PgFile =
  # Procédures et fonctions d'un fichier, avec les noms appelés par chacune
  # (non filtrés : projectGraph ne garde que ceux définis dans le projet).
  let lines = text.splitLines()
  let (toks, _) = lexAll(lines)
  let rows = significant(lines, toks)
  result = PgFile(path: path, rel: rel, lines: lines.len)
  var cur = -1
  for row in rows:
    if row.len == 0: continue
    let s = row[0]
    if s.isKw("procedure") or s.isKw("fonction"):
      if row.len > 1 and row[1].isName:
        var params: seq[string]
        var i = 2
        if i < row.len and row[i].text == "(":
          inc i
          while i < row.len and row[i].text != ")":
            if row[i].isName: params.add row[i].text
            inc i
        result.entities.add PgEntity(name: upper(row[1].text),
                                     display: row[1].text & "(" & params.join(", ") & ")",
                                     kind: (if s.text == "procedure": symProc else: symFunc),
                                     line: s.line, lastLine: s.line)
        cur = result.entities.high
      continue
    if s.isKw("finprocedure") or s.isKw("finfonction"):
      if cur >= 0: result.entities[cur].lastLine = s.line
      cur = -1
      continue
    if cur >= 0: result.entities[cur].lastLine = s.line
    for i, x in row:
      if not x.isName: continue
      var nm = ""
      if i > 0 and row[i - 1].text == "@": nm = upper(x.text)                     # @NOM (rappel)
      elif i + 1 < row.len and row[i + 1].text == "(" and
           (i == 0 or row[i - 1].text notin [".", ":"]): nm = upper(x.text)       # NOM(...)
      if nm.len == 0: continue
      if cur >= 0:
        if nm != result.entities[cur].name: result.entities[cur].calls.addOnce nm
      else: result.calls.addOnce nm

proc projectGraph*(root: string): ProjectGraph =
  # Fichiers .prg du projet (dossiers cachés exclus), triés par chemin relatif ;
  # les appels ne retiennent que les procédures définies dans le projet.
  result.root = root
  if root.len == 0 or not dirExists(root): return
  var paths: seq[string]
  for f in walkDirRec(root, relative = true):
    if not f.toLowerAscii.endsWith(".prg"): continue
    var hidden = false
    for part in f.split({'/', '\\'}):
      if part.startsWith("."): hidden = true
    if not hidden: paths.add f
  paths.sort(proc (a, b: string): int =
    let da = a.count({'/', '\\'})
    let db = b.count({'/', '\\'})
    if da != db: cmp(da, db) else: cmp(a.toLowerAscii, b.toLowerAscii))
  var defined = initHashSet[string]()
  for rel in paths:
    let full = root / rel
    var f: PgFile
    try: f = graphFile(full, rel.replace('\\', '/'), readFile(full))
    except IOError, OSError: continue
    for e in f.entities: defined.incl e.name
    result.files.add f
  for f in result.files.mitems:
    f.calls.keepItIf(it in defined)
    for e in f.entities.mitems: e.calls.keepItIf(it in defined)
