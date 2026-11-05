&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atlas SQL : file d'attente des traitements et agents parallèles.
&&
&& * Un travail : {id, genre, libellé, cible, priorité 1 (urgente) à 5, état, agent,
&&   progression, dépendances (apres), serveur}. États : attente, encours, termine,
&&   erreur, annule, bloque (une dépendance a échoué).
&& * Un agent : un fil (minuterie à un coup) et sa session SQL (sessionsql()) sur
&&   l'entrepôt. Il prend le travail prêt le plus prioritaire, l'exécute, recommence ;
&&   il s'arrête quand la file est vide, en pause, ou si le nombre d'agents baisse.
&& * Nombre d'agents réglable de 3 à 10 (curseur) ; par serveur, au plus N agents en
&&   même temps (« par serveur ») pour ne pas surcharger les bases interrogées.
&& * Pendant qu'un agent attend SQL Server ou DuckDB, l'interpréteur est libre : les
&&   autres agents et l'interface continuent. Le choix d'un travail ne fait aucune
&&   attente : il est donc atomique.
&& * Chaque travail terminé est enregistré dans la table travaux (historique).

procedure INIT_FILE
  globale file
  file = {travaux = {}, parid = {}, numero = 0, lot = 0, pause = faux, arret = faux, agents = {}, demarrages = {}, ;
          debut = nul, termines = 0, affichage = {}, ganttversion = -1, version = 0, finlot = nul, ;
          rappels = {}}
  locale m = RV(nul, "select coalesce(max(id), 0) from travaux", nul)
  file.numero = sisinon(m = nul, 0, m)
  locale l = RV(nul, "select coalesce(max(lot), 0) from travaux", nul)
  file.lot = sisinon(l = nul, 0, l)
  pour i = 1 a 10
    inserer(file.agents, {num = i, fil = faux, session = nul, travail = nul, faits = 0, occupe = 0, depuis = nul})
  suivant
retourner

fonction NOUVEAU_LOT()
  file.lot += 1
  file.debut = systeme.horloge()
  file.termines = 0
retourner file.lot

fonction AJOUTER_TRAVAIL(genre, libelle, cible, params)
  && params : {source_id, serveur, priorite, apres = {ids}, …} ; renvoie l'id
  file.numero += 1
  locale t = {id = file.numero, lot = file.lot, genre = genre, libelle = libelle, cible = sisinon(cible = nul, "", cible), ;
              source_id = nul, serveur = "", priorite = 3, etat = "attente", agent = nul, cree = systeme.horloge(), ;
              debut = nul, fin = nul, duree = nul, progression = 0, message = "", essais = 0, apres = {}, params = {}, ;
              annule = faux}
  si params <> nul
    pour chaque k, v dans params
      faire cas
      cas k = "SOURCE_ID"
        t.source_id = v
      cas k = "SERVEUR"
        t.serveur = v
      cas k = "PRIORITE"
        t.priorite = v
      cas k = "APRES"
        t.apres = v
      autrement
        t.params[k] = v
      fincas
    suivant
  finsi
  inserer(file.travaux, t)
  file.parid[chaine(t.id)] = t
  file.version += 1
retourner t.id

procedure DEPEND(id, autre)
  && le travail id attendra aussi le travail autre (ajout dynamique)
  locale t = file.parid[chaine(id)]
  si t <> nul
    inserer(t.apres, autre)
  finsi
retourner

fonction TRAVAIL(id)
retourner file.parid[chaine(id)]

&&
&& Choix d'un travail (sans attente : atomique pour l'interpréteur)
&&

fonction DANS_LISTE(v, l)
  si l = nul
    retourner faux
  finsi
  pour chaque e dans l
    si e = v
      retourner vrai
    finsi
  suivant
retourner faux

