&& CC BY-NC-SA 4.0 - HyperLexis, atelier de piles pour Lexis+ (wdlexis+)
&& hl_menus.prg : menus, raccourcis, aide, pile d'exemple.

fonction HL_MENUS()
retourner { ;
  {"Fichier", {"Nouvelle pile…", "Nouvelle pile d'exemple (carnet d'adresses)…", "Ouvrir une pile…", ;
               "Ouvrir un dossier par son chemin…", "Enregistrer (Ctrl+S)", "Enregistrer une copie sous…", ;
               "Lancer la pile autonome", "Générer l'application…", "Quitter"}}, ;
  {"Édition", {"Annuler", "Rétablir", "Couper", "Copier", "Coller", "Tout sélectionner", ;
               "Commenter / décommenter", "Rechercher dans le script…"}}, ;
  {"Carte", {"Nouvelle carte (nouveau modèle)…", "Nouvelle carte (même modèle) (Ctrl+N)", "Dupliquer la carte", ;
             "Copier le modèle (carte indépendante)…", "Renommer la carte…", "Supprimer la carte", ;
             "Avancer la carte", "Reculer la carte", "Importer un formulaire wdlexis+…", "-", ;
             "Première carte", "Carte précédente", "Carte suivante", "Dernière carte"}}, ;
  {"Objet", {"Sélectionner la carte", "Dupliquer l'objet (Ctrl+D)", "Supprimer l'objet", "Passer devant", ;
             "Passer derrière", "Modifier le script de l'objet", "Script de la carte", "Script de la pile"}}, ;
  {"Mode", {"Conception", "Exécution", "Basculer (Ctrl+E)", "Boîte de messages (Ctrl+M)"}}, ;
  {"Affichage", {"Thème sombre / clair", "Agrandir la police du script", "Réduire la police du script"}}, ;
  {"Aide", {"Guide pour commencer", "Fonctions des scripts", "Raccourcis clavier", "À propos"}}}
finfonction

procedure HL_CONSTRUIRE_MENUS(m)
  pour chaque groupe dans HL_MENUS()
    pour chaque e dans groupe[2]
      m:ajouter(groupe[1], e)
    suivant
  suivant
finprocedure

