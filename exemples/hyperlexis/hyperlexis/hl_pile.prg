&& CC BY-NC-SA 4.0 - HyperLexis, atelier de piles pour Lexis+ (wdlexis+)
&& hl_pile.prg : ouverture et enregistrement des piles.
&&
&& Une pile est un dossier de projet wdlexis+ :
&&   principal.prg        point d'entrée : PILE_DEMARRER() puis interface.executer()
&&   pile.prg             PILE_DEFINITION() : titre, taille, couleur, ordre des cartes
&&   pile_donnees.prg     PILE_DONNEES_INITIALES() : contenu des champs de chaque carte
&&   pile_donnees.json    même contenu, mis à jour par l'application à l'exécution
&&   pile_moteur.prg      moteur d'exécution (copie de celui de l'atelier)
&&   script_pile.prg      procédures communes (SUR_OUVERTURE_PILE...)
&&   form_<modele>.prg    dessin d'un modèle de carte (concepteur de wdlexis+)
&&   script_<modele>.prg  procédures des événements du modèle
&&   .wdlexis/            réglages de l'atelier wdlexis+ (session, génération)

fonction HL_P(nom)
retourner fichier.joindre(hl.dossier, nom)
finfonction

fonction HL_FORM(modele)
retourner HL_P("form_" + minuscule(modele) + ".prg")
finfonction

fonction HL_SCRIPT(modele)
retourner HL_P("script_" + minuscule(modele) + ".prg")
finfonction

