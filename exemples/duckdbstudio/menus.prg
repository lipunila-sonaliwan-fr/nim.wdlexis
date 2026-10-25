&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : menus, raccourcis, à propos.

fonction MENUS()
retourner { ;
  {"Fichier", {"Nouvelle requête", "Ouvrir un script…", "Enregistrer le script", "-", ;
               "Ouvrir un projet…", "Enregistrer le projet", "Créer la base de démonstration", "-", "Quitter"}}, ;
  {"Connexion", {"Nouvelle connexion…", "Modifier la connexion…", "Tester la connexion", ;
                 "Supprimer la connexion", "-", "Relire tous les catalogues"}}, ;
  {"Requête", {"Exécuter (F5)", "Profiler (F6)", "Compter les lignes du résultat", "Exporter le résultat…", ;
               "-", "Commenter / décommenter", "Effacer l'historique"}}, ;
  {"Conception", {"Schéma de la connexion sélectionnée", "Script → modèle", "Modèle → SQL", ;
                  "Nouvelle table", "Analyse d'impact"}}, ;
  {"Analyse", {"Analyser le projet", "Générer la correction", "Rétablir les recommandations ignorées"}}, ;
  {"Affichage", {"Requêtes", "Schéma", "Profil", "Recommandations", "Cartographie", "Tableau de bord", "-", ;
                 "Thème sombre / clair"}}, ;
  {"Aide", {"Raccourcis clavier", "Connecteurs disponibles", "À propos"}}}

procedure CONSTRUIRE_MENUS(m)
  pour chaque groupe dans MENUS()
    pour chaque e dans groupe[2]
      m:ajouter(groupe[1], e)
    suivant
  suivant
retourner

fonction CONNEXION_SELECTIONNEE()
  si noeudcourant <> nul et noeudcourant.cnx <> nul
    retourner noeudcourant.cnx
  finsi
  si #projet.connexions = 1
    retourner projet.connexions[1]
  finsi
retourner nul

