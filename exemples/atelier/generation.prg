&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ : boîte « Générer l'application ». Les choix sont ceux de
&& l'atelier natif et s'enregistrent au même format (.wdlexis/application.ini) ;
&& la compilation est faite par l'outil wdlexisgen livré avec le runtime.


fonction CIBLES_GEN()
retourner {{id = "linux-x64", libelle = "Linux x64"}, {id = "linux-arm64", libelle = "Linux arm64"}, ;
           {id = "macos-x64", libelle = "macOS x64"}, {id = "macos-arm64", libelle = "macOS Mx (Apple Silicon)"}, ;
           {id = "windows-x64", libelle = "Windows x64"}, {id = "windows-arm64", libelle = "Windows arm64"}}

fonction TYPES_GEN()
retourner {"console", "graphique", "service", "bibliotheque"}

fonction FICHIER_INI()
retourner fichier.joindre(dossier, ".wdlexis", "application.ini")

fonction PROJET_INTERFACE()
  && un projet qui utilise le paquet interface est forcément « graphique »
  pour chaque nom dans fichier.liste(dossier, vrai)
    si minuscule(fichier.extension(nom)) = ".prg"
      locale t = fichier.lire(fichier.joindre(dossier, nom))
      si ("paquet(" + car(34) + "interface" + car(34) + ")") $ t ou ("interface." $ t)
        retourner vrai
      finsi
    finsi
  suivant
retourner faux

fonction LIRE_INI()
  locale plat = systeme.plateforme()
  locale defaut = sisinon(plat = "windows", "windows-x64", sisinon(plat = "macosx", "macos-arm64", "linux-x64"))
  locale s = {type = "console", cibles = defaut, distribution = "dossier", bibliotheques = "1", icone = "", cadrage = ""}
  locale p = FICHIER_INI()
  si fichier.existe(p)
    pour chaque l dans fichier.lignes(p)
      locale i = position("=", l)
      si i > 1 et non commencepar(rogner(l), "#")
        s[majuscule(rogner(gauche(l, i - 1)))] = rogner(souschaine(l, i + 1))
      finsi
    suivant
  finsi
  si PROJET_INTERFACE()
    s.type = "graphique"
  finsi
retourner s

procedure GENERER_DIALOGUE
  globale gendlg, genctl
  si gendlg <> nul
    retourner
  finsi
  locale s = LIRE_INI()
  locale ui_force = PROJET_INTERFACE()
  gendlg = ui.fenetre{titre = "Générer l'application", largeur = 640, hauteur = 580, sombre = reglages.sombre}
  gendlg.surfermeture = @GEN_FERMETURE
  genctl = {}
  gendlg:ajouter(ui.etiquette("Projet : " + fichier.nom(dossier) + "   -   principal : " + FICHIER_PRINCIPAL()))
  locale corps = gendlg:ajouter(ui.rangee())
  locale cg = corps:ajouter(ui.colonne())
  cg.poids = 1
  cg:ajouter(ui.etiquette("Type d'application"))
  genctl.type = cg:ajouter(ui.radio("Console", "Graphique", "Service", "Bibliothèque"))
  pour i = 1 a 4
    si TYPES_GEN()[i] = s.type
      genctl.type.valeur = i
    finsi
  suivant
  si ui_force
    genctl.type.actif = faux
    cg:ajouter(ui.etiquette("(le paquet interface impose Graphique)"))
  finsi
  cg:ajouter(ui.etiquette("Distribution"))
  genctl.options = cg:ajouter(ui.cases("Archive (.zip / .tar.gz)", "Intégrer les bibliothèques"))
  genctl.options:cocher(1, s.distribution = "archive")
  genctl.options:cocher(2, s.bibliotheques = "1" ou s.bibliotheques = "oui" ou s.bibliotheques = "vrai")
  locale cd = corps:ajouter(ui.colonne())
  cd.poids = 1
  cd:ajouter(ui.etiquette("Générer un exécutable pour"))
  locale libelles = {}
  pour chaque c dans CIBLES_GEN()
    inserer(libelles, c.libelle)
  suivant
  genctl.cibles = cd:ajouter(ui.cases(libelles))
  pour i = 1 a 6
    si CIBLES_GEN()[i].id $ s.cibles
      genctl.cibles:cocher(i, vrai)
    finsi
  suivant
  locale rang = gendlg:ajouter(ui.rangee())
  locale bicone = rang:ajouter(ui.bouton("Icône…"))
  bicone.surclic = @GEN_ICONE
  genctl.icone = rang:ajouter(ui.etiquette(sisinon(s.icone = "", "(aucune icône)", s.icone)))
  genctl.icone.poids = 1
  genctl.cheminicone = s.icone
  genctl.etat = gendlg:ajouter(ui.etiquette(""))
  locale rb = gendlg:ajouter(ui.rangee())
  locale esp = rb:ajouter(ui.etiquette(""))
  esp.poids = 1
  locale ba = rb:ajouter(ui.bouton("Annuler", {annuler = vrai}))
  ba.surclic = @GEN_FERMER
  locale bs = rb:ajouter(ui.bouton("Sauver"))
  bs.surclic = @GEN_SAUVER
  genctl.compiler = rb:ajouter(ui.bouton("Compiler", {defaut = vrai}))
  genctl.compiler.surclic = @GEN_COMPILER
