&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : mutualisation par empreintes (lot 2).
&&
&& L'empreinte d'une requête est lue dans son arbre syntaxique (DuckDB) : tables
&& lues, conditions de jointure, clés de regroupement, présence de filtres. Des
&& requêtes différentes qui partagent la même jointure, ou agrègent au même grain
&& les mêmes tables, peuvent s'appuyer sur un objet commun précalculé :
&&   - jointure commune -> table (ou vue) de jointure, lue par chacune ;
&&   - même grain d'agrégation -> table d'agrégats au grain commun, filtres en colonnes.
&& Le gain est estimé à partir des durées de l'historique (estimation prudente : la
&& part du temps passée dans la jointure ou le balayage est économisée).

fonction EMPREINTE(sql)
  && {tables, jointures, groupes, filtre, signature, de} ou nul
  locale a = AST(sql)
  si a = nul ou non a.ok
    retourner nul
  finsi
  locale n = a.arbre
  si n["type"] <> "SELECT_NODE" ou n["from_table"] = nul
    retourner nul
  finsi
  locale e = {tables = {}, jointures = {}, groupes = {}, filtre = n["where_clause"] <> nul, de = ""}
  EMPREINTE_FROM(sql, n["from_table"], "$.statements[0].node.from_table", e)
  si #e.tables = 0
    retourner nul
  finsi
  trier(e.tables)
  trier(e.jointures)
  locale ge = n["group_expressions"]
  si ge <> nul
    pour i = 1 a #ge
      inserer(e.groupes, minuscule(EXPR_SQL(sql, "$.statements[0].node.group_expressions[" + (i - 1) + "]")))
    suivant
  finsi
  trier(e.groupes)
  e.agrege = #e.groupes > 0 ou n["aggregate_handling"] = "FORCE_AGGREGATES"
  e.signature = joindre(e.tables, ",") + " | " + joindre(e.jointures, " & ")
  e.de = FROM_SQL(sql, "$.statements[0].node.from_table")
retourner e

procedure EMPREINTE_FROM(sql, ft, ch, e)
  locale t = ft["type"]
  si t = "BASE_TABLE"
    inserer(e.tables, minuscule(NOM_TABLE(ft)))
  sinonsi t = "JOIN"
    EMPREINTE_FROM(sql, ft["left"], ch + ".left", e)
    EMPREINTE_FROM(sql, ft["right"], ch + ".right", e)
    si ft["condition"] <> nul
      inserer(e.jointures, minuscule(EXPR_SQL(sql, ch + ".condition")))
    sinonsi ft["using_columns"] <> nul et #ft["using_columns"] > 0
      inserer(e.jointures, "using " + minuscule(joindre(ft["using_columns"], ",")))
    finsi
  sinonsi t = "TABLE_FUNCTION"
    inserer(e.tables, minuscule(EXPR_SQL(sql, ch + ".function")))
  finsi
retourner

fonction REGLES_EMPREINTES()
  locale l = {}
  && requêtes distinctes réussies de l'historique, avec leur coût cumulé
  locale formes = {}
  locale ordre = {}
  pour chaque h dans projet.historique
    si h.ok et EST_REQUETE(h.sql)
      locale f = NORMALISER(h.sql)
      si formes[f] = nul
        formes[f] = {sql = h.sql, n = 0, duree = 0}
        inserer(ordre, f)
      finsi
      formes[f].n += 1
      formes[f].duree += sisinon(h.duree = nul, 0, h.duree) / 1000
    finsi
  suivant
  && empreintes regroupées par jointure (au moins deux tables)
  locale groupes = {}
  locale gordre = {}
  locale grains = {}
  locale grordre = {}
  pour chaque f dans ordre
    locale x = formes[f]
    locale e = EMPREINTE(x.sql)
    si e <> nul
      x.empreinte = e
      si #e.tables >= 2 et #e.jointures >= 1
        si groupes[e.signature] = nul
          groupes[e.signature] = {}
          inserer(gordre, e.signature)
        finsi
        inserer(groupes[e.signature], x)
      finsi
      si e.agrege et #e.groupes > 0
        locale cle = e.signature + " # " + joindre(e.groupes, ",")
        si grains[cle] = nul
          grains[cle] = {}
          inserer(grordre, cle)
        finsi
        inserer(grains[cle], x)
      finsi
    finsi
  suivant
  locale k = 0
  pour chaque s dans gordre
    locale g = groupes[s]
    si #g >= 2
      k += 1
      locale total = 0
      locale execs = 0
      pour chaque x dans g
        total += x.duree
        execs += x.n
      suivant
      locale e = g[1].empreinte
      locale apres = total * 0.4
      locale r = RECO(sisinon(total >= 2, "Important", "Opportunité"), "Mutualisation", ;
        "Jointure commune à " + #g + " requêtes (" + joindre(e.tables, " ⋈ ") + ")", ;
        #g + " requêtes différentes (" + execs + " exécutions, " + MS(total) + ") refont la même jointure " + ;
        joindre(e.jointures, " et ") + ". Une table de jointure calculée une fois (et rafraîchie par le " + ;
        "planificateur) leur évite de relire et rapprocher les tables à chaque fois.", ;
        "≈ " + arrondi((total - apres) * 100 / max(total, 0.000001)) + " % (" + MS(total) + " → " + MS(apres) + ", estimation)", ;
        "Matérialiser la jointure, puis réécrire les requêtes sur cette table (colonnes préfixées par leur table d'origine).", ;
        "CREATE OR REPLACE TABLE jointure_" + k + " AS" + car(10) + "SELECT *" + car(10) + "FROM " + e.de + ";" + car(10) + ;
        "-- requêtes concernées :" + car(10) + LISTE_REQUETES(g))
      r.actuel = total
      r.apres = apres
      inserer(l, r)
    finsi
  suivant
  locale c = 0
  pour chaque cle dans grordre
    locale g = grains[cle]
    si #g >= 2
      c += 1
      locale total = 0
      pour chaque x dans g
        total += x.duree
      suivant
      locale e = g[1].empreinte
      locale apres = #g * 0.002
      locale r = RECO("Opportunité", "Mutualisation", ;
        "Même grain d'agrégation pour " + #g + " requêtes (" + joindre(e.groupes, ", ") + ")", ;
        "Ces requêtes regroupent les mêmes tables par " + joindre(e.groupes, ", ") + " et ne diffèrent que par " + ;
        "leurs mesures ou leurs filtres. Une table d'agrégats à ce grain, avec les mesures de toutes, " + ;
        "les sert en quelques millisecondes.", ;
        MS(total) + " → ≈ " + MS(apres), ;
        "Créer la table d'agrégats au grain commun (ajouter les colonnes filtrées au grain si besoin).", ;
        "CREATE OR REPLACE TABLE agregats_" + c + " AS" + car(10) + "SELECT " + joindre(e.groupes, ", ") + ;
        ", count(*) AS nb /* , sum(...) AS ... */" + car(10) + "FROM " + e.de + car(10) + "GROUP BY ALL;" + car(10) + ;
        "-- requêtes concernées :" + car(10) + LISTE_REQUETES(g))
      r.actuel = total
      r.apres = apres
      inserer(l, r)
    finsi
  suivant
retourner l

fonction LISTE_REQUETES(g)
  locale l = {}
  pour chaque x dans g
    inserer(l, "--   " + gauche(RESUME(x.sql), 100))
  suivant
retourner joindre(l, car(10))
