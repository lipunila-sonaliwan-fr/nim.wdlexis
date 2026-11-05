&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atlas SQL : sources, extraction du catalogue, normalisation, analyse par lots,
&& planification d'une campagne d'analyse (module 1 et orchestration).
&&
&& Genres de sources :
&&   mssql     SQL Server par l'extension communautaire DuckDB « mssql » (ATTACH … TYPE
&&             mssql ; requêtes T-SQL transmises telles quelles par mssql_scan) ;
&&             la limite de connexions de l'extension suit le nombre d'agents
&&   odbc      SQL Server par ODBC (extension nanodbc, odbc_query) ;
&&   dossier   scripts .sql (projet SSDT, export « Générer les scripts »…) ;
&&   demo      système d'information de démonstration (demo.prg).
&& Les mots de passe ne sont jamais écrits dans l'entrepôt : ils sont demandés à la
&& première campagne de la session (et mémorisés chiffrés sur le poste si demandé).

fonction SOURCES()
retourner RQ(nul, "select * from sources order by id", nul)

fonction SOURCE(id)
  locale r = RQ(nul, "select * from sources where id = ?", {id})
  si #r = 0
    retourner nul
  finsi
retourner r[1]

fonction ALIAS_SOURCE(src)
retourner "src_" + src.id

procedure AJOUTER_SOURCE_DEMO
  si RV(nul, "select count(*) from sources where genre = 'demo'", nul) > 0
    STATUT("La source de démonstration existe déjà.")
    retourner
  finsi
  locale id = RV(nul, "select coalesce(max(id), 0) + 1 from sources", nul)
  RQ(nul, "insert into sources values (?, ?, 'demo', 'SRV-ERP, SRV-COMPTA, SRV-DWH', 1433, '', 'aucune', '', '{}', true, 3, '', now(), null)", ;
     {id, "Démonstration (3 serveurs)"})
  ARBRE_SOURCES()
retourner

&&
&& Boîte « Source SQL Server »
&&

procedure NOUVELLE_SOURCE(ev)
  SOURCE_DIALOGUE(nul)
retourner

procedure SOURCE_DIALOGUE(src)
  globale srcdlg, srcctl
  si srcdlg <> nul
    retourner
  finsi
  srcctl = {edition = src}
  srcdlg = ui.fenetre{titre = sisinon(src = nul, "Nouvelle source", "Source « " + sisinon(src = nul, "", src.nom) + " »"), ;
                      largeur = 700, hauteur = 720, disposition = "bordure", sombre = reglages.sombre, densite = "compacte"}
  srcdlg.surfermeture = @SRC_FERMETURE
  locale g = srcdlg:ajouter(ui.cadre("Source", "grille"))
  g.ancrage = "haut"
  g:ajouter(ui.etiquette("Nom"))
  srcctl.nom = g:ajouter(ui.saisie{texte = sisinon(src = nul, "", src.nom), indication = "Production ERP"})
  g:ajouter(ui.etiquette("Genre"))
  srcctl.genre = g:ajouter(ui.combo("SQL Server (extension mssql)", "SQL Server par ODBC (nanodbc)", ;
                                    "Dossier de scripts .sql", "Démonstration"))
  srcctl.genre:selectionner(sisinon(src = nul, 1, POSITION_GENRE(src.genre)))
  g:ajouter(ui.etiquette("Serveur (hôte,port ou hôte\\instance)"))
  srcctl.serveur = g:ajouter(ui.saisie{texte = sisinon(src = nul, "", src.serveur), indication = "sqlprod01,1433"})
  g:ajouter(ui.etiquette("Bases (vide : toutes les bases utilisateur)"))
  srcctl.base = g:ajouter(ui.saisie{texte = sisinon(src = nul, "", src.base), indication = "ERP, REF"})
  g:ajouter(ui.etiquette("Authentification"))
  srcctl.auth = g:ajouter(ui.combo("SQL Server (utilisateur / mot de passe)", "Windows (SSPI / Kerberos)", ;
                                   "Entra ID (secret DuckDB)", "Chaîne ODBC (DSN=…)"))
  srcctl.auth:selectionner(sisinon(src = nul, 1, POSITION_AUTH(src.auth)))
  srcctl.auth.surselection = @SRC_AUTH_CHANGE
  g:ajouter(ui.etiquette("Utilisateur / DSN / secret Entra"))
  srcctl.utilisateur = g:ajouter(ui.saisie{texte = sisinon(src = nul, "", src.utilisateur), indication = "atlas_lecture"})
  g:ajouter(ui.etiquette("Mot de passe"))
  locale memorise = src <> nul et SECRET_SOURCE(src, faux) <> nul
  srcctl.mdp = g:ajouter(ui.saisie{motdepasse = vrai, ;
                                   indication = sisinon(memorise, "•••••• mémorisé (laisser vide pour le conserver)", "mot de passe SQL Server")})
  g:ajouter(ui.etiquette(""))
  srcctl.memoriser = g:ajouter(ui.cases("Mémoriser sur ce poste (chiffré)"))
  srcctl.memoriser:cocher(1, vrai)
  g:ajouter(ui.etiquette("Dossier des scripts"))
  srcctl.dossier = g:ajouter(ui.saisie{texte = sisinon(src = nul, "", src.dossier), indication = "/chemin/vers/scripts"})
  g:ajouter(ui.etiquette("Agents au plus sur ce serveur"))
  srcctl.limite = g:ajouter(ui.compteur())
  srcctl.limite.min = 1
  srcctl.limite.max = 10
  srcctl.limite.valeur = sisinon(src = nul, reglages.parserveur, src.limite)
  locale opts = srcdlg:ajouter(ui.cadre("Options", "vertical"))
  opts.ancrage = "centre"
  srcctl.options = opts:ajouter(ui.cases("Faire confiance au certificat (TrustServerCertificate ; certificat auto-signé)", ;
                                         "Chiffrer la connexion (Encrypt ; recommandé)", ;
                                         "Profiler les colonnes (cardinalités, valeurs ; échantillon)", ;
                                         "Statistiques d'exécution et plans en cache (VIEW SERVER STATE)"))
  locale o0 = sisinon(src = nul, {confiance = vrai, chiffrement = vrai, profilage = faux, stats = vrai}, OPTIONS_SOURCE(src))
  srcctl.options:cocher(1, o0.confiance = vrai)
  srcctl.options:cocher(2, o0.chiffrement <> faux)
  srcctl.options:cocher(3, o0.profilage = vrai)
  srcctl.options:cocher(4, o0.stats <> faux)
  locale aide = opts:ajouter(ui.markdown("Droits nécessaires : `VIEW DEFINITION` sur les bases, `VIEW SERVER STATE` " + ;
    "pour les statistiques, lecture de `msdb` pour les jobs. Atlas n'écrit **jamais** dans les bases analysées : " + ;
    "il lit le catalogue (`sys.*`), les modules et les vues de gestion dynamiques.\n\n" + ;
    "L'extension DuckDB `mssql` (communautaire) est téléchargée à la première utilisation."))
  aide.poids = 1
  locale bas_ = srcdlg:ajouter(ui.rangee())
  bas_.ancrage = "bas"
  && message du test ou de l'enregistrement : sur toute la largeur, au-dessus des boutons, avec retour à la ligne
  srcctl.statut = srcdlg:ajouter(ui.markdown(""))
  srcctl.statut.ancrage = "bas"
  srcctl.statut.hauteurfixe = 64
  locale vide_ = bas_:ajouter(ui.etiquette(""))
  vide_.poids = 1
  locale bt = bas_:ajouter(ui.bouton("Tester"))
  bt.surclic = @SRC_TESTER
  locale be = bas_:ajouter(ui.bouton("Enregistrer", {defaut = vrai}))
  be.surclic = @SRC_ENREGISTRER
  locale ba = bas_:ajouter(ui.bouton("Annuler", {annuler = vrai}))
  ba.surclic = @SRC_ANNULER
  SRC_AUTH_CHANGE(nul)
  srcctl.nom:focus()
retourner

procedure SRC_STATUT(m)
  srcctl.statut.valeur = m
retourner

procedure SRC_AUTH_CHANGE(ev)
  && le mot de passe ne sert qu'à l'authentification SQL Server
  locale sql_ = AUTHS_SOURCE()[max(1, srcctl.auth:selection())] = "sql"
  srcctl.mdp.actif = sql_
  srcctl.memoriser.actif = sql_
retourner

fonction GENRES_SOURCE()
retourner {"mssql", "odbc", "dossier", "demo"}

fonction AUTHS_SOURCE()
retourner {"sql", "windows", "entra", "odbc"}

fonction POSITION_GENRE(g)
  locale l = GENRES_SOURCE()
  pour i = 1 a #l
    si l[i] = g
      retourner i
    finsi
  suivant
retourner 1

fonction POSITION_AUTH(g)
  locale l = AUTHS_SOURCE()
  pour i = 1 a #l
    si l[i] = g
      retourner i
    finsi
  suivant
retourner 1

procedure SRC_FERMETURE(ev)
  globale srcdlg
  srcdlg = nul
retourner

procedure SRC_ANNULER(ev)
  globale srcdlg
  srcdlg:fermer()
  srcdlg = nul
