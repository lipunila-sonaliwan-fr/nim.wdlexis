&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ : exécution et débogage (lexis.executer), console, variables,
&& pile d'appels, arguments du programme.

fonction CIBLE()
  locale p = fichier.joindre(dossier, FICHIER_PRINCIPAL())
  si fichier.existe(p)
    retourner p
  finsi
retourner ed:chemin()

procedure EXECUTER
  LANCER(faux, faux)
retourner

procedure DEBOGUER
  LANCER(vrai, faux)
retourner

procedure DEBOGUER_OU_CONTINUER
  si execution <> nul et execution:actif()
    si execution:enpause()
      CONTINUER()
    finsi
  sinon
    LANCER(vrai, faux)
  finsi
retourner

procedure LANCER(deboguer, pasapas)
  globale execution, pausecourante
  si execution <> nul et execution:actif()
    etat.libelle = "Un programme est déjà en cours."
    retourner
  finsi
  && les fichiers modifiés sont enregistrés : le programme lit le disque
  pour chaque d dans ed:documents()
    si d.modifie et d.chemin <> ""
      ed:enregistrer(nul, d.uid)
    finsi
  suivant
  locale cible = CIBLE()
  si cible = ""
    ui.alerte("Enregistrez le document avant de l'exécuter.", "attention")
    retourner
  finsi
  locale s = LIRE_SESSION()
  locale o = {arguments = s.arguments, sursortie = @SORTIE, surdemande = @DEMANDE, surfin = @FIN}
  si deboguer
    o.deboguer = vrai
    o.pasapas = pasapas
    o.pointsarret = TOUS_POINTS_ARRET()
    o.surpause = @PAUSE
  finsi
  console.valeur = ""
  tvars:vider()
  lpile:vider()
  pausecourante = nul
  bas.valeur = 2
  ETAT_BOUTONS("execution")
  etat.libelle = sisinon(deboguer, "Débogage de ", "Exécution de ") + fichier.nom(cible) + "…"
  execution = lexis.executer(cible, o)
retourner

fonction TOUS_POINTS_ARRET()
  locale l = {}
  pour chaque d dans ed:documents()
    locale lignes = ed:pointsarret(d.uid)
    si #lignes > 0 et d.chemin <> ""
      inserer(l, {source = d.chemin, lignes = lignes})
    finsi
  suivant
retourner l

procedure POINTS_ARRET_MODIFIES(uid)
  && F9 pendant l'exécution : le programme reçoit les nouveaux points d'arrêt
  si execution <> nul et execution:actif() et uid <> nul
    locale p = ed:chemin(uid)
    si p <> ""
      execution:pointsarret(p, ed:pointsarret(uid))
    finsi
  finsi
retourner

&& commandes du débogueur
procedure CONTINUER
  si EN_PAUSE()
    REPRISE()
    execution:continuer()
  finsi
retourner

procedure PAS
  si EN_PAUSE()
    REPRISE()
    execution:pas()
  sinonsi execution = nul ou non execution:actif()
    LANCER(vrai, vrai)
  finsi
retourner

procedure PASSER
  si EN_PAUSE()
    REPRISE()
    execution:passer()
  finsi
retourner

procedure SORTIR
  si EN_PAUSE()
    REPRISE()
    execution:sortir()
  finsi
retourner

procedure PAUSE_DEMANDEE
  si execution <> nul et execution:actif() et non execution:enpause()
    execution:pause()
  finsi
retourner

procedure ARRETER
  si execution <> nul et execution:actif()
    execution:arreter()
    etat.libelle = "Arrêt demandé…"
  finsi
retourner

fonction EN_PAUSE()
retourner execution <> nul et execution:actif() et execution:enpause()

procedure REPRISE
  ed:lignexecution()
  ETAT_BOUTONS("execution")
  etat.libelle = "Exécution…"
retourner

&& pause : ligne courante, variables et pile d'appels
procedure PAUSE(ev)
  globale pausecourante
  pausecourante = ev
  ETAT_BOUTONS("pause")
  lpile:vider()
  pour chaque f dans ev.pile
    lpile:ajouter(f.nom + "  —  " + fichier.nom(f.source) + ":" + f.ligne)
  suivant
  MONTRER_CADRE(1)
  bas.valeur = 3
  etat.libelle = "En pause : " + fichier.nom(ev.source) + ", ligne " + ev.ligne + ;
                 "  (F5 continuer, F10 pas principal, F11 pas à pas, Maj+F11 sortir)"
