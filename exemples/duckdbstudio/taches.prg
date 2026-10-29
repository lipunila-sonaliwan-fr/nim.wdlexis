&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : connexions numérotées, onglets de requêtes, opérations en cours.
&&
&& * Chaque connexion du projet a un numéro stable (c.num), affiché partout : « 2 · ventes ».
&& * Chaque onglet de l'éditeur a sa connexion par défaut (numéro dans la pastille de
&&   l'onglet, liste « Connexion » au-dessus de l'éditeur) et sa propre session SQL
&&   (sessionsql()) : USE <connexion> est appliqué avant chaque exécution, et plusieurs
&&   onglets exécutent leurs requêtes en même temps, chacun sur sa session.
&& * Pendant qu'une requête s'exécute, l'interpréteur est libre : l'interface reste
&&   disponible (autres onglets, explorateur, défilement…).
&& * Toute opération longue est enregistrée (OPERATION_DEBUT / OPERATION_FIN) ; au-delà de
&&   15 s, la barre d'arrêt apparaît (« ■ Arrêter », touche Échap) : la requête est
&&   interrompue (session de l'onglet, ou base principale pour les autres opérations).

&&
&& Connexions numérotées
&&

procedure NUMEROTER_CONNEXIONS
  locale m = 0
  pour chaque c dans projet.connexions
    si c.num <> nul et c.num > m
      m = c.num
    finsi
  suivant
  pour chaque c dans projet.connexions
    si c.num = nul ou c.num < 1
      m += 1
      c.num = m
    finsi
  suivant
retourner

fonction NUMERO_LIBRE()
  locale m = 0
  pour chaque c dans projet.connexions
    si c.num <> nul et c.num > m
      m = c.num
    finsi
  suivant
retourner m + 1

fonction CNX_NUM(n)
  si n = nul ou n = 0
    retourner nul
  finsi
  pour chaque c dans projet.connexions
    si c.num = n
      retourner c
    finsi
  suivant
retourner nul

fonction NUM_TEXTE(c)
retourner sisinon(c = nul ou c.num = nul, "0", chaine(entier(c.num)))

fonction LIBELLE_CNX(c)
  si c = nul
    retourner "0 · moteur (mémoire)"
  finsi
retourner NUM_TEXTE(c) + " · " + c.nom

&&
&& Onglets de requêtes : connexion, session, résultat
&&

fonction TITRE_DOC(uid)
  pour chaque d dans ed:documents()
    si d.uid = uid
      retourner d.titre
    finsi
  suivant
retourner ""

fonction ONGLET(uid)
  locale k = chaine(uid)
  locale o = onglets[k]
  si o = nul
    locale n = cnxdefaut
    si projet.scripts <> nul
      locale m = projet.scripts[majuscule(TITRE_DOC(uid))]
      si m <> nul
        n = m
      finsi
    finsi
    si n <> 0 et CNX_NUM(n) = nul
      n = 0
    finsi
    o = {uid = uid, cnx = n, session = nul, tache = nul, resultat = nul}
    onglets[k] = o
  finsi
retourner o

fonction ONGLET_ACTIF()
  locale uid = ed:actif()
  si uid = nul ou uid < 0
    retourner nul
  finsi
retourner ONGLET(uid)

fonction ONGLET_OUTILS()
  && contexte des outils (aperçu de pipeline…) : session propre, moteur, sans onglet
  globale outils
  si outils = nul
    outils = {uid = nul, cnx = 0, session = nul, tache = nul, resultat = nul}
  finsi
retourner outils

procedure PASTILLE_ONGLET(o)
  si o = nul ou o.uid = nul
    retourner
  finsi
  essayer
    si o.tache <> nul
      ed:pastille(NUM_TEXTE(CNX_NUM(o.cnx)) + " …", o.uid, "#D97706")
    sinon
      ed:pastille(NUM_TEXTE(CNX_NUM(o.cnx)), o.uid, sisinon(o.cnx = 0, "#9CA3AF", ""))
    finsi
  capturer e
  finessayer
retourner

procedure PASTILLES
  && toutes les pastilles ; un onglet dont la connexion a disparu revient au moteur
  pour chaque d dans ed:documents()
    locale o = ONGLET(d.uid)
    si o.cnx <> 0 et CNX_NUM(o.cnx) = nul
      o.cnx = 0
    finsi
    PASTILLE_ONGLET(o)
  suivant
retourner

procedure REMPLIR_COMBO_CNX
  globale majcombo, choixcnx
  majcombo = vrai
  cbcnx:vider()
  choixcnx = {0}
  cbcnx:ajouter(LIBELLE_CNX(nul))
  pour chaque c dans projet.connexions
    cbcnx:ajouter(LIBELLE_CNX(c) + sisinon(attachees[minuscule(ALIAS(c))] = vrai, "", "  (non connectée)"))
    inserer(choixcnx, c.num)
  suivant
  majcombo = faux
  ONGLET_CHOISI()
retourner

procedure ONGLET_CHOISI
  && onglet activé : liste des connexions, pastille, résultat de cet onglet
  globale majcombo
  locale o = ONGLET_ACTIF()
  si o = nul
    retourner
  finsi
  majcombo = vrai
  pour i = 1 a #choixcnx
    si choixcnx[i] = o.cnx
      cbcnx:selectionner(i)
    finsi
  suivant
  majcombo = faux
  PASTILLE_ONGLET(o)
  ETAT_ONGLET()
  si o.resultat <> nul et o.resultat <> resultataffiche
    MONTRER_RESULTAT(o)
  finsi
retourner

procedure CNX_ONGLET(ev)
  && choix de la connexion de l'onglet actif
  globale cnxdefaut
  si majcombo
    retourner
  finsi
  locale o = ONGLET_ACTIF()
  locale i = cbcnx:selection()
  si o = nul ou i = nul ou i < 1 ou i > #choixcnx
    retourner
  finsi
  o.cnx = choixcnx[i]
  cnxdefaut = o.cnx
  si projet.scripts = nul
    projet.scripts = {}
  finsi
  projet.scripts[majuscule(TITRE_DOC(o.uid))] = o.cnx
  PASTILLE_ONGLET(o)
  ETAT_ONGLET()
  STATUT("Onglet « " + TITRE_DOC(o.uid) + " » : connexion " + LIBELLE_CNX(CNX_NUM(o.cnx)))
retourner

procedure ETAT_ONGLET
  locale o = ONGLET_ACTIF()
  locale n = 0
  pour chaque k, t dans taches
    n += 1
  suivant
  locale txt = sisinon(o = nul, "", "Onglet : " + LIBELLE_CNX(CNX_NUM(o.cnx)))
  si n > 0
    txt = txt + "   ·   " + n + " opération(s) en cours"
  finsi
  lblcnx.libelle = txt
retourner

fonction CIBLE_USE(c)
  && catalogue (et schéma) que USE doit viser pour la connexion c
  si c = nul
    retourner "memory.main"
  finsi
  locale k = CONNECTEUR(c.type)
  si k <> nul et (k.mode = "fichiers" ou k.mode = "requete")
    retourner "memory." + IDENT(ALIAS(c))
  finsi
retourner IDENT(ALIAS(c))

fonction PREPARER_ONGLET(o)
  && session de l'onglet, connexion attachée au besoin, USE ; nul si impossible
  locale c = CNX_NUM(o.cnx)
  si c <> nul et attachees[minuscule(ALIAS(c))] <> vrai
    locale r = ATTACHER(c, vrai)
    si non r.ok
      ERREUR(c.nom + " : " + r.message)
      retourner nul
    finsi
    REMPLIR_EXPLORATEUR()
    NOMS_COMPLETION()
  finsi
  si o.session = nul
    o.session = sessionsql()
  finsi
  locale cible = CIBLE_USE(c)
  essayer
    o.session:requete("USE " + cible)
  capturer e
    && catalogue sans schéma « main » (PostgreSQL : public…) : premier schéma utilisateur
    essayer
      locale l = o.session:requete("SELECT schema_name FROM duckdb_schemas() WHERE database_name = ? " + ;
                                   "AND NOT internal ORDER BY schema_name <> 'public', schema_name LIMIT 1", ALIAS(c))
      si #l > 0
        o.session:requete("USE " + cible + "." + IDENT(l[1].schema_name))
      finsi
    capturer e2
      JOURNAL("USE " + cible + " : " + e)
    finessayer
  finessayer
retourner o.session

procedure FERMER_ONGLET(uid)
  && fermeture d'un onglet : arrêt de sa requête, fermeture de sa session
  locale o = onglets[chaine(uid)]
  si o <> nul
    si o.tache <> nul
      si non ui.confirmer("Une requête est en cours dans cet onglet. L'arrêter et fermer l'onglet ?")
        retourner
      finsi
      ARRETER_TACHE(o.tache)
    finsi
  finsi
  si ed:modifie(uid)
    si ed:chemin(uid) <> ""
      si ui.confirmer("Enregistrer « " + TITRE_DOC(uid) + " » avant de le fermer ?")
        ed:enregistrer(nul, uid)
      finsi
    sinonsi non ui.confirmer("« " + TITRE_DOC(uid) + " » n'a jamais été enregistré. Le fermer quand même ?")
      retourner
    finsi
  finsi
  ed:fermer(uid)
  si o <> nul
    onglets[chaine(uid)] = nul
    si o.session <> nul
      essayer
        o.session:fermer()
      capturer e
      finessayer
    finsi
  finsi
  locale docs = ed:documents()
  si #docs = 0
    NOUVELLE_REQUETE()
  finsi
  ONGLET_CHOISI()
retourner

&&
&& Opérations en cours, arrêt des opérations longues
&&

fonction OPERATION_DEBUT(libelle, session)
  globale numtache
  numtache += 1
  locale t = {id = numtache, libelle = libelle, debut = systeme.horloge(), session = session, arret = faux}
  taches[chaine(numtache)] = t
  ETAT_ONGLET()
retourner t

procedure OPERATION_FIN(t)
  si t <> nul
    taches[chaine(t.id)] = nul
  finsi
  ETAT_ONGLET()
  SURVEILLER_TACHES(nul)
retourner

fonction OPERATION_ARRETEE(t)
retourner t <> nul et t.arret

fonction EN_COURS(t)
retourner arrondi(systeme.horloge() - t.debut) + " s"

procedure ARRETER_TACHE(t)
  si t = nul
    retourner
  finsi
  t.arret = vrai
  essayer
    si t.session <> nul
      t.session:annuler()
    sinon
      interromprebase()
    finsi
  capturer e
  finessayer
  JOURNAL("Arrêt demandé : " + t.libelle + " (après " + EN_COURS(t) + ")")
  STATUT("Arrêt demandé : " + t.libelle)
retourner

procedure SURVEILLER_TACHES(ev)
  && minuterie (1 s) : barre d'arrêt pour les opérations de plus de 15 s
  globale tachelongue
  locale longue = nul
  locale nl = 0
  pour chaque k, t dans taches
    si non t.arret et systeme.horloge() - t.debut >= 15
      nl += 1
      si longue = nul ou t.debut < longue.debut
        longue = t
      finsi
    finsi
  suivant
  tachelongue = longue
  si longue = nul
    si barrearret.visible
      barrearret.visible = faux
    finsi
    retourner
  finsi
  lblarret.libelle = "●  Opération longue : " + longue.libelle + " — en cours depuis " + EN_COURS(longue) + ;
                     sisinon(nl > 1, "   (+" + (nl - 1) + " autre(s))", "")
  btouttarret.visible = nl > 1
  si non barrearret.visible
    barrearret.visible = vrai
  finsi
retourner

procedure ARRETER_LONGUE(ev)
  si tachelongue <> nul
    ARRETER_TACHE(tachelongue)
  finsi
  SURVEILLER_TACHES(nul)
retourner

procedure ARRETER_TOUT(ev)
  pour chaque k, t dans taches
    si systeme.horloge() - t.debut >= 15
      ARRETER_TACHE(t)
    finsi
  suivant
  SURVEILLER_TACHES(nul)
retourner

procedure ARRETER_COURANTE
  && Échap : la requête de l'onglet actif, sinon l'opération longue
  locale o = ONGLET_ACTIF()
  si o <> nul et o.tache <> nul
    ARRETER_TACHE(o.tache)
  sinonsi tachelongue <> nul
    ARRETER_TACHE(tachelongue)
  finsi
retourner

fonction OPERATION_EN_COURS(libelle)
  pour chaque k, t dans taches
    si t.libelle = libelle
      retourner vrai
    finsi
  suivant
retourner faux
