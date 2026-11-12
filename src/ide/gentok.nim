# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - éditeur de code : langages définis par les programmes (coloration générique)
#
# Un programme Lexis+ décrit un langage (ui.definirlangage) : mots-clés, types,
# fonctions, constantes, commentaires, chaînes, nombres, directives, annotations,
# variables préfixées ($x), balises (HTML/XML) et style des blocs (accolades,
# indentation, mots-clés de début et de fin, balises). L'éditeur colore alors tout
# document de ce langage (choisi par ed:langage ou d'après l'extension) et trace son
# diagramme de structure (CSD) dans la marge.
#
# Le registre est partagé entre les fils (interpréteurs et fil de l'interface) :
# il est protégé par un verrou, et l'éditeur lexe sous ce verrou.

import std/[strutils, sets, locks]
import lexistok

type
  BlockStyle* = enum
    bsBraces = "accolades", bsIndent = "indentation", bsKeywords = "motscles", bsTags = "balises"

  LangDef* = ref object
    name*: string
    title*: string                   # libellé (« Python », « C / C++ »...).
    exts*: seq[string]               # « .py », ou un nom de fichier exact (« makefile »).
    keywords*, types*, builtins*, constants*: HashSet[string]
    caseless*: bool                  # mots-clés insensibles à la casse (SQL, Pascal, BASIC...).
    lineComments*: seq[string]       # « // », « # », « -- »...
    blockOpen*, blockClose*: string  # « /* » « */ »
    docPrefixes*: seq[string]        # commentaires de documentation : « /// », « /** », « ## »...
    quotes*: string                  # délimiteurs de chaîne sur une ligne : "\"'"
    multiQuotes*: seq[string]        # chaînes sur plusieurs lignes : « """ », « ''' », « ` »
    escape*: bool                    # « \ » échappe dans les chaînes.
    directive*: string               # début de ligne de directive (« # » en C) : ligne entière.
    annotation*: char                # « @ » : @nom coloré comme une directive.
    varPrefix*: string               # « $ » : $nom, ${...} colorés comme des fonctions.
    identExtra*: set[char]           # caractères d'identificateur en plus de [A-Za-z0-9_] (« - » en CSS).
    procWords*: HashSet[string]      # mots suivis d'un nom de routine (def, function, fn, class...).
    callsAsProcs*: bool              # nom( coloré comme un nom de routine.
    markup*: bool                    # balises <a b="c"> (HTML, XML, SVG).
    blocks*: set[BlockStyle]
    routines*, conds*, loops*, tries*, sections*, branches*: HashSet[string]
    openers*, closers*, modifiers*: HashSet[string]   # style « motscles ».
    brackets*: bool                  # [ ] ouvrent aussi des blocs (JSON).
    comment*: string                 # marque utilisée pour commenter une ligne (Ctrl+B).
    indentAfter*: seq[string]        # fins de ligne qui augmentent l'indentation (« : », « { »).

var
  regLock: Lock
  registry: seq[LangDef]
initLock(regLock)

proc keyOf*(g: LangDef, w: string): string {.inline.} =
  if g.caseless: w.toLowerAscii else: w

proc registerLang*(g: LangDef) =
  ## Ajoute (ou remplace, même nom) une définition de langage.
  {.cast(gcsafe).}:
    withLock regLock:
      for i in 0 ..< registry.len:
        if registry[i].name == g.name:
          registry[i] = g
          return
      registry.add g

proc removeLang*(name: string) =
  {.cast(gcsafe).}:
    withLock regLock:
      for i in countdown(registry.high, 0):
        if registry[i].name == name: registry.delete(i)

proc langList*(): seq[tuple[name, title: string, exts: seq[string]]] =
  {.cast(gcsafe).}:
    withLock regLock:
      for g in registry: result.add (g.name, g.title, g.exts)

proc lookupNoLock(nameOrPath: string): LangDef =
  let k = nameOrPath.toLowerAscii
  for g in registry:
    if g.name == k: return g
  # d'après le nom du fichier exact, puis l'extension (la plus longue d'abord : « .d.ts »).
  let base = block:
    var p = k
    let s = max(p.rfind('/'), p.rfind('\\'))
    if s >= 0: p = p[s + 1 .. ^1]
    p
  for g in registry:
    for e in g.exts:
      if not e.startsWith(".") and e == base: return g
  var best: LangDef
  var bestLen = 0
  for g in registry:
    for e in g.exts:
      if e.startsWith(".") and base.endsWith(e) and e.len > bestLen:
        best = g
        bestLen = e.len
  best

proc hasLang*(nameOrPath: string): bool =
  {.cast(gcsafe).}:
    withLock regLock: result = lookupNoLock(nameOrPath) != nil

