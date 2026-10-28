&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : assistant IA (lot 3).
&&
&& Trois moteurs, au choix (Réglages…) :
&&   - « règles »  : intégré, sans modèle : explication de plan, d'erreur,
&&                   réécriture (forme normalisée et conseils), modèle à partir
&&                   d'une description structurée ;
&&   - « local »   : modèle GGUF (Llama 3, Mistral, Qwen…) chargé par le paquet llm,
&&                   rien ne quitte le poste ;
&&   - « http »    : serveur compatible OpenAI (/v1/chat/completions : Ollama,
&&                   llama.cpp, LM Studio, vLLM, fournisseurs en ligne) ; la clé
&&                   est lue dans une variable d'environnement, jamais enregistrée.
&& Le contexte envoyé au modèle : schéma des connexions (tables et colonnes), requête
&& courante, dernier plan profilé, dernière erreur. Le SQL proposé (bloc ```sql) peut
&& être inséré dans l'éditeur ; un modèle généré est ouvert dans le concepteur.

fonction ACTIONS_IA()
retourner {{code = "question", libelle = "Question libre"}, ;
           {code = "sql", libelle = "Écrire le SQL d'une question"}, ;
           {code = "plan", libelle = "Expliquer le dernier plan"}, ;
           {code = "reecrire", libelle = "Réécrire la requête courante"}, ;
           {code = "erreur", libelle = "Expliquer la dernière erreur"}, ;
           {code = "modele", libelle = "Générer un modèle de données"}}

procedure CONSTRUIRE_ASSISTANT(page)
  globale ia
  ia = {echanges = {}, modele = nul, chemin = "", dernier_sql = nul, courant = ""}
  locale haut = page:ajouter(ui.rangee())
  haut.ancrage = "haut"
  ia.action = haut:ajouter(ui.combo())
  ia.action.largeurfixe = 250
  pour chaque a dans ACTIONS_IA()
    ia.action:ajouter(a.libelle)
  suivant
  ia.action:selectionner(1)
  OUTIL(haut, "Insérer le SQL", @IA_INSERER, "Insère le dernier bloc SQL proposé dans une nouvelle requête")
  OUTIL(haut, "Effacer", @IA_EFFACER, "Efface la conversation")
  OUTIL(haut, "Réglages…", @IA_REGLAGES, "Moteur : règles intégrées, modèle local GGUF ou serveur HTTP")
  ia.moteur = haut:ajouter(ui.etiquette(""))
  ia.moteur.poids = 1
  locale bas_ = page:ajouter(ui.rangee())
  bas_.ancrage = "bas"
  ia.question = bas_:ajouter(ui.saisie{indication = "Votre question (Entrée ou Envoyer) ; vide : l'action choisie sur la requête courante"})
  ia.question.poids = 1
  ia.question.surtouchebas = @IA_TOUCHE
  locale be = bas_:ajouter(ui.bouton("Envoyer"))
  be.surclic = @IA_ENVOYER
  ia.fil = page:ajouter(ui.markdown("**Assistant** — choisissez une action, puis Envoyer. " + ;
                                    "Sans modèle configuré, l'assistant utilise ses règles intégrées."))
  ia.fil.ancrage = "centre"
  IA_ETIQUETTE()
retourner

procedure IA_ETIQUETTE
  locale m = MOTEUR_IA()
  faire cas
  cas m = "local"
    ia.moteur.libelle = "Moteur : modèle local " + fichier.nom(sisinon(reglages.ia_modele = nul, "", reglages.ia_modele))
  cas m = "http"
    ia.moteur.libelle = "Moteur : " + sisinon(reglages.ia_nom = nul, "", reglages.ia_nom) + " @ " + sisinon(reglages.ia_url = nul, "", reglages.ia_url)
  autrement
    ia.moteur.libelle = "Moteur : règles intégrées (sans modèle)"
  fincas
retourner

fonction MOTEUR_IA()
  locale m = reglages.ia_moteur
  si m = "local" et reglages.ia_modele <> nul et reglages.ia_modele <> "" et fichier.existe(reglages.ia_modele)
    retourner "local"
  finsi
  si m = "http" et reglages.ia_url <> nul et reglages.ia_url <> ""
    retourner "http"
  finsi
retourner "regles"

procedure IA_TOUCHE(ev)
  si ev.touche = 13 ou ev.touche = 1073741912
    IA_ENVOYER(nul)
  finsi
retourner

procedure IA_EFFACER(ev)
  ia.echanges = {}
  ia.dernier_sql = nul
  IA_AFFICHER()
retourner

procedure IA_AFFICHER
  locale nl = car(10)
  locale l = {}
  pour chaque e dans ia.echanges
    si e.role = "utilisateur"
      inserer(l, "> **Vous** — " + remplacertexte(e.texte, nl, nl + "> "))
    sinon
      inserer(l, "**Assistant** *(" + e.moteur + ")*" + nl + nl + e.texte)
    finsi
  suivant
  ia.fil.valeur = joindre(l, nl + nl + "---" + nl + nl)
  ia.fil:defilera("fin")
retourner

fonction ACTION_IA()
  locale i = ia.action:selection()
retourner ACTIONS_IA()[max(1, sisinon(i = nul, 1, i))].code

&&
&& Contexte
&&

fonction CONTEXTE_SCHEMA(maxtables)
  locale nl = car(10)
  locale l = {}
  locale n = 0
  pour chaque c dans projet.connexions
    locale cat = catalogue[majuscule(c.nom)]
    si cat <> nul
      locale k = CONNECTEUR(c.type)
      pour chaque s dans cat.schemas
        pour chaque t dans s.tables
          si n < maxtables
            locale cols = {}
            pour chaque col dans t.colonnes
              inserer(cols, col.nom + " " + minuscule(col.type) + sisinon(contient(sisinon(t.pk = nul, {}, t.pk), col.nom), " PK", ""))
            suivant
            locale fk = ""
            pour chaque f dans t.fk
              fk = fk + " ; FK " + joindre(f.colonnes, ",") + " -> " + f.table
            suivant
            inserer(l, NOM_QUALIFIE(ALIAS(c), s.nom, t.nom, k <> nul et k.mode <> "catalogue") + "(" + gauche(joindre(cols, ", "), 600) + ")" + ;
                    sisinon(t.lignes = nul, "", " ~" + t.lignes + " lignes") + fk)
            n += 1
          finsi
        suivant
        pour chaque v dans s.vues
          si n < maxtables
            locale vc = {}
            pour chaque col dans v.colonnes
              inserer(vc, sisinon(type(col) = "table", col.nom, chaine(col)))
            suivant
            inserer(l, "vue " + NOM_QUALIFIE(ALIAS(c), s.nom, v.nom, k <> nul et k.mode <> "catalogue") + "(" + gauche(joindre(vc, ", "), 300) + ")")
            n += 1
          finsi
        suivant
      suivant
    finsi
  suivant
retourner joindre(l, nl)

fonction RESUME_PLAN(p)
  si p = nul
    retourner ""
  finsi
  locale tri = copier(p.ops)
  trier(tri, @PLUS_LENT)
  locale tot = max(p.total, 0.000001)
  locale l = {"Latence " + arrondi(p.latence * 1000, 1) + " ms ; lignes lues " + p.lues}
  pour i = 1 a min(8, #tri)
    locale o = tri[i]
    locale info = {}
    pour chaque x dans o.info
      inserer(info, x.clef + "=" + gauche(remplacertexte(x.valeur, car(10), " "), 80))
    suivant
    inserer(l, o.nom + " : " + arrondi(o.temps * 1000, 2) + " ms (" + arrondi(o.temps * 100 / tot) + " %), " + ;
            o.lignes + " lignes" + sisinon(#info > 0, " [" + joindre(info, " ; ") + "]", ""))
  suivant
retourner joindre(l, car(10))

fonction SYSTEME_IA()
retourner "Tu es l'assistant de DuckDB Studio, expert de DuckDB et de son dialecte SQL. " + ;
          "Réponds en français, de façon concise et précise. Quand tu proposes du SQL, écris-le " + ;
          "dans un bloc ```sql et utilise les noms qualifiés des tables du schéma fourni. " + ;
          "N'invente ni table ni colonne : si une information manque, dis-le."

fonction PROMPT_IA(action, question)
  locale nl = car(10)
  locale s = "Schéma disponible :" + nl + CONTEXTE_SCHEMA(80) + nl + nl
  locale req = INSTRUCTION_COURANTE()
  faire cas
  cas action = "sql"
    retourner s + "Écris une requête DuckDB qui répond à : " + question
  cas action = "plan"
    retourner s + "Requête :" + nl + "```sql" + nl + sisinon(dernierplan = nul, "", dernierplan.sql) + nl + "```" + nl + ;
              "Profil d'exécution (EXPLAIN ANALYZE, opérateurs les plus coûteux) :" + nl + RESUME_PLAN(dernierplan) + nl + nl + ;
              "Explique ce plan simplement, identifie le goulet d'étranglement et propose des optimisations concrètes." + ;
              sisinon(question = "", "", nl + question)
  cas action = "reecrire"
    retourner s + "Réécris cette requête pour qu'elle soit plus lisible et plus rapide, sans changer son résultat, " + ;
              "puis explique les changements :" + nl + "```sql" + nl + sisinon(req = nul, "", req) + nl + "```" + ;
              sisinon(question = "", "", nl + question)
  cas action = "erreur"
    retourner s + "Requête :" + nl + "```sql" + nl + sisinon(derniereerreur = nul, "", derniereerreur.sql) + nl + "```" + nl + ;
              "Erreur DuckDB : " + sisinon(derniereerreur = nul, "", derniereerreur.message) + nl + ;
              "Explique la cause et donne la requête corrigée."
  cas action = "modele"
    retourner "Conçois un modèle de données DuckDB pour : " + question + nl + ;
              "Donne uniquement un script ```sql de CREATE TABLE avec clés primaires (PRIMARY KEY) et " + ;
              "étrangères (REFERENCES), types DuckDB, dans l'ordre des dépendances, puis une phrase de commentaire."
  fincas
retourner s + sisinon(req = nul, "", "Requête courante :" + nl + "```sql" + nl + req + nl + "```" + nl) + "Question : " + question

&&
&& Envoi
&&

procedure IA_ENVOYER(ev)
  locale action = ACTION_IA()
  locale question = rogner(sisinon(ia.question.valeur = nul, "", ia.question.valeur))
  si (action = "question" ou action = "sql" ou action = "modele") et question = ""
    STATUT("Assistant : écrivez votre question (ou la description du modèle).")
    retourner
  finsi
  si action = "plan" et dernierplan = nul
    STATUT("Assistant : profilez d'abord une requête (F6).")
    retourner
  finsi
  si action = "erreur" et derniereerreur = nul
    STATUT("Assistant : aucune erreur récente.")
    retourner
  finsi
  locale libelle = ACTIONS_IA()[max(1, ia.action:selection())].libelle
  inserer(ia.echanges, {role = "utilisateur", texte = "*" + libelle + "*" + sisinon(question = "", "", " — " + question)})
  ia.question.valeur = ""
  bas.valeur = INDEX_BAS("Assistant")
  locale m = MOTEUR_IA()
  locale rep = {role = "assistant", texte = "…", moteur = m}
  inserer(ia.echanges, rep)
  IA_AFFICHER()
  locale t0 = systeme.horloge()
  essayer
    faire cas
    cas m = "local"
      rep.texte = IA_LOCAL(PROMPT_IA(action, question), rep)
    cas m = "http"
      rep.texte = IA_HTTP(PROMPT_IA(action, question))
    autrement
      rep.texte = IA_REGLES(action, question)
    fincas
  capturer e
    rep.texte = "**Le moteur « " + m + " » a échoué :** " + e + car(10) + car(10) + "Réponse des règles intégrées :" + ;
                car(10) + car(10) + IA_REGLES(action, question)
    rep.moteur = "règles"
  finessayer
  rep.moteur = rep.moteur + ", " + arrondi(systeme.horloge() - t0, 1) + " s"
  ia.dernier_sql = DERNIER_BLOC_SQL(rep.texte)
  IA_AFFICHER()
  si action = "modele" et ia.dernier_sql <> nul
    NOUVELLE_REQUETE()
    ed:fixertexte(ia.dernier_sql)
    SCHEMA_DEPUIS_SCRIPT(nul)
    STATUT("Modèle généré : script dans une nouvelle requête, modèle dans le concepteur de schéma.")
  finsi
retourner

fonction DERNIER_BLOC_SQL(t)
  && contenu du dernier bloc ```sql (ou ```) d'une réponse
  locale r = nul
  locale reste = t
  tantque position("```", reste) > 0
    locale p = position("```", reste)
    locale apres = souschaine(reste, p + 3)
    locale fin_ligne = position(car(10), apres)
    si fin_ligne = 0
      retourner r
    finsi
    locale langue = minuscule(rogner(gauche(apres, fin_ligne - 1)))
    locale corps = souschaine(apres, fin_ligne + 1)
    locale q = position("```", corps)
    si q = 0
      retourner r
    finsi
    locale bloc = rogner(gauche(corps, q - 1))
    si langue = "sql" ou (langue = "" et contient({"select", "with", "create", "insert", "update", "delete", "copy", "alter", "from"}, PREMIER_MOT(bloc)))
      r = bloc
    finsi
    reste = souschaine(corps, q + 3)
  fintantque