procedure HL_MENU(ev)
  locale choix = ev.texte
  si ev.chemin <> nul
    choix = ev.chemin[#ev.chemin]
  finsi
  faire cas
  && Fichier
  cas choix = "Nouvelle pile…"
    HL_NOUVELLE_PILE()
  cas commencepar(choix, "Nouvelle pile d'exemple")
    HL_NOUVEL_EXEMPLE()
  cas choix = "Ouvrir une pile…"
    HL_OUVRIR_PILE()
  cas choix = "Ouvrir un dossier par son chemin…"
    HL_OUVRIR_DOSSIER()
  cas commencepar(choix, "Enregistrer (")
    HL_ENREGISTRER(vrai)
  cas choix = "Enregistrer une copie sous…"
    HL_ENREGISTRER_SOUS()
  cas choix = "Lancer la pile autonome"
    HL_AUTONOME()
  cas choix = "Générer l'application…"
    HL_GENERER_DIALOGUE()
  cas choix = "Quitter"
    HL_FERMETURE(nul)
    hlc.fen:fermer()
  && Édition (dans le script)
  cas choix = "Annuler"
    hlc.ed:commande("annuler")
  cas choix = "Rétablir"
    hlc.ed:commande("retablir")
  cas choix = "Couper"
    hlc.ed:commande("couper")
  cas choix = "Copier"
    hlc.ed:commande("copier")
  cas choix = "Coller"
    hlc.ed:commande("coller")
  cas choix = "Tout sélectionner"
    hlc.ed:commande("toutselectionner")
  cas choix = "Commenter / décommenter"
    hlc.ed:commande("commenter")
  cas choix = "Rechercher dans le script…"
    HL_RECHERCHER()
  && Carte
  cas commencepar(choix, "Nouvelle carte (nouveau")
    HL_NOUVELLE_CARTE_MODELE()
  cas commencepar(choix, "Nouvelle carte (même")
    HL_NOUVELLE_CARTE_MEME()
  cas choix = "Dupliquer la carte"
    HL_DUPLIQUER_CARTE()
  cas commencepar(choix, "Copier le modèle")
    HL_DUPLIQUER_MODELE()
  cas choix = "Renommer la carte…"
    HL_RENOMMER_CARTE()
  cas choix = "Supprimer la carte"
    HL_SUPPRIMER_CARTE()
  cas choix = "Avancer la carte"
    HL_CARTE_MONTER()
  cas choix = "Reculer la carte"
    HL_CARTE_DESCENDRE()
  cas commencepar(choix, "Importer un formulaire")
    HL_IMPORTER_FORMULAIRE()
  cas choix = "Première carte"
    HL_ALLER("premiere")
  cas choix = "Carte précédente"
    HL_ALLER("precedente")
  cas choix = "Carte suivante"
    HL_ALLER("suivante")
  cas choix = "Dernière carte"
    HL_ALLER("derniere")
  && Objet
  cas choix = "Sélectionner la carte"
    HL_SELECTIONNER_CARTE()
  cas commencepar(choix, "Dupliquer l'objet")
    HL_DUPLIQUER_OBJET()
  cas choix = "Supprimer l'objet"
    HL_SUPPRIMER_OBJET()
  cas choix = "Passer devant"
    HL_OBJET_DESCENDRE()
  cas choix = "Passer derrière"
    HL_OBJET_MONTER()
  cas choix = "Modifier le script de l'objet"
    HL_MODIFIER_SCRIPT()
  cas choix = "Script de la carte"
    HL_SCRIPT_MODELE()
  cas choix = "Script de la pile"
    HL_SCRIPT_PILE()
  && Mode
  cas choix = "Conception"
    HL_MODE_CONCEPTION()
  cas choix = "Exécution"
    HL_MODE_EXECUTION()
  cas commencepar(choix, "Basculer")
    HL_BASCULER_MODE()
  cas commencepar(choix, "Boîte de messages")
    HL_ONGLET("messages")
    hlc.saisiemsg:focus()
  && Affichage
  cas choix = "Thème sombre / clair"
    hl.reglages.sombre = non hl.reglages.sombre
    hlc.fen:fixertheme("natif", hl.reglages.sombre)
    HL_ECRIRE_REGLAGES()
  cas choix = "Agrandir la police du script"
    hl.reglages.police = min(28, hl.reglages.police + 1)
    hlc.ed:taillepolice(hl.reglages.police)
    HL_ECRIRE_REGLAGES()
  cas choix = "Réduire la police du script"
    hl.reglages.police = max(9, hl.reglages.police - 1)
    hlc.ed:taillepolice(hl.reglages.police)
    HL_ECRIRE_REGLAGES()
  && Aide
  cas choix = "Guide pour commencer"
    HL_AIDE_FENETRE("Guide", HL_TEXTE_GUIDE())
  cas choix = "Fonctions des scripts"
    HL_AIDE_FENETRE("Fonctions des scripts", HL_TEXTE_FONCTIONS())
  cas choix = "Raccourcis clavier"
    ui.alerte(HL_TEXTE_RACCOURCIS(), "information", "Raccourcis clavier")
  cas choix = "À propos"
    ui.alerte("HyperLexis " + hl.version + NL() + "Atelier de piles de cartes pour Lexis+ (wdlexis+)" + NL() + NL() + ;
              "Dans l'esprit d'HyperCard et de LiveCode : palette d'outils, inspecteur," + NL() + ;
              "bascule Conception / Exécution, scripts en Lexis+." + NL() + NL() + ;
              "Les piles sont des projets wdlexis+ : wdlexisrt, atelier, wdlexisgen.", "information", "À propos")
  fincas
finprocedure

procedure HL_RECHERCHER
  locale r = ui.rechercher{texte = hlc.ed:motcourant()}
  si r <> nul et r.texte <> ""
    si non hlc.ed:chercher(r.texte, {casse = r.casse, motentier = r.motentier, arriere = r.arriere})
      HL_ETAT("Introuvable : " + r.texte)
    finsi
  finsi
finprocedure

fonction HL_CTRL(m)
  && Ctrl (0x00C0) ou Cmd (0x0C00)
  si m = nul
    retourner faux
  finsi
retourner (entier(m / 64) % 4 <> 0) ou (entier(m / 1024) % 4 <> 0)
finfonction

fonction HL_DANS_TEXTE(ev)
  && Ctrl+flèche dans un champ de saisie : déplacement par mot, pas de changement de carte
  essayer
    retourner ev.id <> nul et ev.id.famille = "saisie"
  capturer e
  finessayer
retourner faux
finfonction

procedure HL_TOUCHE(ev)
  && raccourcis de l'atelier (l'éditeur de script garde les siens)
  si ev.id = hlc.ed ou non HL_CTRL(ev.modificateurs)
    retourner
  finsi
  locale t = ev.touche
  faire cas
  cas t = 101                       && Ctrl+E
    HL_BASCULER_MODE()
  cas t = 115                       && Ctrl+S
    HL_ENREGISTRER(vrai)
  cas t = 109                       && Ctrl+M
    HL_ONGLET("messages")
    hlc.saisiemsg:focus()
  cas t = 110                       && Ctrl+N
    HL_NOUVELLE_CARTE_MEME()
  cas t = 100                       && Ctrl+D
    HL_DUPLIQUER_OBJET()
  cas t = 1073741903 et non HL_DANS_TEXTE(ev)     && →
    HL_ALLER("suivante")
  cas t = 1073741904 et non HL_DANS_TEXTE(ev)     && ←
    HL_ALLER("precedente")
  cas t = 1073741898                && Début
    HL_ALLER("premiere")
  cas t = 1073741901                && Fin
    HL_ALLER("derniere")
  fincas
