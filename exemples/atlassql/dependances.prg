&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atlas SQL : graphe orienté des dépendances (modules 3, 12 et 15).
&&
&& Sources du graphe : références trouvées par l'analyseur (lecture, écriture, EXEC,
&& appels, SQL dynamique reconstitué, OPENQUERY, noms à 4 parties), dépendances
&& déclarées par SQL Server (sys.sql_expression_dependencies), synonymes, clés
&& étrangères, déclencheurs, étapes des jobs SQL Agent. Les serveurs liés sont
&& traduits vers le serveur réel ; les synonymes sont traversés (« via synonyme »).
&& Chaque relation porte : nature, fréquence et volumes (statistiques d'exécution),
&& complexité estimée de l'objet appelant, inter-base, inter-serveur.

fonction GENRES_CIBLES()
retourner "('TABLE', 'VUE', 'PROCEDURE', 'FONCTION', 'SYNONYME', 'SEQUENCE', 'TYPE', 'SERVEUR_LIE', 'JOB')"

procedure RESOUDRE(s, t)
  PROGRES(t, 0.05, "Préparation…")
  RQ(s, "delete from dependances", nul)
  RQ(s, "delete from diagnostics where module = 'dependances'", nul)
  && serveurs liés : nom -> serveur réel (data source ou nom connu)
  RQ(s, "create or replace temp table liens as select l.serveur as depuis, lower(l.nom) as lien, " + ;
        "coalesce((select min(o.serveur) from objets o where lower(o.serveur) = lower(l.cible) " + ;
        "or lower(o.serveur) = lower(split_part(split_part(l.cible, ',', 1), '\\', 1))), l.cible) as vers " + ;
        "from objets l where l.genre = 'SERVEUR_LIE'", nul)
  && références brutes -> cible présumée (serveur, base, schéma, nom)
  PROGRES(t, 0.15, "Résolution des noms…")
  RQ(s, "create or replace temp table r1 as select rb.objet_id as de_id, rb.ref, rb.nature, rb.ligne, rb.p1, rb.p2, rb.p3, rb.p4, " + ;
        "o.serveur as s_serveur, o.base as s_base, o.sch as s_sch, " + ;
        "case when rb.p4 <> '' then coalesce(k.vers, rb.p4) else o.serveur end as t_serveur, " + ;
        "case when rb.p3 <> '' then rb.p3 else o.base end as t_base, rb.p2 as t_sch, rb.p1 as t_nom " + ;
        "from refs_brutes rb join objets o on o.id = rb.objet_id " + ;
        "left join liens k on k.depuis = o.serveur and k.lien = lower(rb.p4) where rb.nature <> 'OPENQUERY'", nul)
  RQ(s, "create or replace temp table r2 as select r.*, " + ;
        "coalesce((select min(x.id) from objets x where lower(x.serveur) = lower(r.t_serveur) and lower(x.base) = lower(r.t_base) " + ;
        "and lower(x.sch) = lower(coalesce(nullif(r.t_sch, ''), r.s_sch)) and lower(x.nom) = lower(r.t_nom) and x.genre in " + GENRES_CIBLES() + "), " + ;
        "(select min(x.id) from objets x where lower(x.serveur) = lower(r.t_serveur) and lower(x.base) = lower(r.t_base) " + ;
        "and lower(x.sch) = 'dbo' and lower(x.nom) = lower(r.t_nom) and coalesce(r.t_sch, '') = '' and x.genre in " + GENRES_CIBLES() + ")) as vers_id " + ;
        "from r1 r", nul)
  RQ(s, "insert into dependances select r.de_id, r.vers_id, " + ;
        "r.t_serveur || '.' || r.t_base || '.' || coalesce(nullif(r.t_sch, ''), r.s_sch) || '.' || r.t_nom, " + ;
        "r.nature, r.ligne, lower(r.t_base) <> lower(r.s_base), lower(r.t_serveur) <> lower(r.s_serveur), 'analyse', null, null, null, null " + ;
        "from r2 r where r.vers_id is not null or not (lower(coalesce(r.t_sch, '')) in ('sys', 'information_schema') " + ;
        "or lower(r.t_nom) like 'sp\\_%' escape '\\' or lower(r.t_base) in ('msdb', 'master', 'tempdb'))", nul)
  && OPENQUERY : le serveur lié, puis les tables citées dans la requête distante
  PROGRES(t, 0.35, "Requêtes distantes (OPENQUERY)…")
  RQ(s, "insert into dependances select rb.objet_id, l.id, rb.p4, 'OPENQUERY', rb.ligne, false, true, 'analyse', null, null, null, null " + ;
        "from refs_brutes rb join objets o on o.id = rb.objet_id left join objets l on l.genre = 'SERVEUR_LIE' " + ;
        "and l.serveur = o.serveur and lower(l.nom) = lower(rb.p4) where rb.nature = 'OPENQUERY'", nul)
  RQ(s, "insert into dependances select q.objet_id, (select min(x.id) from objets x where lower(x.serveur) = lower(q.vers) " + ;
        "and lower(x.nom) = lower(q.parts[len(q.parts)]) and (len(q.parts) < 2 or lower(x.sch) = lower(q.parts[len(q.parts) - 1])) " + ;
        "and (len(q.parts) < 3 or lower(x.base) = lower(q.parts[len(q.parts) - 2])) and x.genre in ('TABLE', 'VUE')), " + ;
        "q.vers || '.' || q.nom, 'SELECT', q.ligne, true, true, 'openquery', null, null, null, null " + ;
        "from (select rb.objet_id, rb.ligne, coalesce(k.vers, rb.p4) as vers, x.nom, string_split(replace(replace(x.nom, '[', ''), ']', ''), '.') as parts " + ;
        "from refs_brutes rb join objets o on o.id = rb.objet_id left join liens k on k.depuis = o.serveur and k.lien = lower(rb.p4), " + ;
        "unnest(regexp_extract_all(rb.sql, '(?i)\\b(?:from|join)\\s+([\\w\\.\\[\\]]+)', 1)) as x(nom) where rb.nature = 'OPENQUERY') q", nul)
  && synonymes : synonyme -> objet cible
  PROGRES(t, 0.5, "Synonymes…")
  RQ(s, "insert into dependances select y.id, (select min(x.id) from objets x where lower(x.serveur) = lower(q.srv) " + ;
        "and lower(x.base) = lower(q.b) and lower(x.sch) = lower(q.sc) and lower(x.nom) = lower(q.n) and x.genre in ('TABLE', 'VUE', 'PROCEDURE', 'FONCTION')), " + ;
        "q.srv || '.' || q.b || '.' || q.sc || '.' || q.n, 'SYNONYME', null, lower(q.b) <> lower(y.base), lower(q.srv) <> lower(y.serveur), " + ;
        "'synonyme', null, null, null, null from objets y, " + ;
        "(select y2.id as yid, string_split(replace(replace(y2.cible, '[', ''), ']', ''), '.') as p from objets y2 where y2.genre = 'SYNONYME') pp, " + ;
        "lateral (select case when len(pp.p) >= 4 then coalesce((select vers from liens k where k.depuis = y.serveur and k.lien = lower(pp.p[1])), pp.p[1]) " + ;
        "else y.serveur end as srv, case when len(pp.p) >= 3 then pp.p[len(pp.p) - 2] else y.base end as b, " + ;
        "case when len(pp.p) >= 2 then pp.p[len(pp.p) - 1] else 'dbo' end as sc, pp.p[len(pp.p)] as n) q " + ;
        "where y.genre = 'SYNONYME' and pp.yid = y.id", nul)
  && traversée des synonymes : A -> synonyme -> cible devient aussi A -> cible
  RQ(s, "insert into dependances select a.de_id, b.vers_id, b.vers_nom, a.nature, a.ligne, " + ;
        "lower(c.base) <> lower(d.base), lower(c.serveur) <> lower(d.serveur), 'via synonyme', null, null, null, null " + ;
        "from dependances a join objets y on y.id = a.vers_id and y.genre = 'SYNONYME' " + ;
        "join dependances b on b.de_id = y.id and b.nature = 'SYNONYME' and b.vers_id is not null " + ;
        "join objets c on c.id = a.de_id join objets d on d.id = b.vers_id", nul)
  && clés étrangères, déclencheurs
  PROGRES(t, 0.65, "Clés étrangères et déclencheurs…")
  RQ(s, "insert into dependances select distinct c.objet_id, (select min(x.id) from objets x where x.serveur = c.serveur " + ;
        "and lower(x.base) = lower(split_part(c.fk_vers, '.', 1)) and lower(x.sch) = lower(split_part(c.fk_vers, '.', 2)) " + ;
        "and lower(x.nom) = lower(split_part(c.fk_vers, '.', 3)) and x.genre = 'TABLE'), " + ;
        "c.serveur || '.' || c.fk_vers, 'FK', null, lower(split_part(c.fk_vers, '.', 1)) <> lower(c.base), false, 'catalogue', " + ;
        "null, null, null, null from colonnes c where c.fk_vers is not null and c.fk_vers <> ''", nul)
  RQ(s, "insert into dependances select o.id, o.parent_id, o.parent_nom, 'DECLENCHEUR', null, false, false, 'catalogue', null, null, null, null " + ;
        "from objets o where o.genre = 'DECLENCHEUR' and o.parent_id is not null", nul)
  && dépendances déclarées par SQL Server, absentes de l'analyse
  RQ(s, "insert into dependances select o.id, x.id, e.ref_sch || '.' || e.ref_nom, 'SELECT', null, " + ;
        "coalesce(nullif(e.ref_base, ''), o.base) <> o.base, e.ref_serveur <> '', 'catalogue', null, null, null, null " + ;
        "from ext_dependances e join objets o on o.source_id = e.source_id and o.serveur = e.serveur and o.base = e.base " + ;
        "and o.sch = e.sch and o.nom = e.nom left join objets x on x.serveur = o.serveur and lower(x.base) = lower(coalesce(nullif(e.ref_base, ''), o.base)) " + ;
        "and lower(x.sch) = lower(coalesce(nullif(e.ref_sch, ''), o.sch)) and lower(x.nom) = lower(e.ref_nom) and x.genre in " + GENRES_CIBLES() + " " + ;
        "where not exists (select 1 from dependances d where d.de_id = o.id and d.vers_id = x.id)", nul)
  && fréquence, volumes, complexité
  PROGRES(t, 0.8, "Fréquences et volumes…")
  RQ(s, "update dependances d set frequence = s.ex, volume_moy = s.vm, volume_max = s.vx from (select objet_id, sum(executions) as ex, " + ;
        "sum(lignes) / greatest(sum(executions), 1) as vm, greatest(max(lignes_max), sum(lignes) / greatest(sum(executions), 1)) as vx " + ;
        "from stats_requetes where objet_id is not null group by objet_id) s where s.objet_id = d.de_id", nul)
  RQ(s, "update dependances d set complexite = m.complexite from metriques m where m.objet_id = d.de_id", nul)
  && références introuvables
  RQ(s, "insert into diagnostics select d.de_id, 'dependances', 'REF_INTROUVABLE', 'important', " + ;
        "'Référence introuvable : ' || d.vers_nom || ' (' || d.nature || ')', " + ;
        "'Objet supprimé, renommé, base non analysée ou nom construit dynamiquement : vérifier', '', d.ligne " + ;
        "from dependances d where d.vers_id is null and d.nature not in ('OPENQUERY')", nul)
  locale n = RV(s, "select count(*) from dependances", nul)
  locale nr = RV(s, "select count(*) from dependances where vers_id is null", nul)
  locale nx = RV(s, "select count(*) from dependances where interserveur", nul)
  t.message = NB(n) + " relations, " + nx + " inter-serveurs, " + nr + " non résolues"
retourner

&&
&& Interrogation du graphe (module 3)
&&

fonction NATURES_QUESTION(q)
  faire cas
  cas q = "lit"
    retourner "('SELECT')"
  cas q = "ecrit"
    retourner "('INSERT', 'UPDATE', 'DELETE', 'MERGE')"
  cas q = "supprime"
    retourner "('DELETE')"
  cas q = "metajour"
    retourner "('UPDATE', 'MERGE')"
  cas q = "insere"
    retourner "('INSERT', 'MERGE')"
  cas q = "appelle"
    retourner "('EXEC', 'APPEL', 'OPENQUERY')"
  fincas
retourner ""

fonction RELATIONS(id, sens, question)
  && sens : "sortant" (ce que l'objet utilise) ou "entrant" (qui l'utilise)
  locale filtre = ""
  si question <> nul et question <> ""
    filtre = " and d.nature in " + NATURES_QUESTION(question)
  finsi
  si sens = "sortant"
    retourner RQ(nul, "select d.nature, d.vers_id as id, coalesce(o.serveur || '.' || o.base || '.' || o.sch || '.' || o.nom, d.vers_nom) as nom, " + ;
      "o.genre, d.origine, d.interbase, d.interserveur, max(d.frequence) as frequence, max(d.volume_moy) as volume_moy, " + ;
      "max(d.volume_max) as volume_max, max(d.complexite) as complexite, min(d.ligne) as ligne, count(*) as n " + ;
      "from dependances d left join objets o on o.id = d.vers_id where d.de_id = ?" + filtre + ;
      " group by all order by d.nature, nom", {id})
  finsi
retourner RQ(nul, "select d.nature, d.de_id as id, o.serveur || '.' || o.base || '.' || o.sch || '.' || o.nom as nom, o.genre, d.origine, " + ;
  "d.interbase, d.interserveur, max(d.frequence) as frequence, max(d.volume_moy) as volume_moy, max(d.volume_max) as volume_max, " + ;
  "max(d.complexite) as complexite, min(d.ligne) as ligne, count(*) as n " + ;
  "from dependances d join objets o on o.id = d.de_id where d.vers_id = ?" + filtre + " group by all order by d.nature, nom", {id})

fonction IMPACT_TRANSITIF(id, profondeur)
  && objets touchés si id change : tous ceux qui en dépendent, directement ou non
retourner RQ(nul, "with recursive amont(id, niveau, chemin) as (select ?::integer, 0, [?::integer] " + ;
  "union all select d.de_id, a.niveau + 1, list_append(a.chemin, d.de_id) from amont a join dependances d on d.vers_id = a.id " + ;
  "where a.niveau < ? and not list_contains(a.chemin, d.de_id)) " + ;
  "select o.id, o.serveur, o.base, o.sch, o.nom, o.genre, min(a.niveau) as niveau from amont a join objets o on o.id = a.id " + ;
  "where a.id <> ? group by all order by niveau, o.genre, o.nom", {id, id, sisinon(profondeur = nul, 6, profondeur), id})

fonction IMPACT_COLONNE(nom, table_id)
  && module 15 : où une colonne (ou un nom) est citée, par genre d'objet
  locale motif = "(?i)(^|[^A-Za-z0-9_@#$])\\[?" + remplacertexte(nom, "_", "_") + "\\]?($|[^A-Za-z0-9_$#])"
  locale lignes = RQ(nul, "select o.id, o.serveur, o.base, o.sch, o.nom, o.genre, " + ;
    "len(regexp_extract_all(o.definition, ?)) as occurrences from objets o where o.definition is not null " + ;
    "and regexp_matches(o.definition, ?) order by o.genre, o.nom", {motif, motif})
retourner lignes

fonction OCCURRENCES_LIGNES(id, nom)
  && lignes d'un module où le nom apparaît : {ligne, avant, apres} (aperçu du renommage)
  locale motif = "(?i)(^|[^A-Za-z0-9_@#$])(\\[?)" + nom + "(\\]?)($|[^A-Za-z0-9_$#])"
retourner RQ(nul, "select l.n as ligne, l.t as avant from (select unnest(string_split(definition, chr(10))) as t, " + ;
  "generate_subscripts(string_split(definition, chr(10)), 1) as n from objets where id = ?) l where regexp_matches(l.t, ?) order by l.n", {id, motif})

&&
&& Flux de données (module 12) : table lue -> traitement -> table écrite
&&

fonction FLUX(filtre_base)
  locale f = ""
  locale p = {}
  si filtre_base <> nul et filtre_base <> ""
    f = " and (lower(l.base) = lower(?) or lower(e.base) = lower(?))"
    p = {filtre_base, filtre_base}
  finsi
retourner RQ(nul, "select l.id as src_id, l.serveur || '.' || l.base || '.' || l.sch || '.' || l.nom as source, " + ;
  "e.id as dst_id, e.serveur || '.' || e.base || '.' || e.sch || '.' || e.nom as destination, " + ;
  "p.id as proc_id, p.sch || '.' || p.nom as traitement, p.genre, " + ;
  "max(coalesce(dw.volume_moy, dr.volume_moy, 0)) * max(coalesce(dw.frequence, 1)) as volume, max(dw.nature) as nature " + ;
  "from dependances dr join dependances dw on dw.de_id = dr.de_id and dw.nature in ('INSERT', 'UPDATE', 'MERGE') " + ;
  "join objets l on l.id = dr.vers_id and l.genre in ('TABLE', 'VUE') join objets e on e.id = dw.vers_id and e.genre = 'TABLE' " + ;
  "join objets p on p.id = dr.de_id where dr.nature = 'SELECT' and l.id <> e.id" + f + ;
  " group by all order by volume desc", p)
