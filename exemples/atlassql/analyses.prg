&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atlas SQL : moteurs d'analyse exécutés par les agents.
&&   CONSTRUIRE_DICTIONNAIRE   module 4 : objets et familles métier, nature des tables,
&&                             sensibilité / RGPD, descriptions, cardinalités
&&   CONSTRUIRE_TYPES          module 5 : colonnes similaires -> types métier réutilisables
&&   DETECTER_DUPLICATIONS     module 7 : instructions identiques ou voisines, jointures
&&                             récurrentes, règles dupliquées, indices, propositions
&&   ANALYSER_PERFORMANCES     module 10 : coûts, balayages, index manquants, jointures
&&                             coûteuses, filtrage tardif, curseurs ; corrections proposées
&&   ANALYSER_PATRIMOINE       module 16 : dette, couplage, cohésion, complexité,
&&                             maintenabilité, réutilisation ; classement des objets

&&
&& Vocabulaire métier (extensible : glossaire.json dans le dossier du projet)
&&

fonction GLOSSAIRE()
  globale glossaire_cache
  si glossaire_cache <> nul
    retourner glossaire_cache
  finsi
  locale g = {mots = { ;
    CLIENT = {"Client", "Commercial"}, CLI = {"Client", "Commercial"}, CONTACT = {"Contact", "Commercial"}, ;
    COMMANDE = {"Commande", "Commercial"}, CDE = {"Commande", "Commercial"}, LIGNE = {"Ligne", ""}, ;
    FACTURE = {"Facture", "Finance"}, FACT = {"Facture", "Finance"}, REGLEMENT = {"Règlement", "Finance"}, ;
    REMISE = {"Remise", "Commercial"}, ARTICLE = {"Article", "Logistique"}, ART = {"Article", "Logistique"}, ;
    STOCK = {"Stock", "Logistique"}, ENTREPOT = {"Entrepôt", "Logistique"}, MOUVEMENT = {"Mouvement de stock", "Logistique"}, ;
    EMPLOYE = {"Employé", "Ressources humaines"}, SALARIE = {"Employé", "Ressources humaines"}, CONGE = {"Congé", "Ressources humaines"}, ;
    PAIE = {"Paie", "Ressources humaines"}, ECRITURE = {"Écriture comptable", "Comptabilité"}, JOURNAL = {"Journal comptable", "Comptabilité"}, ;
    COMPTE = {"Compte", "Comptabilité"}, EXERCICE = {"Exercice", "Comptabilité"}, TIERS = {"Tiers", "Comptabilité"}, ;
    BALANCE = {"Balance", "Comptabilité"}, PAYS = {"Pays", "Référentiel"}, DEVISE = {"Devise", "Référentiel"}, ;
    TVA = {"TVA", "Référentiel"}, CODE_POSTAL = {"Code postal", "Référentiel"}, PARAMETRE = {"Paramètre", "Technique"}, ;
    LOG = {"Journal technique", "Technique"}, TRACE = {"Journal technique", "Technique"}, AUDIT = {"Audit", "Technique"}, ;
    DIM = {"Dimension", "Décisionnel"}, FAIT = {"Fait", "Décisionnel"}, VENTE = {"Vente", "Commercial"}, ;
    TEMPS = {"Temps", "Décisionnel"}, FOURNISSEUR = {"Fournisseur", "Achats"}, ACHAT = {"Achat", "Achats"}}, ;
    abreviations = {COD = "CODE", CLI = "CLIENT", CDE = "COMMANDE", ART = "ARTICLE", MT = "MONTANT", MNT = "MONTANT", ;
                    DT = "DATE", NUM = "NUMERO", NO = "NUMERO", LIB = "LIBELLE", QTE = "QUANTITE", QTY = "QUANTITE", ;
                    TEL = "TELEPHONE", MAIL = "EMAIL", CP = "CODE_POSTAL", ADR = "ADRESSE", FACT = "FACTURE", ;
                    FOUR = "FOURNISSEUR", FRN = "FOURNISSEUR", EMP = "EMPLOYE", ID = "ID", REF = "REFERENCE", ;
                    PU = "PRIX_UNITAIRE", RAISON = "RAISON_SOCIALE", DESC = "DESCRIPTION"}, ;
    roles = {"CODE", "ID", "NUMERO", "DATE", "MONTANT", "LIBELLE", "NOM", "PRENOM", "EMAIL", "TELEPHONE", "ADRESSE", ;
             "QUANTITE", "PRIX", "TAUX", "STATUT", "TYPE", "IBAN", "NIR", "SIRET"}}
  && glossaire du projet
  essayer
    locale p = fichier.joindre(dossier, "glossaire.json")
    si fichier.existe(p)
      locale j = dejson(fichier.lire(p))
      si j.mots <> nul
        pour chaque k, v dans j.mots
          g.mots[majuscule(k)] = v
        suivant
      finsi
      si j.abreviations <> nul
        pour chaque k, v dans j.abreviations
          g.abreviations[majuscule(k)] = v
        suivant
      finsi
    finsi
  capturer e
  finessayer
  glossaire_cache = g
