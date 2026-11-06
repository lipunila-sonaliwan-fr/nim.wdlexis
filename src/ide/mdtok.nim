# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - éditeur de code : coloration Markdown
#
# Même interface que lexistok.nim / sqltok.nim (Token, LexState) : titres, citations,
# listes, blocs de code ``` (état lsLongString), code `en ligne`, **gras**, *italique*,
# liens [texte](adresse), tableaux | et commentaires <!-- -->.

import std/strutils
import lexistok

proc lexMdRaw(line: string, state: var LexState, depth: var int): seq[Token]

proc fillGaps*(line: string, toks: seq[Token]): seq[Token] =
  # Ajoute des jetons tkText entre les jetons (l'éditeur ne dessine que les jetons).
  var at = 0
  for t in toks:
    if t.start > at: result.add Token(kind: tkText, start: at, len: t.start - at)
    result.add t
    at = max(at, t.start + t.len)
  if at < line.len: result.add Token(kind: tkText, start: at, len: line.len - at)

proc lexMdLine*(line: string, state: var LexState, depth: var int): seq[Token] =
  fillGaps(line, lexMdRaw(line, state, depth))

proc lexMdRaw(line: string, state: var LexState, depth: var int): seq[Token] =
  depth = 0
  let n = line.len
  var i = 0
  while i < n and line[i] == ' ': inc i
  # bloc de code délimité
  if i + 3 <= n and line[i ..< i + 3] in ["```", "~~~"]:
    result.add Token(kind: tkString, start: 0, len: n)
    state = (if state == lsLongString: lsNormal else: lsLongString)
    return
  if state == lsLongString:
    if n > 0: result.add Token(kind: tkString, start: 0, len: n)
    return
  if state == lsBlockComment:
    let e = line.find("-->")
    if e < 0:
      if n > 0: result.add Token(kind: tkComment, start: 0, len: n)
      return
    result.add Token(kind: tkComment, start: 0, len: e + 3)
    state = lsNormal
    i = e + 3
  if i >= n: return
  # titre
  if line[i] == '#':
    result.add Token(kind: tkKeyword, start: i, len: n - i)
    return
  # citation
  if line[i] == '>':
    result.add Token(kind: tkComment, start: i, len: n - i)
    return
  # règle horizontale
  if n - i >= 3 and (line[i ..< n] == "---" or line[i ..< n] == "***" or line[i ..< n] == "___"):
    result.add Token(kind: tkPunct, start: i, len: n - i)
    return
  # puce ou numéro de liste
  if line[i] in {'-', '*', '+'} and i + 1 < n and line[i + 1] == ' ':
    result.add Token(kind: tkOperator, start: i, len: 1)
    i += 2
  elif line[i] in {'0'..'9'}:
    var j = i
    while j < n and line[j] in {'0'..'9'}: inc j
    if j < n and line[j] in {'.', ')'} and j + 1 < n and line[j + 1] == ' ':
      result.add Token(kind: tkNumber, start: i, len: j - i + 1)
      i = j + 2
  # en ligne
  while i < n:
    let c = line[i]
    if c == '`':
      var j = i + 1
      while j < n and line[j] != '`': inc j
      let e = min(n, j + 1)
      result.add Token(kind: tkString, start: i, len: e - i)
      i = e
    elif c == '<' and i + 3 < n and line[i ..< i + 4] == "<!--":
      let e = line.find("-->", i + 4)
      if e < 0:
        result.add Token(kind: tkComment, start: i, len: n - i)
        state = lsBlockComment
        return
      result.add Token(kind: tkComment, start: i, len: e + 3 - i)
      i = e + 3
    elif (c == '*' or c == '_') and i + 1 < n and line[i + 1] == c:
      let e = line.find(line[i .. i + 1], i + 2)
      if e < 0:
        inc i
        continue
      result.add Token(kind: tkType, start: i, len: e + 2 - i)
      i = e + 2
    elif (c == '*' or c == '_') and i + 1 < n and line[i + 1] != ' ' and (i == 0 or line[i - 1] in {' ', '(', '\t'}):
      var j = i + 1
      while j < n and line[j] != c: inc j
      if j >= n:
        inc i
        continue
      result.add Token(kind: tkBuiltin, start: i, len: j + 1 - i)
      i = j + 1
    elif c == '[' or (c == '!' and i + 1 < n and line[i + 1] == '['):
      let a = (if c == '!': i + 1 else: i)
      let b = line.find(']', a + 1)
      if b < 0:
        inc i
        continue
      result.add Token(kind: tkProcName, start: i, len: b + 1 - i)
      i = b + 1
      if i < n and line[i] == '(':
        let e = line.find(')', i)
        let stop = (if e < 0: n else: e + 1)
        result.add Token(kind: tkString, start: i, len: stop - i)
        i = stop
    elif c == '|':
      result.add Token(kind: tkPunct, start: i, len: 1)
      inc i
    else: inc i