retourner r

procedure IA_INSERER(ev)
  si ia.dernier_sql = nul
    STATUT("Aucun SQL proposé par l'assistant.")
    retourner
  finsi
  NOUVELLE_REQUETE()
  ed:fixertexte(ia.dernier_sql + car(10))
  vues.valeur = 1
retourner

fonction IA_LOCAL(prompt, rep)
  && modèle GGUF (paquet llm), réponse affichée au fil de la génération
  si ia.modele = nul ou ia.chemin <> reglages.ia_modele
    STATUT("Chargement du modèle " + fichier.nom(reglages.ia_modele) + "…")
    ia.modele = llm.charger(reglages.ia_modele)
    ia.chemin = reglages.ia_modele
  finsi
  locale c = ia.modele:conversation({systeme = SYSTEME_IA(), contexte = 8192, maxtokens = 1024})
  ia.flux = rep
  rep.texte = ""
  locale r = c:demander(prompt, @IA_FLUX)
retourner chaine(r)

fonction IA_FLUX(morceau)
  ia.flux.texte = ia.flux.texte + morceau
  IA_AFFICHER()
retourner vrai

fonction IA_HTTP(prompt)
  locale corps = "{" + car(34) + "model" + car(34) + ":" + json.encoder(sisinon(reglages.ia_nom = nul, "", reglages.ia_nom)) + ;
    "," + car(34) + "temperature" + car(34) + ":0.2," + car(34) + "messages" + car(34) + ":[" + ;
    "{" + car(34) + "role" + car(34) + ":" + car(34) + "system" + car(34) + "," + car(34) + "content" + car(34) + ":" + json.encoder(SYSTEME_IA()) + "}," + ;
    "{" + car(34) + "role" + car(34) + ":" + car(34) + "user" + car(34) + "," + car(34) + "content" + car(34) + ":" + json.encoder(prompt) + "}]}"
  locale h = {}
  h["Content-Type"] = "application/json"
  locale cle = nul
  si reglages.ia_cle_env <> nul et reglages.ia_cle_env <> ""
    cle = systeme.env(reglages.ia_cle_env)
  finsi
  si cle <> nul et cle <> ""
    h["Authorization"] = "Bearer " + cle
  finsi
  STATUT("Assistant : requête vers " + reglages.ia_url + "…")
  locale r = http.requete{methode = "POST", url = reglages.ia_url, entetes = h, corps = corps, delai = 300}
  si r.statut < 200 ou r.statut >= 300
    erreur "HTTP " + r.statut + " : " + gauche(r.corps, 300)
  finsi
  locale j = json.decoder(r.corps, vrai)
  si j["choices"] = nul ou #j["choices"] = 0
    erreur "réponse inattendue : " + gauche(r.corps, 300)
  finsi
  STATUT("Assistant : réponse reçue.")
