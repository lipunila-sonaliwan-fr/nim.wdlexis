&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atlas SQL : système d'information de démonstration.
&&
&& Trois serveurs SQL Server simulés (ERP, comptabilité, entrepôt de données) : bases,
&& schémas, tables, vues, procédures (T-SQL réaliste : contrôles, curseurs, SQL
&& dynamique, OPENQUERY, serveurs liés, synonymes, MERGE…), fonctions, déclencheurs,
&& types, séquences, CLR, index, statistiques, partitions, jobs SQL Agent, statistiques
&& d'exécution avec plans, index manquants, profils de colonnes et appels capturés.
&& Les extractions de la source « démonstration » produisent exactement les mêmes
&& tables ext_* que celles d'un vrai serveur (sources.prg) : toute la chaîne d'analyse
&& est donc la même.

fonction DEMO_SERVEURS()
retourner {{nom = "SRV-ERP", version = "SQL Server 2019 (15.0.4375)", bases = {"ERP", "REF"}}, ;
           {nom = "SRV-COMPTA", version = "SQL Server 2017 (14.0.3465)", bases = {"COMPTA"}}, ;
           {nom = "SRV-DWH", version = "SQL Server 2022 (16.0.4135)", bases = {"DWH"}}}

fonction DEMO_TABLES()
  && serveur|base|schéma|table|lignes|date de création|colonnes (nom:type[:pk][:id][:nn][:fk=base.sch.table.col])
retourner { ;
"SRV-ERP|ERP|vente|CLIENT|48200|2014-03-11|CLIENT_ID:int:pk:id,CODE_CLIENT:dbo.T_CODE_CLIENT:nn,NOM:nvarchar(80):nn,PRENOM:nvarchar(60),EMAIL:varchar(120),TELEPHONE:varchar(20),DATE_NAISSANCE:date,IBAN:varchar(34),ADRESSE:nvarchar(200),CODE_POSTAL:varchar(10),VILLE:nvarchar(80),PAYS_CODE:char(2):fk=REF.dbo.PAYS.CODE,CATEGORIE:char(1),DATE_CREATION:datetime2,ACTIF:bit", ;
"SRV-ERP|ERP|vente|CONTACT|12000|2015-06-02|CONTACT_ID:int:pk:id,CODCLI:varchar(10),NOM:nvarchar(80),EMAIL:varchar(120),TEL:varchar(20),FONCTION:nvarchar(60)", ;
"SRV-ERP|ERP|vente|COMMANDE|820000|2014-03-11|COMMANDE_ID:int:pk:id,NUM_COMMANDE:varchar(12):nn,CLIENT_CODE:varchar(10):nn:fk=ERP.vente.CLIENT.CODE_CLIENT,DATE_COMMANDE:datetime2:nn,STATUT:char(1),MONTANT_HT:dbo.T_MONTANT,REMISE:decimal(5,2),COMMERCIAL_ID:int:fk=ERP.rh.EMPLOYE.EMPLOYE_ID", ;
"SRV-ERP|ERP|vente|LIGNE_COMMANDE|3100000|2014-03-11|LIGNE_ID:bigint:pk:id,COMMANDE_ID:int:nn:fk=ERP.vente.COMMANDE.COMMANDE_ID,ARTICLE_CODE:varchar(15):fk=ERP.stock.ARTICLE.CODE_ARTICLE,QTE:decimal(10,3),PRIX:decimal(15,4),REMISE:decimal(5,2)", ;
"SRV-ERP|ERP|vente|FACTURE|760000|2014-03-11|FACTURE_ID:int:pk:id,NUM_FACTURE:varchar(12):nn,CODE_CLIENT:varchar(10):nn,COMMANDE_ID:int:fk=ERP.vente.COMMANDE.COMMANDE_ID,DATE_FACTURE:date:nn,DATE_ECHEANCE:date,MONTANT_HT:dbo.T_MONTANT,MONTANT_TVA:dbo.T_MONTANT,MONTANT_TTC:dbo.T_MONTANT,STATUT:char(1)", ;
"SRV-ERP|ERP|vente|FACTURE_HIST|2900000|2016-01-20|FACTURE_ID:int:pk,NUM_FACTURE:varchar(12),CODE_CLIENT:varchar(10),DATE_FACTURE:date,MONTANT_HT:decimal(15,2),MONTANT_TTC:decimal(15,2),STATUT:char(1),DATE_ARCHIVAGE:datetime2", ;
"SRV-ERP|ERP|vente|REGLEMENT|700000|2014-03-11|REGLEMENT_ID:int:pk:id,FACTURE_ID:int:fk=ERP.vente.FACTURE.FACTURE_ID,DATE_REGLEMENT:date,MONTANT:decimal(15,2),MODE_REGLEMENT:char(3),IBAN_EMETTEUR:varchar(34)", ;
"SRV-ERP|ERP|vente|REMISE_CLIENT|3000|2018-09-14|CLI_CODE:varchar(10):pk,TAUX:decimal(5,2),DATE_DEBUT:date,DATE_FIN:date", ;
"SRV-ERP|ERP|vente|STG_CLIENT|0|2019-02-01|CODE_CLIENT:varchar(10),NOM:nvarchar(80),PRENOM:nvarchar(60),EMAIL:varchar(120),VILLE:nvarchar(80),PAYS_CODE:char(2)", ;
"SRV-ERP|ERP|stock|ARTICLE|15400|2014-03-11|ARTICLE_ID:int:pk:id,CODE_ARTICLE:varchar(15):nn,LIBELLE:nvarchar(120),FAMILLE:varchar(10),PRIX_UNITAIRE:decimal(15,4),TVA_CODE:char(1):fk=REF.dbo.TVA.CODE,POIDS:decimal(10,3),ACTIF:bit", ;
"SRV-ERP|ERP|stock|ENTREPOT|12|2014-03-11|ENTREPOT_ID:int:pk:id,CODE_ENTREPOT:varchar(5),LIBELLE:nvarchar(60),VILLE:nvarchar(80)", ;
"SRV-ERP|ERP|stock|MOUVEMENT_STOCK|5200000|2014-03-11|MOUVEMENT_ID:bigint:pk:id,CODE_ARTICLE:varchar(15),ENTREPOT_ID:int:fk=ERP.stock.ENTREPOT.ENTREPOT_ID,DATE_MOUVEMENT:datetime2,QTE:decimal(10,3),SENS:char(1),ORIGINE:varchar(20)", ;
"SRV-ERP|ERP|stock|STOCK|46000|2014-03-11|CODE_ARTICLE:varchar(15):pk,ENTREPOT_ID:int:pk,QTE_DISPO:decimal(12,3),QTE_RESERVEE:decimal(12,3)", ;
"SRV-ERP|ERP|rh|EMPLOYE|850|2014-05-02|EMPLOYE_ID:int:pk:id,MATRICULE:varchar(8):nn,NOM:nvarchar(80),PRENOM:nvarchar(60),NIR:varchar(15),DATE_NAISSANCE:date,EMAIL:varchar(120),TELEPHONE:varchar(20),SALAIRE_BRUT:decimal(12,2),DATE_EMBAUCHE:date,SERVICE:varchar(20)", ;
"SRV-ERP|ERP|rh|CONGE|22000|2014-05-02|CONGE_ID:int:pk:id,MATRICULE:varchar(8),DATE_DEBUT:date,DATE_FIN:date,TYPE_CONGE:varchar(10),MOTIF:nvarchar(200)", ;
"SRV-ERP|ERP|dbo|LOG_TRAITEMENT|9800000|2014-03-11|LOG_ID:bigint:pk:id,DATE_LOG:datetime2,PROCEDURE_NOM:sysname,MESSAGE:nvarchar(4000),NIVEAU:varchar(10)", ;
"SRV-ERP|ERP|dbo|PARAMETRE|140|2014-03-11|CLE:varchar(50):pk,VALEUR:nvarchar(400),DESCRIPTION:nvarchar(200)", ;
"SRV-ERP|ERP|dbo|TMP_IMPORT_CLIENT|0|2016-11-08|CODCLI:varchar(10),NOM:nvarchar(80),ADRESSE:nvarchar(200),TEL:varchar(20)", ;
"SRV-ERP|ERP|dbo|CLIENT_OLD|31000|2012-01-15|CODE_CLI:varchar(10),RAISON:nvarchar(80),MAIL:varchar(120),TELEPHONE:varchar(20)", ;
"SRV-ERP|REF|dbo|PAYS|249|2013-02-01|CODE:char(2):pk,LIBELLE:nvarchar(80),ZONE_ECO:varchar(10)", ;
"SRV-ERP|REF|dbo|DEVISE|160|2013-02-01|CODE:char(3):pk,LIBELLE:nvarchar(60),TAUX:decimal(18,6)", ;
"SRV-ERP|REF|dbo|TVA|6|2013-02-01|CODE:char(1):pk,TAUX:decimal(5,4),LIBELLE:nvarchar(40)", ;
"SRV-ERP|REF|dbo|CODE_POSTAL|39000|2013-02-01|CODE_POSTAL:varchar(10),VILLE:nvarchar(80),INSEE:varchar(5)", ;
"SRV-COMPTA|COMPTA|dbo|ECRITURE|12500000|2011-07-01|ECRITURE_ID:bigint:pk:id,JOURNAL_CODE:char(3):fk=COMPTA.dbo.JOURNAL.CODE,DATE_ECRITURE:date,COMPTE:varchar(10):fk=COMPTA.dbo.COMPTE.NUMERO,LIBELLE:nvarchar(120),DEBIT:decimal(15,2),CREDIT:decimal(15,2),PIECE:varchar(20),CODE_TIERS:varchar(10)", ;
"SRV-COMPTA|COMPTA|dbo|JOURNAL|12|2011-07-01|CODE:char(3):pk,LIBELLE:nvarchar(60)", ;
"SRV-COMPTA|COMPTA|dbo|COMPTE|1800|2011-07-01|NUMERO:varchar(10):pk,LIBELLE:nvarchar(120),CLASSE:char(1)", ;
"SRV-COMPTA|COMPTA|dbo|EXERCICE|9|2011-07-01|EXERCICE_ID:int:pk:id,DATE_DEBUT:date,DATE_FIN:date,CLOS:bit", ;
"SRV-COMPTA|COMPTA|dbo|TIERS|52000|2011-07-01|CODE_TIERS:varchar(10):pk,RAISON_SOCIALE:nvarchar(120),SIRET:varchar(14),IBAN:varchar(34),EMAIL:varchar(120)", ;
"SRV-DWH|DWH|stg|STG_FACTURE|0|2020-04-01|NUM_FACTURE:varchar(12),CODE_CLIENT:varchar(10),DATE_FACTURE:date,MONTANT_HT:decimal(15,2),MONTANT_TTC:decimal(15,2),DATE_CHARGEMENT:datetime2", ;
"SRV-DWH|DWH|dw|DIM_CLIENT|48000|2020-04-01|CLIENT_SK:int:pk:id,CODE_CLIENT:varchar(10),NOM:nvarchar(80),VILLE:nvarchar(80),PAYS:char(2),SEGMENT:varchar(10),DATE_DEBUT:date,DATE_FIN:date,COURANT:bit", ;
"SRV-DWH|DWH|dw|DIM_ARTICLE|15400|2020-04-01|ARTICLE_SK:int:pk:id,CODE_ARTICLE:varchar(15),LIBELLE:nvarchar(120),FAMILLE:varchar(10)", ;
"SRV-DWH|DWH|dw|DIM_TEMPS|7300|2020-04-01|DATE_SK:int:pk,DATE_JOUR:date,ANNEE:smallint,MOIS:tinyint,JOUR_SEMAINE:tinyint", ;
"SRV-DWH|DWH|dw|FAIT_VENTE|41000000|2020-04-01|DATE_SK:int:fk=DWH.dw.DIM_TEMPS.DATE_SK,CLIENT_SK:int:fk=DWH.dw.DIM_CLIENT.CLIENT_SK,ARTICLE_SK:int:fk=DWH.dw.DIM_ARTICLE.ARTICLE_SK,QTE:decimal(10,3),MONTANT_HT:decimal(15,2),MONTANT_TTC:decimal(15,2),MARGE:decimal(15,2)"}

