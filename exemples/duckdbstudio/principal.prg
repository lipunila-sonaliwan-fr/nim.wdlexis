&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : atelier de conception, d'administration, d'analyse et d'optimisation
&& autour de DuckDB, écrit en Lexis+ (interface inspirée de l'atelier Lexis+).
&&
&&   wdlexisrt principal.prg [dossier_du_projet]
&&
&& Fichiers (le runtime les charge tous) :
&&   principal.prg     fenêtre, menus, barre d'outils, réglages, démarrage
&&   projet.prg        projet (duckstudio.json), historique, scripts
&&   connecteurs.prg   greffons de connexion (connecteurs/*.json), attachement, catalogue
&&   connexions.prg    concepteur de connexions (boîte de dialogue), mots de passe mémorisés
&&   taches.prg        connexions numérotées, onglets (session, connexion), opérations longues
&&   explorateur.prg   arbre des connexions, schémas, tables, vues, macros ; palette
&&   requetes.prg      éditeur SQL, exécution, résultats, validation, export
&&   profil.prg        plan d'exécution (EXPLAIN ANALYZE) en graphe et en tableau
&&   expertise.prg     moteur de règles, recommandations, mutualisation
&&   schema.prg        concepteur entité-relation, SQL <-> modèle, analyse d'impact
&&   sqlast.prg        arbre syntaxique de DuckDB (json_serialize_sql), expressions exactes
&&   pipelines.prg     concepteur de pipelines, pipeline <-> SQL (lot 2)
&&   planificateur.prg travaux planifiés, dépendances, reprises, Gantt (lot 2)
&&   mutualisation.prg empreintes des requêtes : jointures et grains communs (lot 2)
&&   assistant.prg     assistant IA : règles, modèle local GGUF, serveur HTTP (lot 3)
&&   bi.prg            tableau de bord BI (lot 3)
&&   extensions.prg    extensions du projet : règles, onglets, menus (lot 3)
&&   carto.prg         cartographie globale (sources, bases, tables, vues)
&&   tableau.prg       tableau de bord technique
&&   menus.prg         menus, raccourcis, à propos
&&   demo.prg          base de démonstration
&&
&& Le moteur est une base DuckDB en mémoire ; chaque connexion y est attachée sous son
&& nom (ATTACH ... AS nom) : une requête peut joindre plusieurs sources.
ui = paquet("interface")

reglages = DS_LIRE_REGLAGES()
dossier = ""                  && dossier du projet
projet = DS_PROJET_VIDE()     && duckstudio.json
connecteurs = {}              && greffons, par type
catalogue = {}                && catalogue par connexion (cache)
attachees = {}                && connexions attachées (alias -> vrai)
noeudsarbre = {}              && explorateur : clef de chemin -> objet
dernierresultat = nul         && dernière requête affichée {sql, colonnes, lignes}
dernierplan = nul             && dernier plan profilé
recos = {}                    && recommandations affichées
modele = nul                  && modèle du concepteur de schéma
condlg = nul                  && boîte de connexion
conctl = {}
analyse = ""                  && empreinte de la dernière validation
noeudcourant = nul            && élément sélectionné dans l'explorateur
recocourante = nul            && recommandation sélectionnée
tablecourante = nul           && table sélectionnée dans le concepteur de schéma
derniereerreur = nul          && {sql, message} de la dernière erreur d'exécution (assistant)
planif = nul                  && planificateur (lot 2)
ia = nul                      && assistant (lot 3)
bi = nul                      && tableau de bord BI (lot 3)
INITIALISER_EXTENSIONS()      && extensions (lot 3)
secrets = {}                  && secrets saisis pendant la session, par connexion (jamais dans le projet)
onglets = {}                  && onglets de l'éditeur : uid -> {cnx, session, tache, resultat}
taches = {}                   && opérations en cours : id -> {libelle, debut, session, arret}
numtache = 0
tachelongue = nul             && opération affichée dans la barre d'arrêt
cnxdefaut = 0                 && connexion des nouveaux onglets (0 : moteur)
outils = nul                  && contexte des outils (aperçu de pipeline…)
majcombo = faux
choixcnx = {0}                && liste « Connexion » de l'onglet : index -> numéro
resultataffiche = nul         && résultat affiché dans l'onglet Résultats

ouvrirbase(":memoire:")
CHARGER_CONNECTEURS()

fen = ui.fenetre{titre = "DuckDB [S]tudio", largeur = 1440, hauteur = 900, disposition = "bordure", ;
                 sombre = reglages.sombre}
fen.surfermeture = @FERMETURE
fen.surtouchebas = @TOUCHE_FENETRE

menu = fen:ajouter(ui.barremenu())
CONSTRUIRE_MENUS(menu)
menu.surselection = @MENU

barre = fen:ajouter(ui.rangee())
barre.ancrage = "haut"
boutons = {}
BOUTON("connexion", "+ Connexion", @NOUVELLE_CONNEXION)
BOUTON("requete", "+ Requête", @NOUVELLE_REQUETE)
BOUTON("ouvrir", "Ouvrir…", @OUVRIR_SCRIPT)
BOUTON("enregistrer", "Enregistrer", @ENREGISTRER_SCRIPT)
BOUTON("executer", "▶ Exécuter", @EXECUTER_SQL)
BOUTON("profiler", "Profiler", @PROFILER)
BOUTON("analyser", "Analyser", @ANALYSER_TOUT)
BOUTON("schema", "Schéma", @VOIR_SCHEMA)
BOUTON("carto", "Cartographie", @VOIR_CARTO)
BOUTON("tableau", "Tableau de bord", @VOIR_TABLEAU)

pied = fen:ajouter(ui.rangee())
pied.ancrage = "bas"
etat = pied:ajouter(ui.etiquette("Prêt"))
etat.poids = 1
lblcnx = pied:ajouter(ui.etiquette(""))
lblcnx.largeurfixe = 420

&& barre d'arrêt : opérations de plus de 15 s (bouton ou touche Échap)
barrearret = fen:ajouter(ui.rangee())
barrearret.ancrage = "bas"
barrearret.fond = "#FDE68A"
lblarret = barrearret:ajouter(ui.etiquette(""))
lblarret.poids = 1
lblarret.couleur = "#78350F"
barret = barrearret:ajouter(ui.bouton("■ Arrêter"))
barret.surclic = @ARRETER_LONGUE
barret.infobulle = "Interrompre cette opération (Échap)"
btouttarret = barrearret:ajouter(ui.bouton("Tout arrêter"))
btouttarret.surclic = @ARRETER_TOUT
barrearret.visible = faux

sep = fen:ajouter(ui.separateur{vertical = vrai, position = 0.235})

&& à gauche : Explorateur, Palette, Historique
gauche = sep:ajouter(ui.onglets())
pexpl = gauche:ajouterpage("Explorateur", "bordure")
rexpl = pexpl:ajouter(ui.rangee())
rexpl.ancrage = "haut"
OUTIL(rexpl, "Requête", @EXPL_REQUETE, "SELECT sur l'élément sélectionné")
OUTIL(rexpl, "Décrire", @EXPL_DECRIRE, "Colonnes et statistiques (SUMMARIZE)")
OUTIL(rexpl, "Schéma", @EXPL_SCHEMA, "Concepteur de schéma sur ce schéma")
OUTIL(rexpl, "↻", @RAFRAICHIR_TOUT, "Relire le catalogue des connexions")
&& liste en haut, détail en bas, séparés par un séparateur déplaçable
sepexpl = pexpl:ajouter(ui.separateur{vertical = faux, position = reglages.sepexpl})
sepexpl.ancrage = "centre"
arbre = sepexpl:ajouter(ui.arbre())
arbre.surselection = @EXPL_CHOIX
arbre.surdoubleclic = @EXPL_DOUBLE
infoexpl = sepexpl:ajouter(ui.markdown("Sélectionnez une connexion, une table ou une vue."))

ppal = gauche:ajouterpage("Palette", "bordure")
seppal = ppal:ajouter(ui.separateur{vertical = faux, position = reglages.seppal})
seppal.ancrage = "centre"
palette = seppal:ajouter(ui.arbre())
palette.surselection = @PALETTE_CHOIX
palette.surdoubleclic = @PALETTE_UTILISER
infopal = seppal:ajouter(ui.markdown("Double-cliquez un élément pour l'utiliser."))
CONSTRUIRE_PALETTE()

phist = gauche:ajouterpage("Historique", "bordure")
lhist = phist:ajouter(ui.liste())
lhist.ancrage = "centre"
lhist.surdoubleclic = @HISTORIQUE_REPRENDRE

&& à droite : vues (onglets), puis Résultats / Messages
cotedroit = sep:ajouter(ui.separateur{vertical = faux, position = 0.64})
vues = cotedroit:ajouter(ui.onglets())

preq = vues:ajouterpage("Requêtes", "bordure")
rreq = preq:ajouter(ui.rangee())
rreq.ancrage = "haut"
rreq:ajouter(ui.etiquette("Connexion de l'onglet :"))
cbcnx = rreq:ajouter(ui.combo())
cbcnx.largeurfixe = 300
cbcnx.surselection = @CNX_ONGLET
cbcnx.infobulle = "Connexion par défaut des requêtes de cet onglet (USE) ; son numéro s'affiche sur l'onglet"
lblreq = rreq:ajouter(ui.etiquette("Chaque onglet a sa session : plusieurs requêtes peuvent s'exécuter en même temps."))
lblreq.poids = 1
lblreq.couleur = "#6B7280"
ed = preq:ajouter(ui.editeur{minicarte = faux, taille = reglages.police})
ed.ancrage = "centre"
ed.surchangement = @SQL_MODIFIE
ed.surselection = @SQL_SIGNAL

pschema = vues:ajouterpage("Schéma", "bordure")
CONSTRUIRE_SCHEMA(pschema)

pprofil = vues:ajouterpage("Profil", "bordure")
CONSTRUIRE_PROFIL(pprofil)

preco = vues:ajouterpage("Recommandations", "bordure")
CONSTRUIRE_RECOS(preco)

pcarto = vues:ajouterpage("Cartographie", "bordure")
CONSTRUIRE_CARTO(pcarto)

ptab = vues:ajouterpage("Tableau de bord", "bordure")
CONSTRUIRE_TABLEAU(ptab)

ppipe = vues:ajouterpage("Pipelines", "bordure")
CONSTRUIRE_PIPELINES(ppipe)

pplanif = vues:ajouterpage("Planification", "bordure")
CONSTRUIRE_PLANIF(pplanif)

pbi = vues:ajouterpage("BI", "bordure")
CONSTRUIRE_BI(pbi)

ordrevues = {"Requêtes", "Schéma", "Profil", "Recommandations", "Cartographie", "Tableau de bord", "Pipelines", ;
             "Planification", "BI"}

bas = cotedroit:ajouter(ui.onglets())
pres = bas:ajouterpage("Résultats", "bordure")
rres = pres:ajouter(ui.rangee())
rres.ancrage = "haut"
lblres = rres:ajouter(ui.etiquette("Aucun résultat"))
lblres.poids = 1
OUTIL(rres, "Compter", @COMPTER_RESULTAT, "Nombre exact de lignes de la dernière requête")
OUTIL(rres, "Exporter…", @EXPORTER_RESULTAT, "COPY vers CSV, Parquet ou JSON")
zoneres = pres:ajouter(ui.superconteneur("bordure"))
zoneres.ancrage = "centre"
grilleres = nul
pmsg = bas:ajouterpage("Messages", "bordure")
messages = pmsg:ajouter(ui.saisie{multiligne = vrai})
messages.ancrage = "centre"
messages.etat = "lecture"
pia = bas:ajouterpage("Assistant", "bordure")
CONSTRUIRE_ASSISTANT(pia)
ordrebas = {"Résultats", "Messages", "Assistant"}

&& démarrage
depart = systeme.args[1]
si depart = nul ou depart = ""
  depart = reglages.projet
finsi
si depart = nul ou depart = "" ou non fichier.estdossier(depart)
  depart = fichier.joindre(fichier.dossierperso(), "DuckDBStudio")
  fichier.creerdossier(depart)
finsi
CHARGER_PROJET(fichier.absolu(depart))
surveillance = ui.minuterie(1000, @SURVEILLER_TACHES)
ui.executer()

&&
&& Réglages (dossier personnel)
&&

fonction FICHIER_REGLAGES()
retourner fichier.joindre(fichier.dossierperso(), ".duckdbstudio.json")

fonction DS_LIRE_REGLAGES()
  locale r = {sombre = faux, police = 13, projet = "", limite = 1000, sepexpl = 0.68, seppal = 0.70}
  locale p = FICHIER_REGLAGES()
  si fichier.existe(p)
    essayer
      pour chaque k, v dans dejson(fichier.lire(p))
        r[majuscule(k)] = v
      suivant
    capturer e
    finessayer
  finsi
retourner r

procedure DS_ECRIRE_REGLAGES
  reglages.projet = dossier
  essayer
    reglages.sepexpl = sepexpl.position
    reglages.seppal = seppal.position
  capturer e
  finessayer
  essayer
    fichier.ecrire(FICHIER_REGLAGES(), json(reglages))
  capturer e
  finessayer
retourner

&&
&& Barre d'outils, barre d'état, journal
&&

procedure BOUTON(nom, libelle, proc)
  locale b = barre:ajouter(ui.bouton(libelle))
  b.surclic = proc
  boutons[majuscule(nom)] = b
retourner

fonction OUTIL(rangee, libelle, proc, aide)
  locale b = rangee:ajouter(ui.bouton(libelle))
  b.surclic = proc
  b.infobulle = aide
retourner b

procedure STATUT(texte)
  etat.libelle = texte
retourner

procedure JOURNAL(texte)
  locale t = messages.valeur
  si longueur(t) > 60000
    t = droite(t, 40000)
  finsi
  messages.valeur = t + heure() + "  " + texte + car(10)
retourner

fonction INDEX_BAS(titre)
  pour i = 1 a #ordrebas
    si ordrebas[i] = titre
      retourner i
    finsi
  suivant
retourner 1

procedure ERREUR(texte)
  JOURNAL("ERREUR : " + texte)
  STATUT("Erreur : " + gauche(remplacertexte(texte, car(10), " "), 160))
  bas.valeur = 2
retourner

procedure TOUCHE_FENETRE(ev)
  && F5 / Ctrl+Entrée : exécuter ; F6 : profiler ; Échap : arrêter
  si ev.touche = 27
    ARRETER_COURANTE()
  sinonsi ev.touche = 1073741886
    EXECUTER_SQL()
  sinonsi ev.touche = 1073741887
    PROFILER()
  finsi
retourner

procedure FERMETURE(ev)
  pour chaque k, t dans taches
    ARRETER_TACHE(t)
  suivant
  ENREGISTRER_PROJET()
  DS_ECRIRE_REGLAGES()
  si condlg <> nul
    condlg:fermer()
  finsi
retourner