procedure MENU(ev)
  locale choix = ev.texte
  si ev.chemin <> nul
    choix = ev.chemin[#ev.chemin]
  finsi
  locale c = CONNEXION_SELECTIONNEE()
  faire cas
  && Fichier
  cas choix = "Nouvelle requête"
    NOUVELLE_REQUETE()
  cas choix = "Ouvrir un script…"
    OUVRIR_SCRIPT()
  cas choix = "Enregistrer le script"
    ENREGISTRER_SCRIPT()
  cas choix = "Ouvrir un projet…"
    OUVRIR_PROJET()
  cas choix = "Enregistrer le projet"
    ENREGISTRER_PROJET()
    STATUT("Projet enregistré : " + FICHIER_PROJET())
  cas choix = "Créer la base de démonstration"
    CREER_DEMO()
  cas choix = "Quitter"
    FERMETURE(nul)
    fen:fermer()
  && Connexion
  cas choix = "Nouvelle connexion…"
    NOUVELLE_CONNEXION()
  cas choix = "Modifier la connexion…"
    si c = nul
      STATUT("Sélectionnez une connexion dans l'explorateur.")
    sinon
      CONNEXION_DIALOGUE(c, c.type)
    finsi
  cas choix = "Tester la connexion"
    si c = nul
      STATUT("Sélectionnez une connexion dans l'explorateur.")
    sinon
      locale p = PING(c)
      STATUT(c.nom + " : " + sisinon(p <> nul, "répond en " + p + " ms", "ne répond pas (non attachée ?)"))
    finsi
  cas choix = "Supprimer la connexion"
    si c <> nul
      SUPPRIMER_CONNEXION(c)
    finsi
  cas choix = "Relire tous les catalogues"
    RAFRAICHIR_TOUT()
  && Requête
  cas commencepar(choix, "Exécuter")
    EXECUTER_SQL()
  cas commencepar(choix, "Profiler")
    PROFILER()
  cas choix = "Compter les lignes du résultat"
    COMPTER_RESULTAT(nul)
  cas choix = "Exporter le résultat…"
    EXPORTER_RESULTAT(nul)
  cas choix = "Commenter / décommenter"
    ed:commande("commenter")
  cas choix = "Effacer l'historique"
    si ui.confirmer("Effacer les " + #projet.historique + " requête(s) de l'historique ?")
      projet.historique = {}
      REMPLIR_HISTORIQUE()
      ENREGISTRER_PROJET()
    finsi
  && Conception
  cas choix = "Schéma de la connexion sélectionnée"
    si c = nul
      STATUT("Sélectionnez une connexion dans l'explorateur.")
    sinon
      SCHEMA_DEPUIS_CATALOGUE(c, sisinon(noeudcourant <> nul et noeudcourant.schema <> nul, noeudcourant.schema, ""))
    finsi
  cas choix = "Script → modèle"
    SCHEMA_DEPUIS_SCRIPT(nul)
  cas choix = "Modèle → SQL"
    SCHEMA_GENERER(nul)
  cas choix = "Nouvelle table"
    vues.valeur = 2
    SCHEMA_NOUVELLE_TABLE(nul)
  cas choix = "Analyse d'impact"
    vues.valeur = 2
    SCHEMA_IMPACT(nul)
  && Analyse
  cas choix = "Analyser le projet"
    ANALYSER_TOUT()
  cas choix = "Générer la correction"
    RECO_CORRECTION(nul)
  cas choix = "Rétablir les recommandations ignorées"
    projet.ignorees = {}
    ENREGISTRER_PROJET()
    ANALYSER_TOUT()
  && Affichage
  cas choix = "Requêtes"
    vues.valeur = 1
  cas choix = "Schéma"
    VOIR_SCHEMA(nul)
  cas choix = "Profil"
    vues.valeur = 3
  cas choix = "Recommandations"
    vues.valeur = 4
  cas choix = "Cartographie"
    VOIR_CARTO(nul)
  cas choix = "Tableau de bord"
    VOIR_TABLEAU(nul)
  cas choix = "Thème sombre / clair"
    reglages.sombre = non reglages.sombre
    fen:fixertheme("natif", reglages.sombre)
    DS_ECRIRE_REGLAGES()
  && Aide
  cas choix = "Raccourcis clavier"
    ui.alerte(RACCOURCIS(), "information", "Raccourcis clavier")
  cas choix = "Connecteurs disponibles"
    LISTE_CONNECTEURS()
  cas choix = "À propos"
    ui.alerte("DuckDB [S]tudio 0.7.3\nAtelier DuckDB (écrit en Lexis+)\n" +
              "Développez naturellement vos applications métier\n\n" +
              "Tous droits réservés 2026 - Jean-Marc QUÉRÉ\n" +
              "⛶ https://sonaliwan.fr  ✉ metalab (at) sonaliwan.fr\n" +
              "SIRET 13033319800013\n\n" +
              "Moteur : DuckDB " + VERSION_DUCKDB() + car(10) +
              "Connecteurs : " + #TYPES_CONNECTEURS() + " (dossier connecteurs/)"
              , "information", "À propos")
  fincas
retourner

procedure VOIR_SCHEMA(ev)
  && le modèle courant, sinon celui de la connexion sélectionnée
  si modele = nul
    locale c = CONNEXION_SELECTIONNEE()
    si c = nul et #projet.connexions > 0
      c = projet.connexions[1]
    finsi
    si c <> nul
      SCHEMA_DEPUIS_CATALOGUE(c, sisinon(noeudcourant <> nul et noeudcourant.schema <> nul, noeudcourant.schema, ""))
    finsi
  finsi
  SCHEMA_SOURCES()
  vues.valeur = 2
retourner

fonction RACCOURCIS()
  locale nl = car(10)
retourner "F5 / Ctrl+R : exécuter la sélection, ou tout le script" + nl + ;
          "F6 : profiler la requête sous le curseur (EXPLAIN ANALYZE)" + nl + ;
          "Ctrl+S : enregistrer le script" + nl + ;
          "Ctrl+Espace : complétion (tables, colonnes après « table. », mots clés, fonctions)" + nl + ;
          "Ctrl+/ : commenter / décommenter (--)" + nl + nl + ;
          "Concepteur de schéma :" + nl + ;
          "  glisser une table : la déplacer ; glisser le fond : déplacer la vue ; molette : zoom" + nl + ;
          "  glisser la pastille d'une colonne vers une colonne d'une autre table : clé étrangère" + nl + ;
          "  Suppr : supprimer la table ou la clé sélectionnée (après analyse d'impact)"

procedure LISTE_CONNECTEURS
  locale nl = car(10)
  locale l = {}
  pour chaque k dans TYPES_CONNECTEURS()
    inserer(l, "[" + k.sigle + "] " + k.libelle + " - " + k.type + sisinon(k.extension = nul, "", " (extension " + k.extension + ")"))
  suivant
  ui.alerte(joindre(l, nl) + nl + nl + "Ajoutez un connecteur en déposant un fichier .json dans le dossier connecteurs/ " + ;
            "du programme ou du projet.", "information", "Connecteurs")
retourner
