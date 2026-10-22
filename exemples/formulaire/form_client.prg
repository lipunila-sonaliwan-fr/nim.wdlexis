&& Formulaire « client » — généré par le concepteur de wdlexis+.
&& Régénéré à chaque modification dans le concepteur : modifiez le dessin là-bas, pas ce fichier.
&& FORMCLIENT_OUVRIR() ouvre la fenêtre et renvoie ses contrôles, aussi rangés dans la
&& variable globale formclient (formclient.fenetre, formclient.titre…).

fonction FORMCLIENT_OUVRIR()
  globale formclient
  locale f = {}
  f.fenetre = interface.fenetre{titre = "Fiche client", largeur = 560, hauteur = 480, disposition = "bordure"}
  f.titre = f.fenetre:ajouter(interface.etiquette("Nouveau client"))
  f.titre.ancrage = "haut"
  f.titre.couleur = "#2563EB"
  f.identite = f.fenetre:ajouter(interface.cadre("Identité", "grille"))
  f.identite.ancrage = "centre"
  f.lblnom = f.identite:ajouter(interface.etiquette("Nom"))
  f.nom = f.identite:ajouter(interface.saisie{indication = "Dupont"})
  f.lblprenom = f.identite:ajouter(interface.etiquette("Prénom"))
  f.prenom = f.identite:ajouter(interface.saisie{indication = "Marie"})
  f.lblcourriel = f.identite:ajouter(interface.etiquette("Courriel"))
  f.courriel = f.identite:ajouter(interface.saisie{indication = "marie@exemple.fr"})
  f.lblville = f.identite:ajouter(interface.etiquette("Ville"))
  f.ville = f.identite:ajouter(interface.combo("Brest", "Nantes", "Paris", "Rennes"))
  f.lblcategorie = f.identite:ajouter(interface.etiquette("Catégorie"))
  f.categorie = f.identite:ajouter(interface.radio("Particulier", "Professionnel"))
  f.lblinfos = f.identite:ajouter(interface.etiquette("Informations"))
  f.lettre = f.identite:ajouter(interface.cases("Recevoir la lettre d'information"))
  f.boutons = f.fenetre:ajouter(interface.conteneur("horizontal"))
  f.boutons.ancrage = "bas"
  f.etat = f.boutons:ajouter(interface.etiquette(""))
  f.etat.poids = 1
  f.effacer = f.boutons:ajouter(interface.bouton("Effacer"))
  f.enregistrer = f.boutons:ajouter(interface.bouton("Enregistrer", {defaut = vrai}))
  f.enregistrer.etat = "grise"
  && événements (procédures du code : principal.prg)
  f.fenetre.surouverture = @CLIENT_OUVERTURE
  f.nom.surchangement = @CLIENT_SAISIE
  f.effacer.surclic = @CLIENT_EFFACER
  f.enregistrer.surclic = @CLIENT_ENREGISTRER
  formclient = f
retourner f
finfonction

