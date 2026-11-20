&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Autoriser une app macOS : outils (shell, chemins, journal).

&& argument shell entre apostrophes : 'l'\''app' -> l'app
fonction Q(s)
retourner "'" + remplacertexte(chaine(s), "'", "'" + car(92) + "''") + "'"

&& exécute une commande (sortie d'erreur comprise) ; renvoie {sortie, code}
&& en simulation, la commande n'est qu'écrite au journal
fonction CMD(commande, muet)
  si non muet
    JOURNAL("$ " + commande)
  finsi
  si non SUR_MAC
    retourner {sortie = "", code = 127}
  finsi
  locale r = systeme.capturer(commande + " 2>&1")
  r.sortie = rognerd(chaine(r.sortie))
  si non muet et r.sortie <> ""
    JOURNAL(r.sortie)
  finsi
retourner r

&& première ligne non vide d'une sortie
fonction PREMIERE_LIGNE(s)
  pour chaque l dans decouper(chaine(s), car(10))
    si rogner(l) <> ""
      retourner rogner(l)
    finsi
  suivant
retourner ""

&& dossier .app qui contient un chemin (l'exécutable choisi, ou le .app lui-même)
fonction BUNDLE_DE(chemin)
  locale p = rogner(chaine(chemin))
  tantque finitpar(p, "/") et longueur(p) > 1
    p = gauche(p, longueur(p) - 1)
  fintantque
  tantque p <> "" et p <> "/"
    si finitpar(minuscule(p), ".app")
      retourner p
    finsi
    locale parent = fichier.dossier(p)
    si parent = p
      sortir
    finsi
    p = parent
  fintantque
retourner ""

procedure JOURNAL(t)
  journal_texte = journal_texte + chaine(t) + car(10)
  si longueur(journal_texte) > 400000
    journal_texte = droite(journal_texte, 300000)
  finsi
  essayer
    ed_journal:fixertexte(journal_texte)
    ed_journal:aller(9999999)
  capturer e
  finessayer
retourner

procedure STATUT(m)
  l_statut.libelle = m
retourner

fonction OUI_NON(b)
retourner sisinon(b, "oui", "non")
