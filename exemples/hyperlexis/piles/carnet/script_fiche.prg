&& Script du modèle de carte « fiche » (HyperLexis) : procédures des événements.
&& Toutes les fiches partagent ce modèle ; chacune garde le contenu de ses champs.
&& Les contrôles de la fiche affichée sont dans formfiche (formfiche.nom.valeur…).

&& ---- formulaire « fiche » : début (généré par le concepteur, gardez ces marques) ----
&& FORMFICHE_OUVRIR() ouvre le formulaire ; ses contrôles sont dans formfiche (formfiche.fenetre…).

procedure FICHE_OUVERTURE(ev)
  && surouverture de la carte : rang et titre de la fiche
  formfiche.rang.libelle = "Carte " + NUMERO_CARTE() + " / " + NOMBRE_CARTES()
  FICHE_NOM_CHANGEMENT(ev)
finprocedure

procedure FICHE_NOM_CHANGEMENT(ev)
  && surchangement de nom et de prenom : le titre suit
  locale t = rogner(formfiche.prenom.valeur + " " + majuscule(formfiche.nom.valeur))
  formfiche.titre.libelle = sisinon(t = "", "Nouvelle fiche", t)
finprocedure

procedure FICHE_ACCUEIL_CLIC(ev)
  ALLER_CARTE("accueil")
finprocedure

procedure FICHE_PRECEDENTE_CLIC(ev)
  CARTE_PRECEDENTE()
finprocedure

procedure FICHE_SUIVANTE_CLIC(ev)
  CARTE_SUIVANTE()
finprocedure

procedure FICHE_NOUVELLE_CLIC(ev)
  NOUVELLE_CARTE()
  formfiche.nom:focus()
finprocedure

procedure FICHE_SUPPRIMER_CLIC(ev)
  si interface.confirmer("Supprimer cette fiche ?", "question")
    SUPPRIMER_CARTE()
  finsi
finprocedure

&& ---- formulaire « fiche » : fin ----
