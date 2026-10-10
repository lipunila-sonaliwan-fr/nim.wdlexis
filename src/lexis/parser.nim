# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - analyse syntaxique de Lexis+
#
# Un fichier contient :
#   - éventuellement des instructions en tête : le programme principal ;
#   - des procédures et fonctions :  procedure NOM[(a, b)] ... [finprocedure]
#     (le corps s'arrête à la procédure suivante ou à finprocedure / finfonction).
#
# Résolution des noms : une variable déclarée plus haut dans la procédure par
# locale, un paramètre, pour, pour chaque, parametres ou capturer est une case
# du cadre d'appel ; tout autre nom est résolu à l'exécution (champ de la zone
# courante, variable globale, procédure). « globale x » rend x global pour la
# suite de la procédure.

import std/[strutils, tables]
import core, lexer

type
  FuncState = ref object
    proto: Proto
    names: Table[string, int]      # nom (majuscules) -> case
    loops: int

  Parser = object
    toks: seq[Tok]
    p: int
    fs: FuncState
    source: string

  Program* = object
    main*: Proto                   # instructions en tête de fichier (corps éventuellement vide)
    procs*: seq[Proto]             # procédures et fonctions (nom en majuscules)

const
  instrWords = [
    "si", "tantque", "pour", "sortir", "boucler", "faire", "parametres",
    "locale", "local", "globale", "retourner", "retour", "stocker",
    "nouvelle", "supprimer", "inserer", "retirer", "fixermetatable", "sql", "utiliser",
    "selectionner", "fermer", "aller", "sauter", "ajouter", "remplacer", "effacer",
    "localiser", "continuer", "chercher", "parcourir", "compter", "liberer",
    "erreur", "essayer", "rafraichir",
    # réservés aux pages du serveur wdGestion V
    "envoyer", "inclure", "rediriger", "statut", "entete", "deconnecter",
    # mots de structure (erreur s'ils apparaissent hors de leur construction)
    "sinon", "sinonsi", "finsi", "fintantque", "suivant", "finpour", "cas",
    "autrement", "fincas", "finparcourir", "capturer", "finessayer",
    "procedure", "fonction", "finprocedure", "finfonction"]
  serverOnly = ["envoyer", "inclure", "rediriger", "statut", "entete", "deconnecter"]
  procEnd = ["procedure", "fonction", "finprocedure", "finfonction"]

# ------------------------------------------------------------------ outils

proc cur(ps: Parser): Tok {.inline.} = ps.toks[ps.p]
proc peekTok(ps: Parser, k = 1): Tok {.inline.} = ps.toks[min(ps.p + k, ps.toks.high)]
proc advance(ps: var Parser): Tok {.discardable.} =
  result = ps.toks[ps.p]
  if ps.p < ps.toks.high: inc ps.p

proc describe(t: Tok): string =
  case t.kind
  of tkEOL: "fin de ligne"
  of tkEOF: "fin du fichier"
  of tkStr: "\"" & t.text & "\""
  else: "« " & t.text & " »"

proc err(ps: Parser, msg: string) {.noreturn.} =
  synErr(ps.source, ps.cur.line, msg)

proc isWord(t: Tok, w: string): bool {.inline.} = t.kind == tkName and t.text == w
proc isOp(t: Tok, o: string): bool {.inline.} = t.kind == tkOp and t.text == o
proc isWord(ps: Parser, w: string): bool {.inline.} = ps.cur.isWord(w)
proc isOp(ps: Parser, o: string): bool {.inline.} = ps.cur.isOp(o)

proc expectOp(ps: var Parser, o: string) =
  if not ps.isOp(o): ps.err("« " & o & " » attendu au lieu de " & describe(ps.cur))
  ps.advance()

proc expectWord(ps: var Parser, w: string) =
  if not ps.isWord(w): ps.err("« " & w & " » attendu au lieu de " & describe(ps.cur))
  ps.advance()

