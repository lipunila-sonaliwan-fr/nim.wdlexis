&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : projet (duckstudio.json), historique des exécutions, scripts .sql
&&
&& duckstudio.json : {connexions = {...}, historique = {...}, positions = {...}}
&& Les paramètres secrets (mots de passe, jetons) ne sont jamais enregistrés : ils sont
&& demandés à l'attachement et gardés en mémoire pendant la session.

fonction DS_PROJET_VIDE()
retourner {version = 1, connexions = {}, historique = {}, positions = {}, ignorees = {}}

fonction FICHIER_PROJET()
retourner fichier.joindre(dossier, "duckstudio.json")

fonction DOSSIER_CACHE()
  locale d = fichier.joindre(dossier, ".duckstudio")
  fichier.creerdossier(d)
retourner d

procedure CHARGER_PROJET(d)
  globale dossier, projet, catalogue, attachees
  si dossier <> ""
    ENREGISTRER_PROJET()
  finsi
  && détacher les connexions du projet précédent
  pour chaque alias, v dans attachees
    essayer
      requete("DETACH DATABASE IF EXISTS " + IDENT(minuscule(alias)))
    capturer e
    finessayer
  suivant
  attachees = {}
  catalogue = {}
  dossier = d
  projet = DS_PROJET_VIDE()
  si fichier.existe(FICHIER_PROJET())
    essayer
      locale p = dejson(fichier.lire(FICHIER_PROJET()))
      pour chaque k, v dans p
        projet[k] = v
      suivant
    capturer e
      ERREUR("duckstudio.json illisible : " + e)
    finessayer
  finsi
  fen.titre = "DuckDB [S]tudio - " + fichier.nom(dossier)
  && catalogues en cache (sans se connecter)
  pour chaque c dans projet.connexions
    locale cache = fichier.joindre(DOSSIER_CACHE(), "catalogue_" + c.nom + ".json")
    si fichier.existe(cache)
      essayer
        catalogue[majuscule(c.nom)] = dejson(fichier.lire(cache))
      capturer e
      finessayer
    finsi
  suivant
  && connexions sans secret : attachées tout de suite
  pour chaque c dans projet.connexions
    si non A_DES_SECRETS(c)
      ATTACHER(c, faux)
    finsi
  suivant
  REMPLIR_EXPLORATEUR()
  REMPLIR_HISTORIQUE()
  NOMS_COMPLETION()
  && scripts du projet
  locale ouverts = 0
  pour chaque nom dans fichier.liste(dossier, faux)
    si minuscule(fichier.extension(nom)) = ".sql" et ouverts < 6
      ed:ouvrir(fichier.joindre(dossier, nom))
      ouverts += 1
    finsi
  suivant
  si ouverts = 0
    NOUVELLE_REQUETE()
  finsi
  si #projet.connexions = 0
    STATUT("Projet vide : créez une connexion (+ Connexion) ou une base de démonstration (Fichier).")
  sinon
    STATUT("Projet : " + dossier + " - " + #projet.connexions + " connexion(s)")
  finsi
  DS_ECRIRE_REGLAGES()
retourner

procedure ENREGISTRER_PROJET
  si dossier = ""
    retourner
  finsi
  && les secrets ne quittent pas la mémoire
  locale copie = {version = projet.version, connexions = {}, historique = projet.historique, ;
                  positions = projet.positions, ignorees = projet.ignorees}
  pour chaque c dans projet.connexions
    locale p = {}
    pour chaque k, v dans c.parametres
      si non EST_SECRET(c.type, minuscule(k))
        p[k] = v
      finsi
    suivant
    inserer(copie.connexions, {nom = c.nom, description = c.description, type = c.type, ;
                               parametres = p, options = c.options})
  suivant
  essayer
    fichier.ecrire(FICHIER_PROJET(), json(copie))
  capturer e
    ERREUR("enregistrement du projet impossible : " + e)
  finessayer
retourner

procedure OUVRIR_PROJET
  locale p = ui.demander("Dossier du projet :", dossier)
  si p <> nul et p <> ""
    si non fichier.estdossier(p)
      si ui.confirmer("Le dossier « " + p + " » n'existe pas. Le créer ?")
        fichier.creerdossier(p)
      sinon
        retourner
      finsi
    finsi
    CHARGER_PROJET(fichier.absolu(p))
  finsi
retourner

&&
&& Historique des exécutions (tableau de bord, mutualisation)
&&

procedure HISTORISER(texte, duree, lignes, ok, message)
  inserer(projet.historique, {sql = texte, quand = maintenant(), duree = arrondi(duree * 1000, 2), ;
                              lignes = lignes, ok = ok, message = message})
  tantque #projet.historique > 500
    retirer(projet.historique, 1)
  fintantque
  lhist:inserer(1, sisinon(ok, "✓ ", "✗ ") + chaine(arrondi(duree * 1000)) + " ms  " + ;
                gauche(remplacertexte(rogner(texte), car(10), " "), 90))
retourner

procedure REMPLIR_HISTORIQUE
  lhist:vider()
  pour i = #projet.historique a 1 pas -1
    locale h = projet.historique[i]
    lhist:ajouter(sisinon(h.ok, "✓ ", "✗ ") + chaine(arrondi(h.duree)) + " ms  " + ;
                  gauche(remplacertexte(rogner(h.sql), car(10), " "), 90))
  suivant
retourner

procedure HISTORIQUE_REPRENDRE(ev)
  locale i = lhist:selection()
  si i = nul ou i < 1
    retourner
  finsi
  locale h = projet.historique[#projet.historique - i + 1]
  si h <> nul
    vues.valeur = 1
    ed:inserer(car(10) + rogner(h.sql) + ";" + car(10))
  finsi
retourner

&&
&& Scripts .sql
&&

procedure NOUVELLE_REQUETE
  globale nbrequetes
  si nbrequetes = nul
    nbrequetes = 0
  finsi
  nbrequetes += 1
  locale uid = ed:nouveau("requete" + nbrequetes + ".sql")
  ed:langage("sql", uid)
  ed:fixertexte("-- Requête " + nbrequetes + " : F5 ou ▶ Exécuter (la sélection, sinon tout le script)" + car(10), uid, vrai)
  vues.valeur = 1
retourner

procedure OUVRIR_SCRIPT
  locale p = ui.ouvrirfichier{titre = "Ouvrir un script SQL", dossier = dossier, filtre = "SQL|*.sql|Tous les fichiers|*"}
  si p <> nul
    ed:ouvrir(p)
    vues.valeur = 1
  finsi
retourner

procedure ENREGISTRER_SCRIPT
  locale p = ed:chemin()
  si p = "" ou non contient(p, car(47)) et non contient(p, car(92))
    locale nom = ui.demander("Nom du script (dans le projet) :", sisinon(p = "", "requete.sql", fichier.nom(p)))
    si nom = nul ou nom = ""
      retourner
    finsi
    si fichier.extension(nom) = ""
      nom = nom + ".sql"
    finsi
    p = fichier.joindre(dossier, nom)
  finsi
  ed:enregistrer(p)
  REMPLIR_EXPLORATEUR()
  STATUT("Enregistré : " + fichier.nom(p))
retourner