&& Dessin du formulaire (relu par le concepteur) : ne pas modifier.
&&§ {
&&§   "kind": "fenetre",
&&§   "name": "client",
&&§   "props": {
&&§     "titre": "Fiche client",
&&§     "largeur": "560",
&&§     "hauteur": "480",
&&§     "disposition": "bordure"
&&§   },
&&§   "events": [
&&§     [
&&§       "surouverture",
&&§       "CLIENT_OUVERTURE"
&&§     ]
&&§   ],
&&§   "children": [
&&§     {
&&§       "kind": "etiquette",
&&§       "name": "titre",
&&§       "props": {
&&§         "libelle": "Nouveau client",
&&§         "ancrage": "haut",
&&§         "couleur": "#2563EB"
&&§       },
&&§       "events": [],
&&§       "children": []
&&§     },
&&§     {
&&§       "kind": "cadre",
&&§       "name": "identite",
&&§       "props": {
&&§         "titre": "Identité",
&&§         "disposition": "grille",
&&§         "ancrage": "centre"
&&§       },
&&§       "events": [],
&&§       "children": [
&&§         {
&&§           "kind": "etiquette",
&&§           "name": "lblnom",
&&§           "props": {
&&§             "libelle": "Nom"
&&§           },
&&§           "events": [],
&&§           "children": []
&&§         },
&&§         {
&&§           "kind": "saisie",
&&§           "name": "nom",
&&§           "props": {
&&§             "indication": "Dupont"
&&§           },
&&§           "events": [
&&§             [
&&§               "surchangement",
&&§               "CLIENT_SAISIE"
&&§             ]
&&§           ],
&&§           "children": []
&&§         },
&&§         {
&&§           "kind": "etiquette",
&&§           "name": "lblprenom",
&&§           "props": {
&&§             "libelle": "Prénom"
&&§           },
&&§           "events": [],
&&§           "children": []
&&§         },
&&§         {
&&§           "kind": "saisie",
&&§           "name": "prenom",
&&§           "props": {
&&§             "indication": "Marie"
&&§           },
&&§           "events": [],
&&§           "children": []
&&§         },
&&§         {
&&§           "kind": "etiquette",
&&§           "name": "lblcourriel",
&&§           "props": {
&&§             "libelle": "Courriel"
&&§           },
&&§           "events": [],
&&§           "children": []
&&§         },
&&§         {
&&§           "kind": "saisie",
&&§           "name": "courriel",
&&§           "props": {
&&§             "indication": "marie@exemple.fr"
&&§           },
&&§           "events": [],
&&§           "children": []
&&§         },
&&§         {
&&§           "kind": "etiquette",
&&§           "name": "lblville",
&&§           "props": {
&&§             "libelle": "Ville"
&&§           },
&&§           "events": [],
&&§           "children": []
&&§         },
&&§         {
&&§           "kind": "combo",
&&§           "name": "ville",
&&§           "props": {
&&§             "elements": "Brest;Nantes;Paris;Rennes"
&&§           },
&&§           "events": [],
&&§           "children": []
&&§         },
&&§         {
&&§           "kind": "etiquette",
&&§           "name": "lblcategorie",
&&§           "props": {
&&§             "libelle": "Catégorie"
&&§           },
&&§           "events": [],
&&§           "children": []
&&§         },
&&§         {
&&§           "kind": "radio",
&&§           "name": "categorie",
&&§           "props": {
&&§             "options": "Particulier;Professionnel"
&&§           },
&&§           "events": [],
&&§           "children": []
&&§         },
&&§         {
&&§           "kind": "etiquette",
&&§           "name": "lblinfos",
&&§           "props": {
&&§             "libelle": "Informations"
&&§           },
&&§           "events": [],
&&§           "children": []
&&§         },
&&§         {
&&§           "kind": "cases",
&&§           "name": "lettre",
&&§           "props": {
&&§             "options": "Recevoir la lettre d'information"
&&§           },
&&§           "events": [],
&&§           "children": []
&&§         }
&&§       ]
&&§     },
&&§     {
&&§       "kind": "conteneur",
&&§       "name": "boutons",
&&§       "props": {
&&§         "ancrage": "bas",
&&§         "disposition": "horizontal"
&&§       },
&&§       "events": [],
&&§       "children": [
&&§         {
&&§           "kind": "etiquette",
&&§           "name": "etat",
&&§           "props": {
&&§             "libelle": "",
&&§             "poids": "1"
&&§           },
&&§           "events": [],
&&§           "children": []
&&§         },
&&§         {
&&§           "kind": "bouton",
&&§           "name": "effacer",
&&§           "props": {
&&§             "libelle": "Effacer"
&&§           },
&&§           "events": [
&&§             [
&&§               "surclic",
&&§               "CLIENT_EFFACER"
&&§             ]
&&§           ],
&&§           "children": []
&&§         },
&&§         {
&&§           "kind": "bouton",
&&§           "name": "enregistrer",
&&§           "props": {
&&§             "libelle": "Enregistrer",
&&§             "defaut": "true",
&&§             "etat": "grise"
&&§           },
&&§           "events": [
&&§             [
&&§               "surclic",
&&§               "CLIENT_ENREGISTRER"
&&§             ]
&&§           ],
&&§           "children": []
&&§         }
&&§       ]
&&§     }
&&§   ],
&&§   "code": "principal.prg"
&&§ }
