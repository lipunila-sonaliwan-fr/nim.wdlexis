&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ écrit en Lexis+ : la même interface que wdlexis+.
&&
&&   wdlexisrt principal.prg [dossier_du_projet]
&&
&& Fichiers du projet (le runtime les charge tous) :
&&   principal.prg   interface, réglages, démarrage
&&   projet.prg      projet, fichiers, session
&&   edition.prg     analyse, problèmes, structure, recherche, définition
&&   execution.prg   exécution, débogage, console, variables, pile d'appels
&&   reference.prg   référence des fonctions et paquets (fiches Markdown)
&&   generation.prg  boîte « Générer l'application » (outil wdlexisgen)
&&   concepteur.prg  concepteur de formulaires (form_<nom>.prg)
&&   etats.prg       éditeur d'états PDF (etat_<nom>.prg, paquet rapport)
&&   menus.prg       menus, raccourcis, aide
&&
&& L'éditeur (ui.editeur), l'analyse et l'exécution (paquet lexis) sont natifs ;
&& tout le reste est ici.
ui = paquet("interface")

&& état partagé par les gestionnaires
reglages = LIRE_REGLAGES()
dossier = ""
problemes = {}          && lignes affichées dans l'onglet Problèmes
symboles = {}           && lignes de l'onglet Structure
execution = nul         && programme en cours (lexis.executer)
pausecourante = nul     && dernière pause du débogueur
analyse = ""            && empreinte de la dernière analyse (coalescence)
recherche = {texte = "", remplacement = "", casse = faux, motentier = faux}
docs = {}               && référence : entrées de lexis.documentation par chemin d'arbre
docsparnom = {}         && référence : entrée par nom (aide sur le mot courant)
gendlg = nul            && boîte « Générer l'application » ouverte
genctl = {}             && ses contrôles
condlg = nul            && fenêtre du concepteur de formulaires
canevas = nul           && son canevas (ui.concepteur)
conctl = {}             && ses autres contrôles
concode = ""            && fichier de code qui reçoit les procédures du formulaire
etdlg = nul             && fenêtre de l'éditeur d'états
etcanevas = nul         && son canevas (ui.etat)
etctl = {}              && ses autres contrôles

fen = ui.fenetre{titre = "wdlexis+ [S]tudio 1.7.3", largeur = 1320, hauteur = 860, disposition = "bordure", ;
                 sombre = reglages.sombre}
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

sep = fen:ajouter(ui.separateur{vertical = vrai, position = 0.22})

&& à gauche : Projet, Structure, Référence
gauche = sep:ajouter(ui.onglets())
pprojet = gauche:ajouterpage("Projet")
arbre = pprojet:ajouter(ui.arbre())
arbre.poids = 1
arbre.surselection = @ARBRE
arbre.surdoubleclic = @ARBRE_DOUBLE     && form_<nom>.prg : concepteur de formulaires
pstruct = gauche:ajouterpage("Structure")
lstruct = pstruct:ajouter(ui.liste())
lstruct.poids = 1
lstruct.surselection = @SYMBOLE
pref = gauche:ajouterpage("Référence")
aref = pref:ajouter(ui.arbre())
aref.poids = 1
aref.surselection = @REFERENCE
aref.surdoubleclic = @INSERER_REFERENCE
fiche = pref:ajouter(ui.markdown("Sélectionnez un **paquet** ou une **fonction**."))
fiche.poids = 1

&& à droite : éditeur, puis Problèmes / Console / Variables / Pile d'appels
cotedroit = sep:ajouter(ui.separateur{vertical = faux, position = 0.68})
ed = cotedroit:ajouter(ui.editeur{minicarte = reglages.minicarte, taille = reglages.police})
ed.surchangement = @MODIFIE
ed.surselection = @SIGNAL

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

ETAT_BOUTONS("repos")
CHARGER_REFERENCE()
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

procedure FERMETURE(ev)
  ENREGISTRER_SESSION()
  ECRIRE_REGLAGES()
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
