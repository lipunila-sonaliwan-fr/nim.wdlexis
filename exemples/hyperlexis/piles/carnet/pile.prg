&& Pile « Carnet d'adresses » : définition écrite par HyperLexis (atelier de piles Lexis+).
&& Modifiable à la main : titre, taille des cartes, couleur de fond, barre de navigation,
&& persistance des données (pile_donnees.json) et ordre des cartes. Chaque carte utilise
&& un modèle : son dessin form_<modele>.prg et son script script_<modele>.prg.

fonction PILE_DEFINITION()
retourner {
  titre = "Carnet d'adresses",
  largeur = 640, hauteur = 440,
  couleur = "#FFFDF5",
  navigation = vrai, persistance = vrai, version = 1,
  cartes = {
    {nom = "accueil", modele = "accueil"},
    {nom = "fiche_1", modele = "fiche"},
    {nom = "fiche_2", modele = "fiche"},
    {nom = "fiche_3", modele = "fiche"}
  }
}
finfonction
