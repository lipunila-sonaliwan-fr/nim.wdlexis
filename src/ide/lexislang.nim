# Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr
#   wdlexis+ - atelier : coloration syntaxique de Lexis+
#
# Analyse lexicale ligne par ligne, avec un état de reprise (chaîne longue
# [[ ... ]] en cours), pour ne recalculer que les lignes modifiées.
# L'interpréteur a son propre analyseur (lexis/lexer.nim) ; celui-ci est fait
# pour la coloration : il ne lève jamais d'erreur et marque les jetons fautifs.
#
# Mis en évidence à part (couleur « spéciale ») : ? et ?? (affichage),
# @NOM (référence de procédure), -> (champ d'alias), mots pointés .et. .ou.

import std/[strutils, unicode]
import langdocs

type
  TokKind* = enum
    tkSpace       # blancs.
    tkIdent       # identifiant ordinaire.
    tkKeyword     # mot-clé Lexis+.
    tkBuiltin     # fonction intégrée ou paquet.
    tkCallback    # (réservé).
    tkNumber
    tkString
    tkEscape      # séquence d'échappement dans une chaîne.
    tkComment
    tkPod         # (réservé).
    tkOperator    # opérateur.
    tkPicoOp      # forme spéciale : ? ?? @ -> mots pointés.
    tkPunct       # ( ) [ ] { } , ;
    tkError       # caractère invalide, chaîne non terminée, nombre mal formé.

  Token* = object
    kind*: TokKind
    start*, len*: int     # position en octets dans la ligne.

  LexMode* = enum lmNormal, lmLongComment, lmLongString

  LexState* = object
    mode*: LexMode
    level*: int

const
  Keywords* = [
    # instructions
    "si", "sinonsi", "sinon", "finsi", "tantque", "fintantque", "faire", "cas", "autrement", "fincas",
    "pour", "chaque", "dans", "jusqua", "pas", "suivant", "finpour", "sortir", "boucler",
    "procedure", "fonction", "finprocedure", "finfonction", "parametres", "retourner", "retour",
    "locale", "local", "globale", "stocker", "liberer", "nouvelle", "table", "supprimer",
    "inserer", "retirer", "position", "clef", "cle", "fixermetatable", "comme",
    "essayer", "capturer", "finessayer", "erreur", "avec",
    "sql", "utiliser", "alias", "ordre", "filtre", "selectionner", "fermer", "tout", "aller",
    "haut", "bas", "debut", "sauter", "ajouter", "vide", "remplacer", "par", "effacer",
    "localiser", "continuer", "chercher", "parcourir", "finparcourir", "compter", "rafraichir",
    # opérateurs et valeurs
    "et", "ou", "non", "vrai", "faux", "nul"]

  # mots réservés trop courants pour être colorés partout (« a », « de », « fin »...)
  QuietWords* = ["a", "de", "du", "fin"]

  Op2 = ["==", "<>", "!=", "<=", ">=", "->", "..", "**", "??", "+=", "-="]
  Op1 = {'+', '-', '*', '/', '%', '^', '#', '$', '<', '>', '=', ':', '.'}
  Punct1 = {'(', ')', '[', ']', '{', '}', ',', ';'}
  dottedWords = ["et", "ou", "non", "v", "f", "t", "vrai", "faux", "nul", "and", "or", "not"]

proc isIdentStart(c: char): bool {.inline.} = c in {'a'..'z', 'A'..'Z', '_'} or ord(c) >= 128
proc isIdentChar*(c: char): bool {.inline.} = c in {'a'..'z', 'A'..'Z', '_', '0'..'9'} or ord(c) >= 128

proc same*(a, b: LexState): bool {.inline.} = a.mode == b.mode

proc isKeyword*(s: string): bool = s in Keywords

proc tokText*(line: string, t: Token): string {.inline.} =
  line[t.start ..< min(line.len, t.start + t.len)]

