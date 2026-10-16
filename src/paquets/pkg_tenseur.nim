# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet tenseur : calcul de gradients (différentiation automatique)
#   et optimiseurs, pour apprendre les bases de l'apprentissage automatique.
#
#   x = tenseur.depuis({1, -2, 3}, {3}, vrai)
#   f = tenseur.somme(x * x)
#   f:retropropager()
#   ? f:valeur(), joindre(x:gradient(), " ")       && 14  2 -4 6
#
# Les opérateurs + - * s'appliquent aux tenseurs (et * à un nombre).

import std/[strutils, random, math]
import ../lexis/api
import llm_objets

proc forme(t: Tensor): string = "{" & t.shape.join(", ") & "}"

proc tenseurArg(L: Interp, a: seq[Value], i: int, fname: string): Tensor =
  checkTenseur(L, a, i, fname)

proc optTenseur(L: Interp, a: seq[Value], i: int, fname: string): Tensor =
  if arg(a, i).kind == vkNil: nil else: checkTenseur(L, a, i, fname)

template unaire(m: LTable, nom: string, f: untyped) =
  m.fn nom, proc (L: Interp, a: seq[Value]): seq[Value] =
    @[tenseurV(f(L.tenseurArg(a, 1, nom)))]

proc openTenseur(L: Interp): Value =
  let m = newLib()
  # construction
  m.fn "depuis", proc (L: Interp, a: seq[Value]): seq[Value] =
    let v = L.toFloats(arg(a, 1), "depuis")
    let f = if arg(a, 2).kind == vkNil: @[v.len] else: L.formeDe(arg(a, 2), "depuis")
    if numel(f) != v.len: rtError("depuis : " & $v.len & " valeurs pour une forme de " & $numel(f) & " éléments")
    @[tenseurV(fromSeq(v, f, optBool(a, 3, false), L.optStr(a, 4, "depuis", "")))]
  m.fn "plein", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[tenseurV(full(L.formeDe(arg(a, 1), "plein"), float32(L.optNum(a, 2, "plein", 0.0)),
                    optBool(a, 3, false), L.optStr(a, 4, "plein", "")))]
  m.fn "zeros", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[tenseurV(full(L.formeDe(arg(a, 1), "zeros"), 0'f32, optBool(a, 2, false), L.optStr(a, 3, "zeros", "")))]
  m.fn "scalaire", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[tenseurV(fromSeq(@[float32(L.checkNum(a, 1, "scalaire"))], [1], optBool(a, 2, false)))]
  m.fn "aleatoire", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[tenseurV(randn(L.formeDe(arg(a, 1), "aleatoire"), L.optNum(a, 2, "aleatoire", 1.0), rngDe(L),
                     optBool(a, 3, true), L.optStr(a, 4, "aleatoire", "")))]
  m.fn "parametre", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[tenseurV(param(L.formeDe(arg(a, 1), "parametre"), L.optNum(a, 2, "parametre", 0.1), rngDe(L),
                     L.optStr(a, 3, "parametre", "")))]
  m.fn "graine", proc (L: Interp, a: seq[Value]): seq[Value] =
    rngDe(L) = initRand(L.checkInt(a, 1, "graine"))
    @[]
  m.fn "hasard", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Nombre aléatoire (générateur du paquet, reproductible avec graine) :
    ## hasard() dans [0, 1[, hasard(max), ou hasard("gauss") (loi normale).
    var r = addr rngDe(L)
    if arg(a, 1).kind == vkStr: return @[numV(r[].gauss())]
    @[numV(r[].rand(L.optNum(a, 1, "hasard", 1.0)))]
  # opérations
  m.fn "lineaire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.tenseurArg(a, 1, "lineaire")
    let w = L.tenseurArg(a, 2, "lineaire")
    let b = L.optTenseur(a, 3, "lineaire")
    if w.shape.len != 2 or w.cols != x.cols:
      rtError("lineaire : formes incompatibles " & forme(x) & " · " & forme(w) & "ᵀ (w : {sorties, entrées})")
    if not b.isNil and b.numel != w.shape[0]: rtError("lineaire : biais de " & $w.shape[0] & " valeurs attendu")
    @[tenseurV(linear(x, w, b))]
  m.fn "produit", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.tenseurArg(a, 1, "produit")
    let y = L.tenseurArg(a, 2, "produit")
    if y.rows != x.cols: rtError("produit : formes incompatibles " & forme(x) & " · " & forme(y))
    @[tenseurV(matmul(x, y))]
  m.fn "echelle", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[tenseurV(scale(L.tenseurArg(a, 1, "echelle"), float32(L.checkNum(a, 2, "echelle"))))]
  m.unaire("somme", sum)
  m.unaire("moyenne", mean)
  m.unaire("relu", relu)
  m.unaire("silu", silu)
  m.unaire("sigmoide", sigmoid)
  m.unaire("tanh", tanhT)
  m.unaire("gelu", gelu)
  m.unaire("softmax", softmax)
  m.fn "mse", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.tenseurArg(a, 1, "mse")
    let c = L.tenseurArg(a, 2, "mse")
    if p.numel != c.numel: rtError("mse : formes incompatibles " & forme(p) & " et " & forme(c))
    @[tenseurV(mseLoss(p, c))]
  m.fn "entropiecroisee", proc (L: Interp, a: seq[Value]): seq[Value] =
    let lg = L.tenseurArg(a, 1, "entropiecroisee")
    let c = L.toInts(arg(a, 2), "entropiecroisee")
    if c.len != lg.rows: rtError("entropiecroisee : " & $lg.rows & " classes cibles attendues, " & $c.len & " reçues")
    for x in c:
      if x >= lg.cols: rtError("entropiecroisee : classe " & $x & " hors limites (" & $lg.cols & " classes)")
    @[tenseurV(crossEntropy(lg, c))]
  m.fn "concatener", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.tenseurArg(a, 1, "concatener")
    let y = L.tenseurArg(a, 2, "concatener")
    if x.rows != y.rows: rtError("concatener : même nombre de lignes attendu")
    @[tenseurV(concatCols(x, y))]
  m.fn "decrochage", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[tenseurV(dropout(L.tenseurArg(a, 1, "decrochage"), L.checkNum(a, 2, "decrochage"), rngDe(L)))]
  # graphe
  m.fn "sansgradient", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Appelle proc(...) sans enregistrer de graphe de calcul (inférence).
    let f = L.checkFunc(a, 1, "sansgradient")
    noGrad:
      result = L.call(f, (if a.len > 1: a[1 .. ^1] else: @[]))
  m.fn "verifiergradient", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Compare le gradient calculé à une différence finie ; proc() doit
    ## renvoyer un tenseur scalaire calculé à partir de t.
    let f = L.checkFunc(a, 1, "verifiergradient")
    let t = L.tenseurArg(a, 2, "verifiergradient")
    let calc = proc (): Tensor =
      let r = first(L.call(f, @[]))
      if r.kind != vkUser or not (r.u of LTenseur): rtError("verifiergradient : la procédure doit renvoyer un tenseur")
      LTenseur(r.u).t
    var e: float
    protege "verifiergradient":
      e = gradCheck(calc, t, L.optNum(a, 3, "verifiergradient", 1e-2), int(L.optInt(a, 4, "verifiergradient", 10)))
    @[numV(e)]
  m.fn "operation", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Opération personnalisée : resultat = tenseur.operation(parents, valeurs, forme, @RETRO).
    ## Pendant la rétropropagation, RETRO(resultat, parents) lit resultat:gradient()
    ## et appelle p:ajoutergradient(liste) pour chaque parent.
    let parents = L.tenseurs(arg(a, 1), "operation")
    let v = L.toFloats(arg(a, 2), "operation")
    let f = if arg(a, 3).kind == vkNil: @[v.len] else: L.formeDe(arg(a, 3), "operation")
    if numel(f) != v.len: rtError("operation : " & $v.len & " valeurs pour une forme de " & $numel(f) & " éléments")
    let r = fromSeq(v, f)
    if arg(a, 4).kind != vkNil and needsGrad(parents):
      let retro = L.checkFunc(a, 4, "operation")
      let rv = tenseurV(r)
      var ps: seq[Value]
      for p in parents: ps.add tenseurV(p)
      let pv = listV(ps)
      r.makeNode(parents, proc () =
        discard L.call(retro, @[rv, pv]))
    @[tenseurV(r)]
  m.fn "gradientrequis", proc (L: Interp, a: seq[Value]): seq[Value] =
    var ts: seq[Tensor]
    for i in 1 .. a.len:
      if arg(a, i).kind == vkTable: ts.add L.tenseurs(arg(a, i), "gradientrequis")
      else: ts.add L.tenseurArg(a, i, "gradientrequis")
    @[boolV(needsGrad(ts))]
  # optimiseurs
  m.fn "adamw", proc (L: Interp, a: seq[Value]): seq[Value] =
    let ps = L.tenseurs(arg(a, 1), "adamw")
    let o = optsArg(a, 2)
    @[optimV(newAdamW(ps, lr = o.optField("lr", 3e-4), beta1 = o.optField("beta1", 0.9),
                      beta2 = o.optField("beta2", 0.95), weightDecay = o.optField("decroissance", 0.1)))]
  m.fn "sgd", proc (L: Interp, a: seq[Value]): seq[Value] =
    let ps = L.tenseurs(arg(a, 1), "sgd")
    let o = optsArg(a, 2)
    @[optimV(newSGD(ps, lr = o.optField("lr", 0.01), momentum = o.optField("moment", 0.9),
                    weightDecay = o.optField("decroissance", 0.0)))]
  m.fn "lrcosinus", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[numV(cosineLr(int(L.checkInt(a, 1, "lrcosinus")), int(L.checkInt(a, 2, "lrcosinus")),
                    int(L.checkInt(a, 3, "lrcosinus")), L.checkNum(a, 4, "lrcosinus"),
                    L.optNum(a, 5, "lrcosinus", 0.0)))]
  m.fn "normegradient", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[numV(gradNorm(L.tenseurs(arg(a, 1), "normegradient")))]
  tableV(m)

registerPackage PackageDef(name: "tenseur", open: openTenseur,
  description: "Tenseurs à différentiation automatique et optimiseurs (apprentissage)",
  docs: docs("tenseur", [
    "tenseur.depuis(valeurs[, forme, gradient=faux, nom])", "Tenseur à partir d'une liste ; forme {lignes, colonnes}.",
    "tenseur.plein(forme[, valeur=0, gradient=faux, nom])", "Tenseur rempli d'une valeur.",
    "tenseur.zeros(forme[, gradient=faux, nom])", "Tenseur nul.",
    "tenseur.scalaire(v[, gradient=faux])", "Tenseur d'une seule valeur.",
    "tenseur.aleatoire(forme[, ecart=1, gradient=vrai, nom])", "Valeurs gaussiennes N(0, écart²).",
    "tenseur.parametre(forme[, ecart=0.1, nom])", "Paramètre entraînable initialisé au hasard.",
    "tenseur.graine(n)", "Fixe la graine du générateur aléatoire du paquet.",
    "tenseur.hasard([max | \"gauss\"])", "Nombre aléatoire du générateur du paquet.",
    "tenseur.lineaire(x, w[, b])", "x · wᵀ + b (x : {n, entrées}, w : {sorties, entrées}).",
    "tenseur.produit(a, b)", "Produit matriciel {n, k} · {k, m}.",
    "tenseur.echelle(t, s)", "Multiplie par un nombre (aussi : t * s).",
    "tenseur.somme(t)", "Somme des éléments.",
    "tenseur.moyenne(t)", "Moyenne des éléments.",
    "tenseur.relu(t)", "max(0, x).",
    "tenseur.silu(t)", "x · sigmoïde(x).",
    "tenseur.sigmoide(t)", "1 / (1 + e^-x).",
    "tenseur.tanh(t)", "Tangente hyperbolique.",
    "tenseur.gelu(t)", "GELU.",
    "tenseur.softmax(t)", "Softmax par ligne.",
    "tenseur.mse(prediction, cible)", "Erreur quadratique moyenne.",
    "tenseur.entropiecroisee(logits, classes)", "Entropie croisée (classes : liste d'entiers à partir de 0 ; -1 = ignorée).",
    "tenseur.concatener(a, b)", "Concaténation des colonnes.",
    "tenseur.decrochage(t, p)", "Dropout (entraînement).",
    "tenseur.sansgradient(@proc, ...)", "Appelle proc sans construire de graphe (inférence).",
    "tenseur.verifiergradient(@proc, t[, eps, echantillons])", "Écart relatif entre gradient calculé et différence finie.",
    "tenseur.operation(parents, valeurs, forme, @retro)", "Opération personnalisée ; retro(resultat, parents) appelle p:ajoutergradient().",
    "tenseur.gradientrequis(t, ...)", "Vrai si l'un des tenseurs demande un gradient.",
    "tenseur.adamw(parametres[, {lr=3e-4, beta1=0.9, beta2=0.95, decroissance=0.1}])", "Optimiseur AdamW.",
    "tenseur.sgd(parametres[, {lr=0.01, moment=0.9, decroissance=0}])", "Descente de gradient avec moment.",
    "tenseur.lrcosinus(etape, echauffement, total, lrmax[, lrmin])", "Taux d'apprentissage (échauffement + cosinus).",
    "tenseur.normegradient(parametres)", "Norme globale des gradients.",
    "t:retropropager()", "Calcule les gradients de tout le graphe (t scalaire).",
    "t:valeur([i=1])", "Valeur d'un élément.",
    "t:donnees()", "Liste des valeurs.",
    "t:gradient()", "Liste du gradient (nul s'il n'a pas été calculé).",
    "t:forme()", "Forme (liste des dimensions).",
    "t:taille()", "Nombre d'éléments.",
    "t:zerograd()", "Remet le gradient à zéro.",
    "t:detacher()", "Copie sans gradient.",
    "t:remodeler(forme)", "Même données, autre forme.",
    "t:ajoutergradient(valeurs)", "Ajoute au gradient (opérations personnalisées) ; propriétés : nom, gradientrequis.",
    "o:zerograd()", "Remet à zéro les gradients des paramètres.",
    "o:etape()", "Met à jour les paramètres.",
    "o:ecreter(norme_max)", "Limite la norme des gradients ; renvoie la norme d'origine.",
    "o:enregistrer(chemin)", "Enregistre l'état (moments) de l'optimiseur.",
    "o:charger(chemin)", "Recharge l'état ; propriétés : pas, lr (modifiable), type."]))