finprocedure

&&
&& Aide
&&

procedure HL_AIDE_FENETRE(titre, md)
  locale f = ui.fenetre{titre = "HyperLexis - " + titre, largeur = 760, hauteur = 640, sombre = hl.reglages.sombre}
  locale m = f:ajouter(ui.markdown(md))
  m.poids = 1
finprocedure

fonction HL_TEXTE_RACCOURCIS()
  locale l = {"Ctrl+E      bascule Conception / Exécution", ;
              "Ctrl+S      enregistre la pile", ;
              "Ctrl+N      nouvelle carte sur le même modèle", ;
              "Ctrl+D      duplique l'objet sélectionné", ;
              "Ctrl+M      boîte de messages", ;
              "Ctrl+← / →  carte précédente / suivante ; Ctrl+Début / Fin : première / dernière", ;
              "Suppr       supprime l'objet sélectionné (canevas)", ;
              "Échap       sélectionne le conteneur parent (canevas)", ;
              "Flèches     déplacent l'objet de 1 pixel (Maj : 10)", ;
              "", "Dans le script : Ctrl+S enregistre, Ctrl+R bascule le mode, Ctrl+Espace complète."}
retourner joindre(l, NL())
finfonction

fonction HL_TEXTE_GUIDE()
  locale l = {}
  inserer(l, "# HyperLexis en cinq minutes")
  inserer(l, "")
  inserer(l, "Une **pile** est une suite de **cartes**. Chaque carte utilise un **modèle** : son dessin " + ;
             "(boutons, champs, images…) et son **script** (procédures Lexis+ des événements). Plusieurs cartes " + ;
             "peuvent partager un modèle, comme les fiches d'un carnet : même dessin, contenu propre.")
  inserer(l, "")
  inserer(l, "## Concevoir")
  inserer(l, "")
  inserer(l, "1. Mode **✎ Conception** : glissez un outil de la **palette** (onglet *Outils*) sur la carte.")
  inserer(l, "2. Cliquez un objet pour le sélectionner ; les poignées le redimensionnent, les repères magenta l'alignent.")
  inserer(l, "3. L'**inspecteur**, à droite, modifie ses propriétés (nom, libellé, position, couleurs…) " + ;
             "et le **contenu** du champ sur la carte courante.")
  inserer(l, "4. Section *Événements* : **+ nouveau script…** crée la procédure (par exemple " + ;
             "`ACCUEIL_BTN1_CLIC`) dans le script du modèle (page Script) et l'associe à l'événement.")
  inserer(l, "")
  inserer(l, "## Exécuter")
  inserer(l, "")
  inserer(l, "Mode **▶ Exécution** (Ctrl+E) : la pile fonctionne dans la même fenêtre. Les champs saisis sont " + ;
             "gardés avec la carte. **✎ Conception** revient au dessin, sur la carte affichée.")
  inserer(l, "")
  inserer(l, "La **boîte de messages** (onglet *Messages*, Ctrl+M) exécute une commande ou une expression : " + ;
             "`ALLER_CARTE(" + Q() + "suivante" + Q() + ")`, `NOMBRE_CARTES()`, `CHAMP(" + Q() + "nom" + Q() + ")`, " + ;
             "`? 6 * 7`.")
  inserer(l, "")
  inserer(l, "## Exemple de script")
  inserer(l, "")
  inserer(l, "```")
  inserer(l, "procedure FICHE_SUIVANTE_CLIC(ev)")
  inserer(l, "  CARTE_SUIVANTE()")
  inserer(l, "finprocedure")
  inserer(l, "")
  inserer(l, "procedure FICHE_OUVERTURE(ev)")
  inserer(l, "  formfiche.rang.libelle = " + Q() + "Fiche " + Q() + " + NUMERO_CARTE() + " + Q() + " / " + Q() + ;
             " + NOMBRE_CARTES()")
  inserer(l, "finprocedure")
  inserer(l, "```")
  inserer(l, "")
  inserer(l, "Les contrôles de la carte affichée sont dans la variable `form<modele>` (`formfiche.nom.valeur`).")
  inserer(l, "")
  inserer(l, "## Enregistrer, lancer, générer")
  inserer(l, "")
  inserer(l, "- La pile est enregistrée à chaque modification du dessin, et par Ctrl+S.")
  inserer(l, "- Le dossier de la pile est un **projet wdlexis+** : `wdlexisrt principal.prg` l'exécute, " + ;
             "l'atelier wdlexis+ l'ouvre (les modèles `form_<modele>.prg` s'ouvrent dans son concepteur), " + ;
             "`wdlexisgen` en fait une application autonome.")
  inserer(l, "- **▷ Pile autonome** la lance comme le runtime, dans sa propre fenêtre ; " + ;
             "**Générer…** produit l'application (dossier `distribution/`).")