proc expectName(ps: var Parser): Tok =
  if ps.cur.kind != tkName: ps.err("identifiant attendu au lieu de " & describe(ps.cur))
  ps.advance()

proc atEnd(ps: Parser): bool {.inline.} = ps.cur.kind in {tkEOL, tkEOF}

proc endInstr(ps: var Parser) =
  if ps.cur.kind == tkEOF: return
  if ps.cur.kind != tkEOL: ps.err("fin d'instruction attendue au lieu de " & describe(ps.cur))
  while ps.cur.kind == tkEOL: ps.advance()

proc skipLines(ps: var Parser) =
  while ps.cur.kind == tkEOL: ps.advance()

# ------------------------------------------------------------------ portée

proc declare(ps: var Parser, name: string): int =
  ## Déclare (ou retrouve) une variable locale de la procédure en cours.
  let up = cle(name)
  if ps.fs.names.hasKey(up): return ps.fs.names[up]
  let pr = ps.fs.proto
  result = pr.nslots
  inc pr.nslots
  pr.slotNames.add name
  ps.fs.names[up] = result

proc resolve(ps: Parser, t: Tok): Expr =
  let s = ps.fs.names.getOrDefault(t.up, -1)
  if s >= 0: Expr(kind: ekLocal, slot: s, vname: t.text, line: t.line)
  else: Expr(kind: ekName, gname: t.up, line: t.line)

# ------------------------------------------------------------------ expressions

proc expr(ps: var Parser): Expr

proc args(ps: var Parser): seq[Expr] =
  var res: seq[Expr]
  ps.expectOp("(")
  if not ps.isOp(")"):
    res.add ps.expr()
    while ps.isOp(","):
      ps.advance()
      res.add ps.expr()
  ps.expectOp(")")
  result = res

proc tableCons(ps: var Parser): Expr =
  let line = ps.cur.line
  ps.expectOp("{")
  var res = Expr(kind: ekTable, line: line)
  while not ps.isOp("}"):
    if ps.isOp("["):
      ps.advance()
      let k = ps.expr()
      ps.expectOp("]")
      ps.expectOp("=")
      let v = ps.expr()
      res.items.add TItem(keyed: true, key: k, val: v)
    elif ps.cur.kind == tkName and ps.peekTok().isOp("="):
      let nt = ps.advance()
      ps.advance()
      let v = ps.expr()
      res.items.add TItem(keyed: true, key: Expr(kind: ekStr, sval: nt.up, line: nt.line), val: v)
    else:
      let v = ps.expr()
      res.items.add TItem(keyed: false, val: v)
    if ps.isOp(",") or ps.isOp(";"): ps.advance()
    elif not ps.isOp("}"):
      ps.err("« , » ou « } » attendu dans la table (ouverte ligne " & $line & ") au lieu de " & describe(ps.cur))
  ps.advance()
  result = res

proc primary(ps: var Parser): Expr =
  let t = ps.cur
  case t.kind
  of tkNum:
    ps.advance()
    if t.isInt: Expr(kind: ekInt, ival: t.ival, line: t.line)
    else: Expr(kind: ekNum, nval: t.nval, line: t.line)
  of tkStr:
    ps.advance()
    Expr(kind: ekStr, sval: t.text, line: t.line)
  of tkName:
    case t.text
    of "vrai":
      ps.advance()
      Expr(kind: ekTrue, line: t.line)
    of "faux":
      ps.advance()
      Expr(kind: ekFalse, line: t.line)
    of "nul":
      ps.advance()
      Expr(kind: ekNil, line: t.line)
    else:
      if t.up == "SISINON" and ps.peekTok().isOp("("):
        ps.advance()
        let a = ps.args()
        if a.len != 3: synErr(ps.source, t.line, "sisinon(condition, valeur_si_vrai, valeur_si_faux) attend 3 arguments")
        Expr(kind: ekIif, cnd: a[0], yes: a[1], no: a[2], line: t.line)
      else:
        ps.advance()
        ps.resolve(t)
  of tkOp:
    if t.text == "(":
      ps.advance()
      let e = ps.expr()
      ps.expectOp(")")
      Expr(kind: ekParen, e: e, line: t.line)
    elif t.text == "{":
      ps.tableCons()
    elif t.text == "@":
      ps.advance()
      let id = ps.expectName()
      Expr(kind: ekProcRef, gname: id.up, line: t.line)
    else:
      ps.err("expression attendue au lieu de " & describe(t))
  else:
    ps.err("expression attendue au lieu de " & describe(t))

