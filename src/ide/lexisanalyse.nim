# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - analyse des noms d'un fichier Lexis+ (portées, déclarations, usages)
#
# Sert au vérificateur (collisions de noms, types déclarés), au service de langage
# (infobulles, aller à la définition, usages, renommage) et au serveur LSP.
#
# Analyse par jetons (lexislang) : elle ne lève jamais d'erreur, même sur un
# texte en cours de frappe. Résolution comme l'interpréteur : un nom déclaré
# plus haut dans la procédure (paramètre, locale, pour, capturer, parametres)
# est local ; tout autre nom est global (variable globale, procédure, paquet,
# fonction intégrée). Lexis+ est insensible à la casse : clefs en majuscules.

import std/[strutils, tables, sets]
import lexislang, langdocs

type
  Sig* = object
    kind*: TokKind
    text*: string
    line*, col*: int              # 0-based ; colonne en octets

  OccKind* = enum
    okProcDef = "définition"      # nom après procedure / fonction
    okParam = "paramètre"
    okLocalDecl = "locale"        # locale / local / parametres
    okGlobalDecl = "globale"      # globale x
    okForVar = "variable de boucle"
    okCatchVar = "variable d'erreur"
    okAssign = "affectation"      # x = ... (x non déclaré : variable globale implicite)
    okUse = "lecture"
    okCall = "appel"              # NOM(...)
    okRef = "référence"           # @NOM
    okMember = "membre"           # .nom ou :nom (champ, fonction de paquet, méthode)
    okType = "type"               # nom de type après « : »

  Occ* = object
    name*: string                 # majuscules
    text*: string                 # orthographe écrite
    line*, col*: int
    kind*: OccKind
    scope*: int                   # indice dans FileAnalysis.scopes
    local*: bool                  # résolu comme variable locale de la portée
    typ*: string                  # type déclaré (déclarations), tel qu'écrit
    owner*: string                # okMember : nom qui précède (« binaire » dans binaire.oux)
    isMethod*: bool               # okMember écrit obj:methode

  Scope* = object
    name*: string                 # majuscules ; "" pour le programme principal
    display*: string              # NOM(a, b)
    kind*: string                 # procedure, fonction, principal
    line*, col*, lastLine*: int
    params*, paramTypes*: seq[string]
    ret*: string                  # type déclaré du résultat
    doc*: string                  # commentaires qui précèdent l'en-tête
    locals*: Table[string, int]   # nom -> indice de l'occurrence de déclaration

  FileAnalysis* = object
    lines*: seq[string]
    rows*: seq[seq[Sig]]
    scopes*: seq[Scope]
    occs*: seq[Occ]

const
  TypeNames* = ["nombre", "entier", "decimal", "chaine", "logique", "table", "liste",
                "procedure", "fonction", "objet", "tache", "quelconque", "tout", "texte", "reel", "booleen"]

proc isTypeName*(s: string): bool = s.toLowerAscii in TypeNames

proc significant*(lines: openArray[string], toks: openArray[seq[Token]]): seq[seq[Sig]] =
  ## Jetons significatifs, ligne par ligne ; une instruction continuée (« ; » en
  ## fin de ligne) est rangée en entier sur sa première ligne.
  result = newSeq[seq[Sig]](min(lines.len, toks.len))
  var start = -1
  for li in 0 ..< result.len:
    let target = if start >= 0: start else: li
    for t in toks[li]:
      if t.kind notin {tkSpace, tkComment, tkPod}:
        result[target].add Sig(kind: t.kind, text: tokText(lines[li], t), line: li, col: t.start)
    if result[target].len > 0 and result[target][^1].text == ";":
      result[target].setLen(result[target].len - 1)
      start = target
    else:
      start = -1

proc isName*(s: Sig): bool {.inline.} = s.kind in {tkIdent, tkBuiltin, tkCallback}
proc isKw*(s: Sig, w: string): bool {.inline.} = s.kind == tkKeyword and s.text == w
proc isTypeTok(s: Sig): bool {.inline.} = s.kind in {tkIdent, tkBuiltin, tkKeyword}

proc docBefore(lines: openArray[string], line: int): string =
  # Commentaires (&&, //, &&&, ///) juste au-dessus d'une ligne.
  var parts: seq[string]
  var i = line - 1
  while i >= 0:
    let s = lines[i].strip
    if s.startsWith("&&") or s.startsWith("//"):
      var t = s
      while t.len > 0 and t[0] in {'&', '/'}: t = t[1 .. ^1]
      parts.insert(t.strip, 0)
      dec i
    else: break
  parts.join("\n")

