&& Formulaire « accueil » - généré par le concepteur de wdlexis+.
&& Régénéré à chaque modification dans le concepteur : modifiez le dessin là-bas, pas ce fichier.
&& FORMACCUEIL_OUVRIR() ouvre la fenêtre et renvoie ses contrôles, aussi rangés dans la
&& variable globale formaccueil (formaccueil.fenetre, formaccueil.titre…).

fonction FORMACCUEIL_OUVRIR()
  globale formaccueil
  locale f = {}
  f.fenetre = interface.fenetre{titre = "Accueil", largeur = 640, hauteur = 440, disposition = "absolue"}
  f.titre = f.fenetre:ajouter(interface.etiquette("Carnet d'adresses"))
  f.titre.largeurfixe = 400
  f.titre.hauteurfixe = 36
  f.titre.x = 24
  f.titre.y = 18
  f.titre.couleur = "#1E3A8A"
  f.soustitre = f.fenetre:ajouter(interface.etiquette("Une pile HyperLexis : chaque fiche est une carte."))
  f.soustitre.largeurfixe = 400
  f.soustitre.hauteurfixe = 24
  f.soustitre.x = 24
  f.soustitre.y = 54
  f.soustitre.couleur = "#64748B"
  f.aide = f.fenetre:ajouter(interface.markdown("## Mode d'emploi\n\n- **Parcourir** : les fiches sont des cartes du modèle *fiche*.\n- **Nouvelle fiche** : `NOUVELLE_CARTE(\"fiche\")`.\n- **Trouver** : `TROUVER(texte)` cherche dans toutes les cartes.\n\nEn mode **Conception**, sélectionnez un bouton puis *✎ Modifier le script*."))
  f.aide.largeurfixe = 370
  f.aide.hauteurfixe = 250
  f.aide.x = 24
  f.aide.y = 96
  f.parcourir = f.fenetre:ajouter(interface.bouton("Parcourir les fiches ▶"))
  f.parcourir.largeurfixe = 196
  f.parcourir.hauteurfixe = 34
  f.parcourir.x = 420
  f.parcourir.y = 96
  f.nouvelle = f.fenetre:ajouter(interface.bouton("+ Nouvelle fiche"))
  f.nouvelle.largeurfixe = 196
  f.nouvelle.hauteurfixe = 34
  f.nouvelle.x = 420
  f.nouvelle.y = 140
  f.recherche = f.fenetre:ajouter(interface.saisie{indication = "Texte à trouver…"})
  f.recherche.largeurfixe = 196
  f.recherche.hauteurfixe = 30
  f.recherche.x = 420
  f.recherche.y = 196
  f.trouver = f.fenetre:ajouter(interface.bouton("Trouver"))
  f.trouver.largeurfixe = 196
  f.trouver.hauteurfixe = 32
  f.trouver.x = 420
  f.trouver.y = 234
  f.resultat = f.fenetre:ajouter(interface.etiquette(""))
  f.resultat.largeurfixe = 196
  f.resultat.hauteurfixe = 24
  f.resultat.x = 420
  f.resultat.y = 272
  f.resultat.couleur = "#B45309"
  f.compte = f.fenetre:ajouter(interface.etiquette(""))
  f.compte.largeurfixe = 370
  f.compte.hauteurfixe = 24
  f.compte.x = 24
  f.compte.y = 360
  && événements (procédures du code : script_accueil.prg)
  f.fenetre.surouverture = @ACCUEIL_OUVERTURE
  f.parcourir.surclic = @ACCUEIL_PARCOURIR_CLIC
  f.nouvelle.surclic = @ACCUEIL_NOUVELLE_CLIC
  f.trouver.surclic = @ACCUEIL_TROUVER_CLIC
  formaccueil = f
retourner f
finfonction

