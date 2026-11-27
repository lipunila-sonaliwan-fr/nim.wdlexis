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

procedure PROFILER
  && Exécuter > Profiler le programme : résultats dans la page Profil (outils.prg)
  LANCER(faux, faux, vrai)
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

procedure LANCER(avecdebogueur, pasapas, profil)
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
  locale fichiercible = CIBLE()
  si fichiercible = ""
    ui.alerte("Enregistrez le document avant de l'exécuter.", "attention")
    retourner
  finsi
  locale s = LIRE_SESSION()
  locale o = {arguments = s.arguments, sursortie = @SORTIE, surdemande = @DEMANDE, surfin = @FIN}
  si profil = vrai
    o.surprofil = @PROFIL_RESULTAT
  finsi
  si avecdebogueur
    o.deboguer = vrai
    o.pasapas = pasapas
    o.pointsarret = TOUS_POINTS_ARRET()
    o.surpause = @PAUSE
  finsi
  console.valeur = ""
  si profil = vrai
    console.valeur = "[profileur actif : résultats dans la page Profil à la fin]" + car(10)
  finsi
  tvars:vider()
  lpile:vider()
  pausecourante = nul
  bas.valeur = 2
  ETAT_BOUTONS("execution")
  etat.libelle = sisinon(avecdebogueur, "Débogage de ", "Exécution de ") + fichier.nom(fichiercible) + "…"
  execution = lexis.executer(fichiercible, o)
retourner

fonction TOUS_POINTS_ARRET()
  locale l = {}
  pour chaque d dans ed:documents()
    locale lignesarret = ed:pointsarret(d.uid)
    si #lignesarret > 0 et d.chemin <> ""
      inserer(l, {source = d.chemin, lignes = lignesarret})
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
    lpile:ajouter(f.nom + "  -  " + fichier.nom(f.source) + ":" + f.ligne)
  suivant
  MONTRER_CADRE(1)
  AFFICHER_ENSEMBLE("bas")
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
  globale cadrevars, chemintable
  cadrevars = i
  chemintable = {}
  locale lignesvar = {}
  pour chaque v dans f.variables
    inserer(lignesvar, v)
  suivant
  pour chaque v dans pausecourante.globales
    inserer(lignesvar, v)
  suivant
  AFFICHER_VARIABLES(lignesvar)
  si f.source <> "" et fichier.estfichier(f.source)
    ed:ouvrir(f.source)
    ed:lignexecution(f.ligne)
  finsi
retourner

procedure AFFICHER_VARIABLES(lignesvar)
  && variables du cadre (chemintable vide) ou entrées de la table consultée ; ▸ : table
  globale lignesvars, varchoisie
  tvars:vider()
  lignesvars = lignesvar
  varchoisie = nul
  pour chaque v dans lignesvar
    tvars:ajouterligne(sisinon(v.table = vrai, "▸ ", "  ") + v.nom, v.valeur, v.genre, ;
                       sisinon(v.portee = nul, "clef", v.portee))
  suivant
  si #chemintable > 0
    locale noms = {}
    pour chaque p dans chemintable
      inserer(noms, p.libelle)
    suivant
    lblvar.libelle = "Table " + joindre(noms, " › ") + " : choisir une entrée pour la modifier (double-clic sur ▸ : ouvrir)"
  sinon
    lblvar.libelle = "Choisir une variable pour la modifier ; double-clic sur une table (▸) : voir son contenu"
  finsi
  bvarhaut.actif = #chemintable > 0
  bvarplus.actif = #chemintable > 0 et pausecourante <> nul
  bvarmoins.actif = faux
  saisievar.valeur = ""
  saisievar.actif = faux
  bvar.actif = faux
retourner

fonction CLEFS_CHEMIN()
  && clefs codées du chemin consulté, sans la variable de départ
  locale l = {}
  pour i = 2 a #chemintable
    inserer(l, chemintable[i].clef)
  suivant
retourner l

fonction PORTEE_RACINE()
retourner sisinon(racinetable.portee = "globale", "globale", "")

procedure TABLE_RAFRAICHIR
  && relit la table consultée dans le programme en pause
  si #chemintable = 0 ou execution = nul
    retourner
  finsi
  locale entrees = nul
  essayer
    entrees = execution:table(racinetable.nom, cadrevars, PORTEE_RACINE(), CLEFS_CHEMIN())
  capturer e
    etat.libelle = "Table : " + e
    TABLE_REMONTER(nul)
    retourner
  finessayer
  pour chaque x dans entrees
    x.portee = "clef"
  suivant
  AFFICHER_VARIABLES(entrees)
retourner

procedure VARIABLE_OUVRIR(ev)
  && double-clic : une table (▸) s'ouvre, sinon le champ de modification prend la main
  globale racinetable
  si varchoisie = nul
    retourner
  finsi
  locale v = lignesvars[varchoisie]
  si v.table <> vrai
    si saisievar.actif
      saisievar:focus()
    finsi
    retourner
  finsi
  si pausecourante = nul
    etat.libelle = "Le contenu des tables se consulte en pause (point d'arrêt, pas à pas)"
    retourner
  finsi
  si #chemintable = 0
    racinetable = v
    inserer(chemintable, {libelle = v.nom, clef = ""})
  sinon
    inserer(chemintable, {libelle = v.nom, clef = v.clef})
  finsi
  TABLE_RAFRAICHIR()
