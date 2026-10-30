&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ écrit en Lexis+ : la même interface que wdlexis+.
&&
&&   wdlexisrt principal.prg [dossier_du_projet]
&&
&& Fichiers du projet (le runtime les charge tous) :
&&   principal.prg   les deux fenêtres (outils, documents), réglages, démarrage
&&   projet.prg      projet, fichiers, session
&&   edition.prg     analyse, problèmes, structure, recherche, définition,
&&                   pastilles des onglets et vue blueprint
&&   execution.prg   exécution, débogage, console, variables, pile d'appels
&&   reference.prg   référence des fonctions et paquets (fiches Markdown)
&&   generation.prg  boîte « Générer l'application » (outil wdlexisgen)
&&   concepteur.prg  concepteur de formulaires (form_<nom>.prg)
&&   etats.prg       éditeur d'états PDF (etat_<nom>.prg, paquet rapport)
&&   menus.prg       menus, raccourcis, aide
&&
&& L'éditeur (ui.editeur), sa vue blueprint (ui.blueprint), l'analyse et
&& l'exécution (paquet lexis) sont natifs ; tout le reste est ici.
ui = paquet("interface")

&& état partagé par les gestionnaires
reglages = LIRE_REGLAGES()
dossier = ""
problemes = {}          && lignes affichées dans l'onglet Problèmes
symboles = {}           && Structure : symboles du fichier actif
cheminsstruct = {}      && Structure : ligne de chaque nœud de l'arbre (par chemin)
clestruct = ""          && Structure : empreinte du dernier arbre affiché
execution = nul         && programme en cours (lexis.executer)
pausecourante = nul     && dernière pause du débogueur
analyse = ""            && empreinte de la dernière analyse (coalescence)
recherche = {texte = "", remplacement = "", casse = faux, motentier = faux}
docs = {}               && référence : entrées de lexis.documentation par chemin d'arbre
docsparnom = {}         && référence : entrée par nom (aide sur le mot courant)
refentrees = {}         && référence : entrées triées (paquet, puis signature)
gendlg = nul            && boîte « Générer l'application » ouverte
genctl = {}             && ses contrôles
condlg = nul            && fenêtre du concepteur de formulaires
canevas = nul           && son canevas (ui.concepteur)
conctl = {}             && ses autres contrôles
concode = ""            && fichier de code qui reçoit les procédures du formulaire
etdlg = nul             && fenêtre de l'éditeur d'états
etcanevas = nul         && son canevas (ui.etat)
etctl = {}              && ses autres contrôles
outils = nul            && fenêtre Projet / Structure / Référence (nul : fermée)

&& Deux fenêtres, comme l'atelier natif : les outils à gauche, les documents à droite.
fen = ui.fenetre{titre = "wdlexis+ [S]tudio 1.7.3", largeur = 1320, hauteur = 860, disposition = "bordure", ;
                 sombre = reglages.sombre, x = 408, y = 48}
fen.surfermeture = @FERMETURE
fen.surtouchebas = @TOUCHE_FENETRE      && F5, F9, F10, F11 depuis n'importe quel contrôle

&& menus et barre d'outils
menu = fen:ajouter(ui.barremenu())
CONSTRUIRE_MENUS(menu)
menu.surselection = @MENU

barre = fen:ajouter(ui.rangee())
barre.ancrage = "haut"
boutons = {}
BOUTON("ouvrir", "Ouvrir…", @OUVRIR_FICHIER)
BOUTON("nouveau", "Nouveau", @NOUVEAU_FICHIER)
BOUTON("enregistrer", "Enregistrer", @ENREGISTRER)
BOUTON("verifier", "Vérifier", @VERIFIER_TOUT)
BOUTON("executer", "▶ Exécuter", @EXECUTER)
BOUTON("deboguer", "Déboguer", @DEBOGUER)
BOUTON("continuer", "Continuer", @CONTINUER)
BOUTON("pas", "Pas à pas", @PAS)
BOUTON("passer", "Pas principal", @PASSER)
BOUTON("sortir", "Sortir", @SORTIR)
BOUTON("pause", "Pause", @PAUSE_DEMANDEE)
BOUTON("arreter", "■ Arrêter", @ARRETER)

