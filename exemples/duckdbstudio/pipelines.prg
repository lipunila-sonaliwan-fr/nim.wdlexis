&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : concepteur de pipelines (lot 2).
&&
&& Un pipeline est un graphe d'étapes : sources (table, fichier, requête),
&& transformations (filtre, colonnes, calcul, agrégation, jointure, union, tri,
&& limite, dédoublonnage, SQL libre) et cibles (table, fichier, vue).
&&
&& Pipeline -> SQL : les étapes d'une même chaîne sont fusionnées en un bloc
&& SELECT ... FROM ... WHERE ... GROUP BY ... HAVING ... ORDER BY ... LIMIT, dans
&& l'ordre des clauses SQL ; une étape partagée ou qui ne peut pas prolonger le
&& bloc devient une expression de table commune (WITH) qui porte son nom.
&& SQL -> pipeline : l'arbre de DuckDB (sqlast.prg) est découpé de la même façon,
&& si bien que l'aller-retour redonne le même pipeline et le même SQL.
&&
&& projet.pipelines : liste de {nom, description, etapes = {{id, genre, titre,
&& params, x, y}}, liens = {{de, a}}}.

&&
&& Catalogue des étapes
&&

fonction GENRES_ETAPES()
retourner { ;
  {genre = "src_table", categorie = "Sources", libelle = "Table", entrees = 0, couleur = "#16A34A", ;
   params = {{nom = "table", libelle = "Table", defaut = ""}, {nom = "alias", libelle = "Alias", defaut = ""}, ;
             {nom = "colonnes", libelle = "Colonnes", defaut = "*"}}, ;
   aide = "Table ou vue d'une connexion (nom qualifié : demo.main.ventes)."}, ;
  {genre = "src_fichier", categorie = "Sources", libelle = "Fichier", entrees = 0, couleur = "#22C55E", ;
   params = {{nom = "chemin", libelle = "Chemin (motifs * acceptés)", defaut = "donnees.csv"}, ;
             {nom = "format", libelle = "Format", defaut = "auto", choix = "auto, csv, parquet, json, excel"}, ;
             {nom = "alias", libelle = "Alias", defaut = ""}}, ;
   aide = "Fichiers CSV, Parquet, JSON ou Excel, relatifs au dossier du projet."}, ;
  {genre = "src_sql", categorie = "Sources", libelle = "Requête SQL", entrees = 0, couleur = "#0D9488", ;
   params = {{nom = "requete", libelle = "Requête", defaut = "SELECT 1 AS x"}}, ;
   aide = "Requête quelconque (toutes les connexions attachées sont accessibles)."}, ;
  {genre = "filtre", categorie = "Transformations", libelle = "Filtre", entrees = 1, couleur = "#2563EB", ;
   params = {{nom = "condition", libelle = "Condition", defaut = "TRUE"}}, ;
   aide = "WHERE (ou HAVING après une agrégation)."}, ;
  {genre = "colonnes", categorie = "Transformations", libelle = "Colonnes", entrees = 1, couleur = "#2F5BE0", ;
   params = {{nom = "expressions", libelle = "Expressions", defaut = "*"}}, ;
   aide = "Liste SELECT : colonnes, expressions, alias (a, b * 2 AS c, * EXCLUDE (x))."}, ;
  {genre = "calcul", categorie = "Transformations", libelle = "Colonne calculée", entrees = 1, couleur = "#4F46E5", ;
   params = {{nom = "nom", libelle = "Nom", defaut = "nouvelle"}, {nom = "expression", libelle = "Expression", defaut = "1"}}, ;
   aide = "Ajoute une colonne : SELECT *, expression AS nom."}, ;
  {genre = "agregation", categorie = "Transformations", libelle = "Agrégation", entrees = 1, couleur = "#7C3AED", ;
   params = {{nom = "groupes", libelle = "Regrouper par", defaut = "ALL"}, ;
             {nom = "expressions", libelle = "Expressions", defaut = "count(*) AS nb"}}, ;
   aide = "GROUP BY : « ALL » regroupe par toutes les colonnes non agrégées ; vide : une seule ligne."}, ;
  {genre = "jointure", categorie = "Transformations", libelle = "Jointure", entrees = 9, couleur = "#EA580C", ;
   params = {{nom = "alias", libelle = "Alias des entrées", defaut = "g, d"}, {nom = "colonnes", libelle = "Colonnes", defaut = "*"}}, ;
   aide = "Relie deux entrées ou plus ; pour chaque entrée après la première : type (JOIN, LEFT JOIN, ASOF JOIN…) et condition (expression, ou USING (col))."}, ;
  {genre = "union", categorie = "Transformations", libelle = "Union", entrees = 9, couleur = "#C026D3", ;
   params = {{nom = "mode", libelle = "Opération", defaut = "UNION ALL BY NAME", ;
              choix = "UNION ALL BY NAME, UNION BY NAME, UNION ALL, UNION, EXCEPT, INTERSECT"}}, ;
   aide = "Empile les entrées (BY NAME : colonnes rapprochées par leur nom)."}, ;
  {genre = "tri", categorie = "Transformations", libelle = "Tri", entrees = 1, couleur = "#DC2626", ;
   params = {{nom = "ordre", libelle = "Ordre", defaut = "1"}}, aide = "ORDER BY (a DESC, b)."}, ;
  {genre = "limite", categorie = "Transformations", libelle = "Limite", entrees = 1, couleur = "#B91C1C", ;
   params = {{nom = "lignes", libelle = "Lignes", defaut = "100"}}, aide = "LIMIT."}, ;
  {genre = "dedoublonnage", categorie = "Transformations", libelle = "Dédoublonnage", entrees = 1, couleur = "#0891B2", ;
   params = {{nom = "colonnes", libelle = "Clés (vide : toutes)", defaut = ""}}, ;
   aide = "DISTINCT, ou DISTINCT ON (clés) : une ligne par clé."}, ;
  {genre = "sql", categorie = "Transformations", libelle = "SQL libre", entrees = 9, couleur = "#6D28D9", ;
   params = {{nom = "requete", libelle = "Requête", defaut = "SELECT * FROM {entree}"}}, ;
   aide = "Requête qui lit {entree} (ou {entree1}, {entree2}…)."}, ;
  {genre = "cible_table", categorie = "Cibles", libelle = "Table", entrees = 1, couleur = "#F59E0B", ;
   params = {{nom = "table", libelle = "Table", defaut = "resultat"}, ;
             {nom = "mode", libelle = "Mode", defaut = "remplacer", choix = "remplacer, ajouter"}}, ;
   aide = "CREATE OR REPLACE TABLE (remplacer) ou INSERT INTO … BY NAME (ajouter)."}, ;
  {genre = "cible_fichier", categorie = "Cibles", libelle = "Fichier", entrees = 1, couleur = "#D97706", ;
   params = {{nom = "chemin", libelle = "Chemin", defaut = "sortie.parquet"}, ;
             {nom = "format", libelle = "Format", defaut = "parquet", choix = "parquet, csv, json"}}, ;
   aide = "COPY (…) TO fichier."}, ;
  {genre = "cible_vue", categorie = "Cibles", libelle = "Vue", entrees = 1, couleur = "#CA8A04", ;
   params = {{nom = "vue", libelle = "Vue", defaut = "v_resultat"}}, aide = "CREATE OR REPLACE VIEW."}}

