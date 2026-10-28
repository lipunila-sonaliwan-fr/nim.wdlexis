&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : tableau de bord BI (lot 3).
&&
&& Chaque élément du tableau de bord (projet.bi) repose sur une requête :
&&   {titre, genre, sql, dimension, mesures, agregat, limite}
&& genre : colonnes, lignes, aires, secteurs, mosaique, indicateur, tableau.
&& La requête affichée regroupe la requête source par la dimension et agrège les
&& mesures (une série par mesure) : SELECT dim, sum(m1), sum(m2) FROM (sql) GROUP BY 1.
&& « Depuis le résultat » crée un élément à partir de la dernière requête exécutée.

fonction GENRES_BI()
retourner {"colonnes", "lignes", "aires", "secteurs", "mosaique", "indicateur", "tableau"}

fonction AGREGATS_BI()
retourner {"somme", "moyenne", "nombre", "minimum", "maximum", "distincts", "aucun"}

fonction FONCTION_AGREGAT(a, m)
  faire cas
  cas a = "moyenne"
    retourner "avg(" + m + ")"
  cas a = "nombre"
    retourner "count(" + m + ")"
  cas a = "minimum"
    retourner "min(" + m + ")"
  cas a = "maximum"
    retourner "max(" + m + ")"
  cas a = "distincts"
    retourner "count(DISTINCT " + m + ")"
  cas a = "aucun"
    retourner m
  fincas
retourner "sum(" + m + ")"

procedure CONSTRUIRE_BI(page)
  globale bi
  bi = {sel = 0, cadres = {}, colonnes = {}}
  locale sp = page:ajouter(ui.separateur{vertical = vrai, position = 0.30})
  sp.ancrage = "centre"
  locale g = sp:ajouter(ui.colonne())
  locale r1 = g:ajouter(ui.rangee())
  OUTIL(r1, "Depuis le résultat", @BI_DEPUIS_RESULTAT, "Nouvel élément sur la dernière requête exécutée")
  OUTIL(r1, "+", @BI_NOUVEAU, "Nouvel élément vide")
  OUTIL(r1, "✕", @BI_SUPPRIMER, "Supprime l'élément sélectionné")
  OUTIL(r1, "↻", @BI_ACTUALISER, "Relance toutes les requêtes du tableau de bord")
  bi.liste = g:ajouter(ui.liste())
  bi.liste.hauteurfixe = 130
  bi.liste.surselection = @BI_CHOIX
  locale f = g:ajouter(ui.cadre("Élément", "grille"))
  f:ajouter(ui.etiquette("Titre"))
  bi.titre = f:ajouter(ui.saisie(""))
  f:ajouter(ui.etiquette("Genre"))
  bi.genre = f:ajouter(ui.combo(GENRES_BI()))
  f:ajouter(ui.etiquette("Dimension"))
  bi.dimension = f:ajouter(ui.saisie{indication = "colonne ou expression"})
  f:ajouter(ui.etiquette("Mesures"))
  bi.mesures = f:ajouter(ui.saisie{indication = "m1, m2"})
  f:ajouter(ui.etiquette("Agrégat"))
  bi.agregat = f:ajouter(ui.combo(AGREGATS_BI()))
  f:ajouter(ui.etiquette("Limite"))
  bi.limite = f:ajouter(ui.saisie("12"))
  g:ajouter(ui.etiquette("Requête source"))
  bi.sql = g:ajouter(ui.saisie{multiligne = vrai})
  bi.sql.poids = 1
  bi.info = g:ajouter(ui.etiquette(""))
  locale r2 = g:ajouter(ui.rangee())
  OUTIL(r2, "Colonnes", @BI_COLONNES, "Colonnes de la requête source")
  OUTIL(r2, "Appliquer", @BI_APPLIQUER, "Enregistre l'élément et l'affiche")
  OUTIL(r2, "▲", @BI_MONTER, "Avance l'élément dans le tableau de bord")
  bi.zone = sp:ajouter(ui.panneau{disposition = "grille", colonnes = 2, defilement = "automatique"})