fonction HL_DOSSIER_EXEC()
  && copies chargées par lexis.charger : toujours les mêmes chemins, pour que
  && recharger remplace les procédures (même d'une autre pile)
  locale d = fichier.joindre(HL_DOSSIER_PERSO(), "exec")
  si non fichier.existe(d)
    fichier.creerdossier(d)
  finsi
retourner d
finfonction

fonction HL_PILE_EXEMPLE()
  locale d = fichier.joindre(fichier.dossier(systeme.dossierprogramme()), "piles", "carnet")
  si fichier.estdossier(d) et fichier.existe(fichier.joindre(d, "pile.prg"))
    retourner d
  finsi
retourner ""
finfonction

&&
&& Ouverture
&&

procedure HL_CHARGER_PILE(d)
  si hl.mode = "execution"
    HL_MODE_CONCEPTION()
  finsi
  si hl.dossier <> ""
    HL_ENREGISTRER(faux)
  finsi
  si non fichier.existe(fichier.joindre(d, "pile.prg"))
    si #HL_MODELES_DU_DOSSIER(d) = 0
      ui.alerte("Ce dossier ne contient pas de pile HyperLexis (pile.prg) : " + d + NL() + NL() + ;
                "Fichier > Nouvelle pile… crée une pile ; Carte > Importer un formulaire… y ajoute un " + ;
                "formulaire form_<nom>.prg de wdlexis+.", "information", "Ouvrir une pile")
      retourner
    finsi
    si non ui.confirmer("Ce dossier contient des formulaires wdlexis+ mais pas de pile." + NL() + ;
                        "En faire une pile (une carte par formulaire) ?" + NL() + ;
                        "principal.prg sera remplacé (l'ancien est gardé sous principal_avant_pile.txt).", "question")
      retourner
    finsi
    si fichier.existe(fichier.joindre(d, "principal.prg"))
      fichier.copier(fichier.joindre(d, "principal.prg"), fichier.joindre(d, "principal_avant_pile.txt"))
    finsi
  finsi
  hl.dossier = d
  hl.def = HL_LIRE_DEFINITION()
  hl.donnees = HL_LIRE_DONNEES()
  si hl.donnees._CARTES <> nul
    si #hl.donnees._CARTES > 0
      hl.def.cartes = hl.donnees._CARTES
    finsi
    hl.donnees._CARTES = nul
  finsi
  HL_VERIFIER_CARTES()
  hl.index = 1
  hl.modele = ""
  hl.historique = {}
  && l'éditeur ne garde que les scripts de cette pile
  pour chaque doc dans hlc.ed:documents()
    hlc.ed:fermer(doc.uid)
  suivant
  HL_ENREGISTRER(faux)
  hlc.fen.titre = "HyperLexis - " + (hl.def.titre ou fichier.nom(d)) + "  (" + d + ")"
  HL_MAJ_PAGE_PILE()
  HL_SCRIPT_PILE()
  locale depart = 1
  si type(hl.reglages.positions) = "table" et nombre(hl.reglages.positions[majuscule(d)]) <> nul
    depart = nombre(hl.reglages.positions[majuscule(d)])
  finsi
  HL_ALLER_CONCEPTION(depart)
  HL_ECRIRE_REGLAGES()
  HL_ETAT("Pile ouverte : " + d)
  HL_MESSAGE_JOURNAL("Pile ouverte : " + d)
finprocedure

fonction HL_MODELES_DU_DOSSIER(d)
  locale l = {}
  pour chaque nom dans fichier.liste(d)
    locale n = minuscule(nom)
    si commencepar(n, "form_") et finitpar(n, ".prg")
      inserer(l, souschaine(nom, 6, #nom - 9))
    finsi
  suivant
retourner l
finfonction

fonction HL_DEFINITION_DEFAUT()
retourner {titre = fichier.nom(hl.dossier), largeur = 640, hauteur = 440, couleur = "#FFFFFF", ;
           navigation = vrai, persistance = vrai, version = 1, cartes = {}}
finfonction

fonction HL_LIRE_DEFINITION()
  locale def = nul
  locale p = HL_P("pile.prg")
  si fichier.existe(p)
    locale copie = fichier.joindre(HL_DOSSIER_EXEC(), "definition.prg")
    essayer
      fichier.ecrire(copie, fichier.lire(p))
      lexis.charger(copie)
      def = appeler(lexis.procedure("PILE_DEFINITION"))
    capturer e
      HL_MESSAGE_JOURNAL("[pile.prg illisible] " + e + " : définition reconstruite à partir des formulaires")
      def = nul
    finessayer
  finsi
  locale base = HL_DEFINITION_DEFAUT()
  si def = nul
    def = base
  finsi
  pour chaque k, v dans base
    si def[k] = nul
      def[k] = v
    finsi
  suivant
  && cartes : {nom, modele}
  locale cartes = {}
  pour chaque c dans def.cartes
    si type(c) = "chaine"
      inserer(cartes, {nom = c, modele = c})
    sinonsi type(c) = "table" et c.nom <> nul
      inserer(cartes, {nom = chaine(c.nom), modele = chaine(c.modele ou c.nom)})
    finsi
  suivant
  def.cartes = cartes
retourner def
finfonction

fonction HL_LIRE_DONNEES()
  && pile_donnees.json (dernier état, écrit par l'application ou l'atelier), sinon pile_donnees.prg
  locale pj = HL_P("pile_donnees.json")
  si fichier.existe(pj)
    essayer
      locale d = dejson(fichier.lire(pj))
      si type(d) = "table"
        retourner d
      finsi
    capturer e
      HL_MESSAGE_JOURNAL("[pile_donnees.json illisible] " + e)
    finessayer
  finsi
  locale p = HL_P("pile_donnees.prg")
  si fichier.existe(p)
    locale copie = fichier.joindre(HL_DOSSIER_EXEC(), "donnees.prg")
    essayer
      fichier.ecrire(copie, fichier.lire(p))
      lexis.charger(copie)
      locale d2 = appeler(lexis.procedure("PILE_DONNEES_INITIALES"))
      si type(d2) = "table"
        retourner d2
      finsi
    capturer e
      HL_MESSAGE_JOURNAL("[pile_donnees.prg illisible] " + e)
    finessayer
  finsi
retourner {}
finfonction

procedure HL_VERIFIER_CARTES
  && chaque carte doit avoir son modèle ; chaque modèle du dossier sert au moins une fois
  locale ok = {}
  pour chaque c dans hl.def.cartes
    si fichier.existe(HL_FORM(c.modele))
      inserer(ok, c)
    sinon
      HL_MESSAGE_JOURNAL("[carte ignorée] " + c.nom + " : form_" + c.modele + ".prg introuvable")
    finsi
  suivant
  hl.def.cartes = ok
  pour chaque m dans HL_MODELES_DU_DOSSIER(hl.dossier)
    si HL_CARTES_DU_MODELE(m) = 0
      locale nom = minuscule(m)
      si HL_INDEX_CARTE(nom) > 0
        nom = HL_NOM_CARTE_LIBRE(nom)
      finsi
      inserer(hl.def.cartes, {nom = nom, modele = minuscule(m)})
      HL_PREPARER_MODELE_IMPORTE(minuscule(m))
    finsi
  suivant
  si #hl.def.cartes = 0
    HL_CREER_MODELE("accueil", vrai)
    inserer(hl.def.cartes, {nom = "accueil", modele = "accueil"})
  finsi
finprocedure

&&
&& Nouvelle pile, ouvrir
&&

procedure HL_NOUVELLE_PILE
  locale p = ui.demander("Dossier de la nouvelle pile :", fichier.joindre(fichier.dossierperso(), "piles", "ma_pile"))
  si p = nul ou rogner(p) = ""
    retourner
  finsi
  p = fichier.absolu(rogner(p))
  si fichier.existe(fichier.joindre(p, "pile.prg"))
    si ui.confirmer("Une pile existe déjà dans ce dossier. L'ouvrir ?", "question")
      HL_CHARGER_PILE(p)
    finsi
    retourner
  finsi
  fichier.creerdossier(p)
  locale titre = ui.demander("Titre de la pile :", fichier.nom(p))
  locale ancien = hl.dossier
  si hl.mode = "execution"
    HL_MODE_CONCEPTION()
  finsi
  si ancien <> ""
    HL_ENREGISTRER(faux)
  finsi
  hl.dossier = p
  hl.def = HL_DEFINITION_DEFAUT()
  si titre <> nul et rogner(titre) <> ""
    hl.def.titre = rogner(titre)
  finsi
  hl.donnees = {}
  HL_CREER_MODELE("accueil", vrai)
  inserer(hl.def.cartes, {nom = "accueil", modele = "accueil"})
  hl.dossier = ""
  HL_ECRIRE_FICHIERS_PILE(p)
  HL_CHARGER_PILE(p)
finprocedure

procedure HL_OUVRIR_PILE
  locale p = ui.ouvrirfichier{titre = "Ouvrir une pile (pile.prg ou principal.prg)", dossier = hl.dossier, ;
                              filtre = "Pile HyperLexis|pile.prg;principal.prg|Lexis+|*.prg|Tous les fichiers|*"}
  si p <> nul
    HL_CHARGER_PILE(fichier.absolu(fichier.dossier(p)))
  finsi
finprocedure

procedure HL_OUVRIR_DOSSIER
  locale p = ui.demander("Chemin du dossier de la pile :", hl.dossier)
  si p <> nul et rogner(p) <> ""
    si fichier.estdossier(rogner(p))
      HL_CHARGER_PILE(fichier.absolu(rogner(p)))
    sinon
      ui.alerte("Dossier introuvable : " + p, "attention")
    finsi
  finsi
finprocedure

procedure HL_ENREGISTRER_SOUS
  && copie de la pile dans un autre dossier, qui devient la pile ouverte
  si hl.dossier = ""
    retourner
  finsi
  locale p = ui.demander("Enregistrer une copie de la pile dans le dossier :", hl.dossier + "_copie")
  si p = nul ou rogner(p) = ""
    retourner
  finsi
  p = fichier.absolu(rogner(p))
  si fichier.existe(p) et #fichier.liste(p) > 0
    ui.alerte("Ce dossier existe déjà et n'est pas vide : " + p, "attention")
    retourner
  finsi
  HL_ENREGISTRER(faux)
  fichier.creerdossier(p)
  pour chaque nom dans fichier.liste(hl.dossier)
    si non finitpar(nom, "/") et minuscule(nom) <> "donnees.duckdb"
      fichier.copier(HL_P(nom), fichier.joindre(p, nom))
    finsi
  suivant
  si fichier.estdossier(HL_P(".wdlexis"))
    fichier.copier(HL_P(".wdlexis"), fichier.joindre(p, ".wdlexis"))
  finsi
  HL_CHARGER_PILE(p)
finprocedure

&&
&& Enregistrement
&&

procedure HL_ENREGISTRER_MENU
  HL_ENREGISTRER(vrai)
finprocedure

procedure HL_ENREGISTRER(annoncer)
  si hl.dossier = "" ou hl.def = nul
    retourner
  finsi
  && données de la carte affichée (mode Exécution)
  si hl.mode = "execution" et MOTEUR_ACTIF()
    MOTEUR_CAPTURER()
  finsi
  HL_ENREGISTRER_DESSIN()
  HL_ENREGISTRER_SCRIPTS()
  HL_ECRIRE_FICHIERS_PILE(hl.dossier)
  si annoncer
    HL_ETAT("Pile enregistrée : " + hl.dossier)
  finsi
finprocedure

procedure HL_ECRIRE_FICHIERS_PILE(d)
  && définition, données, moteur, point d'entrée, réglages wdlexis+
  fichier.ecrire(fichier.joindre(d, "pile.prg"), HL_TEXTE_DEFINITION())
  locale dj = json(hl.donnees)
  fichier.ecrire(fichier.joindre(d, "pile_donnees.prg"), HL_TEXTE_DONNEES(dj))
  fichier.ecrire(fichier.joindre(d, "pile_donnees.json"), dj)
  locale moteur = HL_LIRE(fichier.joindre(systeme.dossierprogramme(), "pile_moteur.prg"))
  si moteur <> "" et HL_LIRE(fichier.joindre(d, "pile_moteur.prg")) <> moteur
    fichier.ecrire(fichier.joindre(d, "pile_moteur.prg"), moteur)
  finsi
  locale pp = fichier.joindre(d, "principal.prg")
  si non fichier.existe(pp) ou non ("PILE_DEMARRER()" $ HL_LIRE(pp))
    fichier.ecrire(pp, HL_TEXTE_PRINCIPAL())
  finsi
  si non fichier.existe(fichier.joindre(d, "script_pile.prg"))
    fichier.ecrire(fichier.joindre(d, "script_pile.prg"), HL_TEXTE_SCRIPT_PILE())
  finsi
  si non fichier.existe(fichier.joindre(d, "LISEZMOI.md"))
    fichier.ecrire(fichier.joindre(d, "LISEZMOI.md"), HL_TEXTE_LISEZMOI())
  finsi
  locale w = fichier.joindre(d, ".wdlexis")
  fichier.creerdossier(w)
  si non fichier.existe(fichier.joindre(w, "application.ini"))
    fichier.ecrire(fichier.joindre(w, "application.ini"), HL_TEXTE_INI(""))
  finsi
  && session de l'atelier wdlexis+ : les scripts de la pile ouverts
  locale fichiers = {fichier.joindre(d, "principal.prg"), fichier.joindre(d, "script_pile.prg")}
  pour chaque m dans HL_MODELES()
    inserer(fichiers, fichier.joindre(d, "script_" + m + ".prg"))
  suivant
  locale session = {fichiers = fichiers, actif = fichier.joindre(d, "principal.prg"), arguments = "", principal = "principal.prg"}
  locale ps = fichier.joindre(w, "atelier.json")
  si fichier.existe(ps)
    essayer
      locale ancienne = dejson(fichier.lire(ps))
      session.arguments = ancienne.arguments ou ""
      session.principal = ancienne.principal ou "principal.prg"
    capturer e
    finessayer
  finsi
  fichier.ecrire(ps, json(session))
finprocedure

fonction HL_MODELES()
  && modèles utilisés, dans l'ordre de la pile
  locale l = {}
  locale vus = {}
  pour chaque c dans hl.def.cartes
    si vus[majuscule(c.modele)] = nul
      vus[majuscule(c.modele)] = vrai
      inserer(l, minuscule(c.modele))
    finsi
  suivant
retourner l
finfonction

fonction HL_TEXTE_DEFINITION()
  locale d = hl.def
  locale cartes = {}
  pour chaque c dans d.cartes
    inserer(cartes, "    {nom = " + HL_CHAINE(c.nom) + ", modele = " + HL_CHAINE(c.modele) + "}")
  suivant
  locale l = {}
  inserer(l, "&& Pile « " + d.titre + " » : définition écrite par HyperLexis (atelier de piles Lexis+).")
  inserer(l, "&& Modifiable à la main : titre, taille des cartes, couleur de fond, barre de navigation,")
  inserer(l, "&& persistance des données (pile_donnees.json) et ordre des cartes. Chaque carte utilise")
  inserer(l, "&& un modèle : son dessin form_<modele>.prg et son script script_<modele>.prg.")
  inserer(l, "")
  inserer(l, "fonction PILE_DEFINITION()")
  inserer(l, "retourner {")
  inserer(l, "  titre = " + HL_CHAINE(d.titre) + ",")
  inserer(l, "  largeur = " + entier(nombre(d.largeur) ou 640) + ", hauteur = " + entier(nombre(d.hauteur) ou 440) + ",")
  inserer(l, "  couleur = " + HL_CHAINE(d.couleur ou "#FFFFFF") + ",")
  inserer(l, "  navigation = " + sisinon(d.navigation <> faux, "vrai", "faux") + ", persistance = " + ;
             sisinon(d.persistance <> faux, "vrai", "faux") + ", version = 1,")
  inserer(l, "  cartes = {")
  inserer(l, joindre(cartes, "," + NL()))
  inserer(l, "  }")
  inserer(l, "}")
  inserer(l, "finfonction")
retourner joindre(l, NL()) + NL()
finfonction

fonction HL_TEXTE_DONNEES(dj)
  locale l = {}
  inserer(l, "&& Pile « " + hl.def.titre + " » : données des cartes (contenu des champs), écrites par HyperLexis.")
  inserer(l, "&& Elles servent au premier lancement ; l'application garde ensuite son état dans")
  inserer(l, "&& pile_donnees.json (à côté du programme) si la persistance est active (pile.prg).")
  inserer(l, "&& Clefs : NOMCARTE -> {NOMCONTROLE -> valeur} ; _PILE -> données de FIXER_DONNEE().")
  inserer(l, "")
  inserer(l, "fonction PILE_DONNEES_INITIALES()")
  inserer(l, "retourner dejson(" + HL_CHAINE(dj) + ")")
  inserer(l, "finfonction")
retourner joindre(l, NL()) + NL()
finfonction

fonction HL_TEXTE_PRINCIPAL()
  locale l = {}
  inserer(l, "&& Pile « " + hl.def.titre + " » - créée avec HyperLexis (atelier de piles Lexis+).")
  inserer(l, "&&")
  inserer(l, "&&   wdlexisrt principal.prg            exécute la pile")
  inserer(l, "&&   wdlexisgen <dossier de la pile>    application autonome (Linux, macOS, Windows)")
  inserer(l, "&&")
  inserer(l, "&& Le programme principal ouvre la pile ; le reste est dans les autres fichiers")
  inserer(l, "&& (chargés automatiquement) : pile.prg, pile_donnees.prg, pile_moteur.prg,")
  inserer(l, "&& script_pile.prg, et pour chaque modèle de carte form_<modele>.prg (dessin, à")
  inserer(l, "&& modifier avec le concepteur de formulaires) et script_<modele>.prg (procédures).")
  inserer(l, "")
  inserer(l, "PILE_DEMARRER()")
  inserer(l, "interface.executer()")
retourner joindre(l, NL()) + NL()
finfonction

fonction HL_TEXTE_SCRIPT_PILE()
  locale l = {}
  inserer(l, "&& Script de la pile : procédures communes à toutes les cartes.")
  inserer(l, "&& Procédures facultatives appelées par le moteur (pile_moteur.prg) :")
  inserer(l, "&&   SUR_OUVERTURE_PILE()        au lancement de la pile")
  inserer(l, "&&   SUR_FERMETURE_PILE()        à sa fermeture")
  inserer(l, "&&   SUR_OUVERTURE_CARTE(nom)    à chaque carte affichée")
  inserer(l, "&&   SUR_FERMETURE_CARTE(nom)    quand on quitte une carte")
  inserer(l, "&& Fonctions du moteur : ALLER_CARTE, CARTE_SUIVANTE, CARTE_PRECEDENTE, PREMIERE_CARTE,")
  inserer(l, "&& DERNIERE_CARTE, CARTE_RETOUR, CARTE_COURANTE, NUMERO_CARTE, NOMBRE_CARTES, NOUVELLE_CARTE,")
  inserer(l, "&& SUPPRIMER_CARTE, CONTROLE, CHAMP, FIXER_CHAMP, DONNEE, FIXER_DONNEE, TROUVER, MESSAGE.")
  inserer(l, "")
  inserer(l, "procedure SUR_OUVERTURE_PILE")
  inserer(l, "  && MESSAGE(" + Q() + "Bienvenue" + Q() + ")")
  inserer(l, "finprocedure")
retourner joindre(l, NL()) + NL()
finfonction

fonction HL_TEXTE_SCRIPT_MODELE(modele)
  locale l = {}
  inserer(l, "&& Script du modèle de carte « " + modele + " » (HyperLexis) : procédures des événements.")
  inserer(l, "&& Les contrôles de la carte affichée sont dans " + HL_VAR_FORMULAIRE(modele) + " (" + ;
             HL_VAR_FORMULAIRE(modele) + ".nom.valeur…) ;")
  inserer(l, "&& CARTE_COURANTE() donne le nom de la carte (plusieurs cartes peuvent partager ce modèle).")
retourner HL_ASSURER_BLOC(joindre(l, NL()) + NL(), modele)
finfonction

fonction HL_TEXTE_INI(cibles)
  locale plat = systeme.plateforme()
  si cibles = nul ou cibles = ""
    cibles = sisinon(plat = "windows", "windows-x64", sisinon(plat = "macosx", "macos-arm64", "linux-x64"))
  finsi
retourner "# wdlexis+ : paramètres de génération de l'application" + NL() + "type=graphique" + NL() + ;
          "cibles=" + cibles + NL() + "distribution=dossier" + NL() + "bibliotheques=1" + NL() + ;
          "icone=" + NL() + "cadrage=" + NL()
finfonction

fonction HL_TEXTE_LISEZMOI()
  locale l = {}
  inserer(l, "# " + hl.def.titre)
  inserer(l, "")
  inserer(l, "Pile créée avec **HyperLexis**, l'atelier de piles de cartes pour Lexis+.")
  inserer(l, "")
  inserer(l, "```")
  inserer(l, "wdlexisrt principal.prg          # exécuter la pile")
  inserer(l, "wdlexisgen .                     # générer l'application autonome")
  inserer(l, "wdlexisrt <hyperlexis>/principal.prg .   # la modifier dans HyperLexis")
  inserer(l, "```")
  inserer(l, "")
  inserer(l, "| Fichier | Rôle |")
  inserer(l, "| --- | --- |")
  inserer(l, "| `principal.prg` | point d'entrée : `PILE_DEMARRER()` |")
  inserer(l, "| `pile.prg` | titre, taille, ordre des cartes et modèle de chacune |")
  inserer(l, "| `pile_donnees.prg` / `.json` | contenu des champs de chaque carte |")
  inserer(l, "| `form_<modele>.prg` | dessin d'un modèle (concepteur de formulaires de wdlexis+) |")
  inserer(l, "| `script_<modele>.prg` | procédures des événements du modèle |")
  inserer(l, "| `script_pile.prg` | procédures communes |")
  inserer(l, "| `pile_moteur.prg` | moteur d'exécution (recopié par HyperLexis) |")
retourner joindre(l, NL()) + NL()
finfonction