proc langNameFor*(nameOrPath: string): string =
  {.cast(gcsafe).}:
    withLock regLock:
      let g = lookupNoLock(nameOrPath)
      if g != nil: result = g.name

template withLang*(nameOrPath: string, g, body: untyped) =
  ## Exécute `body` avec la définition `g` (nil si inconnue), sous le verrou du registre.
  {.cast(gcsafe).}:
    withLock regLock:
      let g {.inject.} = lookupNoLock(nameOrPath)
      body

# lexer générique

proc isIdStart(g: LangDef, c: char): bool {.inline.} =
  c in {'a'..'z', 'A'..'Z', '_'} or ord(c) >= 128 or (c in g.identExtra and c notin {'0'..'9', '-'})

proc isId(g: LangDef, c: char): bool {.inline.} =
  c in {'a'..'z', 'A'..'Z', '0'..'9', '_'} or ord(c) >= 128 or c in g.identExtra

proc findClose(line: string, start: int, q: string, esc: bool): int =
  var j = start
  while j < line.len:
    if esc and line[j] == '\\':
      j += 2
      continue
    if line.continuesWith(q, j): return j
    inc j
  -1

const OpChars = {'+', '-', '*', '/', '%', '=', '<', '>', '!', '&', '|', '^', '~', '?', ':'}

proc lexMarkup(g: LangDef, line: string, state: var LexState, carry: var int): seq[Token] =
  # HTML / XML : carry = 1 à l'intérieur d'une balise ouverte sur plusieurs lignes.
  var i = 0
  let n = line.len
  template add(k: TokKind, a, b: int) =
    if b > a: result.add Token(kind: k, start: a, len: b - a)
  if state == lsBlockComment:
    let e = line.find("-->")
    if e < 0:
      add(tkComment, 0, n)
      return
    add(tkComment, 0, e + 3)
    i = e + 3
    state = lsNormal
  var inTag = carry == 1
  var afterLt = false
  while i < n:
    let c = line[i]
    if c in {' ', '\t'}:
      inc i
      continue
    if not inTag:
      if line.continuesWith("<!--", i):
        let e = line.find("-->", i + 4)
        if e < 0:
          add(tkComment, i, n)
          state = lsBlockComment
          carry = 0
          return
        add(tkComment, i, e + 3)
        i = e + 3
        continue
      if line.continuesWith("<![CDATA[", i):
        let e = line.find("]]>", i)
        let z = if e < 0: n else: e + 3
        add(tkString, i, z)
        i = z
        continue
      if line.continuesWith("<?", i) or line.continuesWith("<!", i):
        let e = line.find('>', i)
        let z = if e < 0: n else: e + 1
        add(tkPragma, i, z)
        i = z
        continue
      if c == '<':
        let z = if i + 1 < n and line[i + 1] == '/': i + 2 else: i + 1
        add(tkPunct, i, z)
        i = z
        inTag = true
        afterLt = true
        continue
      if c == '&':
        var j = i + 1
        while j < n and (line[j].isAlphaNumeric or line[j] == '#'): inc j
        if j < n and line[j] == ';':
          add(tkNumber, i, j + 1)
          i = j + 1
          continue
      # texte : jusqu'au prochain < ou &
      var j = i + 1
      while j < n and line[j] notin {'<', '&'}: inc j
      add(tkText, i, j)
      i = j
      continue
    # dans une balise
    if c == '>' or line.continuesWith("/>", i):
      let z = if c == '>': i + 1 else: i + 2
      add(tkPunct, i, z)
      i = z
      inTag = false
      continue
    if c in {'"', '\''}:
      var j = i + 1
      while j < n and line[j] != c: inc j
      let z = min(n, j + 1)
      add(tkString, i, z)
      i = z
      continue
    if c == '=':
      add(tkOperator, i, i + 1)
      inc i
      continue
    if c.isAlphaNumeric or c in {'_', ':', '-', '.'} or ord(c) >= 128:
      var j = i + 1
      while j < n and (line[j].isAlphaNumeric or line[j] in {'_', ':', '-', '.'} or ord(line[j]) >= 128): inc j
      add((if afterLt: tkKeyword else: tkType), i, j)
      afterLt = false
      i = j
      continue
    add(tkPunct, i, i + 1)
    inc i
  carry = (if inTag: 1 else: 0)