retourner

fonction SRC_LIRE()
  locale o = {confiance = srcctl.options:coche(1), chiffrement = srcctl.options:coche(2), ;
              profilage = srcctl.options:coche(3), stats = srcctl.options:coche(4)}
retourner {nom = rogner(srcctl.nom.valeur), genre = GENRES_SOURCE()[max(1, srcctl.genre:selection())], ;
           serveur = rogner(srcctl.serveur.valeur), base = rogner(srcctl.base.valeur), ;
           auth = AUTHS_SOURCE()[max(1, srcctl.auth:selection())], utilisateur = rogner(srcctl.utilisateur.valeur), ;
           dossier = rogner(srcctl.dossier.valeur), limite = entier(srcctl.limite.valeur), options = o, ;
           motdepasse = sisinon(srcctl.mdp.valeur = nul, "", srcctl.mdp.valeur), memoriser = srcctl.memoriser:coche(1)}

procedure SRC_ENREGISTRER(ev)
  globale srcdlg
  locale x = SRC_LIRE()
  si x.nom = ""
    SRC_STATUT("Donnez un nom à la source.")
    retourner
  finsi
  si (x.genre = "mssql" ou x.genre = "odbc") et x.serveur = "" et x.auth <> "odbc"
    SRC_STATUT("Indiquez le serveur.")
    retourner
  finsi
  si x.genre = "dossier" et non fichier.estdossier(x.dossier)
    SRC_STATUT("Dossier introuvable : " + x.dossier)
    retourner
  finsi
  si SRC_MDP_REQUIS(x) et x.motdepasse = "" et (srcctl.edition = nul ou SECRET_SOURCE(srcctl.edition, faux) = nul)
    SRC_STATUT("Saisissez le mot de passe de « " + x.utilisateur + " ».")
    srcctl.mdp:focus()
    retourner
  finsi
  locale id = nul
  essayer
    si srcctl.edition = nul
      id = RV(nul, "select coalesce(max(id), 0) + 1 from sources", nul)
      RQ(nul, "insert into sources (id, nom, genre, serveur, port, base, auth, utilisateur, options, actif, limite, dossier, cree) " + ;
              "values (?, ?, ?, ?, 1433, ?, ?, ?, ?, true, ?, ?, now())", ;
         {id, x.nom, x.genre, x.serveur, x.base, x.auth, x.utilisateur, json(x.options), x.limite, x.dossier})
    sinon
      id = srcctl.edition.id
      RQ(nul, "update sources set nom = ?, genre = ?, serveur = ?, base = ?, auth = ?, utilisateur = ?, options = ?, " + ;
              "limite = ?, dossier = ? where id = ?", ;
         {x.nom, x.genre, x.serveur, x.base, x.auth, x.utilisateur, json(x.options), x.limite, x.dossier, id})
      && connexion à refaire avec les nouveaux paramètres
      DETACHER({id = id})
    finsi
    si SRC_MDP_REQUIS(x) et x.motdepasse <> ""
      MEMORISER_SECRET({id = id}, x.motdepasse, x.memoriser)
    finsi
  capturer e
    SRC_STATUT("Enregistrement impossible : " + COURT(e, 160))
    retourner
  finessayer
  srcdlg:fermer()
  srcdlg = nul
  ARBRE_SOURCES()
  STATUT("Source « " + x.nom + " » enregistrée. Lancez l'analyse (F5) pour la cartographier.")
retourner

fonction SRC_MDP_REQUIS(x)
retourner (x.genre = "mssql" ou x.genre = "odbc") et x.auth = "sql"

procedure SRC_TESTER(ev)
  locale x = SRC_LIRE()
  x.id = 0
  SRC_STATUT("Test en cours…")
  essayer
    faire cas
    cas x.genre = "demo"
      SRC_STATUT("Source de démonstration : rien à tester.")
    cas x.genre = "dossier"
      locale n = 0
      pour chaque f dans fichier.liste(x.dossier, vrai)
        si minuscule(fichier.extension(f)) = ".sql"
          n += 1
        finsi
      suivant
      SRC_STATUT(chaine(n) + " script(s) .sql trouvés.")
    autrement
      si SRC_MDP_REQUIS(x) et x.motdepasse = "" et srcctl.edition <> nul
        x.motdepasse = SECRET_SOURCE(srcctl.edition, faux)
      finsi
      si SRC_MDP_REQUIS(x) et (x.motdepasse = nul ou x.motdepasse = "")
        SRC_STATUT("Saisissez le mot de passe de « " + x.utilisateur + " » pour tester.")
        srcctl.mdp:focus()
        retourner
      finsi
      && alias de test : n'écrase ni le cache des secrets ni la connexion d'une source enregistrée
      x.id = 9999
      locale v = nul
      essayer
        v = TEST_CONNEXION(x)
        SRC_STATUT("Connexion réussie : " + COURT(v, 90))
      capturer e1
        && échec TLS : on essaie les autres réglages de chiffrement et on retient celui qui passe
        si non EST_ERREUR_TLS(chaine(e1))
          erreur e1
        finsi
        SRC_STATUT("Négociation TLS refusée : essai d'autres réglages de chiffrement…")
        locale essais = {{confiance = vrai, chiffrement = vrai, lib = "connexion chiffrée, certificat du serveur accepté"}, ;
                         {confiance = faux, chiffrement = faux, lib = "connexion non chiffrée (Encrypt=no)"}}
        locale ok = nul
        locale derniere = chaine(e1)
        pour chaque es dans essais
          si ok = nul et (es.confiance <> (x.options.confiance = vrai) ou es.chiffrement <> (x.options.chiffrement <> faux))
            x.options.confiance = es.confiance
            x.options.chiffrement = es.chiffrement
            essayer
              v = TEST_CONNEXION(x)
              ok = es
            capturer e2
              derniere = chaine(e2)
            finessayer
          finsi
        suivant
        si ok = nul
          SRC_STATUT("Échec : " + COURT(chaine(e1), 160) + " — aucun réglage de chiffrement ne passe (dernier essai : " + ;
                     COURT(derniere, 100) + "). Si le serveur impose le chiffrement strict (TDS 8.0, « Force Strict Encryption » " + ;
                     "de SQL Server 2022/2025), désactivez-le côté serveur ou utilisez le genre ODBC (ODBC Driver 18, Encrypt=Strict).")
        sinon
          srcctl.options:cocher(1, ok.confiance)
          srcctl.options:cocher(2, ok.chiffrement)
          SRC_STATUT("Connexion réussie en " + ok.lib + " : options cochées en conséquence, pensez à **Enregistrer**. " + COURT(v, 60))
        finsi
      finessayer
    fincas
  capturer e
    SRC_STATUT("Échec : " + COURT(e, 220) + CONSEIL_CONNEXION(chaine(e)))
  finessayer
retourner

fonction TEST_CONNEXION(x)
  && attache la source (alias de test), lit @@VERSION et détache ; lève l'erreur du serveur sinon
  locale v = nul
  essayer
    ATTACHER(x, vrai)
    v = RV(nul, "select * from " + FONCTION_SCAN(x, "SELECT CAST(@@VERSION AS NVARCHAR(400)) AS v"), nul)
  capturer e
    DETACHER(x)
    erreur e
  finessayer
  DETACHER(x)
retourner v

fonction EST_ERREUR_TLS(e)
  locale m = minuscule(e)
retourner "tls" $ m ou "ssl" $ m ou "certificat" $ m ou "certificate" $ m ou "handshake" $ m ou "encrypt" $ m

fonction CONSEIL_CONNEXION(e)
  && piste de correction selon le message d'erreur
  locale m = minuscule(e)
  faire cas
  cas "certificate" $ m ou "certificat" $ m ou "ssl" $ m ou "tls" $ m
    retourner " — cochez « Faire confiance au certificat du serveur » (certificat auto-signé)."
  cas "login failed" $ m ou "18456" $ m
    retourner " — utilisateur ou mot de passe refusé (vérifiez aussi que l'authentification SQL est activée sur le serveur)."
  cas "encrypt" $ m
    retourner " — essayez de cocher ou décocher « Chiffrer la connexion »."
  cas "timeout" $ m ou "refused" $ m ou "resolve" $ m ou "unreachable" $ m
    retourner " — serveur injoignable : hôte, port (hôte,1433) et pare-feu ; une instance nommée nécessite le service SQL Browser (UDP 1434)."
  cas "install" $ m ou "extension" $ m ou "http" $ m ou "candidate" $ m
    retourner " — l'extension DuckDB « mssql » n'a pas pu être téléchargée (accès Internet)."
  fincas
retourner ""

&&
&& Connexion à SQL Server (extension mssql ou nanodbc)
&&

fonction OPTIONS_SOURCE(src)
  && options d'une source : JSON (source enregistrée) ou table (fiche en cours de saisie, test)
  si type(src.options) = "table"
    retourner src.options
  finsi
  essayer
    locale o = dejson(src.options)
    si o <> nul
      retourner o
    finsi
  capturer e
  finessayer
retourner {}

fonction CLE_POSTE(src)
  && clé de chiffrement locale des mots de passe mémorisés : propre au poste et au projet
