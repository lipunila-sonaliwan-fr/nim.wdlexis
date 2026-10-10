# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - atelier : jetons de coloration au format de l'éditeur de wdnim
#
# L'éditeur (codeeditor.nim) est un portage de celui de wdnim, qui attend
# l'interface de son nimlexer : TokKind (12 catégories), Token, LexState,
# lexLine(line, state, depth) et codeTail. Ce module la fournit pour Lexis+
# en s'appuyant sur lexislang.nim.

from lexislang as ll import nil

type
  TokKind* = enum
    tkText, tkKeyword, tkType, tkBuiltin, tkProcName, tkString, tkNumber,
    tkComment, tkDocComment, tkPragma, tkOperator, tkPunct
  Token* = object
    kind*: TokKind
    start*, len*: int            # octets dans la ligne.
  LexState* = enum
    lsNormal, lsBlockComment, lsLongString

proc lexLine*(line: string, state: var LexState, depth: var int): seq[Token] =
  ## Jetons d'une ligne ; `state` pour la suivante (chaîne longue [[ ]] en cours).
  var st = ll.LexState()
  st.mode = if state == lsLongString: ll.lmLongString else: ll.lmNormal
  let toks = ll.lexLine(line, st)
  state = if st.mode == ll.lmLongString: lsLongString else: lsNormal
  depth = 0
  var afterProc = false
  for t in toks:
    let txt = ll.tokText(line, t)
    var k: TokKind
    case t.kind
    of ll.tkSpace:
      continue
    of ll.tkKeyword:
      k = tkKeyword
      afterProc = txt in ["procedure", "fonction"]
    of ll.tkIdent, ll.tkCallback:
      if afterProc: k = tkProcName
      elif txt.len > 1 and txt == ll.upper(txt) and txt[0] in {'A'..'Z'}: k = tkType   # NOMS en majuscules
      else: k = tkText
      afterProc = false
    of ll.tkBuiltin:
      k = if afterProc: tkProcName else: tkBuiltin
      afterProc = false
    of ll.tkNumber: k = tkNumber
    of ll.tkString, ll.tkEscape: k = tkString
    of ll.tkComment, ll.tkPod:
      k = if txt.len >= 3 and txt[0 .. 2] in ["&&&", "///"]: tkDocComment else: tkComment
    of ll.tkPicoOp: k = tkPragma                 # ? ?? @NOM -> .et.
    of ll.tkOperator: k = tkOperator
    of ll.tkPunct:
      k = tkPunct
      afterProc = false
    of ll.tkError: k = tkPragma
    result.add Token(kind: k, start: t.start, len: t.len)

proc codeTail*(line: string, toks: seq[Token]): char =
  ## Dernier caractère significatif de la ligne, hors commentaires (' ' si aucun).
  for i in countdown(toks.high, 0):
    let t = toks[i]
    if t.kind notin {tkComment, tkDocComment}:
      return line[t.start + t.len - 1]
  ' '
