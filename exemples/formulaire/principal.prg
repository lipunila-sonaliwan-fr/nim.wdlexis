&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple du concepteur de formulaires de wdlexis+.
&&
&& La fenêtre est dessinée dans le concepteur (Conception > Ouvrir un formulaire…,
&& ou double-clic sur form_client.prg dans l'arbre du projet) ; le concepteur
&& régénère form_client.prg à chaque modification. Ici : le programme principal
&& et les procédures des événements, créées par « + nouvelle procédure… ».

clients = {}

FORMCLIENT_OUVRIR()
interface.executer()

? chaine(#clients) + " client(s) saisi(s)"
pour chaque c dans clients
  ? " -", c.prenom, c.nom, "(" + c.ville + ", " + c.categorie + ")"
suivant

&& ---- formulaire « client » : début (généré par le concepteur, gardez ces marques) ----
&& FORMCLIENT_OUVRIR() ouvre le formulaire ; ses contrôles sont dans formclient (formclient.fenetre…).

procedure CLIENT_OUVERTURE(ev)
  && surouverture de formclient (formulaire « client »)
  formclient.nom:focus()
finprocedure

procedure CLIENT_SAISIE(ev)
  && surchangement de nom (formulaire « client »)
  formclient.enregistrer.actif = rogner(formclient.nom.valeur) <> ""
finprocedure

procedure CLIENT_EFFACER(ev)
  && surclic de effacer (formulaire « client »)
  pour chaque nom dans {"nom", "prenom", "courriel"}
    formclient[majuscule(nom)].valeur = ""
  suivant
  formclient.etat.libelle = ""
  formclient.enregistrer.actif = faux
  formclient.nom:focus()
finprocedure

procedure CLIENT_ENREGISTRER(ev)
  && surclic de enregistrer (formulaire « client »)
  locale f = formclient
  locale c = {nom = majuscule(rogner(f.nom.valeur)), prenom = rogner(f.prenom.valeur)}
  c.courriel = rogner(f.courriel.valeur)
  c.ville = f.ville:element(f.ville:selection())
  c.categorie = sisinon(nombre(f.categorie.valeur) = 1, "particulier", "professionnel")
  c.lettre = f.lettre:coche(1)
  inserer(clients, c)
  CLIENT_EFFACER(ev)
  f.etat.libelle = c.prenom + " " + c.nom + " enregistré (" + #clients + ")"
finprocedure

&& ---- formulaire « client » : fin ----
