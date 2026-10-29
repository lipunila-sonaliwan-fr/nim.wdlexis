&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : greffons de connexion, attachement, catalogue
&&
&& Un connecteur est un fichier connecteurs/<type>.json (à côté du programme, ou dans
&& le dossier « connecteurs » du projet pour ajouter les siens) :
&&   type, libelle, categorie, sigle, couleur
&&   mode       catalogue (ATTACH), fichiers (une vue par fichier), requete (fonctions)
&&   extension  extension DuckDB à charger (INSTALL / LOAD) ; installer : commande d'installation
&&   parametres {nom, libelle, defaut, secret, fichier, dossier}
&&   options    cases à cocher {nom, libelle, defaut}
&&   attacher   instructions SQL ; {param} est remplacé par sa valeur (apostrophes doublées),
&&              {alias} par le nom SQL de la connexion, {si_option:texte} par texte si l'option est cochée
&&   lecteur    mode fichiers : fonction de lecture ({chemin} : le fichier)
&&   version_min  version minimale de DuckDB (Quack : 2.0)


procedure CHARGER_CONNECTEURS
  globale connecteurs
  connecteurs = {}
  pour chaque base dans {systeme.dossierprogramme(), dossier}
    si base <> "" et base <> nul
      locale d = fichier.joindre(base, "connecteurs")
      si fichier.estdossier(d)
        pour chaque n dans fichier.liste(d, faux)
          si minuscule(fichier.extension(n)) = ".json"
            essayer
              locale k = dejson(fichier.lire(fichier.joindre(d, n)))
              connecteurs[majuscule(k.type)] = k
            capturer e
              JOURNAL("connecteur illisible " + n + " : " + e)
            finessayer
          finsi
        suivant
      finsi
    finsi
  suivant
retourner

fonction CONNECTEUR(type)
retourner connecteurs[majuscule(type)]

fonction TYPES_CONNECTEURS()
  && ordre d'affichage : bases puis fichiers, par libellé
  locale l = {}
  pour chaque k, v dans connecteurs
    inserer(l, v)
  suivant
  trier(l, @COMPARER_CONNECTEURS)
retourner l

fonction COMPARER_CONNECTEURS(a, b)
  si a.categorie <> b.categorie
    retourner a.categorie < b.categorie
  finsi
retourner a.libelle < b.libelle

&&
&& Noms SQL
&&

fonction ALIAS(c)
  && nom SQL de la connexion : minuscules, lettres, chiffres et _
  locale s = minuscule(rogner(c.nom))
  locale r = ""
  pour i = 1 a longueur(s)
    locale ch = souschaine(s, i, 1)
    si contient("abcdefghijklmnopqrstuvwxyz0123456789_", ch)
      r = r + ch
    sinonsi contient("àâä", ch)
      r = r + "a"
    sinonsi contient("éèêë", ch)
      r = r + "e"
    sinonsi contient("îï", ch)
      r = r + "i"
    sinonsi contient("ôö", ch)
      r = r + "o"
    sinonsi contient("ùûü", ch)
      r = r + "u"
    sinonsi ch = "ç"
      r = r + "c"
    sinon
      r = r + "_"
    finsi
  suivant
  si r = "" ou contient("0123456789", gauche(r, 1))
    r = "c_" + r
  finsi
retourner r

fonction IDENT(nom)
  && identifiant SQL entre guillemets si nécessaire
  locale simple = vrai
  pour i = 1 a longueur(nom)
    si non contient("abcdefghijklmnopqrstuvwxyz0123456789_", souschaine(nom, i, 1))
      simple = faux
    finsi
  suivant
  si simple et longueur(nom) > 0 et non contient("0123456789", gauche(nom, 1))
    retourner nom
  finsi
retourner car(34) + remplacertexte(nom, car(34), car(34) + car(34)) + car(34)

fonction LITTERAL(s)
retourner "'" + remplacertexte(chaine(s), "'", "''") + "'"

fonction NOM_QUALIFIE(alias, schema, objet, fichiers)
  si fichiers
    retourner "memory." + IDENT(alias) + "." + IDENT(objet)
  finsi
retourner IDENT(alias) + "." + IDENT(schema) + "." + IDENT(objet)

&&
&& Paramètres et gabarits
&&