retourner hachage(fichier.dossierperso() + "|" + dossier + "|" + src.id + "|atlas")

fonction FICHIER_SECRETS()
retourner fichier.joindre(fichier.dossierperso(), ".atlassql-secrets.json")

fonction SECRET_SOURCE(src, demander)
  globale secrets
  si secrets = nul
    secrets = {}
  finsi
  && mot de passe saisi dans la boîte de la source (test) : prioritaire
  si src.motdepasse <> nul et src.motdepasse <> ""
    retourner src.motdepasse
  finsi
  locale k = "S" + src.id
  si secrets[k] <> nul
    retourner secrets[k]
  finsi
  && mémorisé (chiffré) sur le poste ?
  si fichier.existe(FICHIER_SECRETS())
    essayer
      locale t = dejson(fichier.lire(FICHIER_SECRETS()))
      locale c = t[majuscule(k)]
      si c <> nul
        locale v = dechiffrer(c, CLE_POSTE(src))
        si v <> nul
          secrets[k] = v
          retourner v
        finsi
      finsi
    capturer e
    finessayer
  finsi
  si non demander
    retourner nul
  finsi
  locale r = ui.demandersecret("Mot de passe de « " + src.utilisateur + " » sur " + src.serveur + " :", ;
                               {memoriser = "Mémoriser sur ce poste (chiffré)", titre = "Source " + src.nom})
  si r = nul
    erreur "connexion annulée (mot de passe non saisi)"
  finsi
  secrets[k] = r.valeur
  si r.memoriser
    locale t = {}
    essayer
      si fichier.existe(FICHIER_SECRETS())
        t = dejson(fichier.lire(FICHIER_SECRETS()))
      finsi
    capturer e
    finessayer
    t[majuscule(k)] = chiffrer(r.valeur, CLE_POSTE(src))
    fichier.ecrire(FICHIER_SECRETS(), json(t))
  finsi
retourner r.valeur

procedure MEMORISER_SECRET(src, valeur, memoriser)
  && en mémoire pour la session ; chiffré dans ~/.atlassql-secrets.json si demandé (sinon effacé du fichier)
  globale secrets
  si secrets = nul
    secrets = {}
  finsi
  locale k = "S" + src.id
  secrets[k] = valeur
  locale t = {}
  essayer
    si fichier.existe(FICHIER_SECRETS())
      t = dejson(fichier.lire(FICHIER_SECRETS()))
    finsi
  capturer e
    t = {}
  finessayer
  si t = nul
    t = {}
  finsi
  si memoriser
    t[majuscule(k)] = chiffrer(valeur, CLE_POSTE(src))
  sinon
    t[majuscule(k)] = nul
  finsi
  fichier.ecrire(FICHIER_SECRETS(), json(t))
retourner

fonction CHAINE_CONNEXION(src, base)
  && chaîne ADO.NET de l'extension DuckDB « mssql » (clés : Server, Database, User Id, Password,
  && Encrypt, TrustServerCertificate, Integrated Security, Application Name)
  locale o = OPTIONS_SOURCE(src)
  locale c = "Server=" + src.serveur + ";Database=" + sisinon(base = nul ou base = "", "master", base)
  faire cas
  cas src.auth = "windows"
    c = c + ";Integrated Security=SSPI"
  cas src.auth = "entra"
    && Entra ID : le jeton vient d'un secret DuckDB (option azure_secret de l'ATTACH)
  autrement
    c = c + ";User Id=" + src.utilisateur + ";Password=" + VALEUR_CNX(SECRET_SOURCE(src, vrai))
  fincas
  c = c + ";Encrypt=" + sisinon(o.chiffrement = faux, "no", "yes")
  si o.confiance = vrai
    c = c + ";TrustServerCertificate=yes"
  finsi
  c = c + ";Application Name=Atlas SQL"
retourner c

fonction VALEUR_CNX(v)
  && une valeur contenant ; ou des espaces en bord est placée entre accolades (règle ADO.NET)
  si v = nul
    retourner ""
  finsi
  si ";" $ v ou rogner(v) <> v ou commencepar(v, "{")
    retourner "{" + remplacertexte(v, "}", "}}") + "}"
  finsi
retourner v

procedure CHARGER_EXTENSION(nom, depot)
  essayer
    requete("load " + nom)
  capturer e
    essayer
      requete("install " + nom + sisinon(depot = nul, "", " from " + depot))
      requete("load " + nom)
    capturer e2
      erreur "extension DuckDB « " + nom + " » non installée (téléchargement impossible : accès Internet ou proxy ?). Détail : " + COURT(chaine(e2), 160)
    finessayer
  finessayer
retourner

procedure ATTACHER(src, forcer)
  globale attachees
  si attachees = nul
    attachees = {}
  finsi
  locale al = ALIAS_SOURCE(src)
  si attachees[al] = vrai et non forcer
    retourner
  finsi
  si src.genre = "mssql"
    CHARGER_EXTENSION("mssql", "community")
    essayer
      requete("detach database if exists " + al)
    capturer e
    finessayer
    locale opt = "type mssql, read_only"
    si src.auth = "entra" et src.utilisateur <> nul et src.utilisateur <> ""
      opt = opt + ", azure_secret " + SQLTEXTE(src.utilisateur)
    finsi
    requete("attach " + SQLTEXTE(CHAINE_CONNEXION(src, "master")) + " as " + al + " (" + opt + ")")
    essayer
      requete("set mssql_connection_limit = " + chaine(reglages.agents + 2))
    capturer e
    finessayer
  sinonsi src.genre = "odbc"
    CHARGER_EXTENSION("nanodbc", "community")
  finsi
  attachees[al] = vrai
retourner

procedure DETACHER(src)
  essayer
    requete("detach database if exists " + ALIAS_SOURCE(src))
  capturer e
  finessayer
  si attachees <> nul
    attachees[ALIAS_SOURCE(src)] = faux
  finsi
retourner

fonction FONCTION_SCAN(src, tsql)
  && fonction de table DuckDB qui exécute un texte T-SQL sur la source
  si src.genre = "odbc"
    locale cnx = sisinon(src.auth = "odbc", src.utilisateur, ;
      "Driver={ODBC Driver 18 for SQL Server};Server=" + src.serveur + ";Database=master;" + ;
      sisinon(src.auth = "windows", "Trusted_Connection=yes;", "Uid=" + src.utilisateur + ";Pwd=" + SECRET_SOURCE(src, vrai) + ";") + ;
      sisinon(OPTIONS_SOURCE(src).chiffrement = faux, "Encrypt=no;", "Encrypt=yes;") + ;
      sisinon(OPTIONS_SOURCE(src).confiance = vrai, "TrustServerCertificate=yes;", ""))
    retourner "odbc_query(connection = " + SQLTEXTE(cnx) + ", query = " + SQLTEXTE(tsql) + ")"
  finsi
retourner "mssql_scan(" + SQLTEXTE(ALIAS_SOURCE(src)) + ", " + SQLTEXTE(tsql) + ")"

&&
&& Requêtes T-SQL d'extraction (une base : {B} = [base], {N} = nom de la base)
&&

fonction TSQL_BASES()
retourner "SELECT name AS base FROM sys.databases WHERE database_id > 4 AND state = 0 AND name NOT IN ('SSISDB', 'ReportServer', 'ReportServerTempDB', 'distribution') ORDER BY name"