retourner g

fonction SENSIBILITES()
  && motif de nom de colonne -> {catégorie RGPD, niveau, description}
retourner { ;
  {"NIR", "Identifiant national (n° de sécurité sociale)", "très élevée", "Numéro d'inscription au répertoire (NIR)"}, ;
  {"SECU", "Identifiant national (n° de sécurité sociale)", "très élevée", "Numéro de sécurité sociale"}, ;
  {"IBAN", "Données bancaires", "élevée", "Coordonnées bancaires (IBAN)"}, ;
  {"BIC", "Données bancaires", "élevée", "Code BIC de la banque"}, ;
  {"CARTE", "Données bancaires", "très élevée", "Numéro de carte"}, ;
  {"SALAIRE", "Données financières personnelles", "élevée", "Rémunération"}, ;
  {"MOTIF", "Donnée potentiellement de santé", "élevée", "Motif (peut révéler une donnée de santé)"}, ;
  {"NAISSANCE", "Identité", "moyenne", "Date de naissance"}, ;
  {"EMAIL", "Coordonnées", "moyenne", "Adresse électronique"}, ;
  {"MAIL", "Coordonnées", "moyenne", "Adresse électronique"}, ;
  {"TELEPHONE", "Coordonnées", "moyenne", "Numéro de téléphone"}, ;
  {"TEL", "Coordonnées", "moyenne", "Numéro de téléphone"}, ;
  {"ADRESSE", "Coordonnées", "moyenne", "Adresse postale"}, ;
  {"PRENOM", "Identité", "moyenne", "Prénom"}, ;
  {"NOM", "Identité", "faible", "Nom"}, ;
  {"MATRICULE", "Identifiant interne de personne", "faible", "Matricule"}, ;
  {"CODE_POSTAL", "Localisation", "faible", "Code postal"}, ;
  {"VILLE", "Localisation", "faible", "Ville"}}

fonction NIVEAU_RANG(n)
  faire cas
  cas n = "très élevée"
    retourner 4
  cas n = "élevée"
    retourner 3
  cas n = "moyenne"
    retourner 2
  cas n = "faible"
    retourner 1
  fincas
retourner 0

fonction RANG_NIVEAU(r)
retourner {"aucune", "faible", "moyenne", "élevée", "très élevée"}[r + 1]

fonction MOTS_NOM(nom)
  && « CODE_CLIENT » -> {CODE, CLIENT} ; « CodeClient » -> {CODE, CLIENT} ; « CODCLI » -> {CODE, CLIENT}
  locale g = GLOSSAIRE()
  locale brut = {}
  pour chaque p dans decouper(remplacertexte(remplacertexte(nom, "-", "_"), " ", "_"), "_")
    si p <> ""
      inserer(brut, majuscule(p))
    finsi
  suivant
  locale r = {}
  pour chaque p dans brut
    si g.abreviations[p] <> nul
      pour chaque q dans decouper(g.abreviations[p], "_")
        inserer(r, q)
      suivant
    sinonsi #p >= 6 et g.abreviations[gauche(p, 3)] <> nul et g.abreviations[souschaine(p, 4)] <> nul
      && mots collés de 3 + 3 lettres : CODCLI, NUMCDE…
      inserer(r, g.abreviations[gauche(p, 3)])
      inserer(r, g.abreviations[souschaine(p, 4)])
    sinon
      inserer(r, p)
    finsi
  suivant
retourner r

fonction CLE_TYPE(mots)
  && rôle d'abord (CODE, DATE, MONTANT…), puis les autres mots dans l'ordre alphabétique
  locale g = GLOSSAIRE()
  locale roles = {}
  locale autres = {}
  pour chaque m dans mots
    locale estrole = faux
    pour chaque r dans g.roles
      si r = m
        estrole = vrai
      finsi
    suivant
    si estrole
      inserer(roles, m)
    sinon
      inserer(autres, m)
    finsi
  suivant
  trier(autres)
