&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atlas SQL : entrepôt local (une base DuckDB par projet, atlas.duckdb).
&&
&& Tout ce que l'atelier découvre, calcule ou capture est rangé ici :
&&   sources                 serveurs SQL Server déclarés (sans mot de passe)
&&   ext_*                   extractions brutes du catalogue, telles que reçues
&&   objets, colonnes        référentiel central (module 1)
&&   refs_brutes             références trouvées dans le code (analyseur)
&&   dependances             graphe orienté (modules 2, 3, 12, 15)
&&   instructions, ast       arbre syntaxique et synoptique (modules 6, 11)
&&   variables               paramètres, variables, tables temporaires, curseurs, CTE
&&   sql_dynamique           EXEC(...), sp_executesql, OPENQUERY (module 8)
&&   dico_tables, dico_colonnes, types_metier          (modules 4, 5)
&&   duplications            (module 7)
&&   stats_requetes, index_manquants, diagnostics      (module 10)
&&   metriques               (module 16)
&&   captures                appels interceptés (module 14)
&&   travaux                 file d'attente des agents
&&   favoris, journal        navigation, historique
&&
&& Les agents écrivent en parallèle, chacun sur sa session (sessionsql()) : les tables
&& n'ont pas de clé primaire (DuckDB refuserait des insertions concurrentes sur une
&& même clé) et chaque travail ne touche que ses propres lignes.

