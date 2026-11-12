&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ écrit en Lexis+ : la même interface que wdlexis+.
&&
&&   wdlexisrt principal.prg [dossier_du_projet]
&&
&& Fichiers du projet (le runtime les charge tous) :
&&   principal.prg   les deux fenêtres (outils, documents), réglages, démarrage
&&   projet.prg      projet, fichiers, session
&&   edition.prg     analyse, problèmes, structure, recherche, définition,
&&                   pastilles des onglets et fenêtre Blueprint
&&   vueprojet.prg   vue projet : graphe du projet, une colonne par fichier
&&   execution.prg   exécution, débogage, console, variables, pile d'appels
&&   reference.prg   référence des fonctions et paquets (fiches Markdown)
&&   generation.prg  boîte « Générer l'application » (outil wdlexisgen)
&&   concepteur.prg  concepteur de formulaires (form_<nom>.prg)
&&   etats.prg       éditeur d'états PDF (etat_<nom>.prg, paquet rapport)
&&   menus.prg       menus, raccourcis, aide
&&   panneaux.prg    ensembles de pages : masquer / afficher, fenêtre dédiée
&&
&& L'éditeur (ui.editeur), sa fenêtre Blueprint (ui.blueprint), l'analyse et
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
vpfen = nul             && fenêtre « Vue projet » (vueprojet.prg)
vpdia = nul             && son diagramme
vpetat = nul            && sa barre d'état
vpinfos = {}            && fichier, ligne et détails de chaque nœud
vpliens = {}            && liens d'appel affichés {id, de, a, croise}
vpappels = vrai         && liens d'appel affichés ou masqués
outils = nul            && fenêtre principale une fois l'ensemble Projet / Structure / Référence construit
fenpdf = {}             && fenêtres de consultation PDF ouvertes
ensembles = {}          && ensembles de pages (panneaux.prg) : GAUCHE, BAS, PALETTE, PALETTEETAT
lignesvars = {}         && page Variables : variables affichées (pour la modification en pause)
cadrevars = 1           && cadre de pile affiché
varchoisie = nul        && rang de la variable choisie

&& Une fenêtre compacte : menu et barre de symboles collés en haut, état collé en bas ;
&& à gauche Projet / Structure / Référence, en bas Problèmes / Console / Variables /
&& Pile d'appels (chaque ensemble se masque << >> ou s'ouvre dans une fenêtre dédiée).
fen = ui.fenetre{titre = "wdlexis+ [S]tudio 1.9.2", largeur = 1500, hauteur = 900, disposition = "bordure", ;
                 sombre = reglages.sombre, densite = "compacte", x = 40, y = 40}
fen.marge = 0
fen.espacement = 0
fen.surfermeture = @FERMETURE
fen.surtouchebas = @TOUCHE_FENETRE      && F5, F9, F10, F11 depuis n'importe quel contrôle

&& menus et barre d'outils (symboles ; libellés et raccourcis en infobulle)
haut = fen:ajouter(ui.colonne())
haut.ancrage = "haut"
haut.marge = 0
haut.espacement = 0
menu = haut:ajouter(ui.barremenu())
CONSTRUIRE_MENUS(menu)
menu.surselection = @MENU

barre = haut:ajouter(ui.rangee())
barre.marge = 2
barre.espacement = 1
boutons = {}
BOUTON("ouvrir", "ouvrir", "Ouvrir…", "ouvrir un fichier", @OUVRIR_FICHIER)
BOUTON("nouveau", "nouveau", "Nouveau", "nouveau fichier dans le projet", @NOUVEAU_FICHIER)
BOUTON("enregistrer", "enregistrer", "Enregistrer", "Ctrl+S", @ENREGISTRER)
ESPACE(barre, 8)
BOUTON("verifier", "verifier", "Vérifier", "analyser les fichiers ouverts", @VERIFIER_TOUT)
BOUTON("executer", "executer", "Exécuter", "Ctrl+R : exécution directe", @EXECUTER)
BOUTON("deboguer", "deboguer", "Déboguer", "F5 : jusqu'au prochain point d'arrêt", @DEBOGUER)
ESPACE(barre, 8)
BOUTON("continuer", "continuer", "Continuer", "F5 (en pause)", @CONTINUER)
BOUTON("pas", "pasapas", "Pas à pas", "F11 : entrer dans les procédures", @PAS)
BOUTON("passer", "pasprincipal", "Pas principal", "F10 : passer par-dessus les appels", @PASSER)
BOUTON("sortir", "sortir", "Sortir", "Maj+F11 : terminer la procédure en cours", @SORTIR)
BOUTON("pause", "pause", "Pause", "interrompre à la prochaine instruction", @PAUSE_DEMANDEE)
BOUTON("arreter", "arreter", "Arrêter", "Maj+F5", @ARRETER)
ESPACE(barre, nul)
bgauche = OUTIL_SYMBOLE(barre, "masquer", "Projet / Structure / Référence", "", @GAUCHE_BASCULER)
bfengauche = OUTIL_SYMBOLE(barre, "fenetre", "Projet / Structure / Référence", "", @GAUCHE_FENETRE)
ESPACE(barre, 8)
bbas = OUTIL_SYMBOLE(barre, "descendre", "Problèmes / Console / Variables / Pile d'appels", "", @BAS_BASCULER)
bfenbas = OUTIL_SYMBOLE(barre, "fenetre", "Problèmes / Console / Variables / Pile d'appels", "", @BAS_FENETRE)