retourner

procedure MONTRER_CADRE(i)
  si pausecourante = nul
    retourner
  finsi
  locale f = pausecourante.pile[i]
  si f = nul
    retourner
  finsi
  tvars:vider()
  pour chaque v dans f.variables
    tvars:ajouterligne(v.nom, v.valeur, v.genre, v.portee)
  suivant
  pour chaque v dans pausecourante.globales
    tvars:ajouterligne(v.nom, v.valeur, v.genre, v.portee)
  suivant
  si f.source <> "" et fichier.estfichier(f.source)
    ed:ouvrir(f.source)
    ed:lignexecution(f.ligne)
  finsi
retourner

procedure CADRE(ev)
  MONTRER_CADRE(ev.index)
  bas.valeur = 3
retourner

&& touches du débogueur valables partout (l'éditeur les traite déjà lui-même)
procedure TOUCHE_FENETRE(ev)
  si ev.id = ed
    retourner
  finsi
  locale maj = ev.modificateurs <> nul et ev.modificateurs % 4 <> 0
  faire cas
  cas ev.touche = 1073741886            && F5
    si maj
      ARRETER()
    sinon
      DEBOGUER_OU_CONTINUER()
    finsi
  cas ev.touche = 1073741884            && F3
    SUIVANT_TROUVE(maj)
  cas ev.touche = 1073741890            && F9
    ed:basculerpointarret()
  cas ev.touche = 1073741891            && F10
    PASSER()
  cas ev.touche = 1073741892            && F11
    si maj
      SORTIR()
    sinon
      PAS()
    finsi
  fincas
retourner

&& console
procedure SORTIE(t)
  locale c = console.valeur + t
  si #c > 200000
    c = droite(c, 150000)
  finsi
  console.valeur = c
retourner

procedure DEMANDE(invite)
  bas.valeur = 2
  etat.libelle = "Le programme attend une saisie."
  entree:focus()
retourner

procedure TOUCHE(ev)
  si ev.touche = 13
    ENVOYER()
  finsi
retourner

procedure ENVOYER
  si execution <> nul et execution:attentesaisie()
    console.valeur = console.valeur + entree.valeur + car(10)
    execution:envoyer(entree.valeur)
    entree.valeur = ""
  finsi
retourner

procedure COPIER_CONSOLE
  ed:pressepapiers(console.valeur)
  etat.libelle = "Console copiée"
retourner

procedure EFFACER_CONSOLE
  console.valeur = ""
retourner

&& fin du programme
procedure FIN(ev)
  globale pausecourante, problemes
  pausecourante = nul
  ed:lignexecution()
  ETAT_BOUTONS("repos")
  si ev.ok
    etat.libelle = "Programme " + ev.message + "."
    retourner
  finsi
  SORTIE(car(10) + "[erreur] " + ev.message + car(10))
  etat.libelle = "Erreur" + sisinon(ev.ligne > 0, " à la ligne " + ev.ligne + " de " + fichier.nom(ev.source), "")
  && l'erreur rejoint l'onglet Problèmes et l'éditeur se place sur la ligne
  locale p = {genre = "exécution", ligne = ev.ligne, colonne = 1, chemin = ev.source}
  p.message = decouper(ev.message, car(10))[1]
  inserer(problemes, p, 1)
  tprob:vider()
  pour chaque x dans problemes
    tprob:ajouterligne(x.genre, fichier.nom(x.chemin), x.ligne, x.colonne, x.message)
  suivant
  si ev.source <> "" et fichier.existe(ev.source) et ev.ligne > 0
    ed:ouvrir(ev.source)
    ed:aller(ev.ligne, 1)
  finsi
retourner

&& arguments et fichier principal (enregistrés dans le projet)
procedure ARGUMENTS
  locale s = LIRE_SESSION()
  locale a = ui.demander("Arguments du programme (systeme.args) :", s.arguments)
  si a = nul
    retourner
  finsi
  locale p = ui.demander("Fichier principal, relatif au projet (vide = principal.prg) :", s.principal)
  si p = nul
    retourner
  finsi
  s.arguments = a
  s.principal = rogner(p)
  ECRIRE_SESSION(s)
  etat.libelle = "Arguments : " + sisinon(a = "", "aucun", a) + " — principal : " + FICHIER_PRINCIPAL()
retourner
