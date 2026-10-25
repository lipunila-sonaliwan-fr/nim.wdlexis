&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : base de démonstration. Crée dans le dossier du projet :
&&   demo.duckdb            clients, produits, ventes (≈ 1,5 million de lignes, clés
&&                          primaires et étrangères), journal (sans clé), deux vues
&&   fichiers/objectifs.csv objectifs mensuels par catégorie (source « fichiers »)
&&   demo.sql               requêtes d'exemple (jointure fédérée base + CSV comprise)
&& puis déclare les connexions « demo » et « objectifs ».

procedure CREER_DEMO
  locale chemin = fichier.joindre(dossier, "demo.duckdb")
  pour chaque c dans projet.connexions
    si minuscule(c.nom) = "demo"
      si non ui.confirmer("La connexion « demo » existe déjà. Recréer la base de démonstration ?")
        retourner
      finsi
      DETACHER(c)
    finsi
  suivant
  STATUT("Création de la base de démonstration…")
  locale t0 = systeme.horloge()
  essayer
    si fichier.existe(chemin)
      fichier.supprimer(chemin)
    finsi
    requete("ATTACH " + LITTERAL(chemin) + " AS demo_creation")
    requete("USE demo_creation")
    requete("SELECT setseed(0.42)")
    requete("CREATE TABLE clients (id INTEGER PRIMARY KEY, nom VARCHAR NOT NULL, ville VARCHAR, segment VARCHAR, " + ;
            "inscrit DATE)")
    requete("INSERT INTO clients SELECT i, 'Client ' || i, " + ;
            "['Paris','Lyon','Marseille','Lille','Nantes','Bordeaux','Toulouse','Rennes'][1 + (i % 8)], " + ;
            "['Particulier','PME','Grand compte'][1 + (hash(i) % 3)::INTEGER], " + ;
            "DATE '2019-01-01' + (i % 2000)::INTEGER FROM range(1, 50001) t(i)")
    requete("CREATE TABLE produits (id INTEGER PRIMARY KEY, libelle VARCHAR NOT NULL, categorie VARCHAR, " + ;
            "prix DECIMAL(10,2))")
    requete("INSERT INTO produits SELECT i, 'Produit ' || i, " + ;
            "['Maison','Jardin','Bureau','Sport','Loisirs','Cuisine'][1 + (i % 6)], " + ;
            "round(5 + random() * 495, 2) FROM range(1, 2001) t(i)")
    requete("CREATE TABLE ventes (id BIGINT PRIMARY KEY, client_id INTEGER REFERENCES clients(id), " + ;
            "produit_id INTEGER REFERENCES produits(id), jour DATE, quantite INTEGER, montant DECIMAL(12,2))")
    requete("INSERT INTO ventes SELECT i, 1 + (hash(i) % 50000)::INTEGER, 1 + (hash(i * 7) % 2000)::INTEGER, " + ;
            "DATE '2023-01-01' + (i % 1000)::INTEGER, 1 + (i % 5)::INTEGER, 0 FROM range(1, 1500001) t(i)")
    requete("UPDATE ventes SET montant = ventes.quantite * p.prix FROM produits p WHERE p.id = ventes.produit_id")
    requete("CREATE TABLE journal (quand TIMESTAMP, niveau VARCHAR, message VARCHAR)")
    requete("INSERT INTO journal SELECT TIMESTAMP '2024-01-01' + INTERVAL (i) MINUTE, " + ;
            "['INFO','INFO','INFO','ALERTE','ERREUR'][1 + (i % 5)], 'événement ' || i FROM range(0, 20000) t(i)")
    requete("CREATE VIEW ventes_detail AS SELECT v.id, v.jour, c.nom AS client, c.ville, p.libelle AS produit, " + ;
            "p.categorie, v.quantite, v.montant FROM ventes v JOIN clients c ON c.id = v.client_id " + ;
            "JOIN produits p ON p.id = v.produit_id")
    requete("CREATE VIEW ca_mensuel AS SELECT date_trunc('month', jour)::DATE AS mois, categorie, sum(montant) AS ca " + ;
            "FROM ventes_detail GROUP BY ALL")
    requete("USE memory")
    requete("DETACH demo_creation")
  capturer e
    essayer
      requete("USE memory")
      requete("DETACH DATABASE IF EXISTS demo_creation")
    capturer e2
    finessayer
    ERREUR("Base de démonstration : " + e)
    retourner
  finessayer
  && fichier CSV : objectifs mensuels par catégorie
  locale dcsv = fichier.joindre(dossier, "fichiers")
  fichier.creerdossier(dcsv)
  locale l = {"mois,categorie,objectif"}
  pour m = 1 a 12
    pour chaque cat dans {"Maison", "Jardin", "Bureau", "Sport", "Loisirs", "Cuisine"}
      inserer(l, "2024-" + droite("0" + m, 2) + "-01," + cat + "," + (5200000 + m * 60000))
    suivant
  suivant
  fichier.ecrire(fichier.joindre(dcsv, "objectifs.csv"), joindre(l, car(10)) + car(10))
  && script d'exemple
  fichier.ecrire(fichier.joindre(dossier, "demo.sql"), SCRIPT_DEMO())
  && connexions
  DEMO_CONNEXION({nom = "demo", description = "Base de démonstration (ventes)", type = "duckdb", ;
                  parametres = {FICHIER = "demo.duckdb"}, options = {LECTURE = faux}})
  DEMO_CONNEXION({nom = "objectifs", description = "Objectifs mensuels (CSV)", type = "csv", ;
                  parametres = {DOSSIER = "fichiers", MOTIF = "*.csv"}, options = {}})
  ENREGISTRER_PROJET()
  REMPLIR_EXPLORATEUR()
  NOMS_COMPLETION()
  locale u = ed:ouvrir(fichier.joindre(dossier, "demo.sql"))
  ed:langage("sql", u)
  STATUT("Base de démonstration créée en " + arrondi(systeme.horloge() - t0, 1) + " s : demo.duckdb, fichiers/objectifs.csv, demo.sql")
  SCHEMA_DEPUIS_CATALOGUE(DEMO_TROUVER("demo"), "main")