retourner

fonction GEN_CHOIX()
  locale c = {}
  pour i = 1 a 6
    si genctl.cibles:coche(i)
      inserer(c, CIBLES_GEN()[i].id)
    finsi
  suivant
  locale t = TYPES_GEN()[max(1, nombre(genctl.type.valeur) ou 1)]
  locale r = {type = t, cibles = joindre(c, ","), archive = genctl.options:coche(1)}
  r.bibliotheques = genctl.options:coche(2)
  r.icone = genctl.cheminicone
retourner r

procedure GEN_ICONE
  locale p = ui.ouvrirfichier{titre = "Icône de l'application", dossier = dossier, ;
                              filtre = "Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tga"}
  si p <> nul
    genctl.cheminicone = p
    genctl.icone.libelle = p
  finsi
retourner

procedure GEN_SAUVER
  locale c = GEN_CHOIX()
  locale s = LIRE_INI()
  locale l = {"# wdlexis+ : paramètres de génération de l'application", "type=" + c.type, ;
              "cibles=" + c.cibles, "distribution=" + sisinon(c.archive, "archive", "dossier"), ;
              "bibliotheques=" + sisinon(c.bibliotheques, "1", "0"), "icone=" + c.icone, "cadrage=" + s.cadrage}
  fichier.creerdossier(fichier.joindre(dossier, ".wdlexis"))
  fichier.ecrire(FICHIER_INI(), joindre(l, car(10)) + car(10))
  genctl.etat.libelle = "Paramètres enregistrés dans .wdlexis/application.ini"
retourner

procedure GEN_COMPILER
  locale c = GEN_CHOIX()
  si c.cibles = ""
    genctl.etat.libelle = "Choisissez au moins une cible."
    retourner
  finsi
  locale outil = lexis.outil("wdlexisgen")
  si outil = nul
    genctl.etat.libelle = "Outil wdlexisgen introuvable à côté du runtime."
    retourner
  finsi
  locale q = car(34)
  locale cmd = q + outil + q + " " + q + dossier + q + " --type=" + c.type + " --cibles=" + c.cibles + ;
               " --principal=" + q + FICHIER_PRINCIPAL() + q
  si c.archive
    cmd = cmd + " --archive"
  finsi
  si non c.bibliotheques
    cmd = cmd + " --sans-bibliotheques"
  finsi
  si c.icone <> ""
    cmd = cmd + " --icone=" + q + c.icone + q
  finsi
  genctl.compiler.actif = faux
  genctl.etat.libelle = "Compilation en cours… (le détail s'affiche dans la console de l'atelier)"
  bas.valeur = 2
  console.valeur = "$ " + cmd + car(10)
  locale r = systeme.capturer(cmd)
  SORTIE(r.sortie)
  si gendlg <> nul
    genctl.compiler.actif = vrai
    genctl.etat.libelle = sisinon(r.code = 0, "Application générée (voir le dossier distribution/ du projet).", ;
                                  "Échec de la génération (code " + r.code + ") : voir la console.")
  finsi
  ARBRE_PROJET()
retourner

procedure GEN_FERMER
  globale gendlg
  si gendlg <> nul
    gendlg:fermer()
  finsi
  gendlg = nul
retourner

procedure GEN_FERMETURE(ev)
  globale gendlg
  gendlg = nul
retourner
