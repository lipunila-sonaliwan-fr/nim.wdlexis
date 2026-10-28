&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : extensions (lot 3).
&&
&& Les fichiers .prg du dossier extensions/ du projet sont chargés dans le programme
&& (lexis.charger) ; chaque fonction EXTENSION_xxx() qu'ils définissent décrit ce
&& que l'extension apporte : règles d'expertise, onglet, entrées du menu
&& Extensions (voir modeles/extension.txt). Une extension est du code Lexis+ qui
&& s'exécute avec les droits de DuckDB Studio : le premier chargement d'un projet
&& qui en contient demande confirmation, puis le projet est marqué « de confiance ».

procedure INITIALISER_EXTENSIONS
  globale exts
  exts = {liste = {}, vues = {}, menus = {}, dlg = nul, table = nul}
retourner

fonction DOSSIER_EXTENSIONS()
retourner fichier.joindre(dossier, "extensions")

fonction FICHIERS_EXTENSIONS()
  locale l = {}
  locale d = DOSSIER_EXTENSIONS()
  si fichier.estdossier(d)
    pour chaque f dans fichier.liste(d, faux)
      si minuscule(fichier.extension(f)) = ".prg"
        inserer(l, fichier.joindre(d, f))
      finsi
    suivant
  finsi
  trier(l)
retourner l