fonction PRET(t)
  && "oui", "non" (attendre) ou "bloque" (une dépendance a échoué)
  pour chaque d dans t.apres
    locale x = file.parid[chaine(d)]
    si x <> nul
      si x.etat = "erreur" ou x.etat = "annule" ou x.etat = "bloque"
        && dépendance « souple » : son échec n'empêche pas ce travail (il travaille avec ce qui existe)
        si non DANS_LISTE(d, t.params.souples)
          retourner "bloque"
        finsi
      sinonsi x.etat <> "termine"
        retourner "non"
      finsi
    finsi
  suivant
retourner "oui"

fonction PRENDRE_TRAVAIL(a)
  si file.pause ou file.arret
    retourner nul
  finsi
  && agents occupés par serveur
  locale parsrv = {}
  pour chaque x dans file.travaux
    si x.etat = "encours" et x.serveur <> ""
      parsrv[x.serveur] = sisinon(parsrv[x.serveur] = nul, 0, parsrv[x.serveur]) + 1
    finsi
  suivant
  locale meilleur = nul
  pour chaque t dans file.travaux
    si t.etat = "attente"
      locale p = PRET(t)
      si p = "bloque"
        t.etat = "bloque"
        t.message = "Une dépendance a échoué ou a été annulée"
        file.version += 1
      sinonsi p = "oui"
        locale ok = t.serveur = "" ou parsrv[t.serveur] = nul ou parsrv[t.serveur] < reglages.parserveur
        si ok et (meilleur = nul ou t.priorite < meilleur.priorite)
          meilleur = t
        finsi
      finsi
    finsi
  suivant
  si meilleur <> nul
    meilleur.etat = "encours"
    meilleur.agent = a.num
    meilleur.debut = systeme.horloge()
    meilleur.progression = 0
    a.travail = meilleur
    file.version += 1
  finsi
retourner meilleur

fonction RESTE_A_FAIRE()
  pour chaque t dans file.travaux
    si t.etat = "attente" et PRET(t) = "oui"
      retourner vrai
    finsi
  suivant
retourner faux

fonction NB_ETAT(etat)
  locale n = 0
  pour chaque t dans file.travaux
    si t.etat = etat
      n += 1
    finsi
  suivant
retourner n

&&
&& Agents
&&

procedure DISPATCHER(ev)
  && minuterie (300 ms) : démarre les agents nécessaires, puis rafraîchit l'affichage
  si file = nul
    retourner
  finsi
  si non file.pause et non file.arret et RESTE_A_FAIRE()
    pour i = 1 a reglages.agents
      locale a = file.agents[i]
      si non a.fil
        a.fil = vrai
        inserer(file.demarrages, i)
        ui.minuterie(5, @AGENT_FIL, faux)
      finsi
    suivant
  finsi
  && fin de lot : tout est terminé et aucun agent ne travaille
  si file.finlot = nul et #file.travaux > 0 et NB_ETAT("attente") = 0 et NB_ETAT("encours") = 0
    file.finlot = systeme.horloge()
    FIN_DE_LOT()
  finsi
  si ev = nul ou ev.tops % 2 = 0
    RAFRAICHIR_FILE()
  finsi
retourner

procedure AGENT_FIL(ev)
  locale n = retirer(file.demarrages, 1)
  si n = nul
    retourner
  finsi
  locale a = file.agents[n]
  si a.session = nul
    a.session = sessionsql()
  finsi
  tantque non file.arret et non file.pause et a.num <= reglages.agents
    locale t = PRENDRE_TRAVAIL(a)
    si t = nul
      sortir
    finsi
    EXECUTER_TRAVAIL(a, t)
  fintantque
  a.travail = nul
  a.fil = faux
retourner