retourner joindre(l, NL())
finfonction

fonction HL_TEXTE_FONCTIONS()
  locale l = {}
  inserer(l, "# Fonctions des scripts (pile_moteur.prg)")
  inserer(l, "")
  inserer(l, "| Appel | Rôle |")
  inserer(l, "| --- | --- |")
  inserer(l, "| `ALLER_CARTE(cible)` | nom, numéro, `" + Q() + "suivante" + Q() + "`, `" + Q() + "precedente" + Q() + ;
             "`, `" + Q() + "premiere" + Q() + "`, `" + Q() + "derniere" + Q() + "`, `" + Q() + "retour" + Q() + "` |")
  inserer(l, "| `CARTE_SUIVANTE()`, `CARTE_PRECEDENTE()`, `PREMIERE_CARTE()`, `DERNIERE_CARTE()`, `CARTE_RETOUR()` | navigation |")
  inserer(l, "| `CARTE_COURANTE()`, `NUMERO_CARTE()`, `NOMBRE_CARTES()`, `LISTE_CARTES()`, `MODELE_CARTE([carte])` | où l'on est |")
  inserer(l, "| `NOUVELLE_CARTE([modele], [nom])` | nouvelle carte après la carte courante (même modèle par défaut) |")
  inserer(l, "| `SUPPRIMER_CARTE([nom])` | supprime une carte et ses données |")
  inserer(l, "| `CONTROLE(nom)` | contrôle de la carte affichée (aussi `form<modele>.<nom>`) |")
  inserer(l, "| `CHAMP(nom, [carte])` / `FIXER_CHAMP(nom, valeur, [carte])` | contenu d'un champ, d'une carte quelconque |")
  inserer(l, "| `DONNEE(cle)` / `FIXER_DONNEE(cle, valeur)` | données de la pile, gardées avec elle |")
  inserer(l, "| `TROUVER(texte)` | va à la prochaine carte qui contient le texte |")
  inserer(l, "| `MESSAGE(texte)` | boîte de messages (atelier) ou console (application) |")
  inserer(l, "| `ENREGISTRER_PILE()`, `QUITTER_PILE()` | application autonome |")
  inserer(l, "")
  inserer(l, "## Procédures appelées si elles existent (script de la pile)")
  inserer(l, "")
  inserer(l, "`SUR_OUVERTURE_PILE()`, `SUR_FERMETURE_PILE()`, `SUR_OUVERTURE_CARTE(nom)`, `SUR_FERMETURE_CARTE(nom)`.")
  inserer(l, "")
  inserer(l, "Les événements `surouverture` / `surfermeture` de la carte (sélectionnez la carte, section " + ;
             "Événements) sont appelés quand elle s'affiche et quand on la quitte.")
  inserer(l, "")
  inserer(l, "Tout le langage Lexis+ et ses paquets sont disponibles : `ui.alerte`, `ui.demander`, `sql`, " + ;
             "`fichier`, `http`, `rapport`…")