fonction SCHEMA_ENTREPOT()
retourner { ;
  "create sequence if not exists seq_objets start 1", ;
  "create sequence if not exists seq_travaux start 1", ;
  "create table if not exists meta(cle varchar, valeur varchar)", ;
  "create table if not exists sources(id integer, nom varchar, genre varchar, serveur varchar, port integer, " + ;
    "base varchar, auth varchar, utilisateur varchar, options varchar, actif boolean, limite integer, " + ;
    "dossier varchar, cree timestamp, analysee timestamp)", ;
  "create table if not exists ext_objets(source_id integer, serveur varchar, base varchar, sch varchar, nom varchar, " + ;
    "genre varchar, parent_nom varchar, proprietaire varchar, cree timestamp, modifie timestamp, lignes bigint, " + ;
    "taille_ko bigint, definition varchar, cible varchar, detail varchar)", ;
  "create table if not exists ext_colonnes(source_id integer, serveur varchar, base varchar, sch varchar, " + ;
    "table_nom varchar, nom varchar, ordre integer, type_sql varchar, longueur integer, prec integer, echelle integer, " + ;
    "nullable boolean, identite boolean, calculee boolean, defaut varchar, pk boolean, fk_vers varchar)", ;
  "create table if not exists ext_dependances(source_id integer, serveur varchar, base varchar, sch varchar, nom varchar, " + ;
    "ref_serveur varchar, ref_base varchar, ref_sch varchar, ref_nom varchar, nature varchar)", ;
  "create table if not exists ext_stats(source_id integer, serveur varchar, base varchar, sch varchar, nom varchar, " + ;
    "texte varchar, executions bigint, cpu_ms double, duree_ms double, lectures bigint, ecritures bigint, lignes bigint, " + ;
    "lignes_max bigint, memoire_ko bigint, derniere timestamp, plan varchar)", ;
  "create table if not exists ext_index_manquants(source_id integer, serveur varchar, base varchar, sch varchar, " + ;
    "table_nom varchar, egalite varchar, inegalite varchar, inclus varchar, impact double, demandes bigint)", ;
  "create table if not exists ext_jobs(source_id integer, serveur varchar, job varchar, etape integer, nom_etape varchar, " + ;
    "commande varchar, base varchar, heure_debut integer, duree_moy_s double, frequence varchar, actif boolean)", ;
  "create table if not exists ext_profils(source_id integer, serveur varchar, base varchar, sch varchar, table_nom varchar, " + ;
    "colonne varchar, distincts bigint, nuls bigint, exemples varchar)", ;
  "create table if not exists objets(id integer, cle varchar, serveur varchar, base varchar, sch varchar, nom varchar, " + ;
    "genre varchar, parent_id integer, parent_nom varchar, proprietaire varchar, cree timestamp, modifie timestamp, " + ;
    "lignes bigint, taille_ko bigint, definition varchar, cible varchar, detail varchar, source_id integer)", ;
  "create table if not exists colonnes(objet_id integer, serveur varchar, base varchar, sch varchar, table_nom varchar, " + ;
    "nom varchar, ordre integer, type_sql varchar, longueur integer, prec integer, echelle integer, nullable boolean, " + ;
    "identite boolean, calculee boolean, defaut varchar, pk boolean, fk_vers varchar, distincts bigint, nuls bigint, " + ;
    "exemples varchar)", ;
  "create table if not exists refs_brutes(objet_id integer, ref varchar, p1 varchar, p2 varchar, p3 varchar, p4 varchar, " + ;
    "nature varchar, ligne integer, distant varchar, sql varchar)", ;
  "create table if not exists dependances(de_id integer, vers_id integer, vers_nom varchar, nature varchar, ligne integer, " + ;
    "interbase boolean, interserveur boolean, origine varchar, frequence bigint, volume_moy double, volume_max double, " + ;
    "complexite integer)", ;
  "create table if not exists instructions(objet_id integer, num integer, ligne_debut integer, ligne_fin integer, " + ;
    "genre varchar, phase varchar, profondeur integer, texte varchar, normalise varchar, empreinte varchar, tables varchar)", ;
  "create table if not exists ast(objet_id integer, id integer, parent integer, genre varchar, libelle varchar, " + ;
    "phase varchar, ligne_debut integer, ligne_fin integer, ordre integer)", ;
  "create table if not exists variables(objet_id integer, nom varchar, genre varchar, type_sql varchar, ligne integer, " + ;
    "defaut varchar)", ;
  "create table if not exists sql_dynamique(objet_id integer, ligne integer, mode varchar, variable varchar, " + ;
    "sql_reconstitue varchar, parametres varchar, types varchar, empreinte varchar, valeurs varchar)", ;
  "create table if not exists dyn_variantes(empreinte varchar, objet_id integer, sql varchar, premiere timestamp, " + ;
    "derniere timestamp, occurrences bigint, origine varchar)", ;
  "create table if not exists stats_requetes(objet_id integer, serveur varchar, base varchar, texte varchar, " + ;
    "executions bigint, cpu_ms double, duree_ms double, lectures bigint, ecritures bigint, lignes bigint, " + ;
    "lignes_max bigint, memoire_ko bigint, derniere timestamp, plan varchar, cout double, operateurs varchar)", ;
  "create table if not exists index_manquants(objet_id integer, serveur varchar, base varchar, sch varchar, " + ;
    "table_nom varchar, egalite varchar, inegalite varchar, inclus varchar, impact double, demandes bigint)", ;
  "create table if not exists diagnostics(objet_id integer, module varchar, regle varchar, niveau varchar, " + ;
    "message varchar, suggestion varchar, correctif varchar, ligne integer)", ;
  "create table if not exists dico_tables(objet_id integer, objet_metier varchar, famille varchar, nature varchar, " + ;
    "sensibilite varchar, rgpd boolean, description varchar)", ;
  "create table if not exists dico_colonnes(objet_id integer, colonne varchar, description varchar, type_metier varchar, " + ;
    "sensibilite varchar, rgpd boolean, categorie_rgpd varchar, cardinalite varchar)", ;
  "create table if not exists types_metier(code varchar, libelle varchar, type_sql varchar, motif varchar, " + ;
    "occurrences bigint, utilisations bigint, colonnes varchar, variantes varchar)", ;
  "create table if not exists duplications(groupe integer, genre varchar, objet_id integer, num integer, ligne integer, " + ;
    "empreinte varchar, similarite double, extrait varchar, proposition varchar)", ;
  "create table if not exists metriques(objet_id integer, lignes_code integer, nb_instructions integer, complexite integer, " + ;
    "entrant integer, sortant integer, cohesion double, dette_min double, maintenabilite double, reutilisation double, " + ;
    "classe varchar, score double)", ;
  "create table if not exists captures(id integer, quand timestamp, serveur varchar, base varchar, objet varchar, " + ;
    "texte varchar, parametres varchar, duree_ms double, lignes bigint, application varchar, utilisateur varchar, " + ;
    "origine varchar)", ;
  "create table if not exists travaux(id integer, lot integer, genre varchar, libelle varchar, cible varchar, " + ;
    "source_id integer, priorite integer, etat varchar, agent integer, cree timestamp, debut timestamp, fin timestamp, " + ;
    "duree double, progression double, message varchar, essais integer)", ;
  "create table if not exists jointures(objet_id integer, ligne integer, t1 varchar, c1 varchar, t2 varchar, c2 varchar)", ;
  "create table if not exists regles(objet_id integer, ligne integer, genre varchar, texte varchar, normalise varchar, " + ;
    "empreinte varchar)", ;
  "create table if not exists favoris(cle varchar, libelle varchar, cree timestamp)", ;
  "create table if not exists journal(quand timestamp, niveau varchar, message varchar)", ;
  "create table if not exists espaces(nom varchar, contenu varchar, modifie timestamp)"}

