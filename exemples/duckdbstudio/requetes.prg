&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : éditeur SQL (validation pendant la frappe), exécution, résultats,
&& comptage, export, historique.

&&
&& Découpage d'un script en instructions (hors chaînes, identifiants et commentaires)
&&

fonction DECOUPER_SQL(texte)
  && liste de {sql, debut} (debut : position du premier caractère dans le texte, à partir de 1)
  locale l = {}
  locale n = longueur(texte)
  locale i = 1
  locale debut = 1
  locale q = ""          && délimiteur ouvert : ' " ou fin de commentaire
  tantque i <= n
    locale ch = souschaine(texte, i, 1)
    si q = "'" ou q = car(34)
      si ch = q
        q = ""
      finsi
    sinonsi q = "--"
      si ch = car(10)
        q = ""
      finsi
    sinonsi q = "/*"
      si ch = "*" et souschaine(texte, i + 1, 1) = "/"
        q = ""
        i += 1
      finsi
    sinonsi ch = "'" ou ch = car(34)
      q = ch
    sinonsi ch = "-" et souschaine(texte, i + 1, 1) = "-"
      q = "--"
    sinonsi ch = "/" et souschaine(texte, i + 1, 1) = "*"
      q = "/*"
    sinonsi ch = ";"
      AJOUTER_INSTRUCTION(l, texte, debut, i - 1)
      debut = i + 1
    finsi
    i += 1
  fintantque
  AJOUTER_INSTRUCTION(l, texte, debut, n)
retourner l

procedure AJOUTER_INSTRUCTION(l, texte, a, b)
  si b < a
    retourner
  finsi
  locale s = souschaine(texte, a, b - a + 1)
  si SANS_COMMENTAIRES(s) <> ""
    inserer(l, {sql = rogner(s), debut = a + longueur(s) - longueur(rognerg(s))})
  finsi
retourner

fonction SANS_COMMENTAIRES(s)
  && texte sans commentaires -- ni /* */ (pour savoir si une instruction est vide)
  locale r = ""
  pour chaque ligne dans decouper(s, car(10))
    locale p = position("--", ligne)
    si p > 0
      ligne = gauche(ligne, p - 1)
    finsi
    r = r + ligne + " "
  suivant
  tantque position("/*", r) > 0 et position("*/", r) > position("/*", r)
    r = gauche(r, position("/*", r) - 1) + souschaine(r, position("*/", r) + 2)
  fintantque
retourner rogner(r)

fonction PREMIER_MOT(s)
  locale t = minuscule(SANS_COMMENTAIRES(s))
  locale m = ""
  pour i = 1 a longueur(t)
    locale ch = souschaine(t, i, 1)
    si contient("abcdefghijklmnopqrstuvwxyz_", ch)
      m = m + ch
    sinonsi m <> ""
      sortir
    sinonsi ch = "("
      retourner "select"
    finsi
  suivant
retourner m

fonction EST_REQUETE(s)
  && instruction qui renvoie des lignes et peut être encadrée par SELECT * FROM (…)
retourner contient({"select", "with", "from", "values", "table", "pivot", "unpivot"}, PREMIER_MOT(s))

fonction RENVOIE_LIGNES(s)
retourner EST_REQUETE(s) ou contient({"show", "describe", "summarize", "explain", "pragma", "call"}, PREMIER_MOT(s))

&&
&& Exécution
&&

procedure EXECUTER_SQL
  locale sel = ed:selection()
  locale texte = sisinon(sel <> nul et rogner(sel) <> "", sel, ed:texte())
  EXECUTER_TEXTE(texte)
retourner