proc lexLine*(s: string, st: var LexState): seq[Token] =
  ## Découpe une ligne en jetons. `st` est l'état à l'entrée de la ligne ;
  ## il contient l'état de sortie au retour.
  var i = 0
  template push(k: TokKind, a, b: int) =
    if b > a: result.add Token(kind: k, start: a, len: b - a)

  if st.mode == lmLongString:
    let close = s.find("]]")
    if close < 0:
      push(tkString, 0, s.len)
      return
    push(tkString, 0, close + 2)
    i = close + 2
    st = LexState(mode: lmNormal)

  var startOfInstr = true
  while i < s.len:
    let c = s[i]
    if c in {' ', '\t', '\r'}:
      var j = i
      while j < s.len and s[j] in {' ', '\t', '\r'}: inc j
      push(tkSpace, i, j)
      i = j
      continue
    if (c == '&' and i + 1 < s.len and s[i + 1] == '&') or (c == '/' and i + 1 < s.len and s[i + 1] == '/') or
       (c == '*' and startOfInstr):
      push(tkComment, i, s.len)
      return
    startOfInstr = false
    if c == '[' and i + 1 < s.len and s[i + 1] == '[':
      let close = s.find("]]", i + 2)
      if close < 0:
        push(tkString, i, s.len)
        st = LexState(mode: lmLongString)
        return
      push(tkString, i, close + 2)
      i = close + 2
    elif c in {'"', '\''}:
      var j = i + 1
      var segStart = i
      var closed = false
      while j < s.len:
        if s[j] == '\\' and j + 1 < s.len:
          push(tkString, segStart, j)
          push(tkEscape, j, j + 2)
          j += 2
          segStart = j
        elif s[j] == c:
          inc j
          closed = true
          break
        else: inc j
      j = min(j, s.len)
      push(if closed: tkString else: tkError, segStart, j)
      i = j
    elif c in Digits:
      var j = i
      while j < s.len and s[j] in Digits: inc j
      if j + 1 < s.len and s[j] == '.' and s[j + 1] in Digits:
        inc j
        while j < s.len and s[j] in Digits: inc j
      if j < s.len and s[j] in {'e', 'E'}:
        var k = j + 1
        if k < s.len and s[k] in {'+', '-'}: inc k
        if k < s.len and s[k] in Digits:
          j = k
          while j < s.len and s[j] in Digits: inc j
      var ok = true
      if j < s.len and isIdentStart(s[j]):
        ok = false
        while j < s.len and isIdentChar(s[j]): inc j
      push(if ok: tkNumber else: tkError, i, j)
      i = j
    elif c == '.' and i + 1 < s.len and s[i + 1] in {'a'..'z', 'A'..'Z'}:
      var j = i + 1
      while j < s.len and s[j] in {'a'..'z', 'A'..'Z'}: inc j
      if j < s.len and s[j] == '.' and s[i + 1 ..< j].toLowerAscii in dottedWords:
        push(tkPicoOp, i, j + 1)
        i = j + 1
      else:
        push(tkOperator, i, i + 1)
        inc i
    elif isIdentStart(c):
      var j = i
      while j < s.len and isIdentChar(s[j]): inc j
      let w = s[i ..< j]
      let k =
        if isKeyword(w): tkKeyword
        elif isBuiltin(w): tkBuiltin
        else: tkIdent
      push(k, i, j)
      i = j
    elif c == '@':
      var j = i + 1
      while j < s.len and isIdentChar(s[j]): inc j
      push(tkPicoOp, i, j)
      i = j
    elif c == '?':
      let n = if i + 1 < s.len and s[i + 1] == '?': 2 else: 1
      push(tkPicoOp, i, i + n)
      i += n
    elif c in Punct1:
      push(tkPunct, i, i + 1)
      inc i
    else:
      var matched = ""
      if i + 1 < s.len and s[i ..< i + 2] in Op2: matched = s[i ..< i + 2]
      elif c in Op1: matched = $c
      if matched.len > 0:
        push(if matched == "->": tkPicoOp else: tkOperator, i, i + matched.len)
        i += matched.len
      else:
        var j = i + 1
        while j < s.len and (ord(s[j]) and 0xC0) == 0x80: inc j
        push(tkError, i, j)
        i = j

proc lexAll*(lines: openArray[string]): (seq[seq[Token]], seq[LexState]) =
  ## Jetons de toutes les lignes et état d'entrée de chaque ligne
  ## (le tableau d'états a une case de plus : l'état en fin de texte).
  var st = LexState()
  var toks = newSeq[seq[Token]](lines.len)
  var states = newSeq[LexState](lines.len + 1)
  for i, l in lines:
    states[i] = st
    toks[i] = lexLine(l, st)
  states[lines.len] = st
  (toks, states)

proc upper*(s: string): string = unicode.toUpper(s)