fonction GENRE_ETAPE(g)
  pour chaque x dans GENRES_ETAPES()
    si x.genre = g
      retourner x
    finsi
  suivant
retourner nul

fonction EST_CIBLE(g)
retourner commencepar(g, "cible_")

fonction EST_SOURCE(g)
retourner commencepar(g, "src_")

fonction EST_AUTONOME(g)
  && étapes qui forment toujours leur propre expression de table
retourner g = "src_sql" ou g = "union" ou g = "sql"

&&
&& Modèle
&&

fonction PIPELINE_VIDE(nom)
retourner {nom = nom, description = "", etapes = {}, liens = {}}

fonction ETAPE(p, id)
  pour chaque e dans p.etapes
    si e.id = id
      retourner e
    finsi
  suivant
retourner nul

fonction ENTREES(p, id)
  locale l = {}
  pour chaque k dans p.liens
    si k.a = id
      inserer(l, k.de)
    finsi
  suivant
retourner l

fonction SORTIES(p, id)
  locale l = {}
  pour chaque k dans p.liens
    si k.de = id
      inserer(l, k.a)
    finsi
  suivant
retourner l

fonction NOUVEL_ID(p, base)
  locale b = ALIAS({nom = sisinon(base = nul ou base = "", "etape", base)})
  si ETAPE(p, b) = nul
    retourner b
  finsi
  locale i = 2
  tantque ETAPE(p, b + "_" + i) <> nul
    i += 1
  fintantque
retourner b + "_" + i

fonction PARAM(e, nom)
  locale v = nul
  si e.params <> nul
    v = e.params[majuscule(nom)]
  finsi
  si v = nul
    locale g = GENRE_ETAPE(e.genre)
    si g <> nul
      pour chaque d dans g.params
        si d.nom = nom
          v = d.defaut
        finsi
      suivant
    finsi
  finsi
retourner sisinon(v = nul, "", chaine(v))

fonction AJOUTER_ETAPE(p, genre, titre, params)
  locale g = GENRE_ETAPE(genre)
  locale id = NOUVEL_ID(p, sisinon(titre = nul ou titre = "", g.libelle, titre))
  locale pp = {}
  si params <> nul
    pour chaque k, v dans params
      pp[majuscule(k)] = v
    suivant
  finsi
  inserer(p.etapes, {id = id, genre = genre, titre = sisinon(titre = nul ou titre = "", g.libelle, titre), params = pp})
retourner id

procedure RELIER(p, de, a)
  inserer(p.liens, {de = de, a = a})
retourner

procedure RENOMMER_ETAPE(p, ancien, nouveau)
  si ancien = nouveau ou ETAPE(p, nouveau) <> nul
    retourner
  finsi
  ETAPE(p, ancien).id = nouveau
  pour chaque k dans p.liens
    si k.de = ancien
      k.de = nouveau
    finsi
    si k.a = ancien
      k.a = nouveau
    finsi
  suivant
retourner

procedure SUPPRIMER_ETAPE(p, id)
  locale l = {}
  pour chaque e dans p.etapes
    si e.id <> id
      inserer(l, e)
    finsi
  suivant
  p.etapes = l
  locale k2 = {}
  pour chaque k dans p.liens
    si k.de <> id et k.a <> id
      inserer(k2, k)
    finsi
  suivant
  p.liens = k2
retourner

fonction ORDRE_ETAPES(p)
  && ordre topologique (les cycles éventuels sont ajoutés à la fin)
  locale fait = {}
  locale l = {}
  pour tour = 1 a #p.etapes + 1
    pour chaque e dans p.etapes
      si fait[e.id] = nul
        locale pret = vrai
        pour chaque i dans ENTREES(p, e.id)
          si fait[i] = nul
            pret = faux
          finsi
        suivant
        si pret ou tour > #p.etapes
          fait[e.id] = vrai
          inserer(l, e)
        finsi
      finsi
    suivant
  suivant
retourner l

&&
&& Pipeline -> SQL
&&

fonction LECTEUR_FICHIER(e)
  locale chemin = PARAM(e, "chemin")
  locale f = minuscule(PARAM(e, "format"))
  si f = "" ou f = "auto"
    locale x = minuscule(chemin)
    faire cas
    cas finitpar(x, ".parquet")
      f = "parquet"
    cas finitpar(x, ".json") ou finitpar(x, ".ndjson") ou finitpar(x, ".jsonl")
      f = "json"
    cas finitpar(x, ".xlsx")
      f = "excel"
    autrement
      f = "csv"
    fincas
  finsi
  si non commencepar(chemin, "/") et non contient(chemin, ":") et dossier <> ""
    chemin = fichier.joindre(dossier, chemin)
  finsi
  faire cas
  cas f = "parquet"
    retourner "read_parquet(" + LITTERAL(chemin) + ")"
  cas f = "json"
    retourner "read_json_auto(" + LITTERAL(chemin) + ")"
  cas f = "excel"
    retourner "read_xlsx(" + LITTERAL(chemin) + ")"
  fincas
retourner "read_csv_auto(" + LITTERAL(chemin) + ")"

fonction CTX_GEN(p)
  locale c = {p = p, ctes = {}, faits = {}, conso = {}}
  pour chaque k dans p.liens
    c.conso[k.de] = sisinon(c.conso[k.de] = nul, 0, c.conso[k.de]) + 1
  suivant
retourner c

fonction REF_FROM(ctx, id)
  && référence d'une étape dans une clause FROM : table ou fichier en ligne, sinon son CTE
  locale e = ETAPE(ctx.p, id)
  si e.genre = "src_table"
    retourner PARAM(e, "table")
  finsi
  si e.genre = "src_fichier"
    retourner LECTEUR_FICHIER(e)
  finsi
  CTE_DE(ctx, id)
retourner IDENT(id)

procedure CTE_DE(ctx, id)
  si ctx.faits[id] <> nul
    retourner
  finsi
  ctx.faits[id] = vrai
  locale s = SQL_SORTIE(ctx, id)
  inserer(ctx.ctes, {nom = id, sql = s})
retourner

fonction AVEC_ALIAS(ref, alias)
retourner ref + sisinon(alias = nul ou rogner(alias) = "", "", " AS " + rogner(alias))

fonction SQL_SORTIE(ctx, id)
  && SELECT qui produit la sortie d'une étape
  locale e = ETAPE(ctx.p, id)
  locale ins = ENTREES(ctx.p, id)
  faire cas
  cas e.genre = "src_sql"
    retourner rogner(PARAM(e, "requete"))
  cas e.genre = "union"
    si #ins = 0
      erreur "étape « " + e.titre + " » : aucune entrée"
    finsi
    locale l = {}
    pour chaque i dans ins
      inserer(l, "SELECT * FROM " + REF_FROM(ctx, i))
    suivant
    retourner joindre(l, car(10) + PARAM(e, "mode") + car(10))
  cas e.genre = "sql"
    locale s = PARAM(e, "requete")
    pour k = #ins a 1 pas -1
      s = remplacertexte(s, "{entree" + k + "}", REF_FROM(ctx, ins[k]))
    suivant
    si #ins > 0
      s = remplacertexte(s, "{entree}", REF_FROM(ctx, ins[1]))
    finsi
    retourner s
  cas EST_CIBLE(e.genre)
    retourner SQL_SORTIE(ctx, ins[1])
  fincas