retourner

procedure BI_CHARGER
  BI_LISTE()
  BI_ACTUALISER(nul)
retourner

procedure BI_LISTE
  bi.liste:vider()
  pour chaque w dans projet.bi
    bi.liste:ajouter(w.titre + "  [" + w.genre + "]")
  suivant
  si bi.sel >= 1 et bi.sel <= #projet.bi
    bi.liste:selectionner(bi.sel)
  finsi
retourner

procedure BI_CHOIX(ev)
  locale i = bi.liste:selection()
  si i < 1 ou i > #projet.bi
    retourner
  finsi
  bi.sel = i
  locale w = projet.bi[i]
  bi.titre.valeur = w.titre
  bi.genre:selectionner(max(1, POSITION_LISTE(GENRES_BI(), w.genre)))
  bi.dimension.valeur = sisinon(w.dimension = nul, "", w.dimension)
  bi.mesures.valeur = sisinon(w.mesures = nul, "", w.mesures)
  bi.agregat:selectionner(max(1, POSITION_LISTE(AGREGATS_BI(), w.agregat)))
  bi.limite.valeur = chaine(sisinon(w.limite = nul, 12, w.limite))
  bi.sql.valeur = w.sql
  bi.info.libelle = ""
retourner

fonction POSITION_LISTE(l, v)
  pour i = 1 a #l
    si l[i] = v
      retourner i
    finsi
  suivant
retourner 0

fonction EST_NUMERIQUE(t)
  locale m = majuscule(t)
retourner contient(m, "INT") ou contient(m, "DECIMAL") ou contient(m, "DOUBLE") ou contient(m, "FLOAT") ou ;
          contient(m, "REAL") ou contient(m, "NUMERIC") ou m = "HUGEINT"