&&
&& Code des modules (procédures, fonctions, vues, déclencheurs)
&&

fonction DEMO_MODULES()
  locale m = {}
  && --- ERP : facturation, ventes
  DM(m, "SRV-ERP", "ERP", "vente", "SP_EMISSION_FACTURE", "PROCEDURE", "2015-02-10", "2025-11-03", [[CREATE PROCEDURE vente.SP_EMISSION_FACTURE
  @DateFacture DATE = NULL
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;
  DECLARE @nb INT = 0, @Commande INT, @NumFacture VARCHAR(12), @Total DECIMAL(15,2);
  -- Contrôles
  IF @DateFacture IS NULL
    SET @DateFacture = CAST(GETDATE() AS DATE);
  IF EXISTS (SELECT 1 FROM vente.FACTURE WHERE DATE_FACTURE = @DateFacture AND STATUT = 'E')
  BEGIN
    RAISERROR('Facturation déjà émise pour cette date', 16, 1);
    RETURN 1;
  END
  -- Chargement des commandes validées
  SELECT C.COMMANDE_ID, C.CLIENT_CODE, SUM(L.QTE * L.PRIX * (1 - ISNULL(L.REMISE, 0) / 100)) AS HT
  INTO #CMD
  FROM vente.COMMANDE C WITH (NOLOCK)
  JOIN vente.LIGNE_COMMANDE L ON L.COMMANDE_ID = C.COMMANDE_ID
  WHERE C.STATUT = 'V' AND YEAR(C.DATE_COMMANDE) = YEAR(@DateFacture)
  GROUP BY C.COMMANDE_ID, C.CLIENT_CODE;
  -- Calcul de la TVA et des remises client
  UPDATE T SET HT = T.HT * (1 - ISNULL(R.TAUX, 0) / 100)
  FROM #CMD T LEFT JOIN vente.REMISE_CLIENT R ON R.CLI_CODE = T.CLIENT_CODE AND @DateFacture BETWEEN R.DATE_DEBUT AND R.DATE_FIN;
  -- Facturation, commande par commande
  DECLARE cur_cmd CURSOR FOR SELECT COMMANDE_ID FROM #CMD;
  OPEN cur_cmd;
  FETCH NEXT FROM cur_cmd INTO @Commande;
  WHILE @@FETCH_STATUS = 0
  BEGIN
    SET @NumFacture = 'F' + RIGHT('0000000000' + CAST(NEXT VALUE FOR vente.SEQ_NUM_FACTURE AS VARCHAR(10)), 10);
    INSERT INTO vente.FACTURE (NUM_FACTURE, CODE_CLIENT, COMMANDE_ID, DATE_FACTURE, DATE_ECHEANCE, MONTANT_HT, MONTANT_TVA, MONTANT_TTC, STATUT)
    SELECT @NumFacture, T.CLIENT_CODE, T.COMMANDE_ID, @DateFacture, DATEADD(DAY, 30, @DateFacture), T.HT, T.HT * V.TAUX, dbo.FN_TTC(T.HT, V.TAUX), 'E'
    FROM #CMD T CROSS JOIN dbo.SYN_TVA V
    WHERE T.COMMANDE_ID = @Commande AND V.CODE = 'N';
    UPDATE vente.COMMANDE SET STATUT = 'F' WHERE COMMANDE_ID = @Commande;
    SET @nb = @nb + 1;
    FETCH NEXT FROM cur_cmd INTO @Commande;
  END
  CLOSE cur_cmd;
  DEALLOCATE cur_cmd;
  -- Comptabilisation (base COMPTA par le synonyme)
  BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.SYN_ECRITURE (JOURNAL_CODE, DATE_ECRITURE, COMPTE, LIBELLE, DEBIT, CREDIT, PIECE, CODE_TIERS)
    SELECT 'VTE', F.DATE_FACTURE, '411000', 'Facture ' + F.NUM_FACTURE, F.MONTANT_TTC, 0, F.NUM_FACTURE, F.CODE_CLIENT
    FROM vente.FACTURE F WHERE F.DATE_FACTURE = @DateFacture AND F.STATUT = 'E';
    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    EXEC dbo.SP_LOG @Message = 'Erreur de comptabilisation', @Niveau = 'ERREUR';
    THROW;
  END CATCH
  -- Archivage des factures soldées de plus de 3 ans
  INSERT INTO vente.FACTURE_HIST (FACTURE_ID, NUM_FACTURE, CODE_CLIENT, DATE_FACTURE, MONTANT_HT, MONTANT_TTC, STATUT, DATE_ARCHIVAGE)
  SELECT FACTURE_ID, NUM_FACTURE, CODE_CLIENT, DATE_FACTURE, MONTANT_HT, MONTANT_TTC, STATUT, SYSDATETIME()
  FROM vente.FACTURE WHERE STATUT = 'S' AND DATE_FACTURE < DATEADD(YEAR, -3, @DateFacture);
  DELETE FROM vente.FACTURE WHERE STATUT = 'S' AND DATE_FACTURE < DATEADD(YEAR, -3, @DateFacture);
  EXEC dbo.SP_LOG @Message = 'Facturation terminée', @Niveau = 'INFO';
  -- Restitution
  SELECT @nb AS NB_FACTURES, SUM(MONTANT_TTC) AS TOTAL_TTC FROM vente.FACTURE WHERE DATE_FACTURE = @DateFacture;
END]])
  DM(m, "SRV-ERP", "ERP", "vente", "SP_CALCUL_REMISE", "PROCEDURE", "2016-04-18", "2023-05-02", [[CREATE PROCEDURE vente.SP_CALCUL_REMISE
  @CodeClient VARCHAR(10)
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @Taux DECIMAL(5,2);
  SELECT @Taux = TAUX FROM vente.REMISE_CLIENT WHERE CLI_CODE = @CodeClient AND GETDATE() BETWEEN DATE_DEBUT AND DATE_FIN;
  IF @Taux IS NULL
    RETURN 0;
  UPDATE vente.COMMANDE SET REMISE = @Taux WHERE CLIENT_CODE = @CodeClient AND STATUT = 'S';
  EXEC dbo.SP_LOG @Message = 'Remise appliquée', @Niveau = 'INFO';
END]])
  DM(m, "SRV-ERP", "ERP", "vente", "SP_MAJ_STATUT_COMMANDE", "PROCEDURE", "2014-04-01", "2022-10-11", [[CREATE PROCEDURE vente.SP_MAJ_STATUT_COMMANDE
  @Id INT,
  @Statut CHAR(1)
AS
BEGIN
  SET NOCOUNT ON;
  IF @Statut NOT IN ('S', 'V', 'F', 'A')
  BEGIN
    RAISERROR('Statut inconnu', 16, 1);
    RETURN;
  END
  UPDATE vente.COMMANDE SET STATUT = @Statut WHERE COMMANDE_ID = @Id;
  IF @@ROWCOUNT = 0
    THROW 50002, 'Commande introuvable', 1;
  EXEC dbo.SP_LOG @Message = 'Statut modifié', @Niveau = 'INFO';
END]])
  DM(m, "SRV-ERP", "ERP", "vente", "SP_PURGE_COMMANDES", "PROCEDURE", "2016-01-20", "2021-03-30", [[CREATE PROCEDURE vente.SP_PURGE_COMMANDES
  @Mois INT = 36
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @Limite DATE = DATEADD(MONTH, -@Mois, GETDATE());
  DELETE L FROM vente.LIGNE_COMMANDE L JOIN vente.COMMANDE C ON C.COMMANDE_ID = L.COMMANDE_ID WHERE C.DATE_COMMANDE < @Limite AND C.STATUT IN ('F', 'A');
  DELETE FROM vente.COMMANDE WHERE DATE_COMMANDE < @Limite AND STATUT IN ('F', 'A');
  DELETE FROM dbo.LOG_TRAITEMENT WHERE CONVERT(DATE, DATE_LOG) < @Limite;
  EXEC dbo.SP_LOG @Message = 'Purge des commandes', @Niveau = 'INFO';
END]])
  DM(m, "SRV-ERP", "ERP", "vente", "SP_IMPORT_CLIENTS", "PROCEDURE", "2019-02-01", "2024-09-17", [[CREATE PROCEDURE vente.SP_IMPORT_CLIENTS
AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS (SELECT 1 FROM vente.STG_CLIENT)
    RETURN 0;
  MERGE vente.CLIENT AS C
  USING vente.STG_CLIENT AS S ON C.CODE_CLIENT = S.CODE_CLIENT
  WHEN MATCHED THEN UPDATE SET C.NOM = S.NOM, C.PRENOM = S.PRENOM, C.EMAIL = S.EMAIL, C.VILLE = S.VILLE, C.PAYS_CODE = S.PAYS_CODE
  WHEN NOT MATCHED THEN INSERT (CODE_CLIENT, NOM, PRENOM, EMAIL, VILLE, PAYS_CODE, DATE_CREATION, ACTIF)
    VALUES (S.CODE_CLIENT, S.NOM, S.PRENOM, S.EMAIL, S.VILLE, S.PAYS_CODE, SYSDATETIME(), 1);
  TRUNCATE TABLE vente.STG_CLIENT;
  EXEC dbo.SP_LOG @Message = 'Import des clients', @Niveau = 'INFO';
END]])
  DM(m, "SRV-ERP", "ERP", "vente", "SP_RECHERCHE_CLIENT", "PROCEDURE", "2017-08-22", "2025-01-09", [[CREATE PROCEDURE vente.SP_RECHERCHE_CLIENT
  @Nom NVARCHAR(80) = NULL,
  @Ville NVARCHAR(80) = NULL,
  @Tri SYSNAME = N'NOM'
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @sql NVARCHAR(MAX) = N'SELECT CLIENT_ID, CODE_CLIENT, NOM, PRENOM, VILLE FROM vente.CLIENT WHERE ACTIF = 1';
  IF @Nom IS NOT NULL
    SET @sql = @sql + N' AND NOM LIKE @pNom';
  IF @Ville IS NOT NULL
    SET @sql = @sql + N' AND VILLE = @pVille';
  SET @sql = @sql + N' ORDER BY ' + QUOTENAME(@Tri);
  EXEC sp_executesql @sql, N'@pNom NVARCHAR(80), @pVille NVARCHAR(80)', @pNom = @Nom, @pVille = @Ville;
END]])
  DM(m, "SRV-ERP", "ERP", "vente", "SP_RAPPORT_DYNAMIQUE", "PROCEDURE", "2018-03-05", "2020-12-01", [[CREATE PROCEDURE vente.SP_RAPPORT_DYNAMIQUE
  @Table SYSNAME,
  @Annee INT
AS
BEGIN
  DECLARE @req VARCHAR(2000);
  SET @req = 'SELECT CODE_CLIENT, SUM(MONTANT_TTC) AS TOTAL FROM vente.' + @Table;
  SET @req = @req + ' WHERE YEAR(DATE_FACTURE) = ' + CAST(@Annee AS VARCHAR(4)) + ' GROUP BY CODE_CLIENT';
  EXEC (@req);
END]])
  DM(m, "SRV-ERP", "ERP", "vente", "SP_EXPORT_DWH", "PROCEDURE", "2020-04-01", "2025-06-12", [[CREATE PROCEDURE vente.SP_EXPORT_DWH
  @Depuis DATE = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @Depuis IS NULL
    SELECT @Depuis = CAST(VALEUR AS DATE) FROM dbo.PARAMETRE WHERE CLE = 'DERNIER_EXPORT_DWH';
  INSERT INTO LNK_DWH.DWH.stg.STG_FACTURE (NUM_FACTURE, CODE_CLIENT, DATE_FACTURE, MONTANT_HT, MONTANT_TTC, DATE_CHARGEMENT)
  SELECT F.NUM_FACTURE, F.CODE_CLIENT, F.DATE_FACTURE, F.MONTANT_HT, F.MONTANT_TTC, SYSDATETIME()
  FROM vente.FACTURE F
  WHERE F.DATE_FACTURE >= @Depuis;
  EXEC LNK_DWH.DWH.dw.SP_CHARGER_FAIT_VENTE;
  UPDATE dbo.PARAMETRE SET VALEUR = CONVERT(VARCHAR(10), GETDATE(), 120) WHERE CLE = 'DERNIER_EXPORT_DWH';
END]])
  DM(m, "SRV-ERP", "ERP", "vente", "SP_SYNCHRO_TIERS", "PROCEDURE", "2018-10-10", "2024-02-28", [[CREATE PROCEDURE vente.SP_SYNCHRO_TIERS
AS
BEGIN
  SET NOCOUNT ON;
  CREATE TABLE #SOLDES (CODE_TIERS VARCHAR(10), SOLDE DECIMAL(15,2));
  INSERT INTO #SOLDES (CODE_TIERS, SOLDE)
  SELECT CODE_TIERS, SOLDE FROM OPENQUERY(LNK_COMPTA, 'SELECT CODE_TIERS, SUM(DEBIT - CREDIT) AS SOLDE FROM COMPTA.dbo.ECRITURE GROUP BY CODE_TIERS');
  UPDATE C SET C.CATEGORIE = CASE WHEN S.SOLDE > 10000 THEN 'R' ELSE C.CATEGORIE END
  FROM vente.CLIENT C JOIN #SOLDES S ON S.CODE_TIERS = C.CODE_CLIENT;
  SELECT C.CODE_CLIENT, C.NOM, S.SOLDE FROM vente.CLIENT C JOIN #SOLDES S ON S.CODE_TIERS = C.CODE_CLIENT WHERE S.SOLDE > 0;
END]])
  DM(m, "SRV-ERP", "ERP", "vente", "SP_CA_MENSUEL", "PROCEDURE", "2015-09-01", "2019-06-03", [[CREATE PROCEDURE vente.SP_CA_MENSUEL
  @Annee INT
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @d1 DATE = DATEFROMPARTS(@Annee, 1, 1), @d2 DATE = DATEFROMPARTS(@Annee, 12, 31);
  SELECT MONTH(F.DATE_FACTURE) AS MOIS, C.CATEGORIE, SUM(F.MONTANT_HT) AS CA_HT, SUM(F.MONTANT_TTC) AS CA_TTC,
         CASE WHEN SUM(F.MONTANT_TTC) > 10000 THEN 'GRAND' WHEN SUM(F.MONTANT_TTC) > 1000 THEN 'MOYEN' ELSE 'PETIT' END AS SEGMENT
  FROM vente.FACTURE F
  JOIN vente.CLIENT C ON C.CODE_CLIENT = F.CODE_CLIENT
  WHERE F.DATE_FACTURE BETWEEN @d1 AND @d2 AND F.STATUT <> 'A'
  GROUP BY MONTH(F.DATE_FACTURE), C.CATEGORIE
  ORDER BY MOIS;
END]])
  DM(m, "SRV-ERP", "ERP", "vente", "SP_CA_CLIENT", "PROCEDURE", "2016-02-12", "2019-06-03", [[CREATE PROCEDURE vente.SP_CA_CLIENT
  @CodeClient VARCHAR(10),
  @Annee INT
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @d1 DATE = DATEFROMPARTS(@Annee, 1, 1), @d2 DATE = DATEFROMPARTS(@Annee, 12, 31);
  SELECT MONTH(F.DATE_FACTURE) AS MOIS, C.CATEGORIE, SUM(F.MONTANT_HT) AS CA_HT, SUM(F.MONTANT_TTC) AS CA_TTC,
         CASE WHEN SUM(F.MONTANT_TTC) > 10000 THEN 'GRAND' WHEN SUM(F.MONTANT_TTC) > 1000 THEN 'MOYEN' ELSE 'PETIT' END AS SEGMENT
  FROM vente.FACTURE F
  JOIN vente.CLIENT C ON C.CODE_CLIENT = F.CODE_CLIENT
  WHERE F.DATE_FACTURE BETWEEN @d1 AND @d2 AND F.STATUT <> 'A' AND F.CODE_CLIENT = @CodeClient
  GROUP BY MONTH(F.DATE_FACTURE), C.CATEGORIE
  ORDER BY MOIS;
END]])
  DM(m, "SRV-ERP", "ERP", "vente", "SP_STAT_VENTES", "PROCEDURE", "2017-01-23", "2023-11-20", [[CREATE PROCEDURE vente.SP_STAT_VENTES
  @Debut DATE,
  @Fin DATE
AS
BEGIN
  SET NOCOUNT ON;
  SELECT C.PAYS_CODE, P.LIBELLE AS PAYS, COUNT(*) AS NB, SUM(F.MONTANT_TTC) AS CA_TTC,
         CASE WHEN SUM(F.MONTANT_TTC) > 10000 THEN 'GRAND' WHEN SUM(F.MONTANT_TTC) > 1000 THEN 'MOYEN' ELSE 'PETIT' END AS SEGMENT
  FROM vente.FACTURE F
  JOIN vente.CLIENT C ON C.CODE_CLIENT = F.CODE_CLIENT
  JOIN REF.dbo.PAYS P ON P.CODE = C.PAYS_CODE
  WHERE F.DATE_FACTURE BETWEEN @Debut AND @Fin AND F.STATUT <> 'A'
  GROUP BY C.PAYS_CODE, P.LIBELLE;
END]])
  DM(m, "SRV-ERP", "ERP", "vente", "SP_CLIENT_FICHE", "PROCEDURE", "2014-06-30", "2018-04-04", [[CREATE PROCEDURE vente.SP_CLIENT_FICHE
  @Code VARCHAR(10)
AS
BEGIN
  SELECT * FROM vente.CLIENT WHERE UPPER(CODE_CLIENT) = UPPER(@Code);
  SELECT * FROM vente.CONTACT WHERE CODCLI = @Code;
  SELECT F.* FROM vente.FACTURE F WHERE F.CODE_CLIENT = @Code AND F.FACTURE_ID NOT IN (SELECT FACTURE_ID FROM vente.REGLEMENT);
END]])
  DM(m, "SRV-ERP", "ERP", "vente", "SP_RELANCE_IMPAYES", "PROCEDURE", "2017-05-15", "2024-06-01", [[CREATE PROCEDURE vente.SP_RELANCE_IMPAYES
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @i INT = 1, @n INT, @Email VARCHAR(120), @Corps NVARCHAR(MAX);
  SELECT IDENTITY(INT, 1, 1) AS RANG, I.CODE_CLIENT, C.EMAIL, SUM(I.RESTE_DU) AS DU
  INTO #RELANCES
  FROM vente.V_FACTURES_IMPAYEES I JOIN vente.CLIENT C ON C.CODE_CLIENT = I.CODE_CLIENT
  WHERE I.JOURS_RETARD > 30
  GROUP BY I.CODE_CLIENT, C.EMAIL;
  SELECT @n = COUNT(*) FROM #RELANCES;
  WHILE @i <= @n
  BEGIN
    SELECT @Email = EMAIL, @Corps = N'Montant dû : ' + CAST(DU AS NVARCHAR(20)) FROM #RELANCES WHERE RANG = @i;
    EXEC msdb.dbo.sp_send_dbmail @profile_name = 'ERP', @recipients = @Email, @subject = 'Relance', @body = @Corps;
    SET @i = @i + 1;
  END
END]])
  && --- ERP : stocks, RH, technique
  DM(m, "SRV-ERP", "ERP", "stock", "SP_MOUVEMENT_STOCK", "PROCEDURE", "2014-03-20", "2022-01-14", [[CREATE PROCEDURE stock.SP_MOUVEMENT_STOCK
  @Article VARCHAR(15),
  @Entrepot INT,
  @Qte DECIMAL(10,3),
  @Sens CHAR(1)
AS
BEGIN
  SET NOCOUNT ON;
  IF @Sens NOT IN ('E', 'S')
    THROW 50010, 'Sens invalide', 1;
  BEGIN TRAN;
  INSERT INTO stock.MOUVEMENT_STOCK (CODE_ARTICLE, ENTREPOT_ID, DATE_MOUVEMENT, QTE, SENS, ORIGINE)
  VALUES (@Article, @Entrepot, SYSDATETIME(), @Qte, @Sens, 'SAISIE');
  UPDATE stock.STOCK SET QTE_DISPO = QTE_DISPO + CASE WHEN @Sens = 'E' THEN @Qte ELSE -@Qte END
  WHERE CODE_ARTICLE = @Article AND ENTREPOT_ID = @Entrepot;
  IF @@ROWCOUNT = 0
    INSERT INTO stock.STOCK (CODE_ARTICLE, ENTREPOT_ID, QTE_DISPO, QTE_RESERVEE) VALUES (@Article, @Entrepot, @Qte, 0);
  COMMIT;
END]])
  DM(m, "SRV-ERP", "ERP", "stock", "SP_INVENTAIRE", "PROCEDURE", "2014-03-20", "2016-09-09", [[CREATE PROCEDURE stock.SP_INVENTAIRE
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @Article VARCHAR(15), @Entrepot INT, @Qte DECIMAL(12,3);
  DECLARE c_art CURSOR FOR SELECT S.CODE_ARTICLE, S.ENTREPOT_ID FROM stock.STOCK S JOIN stock.ARTICLE A ON A.CODE_ARTICLE = S.CODE_ARTICLE WHERE A.ACTIF = 1;
  OPEN c_art;
  FETCH NEXT FROM c_art INTO @Article, @Entrepot;
  WHILE @@FETCH_STATUS = 0
  BEGIN
    SELECT @Qte = SUM(CASE WHEN SENS = 'E' THEN QTE ELSE -QTE END) FROM stock.MOUVEMENT_STOCK WHERE CODE_ARTICLE = @Article AND ENTREPOT_ID = @Entrepot;
    UPDATE stock.STOCK SET QTE_DISPO = ISNULL(@Qte, 0) WHERE CODE_ARTICLE = @Article AND ENTREPOT_ID = @Entrepot;
    FETCH NEXT FROM c_art INTO @Article, @Entrepot;
  END
  CLOSE c_art;
  DEALLOCATE c_art;
END]])
  DM(m, "SRV-ERP", "ERP", "rh", "SP_PAIE_MENSUELLE", "PROCEDURE", "2015-01-05", "2025-01-02", [[CREATE PROCEDURE rh.SP_PAIE_MENSUELLE
  @Mois DATE
AS
BEGIN
  SET NOCOUNT ON;
  IF EXISTS (SELECT 1 FROM COMPTA.dbo.EXERCICE WHERE @Mois BETWEEN DATE_DEBUT AND DATE_FIN AND CLOS = 1)
    THROW 50020, 'Exercice clos', 1;
  INSERT INTO COMPTA.dbo.ECRITURE (JOURNAL_CODE, DATE_ECRITURE, COMPTE, LIBELLE, DEBIT, CREDIT, PIECE, CODE_TIERS)
  SELECT 'PAI', EOMONTH(@Mois), '641100', 'Salaire ' + E.NOM + ' ' + E.PRENOM, E.SALAIRE_BRUT, 0, 'PAIE-' + E.MATRICULE, E.MATRICULE
  FROM rh.EMPLOYE E
  WHERE E.DATE_EMBAUCHE <= EOMONTH(@Mois);
  SELECT E.MATRICULE, E.NOM, E.PRENOM, E.NIR, E.SALAIRE_BRUT FROM rh.EMPLOYE E ORDER BY E.NOM;
END]])
  DM(m, "SRV-ERP", "ERP", "dbo", "SP_LOG", "PROCEDURE", "2014-03-11", "2014-03-11", [[CREATE PROCEDURE dbo.SP_LOG
  @Message NVARCHAR(4000),
  @Niveau VARCHAR(10) = 'INFO'
AS
  INSERT INTO dbo.LOG_TRAITEMENT (DATE_LOG, PROCEDURE_NOM, MESSAGE, NIVEAU)
  VALUES (SYSDATETIME(), OBJECT_NAME(@@PROCID), @Message, @Niveau);]])
  DM(m, "SRV-ERP", "ERP", "dbo", "SP_NETTOYAGE_LOG", "PROCEDURE", "2016-07-07", "2016-07-07", [[CREATE PROCEDURE dbo.SP_NETTOYAGE_LOG
AS
BEGIN
  SET ROWCOUNT 50000;
  WHILE 1 = 1
  BEGIN
    DELETE FROM dbo.LOG_TRAITEMENT WHERE DATEDIFF(DAY, DATE_LOG, GETDATE()) > 180;
    IF @@ROWCOUNT = 0 BREAK;
    WAITFOR DELAY '00:00:01';
  END
  SET ROWCOUNT 0;
END]])
  DM(m, "SRV-ERP", "ERP", "dbo", "SP_PARAMETRE_LIRE", "PROCEDURE", "2014-03-11", "2014-03-11", [[CREATE PROCEDURE dbo.SP_PARAMETRE_LIRE
  @Cle VARCHAR(50)
AS
  SELECT VALEUR FROM dbo.PARAMETRE WHERE CLE = @Cle;]])
  DM(m, "SRV-ERP", "ERP", "dbo", "FN_TTC", "FONCTION", "2014-03-11", "2019-01-07", [[CREATE FUNCTION dbo.FN_TTC (@Ht DECIMAL(15,2), @Taux DECIMAL(5,4))
RETURNS DECIMAL(15,2)
AS
BEGIN
  RETURN ROUND(@Ht * (1 + @Taux), 2);
END]])
  DM(m, "SRV-ERP", "ERP", "dbo", "FN_AGE", "FONCTION", "2015-03-03", "2015-03-03", [[CREATE FUNCTION dbo.FN_AGE (@Naissance DATE)
RETURNS INT
AS
BEGIN
  RETURN DATEDIFF(YEAR, @Naissance, GETDATE()) - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, @Naissance, GETDATE()), @Naissance) > GETDATE() THEN 1 ELSE 0 END;
END]])
  DM(m, "SRV-ERP", "ERP", "vente", "FN_CA_CLIENT", "FONCTION", "2018-02-02", "2021-08-16", [[CREATE FUNCTION vente.FN_CA_CLIENT (@CodeClient VARCHAR(10))
RETURNS TABLE
AS
RETURN (
  SELECT YEAR(F.DATE_FACTURE) AS ANNEE, SUM(F.MONTANT_HT) AS CA_HT, SUM(F.MONTANT_TTC) AS CA_TTC
  FROM vente.FACTURE F
  JOIN vente.CLIENT C ON C.CODE_CLIENT = F.CODE_CLIENT
  WHERE F.CODE_CLIENT = @CodeClient AND F.STATUT <> 'A'
  GROUP BY YEAR(F.DATE_FACTURE)
)]])
  DM(m, "SRV-ERP", "ERP", "vente", "V_CA_CLIENT", "VUE", "2015-09-01", "2020-03-12", [[CREATE VIEW vente.V_CA_CLIENT AS
SELECT C.CODE_CLIENT, C.NOM, C.VILLE, SUM(F.MONTANT_HT) AS CA_HT, SUM(F.MONTANT_TTC) AS CA_TTC,
       CASE WHEN SUM(F.MONTANT_TTC) > 10000 THEN 'GRAND' WHEN SUM(F.MONTANT_TTC) > 1000 THEN 'MOYEN' ELSE 'PETIT' END AS SEGMENT
FROM vente.FACTURE F
JOIN vente.CLIENT C ON C.CODE_CLIENT = F.CODE_CLIENT
WHERE F.STATUT <> 'A'
GROUP BY C.CODE_CLIENT, C.NOM, C.VILLE]])
  DM(m, "SRV-ERP", "ERP", "vente", "V_FACTURES_IMPAYEES", "VUE", "2017-05-15", "2022-05-30", [[CREATE VIEW vente.V_FACTURES_IMPAYEES AS
SELECT F.FACTURE_ID, F.NUM_FACTURE, F.CODE_CLIENT, F.DATE_ECHEANCE, F.MONTANT_TTC - ISNULL(SUM(R.MONTANT), 0) AS RESTE_DU,
       DATEDIFF(DAY, F.DATE_ECHEANCE, GETDATE()) AS JOURS_RETARD
FROM vente.FACTURE F
LEFT JOIN vente.REGLEMENT R ON R.FACTURE_ID = F.FACTURE_ID
WHERE F.STATUT = 'E'
GROUP BY F.FACTURE_ID, F.NUM_FACTURE, F.CODE_CLIENT, F.DATE_ECHEANCE, F.MONTANT_TTC
HAVING F.MONTANT_TTC - ISNULL(SUM(R.MONTANT), 0) > 0]])
  DM(m, "SRV-ERP", "ERP", "dbo", "V_CLIENT_COMPLET", "VUE", "2016-10-03", "2016-10-03", [[CREATE VIEW dbo.V_CLIENT_COMPLET AS
SELECT C.CLIENT_ID, C.CODE_CLIENT, C.NOM, C.PRENOM, C.EMAIL, C.TELEPHONE, C.VILLE, P.LIBELLE AS PAYS, dbo.FN_AGE(C.DATE_NAISSANCE) AS AGE
FROM vente.CLIENT C
LEFT JOIN dbo.SYN_PAYS P ON P.CODE = C.PAYS_CODE]])
  DM(m, "SRV-ERP", "ERP", "rh", "V_ANNUAIRE", "VUE", "2015-01-05", "2015-01-05", [[CREATE VIEW rh.V_ANNUAIRE AS
SELECT MATRICULE, NOM, PRENOM, EMAIL, TELEPHONE, SERVICE FROM rh.EMPLOYE]])
  DM(m, "SRV-ERP", "ERP", "vente", "TR_FACTURE_AUDIT", "DECLENCHEUR", "2015-02-10", "2020-07-21", [[CREATE TRIGGER vente.TR_FACTURE_AUDIT ON vente.FACTURE
AFTER INSERT, UPDATE
AS
BEGIN
  SET NOCOUNT ON;
  INSERT INTO dbo.LOG_TRAITEMENT (DATE_LOG, PROCEDURE_NOM, MESSAGE, NIVEAU)
  SELECT SYSDATETIME(), 'TR_FACTURE_AUDIT', 'Facture ' + I.NUM_FACTURE + ' : ' + I.STATUT, 'AUDIT' FROM inserted I;
END]], "FACTURE")
  DM(m, "SRV-ERP", "ERP", "vente", "TR_CLIENT_MAJ", "DECLENCHEUR", "2016-11-08", "2016-11-08", [[CREATE TRIGGER vente.TR_CLIENT_MAJ ON vente.CLIENT
AFTER UPDATE
AS
BEGIN
  IF UPDATE(EMAIL)
    INSERT INTO dbo.LOG_TRAITEMENT (DATE_LOG, PROCEDURE_NOM, MESSAGE, NIVEAU)
    SELECT SYSDATETIME(), 'TR_CLIENT_MAJ', 'Email modifié ' + I.CODE_CLIENT, 'AUDIT' FROM inserted I;
END]], "CLIENT")
  && --- COMPTA
  DM(m, "SRV-COMPTA", "COMPTA", "dbo", "SP_SAISIE_ECRITURE", "PROCEDURE", "2011-07-01", "2021-02-11", [[CREATE PROCEDURE dbo.SP_SAISIE_ECRITURE
  @Journal CHAR(3), @Date DATE, @Compte VARCHAR(10), @Libelle NVARCHAR(120), @Debit DECIMAL(15,2), @Credit DECIMAL(15,2), @Piece VARCHAR(20)
AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS (SELECT 1 FROM dbo.COMPTE WHERE NUMERO = @Compte)
    THROW 51000, 'Compte inconnu', 1;
  IF EXISTS (SELECT 1 FROM dbo.EXERCICE WHERE @Date BETWEEN DATE_DEBUT AND DATE_FIN AND CLOS = 1)
    THROW 51001, 'Exercice clos', 1;
  INSERT INTO dbo.ECRITURE (JOURNAL_CODE, DATE_ECRITURE, COMPTE, LIBELLE, DEBIT, CREDIT, PIECE)
  VALUES (@Journal, @Date, @Compte, @Libelle, @Debit, @Credit, @Piece);
  SELECT SCOPE_IDENTITY() AS ECRITURE_ID;
END]])
  DM(m, "SRV-COMPTA", "COMPTA", "dbo", "SP_BALANCE", "PROCEDURE", "2011-07-01", "2018-12-20", [[CREATE PROCEDURE dbo.SP_BALANCE
  @Exercice INT
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @d1 DATE, @d2 DATE;
  SELECT @d1 = DATE_DEBUT, @d2 = DATE_FIN FROM dbo.EXERCICE WHERE EXERCICE_ID = @Exercice;
  SELECT C.NUMERO, C.LIBELLE, SUM(E.DEBIT) AS DEBIT, SUM(E.CREDIT) AS CREDIT, SUM(E.DEBIT - E.CREDIT) AS SOLDE
  FROM dbo.ECRITURE E
  JOIN dbo.COMPTE C ON C.NUMERO = E.COMPTE
  WHERE E.DATE_ECRITURE BETWEEN @d1 AND @d2
  GROUP BY C.NUMERO, C.LIBELLE
  ORDER BY C.NUMERO;
END]])
  DM(m, "SRV-COMPTA", "COMPTA", "dbo", "SP_CLOTURE_EXERCICE", "PROCEDURE", "2012-12-15", "2023-12-28", [[CREATE PROCEDURE dbo.SP_CLOTURE_EXERCICE
  @Exercice INT
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @fin DATE, @Compte VARCHAR(10), @Solde DECIMAL(15,2);
  SELECT @fin = DATE_FIN FROM dbo.EXERCICE WHERE EXERCICE_ID = @Exercice AND CLOS = 0;
  IF @fin IS NULL
    THROW 51010, 'Exercice inconnu ou déjà clos', 1;
  BEGIN TRANSACTION;
  DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT COMPTE, SUM(DEBIT - CREDIT) FROM dbo.ECRITURE WHERE DATE_ECRITURE <= @fin GROUP BY COMPTE;
  OPEN c;
  FETCH NEXT FROM c INTO @Compte, @Solde;
  WHILE @@FETCH_STATUS = 0
  BEGIN
    INSERT INTO dbo.ECRITURE (JOURNAL_CODE, DATE_ECRITURE, COMPTE, LIBELLE, DEBIT, CREDIT, PIECE)
    VALUES ('ANO', DATEADD(DAY, 1, @fin), @Compte, 'A nouveau', CASE WHEN @Solde > 0 THEN @Solde ELSE 0 END, CASE WHEN @Solde < 0 THEN -@Solde ELSE 0 END, 'ANO');
    FETCH NEXT FROM c INTO @Compte, @Solde;
  END
  CLOSE c;
  DEALLOCATE c;
  UPDATE dbo.EXERCICE SET CLOS = 1 WHERE EXERCICE_ID = @Exercice;
  COMMIT;
END]])
  DM(m, "SRV-COMPTA", "COMPTA", "dbo", "V_GRAND_LIVRE", "VUE", "2011-07-01", "2017-03-01", [[CREATE VIEW dbo.V_GRAND_LIVRE AS
SELECT E.DATE_ECRITURE, E.JOURNAL_CODE, J.LIBELLE AS JOURNAL, E.COMPTE, C.LIBELLE AS COMPTE_LIBELLE, E.LIBELLE, E.DEBIT, E.CREDIT, E.PIECE, T.RAISON_SOCIALE
FROM dbo.ECRITURE E
JOIN dbo.JOURNAL J ON J.CODE = E.JOURNAL_CODE
JOIN dbo.COMPTE C ON C.NUMERO = E.COMPTE
LEFT JOIN dbo.TIERS T ON T.CODE_TIERS = E.CODE_TIERS]])
  && --- DWH
  DM(m, "SRV-DWH", "DWH", "dw", "SP_CHARGER_DIM_CLIENT", "PROCEDURE", "2020-04-01", "2025-03-03", [[CREATE PROCEDURE dw.SP_CHARGER_DIM_CLIENT
AS
BEGIN
  SET NOCOUNT ON;
  MERGE dw.DIM_CLIENT AS D
  USING (SELECT CODE_CLIENT, NOM, VILLE, PAYS_CODE, CATEGORIE FROM LNK_ERP.ERP.vente.CLIENT WHERE ACTIF = 1) AS S
  ON D.CODE_CLIENT = S.CODE_CLIENT AND D.COURANT = 1
  WHEN MATCHED AND (D.NOM <> S.NOM OR D.VILLE <> S.VILLE) THEN UPDATE SET D.DATE_FIN = CAST(GETDATE() AS DATE), D.COURANT = 0
  WHEN NOT MATCHED THEN INSERT (CODE_CLIENT, NOM, VILLE, PAYS, SEGMENT, DATE_DEBUT, COURANT)
    VALUES (S.CODE_CLIENT, S.NOM, S.VILLE, S.PAYS_CODE, S.CATEGORIE, CAST(GETDATE() AS DATE), 1);
END]])
  DM(m, "SRV-DWH", "DWH", "dw", "SP_CHARGER_FAIT_VENTE", "PROCEDURE", "2020-04-01", "2025-06-12", [[CREATE PROCEDURE dw.SP_CHARGER_FAIT_VENTE
AS
BEGIN
  SET NOCOUNT ON;
  INSERT INTO dw.FAIT_VENTE (DATE_SK, CLIENT_SK, ARTICLE_SK, QTE, MONTANT_HT, MONTANT_TTC, MARGE)
  SELECT T.DATE_SK, C.CLIENT_SK, 0, 1, S.MONTANT_HT, S.MONTANT_TTC, S.MONTANT_HT * 0.3
  FROM stg.STG_FACTURE S
  JOIN dw.DIM_TEMPS T ON T.DATE_JOUR = S.DATE_FACTURE
  JOIN dw.DIM_CLIENT C ON C.CODE_CLIENT = S.CODE_CLIENT AND C.COURANT = 1;
  TRUNCATE TABLE stg.STG_FACTURE;
END]])
  DM(m, "SRV-DWH", "DWH", "dw", "SP_CHARGER_DIM_TEMPS", "PROCEDURE", "2020-04-01", "2020-04-01", [[CREATE PROCEDURE dw.SP_CHARGER_DIM_TEMPS
  @Annee INT
AS
BEGIN
  DECLARE @d DATE = DATEFROMPARTS(@Annee, 1, 1);
  WHILE YEAR(@d) = @Annee
  BEGIN
    INSERT INTO dw.DIM_TEMPS (DATE_SK, DATE_JOUR, ANNEE, MOIS, JOUR_SEMAINE)
    VALUES (CONVERT(INT, CONVERT(CHAR(8), @d, 112)), @d, YEAR(@d), MONTH(@d), DATEPART(WEEKDAY, @d));
    SET @d = DATEADD(DAY, 1, @d);
  END
END]])
  DM(m, "SRV-DWH", "DWH", "dw", "V_VENTES_MENSUELLES", "VUE", "2020-05-11", "2024-01-15", [[CREATE VIEW dw.V_VENTES_MENSUELLES AS
SELECT T.ANNEE, T.MOIS, C.SEGMENT, SUM(F.MONTANT_HT) AS CA_HT, SUM(F.MARGE) AS MARGE
FROM dw.FAIT_VENTE F
JOIN dw.DIM_TEMPS T ON T.DATE_SK = F.DATE_SK
JOIN dw.DIM_CLIENT C ON C.CLIENT_SK = F.CLIENT_SK
GROUP BY T.ANNEE, T.MOIS, C.SEGMENT]])
  && --- procédures CRUD générées (patrimoine typique : beaucoup de code répétitif)
  pour chaque t dans {"vente.CLIENT|CLIENT_ID|CODE_CLIENT,NOM,PRENOM,EMAIL,TELEPHONE,VILLE", ;
                      "vente.CONTACT|CONTACT_ID|CODCLI,NOM,EMAIL,TEL,FONCTION", ;
                      "vente.COMMANDE|COMMANDE_ID|NUM_COMMANDE,CLIENT_CODE,DATE_COMMANDE,STATUT,MONTANT_HT", ;
                      "vente.REGLEMENT|REGLEMENT_ID|FACTURE_ID,DATE_REGLEMENT,MONTANT,MODE_REGLEMENT", ;
                      "stock.ARTICLE|ARTICLE_ID|CODE_ARTICLE,LIBELLE,FAMILLE,PRIX_UNITAIRE,TVA_CODE", ;
                      "stock.ENTREPOT|ENTREPOT_ID|CODE_ENTREPOT,LIBELLE,VILLE", ;
                      "rh.EMPLOYE|EMPLOYE_ID|MATRICULE,NOM,PRENOM,EMAIL,SERVICE", ;
                      "rh.CONGE|CONGE_ID|MATRICULE,DATE_DEBUT,DATE_FIN,TYPE_CONGE"}
    DEMO_CRUD(m, t)
  suivant
