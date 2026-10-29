&& CC BY-NC-SA 4.0 - HyperLexis, atelier de piles pour Lexis+ (wdlexis+)
&&
&& HyperLexis : un environnement de programmation visuelle à la manière de
&& HyperCard et de LiveCode, écrit en Lexis+.
&&
&&   wdlexisrt principal.prg [dossier_de_la_pile]
&&
&& Une pile est un dossier de projet wdlexis+ ordinaire : elle s'exécute avec
&& wdlexisrt, s'ouvre dans l'atelier wdlexis+ (ou l'atelier écrit en Lexis+) et
&& se compile avec wdlexisgen. Les cartes sont dessinées avec le concepteur de
&& formulaires de wdlexis+ (palette d'outils, poignées, repères), l'inspecteur
&& montre les propriétés et les événements, et l'on bascule à tout moment entre
&& le mode Conception et le mode Exécution, dans la même fenêtre.
&&
&& Fichiers de l'atelier (le runtime les charge tous) :
&&   principal.prg       fenêtre, réglages, démarrage
&&   hl_menus.prg        menus, raccourcis, aide
&&   hl_pile.prg         ouverture, enregistrement, fichiers de la pile
&&   hl_cartes.prg       cartes et modèles (créer, dupliquer, renommer, ordre)
&&   hl_conception.prg   mode Conception : canevas, palette, objets, inspecteur
&&   hl_scripts.prg      scripts : éditeur, analyse, procédures des événements
&&   hl_execution.prg    mode Exécution, boîte de messages, pile autonome, génération
&&   hl_outils.prg       outils communs (textes, JSON du dessin, littéraux Lexis+)
&&   pile_moteur.prg     moteur d'exécution, recopié dans chaque pile
ui = paquet("interface")

&& état de l'atelier (une seule table globale : les scripts de la pile
&& s'exécutent dans le même programme et partagent les variables globales)
hl = {version = "1.0", dossier = "", def = nul, donnees = {}, index = 1, mode = "conception", ;
      canevas = nul, modele = "", reglages = HL_LIRE_REGLAGES(), analyse = "", problemes = {}, ;
      noeuds = {}, lignes = {}, evts = {}, ligneNom = nul, majcombo = faux, historique = {}, ;
      execution = nul, autonome = nul, segments = {}, messages = {}, imessage = 0}
hlc = {}

hlc.fen = ui.fenetre{titre = "HyperLexis", largeur = 1440, hauteur = 900, disposition = "bordure", ;
                     sombre = hl.reglages.sombre}
hlc.fen.surfermeture = @HL_FERMETURE
hlc.fen.surtouchebas = @HL_TOUCHE

&& en haut, comme LiveCode : la barre de menus, et juste dessous la barre de boutons
hlc.entete = hlc.fen:ajouter(ui.superconteneur("vertical"))
hlc.entete.ancrage = "haut"
hlc.entete.espacement = 0
hlc.menu = hlc.entete:ajouter(ui.barremenu())
HL_CONSTRUIRE_MENUS(hlc.menu)
hlc.menu.surselection = @HL_MENU

&& barre de boutons : mode, navigation, cartes, scripts, pile
hlc.barre = hlc.entete:ajouter(ui.superconteneur("horizontal"))
hlc.barre.espacement = 4
hlc.bconception = HL_OUTIL(hlc.barre, "✎ Conception", @HL_MODE_CONCEPTION, "Mode Conception : dessiner la carte (Ctrl+E bascule)")
hlc.bexecution = HL_OUTIL(hlc.barre, "▶ Exécution", @HL_MODE_EXECUTION, "Mode Exécution : la pile fonctionne, ici même (Ctrl+E bascule)")
HL_ESPACE(hlc.barre)
HL_ICONE(hlc.barre, "⏮", @HL_NAV_PREMIERE, "Première carte (Ctrl+Début)")
HL_ICONE(hlc.barre, "◀", @HL_NAV_PRECEDENTE, "Carte précédente (Ctrl+←)")
hlc.ccartes = hlc.barre:ajouter(ui.combo())
hlc.ccartes.largeurfixe = 170
hlc.ccartes.infobulle = "Aller à une carte"
hlc.ccartes.surselection = @HL_COMBO_CARTE
HL_ICONE(hlc.barre, "▶", @HL_NAV_SUIVANTE, "Carte suivante (Ctrl+→)")
HL_ICONE(hlc.barre, "⏭", @HL_NAV_DERNIERE, "Dernière carte (Ctrl+Fin)")
HL_ESPACE(hlc.barre)
HL_OUTIL(hlc.barre, "+ Carte", @HL_NOUVELLE_CARTE_MODELE, "Nouvelle carte avec un nouveau modèle (dessin propre)")
HL_OUTIL(hlc.barre, "+ Même", @HL_NOUVELLE_CARTE_MEME, ;
         "Nouvelle carte sur le modèle de la carte courante (même dessin, données propres) (Ctrl+N)")
HL_ESPACE(hlc.barre)
HL_OUTIL(hlc.barre, "Script carte", @HL_SCRIPT_MODELE, "Ouvre le script du modèle de la carte")
HL_ESPACE(hlc.barre)
HL_OUTIL(hlc.barre, "Enregistrer", @HL_ENREGISTRER_MENU, "Enregistre la pile (Ctrl+S)")
HL_OUTIL(hlc.barre, "▷ Autonome", @HL_AUTONOME, ;
         "Lance la pile enregistrée comme le ferait wdlexisrt, dans sa propre fenêtre")
HL_OUTIL(hlc.barre, "Générer…", @HL_GENERER_DIALOGUE, "Application autonome (wdlexisgen)")

&& barre d'état
hlc.pied = hlc.fen:ajouter(ui.rangee())
hlc.pied.ancrage = "bas"
hlc.etat = hlc.pied:ajouter(ui.etiquette("Prêt"))
hlc.etat.poids = 1
hlc.lblmode = hlc.pied:ajouter(ui.etiquette(""))
hlc.lblmode.largeurfixe = 360

&& au centre : deux pages, Interface (la carte : canevas en Conception, pile réelle
&& en Exécution) et Script (éditeur de code) ; dessous : Messages et Problèmes.
&& À droite, une colonne à onglets : Inspecteur, Pile, Outils, Cartes.
hlc.sep = hlc.fen:ajouter(ui.separateur{vertical = vrai, position = 0.72})
hlc.sepbas = hlc.sep:ajouter(ui.separateur{vertical = faux, position = 0.76})
hlc.onglcentre = hlc.sepbas:ajouter(ui.onglets())
hlc.pinterface = hlc.onglcentre:ajouterpage("Interface")
hlc.conception = hlc.pinterface:ajouter(ui.panneau{defilement = "automatique"})
hlc.conception.poids = 1
hlc.vueexec = hlc.pinterface:ajouter(ui.panneau{defilement = "automatique"})
hlc.vueexec.poids = 1
hlc.vueexec.fond = "#CBD5E1"
hlc.vueexec.visible = faux
hlc.pscript = hlc.onglcentre:ajouterpage("Script", "bordure")
hlc.ed = hlc.pscript:ajouter(ui.editeur{minicarte = faux, taille = hl.reglages.police})
hlc.ed.ancrage = "centre"
hlc.ed.surchangement = @HL_SCRIPT_MODIFIE
hlc.ed.surselection = @HL_SIGNAL_EDITEUR

&& sous l'éditeur : boîte de messages et problèmes
hlc.bas = hlc.sepbas:ajouter(ui.onglets())
hlc.pmessages = hlc.bas:ajouterpage("Messages", "bordure")
locale rm = hlc.pmessages:ajouter(ui.rangee())
rm.ancrage = "bas"
hlc.saisiemsg = rm:ajouter(ui.saisie{indication = "Boîte de messages : commande ou expression Lexis+, ex. ALLER_CARTE(" + ;
                                                 car(34) + "suivante" + car(34) + ") ou NOMBRE_CARTES()  (Entrée)"})
hlc.saisiemsg.poids = 1
hlc.saisiemsg.surtouchebas = @HL_MESSAGE_TOUCHE
HL_OUTIL(rm, "Exécuter", @HL_MESSAGE_ENVOYER, "Exécute la commande (Entrée) ; ↑ / ↓ : historique")
HL_OUTIL(rm, "Effacer", @HL_MESSAGES_EFFACER, "Efface le journal")
hlc.journal = hlc.pmessages:ajouter(ui.liste())
hlc.journal.ancrage = "centre"
hlc.journal.surdoubleclic = @HL_JOURNAL_COPIER
hlc.pprob = hlc.bas:ajouterpage("Problèmes")
hlc.tprob = hlc.pprob:ajouter(ui.tableau())
hlc.tprob.poids = 1
hlc.tprob:ajoutercolonne("Type", 110)
hlc.tprob:ajoutercolonne("Fichier", 170)
hlc.tprob:ajoutercolonne("Ligne", 70, "droite")
hlc.tprob:ajoutercolonne("Message", 900)
hlc.tprob.surselection = @HL_PROBLEME

&& à droite : Inspecteur, Pile, Outils, Cartes
hlc.cotedroit = hlc.sep:ajouter(ui.onglets())
hlc.droite = hlc.cotedroit:ajouterpage("Inspecteur")
hlc.ppile = hlc.cotedroit:ajouterpage("Pile")
hlc.poutils = hlc.cotedroit:ajouterpage("Outils")
hlc.pcartes = hlc.cotedroit:ajouterpage("Cartes")

hlc.droite:ajouter(ui.etiquette("OBJETS DE LA CARTE"))
hlc.arbre = hlc.droite:ajouter(ui.arbre())
hlc.arbre.hauteurfixe = 170
hlc.arbre.surselection = @HL_ARBRE_CHOIX
locale ri = hlc.droite:ajouter(ui.rangee())
HL_OUTIL(ri, "Carte", @HL_SELECTIONNER_CARTE, "Sélectionne la carte (propriétés de la carte et de son modèle)")
HL_ICONE(ri, "⧉", @HL_DUPLIQUER_OBJET, "Duplique l'objet sélectionné (Ctrl+D)")
HL_ICONE(ri, "▲", @HL_OBJET_DESCENDRE, "Plus tard dans l'ordre d'affichage : passe devant")
HL_ICONE(ri, "▼", @HL_OBJET_MONTER, "Plus tôt dans l'ordre d'affichage : passe derrière")
HL_ICONE(ri, "✕", @HL_SUPPRIMER_OBJET, "Supprime l'objet sélectionné (Suppr)")
hlc.titreinsp = hlc.droite:ajouter(ui.etiquette(""))
hlc.titreinsp.couleur = "#2563EB"
hlc.insp = hlc.droite:ajouter(ui.panneau{defilement = "automatique"})
hlc.insp.poids = 1
hlc.contenu = hlc.insp:ajouter(ui.colonne())

locale defpile = hlc.ppile:ajouter(ui.panneau{defilement = "automatique"})
defpile.poids = 1
HL_CONSTRUIRE_PAGE_PILE(defpile:ajouter(ui.colonne()))

hlc.aideoutils = hlc.poutils:ajouter(ui.etiquette("Glissez un outil sur la carte"))
hlc.palette = nul

hlc.lcartes = hlc.pcartes:ajouter(ui.liste())
hlc.lcartes.poids = 1
hlc.lcartes.surselection = @HL_LISTE_CARTE
hlc.lcartes.surdoubleclic = @HL_RENOMMER_CARTE
locale rc = hlc.pcartes:ajouter(ui.rangee())
HL_ICONE(rc, "▲", @HL_CARTE_MONTER, "Avancer la carte dans la pile")
HL_ICONE(rc, "▼", @HL_CARTE_DESCENDRE, "Reculer la carte dans la pile")
HL_ICONE(rc, "⧉", @HL_DUPLIQUER_CARTE, "Dupliquer la carte (même modèle, mêmes données)")
HL_ICONE(rc, "✕", @HL_SUPPRIMER_CARTE, "Supprimer la carte")
HL_OUTIL(rc, "Renommer…", @HL_RENOMMER_CARTE, "Renommer la carte (double-clic)")
HL_OUTIL(rc, "Copier le modèle…", @HL_DUPLIQUER_MODELE, ;
         "Nouvelle carte avec une copie indépendante du modèle (dessin et script)")
hlc.infocartes = hlc.pcartes:ajouter(ui.etiquette(""))

&& démarrage : la pile donnée en argument, sinon la dernière ouverte, sinon l'exemple
HL_MESSAGE_JOURNAL("HyperLexis " + hl.version + " - atelier de piles Lexis+. Aide > Guide pour commencer.")
locale depart = systeme.args[1]
si depart = "--exemple"
  && wdlexisrt principal.prg --exemple <dossier> : crée la pile d'exemple puis l'ouvre
  depart = fichier.absolu(systeme.args[2] ou fichier.joindre(fichier.dossierperso(), "piles", "carnet"))
  si non fichier.existe(fichier.joindre(depart, "pile.prg"))
    HL_CREER_EXEMPLE(depart)
    hl.dossier = ""
  finsi
finsi
si depart = nul ou depart = ""
  depart = hl.reglages.pile
finsi
si depart = nul ou depart = "" ou non fichier.estdossier(depart)
  depart = HL_PILE_EXEMPLE()
finsi
si depart <> "" et fichier.estdossier(depart)
  HL_CHARGER_PILE(fichier.absolu(depart))
sinon
  HL_ETAT("Fichier > Nouvelle pile… pour commencer, ou Fichier > Nouvelle pile d'exemple.")
  HL_MAJ_MODE()
finsi
ui.executer()

&&
&& Réglages (dossier personnel)
&&

fonction HL_DOSSIER_PERSO()
  locale d = fichier.joindre(fichier.dossierperso(), ".hyperlexis")
  si non fichier.existe(d)
    fichier.creerdossier(d)
  finsi
retourner d
finfonction

fonction HL_FICHIER_REGLAGES()
retourner fichier.joindre(HL_DOSSIER_PERSO(), "reglages.json")
finfonction

fonction HL_LIRE_REGLAGES()
  locale r = {sombre = faux, police = 13, pile = "", recentes = {}}
  locale p = HL_FICHIER_REGLAGES()
  si fichier.existe(p)
    essayer
      pour chaque k, v dans dejson(fichier.lire(p))
        r[majuscule(k)] = v
      suivant
    capturer e
    finessayer
  finsi
retourner r
finfonction

procedure HL_ECRIRE_REGLAGES
  hl.reglages.pile = hl.dossier
  si hl.dossier <> ""
    si type(hl.reglages.positions) <> "table"
      hl.reglages.positions = {}
    finsi
    hl.reglages.positions[majuscule(hl.dossier)] = hl.index
  finsi
  essayer
    fichier.ecrire(HL_FICHIER_REGLAGES(), json(hl.reglages))
  capturer e
    HL_ETAT("Réglages non enregistrés : " + e)
  finessayer
finprocedure

fonction HL_OUTIL(barre, libelle, proc, aide)
  locale b = barre:ajouter(ui.bouton(libelle))
  b.surclic = proc
  si aide <> nul
    b.infobulle = aide
  finsi
retourner b
finfonction

fonction HL_ICONE(barre, libelle, proc, aide)
  locale b = HL_OUTIL(barre, libelle, proc, aide)
  b.largeurfixe = 40
retourner b
finfonction

procedure HL_ESPACE(barre)
  locale e = barre:ajouter(ui.etiquette(""))
  e.largeurfixe = 10
finprocedure

procedure HL_ONGLET(nom)
  && pages : au centre Interface / Script ; dessous Messages / Problèmes
  faire cas
  cas nom = "interface"
    hlc.onglcentre.valeur = 1
  cas nom = "script"
    hlc.onglcentre.valeur = 2
  cas nom = "messages"
    hlc.bas.valeur = 1
  cas nom = "problemes"
    hlc.bas.valeur = 2
  fincas
finprocedure

procedure HL_ETAT(message)
  hlc.etat.libelle = message
finprocedure

procedure HL_FERMETURE(ev)
  si hl.mode = "execution"
    HL_MODE_CONCEPTION()
  finsi
  si hl.dossier <> ""
    HL_ENREGISTRER(faux)
  finsi
  HL_ECRIRE_REGLAGES()
  si hl.autonome <> nul et hl.autonome:actif()
    hl.autonome:arreter()
  finsi
finprocedure