proc postfix(ps: var Parser): Expr =
  var res = ps.primary()
  while true:
    let t = ps.cur
    if t.isOp("."):
      ps.advance()
      let id = ps.expectName()
      res = Expr(kind: ekIndex, obj: res, key: Expr(kind: ekStr, sval: id.up, line: id.line), line: t.line)
    elif t.isOp("["):
      ps.advance()
      let k = ps.expr()
      ps.expectOp("]")
      res = Expr(kind: ekIndex, obj: res, key: k, line: t.line)
    elif t.isOp("("):
      let a = ps.args()
      res = Expr(kind: ekCall, fn: res, args: a, line: t.line)
    elif t.isOp("{") and res.kind in {ekName, ekLocal, ekIndex}:
      # appel avec une table d'options : ui.fenetre{titre = "x"}  ==  ui.fenetre({titre = "x"})
      let tc = ps.tableCons()
      res = Expr(kind: ekCall, fn: res, args: @[tc], line: t.line)
    elif t.isOp(":"):
      if ps.peekTok().isWord("procedure"): break        # association t:procedure NOM
      ps.advance()
      let id = ps.expectName()
      let a = if ps.isOp("{"): @[ps.tableCons()] else: ps.args()
      res = Expr(kind: ekMethod, mobj: res, mname: id.up, margs: a, line: t.line)
    elif t.isOp("->"):
      let alias = case res.kind
        of ekName: res.gname
        of ekLocal: cle(res.vname)
        else: ps.err("« -> » doit suivre un alias de zone")
      ps.advance()
      let id = ps.expectName()
      res = Expr(kind: ekField, alias: alias, field: id.up, line: t.line)
    else: break
  result = res

proc unary(ps: var Parser): Expr

proc power(ps: var Parser): Expr =
  var res = ps.postfix()
  if ps.isOp("^") or ps.isOp("**"):
    let t = ps.advance()
    let r = ps.unary()
    res = Expr(kind: ekBin, op: opPow, lhs: res, rhs: r, line: t.line)
  result = res

proc unary(ps: var Parser): Expr =
  let t = ps.cur
  if t.isOp("-"):
    ps.advance()
    let operand = ps.unary()
    if operand.kind == ekInt: return Expr(kind: ekInt, ival: -operand.ival, line: t.line)
    if operand.kind == ekNum: return Expr(kind: ekNum, nval: -operand.nval, line: t.line)
    return Expr(kind: ekNeg, e: operand, line: t.line)
  if t.isOp("#"):
    ps.advance()
    let operand = ps.unary()
    return Expr(kind: ekLen, e: operand, line: t.line)
  if t.isOp("+"):
    ps.advance()
    return ps.unary()
  ps.power()

proc multiplicative(ps: var Parser): Expr =
  var res = ps.unary()
  while ps.cur.kind == tkOp and ps.cur.text in ["*", "/", "%"]:
    let t = ps.advance()
    let op = case t.text
             of "*": opMul
             of "/": opDiv
             else: opMod
    let r = ps.unary()
    res = Expr(kind: ekBin, op: op, lhs: res, rhs: r, line: t.line)
  result = res