retourner m

procedure DM(m, serveur, base, sch, nom, genre, cree, modifie, texte, parent)
  inserer(m, {serveur = serveur, base = base, sch = sch, nom = nom, genre = genre, cree = cree, modifie = modifie, ;
              texte = texte, parent = sisinon(parent = nul, "", parent)})
retourner

procedure DEMO_CRUD(m, spec)
  locale p = decouper(spec, "|")
  locale tq = p[1]
  locale sch = decouper(tq, ".")[1]
  locale t = decouper(tq, ".")[2]
  locale pk = p[2]
  locale cols = decouper(p[3], ",")
  locale nl = car(10)
  locale params = {}
  locale sets = {}
  pour chaque c dans cols
    inserer(params, "  @" + c + " NVARCHAR(200)")
    inserer(sets, c + " = @" + c)
  suivant
  locale lst = joindre(cols, ", ")
  locale vals = "@" + joindre(cols, ", @")
  locale an = "2014-0" + chaine(1 + (#t % 9)) + "-1" + chaine(#cols % 9)
  DM(m, "SRV-ERP", "ERP", sch, "SP_" + t + "_LIRE", "PROCEDURE", an, an, ;
     "CREATE PROCEDURE " + tq + "_LIRE" + nl + "  @Id INT" + nl + "AS" + nl + "BEGIN" + nl + "  SET NOCOUNT ON;" + nl + ;
     "  SELECT " + pk + ", " + lst + " FROM " + tq + " WHERE " + pk + " = @Id;" + nl + "END")
  DM(m, "SRV-ERP", "ERP", sch, "SP_" + t + "_LISTE", "PROCEDURE", an, an, ;
     "CREATE PROCEDURE " + tq + "_LISTE" + nl + "AS" + nl + "BEGIN" + nl + "  SET NOCOUNT ON;" + nl + ;
     "  SELECT * FROM " + tq + " ORDER BY " + pk + ";" + nl + "END")
  DM(m, "SRV-ERP", "ERP", sch, "SP_" + t + "_AJOUTER", "PROCEDURE", an, an, ;
     "CREATE PROCEDURE " + tq + "_AJOUTER" + nl + joindre(params, "," + nl) + nl + "AS" + nl + "BEGIN" + nl + ;
     "  SET NOCOUNT ON;" + nl + "  INSERT INTO " + tq + " (" + lst + ")" + nl + "  VALUES (" + vals + ");" + nl + ;
     "  SELECT @@IDENTITY AS ID;" + nl + "  EXEC dbo.SP_LOG @Message = 'Ajout " + t + "', @Niveau = 'INFO';" + nl + "END")
  DM(m, "SRV-ERP", "ERP", sch, "SP_" + t + "_MODIFIER", "PROCEDURE", an, an, ;
     "CREATE PROCEDURE " + tq + "_MODIFIER" + nl + "  @Id INT," + nl + joindre(params, "," + nl) + nl + "AS" + nl + ;
     "BEGIN" + nl + "  SET NOCOUNT ON;" + nl + "  UPDATE " + tq + " SET " + joindre(sets, ", ") + " WHERE " + pk + " = @Id;" + nl + ;
     "  EXEC dbo.SP_LOG @Message = 'Modification " + t + "', @Niveau = 'INFO';" + nl + "END")
  DM(m, "SRV-ERP", "ERP", sch, "SP_" + t + "_SUPPRIMER", "PROCEDURE", an, an, ;
     "CREATE PROCEDURE " + tq + "_SUPPRIMER" + nl + "  @Id INT" + nl + "AS" + nl + "BEGIN" + nl + "  SET NOCOUNT ON;" + nl + ;
     "  DELETE FROM " + tq + " WHERE " + pk + " = @Id;" + nl + ;
     "  EXEC dbo.SP_LOG @Message = 'Suppression " + t + "', @Niveau = 'INFO';" + nl + "END")
retourner

&&
&& Extraction simulée : remplit les tables ext_* pour un serveur et un genre d'extraction
&&

fonction DEMO_GENRES()
retourner {"objets", "colonnes", "modules", "dependances", "stats", "index_manquants", "jobs", "profils"}

procedure DEMO_EXTRAIRE(s, source_id, serveur, genre, travail)
  faire cas
  cas genre = "objets"
    DEMO_OBJETS(s, source_id, serveur)
  cas genre = "colonnes"
    DEMO_COLONNES(s, source_id, serveur)
  cas genre = "modules"
    DEMO_MODULES_EXT(s, source_id, serveur)
  cas genre = "dependances"
    DEMO_DEPENDANCES(s, source_id, serveur)
  cas genre = "stats"
    DEMO_STATS(s, source_id, serveur)
  cas genre = "index_manquants"
    DEMO_INDEX(s, source_id, serveur)
  cas genre = "jobs"
    DEMO_JOBS(s, source_id, serveur)
  cas genre = "profils"
    DEMO_PROFILS(s, source_id, serveur)
  fincas
retourner

fonction DEMO_TABLES_DE(serveur)
  locale r = {}
  pour chaque l dans DEMO_TABLES()
    locale p = decouper(l, "|")
    si p[1] = serveur
      inserer(r, {serveur = p[1], base = p[2], sch = p[3], nom = p[4], lignes = nombre(p[5]), cree = p[6], cols = p[7]})
    finsi
  suivant
retourner r

fonction DEMO_COLS(t)
  && colonnes d'une spécification : {nom, type, pk, id, nn, fk}
  locale r = {}
  pour chaque c dans decouper(t.cols, ",")
    && decimal(15,2) contient une virgule : on recolle
    si #r > 0 et non (":" $ c)
      r[#r].type = r[#r].type + "," + c
      boucler
    finsi
    locale p = decouper(c, ":")
    locale col = {nom = p[1], type = p[2], pk = faux, id = faux, nn = faux, fk = ""}
    pour i = 3 a #p
      faire cas
      cas p[i] = "pk"
        col.pk = vrai
      cas p[i] = "id"
        col.id = vrai
      cas p[i] = "nn"
        col.nn = vrai
      cas commencepar(p[i], "fk=")
        col.fk = souschaine(p[i], 4)
      fincas
    suivant
    inserer(r, col)
  suivant
  && decimal(15 / 2) découpé sur la virgule : recollage fait ci-dessus pour les morceaux sans « : »
  pour chaque col dans r
    si "(" $ col.type et non (")" $ col.type)
      col.type = col.type + ")"
    finsi
  suivant
retourner r

fonction DEMO_DATE(d, h)
retourner d + " " + sisinon(h = nul, "09:14:00", h)

procedure DEMO_OBJETS(s, source_id, serveur)
  locale l = {}
  locale srv = nul
  pour chaque x dans DEMO_SERVEURS()
    si x.nom = serveur
      srv = x
    finsi
  suivant
  && tables, index, statistiques, contraintes, partitions
  pour chaque t dans DEMO_TABLES_DE(serveur)
    locale taille = entier(t.lignes * (0.12 + (#t.cols % 7) / 40))
    inserer(l, {source_id = source_id, serveur = serveur, base = t.base, sch = t.sch, nom = t.nom, genre = "TABLE", ;
                parent_nom = "", proprietaire = "dbo", cree = DEMO_DATE(t.cree), modifie = DEMO_DATE(t.cree, "18:02:00"), ;
                lignes = t.lignes, taille_ko = taille, definition = nul, cible = "", detail = ""})
    locale pk = {}
    pour chaque c dans DEMO_COLS(t)
      si c.pk
        inserer(pk, c.nom)
      finsi
      si c.fk <> ""
        inserer(l, {source_id = source_id, serveur = serveur, base = t.base, sch = t.sch, nom = "FK_" + t.nom + "_" + c.nom, ;
                    genre = "CONTRAINTE", parent_nom = t.nom, proprietaire = "dbo", cree = DEMO_DATE(t.cree), ;
                    modifie = DEMO_DATE(t.cree), lignes = nul, taille_ko = nul, definition = "FOREIGN KEY (" + c.nom + ") REFERENCES " + c.fk, ;
                    cible = c.fk, detail = "FOREIGN_KEY"})
      finsi
    suivant
    si #pk > 0
      inserer(l, {source_id = source_id, serveur = serveur, base = t.base, sch = t.sch, nom = "PK_" + t.nom, genre = "CONTRAINTE", ;
                  parent_nom = t.nom, proprietaire = "dbo", cree = DEMO_DATE(t.cree), modifie = DEMO_DATE(t.cree), ;
                  lignes = nul, taille_ko = nul, definition = "PRIMARY KEY CLUSTERED (" + joindre(pk, ", ") + ")", cible = "", ;
                  detail = "PRIMARY_KEY"})
      inserer(l, {source_id = source_id, serveur = serveur, base = t.base, sch = t.sch, nom = "PK_" + t.nom, genre = "INDEX", ;
                  parent_nom = t.nom, proprietaire = "dbo", cree = DEMO_DATE(t.cree), modifie = DEMO_DATE(t.cree), ;
                  lignes = t.lignes, taille_ko = taille, definition = "CLUSTERED (" + joindre(pk, ", ") + ")", cible = "", ;
                  detail = "CLUSTERED"})
      inserer(l, {source_id = source_id, serveur = serveur, base = t.base, sch = t.sch, nom = "PK_" + t.nom, genre = "STATISTIQUE", ;
                  parent_nom = t.nom, proprietaire = "dbo", cree = DEMO_DATE(t.cree), modifie = DEMO_DATE("2025-11-0" + chaine(1 + #t.nom % 8)), ;
                  lignes = t.lignes, taille_ko = nul, definition = joindre(pk, ", "), cible = "", detail = "auto"})
    finsi
    si t.nom = "FAIT_VENTE"
      pour a = 2020 a 2025
        inserer(l, {source_id = source_id, serveur = serveur, base = t.base, sch = t.sch, nom = "FAIT_VENTE$" + a, ;
                    genre = "PARTITION", parent_nom = t.nom, proprietaire = "dbo", cree = DEMO_DATE(t.cree), ;
                    modifie = DEMO_DATE(t.cree), lignes = 4000000 + (a - 2020) * 1500000, taille_ko = 900000 + (a - 2020) * 300000, ;
                    definition = "PF_ANNEE / PS_ANNEE : " + a, cible = "", detail = "partition " + (a - 2019)})
      suivant
    finsi
  suivant
  && index non uniques existants
  si serveur = "SRV-ERP"
    DEMO_IDX(l, source_id, serveur, "ERP", "vente", "COMMANDE", "IX_COMMANDE_STATUT", "STATUT, DATE_COMMANDE")
    DEMO_IDX(l, source_id, serveur, "ERP", "vente", "FACTURE", "IX_FACTURE_DATE", "DATE_FACTURE")
    DEMO_IDX(l, source_id, serveur, "ERP", "vente", "CLIENT", "UX_CLIENT_CODE", "CODE_CLIENT")
    DEMO_IDX(l, source_id, serveur, "ERP", "stock", "MOUVEMENT_STOCK", "IX_MVT_ARTICLE", "CODE_ARTICLE, ENTREPOT_ID")
    DEMO_IDX(l, source_id, serveur, "ERP", "vente", "FACTURE", "IX_FACTURE_STATUT", "STATUT")
    DEMO_IDX(l, source_id, serveur, "ERP", "vente", "FACTURE", "IX_FACTURE_STATUT_DATE", "STATUT, DATE_FACTURE")
  finsi
  && modules
  pour chaque md dans DEMO_MODULES()
    si md.serveur = serveur
      inserer(l, {source_id = source_id, serveur = serveur, base = md.base, sch = md.sch, nom = md.nom, genre = md.genre, ;
                  parent_nom = md.parent, proprietaire = "dbo", cree = DEMO_DATE(md.cree), modifie = DEMO_DATE(md.modifie, "11:40:00"), ;
                  lignes = nul, taille_ko = nul, definition = nul, cible = "", detail = ""})
    finsi
  suivant
  && objets propres à chaque serveur
  faire cas
  cas serveur = "SRV-ERP"
    DEMO_OBJ(l, source_id, serveur, "ERP", "dbo", "SYN_TVA", "SYNONYME", "REF.dbo.TVA")
    DEMO_OBJ(l, source_id, serveur, "ERP", "dbo", "SYN_PAYS", "SYNONYME", "REF.dbo.PAYS")
    DEMO_OBJ(l, source_id, serveur, "ERP", "dbo", "SYN_ECRITURE", "SYNONYME", "LNK_COMPTA.COMPTA.dbo.ECRITURE")
    DEMO_OBJ(l, source_id, serveur, "", "", "LNK_COMPTA", "SERVEUR_LIE", "SRV-COMPTA")
    DEMO_OBJ(l, source_id, serveur, "", "", "LNK_DWH", "SERVEUR_LIE", "SRV-DWH")
    DEMO_OBJ(l, source_id, serveur, "ERP", "vente", "SEQ_NUM_FACTURE", "SEQUENCE", "bigint, début 1, pas 1")
    DEMO_OBJ(l, source_id, serveur, "ERP", "dbo", "T_CODE_CLIENT", "TYPE", "varchar(10) NOT NULL")
    DEMO_OBJ(l, source_id, serveur, "ERP", "dbo", "T_MONTANT", "TYPE", "decimal(15,2)")
    DEMO_OBJ(l, source_id, serveur, "ERP", "dbo", "OutilsChaines", "CLR", "SAFE · OutilsChaines, Version=1.2.0.0")
    DEMO_OBJ(l, source_id, serveur, "ERP", "dbo", "FN_REGEX_MATCH", "FONCTION", "CLR OutilsChaines.Regex.Match")
  cas serveur = "SRV-DWH"
    DEMO_OBJ(l, source_id, serveur, "", "", "LNK_ERP", "SERVEUR_LIE", "SRV-ERP")
  fincas
  INSERER_LIGNES(s, "ext_objets", SPEC_TABLE(s, "ext_objets"), l)
retourner

procedure DEMO_IDX(l, source_id, serveur, base, sch, t, nom, cols)
  inserer(l, {source_id = source_id, serveur = serveur, base = base, sch = sch, nom = nom, genre = "INDEX", parent_nom = t, ;
              proprietaire = "dbo", cree = DEMO_DATE("2016-05-12"), modifie = DEMO_DATE("2016-05-12"), lignes = nul, ;
              taille_ko = nul, definition = "NONCLUSTERED (" + cols + ")", cible = "", detail = "NONCLUSTERED"})
retourner

procedure DEMO_OBJ(l, source_id, serveur, base, sch, nom, genre, cible)
  inserer(l, {source_id = source_id, serveur = serveur, base = base, sch = sch, nom = nom, genre = genre, parent_nom = "", ;
              proprietaire = "dbo", cree = DEMO_DATE("2016-03-14"), modifie = DEMO_DATE("2021-09-30"), lignes = nul, ;
              taille_ko = nul, definition = nul, cible = cible, detail = ""})
retourner

procedure DEMO_COLONNES(s, source_id, serveur)
  locale l = {}
  pour chaque t dans DEMO_TABLES_DE(serveur)
    locale o = 0
    pour chaque c dans DEMO_COLS(t)
      o += 1
      locale ty = c.type
      locale lg = nul, pr = nul, ec = nul
      locale par = position("(", ty)
      si par > 0
        locale arg = decouper(souschaine(ty, par + 1, #ty - par - 1), ",")
        si "char" $ minuscule(ty)
          lg = nombre(arg[1])
        sinon
          pr = nombre(arg[1])
          ec = sisinon(#arg > 1, nombre(arg[2]), 0)
        finsi
      finsi
      inserer(l, {source_id = source_id, serveur = serveur, base = t.base, sch = t.sch, table_nom = t.nom, nom = c.nom, ;
                  ordre = o, type_sql = ty, longueur = lg, prec = pr, echelle = ec, nullable = non (c.pk ou c.nn), ;
                  identite = c.id, calculee = faux, defaut = sisinon(c.nom = "DATE_CREATION", "(sysdatetime())", ;
                  sisinon(c.nom = "ACTIF", "((1))", nul)), pk = c.pk, fk_vers = sisinon(c.fk = "", nul, c.fk)})
    suivant
  suivant
  && colonnes des vues (pour le dictionnaire)
  INSERER_LIGNES(s, "ext_colonnes", SPEC_TABLE(s, "ext_colonnes"), l)
retourner

procedure DEMO_MODULES_EXT(s, source_id, serveur)
  && definitions des modules : complète ext_objets (comme sys.sql_modules)
  locale l = {}
  pour chaque md dans DEMO_MODULES()
    si md.serveur = serveur
      inserer(l, {source_id = source_id, serveur = serveur, base = md.base, sch = md.sch, nom = md.nom, genre = "MODULE", ;
                  parent_nom = "", definition = md.texte})
    finsi
  suivant
  INSERER_LIGNES(s, "ext_objets", SPEC_TABLE(s, "ext_objets"), l)
retourner

procedure DEMO_DEPENDANCES(s, source_id, serveur)
  && sys.sql_expression_dependencies ne voit pas le SQL dynamique ni OPENQUERY :
  && quelques dépendances déclarées suffisent (l'analyseur fait le reste)
  locale l = {}
  si serveur = "SRV-ERP"
    inserer(l, {source_id = source_id, serveur = serveur, base = "ERP", sch = "vente", nom = "V_CA_CLIENT", ;
                ref_serveur = "", ref_base = "", ref_sch = "vente", ref_nom = "FACTURE", nature = "SELECT"})
    inserer(l, {source_id = source_id, serveur = serveur, base = "ERP", sch = "vente", nom = "V_CA_CLIENT", ;
                ref_serveur = "", ref_base = "", ref_sch = "vente", ref_nom = "CLIENT", nature = "SELECT"})
    inserer(l, {source_id = source_id, serveur = serveur, base = "ERP", sch = "dbo", nom = "V_CLIENT_COMPLET", ;
                ref_serveur = "", ref_base = "", ref_sch = "dbo", ref_nom = "SYN_PAYS", nature = "SELECT"})
  finsi
  INSERER_LIGNES(s, "ext_dependances", SPEC_TABLE(s, "ext_dependances"), l)
retourner

fonction DEMO_PLAN(op, cout, lignes, table_)
retourner "<ShowPlanXML><StmtSimple StatementSubTreeCost=" + car(34) + cout + car(34) + " StatementEstRows=" + car(34) + lignes + car(34) + ;
       "><RelOp PhysicalOp=" + car(34) + op + car(34) + " EstimateRows=" + car(34) + lignes + car(34) + ;
       " EstimatedTotalSubtreeCost=" + car(34) + cout + car(34) + "><Object Table=" + car(34) + "[" + table_ + "]" + car(34) + ;
       " /></RelOp></StmtSimple></ShowPlanXML>"

procedure DEMO_STATS(s, source_id, serveur)
  && statistiques d'exécution (sys.dm_exec_procedure_stats / query_stats + plans en cache)
  locale l = {}
  locale k = 0
  pour chaque md dans DEMO_MODULES()
    si md.serveur = serveur et (md.genre = "PROCEDURE" ou md.genre = "FONCTION")
      k += 1
      locale ex = 50 + (k * 7919) % 90000
      locale cpu = (k * 37) % 400 + 2
      locale op = "Clustered Index Seek"
      locale cout = 0.0065 + (k % 9) / 100
      locale lignes = 1 + (k * 13) % 40
      locale tbl = md.sch + "." + md.nom
      faire cas
      cas md.nom = "SP_EMISSION_FACTURE"
        ex = 365
        cpu = 184000
        op = "Hash Match"
        cout = 812.4
        lignes = 2300
        tbl = "vente.LIGNE_COMMANDE"
      cas md.nom = "SP_NETTOYAGE_LOG"
        ex = 180
        cpu = 96000
        op = "Table Scan"
        cout = 1240.7
        lignes = 4200000
        tbl = "dbo.LOG_TRAITEMENT"
      cas md.nom = "SP_CA_MENSUEL" ou md.nom = "SP_CA_CLIENT" ou md.nom = "SP_STAT_VENTES"
        ex = 4200 + k
        cpu = 2400
        op = "Clustered Index Scan"
        cout = 145.2
        lignes = 760000
        tbl = "vente.FACTURE"
      cas md.nom = "SP_CLIENT_FICHE"
        ex = 210000
        cpu = 38
        op = "Clustered Index Scan"
        cout = 31.8
        lignes = 48200
        tbl = "vente.CLIENT"
      cas md.nom = "SP_RECHERCHE_CLIENT"
        ex = 88000
        cpu = 22
        op = "Index Seek"
        cout = 0.9
        lignes = 40
        tbl = "vente.CLIENT"
      cas md.nom = "SP_INVENTAIRE"
        ex = 365
        cpu = 512000
        op = "Clustered Index Scan"
        cout = 980.1
        lignes = 5200000
        tbl = "stock.MOUVEMENT_STOCK"
      cas md.nom = "SP_CHARGER_FAIT_VENTE"
        ex = 365
        cpu = 210000
        op = "Hash Match"
        cout = 1520.3
        lignes = 9800
        tbl = "dw.DIM_CLIENT"
      cas md.nom = "SP_BALANCE"
        ex = 900
        cpu = 7200
        op = "Clustered Index Scan"
        cout = 410.6
        lignes = 12500000
        tbl = "dbo.ECRITURE"
      fincas
      inserer(l, {source_id = source_id, serveur = serveur, base = md.base, sch = md.sch, nom = md.nom, ;
                  texte = COURT(md.texte, 300), executions = ex, cpu_ms = cpu * ex / 1000, duree_ms = cpu * ex / 800, ;
                  lectures = entier(cout * 120 * ex), ecritures = sisinon("INSERT" $ md.texte ou "UPDATE" $ md.texte, ex * 4, 0), ;
                  lignes = lignes * ex, lignes_max = lignes * 4, memoire_ko = sisinon(op = "Hash Match", 512000, 1024), ;
                  derniere = "2026-11-0" + chaine(1 + k % 3) + " 0" + chaine(k % 9) + ":12:00", ;
                  plan = DEMO_PLAN(op, cout, lignes, tbl)})
    finsi
  suivant
  INSERER_LIGNES(s, "ext_stats", SPEC_TABLE(s, "ext_stats"), l)
retourner

procedure DEMO_INDEX(s, source_id, serveur)
  locale l = {}
  faire cas
  cas serveur = "SRV-ERP"
    inserer(l, {source_id = source_id, serveur = serveur, base = "ERP", sch = "vente", table_nom = "FACTURE", ;
                egalite = "[CODE_CLIENT]", inegalite = "[DATE_FACTURE]", inclus = "[MONTANT_HT], [MONTANT_TTC]", impact = 87.4, demandes = 12800})
    inserer(l, {source_id = source_id, serveur = serveur, base = "ERP", sch = "dbo", table_nom = "LOG_TRAITEMENT", ;
                egalite = "", inegalite = "[DATE_LOG]", inclus = "", impact = 95.1, demandes = 540})
    inserer(l, {source_id = source_id, serveur = serveur, base = "ERP", sch = "vente", table_nom = "COMMANDE", ;
                egalite = "[CLIENT_CODE]", inegalite = "", inclus = "[STATUT], [REMISE]", impact = 63.9, demandes = 3100})
    inserer(l, {source_id = source_id, serveur = serveur, base = "ERP", sch = "vente", table_nom = "CONTACT", ;
                egalite = "[CODCLI]", inegalite = "", inclus = "", impact = 58.2, demandes = 210000})
  cas serveur = "SRV-COMPTA"
    inserer(l, {source_id = source_id, serveur = serveur, base = "COMPTA", sch = "dbo", table_nom = "ECRITURE", ;
                egalite = "[CODE_TIERS]", inegalite = "", inclus = "[DEBIT], [CREDIT]", impact = 71.0, demandes = 900})
  fincas
  INSERER_LIGNES(s, "ext_index_manquants", SPEC_TABLE(s, "ext_index_manquants"), l)
retourner

fonction DEMO_JOBS_LISTE()
  locale l = {}
  locale d = {"SRV-ERP|ERP - Facturation nocturne|1|Émission|EXEC vente.SP_EMISSION_FACTURE @DateFacture = NULL|ERP|13000|1260|quotidien", ;
              "SRV-ERP|ERP - Import clients|1|Import|EXEC vente.SP_IMPORT_CLIENTS|ERP|4500|300|quotidien", ;
              "SRV-ERP|ERP - Inventaire|1|Recalcul des stocks|EXEC stock.SP_INVENTAIRE|ERP|21500|1800|quotidien", ;
              "SRV-ERP|ERP - Export DWH|1|Export|EXEC vente.SP_EXPORT_DWH|ERP|30000|900|quotidien", ;
              "SRV-ERP|ERP - Purge mensuelle|1|Purge|EXEC vente.SP_PURGE_COMMANDES @Mois = 36|ERP|40000|2400|mensuel", ;
              "SRV-ERP|ERP - Nettoyage des journaux|1|Nettoyage|EXEC dbo.SP_NETTOYAGE_LOG|ERP|50000|600|hebdomadaire", ;
              "SRV-ERP|ERP - Relances|1|Relances impayés|EXEC vente.SP_RELANCE_IMPAYES|ERP|80000|240|quotidien", ;
              "SRV-COMPTA|COMPTA - Balance|1|Balance|EXEC dbo.SP_BALANCE @Exercice = 9|COMPTA|60000|420|quotidien", ;
              "SRV-DWH|DWH - Chargement|1|Dimension temps|EXEC dw.SP_CHARGER_DIM_TEMPS @Annee = 2026|DWH|32000|60|quotidien", ;
              "SRV-DWH|DWH - Chargement|2|Dimension client|EXEC dw.SP_CHARGER_DIM_CLIENT|DWH|32100|480|quotidien", ;
              "SRV-DWH|DWH - Chargement|3|Faits de vente|EXEC dw.SP_CHARGER_FAIT_VENTE|DWH|33000|1500|quotidien"}
  pour chaque x dans d
    locale p = decouper(x, "|")
    inserer(l, {serveur = p[1], job = p[2], etape = nombre(p[3]), nom_etape = p[4], commande = p[5], base = p[6], ;
                heure_debut = nombre(p[7]), duree_moy_s = nombre(p[8]), frequence = p[9], actif = vrai})
  suivant
retourner l

procedure DEMO_JOBS(s, source_id, serveur)
  locale l = {}
  pour chaque j dans DEMO_JOBS_LISTE()
    si j.serveur = serveur
      j.source_id = source_id
      inserer(l, j)
    finsi
  suivant
  INSERER_LIGNES(s, "ext_jobs", SPEC_TABLE(s, "ext_jobs"), l)
retourner

fonction DEMO_EXEMPLES(nom, type_)
  && valeurs d'exemple d'après le nom de la colonne (analyse des valeurs du dictionnaire)
  locale n = majuscule(nom)
  faire cas
  cas "EMAIL" $ n ou n = "MAIL"
    retourner "j.durand@exemple.fr | m.leroy@exemple.com | contact@societe.fr"
  cas "IBAN" $ n
    retourner "FR7630006000011234567890189 | FR7610107001011234567890129"
  cas n = "NIR"
    retourner "185057800608436 | 279083012345678"
  cas "TEL" $ n
    retourner "0601020304 | +33 4 72 00 00 00"
  cas "NAISSANCE" $ n
    retourner "1978-05-14 | 1991-11-02"
  cas n = "STATUT"
    retourner "E | V | F | A | S"
  cas n = "SENS"
    retourner "E | S"
  cas n = "ACTIF" ou n = "CLOS" ou n = "COURANT"
    retourner "0 | 1"
  cas "SIRET" $ n
    retourner "44306184100047 | 55210055400013"
  cas "CODE_POSTAL" $ n
    retourner "69002 | 75011 | 13008"
  cas "SALAIRE" $ n
    retourner "2450.00 | 3890.50"
  cas n = "NOM" ou n = "RAISON" ou n = "RAISON_SOCIALE"
    retourner "DURAND | LEROY | MARTIN"
  cas n = "PRENOM"
    retourner "Julie | Marc | Inès"
  cas "VILLE" $ n
    retourner "Lyon | Paris | Marseille"
  fincas
retourner ""

procedure DEMO_PROFILS(s, source_id, serveur)
  locale l = {}
  pour chaque t dans DEMO_TABLES_DE(serveur)
    pour chaque c dans DEMO_COLS(t)
      locale n = majuscule(c.nom)
      locale d = entier(t.lignes * 0.6)
      faire cas
      cas c.pk
        d = t.lignes
      cas n = "STATUT" ou n = "SENS" ou n = "ACTIF" ou n = "CLOS" ou n = "COURANT" ou n = "CATEGORIE" ou n = "NIVEAU" ;
          ou n = "MODE_REGLEMENT" ou n = "TVA_CODE" ou n = "JOURNAL_CODE"
        d = min(t.lignes, 2 + #n % 4)
      cas "PAYS" $ n
        d = min(t.lignes, 38)
      cas "VILLE" $ n
        d = min(t.lignes, 6200)
      cas "DATE" $ n
        d = min(t.lignes, 4800)
      cas "EMAIL" $ n ou n = "IBAN" ou n = "NIR" ou "SIRET" $ n ou "CODE_CLIENT" $ n ou n = "CODCLI"
        d = entier(t.lignes * 0.97)
      fincas
      inserer(l, {source_id = source_id, serveur = serveur, base = t.base, sch = t.sch, table_nom = t.nom, colonne = c.nom, ;
                  distincts = d, nuls = sisinon(c.pk ou c.nn, 0, entier(t.lignes * ((#c.nom % 5) / 50))), ;
                  exemples = DEMO_EXEMPLES(c.nom, c.type)})
    suivant
  suivant
  INSERER_LIGNES(s, "ext_profils", SPEC_TABLE(s, "ext_profils"), l)
retourner

&&
&& Appels capturés (module 14) : simulés pour la démonstration
&&

procedure DEMO_CAPTURES(s)
  si RV(s, "select count(*) from captures where origine = 'demo'", nul) > 0
    retourner
  finsi
  locale l = {}
  locale noms = {"DUR%", "MART%", "LE%", "BERN%", nul}
  locale villes = {"Lyon", nul, "Paris", "Nantes", nul}
  locale tris = {"NOM", "VILLE", "CODE_CLIENT", "NOM", "DATE_CREATION"}
  pour i = 1 a 30
    locale k = (i % 5) + 1
    inserer(l, {id = i, quand = "2026-11-03 " + DEUX(i % 24) + ":" + DEUX((i * 7) % 60) + ":00", ;
                serveur = "SRV-ERP", base = "ERP", objet = "vente.SP_RECHERCHE_CLIENT", ;
                texte = "EXEC vente.SP_RECHERCHE_CLIENT @Nom = " + sisinon(noms[k] = nul, "NULL", "N'" + noms[k] + "'") + ;
                        ", @Ville = " + sisinon(villes[k] = nul, "NULL", "N'" + villes[k] + "'") + ", @Tri = N'" + tris[k] + "'", ;
                parametres = json({NOM = noms[k], VILLE = villes[k], TRI = tris[k]}), duree_ms = 4 + (i * 17) % 90, ;
                lignes = (i * 31) % 400, application = "ERP Client lourd", utilisateur = "ERP\\vente" + (i % 4), origine = "demo"})
  suivant
  pour i = 31 a 42
    locale t = sisinon(i % 3 = 0, "FACTURE_HIST", "FACTURE")
    inserer(l, {id = i, quand = "2026-11-02 1" + (i % 10) + ":3" + (i % 6) + ":00", serveur = "SRV-ERP", base = "ERP", ;
                objet = "vente.SP_RAPPORT_DYNAMIQUE", texte = "EXEC vente.SP_RAPPORT_DYNAMIQUE @Table = N'" + t + "', @Annee = " + (2020 + i % 6), ;
                parametres = json({TABLE = t, ANNEE = 2020 + i % 6}), duree_ms = 800 + i * 40, lignes = 30000 + i * 100, ;
                application = "Reporting", utilisateur = "ERP\\controle", origine = "demo"})
  suivant
  pour i = 43 a 50
    inserer(l, {id = i, quand = "2026-11-03 0" + (i % 10) + ":05:00", serveur = "SRV-ERP", base = "ERP", ;
                objet = "vente.SP_MAJ_STATUT_COMMANDE", texte = "EXEC vente.SP_MAJ_STATUT_COMMANDE @Id = " + (812000 + i) + ", @Statut = 'V'", ;
                parametres = json({ID = 812000 + i, STATUT = "V"}), duree_ms = 3, lignes = 1, application = "ERP Web", ;
                utilisateur = "ERP\\web", origine = "demo"})
  suivant
  INSERER_LIGNES(s, "captures", SPEC_TABLE(s, "captures"), l)
retourner
