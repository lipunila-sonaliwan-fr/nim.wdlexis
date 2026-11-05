&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atlas SQL : interception des appels (module 14) et profilage des colonnes.
&&
&& Capture sans modifier l'application cliente : une session Extended Events côté
&& serveur (rpc_completed, sql_batch_completed) écrit les appels dans un fichier .xel ;
&& Atlas lit ce fichier (sys.fn_xe_file_target_read_file) dans sa file d'attente et
&& range chaque appel dans l'entrepôt : texte, paramètres, durée, lignes, application,
&& utilisateur. Ensuite :
&&   * enregistrement : tout est conservé (table captures, export CSV) ;
&&   * modification des paramètres : la fiche JSON de l'appel est modifiable ;
&&   * simulation : l'appel est rejoué dans le débogueur symbolique avec ses paramètres,
&&     et le SQL dynamique est reconstitué avec les valeurs ;
&&   * rejeu : sur une source réelle, l'appel est réexécuté dans une transaction annulée
&&     (BEGIN TRAN … ROLLBACK), après confirmation ; durée et lignes sont comparées.

procedure CONSTRUIRE_INTERCEPTION(page)
  globale icp
  icp = {lignes = {}}
  locale haut = page:ajouter(ui.rangee())
  haut.marge = 2
  haut.ancrage = "haut"
  OUTIL(haut, "Script de capture (XE)…", @ICP_SCRIPT, "Session Extended Events à installer sur le serveur (aucune modification de l'application)")
  OUTIL(haut, "Importer les captures", @ICP_IMPORTER, "Lire le fichier .xel des serveurs (travail dans la file d'attente)")
  OUTIL(haut, "Simuler / déboguer", @ICP_SIMULER, "Ouvrir la procédure dans le débogueur avec les paramètres de l'appel")
  OUTIL(haut, "Rejouer", @ICP_REJOUER, "Réexécuter l'appel (transaction annulée) avec les paramètres affichés")
  OUTIL(haut, "Exporter (CSV)…", @ICP_EXPORTER, "Enregistrer les captures")
  icp.resume = haut:ajouter(ui.etiquette(""))
  icp.resume.poids = 1
  locale s1 = page:ajouter(ui.separateur{vertical = faux, position = 0.55})
  s1.ancrage = "centre"
  icp.g = GRILLE(s1, {{"quand", "Quand", 140}, {"serveur", "Serveur", 100}, {"objet", "Objet", 230}, {"params", "Paramètres", 330}, ;
                      {"duree", "Durée (ms)", 80, "nombre"}, {"lignes", "Lignes", 70, "nombre"}, {"app", "Application", 140}, ;
                      {"user", "Utilisateur", 120}})
  icp.g.surselection = @ICP_CHOIX
  locale bas_ = s1:ajouter(ui.separateur{vertical = vrai, position = 0.45})
  locale cg = bas_:ajouter(ui.colonne())
  locale lp = cg:ajouter(ui.etiquette("Paramètres de l'appel (modifiables, JSON)"))
  lp.couleur = "#9CA3AF"
  icp.params = cg:ajouter(ui.saisie{multiligne = vrai})
  icp.params.poids = 1
  icp.detail = bas_:ajouter(ui.markdown("Sélectionnez un appel capturé."))
retourner

procedure REMPLIR_CAPTURES
  icp.g:vider()
  icp.lignes = {}
  pour chaque c dans RQ(nul, "select * from captures order by quand desc limit 2000", nul)
    icp.g:ajouterligne(gauche(chaine(c.quand), 19), c.serveur, c.objet, COURT(c.parametres, 200), arrondi(c.duree_ms, 1), c.lignes, ;
                       c.application, c.utilisateur)
    inserer(icp.lignes, c)
  suivant
  icp.resume.libelle = #icp.lignes + " appel(s) capturé(s)"
retourner

fonction ICP_COURANTE()
  locale i = icp.g:selection()
  si i = nul ou i < 1 ou i > #icp.lignes
    retourner nul
  finsi
retourner icp.lignes[i]

