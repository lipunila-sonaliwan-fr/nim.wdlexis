&& Types déclarés (facultatifs), paquet test, paquet profileur, binaire.xxx sans coût caché
&& (ici, « test » désigne la procédure TEST du banc d'essai : le paquet est pris par paquet("test"))
fonction MOYENNE(t : table) : nombre
  locale s : nombre = 0
  pour chaque v dans t
    s += v
  suivant
  retourner s / #t

fonction ETIQUETTE(n : entier, suffixe : chaine?) : chaine
  retourner chaine(n) .. sisinon(suffixe = nul, "", suffixe)

procedure ESSAI(code)
  essayer
    appeler(code)
  capturer e
    ? "erreur :", e
  finessayer

procedure T_PARAM()
  ? MOYENNE("x")

procedure T_RESULTAT()
  locale k : entier = 1
  k = 1.5

procedure T_GLOBALE()
  globale G : table = {}
  G = "texte"

procedure TEST_UN()
  paquet("test").egal(MOYENNE({2, 4}), 3)

procedure TEST_DEUX()
  paquet("test").egal(ETIQUETTE(1, "a"), "1b")

procedure TEST
  ? MOYENNE({1, 2, 3}), ETIQUETTE(7), ETIQUETTE(7, "e")
  ESSAI(@T_PARAM)
  ESSAI(@T_RESULTAT)
  ESSAI(@T_GLOBALE)
  locale r = paquet("test").executer()
  ? r.total, r.reussis, r.echecs, r.resultats[2].message
  profileur.demarrer()
  locale x = 0
  pour i = 1 a 1000
    x = binaire.oux(x, i)
  suivant
  locale p = profileur.arreter()
  ? x, p.duree_ms >= 0, type(p.fonctions), type(p.lignes)
  ? paquet("test").erreur(@MOYENNE, 5)
retourner
