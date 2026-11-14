# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet wdreka : solveur de contraintes CP-SAT (langage NCP)
#
# Le système de résolution de wdreka (cpsat/ : solveur CDCL avec génération
# paresseuse de clauses, langage de modélisation NCP, contraintes globales
# cumulative, disjunctive, reservoir, windows, alldifferent, table, circuit…),
# en Nim pur, rendu disponible aux programmes Lexis+ : un programme écrit son
# modèle en NCP (texte), le résout, puis lit les valeurs de la solution.
#
#   m = wdreka.modele([[
#     var x[3] : 0..9;
#     constraint alldifferent(x);
#     constraint x[0] + x[1] == x[2];
#     solve maximize x[2];
#   ]])
#   r = m:resoudre({delai = 10})
#   ? r.statut, r.objectif, m:valeur("x")      && optimal 9 {…}
#
# La compilation et la recherche libèrent l'interpréteur : les fenêtres restent
# réactives, une minuterie peut afficher m:progression() et un bouton appeler
# m:arreter() (la meilleure solution trouvée est gardée).

import std/[times, strutils, atomics]
import ../lexis/api
import cpsat/[lang, solver]

type
  WModel = ref object of LUser
    c: Compiler
    source: string
    running: Atomic[bool]
    stop: Atomic[bool]
    solutions: Atomic[int]
    objective: Atomic[int]
    hasObjective: Atomic[bool]
    t0: float
    last: float                      # durée de la dernière résolution
    status: string

  SolveCtx = object
    L: Interp
    m: WModel
    onSol: Value                     # procédure Lexis appelée à chaque solution

var ctx {.threadvar.}: ptr SolveCtx  # la résolution tourne sur le fil appelant

proc progressCb(s: Solver): bool {.nimcall, gcsafe.} =
  {.cast(gcsafe).}:
    if ctx == nil: return true
    let m = ctx.m
    result = not m.stop.load(moRelaxed) and not ctx.L.stopRequested

proc solutionCb(c: Compiler, index: int, objective: int, hasObjective: bool) {.nimcall, gcsafe.} =
  {.cast(gcsafe).}:
    if ctx == nil: return
    let m = ctx.m
    m.solutions.store(index)
    m.objective.store(objective)
    m.hasObjective.store(hasObjective)
    if ctx.onSol.kind != vkNil:
      let L = ctx.L
      let info = newLTable()
      info.set("solution", intV(index))
      if hasObjective: info.set("objectif", intV(objective))
      info.set("duree", numV(epochTime() - m.t0))
      var keep = true
      L.enter()
      try:
        let r = L.call(ctx.onSol, @[tableV(info)])
        if r.len > 0 and r[0].kind == vkBool and not r[0].b: keep = false
      finally:
        L.leave()
      if not keep: m.stop.store(true)

proc cleanError(msg: string): string =
  ## « line N: … » -> « ligne N : … »
  let n = errorLine(msg)
  if n > 0:
    let i = msg.find(':')
    result = "ligne " & $n & " : " & msg[i + 1 .. ^1].strip
  else: result = msg.strip

proc compileSrc(L: Interp, src: string): Compiler =
  var err = ""
  L.blocking:
    try:
      {.cast(gcsafe).}: result = compileModel(src)
    except CatchableError as e:
      err = e.msg
  if err.len > 0: rtError("wdreka : " & cleanError(err))

proc toLexis(t: SolTree): Value =
  case t.kind
  of skInt: intV(t.i)
  of skBool: boolV(t.b)
  of skList:
    let r = newLTable(t.items.len)
    for i, x in t.items: r.rawSet(i + 1, toLexis(x))
    tableV(r)

proc checkModel(L: Interp, a: seq[Value], fname: string): WModel =
  checkUser[WModel](L, a, 1, fname, "modèle wdreka")

proc statsTable(m: WModel): LTable =
  let s = m.c.s
  result = newLTable()
  result.set("booleens", intV(s.numVars))
  result.set("entiers", intV(s.numIntVars))
  result.set("clauses", intV(s.numClauses))
  result.set("propagateurs", intV(s.numProps))
  result.set("apprises", intV(s.numLearnts))
  result.set("conflits", intV(s.conflicts))
  result.set("decisions", intV(s.decisions))
  result.set("propagations", intV(s.propagations))
  result.set("redemarrages", intV(s.restarts))