proc lexGenLine*(g: LangDef, line: string, state: var LexState, carry: var int): seq[Token] =
  ## Jetons d'une ligne ; `state` et `carry` passent d'une ligne à la suivante
  ## (commentaire de bloc ou chaîne multiligne en cours, balise ouverte).
  if g.markup: return lexMarkup(g, line, state, carry)
  var i = 0
  let n = line.len
  template add(k: TokKind, a, b: int) =
    if b > a: result.add Token(kind: k, start: a, len: b - a)
  if state == lsBlockComment:
    let e = if g.blockClose.len > 0: line.find(g.blockClose) else: -1
    if e < 0:
      add(tkComment, 0, n)
      return
    add(tkComment, 0, e + g.blockClose.len)
    i = e + g.blockClose.len
    state = lsNormal
  elif state == lsLongString:
    let q = if carry >= 0 and carry < g.multiQuotes.len: g.multiQuotes[carry] else: "\"\"\""
    let e = findClose(line, 0, q, g.escape)
    if e < 0:
      add(tkString, 0, n)
      return
    add(tkString, 0, e + q.len)
    i = e + q.len
    state = lsNormal
  # directive (préprocesseur C, #! ...) : la ligne entière.
  if i == 0 and g.directive.len > 0:
    var ind = 0
    while ind < n and line[ind] in {' ', '\t'}: inc ind
    if line.continuesWith(g.directive, ind):
      add(tkPragma, ind, n)
      return
  var afterProc = false
  while i < n:
    let c = line[i]
    if c in {' ', '\t'}:
      inc i
      continue
    # commentaires
    var isDoc = false
    for p in g.docPrefixes:
      if line.continuesWith(p, i):
        isDoc = true
        break
    var done = false
    for lc in g.lineComments:
      if line.continuesWith(lc, i):
        add((if isDoc: tkDocComment else: tkComment), i, n)
        done = true
        break
    if done: return
    if g.blockOpen.len > 0 and line.continuesWith(g.blockOpen, i):
      let e = line.find(g.blockClose, i + g.blockOpen.len)
      let k = if isDoc: tkDocComment else: tkComment
      if e < 0:
        add(k, i, n)
        state = lsBlockComment
        return
      add(k, i, e + g.blockClose.len)
      i = e + g.blockClose.len
      continue
    # chaînes multilignes, puis chaînes simples
    var matched = false
    for qi, q in g.multiQuotes:
      if line.continuesWith(q, i):
        let e = findClose(line, i + q.len, q, g.escape)
        if e < 0:
          add(tkString, i, n)
          state = lsLongString
          carry = qi
          return
        add(tkString, i, e + q.len)
        i = e + q.len
        matched = true
        break
    if matched: continue
    if c in g.quotes:
      var j = i + 1
      while j < n:
        if g.escape and line[j] == '\\':
          j += 2
          continue
        if line[j] == c: break
        inc j
      let z = min(n, j + 1)
      add(tkString, i, z)
      i = z
      continue
    # nombres
    if c in {'0'..'9'} or (c == '.' and i + 1 < n and line[i + 1] in {'0'..'9'}):
      var j = i + 1
      let hex = c == '0' and j < n and line[j] in {'x', 'X'}
      while j < n:
        let d = line[j]
        if d.isAlphaNumeric or d in {'.', '_'}: inc j
        elif d in {'+', '-'} and not hex and line[j - 1] in {'e', 'E'}: inc j
        else: break
      add(tkNumber, i, j)
      i = j
      continue
    # annotations (@nom) et variables ($nom, ${...})
    if g.annotation != '\0' and c == g.annotation and i + 1 < n and g.isIdStart(line[i + 1]):
      var j = i + 1
      while j < n and (g.isId(line[j]) or line[j] == '.'): inc j
      add(tkPragma, i, j)
      i = j
      continue
    if g.varPrefix.len > 0 and c in g.varPrefix and i + 1 < n:
      var j = i + 1
      if line[j] == '{':
        let e = line.find('}', j)
        j = if e < 0: n else: e + 1
      else:
        while j < n and (g.isId(line[j]) or line[j] in {'@', '#', '?', '*', '!'} and j == i + 1): inc j
      if j > i + 1:
        add(tkBuiltin, i, j)
        i = j
        continue
    # identificateurs
    if g.isIdStart(c):
      var j = i + 1
      while j < n and g.isId(line[j]): inc j
      let w = line[i ..< j]
      let k = g.keyOf(w)
      var kind = tkText
      if afterProc and k notin g.keywords: kind = tkProcName
      elif k in g.keywords: kind = tkKeyword
      elif k in g.types: kind = tkType
      elif k in g.constants: kind = tkNumber
      elif k in g.builtins: kind = tkBuiltin
      elif g.callsAsProcs:
        var p = j
        while p < n and line[p] == ' ': inc p
        if p < n and line[p] == '(': kind = tkProcName
      afterProc = k in g.procWords or (afterProc and k in g.keywords)
      add(kind, i, j)
      i = j
      continue
    afterProc = afterProc and c in {'*', '&'}
    if c in OpChars:
      var j = i + 1
      while j < n and line[j] in OpChars and j - i < 3: inc j
      add(tkOperator, i, j)
      i = j
      continue
    add(tkPunct, i, i + 1)
    inc i
