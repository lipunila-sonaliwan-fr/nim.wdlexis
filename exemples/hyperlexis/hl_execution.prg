&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& hl_execution.prg : mode Exécution (la pile fonctionne dans la fenêtre de
&& l'atelier), boîte de messages, pile autonome, génération de l'application.
&&
&& Passer en mode Exécution :
&&   1. tout est enregistré ;
&&   2. les formulaires, les scripts et les bibliothèques de la pile sont réunis
&&      dans ~/.hyperlexis/exec/pile_exec.prg et chargés par lexis.charger
&&      (toujours le même fichier : recharger remplace les procédures, d'une
&&      pile à l'autre) ; une erreur est ramenée à son fichier et à sa ligne ;
&&   3. le moteur (pile_moteur.prg, le même que celui de l'application) affiche
&&      la carte courante dans la vue d'exécution.
&& Revenir en Conception relève les données saisies (elles sont enregistrées
&& avec la pile) et affiche la carte où l'on se trouve.

procedure HL_BASCULER_MODE
  si hl.mode = "execution"
    HL_MODE_CONCEPTION()
  sinon
    HL_MODE_EXECUTION()
  finsi
finprocedure

fonction HL_LIBELLE_MODE()
  si hl.mode = "execution"
    retourner "▶ EXÉCUTION · carte " + hl.index + " / " + #hl.def.cartes
  finsi
  si hl.def = nul
    retourner "✎ CONCEPTION"
  finsi
retourner "✎ CONCEPTION · carte " + hl.index + " / " + #hl.def.cartes
finfonction

procedure HL_MAJ_MODE
  locale ex = hl.mode = "execution"
  pour chaque b dans {hlc.bexecution}
    b.fond = sisinon(ex, "#16A34A", "#E5E7EB")
    b.couleur = sisinon(ex, "#FFFFFF", "#111827")
  suivant
  pour chaque b dans {hlc.bconception}
    b.fond = sisinon(ex, "#E5E7EB", "#2563EB")
    b.couleur = sisinon(ex, "#111827", "#FFFFFF")
  suivant
  hlc.aideoutils.libelle = sisinon(ex, "La pile fonctionne.", "Glissez un outil sur la carte")
  hlc.lblmode.libelle = HL_LIBELLE_MODE()
  hlc.lblmode.couleur = sisinon(ex, "#16A34A", "#2563EB")
finprocedure

procedure HL_MODE_EXECUTION
  si hl.mode = "execution" ou hl.dossier = ""
    retourner
  finsi
  HL_ENREGISTRER(faux)
  si non HL_PREPARER_CODE()
    HL_ONGLET("problemes")
    HL_ETAT("Le code de la pile contient une erreur : voir l'onglet Problèmes.")
    retourner
  finsi
  locale manquantes = HL_GESTIONNAIRES_MANQUANTS()
  si #manquantes > 0
    locale noms = {}
    pour chaque m dans manquantes
      inserer(noms, m.procedure)
    suivant
    si non ui.confirmer("Procédure(s) des événements introuvable(s) : " + joindre(noms, ", ") + NL() + ;
                        "Les créer (vides) dans les scripts des modèles ?", "question")
      HL_ETAT("Exécution annulée : procédures manquantes " + joindre(noms, ", "))
      retourner
    finsi
    HL_CREER_MANQUANTES(manquantes)
    si non HL_PREPARER_CODE()
      HL_ONGLET("problemes")
      retourner
    finsi
  finsi
  hl.mode = "execution"
  HL_ONGLET("interface")
  hlc.conception.visible = faux
  hlc.vueexec.visible = vrai
  si hlc.palette <> nul
    hlc.palette.visible = faux
  finsi
  HL_INSPECTEUR()
  HL_ARBRE()
  HL_MAJ_MODE()
  MOTEUR_INITIALISER(hlc.vueexec, hl.def, hl.donnees, {persistance = faux, dossier = hl.dossier, ;
                     surmessage = @HL_MESSAGE_RECU, surerreur = @HL_ERREUR_SCRIPT, ;
                     surcarte = @HL_CARTE_EXEC, surcartes = @HL_CARTES_EXEC})
  MOTEUR_CROCHET("SUR_OUVERTURE_PILE")
  ALLER_CARTE(hl.index)
  HL_ETAT("Mode Exécution : la pile fonctionne. ✎ Conception (ou Ctrl+E) pour revenir au dessin.")
finprocedure

procedure HL_MODE_CONCEPTION
  si hl.mode <> "execution"
    retourner
  finsi
  si MOTEUR_ACTIF()
    locale i = NUMERO_CARTE()
    MOTEUR_ARRETER()
    si i >= 1
      hl.index = i
    finsi
  finsi
  hl.mode = "conception"
  HL_ONGLET("interface")
  hlc.vueexec.visible = faux
  hlc.conception.visible = vrai
  si hlc.palette <> nul
    hlc.palette.visible = vrai
  finsi
  HL_ECRIRE_FICHIERS_PILE(hl.dossier)
  HL_ALLER_CONCEPTION(hl.index)
  HL_ETAT("Mode Conception : les données saisies sont enregistrées avec la pile.")
finprocedure

procedure HL_CARTE_EXEC(nom, i)
  hl.index = i
  HL_MAJ_CARTES()
  HL_MAJ_MODE()
finprocedure

procedure HL_CARTES_EXEC
  HL_MAJ_CARTES()
  HL_ECRIRE_FICHIERS_PILE(hl.dossier)
finprocedure

procedure HL_ERREUR_SCRIPT(m)
  HL_MESSAGE_JOURNAL("[erreur] " + m)
  HL_ETAT("⚠ " + m)
  inserer(hl.problemes, {genre = "exécution", chemin = "", ligne = 0, message = m}, 1)
  HL_PROBLEMES(hl.problemes)
  HL_ONGLET("messages")
finprocedure

procedure HL_MESSAGE_RECU(t)
  HL_MESSAGE_JOURNAL(t)
  HL_ONGLET("messages")
finprocedure

&&
&& Chargement du code de la pile
&&

fonction HL_FICHIER_EXEC()
retourner fichier.joindre(HL_DOSSIER_EXEC(), "pile_exec.prg")
finfonction

fonction HL_PREPARER_CODE()
  && formulaires + scripts + bibliothèques, en un seul fichier chargé par lexis.charger
  locale sources = {}
  pour chaque m dans HL_MODELES_DU_DOSSIER(hl.dossier)
    inserer(sources, HL_FORM(m))
  suivant
  pour chaque p dans HL_FICHIERS_CODE()
    inserer(sources, p)
  suivant
  locale lignes = {}
  hl.segments = {}
  pour chaque p dans sources
    inserer(lignes, "&& ==== " + p + " ====")
    locale debut = #lignes + 1
    pour chaque l dans HL_LIGNES(HL_TEXTE_DE(p))
      inserer(lignes, l)
    suivant
    inserer(hl.segments, {chemin = p, debut = debut, fin = #lignes})
  suivant
  locale cible = HL_FICHIER_EXEC()
  fichier.ecrire(cible, joindre(lignes, NL()) + NL())
  essayer
    lexis.charger(cible)
  capturer e
    locale pb = HL_ERREUR_LOCALISEE(e)
    HL_PROBLEMES({pb})
    HL_MESSAGE_JOURNAL("[code de la pile] " + fichier.nom(pb.chemin) + ":" + pb.ligne + " : " + pb.message)
    si pb.chemin <> "" et fichier.existe(pb.chemin)
      hlc.ed:ouvrir(pb.chemin)
      si pb.ligne > 0
        hlc.ed:aller(pb.ligne, 1)
      finsi
    finsi
    retourner faux
  finessayer
  HL_PROBLEMES({})
retourner vrai
finfonction

fonction HL_ERREUR_LOCALISEE(e)
  && « …/pile_exec.prg:123: message » -> {chemin, ligne, message} dans le vrai fichier
  locale m = texte(e)
  locale cible = HL_FICHIER_EXEC()
  locale i = position(cible + ":", m)
  si i = 0
    retourner {genre = "erreur", chemin = "", ligne = 0, message = m}
  finsi
  locale reste = souschaine(m, i + #cible + 1)
  locale j = position(":", reste)
  locale n = nombre(gauche(reste, j - 1))
  locale msg = rogner(souschaine(reste, j + 1))
  si n = nul
    retourner {genre = "erreur", chemin = "", ligne = 0, message = m}
  finsi
  pour chaque s dans hl.segments
    si n >= s.debut et n <= s.fin
      retourner {genre = "erreur", chemin = s.chemin, ligne = n - s.debut + 1, message = msg}
    finsi
  suivant
retourner {genre = "erreur", chemin = "", ligne = n, message = msg}
finfonction

fonction HL_GESTIONNAIRES_MANQUANTS()
  && procédures associées aux événements des modèles mais absentes du code chargé
  locale l = {}
  pour chaque m dans HL_MODELES()
    locale d = HL_DESSIN_DE(HL_LIRE(HL_FORM(m)))
    si d <> nul
      locale tous = {}
      HL_NOEUDS_TOUS(d, tous)
      pour chaque n dans tous
        pour chaque e dans n["events"]
          si lexis.procedure(e[2]) = nul
            inserer(l, {modele = m, procedure = e[2], evenement = e[1], noeud = n["name"]})
          finsi
        suivant
      suivant
    finsi
  suivant
retourner l
finfonction

procedure HL_CREER_MANQUANTES(l)
  pour chaque x dans l
    locale p = HL_SCRIPT(x.modele)
    si non fichier.existe(p)
      fichier.ecrire(p, HL_TEXTE_SCRIPT_MODELE(x.modele))
    finsi
    locale uid = hlc.ed:chercherdocument(p)
    locale src = sisinon(uid <> nul, hlc.ed:texte(uid), HL_LIRE(p))
    si HL_LIGNE_PROCEDURE(src, x.procedure) = 0
      locale r = HL_INSERER_PROCEDURE(src, x.modele, x.procedure, x.evenement, x.noeud, nul)
      si uid <> nul
        hlc.ed:fixertexte(r.texte, uid)
        hlc.ed:enregistrer(nul, uid)
      sinon
        fichier.ecrire(p, r.texte)
      finsi
    finsi
  suivant
finprocedure

&&
&& Boîte de messages : une commande ou une expression
&& Lexis+, exécutée dans la pile (ALLER_CARTE("suivante"), NOMBRE_CARTES()...)
&&

procedure HL_MESSAGE_JOURNAL(t)
  && le plus récent en haut (une ligne de la liste par ligne de texte)
  locale l = decouper(remplacertexte(texte(t), car(13), ""), car(10))
  pour i = #l a 1 pas -1
    hlc.journal:inserer(1, remplacertexte(l[i], car(9), "    "))
  suivant
  tantque hlc.journal:nombre() > 2000
    hlc.journal:supprimer(hlc.journal:nombre())
  fintantque
finprocedure

procedure HL_MESSAGES_EFFACER
  hlc.journal:vider()
finprocedure

procedure HL_JOURNAL_COPIER(ev)
  && double-clic : la ligne va dans la boîte de messages
  locale i = hlc.journal:selection()
  si i <> nul et i >= 1
    locale l = rogner(hlc.journal:element(i))
    si commencepar(l, "› ")
      l = souschaine(l, 3)
    finsi
    hlc.saisiemsg.valeur = l
    hlc.saisiemsg:focus()
  finsi
finprocedure

procedure HL_MESSAGE_TOUCHE(ev)
  faire cas
  cas ev.touche = 13 ou ev.touche = 1073741912
    HL_MESSAGE_ENVOYER()
  cas ev.touche = 1073741906                  && ↑
    si #hl.messages > 0
      hl.imessage = max(1, hl.imessage - 1)
      hlc.saisiemsg.valeur = hl.messages[hl.imessage]
    finsi
  cas ev.touche = 1073741905                  && ↓
    si hl.imessage < #hl.messages
      hl.imessage += 1
      hlc.saisiemsg.valeur = hl.messages[hl.imessage]
    sinon
      hl.imessage = #hl.messages + 1
      hlc.saisiemsg.valeur = ""
    finsi
  fincas
finprocedure

procedure HL_MESSAGE_ENVOYER
  locale code = rogner(hlc.saisiemsg.valeur)
  si code = ""
    retourner
  finsi
  inserer(hl.messages, code)
  hl.imessage = #hl.messages + 1
  hlc.saisiemsg.valeur = ""
  locale r = HL_EVALUER(code)
  HL_MESSAGE_JOURNAL("› " + code + NL() + "  " + r)
  hlc.saisiemsg:focus()
finprocedure

fonction HL_JOINDRE_MSG(l)
  locale p = {}
  pour chaque x dans l
    inserer(p, HL_AFFICHER_VALEUR(x))
  suivant
retourner joindre(p, " ")
finfonction

fonction HL_AFFICHER_VALEUR(v)
  si type(v) = "table"
    essayer
      retourner json(v)
    capturer e
    finessayer
  finsi
retourner texte(v)
finfonction

fonction HL_EST_COMMANDE(code)
  && instruction (affectation, si, pour…) plutôt qu'expression
  locale m = minuscule(code)
  pour chaque k dans {"si ", "pour ", "tantque ", "faire ", "locale ", "globale ", "inserer ", "retirer ", ;
                      "liberer ", "stocker ", "essayer", "erreur ", "retourner"}
    si commencepar(m, k)
      retourner vrai
    finsi
  suivant
  locale i = position("=", code)
  si i <= 1
    retourner faux
  finsi
  locale avant = souschaine(code, i - 1, 1)
  locale apres = souschaine(code, i + 1, 1)
  si contient({"<", ">", "!", "="}, avant) ou apres = "="
    retourner faux
  finsi
  locale cible = rogner(gauche(code, i - 1))
  si finitpar(cible, "+") ou finitpar(cible, "-")
    cible = rogner(gauche(cible, #cible - 1))
  finsi
  pour j = 1 a #cible
    si position(souschaine(cible, j, 1), "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.[]" + Q()) = 0
      retourner faux
    finsi
  suivant
retourner #cible > 0
finfonction

fonction HL_EVALUER(code)
  locale expr = nul
  si commencepar(code, "?")
    expr = rogner(souschaine(code, 2))
    si "," $ expr
      expr = "HL_JOINDRE_MSG({" + expr + "})"
    finsi
  sinonsi non HL_EST_COMMANDE(code)
    expr = code
  finsi
  si expr <> nul
    locale fe = fichier.joindre(HL_DOSSIER_EXEC(), "message_expression.prg")
    fichier.ecrire(fe, "fonction HL_MESSAGE_EXPRESSION()" + NL() + "retourner (" + expr + ")" + NL() + "finfonction" + NL())
    locale charge = faux
    essayer
      lexis.charger(fe)
      charge = vrai
    capturer e
      charge = faux
    finessayer
    si charge
      essayer
        locale v = appeler(lexis.procedure("HL_MESSAGE_EXPRESSION"))
        retourner "= " + HL_AFFICHER_VALEUR(v)
      capturer e
        retourner "erreur : " + e
      finessayer
    finsi
  finsi
  locale fi = fichier.joindre(HL_DOSSIER_EXEC(), "message_commande.prg")
  fichier.ecrire(fi, "procedure HL_MESSAGE_COMMANDE()" + NL() + code + NL() + "finprocedure" + NL())
  essayer
    lexis.charger(fi)
  capturer e
    locale m = texte(e)
    locale k = position("message_commande.prg:", m)
    si k > 0
      m = souschaine(m, k + 21)
      m = souschaine(m, position(":", m) + 1)
    finsi
    retourner "syntaxe : " + rogner(m)
  finessayer
  essayer
    appeler(lexis.procedure("HL_MESSAGE_COMMANDE"))
  capturer e
    retourner "erreur : " + e
  finessayer
retourner "ok"
finfonction

&&
&& Pile autonome : la pile enregistrée, lancée comme par wdlexisrt
&&

procedure HL_AUTONOME
  si hl.dossier = ""
    retourner
  finsi
  si hl.autonome <> nul et hl.autonome:actif()
    HL_ETAT("La pile autonome est déjà lancée.")
    retourner
  finsi
  si hl.mode = "execution"
    HL_MODE_CONCEPTION()
  finsi
  HL_ENREGISTRER(faux)
  locale p = HL_P("principal.prg")
  HL_MESSAGE_JOURNAL("▷ wdlexisrt " + p)
  hl.autonome = lexis.executer(p, {sursortie = @HL_SORTIE_AUTONOME, surfin = @HL_FIN_AUTONOME})
  HL_ONGLET("messages")
  HL_ETAT("Pile autonome lancée (sa propre fenêtre) : ses données sont relues à sa fermeture.")
finprocedure

procedure HL_SORTIE_AUTONOME(t)
  && sortie du programme, par lignes complètes
  hl.tampon = (hl.tampon ou "") + t
  locale i = position(car(10), hl.tampon)
  tantque i > 0
    HL_MESSAGE_JOURNAL("  " + gauche(hl.tampon, i - 1))
    hl.tampon = souschaine(hl.tampon, i + 1)
    i = position(car(10), hl.tampon)
  fintantque
finprocedure

procedure HL_FIN_AUTONOME(ev)
  si hl.tampon <> nul et hl.tampon <> ""
    HL_MESSAGE_JOURNAL("  " + hl.tampon)
    hl.tampon = ""
  finsi
  si ev.ok
    HL_MESSAGE_JOURNAL("▷ pile autonome terminée")
  sinon
    HL_MESSAGE_JOURNAL("▷ erreur : " + ev.message + sisinon(ev.ligne > 0, " (" + fichier.nom(ev.source) + ":" + ev.ligne + ")", ""))
  finsi
  && l'application a pu modifier les données et la liste des cartes
  si hl.mode = "conception" et hl.dossier <> ""
    hl.donnees = HL_LIRE_DONNEES()
    si hl.donnees._CARTES <> nul
      si #hl.donnees._CARTES > 0
        hl.def.cartes = {}
        pour chaque c dans hl.donnees._CARTES
          inserer(hl.def.cartes, {nom = c.nom, modele = c.modele})
        suivant
      finsi
      hl.donnees._CARTES = nul
    finsi
    HL_ECRIRE_FICHIERS_PILE(hl.dossier)
    HL_ALLER_CONCEPTION(min(hl.index, #hl.def.cartes))
  finsi
finprocedure

&&
&& Générer l'application (outil wdlexisgen livré avec le runtime)
&&

fonction HL_CIBLES()
retourner {{id = "linux-x64", libelle = "Linux x64"}, {id = "linux-arm64", libelle = "Linux arm64"}, ;
           {id = "macos-x64", libelle = "macOS x64"}, {id = "macos-arm64", libelle = "macOS Mx (Apple Silicon)"}, ;
           {id = "windows-x64", libelle = "Windows x64"}, {id = "windows-arm64", libelle = "Windows arm64"}}
finfonction

fonction HL_LIRE_INI()
  locale s = {cibles = "", distribution = "dossier", bibliotheques = "1", icone = "", cadrage = ""}
  locale p = HL_P(".wdlexis/application.ini")
  si fichier.existe(p)
    pour chaque l dans fichier.lignes(p)
      locale i = position("=", l)
      si i > 1 et non commencepar(rogner(l), "#")
        s[majuscule(rogner(gauche(l, i - 1)))] = rogner(souschaine(l, i + 1))
      finsi
    suivant
  finsi
retourner s
finfonction

procedure HL_GENERER_DIALOGUE
  si hl.dossier = ""
    retourner
  finsi
  si hlc.gen <> nul
    retourner
  finsi
  HL_ENREGISTRER(faux)
  locale s = HL_LIRE_INI()
  hlc.gen = {}
  hlc.gen.fen = ui.fenetre{titre = "Générer l'application", largeur = 580, hauteur = 580, sombre = hl.reglages.sombre}
  hlc.gen.fen.surfermeture = @HL_GEN_FERMETURE
  hlc.gen.fen:ajouter(ui.etiquette("Pile « " + hl.def.titre + " » : application graphique autonome (wdlexisgen)"))
  hlc.gen.fen:ajouter(ui.etiquette("Générer un exécutable pour"))
  locale libelles = {}
  pour chaque c dans HL_CIBLES()
    inserer(libelles, c.libelle)
  suivant
  hlc.gen.cibles = hlc.gen.fen:ajouter(ui.cases(libelles))
  locale plat = systeme.plateforme()
  locale defaut = sisinon(plat = "windows", "windows-x64", sisinon(plat = "macosx", "macos-arm64", "linux-x64"))
  locale choisies = sisinon(s.cibles = "", defaut, s.cibles)
  pour i = 1 a 6
    si HL_CIBLES()[i].id $ choisies
      hlc.gen.cibles:cocher(i, vrai)
    finsi
  suivant
  hlc.gen.options = hlc.gen.fen:ajouter(ui.cases("Archive (.zip / .tar.gz)", "Intégrer les bibliothèques requises"))
  hlc.gen.options:cocher(1, s.distribution = "archive")
  hlc.gen.options:cocher(2, s.bibliotheques <> "0")
  locale rang = hlc.gen.fen:ajouter(ui.rangee())
  locale bi = rang:ajouter(ui.bouton("Icône…"))
  bi.surclic = @HL_GEN_ICONE
  hlc.gen.cheminicone = s.icone
  hlc.gen.icone = rang:ajouter(ui.etiquette(sisinon(s.icone = "", "(icône par défaut)", s.icone)))
  hlc.gen.icone.poids = 1
  hlc.gen.etat = hlc.gen.fen:ajouter(ui.etiquette("La distribution est rangée dans le dossier distribution/ de la pile."))
  locale rb = hlc.gen.fen:ajouter(ui.rangee())
  locale esp = rb:ajouter(ui.etiquette(""))
  esp.poids = 1
  locale ba = rb:ajouter(ui.bouton("Fermer", {annuler = vrai}))
  ba.surclic = @HL_GEN_FERMER
  hlc.gen.compiler = rb:ajouter(ui.bouton("Générer", {defaut = vrai}))
  hlc.gen.compiler.surclic = @HL_GEN_COMPILER
finprocedure

procedure HL_GEN_ICONE
  locale p = ui.ouvrirfichier{titre = "Icône de l'application", dossier = hl.dossier, ;
                              filtre = "Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tga"}
  si p <> nul
    hlc.gen.cheminicone = p
    hlc.gen.icone.libelle = p
  finsi
finprocedure

procedure HL_GEN_COMPILER
  locale c = {}
  pour i = 1 a 6
    si hlc.gen.cibles:coche(i)
      inserer(c, HL_CIBLES()[i].id)
    finsi
  suivant
  si #c = 0
    hlc.gen.etat.libelle = "Choisissez au moins une cible."
    retourner
  finsi
  locale archive = hlc.gen.options:coche(1)
  locale biblios = hlc.gen.options:coche(2)
  && mêmes réglages que la boîte de l'atelier wdlexis+
  locale ini = {"# wdlexis+ : paramètres de génération de l'application", "type=graphique", ;
                "cibles=" + joindre(c, ","), "distribution=" + sisinon(archive, "archive", "dossier"), ;
                "bibliotheques=" + sisinon(biblios, "1", "0"), "icone=" + (hlc.gen.cheminicone ou ""), ;
                "cadrage=" + (HL_LIRE_INI().cadrage ou "")}
  fichier.ecrire(HL_P(".wdlexis/application.ini"), joindre(ini, NL()) + NL())
  locale outil = lexis.outil("wdlexisgen")
  si outil = nul
    hlc.gen.etat.libelle = "Outil wdlexisgen introuvable à côté du runtime : réglages enregistrés (.wdlexis/application.ini)."
    HL_MESSAGE_JOURNAL("wdlexisgen introuvable. Depuis un terminal : wdlexisgen " + Q() + hl.dossier + Q())
    retourner
  finsi
  locale cmd = Q() + outil + Q() + " " + Q() + hl.dossier + Q() + " --type=graphique --cibles=" + joindre(c, ",") + ;
               " --principal=principal.prg"
  si archive
    cmd = cmd + " --archive"
  finsi
  si non biblios
    cmd = cmd + " --sans-bibliotheques"
  finsi
  si hlc.gen.cheminicone <> nul et hlc.gen.cheminicone <> ""
    cmd = cmd + " --icone=" + Q() + hlc.gen.cheminicone + Q()
  finsi
  hlc.gen.compiler.actif = faux
  hlc.gen.etat.libelle = "Génération en cours… (le détail s'affiche dans la boîte de messages)"
  locale r = systeme.capturer(cmd)
  HL_MESSAGE_JOURNAL("$ " + cmd + NL() + r.sortie)
  HL_ONGLET("messages")
  si hlc.gen <> nul
    hlc.gen.compiler.actif = vrai
    hlc.gen.etat.libelle = sisinon(r.code = 0, "Application générée : dossier distribution/ de la pile.", ;
                                   "Échec de la génération (code " + r.code + ") : voir la boîte de messages.")
  finsi
finprocedure

procedure HL_GEN_FERMER
  si hlc.gen <> nul
    hlc.gen.fen:fermer()
  finsi
  hlc.gen = nul
finprocedure

procedure HL_GEN_FERMETURE(ev)
  hlc.gen = nul
finprocedure