retourner j["choices"][1]["message"]["content"]

&&
&& Moteur de règles (sans modèle)
&&

fonction IA_REGLES(action, question)
  faire cas
  cas action = "plan"
    retourner REGLES_EXPLIQUER_PLAN(dernierplan)
  cas action = "reecrire"
    retourner REGLES_REECRIRE(INSTRUCTION_COURANTE())
  cas action = "erreur"
    retourner REGLES_ERREUR(derniereerreur)
  cas action = "modele"
    retourner REGLES_MODELE(question)
  cas action = "sql"
    retourner REGLES_SQL(question)
  fincas
retourner "Les règles intégrées savent expliquer un plan ou une erreur, réécrire une requête, écrire une requête " + ;
          "simple et générer un modèle décrit ainsi :" + car(10) + car(10) + ;
          "```" + car(10) + "clients : nom, ville, inscrit date" + car(10) + "commandes : date date, montant decimal -> clients" + ;
          car(10) + "```" + car(10) + car(10) + "Pour des questions libres, configurez un modèle local (GGUF) ou un serveur " + ;
          "compatible OpenAI dans Réglages…"

fonction SENS_OPERATEUR(o)
  locale t = o.type
  locale tab = INFO(o, "Table")
  faire cas
  cas contient(t, "TABLE_SCAN") ou contient(t, "SEQ_SCAN")
    retourner "lit " + sisinon(tab = nul, "une table", "la table " + tab) + sisinon(INFO(o, "Filters") <> nul, ", en appliquant des filtres pendant la lecture", "")
  cas contient(t, "HASH_JOIN")
    retourner "rapproche deux flux par une table de hachage (" + sisinon(INFO(o, "Join Type") = nul, "", INFO(o, "Join Type") + ", ") + ;
              "condition " + sisinon(INFO(o, "Conditions") = nul, "?", INFO(o, "Conditions")) + ")"
  cas contient(t, "NESTED_LOOP") ou contient(t, "CROSS_PRODUCT") ou contient(t, "BLOCKWISE_NL")
    retourner "compare chaque ligne d'un côté à chaque ligne de l'autre : coût quadratique"
  cas contient(t, "GROUP_BY") ou contient(t, "AGGREGATE")
    retourner "regroupe et agrège les lignes"
  cas contient(t, "TOP_N")
    retourner "garde les premières lignes selon l'ordre demandé, sans tri complet"
  cas contient(t, "ORDER")
    retourner "trie toutes les lignes"
  cas contient(t, "FILTER")
    retourner "élimine les lignes qui ne vérifient pas la condition"
  cas contient(t, "PROJECTION")
    retourner "calcule les colonnes du résultat"
  cas contient(t, "WINDOW")
    retourner "calcule des fonctions de fenêtre (partitions triées)"
  cas contient(t, "UNION")
    retourner "empile les résultats"
  fincas