procedure OUVRIR_ENTREPOT(dossier)
  && la base du programme : toutes les sessions des agents l'utilisent
  fichier.creerdossier(dossier)
  essayer
    ouvrirbase(fichier.joindre(dossier, "atlas.duckdb"))
  capturer e
    && base verrouillée (Atlas déjà ouvert sur ce projet) ou illisible
    paquet("interface").alerte("Impossible d'ouvrir l'entrepôt " + fichier.joindre(dossier, "atlas.duckdb") + car(10) + car(10) + e + ;
                               car(10) + car(10) + "Atlas SQL est peut-être déjà ouvert sur ce projet.", "stop", "Atlas SQL")
    erreur "entrepôt indisponible"
  finessayer
  pour chaque s dans SCHEMA_ENTREPOT()
    requete(s)
  suivant
  si valeursql("select count(*) from meta where cle = 'version'") = 0
    requete("insert into meta values ('version', '1')")
  finsi
retourner

&&
&& Requêtes : s = session d'un agent, ou nul (connexion du programme)
&&   RQ(s, sql, {p1, p2...})  liste des lignes
&&   RV(s, sql, {p1, p2...})  première valeur (ou nul)
&& (les paramètres sont toujours passés par « ? », jamais collés dans le texte)
&&

fonction RQ(s, sql, p)
  && requête paramétrée (0 à 15 paramètres) sur la connexion principale (s = nul) ou une session
  locale n = sisinon(p = nul, 0, #p)
  si n > 15
    erreur "RQ : 15 paramètres au plus (" + n + " fournis)"
  finsi
  si s = nul
    faire cas
    cas n = 0
      retourner requete(sql)
    cas n = 1
      retourner requete(sql, p[1])
    cas n = 2
      retourner requete(sql, p[1], p[2])
    cas n = 3
      retourner requete(sql, p[1], p[2], p[3])
    cas n = 4
      retourner requete(sql, p[1], p[2], p[3], p[4])
    cas n = 5
      retourner requete(sql, p[1], p[2], p[3], p[4], p[5])
    cas n = 6
      retourner requete(sql, p[1], p[2], p[3], p[4], p[5], p[6])
    cas n = 7
      retourner requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7])
    cas n = 8
      retourner requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8])
    cas n = 9
      retourner requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9])
    cas n = 10
      retourner requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10])
    cas n = 11
      retourner requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11])
    cas n = 12
      retourner requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12])
    cas n = 13
      retourner requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13])
    cas n = 14
      retourner requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14])
    cas n = 15
      retourner requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15])
    fincas
  finsi
  faire cas
  cas n = 0
    retourner s:requete(sql)
  cas n = 1
    retourner s:requete(sql, p[1])
  cas n = 2
    retourner s:requete(sql, p[1], p[2])
  cas n = 3
    retourner s:requete(sql, p[1], p[2], p[3])
  cas n = 4
    retourner s:requete(sql, p[1], p[2], p[3], p[4])
  cas n = 5
    retourner s:requete(sql, p[1], p[2], p[3], p[4], p[5])
  cas n = 6
    retourner s:requete(sql, p[1], p[2], p[3], p[4], p[5], p[6])
  cas n = 7
    retourner s:requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7])
  cas n = 8
    retourner s:requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8])
  cas n = 9
    retourner s:requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9])
  cas n = 10
    retourner s:requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10])
  cas n = 11
    retourner s:requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11])
  cas n = 12
    retourner s:requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12])
  cas n = 13
    retourner s:requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13])
  cas n = 14
    retourner s:requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14])
  cas n = 15
    retourner s:requete(sql, p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15])
  fincas
retourner nul

fonction RV(s, sql, p)
  locale r = RQ(s, sql, p)
  si #r = 0
    retourner nul
  finsi
  pour chaque k, v dans r[1]
    retourner v
  suivant
