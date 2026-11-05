&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atlas SQL : assistant expert SQL (module 18).
&&
&& Moteur intégré (sans modèle) : il comprend les questions courantes en français et
&& répond à partir de l'entrepôt — résumer, expliquer, anomalies, optimisations,
&& refactorisations, documentation, « qui lit / écrit / supprime / appelle X »,
&& impact, données personnelles, objets inutilisés, SQL dynamique, liens inter-serveurs.
&& Avec un modèle (Réglages) : les faits rassemblés par le moteur intégré sont donnés au
&& modèle, qui rédige la réponse — modèle local GGUF (paquet llm, rien ne quitte le
&& poste) ou serveur compatible OpenAI (Ollama, llama.cpp, LM Studio… ; la clé est lue
&& dans une variable d'environnement, jamais enregistrée).

procedure CONSTRUIRE_ASSISTANT(page)
  globale ia
  ia = {fil = {}, modele = nul, chemin = ""}
  locale haut = page:ajouter(ui.rangee())
  haut.marge = 2
  haut.ancrage = "haut"
  pour chaque a dans {{"Résumer", "résume"}, {"Expliquer", "explique"}, {"Anomalies", "anomalies de"}, ;
                      {"Optimiser", "optimise"}, {"Refactoriser", "refactorise"}, {"Documenter", "documente"}}
    locale b = haut:ajouter(ui.bouton(a[1]))
    b.infobulle = a[1] + " l'objet courant"
    b.surclic = @IA_ACTION
  suivant
  OUTIL(haut, "Effacer", @IA_EFFACER, "Effacer la conversation")
  OUTIL(haut, "Réglages…", @IA_REGLAGES, "Moteur : règles intégrées, modèle local GGUF ou serveur compatible OpenAI")
  ia.moteur = haut:ajouter(ui.etiquette(""))
  ia.moteur.poids = 1
  ia.moteur.couleur = "#9CA3AF"
  locale bas_ = page:ajouter(ui.rangee())
  bas_.ancrage = "bas"
  ia.question = bas_:ajouter(ui.saisie{indication = "Ex. : qui écrit dans FACTURE ? · explique SP_EMISSION_FACTURE · quelles tables contiennent des données personnelles ?"})
  ia.question.poids = 1
  ia.question.surtouchebas = @IA_TOUCHE
  locale be = bas_:ajouter(ui.bouton("Envoyer"))
  be.surclic = @IA_ENVOYER
  ia.vue = page:ajouter(ui.markdown(IA_AIDE()))
  ia.vue.ancrage = "centre"
  IA_ETIQUETTE()
retourner

fonction IA_AIDE()
retourner joindre({"### Assistant expert SQL", "", "Posez une question en français, ou utilisez les boutons sur l'objet courant :", "", ;
  "- *résume* / *explique* **SP_EMISSION_FACTURE**", "- *qui écrit dans* **FACTURE** ? · *qui lit* **CLIENT** ? · *qui appelle* **SP_LOG** ?", ;
  "- *impact de* **CLIENT_CODE** · *anomalies de* **SP_INVENTAIRE** · *optimise* **SP_CA_MENSUEL**", ;
  "- *quelles tables contiennent des données personnelles ?* · *objets inutilisés* · *liens inter-serveurs*", ;
  "- *SQL dynamique* · *types métier* · *combien d'objets ?*"}, car(10))

procedure IA_ETIQUETTE
  locale m = sisinon(reglages.ia_moteur = nul, "regles", reglages.ia_moteur)
  ia.moteur.libelle = "Moteur : " + sisinon(m = "local", "modèle local " + fichier.nom(chaine(reglages.ia_modele)), ;
                                            sisinon(m = "http", chaine(reglages.ia_nom) + " @ " + chaine(reglages.ia_url), "règles intégrées (sans modèle)"))
retourner

procedure IA_EFFACER(ev)
  ia.fil = {}
  ia.vue.valeur = IA_AIDE()
retourner

procedure IA_TOUCHE(ev)
  si ev.touche = 13
    IA_ENVOYER(nul)
  finsi
retourner

procedure IA_ACTION(ev)
  locale v = nul
  pour chaque a dans {{"Résumer", "résume"}, {"Expliquer", "explique"}, {"Anomalies", "anomalies de"}, ;
                      {"Optimiser", "optimise"}, {"Refactoriser", "refactorise"}, {"Documenter", "documente"}}
    si a[1] = ev.id.libelle
      v = a[2]
    finsi
  suivant
  si courant = nul
    STATUT("Sélectionnez d'abord un objet.")
    retourner
  finsi
  IA_DEMANDER(sisinon(v = nul, "résume", v) + " " + courant.nom)
retourner

procedure IA_ENVOYER(ev)
  locale q = rogner(sisinon(ia.question.valeur = nul, "", ia.question.valeur))
  si q = ""
    retourner
  finsi
  ia.question.valeur = ""
  IA_DEMANDER(q)
retourner

procedure IA_DEMANDER(q)
  inserer(ia.fil, "**Vous** — " + q)
  locale faits = ""
  essayer
    faits = IA_REGLES(q)
  capturer e
    faits = "Je n'ai pas pu répondre : " + e
  finessayer
  locale rep = faits
  locale m = sisinon(reglages.ia_moteur = nul, "regles", reglages.ia_moteur)
  si m <> "regles"
    essayer
      locale prompt = "Question : " + q + car(10) + car(10) + "Faits tirés de l'analyse du patrimoine SQL Server (fiables) :" + ;
                      car(10) + faits + car(10) + car(10) + "Réponds en français, de façon structurée et concrète, sans inventer d'objets."
      rep = sisinon(m = "local", IA_LOCAL(prompt), IA_HTTP(prompt))
    capturer e2
      rep = faits + car(10) + car(10) + "*(modèle indisponible : " + e2 + " ; réponse du moteur intégré)*"
    finessayer
  finsi
  inserer(ia.fil, "**Atlas** — " + car(10) + car(10) + rep)
  ia.vue.valeur = MD(joindre(ia.fil, car(10) + car(10) + "---" + car(10) + car(10)))
  ia.vue:defilera("fin")
retourner

fonction SYSTEME_IA()
retourner "Tu es un expert SQL Server (T-SQL, performances, modélisation, RGPD, architecture des données). " + ;
  "Tu réponds en français à partir des faits fournis, sans inventer d'objets ni de chiffres."

fonction IA_LOCAL(prompt)
  si ia.modele = nul ou ia.chemin <> reglages.ia_modele
    STATUT("Chargement du modèle " + fichier.nom(reglages.ia_modele) + "…")
    ia.modele = llm.charger(reglages.ia_modele)
    ia.chemin = reglages.ia_modele
  finsi
  locale c = ia.modele:conversation({systeme = SYSTEME_IA(), contexte = 8192, maxtokens = 1024})
retourner chaine(c:demander(prompt))

fonction IA_HTTP(prompt)
  locale corps = json({model = chaine(reglages.ia_nom), temperature = 0.2, ;
                       messages = {{role = "system", content = SYSTEME_IA()}, {role = "user", content = prompt}}})
  && json() met les clés en majuscules : l'API attend des minuscules
  corps = remplacertexte(remplacertexte(remplacertexte(remplacertexte(remplacertexte(remplacertexte(corps, ;
          car(34) + "MODEL" + car(34), car(34) + "model" + car(34)), car(34) + "TEMPERATURE" + car(34), car(34) + "temperature" + car(34)), ;
          car(34) + "MESSAGES" + car(34), car(34) + "messages" + car(34)), car(34) + "ROLE" + car(34), car(34) + "role" + car(34)), ;
          car(34) + "CONTENT" + car(34), car(34) + "content" + car(34)), "\\/", "/")
  locale h = {}
  h["Content-Type"] = "application/json"
  si reglages.ia_cle_env <> nul et reglages.ia_cle_env <> ""
    locale cle = systeme.env(reglages.ia_cle_env)
    si cle <> nul et cle <> ""
      h["Authorization"] = "Bearer " + cle
    finsi
  finsi
  locale r = http.requete{methode = "POST", url = reglages.ia_url, entetes = h, corps = corps, delai = 300}
  si r.statut < 200 ou r.statut >= 300
    erreur "HTTP " + r.statut + " : " + gauche(r.corps, 300)
  finsi
  locale j = json.decoder(r.corps, vrai)
retourner j["choices"][1]["message"]["content"]

procedure IA_REGLAGES(ev)
  locale m = ui.demander("Moteur de l'assistant : regles, local (modèle GGUF) ou http (serveur compatible OpenAI)", ;
                         sisinon(reglages.ia_moteur = nul, "regles", reglages.ia_moteur))
  si m = nul
    retourner
  finsi
  m = minuscule(rogner(m))
  faire cas
  cas m = "local"
    locale p = ui.ouvrirfichier{titre = "Modèle GGUF", filtre = "GGUF|*.gguf"}
    si p = nul
      retourner
    finsi
    reglages.ia_modele = p
  cas m = "http"
    locale u = ui.demander("URL (…/v1/chat/completions)", sisinon(reglages.ia_url = "", "http://localhost:11434/v1/chat/completions", reglages.ia_url))
    si u = nul
      retourner
    finsi
    reglages.ia_url = u
    reglages.ia_nom = ui.demander("Nom du modèle", sisinon(reglages.ia_nom = "", "qwen2.5-coder", reglages.ia_nom))
    reglages.ia_cle_env = ui.demander("Variable d'environnement de la clé d'API (vide : aucune)", reglages.ia_cle_env)
  autrement
    m = "regles"
  fincas
  reglages.ia_moteur = m
  ECRIRE_REGLAGES()
  IA_ETIQUETTE()
retourner

&&
&& Moteur intégré
&&

fonction IA_OBJET(q)
  && objet cité dans la question (le nom le plus long reconnu), sinon l'objet courant
  locale mots = {}
  pour chaque m dans decouper(remplacertexte(remplacertexte(remplacertexte(remplacertexte(q, "?", " "), ",", " "), "'", " "), "’", " "), " ")
    locale x = rogner(m)
    si #x >= 3
      inserer(mots, minuscule(DERNIER(remplacertexte(remplacertexte(x, "[", ""), "]", ""))))
    finsi
  suivant
  si #mots > 0
    locale r = RQ(nul, "select id from objets where list_contains(string_split(?, '|'), lower(nom)) and genre in ('TABLE', 'VUE', 'PROCEDURE', " + ;
                       "'FONCTION', 'DECLENCHEUR', 'JOB', 'SYNONYME') order by length(nom) desc, case genre when 'TABLE' then 0 else 1 end limit 1", ;
                       {joindre(mots, "|")})
    si #r > 0
      retourner OBJET(r[1].id)
    finsi
  finsi
retourner nul

fonction CONTIENT_UN(q, mots)
  pour chaque m dans mots
    si m $ q
      retourner vrai
    finsi
  suivant
retourner faux

fonction IA_REGLES(question)
  locale q = minuscule(question)
  locale o = IA_OBJET(question)
  && questions sur le graphe : qui lit / écrit / supprime / met à jour / appelle / utilise X
  si commencepar(q, "qui ") ou " qui " $ q
    locale cible = sisinon(o = nul, courant, o)
    si cible = nul
      retourner "Précisez l'objet (ex. : *qui écrit dans FACTURE ?*)."
    finsi
    locale qu = ""
    faire cas
    cas CONTIENT_UN(q, {"écrit", "ecrit", "alimente", "modifie"})
      qu = "ecrit"
    cas CONTIENT_UN(q, {"lit", "lisent", "consulte", "lecture"})
      qu = "lit"
    cas CONTIENT_UN(q, {"supprime", "efface", "purge"})
      qu = "supprime"
    cas CONTIENT_UN(q, {"met à jour", "mets à jour", "mise à jour", "update"})
      qu = "metajour"
    cas CONTIENT_UN(q, {"insère", "insere", "ajoute"})
      qu = "insere"
    cas CONTIENT_UN(q, {"appelle", "exécute", "execute", "lance"})
      qu = "appelle"
    fincas
    locale l = RELATIONS(cible.id, "entrant", qu)
    locale md = {"**" + cible.sch + "." + cible.nom + "** (" + LIBELLE_GENRE(cible.genre) + ") — " + #l + " objet(s) :", ""}
    pour chaque r dans l
      inserer(md, "- " + r.nature + " · " + ICONE_GENRE(r.genre) + " " + r.nom + sisinon(r.frequence = nul, "", " · " + NB(r.frequence) + " exécutions") + ;
                  sisinon(r.interserveur, " · *autre serveur*", sisinon(r.interbase, " · *autre base*", "")))
    suivant
    retourner joindre(md, car(10))
  finsi
  && thèmes globaux
  faire cas
  cas CONTIENT_UN(q, {"personnel", "rgpd", "sensible", "confidenti"})
    locale md2 = {"**Données personnelles** (dictionnaire) :", ""}
    pour chaque r dans RQ(nul, "select o.serveur || ' › ' || o.base || '.' || o.sch || '.' || o.nom as t, d.sensibilite, " + ;
                               "(select string_agg(c.colonne || ' (' || c.categorie_rgpd || ')', ', ') from dico_colonnes c where c.objet_id = d.objet_id and c.rgpd) as cols " + ;
                               "from dico_tables d join objets o on o.id = d.objet_id where d.rgpd order by case d.sensibilite when 'très élevée' then 1 " + ;
                               "when 'élevée' then 2 else 3 end, t", nul)
      inserer(md2, "- **" + r.t + "** — " + r.sensibilite + " : " + r.cols)
    suivant
    inserer(md2, "")
    inserer(md2, "Copies hors production (DWH, exports) : vérifier la pseudonymisation ; registre des traitements à jour.")
    retourner joindre(md2, car(10))
  cas CONTIENT_UN(q, {"inutilis", "obsolète", "obsolete", "mort"})
    locale md3 = {"**Objets inutilisés ou obsolètes** :", ""}
    pour chaque r dans RQ(nul, "select o.sch || '.' || o.nom as n, o.genre, m.classe, strftime(o.modifie, '%Y-%m-%d') as d from metriques m " + ;
                               "join objets o on o.id = m.objet_id where m.classe like '%Inutilisé%' or m.classe like '%Obsolète%' order by o.genre, o.nom", nul)
      inserer(md3, "- " + ICONE_GENRE(r.genre) + " " + r.n + " — " + r.classe + sisinon(r.d = nul, "", " (modifié le " + r.d + ")"))
    suivant
    retourner joindre(md3, car(10))
  cas CONTIENT_UN(q, {"inter-serveur", "interserveur", "serveur lié", "serveurs liés", "openquery", "distant"})
    locale md4 = {"**Liens inter-serveurs** :", ""}
    pour chaque r dans RQ(nul, "select a.serveur || ' › ' || a.sch || '.' || a.nom as de, d.nature, d.vers_nom from dependances d join objets a on a.id = d.de_id " + ;
                               "where d.interserveur order by 1", nul)
      inserer(md4, "- " + r.de + " —" + r.nature + "→ " + r.vers_nom)
    suivant
    retourner joindre(md4, car(10))
  cas CONTIENT_UN(q, {"dynamique", "injection", "sp_executesql"})
    locale md5 = {"**SQL dynamique** :", ""}
    pour chaque r dans RQ(nul, "select o.sch || '.' || o.nom as n, d.mode, d.ligne, d.sql_reconstitue from sql_dynamique d join objets o on o.id = d.objet_id", nul)
      inserer(md5, "- **" + r.n + "** l." + r.ligne + " (" + r.mode + ") : " + MDCODE(COURT(r.sql_reconstitue, 150)))
    suivant
    locale inj = RV(nul, "select count(*) from diagnostics where regle = 'INJECTION'", nul)
    inserer(md5, "")
    inserer(md5, inj + " cas de concaténation à risque d'injection (EXEC sur du texte construit avec des variables).")
    retourner joindre(md5, car(10))
  cas CONTIENT_UN(q, {"type métier", "types métier", "colonnes similaires"})
    locale md6 = {"**Types métier** (colonnes équivalentes) :", ""}
    pour chaque r dans RQ(nul, "select code, colonnes, variantes from types_metier order by occurrences desc limit 15", nul)
      inserer(md6, "- **" + r.code + "** : " + r.colonnes + sisinon("," $ r.variantes, " — *types incohérents : " + r.variantes + "*", ""))
    suivant
    retourner joindre(md6, car(10))
  cas o = nul et CONTIENT_UN(q, {"combien", "inventaire", "volumétrie", "synthèse", "bilan"})
    retourner SYNTHESE()
  fincas
  && actions sur un objet
  si o = nul
    o = courant
  finsi
  si o = nul
    retourner "Je n'ai reconnu aucun objet dans la question. " + car(10) + car(10) + IA_AIDE()
  finsi
  faire cas
  cas CONTIENT_UN(q, {"impact"})
    locale l2 = IMPACT_TRANSITIF(o.id, 6)
    locale md7 = {"**Impact d'une modification de " + o.nom + "** : " + #l2 + " objet(s) en cascade.", ""}
    pour chaque r dans l2
      inserer(md7, "- niveau " + r.niveau + " · " + ICONE_GENRE(r.genre) + " " + r.sch + "." + r.nom)
    suivant
    locale cols = IMPACT_COLONNE(o.nom, nul)
    si #cols > 0
      inserer(md7, "")
      inserer(md7, "Le nom apparaît dans le code de " + #cols + " objet(s) — voir l'onglet *Refactoring* pour l'aperçu ligne par ligne.")
    finsi
    retourner joindre(md7, car(10))
  cas CONTIENT_UN(q, {"anomal", "problème", "probleme", "défaut", "erreur", "risque"})
    retourner IA_CONSTATS(o, "")
  cas CONTIENT_UN(q, {"optimis", "performance", "lent", "accélér"})
    retourner IA_OPTIMISER(o)
  cas CONTIENT_UN(q, {"refactor", "découp", "decoup", "mutualis", "simplifi"})
    retourner IA_REFACTORISER(o)
  cas CONTIENT_UN(q, {"document"})
    retourner IA_DOCUMENTER(o)
  cas CONTIENT_UN(q, {"explique", "fonctionnement", "comment", "que fait"})
    retourner IA_EXPLIQUER(o)
  fincas
retourner IA_RESUMER(o)

fonction IA_RESUMER(o)
  locale md = {"**" + o.sch + "." + o.nom + "** — " + LIBELLE_GENRE(o.genre) + " de " + o.serveur + " › " + o.base + "."}
  locale d = RQ(nul, "select * from dico_tables where objet_id = ?", {o.id})
  si #d > 0
    inserer(md, d[1].description + ".")
  finsi
  locale m = RQ(nul, "select * from metriques where objet_id = ?", {o.id})
  si #m > 0 et m[1].lignes_code <> nul et m[1].lignes_code > 0
    inserer(md, "Code de " + m[1].lignes_code + " lignes, complexité " + m[1].complexite + sisinon(m[1].maintenabilite = nul, "", ", maintenabilité " + ;
                arrondi(m[1].maintenabilite) + "/100") + ".")
  finsi
  locale lit = {}
  locale ecrit = {}
  locale appelle = {}
  pour chaque r dans RELATIONS(o.id, "sortant", "")
    locale n = DERNIER(sisinon(r.nom = nul, "?", r.nom))
    faire cas
    cas r.nature = "SELECT"
      inserer(lit, n)
    cas r.nature = "EXEC" ou r.nature = "APPEL"
      inserer(appelle, n)
    cas r.nature <> "FK" et r.nature <> "SYNONYME" et r.nature <> "DECLENCHEUR"
      inserer(ecrit, n + " (" + minuscule(r.nature) + ")")
    fincas
  suivant
  si #lit > 0
    inserer(md, "Lit : " + joindre(lit, ", ") + ".")
  finsi
  si #ecrit > 0
    inserer(md, "Écrit : " + joindre(ecrit, ", ") + ".")
  finsi
  si #appelle > 0
    inserer(md, "Appelle : " + joindre(appelle, ", ") + ".")
  finsi
  locale ent = RELATIONS(o.id, "entrant", "")
  si #ent > 0
    locale l = {}
    pour chaque r dans ent
      inserer(l, DERNIER(r.nom))
    suivant
    inserer(md, "Utilisé par " + #ent + " objet(s) : " + COURT(joindre(l, ", "), 300) + ".")
  finsi
  si #m > 0 et m[1].classe <> nul et m[1].classe <> ""
    inserer(md, "Classement : **" + m[1].classe + "**.")
  finsi
retourner joindre(md, " ")

fonction IA_EXPLIQUER(o)
  si o.definition = nul
    retourner IA_RESUMER(o)
  finsi
  locale R = ANALYSER_TEXTE(nul, o.definition, {serveur = o.serveur, base = o.base, sch = o.sch, nom = o.nom, genre = o.genre})
  locale md = {"**Fonctionnement de " + o.sch + "." + o.nom + "**", ""}
  si #R.params > 0
    locale p = {}
    pour chaque x dans R.params
      inserer(p, x.nom + " (" + x.type + sisinon(x.defaut = "", "", ", défaut " + x.defaut) + ")")
    suivant
    inserer(md, "Paramètres : " + joindre(p, ", ") + ".")
    inserer(md, "")
  finsi
  && déroulé par phase, d'après le synoptique
  locale etape = 0
  locale phase = ""
  locale lignes = {}
  pour chaque a dans R.ast
    si a.parent = R.corps
      si a.phase <> phase
        si phase <> ""
          inserer(md, etape + ". **" + phase + "** — " + joindre(lignes, " ; "))
        finsi
        etape += 1
        phase = a.phase
        lignes = {}
      finsi
      si #lignes < 4
        inserer(lignes, COURT(a.libelle, 70))
      finsi
    finsi
  suivant
  si phase <> ""
    inserer(md, etape + ". **" + phase + "** — " + joindre(lignes, " ; "))
  finsi
  si #R.dyn > 0
    inserer(md, "")
    inserer(md, "SQL dynamique : " + #R.dyn + " construction(s), par exemple " + MDCODE(COURT(R.dyn[1].sql, 120)) + ".")
  finsi
  inserer(md, "")
  inserer(md, IA_RESUMER(o))
retourner joindre(md, car(10))

fonction IA_CONSTATS(o, module_)
  locale md = {"**Constats sur " + o.nom + "** :", ""}
  locale n = 0
  pour chaque r dans RQ(nul, "select niveau, module, message, suggestion, ligne from diagnostics where objet_id = ? and (? = '' or module = ?) " + ;
                             "order by case niveau when 'critique' then 1 when 'important' then 2 else 3 end", {o.id, module_, module_})
    n += 1
    inserer(md, "- " + PASTILLE_NIVEAU(r.niveau) + " " + r.message + sisinon(r.ligne = nul, "", " (l." + r.ligne + ")") + " → *" + r.suggestion + "*")
  suivant
  si n = 0
    inserer(md, "Aucun constat pour cet objet.")
  finsi
retourner joindre(md, car(10))

fonction IA_OPTIMISER(o)
  locale md = {IA_CONSTATS(o, "performances")}
  locale st = INDICATEURS_REQUETE(o.id)
  si #st > 0 et st[1].executions <> nul
    inserer(md, "")
    inserer(md, "Mesures : " + NB(st[1].executions) + " exécutions, coût " + arrondi(sisinon(st[1].cout = nul, 0, st[1].cout), 1) + ", " + ;
                arrondi(st[1].temps_ms, 1) + " ms et " + NB(st[1].lectures) + " lectures par exécution ; opérateurs : " + st[1].operateurs + ".")
  finsi
  locale an = RQ(nul, "select message, suggestion from diagnostics where objet_id = ? and module = 'analyse' and regle in " + ;
                      "('SELECT_ETOILE', 'NOLOCK', 'FONCTION_FILTRE', 'LIKE_DEBUT', 'NOT_IN', 'CURSEUR', 'BOUCLE')", {o.id})
  si #an > 0
    inserer(md, "")
    inserer(md, "Réécritures conseillées :")
    pour chaque r dans an
      inserer(md, "- " + r.message + " → " + r.suggestion)
    suivant
  finsi
  pour chaque r dans RQ(nul, "select correctif from diagnostics where objet_id = ? and correctif <> ''", {o.id})
    inserer(md, "")
    inserer(md, "```sql")
    inserer(md, r.correctif)
    inserer(md, "```")
  suivant
retourner joindre(md, car(10))

fonction IA_REFACTORISER(o)
  locale md = {"**Refactorisation de " + o.nom + "** :", ""}
  locale m = RQ(nul, "select * from metriques where objet_id = ?", {o.id})
  si #m > 0 et m[1].complexite <> nul et m[1].complexite > 8
    inserer(md, "- Complexité " + m[1].complexite + " : découper par phases (onglet Refactoring › *Découper par phases*).")
  finsi
  pour chaque r dans RQ(nul, "select distinct u.groupe, u.genre, u.proposition, (select string_agg(distinct o2.nom, ', ') from duplications u2 " + ;
                             "join objets o2 on o2.id = u2.objet_id where u2.groupe = u.groupe and u2.objet_id <> u.objet_id) as autres " + ;
                             "from duplications u where u.objet_id = ?", {o.id})
    inserer(md, "- Duplication (" + r.genre + ", groupe " + r.groupe + ") avec " + sisinon(r.autres = nul, "?", r.autres) + " → " + r.proposition)
  suivant
  pour chaque r dans RQ(nul, "select message, suggestion from diagnostics where objet_id = ? and regle in ('CURSEUR', 'BOUCLE', 'GOTO', 'INJECTION')", {o.id})
    inserer(md, "- " + r.message + " → " + r.suggestion)
  suivant
  si #md = 2
    inserer(md, "Rien de prioritaire : code simple et sans duplication détectée.")
  finsi
retourner joindre(md, car(10))

fonction IA_DOCUMENTER(o)
  locale md = {"## " + o.sch + "." + o.nom, "", "*" + LIBELLE_GENRE(o.genre) + " · " + o.serveur + " › " + o.base + "*", "", IA_RESUMER(o), ""}
  si o.definition <> nul
    inserer(md, IA_EXPLIQUER(o))
    inserer(md, "")
  finsi
  locale cols = RQ(nul, "select c.nom, c.type_sql, d.description from colonnes c left join dico_colonnes d on d.objet_id = c.objet_id " + ;
                        "and d.colonne = c.nom where c.objet_id = ? order by c.ordre", {o.id})
  si #cols > 0
    inserer(md, "| Colonne | Type | Description |")
    inserer(md, "|---|---|---|")
    pour chaque c dans cols
      inserer(md, "| " + c.nom + " | " + MDCELL(c.type_sql) + " | " + MDCELL(c.description) + " |")
    suivant
  finsi
retourner joindre(md, car(10))