proc solveModel(L: Interp, m: WModel, o: LTable): Value =
  if m.running.load: rtError("wdreka : résolution déjà en cours pour ce modèle")
  let delai = if o != nil: o.optField("delai", 0.0) else: 0.0
  let maxSol = if o != nil: o.optField("solutions", 0) else: 0
  let onSol = if o != nil: o.field("solution") else: nilV()
  m.stop.store(false)
  m.solutions.store(0)
  m.hasObjective.store(false)
  m.running.store(true)
  m.t0 = epochTime()
  var c = SolveCtx(L: L, m: m, onSol: onSol)
  var summary: RunSummary
  var err = ""
  m.c.s.progress = progressCb
  L.blocking:
    ctx = addr c
    try:
      {.cast(gcsafe).}:
        summary = m.c.runInteractive(solutionCb, timeout = delai, maxSolutions = maxSol)
    except CatchableError as e:
      err = e.msg
    finally:
      ctx = nil
  m.running.store(false)
  m.last = epochTime() - m.t0
  if err.len > 0: rtError("wdreka : " & cleanError(err))
  let stopped = m.stop.load or L.stopRequested
  let n = summary.solutions
  m.status =
    if n > 0 and summary.complete and summary.kind in ["minimize", "maximize"]: "optimal"
    elif n > 0 and summary.complete and summary.kind == "all": "toutes"
    elif n > 0: "solution"
    elif summary.complete: "infaisable"
    elif stopped: "arrete"
    else: "temps"
  let r = newLTable()
  r.set("statut", strV(m.status))
  r.set("solutions", intV(n))
  r.set("complet", boolV(summary.complete))
  r.set("genre", strV(case summary.kind
                         of "minimize": "minimiser"
                         of "maximize": "maximiser"
                         of "all": "toutes"
                         else: "satisfaire"))
  if n > 0 and summary.kind in ["minimize", "maximize"]:
    r.set("objectif", intV(summary.lastObjective))
  r.set("duree", numV(m.last))
  r.set("statistiques", tableV(statsTable(m)))
  tableV(r)

proc openWdreka(L: Interp): Value =
  let im = newLib()
  im.fn "resoudre", proc (L: Interp, a: seq[Value]): seq[Value] =
    let m = L.checkModel(a, "resoudre")
    let o = if arg(a, 2).kind == vkTable: a[1].t else: nil
    @[L.solveModel(m, o)]
  im.fn "valeur", proc (L: Interp, a: seq[Value]): seq[Value] =
    let m = L.checkModel(a, "valeur")
    let name = L.checkStr(a, 2, "valeur")
    if m.solutions.load == 0: return @[nilV()]
    var found = false
    let t = m.c.solutionTree(name, found)
    if not found: rtError("wdreka : valeur : nom inconnu « " & name & " »")
    @[toLexis(t)]
  im.fn "vrais", proc (L: Interp, a: seq[Value]): seq[Value] =
    let m = L.checkModel(a, "vrais")
    let name = L.checkStr(a, 2, "vrais")
    let r = newLTable()
    if m.solutions.load == 0: return @[tableV(r)]
    if not m.c.hasName(name): rtError("wdreka : vrais : nom inconnu « " & name & " »")
    let dims = m.c.arrayDims(name)
    var k = 1
    for flat in m.c.trueIndices(name):
      if dims.len <= 1:
        r.rawSet(k, intV(flat))
      else:
        # coordonnées (base 0) dans le tableau à plusieurs dimensions
        let co = newLTable(dims.len)
        var rest = flat
        var coords = newSeq[int](dims.len)
        for d in countdown(dims.len - 1, 0):
          coords[d] = rest mod dims[d]
          rest = rest div dims[d]
        for d, x in coords: co.rawSet(d + 1, intV(x))
        r.rawSet(k, tableV(co))
      inc k
    @[tableV(r)]
  im.fn "contient", proc (L: Interp, a: seq[Value]): seq[Value] =
    let m = L.checkModel(a, "contient")
    @[boolV(m.c.hasName(L.checkStr(a, 2, "contient")))]
  im.fn "noms", proc (L: Interp, a: seq[Value]): seq[Value] =
    let m = L.checkModel(a, "noms")
    @[toV(m.c.topLevelNames())]
  im.fn "objectif", proc (L: Interp, a: seq[Value]): seq[Value] =
    let m = L.checkModel(a, "objectif")
    if m.solutions.load == 0 or not m.c.isOptimizing: return @[nilV()]
    @[intV(m.c.currentObjective())]
  im.fn "bornes", proc (L: Interp, a: seq[Value]): seq[Value] =
    let m = L.checkModel(a, "bornes")
    let (lo, hi) = m.c.objectiveBounds()
    @[intV(lo), intV(hi)]
  im.fn "statistiques", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[tableV(statsTable(L.checkModel(a, "statistiques")))]
  im.fn "progression", proc (L: Interp, a: seq[Value]): seq[Value] =
    let m = L.checkModel(a, "progression")
    let r = newLTable()
    let running = m.running.load
    r.set("encours", boolV(running))
    r.set("solutions", intV(m.solutions.load))
    if m.hasObjective.load: r.set("objectif", intV(m.objective.load))
    r.set("duree", numV(if running: epochTime() - m.t0 else: m.last))
    r.set("conflits", intV(m.c.s.conflicts))
    r.set("decisions", intV(m.c.s.decisions))
    if not running and m.status.len > 0: r.set("statut", strV(m.status))
    @[tableV(r)]
  im.fn "arreter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let m = L.checkModel(a, "arreter")
    m.stop.store(true)
    @[boolV(m.running.load)]
  im.fn "texte", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(L.checkModel(a, "texte").source)]
  discard L.userMeta("wdreka", im)

  let m = newLib()
  m.fn "modele", proc (L: Interp, a: seq[Value]): seq[Value] =
    let src = L.checkStr(a, 1, "modele")
    let c = L.compileSrc(src)
    let w = WModel(c: c, source: src)
    @[L.wrap(w, "wdreka", im)]
  m.fn "resoudre", proc (L: Interp, a: seq[Value]): seq[Value] =
    let src = L.checkStr(a, 1, "resoudre")
    let o = if arg(a, 2).kind == vkTable: a[1].t else: nil
    let w = WModel(c: L.compileSrc(src), source: src)
    let r = L.solveModel(w, o)
    r.t.set("modele", L.wrap(w, "wdreka", im))
    @[r]
  m.fn "verifier", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## nul si le modèle se compile, sinon {ligne, message}
    let src = L.checkStr(a, 1, "verifier")
    var err = ""
    L.blocking:
      try:
        {.cast(gcsafe).}: discard compileModel(src)
      except CatchableError as e:
        err = e.msg
    if err.len == 0: return @[nilV()]
    let r = newLTable()
    r.set("ligne", intV(errorLine(err)))
    r.set("message", strV(cleanError(err)))
    @[tableV(r)]
  tableV(m)