proc additive(ps: var Parser): Expr =
  var res = ps.multiplicative()
  while ps.cur.kind == tkOp and ps.cur.text in ["+", "-"]:
    let t = ps.advance()
    let r = ps.multiplicative()
    res = Expr(kind: ekBin, op: (if t.text == "+": opAdd else: opSub), lhs: res, rhs: r, line: t.line)
  result = res

proc concat(ps: var Parser): Expr =
  var res = ps.additive()
  if ps.isOp(".."):
    let t = ps.advance()
    let r = ps.concat()
    res = Expr(kind: ekBin, op: opConcat, lhs: res, rhs: r, line: t.line)
  result = res

proc comparison(ps: var Parser): Expr =
  var res = ps.concat()
  while ps.cur.kind == tkOp and ps.cur.text in ["=", "==", "<>", "!=", "#", "<", ">", "<=", ">=", "$"]:
    let t = ps.advance()
    let op = case t.text
             of "=", "==": opEq
             of "<>", "!=", "#": opNe
             of "<": opLt
             of ">": opGt
             of "<=": opLe
             of ">=": opGe
             else: opIn
    let r = ps.concat()
    res = Expr(kind: ekBin, op: op, lhs: res, rhs: r, line: t.line)
  result = res

proc negation(ps: var Parser): Expr =
  if ps.isWord("non"):
    let t = ps.advance()
    let e = ps.negation()
    return Expr(kind: ekNot, e: e, line: t.line)
  ps.comparison()

proc conjunction(ps: var Parser): Expr =
  var res = ps.negation()
  while ps.isWord("et"):
    let t = ps.advance()
    let r = ps.negation()
    res = Expr(kind: ekAnd, a: res, b: r, line: t.line)
  result = res

proc expr(ps: var Parser): Expr =
  var res = ps.conjunction()
  while ps.isWord("ou"):
    let t = ps.advance()
    let r = ps.conjunction()
    res = Expr(kind: ekOr, a: res, b: r, line: t.line)
  result = res

proc exprList(ps: var Parser): seq[Expr] =
  var res = @[ps.expr()]
  while ps.isOp(","):
    ps.advance()
    res.add ps.expr()
  result = res

proc isTarget(e: Expr): bool = e.kind in {ekLocal, ekName, ekIndex}

proc target(ps: var Parser): Expr =
  let line = ps.cur.line
  let e = ps.postfix()
  if not e.isTarget: synErr(ps.source, line, "cible d'affectation invalide")
  e

proc nameOrExpr(ps: var Parser): Expr =
  ## Un identifiant seul est pris comme nom littéral ; sinon expression.
  let t = ps.cur
  if t.kind == tkName and not ps.peekTok().isOp(".") and not ps.peekTok().isOp("(") and
     not ps.peekTok().isOp("[") and not ps.peekTok().isOp("->"):
    ps.advance()
    return Expr(kind: ekStr, sval: t.text, line: t.line)
  ps.expr()

# ------------------------------------------------------------------ instructions

proc statement(ps: var Parser): Stmt

proc blockUntil(ps: var Parser, ends: openArray[string]): seq[Stmt] =
  var res: seq[Stmt]
  while true:
    ps.skipLines()
    if ps.cur.kind == tkEOF: break
    if ps.cur.kind == tkName and ps.cur.text in ends: break
    res.add ps.statement()
  result = res

proc closeBlock(ps: var Parser, word: string, openLine: int, opener: string) =
  if not ps.isWord(word):
    synErr(ps.source, ps.cur.line, "« " & word & " » manquant pour « " & opener & " » (ligne " & $openLine & ")")
  ps.advance()

proc loopBody(ps: var Parser, ends: openArray[string]): seq[Stmt] =
  inc ps.fs.loops
  result = ps.blockUntil(ends)
  dec ps.fs.loops

proc mk(kind: StmtKind, line: int): Stmt {.inline.} = Stmt(kind: kind, line: line)

proc zone(zk: ZoneKind, line: int): Stmt {.inline.} = Stmt(kind: skZone, zk: zk, line: line)

