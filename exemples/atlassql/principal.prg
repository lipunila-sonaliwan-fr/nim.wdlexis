&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atlas SQL : cartographie, analyse et outillage du patrimoine SQL Server, écrit en Lexis+.
&&
&&   wdlexisrt principal.prg [dossier_du_projet]
&&
&& Fichiers (le runtime les charge tous) :
&&   principal.prg     fenêtre, menus, navigation (explorateur, fil d'Ariane, historique,
&&                     favoris, recherche instantanée), propriétés, réglages, démarrage
&&   entrepot.prg      entrepôt local DuckDB (atlas.duckdb), utilitaires
&&   agents.prg        file d'attente des traitements, agents parallèles (3 à 10)
&&   sources.prg       sources SQL Server, extraction du catalogue, normalisation, campagnes
&&   demo.prg          système d'information de démonstration (3 serveurs)
&&   sqlanalyse.prg    analyseur T-SQL : jetons, instructions, AST, références, SQL dynamique
&&   dependances.prg   graphe orienté des dépendances, impact, flux
&&   analyses.prg      dictionnaire, types métier, duplications, performances, patrimoine
&&   vues.prg          tableau de bord, cartographie, dépendances, dictionnaire, flux…
&&   editeur.prg       éditeur SQL, synoptique, débogueur symbolique, refactoring
&&   interception.prg  capture (Extended Events), simulation et rejeu des appels
&&   assistant.prg     assistant expert (règles, modèle local GGUF ou serveur compatible OpenAI)
&&   menus.prg         menus, raccourcis, espaces de travail, à propos
ui = paquet("interface")

reglages = LIRE_REGLAGES()
dossier = ""
courant = nul               && objet affiché {id, serveur, base, sch, nom, genre}
historique = {}             && navigation : ids visités
poshist = 0
noeuds = {}                 && explorateur : chemin -> {genre, id, serveur, base, sch, g}
resultats = {}              && recherche : index -> id
vueactive = 1
fenpanneau = nul            && fenêtre du panneau de gauche quand il est détaché
panneau_affiche = vrai      && panneau de gauche présent dans la fenêtre principale

depart = systeme.args[1]
si depart = nul ou depart = ""
  depart = reglages.projet
finsi
si depart = nul ou depart = ""
  depart = fichier.joindre(fichier.dossierperso(), "AtlasSQL")
finsi
dossier = fichier.absolu(depart)
OUVRIR_ENTREPOT(dossier)
INIT_FILE()

fen = ui.fenetre{titre = "Atlas SQL — " + fichier.nom(dossier), largeur = 1600, hauteur = 960, disposition = "bordure", ;
                 sombre = reglages.sombre, etat = "agrandie", densite = "compacte"}
&& pas de marge autour de la fenêtre : chaque zone gère son propre espacement
fen.marge = 0
fen.espacement = 0
fen.surfermeture = @FERMETURE
fen.surtouchebas = @TOUCHE

menu = fen:ajouter(ui.barremenu())
CONSTRUIRE_MENUS(menu)
menu.surselection = @MENU

&& barre d'outils compacte (une seule ligne) : panneau · campagne · recherche et navigation · fil d'Ariane · file
barre = fen:ajouter(ui.rangee())
barre.ancrage = "haut"
barre.marge = 3
barre.espacement = 2
bpanneau = OUTIL(barre, "<<", @PANNEAU_BASCULER, "Masquer le panneau de gauche (navigation et propriétés)")
bpanneau.largeurfixe = 30
bfenpan = OUTIL(barre, "⧉", @PANNEAU_FENETRE, "Ouvrir le panneau de gauche dans une fenêtre séparée (second écran) ; le fermer le remet à gauche")
bfenpan.largeurfixe = 30
ESPACE_BARRE(barre)
OUTIL(barre, "+ Source", @NOUVELLE_SOURCE, "Déclarer un serveur SQL Server, une connexion ODBC ou un dossier de scripts")
OUTIL(barre, "▶ Analyser", @ANALYSER_TOUT, "Lancer la campagne complète (F5) : extraction, analyse du code, dépendances, dictionnaire…")
OUTIL(barre, "File", @VUE_FILE, "File d'attente des traitements et agents")
ESPACE_BARRE(barre)
recherche = barre:ajouter(ui.saisie{indication = "Rechercher… (Ctrl+F)"})
recherche.largeurfixe = 240
recherche.surchangement = @RECHERCHE
recherche.surtouchebas = @RECHERCHE_TOUCHE
bprec = OUTIL(barre, "◀", @PRECEDENT, "Objet précédent (Alt+←)")
bprec.largeurfixe = 28
bsuiv = OUTIL(barre, "▶", @SUIVANT, "Objet suivant (Alt+→)")
bsuiv.largeurfixe = 28
bfavori = OUTIL(barre, "☆", @BASCULER_FAVORI, "Ajouter l'objet courant aux favoris (Ctrl+D)")
bfavori.largeurfixe = 28
OUTIL(barre, "⌖ Recentrer", @RECENTRER, "Recentrer la cartographie sur l'objet courant")
OUTIL(barre, "Code", @OUVRIR_CODE_COURANT, "Ouvrir le code de l'objet courant dans l'éditeur")
OUTIL(barre, "Impact", @IMPACT_COURANT, "Analyse d'impact de l'objet courant")
ESPACE_BARRE(barre)
&& fil d'Ariane : dans la barre d'outils, il prend la place restante
ariane = barre:ajouter(ui.rangee())
ariane.poids = 1
ariane.marge = 0
ariane.espacement = 0
TRACER_ARIANE()
indic = barre:ajouter(ui.etiquette(""))
indic.couleur = "#FBBF24"