&& barre d'état (collée au bas de la fenêtre)
pied = fen:ajouter(ui.rangee())
pied.ancrage = "bas"
pied.marge = 0
pied.hauteurfixe = 20
etat = pied:ajouter(ui.etiquette(" Prêt"))
etat.poids = 1
lblpos = pied:ajouter(ui.etiquette("Ln 1, Col 1"))
lblpos.largeurfixe = 130

&& Projet / Structure / Référence (à gauche) | documents au-dessus des panneaux d'exécution
sepg = fen:ajouter(ui.separateur{vertical = vrai, position = 0.22})
sepg.ancrage = "centre"
hotegauche = sepg:ajouter(ui.conteneur("bordure"))
hotegauche.marge = 0
CONSTRUIRE_OUTILS()

&& documents (un onglet par document, pastille de couleur selon sa nature :
&& rouge code, orange formulaire, jaune état, vert aperçu Markdown, violet image ;
&& la pastille rouge ouvre la fenêtre Blueprint), puis Problèmes / Console / Variables / Pile d'appels
cotedroit = sepg:ajouter(ui.separateur{vertical = faux, position = 0.72})
ed = ui.editeur{minicarte = reglages.minicarte, taille = reglages.police}
ed.surchangement = @MODIFIE
ed.surselection = @SIGNAL
vb = cotedroit:ajouter(ui.blueprint(ed, {sombre = reglages.sombre, densite = "compacte"}))   && éditeur (+ fenêtre Blueprint)
vb.surselection = @SIGNAL_BLUEPRINT

hotebas = cotedroit:ajouter(ui.conteneur("bordure"))
hotebas.marge = 0
bas = hotebas:ajouter(ui.onglets())
bas.ancrage = "centre"
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
rangcons = pcons:ajouter(ui.rangee())
rangcons.ancrage = "haut"
rangcons.marge = 1
OUTIL_SYMBOLE(rangcons, "copier", "Copier", "copier tout le contenu de la console", @COPIER_CONSOLE)
OUTIL_SYMBOLE(rangcons, "effacer", "Effacer", "vider la console", @EFFACER_CONSOLE)
ESPACE(rangcons, nul)
rangsaisie = pcons:ajouter(ui.rangee())
rangsaisie.ancrage = "bas"
rangsaisie.marge = 1
entree = rangsaisie:ajouter(ui.saisie{indication = "Saisie pour saisir() ou es.lire() (Entrée pour envoyer)"})
entree.poids = 1
entree.surtouchebas = @TOUCHE
benvoi = OUTIL_SYMBOLE(rangsaisie, "envoyer", "Envoyer", "envoie la ligne au programme", @ENVOYER)
console = pcons:ajouter(ui.saisie{multiligne = vrai})
console.ancrage = "centre"

pvars = bas:ajouterpage("Variables", "bordure")
rangvar = pvars:ajouter(ui.rangee())
rangvar.ancrage = "bas"
rangvar.marge = 1
lblvar = rangvar:ajouter(ui.etiquette("Choisir une variable (en pause) pour modifier sa valeur :"))
saisievar = rangvar:ajouter(ui.saisie{indication = "nouvelle valeur (Entrée pour appliquer)"})
saisievar.poids = 1
saisievar.actif = faux
saisievar.surtouchebas = @VARIABLE_TOUCHE
bvar = OUTIL_SYMBOLE(rangvar, "verifier", "Appliquer", "affecte la nouvelle valeur à la variable (Entrée)", @VARIABLE_APPLIQUER)
bvar.actif = faux
tvars = pvars:ajouter(ui.tableau())
tvars.ancrage = "centre"
tvars:ajoutercolonne("Nom", 160)
tvars:ajoutercolonne("Valeur", 520)
tvars:ajoutercolonne("Type", 90)
tvars:ajoutercolonne("Portée", 90)
tvars.surselection = @VARIABLE_CHOISIE
tvars.surdoubleclic = @VARIABLE_CHOISIE