&& barre d'état
pied = fen:ajouter(ui.rangee())
pied.ancrage = "bas"
etat = pied:ajouter(ui.etiquette("Prêt"))
etat.poids = 1
lblpos = pied:ajouter(ui.etiquette("Ln 1, Col 1"))
lblpos.largeurfixe = 140

&& documents (un onglet par document, pastille de couleur selon sa nature :
&& rouge code, orange formulaire, jaune état, bleu blueprint), puis
&& Problèmes / Console / Variables / Pile d'appels
cotedroit = fen:ajouter(ui.separateur{vertical = faux, position = 0.72})
cotedroit.ancrage = "centre"
ed = ui.editeur{minicarte = reglages.minicarte, taille = reglages.police}
ed.surchangement = @MODIFIE
ed.surselection = @SIGNAL
vb = cotedroit:ajouter(ui.blueprint(ed, {sombre = reglages.sombre}))   && éditeur + vue blueprint
vb.surselection = @SIGNAL_BLUEPRINT

bas = cotedroit:ajouter(ui.onglets())
pprob = bas:ajouterpage("Problèmes")
tprob = pprob:ajouter(ui.tableau())
tprob.poids = 1
tprob:ajoutercolonne("Type", 110)
tprob:ajoutercolonne("Fichier", 140)
tprob:ajoutercolonne("Ligne", 70, "droite")
tprob:ajoutercolonne("Col", 60, "droite")
tprob:ajoutercolonne("Message", 700)
tprob.surselection = @PROBLEME

pcons = bas:ajouterpage("Console", "bordure")
rangsaisie = pcons:ajouter(ui.rangee())
rangsaisie.ancrage = "bas"
entree = rangsaisie:ajouter(ui.saisie{indication = "Saisie pour saisir() ou es.lire() (Entrée pour envoyer)"})
entree.poids = 1
entree.surtouchebas = @TOUCHE
benvoi = rangsaisie:ajouter(ui.bouton("Envoyer"))
benvoi.surclic = @ENVOYER
console = pcons:ajouter(ui.saisie{multiligne = vrai})
console.ancrage = "centre"

pvars = bas:ajouterpage("Variables")
tvars = pvars:ajouter(ui.tableau())
tvars.poids = 1
tvars:ajoutercolonne("Nom", 160)
tvars:ajoutercolonne("Valeur", 520)
tvars:ajoutercolonne("Type", 90)
tvars:ajoutercolonne("Portée", 90)

ppile = bas:ajouterpage("Pile d'appels")
lpile = ppile:ajouter(ui.liste())
lpile.poids = 1
lpile.surselection = @CADRE

CONSTRUIRE_OUTILS()
ETAT_BOUTONS("repos")
&& dossier reste vide jusqu'au chargement : CHARGER_PROJET n'enregistre la session
&& du projet précédent que s'il y en a un.
depart = systeme.args[1]
si depart = nul ou depart = ""
  depart = reglages.projet
finsi
si depart = nul ou depart = "" ou non fichier.estdossier(depart)
  depart = systeme.dossierprogramme()
finsi
CHARGER_PROJET(fichier.absolu(depart))
ui.executer()

&&
&& Réglages (dossier personnel) et barre d'outils
&&

fonction FICHIER_REGLAGES()
retourner fichier.joindre(fichier.dossierperso(), ".wdlexis-atelier.json")

fonction LIRE_REGLAGES()
  locale r = {sombre = vrai, minicarte = vrai, police = 14, globales = vrai, appelsinconnus = vrai, projet = ""}
  locale p = FICHIER_REGLAGES()
  si fichier.existe(p)
    essayer
      pour chaque k, v dans dejson(fichier.lire(p))
        r[majuscule(k)] = v
      suivant
    capturer e
      && réglages illisibles : valeurs par défaut
    finessayer
  finsi
retourner r