procedure ICP_CHOIX(ev)
  locale c = ICP_COURANTE()
  si c = nul
    retourner
  finsi
  icp.params.valeur = c.parametres
  locale md = {"### " + c.objet, "", "```sql", c.texte, "```", ""}
  locale st = RQ(nul, "select sum(executions) as ex, sum(duree_ms) / greatest(sum(executions), 1) as moy from stats_requetes q " + ;
                      "join objets o on o.id = q.objet_id where lower(o.sch || '.' || o.nom) = lower(?)", {c.objet})
  si #st > 0 et st[1].ex <> nul
    inserer(md, "Durée de cet appel : **" + arrondi(c.duree_ms, 1) + " ms** · moyenne serveur : **" + arrondi(st[1].moy, 1) + " ms** sur " + NB(st[1].ex) + " exécutions")
    inserer(md, "")
  finsi
  && SQL dynamique de la procédure, reconstitué avec ces valeurs
  pour chaque d dans RQ(nul, "select d.sql_reconstitue, d.mode, d.ligne from sql_dynamique d join objets o on o.id = d.objet_id " + ;
                             "where lower(o.sch || '.' || o.nom) = lower(?)", {c.objet})
    inserer(md, "**SQL dynamique (l." + d.ligne + ", " + d.mode + ") avec ces paramètres :**")
    inserer(md, "```sql")
    inserer(md, SQL_AVEC_VALEURS(d.sql_reconstitue, c.parametres))
    inserer(md, "```")
  suivant
  icp.detail.valeur = MD(joindre(md, car(10)))
retourner

procedure ICP_SCRIPT(ev)
  locale l = {"-- Atlas SQL : capture des appels par Extended Events (aucune modification de l'application cliente)", ;
    "-- À exécuter sur chaque serveur à observer (droit ALTER ANY EVENT SESSION) ; arrêter avec STATE = STOP.", "", ;
    "IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'AtlasCapture')", "    DROP EVENT SESSION [AtlasCapture] ON SERVER;", "GO", ;
    "CREATE EVENT SESSION [AtlasCapture] ON SERVER", ;
    "ADD EVENT sqlserver.rpc_completed (", ;
    "    ACTION (sqlserver.client_app_name, sqlserver.username, sqlserver.database_name, sqlserver.client_hostname)", ;
    "    WHERE sqlserver.database_name <> N'master' AND sqlserver.database_name <> N'msdb' AND duration > 0),", ;
    "ADD EVENT sqlserver.sql_batch_completed (", ;
    "    ACTION (sqlserver.client_app_name, sqlserver.username, sqlserver.database_name, sqlserver.client_hostname)", ;
    "    WHERE sqlserver.database_name <> N'master' AND sqlserver.database_name <> N'msdb')", ;
    "ADD TARGET package0.event_file (SET filename = N'AtlasCapture.xel', max_file_size = (200), max_rollover_files = (5))", ;
    "WITH (MAX_MEMORY = 8 MB, EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS, MAX_DISPATCH_LATENCY = 5 SECONDS, STARTUP_STATE = OFF);", "GO", ;
    "ALTER EVENT SESSION [AtlasCapture] ON SERVER STATE = START;", "GO"}
  NOUVEAU_SCRIPT("capture_xe.sql", joindre(l, car(10)))
retourner

fonction TSQL_CAPTURES()
retourner "SELECT x.value('(event/@timestamp)[1]', 'datetime2') AS quand, " + ;
  "x.value('(event/action[@name=" + car(34) + "database_name" + car(34) + "]/value)[1]', 'nvarchar(256)') AS base, " + ;
  "ISNULL(x.value('(event/data[@name=" + car(34) + "object_name" + car(34) + "]/value)[1]', 'nvarchar(256)'), '') AS objet, " + ;
  "COALESCE(x.value('(event/data[@name=" + car(34) + "statement" + car(34) + "]/value)[1]', 'nvarchar(max)'), " + ;
  "x.value('(event/data[@name=" + car(34) + "batch_text" + car(34) + "]/value)[1]', 'nvarchar(max)')) AS texte, " + ;
  "x.value('(event/data[@name=" + car(34) + "duration" + car(34) + "]/value)[1]', 'bigint') / 1000.0 AS duree_ms, " + ;
  "x.value('(event/data[@name=" + car(34) + "row_count" + car(34) + "]/value)[1]', 'bigint') AS lignes, " + ;
  "x.value('(event/action[@name=" + car(34) + "client_app_name" + car(34) + "]/value)[1]', 'nvarchar(256)') AS application, " + ;
  "x.value('(event/action[@name=" + car(34) + "username" + car(34) + "]/value)[1]', 'nvarchar(256)') AS utilisateur " + ;
  "FROM (SELECT CAST(event_data AS XML) AS x FROM sys.fn_xe_file_target_read_file(N'AtlasCapture*.xel', NULL, NULL, NULL)) t"

procedure ICP_IMPORTER(ev)
  locale n = 0
  locale lot = NOUVEAU_LOT()
  file.finlot = nul
  pour chaque src dans RQ(nul, "select * from sources where actif and genre in ('mssql', 'odbc')", nul)
    essayer
      ATTACHER(src, faux)
      AJOUTER_TRAVAIL("captures", "Import des appels capturés · " + src.nom, src.serveur, {source_id = src.id, serveur = src.serveur, priorite = 2})
      n += 1
    capturer e
      STATUT("Source " + src.nom + " : " + e)
    finessayer
  suivant
  si n = 0
    && démonstration : appels simulés
    DEMO_CAPTURES(nul)
    REMPLIR_CAPTURES()
    STATUT("Démonstration : appels simulés chargés (sur un vrai serveur : script de capture, puis import).")
  sinon
    VUE_FILE(nul)
  finsi