procedure EXECUTER_TRAVAIL(a, t)
  locale h0 = systeme.horloge()
  essayer
    TRAVAIL_EXECUTER(a.session, t)
    si t.annule
      t.etat = "annule"
    sinon
      t.etat = "termine"
      t.progression = 1
      si t.message = ""
        t.message = "OK"
      finsi
    finsi
  capturer e
    si t.annule ou file.arret
      t.etat = "annule"
      t.message = "Annulé"
    sinon
      t.etat = "erreur"
      t.message = COURT(e, 400)
      JOURNAL("erreur", "Travail " + t.id + " (" + t.libelle + ") : " + e)
    finsi
  finessayer
  t.fin = systeme.horloge()
  t.duree = t.fin - h0
  a.faits += 1
  a.occupe += t.duree
  file.termines += 1
  file.version += 1
  && historique
  ENREGISTRER_TRAVAIL(a.session, t)
retourner

procedure ENREGISTRER_TRAVAIL(s, t)
  essayer
    RQ(s, "delete from travaux where id = ?", {t.id})
    INSERER_LIGNES(s, "travaux", SPEC_TRAVAUX(), {{id = t.id, lot = t.lot, genre = t.genre, libelle = t.libelle, cible = t.cible, ;
              source_id = t.source_id, priorite = t.priorite, etat = t.etat, agent = t.agent, ;
              duree = t.duree, progression = t.progression, message = t.message, essais = t.essais}})
    RQ(s, "update travaux set cree = now() - to_seconds(?::double), debut = now() - to_seconds(?::double), fin = now() where id = ?", ;
       {max(0, systeme.horloge() - t.cree), max(0, systeme.horloge() - sisinon(t.debut = nul, t.cree, t.debut)), t.id})
  capturer e
  finessayer
retourner

fonction SPEC_TRAVAUX()
  globale spectravaux
  si spectravaux = nul
    spectravaux = {id = "INTEGER", lot = "INTEGER", genre = "VARCHAR", libelle = "VARCHAR", cible = "VARCHAR", ;
                   source_id = "INTEGER", priorite = "INTEGER", etat = "VARCHAR", agent = "INTEGER", duree = "DOUBLE", ;
                   progression = "DOUBLE", message = "VARCHAR", essais = "INTEGER"}
  finsi
retourner spectravaux

procedure PROGRES(t, p, message)
  && appelé par les traitements : avancement 0..1 ; lève une erreur si le travail est annulé
  t.progression = max(0, min(1, p))
  si message <> nul
    t.message = message
  finsi
  file.version += 1
  si t.annule ou file.arret
    erreur "annulé"
  finsi
retourner

&&
&& Aiguillage : genre de travail -> traitement
&&

procedure TRAVAIL_EXECUTER(s, t)
  faire cas
  cas t.genre = "inventaire"
    INVENTAIRE_SERVEUR(s, t)
  cas t.genre = "extraction"
    EXTRAIRE(s, t)
  cas t.genre = "normalisation"
    NORMALISER(s, t)
  cas t.genre = "analyse"
    ANALYSER_LOT(s, t)
  cas t.genre = "resolution"
    RESOUDRE(s, t)
  cas t.genre = "dictionnaire"
    CONSTRUIRE_DICTIONNAIRE(s, t)
  cas t.genre = "types"
    CONSTRUIRE_TYPES(s, t)
  cas t.genre = "duplications"
    DETECTER_DUPLICATIONS(s, t)
  cas t.genre = "performances"
    ANALYSER_PERFORMANCES(s, t)
  cas t.genre = "patrimoine"
    ANALYSER_PATRIMOINE(s, t)
  cas t.genre = "profilage"
    PROFILER_TABLE(s, t)
  cas t.genre = "captures"
    IMPORTER_CAPTURES(s, t)
  cas t.genre = "rejeu"
    REJOUER(s, t)
  cas t.genre = "attente"
    && travail de démonstration : simule une requête longue
    s:requete("select count(*) from range(?) t(x) where x % 7 = 3", t.params.n)
  autrement
    erreur "genre de travail inconnu : " + t.genre
  fincas
retourner

&&
&& Commandes de la file
&&

