&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ : menus (les mêmes que l'atelier natif), raccourcis, à propos.

fonction MENUS()
retourner { ;
  {"Fichier", {"Nouveau projet…", "Ouvrir un projet…", "Ouvrir un dossier par son chemin…", ;
               "Nouveau fichier…", "Ouvrir un fichier…", "Enregistrer", "Enregistrer sous…", ;
               "Enregistrer tout", "Fermer l'onglet", "Quitter"}}, ;
  {"Édition", {"Annuler", "Rétablir", "Couper", "Copier", "Coller", "Tout sélectionner", ;
               "Dupliquer la ligne", "Commenter / décommenter", "Indenter", "Désindenter"}}, ;
  {"Recherche", {"Rechercher…", "Remplacer…", "Occurrence suivante", "Aller à la ligne…", ;
                 "Aller à la définition"}}, ;
  {"Exécuter", {"Exécuter (Ctrl+R)", "Déboguer / Continuer (F5)", "Pas à pas (F11)", ;
                "Pas principal (F10)", "Sortir de la procédure (Maj+F11)", "Pause", ;
                "Arrêter (Maj+F5)", "Basculer le point d'arrêt (F9)", ;
                "Supprimer tous les points d'arrêt", "Vérifier les fichiers ouverts", ;
                "Arguments et fichier principal…", "Générer l'application…"}}, ;
  {"Conception", {"Nouveau formulaire pour le fichier courant…", "Ouvrir un formulaire…", ;
                  "Concepteur de formulaires", "-", "Nouvel état…", "Ouvrir un état…"}}, ;
  {"Affichage", {"Copier la console", "Effacer la console", "Agrandir la police (Ctrl++)", ;
                 "Réduire la police (Ctrl+-)", "Taille de police par défaut (Ctrl+0)", ;
                 "Minicarte", "Thème sombre / clair", "Signaler les variables globales implicites", ;
                 "Signaler les procédures inconnues"}}, ;
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
  && Recherche
  cas choix = "Rechercher…"
    RECHERCHER(faux)
  cas choix = "Remplacer…"
    RECHERCHER(vrai)
  cas choix = "Occurrence suivante"
    SUIVANT_TROUVE(faux)
  cas choix = "Aller à la ligne…"
    ALLER_LIGNE()
  cas choix = "Aller à la définition"
    ALLER_DEFINITION(ed:motcourant())
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
  cas choix = "Générer l'application…"
    GENERER_DIALOGUE()
  && Conception
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
  cas choix = "Minicarte"
    BASCULER_MINICARTE()
  cas choix = "Thème sombre / clair"
    BASCULER_THEME()
  cas choix = "Signaler les variables globales implicites"
    BASCULER_GLOBALES()
  cas choix = "Signaler les procédures inconnues"
    BASCULER_INCONNUES()
  && Aide
  cas choix = "Raccourcis clavier"
    ui.alerte(RACCOURCIS(), "information", "Raccourcis clavier")
  cas choix = "Référence des fonctions et paquets"
    gauche.valeur = 3
  cas choix = "À propos"
    ui.alerte("wdlexis+ [S]tudio 1.7.2\nAtelier du langage Lexis+ (en Lexis+!)\n" +
      "Développez naturellement vos applications métier\n\n" +
      "Tous droits réservés 2026 - Jean-Marc QUÉRÉ\n" +
      "⛶ https://sonaliwan.fr - ✉ metalab (at) sonaliwan.fr\n" +
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
    "F12 ou Ctrl+clic aller à la définition   Ctrl+Tab document suivant", ;
    "", ;
    "Exécution et débogage", ;
    "Ctrl+R exécuter (sans débogueur)         F5 déboguer / continuer", ;
    "F9 ou clic dans la marge : point d'arrêt F10 pas principal", ;
    "F11 pas à pas                            Maj+F11 sortir de la procédure", ;
    "Maj+F5 arrêter"}
retourner joindre(l, car(10))
