&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atlas SQL : menus, raccourcis, espaces de travail, à propos.

fonction MENUS()
retourner { ;
  {"Fichier", {"Nouveau projet…", "Ouvrir un projet…", "-", "Exporter le dictionnaire (Markdown)…", ;
               "Exporter l'inventaire (CSV)…", "Exporter les dépendances (CSV)…", "-", "Quitter"}}, ;
  {"Sources", {"Nouvelle source…", "Modifier la source…", "Ajouter la démonstration", "Supprimer une source…"}}, ;
  {"Analyse", {"Lancer l'analyse complète (F5)", "Relancer les travaux en erreur", "Pause / reprise de la file", ;
               "Tout arrêter", "-", "Importer les appels capturés"}}, ;
  {"Affichage", {"Tableau de bord", "Cartographie", "Dépendances", "Dictionnaire", "Types métier", "Code SQL", "Flux", ;
                 "Duplications", "SQL dynamique", "Performances", "Patrimoine", "Refactoring", "Interception", "Assistant", ;
                 "Diagnostics", "-", "Masquer / afficher le panneau de gauche", "Panneau de gauche dans une fenêtre", "Cartographie dans une fenêtre", "-", "Thème sombre / clair", ;
                 "Enregistrer l'espace de travail…", "Restaurer un espace de travail…"}}, ;
  {"Aide", {"Guide de démarrage", "Raccourcis clavier", "Architecture", "À propos"}}}

procedure CONSTRUIRE_MENUS(m)
  pour chaque groupe dans MENUS()
    pour chaque e dans groupe[2]
      m:ajouter(groupe[1], e)
    suivant
  suivant
retourner

