&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 15 - Les bases de l'apprentissage : tenseurs, gradients et
&& optimiseur, sur deux petits problèmes (régression linéaire et XOR).
&&
&&   wdlexisrt exemples/llm/15_autograd/principal.prg
&&
&& (aucun modèle de langage nécessaire)
&& Rappel : Lexis+ ne distingue pas les majuscules (x et X sont la même variable).

tenseur.graine(2024)

&& 1. Un gradient calculé à la main.
&& f(x) = somme(x²)  => df/dx = 2x
locale x = tenseur.depuis({1, -2, 3}, {3}, vrai)
locale f = tenseur.somme(x * x)
f:retropropager()
? "f =", f:valeur(), "  df/dx =", joindre(x:gradient(), ", ")          && 2, -4, 6

&& 2. Régression linéaire : retrouver y = 3x + 1
locale xs = {}
locale ys = {}
locale v
pour i = 1 a 64
  v = tenseur.hasard(2) - 1
  inserer v dans xs
  inserer 3 * v + 1 + tenseur.hasard("gauss") * 0.05 dans ys
suivant
locale lx = tenseur.depuis(xs, {64, 1})
locale ly = tenseur.depuis(ys, {64, 1})
locale w = tenseur.parametre({1, 1}, 0.1, "w")                       && poids {sorties, entrées}.
locale b = tenseur.plein({1}, 0, vrai, "b")                          && biais.
locale opt = tenseur.sgd({w, b}, {lr = 0.1, moment = 0.9})
locale perte
pour etape = 1 a 100
  opt:zerograd()
  perte = tenseur.mse(tenseur.lineaire(lx, w, b), ly)
  perte:retropropager()
  opt:etape()
  si etape % 25 = 0
    ? "étape", etape, "perte=" + chaine(perte:valeur(), 0, 5), " w=" + chaine(w:valeur(), 0, 3), ;
      "b=" + chaine(b:valeur(), 0, 3)
  finsi
suivant

&& 3. Réseau de neurones à 2 couches : le XOR.
&& Entrées 2 → 16 neurones cachés (tanh) → 2 classes (entropie croisée).
&& Les paramètres sont globaux : la fonction PREDIRE les utilise.
entrees = tenseur.depuis({0, 0, 0, 1, 1, 0, 1, 1}, {4, 2})
locale cibles = {0, 1, 1, 0}
w1 = tenseur.parametre({16, 2}, 1.0, "w1")
b1 = tenseur.plein({16}, 0, vrai, "b1")
w2 = tenseur.parametre({2, 16}, 0.5, "w2")
b2 = tenseur.plein({2}, 0, vrai, "b2")
locale adam = tenseur.adamw({w1, b1, w2, b2}, {lr = 0.05, decroissance = 0})

pour etape = 1 a 300
  adam:zerograd()
  perte = tenseur.entropiecroisee(PREDIRE(entrees), cibles)
  perte:retropropager()
  adam:etape()
  si etape % 100 = 0
    ? "XOR étape", etape, "perte=" + chaine(perte:valeur(), 0, 4)
  finsi
suivant

tenseur.sansgradient(@AFFICHER_XOR)                 && pas de graphe en inférence.

&& 4. Vérifier une dérivée par différences finies.
tt = tenseur.aleatoire({3, 4}, 1.0)
? "Écart relatif gradient analytique / numérique :", tenseur.verifiergradient(@F_SILU, tt)

&& 5. Opération personnalisée avec sa propre dérivée.
? "Vérification de l'opération personnalisée :", tenseur.verifiergradient(@F_CARRE, tt)

fonction PREDIRE(e)
retourner tenseur.lineaire(tenseur.tanh(tenseur.lineaire(e, w1, b1)), w2, b2)

procedure AFFICHER_XOR
  locale probas = tenseur.softmax(PREDIRE(entrees)):donnees()
  locale e = entrees:donnees()
  locale p1
  pour i = 1 a 4
    p1 = probas[2 * i]
    ? "XOR(" + e[2 * i - 1] + ", " + e[2 * i] + ") =", sisinon(p1 > 0.5, 1, 0), ;
      "  (probabilité de 1 : " + chaine(p1, 0, 3) + ")"
  suivant
retourner

fonction F_SILU()
retourner tenseur.somme(tenseur.silu(tt) * tt)

fonction F_CARRE()
retourner tenseur.somme(CARRE(tt))

&& y = a², dy/da = 2a
fonction CARRE(a)
  locale v = {}
  pour chaque x dans a:donnees()
    inserer x * x dans v
  suivant
retourner tenseur.operation({a}, v, a:forme(), @CARRE_RETRO)

&& Rétropropagation : r:gradient() est dL/dy ; on ajoute dL/da = dL/dy · 2a.
procedure CARRE_RETRO(r, parents)
  locale a = parents[1]
  locale g = r:gradient()
  locale d = a:donnees()
  locale dg = {}
  pour i = 1 a #d
    inserer g[i] * 2 * d[i] dans dg
  suivant
  a:ajoutergradient(dg)
retourner