&& barre d'état : une ligne fine, collée au bord
pied = fen:ajouter(ui.rangee())
pied.ancrage = "bas"
pied.marge = 2
pied.espacement = 12
pied.hauteurfixe = 22
pied.fond = "#111827"
etat = pied:ajouter(ui.etiquette("Prêt"))
etat.poids = 1
etat.couleur = "#9CA3AF"
lblfile = pied:ajouter(ui.etiquette(""))
lblfile.couleur = "#9CA3AF"
lblbase = pied:ajouter(ui.etiquette(""))
lblbase.couleur = "#9CA3AF"

&& zone principale | panneaux du bas
sepbas = fen:ajouter(ui.separateur{vertical = faux, position = reglages.sep_bas})
sepbas.ancrage = "centre"
&& « centre » contient soit le séparateur (panneau | vues), soit les vues seules (panneau masqué ou
&& détaché) : aucun séparateur inutile ne reste alors à l'écran
centre = sepbas:ajouter(ui.conteneur("bordure"))
centre.marge = 0
centre.espacement = 0
sepg = centre:ajouter(ui.separateur{vertical = vrai, position = reglages.sep_gauche})
sepg.ancrage = "centre"

&& à gauche : le panneau de navigation (objets, recherche, favoris, récents, propriétés).
&& Il vit dans « hote » ; détaché, il part dans sa propre fenêtre et « hote » est masqué.
hote = sepg:ajouter(ui.conteneur("bordure"))
gauche = hote:ajouter(ui.onglets())
gauche.ancrage = "centre"
pexpl = gauche:ajouterpage("Objets", "bordure")
arbre = pexpl:ajouter(ui.arbre())
arbre.ancrage = "centre"
arbre.surselection = @EXPL_CHOIX
arbre.surdoubleclic = @EXPL_DOUBLE
arbre.surdeploiement = @EXPL_DEPLOIEMENT
prech = gauche:ajouterpage("Chercher", "bordure")
lrech = prech:ajouter(ui.liste())
lrech.ancrage = "centre"
lrech.surselection = @RECHERCHE_CHOIX
pfav = gauche:ajouterpage("Favoris", "bordure")
lfav = pfav:ajouter(ui.liste())
lfav.ancrage = "centre"
lfav.surselection = @FAVORI_CHOIX
phist = gauche:ajouterpage("Récents", "bordure")
lhist = phist:ajouter(ui.liste())
lhist.ancrage = "centre"
lhist.surselection = @HISTORIQUE_CHOIX
pprop = gauche:ajouterpage("Propriétés", "bordure")
fiche = pprop:ajouter(ui.markdown(ACCUEIL()))
fiche.ancrage = "centre"
fiche.surselection = @LIEN_FICHE

&& au centre : les vues (toute la largeur quand le panneau est masqué ou détaché)
vues = sepg:ajouter(ui.onglets())
vues.ancrage = "centre"
vues.surchangement = @VUE_CHANGEE
CONSTRUIRE_VUES(vues)
si reglages.panneau_masque = vrai
  AFFICHER_PANNEAU(faux)
finsi
ETAT_PANNEAU()

&& en bas : file d'attente, console, journal
bas = sepbas:ajouter(ui.onglets())
pfile = bas:ajouterpage("File d'attente", "bordure")
CONSTRUIRE_FILE(pfile)
pcons = bas:ajouterpage("Console", "bordure")
console = pcons:ajouter(ui.saisie{multiligne = vrai})
console.ancrage = "centre"
pjour = bas:ajouterpage("Journal", "bordure")
gjour = pjour:ajouter(ui.grille())
gjour.ancrage = "centre"
gjour:ajoutercolonne{nom = "quand", titre = "Quand", largeur = 150}
gjour:ajoutercolonne{nom = "niveau", titre = "Niveau", largeur = 80}
gjour:ajoutercolonne{nom = "message", titre = "Message", largeur = 900}
gjour:ajouterformat("niveau", "=", "erreur", {texte = "#F87171", ligneentiere = vrai})

ARBRE_SOURCES()
FAVORIS()
RAFRAICHIR_VUES()
ui.minuterie(300, @DISPATCHER, vrai)
si #SOURCES() = 0
  fiche.valeur = ACCUEIL()
finsi
ui.executer()

&&
&& Outils communs de l'interface
&&

fonction OUTIL(conteneur, libelle, proc, infobulle)
  && bouton de barre d'outils : plat (relief au survol), juste à la taille de son libellé
  locale b = conteneur:ajouter(ui.bouton(libelle, {plat = vrai}))
  b.surclic = proc
  si infobulle <> nul
    b.infobulle = infobulle
  finsi
retourner b

procedure ESPACE_BARRE(barre_)
  && petit filet vertical entre deux groupes de boutons
  locale e = barre_:ajouter(ui.etiquette(""))
  e.largeurfixe = 10
retourner

procedure STATUT(m)
  essayer
    etat.libelle = m
  capturer e
  finessayer
retourner

procedure TRACE(niveau, m)
  essayer
    locale c = console.valeur + "[" + heure() + "] " + niveau + " : " + m + car(10)
    si #c > 60000
      c = droite(c, 50000)
    finsi
    console.valeur = c
  capturer e
  finessayer
retourner

procedure PROPRIETES(md)
  fiche.valeur = MD(md)
retourner