proc analyse*(lines: openArray[string], toks: openArray[seq[Token]]): FileAnalysis =
  var fa = FileAnalysis(lines: @lines)
  fa.rows = significant(lines, toks)
  fa.scopes.add Scope(name: "", display: "programme principal", kind: "principal",
                      lastLine: max(0, lines.len - 1), locals: initTable[string, int]())
  var cur = 0
  var lastProc = -1

  template add(o: Occ) =
    fa.occs.add o

  proc declLocal(fa: var FileAnalysis, sc: int, s: Sig, k: OccKind, typ = "") =
    let nm = upper(s.text)
    fa.occs.add Occ(name: nm, text: s.text, line: s.line, col: s.col, kind: k, scope: sc,
                    local: true, typ: typ)
    if nm notin fa.scopes[sc].locals: fa.scopes[sc].locals[nm] = fa.occs.high

  proc typeAt(row: seq[Sig], i: int): (string, int) =
    # « : type [?] » à partir de row[i] (le « : ») ; renvoie (texte, indice suivant).
    if i + 1 < row.len and row[i].text == ":" and row[i + 1].isTypeTok:
      var t = row[i + 1].text
      var j = i + 2
      if j < row.len and row[j].text == "?":
        t.add "?"
        inc j
      return (t, j)
    ("", i)

  proc exprNames(fa: var FileAnalysis, sc: int, row: seq[Sig], a, b: int, skip: HashSet[int]) =
    # Usages dans row[a ..< b] : appels, lectures, membres, références, clefs de table.
    var brackets: seq[string]
    for i in a ..< min(b, row.len):
      let s = row[i]
      if s.text in ["(", "[", "{"]: brackets.add s.text
      elif s.text in [")", "]", "}"]:
        if brackets.len > 0: discard brackets.pop()
      if i in skip: continue
      if s.kind == tkPicoOp and s.text.len > 1 and s.text[0] == '@':
        let nm = s.text[1 .. ^1]
        fa.occs.add Occ(name: upper(nm), text: nm, line: s.line, col: s.col + 1, kind: okRef, scope: sc)
        continue
      # mot-clé employé comme nom de variable locale (locale vide = …) : c'est un usage
      if not s.isName and not (s.kind == tkKeyword and upper(s.text) in fa.scopes[sc].locals): continue
      let prev = if i > a: row[i - 1].text else: ""
      let next = if i + 1 < row.len: row[i + 1].text else: ""
      if prev in [".", ":", "->"] and i > a:
        var o = Occ(name: upper(s.text), text: s.text, line: s.line, col: s.col, kind: okMember,
                    scope: sc, isMethod: prev == ":")
        if i >= 2 and row[i - 2].isName: o.owner = row[i - 2].text
        fa.occs.add o
        continue
      # clef de table : {nom = 1, autre = 2}
      if next == "=" and brackets.len > 0 and brackets[^1] == "{" and prev in ["{", ","]: continue
      let nm = upper(s.text)
      let isLocal = nm in fa.scopes[sc].locals
      let k = if next in ["(", "{"]: okCall else: okUse
      fa.occs.add Occ(name: nm, text: s.text, line: s.line, col: s.col, kind: k, scope: sc,
                      local: isLocal and k == okUse or (isLocal and k == okCall))

  for row in fa.rows:
    if row.len == 0: continue
    let s = row[0]
    if s.isKw("procedure") or s.isKw("fonction"):
      if lastProc >= 0: fa.scopes[lastProc].lastLine = max(fa.scopes[lastProc].line, s.line - 1)
      var sc = Scope(kind: s.text, line: s.line, col: s.col, lastLine: max(0, lines.len - 1),
                     locals: initTable[string, int]())
      sc.doc = docBefore(lines, s.line)
      fa.scopes.add sc
      cur = fa.scopes.high
      lastProc = cur
      if row.len > 1 and row[1].isName:
        fa.scopes[cur].name = upper(row[1].text)
        fa.occs.add Occ(name: upper(row[1].text), text: row[1].text, line: row[1].line, col: row[1].col,
                        kind: okProcDef, scope: 0)
        var shown: seq[string]
        var i = 2
        if i < row.len and row[i].text == "(":
          inc i
          while i < row.len and row[i].text != ")":
            if row[i].isName or (row[i].kind == tkKeyword and row[i - 1].text in ["(", ","]):
              let p = row[i]
              var (t, j) = typeAt(row, i + 1)
              fa.scopes[cur].params.add p.text
              fa.scopes[cur].paramTypes.add t
              fa.declLocal(cur, p, okParam, t)
              shown.add(if t.len > 0: p.text & " : " & t else: p.text)
              if t.len > 0:
                fa.occs.add Occ(name: upper(row[i + 2].text), text: row[i + 2].text, line: row[i + 2].line,
                                col: row[i + 2].col, kind: okType, scope: cur)
                i = j
                continue
            inc i
          if i < row.len: inc i              # « ) »
        let (rt, _) = typeAt(row, i)
        fa.scopes[cur].ret = rt
        fa.scopes[cur].display = row[1].text & "(" & shown.join(", ") & ")" & (if rt.len > 0: " : " & rt else: "")
      continue
    if s.isKw("finprocedure") or s.isKw("finfonction"):
      if cur > 0: fa.scopes[cur].lastLine = s.line
      lastProc = -1
      cur = 0
      continue
    var skip = initHashSet[int]()
    if s.isKw("locale") or s.isKw("local") or s.isKw("parametres") or s.isKw("globale"):
      # noms déclarés (et types) ; le reste de la ligne : valeurs initiales.
      var i = 1
      var depth = 0
      var expectName = true
      var pendingDecls: seq[(Sig, string)]
      while i < row.len:
        let x = row[i]
        if x.text in ["(", "[", "{"]: inc depth
        elif x.text in [")", "]", "}"]: dec depth
        elif depth == 0 and x.text == ",": expectName = true
        elif depth == 0 and expectName and (x.isName or x.kind == tkKeyword):
          let (t, j) = typeAt(row, i + 1)
          pendingDecls.add (x, t)
          skip.incl i
          if t.len > 0:
            for k in i + 1 ..< j: skip.incl k
            fa.occs.add Occ(name: upper(row[i + 2].text), text: row[i + 2].text, line: row[i + 2].line,
                            col: row[i + 2].col, kind: okType, scope: cur)
            i = j
            expectName = false
            continue
          expectName = false
        elif depth == 0: expectName = false
        inc i
      # valeurs évaluées avant la déclaration (comme l'interpréteur)
      fa.exprNames(cur, row, 1, row.len, skip)
      for (x, t) in pendingDecls:
        if s.isKw("globale"):
          fa.scopes[cur].locals.del(upper(x.text))
          fa.occs.add Occ(name: upper(x.text), text: x.text, line: x.line, col: x.col, kind: okGlobalDecl,
                          scope: cur, typ: t)
        else:
          fa.declLocal(cur, x, okLocalDecl, t)
      continue
    if s.isKw("pour"):
      var i = 1
      if i < row.len and row[i].isKw("chaque"): inc i
      var vars: seq[Sig]
      while i < row.len and (row[i].isName or row[i].text == ","):
        if row[i].isName:
          vars.add row[i]
          skip.incl i
        inc i
      fa.exprNames(cur, row, 1, row.len, skip)
      for v in vars: fa.declLocal(cur, v, okForVar)
      continue
    if s.isKw("capturer") and row.len > 1 and row[1].isName:
      fa.declLocal(cur, row[1], okCatchVar)
      continue
    if s.isKw("stocker") or s.isKw("compter") or s.isKw("sql") or s.isKw("retirer"):
      var after = -1
      for i, x in row:
        if x.isKw("dans"): after = i
      if after > 0:
        fa.exprNames(cur, row, 1, after, skip)
        for i in after + 1 ..< row.len:
          if row[i].isName and (i == after + 1 or row[i - 1].text == ","):
            let nm = upper(row[i].text)
            fa.occs.add Occ(name: nm, text: row[i].text, line: row[i].line, col: row[i].col, kind: okAssign,
                            scope: cur, local: nm in fa.scopes[cur].locals)
            skip.incl i
        fa.exprNames(cur, row, after + 1, row.len, skip)
      else: fa.exprNames(cur, row, 1, row.len, skip)
      continue
    if s.isName and row.len > 1 and row[1].text in ["=", "+=", "-="]:
      let nm = upper(s.text)
      fa.occs.add Occ(name: nm, text: s.text, line: s.line, col: s.col, kind: okAssign, scope: cur,
                      local: nm in fa.scopes[cur].locals)
      skip.incl 0
      fa.exprNames(cur, row, 0, row.len, skip)
      continue
    fa.exprNames(cur, row, 0, row.len, skip)
  fa

