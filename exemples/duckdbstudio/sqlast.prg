&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : arbre syntaxique SQL. L'analyse est celle de DuckDB
&& (json_serialize_sql) : l'arbre JSON est lu tel quel (clefs exactes), et chaque
&& expression est réécrite en SQL par DuckDB lui-même (json_deserialize_sql sur une
&& requête modèle dont on remplace un nœud) : la traduction est exacte, quelles que
&& soient les fonctions, les CASE ou les sous-requêtes utilisées.

fonction AST(sql)
  && arbre d'une requête SELECT (ou nul si DuckDB ne sait pas la sérialiser) : {ok, arbre, message}
  essayer
    locale t = json.decoder(valeursql("SELECT json_serialize_sql(?::VARCHAR)", sql), vrai)
    si t["error"] = vrai
      retourner {ok = faux, message = sisinon(t["error_message"] = nul, "erreur de syntaxe", t["error_message"])}
    finsi
    si t["statements"] = nul ou #t["statements"] <> 1
      retourner {ok = faux, message = "une seule requête SELECT attendue"}
    finsi
    retourner {ok = vrai, arbre = t["statements"][1]["node"]}
  capturer e
    retourner {ok = faux, message = e}
  finessayer
retourner nul

fonction SQL_NOEUD(sql, chemin, modele, chemin_modele)
  && texte SQL du nœud `chemin` (JSONPath, indices à partir de 0) de l'arbre de `sql`,
  && obtenu en le greffant à la place du nœud `chemin_modele` de la requête `modele`
  locale r = valeursql("WITH s AS (SELECT json_serialize_sql(?::VARCHAR) AS j), " + ;
    "m AS (SELECT json_serialize_sql(?::VARCHAR)::VARCHAR AS tpl, " + ;
    "json_extract(json_serialize_sql(?::VARCHAR), ?)::VARCHAR AS c) " + ;
    "SELECT json_deserialize_sql(replace(tpl, c, json_extract(j, ?)::VARCHAR)::JSON) FROM s, m", ;
    sql, modele, modele, chemin_modele, chemin)
retourner sisinon(r = nul, "", r)

fonction SANS_PARENTHESES(t)
  && retire les parenthèses extérieures superflues : ((a > 1)) -> a > 1
  t = rogner(t)
  tantque gauche(t, 1) = "(" et droite(t, 1) = ")" et PARENTHESE_FERMANTE(t, 1) = longueur(t)
    t = rogner(souschaine(t, 2, longueur(t) - 2))
  fintantque
retourner t

fonction PARENTHESE_FERMANTE(t, debut)
  && position de la parenthèse qui ferme celle de `debut` (chaînes et identifiants respectés)
  locale n = 0
  locale dans = ""
  pour i = debut a longueur(t)
    locale ch = souschaine(t, i, 1)
    si dans <> ""
      si ch = dans
        dans = ""
      finsi
    sinonsi ch = "'" ou ch = car(34)
      dans = ch
    sinonsi ch = "("
      n += 1
    sinonsi ch = ")"
      n -= 1
      si n = 0
        retourner i
      finsi
    finsi
  suivant
retourner 0

fonction EXPR_SQL(sql, chemin)
  && texte d'une expression de la requête (alias compris : « x + 1 AS y »)
  locale t = SQL_NOEUD(sql, chemin, "SELECT 42424242", "$.statements[0].node.select_list[0]")
  si commencepar(t, "SELECT ")
    t = souschaine(t, 8)
  finsi
  t = remplacertexte(t, "count_star()", "count(*)")
  && alias éventuel : on simplifie l'expression avant lui
  locale p = POSITION_ALIAS(t)
  si p > 0
    retourner SANS_PARENTHESES(gauche(t, p - 1)) + souschaine(t, p)
  finsi
retourner SANS_PARENTHESES(t)

fonction POSITION_ALIAS(t)
  && position de « AS alias » final hors parenthèses et chaînes (0 si absent)
  locale n = 0
  locale dans = ""
  locale p = 0
  pour i = 1 a longueur(t)
    locale ch = souschaine(t, i, 1)
    si dans <> ""
      si ch = dans
        dans = ""
      finsi
    sinonsi ch = "'" ou ch = car(34)
      dans = ch
    sinonsi ch = "("
      n += 1
    sinonsi ch = ")"
      n -= 1
    sinonsi n = 0 et souschaine(t, i, 4) = " AS "
      p = i
    finsi
  suivant
retourner p

fonction FROM_SQL(sql, chemin)
  && texte d'une clause FROM (table, jointure, fonction de table, sous-requête)
  locale t = SQL_NOEUD(sql, chemin, "SELECT * FROM x", "$.statements[0].node.from_table")
  locale p = position(" FROM ", t)
retourner sisinon(p > 0, rogner(souschaine(t, p + 6)), t)

fonction REQUETE_SQL(sql, chemin)
  && texte d'une requête imbriquée (CTE, sous-requête, branche d'union)
retourner SQL_NOEUD(sql, chemin, "SELECT 1", "$.statements[0].node")