retourner "opérateur " + t

fonction REGLES_EXPLIQUER_PLAN(p)
  si p = nul
    retourner "Aucun plan : profilez une requête (F6)."
  finsi
  locale nl = car(10)
  locale tri = copier(p.ops)
  trier(tri, @PLUS_LENT)
  locale tot = max(p.total, 0.000001)
  locale md = "La requête a pris **" + arrondi(p.latence * 1000, 1) + " ms** et lu **" + LIGNES_TEXTE(p.lues) + "** lignes. " + ;
              "DuckDB l'exécute de bas en haut : les feuilles lisent les données, chaque opérateur transmet ses lignes au suivant." + nl + nl
  md = md + "Les étapes les plus coûteuses :" + nl
  pour i = 1 a min(5, #tri)
    locale o = tri[i]
    si o.temps > 0
      md = md + "- **" + o.nom + "** (" + arrondi(o.temps * 100 / tot) + " %, " + LIGNES_TEXTE(o.lignes) + " lignes) : " + SENS_OPERATEUR(o) + nl
    finsi
  suivant
  locale r = REGLES_PLAN(p)
  si #r > 0
    md = md + nl + "Ce que je recommande :" + nl
    pour chaque x dans r
      md = md + "- **" + x.probleme + "** — " + x.correction + nl
    suivant
  sinon
    md = md + nl + "Aucun défaut notable : le plan est sain pour ce volume."
  finsi
retourner md

fonction REGLES_REECRIRE(q)
  locale nl = car(10)
  si q = nul ou rogner(q) = ""
    retourner "Placez le curseur dans une requête."
  finsi
  locale conseils = {}
  locale m = " " + minuscule(remplacertexte(q, nl, " ")) + " "
  si contient(m, "select * ") ou contient(m, "select *,")
    inserer(conseils, "`SELECT *` lit toutes les colonnes : sur un stockage en colonnes, ne lire que celles utiles réduit les lectures.")
  finsi
  si contient(m, " not in (select")
    inserer(conseils, "`NOT IN (SELECT …)` se comporte mal avec les NULL : préférez `NOT EXISTS` ou une `ANTI JOIN`.")
  finsi
  si contient(m, "count(distinct")
    inserer(conseils, "`count(DISTINCT …)` sur un gros volume : `approx_count_distinct(…)` est bien plus rapide (erreur ≈ 2 %).")
  finsi
  si contient(m, " order by ") et non contient(m, " limit ") et non contient(m, "over (")
    inserer(conseils, "Tri sans `LIMIT` : utile seulement si l'ordre de tout le résultat compte.")
  finsi
  si contient(m, " like '%")
    inserer(conseils, "`LIKE '%…'` ne peut pas profiter des statistiques : `contains()` ou `regexp_matches()` sont équivalents, une colonne dérivée indexable est plus rapide.")
  finsi
  si contient(m, " union ") et non contient(m, " union all ")
    inserer(conseils, "`UNION` élimine les doublons (coûteux) : `UNION ALL` si les branches sont disjointes.")
  finsi
  locale forme = nul
  essayer
    locale p = PIPELINE_DEPUIS_SQL(q, "r")
    forme = SQL_PIPELINE(p)
    forme = rogner(souschaine(forme, position(car(10), forme) + 1))
    si commencepar(forme, "-- ")
      forme = rogner(souschaine(forme, position(car(10), forme) + 1))
    finsi
  capturer e
    forme = nul
  finessayer
  locale md = ""
  si forme <> nul
    md = "Forme normalisée (analyse de DuckDB : jointures explicites, clauses dans l'ordre, sous-requêtes à plat) :" + nl + nl + ;
         "```sql" + nl + forme + nl + "```" + nl + nl
  finsi
  si #conseils > 0
    md = md + "Conseils :" + nl
    pour chaque c dans conseils
      md = md + "- " + c + nl
    suivant
  sinon
    md = md + "Aucun motif coûteux reconnu. Profilez la requête (F6) pour un diagnostic chiffré."
  finsi
retourner md

fonction REGLES_ERREUR(e)
  locale nl = car(10)
  si e = nul
    retourner "Aucune erreur récente."
  finsi
  locale msg = e.message
  locale md = "**Erreur :** " + remplacertexte(msg, nl, " ") + nl + nl
  locale mn = minuscule(msg)
  faire cas
  cas contient(mn, "catalog error") et contient(mn, "does not exist")
    md = md + "La table (ou la vue) citée n'existe pas sous ce nom. Les objets sont nommés `connexion.schéma.table` ; " + ;
         "les noms proches du catalogue :" + nl + SIMILAIRES(msg, "table")
  cas contient(mn, "binder error") et (contient(mn, "column") ou contient(mn, "referenced"))
    md = md + "Une colonne citée n'existe pas dans les tables de la requête (ou elle est ambiguë : préfixez-la par sa table). " + ;
         "Colonnes proches :" + nl + SIMILAIRES(msg, "colonne")
  cas contient(mn, "parser error")
    md = md + "Erreur de syntaxe : vérifiez les parenthèses, les virgules et les mots clés près de la position indiquée ; " + ;
         "les chaînes s'écrivent entre apostrophes `'…'`, les identifiants entre guillemets `" + car(34) + "…" + car(34) + "`."
  cas contient(mn, "conversion error") ou contient(mn, "could not convert")
    md = md + "Une valeur ne peut pas être convertie dans le type attendu. Utilisez `TRY_CAST(x AS type)` (NULL en cas d'échec) " + ;
         "ou nettoyez la colonne ; à la lecture d'un CSV, `read_csv(…, types = {…})` fixe les types."
  cas contient(mn, "must appear in the group by") ou contient(mn, "group by clause")
    md = md + "Toute colonne non agrégée du SELECT doit figurer dans le GROUP BY : `GROUP BY ALL` le fait automatiquement."
  cas contient(mn, "out of memory")
    md = md + "Mémoire insuffisante : `SET memory_limit = '…'`, `SET temp_directory = '…'` pour déborder sur disque, ou réduisez les colonnes lues."
  cas contient(mn, "constraint error")
    md = md + "Une contrainte (clé primaire, unicité, NOT NULL, clé étrangère) est violée par les lignes insérées : " + ;
         "repérez les doublons avec `GROUP BY clé HAVING count(*) > 1`."
  autrement
    md = md + "Relisez la requête près de l'élément cité par le message ; l'onglet Messages garde le détail."
  fincas
retourner md

fonction MOT_CITE(msg)
  && premier nom entre guillemets d'un message d'erreur
  locale p = position(car(34), msg)
  si p = 0
    retourner nul
  finsi
  locale r = souschaine(msg, p + 1)
  locale q = position(car(34), r)
retourner sisinon(q > 0, gauche(r, q - 1), nul)

fonction SIMILAIRES(msg, genre)
  locale mot = MOT_CITE(msg)
  si mot = nul
    retourner "(aucun nom cité)"
  finsi
  locale noms = {}
  pour chaque o dans TOUS_LES_OBJETS()
    si genre = "table"
      inserer(noms, QUALIFIE(o))
    sinonsi o.objet.colonnes <> nul
      pour chaque c dans o.objet.colonnes
        inserer(noms, o.nom + "." + sisinon(type(c) = "table", c.nom, c))
      suivant
    finsi
  suivant
  si #noms = 0
    retourner "(catalogue vide)"
  finsi
  essayer
    requete("CREATE OR REPLACE TEMP TABLE _noms (nom VARCHAR)")
    pour chaque n dans noms
      requete("INSERT INTO _noms VALUES (?)", n)
    suivant
    locale l = {}
    pour chaque r dans requete("SELECT nom FROM _noms ORDER BY jaro_winkler_similarity(lower(?), lower(split_part(nom, '.', -1))) DESC LIMIT 5", mot)
      inserer(l, "- `" + r.nom + "`")
    suivant
    requete("DROP TABLE _noms")
    retourner joindre(l, car(10))
  capturer e
    retourner "(" + e + ")"
  finessayer
retourner ""

fonction REGLES_SQL(question)
  && sans modèle : tables citées par la question
  locale q = " " + minuscule(question) + " "
  locale l = {}
  pour chaque o dans TOUS_LES_OBJETS()
    si contient(q, minuscule(o.nom)) ou contient(q, minuscule(o.nom) + "s") ou ;
       (finitpar(minuscule(o.nom), "s") et contient(q, gauche(minuscule(o.nom), longueur(o.nom) - 1)))
      inserer(l, o)
    finsi
  suivant
  si #l = 0
    retourner "Aucune table du catalogue n'est citée dans la question. Sans modèle de langage, je ne peux écrire " + ;
              "que des requêtes simples : citez le nom d'une table (ou configurez un modèle dans Réglages…)."
  finsi
  locale o = l[1]
  locale s = "SELECT *" + car(10) + "FROM " + QUALIFIE(o) + car(10) + "LIMIT 100;"
  si contient(q, "combien") ou contient(q, "nombre")
    s = "SELECT count(*) AS nb" + car(10) + "FROM " + QUALIFIE(o) + ";"
  finsi
retourner "Requête de départ sur **" + o.nom + "** (règles intégrées : complétez-la ou configurez un modèle) :" + car(10) + car(10) + ;
          "```sql" + car(10) + s + car(10) + "```"

fonction REGLES_MODELE(description)
  && description structurée : « table : col type, col type -> autre_table » (une par ligne ou séparées par ;)
  locale nl = car(10)
  locale lignes = decouper(remplacertexte(description, ";", nl), nl)
  locale tables = {}
  pour chaque li dans lignes
    locale p = position(":", li)
    si p > 0
      locale nom = ALIAS({nom = rogner(gauche(li, p - 1))})
      locale reste = souschaine(li, p + 1)
      locale refs = {}
      locale f = position("->", reste)
      si f > 0
        pour chaque r dans decouper(souschaine(reste, f + 2), ",")
          si rogner(r) <> ""
            inserer(refs, ALIAS({nom = rogner(r)}))
          finsi
        suivant
        reste = gauche(reste, f - 1)
      finsi
      locale cols = {}
      pour chaque c dans decouper(reste, ",")
        locale mots = decouper(rogner(c), " ")
        si rogner(c) <> ""
          locale cn = ALIAS({nom = mots[1]})
          locale ty = "VARCHAR"
          si #mots >= 2
            ty = TYPE_SQL(mots[2])
          sinonsi contient(cn, "date") ou cn = "jour" ou cn = "inscrit"
            ty = "DATE"
          sinonsi contient(cn, "montant") ou contient(cn, "prix") ou contient(cn, "total")
            ty = "DECIMAL(12,2)"
          sinonsi contient(cn, "quantite") ou contient(cn, "nombre") ou commencepar(cn, "nb")
            ty = "INTEGER"
          finsi
          inserer(cols, {nom = cn, type = ty})
        finsi
      suivant
      inserer(tables, {nom = nom, cols = cols, refs = refs})
    finsi
  suivant
  si #tables = 0
    retourner IA_REGLES("question", "")
  finsi
  locale out = {}
  pour chaque t dans tables
    locale l = {"  id INTEGER PRIMARY KEY"}
    pour chaque c dans t.cols
      inserer(l, "  " + c.nom + " " + c.type)
    suivant
    pour chaque r dans t.refs
      inserer(l, "  " + SINGULIER(r) + "_id INTEGER REFERENCES " + r + " (id)")
    suivant
    inserer(out, "CREATE TABLE " + t.nom + " (" + nl + joindre(l, "," + nl) + nl + ");")
  suivant
retourner "Modèle déduit de la description (chaque table reçoit une clé `id`, chaque « -> » une clé étrangère) :" + nl + nl + ;
          "```sql" + nl + joindre(ORDONNER_DDL(out, tables), nl + nl) + nl + "```"

fonction ORDONNER_DDL(out, tables)
  && tables référencées d'abord
  locale fait = {}
  locale r = {}
  pour tour = 1 a #tables + 1
    pour i = 1 a #tables
      locale t = tables[i]
      si fait[t.nom] = nul
        locale pret = vrai
        pour chaque x dans t.refs
          si fait[x] = nul et x <> t.nom
            pour chaque y dans tables
              si y.nom = x
                pret = faux
              finsi
            suivant
          finsi
        suivant
        si pret ou tour > #tables
          fait[t.nom] = vrai
          inserer(r, out[i])
        finsi
      finsi
    suivant
  suivant
retourner r

fonction SINGULIER(n)
retourner sisinon(finitpar(n, "s") et longueur(n) > 3, gauche(n, longueur(n) - 1), n)

fonction TYPE_SQL(t)
  locale m = minuscule(t)
  faire cas
  cas m = "entier" ou m = "int" ou m = "integer"
    retourner "INTEGER"
  cas m = "texte" ou m = "chaine" ou m = "varchar"
    retourner "VARCHAR"
  cas m = "date"
    retourner "DATE"
  cas m = "horodatage" ou m = "timestamp"
    retourner "TIMESTAMP"
  cas m = "decimal" ou m = "montant"
    retourner "DECIMAL(12,2)"
  cas m = "nombre" ou m = "double" ou m = "reel"
    retourner "DOUBLE"
  cas m = "logique" ou m = "booleen" ou m = "boolean"
    retourner "BOOLEAN"
  fincas
retourner majuscule(t)

&&
&& Réglages
&&

procedure IA_REGLAGES(ev)
  si ia.dlg <> nul
    retourner
  finsi
  ia.dlg = ui.fenetre{titre = "Assistant : moteur", largeur = 620, hauteur = 420, disposition = "bordure", sombre = reglages.sombre}
  ia.dlg.surfermeture = @IA_REGLAGES_FERMETURE
  locale g = ia.dlg:ajouter(ui.cadre("Moteur", "grille"))
  g.ancrage = "haut"
  g:ajouter(ui.etiquette("Moteur"))
  ia.cmoteur = g:ajouter(ui.combo("Règles intégrées (sans modèle)", "Modèle local GGUF (paquet llm)", "Serveur compatible OpenAI (HTTP)"))
  ia.cmoteur:selectionner(sisinon(reglages.ia_moteur = "local", 2, sisinon(reglages.ia_moteur = "http", 3, 1)))
  g:ajouter(ui.etiquette("Fichier du modèle (.gguf)"))
  ia.cfichier = g:ajouter(ui.saisie{texte = sisinon(reglages.ia_modele = nul, "", reglages.ia_modele), indication = "~/modeles/qwen2.5-7b-instruct-q4_k_m.gguf"})
  g:ajouter(ui.etiquette("URL du serveur"))
  ia.curl = g:ajouter(ui.saisie{texte = sisinon(reglages.ia_url = nul, "", reglages.ia_url), indication = "http://localhost:11434/v1/chat/completions"})
  g:ajouter(ui.etiquette("Nom du modèle"))
  ia.cnom = g:ajouter(ui.saisie{texte = sisinon(reglages.ia_nom = nul, "", reglages.ia_nom), indication = "llama3.1"})
  g:ajouter(ui.etiquette("Variable d'environnement de la clé"))
  ia.ccle = g:ajouter(ui.saisie{texte = sisinon(reglages.ia_cle_env = nul, "", reglages.ia_cle_env), indication = "OPENAI_API_KEY (vide : aucune)"})
  locale aide = ia.dlg:ajouter(ui.markdown("La clé d'API n'est jamais enregistrée : seul le **nom** de la variable d'environnement " + ;
    "qui la contient l'est. Avec le moteur local, rien ne quitte le poste. Le contexte envoyé comprend le schéma " + ;
    "(noms de tables et de colonnes), la requête courante, le dernier plan et la dernière erreur, jamais les données."))
  aide.ancrage = "centre"
  locale bas_ = ia.dlg:ajouter(ui.rangee())
  bas_.ancrage = "bas"
  locale vide = bas_:ajouter(ui.etiquette(""))
  vide.poids = 1
  locale be = bas_:ajouter(ui.bouton("Enregistrer", {defaut = vrai}))
  be.surclic = @IA_REGLAGES_OK
  locale ba = bas_:ajouter(ui.bouton("Annuler", {annuler = vrai}))
  ba.surclic = @IA_REGLAGES_ANNULER
retourner

procedure IA_REGLAGES_OK(ev)
  locale i = ia.cmoteur:selection()
  reglages.ia_moteur = sisinon(i = 2, "local", sisinon(i = 3, "http", "regles"))
  reglages.ia_modele = rogner(ia.cfichier.valeur)
  reglages.ia_url = rogner(ia.curl.valeur)
  reglages.ia_nom = rogner(ia.cnom.valeur)
  reglages.ia_cle_env = rogner(ia.ccle.valeur)
  DS_ECRIRE_REGLAGES()
  IA_ETIQUETTE()
  si reglages.ia_moteur <> MOTEUR_IA()
    STATUT("Assistant : moteur « " + reglages.ia_moteur + " » incomplet (fichier ou URL) : règles intégrées utilisées.")
  finsi
  ia.dlg:fermer()
retourner

procedure IA_REGLAGES_ANNULER(ev)
  ia.dlg:fermer()
retourner

procedure IA_REGLAGES_FERMETURE(ev)
  ia.dlg = nul
retourner
