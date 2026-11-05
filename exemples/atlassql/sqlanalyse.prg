&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atlas SQL : analyseur T-SQL (modules 3, 6, 8, 11, et la base des modules 7, 10, 15, 16).
&&
&& 1. Découpage lexical par DuckDB (une expression régulière, rapide même sur des
&&    milliers de lignes) : mots, identifiants [entre crochets], @variables, #tables
&&    temporaires, chaînes N'…' (contenu conservé : SQL dynamique), symboles, numéro de
&&    ligne de chaque jeton ; les commentaires sont écartés.
&& 2. Découpage en instructions (T-SQL n'impose pas le « ; ») : mots-clés de début
&&    d'instruction, profondeur des parenthèses et des CASE, règles de continuation
&&    (INSERT … SELECT, UPDATE … SET, MERGE … ;, UNION, CTE, curseurs…).
&& 3. Arbre syntaxique : blocs IF / ELSE / WHILE / BEGIN…END / TRY / CATCH, phases
&&    (Déclarations, Initialisation, Contrôles, Chargement, Calcul, Écriture,
&&    Archivage, Restitution, Gestion d'erreurs, Transaction) pour le synoptique.
&& 4. Références : lecture, insertion, mise à jour, suppression, MERGE, EXEC, appels
&&    de fonctions, OPENQUERY, noms à 4 parties (serveurs liés), alias résolus.
&& 5. SQL dynamique : suivi des variables chaînes (SET / SELECT / DECLARE …=),
&&    reconstitution de EXEC(…) et sp_executesql (paramètres et types).
&& 6. Mesures et constats : complexité cyclomatique, jointures, règles (CASE, filtres),
&&    anti-modèles (SELECT *, curseurs, fonctions sur colonnes filtrées, injection…).
&&
&& L'analyse d'un texte est une fonction pure (ANALYSER_TEXTE) : l'éditeur l'appelle à
&& chaque modification (synoptique synchronisé), les agents par lots d'objets.

fonction REGEX_JETONS()
retourner "(--[^\n]*|/\*(?s:.*?)\*/|N?'(?:[^']|'')*'|\[[^\]]*\]|@@?[\w$#]+|##?[\w$#]+|[A-Za-z_\x{00C0}-\x{024F}][\w$#\x{00C0}-\x{024F}]*|[0-9]+(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?|0x[0-9A-Fa-f]+|\n|<>|!=|>=|<=|\+=|-=|\*=|/=|::|[^\s\w])"

fonction SQL_JETONS(source)
  && source : « ? » (un texte) ou « definition from objets where … »
  locale re = remplacertexte(REGEX_JETONS(), "'", "''")
retourner "with t as (select " + source + "), " + ;
  "a as (select oid, regexp_extract_all(txt, '" + re + "') l from t), " + ;
  "u as (select oid, unnest(l) as tok, generate_subscripts(l, 1) as ord from a), " + ;
  "v as (select oid, ord, tok, 1 + coalesce(sum(length(tok) - length(replace(tok, chr(10), ''))) " + ;
  "over (partition by oid order by ord rows between unbounded preceding and 1 preceding), 0) as ligne from u) " + ;
  "select oid, ligne as l, tok as o, upper(tok) as u, " + ;
  "case when tok like 'N''%' or tok like '''%' then 'S' when tok like '[%' then 'I' when tok like '@%' then 'V' " + ;
  "when tok like '#%' then 'T' when regexp_matches(tok, '^[0-9]') then 'N' " + ;
  "when regexp_matches(tok, '^[A-Za-z_\x{00C0}-\x{024F}]') then 'W' else 'P' end as k " + ;
  "from v where tok <> chr(10) and not starts_with(tok, '--') and not starts_with(tok, '/*') order by oid, ord"

fonction JETONS_TEXTE(s, texte)
  locale r = RQ(s, SQL_JETONS("0 as oid, ?::varchar as txt"), {texte})
retourner r

fonction JETONS_OBJETS(s, ids)
  && jetons de plusieurs objets en une requête : table oid -> liste de jetons
  locale r = RQ(s, SQL_JETONS("id as oid, definition as txt from objets where list_contains(string_split(?, ',')::integer[], id) " + ;
                              "and definition is not null"), {joindre(ids, ",")})
  locale par = {}
  pour chaque j dans r
    locale k = chaine(j.oid)
    si par[k] = nul
      par[k] = {}
    finsi
    inserer(par[k], j)
  suivant
retourner par

&&
&& Vocabulaire
&&

fonction ENSEMBLE(liste)
  locale e = {}
  pour chaque m dans liste
    e[m] = vrai
  suivant
retourner e

fonction DEBUTS()
retourner ENSEMBLE({"SELECT", "INSERT", "UPDATE", "DELETE", "MERGE", "EXEC", "EXECUTE", "DECLARE", "SET", "IF", ;
  "ELSE", "WHILE", "BEGIN", "END", "RETURN", "RAISERROR", "THROW", "PRINT", "OPEN", "FETCH", "CLOSE", ;
  "DEALLOCATE", "CREATE", "ALTER", "DROP", "TRUNCATE", "WITH", "BREAK", "CONTINUE", "COMMIT", "ROLLBACK", ;
  "GOTO", "WAITFOR", "USE", "GO", "SAVE", "BULK", "GRANT", "REVOKE", "DENY", "ENABLE", "DISABLE"})

fonction MOTS_RESERVES()
retourner ENSEMBLE({"SELECT", "FROM", "WHERE", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS", "ON", ;
  "AND", "OR", "NOT", "AS", "GROUP", "BY", "ORDER", "HAVING", "UNION", "ALL", "INTO", "VALUES", "SET", "WITH", ;
  "NOLOCK", "APPLY", "OUTPUT", "WHEN", "THEN", "ELSE", "END", "CASE", "IS", "NULL", "IN", "EXISTS", "TOP", ;
  "DISTINCT", "OPTION", "PIVOT", "UNPIVOT", "USING", "MATCHED", "BETWEEN", "LIKE", "EXCEPT", "INTERSECT", "FOR", ;
  "WHILE", "IF", "BEGIN", "RETURN", "DECLARE", "EXEC", "EXECUTE", "UPDATE", "DELETE", "INSERT", "MERGE", "TABLE", ;
  "OVER", "PARTITION", "ROWS", "RANGE", "OFFSET", "FETCH", "NEXT", "ONLY", "TABLESAMPLE", "GO", "WAITFOR"})

&&
&& Lecture d'un nom qualifié à partir du jeton i : [srv].[base].[schema].[objet], a..b
&& renvoie {texte, parties (de gauche à droite), fin}
&&

fonction NOM_PARTIE(j)
  si j.k = "I"
    retourner souschaine(j.o, 2, #j.o - 2)
  finsi
retourner j.o

fonction LIRE_NOM(toks, i)
  locale n = #toks
  si i > n
    retourner nul
  finsi
  locale j = toks[i]
  si j.k <> "W" et j.k <> "I" et j.k <> "T" et j.k <> "V"
    retourner nul
  finsi
  locale parties = {NOM_PARTIE(j)}
  locale k = i
  tantque k + 1 <= n et toks[k + 1].o = "."
    si k + 2 <= n et toks[k + 2].o = "."
      inserer(parties, "")          && a..b : schéma par défaut
      k += 1
    sinonsi k + 2 <= n et (toks[k + 2].k = "W" ou toks[k + 2].k = "I")
      inserer(parties, NOM_PARTIE(toks[k + 2]))
      k += 2
    sinon
      sortir
    finsi
  fintantque
  && dernier « . » d'un a..b
  si k > i et toks[k].o = "."
    k += 1
    si k <= n
      inserer(parties, NOM_PARTIE(toks[k]))
    finsi
  finsi
retourner {texte = joindre(parties, "."), parties = parties, fin = k}

fonction PARTIES_REF(parties)
  && p1 = objet, p2 = schéma, p3 = base, p4 = serveur (de droite à gauche)
  locale n = #parties
  locale r = {p1 = "", p2 = "", p3 = "", p4 = ""}
  si n >= 1
    r.p1 = parties[n]
  finsi
  si n >= 2
    r.p2 = parties[n - 1]
  finsi
  si n >= 3
    r.p3 = parties[n - 2]
  finsi
  si n >= 4
    r.p4 = parties[n - 3]
  finsi
retourner r

&&
&& Découpage en instructions
&&

fonction INSTRUCTIONS(toks)
  locale debuts = DEBUTS()
  locale liste = {}
  locale cur = nil_instr()
  locale dp = 0, cd = 0
  locale n = #toks
  locale i = 1
  tantque i <= n
    locale j = toks[i]
    locale u = j.u
    locale prec = sisinon(#cur.toks > 0, cur.toks[#cur.toks].u, "")
    si j.o = "("
      dp += 1
    sinonsi j.o = ")"
      dp = max(0, dp - 1)
    finsi
    si u = "CASE" et j.k = "W"
      cd += 1
    finsi
    locale coupe = faux
    si j.o = ";" et dp = 0
      && fin explicite
      si #cur.toks > 0
        inserer(liste, cur)
      finsi
      cur = nil_instr()
      i += 1
      boucler
    finsi
    si u = "END" et j.k = "W" et cd > 0
      cd -= 1
    sinonsi j.k = "W" et dp = 0 et cd = 0 et debuts[u] <> nul et #cur.toks > 0
      coupe = non CONTINUE_INSTR(cur, u, prec, toks, i)
    finsi
    && en-tête CREATE PROCEDURE / FUNCTION / TRIGGER / VIEW : coupé après le AS
    si coupe = faux et cur.entete et u = "AS" et j.k = "W" et dp = 0 et prec <> "EXECUTE" et prec <> "EXEC" ;
       et i < n
      locale suiv = toks[i + 1].u
      si debuts[suiv] <> nul ou suiv = "RETURN" ou cur.vue
        inserer(cur.toks, j)
        cur.l2 = j.l
        inserer(liste, cur)
        cur = nil_instr()
        i += 1
        boucler
      finsi
    finsi
    si coupe
      inserer(liste, cur)
      cur = nil_instr()
      cd = 0
    finsi
    si #cur.toks = 0
      cur.kw = u
      cur.l1 = j.l
      si u = "CREATE" ou u = "ALTER"
        && CREATE [OR ALTER] PROC… : en-tête
        locale m = i + 1
        si m + 1 <= n et toks[m].u = "OR"
          m += 2
        finsi
        si m <= n
          locale g = toks[m].u
          si g = "PROC" ou g = "PROCEDURE" ou g = "FUNCTION" ou g = "TRIGGER" ou g = "VIEW"
            cur.entete = vrai
            cur.vue = g = "VIEW"
          finsi
        finsi
      finsi
    finsi
    inserer(cur.toks, j)
    cur.l2 = j.l
    MARQUER_INSTR(cur, u, dp)
    i += 1
  fintantque
  si #cur.toks > 0
    inserer(liste, cur)
  finsi
retourner liste

fonction nil_instr()
retourner {toks = {}, kw = "", l1 = 0, l2 = 0, entete = faux, vue = faux, aselect = faux, aset = faux, ;
           principal = faux, n = 0}

procedure MARQUER_INSTR(cur, u, dp)
  si dp = 0
    si u = "SELECT" ou u = "VALUES" ou u = "EXEC" ou u = "EXECUTE"
      cur.aselect = vrai
    finsi
    si u = "SET"
      cur.aset = vrai
    finsi
    si cur.kw = "WITH" et (u = "SELECT" ou u = "INSERT" ou u = "UPDATE" ou u = "DELETE" ou u = "MERGE")
      cur.principal = vrai
    finsi
  finsi
retourner

fonction CONTINUE_INSTR(cur, u, prec, toks, i)
  && vrai si le mot-clé u continue l'instruction en cours au lieu d'en commencer une
  locale kw = cur.kw
  si kw = "MERGE"
    retourner vrai                                   && MERGE se termine par « ; »
  finsi
  si prec = "UNION" ou prec = "ALL" ou prec = "EXCEPT" ou prec = "INTERSECT" ou prec = "(" ou prec = "THEN"
    retourner vrai
  finsi
  si prec = "ON" et (u = "DELETE" ou u = "UPDATE")
    retourner vrai                                   && ON DELETE CASCADE
  finsi
  si (prec = "DELETE" ou prec = "UPDATE") et (u = "SET")
    retourner vrai                                   && ON UPDATE SET NULL
  finsi
  si u = "WITH"
    retourner vrai                                   && indications de table, WITH (NOLOCK), OPTION…
  finsi
  si prec = "WITH" et (u = "EXECUTE" ou u = "EXEC")
    retourner vrai                                   && WITH EXECUTE AS
  finsi
  si cur.entete
    retourner vrai                                   && en-tête : jusqu'au AS
  finsi
  si u = "SELECT"
    si kw = "INSERT" et non cur.aselect
      retourner vrai
    finsi
    si kw = "WITH" et non cur.principal
      retourner vrai
    finsi
    si kw = "DECLARE" et prec = "FOR"
      retourner vrai                                 && DECLARE c CURSOR FOR SELECT
    finsi
    si kw = "SET" et prec = "="
      retourner vrai                                 && SET @x = (SELECT…) sans parenthèses
    finsi
    retourner faux
  finsi
  si u = "EXEC" ou u = "EXECUTE"
    si kw = "INSERT" et non cur.aselect
      retourner vrai                                 && INSERT INTO #t EXEC p
    finsi
    retourner faux
  finsi
  si u = "SET"
    si kw = "UPDATE" et non cur.aset
      retourner vrai
    finsi
    retourner faux
  finsi
  si kw = "WITH" et non cur.principal et (u = "INSERT" ou u = "UPDATE" ou u = "DELETE" ou u = "MERGE")
    retourner vrai
  finsi
  si u = "OPEN" ou u = "CLOSE" ou u = "FETCH"
    && OPEN est aussi un mot de OPENQUERY… mais ici c'est un mot isolé ; FETCH NEXT dans OFFSET
    si prec = "ROWS" ou prec = "ROW" ou prec = "OFFSET"
      retourner vrai
    finsi
  finsi
  si (u = "BEGIN" ou u = "END") et kw = "DECLARE"
    retourner faux
  finsi
retourner faux

&&
&& Analyse d'un texte complet
&&

fonction ANALYSER_TEXTE(s, texte, ctx)
  && ctx : {serveur, base, sch, nom, genre} (contexte de résolution des noms)
retourner ANALYSER_JETONS(JETONS_TEXTE(s, texte), ctx)

fonction ANALYSE_VIDE()
retourner {instructions = {}, ast = {}, refs = {}, vars = {}, dyn = {}, jointures = {}, regles = {}, diag = {}, ;
           complexite = 1, lignes = 0, entete = nul, params = {}, phases = {}, corps = 1}

fonction ANALYSER_JETONS(toks, ctx)
  locale R = ANALYSE_VIDE()
  si toks = nul ou #toks = 0
    retourner R
  finsi
  R.lignes = toks[#toks].l
  locale instrs = INSTRUCTIONS(toks)
  locale etat = {dyn = {}, ctes = {}, alias = {}, temps = {}, curseurs = {}, transaction = 0, trycatch = 0, ;
                 numero = 0, nid = 0, pile = {}, dernier_si = nul, racine = nul, ctx = ctx, avec_corps = faux}
  && racine de l'arbre
  locale titre = sisinon(ctx = nul ou ctx.nom = nul, "Script", LIBELLE_GENRE(ctx.genre) + " " + ctx.nom)
  etat.racine = NOEUD_AST(R, etat, 0, "RACINE", titre, "", 1, R.lignes)
  inserer(etat.pile, {noeud = etat.racine, mode = "bloc"})
  pour chaque ins dans instrs
    ANALYSER_INSTR(R, etat, ins)
  suivant
  && phases des contrôles : un IF dont le corps lève une erreur ou sort
  PHASES_CONTROLES(R)
  && résumé des phases dans l'ordre (synoptique)
  locale vu = {}
  locale corps = etat.racine.id
  locale tops = 0
  locale premier = nul
  pour chaque a dans R.ast
    si a.parent = corps
      tops += 1
      si premier = nul
        premier = a
      finsi
    finsi
  suivant
  si tops = 1 et premier.genre = "BLOC"
    corps = premier.id                 && AS BEGIN … END : le corps est le bloc
  finsi
  R.corps = corps
  pour chaque a dans R.ast
    si a.parent = corps et a.phase <> "" et vu[a.phase] = nul
      vu[a.phase] = vrai
      inserer(R.phases, a.phase)
    finsi
  suivant
retourner R

fonction NOEUD_AST(R, etat, parent, genre, libelle, phase, l1, l2)
  etat.nid += 1
  locale nd = {id = etat.nid, parent = parent, genre = genre, libelle = libelle, phase = phase, ;
               l1 = l1, l2 = l2, ordre = etat.nid, enfants = 0}
  inserer(R.ast, nd)
retourner nd

fonction TEXTE_INSTR(ins, max_)
  locale p = {}
  pour chaque j dans ins.toks
    si j.k = "S"
      inserer(p, COURT(j.o, 60))
    sinon
      inserer(p, j.o)
    finsi
    si #p > 400
      sortir
    finsi
  suivant
  locale t = joindre(p, " ")
  t = remplacertexte(remplacertexte(remplacertexte(t, " . ", "."), " ,", ","), "( ", "(")
  t = remplacertexte(t, " )", ")")
retourner COURT(t, sisinon(max_ = nul, 4000, max_))

fonction NORMALISE_INSTR(ins)
  && forme normalisée (empreinte des duplications) : littéraux -> ?, variables -> @v
  locale p = {}
  pour chaque j dans ins.toks
    faire cas
    cas j.k = "S" ou j.k = "N"
      inserer(p, "?")
    cas j.k = "V"
      inserer(p, sisinon(commencepar(j.o, "@@"), j.u, "@v"))
    cas j.k = "I"
      inserer(p, majuscule(NOM_PARTIE(j)))
    autrement
      inserer(p, j.u)
    fincas
  suivant
retourner joindre(p, " ")

procedure ANALYSER_INSTR(R, etat, ins)
  locale kw = ins.kw
  locale toks = ins.toks
  locale n = #toks
  locale u2 = sisinon(n >= 2, toks[min(2, n)].u, "")
  locale haut = etat.pile[#etat.pile]
  && fin de bloc
  si kw = "END"
    FERMER_BLOC(etat, ins.l2)
    retourner
  finsi
  si kw = "GO"
    retourner
  finsi
  etat.numero += 1
  ins.n = etat.numero
  locale genre = kw
  locale libelle = TEXTE_INSTR(ins, 90)
  locale phase = ""
  && en-tête CREATE PROCEDURE … AS : paramètres
  si ins.entete
    R.entete = ins
    ENTETE(R, etat, ins)
    etat.avec_corps = vrai
    retourner
  finsi
  && blocs
  locale bloc = ""
  si kw = "BEGIN"
    faire cas
    cas u2 = "TRY"
      bloc = "TRY"
      genre = "TRY"
      libelle = "Essayer (TRY)"
      etat.trycatch += 1
    cas u2 = "CATCH"
      bloc = "CATCH"
      genre = "CATCH"
      libelle = "Gestion d'erreurs (CATCH)"
      phase = "Gestion d'erreurs"
      R.complexite += 1
    cas u2 = "TRAN" ou u2 = "TRANSACTION" ou u2 = "DISTRIBUTED"
      genre = "TRANSACTION"
      phase = "Transaction"
      libelle = "Début de transaction"
      etat.transaction += 1
    autrement
      bloc = "BEGIN"
      genre = "BLOC"
      libelle = "Bloc BEGIN … END"
    fincas
  finsi
  si kw = "COMMIT" ou kw = "ROLLBACK"
    phase = "Transaction"
    genre = "TRANSACTION"
  finsi
  locale cond = ""
  si kw = "IF" ou kw = "WHILE"
    R.complexite += 1
    cond = CONDITION(ins)
    si kw = "IF"
      libelle = "Si " + COURT(cond, 80)
    sinon
      libelle = sisinon("@@FETCH_STATUS" $ majuscule(cond), "Boucle de curseur", "Tant que " + COURT(cond, 70))
    finsi
    pour chaque j dans toks
      si j.u = "AND" ou j.u = "OR"
        R.complexite += 1
      finsi
    suivant
  finsi
  si kw = "ELSE"
    libelle = "Sinon"
  finsi
  && cas WHEN
  pour chaque j dans toks
    si j.u = "WHEN" et j.k = "W"
      R.complexite += 1
    finsi
  suivant
  && références, variables, SQL dynamique, constats
  locale info = REFERENCES_INSTR(R, etat, ins)
  si phase = "" et bloc = "" et genre <> "TRY"
    phase = PHASE_INSTR(etat, ins, info)
  finsi
  && instruction (liste plate)
  locale norm = NORMALISE_INSTR(ins)
  inserer(R.instructions, {num = ins.n, l1 = ins.l1, l2 = ins.l2, genre = genre, phase = phase, ;
                           prof = #etat.pile - 1, texte = TEXTE_INSTR(ins, 4000), normalise = norm, ;
                           empreinte = "", tables = joindre(info.tables, ",")})
  && arbre
  locale parent = haut.noeud
  si kw = "ELSE" et etat.dernier_si <> nul
    parent = etat.dernier_si
  finsi
  locale nd = NOEUD_AST(R, etat, parent.id, genre, libelle, phase, ins.l1, ins.l2)
  R.instructions[#R.instructions].noeud = nd
  parent.enfants += 1
  si kw = "IF" ou kw = "WHILE" ou kw = "ELSE"
    nd.corps = vrai
    inserer(etat.pile, {noeud = nd, mode = "corps1"})
    retourner
  finsi
  si bloc <> ""
    inserer(etat.pile, {noeud = nd, mode = "bloc", genre = bloc})
    retourner
  finsi
  COMPLETER(etat)
retourner

procedure COMPLETER(etat)
  && une instruction simple vient de remplir le corps d'un IF / WHILE / ELSE
  tantque #etat.pile > 1 et etat.pile[#etat.pile].mode = "corps1"
    locale e = retirer(etat.pile)
    si e.noeud.genre = "IF"
      etat.dernier_si = e.noeud
    finsi
  fintantque
retourner

procedure FERMER_BLOC(etat, l2)
  tantque #etat.pile > 1
    locale e = retirer(etat.pile)
    e.noeud.l2 = l2
    si e.mode = "bloc"
      sortir
    finsi
  fintantque
  COMPLETER(etat)
retourner

fonction CONDITION(ins)
  locale p = {}
  pour i = 2 a #ins.toks
    inserer(p, ins.toks[i].o)
    si #p > 40
      sortir
    finsi
  suivant
retourner joindre(p, " ")

procedure ENTETE(R, etat, ins)
  && CREATE PROCEDURE nom @p type [= défaut] [OUTPUT], … AS
  locale toks = ins.toks
  locale n = #toks
  locale i = 1
  tantque i <= n
    locale j = toks[i]
    si j.k = "V" et non commencepar(j.o, "@@")
      locale typ = TYPE_A(toks, i + 1)
      locale def = ""
      locale m = i + 1
      locale dp = 0
      tantque m <= n
        si toks[m].o = "("
          dp += 1
        sinonsi toks[m].o = ")"
          dp -= 1
        sinonsi dp = 0 et (toks[m].o = "," ou (toks[m].u = "AS" et m > i + 1) ou toks[m].u = "WITH")
          sortir
        finsi
        si dp = 0 et toks[m].o = "=" et m + 1 <= n
          def = toks[m + 1].o
        finsi
        m += 1
      fintantque
      inserer(R.params, {nom = j.o, type = typ, defaut = def})
      inserer(R.vars, {nom = j.o, genre = "parametre", type = typ, ligne = j.l, defaut = def})
      i = m
    finsi
    i += 1
  fintantque
retourner

fonction INFO_VIDE()
retourner {tables = {}, lit = {}, ecrit = {}, cible = "", temp = faux, into = "", retourne = faux, ;
           assigne = faux, erreur = faux, dynamique = faux, appel = faux}

fonction EST_TEMP(nom)
  && tables temporaires, variables tables, pseudo-tables des déclencheurs
  locale u = majuscule(nom)
retourner commencepar(nom, "#") ou commencepar(nom, "@") ou u = "INSERTED" ou u = "DELETED"

fonction REFERENCES_INSTR(R, etat, ins)
  locale info = INFO_VIDE()
  locale toks = ins.toks
  locale n = #toks
  locale kw = ins.kw
  locale reserves = MOTS_RESERVES()
  locale alias = {}
  locale refs = {}
  locale i = 1
  && WITH cte AS ( … ) : noms de CTE
  si kw = "WITH"
    pour k = 2 a n - 1
      si toks[k].k = "W" et (toks[k + 1].u = "AS" ou (toks[k + 1].o = "(" et k = 2)) et (k = 2 ou toks[k - 1].o = ",")
        etat.ctes[toks[k].u] = vrai
        inserer(R.vars, {nom = toks[k].o, genre = "cte", type = "", ligne = toks[k].l, defaut = ""})
      finsi
    suivant
  finsi
  && DECLARE : variables, tables variables, curseurs
  si kw = "DECLARE"
    DECLARATIONS(R, etat, ins)
  finsi
  && affectations de chaînes (SQL dynamique)
  si kw = "SET" ou kw = "SELECT" ou kw = "DECLARE"
    AFFECTATIONS(R, etat, ins)
  finsi
  && CREATE TABLE #t : table temporaire
  si kw = "CREATE" et n >= 3 et toks[2].u = "TABLE" et commencepar(toks[3].o, "#")
    inserer(R.vars, {nom = toks[3].o, genre = "table_temp", type = "CREATE TABLE", ligne = toks[3].l, defaut = ""})
    etat.temps[majuscule(toks[3].o)] = vrai
    info.temp = vrai
    info.cible = toks[3].o
    retourner info
  finsi
  && instructions de curseur : FETCH NEXT FROM c (le nom est celui du curseur)
  si kw = "FETCH" ou kw = "OPEN" ou kw = "CLOSE" ou kw = "DEALLOCATE"
    retourner info
  finsi
  tantque i <= n
    locale j = toks[i]
    locale u = j.u
    locale nat = ""
    si j.k = "W"
      faire cas
      cas u = "FROM" ou u = "JOIN" ou u = "USING"
        nat = "SELECT"
        si u = "FROM" et kw = "DELETE" et i <= 3
          nat = "DELETE"
        finsi
        si u = "USING" et kw <> "MERGE"
          nat = ""
        finsi
      cas u = "INTO" et kw = "SELECT"
        nat = "INSERT"
      cas u = "INTO" et (kw = "INSERT" ou kw = "MERGE")
        nat = sisinon(kw = "MERGE", "MERGE", "INSERT")
      cas u = "INSERT" et kw = "INSERT" et i = 1 et i + 1 <= n et toks[i + 1].u <> "INTO"
        nat = "INSERT"
      cas u = "UPDATE" et i = 1 et kw = "UPDATE"
        nat = "UPDATE"
      cas u = "DELETE" et i = 1 et kw = "DELETE" et i + 1 <= n et toks[i + 1].u <> "FROM"
        nat = "DELETE"
      cas u = "MERGE" et i = 1 et i + 1 <= n et toks[i + 1].u <> "INTO"
        nat = "MERGE"
      cas u = "TABLE" et kw = "TRUNCATE"
        nat = "DELETE"
      cas (u = "EXEC" ou u = "EXECUTE") et (i = 1 ou toks[i - 1].u <> "WITH")
        nat = "EXEC"
      fincas
    finsi
    si nat <> ""
      locale k = i + 1
      && EXEC @ret = proc
      si nat = "EXEC" et k + 1 <= n et toks[k].k = "V" et toks[k + 1].o = "="
        k += 2
      finsi
      si nat = "EXEC" et k <= n et (toks[k].o = "(" ou (toks[k].k = "V" et non (k + 1 <= n et toks[k + 1].o = ".")))
        && EXEC (@sql) / EXEC @sql : SQL dynamique
        DYNAMIQUE_EXEC(R, etat, ins, k)
        info.dynamique = vrai
        i = k
        boucler
      finsi
      && TOP (n), ONLY, LATERAL… : ignorés ; FROM ( sous-requête ) : la sous-requête est lue plus loin
      si k <= n et toks[k].o = "("
        i += 1
        boucler
      finsi
      locale nm = LIRE_NOM(toks, k)
      si nm <> nul et #nm.parties = 1 et nm.fin + 1 <= n et toks[nm.fin + 1].o = "(" et nat <> "EXEC"
        && FROM OPENQUERY(…), FROM fonction_intégrée(…) : traité plus loin
        i = k
        boucler
      finsi
      si nm <> nul
        locale up = majuscule(nm.texte)
        si nat = "EXEC" et (up = "SP_EXECUTESQL" ou finitpar(up, ".SP_EXECUTESQL"))
          DYNAMIQUE_SPEXEC(R, etat, ins, nm.fin + 1)
          info.dynamique = vrai
          i = nm.fin + 1
          boucler
        finsi
        si reserves[up] = nul et etat.ctes[up] = nul
          locale vers = up
          && alias déclarés plus loin (UPDATE a SET … FROM T a)
          inserer(refs, {nom = nm, nature = nat, ligne = toks[k].l, pos = k})
        finsi
        && alias : nom [AS] alias
        locale a = nm.fin + 1
        si a <= n et toks[a].u = "AS"
          a += 1
        finsi
        si a <= n et toks[a].k = "W" et reserves[toks[a].u] = nul
          alias[toks[a].u] = nm.texte
        finsi
        i = nm.fin + 1
        boucler
      finsi
    finsi
    && OPENQUERY(serveur, 'requête') / OPENROWSET
    si j.k = "W" et (u = "OPENQUERY" ou u = "OPENDATASOURCE") et i + 2 <= n
      locale srv = NOM_PARTIE(toks[i + 2])
      locale txt = ""
      si i + 4 <= n et toks[i + 4].k = "S"
        txt = VALEUR_CHAINE(toks[i + 4].o)
      finsi
      inserer(R.refs, {ref = srv, p1 = "", p2 = "", p3 = "", p4 = srv, nature = "OPENQUERY", ligne = j.l, distant = srv, ;
                       sql = txt})
      inserer(R.dyn, {ligne = j.l, mode = "OPENQUERY", variable = srv, sql = txt, params = "", types = ""})
      inserer(info.tables, srv + "::" + COURT(txt, 40))
    finsi
    && appels de fonctions schéma.fonction( … )
    si (j.k = "W" ou j.k = "I") et i + 1 <= n
      locale fn = LIRE_NOM(toks, i)
      si fn <> nul et #fn.parties >= 2 et fn.fin + 1 <= n et toks[fn.fin + 1].o = "(" et (i = 1 ou toks[i - 1].o <> ".")
        locale prv = sisinon(i > 1, toks[i - 1].u, "")
        si prv <> "FROM" et prv <> "JOIN" et prv <> "EXEC" et prv <> "EXECUTE" et prv <> "INTO" et prv <> "APPLY" ;
           et prv <> "UPDATE" et prv <> "TABLE"
          inserer(refs, {nom = fn, nature = "APPEL", ligne = j.l, pos = i})
        finsi
        i = fn.fin + 1
        boucler
      finsi
    finsi
    && SELECT … INTO @var : affectation, pas de table
    i += 1
  fintantque
  && UPDATE alias / DELETE alias : résolution par les alias de l'instruction
  pour chaque rf dans refs
    locale nomr = rf.nom.texte
    si #rf.nom.parties = 1 et alias[majuscule(nomr)] <> nul et (rf.nature = "UPDATE" ou rf.nature = "DELETE")
      nomr = alias[majuscule(nomr)]
      rf.nom = {texte = nomr, parties = decouper(nomr, "."), fin = 0}
    finsi
    locale pr = PARTIES_REF(rf.nom.parties)
    si EST_TEMP(nomr)
      && table temporaire ou variable table : suivie, pas de dépendance
      etat.temps[majuscule(nomr)] = vrai
      inserer(info.tables, nomr)
      si rf.nature = "INSERT" ou rf.nature = "UPDATE" ou rf.nature = "DELETE" ou rf.nature = "MERGE"
        info.temp = vrai
        info.cible = nomr
        si rf.nature = "INSERT" et kw = "SELECT" et commencepar(nomr, "#")
          inserer(R.vars, {nom = nomr, genre = "table_temp", type = "SELECT INTO", ligne = rf.ligne, defaut = ""})
        finsi
      sinon
        inserer(info.lit, nomr)
      finsi
      boucler
    finsi
    inserer(R.refs, {ref = nomr, p1 = pr.p1, p2 = pr.p2, p3 = pr.p3, p4 = pr.p4, nature = rf.nature, ligne = rf.ligne, ;
                     distant = pr.p4})
    inserer(info.tables, pr.p1)
    si rf.nature = "SELECT"
      inserer(info.lit, pr.p1)
    sinonsi rf.nature = "EXEC" ou rf.nature = "APPEL"
      info.appel = vrai
    sinon
      inserer(info.ecrit, pr.p1)
      si info.cible = ""
        info.cible = pr.p1
      finsi
    finsi
  suivant
  && jointures : JOIN t [alias] ON a.c = b.d
  JOINTURES(R, ins, alias)
  && règles : CASE … END et prédicats WHERE
  REGLES_INSTR(R, ins)
  && constats
  CONSTATS(R, etat, ins, info)
  && affectation pure SELECT @x = …
  si kw = "SELECT" et n >= 3 et toks[2].k = "V" et toks[3].o = "="
    info.assigne = vrai
  finsi
  si kw = "RETURN"
    info.retourne = vrai
  finsi
  si kw = "THROW" ou kw = "RAISERROR"
    info.erreur = vrai
  finsi
retourner info

fonction VALEUR_CHAINE(o)
  && 'texte' ou N'texte' -> texte (apostrophes doublées rendues simples)
  locale d = sisinon(commencepar(o, "N"), 3, 2)
  locale t = souschaine(o, d, #o - d)
retourner remplacertexte(t, "''", "'")

procedure DECLARATIONS(R, etat, ins)
  locale toks = ins.toks
  locale n = #toks
  locale i = 2
  tantque i <= n
    locale j = toks[i]
    si j.k = "V"
      locale typ = sisinon(i + 1 <= n, toks[i + 1].u, "")
      si typ = "AS" et i + 2 <= n
        typ = toks[i + 2].u
      finsi
      si typ = "TABLE"
        inserer(R.vars, {nom = j.o, genre = "variable_table", type = "TABLE", ligne = j.l, defaut = ""})
        etat.temps[majuscule(j.o)] = vrai
      sinon
        locale def = ""
        locale k = i + 1
        tantque k <= n et toks[k].o <> ","
          si toks[k].o = "=" et k + 1 <= n
            def = toks[k + 1].o
            sortir
          finsi
          k += 1
        fintantque
        inserer(R.vars, {nom = j.o, genre = "variable", type = TYPE_A(toks, i + 1), ligne = j.l, defaut = COURT(def, 60)})
      finsi
      && saute jusqu'à la virgule de niveau 0
      locale dp = 0
      i += 1
      tantque i <= n
        si toks[i].o = "("
          dp += 1
        sinonsi toks[i].o = ")"
          dp -= 1
        sinonsi toks[i].o = "," et dp = 0
          sortir
        finsi
        i += 1
      fintantque
    sinonsi j.k = "W" et i + 1 <= n et toks[i + 1].u = "CURSOR"
      inserer(R.vars, {nom = j.o, genre = "curseur", type = "CURSOR", ligne = j.l, defaut = ""})
      etat.curseurs[j.u] = vrai
      i = n + 1
    finsi
    i += 1
  fintantque
retourner

fonction TYPE_A(toks, i)
  si i > #toks
    retourner ""
  finsi
  locale t = toks[i].o
  si toks[i].u = "AS" et i + 1 <= #toks
    i += 1
    t = toks[i].o
  finsi
  si i + 2 <= #toks et toks[i + 1].o = "("
    t = t + "(" + toks[i + 2].o
    si i + 4 <= #toks et toks[i + 3].o = ","
      t = t + "," + toks[i + 4].o
    finsi
    t = t + ")"
  finsi
retourner t

&&
&& SQL dynamique
&&

fonction EXPRESSION_DYN(etat, toks, debut, fin)
  && reconstitue une expression de chaînes : 'a' + @x + 'b' -> a{@x}b
  locale p = {}
  locale lit = 0
  locale k = debut
  locale dp = 0
  tantque k <= fin
    locale j = toks[k]
    faire cas
    cas j.k = "S" et dp = 0
      inserer(p, VALEUR_CHAINE(j.o))
      lit += 1
    cas j.o = "+" et dp = 0
      && concaténation
    cas j.k = "V" et dp = 0 et etat.dyn[j.u] <> nul
      inserer(p, etat.dyn[j.u])
      lit += 1
    cas j.k = "V" et dp = 0
      inserer(p, "{" + j.o + "}")
    autrement
      && fonction, CAST(…), QUOTENAME(…) : regroupés jusqu'au « + » de niveau 0
      locale q = {}
      tantque k <= fin
        locale x = toks[k]
        si x.o = "("
          dp += 1
        sinonsi x.o = ")"
          dp -= 1
        finsi
        si dp = 0 et x.o = "+"
          sortir
        finsi
        inserer(q, x.o)
        k += 1
      fintantque
      dp = 0
      inserer(p, "{" + COURT(joindre(q, ""), 60) + "}")
      boucler
    fincas
    k += 1
  fintantque
  si lit = 0
    retourner nul
  finsi
retourner joindre(p, "")

procedure AFFECTATIONS(R, etat, ins)
  && SET @v = … / SELECT @v = … / DECLARE @v type = …
  locale toks = ins.toks
  locale n = #toks
  pour i = 1 a n - 2
    si toks[i].k = "V" et (toks[i + 1].o = "=" ou toks[i + 1].o = "+=")
      && fin de l'expression : virgule de niveau 0 ou FROM ou fin
      locale fin = n
      locale dp = 0
      pour k = i + 2 a n
        si toks[k].o = "("
          dp += 1
        sinonsi toks[k].o = ")"
          dp -= 1
        sinonsi dp = 0 et (toks[k].o = "," ou toks[k].u = "FROM" ou toks[k].u = "WHERE")
          fin = k - 1
          sortir
        finsi
      suivant
      locale e = EXPRESSION_DYN(etat, toks, i + 2, fin)
      si e <> nul
        locale v = toks[i].u
        si toks[i + 1].o = "+=" et etat.dyn[v] <> nul
          e = etat.dyn[v] + e
        finsi
        && SQL plausible : un mot SQL dans le texte
        locale up = majuscule(e)
        si "SELECT" $ up ou "INSERT" $ up ou "UPDATE" $ up ou "DELETE" $ up ou "EXEC" $ up ou "FROM" $ up ;
           ou "WHERE" $ up ou "MERGE" $ up ou etat.dyn[v] <> nul
          etat.dyn[v] = e
        finsi
      finsi
    finsi
  suivant
retourner

procedure DYNAMIQUE_EXEC(R, etat, ins, k)
  && EXEC (@sql) / EXEC (@a + @b) / EXEC @sql
  locale toks = ins.toks
  locale n = #toks
  locale d = k
  locale f = n
  si toks[k].o = "("
    d = k + 1
    locale dp = 1
    pour m = k + 1 a n
      si toks[m].o = "("
        dp += 1
      sinonsi toks[m].o = ")"
        dp -= 1
        si dp = 0
          f = m - 1
          sortir
        finsi
      finsi
    suivant
  sinon
    f = k
  finsi
  locale sqlr = EXPRESSION_DYN(etat, toks, d, f)
  locale var_ = ""
  si d = f et toks[d].k = "V"
    var_ = toks[d].o
    si sqlr = nul
      sqlr = etat.dyn[toks[d].u]
    finsi
  finsi
  si sqlr = nul
    sqlr = "{" + COURT(TEXTE_TOKS(toks, d, f), 80) + "}"
  finsi
  inserer(R.dyn, {ligne = toks[k].l, mode = "EXEC", variable = var_, sql = sqlr, params = "", types = ""})
retourner

procedure DYNAMIQUE_SPEXEC(R, etat, ins, k)
  && EXEC sp_executesql @stmt [, N'@p int, …' [, @p = valeur…]]
  locale toks = ins.toks
  locale n = #toks
  locale args = ARGUMENTS(toks, k, n)
  si #args = 0
    retourner
  finsi
  locale a1 = args[1]
  locale sqlr = EXPRESSION_DYN(etat, toks, a1.d, a1.f)
  locale var_ = ""
  si a1.d = a1.f et toks[a1.d].k = "V"
    var_ = toks[a1.d].o
    si sqlr = nul
      sqlr = etat.dyn[toks[a1.d].u]
    finsi
  finsi
  si sqlr = nul
    sqlr = "{" + TEXTE_TOKS(toks, a1.d, a1.f) + "}"
  finsi
  locale params = ""
  locale types = ""
  si #args >= 2
    locale a2 = args[2]
    locale decl = ""
    si a2.d = a2.f et toks[a2.d].k = "S"
      decl = VALEUR_CHAINE(toks[a2.d].o)
    sinonsi a2.d = a2.f et toks[a2.d].k = "V" et etat.dyn[toks[a2.d].u] <> nul
      decl = etat.dyn[toks[a2.d].u]
    finsi
    locale noms = {}
    locale typs = {}
    pour chaque d dans decouper(decl, ",")
      locale x = rogner(d)
      si commencepar(x, "@")
        locale sp = position(" ", x)
        si sp > 0
          inserer(noms, gauche(x, sp - 1))
          inserer(typs, rogner(souschaine(x, sp + 1)))
        sinon
          inserer(noms, x)
          inserer(typs, "")
        finsi
      sinon
        && suite d'un decimal(15,2)
        si #typs > 0
          typs[#typs] = typs[#typs] + "," + x
        finsi
      finsi
    suivant
    && valeurs passées : @p = expr
    locale vals = {}
    pour a = 3 a #args
      locale d0 = args[a].d
      si d0 + 1 <= args[a].f et toks[d0].k = "V" et toks[d0 + 1].o = "="
        d0 += 2
      finsi
      inserer(vals, COURT(TEXTE_TOKS(toks, d0, args[a].f), 60))
    suivant
    locale lp = {}
    pour i = 1 a #noms
      inserer(lp, noms[i] + sisinon(i <= #typs, " " + typs[i], "") + sisinon(i <= #vals, " ← " + vals[i], ""))
    suivant
    params = joindre(lp, " ; ")
    types = joindre(typs, " ; ")
  finsi
  inserer(R.dyn, {ligne = toks[k].l, mode = "sp_executesql", variable = var_, sql = sqlr, params = params, types = types})
retourner

fonction ARGUMENTS(toks, d, n)
  && arguments séparés par des virgules de niveau 0 : liste de {d, f}
  locale args = {}
  locale dp = 0
  locale debut = d
  pour k = d a n
    locale o = toks[k].o
    si o = "("
      dp += 1
    sinonsi o = ")"
      dp -= 1
    sinonsi o = "," et dp = 0
      si k - 1 >= debut
        inserer(args, {d = debut, f = k - 1})
      finsi
      debut = k + 1
    finsi
  suivant
  si n >= debut
    inserer(args, {d = debut, f = n})
  finsi
retourner args

fonction TEXTE_TOKS(toks, d, f)
  locale p = {}
  pour k = d a min(f, #toks)
    inserer(p, toks[k].o)
  suivant
retourner joindre(p, " ")

&&
&& Jointures et règles (module 7)
&&

procedure JOINTURES(R, ins, alias)
  locale toks = ins.toks
  locale n = #toks
  pour i = 1 a n - 6
    si toks[i].u = "ON" et toks[i].k = "W"
      && a.c = b.d
      locale g = LIRE_NOM(toks, i + 1)
      si g <> nul et #g.parties >= 2 et g.fin + 1 <= n et toks[g.fin + 1].o = "="
        locale d = LIRE_NOM(toks, g.fin + 2)
        si d <> nul et #d.parties >= 2
          locale t1 = g.parties[#g.parties - 1]
          locale t2 = d.parties[#d.parties - 1]
          si alias[majuscule(t1)] <> nul
            t1 = alias[majuscule(t1)]
          finsi
          si alias[majuscule(t2)] <> nul
            t2 = alias[majuscule(t2)]
          finsi
          t1 = DERNIER(t1)
          t2 = DERNIER(t2)
          locale c1 = g.parties[#g.parties]
          locale c2 = d.parties[#d.parties]
          && ordre canonique
          si majuscule(t1 + "." + c1) > majuscule(t2 + "." + c2)
            inserer(R.jointures, {ligne = toks[i].l, t1 = majuscule(t2), c1 = majuscule(c2), t2 = majuscule(t1), c2 = majuscule(c1)})
          sinon
            inserer(R.jointures, {ligne = toks[i].l, t1 = majuscule(t1), c1 = majuscule(c1), t2 = majuscule(t2), c2 = majuscule(c2)})
          finsi
        finsi
      finsi
    finsi
  suivant
retourner

fonction DERNIER(nom)
  locale p = decouper(nom, ".")
retourner p[#p]

procedure REGLES_INSTR(R, ins)
  locale toks = ins.toks
  locale n = #toks
  locale i = 1
  tantque i <= n
    locale j = toks[i]
    si j.u = "CASE" et j.k = "W"
      && CASE … END (règle de calcul)
      locale prof = 0
      locale k = i
      tantque k <= n
        si toks[k].u = "CASE"
          prof += 1
        sinonsi toks[k].u = "END"
          prof -= 1
          si prof = 0
            sortir
          finsi
        finsi
        k += 1
      fintantque
      si k - i >= 6
        locale sous = {toks = SOUS_LISTE(toks, i, min(k, n))}
        locale norm = NORMALISE_INSTR(sous)
        inserer(R.regles, {ligne = j.l, genre = "CASE", texte = COURT(TEXTE_TOKS(toks, i, min(k, n)), 400), normalise = norm})
      finsi
      i = k + 1
      boucler
    finsi
    si j.u = "WHERE" et j.k = "W"
      locale k = i + 1
      locale dp = 0
      tantque k <= n
        si toks[k].o = "("
          dp += 1
        sinonsi toks[k].o = ")"
          dp -= 1
          si dp < 0
            sortir
          finsi
        sinonsi dp = 0 et (toks[k].u = "GROUP" ou toks[k].u = "ORDER" ou toks[k].u = "OPTION" ou toks[k].u = "UNION")
          sortir
        finsi
        k += 1
      fintantque
      si k - i >= 4
        locale sous = {toks = SOUS_LISTE(toks, i + 1, k - 1)}
        inserer(R.regles, {ligne = j.l, genre = "FILTRE", texte = COURT(TEXTE_TOKS(toks, i + 1, k - 1), 400), ;
                           normalise = NORMALISE_INSTR(sous)})
      finsi
    finsi
    i += 1
  fintantque
retourner

fonction SOUS_LISTE(t, d, f)
  locale r = {}
  pour k = d a f
    inserer(r, t[k])
  suivant
retourner r

&&
&& Phases (synoptique)
&&

fonction PHASE_INSTR(etat, ins, info)
  locale kw = ins.kw
  locale toks = ins.toks
  faire cas
  cas kw = "DECLARE"
    retourner "Déclarations"
  cas kw = "SET" et #toks >= 2 et toks[2].k = "W"
    retourner "Initialisation"                     && SET NOCOUNT, XACT_ABORT…
  cas kw = "SET" et non info.dynamique et #info.lit = 0
    retourner "Initialisation"
  cas kw = "SET"
    retourner "Chargement"
  cas kw = "RAISERROR" ou kw = "THROW"
    retourner "Contrôles"
  cas kw = "RETURN"
    retourner "Restitution"
  cas kw = "PRINT"
    retourner "Traces"
  cas kw = "CREATE" et #toks >= 3 et toks[2].u = "TABLE" et commencepar(toks[3].o, "#")
    retourner "Chargement"
  cas kw = "OPEN" ou kw = "FETCH" ou kw = "CLOSE" ou kw = "DEALLOCATE"
    retourner "Calcul"
  cas kw = "IF" ou kw = "WHILE" ou kw = "ELSE"
    retourner ""                                   && déterminé par le corps
  cas info.dynamique
    retourner "Écriture"
  cas info.appel et #info.ecrit = 0 et #info.lit = 0
    retourner "Traitements"
  cas info.assigne
    retourner "Chargement"
  fincas
  locale cible = majuscule(info.cible)
  si #info.ecrit > 0 ou (info.cible <> "" et non info.temp)
    si "HIST" $ cible ou "ARCH" $ cible ou "LOG" $ cible ou "AUDIT" $ cible
      retourner "Archivage"
    finsi
    si kw = "DELETE" ou kw = "TRUNCATE"
      retourner "Purge"
    finsi
    retourner "Écriture"
  finsi
  si info.temp
    si kw = "SELECT" ou kw = "INSERT"
      retourner "Chargement"
    finsi
    retourner "Calcul"
  finsi
  si kw = "SELECT" ou kw = "WITH"
    retourner "Restitution"
  finsi
  si kw = "EXEC" ou kw = "EXECUTE"
    retourner "Traitements"
  finsi
retourner "Traitements"

procedure PHASES_CONTROLES(R)
  && IF dont le corps lève une erreur ou sort : Contrôles ; sinon, phase dominante du corps
  locale enfants = {}
  pour chaque a dans R.ast
    locale k = chaine(a.parent)
    si enfants[k] = nul
      enfants[k] = {}
    finsi
    inserer(enfants[k], a)
  suivant
  pour i = #R.ast a 1 pas -1
    locale a = R.ast[i]
    locale e = enfants[chaine(a.id)]
    locale ctrl = a.genre = "RAISERROR" ou a.genre = "THROW" ou a.genre = "RETURN"
    locale compte = {}
    locale meilleur = ""
    locale nmax = 0
    si e <> nul
      pour chaque c dans e
        si c.leve = vrai
          ctrl = vrai
        finsi
        si c.phase <> ""
          compte[c.phase] = sisinon(compte[c.phase] = nul, 0, compte[c.phase]) + 1
          si compte[c.phase] > nmax
            nmax = compte[c.phase]
            meilleur = c.phase
          finsi
        finsi
      suivant
    finsi
    a.leve = ctrl
    si a.genre = "IF" et ctrl
      a.phase = "Contrôles"
    sinonsi a.phase = "" et a.genre <> "RACINE"
      faire cas
      cas meilleur <> ""
        a.phase = meilleur
      autrement
        a.phase = "Traitements"
      fincas
    finsi
  suivant
  && les instructions d'un corps de contrôle prennent la phase Contrôles
  pour chaque ins dans R.instructions
    si ins.phase = "" et ins.noeud <> nul
      ins.phase = ins.noeud.phase
    finsi
  suivant
retourner

&&
&& Constats (anti-modèles, modules 10 et 16)
&&

procedure CONSTAT(R, regle, niveau, ligne, message, suggestion)
  inserer(R.diag, {regle = regle, niveau = niveau, ligne = ligne, message = message, suggestion = suggestion})
retourner

procedure CONSTATS(R, etat, ins, info)
  locale toks = ins.toks
  locale n = #toks
  locale kw = ins.kw
  && SELECT *
  pour i = 2 a n
    si toks[i].o = "*" et (toks[i - 1].u = "SELECT" ou toks[i - 1].u = "DISTINCT" ou toks[i - 1].o = ".") ;
       et i < n et (toks[i + 1].u = "FROM" ou toks[i + 1].o = ",")
      CONSTAT(R, "SELECT_ETOILE", "opportunite", toks[i].l, "SELECT * : toutes les colonnes sont lues", ;
              "Lister les colonnes utiles (moins d'E/S, plans couvrants possibles, résistance aux évolutions)")
      sortir
    finsi
  suivant
  && UPDATE / DELETE sans WHERE sur une table permanente
  si (kw = "UPDATE" ou kw = "DELETE") et non info.temp
    locale avecw = faux
    pour chaque j dans toks
      si j.u = "WHERE" ou j.u = "CURRENT"
        avecw = vrai
      finsi
    suivant
    si non avecw et info.cible <> ""
      CONSTAT(R, "SANS_WHERE", "critique", ins.l1, kw + " sans WHERE sur " + info.cible, ;
              "Vérifier l'intention ; sinon TRUNCATE (si autorisé) ou un filtre explicite")
    finsi
  finsi
  && fonctions sur colonnes dans les filtres (non SARGable)
  pour i = 1 a n - 3
    si toks[i].u = "WHERE" ou toks[i].u = "AND" ou toks[i].u = "OR" ou toks[i].u = "ON"
      locale f = toks[i + 1].u
      si (f = "YEAR" ou f = "MONTH" ou f = "UPPER" ou f = "LOWER" ou f = "CONVERT" ou f = "CAST" ou f = "ISNULL" ;
          ou f = "LTRIM" ou f = "RTRIM" ou f = "SUBSTRING" ou f = "DATEPART" ou f = "LEFT" ou f = "COALESCE") ;
          et toks[i + 2].o = "("
        CONSTAT(R, "FONCTION_FILTRE", "important", toks[i].l, ;
                "Fonction " + f + "() sur une colonne filtrée : l'index ne peut pas être utilisé (filtrage tardif)", ;
                "Réécrire en intervalle (col >= @debut AND col < @fin) ou ajouter une colonne calculée indexée")
      finsi
    finsi
    si toks[i].u = "LIKE" et toks[i + 1].k = "S" et commencepar(VALEUR_CHAINE(toks[i + 1].o), "%")
      CONSTAT(R, "LIKE_DEBUT", "important", toks[i].l, "LIKE '%…' : recherche sans index possible (balayage)", ;
              "Recherche plein texte, colonne inversée indexée, ou préfixe connu")
    finsi
    si toks[i].u = "NOT" et toks[i + 1].u = "IN" et toks[i + 2].o = "(" et toks[i + 3].u = "SELECT"
      CONSTAT(R, "NOT_IN", "important", toks[i].l, "NOT IN (SELECT …) : piège des NULL et plan coûteux", ;
              "Remplacer par NOT EXISTS (corrélé)")
    finsi
  suivant
  && NOLOCK
  pour chaque j dans toks
    si j.u = "NOLOCK" ou j.u = "READUNCOMMITTED"
      CONSTAT(R, "NOLOCK", "important", j.l, "Lecture NOLOCK : lectures sales, lignes manquantes ou en double", ;
              "Isolement par instantané (READ_COMMITTED_SNAPSHOT) ou verrous adaptés")
      sortir
    finsi
    si j.u = "@@IDENTITY"
      CONSTAT(R, "IDENTITY", "important", j.l, "@@IDENTITY peut renvoyer l'identité créée par un déclencheur", ;
              "Utiliser SCOPE_IDENTITY() ou OUTPUT INSERTED.id")
    finsi
    si j.u = "GOTO"
      CONSTAT(R, "GOTO", "opportunite", j.l, "GOTO : flot de contrôle difficile à suivre", "Structurer en blocs IF / TRY")
    finsi
  suivant
  && curseurs : traitement ligne à ligne
  si kw = "DECLARE"
    pour i = 2 a n
      si toks[i].u = "CURSOR"
        locale opts = TEXTE_TOKS(toks, i, min(n, i + 6))
        CONSTAT(R, "CURSEUR", "important", toks[i].l, "Curseur " + toks[i - 1].o + " : traitement ligne à ligne", ;
                "Réécrire en traitement ensembliste (UPDATE … FROM, INSERT … SELECT, MERGE)" + ;
                sisinon("FAST_FORWARD" $ majuscule(opts) ou "LOCAL" $ majuscule(opts), "", ;
                        " ; à défaut, LOCAL FAST_FORWARD"))
        sortir
      finsi
    suivant
  finsi
  && SQL dynamique concaténé (injection)
  si info.dynamique et kw <> "SET"
    pour chaque d dans R.dyn
      si d.ligne = ins.l1 ou (d.ligne >= ins.l1 et d.ligne <= ins.l2)
        si d.mode = "EXEC" et "{@" $ d.sql et non ("QUOTENAME" $ majuscule(d.sql))
          CONSTAT(R, "INJECTION", "critique", d.ligne, "SQL dynamique concaténé avec des variables : risque d'injection SQL", ;
                  "sp_executesql avec paramètres typés ; QUOTENAME() pour les noms d'objets")
        finsi
      finsi
    suivant
  finsi
  && transaction sans gestion d'erreur
  si (kw = "BEGIN" et #toks >= 2 et (toks[2].u = "TRAN" ou toks[2].u = "TRANSACTION")) et etat.trycatch = 0
    CONSTAT(R, "TRANSACTION_SANS_TRY", "important", ins.l1, "Transaction ouverte hors d'un bloc TRY…CATCH", ;
            "Entourer de BEGIN TRY … COMMIT … END TRY BEGIN CATCH ROLLBACK ; THROW END CATCH (SET XACT_ABORT ON)")
  finsi
  && WAITFOR, SET ROWCOUNT
  si kw = "WAITFOR"
    CONSTAT(R, "WAITFOR", "opportunite", ins.l1, "WAITFOR : attente active dans le code", "Planifier par SQL Agent ou Service Broker")
  finsi
  si kw = "SET" et n >= 2 et toks[2].u = "ROWCOUNT"
    CONSTAT(R, "ROWCOUNT", "opportunite", ins.l1, "SET ROWCOUNT est obsolète pour les écritures", "Utiliser TOP (n)")
  finsi
  && boucle WHILE sur un compteur avec écritures (ligne à ligne)
  si kw = "WHILE" et non ("@@FETCH_STATUS" $ majuscule(CONDITION(ins)))
    CONSTAT(R, "BOUCLE", "opportunite", ins.l1, "Boucle WHILE : vérifier qu'un traitement ensembliste n'est pas possible", ;
            "Remplacer par une requête ensembliste ou par lots (TOP + OUTPUT)")
  finsi
retourner

&&
&& Mise en forme du SQL (module 9 : formatage automatique)
&&

fonction FORMATER_SQL(s, texte)
  && une instruction par ligne, clauses principales à la ligne, mots-clés en majuscules,
  && retrait des blocs BEGIN … END
  locale toks = JETONS_TEXTE(s, texte)
  locale instrs = INSTRUCTIONS(toks)
  locale lignes = {}
  locale retrait = 0
  locale clauses = ENSEMBLE({"FROM", "WHERE", "GROUP", "ORDER", "HAVING", "UNION", "SET", "VALUES", "OUTPUT", ;
                             "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "JOIN", "WHEN", "USING"})
  locale mots = MOTS_RESERVES()
  locale debuts = DEBUTS()
  locale colles_avant = ENSEMBLE({",", ")", ".", ";"})
  pour chaque ins dans instrs
    locale kw = ins.kw
    si kw = "END"
      retrait = max(0, retrait - 1)
    finsi
    locale marge = repliquer("    ", retrait)
    locale cur = marge
    locale dp = 0
    locale prec = ""
    locale premier = vrai
    pour chaque j dans ins.toks
      locale o = j.o
      si j.k = "W" et (mots[j.u] <> nul ou debuts[j.u] <> nul)
        o = j.u
      finsi
      locale joint = prec = "INNER" ou prec = "LEFT" ou prec = "RIGHT" ou prec = "FULL" ou prec = "CROSS" ou prec = "OUTER"
      si non premier et dp = 0 et j.k = "W" et clauses[j.u] <> nul et non (j.u = "JOIN" et joint) ;
         et non (ins.entete)
        inserer(lignes, rognerd(cur))
        cur = marge + "    "
        premier = vrai
      finsi
      si premier ou colles_avant[j.o] <> nul ou prec = "." ou prec = "(" ou prec = "@"
        cur = cur + o
      sinon
        cur = cur + " " + o
      finsi
      si j.o = "("
        dp += 1
      sinonsi j.o = ")"
        dp -= 1
      finsi
      prec = j.o
      premier = faux
    suivant
    inserer(lignes, rognerd(cur) + sisinon(kw = "MERGE", ";", ""))
    si kw = "BEGIN" et (#ins.toks = 1 ou ins.toks[2].u = "TRY" ou ins.toks[2].u = "CATCH")
      retrait += 1
    finsi
  suivant
retourner joindre(lignes, car(10))