proc statement(ps: var Parser): Stmt =
  let t = ps.cur
  var res: Stmt
  if t.kind == tkOp and t.text in ["?", "??"]:
    ps.advance()
    res = mk(skPrint, t.line)
    res.flag = t.text == "?"
    if not ps.atEnd(): res.e = ps.exprList()
    ps.endInstr()
    return res
  if t.kind == tkName and t.text in instrWords and
     not (t.text in ["fixermetatable", "inserer", "retirer"] and ps.peekTok().isOp("(")) and
     not ps.peekTok().isOp("=") and not ps.peekTok().isOp(".") and not ps.peekTok().isOp("[") and
     not ps.peekTok().isOp("+=") and not ps.peekTok().isOp("-=") and not ps.peekTok().isOp(":"):
    let w = t.text
    ps.advance()
    case w
    of "si":
      res = mk(skIf, t.line)
      res.e.add ps.expr()
      ps.endInstr()
      res.blocks.add ps.blockUntil(["sinonsi", "sinon", "finsi"])
      while true:
        if ps.isWord("sinonsi") or (ps.isWord("sinon") and ps.peekTok().isWord("si")):
          if ps.isWord("sinon"): ps.advance()
          ps.advance()
          res.e.add ps.expr()
          ps.endInstr()
          res.blocks.add ps.blockUntil(["sinonsi", "sinon", "finsi"])
        elif ps.isWord("sinon"):
          ps.advance()
          ps.endInstr()
          res.blocks.add ps.blockUntil(["finsi"])
          break
        else: break
      ps.closeBlock("finsi", t.line, "si")
    of "tantque":
      res = mk(skWhile, t.line)
      res.e.add ps.expr()
      ps.endInstr()
      res.body = ps.loopBody(["fintantque"])
      ps.closeBlock("fintantque", t.line, "tantque")
    of "faire":
      if ps.isWord("tantque"):
        ps.advance()
        res = mk(skWhile, t.line)
        res.e.add ps.expr()
        ps.endInstr()
        res.body = ps.loopBody(["fintantque"])
        ps.closeBlock("fintantque", t.line, "faire tantque")
      elif ps.isWord("cas"):
        ps.advance()
        ps.endInstr()
        res = mk(skIf, t.line)
        ps.skipLines()
        while ps.isWord("cas"):
          ps.advance()
          res.e.add ps.expr()
          ps.endInstr()
          res.blocks.add ps.blockUntil(["cas", "autrement", "fincas"])
        if ps.isWord("autrement"):
          ps.advance()
          ps.endInstr()
          res.blocks.add ps.blockUntil(["fincas"])
        ps.closeBlock("fincas", t.line, "faire cas")
      else:
        let id = ps.expectName()
        var a: seq[Expr]
        if ps.isWord("avec"):
          ps.advance()
          a = ps.exprList()
        res = mk(skCall, t.line)
        res.e.add Expr(kind: ekCall, fn: Expr(kind: ekName, gname: id.up, line: id.line), args: a, line: t.line)
    of "pour":
      if ps.isWord("chaque"):
        ps.advance()
        res = mk(skForEach, t.line)
        var names = @[ps.expectName()]
        if ps.isOp(","):
          ps.advance()
          names.add ps.expectName()
        ps.expectWord("dans")
        res.e.add ps.expr()
        ps.endInstr()
        for nm in names: res.slots.add ps.declare(nm.text)
        res.body = ps.loopBody(["suivant", "finpour"])
        if not (ps.isWord("suivant") or ps.isWord("finpour")):
          ps.closeBlock("suivant", t.line, "pour chaque")
        ps.advance()
        if ps.cur.kind == tkName: ps.advance()           # suivant x
      else:
        res = mk(skNumFor, t.line)
        let v = ps.expectName()
        ps.expectOp("=")
        res.e.add ps.expr()
        if not (ps.isWord("a") or ps.isWord("jusqua")):
          ps.err("« a » (ou « jusqua ») attendu dans « pour » au lieu de " & describe(ps.cur))
        ps.advance()
        res.e.add ps.expr()
        if ps.isWord("pas"):
          ps.advance()
          res.e.add ps.expr()
        ps.endInstr()
        res.slots.add ps.declare(v.text)
        res.body = ps.loopBody(["suivant", "finpour"])
        if not (ps.isWord("suivant") or ps.isWord("finpour")):
          ps.closeBlock("suivant", t.line, "pour")
        ps.advance()
        if ps.cur.kind == tkName: ps.advance()
    of "sortir":
      if ps.fs.loops == 0: synErr(ps.source, t.line, "« sortir » hors d'une boucle")
      res = mk(skBreak, t.line)
    of "boucler":
      if ps.fs.loops == 0: synErr(ps.source, t.line, "« boucler » hors d'une boucle")
      res = mk(skContinue, t.line)
    of "parametres":
      res = mk(skParams, t.line)
      ps.fs.proto.usesArgs = true
      res.slots.add ps.declare(ps.expectName().text)
      while ps.isOp(","):
        ps.advance()
        res.slots.add ps.declare(ps.expectName().text)
    of "locale", "local":
      # plusieurs déclarations : une instruction par nom (valeur évaluée avant la déclaration)
      var group: seq[Stmt]
      while true:
        let nm = ps.expectName()
        let s = mk(skLocal, nm.line)
        if ps.isOp("="):
          ps.advance()
          s.e.add ps.expr()
        s.slots.add ps.declare(nm.text)
        group.add s
        if ps.isOp(","): ps.advance() else: break
      if group.len == 1: res = group[0]
      else:
        res = mk(skIf, t.line)            # bloc toujours exécuté : si vrai ... finsi
        res.e.add Expr(kind: ekTrue, line: t.line)
        res.blocks.add group
    of "globale":
      var group: seq[Stmt]
      while true:
        let nm = ps.expectName()
        ps.fs.names.del(nm.up)
        let s = mk(skGlobal, nm.line)
        s.name = nm.up
        if ps.isOp("="):
          ps.advance()
          s.e.add ps.expr()
        group.add s
        if ps.isOp(","): ps.advance() else: break
      if group.len == 1: res = group[0]
      else:
        res = mk(skIf, t.line)
        res.e.add Expr(kind: ekTrue, line: t.line)
        res.blocks.add group
    of "retourner", "retour":
      res = mk(skReturn, t.line)
      if not ps.atEnd(): res.e.add ps.expr()
    of "stocker":
      res = mk(skStore, t.line)
      res.e.add ps.expr()
      ps.expectWord("dans")
      res.e.add ps.target()
      while ps.isOp(","):
        ps.advance()
        res.e.add ps.target()
    of "nouvelle":
      ps.expectWord("table")
      res = mk(skNewTable, t.line)
      res.e.add ps.target()
      if ps.isOp("="):
        ps.advance()
        res.e.add ps.expr()
    of "supprimer":
      ps.expectWord("table")
      res = mk(skFree, t.line)
      res.e.add ps.target()
    of "liberer":
      res = mk(skFree, t.line)
      res.e.add ps.resolve(ps.expectName())
      while ps.isOp(","):
        ps.advance()
        res.e.add ps.resolve(ps.expectName())
    of "inserer":
      res = mk(skInsert, t.line)
      res.e.add ps.expr()
      ps.expectWord("dans")
      res.e.add ps.postfix()
      if ps.isWord("position") or ps.isWord("clef") or ps.isWord("cle"):
        res.name = (if ps.cur.text == "position": "position" else: "clef")
        ps.advance()
        res.e.add ps.expr()
    of "retirer":
      res = mk(skRemove, t.line)
      if ps.isWord("de") or ps.isWord("du"): ps.advance()
      res.e = @[ps.postfix(), nil, nil]
      if ps.isWord("position") or ps.isWord("clef") or ps.isWord("cle"):
        res.name = (if ps.cur.text == "position": "position" else: "clef")
        ps.advance()
        res.e[1] = ps.expr()
      if ps.isWord("dans"):
        ps.advance()
        res.e[2] = ps.target()
    of "fixermetatable":
      res = mk(skSetMeta, t.line)
      res.e.add ps.expr()
      ps.expectOp(",")
      res.e.add ps.expr()
    of "sql":
      res = mk(skSql, t.line)
      res.e = @[ps.expr(), nil]
      if ps.isWord("avec"):
        ps.advance()
        res.e.add ps.exprList()
      if ps.isWord("dans"):
        ps.advance()
        res.e[1] = ps.target()
    of "erreur":
      res = mk(skError, t.line)
      res.e.add ps.expr()
    of "essayer":
      res = mk(skTry, t.line)
      ps.endInstr()
      res.blocks.add ps.blockUntil(["capturer", "finessayer"])
      res.slots.add -1
      if ps.isWord("capturer"):
        ps.advance()
        if ps.cur.kind == tkName: res.slots[0] = ps.declare(ps.advance().text)
        ps.endInstr()
        res.blocks.add ps.blockUntil(["finessayer"])
      ps.closeBlock("finessayer", t.line, "essayer")
    # ---------------------------------------------------- zones de travail
    of "utiliser":
      res = zone(zkUse, t.line)
      res.e = @[nil, nil, nil]
      if not ps.atEnd():
        res.e[0] = ps.nameOrExpr()
        while not ps.atEnd():
          if ps.isWord("alias"):
            ps.advance()
            res.name = ps.expectName().up
          elif ps.isWord("ordre"):
            ps.advance()
            res.e[1] = ps.expr()
          elif ps.isWord("filtre"):
            ps.advance()
            res.e[2] = ps.expr()
          else: ps.err("« alias », « ordre » ou « filtre » attendu au lieu de " & describe(ps.cur))
    of "selectionner":
      res = zone(zkSelect, t.line)
      res.e.add ps.nameOrExpr()
    of "fermer":
      res = zone(zkClose, t.line)
      if ps.isWord("tout"):
        res.name = "*"
        ps.advance()
      elif ps.cur.kind == tkName: res.name = ps.advance().up
    of "aller":
      res = zone(zkGo, t.line)
      if ps.isWord("haut") or ps.isWord("debut"):
        res.name = "haut"
        ps.advance()
      elif ps.isWord("bas") or ps.isWord("fin"):
        res.name = "bas"
        ps.advance()
      else: res.e.add ps.expr()
    of "sauter":
      res = zone(zkSkip, t.line)
      if not ps.atEnd(): res.e.add ps.expr()
    of "ajouter", "remplacer":
      res = zone((if w == "ajouter": zkAppend else: zkReplace), t.line)
      if w == "ajouter" and ps.isWord("vide"): ps.advance()
      if w == "ajouter" and ps.isWord("avec"): ps.advance()
      if w == "remplacer" or not ps.atEnd():
        while true:
          res.names.add ps.expectName().text
          ps.expectWord("par")
          res.e.add ps.expr()
          if ps.isOp(","): ps.advance() else: break
    of "effacer": res = zone(zkDelete, t.line)
    of "continuer": res = zone(zkContinue, t.line)
    of "rafraichir": res = zone(zkRefresh, t.line)
    of "localiser":
      res = zone(zkLocate, t.line)
      if ps.isWord("pour"): ps.advance()
      res.e.add ps.expr()
    of "chercher":
      res = zone(zkSeek, t.line)
      res.e.add ps.expr()
    of "parcourir":
      res = zone(zkScan, t.line)
      if ps.isWord("pour"):
        ps.advance()
        res.e.add ps.expr()
      else: res.e.add nil
      ps.endInstr()
      res.body = ps.loopBody(["finparcourir"])
      ps.closeBlock("finparcourir", t.line, "parcourir")
    of "compter":
      res = zone(zkCount, t.line)
      res.e = @[nil, nil]
      if ps.isWord("pour"):
        ps.advance()
        res.e[0] = ps.expr()
      ps.expectWord("dans")
      res.e[1] = ps.target()
    of "procedure", "fonction":
      synErr(ps.source, t.line, "« " & w & " » inattendu : procédure imbriquée ou bloc non fermé")
    else:
      if w in serverOnly:
        synErr(ps.source, t.line, "« " & w & " » est réservé aux pages du serveur wdGestion V")
      synErr(ps.source, t.line, "« " & w & " » inattendu ici (bloc non ouvert ?)")
    ps.endInstr()
    return res

  # ---- affectation, appel, association de procédure
  let line = t.line
  let e = ps.postfix()
  if ps.isOp("="):
    if not e.isTarget: ps.err("cible d'affectation invalide")
    ps.advance()
    res = mk(skAssign, line)
    let v = ps.expr()
    res.e = @[e, v]
  elif ps.isOp("+=") or ps.isOp("-="):
    if not e.isTarget: ps.err("cible d'affectation invalide")
    res = mk(skCompound, line)
    res.op = if ps.cur.text == "+=": opAdd else: opSub
    ps.advance()
    let v = ps.expr()
    res.e = @[e, v]
  elif ps.isOp(":") and ps.peekTok().isWord("procedure"):
    ps.advance()
    ps.advance()
    res = mk(skAssoc, line)
    res.e = @[e]
    res.name = ps.expectName().up
    res.name2 = res.name
    if ps.isWord("comme"):
      ps.advance()
      if ps.cur.kind == tkStr: res.name2 = ps.advance().text
      else: res.name2 = ps.expectName().up
  elif e.kind in {ekCall, ekMethod}:
    res = mk(skCall, line)
    res.e = @[e]
  else:
    synErr(ps.source, line, "instruction inconnue ou incomplète" &
           (if t.kind == tkName: " : « " & t.text & " »" else: ""))
  ps.endInstr()
  result = res