ppile = bas:ajouterpage("Pile d'appels")
lpile = ppile:ajouter(ui.liste())
lpile.poids = 1
lpile.surselection = @CADRE

&& ensembles de pages : masquer / afficher (<< >>) et fenêtre dédiée, comme Atlas SQL
ENSEMBLE("gauche", "Projet / Structure / Référence", hotegauche, pagesoutils, bgauche, bfengauche, ;
         380, 860, "masquer", "afficher")
ENSEMBLE("bas", "Problèmes / Console / Variables / Pile d'appels", hotebas, bas, bbas, bfenbas, ;
         1000, 360, "descendre", "monter")
si reglages.gauchemasque
  ENSEMBLE_MASQUER(ensembles.gauche, vrai)
finsi
si reglages.basmasque
  ENSEMBLE_MASQUER(ensembles.bas, vrai)
finsi

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
  locale r = {sombre = vrai, minicarte = vrai, police = 14, globales = vrai, appelsinconnus = vrai, projet = "", gauchemasque = faux, basmasque = faux}
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

procedure BOUTON(nom, icone, libelle, bulle, proc)
  boutons[majuscule(nom)] = OUTIL_SYMBOLE(barre, icone, libelle, bulle, proc)
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
&& Ensemble Projet, Structure, Référence (à gauche de la fenêtre principale ; il se
&& masque ou s'ouvre dans une fenêtre dédiée, voir panneaux.prg)
&&

procedure CONSTRUIRE_OUTILS
  globale outils, pagesoutils, arbre, arbrestruct, aref, fiche, rechref
  outils = fen            && compatibilité : « outils = nul » signifiait « fenêtre fermée »
  pagesoutils = hotegauche:ajouter(ui.onglets())
  pagesoutils.ancrage = "centre"
  locale pprojet = pagesoutils:ajouterpage("Projet", "bordure")
  && Dupliquer, Renommer, Supprimer : en haut à gauche de la page Projet
  locale bproj = pprojet:ajouter(ui.rangee())
  bproj.ancrage = "haut"
  bproj.marge = 1
  bproj.espacement = 1
  OUTIL_SYMBOLE(bproj, "dupliquer", "Dupliquer", "copie du fichier choisi avec le suffixe 1, 2… (après confirmation)", ;
                @FICHIER_DUPLIQUER)
  OUTIL_SYMBOLE(bproj, "renommer", "Renommer", "donner un nouveau nom au fichier choisi", @FICHIER_RENOMMER)
  OUTIL_SYMBOLE(bproj, "supprimer", "Supprimer", "supprimer le fichier choisi (après confirmation)", @FICHIER_SUPPRIMER)
  ESPACE(bproj, nul)
  arbre = pprojet:ajouter(ui.arbre())
  arbre.ancrage = "centre"
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
retourner

procedure AFFICHER_OUTILS(page)
  && Affichage > Projet / Structure / Référence, Aide > Référence : l'ensemble réapparaît
  AFFICHER_ENSEMBLE("gauche")
  si page <> nul
    pagesoutils.valeur = page
  finsi
retourner

procedure FERMETURE(ev)
  ENREGISTRER_SESSION()
  reglages.gauchemasque = ensembles.gauche.masque
  reglages.basmasque = ensembles.bas.masque
  ECRIRE_REGLAGES()
  pour chaque k, e dans ensembles
    si e.fen <> nul
      essayer
        e.fen:fermer()
      capturer err
      finessayer
    finsi
  suivant
  pour chaque f dans fenpdf
    essayer
      f:fermer()
    capturer err
    finessayer
  suivant
  si condlg <> nul
    condlg:fermer()
  finsi
  si vpfen <> nul
    vpfen:fermer()
  finsi
  vb:fermer()               && fenêtre Blueprint
  si etdlg <> nul
    etdlg:fermer()
  finsi
  si execution <> nul
    execution:arreter()
  finsi
retourner
