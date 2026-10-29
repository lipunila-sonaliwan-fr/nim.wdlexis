&& Formulaire « fiche » - généré par le concepteur de wdlexis+.
&& Régénéré à chaque modification dans le concepteur : modifiez le dessin là-bas, pas ce fichier.
&& FORMFICHE_OUVRIR() ouvre la fenêtre et renvoie ses contrôles, aussi rangés dans la
&& variable globale formfiche (formfiche.fenetre, formfiche.titre…).

fonction FORMFICHE_OUVRIR()
  globale formfiche
  locale f = {}
  f.fenetre = interface.fenetre{titre = "Fiche", largeur = 640, hauteur = 440, disposition = "absolue"}
  f.titre = f.fenetre:ajouter(interface.etiquette("Fiche"))
  f.titre.largeurfixe = 420
  f.titre.hauteurfixe = 34
  f.titre.x = 24
  f.titre.y = 16
  f.titre.couleur = "#1E3A8A"
  f.rang = f.fenetre:ajouter(interface.etiquette("", "droite"))
  f.rang.largeurfixe = 160
  f.rang.hauteurfixe = 26
  f.rang.x = 456
  f.rang.y = 20
  f.rang.couleur = "#64748B"
  f.lblnom = f.fenetre:ajouter(interface.etiquette("Nom"))
  f.lblnom.largeurfixe = 100
  f.lblnom.hauteurfixe = 26
  f.lblnom.x = 24
  f.lblnom.y = 70
  f.nom = f.fenetre:ajouter(interface.saisie())
  f.nom.largeurfixe = 300
  f.nom.hauteurfixe = 30
  f.nom.x = 130
  f.nom.y = 66
  f.lblprenom = f.fenetre:ajouter(interface.etiquette("Prénom"))
  f.lblprenom.largeurfixe = 100
  f.lblprenom.hauteurfixe = 26
  f.lblprenom.x = 24
  f.lblprenom.y = 110
  f.prenom = f.fenetre:ajouter(interface.saisie())
  f.prenom.largeurfixe = 300
  f.prenom.hauteurfixe = 30
  f.prenom.x = 130
  f.prenom.y = 106
  f.lbltelephone = f.fenetre:ajouter(interface.etiquette("Téléphone"))
  f.lbltelephone.largeurfixe = 100
  f.lbltelephone.hauteurfixe = 26
  f.lbltelephone.x = 24
  f.lbltelephone.y = 150
  f.telephone = f.fenetre:ajouter(interface.saisie())
  f.telephone.largeurfixe = 300
  f.telephone.hauteurfixe = 30
  f.telephone.x = 130
  f.telephone.y = 146
  f.lblcourriel = f.fenetre:ajouter(interface.etiquette("Courriel"))
  f.lblcourriel.largeurfixe = 100
  f.lblcourriel.hauteurfixe = 26
  f.lblcourriel.x = 24
  f.lblcourriel.y = 190
  f.courriel = f.fenetre:ajouter(interface.saisie())
  f.courriel.largeurfixe = 300
  f.courriel.hauteurfixe = 30
  f.courriel.x = 130
  f.courriel.y = 186
  f.lblville = f.fenetre:ajouter(interface.etiquette("Ville"))
  f.lblville.largeurfixe = 100
  f.lblville.hauteurfixe = 26
  f.lblville.x = 24
  f.lblville.y = 230
  f.ville = f.fenetre:ajouter(interface.combo("Brest", "Lyon", "Nantes", "Paris", "Rennes", "Autre"))
  f.ville.largeurfixe = 200
  f.ville.hauteurfixe = 30
  f.ville.x = 130
  f.ville.y = 226
  f.favori = f.fenetre:ajouter(interface.cases("Favori ★"))
  f.favori.largeurfixe = 160
  f.favori.hauteurfixe = 30
  f.favori.x = 456
  f.favori.y = 66
  f.lblnotes = f.fenetre:ajouter(interface.etiquette("Notes"))
  f.lblnotes.largeurfixe = 100
  f.lblnotes.hauteurfixe = 26
  f.lblnotes.x = 24
  f.lblnotes.y = 270
  f.notes = f.fenetre:ajouter(interface.saisie{multiligne = vrai})
  f.notes.largeurfixe = 486
  f.notes.hauteurfixe = 80
  f.notes.x = 130
  f.notes.y = 266
  f.accueil = f.fenetre:ajouter(interface.bouton("⌂ Accueil"))
  f.accueil.largeurfixe = 100
  f.accueil.hauteurfixe = 34
  f.accueil.x = 24
  f.accueil.y = 384
  f.precedente = f.fenetre:ajouter(interface.bouton("◀"))
  f.precedente.largeurfixe = 46
  f.precedente.hauteurfixe = 34
  f.precedente.x = 130
  f.precedente.y = 384
  f.suivante = f.fenetre:ajouter(interface.bouton("▶"))
  f.suivante.largeurfixe = 46
  f.suivante.hauteurfixe = 34
  f.suivante.x = 182
  f.suivante.y = 384
  f.nouvelle = f.fenetre:ajouter(interface.bouton("+ Fiche"))
  f.nouvelle.largeurfixe = 110
  f.nouvelle.hauteurfixe = 34
  f.nouvelle.x = 380
  f.nouvelle.y = 384
  f.supprimer = f.fenetre:ajouter(interface.bouton("Supprimer"))
  f.supprimer.largeurfixe = 116
  f.supprimer.hauteurfixe = 34
  f.supprimer.x = 500
  f.supprimer.y = 384
  && événements (procédures du code : script_fiche.prg)
  f.fenetre.surouverture = @FICHE_OUVERTURE
  f.nom.surchangement = @FICHE_NOM_CHANGEMENT
  f.prenom.surchangement = @FICHE_NOM_CHANGEMENT
  f.accueil.surclic = @FICHE_ACCUEIL_CLIC
  f.precedente.surclic = @FICHE_PRECEDENTE_CLIC
  f.suivante.surclic = @FICHE_SUIVANTE_CLIC
  f.nouvelle.surclic = @FICHE_NOUVELLE_CLIC
  f.supprimer.surclic = @FICHE_SUPPRIMER_CLIC
  formfiche = f