# ------------------------------------------------------------------ points d'entrée

proc newFunc(ps: var Parser, name: string, line: int): FuncState =
  FuncState(proto: Proto(name: name, source: ps.source, line: line), names: initTable[string, int]())

proc parseChunk*(src, source: string): Program =
  ## Analyse un fichier ; lève SyntaxError (message « source:ligne: ... »).
  var ps = Parser(toks: tokenize(src, source), source: source)
  var prog: Program
  ps.fs = ps.newFunc("programme principal", 1)
  prog.main = ps.fs.proto
  let mainFs = ps.fs
  while true:
    ps.skipLines()
    if ps.cur.kind == tkEOF: break
    if ps.isWord("procedure") or ps.isWord("fonction"):
      let t = ps.advance()
      let id = ps.expectName()
      ps.fs = ps.newFunc(id.up, t.line)
      let pr = ps.fs.proto
      if ps.isOp("("):
        ps.advance()
        if not ps.isOp(")"):
          while true:
            discard ps.declare(ps.expectName().text)
            inc pr.nparams
            if ps.isOp(","): ps.advance() else: break
        ps.expectOp(")")
      ps.endInstr()
      pr.body = ps.blockUntil(procEnd)
      pr.lastLine = ps.cur.line
      if ps.isWord("finprocedure") or ps.isWord("finfonction"):
        ps.advance()
        ps.endInstr()
      prog.procs.add pr
      ps.fs = mainFs
    elif ps.isWord("finprocedure") or ps.isWord("finfonction"):
      ps.err("« " & ps.cur.text & " » sans procédure ouverte")
    else:
      prog.main.body.add ps.statement()
  prog.main.lastLine = ps.cur.line
  result = prog