fonction AGREGATS()
retourner {"count_star", "count", "sum", "avg", "mean", "min", "max", "any_value", "first", "last", "list", ;
           "array_agg", "string_agg", "group_concat", "median", "mode", "quantile", "quantile_cont", ;
           "quantile_disc", "stddev", "stddev_pop", "stddev_samp", "var_pop", "var_samp", "variance", ;
           "approx_count_distinct", "approx_quantile", "bool_and", "bool_or", "arg_max", "arg_min", ;
           "max_by", "min_by", "product", "histogram", "bit_and", "bit_or", "corr", "covar_pop", "entropy", ;
           "kurtosis", "skewness", "fsum", "favg", "sumkahan", "bitstring_agg"}

fonction CONTIENT_AGREGAT(n)
  && vrai si l'expression (table JSON) appelle une fonction d'agrégation (hors sous-requêtes)
  si n = nul ou type(n) <> "table"
    retourner faux
  finsi
  si n["class"] = "SUBQUERY"
    retourner faux
  finsi
  si n["class"] = "WINDOW"
    retourner faux
  finsi
  si n["class"] = "FUNCTION" et contient(AGREGATS(), minuscule(sisinon(n["function_name"] = nul, "", n["function_name"])))
    retourner vrai
  finsi
  pour chaque k, v dans n
    si type(v) = "table" et CONTIENT_AGREGAT(v)
      retourner vrai
    finsi
  suivant
retourner faux

fonction NOM_TABLE(ft)
  && nom qualifié d'une référence BASE_TABLE
  locale l = {}
  pour chaque k dans {"catalog_name", "schema_name", "table_name"}
    si ft[k] <> nul et ft[k] <> ""
      inserer(l, IDENT(ft[k]))
    finsi
  suivant
retourner joindre(l, ".")

&&
&& Découpage d'un texte en cible + requête
&&

fonction INSTRUCTION_CIBLE(s)
  && {cible = {genre, ...} ou nul, requete} ; nul si l'instruction n'est pas reconnue
  locale t = rogner(SANS_COMMENTAIRES(s))
  si finitpar(t, ";")
    t = rogner(gauche(t, longueur(t) - 1))
  finsi
  locale m = minuscule(t)
  locale mots = decouper(remplacertexte(remplacertexte(m, car(10), " "), car(9), " "), " ")
  locale l = {}
  pour chaque w dans mots
    si w <> ""
      inserer(l, w)
    finsi
  suivant
  si #l = 0
    retourner nul
  finsi
  && CREATE [OR REPLACE] TABLE|VIEW nom AS requete
  si l[1] = "create"
    locale i = 2
    locale remplacer = faux
    si #l >= 3 et l[2] = "or" et l[3] = "replace"
      i = 4
      remplacer = vrai
    finsi
    si #l > i et (l[i] = "table" ou l[i] = "view")
      locale genre = l[i]
      locale p = position(" as ", m)
      locale p2 = position(car(10) + "as ", m)
      si p = 0 ou (p2 > 0 et p2 < p)
        p = p2
      finsi
      si p > 0
        locale nom = rogner(souschaine(t, position(l[i], m) + longueur(l[i]), p - position(l[i], m) - longueur(l[i])))
        nom = rogner(remplacertexte(remplacertexte(nom, "IF NOT EXISTS", ""), "if not exists", ""))
        locale q = rogner(souschaine(t, p + 4))
        si genre = "table"
          retourner {cible = {genre = "cible_table", table = nom, mode = "remplacer"}, requete = q}
        finsi
        retourner {cible = {genre = "cible_vue", vue = nom}, requete = q}
      finsi
    finsi
    retourner nul
  finsi
  && INSERT INTO nom [BY NAME] requete
  si l[1] = "insert" et #l >= 3 et l[2] = "into"
    locale p = position("into", m) + 4
    locale reste = rogner(souschaine(t, p))
    locale k = 1
    tantque k <= longueur(reste) et non contient(" (" + car(10), souschaine(reste, k, 1))
      k += 1
    fintantque
    locale nom = gauche(reste, k - 1)
    reste = rogner(souschaine(reste, k))
    si commencepar(minuscule(reste), "by name")
      reste = rogner(souschaine(reste, 8))
    finsi
    retourner {cible = {genre = "cible_table", table = nom, mode = "ajouter"}, requete = reste}
  finsi
  && COPY (requete) TO 'chemin' (FORMAT x)
  si l[1] = "copy"
    locale p = position("(", t)
    si p > 0
      locale f = PARENTHESE_FERMANTE(t, p)
      si f > 0
        locale q = souschaine(t, p + 1, f - p - 1)
        locale reste = souschaine(t, f + 1)
        locale a = position("'", reste)
        locale b = 0
        si a > 0
          b = position("'", souschaine(reste, a + 1)) + a
        finsi
        locale chemin = sisinon(a > 0 et b > a, souschaine(reste, a + 1, b - a - 1), "sortie.parquet")
        locale fmt = "parquet"
        pour chaque x dans {"csv", "json", "parquet"}
          si contient(minuscule(reste), "format " + x) ou contient(minuscule(reste), "format '" + x)
            fmt = x
          finsi
        suivant
        retourner {cible = {genre = "cible_fichier", chemin = chemin, format = fmt}, requete = rogner(q)}
      finsi
    finsi
    retourner nul
  finsi
  si EST_REQUETE(t)
    retourner {cible = nul, requete = t}
  finsi
retourner nul