&& Dessin du formulaire (relu par le concepteur) : ne pas modifier.
&&§ {
&&§   "kind": "fenetre",
&&§   "name": "accueil",
&&§   "props": {
&&§     "titre": "Accueil",
&&§     "largeur": "640",
&&§     "hauteur": "440",
&&§     "disposition": "absolue"
&&§   },
&&§   "events": [
&&§     [
&&§       "surouverture",
&&§       "ACCUEIL_OUVERTURE"
&&§     ]
&&§   ],
&&§   "children": [
&&§     {
&&§       "kind": "etiquette",
&&§       "name": "titre",
&&§       "props": {
&&§         "libelle": "Carnet d'adresses",
&&§         "x": "24",
&&§         "y": "18",
&&§         "largeurfixe": "400",
&&§         "hauteurfixe": "36",
&&§         "couleur": "#1E3A8A"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "etiquette",
&&§       "name": "soustitre",
&&§       "props": {
&&§         "libelle": "Une pile HyperLexis : chaque fiche est une carte.",
&&§         "x": "24",
&&§         "y": "54",
&&§         "largeurfixe": "400",
&&§         "hauteurfixe": "24",
&&§         "couleur": "#64748B"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "markdown",
&&§       "name": "aide",
&&§       "props": {
&&§         "texte": "## Mode d'emploi\n\n- **Parcourir** : les fiches sont des cartes du modèle *fiche*.\n- **Nouvelle fiche** : `NOUVELLE_CARTE(\"fiche\")`.\n- **Trouver** : `TROUVER(texte)` cherche dans toutes les cartes.\n\nEn mode **Conception**, sélectionnez un bouton puis *✎ Modifier le script*.",
&&§         "x": "24",
&&§         "y": "96",
&&§         "largeurfixe": "370",
&&§         "hauteurfixe": "250"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "bouton",
&&§       "name": "parcourir",
&&§       "props": {
&&§         "libelle": "Parcourir les fiches ▶",
&&§         "x": "420",
&&§         "y": "96",
&&§         "largeurfixe": "196",
&&§         "hauteurfixe": "34"
&&§       },
&&§       "events": [
&&§         [
&&§           "surclic",
&&§           "ACCUEIL_PARCOURIR_CLIC"
&&§         ]
&&§       ],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "bouton",
&&§       "name": "nouvelle",
&&§       "props": {
&&§         "libelle": "+ Nouvelle fiche",
&&§         "x": "420",
&&§         "y": "140",
&&§         "largeurfixe": "196",
&&§         "hauteurfixe": "34"
&&§       },
&&§       "events": [
&&§         [
&&§           "surclic",
&&§           "ACCUEIL_NOUVELLE_CLIC"
&&§         ]
&&§       ],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "saisie",
&&§       "name": "recherche",
&&§       "props": {
&&§         "indication": "Texte à trouver…",
&&§         "x": "420",
&&§         "y": "196",
&&§         "largeurfixe": "196",
&&§         "hauteurfixe": "30"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "bouton",
&&§       "name": "trouver",
&&§       "props": {
&&§         "libelle": "Trouver",
&&§         "x": "420",
&&§         "y": "234",
&&§         "largeurfixe": "196",
&&§         "hauteurfixe": "32"
&&§       },
&&§       "events": [
&&§         [
&&§           "surclic",
&&§           "ACCUEIL_TROUVER_CLIC"
&&§         ]
&&§       ],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "etiquette",
&&§       "name": "resultat",
&&§       "props": {
&&§         "libelle": "",
&&§         "x": "420",
&&§         "y": "272",
&&§         "largeurfixe": "196",
&&§         "hauteurfixe": "24",
&&§         "couleur": "#B45309"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "etiquette",
&&§       "name": "compte",
&&§       "props": {
&&§         "libelle": "",
&&§         "x": "24",
&&§         "y": "360",
&&§         "largeurfixe": "370",
&&§         "hauteurfixe": "24"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     }
&&§   ],
&&§   "code": "script_accueil.prg"
&&§ }