procedure INDICATEUR_FILE(attente, encours, erreurs)
  locale t = ""
  si encours > 0 ou attente > 0
    t = "⚙ " + encours + " en cours · " + attente + " en attente"
  finsi
  si erreurs > 0
    t = t + sisinon(t = "", "", " · ") + "✖ " + erreurs + " erreur(s)"
  finsi
  lblfile.libelle = t
  indic.libelle = t
retourner

procedure FIN_DE_LOT
  RAFRAICHIR_FILE()
  locale ne = NB_ETAT("erreur")
  STATUT("Campagne terminée en " + DUREE_TEXTE(file.finlot - file.debut) + sisinon(ne > 0, " — " + ne + " travail(aux) en erreur", "") + ;
         ". Vues mises à jour.")
  JOURNAL("info", "Campagne " + file.lot + " terminée (" + NB_ETAT("termine") + " travaux)")
  ARBRE_SOURCES()
  RAFRAICHIR_VUES()
  RAFRAICHIR_JOURNAL()
retourner

procedure RAFRAICHIR_JOURNAL
  gjour:vider()
  pour chaque r dans RQ(nul, "select strftime(quand, '%Y-%m-%d %H:%M:%S') as q, niveau, message from journal order by quand desc limit 300", nul)
    gjour:ajouterligne(r.q, r.niveau, r.message)
  suivant
retourner

procedure VUE_FILE(ev)
  bas.valeur = 1
retourner

procedure FERMETURE(ev)
  && disposition mémorisée pour la prochaine ouverture
  essayer
    reglages.sep_gauche = nombre(sepg.valeur)
    reglages.sep_bas = nombre(sepbas.valeur)
  capturer e
  finessayer
  reglages.panneau_masque = fenpanneau = nul et non panneau_affiche
  ECRIRE_REGLAGES()
  essayer
    file.arret = vrai
  capturer e
  finessayer
  si srcdlg <> nul
    srcdlg:fermer()
  finsi
  si fenpanneau <> nul
    fenpanneau:fermer()
  finsi
retourner

procedure TOUCHE(ev)
  locale ctrl = ev.modificateurs <> nul et (ev.modificateurs % 256) >= 64
  locale alt = ev.modificateurs <> nul et (ev.modificateurs % 1024) >= 256
  faire cas
  cas ev.touche = 1073741886            && F5
    ANALYSER_TOUT(nul)
  cas ctrl et (ev.touche = 102 ou ev.touche = 70)
    recherche:focus()
  cas ctrl et (ev.touche = 100 ou ev.touche = 68)
    BASCULER_FAVORI(nul)
  cas alt et ev.touche = 1073741904
    PRECEDENT(nul)
  cas alt et ev.touche = 1073741903
    SUIVANT(nul)
  fincas
retourner

fonction ACCUEIL()
retourner joindre({"# Atlas SQL", "", ;
  "Cartographie, analyse et outillage du patrimoine **SQL Server**.", "", ;
  "1. **+ Source** : déclarez un serveur (extension DuckDB `mssql` ou ODBC), un dossier de scripts `.sql`, " + ;
  "ou ajoutez la **démonstration** (3 serveurs simulés).", ;
  "2. **▶ Analyser** (F5) : la campagne est découpée en travaux placés dans la **file d'attente** ; " + ;
  "de 3 à 10 **agents** les exécutent en parallèle, au plus N à la fois par serveur.", ;
  "3. Explorez : **Tableau de bord**, **Cartographie**, **Dépendances**, **Dictionnaire**, **Code SQL** " + ;
  "(synoptique, débogueur), **Flux**, **Performances**, **Patrimoine**, **Refactoring**, **Interception**, **Assistant**.", "", ;
  "Toutes les informations sont rangées en local dans `atlas.duckdb` (dossier du projet) ; " + ;
  "Atlas ne modifie jamais les bases analysées.", "", ;
  "Raccourcis : **F5** analyser · **Ctrl+F** rechercher · **Ctrl+D** favori · **Alt+← / →** historique"}, car(10))