retourner joindre(l, NL())
finfonction

&&
&& Pile d'exemple : un carnet d'adresses (deux modèles, quatre cartes)
&&

fonction HL_N(genre, nom, props, evenements)
  locale n = HL_NOEUD(genre, nom, HL_NOEUD_PROPS(props), {})
  si evenements <> nul
    n["events"] = evenements
  finsi
retourner n
finfonction

procedure HL_NOUVEL_EXEMPLE
  locale p = ui.demander("Dossier de la pile d'exemple :", fichier.joindre(fichier.dossierperso(), "piles", "carnet"))
  si p = nul ou rogner(p) = ""
    retourner
  finsi
  p = fichier.absolu(rogner(p))
  si fichier.existe(fichier.joindre(p, "pile.prg"))
    si ui.confirmer("Une pile existe déjà dans ce dossier. L'ouvrir ?", "question")
      HL_CHARGER_PILE(p)
    finsi
    retourner
  finsi
  si hl.mode = "execution"
    HL_MODE_CONCEPTION()
  finsi
  si hl.dossier <> ""
    HL_ENREGISTRER(faux)
  finsi
  HL_CREER_EXEMPLE(p)
  hl.dossier = ""
  HL_CHARGER_PILE(p)
finprocedure

procedure HL_CREER_EXEMPLE(p)
  fichier.creerdossier(p)
  hl.dossier = p
  hl.def = {titre = "Carnet d'adresses", largeur = 640, hauteur = 440, couleur = "#FFFDF5", ;
            navigation = vrai, persistance = vrai, version = 1, ;
            cartes = {{nom = "accueil", modele = "accueil"}, {nom = "fiche_1", modele = "fiche"}, ;
                      {nom = "fiche_2", modele = "fiche"}, {nom = "fiche_3", modele = "fiche"}}}
  && modèle « accueil »
  locale aide = "## Mode d'emploi" + NL() + NL() + "- **Parcourir** : les fiches sont des cartes du modèle *fiche*." + NL() + ;
                "- **Nouvelle fiche** : `NOUVELLE_CARTE(" + Q() + "fiche" + Q() + ")`." + NL() + ;
                "- **Trouver** : `TROUVER(texte)` cherche dans toutes les cartes." + NL() + NL() + ;
                "En mode **Conception**, sélectionnez un bouton puis *✎ Modifier le script*."
  locale ea = {}
  inserer(ea, HL_N("etiquette", "titre", {"libelle", "Carnet d'adresses", "x", 24, "y", 18, "largeurfixe", 400, ;
                                          "hauteurfixe", 36, "couleur", "#1E3A8A"}))
  inserer(ea, HL_N("etiquette", "soustitre", {"libelle", "Une pile HyperLexis : chaque fiche est une carte.", ;
                                              "x", 24, "y", 54, "largeurfixe", 400, "hauteurfixe", 24, "couleur", "#64748B"}))
  inserer(ea, HL_N("markdown", "aide", {"texte", aide, "x", 24, "y", 96, "largeurfixe", 370, "hauteurfixe", 250}))
  inserer(ea, HL_N("bouton", "parcourir", {"libelle", "Parcourir les fiches ▶", "x", 420, "y", 96, ;
                                           "largeurfixe", 196, "hauteurfixe", 34}, {{"surclic", "ACCUEIL_PARCOURIR_CLIC"}}))
  inserer(ea, HL_N("bouton", "nouvelle", {"libelle", "+ Nouvelle fiche", "x", 420, "y", 140, ;
                                          "largeurfixe", 196, "hauteurfixe", 34}, {{"surclic", "ACCUEIL_NOUVELLE_CLIC"}}))
  inserer(ea, HL_N("saisie", "recherche", {"indication", "Texte à trouver…", "x", 420, "y", 196, ;
                                           "largeurfixe", 196, "hauteurfixe", 30}))
  inserer(ea, HL_N("bouton", "trouver", {"libelle", "Trouver", "x", 420, "y", 234, "largeurfixe", 196, ;
                                         "hauteurfixe", 32}, {{"surclic", "ACCUEIL_TROUVER_CLIC"}}))
  inserer(ea, HL_N("etiquette", "resultat", {"libelle", "", "x", 420, "y", 272, "largeurfixe", 196, "hauteurfixe", 24, ;
                                             "couleur", "#B45309"}))
  inserer(ea, HL_N("etiquette", "compte", {"libelle", "", "x", 24, "y", 360, "largeurfixe", 370, "hauteurfixe", 24}))
  locale da = HL_N("fenetre", "accueil", {"titre", "Accueil", "largeur", 640, "hauteur", 440, "disposition", "absolue"}, ;
                   {{"surouverture", "ACCUEIL_OUVERTURE"}})
  da["children"] = ea
  HL_ECRIRE_DESSIN("accueil", da)
  locale sa = {}
  inserer(sa, "&& Script du modèle de carte « accueil » (HyperLexis) : procédures des événements.")
  inserer(sa, "&& Les contrôles de la carte affichée sont dans formaccueil (formaccueil.recherche.valeur…).")
  inserer(sa, "")
  inserer(sa, HL_MARQUE_DEBUT("accueil"))
  inserer(sa, "&& FORMACCUEIL_OUVRIR() ouvre le formulaire ; ses contrôles sont dans formaccueil (formaccueil.fenetre…).")
  inserer(sa, "")
  inserer(sa, "procedure ACCUEIL_OUVERTURE(ev)")
  inserer(sa, "  && surouverture de la carte : nombre de fiches")
  inserer(sa, "  locale n = 0")
  inserer(sa, "  pour chaque c dans LISTE_CARTES()")
  inserer(sa, "    si MODELE_CARTE(c) = " + Q() + "fiche" + Q())
  inserer(sa, "      n += 1")
  inserer(sa, "    finsi")
  inserer(sa, "  suivant")
  inserer(sa, "  formaccueil.compte.libelle = n + " + Q() + " fiche(s) dans le carnet" + Q())
  inserer(sa, "finprocedure")
  inserer(sa, "")
  inserer(sa, "procedure ACCUEIL_PARCOURIR_CLIC(ev)")
  inserer(sa, "  && surclic de parcourir : la première fiche")
  inserer(sa, "  pour chaque c dans LISTE_CARTES()")
  inserer(sa, "    si MODELE_CARTE(c) = " + Q() + "fiche" + Q())
  inserer(sa, "      ALLER_CARTE(c)")
  inserer(sa, "      retourner")
  inserer(sa, "    finsi")
  inserer(sa, "  suivant")
  inserer(sa, "  formaccueil.resultat.libelle = " + Q() + "Aucune fiche : créez-en une." + Q())
  inserer(sa, "finprocedure")
  inserer(sa, "")
  inserer(sa, "procedure ACCUEIL_NOUVELLE_CLIC(ev)")
  inserer(sa, "  && surclic de nouvelle : une carte de plus sur le modèle « fiche »")
  inserer(sa, "  NOUVELLE_CARTE(" + Q() + "fiche" + Q() + ")")
  inserer(sa, "  CONTROLE(" + Q() + "nom" + Q() + "):focus()")
  inserer(sa, "finprocedure")
  inserer(sa, "")
  inserer(sa, "procedure ACCUEIL_TROUVER_CLIC(ev)")
  inserer(sa, "  && surclic de trouver : comme « find » d'HyperCard")
  inserer(sa, "  locale t = rogner(formaccueil.recherche.valeur)")
  inserer(sa, "  si t = " + Q() + Q())
  inserer(sa, "    formaccueil.resultat.libelle = " + Q() + "Tapez un texte à trouver." + Q())
  inserer(sa, "  sinonsi non TROUVER(t)")
  inserer(sa, "    formaccueil.resultat.libelle = " + Q() + "Introuvable : " + Q() + " + t")
  inserer(sa, "  finsi")
  inserer(sa, "finprocedure")
  inserer(sa, "")
  inserer(sa, HL_MARQUE_FIN("accueil"))
  fichier.ecrire(HL_SCRIPT("accueil"), joindre(sa, NL()) + NL())
  && modèle « fiche »
  locale ef = {}
  inserer(ef, HL_N("etiquette", "titre", {"libelle", "Fiche", "x", 24, "y", 16, "largeurfixe", 420, "hauteurfixe", 34, ;
                                          "couleur", "#1E3A8A"}))
  inserer(ef, HL_N("etiquette", "rang", {"libelle", "", "alignement", "droite", "x", 456, "y", 20, "largeurfixe", 160, ;
                                         "hauteurfixe", 26, "couleur", "#64748B"}))
  locale y = 66
  pour chaque ch dans {{"nom", "Nom"}, {"prenom", "Prénom"}, {"telephone", "Téléphone"}, {"courriel", "Courriel"}}
    inserer(ef, HL_N("etiquette", "lbl" + ch[1], {"libelle", ch[2], "x", 24, "y", y + 4, "largeurfixe", 100, "hauteurfixe", 26}))
    locale evs = nul
    si ch[1] = "nom" ou ch[1] = "prenom"
      evs = {{"surchangement", "FICHE_NOM_CHANGEMENT"}}
    finsi
    inserer(ef, HL_N("saisie", ch[1], {"x", 130, "y", y, "largeurfixe", 300, "hauteurfixe", 30}, evs))
    y += 40
  suivant
  inserer(ef, HL_N("etiquette", "lblville", {"libelle", "Ville", "x", 24, "y", y + 4, "largeurfixe", 100, "hauteurfixe", 26}))
  inserer(ef, HL_N("combo", "ville", {"elements", "Brest;Lyon;Nantes;Paris;Rennes;Autre", "x", 130, "y", y, ;
                                      "largeurfixe", 200, "hauteurfixe", 30}))
  y += 40
  inserer(ef, HL_N("cases", "favori", {"options", "Favori ★", "x", 456, "y", 66, "largeurfixe", 160, "hauteurfixe", 30}))
  inserer(ef, HL_N("etiquette", "lblnotes", {"libelle", "Notes", "x", 24, "y", y + 4, "largeurfixe", 100, "hauteurfixe", 26}))
  inserer(ef, HL_N("saisie", "notes", {"multiligne", "true", "x", 130, "y", y, "largeurfixe", 486, "hauteurfixe", 80}))
  inserer(ef, HL_N("bouton", "accueil", {"libelle", "⌂ Accueil", "x", 24, "y", 384, "largeurfixe", 100, "hauteurfixe", 34}, ;
                   {{"surclic", "FICHE_ACCUEIL_CLIC"}}))
  inserer(ef, HL_N("bouton", "precedente", {"libelle", "◀", "x", 130, "y", 384, "largeurfixe", 46, "hauteurfixe", 34}, ;
                   {{"surclic", "FICHE_PRECEDENTE_CLIC"}}))
  inserer(ef, HL_N("bouton", "suivante", {"libelle", "▶", "x", 182, "y", 384, "largeurfixe", 46, "hauteurfixe", 34}, ;
                   {{"surclic", "FICHE_SUIVANTE_CLIC"}}))
  inserer(ef, HL_N("bouton", "nouvelle", {"libelle", "+ Fiche", "x", 380, "y", 384, "largeurfixe", 110, "hauteurfixe", 34}, ;
                   {{"surclic", "FICHE_NOUVELLE_CLIC"}}))
  inserer(ef, HL_N("bouton", "supprimer", {"libelle", "Supprimer", "x", 500, "y", 384, "largeurfixe", 116, "hauteurfixe", 34}, ;
                   {{"surclic", "FICHE_SUPPRIMER_CLIC"}}))
  locale df = HL_N("fenetre", "fiche", {"titre", "Fiche", "largeur", 640, "hauteur", 440, "disposition", "absolue"}, ;
                   {{"surouverture", "FICHE_OUVERTURE"}})
  df["children"] = ef
  HL_ECRIRE_DESSIN("fiche", df)
  locale sf = {}
  inserer(sf, "&& Script du modèle de carte « fiche » (HyperLexis) : procédures des événements.")
  inserer(sf, "&& Toutes les fiches partagent ce modèle ; chacune garde le contenu de ses champs.")
  inserer(sf, "&& Les contrôles de la fiche affichée sont dans formfiche (formfiche.nom.valeur…).")
  inserer(sf, "")
  inserer(sf, HL_MARQUE_DEBUT("fiche"))
  inserer(sf, "&& FORMFICHE_OUVRIR() ouvre le formulaire ; ses contrôles sont dans formfiche (formfiche.fenetre…).")
  inserer(sf, "")
  inserer(sf, "procedure FICHE_OUVERTURE(ev)")
  inserer(sf, "  && surouverture de la carte : rang et titre de la fiche")
  inserer(sf, "  formfiche.rang.libelle = " + Q() + "Carte " + Q() + " + NUMERO_CARTE() + " + Q() + " / " + Q() + " + NOMBRE_CARTES()")
  inserer(sf, "  FICHE_NOM_CHANGEMENT(ev)")
  inserer(sf, "finprocedure")
  inserer(sf, "")
  inserer(sf, "procedure FICHE_NOM_CHANGEMENT(ev)")
  inserer(sf, "  && surchangement de nom et de prenom : le titre suit")
  inserer(sf, "  locale t = rogner(formfiche.prenom.valeur + " + Q() + " " + Q() + " + majuscule(formfiche.nom.valeur))")
  inserer(sf, "  formfiche.titre.libelle = sisinon(t = " + Q() + Q() + ", " + Q() + "Nouvelle fiche" + Q() + ", t)")
  inserer(sf, "finprocedure")
  inserer(sf, "")
  inserer(sf, "procedure FICHE_ACCUEIL_CLIC(ev)")
  inserer(sf, "  ALLER_CARTE(" + Q() + "accueil" + Q() + ")")
  inserer(sf, "finprocedure")
  inserer(sf, "")
  inserer(sf, "procedure FICHE_PRECEDENTE_CLIC(ev)")
  inserer(sf, "  CARTE_PRECEDENTE()")
  inserer(sf, "finprocedure")
  inserer(sf, "")
  inserer(sf, "procedure FICHE_SUIVANTE_CLIC(ev)")
  inserer(sf, "  CARTE_SUIVANTE()")
  inserer(sf, "finprocedure")
  inserer(sf, "")
  inserer(sf, "procedure FICHE_NOUVELLE_CLIC(ev)")
  inserer(sf, "  NOUVELLE_CARTE()")
  inserer(sf, "  formfiche.nom:focus()")
  inserer(sf, "finprocedure")
  inserer(sf, "")
  inserer(sf, "procedure FICHE_SUPPRIMER_CLIC(ev)")
  inserer(sf, "  si interface.confirmer(" + Q() + "Supprimer cette fiche ?" + Q() + ", " + Q() + "question" + Q() + ")")
  inserer(sf, "    SUPPRIMER_CARTE()")
  inserer(sf, "  finsi")
  inserer(sf, "finprocedure")
  inserer(sf, "")
  inserer(sf, HL_MARQUE_FIN("fiche"))
  fichier.ecrire(HL_SCRIPT("fiche"), joindre(sf, NL()) + NL())
  && script de la pile
  fichier.ecrire(HL_P("script_pile.prg"), remplacertexte(HL_TEXTE_SCRIPT_PILE(), ;
                 "  && MESSAGE(" + Q() + "Bienvenue" + Q() + ")", ;
                 "  MESSAGE(" + Q() + "Carnet d'adresses : " + Q() + " + NOMBRE_CARTES() + " + Q() + " cartes" + Q() + ")"))
  && données des fiches (ville : rang dans la liste ; favori : case cochée = 1)
  hl.donnees = {FICHE_1 = {NOM = "Lovelace", PRENOM = "Ada", TELEPHONE = "01 23 45 67 89", COURRIEL = "ada@exemple.fr", ;
                           VILLE = "4", FAVORI = "1", NOTES = "Première programmeuse : les notes sur la machine analytique."}, ;
                FICHE_2 = {NOM = "Turing", PRENOM = "Alan", TELEPHONE = "02 98 76 54 32", COURRIEL = "alan@exemple.fr", ;
                           VILLE = "1", NOTES = "Machine de Turing, test de Turing."}, ;
                FICHE_3 = {NOM = "Hopper", PRENOM = "Grace", TELEPHONE = "04 72 00 00 00", COURRIEL = "grace@exemple.fr", ;
                           VILLE = "2", FAVORI = "1", NOTES = "Compilateurs, COBOL, et le premier « bug »."}, ;
                _PILE = {}}
  HL_ECRIRE_FICHIERS_PILE(p)
finprocedure