procedure FILE_PAUSE(ev)
  file.pause = non file.pause
  file.version += 1
  boutons_file.pause.libelle = sisinon(file.pause, "▶ Reprendre", "⏸ Pause")
  STATUT(sisinon(file.pause, "File en pause : les travaux en cours se terminent, aucun autre ne démarre.", "File reprise."))
retourner

procedure FILE_ARRETER(ev)
  si non ui.confirmer("Arrêter tous les travaux (en cours et en attente) ?", "question")
    retourner
  finsi
  file.arret = vrai
  pour chaque t dans file.travaux
    si t.etat = "attente"
      t.etat = "annule"
      t.message = "Annulé (arrêt général)"
    finsi
    si t.etat = "encours"
      t.annule = vrai
    finsi
  suivant
  pour chaque a dans file.agents
    si a.session <> nul et a.travail <> nul
      essayer
        a.session:annuler()
      capturer e
      finessayer
    finsi
  suivant
  file.version += 1
  ui.minuterie(1500, @FILE_REARMER, faux)
  STATUT("Arrêt demandé : interruption des requêtes en cours…")
retourner

procedure FILE_REARMER(ev)
  file.arret = faux
  STATUT("File arrêtée. Les travaux annulés peuvent être relancés.")
retourner

procedure FILE_RELANCER(ev)
  locale n = 0
  pour chaque t dans file.travaux
    si t.etat = "erreur" ou t.etat = "annule" ou t.etat = "bloque"
      t.etat = "attente"
      t.message = "Relancé"
      t.essais += 1
      t.annule = faux
      t.progression = 0
      n += 1
    finsi
  suivant
  file.finlot = nul
  file.version += 1
  STATUT(chaine(n) + " travail(aux) relancé(s)")
retourner

procedure FILE_ANNULER(ev)
  locale t = TRAVAIL_SELECTIONNE()
  si t = nul
    STATUT("Sélectionnez un travail dans la file.")
    retourner
  finsi
  faire cas
  cas t.etat = "attente" ou t.etat = "bloque"
    t.etat = "annule"
    t.message = "Annulé par l'utilisateur"
  cas t.etat = "encours"
    t.annule = vrai
    locale a = file.agents[t.agent]
    si a <> nul et a.session <> nul
      essayer
        a.session:annuler()
      capturer e
      finessayer
    finsi
  fincas
  file.version += 1
retourner

procedure FILE_PRIORITE(ev)
  locale t = TRAVAIL_SELECTIONNE()
  si t <> nul et t.etat = "attente"
    t.priorite = max(1, t.priorite - 1)
    file.version += 1
    STATUT("Priorité de « " + t.libelle + " » : " + t.priorite)
  finsi
retourner

procedure FILE_NETTOYER(ev)
  locale garde = {}
  file.parid = {}
  pour chaque t dans file.travaux
    si t.etat <> "termine" et t.etat <> "annule"
      inserer(garde, t)
      file.parid[chaine(t.id)] = t
    finsi
  suivant
  file.travaux = garde
  file.affichage = {}
  gfile:vider()
  file.version += 1
  RAFRAICHIR_FILE()
retourner

procedure AGENTS_CHANGES(ev)
  reglages.agents = max(3, min(10, entier(cagents.valeur)))
  lagents.libelle = chaine(reglages.agents) + " agents"
  pour i = 1 a 10
    cartes[i].cadre.visible = i <= reglages.agents
  suivant
  ECRIRE_REGLAGES()
  && la limite de connexions de l'extension mssql suit le nombre d'agents
  essayer
    requete("set mssql_connection_limit = " + chaine(reglages.agents + 2))
  capturer e
  finessayer
retourner

procedure PARSERVEUR_CHANGE(ev)
  reglages.parserveur = max(1, min(10, entier(cparsrv.valeur)))
  ECRIRE_REGLAGES()
retourner

&&
&& Panneau « File d'attente »
&&