fonction EST_SECRET(type, param)
  locale k = CONNECTEUR(type)
  si k = nul
    retourner faux
  finsi
  pour chaque p dans k.parametres
    si minuscule(p.nom) = minuscule(param) et p.secret = vrai
      retourner vrai
    finsi
  suivant
retourner faux

fonction A_DES_SECRETS(c)
  locale k = CONNECTEUR(c.type)
  si k = nul
    retourner faux
  finsi
  pour chaque p dans k.parametres
    si p.secret = vrai
      retourner vrai
    finsi
  suivant
retourner faux

fonction VALEUR_PARAM(c, nom)
  si EST_SECRET(c.type, nom)
    locale s = secrets[majuscule(c.nom)]
    si s <> nul et s[majuscule(nom)] <> nul
      retourner s[majuscule(nom)]
    finsi
  finsi
  locale v = nul
  si c.parametres <> nul
    v = c.parametres[majuscule(nom)]
  finsi
  si v = nul
    locale k = CONNECTEUR(c.type)
    pour chaque p dans k.parametres
      si minuscule(p.nom) = minuscule(nom)
        v = p.defaut
      finsi
    suivant
  finsi
retourner sisinon(v = nul, "", v)

fonction OPTION_COCHEE(c, nom)
  si c.options <> nul et c.options[majuscule(nom)] <> nul
    retourner c.options[majuscule(nom)] = vrai
  finsi
  locale k = CONNECTEUR(c.type)
  si k.options <> nul
    pour chaque o dans k.options
      si minuscule(o.nom) = minuscule(nom)
        retourner o.defaut = vrai
      finsi
    suivant
  finsi
retourner faux

fonction CHEMIN_PROJET(p)
  && chemins relatifs : dossier du projet
  si p = "" ou p = ":memory:" ou commencepar(p, "/") ou souschaine(p, 2, 1) = ":" ou commencepar(p, car(92))
    retourner p
  finsi
retourner fichier.joindre(dossier, p)

fonction GABARIT(modele, c)
  locale r = ""
  locale reste = modele
  tantque vrai
    locale a = position("{", reste)
    si a = 0
      r = r + reste
      sortir
    finsi
    locale b = position("}", reste)
    si b < a
      r = r + reste
      sortir
    finsi
    r = r + gauche(reste, a - 1)
    locale clef = souschaine(reste, a + 1, b - a - 1)
    reste = souschaine(reste, b + 1)
    si clef = "alias"
      r = r + IDENT(ALIAS(c))
    sinonsi commencepar(clef, "si_")
      locale dp = position(":", clef)
      si dp > 0 et OPTION_COCHEE(c, souschaine(clef, 4, dp - 4))
        r = r + souschaine(clef, dp + 1)
      finsi
    sinon
      locale v = VALEUR_PARAM(c, clef)
      si clef = "fichier" ou clef = "dossier"
        v = CHEMIN_PROJET(v)
      finsi
      r = r + remplacertexte(chaine(v), "'", "''")
    finsi
  fintantque
retourner r

&&
&& Attachement
&&

fonction VERSION_DUCKDB()
  locale v = valeursql("select version()")
  si commencepar(v, "v")
    v = souschaine(v, 2)
  finsi
retourner v

fonction NOMBRE_VERSION(s)
  && « 5-dev123 » -> 5 : chiffres de tête seulement
  locale r = ""
  pour i = 1 a longueur(s)
    locale ch = souschaine(s, i, 1)
    si non contient("0123456789", ch)
      sortir
    finsi
    r = r + ch
  suivant
retourner sisinon(r = "", 0, valeur(r))