procedure EXECUTER_TEXTE(texte)
  locale l = DECOUPER_SQL(texte)
  si #l = 0
    STATUT("Rien à exécuter.")
    retourner
  finsi
  locale t0 = systeme.horloge()
  locale nok = 0
  pour i = 1 a #l
    locale r = EXECUTER_UNE(l[i].sql, i = #l)
    si r
      nok += 1
    sinon
      sortir
    finsi
  suivant
  ENREGISTRER_PROJET()
  si nok = #l
    STATUT(nok + " instruction(s) exécutée(s) en " + arrondi((systeme.horloge() - t0) * 1000) + " ms")
  finsi
  && une instruction de définition (CREATE, DROP, ATTACH…) change le catalogue
  pour chaque x dans l
    si contient({"create", "drop", "alter", "attach", "detach", "copy", "insert", "import"}, PREMIER_MOT(x.sql))
      RAFRAICHIR_CATALOGUES()
      sortir
    finsi
  suivant
retourner

fonction EXECUTER_UNE(s, afficher)
  && exécute une instruction ; affiche son résultat si afficher ; vrai si réussie
  locale t0 = systeme.horloge()
  locale limite = sisinon(reglages.limite = nul, 1000, reglages.limite)
  essayer
    si EST_REQUETE(s)
      locale colonnes = requete("DESCRIBE " + s)
      locale lignes = requete("SELECT " + PROJECTION(colonnes) + " FROM (" + s + ") AS _r LIMIT " + (limite + 1))
      locale duree = systeme.horloge() - t0
      HISTORISER(s, duree, #lignes, vrai, "")
      JOURNAL(sisinon(#lignes > limite, limite + "+", chaine(#lignes)) + " ligne(s) en " + arrondi(duree * 1000, 1) + " ms : " + RESUME(s))
      si afficher
        AFFICHER_RESULTAT(s, colonnes, lignes, duree, limite)
      finsi
    sinon
      locale lignes = requete(s)
      locale duree = systeme.horloge() - t0
      HISTORISER(s, duree, #lignes, vrai, "")
      JOURNAL("OK en " + arrondi(duree * 1000, 1) + " ms : " + RESUME(s))
      si afficher et RENVOIE_LIGNES(s) et #lignes > 0
        AFFICHER_RESULTAT(s, nul, lignes, duree, limite)
      sinonsi afficher
        lblres.libelle = "OK : " + RESUME(s) + " (" + arrondi(duree * 1000, 1) + " ms)"
      finsi
    finsi
  capturer e
    HISTORISER(s, systeme.horloge() - t0, 0, faux, e)
    ERREUR(e + car(10) + "    dans : " + RESUME(s))
    SIGNALER_ERREUR(s, e)
    retourner faux
  finessayer
retourner vrai

fonction EST_COMPOSE(type_)
  && listes, tableaux, structures, dictionnaires, unions : lus en texte
  locale t = majuscule(type_)
retourner finitpar(t, "]") ou commencepar(t, "STRUCT") ou commencepar(t, "MAP") ou commencepar(t, "UNION")

fonction PROJECTION(colonnes)
  locale compose = faux
  pour chaque c dans colonnes
    si EST_COMPOSE(c.column_type)
      compose = vrai
    finsi
  suivant
  si non compose
    retourner "*"
  finsi
  locale l = {}
  pour chaque c dans colonnes
    si EST_COMPOSE(c.column_type)
      inserer(l, IDENT(c.column_name) + "::VARCHAR AS " + IDENT(c.column_name))
    sinon
      inserer(l, IDENT(c.column_name))
    finsi
  suivant
retourner joindre(l, ", ")

fonction RESUME(s)
  locale t = rogner(SANS_COMMENTAIRES(s))
  si t = ""
    t = rogner(s)
  finsi
  t = remplacertexte(t, car(10), " ")
  tantque contient(t, "  ")
    t = remplacertexte(t, "  ", " ")
  fintantque
retourner gauche(t, 110)

procedure AFFICHER_RESULTAT(s, colonnes, lignes, duree, limite)
  globale grilleres, dernierresultat
  si grilleres <> nul
    grilleres:detruire()
  finsi
  grilleres = zoneres:ajouter(ui.grille())
  grilleres.ancrage = "centre"
  && colonnes : DESCRIBE (ordre et types), sinon les clefs des lignes
  locale noms = {}
  locale types = {}
  si colonnes <> nul
    pour chaque c dans colonnes
      inserer(noms, c.column_name)
      inserer(types, c.column_type)
    suivant
  sinon
    pour chaque r dans lignes
      pour chaque k, v dans r
        si non contient(noms, k)
          inserer(noms, k)
          inserer(types, "")
        finsi
      suivant
    suivant
  finsi
  pour i = 1 a #noms
    locale num = contient({"INTEGER", "BIGINT", "SMALLINT", "TINYINT", "HUGEINT", "DOUBLE", "FLOAT", "REAL", "UBIGINT", "UINTEGER"}, ;
                          majuscule(types[i])) ou commencepar(majuscule(types[i]), "DECIMAL")
    grilleres:ajoutercolonne{nom = "c" + i, titre = noms[i] + sisinon(types[i] = "", "", "  " + minuscule(types[i])), ;
                             genre = sisinon(num, "nombre", "texte"), largeur = 150}
  suivant
  locale n = min(#lignes, limite)
  pour j = 1 a n
    locale r = lignes[j]
    locale cel = {}
    pour i = 1 a #noms
      locale v = r[majuscule(noms[i])]
      inserer(cel, sisinon(v = nul, "∅", v))
    suivant
    grilleres:ajouterligne(cel)
  suivant
  dernierresultat = {sql = s, colonnes = noms, nombre = #lignes}
  lblres.libelle = sisinon(#lignes > limite, "Plus de " + limite + " lignes (affichage limité)", #lignes + " ligne(s)") + ;
                   " · " + #noms + " colonne(s) · " + arrondi(duree * 1000, 1) + " ms"
  bas.valeur = 1
retourner

procedure COMPTER_RESULTAT(ev)
  si dernierresultat = nul ou non EST_REQUETE(dernierresultat.sql)
    STATUT("Exécutez d'abord une requête SELECT.")
    retourner
  finsi
  locale t0 = systeme.horloge()
  essayer
    locale n = valeursql("SELECT count(*) FROM (" + dernierresultat.sql + ") AS _r")
    lblres.libelle = n + " ligne(s) au total (comptées en " + arrondi((systeme.horloge() - t0) * 1000, 1) + " ms)"
  capturer e
    ERREUR(e)
  finessayer
retourner

procedure EXPORTER_RESULTAT(ev)
  si dernierresultat = nul
    STATUT("Exécutez d'abord une requête.")
    retourner
  finsi
  locale p = ui.enregistrerfichier{nom = "resultat.parquet", filtre = "Parquet|*.parquet|CSV|*.csv|JSON|*.json"}
  si p = nul
    retourner
  finsi
  locale ext = minuscule(fichier.extension(p))
  locale fmt = sisinon(ext = ".csv", "csv, HEADER", sisinon(ext = ".json", "json", "parquet"))
  locale src = sisinon(EST_REQUETE(dernierresultat.sql), dernierresultat.sql, "SELECT 1")
  essayer
    locale t0 = systeme.horloge()
    requete("COPY (" + src + ") TO " + LITTERAL(p) + " (FORMAT " + fmt + ")")
    JOURNAL("Export : " + p + " (" + arrondi((systeme.horloge() - t0) * 1000) + " ms)")
    STATUT("Exporté : " + p)
  capturer e
    ERREUR(e)
  finessayer
retourner

procedure RAFRAICHIR_CATALOGUES
  pour chaque c dans projet.connexions
    si attachees[minuscule(ALIAS(c))] = vrai
      essayer
        INTROSPECTER(c)
      capturer e
      finessayer
    finsi
  suivant
  REMPLIR_EXPLORATEUR()
  NOMS_COMPLETION()
retourner

&&
&& Validation syntaxique pendant la frappe (analyseur de DuckDB : json_serialize_sql)
&&

procedure SQL_MODIFIE(ev)
  globale analyse
  si ed:langage() <> "sql"
    retourner
  finsi
  locale texte = ed:texte()
  locale empreinte = hachage(texte)
  si empreinte == analyse
    retourner
  finsi
  analyse = empreinte
  ed:diagnostics(DIAGNOSTICS_SQL(texte))
retourner

fonction LIGNE_COLONNE(texte, pos)
  && position (1 = premier caractère) -> {ligne, colonne}
  locale avant = gauche(texte, pos - 1)
  locale lignes = decouper(avant, car(10))
retourner {ligne = #lignes, colonne = longueur(lignes[#lignes]) + 1}

fonction DIAGNOSTICS_SQL(texte)
  locale d = {}
  pour chaque ins dans DECOUPER_SQL(texte)
    si EST_REQUETE(ins.sql)
      essayer
        locale j = dejson(valeursql("SELECT json_serialize_sql(?)", ins.sql))
        si j.error = vrai
          locale p = valeur(sisinon(j.position = nul, "0", j.position))
          locale lc = LIGNE_COLONNE(texte, ins.debut + p)
          inserer(d, {ligne = lc.ligne, colonne = lc.colonne, longueur = 3, genre = "erreur", ;
                      message = remplacertexte(j.error_message, car(10), " ")})
        finsi
      capturer e
      finessayer
    finsi
  suivant
retourner d

procedure SIGNALER_ERREUR(s, e)
  && erreur d'exécution : soulignée au début de l'instruction dans l'éditeur
  locale texte = ed:texte()
  locale p = position(s, texte)
  si p > 0
    locale lc = LIGNE_COLONNE(texte, p)
    ed:diagnostics({{ligne = lc.ligne, colonne = lc.colonne, longueur = longueur(PREMIER_MOT(s)), genre = "erreur", ;
                     message = remplacertexte(e, car(10), " ")}})
  finsi
retourner

procedure SQL_SIGNAL(ev)
  && signaux de l'éditeur : Ctrl+R (cmd:run), Ctrl+S (cmd:save)
  si ev.texte = "cmd:run"
    EXECUTER_SQL()
  sinonsi ev.texte = "cmd:save"
    ENREGISTRER_SCRIPT()
  finsi
retourner