retourner f
finfonction

&& Dessin du formulaire (relu par le concepteur) : ne pas modifier.
&&§ {
&&§   "kind": "fenetre",
&&§   "name": "fiche",
&&§   "props": {
&&§     "titre": "Fiche",
&&§     "largeur": "640",
&&§     "hauteur": "440",
&&§     "disposition": "absolue"
&&§   },
&&§   "events": [
&&§     [
&&§       "surouverture",
&&§       "FICHE_OUVERTURE"
&&§     ]
&&§   ],
&&§   "children": [
&&§     {
&&§       "kind": "etiquette",
&&§       "name": "titre",
&&§       "props": {
&&§         "libelle": "Fiche",
&&§         "x": "24",
&&§         "y": "16",
&&§         "largeurfixe": "420",
&&§         "hauteurfixe": "34",
&&§         "couleur": "#1E3A8A"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "etiquette",
&&§       "name": "rang",
&&§       "props": {
&&§         "libelle": "",
&&§         "alignement": "droite",
&&§         "x": "456",
&&§         "y": "20",
&&§         "largeurfixe": "160",
&&§         "hauteurfixe": "26",
&&§         "couleur": "#64748B"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "etiquette",
&&§       "name": "lblnom",
&&§       "props": {
&&§         "libelle": "Nom",
&&§         "x": "24",
&&§         "y": "70",
&&§         "largeurfixe": "100",
&&§         "hauteurfixe": "26"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "saisie",
&&§       "name": "nom",
&&§       "props": {
&&§         "x": "130",
&&§         "y": "66",
&&§         "largeurfixe": "300",
&&§         "hauteurfixe": "30"
&&§       },
&&§       "events": [
&&§         [
&&§           "surchangement",
&&§           "FICHE_NOM_CHANGEMENT"
&&§         ]
&&§       ],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "etiquette",
&&§       "name": "lblprenom",
&&§       "props": {
&&§         "libelle": "Prénom",
&&§         "x": "24",
&&§         "y": "110",
&&§         "largeurfixe": "100",
&&§         "hauteurfixe": "26"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "saisie",
&&§       "name": "prenom",
&&§       "props": {
&&§         "x": "130",
&&§         "y": "106",
&&§         "largeurfixe": "300",
&&§         "hauteurfixe": "30"
&&§       },
&&§       "events": [
&&§         [
&&§           "surchangement",
&&§           "FICHE_NOM_CHANGEMENT"
&&§         ]
&&§       ],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "etiquette",
&&§       "name": "lbltelephone",
&&§       "props": {
&&§         "libelle": "Téléphone",
&&§         "x": "24",
&&§         "y": "150",
&&§         "largeurfixe": "100",
&&§         "hauteurfixe": "26"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "saisie",
&&§       "name": "telephone",
&&§       "props": {
&&§         "x": "130",
&&§         "y": "146",
&&§         "largeurfixe": "300",
&&§         "hauteurfixe": "30"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "etiquette",
&&§       "name": "lblcourriel",
&&§       "props": {
&&§         "libelle": "Courriel",
&&§         "x": "24",
&&§         "y": "190",
&&§         "largeurfixe": "100",
&&§         "hauteurfixe": "26"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "saisie",
&&§       "name": "courriel",
&&§       "props": {
&&§         "x": "130",
&&§         "y": "186",
&&§         "largeurfixe": "300",
&&§         "hauteurfixe": "30"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "etiquette",
&&§       "name": "lblville",
&&§       "props": {
&&§         "libelle": "Ville",
&&§         "x": "24",
&&§         "y": "230",
&&§         "largeurfixe": "100",
&&§         "hauteurfixe": "26"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "combo",
&&§       "name": "ville",
&&§       "props": {
&&§         "elements": "Brest;Lyon;Nantes;Paris;Rennes;Autre",
&&§         "x": "130",
&&§         "y": "226",
&&§         "largeurfixe": "200",
&&§         "hauteurfixe": "30"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "cases",
&&§       "name": "favori",
&&§       "props": {
&&§         "options": "Favori ★",
&&§         "x": "456",
&&§         "y": "66",
&&§         "largeurfixe": "160",
&&§         "hauteurfixe": "30"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "etiquette",
&&§       "name": "lblnotes",
&&§       "props": {
&&§         "libelle": "Notes",
&&§         "x": "24",
&&§         "y": "270",
&&§         "largeurfixe": "100",
&&§         "hauteurfixe": "26"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "saisie",
&&§       "name": "notes",
&&§       "props": {
&&§         "multiligne": "true",
&&§         "x": "130",
&&§         "y": "266",
&&§         "largeurfixe": "486",
&&§         "hauteurfixe": "80"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "bouton",
&&§       "name": "accueil",
&&§       "props": {
&&§         "libelle": "⌂ Accueil",
&&§         "x": "24",
&&§         "y": "384",
&&§         "largeurfixe": "100",
&&§         "hauteurfixe": "34"
&&§       },
&&§       "events": [
&&§         [
&&§           "surclic",
&&§           "FICHE_ACCUEIL_CLIC"
&&§         ]
&&§       ],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "bouton",
&&§       "name": "precedente",
&&§       "props": {
&&§         "libelle": "◀",
&&§         "x": "130",
&&§         "y": "384",
&&§         "largeurfixe": "46",
&&§         "hauteurfixe": "34"
&&§       },
&&§       "events": [
&&§         [
&&§           "surclic",
&&§           "FICHE_PRECEDENTE_CLIC"
&&§         ]
&&§       ],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "bouton",
&&§       "name": "suivante",
&&§       "props": {
&&§         "libelle": "▶",
&&§         "x": "182",
&&§         "y": "384",
&&§         "largeurfixe": "46",
&&§         "hauteurfixe": "34"
&&§       },
&&§       "events": [
&&§         [
&&§           "surclic",
&&§           "FICHE_SUIVANTE_CLIC"
&&§         ]
&&§       ],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "bouton",
&&§       "name": "nouvelle",
&&§       "props": {
&&§         "libelle": "+ Fiche",
&&§         "x": "380",
&&§         "y": "384",
&&§         "largeurfixe": "110",
&&§         "hauteurfixe": "34"
&&§       },
&&§       "events": [
&&§         [
&&§           "surclic",
&&§           "FICHE_NOUVELLE_CLIC"
&&§         ]
&&§       ],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "bouton",
&&§       "name": "supprimer",
&&§       "props": {
&&§         "libelle": "Supprimer",
&&§         "x": "500",
&&§         "y": "384",
&&§         "largeurfixe": "116",
&&§         "hauteurfixe": "34"
&&§       },
&&§       "events": [
&&§         [
&&§           "surclic",
&&§           "FICHE_SUPPRIMER_CLIC"
&&§         ]
&&§       ],
&&§       "children": []
&&§     }
&&§   ],
&&§   "code": "script_fiche.prg"
&&§ }