retourner joindre(roles, "_") + sisinon(#roles > 0 et #autres > 0, "_", "") + joindre(autres, "_")

fonction LIBELLE_MOTS(mots)
  locale l = {CODE = "Code", ID = "Identifiant", NUMERO = "Numéro", DATE = "Date", MONTANT = "Montant", LIBELLE = "Libellé", ;
              NOM = "Nom", PRENOM = "Prénom", EMAIL = "Adresse électronique", TELEPHONE = "Téléphone", ADRESSE = "Adresse", ;
              QUANTITE = "Quantité", PRIX = "Prix", TAUX = "Taux", STATUT = "Statut", TYPE = "Type", HT = "hors taxes", ;
              TTC = "toutes taxes comprises", TVA = "de TVA", CREATION = "de création", MODIFICATION = "de modification", ;
              NAISSANCE = "de naissance", DEBUT = "de début", FIN = "de fin", ECHEANCE = "d'échéance", UNITAIRE = "unitaire", ;
              ACTIF = "Indicateur actif", CLOS = "Indicateur clos", SENS = "Sens", QTE = "Quantité", DISPO = "disponible", ;
              RESERVEE = "réservée", BRUT = "brut", POSTAL = "postal", VALEUR = "Valeur", CLE = "Clé", DEBIT = "Débit", ;
              CREDIT = "Crédit", PIECE = "Pièce", JOUR = "jour", ANNEE = "Année", MOIS = "Mois", MARGE = "Marge", ;
              SK = "clé technique (substitution)", COURANT = "Version courante", SEGMENT = "Segment", NIVEAU = "Niveau", ;
              MESSAGE = "Message", RAISON = "Raison", SOCIALE = "sociale", CATEGORIE = "Catégorie", REMISE = "Remise"}
  locale g = GLOSSAIRE()
  locale p = {}
  locale i = 0
  pour chaque m dans mots
    i += 1
    si l[m] <> nul
      inserer(p, sisinon(i = 1, l[m], minuscule(gauche(l[m], 1)) + souschaine(l[m], 2)))
    sinonsi g.mots[m] <> nul
      inserer(p, sisinon(i = 1, g.mots[m][1], "du " + minuscule(g.mots[m][1])))
    sinon
      inserer(p, sisinon(i = 1, gauche(m, 1) + minuscule(souschaine(m, 2)), minuscule(m)))
    finsi
  suivant
retourner joindre(p, " ")

procedure CONSTRUIRE_DICTIONNAIRE(s, t)
  locale g = GLOSSAIRE()
  RQ(s, "delete from dico_tables", nul)
  RQ(s, "delete from dico_colonnes", nul)
  RQ(s, "delete from diagnostics where module = 'dictionnaire'", nul)
  PROGRES(t, 0.05, "Lecture des tables…")
  locale tables_ = RQ(s, "select o.id, o.serveur, o.base, o.sch, o.nom, o.genre, coalesce(o.lignes, 0) as lignes, " + ;
    "(select count(*) from colonnes c where c.objet_id = o.id) as ncol, " + ;
    "(select count(*) from colonnes c where c.objet_id = o.id and (c.type_sql ilike '%date%' or c.type_sql ilike '%time%')) as ndate, " + ;
    "(select count(*) from refs_brutes r where lower(r.p1) = lower(o.nom) and r.nature in ('INSERT', 'UPDATE', 'DELETE', 'MERGE')) as ecritures " + ;
    "from objets o where o.genre in ('TABLE', 'VUE') order by o.id", nul)
  locale colonnes_ = RQ(s, "select objet_id, nom, type_sql, pk, identite, nullable, fk_vers, distincts, nuls, exemples, " + ;
    "(select coalesce(lignes, 0) from objets o where o.id = c.objet_id) as lignes from colonnes c order by objet_id, ordre", nul)
  locale parobj = {}
  pour chaque c dans colonnes_
    locale k = chaine(c.objet_id)
    si parobj[k] = nul
      parobj[k] = {}
    finsi
    inserer(parobj[k], c)
  suivant
  locale dt = {}
  locale dc = {}
  locale sens = SENSIBILITES()
  locale i = 0
  pour chaque tb dans tables_
    i += 1
    si i % 10 = 0
      PROGRES(t, 0.1 + 0.8 * i / #tables_, tb.nom)
    finsi
    && objet et famille métier
    locale mots = MOTS_NOM(tb.nom)
    locale objet_m = ""
    locale famille = ""
    pour chaque m dans mots
      si g.mots[m] <> nul et objet_m = ""
        objet_m = g.mots[m][1]
        famille = g.mots[m][2]
      finsi
    suivant
    si objet_m = ""
      objet_m = LIBELLE_MOTS(mots)
    finsi
    locale sch = majuscule(tb.sch)
    locale ub = majuscule(tb.base)
    si famille = "" et (ub = "REF" ou sch = "REF")
      famille = "Référentiel"
    finsi
    si sch = "DW" ou sch = "STG" ou ub = "DWH"
      famille = "Décisionnel"
    finsi
    si famille = ""
      famille = "Non classé"
    finsi
    && nature de la table
    locale un = majuscule(tb.nom)
    locale nature = "Transactionnel"
    faire cas
    cas tb.genre = "VUE"
      nature = "Vue"
    cas "HIST" $ un ou "ARCH" $ un ou "_OLD" $ un
      nature = "Historique"
    cas "LOG" $ un ou "AUDIT" $ un ou "TRACE" $ un
      nature = "Journal technique"
    cas commencepar(un, "TMP") ou commencepar(un, "STG") ou "IMPORT" $ un ou sch = "STG"
      nature = "Transit / technique"
    cas commencepar(un, "DIM_")
      nature = "Dimension (décisionnel)"
    cas commencepar(un, "FAIT_") ou commencepar(un, "FACT_")
      nature = "Fait (décisionnel)"
    cas famille = "Référentiel" ou (tb.lignes < 2000 et tb.ndate = 0) ou "PARAM" $ un
      nature = "Référentiel"
    cas tb.ndate = 0 et tb.ecritures = 0
      nature = "Référentiel"
    fincas
    && colonnes
    locale maxsens = 0
    locale rgpd = faux
    locale lescols = parobj[chaine(tb.id)]
    si lescols = nul
      lescols = {}
    finsi
    pour chaque c dans lescols
      locale cm = MOTS_NOM(c.nom)
      locale cn = majuscule(c.nom)
      locale desc = LIBELLE_MOTS(cm)
      si c.pk
        desc = desc + " (identifiant, clé primaire)"
      finsi
      si c.identite
        desc = desc + ", numéroté automatiquement"
      finsi
      si c.fk_vers <> nul et c.fk_vers <> ""
        desc = desc + " → " + c.fk_vers
      finsi
      && sensibilité : nom de colonne, puis valeurs observées
      locale cat = ""
      locale niv = ""
      pour chaque sx dans sens
        si cat = "" et (cn = sx[1] ou commencepar(cn, sx[1] + "_") ou finitpar(cn, "_" + sx[1]) ou ("_" + sx[1] + "_") $ cn)
          cat = sx[2]
          niv = sx[3]
        finsi
      suivant
      locale ex = sisinon(c.exemples = nul, "", c.exemples)
      si cat = "" et "@" $ ex et "." $ ex
        cat = "Coordonnées"
        niv = "moyenne"
      finsi
      si cat = "" et commencepar(ex, "FR76")
        cat = "Données bancaires"
        niv = "élevée"
      finsi
      && « NOM » d'une table sans personne (ARTICLE, ENTREPOT, PAYS…) n'est pas une donnée personnelle
      si (cat = "Identité" ou cat = "Localisation" ou cat = "Coordonnées") et (famille = "Référentiel" ou famille = "Logistique" ;
         ou famille = "Technique" ou famille = "Comptabilité" et non ("TIERS" $ un))
        si non ("EMAIL" $ cn ou "TEL" $ cn)
          cat = ""
          niv = ""
        finsi
      finsi
      && type métier
      locale cle = CLE_TYPE(cm)
      locale tm = "TYPE_" + cle
      && cardinalité
      locale card = ""
      si c.distincts <> nul et tb.lignes > 0
        locale ratio = c.distincts / max(1, tb.lignes)
        faire cas
        cas c.distincts <= 1
          card = "constante"
        cas c.distincts <= 10
          card = "faible (" + c.distincts + " valeurs : code, statut ou indicateur)"
        cas ratio >= 0.95
          card = "unique ou quasi unique"
        cas ratio >= 0.3
          card = "forte"
        autrement
          card = "moyenne (" + NB(c.distincts) + " valeurs)"
        fincas
      finsi
      si niv <> ""
        rgpd = vrai
        maxsens = max(maxsens, NIVEAU_RANG(niv))
      finsi
      inserer(dc, {objet_id = tb.id, colonne = c.nom, description = desc, type_metier = tm, ;
                   sensibilite = sisinon(niv = "", "aucune", niv), rgpd = niv <> "", categorie_rgpd = cat, cardinalite = card})
    suivant
    locale descr = objet_m + " — " + minuscule(nature) + sisinon(tb.lignes > 0, ", " + NB(tb.lignes) + " lignes", "") + ;
                   sisinon(rgpd, " ; contient des données personnelles", "")
    inserer(dt, {objet_id = tb.id, objet_metier = objet_m, famille = famille, nature = nature, ;
                 sensibilite = RANG_NIVEAU(maxsens), rgpd = rgpd, description = descr})
  suivant
  PROGRES(t, 0.92, "Enregistrement…")
  INSERER_LIGNES(s, "dico_tables", SPEC_TABLE(s, "dico_tables"), dt)
  INSERER_LIGNES(s, "dico_colonnes", SPEC_TABLE(s, "dico_colonnes"), dc)
  && constats RGPD : données sensibles lues par des vues ou exportées vers un autre serveur
  RQ(s, "insert into diagnostics select o.id, 'dictionnaire', 'RGPD_SENSIBLE', " + ;
        "case when d.sensibilite = 'très élevée' then 'critique' else 'important' end, " + ;
        "'Table à données personnelles (' || d.sensibilite || ') : ' || (select string_agg(c.colonne || ' [' || c.categorie_rgpd || ']', ', ') " + ;
        "from dico_colonnes c where c.objet_id = o.id and c.rgpd), " + ;
        "'Registre des traitements, durée de conservation, droits d''accès, pseudonymisation des copies (DWH, recette)', '', null " + ;
        "from dico_tables d join objets o on o.id = d.objet_id where d.rgpd and d.sensibilite in ('élevée', 'très élevée')", nul)
  t.message = chaine(#dt) + " tables/vues, " + #dc + " colonnes documentées"
retourner

procedure CONSTRUIRE_TYPES(s, t)
  PROGRES(t, 0.1, "Regroupement des colonnes similaires…")
  RQ(s, "delete from types_metier", nul)
  RQ(s, "delete from diagnostics where module = 'types'", nul)
  && un type métier = colonnes de même clé normalisée (CODE_CLIENT, CLIENT_CODE, CODCLI, CLI_CODE…)
  RQ(s, "insert into types_metier select d.type_metier, '', mode(c.type_sql), '', count(*), count(distinct c.objet_id), " + ;
        "string_agg(distinct c.nom, ', ' order by c.nom), string_agg(distinct c.type_sql, ', ' order by c.type_sql) " + ;
        "from dico_colonnes d join colonnes c on c.objet_id = d.objet_id and c.nom = d.colonne " + ;
        "group by d.type_metier having count(*) >= 2", nul)
  && libellés
  locale l = RQ(s, "select code from types_metier", nul)
  pour chaque x dans l
    locale mots = decouper(souschaine(x.code, 6), "_")
    RQ(s, "update types_metier set libelle = ? where code = ?", {LIBELLE_MOTS(mots), x.code})
  suivant
  && incohérences : même type métier, types SQL différents
  RQ(s, "insert into diagnostics select null, 'types', 'TYPE_INCOHERENT', 'important', " + ;
        "code || ' : types SQL différents (' || variantes || ') pour ' || colonnes, " + ;
        "'Créer un type utilisateur (CREATE TYPE ' || code || ' FROM ' || type_sql || ') et aligner les colonnes ; " + ;
        "les jointures entre types différents empêchent l''usage des index (conversions implicites)', '', null " + ;
        "from types_metier where variantes like '%,%'", nul)
  RQ(s, "insert into diagnostics select null, 'types', 'NOMMAGE_INCOHERENT', 'opportunite', " + ;
        "code || ' : ' || (length(colonnes) - length(replace(colonnes, ',', '')) + 1) || ' noms pour la même donnée (' || colonnes || ')', " + ;
        "'Normaliser le nommage (convention unique) ; les synonymes de noms masquent les dépendances', '', null " + ;
        "from types_metier where colonnes like '%,%'", nul)
  locale n = RV(s, "select count(*) from types_metier", nul)
  t.message = chaine(n) + " types métier"
retourner

&&
&& Duplications (module 7)
&&

procedure DETECTER_DUPLICATIONS(s, t)
  RQ(s, "delete from duplications", nul)
  RQ(s, "delete from diagnostics where module = 'duplications'", nul)
  PROGRES(t, 0.1, "Instructions identiques…")
  && 1. instructions identiques (après normalisation) dans au moins deux objets
  RQ(s, "insert into duplications select dense_rank() over (order by i.empreinte), 'identique', i.objet_id, i.num, i.ligne_debut, i.empreinte, 1.0, " + ;
        "left(i.texte, 300), 'Vue ou fonction mutualisée' from instructions i join (select empreinte from instructions " + ;
        "where length(normalise) > 60 and genre in ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'MERGE', 'WITH') group by empreinte " + ;
        "having count(distinct objet_id) >= 2) d on d.empreinte = i.empreinte", nul)
  locale base_groupe = RV(s, "select coalesce(max(groupe), 0) from duplications", nul)
  && 2. instructions voisines : similarité de Jaccard sur les trigrammes de jetons
  PROGRES(t, 0.35, "Instructions voisines…")
  RQ(s, "create or replace temp table tri as select objet_id, num, ligne_debut, texte, empreinte, genre, " + ;
        "list_distinct(list_transform(range(1, greatest(len(string_split(normalise, ' ')) - 1, 1)), " + ;
        "lambda k: string_split(normalise, ' ')[k] || ' ' || string_split(normalise, ' ')[k + 1] || ' ' || coalesce(string_split(normalise, ' ')[k + 2], ''))) as g " + ;
        "from instructions where length(normalise) > 80 and genre in ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'MERGE', 'WITH')", nul)
  RQ(s, "create or replace temp table paires as select a.objet_id as oa, a.num as na, a.ligne_debut as la, b.objet_id as ob, b.num as nb, " + ;
        "b.ligne_debut as lb, a.texte, len(list_intersect(a.g, b.g)) / (len(a.g) + len(b.g) - len(list_intersect(a.g, b.g)))::double as sim " + ;
        "from tri a join tri b on a.genre = b.genre and (a.objet_id < b.objet_id) and a.empreinte <> b.empreinte " + ;
        "and abs(len(a.g) - len(b.g)) <= greatest(len(a.g), len(b.g)) * 0.3 " + ;
        "where len(list_intersect(a.g, b.g)) / (len(a.g) + len(b.g) - len(list_intersect(a.g, b.g)))::double >= 0.72", nul)
  RQ(s, "insert into duplications select ? + row_number() over (), 'voisine', oa, na, la, '', sim, left(texte, 300), " + ;
        "'Factoriser : paramètre supplémentaire ou fonction table' from paires", {base_groupe})
  RQ(s, "insert into duplications select ? + row_number() over (), 'voisine', ob, nb, lb, '', sim, left(texte, 300), " + ;
        "'Factoriser : paramètre supplémentaire ou fonction table' from paires", {base_groupe})
  && 3. jointures récurrentes
  PROGRES(t, 0.6, "Jointures récurrentes…")
  base_groupe = RV(s, "select coalesce(max(groupe), 0) from duplications", nul)
  RQ(s, "insert into duplications select ? + dense_rank() over (order by j.t1, j.c1, j.t2, j.c2), 'jointure', j.objet_id, null, j.ligne, " + ;
        "j.t1 || '.' || j.c1 || '=' || j.t2 || '.' || j.c2, 1.0, j.t1 || ' ⋈ ' || j.t2 || ' ON ' || j.t1 || '.' || j.c1 || ' = ' || j.t2 || '.' || j.c2, " + ;
        "'Vue V_' || j.t1 || '_' || j.t2 || ' (jointure utilisée dans ' || r.n || ' objets)' " + ;
        "from jointures j join (select t1, c1, t2, c2, count(distinct objet_id) as n from jointures where t1 <> t2 group by all having n >= 3) r " + ;
        "using (t1, c1, t2, c2)", {base_groupe})
  && 4. règles dupliquées (CASE, filtres)
  PROGRES(t, 0.75, "Règles métier dupliquées…")
  base_groupe = RV(s, "select coalesce(max(groupe), 0) from duplications", nul)
  RQ(s, "insert into duplications select ? + dense_rank() over (order by g.empreinte), 'regle', g.objet_id, null, g.ligne, g.empreinte, 1.0, " + ;
        "left(g.texte, 300), case when g.genre = 'CASE' then 'Fonction scalaire ou colonne calculée (règle de calcul unique)' " + ;
        "else 'Vue filtrée ou fonction table (règle de sélection unique)' end " + ;
        "from regles g join (select empreinte from regles where length(normalise) > 40 group by empreinte " + ;
        "having count(distinct objet_id) >= 2) d using (empreinte)", {base_groupe})
  && indices
  PROGRES(t, 0.9, "Indices…")
  locale tot = RV(s, "select count(*) from instructions where genre in ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'MERGE', 'WITH')", nul)
  locale dup = RV(s, "select count(distinct objet_id || ':' || num) from duplications where genre in ('identique', 'voisine')", nul)
  locale pct = arrondi(100 * dup / max(1, tot), 1)
  RQ(s, "delete from meta where cle like 'dup_%'", nul)
  RQ(s, "insert into meta values ('dup_pct', ?), ('dup_groupes', ?), ('dup_instr', ?)", ;
     {chaine(pct), chaine(RV(s, "select count(distinct groupe) from duplications", nul)), chaine(dup)})
  && constats par objet
  RQ(s, "insert into diagnostics select objet_id, 'duplications', 'DUPLICATION', case when count(*) >= 3 then 'important' else 'opportunite' end, " + ;
        "count(*) || ' instruction(s) dupliquée(s) ou voisine(s) d''autres objets', " + ;
        "'Mutualiser (vue, fonction, procédure commune) : voir l''onglet Duplications', '', min(ligne) " + ;
        "from duplications where genre in ('identique', 'voisine') group by objet_id", nul)
  t.message = chaine(pct) + " % d'instructions dupliquées, " + RV(s, "select count(distinct groupe) from duplications", nul) + " groupes"
retourner

&&
&& Performances (module 10)
&&

procedure ANALYSER_PERFORMANCES(s, t)
  RQ(s, "delete from diagnostics where module = 'performances'", nul)
  PROGRES(t, 0.1, "Plans d'exécution…")
  && balayages de grandes tables
  RQ(s, "insert into diagnostics select q.objet_id, 'performances', 'TABLE_SCAN', " + ;
        "case when q.cout > 500 then 'critique' else 'important' end, " + ;
        "'Balayage (' || q.operateurs || ') : coût ' || round(q.cout, 1) || ', ' || q.executions || ' exécutions, CPU total ' || round(q.cpu_ms / 1000) || ' s', " + ;
        "'Index couvrant sur les colonnes filtrées ou jointes ; réécrire les prédicats non SARGables', '', null " + ;
        "from stats_requetes q where (q.operateurs ilike '%Table Scan%' or q.operateurs ilike '%Index Scan%') and q.cout > 20", nul)
  && jointures coûteuses (hachage avec forte mémoire)
  RQ(s, "insert into diagnostics select q.objet_id, 'performances', 'JOINTURE_COUTEUSE', 'important', " + ;
        "'Jointure par hachage coûteuse (coût ' || round(q.cout, 1) || ', mémoire ' || round(q.memoire_ko / 1024) || ' Mo par exécution)', " + ;
        "'Indexer les colonnes de jointure, filtrer avant de joindre, vérifier les statistiques (cardinalités estimées)', '', null " + ;
        "from stats_requetes q where q.operateurs ilike '%Hash Match%' and q.cout > 100", nul)
  && index manquants -> CREATE INDEX proposé
  PROGRES(t, 0.4, "Index manquants…")
  RQ(s, "insert into diagnostics select coalesce(i.objet_id, (select min(o.id) from objets o where o.serveur = i.serveur and o.base = i.base " + ;
        "and o.sch = i.sch and o.nom = i.table_nom)), 'performances', 'INDEX_MANQUANT', case when i.impact >= 80 then 'critique' else 'important' end, " + ;
        "'Index manquant sur ' || i.sch || '.' || i.table_nom || ' (gain estimé ' || round(i.impact) || ' %, ' || i.demandes || ' demandes)', " + ;
        "'Créer l''index proposé (vérifier les index existants et le coût en écriture)', " + ;
        "'CREATE NONCLUSTERED INDEX IX_' || i.table_nom || '_' || replace(replace(replace(trim(i.egalite || ' ' || i.inegalite), '[', ''), ']', ''), ', ', '_') " + ;
        "|| ' ON ' || i.base || '.' || i.sch || '.' || i.table_nom || ' (' || trim(both ', ' from i.egalite || case when i.egalite <> '' and i.inegalite <> '' then ', ' else '' end || i.inegalite) || ')' " + ;
        "|| case when i.inclus <> '' then ' INCLUDE (' || i.inclus || ')' else '' end || ';', null from index_manquants i", nul)
  && jointures sur des colonnes sans index (d'après les jointures du code et les index du catalogue)
  PROGRES(t, 0.6, "Jointures sans index…")
  RQ(s, "insert into diagnostics select min(j.objet_id), 'performances', 'JOINTURE_SANS_INDEX', 'opportunite', " + ;
        "'Jointure ' || j.t1 || '.' || j.c1 || ' = ' || j.t2 || '.' || j.c2 || ' : ' || j.t2 || '.' || j.c2 || ' n''est en tête d''aucun index (' || count(distinct j.objet_id) || ' objets)', " + ;
        "'CREATE INDEX IX_' || j.t2 || '_' || j.c2 || ' ON ' || j.t2 || ' (' || j.c2 || ')', '', min(j.ligne) " + ;
        "from jointures j join objets t on t.genre = 'TABLE' and upper(t.nom) = j.t2 and coalesce(t.lignes, 0) > 10000 " + ;
        "where not exists (select 1 from objets x where x.genre = 'INDEX' and x.parent_id = t.id " + ;
        "and upper(regexp_extract(x.definition, '\\(([A-Za-z0-9_]+)', 1)) = j.c2) " + ;
        "group by j.t1, j.c1, j.t2, j.c2", nul)
  && constats de l'analyse du code reclassés : filtrage tardif, curseurs
  PROGRES(t, 0.8, "Filtrage tardif, curseurs…")
  RQ(s, "insert into diagnostics select d.objet_id, 'performances', case when d.regle = 'CURSEUR' then 'CURSEUR_INUTILE' else 'FILTRAGE_TARDIF' end, " + ;
        "case when coalesce(q.executions, 0) * coalesce(q.cout, 0) > 10000 then 'critique' else d.niveau end, d.message || " + ;
        "case when q.executions is not null then ' — ' || q.executions || ' exécutions' else '' end, d.suggestion, '', d.ligne " + ;
        "from diagnostics d left join (select objet_id, sum(executions) as executions, max(cout) as cout from stats_requetes group by objet_id) q " + ;
        "on q.objet_id = d.objet_id where d.module = 'analyse' and d.regle in ('CURSEUR', 'FONCTION_FILTRE', 'LIKE_DEBUT', 'NOT_IN')", nul)
  locale n = RV(s, "select count(*) from diagnostics where module = 'performances'", nul)
  t.message = chaine(n) + " recommandations de performance"
retourner

fonction INDICATEURS_REQUETE(id)
  && module 10 : coût, lignes, temps, CPU, mémoire, E/S d'un objet
retourner RQ(nul, "select sum(executions) as executions, max(cout) as cout, sum(lignes) / greatest(sum(executions), 1) as lignes, " + ;
  "sum(duree_ms) / greatest(sum(executions), 1) as temps_ms, sum(cpu_ms) / greatest(sum(executions), 1) as cpu_ms, " + ;
  "max(memoire_ko) as memoire_ko, sum(lectures) / greatest(sum(executions), 1) as lectures, " + ;
  "sum(ecritures) / greatest(sum(executions), 1) as ecritures, max(operateurs) as operateurs from stats_requetes where objet_id = ?", {id})

&&
&& Patrimoine (module 16)
&&

procedure ANALYSER_PATRIMOINE(s, t)
  PROGRES(t, 0.1, "Couplage…")
  RQ(s, "delete from diagnostics where module = 'patrimoine'", nul)
  && objets sans analyse de code (tables, vues sans définition) : une ligne aussi
  RQ(s, "insert into metriques select o.id, 0, 0, 1, null, null, null, null, null, null, null, null from objets o " + ;
        "where o.genre in ('TABLE', 'VUE', 'PROCEDURE', 'FONCTION', 'DECLENCHEUR', 'JOB') and not exists (select 1 from metriques m where m.objet_id = o.id)", nul)
  RQ(s, "update metriques m set entrant = coalesce((select count(distinct d.de_id) from dependances d where d.vers_id = m.objet_id), 0), " + ;
        "sortant = coalesce((select count(distinct d.vers_id) from dependances d where d.de_id = m.objet_id and d.vers_id is not null), 0)", nul)
  PROGRES(t, 0.3, "Cohésion…")
  && cohésion : part des instructions qui portent sur la table principale de l'objet
  RQ(s, "update metriques m set cohesion = c.coh from (select objet_id, max(n) / greatest(sum(n), 1)::double as coh from " + ;
        "(select objet_id, tb, count(*) as n from (select i.objet_id, unnest(string_split(i.tables, ',')) as tb from instructions i " + ;
        "where i.tables <> '') group by all) " + ;
        "group by objet_id) c where c.objet_id = m.objet_id", nul)
  PROGRES(t, 0.5, "Dette et maintenabilité…")
  && dette (minutes) : constats pondérés par gravité
  RQ(s, "update metriques m set dette_min = coalesce((select sum(case niveau when 'critique' then 60 when 'important' then 20 " + ;
        "when 'opportunite' then 5 else 1 end) from diagnostics d where d.objet_id = m.objet_id), 0)", nul)
  && indice de maintenabilité (0-100), inspiré de Oman & Hagemeister : volume, complexité, taille
  RQ(s, "update metriques set maintenabilite = greatest(0, least(100, (171 - 5.2 * ln(greatest(nb_instructions, 1) * 12) " + ;
        "- 0.23 * complexite - 16.2 * ln(greatest(lignes_code, 1))) * 100 / 171)) where lignes_code > 0", nul)
  RQ(s, "update metriques set reutilisation = least(1, coalesce(entrant, 0) / 5.0)", nul)
  PROGRES(t, 0.7, "Classement…")
  RQ(s, "create or replace temp table classes as select o.id, " + ;
        "concat_ws(', ', " + ;
        "case when exists (select 1 from diagnostics d where d.objet_id = o.id and d.niveau = 'critique') " + ;
        "or exists (select 1 from dependances d join objets j on j.id = d.de_id where d.vers_id = o.id and j.genre = 'JOB') " + ;
        "or coalesce((select sum(executions) from stats_requetes q where q.objet_id = o.id), 0) > 100000 then 'Critique' end, " + ;
        "case when exists (select 1 from dico_tables t where t.objet_id = o.id and t.rgpd) " + ;
        "or exists (select 1 from dependances d join dico_tables t on t.objet_id = d.vers_id and t.rgpd where d.de_id = o.id) then 'Sensible' end, " + ;
        "case when (o.modifie < now() - interval 5 year or o.nom ilike '%old%' or o.nom ilike 'tmp%') " + ;
        "and coalesce(m.entrant, 0) = 0 then 'Obsolète' end, " + ;
        "case when coalesce(m.entrant, 0) = 0 and o.genre in ('TABLE', 'VUE', 'PROCEDURE', 'FONCTION') " + ;
        "and not exists (select 1 from stats_requetes q where q.objet_id = o.id and q.executions > 0) " + ;
        "and not exists (select 1 from dependances d where d.de_id = o.id and d.nature = 'FK') then 'Inutilisé' end, " + ;
        "case when m.complexite > 12 or m.dette_min >= 120 or m.maintenabilite < 45 " + ;
        "or exists (select 1 from duplications u where u.objet_id = o.id) then 'À refactoriser' end) as classe " + ;
        "from objets o join metriques m on m.objet_id = o.id", nul)
  RQ(s, "update metriques m set classe = c.classe from classes c where c.id = m.objet_id", nul)
  && score de risque (0-100) : complexité, couplage, dette, criticité
  RQ(s, "update metriques set score = least(100, coalesce(complexite, 0) * 2 + (coalesce(entrant, 0) + coalesce(sortant, 0)) * 1.5 " + ;
        "+ coalesce(dette_min, 0) / 6 + case when classe like '%Critique%' then 20 else 0 end)", nul)
  RQ(s, "insert into diagnostics select objet_id, 'patrimoine', 'COMPLEXITE', case when complexite > 20 then 'important' else 'opportunite' end, " + ;
        "'Complexité cyclomatique ' || complexite || ' (' || lignes_code || ' lignes, maintenabilité ' || round(maintenabilite) || '/100)', " + ;
        "'Découper en procédures plus petites (une par phase du synoptique)', '', null from metriques where complexite > 12", nul)
  RQ(s, "insert into diagnostics select objet_id, 'patrimoine', 'INUTILISE', 'opportunite', 'Objet sans utilisateur connu ni exécution', " + ;
        "'Vérifier (applications externes, rapports, ETL) puis archiver ou supprimer', '', null from metriques where classe like '%Inutilisé%'", nul)
  locale dette = RV(s, "select round(sum(dette_min) / 60, 1) from metriques", nul)
  RQ(s, "delete from meta where cle = 'dette_h'", nul)
  RQ(s, "insert into meta values ('dette_h', ?)", {chaine(dette)})
  t.message = "Dette technique estimée : " + dette + " h"
retourner
