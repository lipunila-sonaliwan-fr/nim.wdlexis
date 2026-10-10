&& Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr
&& Fenêtre, bouton, compteur : le minimum avec le paquet interface
ui = paquet("interface")
&& ui.tracer(vrai)   && décommentez pour afficher chaque événement reçu dans la console

fen = ui.fenetre{titre = "Bonjour wdlexis+", largeur = 420, hauteur = 200}
lbl = fen:ajouter(ui.etiquette("Cliquez sur le bouton", "centre"))
nb = 0
btn = fen:ajouter(ui.bouton("Compter", {defaut = vrai}))
btn.surclic = @COMPTER
ui.executer()

procedure COMPTER(ev)
  nb += 1
  btn.valeur = "Clics : " + nb
retourner