procedure BI_DEPUIS_RESULTAT(ev)
  si dernierresultat = nul
    STATUT("Exécutez d'abord une requête : son résultat servira de source.")
    retourner
  finsi
  locale s = rogner(dernierresultat.sql)
  si finitpar(s, ";")
    s = gauche(s, longueur(s) - 1)
  finsi
  locale dim = ""
  locale mes = ""
  essayer
    pour chaque c dans requete("DESCRIBE " + s)
      si EST_NUMERIQUE(c.column_type)
        si mes = ""
          mes = IDENT(c.column_name)
        finsi
      sinonsi dim = ""
        dim = IDENT(c.column_name)
      finsi
    suivant
  capturer e
    ERREUR("BI : " + e)
    retourner
  finessayer
  locale w = {titre = "Élément " + (#projet.bi + 1), genre = sisinon(dim = "", "indicateur", "colonnes"), sql = s, ;
              dimension = dim, mesures = sisinon(mes = "", "*", mes), agregat = sisinon(mes = "", "nombre", "somme"), limite = 12}
  inserer(projet.bi, w)
  bi.sel = #projet.bi
  BI_LISTE()
  BI_CHOIX(nul)
  ENREGISTRER_PROJET()
  BI_ACTUALISER(nul)
  vues.valeur = INDEX_VUE("BI")
retourner

procedure BI_NOUVEAU(ev)
  inserer(projet.bi, {titre = "Élément " + (#projet.bi + 1), genre = "colonnes", sql = "SELECT 'a' AS d, 1 AS v", ;
                      dimension = "d", mesures = "v", agregat = "somme", limite = 12})
  bi.sel = #projet.bi
  BI_LISTE()
  BI_CHOIX(nul)
  ENREGISTRER_PROJET()
  BI_ACTUALISER(nul)
retourner

procedure BI_SUPPRIMER(ev)
  si bi.sel < 1 ou bi.sel > #projet.bi
    retourner
  finsi
  retirer(projet.bi, bi.sel)
  bi.sel = 0
  BI_LISTE()
  ENREGISTRER_PROJET()
  BI_ACTUALISER(nul)
retourner

procedure BI_MONTER(ev)
  si bi.sel < 2 ou bi.sel > #projet.bi
    retourner
  finsi
  locale w = projet.bi[bi.sel]
  projet.bi[bi.sel] = projet.bi[bi.sel - 1]
  projet.bi[bi.sel - 1] = w
  bi.sel -= 1
  BI_LISTE()
  ENREGISTRER_PROJET()
  BI_ACTUALISER(nul)
retourner

procedure BI_COLONNES(ev)
  essayer
    locale l = {}
    pour chaque c dans requete("DESCRIBE " + rogner(bi.sql.valeur))
      inserer(l, c.column_name + sisinon(EST_NUMERIQUE(c.column_type), " #", ""))
    suivant
    bi.info.libelle = gauche(joindre(l, ", "), 200)
    bi.info.infobulle = "# : colonne numérique (mesure possible)"
  capturer e
    bi.info.libelle = "Erreur : " + gauche(e, 160)
  finessayer
retourner

procedure BI_APPLIQUER(ev)
  si bi.sel < 1 ou bi.sel > #projet.bi
    BI_NOUVEAU(nul)
  finsi
  locale w = projet.bi[bi.sel]
  w.titre = rogner(bi.titre.valeur)
  w.genre = GENRES_BI()[max(1, bi.genre:selection())]
  w.dimension = rogner(bi.dimension.valeur)
  w.mesures = rogner(bi.mesures.valeur)
  w.agregat = AGREGATS_BI()[max(1, bi.agregat:selection())]
  w.limite = max(1, valeur(sisinon(bi.limite.valeur = "", "12", bi.limite.valeur)))
  locale s = rogner(bi.sql.valeur)
  si finitpar(s, ";")
    s = gauche(s, longueur(s) - 1)
  finsi
  w.sql = s
  BI_LISTE()
  ENREGISTRER_PROJET()
  BI_ACTUALISER(nul)
retourner

fonction SQL_ELEMENT(w)
  locale mes = {}
  pour chaque m dans decouper(sisinon(w.mesures = nul, "", w.mesures), ",")
    si rogner(m) <> ""
      inserer(mes, rogner(m))
    finsi
  suivant
  si #mes = 0
    inserer(mes, "*")
    w.agregat = "nombre"
  finsi
  locale src = "(" + car(10) + w.sql + car(10) + ") AS _source"
  locale lim = sisinon(w.limite = nul, 12, w.limite)
  si w.genre = "tableau"
    retourner "SELECT * FROM " + src + " LIMIT " + lim
  finsi
  locale sel = {}
  pour i = 1 a #mes
    inserer(sel, FONCTION_AGREGAT(w.agregat, mes[i]) + " AS m" + i)
  suivant
  si w.genre = "indicateur" ou w.dimension = nul ou w.dimension = ""
    retourner "SELECT " + joindre(sel, ", ") + " FROM " + src
  finsi
  si w.agregat = "aucun"
    retourner "SELECT " + w.dimension + " AS d, " + joindre(sel, ", ") + " FROM " + src + " LIMIT " + lim
  finsi
  locale ordre = sisinon(w.genre = "lignes" ou w.genre = "aires", "1", "2 DESC")
retourner "SELECT " + w.dimension + " AS d, " + joindre(sel, ", ") + " FROM " + src + " GROUP BY 1 ORDER BY " + ordre + " LIMIT " + lim

fonction FORMAT_NOMBRE(v)
  si v = nul
    retourner "∅"
  finsi
  si type(v) <> "nombre"
    retourner chaine(v)
  finsi
  locale neg = v < 0
  locale a = abs(v)
  locale ent = entier(a)
  locale dec = a - ent
  locale s = chaine(ent)
  locale r = ""
  tantque longueur(s) > 3
    r = " " + droite(s, 3) + r
    s = gauche(s, longueur(s) - 3)
  fintantque
  r = s + r
  si dec > 0.005 et ent < 1000000
    r = r + "," + droite("0" + chaine(arrondi(dec * 100)), 2)
  finsi
retourner sisinon(neg, "-", "") + r

procedure BI_ACTUALISER(ev)
  pour chaque c dans bi.cadres
    c:detruire()
  suivant
  bi.cadres = {}
  pour chaque w dans projet.bi
    locale cadre = bi.zone:ajouter(ui.cadre(w.titre, "bordure"))
    cadre.hauteurfixe = 280
    inserer(bi.cadres, cadre)
    essayer
      locale lignes = requete(SQL_ELEMENT(w))
      BI_DESSINER(cadre, w, lignes)
    capturer e
      locale m = cadre:ajouter(ui.markdown("**Erreur** : " + e))
      m.ancrage = "centre"
    finessayer
  suivant
  si #projet.bi = 0
    locale cadre = bi.zone:ajouter(ui.cadre("Tableau de bord vide", "bordure"))
    cadre.hauteurfixe = 200
    inserer(bi.cadres, cadre)
    locale m = cadre:ajouter(ui.markdown("Exécutez une requête, puis **Depuis le résultat** : un graphique est créé " + ;
                                         "(dimension = première colonne texte, mesure = première colonne numérique). " + ;
                                         "Réglez ensuite le genre, l'agrégat et la limite, puis **Appliquer**."))
    m.ancrage = "centre"
  finsi
retourner

fonction LIBELLE_COURT(v)
  && dates : AAAA-MM (ou AAAA-MM-JJ si le jour compte) ; textes : 14 caractères
  si v = nul
    retourner "∅"
  finsi
  locale s = chaine(v)
  si longueur(s) >= 10 et souschaine(s, 5, 1) = "-" et souschaine(s, 8, 1) = "-"
    retourner sisinon(souschaine(s, 9, 2) = "01", gauche(s, 7), gauche(s, 10))
  finsi
retourner gauche(s, 14)

procedure BI_DESSINER(cadre, w, lignes)
  locale mes = {}
  pour chaque m dans decouper(sisinon(w.mesures = nul, "*", w.mesures), ",")
    si rogner(m) <> ""
      inserer(mes, rogner(m))
    finsi
  suivant
  faire cas
  cas w.genre = "indicateur"
    locale v = sisinon(#lignes > 0, lignes[1].m1, nul)
    locale l = cadre:ajouter(ui.markdown("# " + FORMAT_NOMBRE(v) + car(10) + car(10) + w.agregat + " de " + joindre(mes, ", ")))
    l.ancrage = "centre"
  cas w.genre = "tableau"
    locale t = cadre:ajouter(ui.tableau())
    t.ancrage = "centre"
    si #lignes > 0
      locale cols = {}
      pour chaque r dans requete("DESCRIBE " + w.sql)
        inserer(cols, r.column_name)
        t:ajoutercolonne(r.column_name, 110)
      suivant
      pour chaque r dans lignes
        locale cel = {}
        pour chaque c dans cols
          inserer(cel, FORMAT_NOMBRE(r[majuscule(c)]))
        suivant
        t:ajouterligne(cel)
      suivant
    finsi
  cas w.genre = "mosaique"
    locale m = cadre:ajouter(ui.mosaique())
    m.ancrage = "centre"
    pour chaque r dans lignes
      si r.m1 <> nul et r.m1 > 0
        m:ajouter(chaine(sisinon(r.d = nul, "∅", r.d)), r.m1)
      finsi
    suivant
  autrement
    locale g = cadre:ajouter(ui.graphe(w.genre, ""))
    g.ancrage = "centre"
    pour i = 1 a #lignes
      locale r = lignes[i]
      pour k = 1 a #mes
        locale v = r["M" + k]
        g:ajouterdonnee(k, i, sisinon(v = nul, 0, v))
      suivant
      g:libellecategorie(i, LIBELLE_COURT(r.d))
    suivant
    pour k = 1 a #mes
      g:libelleserie(k, w.agregat + " " + mes[k])
    suivant
  fincas
retourner
