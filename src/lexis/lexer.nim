# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - analyse lexicale de Lexis+
#
#   - identifiants insensibles à la casse (normalisés en majuscules), lettres
#     accentuées admises ; « à » s'écrit aussi « a » ;
#   - fins de ligne = fins d'instruction, sauf entre parenthèses, crochets ou
#     accolades, ou après un « ; » final (continuation à la dBase) ;
#   - commentaires : && et // jusqu'à la fin de la ligne, * en début d'instruction ;
#   - mots pointés de dBase : .et. .ou. .non. .v. .f. .vrai. .faux. .nul. ;
#   - chaînes "..." ou '...' (échappements \n \t \r \\ \" \') et [[ ... ]] multilignes.

import std/[strutils, unicode]
import core

type
  TokKind* = enum tkName, tkNum, tkStr, tkOp, tkEOL, tkEOF

  Tok* = object
    kind*: TokKind
    text*: string        # texte tel qu'écrit (nom, opérateur) ou contenu décodé (chaîne).
    up*: string          # nom en majuscules.
    isInt*: bool
    ival*: int64
    nval*: float64
    line*, col*: int

  SyntaxError* = object of CatchableError
    line*: int
    source*: string
    msg0*: string        # message sans position.

const dottedWords = ["et", "ou", "non", "v", "f", "t", "vrai", "faux", "nul", "and", "or", "not"]

proc synErr*(source: string, line: int, msg: string) {.noreturn.} =
  var e = newException(SyntaxError, source & ":" & $line & ": " & msg)
  e.line = line
  e.source = source
  e.msg0 = msg
  raise e

proc isIdentStart(c: char): bool {.inline.} = c in {'a'..'z', 'A'..'Z', '_'} or ord(c) >= 128
proc isIdentChar(c: char): bool {.inline.} = c in {'a'..'z', 'A'..'Z', '_', '0'..'9'} or ord(c) >= 128