retourner SQL_BLOC(BLOC_DE(ctx, id))

fonction BLOC_NEUF(from)
retourner {from = from, where = {}, groupes = nul, having = {}, select = "*", distinct = nul, ;
           ordre = "", limite = "", rang = 0, agrege = faux, calculs = faux}

fonction EXTENSIBLE(ctx, id)
  locale e = ETAPE(ctx.p, id)
  si e.genre = "src_table" ou e.genre = "src_fichier"
    retourner vrai
  finsi
  si EST_AUTONOME(e.genre) ou EST_CIBLE(e.genre)
    retourner faux
  finsi
retourner ctx.conso[id] = 1

fonction BLOC_DE(ctx, id)
  locale e = ETAPE(ctx.p, id)
  locale ins = ENTREES(ctx.p, id)
  si e.genre = "src_table" ou e.genre = "src_fichier"
    locale b = BLOC_NEUF(AVEC_ALIAS(REF_FROM(ctx, id), PARAM(e, "alias")))
    locale c = rogner(PARAM(e, "colonnes"))
    si c <> "" et c <> "*"
      b.select = c
      b.rang = 4
    finsi
    retourner b
  finsi
  si e.genre = "jointure"
    si #ins < 2
      erreur "jointure « " + e.titre + " » : deux entrées au moins sont nécessaires"
    finsi
    locale alias = decouper(PARAM(e, "alias"), ",")
    locale f = AVEC_ALIAS(REF_FROM(ctx, ins[1]), sisinon(#alias >= 1, alias[1], ""))
    pour k = 2 a #ins
      locale t = rogner(PARAM(e, "type" + k))
      si t = ""
        t = "JOIN"
      finsi
      locale cond = rogner(PARAM(e, "condition" + k))
      f = f + car(10) + "  " + t + " " + AVEC_ALIAS(REF_FROM(ctx, ins[k]), sisinon(#alias >= k, alias[k], ""))
      si cond <> ""
        f = f + sisinon(commencepar(majuscule(cond), "USING"), " " + cond, " ON " + cond)
      finsi
    suivant
    locale b = BLOC_NEUF(f)
    locale c = rogner(PARAM(e, "colonnes"))
    si c <> "" et c <> "*"
      b.select = c
      b.rang = 4
    finsi
    retourner b
  finsi
  si #ins = 0
    erreur "étape « " + e.titre + " » : aucune entrée"
  finsi
  locale i = ins[1]
  si EXTENSIBLE(ctx, i)
    locale b = BLOC_DE(ctx, i)
    si PROLONGER(b, e)
      retourner b
    finsi
  finsi
  locale b = BLOC_NEUF(REF_FROM(ctx, i))
  PROLONGER(b, e)
retourner b

fonction PROLONGER(b, e)
  && ajoute l'étape au bloc si l'ordre des clauses SQL le permet
  locale g = e.genre
  faire cas
  cas g = "filtre"
    si b.rang <= 1
      inserer(b.where, PARAM(e, "condition"))
      b.rang = 1
      retourner vrai
    finsi
    si b.agrege et b.rang <= 3
      inserer(b.having, PARAM(e, "condition"))
      b.rang = 3
      retourner vrai
    finsi
  cas g = "agregation"
    si b.rang <= 1
      b.groupes = PARAM(e, "groupes")
      b.select = PARAM(e, "expressions")
      b.agrege = vrai
      b.rang = 2
      retourner vrai
    finsi
  cas g = "colonnes"
    si b.rang <= 1
      b.select = PARAM(e, "expressions")
      b.rang = 4
      retourner vrai
    finsi
  cas g = "calcul"
    si b.rang <= 1 ou (b.rang = 4 et b.calculs)
      b.select = sisinon(b.calculs, b.select, "*") + ", " + PARAM(e, "expression") + " AS " + IDENT(PARAM(e, "nom"))
      b.calculs = vrai
      b.rang = 4
      retourner vrai
    finsi
  cas g = "dedoublonnage"
    si b.rang <= 4
      b.distinct = PARAM(e, "colonnes")
      b.rang = 5
      retourner vrai
    finsi
  cas g = "tri"
    si b.rang <= 5
      b.ordre = PARAM(e, "ordre")
      b.rang = 6
      retourner vrai
    finsi
  cas g = "limite"
    si b.rang <= 6
      b.limite = PARAM(e, "lignes")
      b.rang = 7
      retourner vrai
    finsi
  fincas
retourner faux

fonction SQL_BLOC(b)
  locale nl = car(10)
  locale s = "SELECT "
  si b.distinct <> nul
    s = s + sisinon(rogner(b.distinct) = "", "DISTINCT ", "DISTINCT ON (" + b.distinct + ") ")
  finsi
  s = s + b.select + nl + "FROM " + b.from
  si #b.where > 0
    s = s + nl + "WHERE " + JOINDRE_CONDITIONS(b.where)
  finsi
  si b.groupes <> nul et rogner(b.groupes) <> ""
    s = s + nl + "GROUP BY " + b.groupes
  finsi
  si #b.having > 0
    s = s + nl + "HAVING " + JOINDRE_CONDITIONS(b.having)
  finsi
  si b.ordre <> ""
    s = s + nl + "ORDER BY " + b.ordre
  finsi
  si b.limite <> ""
    s = s + nl + "LIMIT " + b.limite
  finsi
retourner s

fonction JOINDRE_CONDITIONS(l)
  si #l = 1
    retourner l[1]
  finsi
  locale r = {}
  pour chaque c dans l
    inserer(r, "(" + c + ")")
  suivant
retourner joindre(r, " AND ")

fonction AVEC_CTES(ctx, final)
  si #ctx.ctes = 0
    retourner final
  finsi
  locale l = {}
  pour chaque c dans ctx.ctes
    inserer(l, IDENT(c.nom) + " AS (" + car(10) + INDENTER(c.sql) + car(10) + ")")
  suivant
retourner "WITH " + joindre(l, "," + car(10)) + car(10) + final

fonction INDENTER(s)
retourner "  " + remplacertexte(s, car(10), car(10) + "  ")

fonction SQL_JUSQUA(p, id)
  && requête qui produit la sortie de l'étape (aperçu, validation)
  locale ctx = CTX_GEN(p)
  locale e = ETAPE(p, id)
  si EST_CIBLE(e.genre)
    id = ENTREES(p, id)[1]
  finsi
  locale final = SQL_SORTIE(ctx, id)
retourner AVEC_CTES(ctx, final)

fonction SQL_CIBLE(p, id)
  locale e = ETAPE(p, id)
  locale ins = ENTREES(p, id)
  si #ins = 0
    erreur "cible « " + e.titre + " » : aucune entrée"
  finsi
  locale corps = SQL_JUSQUA(p, id)
  locale nl = car(10)
  faire cas
  cas e.genre = "cible_table" et minuscule(PARAM(e, "mode")) = "ajouter"
    retourner "INSERT INTO " + PARAM(e, "table") + " BY NAME" + nl + corps + ";"
  cas e.genre = "cible_table"
    retourner "CREATE OR REPLACE TABLE " + PARAM(e, "table") + " AS" + nl + corps + ";"
  cas e.genre = "cible_fichier"
    locale chemin = PARAM(e, "chemin")
    si non commencepar(chemin, "/") et non contient(chemin, ":") et dossier <> ""
      chemin = fichier.joindre(dossier, chemin)
    finsi
    retourner "COPY (" + nl + INDENTER(corps) + nl + ") TO " + LITTERAL(chemin) + " (FORMAT " + minuscule(PARAM(e, "format")) + ");"
  cas e.genre = "cible_vue"
    retourner "CREATE OR REPLACE VIEW " + PARAM(e, "vue") + " AS" + nl + corps + ";"
  fincas
retourner corps + ";"

fonction SQL_PIPELINE(p)
  locale nl = car(10)
  locale out = {"-- Pipeline « " + p.nom + " » (DuckDB Studio)"}
  locale n = 0
  pour chaque e dans ORDRE_ETAPES(p)
    si EST_CIBLE(e.genre)
      inserer(out, "-- " + e.titre + nl + SQL_CIBLE(p, e.id))
      n += 1
    finsi
  suivant
  si n = 0
    && sans cible : une requête par extrémité
    pour chaque e dans ORDRE_ETAPES(p)
      si #SORTIES(p, e.id) = 0
        inserer(out, "-- " + e.titre + nl + SQL_JUSQUA(p, e.id) + ";")
      finsi
    suivant
  finsi
retourner joindre(out, nl + nl) + nl

&&
&& SQL -> pipeline
&&

fonction PIPELINE_DEPUIS_SQL(texte, nom)
  locale p = PIPELINE_VIDE(nom)
  locale ctx = {p = p, ctes = {}, messages = {}}
  pour chaque ins dans DECOUPER_SQL(texte)
    locale ic = INSTRUCTION_CIBLE(ins.sql)
    si ic = nul
      inserer(ctx.messages, "ignorée : " + RESUME(ins.sql))
    sinon
      locale sortie = CONVERTIR_REQUETE(ctx, ic.requete)
      si ic.cible <> nul et sortie <> nul
        locale c = ic.cible
        locale titre = sisinon(c.table <> nul, c.table, sisinon(c.vue <> nul, c.vue, fichier.nom(sisinon(c.chemin = nul, "", c.chemin))))
        locale params = {}
        pour chaque k, v dans c
          si k <> "GENRE"
            params[k] = v
          finsi
        suivant
        locale id = AJOUTER_ETAPE(p, c.genre, titre, params)
        RELIER(p, sortie, id)
      finsi
    finsi
  suivant
  p.messages = ctx.messages
retourner p

fonction CONVERTIR_REQUETE(ctx, q)
  locale a = AST(q)
  si a = nul ou non a.ok
    inserer(ctx.messages, "requête gardée telle quelle (" + sisinon(a = nul, "?", a.message) + ")")
    retourner AJOUTER_ETAPE(ctx.p, "src_sql", "requete", {requete = q})
  finsi
retourner CONVERTIR_NOEUD(ctx, q, a.arbre, "$.statements[0].node")

fonction CONVERTIR_NOEUD(ctx, q, n, ch)
  locale p = ctx.p
  && expressions de table communes : une chaîne d'étapes chacune, nommée comme le CTE
  si n["cte_map"] <> nul et n["cte_map"]["map"] <> nul
    locale m = n["cte_map"]["map"]
    pour i = 1 a #m
      locale cle = m[i]["key"]
      locale id = CONVERTIR_NOEUD(ctx, q, m[i]["value"]["query"]["node"], ;
                                  ch + ".cte_map.map[" + (i - 1) + "].value.query.node")
      si ETAPE(p, cle) = nul
        RENOMMER_ETAPE(p, id, cle)
        id = cle
      finsi
      ETAPE(p, id).titre = cle
      ctx.ctes[minuscule(cle)] = id
    suivant
  finsi
  locale cur = nul
  si n["type"] = "SET_OPERATION_NODE"
    locale l = CONVERTIR_NOEUD(ctx, q, n["left"], ch + ".left")
    locale r = CONVERTIR_NOEUD(ctx, q, n["right"], ch + ".right")
    locale t = n["setop_type"]
    locale mode = "UNION"
    faire cas
    cas t = "UNION_BY_NAME"
      mode = sisinon(n["setop_all"] = vrai, "UNION ALL BY NAME", "UNION BY NAME")
    cas t = "UNION"
      mode = sisinon(n["setop_all"] = vrai, "UNION ALL", "UNION")
    cas t = "EXCEPT"
      mode = sisinon(n["setop_all"] = vrai, "EXCEPT ALL", "EXCEPT")
    cas t = "INTERSECT"
      mode = sisinon(n["setop_all"] = vrai, "INTERSECT ALL", "INTERSECT")
    fincas
    cur = AJOUTER_ETAPE(p, "union", "union", {mode = mode})
    RELIER(p, l, cur)
    RELIER(p, r, cur)
  sinonsi n["type"] = "SELECT_NODE"
    locale ft = n["from_table"]
    si ft = nul ou ft["type"] = "EMPTY" ou n["qualify"] <> nul ou n["sample"] <> nul
      && hors du modèle en étapes : la requête est gardée entière
      retourner AJOUTER_ETAPE(p, "src_sql", "requete", {requete = REQUETE_SQL(q, ch)})
    finsi
    cur = CONVERTIR_FROM(ctx, q, ft, ch + ".from_table", vrai)
    si n["where_clause"] <> nul
      cur = CHAINER(p, cur, "filtre", "filtre", {condition = EXPR_SQL(q, ch + ".where_clause")})
    finsi
    locale sel = {}
    locale etoile = faux
    locale agr = faux
    locale liste = n["select_list"]
    pour i = 1 a #liste
      inserer(sel, EXPR_SQL(q, ch + ".select_list[" + (i - 1) + "]"))
      si CONTIENT_AGREGAT(liste[i])
        agr = vrai
      finsi
    suivant
    si #liste = 1 et liste[1]["class"] = "STAR" et sel[1] = "*"
      etoile = vrai
    finsi
    locale ge = n["group_expressions"]
    si ge <> nul et #ge > 0
      agr = vrai
    finsi
    si n["aggregate_handling"] = "FORCE_AGGREGATES"
      agr = vrai
    finsi
    si agr
      locale groupes = ""
      si n["aggregate_handling"] = "FORCE_AGGREGATES"
        groupes = "ALL"
      sinonsi ge <> nul et #ge > 0
        locale g = {}
        pour i = 1 a #ge
          inserer(g, EXPR_SQL(q, ch + ".group_expressions[" + (i - 1) + "]"))
        suivant
        groupes = joindre(g, ", ")
      finsi
      cur = CHAINER(p, cur, "agregation", "agregation", {groupes = groupes, expressions = joindre(sel, ", ")})
      si n["having"] <> nul
        cur = CHAINER(p, cur, "filtre", "having", {condition = EXPR_SQL(q, ch + ".having")})
      finsi
    sinonsi non etoile
      cur = CHAINER(p, cur, "colonnes", "colonnes", {expressions = joindre(sel, ", ")})
    finsi
  sinon
    retourner AJOUTER_ETAPE(p, "src_sql", "requete", {requete = REQUETE_SQL(q, ch)})
  finsi
  && modificateurs : DISTINCT, ORDER BY, LIMIT
  locale mods = n["modifiers"]
  si mods <> nul
    pour i = 1 a #mods
      locale md = mods[i]
      locale mc = ch + ".modifiers[" + (i - 1) + "]"
      faire cas
      cas md["type"] = "DISTINCT_MODIFIER"
        locale cles = {}
        locale cibles = md["distinct_on_targets"]
        si cibles <> nul
          pour k = 1 a #cibles
            inserer(cles, EXPR_SQL(q, mc + ".distinct_on_targets[" + (k - 1) + "]"))
          suivant
        finsi
        cur = CHAINER(p, cur, "dedoublonnage", "distinct", {colonnes = joindre(cles, ", ")})
      cas md["type"] = "ORDER_MODIFIER"
        locale o = {}
        pour k = 1 a #md["orders"]
          locale x = md["orders"][k]
          locale t = EXPR_SQL(q, mc + ".orders[" + (k - 1) + "].expression")
          si x["type"] = "DESCENDING"
            t = t + " DESC"
          finsi
          si x["null_order"] = "NULLS_FIRST"
            t = t + " NULLS FIRST"
          sinonsi x["null_order"] = "NULLS_LAST"
            t = t + " NULLS LAST"
          finsi
          inserer(o, t)
        suivant
        cur = CHAINER(p, cur, "tri", "tri", {ordre = joindre(o, ", ")})
      cas md["type"] = "LIMIT_MODIFIER" et md["limit"] <> nul
        cur = CHAINER(p, cur, "limite", "limite", {lignes = EXPR_SQL(q, mc + ".limit")})
      fincas
    suivant
  finsi
retourner cur

fonction CHAINER(p, de, genre, titre, params)
  locale id = AJOUTER_ETAPE(p, genre, titre, params)
  RELIER(p, de, id)
retourner id

fonction CONVERTIR_FROM(ctx, q, ft, ch, seul)
  && renvoie l'étape qui produit la clause FROM ; `seul` : hors jointure (l'alias va sur la source)
  locale p = ctx.p
  locale t = ft["type"]
  faire cas
  cas t = "BASE_TABLE"
    locale nomt = ft["table_name"]
    si (ft["schema_name"] = nul ou ft["schema_name"] = "") et ctx.ctes[minuscule(nomt)] <> nul
      retourner ctx.ctes[minuscule(nomt)]
    finsi
    locale params = {table = NOM_TABLE(ft)}
    si seul et ft["alias"] <> nul et ft["alias"] <> ""
      params.alias = ft["alias"]
    finsi
    retourner AJOUTER_ETAPE(p, "src_table", nomt, params)
  cas t = "TABLE_FUNCTION"
    locale f = ft["function"]
    locale nomf = minuscule(sisinon(f["function_name"] = nul, "", f["function_name"]))
    locale enf = f["children"]
    si commencepar(nomf, "read_") et enf <> nul et #enf >= 1 et enf[1]["class"] = "CONSTANT" et ;
       type(enf[1]["value"]["value"]) = "chaine" et #enf = 1
      locale chemin = enf[1]["value"]["value"]
      locale fmt = "auto"
      faire cas
      cas contient(nomf, "parquet")
        fmt = "parquet"
      cas contient(nomf, "json")
        fmt = "json"
      cas contient(nomf, "xlsx")
        fmt = "excel"
      cas contient(nomf, "csv")
        fmt = "csv"
      fincas
      locale params = {chemin = chemin, format = fmt}
      si seul et ft["alias"] <> nul et ft["alias"] <> ""
        params.alias = ft["alias"]
      finsi
      retourner AJOUTER_ETAPE(p, "src_fichier", fichier.nom(chemin), params)
    finsi
    retourner AJOUTER_ETAPE(p, "src_sql", nomf, {requete = "SELECT * FROM " + EXPR_SQL(q, ch + ".function")})
  cas t = "SUBQUERY"
    locale id = CONVERTIR_NOEUD(ctx, q, ft["subquery"]["node"], ch + ".subquery.node")
    si ft["alias"] <> nul et ft["alias"] <> "" et ETAPE(p, ft["alias"]) = nul
      RENOMMER_ETAPE(p, id, ft["alias"])
      id = ft["alias"]
    finsi
    retourner id
  cas t = "JOIN"
    locale feuilles = {}
    APLATIR_JOINTURE(ctx, q, ft, ch, feuilles)
    locale alias = {}
    locale params = {}
    pour k = 1 a #feuilles
      inserer(alias, feuilles[k].alias)
      si k > 1
        params["TYPE" + k] = feuilles[k].type
        params["CONDITION" + k] = feuilles[k].condition
      finsi
    suivant
    params.alias = joindre(alias, ", ")
    locale j = AJOUTER_ETAPE(p, "jointure", "jointure", params)
    pour chaque fe dans feuilles
      RELIER(p, fe.id, j)
    suivant
    retourner j
  fincas
retourner AJOUTER_ETAPE(p, "src_sql", "source", {requete = "SELECT * FROM " + FROM_SQL(q, ch)})

procedure APLATIR_JOINTURE(ctx, q, ft, ch, feuilles)
  && jointure « à gauche » : a JOIN b ON ... JOIN c ON ... -> feuilles a, b, c
  si ft["left"]["type"] = "JOIN"
    APLATIR_JOINTURE(ctx, q, ft["left"], ch + ".left", feuilles)
  sinon
    inserer(feuilles, FEUILLE(ctx, q, ft["left"], ch + ".left", #feuilles + 1))
  finsi
  locale f = FEUILLE(ctx, q, ft["right"], ch + ".right", #feuilles + 1)
  f.type = TEXTE_JOINTURE(ft["join_type"], ft["ref_type"])
  locale u = ft["using_columns"]
  si u <> nul et #u > 0
    locale l = {}
    pour chaque c dans u
      inserer(l, IDENT(c))
    suivant
    f.condition = "USING (" + joindre(l, ", ") + ")"
  sinonsi ft["condition"] <> nul
    f.condition = EXPR_SQL(q, ch + ".condition")
  sinon
    f.condition = ""
  finsi
  inserer(feuilles, f)
retourner

fonction FEUILLE(ctx, q, ft, ch, rang)
  locale id = CONVERTIR_FROM(ctx, q, ft, ch, faux)
  locale alias = sisinon(ft["alias"] = nul, "", ft["alias"])
  si alias = "" et ft["type"] = "BASE_TABLE"
    alias = ft["table_name"]
  finsi
  si alias = ""
    alias = id
  finsi
retourner {id = id, alias = alias, type = "", condition = ""}

fonction TEXTE_JOINTURE(jt, rt)
  locale t = "JOIN"
  faire cas
  cas jt = "LEFT"
    t = "LEFT JOIN"
  cas jt = "RIGHT"
    t = "RIGHT JOIN"
  cas jt = "OUTER"
    t = "FULL JOIN"
  cas jt = "SEMI"
    t = "SEMI JOIN"
  cas jt = "ANTI"
    t = "ANTI JOIN"
  fincas
  faire cas
  cas rt = "CROSS"
    retourner "CROSS JOIN"
  cas rt = "ASOF"
    retourner "ASOF " + t
  cas rt = "NATURAL"
    retourner "NATURAL " + t
  cas rt = "POSITIONAL"
    retourner "POSITIONAL JOIN"
  fincas
retourner t

&&
&& Interface
&&

procedure CONSTRUIRE_PIPELINES(page)
  globale pipe
  pipe = {courant = nul, sel = nul, colonnes = {}, erreurs = {}}
  locale haut = page:ajouter(ui.rangee())
  haut.ancrage = "haut"
  pipe.choix = haut:ajouter(ui.combo())
  pipe.choix.largeurfixe = 160
  pipe.choix.surselection = @PIPE_CHOISIR
  OUTIL(haut, "Nouveau", @PIPE_NOUVEAU, "Nouveau pipeline vide")
  OUTIL(haut, "SQL → pipeline", @PIPE_DEPUIS_EDITEUR, "Construit un pipeline à partir du script (ou de la sélection) de l'éditeur")
  OUTIL(haut, "Pipeline → SQL", @PIPE_VERS_EDITEUR, "Écrit le SQL du pipeline dans une nouvelle requête")
  OUTIL(haut, "Valider", @PIPE_VALIDER, "Colonnes de chaque étape (DESCRIBE) et erreurs")
  OUTIL(haut, "Aperçu", @PIPE_APERCU, "100 premières lignes de l'étape sélectionnée")
  OUTIL(haut, "Exécuter", @PIPE_EXECUTER, "Exécute les cibles du pipeline")
  OUTIL(haut, "Disposer", @PIPE_DISPOSER, "Disposition automatique")
  OUTIL(haut, "✕", @PIPE_SUPPRIMER, "Supprime le pipeline")
  locale sp = page:ajouter(ui.separateur{vertical = vrai, position = 0.70})
  sp.ancrage = "centre"
  locale gauche_ = sp:ajouter(ui.separateur{vertical = vrai, position = 0.14})
  pipe.palette = gauche_:ajouter(ui.arbre())
  pipe.palette.surdoubleclic = @PIPE_PALETTE
  pipe.palette.infobulle = "Double-cliquez une étape pour l'ajouter (reliée à l'étape sélectionnée)"
  pour chaque g dans GENRES_ETAPES()
    pipe.palette:ajouter({g.categorie, g.libelle})
  suivant
  pour chaque c dans {"Sources", "Transformations", "Cibles"}
    pipe.palette:deplier(c)
  suivant
  pipe.dia = gauche_:ajouter(ui.diagramme{modifiable = vrai, direction = "droite"})
  pipe.dia.surselection = @PIPE_SELECTION
  pipe.dia.surchangement = @PIPE_ACTION
  locale droite_ = sp:ajouter(ui.separateur{vertical = faux, position = 0.55})
  locale insp = droite_:ajouter(ui.colonne())
  pipe.genre = insp:ajouter(ui.etiquette("Sélectionnez une étape"))
  locale r = insp:ajouter(ui.rangee())
  pipe.titre = r:ajouter(ui.saisie{indication = "titre de l'étape"})
  pipe.titre.poids = 1
  locale ba = r:ajouter(ui.bouton("Appliquer"))
  ba.surclic = @PIPE_APPLIQUER
  pipe.zone = insp:ajouter(ui.panneau{disposition = "bordure", defilement = "masque"})
  pipe.zone.poids = 1
  pipe.grille = nul
  pipe.fiche = droite_:ajouter(ui.markdown("Créez un pipeline (Nouveau), ou construisez-le à partir d'un script SQL (SQL → pipeline)."))
  PIPE_GRILLE(nul)
retourner

procedure REMPLIR_PIPELINES
  locale nom = sisinon(pipe.courant = nul, "", pipe.courant.nom)
  pipe.choix:vider()
  locale k = 0
  pour i = 1 a #projet.pipelines
    pipe.choix:ajouter(projet.pipelines[i].nom)
    si projet.pipelines[i].nom = nom
      k = i
    finsi
  suivant
  si k = 0 et #projet.pipelines > 0
    k = 1
  finsi
  si k > 0
    pipe.choix:selectionner(k)
    pipe.courant = projet.pipelines[k]
  sinon
    pipe.courant = nul
  finsi
  AFFICHER_PIPELINE(faux)
retourner

procedure PIPE_CHOISIR(ev)
  locale i = pipe.choix:selection()
  si i >= 1 et i <= #projet.pipelines
    pipe.courant = projet.pipelines[i]
    pipe.sel = nul
    pipe.colonnes = {}
    pipe.erreurs = {}
    AFFICHER_PIPELINE(faux)
  finsi
retourner

fonction PIPELINE_NOMME(nom)
  pour chaque p dans projet.pipelines
    si minuscule(p.nom) = minuscule(nom)
      retourner p
    finsi
  suivant
retourner nul

fonction NOM_PIPELINE_LIBRE(base)
  locale n = base
  locale i = 2
  tantque PIPELINE_NOMME(n) <> nul
    n = base + " " + i
    i += 1
  fintantque
retourner n

procedure PIPE_NOUVEAU(ev)
  locale nom = ui.demander("Nom du pipeline :", NOM_PIPELINE_LIBRE("pipeline"))
  si nom = nul ou rogner(nom) = ""
    retourner
  finsi
  si PIPELINE_NOMME(nom) <> nul
    STATUT("Un pipeline « " + nom + " » existe déjà.")
    retourner
  finsi
  locale p = PIPELINE_VIDE(rogner(nom))
  inserer(projet.pipelines, p)
  pipe.courant = p
  REMPLIR_PIPELINES()
  ENREGISTRER_PROJET()
  vues.valeur = INDEX_VUE("Pipelines")
retourner

procedure PIPE_SUPPRIMER(ev)
  si pipe.courant = nul
    retourner
  finsi
  si non ui.confirmer("Supprimer le pipeline « " + pipe.courant.nom + " » ?")
    retourner
  finsi
  locale l = {}
  pour chaque p dans projet.pipelines
    si p <> pipe.courant
      inserer(l, p)
    finsi
  suivant
  projet.pipelines = l
  pipe.courant = nul
  REMPLIR_PIPELINES()
  ENREGISTRER_PROJET()
retourner

fonction RESUME_ETAPE(p, e)
  && lignes affichées dans le nœud
  locale l = {}
  locale g = GENRE_ETAPE(e.genre)
  si e.genre = "jointure"
    locale ins = ENTREES(p, e.id)
    locale alias = decouper(PARAM(e, "alias"), ",")
    pour k = 1 a #ins
      locale txt = sisinon(k = 1, "de", rogner(PARAM(e, "type" + k)))
      inserer(l, {texte = sisinon(k <= #alias, rogner(alias[k]), ins[k]), detail = gauche(txt + " " + PARAM(e, "condition" + k), 34)})
    suivant
  sinon
    pour chaque d dans g.params
      locale v = PARAM(e, d.nom)
      si v <> "" et v <> d.defaut ou d.nom = "table" ou d.nom = "condition" ou d.nom = "expressions"
        inserer(l, {texte = d.nom, detail = gauche(remplacertexte(v, car(10), " "), 34)})
      finsi
    suivant
  finsi
  locale cols = pipe.colonnes[e.id]
  si cols <> nul
    inserer(l, {texte = "→ " + #cols + " colonne(s)", detail = gauche(joindre(cols, ", "), 34), marque = ""})
  finsi
retourner l

procedure AFFICHER_PIPELINE(disposer)
  locale d = pipe.dia
  d:vider()
  locale p = pipe.courant
  si p = nul
    pipe.fiche.valeur = "Aucun pipeline : **Nouveau**, ou **SQL → pipeline** depuis un script."
    retourner
  finsi
  locale places = 0
  pour chaque e dans p.etapes
    locale g = GENRE_ETAPE(e.genre)
    locale coul = sisinon(pipe.erreurs[e.id] <> nul, "#DC2626", g.couleur)
    locale o = {id = e.id, titre = e.titre, soustitre = g.categorie + " · " + g.libelle, couleur = coul, ;
                lignes = RESUME_ETAPE(p, e), forme = sisinon(EST_SOURCE(e.genre) ou EST_CIBLE(e.genre), "boite", "table")}
    si e.x <> nul
      o.x = e.x
      o.y = e.y
      places += 1
    finsi
    d:noeud(o)
  suivant
  pour chaque k dans p.liens
    d:lien{de = k.de, a = k.a, couleur = "#94A3B8"}
  suivant
  si disposer ou (places < #p.etapes et #p.etapes > 0)
    d:disposer("droite")
    PIPE_MEMORISER()
  finsi
  d:ajuster(55)
  si pipe.sel <> nul et ETAPE(p, pipe.sel) <> nul
    d:selectionner(pipe.sel)
  finsi
  pipe.fiche.valeur = "### " + p.nom + car(10) + car(10) + #p.etapes + " étape(s), " + #p.liens + " lien(s). " + ;
                      "Double-cliquez la palette pour ajouter une étape ; tirez la pastille d'une étape vers une autre pour les relier ; Suppr supprime."
retourner

procedure PIPE_MEMORISER
  si pipe.courant = nul
    retourner
  finsi
  pour chaque n dans pipe.dia:noeuds()
    locale e = ETAPE(pipe.courant, n.id)
    si e <> nul
      e.x = n.x
      e.y = n.y
    finsi
  suivant
retourner

procedure PIPE_DISPOSER(ev)
  AFFICHER_PIPELINE(vrai)
  ENREGISTRER_PROJET()
retourner

fonction INDEX_VUE(titre)
  pour i = 1 a #ordrevues
    si ordrevues[i] = titre
      retourner i
    finsi
  suivant
retourner 1

&&
&& Palette et édition
&&

procedure PIPE_PALETTE(ev)
  si ev.chemin = nul ou #ev.chemin < 2
    retourner
  finsi
  si pipe.courant = nul
    inserer(projet.pipelines, PIPELINE_VIDE(NOM_PIPELINE_LIBRE("pipeline")))
    pipe.courant = projet.pipelines[#projet.pipelines]
    REMPLIR_PIPELINES()
  finsi
  locale genre = nul
  pour chaque g dans GENRES_ETAPES()
    si g.categorie = ev.chemin[1] et g.libelle = ev.chemin[2]
      genre = g
    finsi
  suivant
  si genre = nul
    retourner
  finsi
  locale p = pipe.courant
  locale params = {}
  si genre.genre = "src_table" et noeudcourant <> nul et (noeudcourant.genre = "table" ou noeudcourant.genre = "vue")
    params.table = NOM_NOEUD(noeudcourant)
  finsi
  locale id = AJOUTER_ETAPE(p, genre.genre, sisinon(params.table <> nul, noeudcourant.nom, genre.libelle), params)
  locale e = ETAPE(p, id)
  && placée à droite de la sélection, et reliée à elle si c'est possible
  locale s = sisinon(pipe.sel = nul, nul, ETAPE(p, pipe.sel))
  si s <> nul
    si s.x <> nul
      e.x = s.x + 260
      e.y = s.y
    finsi
    si genre.entrees > 0 et non EST_CIBLE(s.genre)
      RELIER(p, s.id, id)
    finsi
  finsi
  pipe.sel = id
  AFFICHER_PIPELINE(faux)
  PIPE_INSPECTER(e)
  ENREGISTRER_PROJET()
retourner

procedure PIPE_SELECTION(ev)
  si pipe.courant = nul
    retourner
  finsi
  locale e = ETAPE(pipe.courant, ev.texte)
  si e = nul
    retourner
  finsi
  pipe.sel = e.id
  PIPE_INSPECTER(e)
retourner

fonction DEFS_PARAMS(p, e)
  && paramètres affichés dans l'inspecteur (la jointure en a par entrée)
  locale g = GENRE_ETAPE(e.genre)
  locale l = copier(g.params)
  si e.genre = "jointure"
    locale ins = ENTREES(p, e.id)
    pour k = 2 a max(2, #ins)
      inserer(l, {nom = "type" + k, libelle = "Type " + k, defaut = "JOIN"})
      inserer(l, {nom = "condition" + k, libelle = "Condition " + k, defaut = ""})
    suivant
  finsi
retourner l

procedure PIPE_GRILLE(e)
  si pipe.grille <> nul
    pipe.grille:detruire()
  finsi
  pipe.grille = pipe.zone:ajouter(ui.grille())
  pipe.grille.ancrage = "centre"
  pipe.grille:ajoutercolonne{nom = "param", titre = "Paramètre", largeur = 120}
  pipe.grille:ajoutercolonne{nom = "valeur", titre = "Valeur", largeur = 260}
  pipe.grille:fixermodifiable(vrai)
  pipe.defs = {}
  si e <> nul
    pipe.defs = DEFS_PARAMS(pipe.courant, e)
    pour chaque d dans pipe.defs
      pipe.grille:ajouterligne(d.libelle, PARAM(e, d.nom))
    suivant
  finsi
retourner

procedure PIPE_INSPECTER(e)
  locale g = GENRE_ETAPE(e.genre)
  pipe.genre.libelle = g.categorie + " · " + g.libelle + "  (" + e.id + ")"
  pipe.titre.valeur = e.titre
  PIPE_GRILLE(e)
  locale nl = car(10)
  locale md = "### " + e.titre + nl + nl + g.aide + nl
  pour chaque d dans pipe.defs
    si d.choix <> nul
      md = md + nl + "*" + d.libelle + "* : " + d.choix + nl
    finsi
  suivant
  si pipe.erreurs[e.id] <> nul
    md = md + nl + "**Erreur :** " + pipe.erreurs[e.id] + nl
  finsi
  essayer
    si non EST_CIBLE(e.genre) ou #ENTREES(pipe.courant, e.id) > 0
      locale s = sisinon(EST_CIBLE(e.genre), SQL_CIBLE(pipe.courant, e.id), SQL_JUSQUA(pipe.courant, e.id))
      md = md + nl + "```" + nl + s + nl + "```" + nl
    finsi
  capturer x
    md = md + nl + "*SQL incomplet : " + x + "*" + nl
  finessayer
  pipe.fiche.valeur = md
retourner

procedure PIPE_APPLIQUER(ev)
  si pipe.courant = nul ou pipe.sel = nul
    retourner
  finsi
  locale e = ETAPE(pipe.courant, pipe.sel)
  si e = nul
    retourner
  finsi
  si rogner(pipe.titre.valeur) <> ""
    e.titre = rogner(pipe.titre.valeur)
  finsi
  pour i = 1 a min(#pipe.defs, pipe.grille:nombre())
    locale v = pipe.grille:cellule(i, "valeur")
    e.params[majuscule(pipe.defs[i].nom)] = sisinon(v = nul, "", chaine(v))
  suivant
  pipe.erreurs[e.id] = nul
  pipe.colonnes[e.id] = nul
  AFFICHER_PIPELINE(faux)
  PIPE_INSPECTER(e)
  ENREGISTRER_PROJET()
retourner

procedure PIPE_ACTION(ev)
  locale p = pipe.courant
  si p = nul
    retourner
  finsi
  locale a = pipe.dia:action()
  faire cas
  cas a.action = "deplace"
    PIPE_MEMORISER()
    ENREGISTRER_PROJET()
  cas a.action = "lien"
    locale de = ETAPE(p, a.de)
    locale vers = ETAPE(p, a.a)
    si de = nul ou vers = nul ou de = vers
      retourner
    finsi
    locale g = GENRE_ETAPE(vers.genre)
    si EST_CIBLE(de.genre)
      STATUT("Une cible n'a pas de sortie.")
      retourner
    finsi
    si g.entrees = 0
      STATUT("« " + vers.titre + " » est une source : elle n'a pas d'entrée.")
      retourner
    finsi
    si #ENTREES(p, vers.id) >= g.entrees
      && entrée unique déjà prise : remplacée
      locale l = {}
      pour chaque k dans p.liens
        si k.a <> vers.id
          inserer(l, k)
        finsi
      suivant
      p.liens = l
    finsi
    RELIER(p, de.id, vers.id)
    AFFICHER_PIPELINE(faux)
    ENREGISTRER_PROJET()
  cas a.action = "supprimer"
    si commencepar(a.id, "lien:") ou contient(a.id, ">")
      locale cle = remplacertexte(a.id, "lien:", "")
      locale l = {}
      pour chaque k dans p.liens
        si k.de + ">" + k.a <> cle
          inserer(l, k)
        finsi
      suivant
      p.liens = l
    sinonsi ETAPE(p, a.id) <> nul
      SUPPRIMER_ETAPE(p, a.id)
      pipe.sel = nul
    finsi
    AFFICHER_PIPELINE(faux)
    ENREGISTRER_PROJET()
  fincas
retourner

&&
&& SQL <-> éditeur, validation, aperçu, exécution
&&

procedure PIPE_DEPUIS_EDITEUR(ev)
  locale texte = ed:selection()
  si texte = nul ou rogner(texte) = ""
    texte = ed:texte()
  finsi
  locale base = sisinon(ed:chemin() = "", "pipeline", remplacertexte(fichier.nom(ed:chemin()), ".sql", ""))
  locale p = PIPELINE_DEPUIS_SQL(texte, NOM_PIPELINE_LIBRE(base))
  si #p.etapes = 0
    STATUT("Aucune instruction exploitable dans le script.")
    retourner
  finsi
  pour chaque m dans p.messages
    JOURNAL("SQL → pipeline : " + m)
  suivant
  p.messages = nul
  inserer(projet.pipelines, p)
  pipe.courant = p
  pipe.sel = nul
  pipe.colonnes = {}
  pipe.erreurs = {}
  REMPLIR_PIPELINES()
  AFFICHER_PIPELINE(vrai)
  ENREGISTRER_PROJET()
  vues.valeur = INDEX_VUE("Pipelines")
  STATUT("Pipeline « " + p.nom + " » : " + #p.etapes + " étape(s)")
retourner

procedure PIPE_VERS_EDITEUR(ev)
  si pipe.courant = nul
    retourner
  finsi
  essayer
    locale s = SQL_PIPELINE(pipe.courant)
    NOUVELLE_REQUETE()
    ed:fixertexte(s)
    vues.valeur = 1
  capturer e
    ERREUR("Pipeline → SQL : " + e)
  finessayer
retourner

procedure PIPE_VALIDER(ev)
  && colonnes de chaque étape (DESCRIBE), étapes en erreur en rouge
  locale p = pipe.courant
  si p = nul
    retourner
  finsi
  pipe.colonnes = {}
  pipe.erreurs = {}
  locale n = 0
  pour chaque e dans ORDRE_ETAPES(p)
    si non EST_CIBLE(e.genre)
      essayer
        locale cols = {}
        pour chaque r dans requete("DESCRIBE " + SQL_JUSQUA(p, e.id))
          inserer(cols, r.column_name)
        suivant
        pipe.colonnes[e.id] = cols
      capturer x
        pipe.erreurs[e.id] = x
        n += 1
      finessayer
    sinonsi #ENTREES(p, e.id) = 0
      pipe.erreurs[e.id] = "aucune entrée"
      n += 1
    finsi
  suivant
  AFFICHER_PIPELINE(faux)
  STATUT(sisinon(n = 0, "Pipeline valide : " + #p.etapes + " étape(s).", n + " étape(s) en erreur (en rouge)."))
retourner

procedure PIPE_APERCU(ev)
  si pipe.courant = nul ou pipe.sel = nul
    STATUT("Sélectionnez une étape du pipeline.")
    retourner
  finsi
  essayer
    EXECUTER_UNE(SQL_JUSQUA(pipe.courant, pipe.sel), vrai)
    bas.valeur = 1
  capturer e
    ERREUR("Aperçu : " + e)
  finessayer
retourner

fonction EXECUTER_PIPELINE(p, ses)
  && exécute les cibles dans l'ordre ; {ok, message, lignes}
  && ses : session SQL (sessionsql()) ; nul : base principale
  locale t0 = systeme.horloge()
  locale n = 0
  locale lignes = 0
  pour chaque e dans ORDRE_ETAPES(p)
    si EST_CIBLE(e.genre)
      locale s = SQL_CIBLE(p, e.id)
      essayer
        locale r = nul
        si ses = nul
          r = requete(s)
        sinon
          r = ses:requete(s)
        finsi
        si #r > 0 et r[1].count <> nul
          lignes += r[1].count
        finsi
        HISTORISER(s, systeme.horloge() - t0, lignes, vrai, "pipeline " + p.nom)
        n += 1
      capturer x
        HISTORISER(s, systeme.horloge() - t0, 0, faux, x)
        retourner {ok = faux, message = e.titre + " : " + x, lignes = lignes}
      finessayer
    finsi
  suivant
  si n = 0
    retourner {ok = faux, message = "aucune cible dans le pipeline", lignes = 0}
  finsi
retourner {ok = vrai, message = n + " cible(s), " + lignes + " ligne(s) en " + arrondi((systeme.horloge() - t0) * 1000) + " ms", lignes = lignes}

procedure PIPE_EXECUTER(ev)
  si pipe.courant = nul
    retourner
  finsi
  locale libelle = "pipeline « " + pipe.courant.nom + " »"
  pour chaque k, x dans taches
    si x.libelle = libelle
      STATUT("Le " + libelle + " est déjà en cours d'exécution.")
      retourner
    finsi
  suivant
  locale ses = sessionsql()
  locale tache = OPERATION_DEBUT(libelle, ses)
  STATUT("Exécution du " + libelle + "…")
  locale r = EXECUTER_PIPELINE(pipe.courant, ses)
  si tache.arret
    r = {ok = faux, message = "arrêté par l'utilisateur"}
  finsi
  OPERATION_FIN(tache)
  ses:fermer()
  si r.ok
    STATUT("Pipeline « " + pipe.courant.nom + " » : " + r.message)
    JOURNAL("Pipeline « " + pipe.courant.nom + " » : " + r.message)
    RAFRAICHIR_CATALOGUES()
  sinon
    ERREUR("Pipeline « " + pipe.courant.nom + " » : " + r.message)
  finsi
retourner