procedure CONSTRUIRE_FILE(page)
  globale cagents, lagents, cparsrv, cartes, gfile, gantt, lfile, boutons_file
  boutons_file = {}
  locale haut = page:ajouter(ui.rangee())
  haut.marge = 2
  haut.ancrage = "haut"
  locale l1 = haut:ajouter(ui.etiquette("Agents"))
  cagents = haut:ajouter(ui.curseur())
  cagents.min = 3
  cagents.max = 10
  cagents.valeur = reglages.agents
  cagents.largeurfixe = 160
  cagents.infobulle = "Nombre de traitements exécutés en parallèle (3 à 10) : selon la puissance du poste et la charge acceptable pour les bases"
  cagents.surchangement = @AGENTS_CHANGES
  lagents = haut:ajouter(ui.etiquette(chaine(reglages.agents) + " agents"))
  lagents.largeurfixe = 70
  haut:ajouter(ui.etiquette("  par serveur"))
  cparsrv = haut:ajouter(ui.compteur())
  cparsrv.min = 1
  cparsrv.max = 10
  cparsrv.valeur = reglages.parserveur
  cparsrv.largeurfixe = 70
  cparsrv.infobulle = "Au plus N agents interrogent en même temps un même serveur SQL Server"
  cparsrv.surchangement = @PARSERVEUR_CHANGE
  boutons_file.pause = OUTIL(haut, "⏸ Pause", @FILE_PAUSE, "Suspendre : les travaux en cours se terminent, aucun autre ne démarre")
  OUTIL(haut, "■ Arrêter", @FILE_ARRETER, "Interrompre les requêtes en cours et annuler la file")
  OUTIL(haut, "↻ Relancer", @FILE_RELANCER, "Remettre en file les travaux en erreur, annulés ou bloqués")
  OUTIL(haut, "⇡ Priorité", @FILE_PRIORITE, "Augmenter la priorité du travail sélectionné")
  OUTIL(haut, "✕ Annuler", @FILE_ANNULER, "Annuler le travail sélectionné (interrompt sa requête s'il est en cours)")
  OUTIL(haut, "Nettoyer", @FILE_NETTOYER, "Retirer de la liste les travaux terminés et annulés")
  lfile = haut:ajouter(ui.etiquette(""))
  lfile.poids = 1
  && cartes des agents
  && à droite de la liste : les agents (grille 5 × 2) au-dessus de la chronologie
  locale sep_ = page:ajouter(ui.separateur{vertical = vrai, position = 0.56})
  sep_.ancrage = "centre"
  gfile = sep_:ajouter(ui.grille())
  locale droite_ = sep_:ajouter(ui.colonne())
  droite_.marge = 0
  droite_.espacement = 4
  locale bandeau = droite_:ajouter(ui.conteneur("grille", 5))
  bandeau.marge = 0
  bandeau.espacement = 4
  cartes = {}
  pour i = 1 a 10
    locale c = bandeau:ajouter(ui.colonne())
    c.fond = "#1F2937"
    c.rayon = 6
    c.marge = 3
    c.espacement = 2
    c.hauteurfixe = 46
    && carte compacte : « ⬤ n  travail en cours » sur une ligne, la jauge en filet dessous
    locale r1 = c:ajouter(ui.rangee())
    r1.marge = 0
    r1.espacement = 4
    r1.hauteurfixe = 22
    locale t = r1:ajouter(ui.etiquette("⬤ " + i))
    t.couleur = COULEUR_AGENT(i)
    t.largeurfixe = 40
    locale d = r1:ajouter(ui.etiquette("libre"))
    d.couleur = "#9CA3AF"
    d.poids = 1
    locale j = c:ajouter(ui.jauge())
    j.hauteurfixe = 14
    j.accent = COULEUR_AGENT(i)
    c.visible = i <= reglages.agents
    inserer(cartes, {cadre = c, titre = t, detail = d, jauge = j})
  suivant
  && liste des travaux et chronologie
  gfile:ajoutercolonne{nom = "id", titre = "#", genre = "nombre", largeur = 46}
  gfile:ajoutercolonne{nom = "etat", titre = "État", largeur = 92}
  gfile:ajoutercolonne{nom = "prio", titre = "P", genre = "nombre", largeur = 30}
  gfile:ajoutercolonne{nom = "travail", titre = "Travail", largeur = 250}
  gfile:ajoutercolonne{nom = "cible", titre = "Cible", largeur = 150}
  gfile:ajoutercolonne{nom = "agent", titre = "Agent", largeur = 52}
  gfile:ajoutercolonne{nom = "avance", titre = "Avancement", largeur = 86}
  gfile:ajoutercolonne{nom = "duree", titre = "Durée", largeur = 70}
  gfile:ajoutercolonne{nom = "message", titre = "Message", largeur = 380}
  gfile:ajouterformat("etat", "=", "▶ en cours", {fond = "#1E3A8A", texte = "#DBEAFE", ligneentiere = vrai})
  gfile:ajouterformat("etat", "=", "✖ erreur", {fond = "#7F1D1D", texte = "#FEE2E2", ligneentiere = vrai})
  gfile:ajouterformat("etat", "=", "⛔ bloqué", {fond = "#78350F", texte = "#FEF3C7", ligneentiere = vrai})
  gfile:ajouterformat("etat", "=", "✔ terminé", {texte = "#86EFAC"})
  gfile:ajouterformat("etat", "=", "○ annulé", {texte = "#9CA3AF"})
  gfile.surdoubleclic = @FILE_DETAIL
  gantt = droite_:ajouter(ui.gantt())
  gantt.poids = 1
  gantt:largeurlibelles(170)
