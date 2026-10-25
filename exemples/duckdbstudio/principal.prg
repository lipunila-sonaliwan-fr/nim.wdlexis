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
&&   connexions.prg    concepteur de connexions (boîte de dialogue)
&&   explorateur.prg   arbre des connexions, schémas, tables, vues, macros ; palette
&&   requetes.prg      éditeur SQL, exécution, résultats, validation, export
&&   profil.prg        plan d'exécution (EXPLAIN ANALYZE) en graphe et en tableau
&&   expertise.prg     moteur de règles, recommandations, mutualisation
&&   schema.prg        concepteur entité-relation, SQL <-> modèle, analyse d'impact
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
secrets = {}                  && secrets saisis pendant la session, par connexion (jamais enregistrés)

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
lblcnx.largeurfixe = 360

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
arbre = pexpl:ajouter(ui.arbre())
arbre.ancrage = "centre"
arbre.surselection = @EXPL_CHOIX
arbre.surdoubleclic = @EXPL_DOUBLE
infoexpl = pexpl:ajouter(ui.markdown("Sélectionnez une connexion, une table ou une vue."))
infoexpl.ancrage = "bas"
infoexpl.hauteurfixe = 170

ppal = gauche:ajouterpage("Palette", "bordure")
palette = ppal:ajouter(ui.arbre())
palette.ancrage = "centre"
palette.surselection = @PALETTE_CHOIX
palette.surdoubleclic = @PALETTE_UTILISER
infopal = ppal:ajouter(ui.markdown("Double-cliquez un élément pour l'utiliser."))
infopal.ancrage = "bas"
infopal.hauteurfixe = 150
CONSTRUIRE_PALETTE()

phist = gauche:ajouterpage("Historique", "bordure")
lhist = phist:ajouter(ui.liste())
lhist.ancrage = "centre"
lhist.surdoubleclic = @HISTORIQUE_REPRENDRE

&& à droite : vues (onglets), puis Résultats / Messages
cotedroit = sep:ajouter(ui.separateur{vertical = faux, position = 0.64})
vues = cotedroit:ajouter(ui.onglets())

preq = vues:ajouterpage("Requêtes", "bordure")
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

bas = cotedroit:ajouter(ui.onglets())
pres = bas:ajouterpage("Résultats", "bordure")
rres = pres:ajouter(ui.rangee())
rres.ancrage = "haut"
lblres = rres:ajouter(ui.etiquette("Aucun résultat"))
lblres.poids = 1
OUTIL(rres, "Compter", @COMPTER_RESULTAT, "Nombre exact de lignes de la dernière requête")
OUTIL(rres, "Exporter…", @EXPORTER_RESULTAT, "COPY vers CSV, Parquet ou JSON")
zoneres = pres:ajouter(ui.panneau{disposition = "bordure", defilement = "masque"})
zoneres.ancrage = "centre"
grilleres = nul
pmsg = bas:ajouterpage("Messages", "bordure")
messages = pmsg:ajouter(ui.saisie{multiligne = vrai})
messages.ancrage = "centre"
messages.etat = "lecture"

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
ui.executer()

&&
&& Réglages (dossier personnel)
&&

fonction FICHIER_REGLAGES()
retourner fichier.joindre(fichier.dossierperso(), ".duckdbstudio.json")

fonction DS_LIRE_REGLAGES()
  locale r = {sombre = faux, police = 13, projet = "", limite = 1000}
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

procedure ERREUR(texte)
  JOURNAL("ERREUR : " + texte)
  STATUT("Erreur : " + gauche(remplacertexte(texte, car(10), " "), 160))
  bas.valeur = 2
retourner

procedure TOUCHE_FENETRE(ev)
  && F5 / Ctrl+Entrée : exécuter ; F6 : profiler
  si ev.touche = 1073741886
    EXECUTER_SQL()
  sinonsi ev.touche = 1073741887
    PROFILER()
  finsi
retourner

procedure FERMETURE(ev)
  ENREGISTRER_PROJET()
  DS_ECRIRE_REGLAGES()
  si condlg <> nul
    condlg:fermer()
  finsi
retourner
