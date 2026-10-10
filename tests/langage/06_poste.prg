&& Particularités du poste de travail (wdlexis+)
procedure TEST
  && boucler, sortir
  locale s = ""
  pour i = 1 a 10
    si mod(i, 2) = 0
      boucler
    finsi
    si i > 7
      sortir
    finsi
    s = s + i
  suivant
  ? "impairs :", s
  && essayer / capturer une erreur d'un paquet et une erreur levée
  essayer
    fichier.lire("/inexistant/x.txt")
  capturer e
    ? "capturé :", e
  finessayer
  essayer
    erreur "aïe"
  capturer e
    ? "capturé :", e
  finessayer
  && itérateur dans pour chaque
  locale n = 0
  pour chaque x dans COMPTEUR(3)
    n += x
  suivant
  ? "itérateur :", n
  && appel avec une table d'options, paramètres, globale
  ? OPTIONS{nom = "Ada", age = 36}
  ? SOMME(1, 2, 3)
  globale g = 5
  g += 1
  ? "globale :", SESSION.G
  && nombres
  ? 10 / 4, 10 / 2, 7 % 3, 2 ^ 10, entier(-3.7), arrondi(2.675, 2), "12,5" * 2
  ? valeur("3,5") + 1, nombre("x"), chaine(42, 5, 0), chaine(3.14159, 8, 2)
  && chaînes et tables
  ? longueur("héllo"), majuscule("été"), position("jour", "Bonjour"), "jour" $ "Bonjour"
  locale t = {3, 1, 2}
  trier(t)
  ? joindre(t, "-"), #t, json(t)
  locale trou = {1, 2, 3}
  trou[2] = nul
  ? #trou
  ? type(paquet("json")), type(@SOMME), type(nul), type(vrai), type("a"), type({})
retourner

fonction COMPTEUR(max)
  locale etat = {n = 0, max = max}
  etat:procedure SUIVANT_C comme "__call"
  fixermetatable(etat, {__call = @SUIVANT_C})
retourner @PROCHAIN_ITER

fonction PROCHAIN_ITER
  globale compteur_n
  si compteur_n = nul
    compteur_n = 0
  finsi
  compteur_n += 1
  si compteur_n > 3
    retourner nul
  finsi
retourner compteur_n

procedure SUIVANT_C(soi)
retourner nul

fonction OPTIONS(o)
retourner o.nom + " a " + o.AGE + " ans"

fonction SOMME
  parametres a, b, c
retourner a + b + c
