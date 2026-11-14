&& Paquet wdreka : modèle NCP, résolution, valeurs, tableaux booléens, erreurs, rappels
procedure TEST
  locale m = wdreka.modele([[
    var x : 0..10;
    var y : 0..10;
    constraint x + 2 * y <= 14;
    constraint 3 * x - y >= 0;
    solve maximize 3 * x + 4 * y;
  ]])
  locale r = m:resoudre({delai = 10})
  ? "optimum :", r.statut, r.objectif, m:valeur("x"), m:valeur("y"), m:objectif(), r.complet
  ? "noms :", m:contient("x"), m:contient("z")
  && affectation : 3 tâches sur 3 machines, coûts
  locale a = wdreka.resoudre([[
    const COUT = [4, 2, 8, 4, 3, 7, 3, 1, 6];
    var z[3, 3] : bool;
    forall i in 0..2 { constraint sum([ite(z[i, j], 1, 0) | j in 0..2]) == 1; }
    forall j in 0..2 { constraint sum([ite(z[i, j], 1, 0) | i in 0..2]) == 1; }
    solve minimize sum([ite(z[i, j], COUT[i * 3 + j], 0) | i in 0..2, j in 0..2]);
  ]], {delai = 10})
  ? "affectation :", a.statut, a.objectif
  pour chaque c dans a.modele:vrais("z")
    ? "  vrai :", c[1], c[2]
  suivant
  && toutes les solutions
  globale NB_SOLUTIONS
  NB_SOLUTIONS = 0
  locale t = wdreka.resoudre([[
    var a : 1..3;
    var b : 1..3;
    constraint a < b;
    solve all;
  ]], {solution = @COMPTER})
  ? "toutes :", t.statut, t.solutions, NB_SOLUTIONS
  ? "infaisable :", wdreka.resoudre("var q : 0..3; constraint q > 5; solve satisfy;").statut
  locale e = wdreka.verifier("var q : 0..3;" + car(10) + "constraint q >> 2;")
  ? "erreur :", e <> nul, e.ligne
  ? "correct :", wdreka.verifier("var q : 0..3; solve satisfy;") = nul
retourner

procedure COMPTER(s)
  globale NB_SOLUTIONS
  NB_SOLUTIONS = NB_SOLUTIONS + 1
retourner
