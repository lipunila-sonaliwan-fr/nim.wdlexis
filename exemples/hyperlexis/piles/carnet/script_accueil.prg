&& Script du modèle de carte « accueil » (HyperLexis) : procédures des événements.
&& Les contrôles de la carte affichée sont dans formaccueil (formaccueil.recherche.valeur…).

&& ---- formulaire « accueil » : début (généré par le concepteur, gardez ces marques) ----
&& FORMACCUEIL_OUVRIR() ouvre le formulaire ; ses contrôles sont dans formaccueil (formaccueil.fenetre…).

procedure ACCUEIL_OUVERTURE(ev)
  && surouverture de la carte : nombre de fiches
  locale n = 0
  pour chaque c dans LISTE_CARTES()
    si MODELE_CARTE(c) = "fiche"
      n += 1
    finsi
  suivant
  formaccueil.compte.libelle = n + " fiche(s) dans le carnet"
finprocedure

procedure ACCUEIL_PARCOURIR_CLIC(ev)
  && surclic de parcourir : la première fiche
  pour chaque c dans LISTE_CARTES()
    si MODELE_CARTE(c) = "fiche"
      ALLER_CARTE(c)
      retourner
    finsi
  suivant
  formaccueil.resultat.libelle = "Aucune fiche : créez-en une."
finprocedure

procedure ACCUEIL_NOUVELLE_CLIC(ev)
  && surclic de nouvelle : une carte de plus sur le modèle « fiche »
  NOUVELLE_CARTE("fiche")
  CONTROLE("nom"):focus()
finprocedure

procedure ACCUEIL_TROUVER_CLIC(ev)
  && surclic de trouver : comme « find » des applications orientées cartes
  locale t = rogner(formaccueil.recherche.valeur)
  si t = ""
    formaccueil.resultat.libelle = "Tapez un texte à trouver."
  sinonsi non TROUVER(t)
    formaccueil.resultat.libelle = "Introuvable : " + t
  finsi
finprocedure

&& ---- formulaire « accueil » : fin ----