proc analyseText*(text: string): FileAnalysis =
  let lines = text.replace("\r\n", "\n").split('\n')
  let (toks, _) = lexAll(lines)
  analyse(lines, toks)

proc scopeAt*(fa: FileAnalysis, line: int): int =
  ## Portée (procédure) qui contient la ligne ; 0 = programme principal.
  result = 0
  for i in 1 ..< fa.scopes.len:
    if line >= fa.scopes[i].line and line <= fa.scopes[i].lastLine: result = i

proc occAt*(fa: FileAnalysis, line, col: int): int =
  ## Occurrence sous la position (colonne en octets), -1 sinon.
  for i, o in fa.occs:
    if o.line == line and col >= o.col and col <= o.col + o.text.len: return i
  -1

proc isDecl*(o: Occ): bool =
  o.kind in {okProcDef, okParam, okLocalDecl, okGlobalDecl, okForVar, okCatchVar}

proc isVariableOcc*(o: Occ): bool =
  o.kind in {okParam, okLocalDecl, okGlobalDecl, okForVar, okCatchVar, okAssign, okUse}

proc symbolKey*(fa: FileAnalysis, o: Occ): string =
  ## Clef du symbole désigné : « L<portée>:NOM » (variable locale) ou « G:NOM ».
  if o.kind in {okMember, okType}: return ""
  if o.local or (o.kind in {okUse, okCall} and o.name in fa.scopes[o.scope].locals and
                 fa.occs[fa.scopes[o.scope].locals[o.name]].line <= o.line):
    return "L" & $o.scope & ":" & o.name
  "G:" & o.name