fonction VERSION_SUFFISANTE(minimum)
  && compare majeur.mineur.correctif (1.5.5 <= 1.5.6-dev… <= 2.0)
  locale a = decouper(VERSION_DUCKDB(), ".")
  locale b = decouper(minimum, ".")
  pour i = 1 a 3
    locale x = sisinon(i <= #a, NOMBRE_VERSION(a[i]), 0)
    locale y = sisinon(i <= #b, NOMBRE_VERSION(b[i]), 0)
    si x > y
      retourner vrai
    sinonsi x < y
      retourner faux
    finsi
  suivant
retourner vrai

procedure CHARGER_EXTENSION(k)
  si k.extension = nul ou k.extension = ""
    retourner
  finsi
  essayer
    requete("LOAD " + k.extension)
  capturer e
    && pas encore installée : téléchargement depuis le dépôt DuckDB (réseau nécessaire) ;
    && à défaut, dépôt communautaire (extensions publiées hors du dépôt principal)
    essayer
      requete(sisinon(k.installer <> nul, k.installer, "INSTALL " + k.extension))
    capturer e2
      si k.installer <> nul
        erreur e2
      finsi
      requete("INSTALL " + k.extension + " FROM community")
    finessayer
    requete("LOAD " + k.extension)
  finessayer
retourner

fonction DEMANDER_SECRETS(c)
  locale k = CONNECTEUR(c.type)
  && saisie masquée ; « Mémoriser » : gardés chiffrés sur ce poste (hors du projet)
  locale memo = faux
  locale n = 0
  pour chaque p dans k.parametres
    si p.secret = vrai et VALEUR_PARAM(c, p.nom) = ""
      locale r = ui.demandersecret(p.libelle + " de la connexion « " + LIBELLE_CNX(c) + " » :", ;
                                   {memoriser = "Mémoriser sur ce poste (chiffré, hors du projet)", coche = memo, ;
                                    titre = "Connexion " + c.nom})
      si r = nul
        retourner faux
      finsi
      memo = r.memoriser
      si secrets[majuscule(c.nom)] = nul
        secrets[majuscule(c.nom)] = {}
      finsi
      secrets[majuscule(c.nom)][majuscule(p.nom)] = r.valeur
      n += 1
    finsi
  suivant
  si n > 0 et memo
    MEMORISER_SECRETS(c, vrai)
  finsi
retourner vrai

fonction SECRETS_CONNUS(c)
  && tous les paramètres secrets de c ont une valeur (saisie ou mémorisée)
  locale k = CONNECTEUR(c.type)
  si k = nul
    retourner faux
  finsi
  pour chaque p dans k.parametres
    si p.secret = vrai et VALEUR_PARAM(c, p.nom) = ""
      retourner faux
    finsi
  suivant
retourner vrai

fonction ATTACHER(c, interactif)
  && Attache la connexion au moteur et relit son catalogue ; renvoie {ok, message, ms}.
  locale k = CONNECTEUR(c.type)
  si k = nul
    retourner {ok = faux, message = "connecteur inconnu : " + c.type, ms = 0}
  finsi
  si k.version_min <> nul et non VERSION_SUFFISANTE(k.version_min)
    retourner {ok = faux, ms = 0, message = k.libelle + " exige DuckDB " + k.version_min + ;
               " ou plus récent (bibliothèque actuelle : " + VERSION_DUCKDB() + ")"}
  finsi
  si interactif et non DEMANDER_SECRETS(c)
    retourner {ok = faux, message = "connexion annulée", ms = 0}
  finsi
  locale alias = ALIAS(c)
  locale t0 = systeme.horloge()
  && suivie : au-delà de 15 s, la barre d'arrêt permet de l'interrompre
  locale tache = OPERATION_DEBUT("connexion " + sisinon(c.num = nul, c.nom, LIBELLE_CNX(c)), nul)
  essayer
    CHARGER_EXTENSION(k)
    DETACHER(c)
    si k.mode = "fichiers"
      requete("CREATE SCHEMA IF NOT EXISTS memory." + IDENT(alias))
      locale d = CHEMIN_PROJET(VALEUR_PARAM(c, "dossier"))
      locale motif = minuscule(VALEUR_PARAM(c, "motif"))
      locale ext = sisinon(commencepar(motif, "*"), souschaine(motif, 2), motif)
      locale n = 0
      pour chaque f dans fichier.liste(d, faux)
        si finitpar(minuscule(f), ext)
          locale vue = gauche(f, longueur(f) - longueur(fichier.extension(f)))
          locale lect = remplacertexte(k.lecteur, "{chemin}", remplacertexte(fichier.joindre(d, f), "'", "''"))
          requete("CREATE OR REPLACE VIEW memory." + IDENT(alias) + "." + IDENT(vue) + " AS SELECT * FROM " + lect)
          n += 1
        finsi
      suivant
      si n = 0
        JOURNAL(c.nom + " : aucun fichier « " + motif + " » dans " + d)
      finsi
    sinon
      pour chaque s dans k.attacher
        requete(GABARIT(s, c))
      suivant
    finsi
    attachees[minuscule(alias)] = vrai
    locale ms = arrondi((systeme.horloge() - t0) * 1000, 1)
    INTROSPECTER(c)
    OPERATION_FIN(tache)
    retourner {ok = vrai, message = "connectée en " + ms + " ms", ms = ms}
  capturer e
    OPERATION_FIN(tache)
    retourner {ok = faux, message = sisinon(tache.arret, "connexion interrompue par l'utilisateur", e), ms = 0}
  finessayer
retourner nul

procedure DETACHER(c)
  locale alias = ALIAS(c)
  locale k = CONNECTEUR(c.type)
  essayer
    si k <> nul et k.mode = "fichiers" ou k <> nul et k.mode = "requete"
      requete("DROP SCHEMA IF EXISTS memory." + IDENT(alias) + " CASCADE")
    sinon
      requete("DETACH DATABASE IF EXISTS " + IDENT(alias))
    finsi
  capturer e
  finessayer
  attachees[minuscule(alias)] = nul
retourner

fonction PING(c)
  && aller-retour minimal vers la connexion (en ms), nul en cas d'échec
  locale alias = ALIAS(c)
  locale k = CONNECTEUR(c.type)
  locale t0 = systeme.horloge()
  essayer
    si k.mode = "catalogue"
      requete("SELECT count(*) FROM duckdb_schemas() WHERE database_name = ?", alias)
      && une vraie lecture côté source
      locale t = valeursql("SELECT schema_name || '.' || table_name FROM duckdb_tables() WHERE database_name = ? LIMIT 1", alias)
      si t <> nul
        requete("SELECT 1 FROM " + IDENT(alias) + "." + t + " LIMIT 1")
      finsi
    sinon
      requete("SELECT 1")
    finsi
  capturer e
    retourner nul
  finessayer
retourner arrondi((systeme.horloge() - t0) * 1000, 2)

&&
&& Catalogue (introspection) et cache local
&&

fonction LISTE_SQL(s)
  && liste SQL lue par array_to_string(liste, chr(31))
  si s = nul ou s = ""
    retourner {}
  finsi
retourner decouper(s, car(31))

fonction CONDITION_CATALOGUE(c)
  locale k = CONNECTEUR(c.type)
  si k <> nul et k.mode <> "catalogue"
    retourner "database_name = 'memory' AND schema_name = " + LITTERAL(ALIAS(c))
  finsi
retourner "database_name = " + LITTERAL(ALIAS(c))

fonction SCHEMA_DE(cat, nom)
  pour chaque s dans cat.schemas
    si s.nom = nom
      retourner s
    finsi
  suivant
  locale s = {nom = nom, tables = {}, vues = {}, macros = {}}
  inserer(cat.schemas, s)
retourner s

fonction OBJET_DE(s, nom)
  pour chaque t dans s.tables
    si t.nom = nom
      retourner t
    finsi
  suivant
  pour chaque v dans s.vues
    si v.nom = nom
      retourner v
    finsi
  suivant
retourner nul

procedure INTROSPECTER(c)
  locale cond = CONDITION_CATALOGUE(c)
  locale cat = {nom = c.nom, alias = ALIAS(c), type = c.type, quand = maintenant(), schemas = {}}
  pour chaque r dans requete("SELECT schema_name FROM duckdb_schemas() WHERE " + cond + " AND NOT internal ORDER BY 1")
    SCHEMA_DE(cat, r.schema_name)
  suivant
  pour chaque r dans requete("SELECT schema_name, table_name, estimated_size, column_count, has_primary_key " + ;
                             "FROM duckdb_tables() WHERE " + cond + " ORDER BY 1, 2")
    inserer(SCHEMA_DE(cat, r.schema_name).tables, {nom = r.table_name, genre = "table", lignes = r.estimated_size, ;
            colonnes = {}, pk = {}, fk = {}, index = {}})
  suivant
  pour chaque r dans requete("SELECT schema_name, view_name, sql FROM duckdb_views() WHERE " + cond + ;
                             " AND NOT internal ORDER BY 1, 2")
    inserer(SCHEMA_DE(cat, r.schema_name).vues, {nom = r.view_name, genre = "vue", sql = r.sql, colonnes = {}})
  suivant
  pour chaque r dans requete("SELECT schema_name, table_name, column_name, data_type, is_nullable, column_default " + ;
                             "FROM duckdb_columns() WHERE " + cond + " ORDER BY schema_name, table_name, column_index")
    locale o = OBJET_DE(SCHEMA_DE(cat, r.schema_name), r.table_name)
    si o <> nul
      inserer(o.colonnes, {nom = r.column_name, type = r.data_type, nul = r.is_nullable, defaut = r.column_default})
    finsi
  suivant
  essayer
    pour chaque r dans requete("SELECT schema_name, table_name, constraint_type, array_to_string(constraint_column_names, chr(31)) AS cols, " + ;
                               "referenced_table, array_to_string(referenced_column_names, chr(31)) AS refs FROM duckdb_constraints() WHERE " + cond)
      locale o = OBJET_DE(SCHEMA_DE(cat, r.schema_name), r.table_name)
      si o <> nul et o.genre = "table"
        si r.constraint_type = "PRIMARY KEY"
          o.pk = LISTE_SQL(r.cols)
        sinonsi r.constraint_type = "FOREIGN KEY"
          inserer(o.fk, {colonnes = LISTE_SQL(r.cols), table = r.referenced_table, refs = LISTE_SQL(r.refs)})
        finsi
      finsi
    suivant
    pour chaque r dans requete("SELECT schema_name, table_name, index_name, sql FROM duckdb_indexes() WHERE " + cond)
      locale o = OBJET_DE(SCHEMA_DE(cat, r.schema_name), r.table_name)
      si o <> nul et o.genre = "table"
        inserer(o.index, {nom = r.index_name, sql = r.sql})
      finsi
    suivant
    pour chaque r dans requete("SELECT schema_name, function_name, function_type, array_to_string(parameters, ', ') AS parameters FROM duckdb_functions() " + ;
                               "WHERE " + cond + " AND NOT internal AND function_type IN ('macro', 'table_macro')")
      inserer(SCHEMA_DE(cat, r.schema_name).macros, {nom = r.function_name, genre = r.function_type, ;
              parametres = sisinon(r.parameters = nul, "", r.parameters)})
    suivant
  capturer e
    JOURNAL(c.nom + " : catalogue partiel (" + e + ")")
  finessayer
  catalogue[majuscule(c.nom)] = cat
  essayer
    fichier.ecrire(fichier.joindre(DOSSIER_CACHE(), "catalogue_" + c.nom + ".json"), json(cat))
  capturer e
  finessayer
retourner

fonction TOUS_LES_OBJETS()
  && liste à plat : {cnx, alias, schema, nom, genre, lignes, colonnes, objet, fichiers}
  locale l = {}
  pour chaque c dans projet.connexions
    locale cat = catalogue[majuscule(c.nom)]
    locale k = CONNECTEUR(c.type)
    si cat <> nul
      pour chaque s dans cat.schemas
        pour chaque t dans s.tables
          inserer(l, {cnx = c, alias = ALIAS(c), schema = s.nom, nom = t.nom, genre = "table", objet = t, ;
                      fichiers = k <> nul et k.mode <> "catalogue"})
        suivant
        pour chaque v dans s.vues
          inserer(l, {cnx = c, alias = ALIAS(c), schema = s.nom, nom = v.nom, genre = "vue", objet = v, ;
                      fichiers = k <> nul et k.mode <> "catalogue"})
        suivant
      suivant
    finsi
  suivant
retourner l

fonction QUALIFIE(o)
retourner NOM_QUALIFIE(o.alias, o.schema, o.nom, o.fichiers)

procedure NOMS_COMPLETION
  && noms proposés par la complétion SQL de l'éditeur
  locale n = {}
  pour chaque c dans projet.connexions
    inserer(n, ALIAS(c))
    locale cat = catalogue[majuscule(c.nom)]
    si cat <> nul
      pour chaque s dans cat.schemas
        inserer(n, ALIAS(c) + "." + s.nom)
      suivant
    finsi
  suivant
  pour chaque o dans TOUS_LES_OBJETS()
    inserer(n, o.nom)
    inserer(n, o.schema + "." + o.nom)
    pour chaque col dans o.objet.colonnes
      inserer(n, o.nom + "." + col.nom)
    suivant
  suivant
  ed:noms(n)
retourner

procedure RAFRAICHIR_TOUT
  locale nb = 0
  pour chaque c dans projet.connexions
    locale r = ATTACHER(c, vrai)
    si r.ok
      nb += 1
    sinon
      ERREUR(c.nom + " : " + r.message)
    finsi
  suivant
  REMPLIR_EXPLORATEUR()
  NOMS_COMPLETION()
  STATUT(nb + " connexion(s) relue(s)")
retourner