procedure ECRIRE_REGLAGES
  reglages.projet = dossier
  essayer
    fichier.ecrire(FICHIER_REGLAGES(), json(reglages))
  capturer e
    etat.libelle = "Réglages non enregistrés : " + e
  finessayer
retourner

procedure BOUTON(nom, libelle, proc)
  locale b = barre:ajouter(ui.bouton(libelle))
  b.surclic = proc
  boutons[majuscule(nom)] = b
retourner

procedure ETAT_BOUTONS(mode)
  && repos : rien ne s'exécute ; execution : en cours ; pause : débogueur arrêté
  boutons.executer.actif = mode = "repos"
  boutons.deboguer.actif = mode = "repos"
  boutons.continuer.actif = mode = "pause"
  boutons.pas.actif = mode = "repos" ou mode = "pause"
  boutons.passer.actif = mode = "pause"
  boutons.sortir.actif = mode = "pause"
  boutons.pause.actif = mode = "execution"
  boutons.arreter.actif = mode <> "repos"
retourner

&&
&& Fenêtre d'outils : Projet, Structure, Référence (refermable, rouverte par le
&& menu Affichage > Fenêtre Projet / Structure / Référence)
&&

procedure CONSTRUIRE_OUTILS
  globale outils, pagesoutils, arbre, arbrestruct, aref, fiche, rechref
  si outils <> nul
    retourner
  finsi
  outils = ui.fenetre{titre = "Projet - wdlexis+ [S]tudio", largeur = 380, hauteur = 860, ;
                      disposition = "bordure", sombre = reglages.sombre, x = 16, y = 48}
  outils.surfermeture = @OUTILS_FERMES
  outils.surtouchebas = @TOUCHE_FENETRE
  pagesoutils = outils:ajouter(ui.onglets())
  pagesoutils.ancrage = "centre"
  locale pprojet = pagesoutils:ajouterpage("Projet")
  arbre = pprojet:ajouter(ui.arbre())
  arbre.poids = 1
  arbre.surselection = @ARBRE
  arbre.surdoubleclic = @ARBRE_DOUBLE     && form_<nom>.prg, etat_<nom>.prg : leur concepteur
  && Structure : fichier > Procédures / Fonctions (variables locales) > Variables globales
  locale pstruct = pagesoutils:ajouterpage("Structure")
  arbrestruct = pstruct:ajouter(ui.arbre())
  arbrestruct.poids = 1
  arbrestruct.surselection = @SYMBOLE
  && Référence : recherche, puis l'arbre des paquets au-dessus de la fiche (séparateur horizontal)
  locale pref = pagesoutils:ajouterpage("Référence", "bordure")
  rechref = pref:ajouter(ui.saisie{indication = "Rechercher (fonction, paquet, description…)"})
  rechref.ancrage = "haut"
  rechref.surchangement = @FILTRER_REFERENCE
  locale sref = pref:ajouter(ui.separateur{vertical = faux, position = 0.55})
  sref.ancrage = "centre"
  aref = sref:ajouter(ui.arbre())
  aref.surselection = @REFERENCE
  aref.surdoubleclic = @INSERER_REFERENCE
  fiche = sref:ajouter(ui.markdown(BIENVENUE_REFERENCE()))
  CHARGER_REFERENCE()
  si dossier <> ""
    ARBRE_PROJET()
  finsi
  clestruct = ""
  si dossier <> ""
    ANALYSER(vrai)
  finsi
retourner

procedure OUTILS_FERMES(ev)
  globale outils
  outils = nul
retourner

procedure AFFICHER_OUTILS(page)
  si outils = nul
    CONSTRUIRE_OUTILS()
  finsi
  si page <> nul
    pagesoutils.valeur = page
  finsi
retourner

procedure FERMETURE(ev)
  ENREGISTRER_SESSION()
  ECRIRE_REGLAGES()
  si outils <> nul
    outils:fermer()
  finsi
  si condlg <> nul
    condlg:fermer()
  finsi
  si etdlg <> nul
    etdlg:fermer()
  finsi
  si execution <> nul
    execution:arreter()
  finsi
retourner