retourner

fonction DEMO_TROUVER(nom)
  pour chaque c dans projet.connexions
    si minuscule(c.nom) = nom
      retourner c
    finsi
  suivant
retourner nul

procedure DEMO_CONNEXION(c)
  locale garde = {}
  pour chaque x dans projet.connexions
    si minuscule(x.nom) <> minuscule(c.nom)
      inserer(garde, x)
    sinon
      DETACHER(x)
    finsi
  suivant
  inserer(garde, c)
  projet.connexions = garde
  locale r = ATTACHER(c, faux)
  si non r.ok
    ERREUR(c.nom + " : " + r.message)
  finsi
retourner

fonction SCRIPT_DEMO()
  locale nl = car(10)
retourner "-- DuckDB [S]tudio : requêtes de démonstration" + nl + ;
  "-- F5 exécute la sélection (ou tout le script), F6 profile la requête sous le curseur." + nl + nl + ;
  "-- 1. Chiffre d'affaires par ville" + nl + ;
  "SELECT c.ville, count(*) AS ventes, sum(v.montant) AS ca" + nl + ;
  "FROM demo.ventes v JOIN demo.clients c ON c.id = v.client_id" + nl + ;
  "GROUP BY c.ville ORDER BY ca DESC;" + nl + nl + ;
  "-- 2. Meilleurs produits (tri complet : voir le profil)" + nl + ;
  "SELECT p.libelle, p.categorie, sum(v.quantite) AS qte, sum(v.montant) AS ca" + nl + ;
  "FROM demo.ventes v JOIN demo.produits p ON p.id = v.produit_id" + nl + ;
  "GROUP BY ALL ORDER BY ca DESC LIMIT 20;" + nl + nl + ;
  "-- 3. Requête fédérée : base DuckDB + fichier CSV" + nl + ;
  "SELECT m.mois, m.categorie, m.ca, o.objectif, round(100 * m.ca / o.objectif, 1) AS atteinte" + nl + ;
  "FROM demo.ca_mensuel m JOIN objectifs.objectifs o" + nl + ;
  "  ON o.mois = m.mois AND o.categorie = m.categorie" + nl + ;
  "ORDER BY m.mois, m.categorie;" + nl + nl + ;
  "-- 4. Produit cartésien involontaire (le moteur d'expertise le signale)" + nl + ;
  "SELECT count(*) FROM demo.clients c, demo.produits p WHERE c.ville = 'Lyon' AND p.prix > 400;" + nl + nl + ;
  "-- 5. Balayage complet sans filtre" + nl + ;
  "SELECT avg(montant) FROM demo.ventes;" + nl