procedure MENU(ev)
  locale choix = ev.texte
  si ev.chemin <> nul
    choix = ev.chemin[#ev.chemin]
  finsi
  && vues
  pour chaque v dans NOMS_VUES()
    si choix = v
      VOIR_VUE(v)
      retourner
    finsi
  suivant
  faire cas
  cas choix = "Nouveau projet…" ou choix = "Ouvrir un projet…"
    CHANGER_PROJET(choix = "Nouveau projet…")
  cas choix = "Exporter le dictionnaire (Markdown)…"
    DICO_EXPORTER(nul)
  cas choix = "Exporter l'inventaire (CSV)…"
    EXPORTER_CSV("inventaire.csv", "select id, serveur, base, sch as schema, nom, genre, parent_nom, proprietaire, cree, modifie, lignes, taille_ko from objets order by 2, 3, 4, 5")
  cas choix = "Exporter les dépendances (CSV)…"
    EXPORTER_CSV("dependances.csv", "select a.serveur || '.' || a.base || '.' || a.sch || '.' || a.nom as de, d.nature, " + ;
                 "coalesce(b.serveur || '.' || b.base || '.' || b.sch || '.' || b.nom, d.vers_nom) as vers, d.origine, d.interbase, " + ;
                 "d.interserveur, d.frequence, d.volume_moy, d.volume_max, d.complexite from dependances d join objets a on a.id = d.de_id " + ;
                 "left join objets b on b.id = d.vers_id order by 1")
  cas choix = "Quitter"
    FERMETURE(nul)
    fen:fermer()
  cas choix = "Nouvelle source…"
    NOUVELLE_SOURCE(nul)
  cas choix = "Modifier la source…"
    MODIFIER_SOURCE()
  cas choix = "Ajouter la démonstration"
    AJOUTER_SOURCE_DEMO()
    STATUT("Source de démonstration ajoutée : lancez l'analyse (F5).")
  cas choix = "Supprimer une source…"
    SUPPRIMER_SOURCE()
  cas commencepar(choix, "Lancer l'analyse")
    ANALYSER_TOUT(nul)
  cas choix = "Relancer les travaux en erreur"
    FILE_RELANCER(nul)
  cas choix = "Pause / reprise de la file"
    FILE_PAUSE(nul)
  cas choix = "Tout arrêter"
    FILE_ARRETER(nul)
  cas choix = "Importer les appels capturés"
    ICP_IMPORTER(nul)
  cas choix = "Masquer / afficher le panneau de gauche"
    PANNEAU_BASCULER(nul)
  cas choix = "Panneau de gauche dans une fenêtre"
    PANNEAU_FENETRE(nul)
  cas choix = "Cartographie dans une fenêtre"
    CARTO_FENETRE(nul)
  cas choix = "Thème sombre / clair"
    reglages.sombre = non reglages.sombre
    fen:fixertheme("natif", reglages.sombre, "compacte")
    si fenpanneau <> nul
      fenpanneau:fixertheme("natif", reglages.sombre, "compacte")
    finsi
    ECRIRE_REGLAGES()
  cas choix = "Enregistrer l'espace de travail…"
    ESPACE_ENREGISTRER()
  cas choix = "Restaurer un espace de travail…"
    ESPACE_RESTAURER()
  cas choix = "Guide de démarrage"
    PROPRIETES(ACCUEIL())
  cas choix = "Raccourcis clavier"
    ui.alerte(RACCOURCIS(), "information", "Raccourcis clavier")
  cas choix = "Architecture"
    essayer
      PROPRIETES(fichier.lire(fichier.joindre(systeme.dossierprogramme(), "ARCHITECTURE.md")))
    capturer e
      STATUT("ARCHITECTURE.md introuvable à côté du programme.")
    finessayer
  cas choix = "À propos"
    ui.alerte("Atlas SQL 1.0 - Cartographie et analyse du patrimoine SQL Server" + car(10) +
              "Écrit en Lexis+ (wdlexis+) · entrepôt DuckDB local" + car(10) + car(10) +
              "Tous droits réservés 2026 - Jean-Marc QUÉRÉ\n" +
              "⛶ https://sonaliwan.fr  ✉ metalab (at) sonaliwan.fr\n" +
              "SIRET 13033319800013"
              , "information", "À propos")
  fincas
retourner

fonction RACCOURCIS()
retourner joindre({"F5            lancer l'analyse complète (éditeur : continuer le débogage)", ;
  "Ctrl+F        rechercher (objets, colonnes, objets métier, code)", ;
  "Ctrl+D        ajouter / retirer l'objet courant des favoris", ;
  "Alt+← / Alt+→ objet précédent / suivant", "", ;
  "Éditeur SQL", ;
  "F12           aller à la définition", ;
  "F9            point d'arrêt du débogueur", ;
  "F10 / F11     pas à pas / pas à pas détaillé (entre dans EXEC)", ;
  "Ctrl+S        enregistrer le script", "", ;
  "Explorateur : double-clic sur un objet = son code ; sur un serveur, une base, un schéma = sa cartographie.", ;
  "Cartographie : molette = zoom, glisser le fond = déplacement, double-clic = descendre d'un niveau."}, car(10))

procedure EXPORTER_CSV(nom, sql)
  locale p = ui.enregistrerfichier{nom = nom, filtre = "CSV|*.csv"}
  si p <> nul
    RQ(nul, "copy (" + sql + ") to '" + remplacertexte(p, "'", "''") + "' (header, delimiter ';')", nul)
    STATUT("Exporté : " + p)
  finsi
retourner

procedure CHANGER_PROJET(nouveau)
  locale p = nul
  si nouveau
    p = ui.demander("Dossier du nouveau projet :", fichier.joindre(fichier.dossierperso(), "AtlasSQL-projet"))
  sinon
    p = ui.demander("Dossier du projet (contenant atlas.duckdb) :", dossier)
  finsi
  si p = nul ou p = ""
    retourner
  finsi
  reglages.projet = fichier.absolu(p)
  ECRIRE_REGLAGES()
  ui.alerte("Le projet « " + fichier.nom(p) + " » sera ouvert au prochain démarrage d'Atlas SQL.", "information")
retourner

procedure MODIFIER_SOURCE
  locale l = SOURCES()
  si #l = 0
    NOUVELLE_SOURCE(nul)
    retourner
  finsi
  locale noms = {}
  pour chaque s dans l
    inserer(noms, s.id + " · " + s.nom)
  suivant
  locale r = ui.demander("Numéro de la source à modifier (" + joindre(noms, " ; ") + ") :", chaine(l[1].id))
  si r = nul
    retourner
  finsi
  locale src = SOURCE(nombre(r))
  si src <> nul
    SOURCE_DIALOGUE(src)
  finsi
retourner

procedure SUPPRIMER_SOURCE
  locale l = SOURCES()
  si #l = 0
    retourner
  finsi
  locale noms = {}
  pour chaque s dans l
    inserer(noms, s.id + " · " + s.nom)
  suivant
  locale r = ui.demander("Numéro de la source à supprimer, avec tout ce qui a été analysé (" + joindre(noms, " ; ") + ") :", "")
  si r = nul ou nombre(r) = nul
    retourner
  finsi
  locale id = nombre(r)
  si non ui.confirmer("Supprimer la source " + id + " et ses résultats d'analyse de l'entrepôt ?", "attention")
    retourner
  finsi
  locale anciens = "(select id from objets where source_id = " + entier(id) + ")"
  pour chaque tb dans {"colonnes", "refs_brutes", "instructions", "ast", "variables", "sql_dynamique", "diagnostics", "jointures", "regles", ;
                       "metriques", "stats_requetes", "index_manquants", "dico_tables", "dico_colonnes", "duplications"}
    RQ(nul, "delete from " + tb + " where objet_id in " + anciens, nul)
  suivant
  RQ(nul, "delete from dependances where de_id in " + anciens + " or vers_id in " + anciens, nul)
  RQ(nul, "delete from objets where source_id = ?", {id})
  RQ(nul, "delete from sources where id = ?", {id})
  pour chaque tb dans {"ext_objets", "ext_colonnes", "ext_dependances", "ext_stats", "ext_index_manquants", "ext_jobs", "ext_profils"}
    RQ(nul, "delete from " + tb + " where source_id = ?", {id})
  suivant
  ARBRE_SOURCES()
  RAFRAICHIR_VUES()
  STATUT("Source " + id + " supprimée.")
retourner

&&
&& Espaces de travail : vue active, objet courant, réglages d'affichage
&&

procedure ESPACE_ENREGISTRER
  locale nom = ui.demander("Nom de l'espace de travail :", sisinon(reglages.espace = nul, "Standard", reglages.espace))
  si nom = nul ou nom = ""
    retourner
  finsi
  locale e = {vue = vues.valeur, objet = sisinon(courant = nul, nul, courant.cle), agents = reglages.agents, ;
              parserveur = reglages.parserveur, sombre = reglages.sombre, gauche = gauche.valeur, bas = bas.valeur}
  RQ(nul, "delete from espaces where nom = ?", {nom})
  RQ(nul, "insert into espaces values (?, ?, now())", {nom, json(e)})
  reglages.espace = nom
  ECRIRE_REGLAGES()
  STATUT("Espace de travail « " + nom + " » enregistré.")
retourner

procedure ESPACE_RESTAURER
  locale noms = {}
  pour chaque r dans RQ(nul, "select nom from espaces order by modifie desc", nul)
    inserer(noms, r.nom)
  suivant
  si #noms = 0
    STATUT("Aucun espace de travail enregistré.")
    retourner
  finsi
  locale nom = ui.demander("Espace à restaurer (" + joindre(noms, ", ") + ") :", noms[1])
  si nom = nul
    retourner
  finsi
  locale r = RQ(nul, "select contenu from espaces where nom = ?", {nom})
  si #r = 0
    retourner
  finsi
  locale e = dejson(r[1].contenu)
  si e.objet <> nul
    locale id = RV(nul, "select id from objets where cle = ?", {e.objet})
    si id <> nul
      ALLER_OBJET(id, "espace")
    finsi
  finsi
  vues.valeur = e.vue
  gauche.valeur = e.gauche
  bas.valeur = e.bas
  reglages.agents = e.agents
  cagents.valeur = e.agents
  AGENTS_CHANGES(nul)
  reglages.espace = nom
  STATUT("Espace de travail « " + nom + " » restauré.")
retourner