&&
&& Explorateur : serveurs ▸ bases ▸ schémas ▸ genres ▸ objets (chargés à l'ouverture du dossier)
&&

procedure ARBRE_SOURCES
  globale noeuds
  arbre:vider()
  noeuds = {}
  locale sp = ui.sep
  locale lignes = RQ(nul, "select serveur, base, sch, genre, count(*) as n from objets " + ;
                          "where genre in ('TABLE', 'VUE', 'PROCEDURE', 'FONCTION', 'DECLENCHEUR', 'SYNONYME', 'SEQUENCE', 'TYPE', 'CLR') " + ;
                          "group by all order by serveur, base, sch, genre", nul)
  locale vus = {}
  pour chaque l dans lignes
    locale ps = "🖥 " + l.serveur
    locale pb = ps + sp + "🗄 " + l.base
    locale psc = pb + sp + l.sch
    locale pg = psc + sp + ICONE_GENRE(l.genre) + " " + LIBELLE_GENRE(l.genre) + "s (" + l.n + ")"
    si vus[ps] = nul
      vus[ps] = vrai
      noeuds[ps] = {genre = "SERVEUR", serveur = l.serveur}
    finsi
    si vus[pb] = nul
      vus[pb] = vrai
      noeuds[pb] = {genre = "BASE", serveur = l.serveur, base = l.base}
    finsi
    si vus[psc] = nul
      vus[psc] = vrai
      noeuds[psc] = {genre = "SCHEMA", serveur = l.serveur, base = l.base, sch = l.sch}
    finsi
    noeuds[pg] = {genre = "DOSSIER", serveur = l.serveur, base = l.base, sch = l.sch, g = l.genre, charge = faux}
    arbre:ajouter(pg + sp + "…")
  suivant
  && jobs SQL Agent : au niveau du serveur (ils vivent dans msdb, pas dans un schéma)
  pour chaque l dans RQ(nul, "select serveur, count(*) as n from objets where genre = 'JOB' group by serveur order by serveur", nul)
    locale pj = "🖥 " + l.serveur + sp + ICONE_GENRE("JOB") + " Jobs SQL Agent (" + l.n + ")"
    noeuds[pj] = {genre = "DOSSIER", serveur = l.serveur, g = "JOB", charge = faux}
    arbre:ajouter(pj + sp + "…")
  suivant
  && serveurs liés : au niveau du serveur
  pour chaque l dans RQ(nul, "select id, serveur, nom, cible from objets where genre = 'SERVEUR_LIE' order by 1", nul)
    locale p = "🖥 " + l.serveur + sp + "⇄ " + l.nom + " → " + l.cible
    noeuds[p] = {genre = "OBJET", id = l.id}
    arbre:ajouter(p)
  suivant
  && sources déclarées mais pas encore analysées (ou sans objet) : visibles tout de suite
  pour chaque src dans RQ(nul, "select s.* from sources s where not exists (select 1 from objets o where o.source_id = s.id) " + ;
                              "order by s.id", nul)
    locale etiq = sisinon(src.genre = "dossier", "📁 ", "🖥 ") + src.nom + "  (" + ;
                  sisinon(src.genre = "dossier", src.dossier, src.serveur) + ") — à analyser (F5)"
    noeuds[etiq] = {genre = "SOURCE", id = src.id}
    arbre:ajouter(etiq)
  suivant
  pour chaque k, v dans noeuds
    si v.genre = "SERVEUR"
      arbre:deplier(k)
    finsi
  suivant
  locale n = RV(nul, "select count(*) from objets", nul)
  lblbase.libelle = "🗃 " + NB(n) + " objets · " + fichier.nom(dossier) + "/atlas.duckdb"
  si #lignes = 0 et #SOURCES() = 0
    arbre:ajouter("Aucune source : + Source, puis ▶ Analyser")
  finsi
retourner

procedure CHARGER_DOSSIER(chemin)
  locale nd = noeuds[chemin]
  si nd = nul ou nd.genre <> "DOSSIER" ou nd.charge
    retourner
  finsi
  nd.charge = vrai
  arbre:supprimer(chemin + ui.sep + "…")
  pour chaque o dans RQ(nul, "select o.id, o.nom, o.genre, coalesce(m.classe, '') as classe, d.rgpd from objets o " + ;
                             "left join metriques m on m.objet_id = o.id left join dico_tables d on d.objet_id = o.id " + ;
                             "where o.serveur = ? and (? = '' or (o.base = ? and o.sch = ?)) and o.genre = ? order by o.nom", ;
                             {nd.serveur, sisinon(nd.base = nul, "", nd.base), sisinon(nd.base = nul, "", nd.base), sisinon(nd.sch = nul, "", nd.sch), nd.g})
    locale marque = ""
    si "Critique" $ o.classe
      marque = marque + " ◆"
    finsi
    si o.rgpd = vrai
      marque = marque + " 🔒"
    finsi
    si "Inutilisé" $ o.classe ou "Obsolète" $ o.classe
      marque = marque + " ∅"
    finsi
    locale p = chemin + ui.sep + o.nom + marque
    noeuds[p] = {genre = "OBJET", id = o.id}
    arbre:ajouter(p)
  suivant
retourner

procedure EXPL_DEPLOIEMENT(ev)
  CHARGER_DOSSIER(ev.texte)
retourner

procedure EXPL_CHOIX(ev)
  locale nd = noeuds[ev.texte]
  si nd = nul
    retourner
  finsi
  faire cas
  cas nd.genre = "OBJET"
    ALLER_OBJET(nd.id, "explorateur")
  cas nd.genre = "DOSSIER"
    CHARGER_DOSSIER(ev.texte)
    arbre:deplier(ev.texte)
  cas nd.genre = "SOURCE"
    FICHE_SOURCE(nd.id)
  autrement
    FICHE_CONTENEUR(nd)
  fincas
retourner

procedure FICHE_SOURCE(id)
  locale src = SOURCE(id)
  si src = nul
    retourner
  finsi
  locale md = {"## " + sisinon(src.genre = "dossier", "📁 ", "🖥 ") + src.nom, ""}
  inserer(md, "- **Genre** : " + src.genre)
  si src.genre = "dossier"
    inserer(md, "- **Dossier** : " + MDCODE(src.dossier))
  sinon
    inserer(md, "- **Serveur** : " + MDCODE(src.serveur))
    inserer(md, "- **Bases** : " + sisinon(src.base = nul ou src.base = "", "toutes les bases utilisateur", src.base))
    inserer(md, "- **Authentification** : " + src.auth + sisinon(src.utilisateur = nul ou src.utilisateur = "", "", " (" + src.utilisateur + ")"))
  finsi
  inserer(md, "- **Dernière analyse** : " + sisinon(src.analysee = nul, "jamais", gauche(chaine(src.analysee), 16)))
  inserer(md, "")
  inserer(md, "Lancez **▶ Analyser** (F5) pour l'inventorier. Double-clic sur la source pour la modifier.")
  PROPRIETES(joindre(md, car(10)))
retourner

procedure EXPL_DOUBLE(ev)
  locale nd = noeuds[arbre.valeur]
  si nd = nul
    retourner
  finsi
  si nd.genre = "OBJET"
    OUVRIR_CODE(nd.id)
  sinonsi nd.genre = "SOURCE"
    SOURCE_DIALOGUE(SOURCE(nd.id))
  sinon
    CARTO_NIVEAU(nd)
  finsi
retourner

&&
&& Navigation : objet courant, fil d'Ariane, historique, favoris
&&

fonction OBJET(id)
  locale r = RQ(nul, "select * from objets where id = ?", {id})
  si #r = 0
    retourner nul
  finsi
retourner r[1]

procedure ALLER_OBJET(id, origine)
  globale courant, poshist, historique
  locale o = OBJET(id)
  si o = nul
    retourner
  finsi
  courant = o
  si origine <> "historique"
    && tronque l'historique « en avant », puis empile
    tantque #historique > poshist
      retirer(historique)
    fintantque
    si #historique = 0 ou historique[#historique] <> id
      inserer(historique, id)
    finsi
    poshist = #historique
    lhist:inserer(1, LIBELLE_GENRE(o.genre) + " · " + o.sch + "." + o.nom)
  finsi
  TRACER_ARIANE()
  FICHE_OBJET(o)
  bfavori.libelle = sisinon(EST_FAVORI(o.cle), "★", "☆")
  RAFRAICHIR_VUE_OBJET()
retourner

procedure PRECEDENT(ev)
  globale poshist
  si poshist > 1
    poshist -= 1
    ALLER_OBJET(historique[poshist], "historique")
  finsi
retourner

procedure SUIVANT(ev)
  globale poshist
  si poshist < #historique
    poshist += 1
    ALLER_OBJET(historique[poshist], "historique")
  finsi
retourner

procedure HISTORIQUE_CHOIX(ev)
  && la liste est en ordre inverse (le plus récent en haut)
  locale i = #historique - ev.index + 1
  si i >= 1 et i <= #historique
    ALLER_OBJET(historique[i], "historique")
  finsi
retourner

procedure TRACER_ARIANE
  globale miettes
  si miettes <> nul
    pour chaque m dans miettes
      m.ctl:detruire()
    suivant
  finsi
  miettes = {}
  locale l0 = ariane:ajouter(ui.etiquette(" ⌂ "))
  l0.couleur = "#6B7280"
  inserer(miettes, {ctl = l0})
  si courant = nul
    locale l1 = ariane:ajouter(ui.etiquette("Sélectionnez un objet (explorateur, carte ou recherche)"))
    l1.couleur = "#9CA3AF"
    inserer(miettes, {ctl = l1})
    retourner
  finsi
  locale niveaux = {{"🖥 " + courant.serveur, {genre = "SERVEUR", serveur = courant.serveur}}, ;
                    {"🗄 " + courant.base, {genre = "BASE", serveur = courant.serveur, base = courant.base}}, ;
                    {courant.sch, {genre = "SCHEMA", serveur = courant.serveur, base = courant.base, sch = courant.sch}}, ;
                    {ICONE_GENRE(courant.genre) + " " + courant.nom, {genre = "OBJET", id = courant.id}}}
  pour i = 1 a #niveaux
    si niveaux[i][1] <> "" et niveaux[i][1] <> "🗄 "
      locale b = ariane:ajouter(ui.bouton(niveaux[i][1], {plat = vrai}))
      b.surclic = @ARIANE_CLIC
      si i = #niveaux
        b.couleur = "#93C5FD"
      finsi
      b.infobulle = "Cartographie de ce niveau"
      inserer(miettes, {ctl = b, niveau = niveaux[i][2]})
      si i < #niveaux
        locale sepm = ariane:ajouter(ui.etiquette("›"))
        sepm.couleur = "#6B7280"
        inserer(miettes, {ctl = sepm})
      finsi
    finsi
  suivant
retourner

procedure ARIANE_CLIC(ev)
  pour chaque m dans miettes
    si m.niveau <> nul et ev.id = m.ctl
      CARTO_NIVEAU(m.niveau)
      retourner
    finsi
  suivant
retourner

fonction EST_FAVORI(cle)
retourner RV(nul, "select count(*) from favoris where cle = ?", {cle}) > 0

procedure BASCULER_FAVORI(ev)
  si courant = nul
    retourner
  finsi
  si EST_FAVORI(courant.cle)
    RQ(nul, "delete from favoris where cle = ?", {courant.cle})
    bfavori.libelle = "☆"
  sinon
    RQ(nul, "insert into favoris values (?, ?, now())", {courant.cle, LIBELLE_GENRE(courant.genre) + " · " + ;
       courant.serveur + " › " + courant.base + " › " + courant.sch + "." + courant.nom})
    bfavori.libelle = "★"
  finsi
  FAVORIS()
retourner

procedure FAVORIS
  globale favoris_ids
  lfav:vider()
  favoris_ids = {}
  pour chaque f dans RQ(nul, "select f.libelle, o.id from favoris f join objets o on o.cle = f.cle order by f.cree desc", nul)
    lfav:ajouter("★ " + f.libelle)
    inserer(favoris_ids, f.id)
  suivant
retourner

procedure FAVORI_CHOIX(ev)
  si ev.index >= 1 et ev.index <= #favoris_ids
    ALLER_OBJET(favoris_ids[ev.index], "favori")
  finsi
retourner

&&
&& Recherche instantanée (objets, colonnes, texte du code)
&&

procedure RECHERCHE(ev)
  globale resultats, version_recherche
  version_recherche = sisinon(version_recherche = nul, 0, version_recherche) + 1
  locale v = version_recherche
  locale q = rogner(sisinon(recherche.valeur = nul, "", recherche.valeur))
  si #q < 2
    lrech:vider()
    resultats = {}
    retourner
  finsi
  locale motif = "%" + q + "%"
  locale lignes = RQ(nul, "select id, genre, serveur, base, sch, nom, 1 as rang from objets where nom ilike ? " + ;
                             "and genre in ('TABLE', 'VUE', 'PROCEDURE', 'FONCTION', 'DECLENCHEUR', 'SYNONYME', 'JOB', 'SERVEUR_LIE', 'SEQUENCE', 'TYPE') " + ;
                             "union all select distinct c.objet_id, 'COLONNE', c.serveur, c.base, c.sch, c.table_nom || '.' || c.nom, 2 " + ;
                             "from colonnes c where c.nom ilike ? " + ;
                             "union all select d.objet_id, 'METIER', o.serveur, o.base, o.sch, o.nom || ' — ' || d.objet_metier, 3 " + ;
                             "from dico_tables d join objets o on o.id = d.objet_id where d.objet_metier ilike ? " + ;
                             "union all select id, 'CODE', serveur, base, sch, nom, 4 from objets where definition ilike ? and nom not ilike ? " + ;
                             "order by rang, nom limit 250", {motif, motif, motif, motif, motif})
  si v <> version_recherche
    && une frappe plus récente a relancé la recherche : on abandonne celle-ci
    retourner
  finsi
  lrech:vider()
  resultats = {}
  pour chaque r dans lignes
    locale lib = faire_libelle_recherche(r)
    lrech:ajouter(lib)
    inserer(resultats, r.id)
  suivant
  si #resultats > 0
    gauche.valeur = 2
  finsi
  STATUT(chaine(#resultats) + " résultat(s) pour « " + q + " » (objets, colonnes, objets métier, code)")
retourner

fonction faire_libelle_recherche(r)
  faire cas
  cas r.genre = "COLONNE"
    retourner "▤ " + r.nom + "   (" + r.serveur + " › " + r.base + "." + r.sch + ")"
  cas r.genre = "METIER"
    retourner "◎ " + r.nom
  cas r.genre = "CODE"
    retourner "⌕ cité dans " + r.sch + "." + r.nom
  fincas
retourner ICONE_GENRE(r.genre) + " " + r.sch + "." + r.nom + "   (" + r.serveur + " › " + r.base + ")"

procedure RECHERCHE_TOUCHE(ev)
  si ev.touche = 13 et #resultats > 0
    ALLER_OBJET(resultats[1], "recherche")
  finsi
retourner

procedure RECHERCHE_CHOIX(ev)
  si ev.index >= 1 et ev.index <= #resultats
    ALLER_OBJET(resultats[ev.index], "recherche")
  finsi
retourner

&&
&& Fiches de propriétés
&&

procedure FICHE_CONTENEUR(nd)
  locale md = {}
  faire cas
  cas nd.genre = "SERVEUR"
    inserer(md, "# 🖥 " + nd.serveur)
    pour chaque r dans RQ(nul, "select base, count(*) as n, sum(case when genre = 'TABLE' then 1 else 0 end) as t, " + ;
                               "sum(case when genre in ('PROCEDURE', 'FONCTION') then 1 else 0 end) as p, sum(coalesce(taille_ko, 0)) as ko " + ;
                               "from objets where serveur = ? and genre in ('TABLE', 'VUE', 'PROCEDURE', 'FONCTION', 'DECLENCHEUR') group by base order by base", {nd.serveur})
      inserer(md, "- **" + r.base + "** : " + r.n + " objets (" + r.t + " tables, " + r.p + " procédures/fonctions), " + NB(r.ko / 1024) + " Mo")
    suivant
    inserer(md, "")
    inserer(md, "### Serveurs liés")
    pour chaque r dans RQ(nul, "select nom, cible from objets where serveur = ? and genre = 'SERVEUR_LIE'", {nd.serveur})
      inserer(md, "- " + MDCODE(r.nom) + " → " + r.cible)
    suivant
    inserer(md, "")
    inserer(md, "### Jobs SQL Agent")
    pour chaque r dans RQ(nul, "select nom, cible, detail from objets where serveur = ? and genre = 'JOB' order by nom", {nd.serveur})
      inserer(md, "- " + r.nom + " — " + r.cible + ", " + r.detail)
    suivant
  cas nd.genre = "BASE" ou nd.genre = "SCHEMA"
    inserer(md, "# " + sisinon(nd.genre = "BASE", "🗄 " + nd.base, nd.base + "." + nd.sch))
    locale filtre = sisinon(nd.genre = "BASE", "", " and sch = ?")
    locale p = sisinon(nd.genre = "BASE", {nd.serveur, nd.base}, {nd.serveur, nd.base, nd.sch})
    inserer(md, "| Genre | Nombre |")
    inserer(md, "|---|---:|")
    pour chaque r dans RQ(nul, "select genre, count(*) as n from objets where serveur = ? and base = ?" + filtre + " group by genre order by n desc", p)
      inserer(md, "| " + ICONE_GENRE(r.genre) + " " + LIBELLE_GENRE(r.genre) + " | " + r.n + " |")
    suivant
    inserer(md, "")
    inserer(md, "### Plus grosses tables")
    pour chaque r dans RQ(nul, "select sch, nom, lignes, taille_ko from objets where serveur = ? and base = ?" + filtre + ;
                               " and genre = 'TABLE' order by lignes desc nulls last limit 8", p)
      inserer(md, "- " + r.sch + "." + r.nom + " — " + NB(r.lignes) + " lignes, " + NB(r.taille_ko / 1024) + " Mo")
    suivant
  fincas
  inserer(md, "")
  inserer(md, "*Double-clic : cartographie de ce niveau.*")
  PROPRIETES(joindre(md, car(10)))
retourner

procedure FICHE_OBJET(o)
  locale md = {}
  inserer(md, "# " + ICONE_GENRE(o.genre) + " " + o.nom)
  inserer(md, "**" + LIBELLE_GENRE(o.genre) + "** · " + o.serveur + " › " + o.base + " › " + o.sch)
  inserer(md, "")
  locale d = RQ(nul, "select * from dico_tables where objet_id = ?", {o.id})
  si #d > 0
    inserer(md, "> " + d[1].description)
    inserer(md, "")
  finsi
  inserer(md, "| | |")
  inserer(md, "|---|---|")
  si o.proprietaire <> nul
    inserer(md, "| Propriétaire | " + o.proprietaire + " |")
  finsi
  si o.cree <> nul
    inserer(md, "| Créé le | " + gauche(chaine(o.cree), 16) + " |")
  finsi
  si o.modifie <> nul
    inserer(md, "| Modifié le | " + gauche(chaine(o.modifie), 16) + " |")
  finsi
  si o.lignes <> nul
    inserer(md, "| Lignes | " + NB(o.lignes) + " |")
  finsi
  si o.taille_ko <> nul
    inserer(md, "| Taille | " + NB(o.taille_ko / 1024) + " Mo |")
  finsi
  si o.cible <> nul et o.cible <> ""
    inserer(md, "| " + sisinon(o.genre = "JOB", "Fréquence", "Cible") + " | " + MDCELL(o.cible) + " |")
  finsi
  si o.detail <> nul et o.detail <> ""
    inserer(md, "| Détail | " + MDCELL(o.detail) + " |")
  finsi
  si #d > 0
    inserer(md, "| Objet métier | " + d[1].objet_metier + " (" + d[1].famille + ") |")
    inserer(md, "| Nature | " + d[1].nature + " |")
    inserer(md, "| Sensibilité | " + d[1].sensibilite + sisinon(d[1].rgpd, " · **RGPD**", "") + " |")
  finsi
  locale m = RQ(nul, "select * from metriques where objet_id = ?", {o.id})
  si #m > 0
    si m[1].lignes_code <> nul et m[1].lignes_code > 0
      inserer(md, "| Code | " + m[1].lignes_code + " lignes, " + m[1].nb_instructions + " instructions |")
      inserer(md, "| Complexité | " + m[1].complexite + sisinon(m[1].maintenabilite = nul, "", " · maintenabilité " + arrondi(m[1].maintenabilite) + "/100") + " |")
    finsi
    si m[1].dette_min <> nul
      inserer(md, "| Dette | " + arrondi(m[1].dette_min) + " min · score de risque " + arrondi(sisinon(m[1].score = nul, 0, m[1].score)) + "/100 |")
    finsi
    si m[1].classe <> nul et m[1].classe <> ""
      inserer(md, "| Classement | **" + m[1].classe + "** |")
    finsi
  finsi
  locale st = INDICATEURS_REQUETE(o.id)
  si #st > 0 et st[1].executions <> nul
    inserer(md, "| Exécutions | " + NB(st[1].executions) + " · " + arrondi(st[1].temps_ms, 1) + " ms en moyenne · CPU " + arrondi(st[1].cpu_ms, 1) + " ms |")
  finsi
  locale ns = RV(nul, "select count(distinct vers_id) from dependances where de_id = ?", {o.id})
  locale ne = RV(nul, "select count(distinct de_id) from dependances where vers_id = ?", {o.id})
  inserer(md, "| Dépendances | utilise **" + ns + "** · utilisé par **" + ne + "** |")
  inserer(md, "")
  && colonnes
  locale cols = RQ(nul, "select c.nom, c.type_sql, c.pk, c.nullable, c.fk_vers, d.rgpd, d.categorie_rgpd from colonnes c " + ;
                        "left join dico_colonnes d on d.objet_id = c.objet_id and d.colonne = c.nom where c.objet_id = ? order by c.ordre", {o.id})
  si #cols > 0
    inserer(md, "### Colonnes (" + #cols + ")")
    pour chaque c dans cols
      inserer(md, "- " + sisinon(c.pk, "🔑 ", "") + "**" + c.nom + "** " + MDCODE(c.type_sql) + sisinon(c.nullable, "", " non nul") + ;
                  sisinon(c.fk_vers = nul, "", " → " + c.fk_vers) + sisinon(c.rgpd = vrai, " 🔒 *" + c.categorie_rgpd + "*", ""))
    suivant
    inserer(md, "")
  finsi
  && paramètres
  locale ps = RQ(nul, "select nom, type_sql, defaut from variables where objet_id = ? and genre = 'parametre' order by ligne", {o.id})
  si #ps > 0
    inserer(md, "### Paramètres")
    pour chaque p dans ps
      inserer(md, "- " + MDCODE(p.nom) + " " + p.type_sql + sisinon(p.defaut = "", "", " = " + MDCODE(p.defaut)))
    suivant
    inserer(md, "")
  finsi
  && constats
  locale dg = RQ(nul, "select niveau, message, ligne from diagnostics where objet_id = ? order by case niveau when 'critique' then 1 " + ;
                      "when 'important' then 2 else 3 end limit 12", {o.id})
  si #dg > 0
    inserer(md, "### Constats")
    pour chaque x dans dg
      inserer(md, "- " + PASTILLE_NIVEAU(x.niveau) + " " + MDCELL(x.message) + sisinon(x.ligne = nul, "", " *(ligne " + x.ligne + ")*"))
    suivant
    inserer(md, "")
  finsi
  si o.definition <> nul
    inserer(md, "[Ouvrir le code](atlas:code) · [Dépendances](atlas:dep) · [Impact](atlas:impact) · [Cartographie](atlas:carto)")
  sinon
    inserer(md, "[Dépendances](atlas:dep) · [Impact](atlas:impact) · [Cartographie](atlas:carto)")
  finsi
  PROPRIETES(joindre(md, car(10)))
retourner

fonction PASTILLE_NIVEAU(n)
  faire cas
  cas n = "critique"
    retourner "⬤"
  cas n = "important"
    retourner "▲"
  cas n = "opportunite"
    retourner "◇"
  fincas
retourner "○"

procedure LIEN_FICHE(ev)
  locale u = ev.texte
  si courant = nul
    retourner
  finsi
  faire cas
  cas u = "atlas:code"
    OUVRIR_CODE(courant.id)
  cas u = "atlas:dep"
    VOIR_VUE("Dépendances")
  cas u = "atlas:impact"
    IMPACT_COURANT(nul)
  cas u = "atlas:carto"
    RECENTRER(nul)
  fincas
retourner

&&
&& Panneau de gauche : visible (<<), masqué (>>) ou détaché dans sa fenêtre (⧉)
&&

procedure ETAT_PANNEAU
  && libellés des deux boutons selon l'état du panneau
  si fenpanneau <> nul
    bpanneau.libelle = ">>"
    bpanneau.infobulle = "Remettre le panneau à gauche (ferme sa fenêtre)"
    bfenpan.libelle = "⧈"
    bfenpan.infobulle = "Remettre le panneau dans la fenêtre principale"
  sinonsi panneau_affiche
    bpanneau.libelle = "<<"
    bpanneau.infobulle = "Masquer le panneau de gauche : toute la place pour les vues"
    bfenpan.libelle = "⧉"
    bfenpan.infobulle = "Ouvrir le panneau de gauche dans une fenêtre séparée (second écran)"
  sinon
    bpanneau.libelle = ">>"
    bpanneau.infobulle = "Réafficher le panneau de gauche (à sa taille précédente)"
    bfenpan.libelle = "⧉"
    bfenpan.infobulle = "Ouvrir le panneau de gauche dans une fenêtre séparée (second écran)"
  finsi
retourner

procedure AFFICHER_PANNEAU(v)
  && visible : séparateur (panneau | vues) ; sinon les vues seules occupent toute la zone centrale.
  && Le séparateur n'est pas recréé : il garde sa position, donc la largeur du panneau.
  globale panneau_affiche
  si v = panneau_affiche
    retourner
  finsi
  panneau_affiche = v
  si v
    sepg:ajouter(vues)
    sepg.visible = vrai
  sinon
    centre:ajouter(vues)
    sepg.visible = faux
  finsi
retourner

procedure PANNEAU_BASCULER(ev)
  si fenpanneau <> nul
    PANNEAU_RATTACHER()
    retourner
  finsi
  && le séparateur garde sa position : le panneau revient à la même largeur
  AFFICHER_PANNEAU(non panneau_affiche)
  ETAT_PANNEAU()
retourner

procedure PANNEAU_FENETRE(ev)
  globale fenpanneau
  si fenpanneau <> nul
    PANNEAU_RATTACHER()
    retourner
  finsi
  fenpanneau = ui.fenetre{titre = "Atlas SQL — Navigation et propriétés", largeur = 460, hauteur = 900, ;
                          disposition = "bordure", sombre = reglages.sombre, densite = "compacte"}
  fenpanneau.marge = 0
  fenpanneau.surfermeture = @PANNEAU_FERME
  fenpanneau.surtouchebas = @TOUCHE
  fenpanneau:ajouter(gauche)
  AFFICHER_PANNEAU(faux)
  ETAT_PANNEAU()
  STATUT("Panneau détaché : fermez sa fenêtre (ou ⧈ / >>) pour le remettre à gauche.")
retourner

procedure PANNEAU_RATTACHER
  && ramène les pages dans la fenêtre principale, puis ferme la fenêtre dédiée
  globale fenpanneau
  locale f = fenpanneau
  fenpanneau = nul
  hote:ajouter(gauche)
  AFFICHER_PANNEAU(vrai)
  si f <> nul
    essayer
      f:fermer()
    capturer e
    finessayer
  finsi
  ETAT_PANNEAU()
  STATUT("Panneau remis à gauche.")
retourner

procedure PANNEAU_FERME(ev)
  && fenêtre fermée par sa case : les pages réapparaissent à gauche
  globale fenpanneau
  si fenpanneau <> nul
    fenpanneau = nul
    hote:ajouter(gauche)
    AFFICHER_PANNEAU(vrai)
    ETAT_PANNEAU()
    STATUT("Panneau remis à gauche.")
  finsi
retourner

procedure OUVRIR_CODE_COURANT(ev)
  si courant <> nul
    OUVRIR_CODE(courant.id)
  finsi
retourner