procedure EXTENSIONS_CHARGER(interactif)
  exts.liste = {}
  locale fichiers = FICHIERS_EXTENSIONS()
  si #fichiers = 0
    EXT_ACTUALISER_DIALOGUE()
    retourner
  finsi
  si projet.extensions_confiance <> vrai
    si non interactif
      JOURNAL("Extensions : " + #fichiers + " extension(s) non chargée(s) — projet pas encore de confiance (menu Extensions).")
      STATUT("Ce projet contient " + #fichiers + " extension(s) non chargée(s) : Extensions ▸ Recharger les extensions pour les examiner et les charger.")
      pour chaque f dans fichiers
        inserer(exts.liste, {fichier = f, nom = fichier.nom(f), etat = "non chargée (confiance)", info = nul})
      suivant
      EXT_ACTUALISER_DIALOGUE()
      retourner
    finsi
    si non ui.confirmer("Ce projet contient " + #fichiers + " extension(s) : du code Lexis+ qui s'exécutera avec les " + ;
                        "droits de DuckDB Studio (fichiers, bases, réseau)." + car(10) + car(10) + ;
                        "Ne chargez que des extensions dont vous connaissez l'origine. Les charger et faire confiance à ce projet ?")
      pour chaque f dans fichiers
        inserer(exts.liste, {fichier = f, nom = fichier.nom(f), etat = "non chargée (confiance refusée)", info = nul})
      suivant
      EXT_ACTUALISER_DIALOGUE()
      retourner
    finsi
    projet.extensions_confiance = vrai
    ENREGISTRER_PROJET()
  finsi
  pour chaque f dans fichiers
    essayer
      locale noms = lexis.charger(f)
      locale trouve = faux
      pour chaque n dans noms
        si commencepar(n, "EXTENSION_")
          trouve = vrai
          locale info = appeler(lexis.procedure(n))
          si info = nul ou type(info) <> "table"
            inserer(exts.liste, {fichier = f, nom = n, etat = "erreur : " + n + "() doit renvoyer une table", info = nul})
          sinon
            inserer(exts.liste, {fichier = f, nom = sisinon(info.nom = nul, n, info.nom), etat = "chargée", info = info})
            EXT_INSTALLER(info)
          finsi
        finsi
      suivant
      si non trouve
        inserer(exts.liste, {fichier = f, nom = fichier.nom(f), etat = "chargée (aucune fonction EXTENSION_…)", info = nul})
      finsi
    capturer e
      inserer(exts.liste, {fichier = f, nom = fichier.nom(f), etat = "erreur : " + e, info = nul})
      JOURNAL("Extension " + fichier.nom(f) + " : " + e)
    finessayer
  suivant
  locale ok = 0
  pour chaque x dans exts.liste
    si x.etat = "chargée"
      ok += 1
    finsi
  suivant
  STATUT("Extensions : " + ok + " chargée(s) sur " + #exts.liste)
  EXT_ACTUALISER_DIALOGUE()
retourner

procedure EXT_INSTALLER(info)
  && onglet (une seule fois par titre) et entrées de menu
  si info.vue <> nul
    locale titre = sisinon(info.titrevue = nul, sisinon(info.nom = nul, "Extension", info.nom), info.titrevue)
    si exts.vues[titre] = nul
      locale page = vues:ajouterpage(titre, "bordure")
      exts.vues[titre] = page
      inserer(ordrevues, titre)
      essayer
        appeler(info.vue, page)
      capturer e
        JOURNAL("Extension « " + titre + " » : vue en erreur : " + e)
      finessayer
    finsi
  finsi
  si info.menus <> nul
    pour chaque m dans info.menus
      si m.libelle <> nul et m.action <> nul
        si exts.menus[m.libelle] = nul
          menu:ajouter("Extensions", m.libelle)
        finsi
        exts.menus[m.libelle] = m.action
      finsi
    suivant
  finsi
retourner

fonction REGLES_EXTENSIONS()
  locale l = {}
  si exts = nul
    retourner l
  finsi
  locale ctx = nul
  pour chaque x dans exts.liste
    si x.info <> nul et x.info.regles <> nul
      si ctx = nul
        ctx = {objets = TOUS_LES_OBJETS(), historique = projet.historique, plan = dernierplan, connexions = projet.connexions}
      finsi
      essayer
        locale r = appeler(x.info.regles, ctx)
        si r <> nul
          pour chaque reco dans r
            si reco.domaine = nul
              reco.domaine = "Extension"
            finsi
            inserer(l, reco)
          suivant
        finsi
      capturer e
        JOURNAL("Extension « " + x.nom + " » : règles en erreur : " + e)
      finessayer
    finsi
  suivant
retourner l

fonction MENU_EXTENSION(choix)
  && vrai si le choix de menu appartient à une extension (et l'exécute)
  si exts = nul ou exts.menus[choix] = nul
    retourner faux
  finsi
  essayer
    appeler(exts.menus[choix], nul)
  capturer e
    ERREUR("Extension : " + e)
  finessayer
retourner vrai

&&
&& Gestionnaire
&&

procedure EXT_GESTIONNAIRE
  si exts.dlg <> nul
    retourner
  finsi
  exts.dlg = ui.fenetre{titre = "Extensions du projet", largeur = 760, hauteur = 460, disposition = "bordure", sombre = reglages.sombre}
  exts.dlg.surfermeture = @EXT_FERMETURE
  locale haut = exts.dlg:ajouter(ui.rangee())
  haut.ancrage = "haut"
  OUTIL(haut, "Nouvelle extension…", @EXT_NOUVELLE, "Crée une extension à partir du modèle et l'ouvre dans l'éditeur")
  OUTIL(haut, "Ouvrir", @EXT_OUVRIR, "Ouvre le fichier de l'extension sélectionnée dans l'éditeur")
  OUTIL(haut, "Recharger", @EXT_RECHARGER, "Recharge toutes les extensions du projet")
  exts.zone = exts.dlg:ajouter(ui.panneau{disposition = "bordure", defilement = "masque"})
  exts.zone.ancrage = "centre"
  locale aide = exts.dlg:ajouter(ui.markdown("Dossier : `" + DOSSIER_EXTENSIONS() + "`. Une extension déclare des **règles** " + ;
    "d'expertise (ajoutées à Analyser), un **onglet** et des entrées du menu **Extensions**. Modèle commenté : " + ;
    "*Nouvelle extension…*."))
  aide.ancrage = "bas"
  aide.hauteurfixe = 90
  EXT_ACTUALISER_DIALOGUE()
retourner

procedure EXT_ACTUALISER_DIALOGUE
  si exts.dlg = nul
    retourner
  finsi
  si exts.table <> nul
    exts.table:detruire()
  finsi
  exts.table = exts.zone:ajouter(ui.tableau())
  exts.table.ancrage = "centre"
  exts.table:ajoutercolonne("Extension", 170)
  exts.table:ajoutercolonne("Version", 60)
  exts.table:ajoutercolonne("Apports", 170)
  exts.table:ajoutercolonne("Fichier", 140)
  exts.table:ajoutercolonne("État", 200)
  pour chaque x dans exts.liste
    locale apports = {}
    si x.info <> nul
      si x.info.regles <> nul
        inserer(apports, "règles")
      finsi
      si x.info.vue <> nul
        inserer(apports, "onglet")
      finsi
      si x.info.menus <> nul et #x.info.menus > 0
        inserer(apports, #x.info.menus + " menu(s)")
      finsi
    finsi
    exts.table:ajouterligne(x.nom, sisinon(x.info = nul ou x.info.version = nul, "", x.info.version), joindre(apports, ", "), ;
                            fichier.nom(x.fichier), x.etat)
  suivant
retourner

procedure EXT_FERMETURE(ev)
  exts.dlg = nul
  exts.table = nul
retourner

procedure EXT_RECHARGER(ev)
  EXTENSIONS_CHARGER(vrai)
retourner

procedure EXT_OUVRIR(ev)
  si exts.table = nul
    retourner
  finsi
  locale i = exts.table:selection()
  si i >= 1 et i <= #exts.liste
    locale u = ed:ouvrir(exts.liste[i].fichier)
    ed:langage("lexis", u)
    vues.valeur = 1
  finsi
retourner

procedure EXT_NOUVELLE(ev)
  locale nom = ui.demander("Nom de l'extension :", "Règles maison")
  si nom = nul ou rogner(nom) = ""
    retourner
  finsi
  locale code = majuscule(ALIAS({nom = nom}))
  locale d = DOSSIER_EXTENSIONS()
  fichier.creerdossier(d)
  locale chemin = fichier.joindre(d, minuscule(code) + ".prg")
  si fichier.existe(chemin)
    STATUT("L'extension « " + fichier.nom(chemin) + " » existe déjà.")
    retourner
  finsi
  locale modele = fichier.lire(fichier.joindre(fichier.joindre(systeme.dossierprogramme(), "modeles"), "extension.txt"))
  modele = remplacertexte(remplacertexte(modele, "{CODE}", code), "{NOM}", rogner(nom))
  fichier.ecrire(chemin, modele)
  locale u = ed:ouvrir(chemin)
  ed:langage("lexis", u)
  vues.valeur = 1
  STATUT("Extension créée : " + chemin + " — modifiez-la puis Extensions ▸ Recharger les extensions.")
  EXTENSIONS_CHARGER(vrai)
retourner