fonction TSQL(genre)
  faire cas
  cas genre = "objets"
    retourner "SELECT N'{N}' AS base, s.name AS sch, o.name AS nom, " + ;
      "CASE o.type WHEN 'U' THEN 'TABLE' WHEN 'V' THEN 'VUE' WHEN 'P' THEN 'PROCEDURE' WHEN 'PC' THEN 'PROCEDURE' " + ;
      "WHEN 'X' THEN 'PROCEDURE' WHEN 'FN' THEN 'FONCTION' WHEN 'IF' THEN 'FONCTION' WHEN 'TF' THEN 'FONCTION' " + ;
      "WHEN 'FS' THEN 'FONCTION' WHEN 'FT' THEN 'FONCTION' WHEN 'AF' THEN 'FONCTION' WHEN 'TR' THEN 'DECLENCHEUR' " + ;
      "WHEN 'SN' THEN 'SYNONYME' WHEN 'SO' THEN 'SEQUENCE' ELSE 'CONTRAINTE' END AS genre, " + ;
      "ISNULL(po.name, '') AS parent_nom, ISNULL(dp.name, 'dbo') AS proprietaire, o.create_date AS cree, o.modify_date AS modifie, " + ;
      "CAST((SELECT SUM(p.rows) FROM {B}.sys.partitions p WHERE p.object_id = o.object_id AND p.index_id IN (0, 1)) AS BIGINT) AS lignes, " + ;
      "CAST((SELECT SUM(a.total_pages) * 8 FROM {B}.sys.partitions p JOIN {B}.sys.allocation_units a ON a.container_id = p.partition_id " + ;
      "WHERE p.object_id = o.object_id) AS BIGINT) AS taille_ko, CAST(NULL AS NVARCHAR(MAX)) AS definition, " + ;
      "CAST(COALESCE(sy.base_object_name COLLATE DATABASE_DEFAULT, rs.name COLLATE DATABASE_DEFAULT + N'.' + ro.name COLLATE DATABASE_DEFAULT, N'') AS NVARCHAR(600)) COLLATE DATABASE_DEFAULT AS cible, " + ;
      "CAST(o.type_desc AS NVARCHAR(120)) COLLATE DATABASE_DEFAULT AS detail " + ;
      "FROM {B}.sys.objects o JOIN {B}.sys.schemas s ON s.schema_id = o.schema_id " + ;
      "LEFT JOIN {B}.sys.objects po ON po.object_id = o.parent_object_id " + ;
      "LEFT JOIN {B}.sys.database_principals dp ON dp.principal_id = COALESCE(o.principal_id, s.principal_id) " + ;
      "LEFT JOIN {B}.sys.synonyms sy ON sy.object_id = o.object_id " + ;
      "LEFT JOIN {B}.sys.foreign_keys fk ON fk.object_id = o.object_id " + ;
      "LEFT JOIN {B}.sys.objects ro ON ro.object_id = fk.referenced_object_id " + ;
      "LEFT JOIN {B}.sys.schemas rs ON rs.schema_id = ro.schema_id " + ;
      "WHERE o.is_ms_shipped = 0 AND o.type IN ('U','V','P','PC','X','FN','IF','TF','FS','FT','AF','TR','SN','SO','PK','UQ','F','C','D') " + ;
      "UNION ALL SELECT N'{N}', s.name, i.name, 'INDEX', o.name, 'dbo', o.create_date, o.modify_date, " + ;
      "CAST(NULL AS BIGINT), CAST((SELECT SUM(a.used_pages) * 8 FROM {B}.sys.partitions p JOIN {B}.sys.allocation_units a " + ;
      "ON a.container_id = p.partition_id WHERE p.object_id = i.object_id AND p.index_id = i.index_id) AS BIGINT), " + ;
      "CAST(i.type_desc COLLATE DATABASE_DEFAULT + N' (' + STUFF((SELECT N', ' + c.name COLLATE DATABASE_DEFAULT FROM {B}.sys.index_columns ic JOIN {B}.sys.columns c " + ;
      "ON c.object_id = ic.object_id AND c.column_id = ic.column_id WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id " + ;
      "AND ic.is_included_column = 0 ORDER BY ic.key_ordinal FOR XML PATH('')), 1, 2, N'') + N')' AS NVARCHAR(MAX)) COLLATE DATABASE_DEFAULT, N'', " + ;
      "CAST(i.type_desc AS NVARCHAR(120)) COLLATE DATABASE_DEFAULT FROM {B}.sys.indexes i JOIN {B}.sys.objects o ON o.object_id = i.object_id " + ;
      "JOIN {B}.sys.schemas s ON s.schema_id = o.schema_id WHERE o.is_ms_shipped = 0 AND i.index_id > 0 AND o.type IN ('U', 'V') " + ;
      "UNION ALL SELECT N'{N}', s.name, st.name, 'STATISTIQUE', o.name, 'dbo', o.create_date, o.modify_date, CAST(NULL AS BIGINT), " + ;
      "CAST(NULL AS BIGINT), CAST(NULL AS NVARCHAR(MAX)), '', CASE WHEN st.auto_created = 1 THEN N'auto' ELSE N'manuelle' END " + ;
      "FROM {B}.sys.stats st JOIN {B}.sys.objects o ON o.object_id = st.object_id JOIN {B}.sys.schemas s ON s.schema_id = o.schema_id " + ;
      "WHERE o.is_ms_shipped = 0 AND o.type = 'U' " + ;
      "UNION ALL SELECT N'{N}', s.name, t.name, 'TYPE', '', 'dbo', NULL, NULL, CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), " + ;
      "CAST(NULL AS NVARCHAR(MAX)), CAST(TYPE_NAME(t.system_type_id) COLLATE DATABASE_DEFAULT + CASE WHEN t.max_length > 0 AND TYPE_NAME(t.system_type_id) LIKE '%char%' " + ;
      "THEN N'(' + CAST(t.max_length AS NVARCHAR(10)) + N')' ELSE N'' END AS NVARCHAR(600)) COLLATE DATABASE_DEFAULT, N'type utilisateur' " + ;
      "FROM {B}.sys.types t JOIN {B}.sys.schemas s ON s.schema_id = t.schema_id WHERE t.is_user_defined = 1 " + ;
      "UNION ALL SELECT N'{N}', 'dbo', a.name, 'CLR', '', 'dbo', a.create_date, a.modify_date, CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), " + ;
      "CAST(NULL AS NVARCHAR(MAX)), CAST(a.permission_set_desc COLLATE DATABASE_DEFAULT + N' · ' + a.clr_name COLLATE DATABASE_DEFAULT AS NVARCHAR(600)) COLLATE DATABASE_DEFAULT, N'assembly' " + ;
      "FROM {B}.sys.assemblies a WHERE a.is_user_defined = 1 " + ;
      "UNION ALL SELECT N'{N}', s.name, o.name COLLATE DATABASE_DEFAULT + N'$' + CAST(p.partition_number AS NVARCHAR(10)), 'PARTITION', o.name, 'dbo', NULL, NULL, " + ;
      "CAST(p.rows AS BIGINT), CAST(NULL AS BIGINT), CAST(NULL AS NVARCHAR(MAX)), '', N'partition' " + ;
      "FROM {B}.sys.partitions p JOIN {B}.sys.objects o ON o.object_id = p.object_id JOIN {B}.sys.schemas s ON s.schema_id = o.schema_id " + ;
      "WHERE o.is_ms_shipped = 0 AND p.index_id IN (0, 1) AND EXISTS (SELECT 1 FROM {B}.sys.partitions p2 WHERE p2.object_id = p.object_id " + ;
      "AND p2.index_id = p.index_id AND p2.partition_number > 1)"
  cas genre = "modules"
    retourner "SELECT N'{N}' AS base, s.name AS sch, o.name AS nom, 'MODULE' AS genre, '' AS parent_nom, m.definition AS definition " + ;
      "FROM {B}.sys.sql_modules m JOIN {B}.sys.objects o ON o.object_id = m.object_id JOIN {B}.sys.schemas s ON s.schema_id = o.schema_id " + ;
      "WHERE o.is_ms_shipped = 0"
  cas genre = "colonnes"
    retourner "SELECT N'{N}' AS base, s.name AS sch, o.name AS table_nom, c.name AS nom, c.column_id AS ordre, " + ;
      "CAST(CASE WHEN t.is_user_defined = 1 THEN ts.name COLLATE DATABASE_DEFAULT + N'.' + t.name COLLATE DATABASE_DEFAULT WHEN t.name IN ('varchar','char','varbinary','binary') " + ;
      "THEN t.name COLLATE DATABASE_DEFAULT + N'(' + CASE WHEN c.max_length = -1 THEN N'max' ELSE CAST(c.max_length AS NVARCHAR(10)) END + N')' " + ;
      "WHEN t.name IN ('nvarchar','nchar') THEN t.name COLLATE DATABASE_DEFAULT + N'(' + CASE WHEN c.max_length = -1 THEN N'max' ELSE CAST(c.max_length / 2 AS NVARCHAR(10)) END + N')' " + ;
      "WHEN t.name IN ('decimal','numeric') THEN t.name COLLATE DATABASE_DEFAULT + N'(' + CAST(c.precision AS NVARCHAR(5)) + N',' + CAST(c.scale AS NVARCHAR(5)) + N')' " + ;
      "ELSE t.name COLLATE DATABASE_DEFAULT END AS NVARCHAR(300)) AS type_sql, CAST(CASE WHEN t.name LIKE 'n%char' THEN c.max_length / 2 ELSE c.max_length END AS INT) AS longueur, " + ;
      "CAST(c.precision AS INT) AS prec, CAST(c.scale AS INT) AS echelle, c.is_nullable AS nullable, c.is_identity AS identite, " + ;
      "c.is_computed AS calculee, dc.definition COLLATE DATABASE_DEFAULT AS defaut, " + ;
      "CAST(CASE WHEN EXISTS (SELECT 1 FROM {B}.sys.index_columns ic JOIN {B}.sys.indexes i ON i.object_id = ic.object_id " + ;
      "AND i.index_id = ic.index_id WHERE i.is_primary_key = 1 AND ic.object_id = c.object_id AND ic.column_id = c.column_id) " + ;
      "THEN 1 ELSE 0 END AS BIT) AS pk, " + ;
      "(SELECT TOP 1 N'{N}.' + rs.name COLLATE DATABASE_DEFAULT + N'.' + ro.name COLLATE DATABASE_DEFAULT + N'.' + rc.name COLLATE DATABASE_DEFAULT FROM {B}.sys.foreign_key_columns fkc " + ;
      "JOIN {B}.sys.objects ro ON ro.object_id = fkc.referenced_object_id JOIN {B}.sys.schemas rs ON rs.schema_id = ro.schema_id JOIN {B}.sys.columns rc ON rc.object_id = fkc.referenced_object_id " + ;
      "AND rc.column_id = fkc.referenced_column_id WHERE fkc.parent_object_id = c.object_id AND fkc.parent_column_id = c.column_id) AS fk_vers " + ;
      "FROM {B}.sys.columns c JOIN {B}.sys.objects o ON o.object_id = c.object_id JOIN {B}.sys.schemas s ON s.schema_id = o.schema_id " + ;
      "JOIN {B}.sys.types t ON t.user_type_id = c.user_type_id JOIN {B}.sys.schemas ts ON ts.schema_id = t.schema_id LEFT JOIN {B}.sys.default_constraints dc ON dc.object_id = c.default_object_id " + ;
      "WHERE o.is_ms_shipped = 0 AND o.type IN ('U', 'V')"
  cas genre = "dependances"
    retourner "SELECT N'{N}' AS base, OBJECT_SCHEMA_NAME(d.referencing_id, DB_ID(N'{N}')) AS sch, " + ;
      "OBJECT_NAME(d.referencing_id, DB_ID(N'{N}')) AS nom, ISNULL(d.referenced_server_name, '') AS ref_serveur, " + ;
      "ISNULL(d.referenced_database_name, '') AS ref_base, ISNULL(d.referenced_schema_name, '') AS ref_sch, " + ;
      "d.referenced_entity_name AS ref_nom, CASE WHEN d.is_caller_dependent = 1 THEN 'DYNAMIQUE' ELSE 'CATALOGUE' END AS nature " + ;
      "FROM {B}.sys.sql_expression_dependencies d WHERE d.referenced_entity_name IS NOT NULL"
  cas genre = "stats"
    retourner "SELECT N'{N}' AS base, OBJECT_SCHEMA_NAME(ps.object_id, ps.database_id) AS sch, OBJECT_NAME(ps.object_id, ps.database_id) AS nom, " + ;
      "CAST(N'' AS NVARCHAR(400)) COLLATE DATABASE_DEFAULT AS texte, ps.execution_count AS executions, ps.total_worker_time / 1000.0 AS cpu_ms, " + ;
      "ps.total_elapsed_time / 1000.0 AS duree_ms, ps.total_logical_reads AS lectures, ps.total_logical_writes AS ecritures, " + ;
      "CAST(0 AS BIGINT) AS lignes, CAST(0 AS BIGINT) AS lignes_max, CAST(0 AS BIGINT) AS memoire_ko, ps.last_execution_time AS derniere, " + ;
      "LEFT(CAST(qp.query_plan AS NVARCHAR(MAX)), 60000) AS [plan] " + ;
      "FROM sys.dm_exec_procedure_stats ps OUTER APPLY sys.dm_exec_query_plan(ps.plan_handle) qp WHERE ps.database_id = DB_ID(N'{N}') " + ;
      "UNION ALL SELECT N'{N}', OBJECT_SCHEMA_NAME(st.objectid, st.dbid), ISNULL(OBJECT_NAME(st.objectid, st.dbid), '(ad hoc)'), " + ;
      "CAST(LEFT(SUBSTRING(st.text, qs.statement_start_offset / 2 + 1, 400), 400) AS NVARCHAR(400)) COLLATE DATABASE_DEFAULT, qs.execution_count, qs.total_worker_time / 1000.0, " + ;
      "qs.total_elapsed_time / 1000.0, qs.total_logical_reads, qs.total_logical_writes, qs.total_rows, qs.max_rows, " + ;
      "qs.max_grant_kb, qs.last_execution_time, CAST(NULL AS NVARCHAR(MAX)) " + ;
      "FROM (SELECT TOP 200 * FROM sys.dm_exec_query_stats ORDER BY total_worker_time DESC) qs " + ;
      "CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st WHERE st.dbid = DB_ID(N'{N}')"
  cas genre = "index_manquants"
    retourner "SELECT N'{N}' AS base, OBJECT_SCHEMA_NAME(d.object_id, d.database_id) AS sch, OBJECT_NAME(d.object_id, d.database_id) AS table_nom, " + ;
      "ISNULL(d.equality_columns, '') AS egalite, ISNULL(d.inequality_columns, '') AS inegalite, ISNULL(d.included_columns, '') AS inclus, " + ;
      "s.avg_user_impact AS impact, s.user_seeks + s.user_scans AS demandes " + ;
      "FROM sys.dm_db_missing_index_details d JOIN sys.dm_db_missing_index_groups g ON g.index_handle = d.index_handle " + ;
      "JOIN sys.dm_db_missing_index_group_stats s ON s.group_handle = g.index_group_handle WHERE d.database_id = DB_ID(N'{N}')"
  cas genre = "serveurs_lies"
    retourner "SELECT N'' AS base, N'' AS sch, s.name AS nom, 'SERVEUR_LIE' AS genre, '' AS parent_nom, 'sa' AS proprietaire, " + ;
      "NULL AS cree, s.modify_date AS modifie, CAST(NULL AS BIGINT) AS lignes, CAST(NULL AS BIGINT) AS taille_ko, " + ;
      "CAST(NULL AS NVARCHAR(MAX)) AS definition, CAST(s.data_source AS NVARCHAR(600)) COLLATE DATABASE_DEFAULT AS cible, CAST(s.product COLLATE DATABASE_DEFAULT + N' / ' + s.provider COLLATE DATABASE_DEFAULT AS NVARCHAR(200)) AS detail " + ;
      "FROM sys.servers s WHERE s.is_linked = 1"
  cas genre = "jobs"
    retourner "SELECT j.name AS job, st.step_id AS etape, st.step_name AS nom_etape, st.command AS commande, st.database_name AS base, " + ;
      "ISNULL(sc.active_start_time, 0) AS heure_debut, " + ;
      "(SELECT AVG(CAST(h.run_duration / 10000 * 3600 + h.run_duration / 100 % 100 * 60 + h.run_duration % 100 AS FLOAT)) " + ;
      "FROM msdb.dbo.sysjobhistory h WHERE h.job_id = j.job_id AND h.step_id = st.step_id) AS duree_moy_s, " + ;
      "CASE sc.freq_type WHEN 4 THEN 'quotidien' WHEN 8 THEN 'hebdomadaire' WHEN 16 THEN 'mensuel' WHEN 32 THEN 'mensuel' " + ;
      "WHEN 64 THEN 'au démarrage' ELSE 'ponctuel' END AS frequence, CAST(j.enabled AS BIT) AS actif " + ;
      "FROM msdb.dbo.sysjobs j JOIN msdb.dbo.sysjobsteps st ON st.job_id = j.job_id " + ;
      "LEFT JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id LEFT JOIN msdb.dbo.sysschedules sc ON sc.schedule_id = js.schedule_id " + ;
      "WHERE st.subsystem = 'TSQL'"
  fincas