proc typeCompatible*(typ, literal: string): bool =
  ## Un littéral (« chaine », « entier », « decimal », « logique », « table », « nul »)
  ## est-il accepté par le type déclaré ?
  var t = typ.toLowerAscii
  let nullable = t.endsWith("?")
  if nullable: t = t[0 .. ^2]
  case literal
  of "nul": nullable or t in ["quelconque", "tout"]
  of "chaine": t in ["chaine", "texte", "quelconque", "tout"] or t notin TypeNames
  of "entier": t in ["nombre", "entier", "decimal", "reel", "quelconque", "tout"] or t notin TypeNames
  of "decimal": t in ["nombre", "decimal", "reel", "quelconque", "tout"] or t notin TypeNames
  of "logique": t in ["logique", "booleen", "quelconque", "tout"] or t notin TypeNames
  of "table": t in ["table", "liste", "objet", "procedure", "fonction", "quelconque", "tout"] or t notin TypeNames
  else: true

proc literalKind*(row: seq[Sig], a, b: int): string =
  ## Genre d'une expression réduite à un littéral (row[a ..< b]) ; "" sinon.
  if b - a == 1:
    let s = row[a]
    case s.kind
    of tkString: return "chaine"
    of tkNumber:
      return (if '.' in s.text or ('e' in s.text.toLowerAscii and not s.text.startsWith("0x")): "decimal" else: "entier")
    of tkKeyword:
      if s.text in ["vrai", "faux"]: return "logique"
      if s.text == "nul": return "nul"
    else: discard
  if b - a == 2 and row[a].text == "-" and row[a + 1].kind == tkNumber:
    return literalKind(row, a + 1, b)
  if b - a >= 2 and row[a].text == "{" and row[b - 1].text == "}":
    var depth = 0
    for i in a ..< b:
      if row[i].text in ["(", "[", "{"]: inc depth
      elif row[i].text in [")", "]", "}"]:
        dec depth
        if depth == 0 and i < b - 1: return ""
    return "table"
  # chaîne sur plusieurs jetons (échappements)
  var allStr = b > a
  for i in a ..< b:
    if row[i].kind notin {tkString, tkEscape}: allStr = false
  if allStr and row[a].col + 0 >= 0:
    var contiguous = true
    for i in a + 1 ..< b:
      if row[i].line != row[i - 1].line or row[i].col != row[i - 1].col + row[i - 1].text.len: contiguous = false
    if contiguous: return "chaine"
  ""

proc builtinKind*(name: string): string =
  ## « paquet », « fonction intégrée » ou "" (nom libre).
  let n = name.toLowerAscii
  for p in packageNames():
    if p == n: return "paquet"
  if isBuiltin(name): return "fonction intégrée"
  ""