retourner nul

fonction SQLTEXTE(s)
  && littéral SQL (pour les rares textes qui ne peuvent pas être des paramètres :
  && arguments constants des fonctions de table de l'extension mssql)
retourner "'" + remplacertexte(chaine(s), "'", "''") + "'"

fonction CLE_OBJET(serveur, base, sch, nom)
retourner minuscule(serveur + "." + base + "." + sch + "." + nom)

procedure JOURNAL(niveau, message)
  essayer
    requete("insert into journal values (now(), ?, ?)", niveau, message)
  capturer e
  finessayer
  essayer
    TRACE(niveau, message)
  capturer e
  finessayer
retourner

&&
&& Projet : dossier contenant atlas.duckdb et atlas.json (réglages du projet)
&&

fonction FICHIER_REGLAGES()
retourner fichier.joindre(fichier.dossierperso(), ".atlassql.json")

fonction REGLAGES_DEFAUT()
retourner {sombre = vrai, agents = 4, parserveur = 3, projet = "", lot = 20, profilage = faux, ;
           ia_moteur = "regles", ia_modele = "", ia_url = "", ia_nom = "", ia_cle_env = "", ;
           sep_gauche = 0.22, panneau_masque = faux, sep_bas = 0.70, police = 13, vue = 1, espace = "Standard"}

fonction LIRE_REGLAGES()
  locale r = REGLAGES_DEFAUT()
  locale p = FICHIER_REGLAGES()
  si fichier.existe(p)
    essayer
      pour chaque k, v dans dejson(fichier.lire(p))
        r[majuscule(k)] = v
      suivant
    capturer e
    finessayer
  finsi
  r.agents = max(3, min(10, entier(r.agents)))
retourner r

procedure ECRIRE_REGLAGES
  essayer
    fichier.ecrire(FICHIER_REGLAGES(), json(reglages))
  capturer e
  finessayer
retourner

&&
&& Petits outils de texte
&&

fonction COURT(s, n)
  si s = nul
    retourner ""
  finsi
  s = chaine(s)
  si #s <= n
    retourner s
  finsi
retourner gauche(s, n - 1) + "…"

fonction NB(v)
  && nombre lisible : 12 345 / 1,2 M
  si v = nul
    retourner "-"
  finsi
  si v >= 1000000
    retourner chaine(arrondi(v / 1000000, 1)) + " M"
  finsi
  si v >= 10000
    retourner chaine(arrondi(v / 1000, 1)) + " k"
  finsi
retourner chaine(arrondi(v, 2))

fonction DUREE_TEXTE(s)
  si s = nul
    retourner ""
  finsi
  si s < 1
    retourner chaine(arrondi(s * 1000)) + " ms"
  finsi
  si s < 60
    retourner chaine(arrondi(s, 1)) + " s"
  finsi
retourner chaine(entier(s / 60)) + " min " + chaine(entier(s % 60)) + " s"

fonction MDCODE(s)
retourner "`" + remplacertexte(chaine(s), "`", "'") + "`"

fonction MDCELL(s)
  && cellule de tableau Markdown
  si s = nul
    retourner ""
  finsi
retourner remplacertexte(remplacertexte(chaine(s), "|", "/"), car(10), " ")

fonction LIBELLE_GENRE(g)
  locale t = {TABLE = "Table", VUE = "Vue", PROCEDURE = "Procédure", FONCTION = "Fonction", ;
              DECLENCHEUR = "Déclencheur", TYPE = "Type utilisateur", SYNONYME = "Synonyme", ;
              SERVEUR_LIE = "Serveur lié", JOB = "Job SQL Agent", CLR = "Assembly CLR", SEQUENCE = "Séquence", ;
              CONTRAINTE = "Contrainte", INDEX = "Index", STATISTIQUE = "Statistique", PARTITION = "Partition"}
  locale l = t[majuscule(sisinon(g = nul, "", g))]
retourner sisinon(l = nul, sisinon(g = nul, "", g), l)

fonction ICONE_GENRE(g)
  locale t = {TABLE = "▦", VUE = "◫", PROCEDURE = "ƒ", FONCTION = "λ", DECLENCHEUR = "⚡", TYPE = "τ", ;
              SYNONYME = "↪", SERVEUR_LIE = "⇄", JOB = "⏱", CLR = "◆", SEQUENCE = "#", CONTRAINTE = "🔒", ;
              INDEX = "⌕", STATISTIQUE = "σ", PARTITION = "▤"}
  locale l = t[majuscule(sisinon(g = nul, "", g))]
retourner sisinon(l = nul, "•", l)

fonction COULEUR_GENRE(g)
  locale t = {TABLE = "#2563EB", VUE = "#0891B2", PROCEDURE = "#7C3AED", FONCTION = "#9333EA", ;
              DECLENCHEUR = "#DB2777", TYPE = "#64748B", SYNONYME = "#0D9488", SERVEUR_LIE = "#EA580C", ;
              JOB = "#CA8A04", CLR = "#475569", SEQUENCE = "#64748B"}
  locale l = t[majuscule(sisinon(g = nul, "", g))]
retourner sisinon(l = nul, "#6B7280", l)

&&
&& Insertion en masse : une liste de fiches Lexis -> une requête (JSON déroulé par DuckDB)
&&   INSERER_LIGNES(s, "colonnes", {objet_id = "INTEGER", nom = "VARCHAR"…}, lignes)
&&

procedure INSERER_LIGNES(s, table_, spec, lignes)
  si lignes = nul ou #lignes = 0
    retourner
  finsi
  locale sq = "insert into " + table_ + " by name select unnest(from_json(?, " + SQLTEXTE("[" + json(spec) + "]") + ;
              "), recursive := true)"
  locale lot = {}
  pour chaque l dans lignes
    inserer(lot, l)
    si #lot >= 400
      RQ(s, sq, {json(lot)})
      lot = {}
    finsi
  suivant
  si #lot > 0
    RQ(s, sq, {json(lot)})
  finsi
retourner

fonction SPEC_TABLE(s, table_)
  && types des colonnes d'une table de l'entrepôt (pour INSERER)
  locale spec = {}
  pour chaque c dans RQ(s, "select column_name as n, data_type as t from information_schema.columns " + ;
                            "where table_name = ? order by ordinal_position", {table_})
    spec[majuscule(c.n)] = c.t
  suivant
retourner spec

fonction DEUX(n)
retourner sisinon(n < 10, "0" + chaine(entier(n)), chaine(entier(n)))

fonction CELLULES_MD(l)
  && découpe une ligne « | a | b | » en cellules
  locale p = decouper(l, "|")
  locale c = {}
  pour i = 2 a #p - 1
    inserer(c, rogner(p[i]))
  suivant
retourner c

fonction SEPARATEUR_MD(l)
  locale s = remplacertexte(remplacertexte(remplacertexte(remplacertexte(l, "|", ""), "-", ""), ":", ""), " ", "")
retourner s = "" et "-" $ l

fonction MD(texte)
  && le contrôle markdown ne rend pas les tableaux : on les convertit en listes lisibles
  si texte = nul
    retourner ""
  finsi
  locale lignes = decouper(chaine(texte), car(10))
  locale sortie = {}
  locale entetes = nul
  locale code_ = faux
  pour i = 1 a #lignes
    locale l = rogner(lignes[i])
    si commencepar(l, "```")
      code_ = non code_
      inserer(sortie, lignes[i])
    sinonsi code_
      inserer(sortie, lignes[i])
    sinonsi souschaine(l, 1, 1) = "|" et droite(l, 1) = "|" et #l > 1
      si SEPARATEUR_MD(l)
        && rien
      sinonsi i < #lignes et SEPARATEUR_MD(rogner(lignes[i + 1]))
        entetes = CELLULES_MD(l)
        si joindre(entetes, "") = "" ou #entetes = 2
          entetes = nul
        finsi
      sinon
        locale c = CELLULES_MD(l)
        si #c = 2
          inserer(sortie, "- **" + c[1] + "** : " + c[2])
        sinonsi #c > 0
          locale parts = {"**" + c[1] + "**"}
          pour j = 2 a #c
            si c[j] <> "" et c[j] <> "-"
              si entetes <> nul et j <= #entetes
                inserer(parts, entetes[j] + " : " + c[j])
              sinon
                inserer(parts, c[j])
              finsi
            finsi
          suivant
          inserer(sortie, "- " + joindre(parts, " · "))
        finsi
      finsi
    sinon
      entetes = sisinon(l = "", entetes, nul)
      inserer(sortie, lignes[i])
    finsi
  suivant
retourner joindre(sortie, car(10))
