&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : explorateur (connexions, catalogues, schémas, tables, vues, vues
&& matérialisées, macros, index, scripts) et palette d'outils.

fonction CLEF_CHEMIN(l)
retourner joindre(l, " » ")

procedure AJOUTER_NOEUD(chemin, info)
  arbre:ajouter(chemin)
  noeudsarbre[CLEF_CHEMIN(chemin)] = info
retourner

fonction LIGNES_TEXTE(n)
  && 1234567 -> « 1,2 M »
  si n = nul
    retourner ""
  finsi
  si n >= 1000000000
    retourner chaine(arrondi(n / 1000000000, 1)) + " G"
  sinonsi n >= 1000000
    retourner chaine(arrondi(n / 1000000, 1)) + " M"
  sinonsi n >= 10000
    retourner chaine(arrondi(n / 1000)) + " k"
  finsi
retourner chaine(n)

procedure REMPLIR_EXPLORATEUR
  globale noeudsarbre
  arbre:vider()
  noeudsarbre = {}
  pour chaque c dans projet.connexions
    locale k = CONNECTEUR(c.type)
    locale etiq = LIBELLE_CNX(c) + "  [" + sisinon(k = nul, "?", k.sigle) + "]" + ;
                  sisinon(attachees[minuscule(ALIAS(c))] = vrai, "", "  (non connectée)")
    locale base = {"Connexions", etiq}
    AJOUTER_NOEUD(base, {genre = "connexion", cnx = c})
    locale cat = catalogue[majuscule(c.nom)]
    si cat <> nul
      pour chaque s dans cat.schemas
        locale ps = {"Connexions", etiq, s.nom}
        AJOUTER_NOEUD(ps, {genre = "schema", cnx = c, schema = s.nom})
        si #s.tables > 0
          AJOUTER_NOEUD({"Connexions", etiq, s.nom, "Tables (" + #s.tables + ")"}, {genre = "groupe"})
          pour chaque t dans s.tables
            locale lt = t.nom + sisinon(t.lignes = nul, "", "   " + LIGNES_TEXTE(t.lignes))
            AJOUTER_NOEUD({"Connexions", etiq, s.nom, "Tables (" + #s.tables + ")", lt}, ;
                          {genre = "table", cnx = c, schema = s.nom, nom = t.nom, objet = t})
          suivant
        finsi
        si #s.vues > 0
          AJOUTER_NOEUD({"Connexions", etiq, s.nom, "Vues (" + #s.vues + ")"}, {genre = "groupe"})
          pour chaque v dans s.vues
            AJOUTER_NOEUD({"Connexions", etiq, s.nom, "Vues (" + #s.vues + ")", v.nom}, ;
                          {genre = "vue", cnx = c, schema = s.nom, nom = v.nom, objet = v})
          suivant
        finsi
        si #s.macros > 0
          AJOUTER_NOEUD({"Connexions", etiq, s.nom, "Macros (" + #s.macros + ")"}, {genre = "groupe"})
          pour chaque m dans s.macros
            AJOUTER_NOEUD({"Connexions", etiq, s.nom, "Macros (" + #s.macros + ")", m.nom + "(" + m.parametres + ")"}, ;
                          {genre = "macro", cnx = c, schema = s.nom, nom = m.nom, objet = m})
          suivant
        finsi
      suivant
    finsi
    arbre:deplier(base)
  suivant
  && scripts du projet
  pour chaque n dans fichier.liste(dossier, faux)
    si minuscule(fichier.extension(n)) = ".sql"
      AJOUTER_NOEUD({"Scripts", n}, {genre = "script", chemin = fichier.joindre(dossier, n)})
    finsi
  suivant
  arbre:deplier({"Connexions"})
  REMPLIR_COMBO_CNX()
  PASTILLES()
retourner

fonction NOEUD_COURANT(ev)
  locale k = nul
  si ev <> nul
    k = sisinon(ev.chemin <> nul, CLEF_CHEMIN(sisinon(ev.chemin = nul, {}, ev.chemin)), ev.texte)
  finsi
  si k = nul ou k = ""
    retourner noeudcourant
  finsi
retourner noeudsarbre[k]

procedure EXPL_CHOIX(ev)
  globale noeudcourant
  locale n = NOEUD_COURANT(ev)
  noeudcourant = n
  si n = nul
    retourner
  finsi
  infoexpl.valeur = FICHE_NOEUD(n)
retourner

fonction FICHE_NOEUD(n)
  locale nl = car(10)
  faire cas
  cas n.genre = "connexion"
    locale k = CONNECTEUR(n.cnx.type)
    locale md = "### " + n.cnx.nom + nl + "**" + sisinon(k = nul, n.cnx.type, k.libelle) + "** · nom SQL `" + ALIAS(n.cnx) + "`" + nl + nl
    si n.cnx.description <> nul et n.cnx.description <> ""
      md = md + n.cnx.description + nl + nl
    finsi
    md = md + sisinon(attachees[minuscule(ALIAS(n.cnx))] = vrai, "Connectée.", "Non connectée : ↻ pour se connecter.") + nl + nl + ;
         "Double-clic : modifier la connexion."
    retourner md
  cas n.genre = "table" ou n.genre = "vue"
    locale o = n.objet
    locale md = "### " + n.nom + nl + sisinon(n.genre = "table", "Table", "Vue") + " · `" + ;
                NOM_QUALIFIE(ALIAS(n.cnx), n.schema, n.nom, CONNECTEUR(n.cnx.type).mode <> "catalogue") + "`" + nl + nl
    si n.genre = "table" et o.lignes <> nul
      md = md + "Lignes (estimation) : **" + LIGNES_TEXTE(o.lignes) + "**" + nl + nl
    finsi
    pour chaque col dans o.colonnes
      locale marque = ""
      si n.genre = "table" et contient(sisinon(o.pk = nul, {}, o.pk), col.nom)
        marque = " **PK**"
      finsi
      md = md + "- `" + col.nom + "` " + col.type + marque + nl
    suivant
    retourner md
  cas n.genre = "macro"
    retourner "### " + n.nom + nl + "Macro (" + n.objet.genre + ")  · paramètres : " + n.objet.parametres
  cas n.genre = "script"
    retourner "### " + fichier.nom(n.chemin) + nl + "Double-clic : ouvrir le script."
  cas n.genre = "schema"
    retourner "### Schéma " + n.schema + nl + "Bouton **Schéma** : concepteur entité-relation de ce schéma."
  fincas
retourner ""

procedure EXPL_DOUBLE(ev)
  locale n = NOEUD_COURANT(ev)
  si n = nul
    retourner
  finsi
  faire cas
  cas n.genre = "connexion"
    CONNEXION_DIALOGUE(n.cnx, n.cnx.type)
  cas n.genre = "table" ou n.genre = "vue"
    EXPL_REQUETE(nul)
  cas n.genre = "script"
    ed:ouvrir(n.chemin)
    vues.valeur = 1
  cas n.genre = "schema"
    EXPL_SCHEMA(nul)
  fincas
retourner

fonction NOM_NOEUD(n)
retourner NOM_QUALIFIE(ALIAS(n.cnx), n.schema, n.nom, CONNECTEUR(n.cnx.type).mode <> "catalogue")

procedure EXPL_REQUETE(ev)
  locale n = noeudcourant
  si n = nul ou (n.genre <> "table" et n.genre <> "vue")
    STATUT("Sélectionnez une table ou une vue dans l'explorateur.")
    retourner
  finsi
  vues.valeur = 1
  locale sql = "SELECT * FROM " + NOM_NOEUD(n) + " LIMIT 100;"
  ed:inserer(car(10) + sql + car(10))
  EXECUTER_TEXTE(sql)
retourner

procedure EXPL_DECRIRE(ev)
  locale n = noeudcourant
  si n = nul ou (n.genre <> "table" et n.genre <> "vue")
    STATUT("Sélectionnez une table ou une vue dans l'explorateur.")
    retourner
  finsi
  EXECUTER_TEXTE("SUMMARIZE " + NOM_NOEUD(n))
retourner

procedure EXPL_SCHEMA(ev)
  locale n = noeudcourant
  si n = nul ou n.cnx = nul
    STATUT("Sélectionnez une connexion ou un schéma.")
    retourner
  finsi
  SCHEMA_DEPUIS_CATALOGUE(n.cnx, sisinon(n.schema = nul, "", n.schema))
  vues.valeur = 2
retourner

&&
&& Palette d'outils
&&

fonction ELEMENTS_PALETTE()
retourner { ;
  {"Sources", {"DuckDB", "Quack", "MSSQL", "ODBC", "PostgreSQL", "MySQL", "SQLite", "CSV", "Parquet", "Excel", "JSON"}}, ;
  {"Modèles", {"Table", "Vue", "Vue matérialisée", "Macro", "Fonction", "Index"}}, ;
  {"Flux", {"Import", "Export", "Jointure", "Filtre", "Agrégation", "Tri", "Union", "Fenêtres analytiques", ;
            "Transformation", "Fusion (MERGE)"}}, ;
  {"Orchestration", {"Pipeline", "Job", "Workflow", "Déclencheur", "Planificateur"}}, ;
  {"Analyse", {"Assistant", "Élément BI", "Extensions"}}, ;
  {"Optimisation", {"Profiling", "Analyse volumétrique", "Analyse mémoire", "Analyse coût", "Recommandations"}}}

procedure CONSTRUIRE_PALETTE
  pour chaque g dans ELEMENTS_PALETTE()
    pour chaque e dans g[2]
      palette:ajouter({g[1], e})
    suivant
    palette:deplier({g[1]})
  suivant
retourner

fonction TYPE_SOURCE(nom)
  locale t = {DUCKDB = "duckdb", QUACK = "quack", MSSQL = "mssql", ODBC = "odbc", POSTGRESQL = "postgres", ;
              MYSQL = "mysql", SQLITE = "sqlite", CSV = "csv", PARQUET = "parquet", EXCEL = "excel", JSON = "json"}
retourner t[majuscule(nom)]

fonction MODELE_SQL(nom)
  locale nl = car(10)
  faire cas
  cas nom = "Table"
    retourner "CREATE TABLE clients (" + nl + "  id INTEGER PRIMARY KEY," + nl + "  nom VARCHAR NOT NULL," + nl + ;
              "  ville VARCHAR" + nl + ");"
  cas nom = "Vue"
    retourner "CREATE OR REPLACE VIEW v_clients_actifs AS" + nl + "SELECT * FROM clients WHERE actif;"
  cas nom = "Vue matérialisée"
    retourner "-- DuckDB n'a pas de vue matérialisée : une table recalculée à la demande" + nl + ;
              "CREATE OR REPLACE TABLE mv_ventes_mois AS" + nl + ;
              "SELECT date_trunc('month', date) AS mois, sum(montant) AS total FROM ventes GROUP BY ALL;"
  cas nom = "Macro"
    retourner "CREATE OR REPLACE MACRO ttc(ht, taux := 20) AS ht * (1 + taux / 100);"
  cas nom = "Fonction"
    retourner "CREATE OR REPLACE MACRO ventes_de(c) AS TABLE" + nl + "SELECT * FROM ventes WHERE client_id = c;"
  cas nom = "Index"
    retourner "CREATE INDEX idx_ventes_client ON ventes (client_id);"
  cas nom = "Import"
    retourner "CREATE TABLE import AS SELECT * FROM read_csv_auto('donnees/*.csv', union_by_name = true);"
  cas nom = "Export"
    retourner "COPY (SELECT * FROM ventes) TO 'export/ventes' (FORMAT parquet, PARTITION_BY (annee), OVERWRITE_OR_IGNORE);"
  cas nom = "Jointure"
    retourner "SELECT c.nom, v.montant" + nl + "FROM ventes v" + nl + "JOIN clients c ON c.id = v.client_id;"
  cas nom = "Filtre"
    retourner "SELECT * FROM ventes WHERE date >= DATE '2026-01-01' AND montant > 100;"
  cas nom = "Agrégation"
    retourner "SELECT client_id, count(*) AS nb, sum(montant) AS total" + nl + "FROM ventes GROUP BY ALL ORDER BY total DESC;"
  cas nom = "Tri"
    retourner "SELECT * FROM ventes ORDER BY montant DESC LIMIT 100;"
  cas nom = "Union"
    retourner "SELECT * FROM ventes_2025" + nl + "UNION ALL BY NAME" + nl + "SELECT * FROM ventes_2026;"
  cas nom = "Fenêtres analytiques"
    retourner "SELECT client_id, date, montant," + nl + ;
              "  sum(montant) OVER (PARTITION BY client_id ORDER BY date) AS cumul," + nl + ;
              "  rank() OVER (PARTITION BY client_id ORDER BY montant DESC) AS rang" + nl + "FROM ventes;"
  cas nom = "Transformation"
    retourner "SELECT * REPLACE (upper(nom) AS nom), strftime(date, '%Y-%m') AS mois FROM clients;"
  cas nom = "Fusion (MERGE)"
    retourner "INSERT OR REPLACE INTO clients SELECT * FROM clients_import;" + nl + ;
              "-- (MERGE INTO … USING … ON … : DuckDB 1.4 et plus)"
  fincas
retourner nul

procedure PALETTE_CHOIX(ev)
  locale nom = sisinon(ev.chemin <> nul, ev.chemin[#ev.chemin], ev.texte)
  locale md = "### " + nom + car(10)
  locale t = TYPE_SOURCE(nom)
  si t <> nul
    locale k = CONNECTEUR(t)
    md = md + "Source : **" + sisinon(k = nul, t, k.libelle) + "**. Double-clic : nouvelle connexion."
  sinonsi MODELE_SQL(nom) <> nul
    md = md + "Double-clic : insère le modèle SQL dans la requête active." + car(10) + car(10) + ;
         "```" + car(10) + MODELE_SQL(nom) + car(10) + "```"
  sinonsi contient({"Profiling", "Analyse volumétrique", "Analyse mémoire", "Analyse coût", "Recommandations"}, nom)
    md = md + "Double-clic : lance l'analyse."
  sinonsi nom = "Pipeline" ou nom = "Workflow"
    md = md + "Double-clic : nouveau pipeline (sources, transformations, cibles), ou onglet Pipelines → SQL → pipeline pour partir d'un script."
  sinonsi nom = "Job" ou nom = "Déclencheur" ou nom = "Planificateur"
    md = md + "Double-clic : nouveau travail planifié (pipeline, requête ou script ; manuel, périodique, quotidien ou chaîné)."
  sinonsi nom = "Assistant"
    md = md + "Double-clic : ouvre l'assistant (explication de plan, réécriture, texte → SQL, génération de modèle)."
  sinonsi nom = "Élément BI"
    md = md + "Double-clic : élément de tableau de bord BI sur la dernière requête exécutée."
  sinon
    md = md + "Double-clic : gestionnaire des extensions du projet."
  finsi
  infopal.valeur = md
retourner

procedure PALETTE_UTILISER(ev)
  locale nom = sisinon(ev.chemin <> nul, ev.chemin[#ev.chemin], ev.texte)
  locale t = TYPE_SOURCE(nom)
  si t <> nul
    CONNEXION_DIALOGUE(nul, t)
    retourner
  finsi
  locale m = MODELE_SQL(nom)
  si m <> nul
    vues.valeur = 1
    ed:inserer(car(10) + m + car(10))
    retourner
  finsi
  faire cas
  cas nom = "Profiling" ou nom = "Analyse coût"
    PROFILER()
  cas nom = "Analyse volumétrique" ou nom = "Analyse mémoire" ou nom = "Recommandations"
    ANALYSER_TOUT()
  cas nom = "Pipeline" ou nom = "Workflow"
    vues.valeur = INDEX_VUE("Pipelines")
    PIPE_NOUVEAU(nul)
  cas nom = "Job" ou nom = "Déclencheur" ou nom = "Planificateur"
    vues.valeur = INDEX_VUE("Planification")
    PLANIF_NOUVEAU(nul)
  cas nom = "Assistant"
    bas.valeur = INDEX_BAS("Assistant")
    ia.question:focus()
  cas nom = "Élément BI"
    BI_DEPUIS_RESULTAT(nul)
  cas nom = "Extensions"
    EXT_GESTIONNAIRE()
  fincas
retourner
