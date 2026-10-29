&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : moteur d'expertise. Des règles examinent le dernier plan profilé, le
&& catalogue des connexions et l'historique des exécutions ; chacune produit des
&& recommandations classées :
&&   Critique     impact majeur
&&   Important    gain significatif
&&   Opportunité  optimisation facultative
&& Chaque recommandation : problème, justification, gain estimé, correction proposée
&& (SQL généré quand c'est possible), coût actuel / après et retour sur investissement
&& pour la mutualisation.

procedure CONSTRUIRE_RECOS(page)
  globale rec
  rec = {}
  locale haut = page:ajouter(ui.rangee())
  haut.ancrage = "haut"
  rec.resume = haut:ajouter(ui.etiquette("Analyser : plan profilé, catalogue et historique."))
  rec.resume.poids = 1
  locale b1 = haut:ajouter(ui.bouton("Analyser"))
  b1.surclic = @ANALYSER_TOUT
  locale b2 = haut:ajouter(ui.bouton("Générer la correction"))
  b2.surclic = @RECO_CORRECTION
  locale b3 = haut:ajouter(ui.bouton("Ignorer"))
  b3.surclic = @RECO_IGNORER
  locale sp = page:ajouter(ui.separateur{vertical = vrai, position = 0.58})
  sp.ancrage = "centre"
  rec.zone = sp:ajouter(ui.panneau{disposition = "bordure", defilement = "masque"})
  rec.fiche = sp:ajouter(ui.markdown("Sélectionnez une recommandation."))
  rec.table = nul
  NOUVELLE_TABLE_RECOS()
retourner

procedure NOUVELLE_TABLE_RECOS
  si rec.table <> nul
    rec.table:detruire()
  finsi
  rec.table = rec.zone:ajouter(ui.tableau())
  rec.table.ancrage = "centre"
  rec.table:ajoutercolonne("Niveau", 100)
  rec.table:ajoutercolonne("Domaine", 100)
  rec.table:ajoutercolonne("Problème", 330)
  rec.table:ajoutercolonne("Gain estimé", 170)
  rec.table.surselection = @RECO_CHOIX
retourner

fonction RECO(niveau, domaine, probleme, justification, gain, correction, sql)
retourner {niveau = niveau, domaine = domaine, probleme = probleme, justification = justification, ;
           gain = gain, correction = correction, sql = sql, actuel = nul, apres = nul}

fonction RANG_NIVEAU(n)
retourner sisinon(n = "Critique", 1, sisinon(n = "Important", 2, 3))

fonction ORDRE_RECOS(a, b)
  si RANG_NIVEAU(a.niveau) <> RANG_NIVEAU(b.niveau)
    retourner RANG_NIVEAU(a.niveau) < RANG_NIVEAU(b.niveau)
  finsi
retourner a.probleme < b.probleme

fonction MS(s)
  && secondes -> texte
  si s >= 1
    retourner arrondi(s, 2) + " s"
  finsi
retourner arrondi(s * 1000, 1) + " ms"

&&
&& Règles sur le plan d'exécution
&&

fonction REGLES_PLAN(p)
  locale l = {}
  si p = nul
    retourner l
  finsi
  locale tot = max(p.total, 0.000001)
  locale tris = 0
  pour chaque o dans p.ops
    locale t = majuscule(o.type)
    locale part = o.temps / tot
    && scan complet d'une grosse table sans filtre
    si contient(t, "SCAN") et o.lues >= 1000000 et INFO(o, "Filters") = nul
      locale niv = sisinon(o.lues >= 10000000, "Critique", "Important")
      locale tb = sisinon(INFO(o, "Table") = nul, o.nom, INFO(o, "Table"))
      inserer(l, RECO(niv, "Requête", "Scan complet de " + tb + " (" + LIGNES_TEXTE(o.lues) + " lignes)", ;
        "L'opérateur " + o.nom + " lit toute la table sans filtre poussé jusqu'au stockage (" + arrondi(part * 100) + ;
        " % du temps). Les zone maps de DuckDB ne peuvent pas sauter de groupes de lignes.", ;
        "jusqu'à " + arrondi(part * 90) + " % du temps de la requête", ;
        "Filtrer au plus tôt (WHERE sur une colonne triée ou partitionnée), ne projeter que les colonnes utiles, " + ;
        "ou interroger un agrégat précalculé.", nul))
    finsi
    && jointures coûteuses
    si contient(t, "NESTED_LOOP") ou contient(t, "CROSS_PRODUCT") ou contient(t, "BLOCKWISE_NL")
      inserer(l, RECO("Critique", "Requête", "Jointure " + o.nom + " (produit cartésien ou boucles imbriquées)", ;
        "La condition de jointure n'est pas une égalité exploitable par une jointure par hachage ; le coût croît " + ;
        "comme le produit des deux tailles. Conditions : " + sisinon(INFO(o, "Conditions") = nul, "aucune", INFO(o, "Conditions")), ;
        "souvent plus de 90 % de la requête", ;
        "Exprimer la jointure par une égalité (ON a.cle = b.cle), ou ASOF JOIN pour les jointures temporelles.", nul))
    finsi
    si contient(t, "HASH_JOIN") et #o.enfants = 2
      locale g = OP_PAR_ID(p, o.enfants[1])
      locale d = OP_PAR_ID(p, o.enfants[2])
      si g <> nul et d <> nul
        si o.lignes > 10 * max(g.lignes, d.lignes) et o.lignes > 100000
          inserer(l, RECO("Important", "Requête", "Jointure qui démultiplie les lignes (" + LIGNES_TEXTE(o.lignes) + ")", ;
            "La jointure produit " + LIGNES_TEXTE(o.lignes) + " lignes à partir de " + LIGNES_TEXTE(g.lignes) + " et " + ;
            LIGNES_TEXTE(d.lignes) + " : la clé n'est probablement pas unique d'un côté.", ;
            "élimination d'un volume intermédiaire inutile", ;
            "Vérifier la clé de jointure ; agréger le côté « plusieurs » avant de joindre.", nul))
        finsi
        si d.lignes > 5 * g.lignes et d.lignes > 1000000
          inserer(l, RECO("Opportunité", "Requête", "Table de construction volumineuse dans " + o.nom, ;
            "La table de hachage est construite sur le côté droit (" + LIGNES_TEXTE(d.lignes) + " lignes) alors que " + ;
            "le côté gauche est plus petit (" + LIGNES_TEXTE(g.lignes) + "). Les statistiques sont peut-être faussées " + ;
            "par un filtre ou une sous-requête.", "mémoire et temps de construction", ;
            "Filtrer le grand côté avant la jointure, ou matérialiser le petit côté dans une table.", nul))
        finsi
      finsi
    finsi
    si contient(t, "ORDER") ou contient(t, "SORT")
      tris += 1
      si o.lignes > 1000000
        inserer(l, RECO("Opportunité", "Requête", "Tri complet de " + LIGNES_TEXTE(o.lignes) + " lignes", ;
          "Un tri sans LIMIT range toutes les lignes ; il coûte " + arrondi(part * 100) + " % de la requête.", ;
          "jusqu'à " + arrondi(part * 100) + " % du temps", ;
          "Ajouter LIMIT (DuckDB passe alors en TOP_N) ou trier une seule fois en amont (table triée).", nul))
      finsi
    finsi
    si part >= 0.6 et tot >= 0.05
      inserer(l, RECO("Opportunité", "Requête", o.nom + " concentre " + arrondi(part * 100) + " % du temps", ;
        "Sur " + MS(tot) + " de calcul, " + MS(o.temps) + " sont passés dans " + o.nom + ". C'est là qu'il faut agir.", ;
        MS(o.temps) + " au plus", "Voir le profil : informations de l'opérateur (table, filtres, conditions).", nul))
    finsi
  suivant
  si tris >= 2
    inserer(l, RECO("Important", "Requête", "Tris répétés (" + tris + " tris dans le plan)", ;
      "Plusieurs opérateurs trient les mêmes données (fenêtres, ORDER BY imbriqués, DISTINCT ON…).", ;
      "un tri au lieu de " + tris, "Regrouper les fenêtres sur la même partition et le même ordre ; retirer les ORDER BY des sous-requêtes.", nul))
  finsi
  si p.temporaire <> nul et p.temporaire > 0
    inserer(l, RECO("Important", "Mémoire", "Débordement sur disque (" + OCTETS(p.temporaire) + ")", ;
      "La requête a dépassé la mémoire allouée et a écrit des fichiers temporaires.", "suppression des écritures disque", ;
      "Augmenter la mémoire allouée, ou réduire le volume intermédiaire (filtres, colonnes).", ;
      "SET memory_limit = '8GB';"))
  finsi
retourner l

fonction OP_PAR_ID(p, id)
  pour chaque o dans p.ops
    si o.id = id
      retourner o
    finsi
  suivant
retourner nul

&&
&& Règles sur le catalogue (volumétrie, stockage, structures)
&&

fonction REGLES_CATALOGUE()
  locale l = {}
  locale signatures = {}
  locale textes = TEXTES_HISTORIQUE()
  pour chaque o dans TOUS_LES_OBJETS()
    si o.genre = "table"
      locale t = o.objet
      locale n = sisinon(t.lignes = nul, 0, t.lignes)
      locale qn = QUALIFIE(o)
      si n >= 10000000
        inserer(l, RECO("Important", "Volumétrie", "Table très volumineuse : " + o.nom + " (" + LIGNES_TEXTE(n) + " lignes)", ;
          "Au-delà de dix millions de lignes, chaque requête non filtrée lit l'ensemble de la table.", ;
          "lecture limitée aux partitions utiles", ;
          "Partitionner l'historique en Parquet (PARTITION_BY) ou trier la table sur la colonne de filtre principale " + ;
          "pour que les zone maps éliminent des groupes de lignes.", ;
          "COPY " + qn + " TO 'partitions/" + o.nom + "' (FORMAT parquet, PARTITION_BY (annee));"))
      finsi
      si n >= 100000 et (t.pk = nul ou #t.pk = 0) et non o.fichiers
        inserer(l, RECO("Opportunité", "Structure", "Table sans clé primaire : " + o.nom, ;
          "Sans clé, les doublons ne sont pas détectés et les mises à jour par clé (INSERT OR REPLACE) sont impossibles.", ;
          "intégrité, MERGE possible", "Déclarer une clé primaire si une colonne identifie les lignes.", nul))
      finsi
      && signature (colonnes et types) pour détecter les structures redondantes
      locale sig = ""
      pour chaque c dans t.colonnes
        sig = sig + c.nom + ":" + c.type + ";"
      suivant
      si sig <> "" et #t.colonnes >= 3
        si signatures[sig] <> nul
          inserer(l, RECO("Opportunité", "Stockage", "Structures redondantes : " + signatures[sig] + " et " + o.nom, ;
            "Ces deux tables ont exactement les mêmes colonnes et les mêmes types.", "stockage et maintenance", ;
            "Fusionner (UNION ALL BY NAME) dans une table avec une colonne de distinction, ou remplacer l'une par une vue.", nul))
        sinon
          signatures[sig] = o.nom
        finsi
      finsi
      && colonnes inutilisées (si la table apparaît dans l'historique sans SELECT *)
      locale usages = 0
      locale etoile = faux
      pour chaque q dans textes
        si contient(q, minuscule(o.nom))
          usages += 1
          si contient(q, "select *") ou contient(q, "summarize")
            etoile = vrai
          finsi
        finsi
      suivant
      si usages >= 3 et non etoile
        locale inutiles = {}
        pour chaque c dans t.colonnes
          locale vue_ = faux
          pour chaque q dans textes
            si contient(q, minuscule(o.nom)) et contient(q, minuscule(c.nom))
              vue_ = vrai
            finsi
          suivant
          si non vue_
            inserer(inutiles, c.nom)
          finsi
        suivant
        si #inutiles > 0
          inserer(l, RECO("Opportunité", "Volumétrie", "Colonnes inutilisées dans " + o.nom + " : " + joindre(inutiles, ", "), ;
            usages + " requêtes de l'historique lisent " + o.nom + " sans jamais citer ces colonnes.", ;
            "stockage et lecture", "Les retirer des tables dérivées, ou les déplacer dans une table annexe.", nul))
        finsi
      finsi
      && stockage : compression et fragmentation (bases DuckDB sur disque)
      si n >= 500000 et CONNECTEUR(o.cnx.type) <> nul et CONNECTEUR(o.cnx.type).type = "duckdb"
        essayer
          locale st = requete("SELECT count(DISTINCT row_group_id) AS groupes, count(*) AS segments, " + ;
                              "sum(CASE WHEN compression = 'Uncompressed' THEN 1 ELSE 0 END) AS bruts " + ;
                              "FROM pragma_storage_info(" + LITTERAL(o.alias + "." + o.schema + "." + o.nom) + ")")[1]
          locale attendus = plafond(n / 122880)
          si st.groupes > 2 * attendus
            inserer(l, RECO("Important", "Stockage", "Fragmentation de " + o.nom + " (" + st.groupes + " groupes au lieu de " + attendus + ")", ;
              "Des insertions par petits lots ont créé des groupes de lignes partiellement remplis.", ;
              "lectures et compression meilleures", "Réécrire la table d'un bloc (CREATE OR REPLACE TABLE … AS SELECT …).", ;
              "CREATE OR REPLACE TABLE " + qn + " AS SELECT * FROM " + qn + ";"))
          finsi
          si st.segments > 0 et st.bruts / st.segments > 0.5
            inserer(l, RECO("Opportunité", "Stockage", "Mauvaise compression de " + o.nom, ;
              arrondi(st.bruts * 100 / st.segments) + " % des segments ne sont pas compressés (base pas encore contrôlée " + ;
              "par CHECKPOINT, ou données peu répétitives).", "place disque et lectures", "Forcer un point de contrôle.", ;
              "CHECKPOINT " + IDENT(o.alias) + ";"))
          finsi
        capturer e
        finessayer
      finsi
    finsi
  suivant
retourner l

fonction TEXTES_HISTORIQUE()
  locale l = {}
  pour chaque h dans projet.historique
    si h.ok
      inserer(l, minuscule(h.sql))
    finsi
  suivant
  && le texte des vues compte aussi comme usage
  pour chaque k, cat dans catalogue
    pour chaque s dans cat.schemas
      pour chaque v dans s.vues
        si v.sql <> nul
          inserer(l, minuscule(v.sql))
        finsi
      suivant
    suivant
  suivant
retourner l

&&
&& Mutualisation et précalcul (historique)
&&

fonction NORMALISER(s)
  && texte « en forme » d'une requête : minuscules, littéraux remplacés par ?, espaces réduits
  locale t = minuscule(SANS_COMMENTAIRES(s))
  locale r = ""
  locale i = 1
  locale n = longueur(t)
  tantque i <= n
    locale ch = souschaine(t, i, 1)
    si ch = "'"
      locale j = i + 1
      tantque j <= n et souschaine(t, j, 1) <> "'"
        j += 1
      fintantque
      r = r + "?"
      i = j + 1
    sinonsi contient("0123456789", ch) et (i = 1 ou non contient("abcdefghijklmnopqrstuvwxyz_", souschaine(t, i - 1, 1)))
      tantque i <= n et contient("0123456789.", souschaine(t, i, 1))
        i += 1
      fintantque
      r = r + "?"
    sinonsi ch = " " ou ch = car(9) ou ch = car(10) ou ch = car(13)
      si droite(r, 1) <> " "
        r = r + " "
      finsi
      i += 1
    sinon
      r = r + ch
      i += 1
    finsi
  fintantque
retourner rogner(r)

fonction REGLES_HISTORIQUE()
  locale l = {}
  locale groupes = {}
  locale ordre = {}
  pour chaque h dans projet.historique
    si h.ok et EST_REQUETE(h.sql)
      locale f = NORMALISER(h.sql)
      si groupes[f] = nul
        groupes[f] = {forme = f, n = 0, duree = 0, exemple = h.sql}
        inserer(ordre, f)
      finsi
      groupes[f].n += 1
      groupes[f].duree += h.duree / 1000
    finsi
  suivant
  && requêtes similaires répétées
  locale k = 0
  pour chaque f dans ordre
    locale g = groupes[f]
    si g.n >= 3
      k += 1
      locale moy = g.duree / g.n
      locale apres = moy + g.n * 0.001
      locale r = RECO(sisinon(g.duree >= 5, "Important", "Opportunité"), "Mutualisation", ;
        "Requête répétée " + g.n + " fois : " + gauche(RESUME(g.exemple), 60), ;
        "La même requête (aux valeurs près) a été exécutée " + g.n + " fois, pour " + MS(g.duree) + " au total. " + ;
        sisinon(contient(f, "?"), "Ses valeurs changent : une macro paramétrée la factorise ; ", "") + ;
        "si ses données changent peu, une table précalculée évite de la recalculer.", ;
        "≈ " + arrondi(max(0, g.duree - apres) * 100 / max(g.duree, 0.000001)) + " % (" + MS(g.duree) + " → " + MS(apres) + ")", ;
        "Créer une vue (lisibilité), une macro (paramètres) ou une table précalculée (performance).", ;
        "CREATE OR REPLACE TABLE pre_" + k + " AS" + car(10) + rogner(g.exemple) + ";" + car(10) + ;
        "-- puis : SELECT * FROM pre_" + k + ";  (à rafraîchir quand les sources changent)")
      r.actuel = g.duree
      r.apres = apres
      inserer(l, r)
    finsi
  suivant
  && agrégations répétées sur les mêmes tables
  locale aggs = {}
  locale aordre = {}
  pour chaque h dans projet.historique
    locale t = minuscule(h.sql)
    si h.ok et contient(t, "group by")
      locale p = position(" from ", t)
      si p > 0
        locale src = decouper(rogner(souschaine(t, p + 6)), " ")[1]
        si aggs[src] = nul
          aggs[src] = {n = 0, duree = 0}
          inserer(aordre, src)
        finsi
        aggs[src].n += 1
        aggs[src].duree += h.duree / 1000
      finsi
    finsi
  suivant
  pour chaque src dans aordre
    si aggs[src].n >= 3
      locale r = RECO("Opportunité", "Mutualisation", "Agrégations répétées sur " + src + " (" + aggs[src].n + " requêtes)", ;
        "Plusieurs requêtes regroupent les lignes de " + src + ". Un cube précalculé au grain le plus fin utilisé " + ;
        "(par exemple jour × client) les sert toutes.", ;
        MS(aggs[src].duree) + " → quelques ms par requête", ;
        "Créer une table d'agrégats (vue matérialisée) rafraîchie après chaque chargement.", ;
        "CREATE OR REPLACE TABLE agg_" + ALIAS({nom = src}) + " AS" + car(10) + ;
        "SELECT /* colonnes de regroupement */ count(*) AS nb /* , sum(...) */" + car(10) + ;
        "FROM " + src + car(10) + "GROUP BY ALL;")
      r.actuel = aggs[src].duree
      r.apres = aggs[src].n * 0.002
      inserer(l, r)
    finsi
  suivant
  && sous-requêtes répétées dans des requêtes différentes
  locale sous = {}
  locale sordre = {}
  pour chaque h dans projet.historique
    locale t = NORMALISER(h.sql)
    locale p = position("(select ", t)
    tantque p > 0
      locale prof_ = 0
      locale j = p
      tantque j <= longueur(t)
        locale ch = souschaine(t, j, 1)
        si ch = "("
          prof_ += 1
        sinonsi ch = ")"
          prof_ -= 1
          si prof_ = 0
            sortir
          finsi
        finsi
        j += 1
      fintantque
      locale sq = souschaine(t, p, j - p + 1)
      si longueur(sq) > 30
        si sous[sq] = nul
          sous[sq] = {n = 0, requetes = {}}
          inserer(sordre, sq)
        finsi
        sous[sq].n += 1
      finsi
      locale reste = souschaine(t, j + 1)
      locale q = position("(select ", reste)
      p = sisinon(q > 0, j + q, 0)
    fintantque
  suivant
  pour chaque sq dans sordre
    si sous[sq].n >= 2
      inserer(l, RECO("Opportunité", "Mutualisation", "Sous-requête répétée " + sous[sq].n + " fois", ;
        "La sous-requête " + gauche(sq, 90) + " revient dans plusieurs requêtes.", "calcul partagé, code plus lisible", ;
        "En faire une vue (ou une CTE commune).", "CREATE OR REPLACE VIEW v_commune AS " + souschaine(sq, 2, longueur(sq) - 2) + ";"))
    finsi
  suivant
retourner l

&&
&& Affichage et actions
&&

procedure ANALYSER_PLAN(p)
  globale recos
  locale l = REGLES_PLAN(p)
  && garde les recommandations non liées au plan
  pour chaque r dans recos
    si r.domaine <> "Requête" et r.domaine <> "Mémoire"
      inserer(l, r)
    finsi
  suivant
  AFFICHER_RECOS(l)
retourner

procedure ANALYSER_TOUT
  && une seule analyse à la fois (l'interface reste disponible pendant les requêtes)
  si OPERATION_EN_COURS("analyse du projet")
    STATUT("L'analyse du projet est déjà en cours.")
    retourner
  finsi
  locale tache = OPERATION_DEBUT("analyse du projet", nul)
  essayer
    ANALYSER_TOUT_SUITE()
  capturer e
    ERREUR("Analyse : " + sisinon(tache.arret, "interrompue par l'utilisateur", e))
  finessayer
  OPERATION_FIN(tache)
retourner

procedure ANALYSER_TOUT_SUITE
  locale l = REGLES_PLAN(dernierplan)
  pour chaque r dans REGLES_CATALOGUE()
    inserer(l, r)
  suivant
  pour chaque r dans REGLES_HISTORIQUE()
    inserer(l, r)
  suivant
  pour chaque r dans REGLES_EMPREINTES()
    inserer(l, r)
  suivant
  pour chaque r dans REGLES_EXTENSIONS()
    inserer(l, r)
  suivant
  AFFICHER_RECOS(l)
  vues.valeur = 4
  REMPLIR_TABLEAU()
retourner

fonction SCORE_GLOBAL(l)
  locale s = 100
  pour chaque r dans l
    s -= sisinon(r.niveau = "Critique", 15, sisinon(r.niveau = "Important", 7, 2))
  suivant
retourner max(0, s)

procedure AFFICHER_RECOS(l)
  globale recos
  && sans les recommandations ignorées
  locale garde = {}
  pour chaque r dans l
    si non contient(projet.ignorees, r.probleme)
      inserer(garde, r)
    finsi
  suivant
  trier(garde, @ORDRE_RECOS)
  recos = garde
  NOUVELLE_TABLE_RECOS()
  locale n = {CRITIQUE = 0, IMPORTANT = 0, OPPORTUNITE = 0}
  pour chaque r dans recos
    rec.table:ajouterligne(sisinon(r.niveau = "Critique", "● Critique", sisinon(r.niveau = "Important", "● Important", "○ Opportunité")), ;
                           r.domaine, r.probleme, r.gain)
    si r.niveau = "Critique"
      n.critique += 1
    sinonsi r.niveau = "Important"
      n.important += 1
    sinon
      n.opportunite += 1
    finsi
  suivant
  rec.resume.libelle = "Score " + SCORE_GLOBAL(recos) + " / 100 · " + n.critique + " critique(s), " + ;
                       n.important + " importante(s), " + n.opportunite + " opportunité(s)"
  rec.fiche.valeur = sisinon(#recos = 0, "Aucune recommandation : rien de critique dans ce qui a été analysé.", ;
                             "Sélectionnez une recommandation.")
retourner

procedure RECO_CHOIX(ev)
  globale recocourante
  locale i = rec.table:selection()
  si i = nul ou i < 1 ou i > #recos
    retourner
  finsi
  locale r = recos[i]
  recocourante = r
  locale nl = car(10)
  locale md = "## " + r.niveau + " · " + r.domaine + nl + nl + "**" + r.probleme + "**" + nl + nl + ;
              "**Justification.** " + r.justification + nl + nl + "**Gain estimé.** " + r.gain + nl + nl + ;
              "**Proposition.** " + r.correction + nl
  si r.actuel <> nul
    md = md + nl + "| Coût actuel | Coût après | ROI estimé |" + nl + "| --- | --- | --- |" + nl + ;
         "| " + MS(r.actuel) + " | " + MS(r.apres) + " | × " + arrondi(r.actuel / max(r.apres, 0.000001), 1) + " |" + nl
  finsi
  si r.sql <> nul
    md = md + nl + "**Correction générée** (bouton « Générer la correction ») :" + nl + nl + "```" + nl + r.sql + nl + "```" + nl
  finsi
  rec.fiche.valeur = md
retourner

procedure RECO_CORRECTION(ev)
  si recocourante = nul ou recocourante.sql = nul
    STATUT("Cette recommandation n'a pas de correction générée.")
    retourner
  finsi
  NOUVELLE_REQUETE()
  ed:inserer("-- " + recocourante.niveau + " : " + recocourante.probleme + car(10) + ;
             "-- relisez puis exécutez (F5)" + car(10) + recocourante.sql + car(10))
retourner

procedure RECO_IGNORER(ev)
  si recocourante = nul
    retourner
  finsi
  inserer(projet.ignorees, recocourante.probleme)
  ENREGISTRER_PROJET()
  AFFICHER_RECOS(recos)
retourner
