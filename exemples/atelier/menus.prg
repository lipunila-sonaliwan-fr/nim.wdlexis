&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ : menus (les mêmes que l'atelier natif), raccourcis, à propos.

fonction MENUS()
retourner { ;
  {"Fichier", {"Nouveau projet…", "Ouvrir un projet…", "Ouvrir un dossier par son chemin…", ;
               "Nouveau fichier…", "Ouvrir un fichier…", "Enregistrer", "Enregistrer sous…", ;
               "Enregistrer tout", "Fermer l'onglet", "-", "Dupliquer le fichier…", "Renommer le fichier…", ;
               "Supprimer le fichier…", "-", "Exporter le projet (archive)…", ;
               "Importer un projet (archive)…", "-", "Quitter"}}, ;
  {"Édition", {"Annuler", "Rétablir", "Couper", "Copier", "Coller", "Tout sélectionner", ;
               "Dupliquer la ligne", "Commenter / décommenter", "Indenter", "Désindenter", "-", ;
               "Formater le document (Ctrl+Maj+F)", "Conventions de formatage du projet…"}}, ;
  {"Recherche", {"Rechercher…", "Remplacer…", "Occurrence suivante", "Aller à la ligne…", ;
                 "Aller à la définition (F12)", "Lister les usages (Maj+F12)"}}, ;
  {"Exécuter", {"Exécuter (Ctrl+R)", "Déboguer / Continuer (F5)", "Pas à pas (F11)", ;
                "Pas principal (F10)", "Sortir de la procédure (Maj+F11)", "Pause", ;
                "Arrêter (Maj+F5)", "Basculer le point d'arrêt (F9)", ;
                "Supprimer tous les points d'arrêt", "Vérifier les fichiers ouverts", ;
                "Arguments et fichier principal…", "-", "Lancer les tests (Ctrl+T)", ;
                "Lancer les tests du fichier courant", "Profiler le programme", "-", ;
                "Générer l'application…"}}, ;
  {"Git", {"Statut du dépôt", "Comparer le fichier avec la dernière validation", ;
           "Comparer le projet avec la dernière validation", "Annotations du fichier (blame)", ;
           "Historique du fichier", "-", "Fusionner une branche…", "Conflits : garder la version locale", ;
           "Conflits : garder la version fusionnée", "Conflits : garder les deux", "Abandonner la fusion", ;
           "-", "Valider (commit)…"}}, ;
  {"Conception", {"Vue projet…", "Vue blueprint du fichier courant", "-", "Nouveau formulaire pour le fichier courant…", "Ouvrir un formulaire…", ;
                  "Concepteur de formulaires", "-", "Nouvel état…", "Ouvrir un état…"}}, ;
  {"Affichage", {"Agrandir la police (Ctrl++)", "Réduire la police (Ctrl+-)", ;
                 "Taille de police par défaut (Ctrl+0)", "Minicarte afficher / masquer", ;
                 "Thème sombre / clair", "-", ;
                 "Signaler les variables globales implicites", "Signaler les procédures inconnues", ;
                 "Signaler les collisions de noms", "Contrôler les types déclarés", "-", ;
                 "Copier la console", "Effacer la console", "-", ;
                 "Problèmes - Console - ... : afficher / masquer", ;
                 "Problèmes - Console - ... : fenêtre dédiée", ;
                 "Projet - Structure - ... : afficher / masquer", ;
                 "Projet - Structure - ... : fenêtre dédiée"}}, ;
  {"Aide", {"Raccourcis clavier", "Référence des fonctions et paquets", "À propos"}}}

procedure CONSTRUIRE_MENUS(m)
  pour chaque groupe dans MENUS()
    pour chaque e dans groupe[2]
      m:ajouter(groupe[1], e)
    suivant
  suivant
retourner

procedure MENU(ev)
  locale choix = ev.texte
  si ev.chemin <> nul
    choix = ev.chemin[#ev.chemin]
  finsi
  faire cas
  && Fichier
  cas choix = "Nouveau projet…"
    NOUVEAU_PROJET()
  cas choix = "Ouvrir un projet…"
    OUVRIR_PROJET()
  cas choix = "Ouvrir un dossier par son chemin…"
    OUVRIR_DOSSIER()
  cas choix = "Nouveau fichier…"
    NOUVEAU_FICHIER()
  cas choix = "Ouvrir un fichier…"
    OUVRIR_FICHIER()
  cas choix = "Enregistrer"
    ENREGISTRER()
  cas choix = "Enregistrer sous…"
    ENREGISTRER_SOUS()
  cas choix = "Enregistrer tout"
    TOUT_ENREGISTRER()
  cas choix = "Fermer l'onglet"
    FERMER_DOCUMENT(ed:actif())
  cas choix = "Quitter"
    QUITTER()
  && Édition
  cas choix = "Annuler"
    ed:commande("annuler")
  cas choix = "Rétablir"
    ed:commande("retablir")
  cas choix = "Couper"
    ed:commande("couper")
  cas choix = "Copier"
    ed:commande("copier")
  cas choix = "Coller"
    ed:commande("coller")
  cas choix = "Tout sélectionner"
    ed:commande("toutselectionner")
  cas choix = "Dupliquer la ligne"
    ed:commande("dupliquer")
  cas choix = "Commenter / décommenter"
    ed:commande("commenter")
  cas choix = "Indenter"
    ed:commande("indenter")
  cas choix = "Désindenter"
    ed:commande("desindenter")
  cas commencepar(choix, "Formater le document")
    FORMATER_DOCUMENT()
  cas choix = "Conventions de formatage du projet…"
    CONVENTIONS_FORMATAGE()
  && Recherche
  cas choix = "Rechercher…"
    RECHERCHER(faux)
  cas choix = "Remplacer…"
    RECHERCHER(vrai)
  cas choix = "Occurrence suivante"
    SUIVANT_TROUVE(faux)
  cas choix = "Aller à la ligne…"
    ALLER_LIGNE()
  cas commencepar(choix, "Aller à la définition")
    ALLER_DEFINITION(ed:motcourant())
  cas commencepar(choix, "Lister les usages")
    LISTER_USAGES()
  && Exécuter
  cas commencepar(choix, "Exécuter")
    EXECUTER()
  cas commencepar(choix, "Déboguer")
    DEBOGUER_OU_CONTINUER()
  cas commencepar(choix, "Pas à pas")
    PAS()
  cas commencepar(choix, "Pas principal")
    PASSER()
  cas commencepar(choix, "Sortir")
    SORTIR()
  cas choix = "Pause"
    PAUSE_DEMANDEE()
  cas commencepar(choix, "Arrêter")
    ARRETER()
  cas commencepar(choix, "Basculer le point")
    ed:basculerpointarret()
  cas choix = "Supprimer tous les points d'arrêt"
    ed:effacerpointsarret()
  cas choix = "Vérifier les fichiers ouverts"
    VERIFIER_TOUT()
  cas choix = "Arguments et fichier principal…"
    ARGUMENTS()
  cas commencepar(choix, "Lancer les tests (")
    LANCER_TESTS(faux)
  cas choix = "Lancer les tests du fichier courant"
    LANCER_TESTS(vrai)
  cas choix = "Profiler le programme"
    PROFILER()
  cas choix = "Générer l'application…"
    GENERER_DIALOGUE()
  && Git
  cas choix = "Statut du dépôt"
    GIT_STATUT()
  cas choix = "Comparer le fichier avec la dernière validation"
    GIT_COMPARER(faux)
  cas choix = "Comparer le projet avec la dernière validation"
    GIT_COMPARER(vrai)
  cas choix = "Annotations du fichier (blame)"
    GIT_ANNOTATIONS()
  cas choix = "Historique du fichier"
    GIT_HISTORIQUE()
  cas choix = "Fusionner une branche…"
    GIT_FUSIONNER()
  cas choix = "Conflits : garder la version locale"
    GIT_RESOUDRE("local")
  cas choix = "Conflits : garder la version fusionnée"
    GIT_RESOUDRE("fusion")
  cas choix = "Conflits : garder les deux"
    GIT_RESOUDRE("deux")
  cas choix = "Abandonner la fusion"
    GIT_ABANDONNER()
  cas choix = "Valider (commit)…"
    GIT_VALIDER()
  && Conception
  cas choix = "Vue projet…"
    VUE_PROJET()
  cas choix = "Vue blueprint du fichier courant"
    BLUEPRINT_BASCULER()
  cas choix = "Nouveau formulaire pour le fichier courant…"
    CONCEPTEUR_NOUVEAU()
  cas choix = "Ouvrir un formulaire…"
    CONCEPTEUR_CHOISIR()
  cas choix = "Concepteur de formulaires"
    CONCEPTEUR_BOUTON()
  cas choix = "Nouvel état…"
    ETAT_NOUVEAU()
  cas choix = "Ouvrir un état…"
    ETAT_CHOISIR()
  && Affichage
  cas choix = "Projet - Structure - ... : afficher / masquer"
    GAUCHE_BASCULER(nul)
  cas choix = "Projet - Structure - ... : fenêtre dédiée"
    GAUCHE_FENETRE(nul)
  cas choix = "Problèmes - Console - ... : afficher / masquer"
    BAS_BASCULER(nul)
  cas choix = "Problèmes - Console - ... : fenêtre dédiée"
    BAS_FENETRE(nul)
  cas choix = "Dupliquer le fichier…"
    FICHIER_DUPLIQUER(nul)
  cas choix = "Renommer le fichier…"
    FICHIER_RENOMMER(nul)
  cas choix = "Supprimer le fichier…"
    FICHIER_SUPPRIMER(nul)
  cas choix = "Exporter le projet (archive)…"
    PROJET_EXPORTER()
  cas choix = "Importer un projet (archive)…"
    PROJET_IMPORTER()
  cas choix = "Copier la console"
    COPIER_CONSOLE()
  cas choix = "Effacer la console"
    EFFACER_CONSOLE()
  cas commencepar(choix, "Agrandir")
    POLICE(1)
  cas commencepar(choix, "Réduire")
    POLICE(-1)
  cas commencepar(choix, "Taille de police")
    POLICE(0)
  cas choix = "Minicarte afficher / masquer"
    BASCULER_MINICARTE()
  cas choix = "Thème sombre / clair"
    BASCULER_THEME()
  cas choix = "Signaler les variables globales implicites"
    BASCULER_GLOBALES()
  cas choix = "Signaler les procédures inconnues"
    BASCULER_INCONNUES()
  cas choix = "Signaler les collisions de noms"
    BASCULER_COLLISIONS()
  cas choix = "Contrôler les types déclarés"
    BASCULER_TYPES()
  && Aide
  cas choix = "Raccourcis clavier"
    ui.alerte(RACCOURCIS(), "information", "Raccourcis clavier")
  cas choix = "Référence des fonctions et paquets"
    AFFICHER_OUTILS(3)
  cas choix = "À propos"
    ui.alerte("wdlexis+ [S]tudio 2.1.3\nAtelier du langage Lexis+\n" +
              "Développez naturellement vos applications métier\n\n" +
              "Tous droits réservés 2026 - Jean-Marc QUÉRÉ\n" +
              "⛶ https://sonaliwan.fr  ✉ metalab (at) sonaliwan.fr\n" +
              "SIRET 13033319800013"
              , "information", "À propos")
  fincas
retourner

fonction RACCOURCIS()
  locale l = {"Édition", ;
    "Ctrl+X/C/V couper, copier, coller        Ctrl+Z/Y annuler, rétablir", ;
    "Ctrl+F rechercher, Ctrl+H / F3 suivant   Ctrl+L aller à la ligne", ;
    "Ctrl+W/E début / fin de ligne            Ctrl+D dupliquer la ligne", ;
    "Tab / Maj+Tab indenter, désindenter      Ctrl+B commenter / décommenter (&&)", ;
    "Ctrl+Espace complétion                   Ctrl+ + / - / 0 taille de la police", ;
    "F12 ou Ctrl+clic aller à la définition   Maj+F12 lister les usages", ;
    "Ctrl+Maj+F formater le document          Ctrl+Tab document suivant", ;
    "Survol d'un nom : infobulle (définition, type, documentation)", ;
    "", ;
    "Exécution et débogage", ;
    "Ctrl+R exécuter (sans débogueur)         F5 déboguer / continuer", ;
    "F9 ou clic dans la marge : point d'arrêt F10 pas principal", ;
    "F11 pas à pas                            Maj+F11 sortir de la procédure", ;
    "Maj+F5 arrêter                           Ctrl+T lancer les tests", ;
    "En pause, page Variables : double-clic sur une table (▸) pour voir et modifier son contenu", ;
    "", ;
    "Fenêtre Blueprint (clic sur la pastille rouge d'un onglet)", ;
    "Glisser depuis la palette, relier les broches   Suppr supprimer la sélection", ;
    "Ctrl+Z/Y annuler, rétablir                      F ou Origine tout voir", ;
    "Double-clic sur l'icône fichier d'un appel : la procédure s'ouvre en blueprint", ;
    "Ctrl+Tab fichier suivant ; << / >> palette des entités, fenêtre dédiée", ;
    "", ;
    "Vue projet (Conception > Vue projet…)", ;
    "Une colonne par fichier ; clic : appels (orange) et appelants (vert)", ;
    "Double-clic : ouvrir le code à la définition"}
retourner joindre(l, car(10))