retourner

procedure IMPORTER_CAPTURES(s, t)
  locale src = SOURCE(t.source_id)
  locale base_id = RV(s, "select coalesce(max(id), 0) from captures", nul)
  PROGRES(t, 0.1, "Lecture du fichier .xel…")
  RQ(s, "insert into captures select ? + row_number() over (), quand, ?, base, objet, texte, '{}', duree_ms, lignes, application, " + ;
        "utilisateur, 'xe' from " + FONCTION_SCAN(src, TSQL_CAPTURES()) + " c where not exists (select 1 from captures k " + ;
        "where k.quand = c.quand and k.texte = c.texte)", {base_id, t.serveur})
  && paramètres : analyse de « EXEC proc @a = 1, @b = N'x' »
  PROGRES(t, 0.6, "Paramètres des appels…")
  locale l = RQ(s, "select id, texte from captures where origine = 'xe' and parametres = '{}' limit 5000", nul)
  pour chaque c dans l
    locale p = PARAMETRES_APPEL(s, c.texte)
    RQ(s, "update captures set parametres = ?, objet = coalesce(nullif(objet, ''), ?) where id = ?", {json(p.valeurs), p.objet, c.id})
  suivant
  t.message = chaine(#l) + " appel(s) importé(s)"
retourner

fonction PARAMETRES_APPEL(s, texte_)
  && « EXEC [dbo].[P] @A = 1, @B = N'x' » -> {objet = "dbo.P", valeurs = {A = 1, B = "x"}}
  locale toks = JETONS_TEXTE(s, texte_)
  locale r = {objet = "", valeurs = {}}
  locale i = 1
  si #toks > 0 et (toks[1].u = "EXEC" ou toks[1].u = "EXECUTE")
    i = 2
    locale nm = LIRE_NOM(toks, i)
    si nm <> nul
      r.objet = nm.texte
      i = nm.fin + 1
    finsi
  finsi
  tantque i <= #toks
    si toks[i].k = "V" et i + 2 <= #toks et toks[i + 1].o = "="
      locale v = toks[i + 2]
      locale val = v.o
      si v.k = "S"
        val = VALEUR_CHAINE(v.o)
      sinonsi v.k = "N"
        val = nombre(v.o)
      sinonsi v.u = "NULL"
        val = nul
      finsi
      r.valeurs[majuscule(souschaine(toks[i].o, 2))] = val
      i += 3
    sinon
      i += 1
    finsi
  fintantque
retourner r

procedure ICP_SIMULER(ev)
  locale c = ICP_COURANTE()
  si c = nul
    STATUT("Sélectionnez un appel capturé.")
    retourner
  finsi
  locale r = RQ(nul, "select id from objets where lower(sch || '.' || nom) = lower(?) and definition is not null limit 1", {c.objet})
  si #r = 0
    STATUT("Code de " + c.objet + " introuvable dans l'entrepôt.")
    retourner
  finsi
  && les paramètres (éventuellement modifiés) deviennent ceux du débogueur
  edi.params_force = icp.params.valeur
  OUVRIR_CODE(r[1].id)
  DBG_DEMARRER(nul)
  STATUT("Simulation de " + c.objet + " avec les paramètres de l'appel : pas à pas (F10), détaillé (F11), continuer (F5).")
retourner

procedure ICP_REJOUER(ev)
  locale c = ICP_COURANTE()
  si c = nul
    STATUT("Sélectionnez un appel capturé.")
    retourner
  finsi
  locale src = nul
  pour chaque x dans RQ(nul, "select * from sources where actif and genre in ('mssql', 'odbc')", nul)
    si src = nul
      src = x
    finsi
  suivant
  locale texte_ = APPEL_AVEC_PARAMETRES(c, icp.params.valeur)
  si src = nul
    && démonstration : rejeu simulé d'après les statistiques
    locale st = RQ(nul, "select sum(duree_ms) / greatest(sum(executions), 1) as moy from stats_requetes q join objets o on o.id = q.objet_id " + ;
                        "where lower(o.sch || '.' || o.nom) = lower(?)", {c.objet})
    locale moy = sisinon(#st = 0 ou st[1].moy = nul, c.duree_ms, st[1].moy)
    icp.detail.valeur = "### Rejeu simulé (source de démonstration)" + car(10) + car(10) + "```sql" + car(10) + texte_ + car(10) + "```" + car(10) + car(10) + ;
                        "Durée estimée : **" + arrondi(moy, 1) + " ms** (capturée : " + arrondi(c.duree_ms, 1) + " ms). " + ;
                        "Sur un vrai serveur, l'appel est réexécuté dans une transaction annulée."
    retourner
  finsi
  si non ui.confirmer("Rejouer cet appel sur " + src.nom + " ?" + car(10) + car(10) + texte_ + car(10) + car(10) + ;
                      "Il sera exécuté dans une transaction annulée (ROLLBACK). Attention : les effets hors transaction " + ;
                      "(courriels, appels distants, séquences) ne sont pas annulés.", "attention")
    retourner
  finsi
  AJOUTER_TRAVAIL("rejeu", "Rejeu · " + c.objet, src.serveur, {source_id = src.id, serveur = src.serveur, priorite = 1, ;
                  texte = texte_, capture = c.id})
  VUE_FILE(nul)
retourner

fonction APPEL_AVEC_PARAMETRES(c, params_json)
  locale p = {}
  essayer
    p = dejson(params_json)
  capturer e
    retourner c.texte
  finessayer
  locale l = {}
  pour chaque k, v dans p
    inserer(l, "@" + k + " = " + sisinon(v = nul, "NULL", sisinon(type(v) = "nombre", chaine(v), "N'" + remplacertexte(chaine(v), "'", "''") + "'")))
  suivant
retourner "EXEC " + c.objet + sisinon(#l > 0, " " + joindre(l, ", "), "")

procedure REJOUER(s, t)
  locale src = SOURCE(t.source_id)
  locale h = systeme.horloge()
  locale tsql = "SET NOCOUNT ON; BEGIN TRANSACTION; " + t.params.texte + "; IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;"
  locale n = RV(s, "select " + sisinon(src.genre = "odbc", "count(*) from " + FONCTION_SCAN(src, tsql), ;
                                       "mssql_exec(" + SQLTEXTE(ALIAS_SOURCE(src)) + ", " + SQLTEXTE(tsql) + ")"), nul)
  locale d = (systeme.horloge() - h) * 1000
  RQ(s, "insert into captures values ((select coalesce(max(id), 0) + 1 from captures), now(), ?, '', ?, ?, '{}', ?, ?, 'Atlas (rejeu)', 'atlas', 'rejeu')", ;
     {t.serveur, t.cible, t.params.texte, d, n})
  t.message = "Rejoué en " + arrondi(d, 1) + " ms (annulé)"
retourner

procedure ICP_EXPORTER(ev)
  locale p = ui.enregistrerfichier{nom = "captures.csv", filtre = "CSV|*.csv"}
  si p <> nul
    RQ(nul, "copy (select * from captures order by quand) to '" + remplacertexte(p, "'", "''") + "' (header, delimiter ';')", nul)
    STATUT("Captures exportées : " + p)
  finsi
retourner

&&
&& Profilage des colonnes (option de la source) : cardinalités et valeurs nulles
&&

procedure PROFILER_TABLE(s, t)
  locale src = SOURCE(t.source_id)
  locale cols = RQ(s, "select nom, type_sql from colonnes where objet_id = ? and type_sql not ilike '%max%' and type_sql not in " + ;
                      "('image', 'text', 'ntext', 'xml', 'geography', 'geometry', 'varbinary', 'binary') order by ordre limit 60", {t.params.objet_id})
  si #cols = 0
    retourner
  finsi
  locale o = OBJET_S(s, t.params.objet_id)
  locale sel = {}
  pour i = 1 a #cols
    locale c = "[" + remplacertexte(cols[i].nom, "]", "]]") + "]"
    inserer(sel, "COUNT_BIG(DISTINCT " + c + ") AS d" + i + ", SUM(CASE WHEN " + c + " IS NULL THEN 1 ELSE 0 END) AS n" + i)
  suivant
  locale tsql = "SELECT " + joindre(sel, ", ") + " FROM [" + o.base + "].[" + o.sch + "].[" + o.nom + "]" + ;
                sisinon(o.lignes <> nul et o.lignes > 1000000, " TABLESAMPLE (1000000 ROWS)", "") + " WITH (NOLOCK)"
  locale r = RQ(s, "select * from " + FONCTION_SCAN(src, tsql), nul)
  si #r > 0
    pour i = 1 a #cols
      RQ(s, "update colonnes set distincts = ?, nuls = ? where objet_id = ? and nom = ?", ;
         {r[1]["D" + i], r[1]["N" + i], t.params.objet_id, cols[i].nom})
    suivant
  finsi
  t.message = chaine(#cols) + " colonne(s) profilée(s)"
retourner

fonction OBJET_S(s, id)
retourner RQ(s, "select * from objets where id = ?", {id})[1]