proc tokenize*(src, source: string): seq[Tok] =
  var toks: seq[Tok]      # pas de `result` partiel si une erreur remonte.
  var i = 0
  var line = 1
  var lineStart = 0
  var depth = 0
  var startOfInstr = true
  let n = src.len
  template err(msg: string) = synErr(source, line, msg)
  template add(t: Tok) =
    toks.add t
    startOfInstr = false
  template endOfLine() =
    if depth == 0 and toks.len > 0 and toks[^1].kind != tkEOL:
      toks.add Tok(kind: tkEOL, line: line, col: i - lineStart)
    if depth == 0: startOfInstr = true

  if src.startsWith("#!"):
    while i < n and src[i] != '\n': inc i

  while i < n:
    let c = src[i]
    let col = i - lineStart
    if c == '\n':
      endOfLine()
      inc line
      inc i
      lineStart = i
      continue
    if c in {' ', '\t', '\r', '\f', '\v'}:
      inc i
      continue
    # commentaires
    if c == '*' and startOfInstr:
      while i < n and src[i] != '\n': inc i
      continue
    if (c == '&' and i + 1 < n and src[i + 1] == '&') or (c == '/' and i + 1 < n and src[i + 1] == '/'):
      while i < n and src[i] != '\n': inc i
      continue
    # « ; » : continuation en fin de ligne, séparateur sinon
    if c == ';':
      var j = i + 1
      while j < n and src[j] in {' ', '\t', '\r'}: inc j
      if j + 1 < n and src[j] == '&' and src[j + 1] == '&':
        while j < n and src[j] != '\n': inc j
      if j >= n or src[j] == '\n':
        i = j
        if i < n:
          inc line
          inc i
          lineStart = i
        continue
      if depth > 0: add Tok(kind: tkOp, text: ";", line: line, col: col)
      else: endOfLine()
      inc i
      continue
    # nombres
    if c in Digits:
      var j = i
      var isInt = true
      while j < n and src[j] in Digits: inc j
      if j + 1 < n and src[j] == '.' and src[j + 1] in Digits:
        isInt = false
        inc j
        while j < n and src[j] in Digits: inc j
      if j < n and src[j] in {'e', 'E'}:
        var k = j + 1
        if k < n and src[k] in {'+', '-'}: inc k
        if k < n and src[k] in Digits:
          isInt = false
          j = k
          while j < n and src[j] in Digits: inc j
      if j < n and isIdentStart(src[j]): err("nombre mal formé près de « " & src[i .. j] & " »")
      let t = src[i ..< j]
      var tk = Tok(kind: tkNum, text: t, line: line, col: col)
      if isInt:
        try:
          tk.ival = parseBiggestInt(t)
          tk.isInt = true
        except ValueError:
          tk.nval = parseFloat(t)
      else: tk.nval = parseFloat(t)
      add tk
      i = j
      continue
    # chaînes "..." '...'
    if c in {'"', '\''}:
      var s = ""
      var j = i + 1
      var closed = false
      while j < n:
        let d = src[j]
        if d == c:
          closed = true
          break
        if d == '\n': err("chaîne non terminée")
        if d == '\\' and j + 1 < n:
          case src[j + 1]
          of 'n': s.add '\n'
          of 't': s.add '\t'
          of 'r': s.add '\r'
          of '\\': s.add '\\'
          of '"': s.add '"'
          of '\'': s.add '\''
          else:
            s.add '\\'
            s.add src[j + 1]
          j += 2
          continue
        s.add d
        inc j
      if not closed: err("chaîne non terminée")
      add Tok(kind: tkStr, text: s, line: line, col: col)
      i = j + 1
      continue
    # chaînes longues [[ ... ]]
    if c == '[' and i + 1 < n and src[i + 1] == '[':
      let fin = src.find("]]", i + 2)
      if fin < 0: err("chaîne longue [[ ... ]] non terminée")
      var s = src[i + 2 ..< fin]
      if s.startsWith("\r\n"): s = s[2 .. ^1]
      elif s.startsWith("\n"): s = s[1 .. ^1]
      let l0 = line
      for k in i ..< fin:
        if src[k] == '\n':
          inc line
          lineStart = k + 1
      add Tok(kind: tkStr, text: s, line: l0, col: col)
      i = fin + 2
      continue
    # mots pointés .et. .ou. .non. .v. .f. ...
    if c == '.' and i + 1 < n and src[i + 1] in {'a'..'z', 'A'..'Z'}:
      var j = i + 1
      while j < n and src[j] in {'a'..'z', 'A'..'Z'}: inc j
      if j < n and src[j] == '.':
        let w = src[i + 1 ..< j].toLowerAscii
        if w in dottedWords:
          let m = case w
                  of "v", "t", "vrai": "vrai"
                  of "f", "faux": "faux"
                  of "and": "et"
                  of "or": "ou"
                  of "not": "non"
                  else: w
          add Tok(kind: tkName, text: m, up: m.toUpperAscii, line: line, col: col)
          i = j + 1
          continue
    # identifiants
    if isIdentStart(c):
      var j = i
      while j < n and isIdentChar(src[j]): inc j
      var t = src[i ..< j]
      if t == "à": t = "a"
      add Tok(kind: tkName, text: t, up: unicode.toUpper(t), line: line, col: col)
      i = j
      continue
    # opérateurs
    var op = ""
    if i + 2 < n and src[i ..< i + 3] == "...": op = "..."
    elif i + 1 < n:
      let two = src[i ..< i + 2]
      if two in ["==", "<>", "!=", "<=", ">=", "->", "..", "**", "??", "+=", "-="]: op = two
    if op == "":
      if c in {'+', '-', '*', '/', '%', '^', '(', ')', '[', ']', '{', '}', ',', ':',
               '=', '<', '>', '#', '$', '.', '?', '@'}:
        op = $c
      else:
        var j = i + 1
        while j < n and (ord(src[j]) and 0xC0) == 0x80: inc j
        err("caractère inattendu : « " & src[i ..< j] & " »")
    case op
    of "(", "[", "{": inc depth
    of ")", "]", "}":
      if depth > 0: dec depth
    else: discard
    add Tok(kind: tkOp, text: op, line: line, col: col)
    i += op.len
  endOfLine()
  toks.add Tok(kind: tkEOF, line: line, col: 0)
  result = toks