retourner

fonction COULEUR_AGENT(i)
  locale c = {"#60A5FA", "#34D399", "#FBBF24", "#F472B6", "#A78BFA", "#F87171", "#2DD4BF", "#FB923C", "#A3E635", "#E879F9"}
retourner c[((i - 1) % 10) + 1]

fonction ETAT_TEXTE(e)
  faire cas
  cas e = "attente"
    retourner "… en attente"
  cas e = "encours"
    retourner "▶ en cours"
  cas e = "termine"
    retourner "✔ terminé"
  cas e = "erreur"
    retourner "✖ erreur"
  cas e = "annule"
    retourner "○ annulé"
  cas e = "bloque"
    retourner "⛔ bloqué"
  fincas
retourner e

fonction TRAVAIL_SELECTIONNE()
  locale i = gfile:selection()
  si i = nul ou i < 1 ou i > #file.affichage
    retourner nul
  finsi
retourner file.affichage[i]

procedure FILE_DETAIL(ev)
  locale t = TRAVAIL_SELECTIONNE()
  si t = nul
    retourner
  finsi
  locale md = {"### Travail " + t.id + " · " + t.libelle, "", ;
               "| | |", "|---|---|", ;
               "| Genre | " + t.genre + " |", "| Cible | " + MDCELL(t.cible) + " |", ;
               "| État | " + ETAT_TEXTE(t.etat) + " |", "| Priorité | " + t.priorite + " |", ;
               "| Agent | " + sisinon(t.agent = nul, "-", t.agent) + " |", ;
               "| Durée | " + DUREE_TEXTE(t.duree) + " |", "| Dépendances | " + joindre(t.apres, ", ") + " |", ;
               "", "**Message**", "", "```", chaine(t.message), "```"}
  PROPRIETES(joindre(md, car(10)))
retourner

