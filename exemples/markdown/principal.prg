&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Visionneuse Markdown : texte chargé d'un fichier, complété par le programme
ui = paquet("interface")
fen = ui.fenetre{titre = "Aide", largeur = 460, hauteur = 420}
aide = fen:ajouter(ui.markdown{fichier = "aide.md"})   && relatif au programme
aide.poids = 1                                         && occupe toute la fenêtre
aide.surselection = @LIEN                              && clic sur un lien
aide:ajouter("---", "*Ajouté par le programme.*", "### Journal")
pour i = 1 a 8
  aide:ajouter("- ligne de journal **" + i + "**")
finpour
ui.executer()

procedure LIEN(ev)
  ? "lien cliqué :", ev.texte
  ? "défilement :", aide:position(), "pixels"
retourner