retourner

procedure TABLE_REMONTER(ev)
  si #chemintable > 0
    retirer(chemintable, #chemintable)
  finsi
  si #chemintable = 0
    MONTRER_CADRE(cadrevars)
  sinon
    TABLE_RAFRAICHIR()
  finsi
retourner

procedure TABLE_AJOUTER(ev)
  si #chemintable = 0 ou execution = nul
    retourner
  finsi
  locale k = ui.demander("Clef de la nouvelle entrée (nombre, nom, ou \"texte exact\") :", "")
  si k = nul ou rogner(k) = ""
    retourner
  finsi
  locale v = ui.demander("Valeur (12, 1.5, \"texte\", vrai, faux, {}) :", "")
  si v = nul
    retourner
  finsi
  essayer
    locale montre = execution:modifiertable(racinetable.nom, cadrevars, PORTEE_RACINE(), CLEFS_CHEMIN(), rogner(k), v)
    etat.libelle = "Entrée ajoutée : " + k + " = " + montre
  capturer e
    etat.libelle = "Ajout refusé : " + e
  finessayer
  TABLE_RAFRAICHIR()
retourner

procedure TABLE_SUPPRIMER(ev)
  si #chemintable = 0 ou varchoisie = nul ou execution = nul
    retourner
  finsi
  locale v = lignesvars[varchoisie]
  essayer
    execution:supprimerentree(racinetable.nom, cadrevars, PORTEE_RACINE(), CLEFS_CHEMIN(), v.clef)
    etat.libelle = "Entrée supprimée : " + v.nom
  capturer e
    etat.libelle = "Suppression refusée : " + e
  finessayer
  TABLE_RAFRAICHIR()
retourner

&& Modification d'une variable ou d'une entrée de table pendant une pause : même type,
&& ou littéral pour en changer (12, 1.5, "texte", vrai, faux, nul, {})
procedure VARIABLE_CHOISIE(ev)
  globale varchoisie
  locale i = ev.index
  si lignesvars = nul ou i = nul ou i < 1 ou i > #lignesvars
    retourner
  finsi
  locale v = lignesvars[i]
  varchoisie = i
  bvarmoins.actif = pausecourante <> nul et #chemintable > 0
  si pausecourante = nul ou v.genre = "zone"
    lblvar.libelle = v.nom + " (" + v.genre + ") : modifiable seulement en pause"
    saisievar.actif = faux
    bvar.actif = faux
    retourner
  finsi
  locale simple = v.genre = "chaine" ou v.genre = "entier" ou v.genre = "décimal" ou v.genre = "logique" ou v.genre = "nul"
  locale val = sisinon(simple, v.valeur, "")
  si v.genre = "chaine" et #val >= 2 et commencepar(val, car(34)) et finitpar(val, car(34))
    val = souschaine(val, 2, #val - 1)
  finsi
  lblvar.libelle = v.nom + " (" + v.genre + ", " + sisinon(v.portee = nul, "clef", v.portee) + ") =" + ;
                   sisinon(v.table = vrai, "  [table : double-clic pour l'ouvrir, ou nouvelle valeur]", "")
  saisievar.actif = vrai
  bvar.actif = vrai
  saisievar.valeur = val
retourner

procedure VARIABLE_TOUCHE(ev)
  si ev.touche = 13
    VARIABLE_APPLIQUER(ev)
  finsi
retourner

procedure VARIABLE_APPLIQUER(ev)
  si varchoisie = nul ou execution = nul ou pausecourante = nul
    retourner
  finsi
  locale v = lignesvars[varchoisie]
  locale montre = nul
  si #chemintable > 0
    essayer
      montre = execution:modifiertable(racinetable.nom, cadrevars, PORTEE_RACINE(), CLEFS_CHEMIN(), v.clef, saisievar.valeur)
    capturer e
      etat.libelle = "Modification refusée : " + e
      retourner
    finessayer
    TABLE_RAFRAICHIR()
    etat.libelle = v.nom + " = " + montre + " (valeur modifiée ; F5 continuer, F10 / F11 pas à pas)"
    retourner
  finsi
  locale portee = sisinon(v.portee = "globale", "globale", "")
  essayer
    montre = execution:modifier(v.nom, saisievar.valeur, cadrevars, portee)
  capturer e
    etat.libelle = "Modification refusée : " + e
    retourner
  finessayer
  v.valeur = montre
  && l'instantané de la pause suit (changement de cadre dans la pile d'appels)
  locale liste = sisinon(v.portee = "globale", pausecourante.globales, pausecourante.pile[cadrevars].variables)
  pour chaque w dans liste
    si minuscule(w.nom) = minuscule(v.nom)
      w.valeur = montre
    finsi
  suivant
  tvars:fixercellule(varchoisie, 2, montre)
  etat.libelle = v.nom + " = " + montre + " (valeur modifiée ; F5 continuer, F10 / F11 pas à pas)"
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
  etat.libelle = "Arguments : " + sisinon(a = "", "aucun", a) + " - principal : " + FICHIER_PRINCIPAL()
retourner