procedure RAFRAICHIR_FILE
  si gfile = nul
    retourner
  finsi
  && cartes des agents
  locale maintenant = systeme.horloge()
  pour i = 1 a 10
    locale a = file.agents[i]
    locale c = cartes[i]
    si a.travail <> nul et a.travail.etat = "encours"
      c.detail.libelle = COURT(a.travail.libelle, 26)
      c.detail.couleur = "#E5E7EB"
      c.jauge.valeur = entier(a.travail.progression * 100)
      c.cadre.infobulle = "Agent " + i + " · " + a.travail.libelle + " · " + DUREE_TEXTE(maintenant - a.travail.debut)
    sinon
      c.detail.libelle = sisinon(i <= reglages.agents, sisinon(file.pause, "en pause", "libre"), "désactivé")
      c.detail.couleur = "#9CA3AF"
      c.jauge.valeur = 0
      c.cadre.infobulle = "Agent " + i + sisinon(a.faits > 0, " · " + a.faits + " travaux faits", "")
    finsi
  suivant
  && lignes de la grille (seules les lignes modifiées sont réécrites)
  pour chaque t dans file.travaux
    locale sig = t.etat + "|" + entier(t.progression * 100) + "|" + t.message + "|" + t.priorite + "|" + ;
                 sisinon(t.etat = "encours", entier(maintenant - t.debut), "")
    si t.ligne = nul
      inserer(file.affichage, t)
      t.ligne = #file.affichage
      gfile:ajouterligne(t.id, ETAT_TEXTE(t.etat), t.priorite, t.libelle, t.cible, "", "", "", "")
    finsi
    si t.sig <> sig
      t.sig = sig
      gfile:fixercellule(t.ligne, "etat", ETAT_TEXTE(t.etat))
      gfile:fixercellule(t.ligne, "prio", t.priorite)
      gfile:fixercellule(t.ligne, "agent", sisinon(t.agent = nul, "", chaine(t.agent)))
      gfile:fixercellule(t.ligne, "avance", sisinon(t.etat = "attente", "", chaine(entier(t.progression * 100)) + " %"))
      gfile:fixercellule(t.ligne, "duree", sisinon(t.etat = "encours", DUREE_TEXTE(maintenant - t.debut), DUREE_TEXTE(t.duree)))
      gfile:fixercellule(t.ligne, "message", COURT(t.message, 200))
    finsi
  suivant
  && résumé
  locale ea = NB_ETAT("attente")
  locale ec = NB_ETAT("encours")
  locale et = NB_ETAT("termine")
  locale ee = NB_ETAT("erreur")
  locale eb = NB_ETAT("bloque")
  locale txt = ea + " en attente · " + ec + " en cours · " + et + " terminés"
  si ee > 0
    txt = txt + " · " + ee + " en erreur"
  finsi
  si eb > 0
    txt = txt + " · " + eb + " bloqués"
  finsi
  si file.debut <> nul et et > 0
    locale fin_ = sisinon(file.finlot = nul, maintenant, file.finlot)
    txt = txt + " · " + arrondi(et / max(0.1, fin_ - file.debut), 1) + " travaux/s"
  finsi
  lfile.libelle = txt
  INDICATEUR_FILE(ea, ec, ee)
  && chronologie (Gantt) : refaite quand un travail a changé d'état
  si file.ganttversion <> file.version et file.debut <> nul
    file.ganttversion = file.version
    gantt:vider()
    locale n = 0
    pour chaque t dans file.travaux
      si t.debut <> nul et t.lot = file.lot
        n += 1
        si n > 160
          sortir
        finsi
        locale d0 = t.debut - file.debut
        locale du = sisinon(t.etat = "encours", maintenant - t.debut, sisinon(t.duree = nul, 0, t.duree))
        gantt:ajoutertache("#" + t.id + " " + COURT(t.libelle, 22), d0, max(0.05, du), t.progression, ;
                           sisinon(t.etat = "erreur", "#EF4444", COULEUR_AGENT(sisinon(t.agent = nul, 1, t.agent))), ;
                           "A" + sisinon(t.agent = nul, "?", t.agent))
      finsi
    suivant
  finsi
retourner