retourner ""

fonction TSQL_BASE(genre, base)
  locale b = "[" + remplacertexte(base, "]", "]]") + "]"
  locale n = remplacertexte(base, "'", "''")
retourner remplacertexte(remplacertexte(TSQL(genre), "{B}", b), "{N}", n)

fonction TABLE_EXT(genre)
  faire cas
  cas genre = "objets" ou genre = "modules" ou genre = "serveurs_lies"
    retourner "ext_objets"
  cas genre = "colonnes"
    retourner "ext_colonnes"
  cas genre = "dependances"
    retourner "ext_dependances"
  cas genre = "stats"
    retourner "ext_stats"
  cas genre = "index_manquants"
    retourner "ext_index_manquants"
  cas genre = "jobs"
    retourner "ext_jobs"
  cas genre = "profils"
    retourner "ext_profils"
  fincas
retourner ""

&&
&& Traitements de la file : inventaire, extraction, normalisation, analyse
&&

procedure INVENTAIRE_SERVEUR(s, t)
  && SQL Server : bases à analyser, puis une extraction par base et par genre
  locale src = SOURCE(t.source_id)
  locale nomsrv = RV(s, "select v from " + FONCTION_SCAN(src, "SELECT CAST(@@SERVERNAME AS NVARCHAR(256)) AS v"), nul)
  si nomsrv = nul ou nomsrv = ""
    nomsrv = src.serveur
  finsi
  t.params.nomserveur = nomsrv
  locale bases = {}
  si src.base <> nul et rogner(src.base) <> ""
    pour chaque b dans decouper(src.base, ",")
      inserer(bases, rogner(b))
    suivant
  sinon
    pour chaque r dans RQ(s, "select base from " + FONCTION_SCAN(src, TSQL_BASES()), nul)
      inserer(bases, r.base)
    suivant
  finsi
  locale o = OPTIONS_SOURCE(src)
  locale genres = {"objets", "modules", "colonnes", "dependances"}
  si o.stats <> faux
    inserer(genres, "stats")
    inserer(genres, "index_manquants")
  finsi
  locale norm = t.params.normalisation
  pour chaque b dans bases
    pour chaque g dans genres
      locale id = AJOUTER_TRAVAIL("extraction", "Extraction " + g + " · " + b, nomsrv + "." + b, ;
                                  {source_id = src.id, serveur = nomsrv, priorite = 2, genre_ext = g, base = b, apres = {t.id}})
      DEPEND(norm, id)
    suivant
  suivant
  && niveau serveur : serveurs liés, jobs
  pour chaque g dans {"serveurs_lies", "jobs"}
    locale id2 = AJOUTER_TRAVAIL("extraction", "Extraction " + g, nomsrv, ;
                                 {source_id = src.id, serveur = nomsrv, priorite = 2, genre_ext = g, base = "", apres = {t.id}})
    DEPEND(norm, id2)
  suivant
  t.message = chaine(#bases) + " base(s) : " + COURT(joindre(bases, ", "), 120)
retourner

procedure EXTRAIRE(s, t)
  locale src = SOURCE(t.source_id)
  locale g = t.params.genre_ext
  si src.genre = "demo"
    PROGRES(t, 0.1, "Lecture du catalogue simulé…")
    si g = "captures"
      DEMO_CAPTURES(s)
    sinon
      DEMO_EXTRAIRE(s, src.id, t.serveur, g, t)
    finsi
    t.message = "Catalogue de démonstration : " + g
    retourner
  finsi
  si src.genre = "dossier"
    EXTRAIRE_SCRIPTS(s, t, src)
    retourner
  finsi
  && SQL Server
  locale table_ = TABLE_EXT(g)
  locale tsql = sisinon(t.params.base = "", TSQL(g), TSQL_BASE(g, t.params.base))
  PROGRES(t, 0.05, "Requête sur " + t.serveur + "…")
  locale avant = RV(s, "select count(*) from " + table_ + " where source_id = ?", {src.id})
  RQ(s, "insert into " + table_ + " by name select ? as source_id, ? as serveur, * from " + FONCTION_SCAN(src, tsql), ;
     {src.id, t.serveur})
  locale apres_ = RV(s, "select count(*) from " + table_ + " where source_id = ?", {src.id})
  t.message = chaine(apres_ - avant) + " ligne(s) extraites"
retourner

procedure EXTRAIRE_SCRIPTS(s, t, src)
  && scripts .sql : un objet par CREATE (lots séparés par GO), colonnes des CREATE TABLE
  locale fichiers = {}
  pour chaque f dans fichier.liste(src.dossier, vrai)
    si minuscule(fichier.extension(f)) = ".sql"
      inserer(fichiers, f)
    finsi
  suivant
  locale serveur = sisinon(src.serveur = nul ou src.serveur = "", "SCRIPTS", src.serveur)
  locale basedef = sisinon(src.base = nul ou src.base = "", fichier.nom(src.dossier), src.base)
  locale objets_ = {}
  locale cols = {}
  locale i = 0
  pour chaque f dans fichiers
    i += 1
    PROGRES(t, i / max(1, #fichiers), fichier.nom(f))
    locale texte = fichier.lire(fichier.joindre(src.dossier, f))
    locale base = basedef
    locale lot = {}
    pour chaque l dans decouper(remplacertexte(texte, car(13), ""), car(10))
      locale u = majuscule(rogner(l))
      si u = "GO" ou commencepar(u, "GO ")
        SCRIPT_LOT(s, joindre(lot, car(10)), serveur, base, src, objets_, cols)
        lot = {}
      sinonsi commencepar(u, "USE ")
        base = remplacertexte(remplacertexte(remplacertexte(rogner(souschaine(rogner(l), 5)), "[", ""), "]", ""), ";", "")
      sinon
        inserer(lot, l)
      finsi
    suivant
    SCRIPT_LOT(s, joindre(lot, car(10)), serveur, base, src, objets_, cols)
  suivant
  INSERER_LIGNES(s, "ext_objets", SPEC_TABLE(s, "ext_objets"), objets_)
  INSERER_LIGNES(s, "ext_colonnes", SPEC_TABLE(s, "ext_colonnes"), cols)
  t.message = chaine(#fichiers) + " script(s), " + #objets_ + " objet(s)"
retourner

procedure SCRIPT_LOT(s, texte, serveur, base, src, objets_, cols)
  si rogner(texte) = ""
    retourner
  finsi
  locale toks = JETONS_TEXTE(s, texte)
  locale n = #toks
  pour i = 1 a n - 2
    si toks[i].u = "CREATE" ou (toks[i].u = "ALTER" et toks[i + 1].u <> "TABLE")
      locale k = i + 1
      si toks[k].u = "OR" et k + 2 <= n
        k += 2
      finsi
      locale g = toks[k].u
      locale genre = ""
      faire cas
      cas g = "PROC" ou g = "PROCEDURE"
        genre = "PROCEDURE"
      cas g = "FUNCTION"
        genre = "FONCTION"
      cas g = "VIEW"
        genre = "VUE"
      cas g = "TRIGGER"
        genre = "DECLENCHEUR"
      cas g = "TABLE"
        genre = "TABLE"
      cas g = "SYNONYM"
        genre = "SYNONYME"
      cas g = "SEQUENCE"
        genre = "SEQUENCE"
      cas g = "TYPE"
        genre = "TYPE"
      cas (g = "UNIQUE" ou g = "CLUSTERED" ou g = "NONCLUSTERED" ou g = "INDEX")
        genre = "INDEX"
      fincas
      si genre <> "" et k + 1 <= n
        locale m = k + 1
        si genre = "INDEX"
          tantque m <= n et toks[m].u <> "INDEX"
            m += 1
          fintantque
          m += 1
        finsi
        locale nm = LIRE_NOM(toks, m)
        si nm <> nul et non commencepar(nm.texte, "#")
          locale pr = PARTIES_REF(nm.parties)
          locale sch = sisinon(pr.p2 = "", "dbo", pr.p2)
          locale cible = ""
          locale parent = ""
          si genre = "SYNONYME"
            pour q = nm.fin a n
              si toks[q].u = "FOR"
                locale c2 = LIRE_NOM(toks, q + 1)
                si c2 <> nul
                  cible = c2.texte
                finsi
                sortir
              finsi
            suivant
          finsi
          si genre = "INDEX" ou genre = "DECLENCHEUR"
            pour q = nm.fin a n
              si toks[q].u = "ON"
                locale c3 = LIRE_NOM(toks, q + 1)
                si c3 <> nul
                  parent = c3.parties[#c3.parties]
                finsi
                sortir
              finsi
            suivant
          finsi
          locale code_ = genre = "PROCEDURE" ou genre = "FONCTION" ou genre = "VUE" ou genre = "DECLENCHEUR"
          inserer(objets_, {source_id = src.id, serveur = serveur, base = sisinon(pr.p3 = "", base, pr.p3), sch = sch, nom = pr.p1, ;
                            genre = genre, parent_nom = parent, proprietaire = "dbo", cree = nul, modifie = nul, lignes = nul, ;
                            taille_ko = nul, definition = sisinon(code_, texte, nul), cible = cible, detail = "script"})
          si genre = "TABLE"
            SCRIPT_COLONNES(toks, nm.fin + 1, serveur, sisinon(pr.p3 = "", base, pr.p3), sch, pr.p1, src, cols)
          finsi
          si code_
            retourner                  && un module par lot
          finsi
        finsi
      finsi
    finsi
  suivant
retourner

procedure SCRIPT_COLONNES(toks, d, serveur, base, sch, table_, src, cols)
  && CREATE TABLE t ( col type [NULL|NOT NULL] [IDENTITY] [PRIMARY KEY] [REFERENCES x(y)], … )
  locale n = #toks
  si d > n ou toks[d].o <> "("
    retourner
  finsi
  locale args = {}
  locale dp = 0
  locale debut = d + 1
  pour k = d a n
    si toks[k].o = "("
      dp += 1
    sinonsi toks[k].o = ")"
      dp -= 1
      si dp = 0
        inserer(args, {d = debut, f = k - 1})
        sortir
      finsi
    sinonsi toks[k].o = "," et dp = 1
      inserer(args, {d = debut, f = k - 1})
      debut = k + 1
    finsi
  suivant
  locale ordre = 0
  locale pks = {}
  pour chaque a dans args
    locale j = toks[a.d]
    si j.u = "CONSTRAINT" ou j.u = "PRIMARY" ou j.u = "FOREIGN" ou j.u = "UNIQUE" ou j.u = "INDEX" ou j.u = "CHECK"
      && contrainte de table : PRIMARY KEY (a, b)
      pour q = a.d a a.f
        si toks[q].u = "PRIMARY"
          pour z = q a a.f
            si toks[z].k = "W" ou toks[z].k = "I"
              si toks[z].u <> "PRIMARY" et toks[z].u <> "KEY" et toks[z].u <> "CLUSTERED" et toks[z].u <> "NONCLUSTERED" ;
                 et toks[z].u <> "ASC" et toks[z].u <> "DESC"
                pks[majuscule(NOM_PARTIE(toks[z]))] = vrai
              finsi
            finsi
          suivant
        finsi
      suivant
      boucler
    finsi
    ordre += 1
    locale nom = NOM_PARTIE(j)
    locale typ = TYPE_A(toks, a.d + 1)
    locale nn = faux, ident = faux, pk = faux, fk = nul
    pour q = a.d a a.f
      si toks[q].u = "NOT" et q + 1 <= a.f et toks[q + 1].u = "NULL"
        nn = vrai
      finsi
      si toks[q].u = "IDENTITY"
        ident = vrai
      finsi
      si toks[q].u = "PRIMARY"
        pk = vrai
      finsi
      si toks[q].u = "REFERENCES"
        locale rf = LIRE_NOM(toks, q + 1)
        si rf <> nul et rf.fin + 2 <= a.f
          fk = base + "." + sisinon(#rf.parties >= 2, rf.parties[#rf.parties - 1], "dbo") + "." + rf.parties[#rf.parties] + ;
               "." + NOM_PARTIE(toks[rf.fin + 2])
        finsi
      finsi
    suivant
    inserer(cols, {source_id = src.id, serveur = serveur, base = base, sch = sch, table_nom = table_, nom = nom, ordre = ordre, ;
                   type_sql = typ, longueur = nul, prec = nul, echelle = nul, nullable = non (nn ou pk), identite = ident, ;
                   calculee = typ = "AS", defaut = nul, pk = pk, fk_vers = fk})
  suivant
  pour chaque c dans cols
    si c.table_nom = table_ et pks[majuscule(c.nom)] = vrai
      c.pk = vrai
      c.nullable = faux
    finsi
  suivant
retourner

procedure NORMALISER(s, t)
  && extractions -> référentiel central (objets, colonnes, statistiques…), puis lots d'analyse
  locale sid = t.source_id
  PROGRES(t, 0.05, "Nettoyage des résultats précédents…")
  locale anciens = "(select id from objets where source_id = " + entier(sid) + ")"
  pour chaque tb dans {"colonnes", "refs_brutes", "instructions", "ast", "variables", "sql_dynamique", "diagnostics", ;
                       "jointures", "regles", "metriques", "stats_requetes", "index_manquants", "dico_tables", "dico_colonnes", "duplications"}
    RQ(s, "delete from " + tb + " where objet_id in " + anciens, nul)
  suivant
  RQ(s, "delete from dependances where de_id in " + anciens + " or vers_id in " + anciens, nul)
  RQ(s, "delete from objets where source_id = ?", {sid})
  PROGRES(t, 0.2, "Objets…")
  RQ(s, "insert into objets select nextval('seq_objets'), lower(serveur || '.' || base || '.' || sch || '.' || nom), serveur, base, sch, nom, " + ;
        "genre, null, parent_nom, proprietaire, cree, modifie, lignes, taille_ko, definition, cible, detail, source_id " + ;
        "from (select distinct on (serveur, base, sch, nom, genre, parent_nom) * from ext_objets where source_id = ? and genre <> 'MODULE')", {sid})
  && définitions des modules
  RQ(s, "update objets o set definition = m.definition from ext_objets m where m.source_id = ? and m.genre = 'MODULE' " + ;
        "and o.source_id = m.source_id and o.serveur = m.serveur and o.base = m.base and o.sch = m.sch and o.nom = m.nom " + ;
        "and o.genre in ('PROCEDURE', 'FONCTION', 'VUE', 'DECLENCHEUR')", {sid})
  && jobs SQL Agent : un objet par job, ses étapes forment sa définition (analysée comme du T-SQL)
  RQ(s, "insert into objets select nextval('seq_objets'), lower(serveur || '.' || min(base) || '.job.' || job), serveur, min(base), 'job', job, 'JOB', null, '', " + ;
        "'sa', null, null, null, null, string_agg('-- étape ' || etape || ' : ' || nom_etape || chr(10) || commande, chr(10) order by etape), " + ;
        "max(frequence), 'début ' || lpad((min(heure_debut) // 10000)::varchar, 2, '0') || ':' || lpad((min(heure_debut) // 100 % 100)::varchar, 2, '0') " + ;
        "|| ' · ' || round(sum(duree_moy_s)) || ' s', source_id from ext_jobs where source_id = ? group by serveur, job, source_id", {sid})
  && parents (index, contraintes, déclencheurs, partitions -> table)
  RQ(s, "update objets o set parent_id = p.id from objets p where o.source_id = ? and p.source_id = o.source_id and o.parent_nom <> '' " + ;
        "and p.serveur = o.serveur and p.base = o.base and p.sch = o.sch and p.nom = o.parent_nom and p.genre in ('TABLE', 'VUE')", {sid})
  PROGRES(t, 0.4, "Colonnes…")
  RQ(s, "insert into colonnes select o.id, c.serveur, c.base, c.sch, c.table_nom, c.nom, c.ordre, c.type_sql, c.longueur, c.prec, c.echelle, " + ;
        "c.nullable, c.identite, c.calculee, c.defaut, c.pk, c.fk_vers, p.distincts, p.nuls, p.exemples " + ;
        "from ext_colonnes c join objets o on o.source_id = c.source_id and o.serveur = c.serveur and o.base = c.base " + ;
        "and o.sch = c.sch and o.nom = c.table_nom and o.genre in ('TABLE', 'VUE') " + ;
        "left join ext_profils p on p.source_id = c.source_id and p.serveur = c.serveur and p.base = c.base and p.sch = c.sch " + ;
        "and p.table_nom = c.table_nom and p.colonne = c.nom where c.source_id = ?", {sid})
  PROGRES(t, 0.55, "Statistiques d'exécution…")
  RQ(s, "insert into stats_requetes select o.id, e.serveur, e.base, e.texte, e.executions, e.cpu_ms, e.duree_ms, e.lectures, e.ecritures, " + ;
        "e.lignes, e.lignes_max, e.memoire_ko, e.derniere, e.plan, " + ;
        "try_cast(regexp_extract(e.plan, 'StatementSubTreeCost=" + car(34) + "([0-9.eE+-]+)', 1) as double), " + ;
        "array_to_string(list_distinct(regexp_extract_all(e.plan, 'PhysicalOp=" + car(34) + "([^" + car(34) + "]+)', 1)), ', ') " + ;
        "from ext_stats e left join objets o on o.source_id = e.source_id and o.serveur = e.serveur and o.base = e.base " + ;
        "and o.sch = e.sch and o.nom = e.nom and o.genre in ('PROCEDURE', 'FONCTION', 'DECLENCHEUR') where e.source_id = ?", {sid})
  RQ(s, "insert into index_manquants select o.id, e.serveur, e.base, e.sch, e.table_nom, e.egalite, e.inegalite, e.inclus, e.impact, e.demandes " + ;
        "from ext_index_manquants e left join objets o on o.source_id = e.source_id and o.serveur = e.serveur and o.base = e.base " + ;
        "and o.sch = e.sch and o.nom = e.table_nom and o.genre = 'TABLE' where e.source_id = ?", {sid})
  RQ(s, "update sources set analysee = now() where id = ?", {sid})
  && lots d'analyse du code
  PROGRES(t, 0.8, "Préparation des lots d'analyse…")
  locale ids = {}
  pour chaque r dans RQ(s, "select id from objets where source_id = ? and definition is not null " + ;
                          "and genre in ('PROCEDURE', 'FONCTION', 'VUE', 'DECLENCHEUR', 'JOB') order by length(definition) desc", {sid})
    inserer(ids, r.id)
  suivant
  locale taille = max(5, entier(reglages.lot))
  locale lot = {}
  locale nlots = 0
  pour chaque id dans ids
    inserer(lot, id)
    si #lot >= taille
      nlots += 1
      DEPEND(t.params.resolution, AJOUTER_TRAVAIL("analyse", "Analyse du code · lot " + nlots, t.cible, ;
                                                  {source_id = sid, priorite = 3, ids = lot, apres = {t.id}}))
      lot = {}
    finsi
  suivant
  si #lot > 0
    nlots += 1
    DEPEND(t.params.resolution, AJOUTER_TRAVAIL("analyse", "Analyse du code · lot " + nlots, t.cible, ;
                                                {source_id = sid, priorite = 3, ids = lot, apres = {t.id}}))
  finsi
  && profilage des colonnes (option de la source SQL Server) : avant le dictionnaire
  locale src = SOURCE(sid)
  si (src.genre = "mssql" ou src.genre = "odbc") et OPTIONS_SOURCE(src).profilage = vrai et t.params.dictionnaire <> nul
    pour chaque r dans RQ(s, "select id, base || '.' || sch || '.' || nom as n, serveur from objets where source_id = ? and genre = 'TABLE' " + ;
                             "and coalesce(lignes, 0) > 0 order by lignes desc", {sid})
      DEPEND(t.params.dictionnaire, AJOUTER_TRAVAIL("profilage", "Profilage · " + r.n, r.n, ;
                                                    {source_id = sid, serveur = r.serveur, priorite = 4, objet_id = r.id, apres = {t.id}}))
    suivant
  finsi
  locale nobj = RV(s, "select count(*) from objets where source_id = ?", {sid})
  t.message = NB(nobj) + " objets, " + #ids + " modules en " + nlots + " lot(s)"
retourner

procedure ANALYSER_LOT(s, t)
  locale ids = t.params.ids
  locale liste = joindre(ids, ",")
  PROGRES(t, 0.02, "Découpage lexical de " + #ids + " module(s)…")
  locale jetons = JETONS_OBJETS(s, ids)
  locale meta = RQ(s, "select id, serveur, base, sch, nom, genre from objets where list_contains(string_split(?, ',')::integer[], id)", {liste})
  locale L = {refs = {}, ins = {}, ast = {}, vars = {}, dyn = {}, var_ = {}, diag = {}, jt = {}, rg = {}, met = {}}
  locale k = 0
  pour chaque o dans meta
    k += 1
    PROGRES(t, 0.05 + 0.75 * k / #meta, o.sch + "." + o.nom)
    locale R = ANALYSER_JETONS(jetons[chaine(o.id)], {serveur = o.serveur, base = o.base, sch = o.sch, nom = o.nom, genre = o.genre})
    pour chaque x dans R.refs
      inserer(L.refs, {objet_id = o.id, ref = x.ref, p1 = x.p1, p2 = x.p2, p3 = x.p3, p4 = x.p4, nature = x.nature, ;
                       ligne = x.ligne, distant = x.distant, sql = x.sql})
    suivant
    pour chaque x dans R.instructions
      inserer(L.ins, {objet_id = o.id, num = x.num, ligne_debut = x.l1, ligne_fin = x.l2, genre = x.genre, phase = x.phase, ;
                      profondeur = x.prof, texte = x.texte, normalise = COURT(x.normalise, 3000), empreinte = hachage(x.normalise), ;
                      tables = x.tables})
    suivant
    pour chaque x dans R.ast
      inserer(L.ast, {objet_id = o.id, id = x.id, parent = x.parent, genre = x.genre, libelle = x.libelle, phase = x.phase, ;
                      ligne_debut = x.l1, ligne_fin = x.l2, ordre = x.ordre})
    suivant
    pour chaque x dans R.vars
      inserer(L.vars, {objet_id = o.id, nom = x.nom, genre = x.genre, type_sql = x.type, ligne = x.ligne, defaut = x.defaut})
    suivant
    pour chaque x dans R.dyn
      inserer(L.dyn, {objet_id = o.id, ligne = x.ligne, mode = x.mode, variable = x.variable, sql_reconstitue = x.sql, ;
                      parametres = x.params, types = x.types, empreinte = hachage(chaine(x.sql)), valeurs = ""})
    suivant
    pour chaque x dans R.diag
      inserer(L.diag, {objet_id = o.id, module = "analyse", regle = x.regle, niveau = x.niveau, message = x.message, ;
                       suggestion = x.suggestion, correctif = "", ligne = x.ligne})
    suivant
    pour chaque x dans R.jointures
      inserer(L.jt, {objet_id = o.id, ligne = x.ligne, t1 = x.t1, c1 = x.c1, t2 = x.t2, c2 = x.c2})
    suivant
    pour chaque x dans R.regles
      inserer(L.rg, {objet_id = o.id, ligne = x.ligne, genre = x.genre, texte = x.texte, normalise = x.normalise, ;
                     empreinte = hachage(x.normalise)})
    suivant
    inserer(L.met, {objet_id = o.id, lignes_code = R.lignes, nb_instructions = #R.instructions, complexite = R.complexite})
  suivant
  PROGRES(t, 0.85, "Enregistrement…")
  pour chaque tb dans {"refs_brutes", "instructions", "ast", "variables", "sql_dynamique", "jointures", "regles", "metriques"}
    RQ(s, "delete from " + tb + " where list_contains(string_split(?, ',')::integer[], objet_id)", {liste})
  suivant
  RQ(s, "delete from diagnostics where module = 'analyse' and list_contains(string_split(?, ',')::integer[], objet_id)", {liste})
  INSERER_LIGNES(s, "refs_brutes", SPEC_TABLE(s, "refs_brutes"), L.refs)
  INSERER_LIGNES(s, "instructions", SPEC_TABLE(s, "instructions"), L.ins)
  INSERER_LIGNES(s, "ast", SPEC_TABLE(s, "ast"), L.ast)
  INSERER_LIGNES(s, "variables", SPEC_TABLE(s, "variables"), L.vars)
  INSERER_LIGNES(s, "sql_dynamique", SPEC_TABLE(s, "sql_dynamique"), L.dyn)
  INSERER_LIGNES(s, "diagnostics", SPEC_TABLE(s, "diagnostics"), L.diag)
  INSERER_LIGNES(s, "jointures", SPEC_TABLE(s, "jointures"), L.jt)
  INSERER_LIGNES(s, "regles", SPEC_TABLE(s, "regles"), L.rg)
  INSERER_LIGNES(s, "metriques", SPEC_TABLE(s, "metriques"), L.met)
  && variantes de SQL dynamique (historique)
  RQ(s, "insert into dyn_variantes select d.empreinte, d.objet_id, d.sql_reconstitue, now(), now(), 1, 'analyse' from sql_dynamique d " + ;
        "where list_contains(string_split(?, ',')::integer[], d.objet_id) and not exists (select 1 from dyn_variantes v " + ;
        "where v.empreinte = d.empreinte and v.objet_id = d.objet_id)", {liste})
  t.message = chaine(#meta) + " module(s), " + #L.refs + " références, " + #L.dyn + " SQL dynamique(s), " + #L.diag + " constat(s)"
retourner

&&
&& Campagne d'analyse : toute la chaîne dans la file
&&

procedure ANALYSER_TOUT(ev)
  locale srcs = RQ(nul, "select * from sources where actif order by id", nul)
  si #srcs = 0
    si ui.confirmer("Aucune source déclarée. Ajouter la source de démonstration (3 serveurs SQL Server simulés) ?", "question")
      AJOUTER_SOURCE_DEMO()
      srcs = RQ(nul, "select * from sources where actif order by id", nul)
    sinon
      NOUVELLE_SOURCE(nul)
      retourner
    finsi
  finsi
  PLANIFIER(srcs)
retourner

procedure PLANIFIER(srcs)
  && connexions (mot de passe demandé ici, dans le fil de l'interface), puis la file
  pour chaque src dans srcs
    si src.genre = "mssql" ou src.genre = "odbc"
      essayer
        ATTACHER(src, faux)
      capturer e
        ui.alerte("Source « " + src.nom + " » : connexion impossible." + car(10) + e, "attention")
        retourner
      finessayer
    finsi
    pour chaque tb dans {"ext_objets", "ext_colonnes", "ext_dependances", "ext_stats", "ext_index_manquants", "ext_jobs", "ext_profils"}
      RQ(nul, "delete from " + tb + " where source_id = ?", {src.id})
    suivant
  suivant
  && création des travaux (sans attente : la file ne démarre qu'une fois le graphe complet)
  locale lot = NOUVEAU_LOT()
  file.finlot = nul
  locale norms = {}
  pour chaque src dans srcs
    locale extr = {}
    locale norm_lib = "Normalisation · " + src.nom
    faire cas
    cas src.genre = "demo"
      pour chaque srv dans DEMO_SERVEURS()
        pour chaque g dans DEMO_GENRES()
          inserer(extr, AJOUTER_TRAVAIL("extraction", "Extraction " + g + " · " + srv.nom, srv.nom, ;
                                        {source_id = src.id, serveur = srv.nom, priorite = 2, genre_ext = g, base = ""}))
        suivant
      suivant
      inserer(extr, AJOUTER_TRAVAIL("extraction", "Appels capturés (démonstration)", "SRV-ERP", ;
                                    {source_id = src.id, serveur = "SRV-ERP", priorite = 4, genre_ext = "captures", base = ""}))
    cas src.genre = "dossier"
      inserer(extr, AJOUTER_TRAVAIL("extraction", "Lecture des scripts · " + src.nom, src.dossier, ;
                                    {source_id = src.id, serveur = "", priorite = 2, genre_ext = "scripts", base = ""}))
    autrement
      inserer(extr, AJOUTER_TRAVAIL("inventaire", "Inventaire du serveur · " + src.nom, src.serveur, ;
                                    {source_id = src.id, serveur = src.serveur, priorite = 1}))
    fincas
    locale n = AJOUTER_TRAVAIL("normalisation", norm_lib, src.nom, {source_id = src.id, priorite = 2, apres = extr})
    inserer(norms, n)
    si src.genre = "mssql" ou src.genre = "odbc"
      TRAVAIL(extr[1]).params.normalisation = n
    finsi
  suivant
  locale r = AJOUTER_TRAVAIL("resolution", "Résolution des dépendances", "graphe", {priorite = 2, apres = copier(norms)})
  pour chaque n dans norms
    TRAVAIL(n).params.resolution = r
  suivant
  locale d = AJOUTER_TRAVAIL("dictionnaire", "Dictionnaire de données", "colonnes", {priorite = 3, apres = copier(norms)})
  pour chaque n dans norms
    TRAVAIL(n).params.dictionnaire = d
  suivant
  locale tm = AJOUTER_TRAVAIL("types", "Catalogue des types métier", "colonnes", {priorite = 3, apres = {d}})
  locale du = AJOUTER_TRAVAIL("duplications", "Détection des duplications", "code", {priorite = 4, apres = {r}})
  locale pf = AJOUTER_TRAVAIL("performances", "Analyse des performances", "requêtes", {priorite = 3, apres = {r}})
  && duplications, performances, dictionnaire et types enrichissent le patrimoine sans le conditionner
  AJOUTER_TRAVAIL("patrimoine", "Analyse patrimoniale", "objets", {priorite = 4, apres = {r, du, pf, d, tm}, souples = {du, pf, d, tm}})
  VUE_FILE()
  STATUT("Campagne " + lot + " : " + #file.travaux + " travaux en file, " + reglages.agents + " agents.")
retourner