registerPackage PackageDef(name: "wdreka", open: openWdreka,
  description: "Solveur de contraintes CP-SAT de wdreka (langage NCP), en Nim pur",
  docs: docs("wdreka", [
    "wdreka.modele(texte)", "Compile un modèle NCP (var, let, const, constraint, forall, solve satisfy | minimize | maximize | all ; contraintes alldifferent, cumulative, disjunctive, reservoir, windows, table, circuit, count, sum, min, max…). Erreur « wdreka : ligne N : … » si le texte est incorrect.",
    "wdreka.resoudre(texte, [options])", "Compile et résout en une fois ; le résultat a en plus le champ modele.",
    "wdreka.verifier(texte)", "nul si le modèle se compile, sinon {ligne, message}.",
    "m:resoudre([{delai=0, solutions=0, solution=@proc}])", "Résout : délai en secondes (0 : sans limite), nombre maximal de solutions (solve all), procédure appelée à chaque solution ou amélioration avec {solution, objectif, duree} (renvoyer faux arrête). Renvoie {statut, solutions, complet, genre, objectif, duree, statistiques} ; statut : optimal, solution, toutes, infaisable, temps, arrete.",
    "m:valeur(nom)", "Valeur d'un nom du modèle dans la dernière solution : entier, booléen, ou liste (tableaux, imbriqués s'ils ont plusieurs dimensions) ; nul sans solution.",
    "m:vrais(nom)", "Indices (base 0) des éléments vrais d'un tableau booléen ; pour un tableau à plusieurs dimensions, leurs coordonnées {i, j, …}.",
    "m:contient(nom)", "Vrai si le modèle définit ce nom.",
    "m:noms()", "Noms qui dépendent des variables de décision.",
    "m:objectif()", "Objectif de la dernière solution (nul sans objectif).",
    "m:bornes()", "Bornes connues de l'objectif (deux valeurs).",
    "m:progression()", "Pendant ou après la résolution (depuis un autre gestionnaire, par exemple une minuterie) : {encours, solutions, objectif, duree, conflits, decisions, statut}.",
    "m:arreter()", "Arrête la résolution en cours ; la meilleure solution trouvée est gardée.",
    "m:statistiques()", "Taille et effort : {booleens, entiers, clauses, propagateurs, apprises, conflits, decisions, propagations, redemarrages}.",
    "m:texte()", "Texte NCP du modèle."]))
