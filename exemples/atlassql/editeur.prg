&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atlas SQL : éditeur SQL avancé (module 9), synoptique logique synchronisé (module 11),
&& débogueur symbolique (module 13) et refactoring assisté (module 15).
&&
&& Éditeur : coloration et complétion SQL (tables, colonnes de l'entrepôt), minicarte,
&& formatage, extraits (snippets), renommage d'un nom dans le document, aller à la
&& définition (F12), constats soulignés pendant la frappe. À droite, en même temps que
&& le code : Synoptique, Arbre, Analyse, Dépendances, Débogueur, Résultat.
&& Le synoptique est recalculé à chaque modification (analyse en ~10-40 ms) et suit
&& le curseur : un clic sur une étape place le curseur sur la ligne.

procedure CONSTRUIRE_EDITEUR(page)
  globale edi, ed
  edi = {docs = {}, version = 0, analyse = nul, chemins = {}, lignes_noeud = {}, dbg = nul}
  locale haut = page:ajouter(ui.rangee())
  haut.marge = 2
  haut.ancrage = "haut"
  OUTIL(haut, "Nouveau", @EDI_NOUVEAU, "Nouveau script SQL")
  OUTIL(haut, "Formater", @EDI_FORMATER, "Mise en forme du script (une instruction par ligne, clauses à la ligne, mots-clés en majuscules)")
  edi.snippets = haut:ajouter(ui.combo())
  edi.snippets.largeurfixe = 210
  edi.snippets:ajouter("Extraits…")
  pour chaque s dans SNIPPETS()
    edi.snippets:ajouter(s[1])
  suivant
  edi.snippets:selectionner(1)
  edi.snippets.surselection = @EDI_SNIPPET
  OUTIL(haut, "Renommer…", @EDI_RENOMMER, "Renommer le nom sous le curseur dans ce document (variable, alias, colonne)")
  OUTIL(haut, "Définition (F12)", @EDI_DEFINITION, "Aller à la définition du nom sous le curseur")
  OUTIL(haut, "▶ Exécuter (lecture)", @EDI_EXECUTER, "Exécuter un SELECT sur la source de l'objet (lecture seule, sources SQL Server)")
  OUTIL(haut, "Enregistrer .sql…", @EDI_ENREGISTRER, "Enregistrer le document dans un fichier")
  edi.info = haut:ajouter(ui.etiquette(""))
  edi.info.poids = 1
  edi.info.couleur = "#9CA3AF"
  locale s1 = page:ajouter(ui.separateur{vertical = vrai, position = 0.56})
  s1.ancrage = "centre"
  ed = s1:ajouter(ui.editeur{minicarte = vrai, taille = reglages.police})
  ed.surchangement = @EDI_MODIFIE
  ed.surselection = @EDI_SIGNAL
  locale droite_ = s1:ajouter(ui.onglets())
  edi.onglets = droite_
  locale psyn = droite_:ajouterpage("Synoptique", "bordure")
  edi.syn = psyn:ajouter(ui.diagramme{modifiable = faux, direction = "bas"})
  edi.syn.ancrage = "centre"
  edi.syn.surselection = @SYN_CHOIX
  locale parb = droite_:ajouterpage("Arbre", "bordure")
  edi.arbre = parb:ajouter(ui.arbre())
  edi.arbre.ancrage = "centre"
  edi.arbre.surselection = @ARBRE_AST_CHOIX
  locale pan = droite_:ajouterpage("Analyse", "bordure")
  edi.analyse_md = pan:ajouter(ui.markdown("Ouvrez un objet (double-clic dans l'explorateur, bouton Code) ou tapez du T-SQL."))
  edi.analyse_md.ancrage = "centre"
  locale pdep = droite_:ajouterpage("Dépendances", "bordure")
  edi.dep_md = pdep:ajouter(ui.markdown(""))
  edi.dep_md.ancrage = "centre"
  locale pdbg = droite_:ajouterpage("Débogueur", "bordure")
  CONSTRUIRE_DEBOGUEUR(pdbg)
  locale pres = droite_:ajouterpage("Résultat", "bordure")
  edi.pres = pres
  edi.res_info = pres:ajouter(ui.etiquette("Sélectionnez un SELECT puis « Exécuter (lecture) »."))
  edi.res_info.ancrage = "haut"
  edi.res = pres:ajouter(ui.grille())
  edi.res.ancrage = "centre"
retourner

fonction DOC_ACTIF()
  locale uid = ed:actif()
  si uid = nul ou uid < 0
    retourner nul
  finsi
retourner edi.docs[chaine(uid)]

procedure OUVRIR_CODE(id, ligne)
  locale o = OBJET(id)
  si o = nul
    retourner
  finsi
  si o.definition = nul
    STATUT(o.nom + " : pas de code (table, index…) — voir ses propriétés et sa cartographie.")
    ALLER_OBJET(id, "code")
    retourner
  finsi
  vues.valeur = INDEX_VUE("Code SQL")
  edi.dernier = id
  edi.ouverts = sisinon(edi.ouverts = nul, 0, edi.ouverts) + 1
  locale uid = nul
  pour chaque k, d dans edi.docs
    si d.id = id
      uid = d.uid
    finsi
  suivant
  si uid = nul
    uid = ed:nouveau(o.sch + "." + o.nom + ".sql")
    ed:fixertexte(o.definition, uid, vrai)
    ed:langage("sql", uid)
    edi.docs[chaine(uid)] = {uid = uid, id = id, nom = o.nom, ctx = {serveur = o.serveur, base = o.base, sch = o.sch, nom = o.nom, genre = o.genre}}
    ed:pastille(ICONE_GENRE(o.genre), uid, COULEUR_GENRE(o.genre))
  sinon
    ed:activer(uid)
  finsi
  si courant = nul ou courant.id <> id
    ALLER_OBJET(id, "code")
  finsi
  ANALYSE_EDITEUR()
  si ligne <> nul et ligne > 0
    ed:aller(ligne, 1)
  finsi
  ed:focus()
retourner

procedure NOUVEAU_SCRIPT(titre, texte_)
  vues.valeur = INDEX_VUE("Code SQL")
  edi.ouverts = sisinon(edi.ouverts = nul, 0, edi.ouverts) + 1
  locale uid = ed:nouveau(titre)
  ed:fixertexte(texte_, uid)
  ed:langage("sql", uid)
  edi.docs[chaine(uid)] = {uid = uid, id = nul, nom = titre, ctx = {serveur = "", base = "", sch = "dbo", nom = titre, genre = "SCRIPT"}}
  ANALYSE_EDITEUR()
retourner

procedure EDI_NOUVEAU(ev)
  NOUVEAU_SCRIPT("script.sql", "-- Nouveau script" + car(10))
retourner

procedure EDI_MODIFIE(ev)
  && analyse différée (~0,4 s après la dernière frappe) : le synoptique suit le code
  edi.version += 1
  ui.minuterie(400, @EDI_ANALYSE_DIFFEREE, faux)
retourner

procedure EDI_ANALYSE_DIFFEREE(ev)
  globale derniere_version
  si derniere_version = edi.version
    retourner
  finsi
  derniere_version = edi.version
  ANALYSE_EDITEUR()
retourner

procedure EDI_SIGNAL(ev)
  locale s = ev.texte
  faire cas
  cas commencepar(s, "pos:")
    SYNOPTIQUE_SUIVRE()
  cas commencepar(s, "doc:")
    ANALYSE_EDITEUR()
  cas commencepar(s, "cmd:definition:")
    ALLER_DEFINITION(souschaine(s, 16))
  cas s = "cmd:save"
    EDI_ENREGISTRER(nul)
  cas s = "cmd:run"
    EDI_EXECUTER(nul)
  cas commencepar(s, "cmd:close:")
    locale uid = nombre(souschaine(s, 11))
    edi.docs[chaine(uid)] = nul
    ed:fermer(uid)
  cas s = "cmd:stepinto"
    DBG_PAS_DETAILLE(nul)
  cas s = "cmd:stepover"
    DBG_PAS(nul)
  cas s = "cmd:debug"
    DBG_CONTINUER(nul)
  cas s = "cmd:stop"
    DBG_ARRETER(nul)
  fincas
retourner

&&
&& Analyse du document : synoptique, arbre, analyse, constats soulignés
&&

procedure ANALYSE_EDITEUR
  locale d = DOC_ACTIF()
  si d = nul
    retourner
  finsi
  locale t0 = systeme.horloge()
  locale txt = ed:texte()
  locale R = ANALYSER_TEXTE(nul, txt, d.ctx)
  edi.analyse = R
  edi.ctx = d.ctx
  && constats soulignés
  locale diags = {}
  pour chaque x dans R.diag
    inserer(diags, {ligne = x.ligne, colonne = 1, longueur = 200, genre = sisinon(x.niveau = "critique", "erreur", "avertissement"), ;
                    message = x.message + " — " + x.suggestion})
  suivant
  essayer
    ed:diagnostics(diags)
  capturer e
  finessayer
  SYNOPTIQUE(R)
  ARBRE_AST(R)
  ANALYSE_MD(R, d)
  edi.info.libelle = R.lignes + " lignes · " + #R.instructions + " instructions · complexité " + R.complexite + " · " + ;
                     #R.refs + " références · analyse " + arrondi((systeme.horloge() - t0) * 1000) + " ms"
retourner

procedure SYNOPTIQUE(R)
  && blocs successifs de même phase, dans l'ordre du corps de la procédure
  locale d = edi.syn
  d:vider()
  edi.lignes_noeud = {}
  locale blocs = {}
  locale cour = nul
  pour chaque a dans R.ast
    si a.parent = R.corps
      locale ph = sisinon(a.phase = "", "Traitements", a.phase)
      si cour = nul ou cour.phase <> ph
        cour = {phase = ph, lignes = {}, l1 = a.l1, l2 = a.l2, n = 0}
        inserer(blocs, cour)
      finsi
      cour.n += 1
      cour.l2 = max(cour.l2, a.l2)
      inserer(cour.lignes, {texte = COURT(a.libelle, 46), detail = "l." + a.l1, ligne = a.l1})
    finsi
  suivant
  locale i = 0
  locale prec = nul
  pour chaque b dans blocs
    i += 1
    locale lignes = {}
    locale nl = {}
    pour chaque l dans b.lignes
      si #lignes < 9
        inserer(lignes, {texte = l.texte, detail = l.detail})
        inserer(nl, l.ligne)
      finsi
    suivant
    si #b.lignes > 9
      inserer(lignes, {texte = "… " + (#b.lignes - 9) + " autre(s)", detail = ""})
      inserer(nl, b.lignes[10].ligne)
    finsi
    locale id = "P" + i
    edi.lignes_noeud[id] = {l1 = b.l1, l2 = b.l2, lignes = nl}
    d:noeud{id = id, titre = i + ". " + b.phase, soustitre = "lignes " + b.l1 + "–" + b.l2 + " · " + b.n + " instruction(s)", ;
            lignes = lignes, couleur = COULEUR_PHASE(b.phase)}
    si prec <> nul
      d:lien{de = prec, a = id, fleche = vrai, couleur = "#94A3B8"}
    finsi
    prec = id
  suivant
  d:disposer("bas")
  d:ajuster(55)
retourner

fonction COULEUR_PHASE(p)
  locale t = {}
  t["Déclarations"] = "#64748B"
  t["Initialisation"] = "#0EA5E9"
  t["Contrôles"] = "#F59E0B"
  t["Chargement"] = "#3B82F6"
  t["Calcul"] = "#8B5CF6"
  t["Écriture"] = "#22C55E"
  t["Archivage"] = "#14B8A6"
  t["Purge"] = "#EF4444"
  t["Restitution"] = "#EC4899"
  t["Gestion d'erreurs"] = "#DC2626"
  t["Transaction"] = "#A3A3A3"
  t["Traitements"] = "#6366F1"
  t["Traces"] = "#78716C"
  locale c = t[p]
retourner sisinon(c = nul, "#6B7280", c)

procedure SYN_CHOIX(ev)
  locale n = edi.lignes_noeud[ev.texte]
  si n = nul
    retourner
  finsi
  locale l = n.l1
  si ev.index <> nul et ev.index >= 1 et ev.index <= #n.lignes
    l = n.lignes[ev.index]
  finsi
  ed:aller(l, 1)
  ed:focus()
retourner

procedure SYNOPTIQUE_SUIVRE
  && le bloc du synoptique qui contient la ligne du curseur est sélectionné
  locale c = ed:curseur()
  si c = nul
    retourner
  finsi
  pour chaque k, n dans edi.lignes_noeud
    si c.ligne >= n.l1 et c.ligne <= n.l2
      locale sel = edi.syn:selection()
      si sel = nul ou sel.id <> k
        edi.syn:selectionner(k)
      finsi
      retourner
    finsi
  suivant
retourner

procedure ARBRE_AST(R)
  locale a_ = edi.arbre
  a_:vider()
  edi.chemins = {}
  locale chemins = {}
  pour chaque n dans R.ast
    locale lib = sisinon(n.genre = "RACINE", n.libelle, "l." + n.l1 + "  " + COURT(n.libelle, 60) + sisinon(n.phase = "", "", "  [" + n.phase + "]"))
    locale p = sisinon(n.parent = 0, lib, chemins[chaine(n.parent)] + ui.sep + lib)
    chemins[chaine(n.id)] = p
    edi.chemins[p] = n.l1
    a_:ajouter(p)
  suivant
  si #R.ast > 0
    a_:deplier(chemins["1"])
  finsi
retourner

procedure ARBRE_AST_CHOIX(ev)
  locale l = edi.chemins[ev.texte]
  si l <> nul
    ed:aller(l, 1)
  finsi
retourner

procedure ANALYSE_MD(R, d)
  locale md = {"### " + d.nom, ""}
  inserer(md, "**" + R.lignes + "** lignes · **" + #R.instructions + "** instructions · complexité cyclomatique **" + R.complexite + "**")
  inserer(md, "")
  si #R.phases > 0
    inserer(md, "**Synoptique** : " + joindre(R.phases, " → "))
    inserer(md, "")
  finsi
  locale groupes = {{"parametre", "Paramètres"}, {"variable", "Variables"}, {"table_temp", "Tables temporaires"}, ;
                    {"variable_table", "Variables tables"}, {"curseur", "Curseurs"}, {"cte", "CTE"}}
  pour chaque g dans groupes
    locale l = {}
    pour chaque v dans R.vars
      si v.genre = g[1]
        inserer(l, MDCODE(v.nom) + sisinon(v.type = "", "", " " + v.type) + sisinon(v.defaut = "", "", " = " + MDCODE(v.defaut)) + " *(l." + v.ligne + ")*")
      finsi
    suivant
    si #l > 0
      inserer(md, "**" + g[2] + "** : " + joindre(l, " · "))
      inserer(md, "")
    finsi
  suivant
  locale parn = {}
  pour chaque rf dans R.refs
    si parn[rf.nature] = nul
      parn[rf.nature] = {}
    finsi
    si non (rf.ref $ joindre(parn[rf.nature], "|"))
      inserer(parn[rf.nature], rf.ref)
    finsi
  suivant
  si #R.refs > 0
    inserer(md, "#### Références")
    pour chaque k, l2 dans parn
      inserer(md, "- **" + k + "** : " + joindre(l2, ", "))
    suivant
    inserer(md, "")
  finsi
  si #R.dyn > 0
    inserer(md, "#### SQL dynamique")
    pour chaque x dans R.dyn
      inserer(md, "- l." + x.ligne + " " + x.mode + " : " + MDCODE(COURT(x.sql, 160)) + sisinon(x.params = "", "", " — " + MDCELL(x.params)))
    suivant
    inserer(md, "")
  finsi
  si #R.diag > 0
    inserer(md, "#### Constats")
    pour chaque x dans R.diag
      inserer(md, "- " + PASTILLE_NIVEAU(x.niveau) + " l." + x.ligne + " " + x.message + " — *" + x.suggestion + "*")
    suivant
  finsi
  edi.analyse_md.valeur = MD(joindre(md, car(10)))
  && dépendances (entrepôt) de l'objet
  si d.id <> nul
    locale dm = {"### Dépendances de " + d.nom, ""}
    pour chaque x dans RELATIONS(d.id, "sortant", "")
      inserer(dm, "- ➜ **" + x.nature + "** " + sisinon(x.nom = nul, "?", x.nom) + sisinon(x.interserveur, " · *inter-serveur*", sisinon(x.interbase, " · *inter-base*", "")))
    suivant
    inserer(dm, "")
    pour chaque x dans RELATIONS(d.id, "entrant", "")
      inserer(dm, "- ⬅ " + x.nom + " (" + x.nature + ")")
    suivant
    edi.dep_md.valeur = joindre(dm, car(10))
  finsi
retourner

&&
&& Commandes de l'éditeur
&&

procedure EDI_FORMATER(ev)
  locale t = ed:texte()
  si rogner(t) = ""
    retourner
  finsi
  ed:fixertexte(FORMATER_SQL(nul, t))
  STATUT("Script mis en forme.")
retourner

fonction SNIPPETS()
retourner { ;
  {"TRY … CATCH avec transaction", "BEGIN TRY" + car(10) + "    BEGIN TRANSACTION;" + car(10) + "    -- traitement" + car(10) + ;
     "    COMMIT TRANSACTION;" + car(10) + "END TRY" + car(10) + "BEGIN CATCH" + car(10) + "    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;" + car(10) + "    THROW;" + car(10) + "END CATCH;" + car(10)}, ;
  {"MERGE (upsert)", "MERGE dbo.CIBLE AS C" + car(10) + "USING dbo.SOURCE AS S ON C.ID = S.ID" + car(10) + ;
     "WHEN MATCHED THEN UPDATE SET C.VALEUR = S.VALEUR" + car(10) + "WHEN NOT MATCHED THEN INSERT (ID, VALEUR) VALUES (S.ID, S.VALEUR);" + car(10)}, ;
  {"CTE récursive", "WITH arbre AS (" + car(10) + "    SELECT ID, PARENT_ID, 0 AS NIVEAU FROM dbo.T WHERE PARENT_ID IS NULL" + car(10) + ;
     "    UNION ALL" + car(10) + "    SELECT t.ID, t.PARENT_ID, a.NIVEAU + 1 FROM dbo.T t JOIN arbre a ON t.PARENT_ID = a.ID" + car(10) + ")" + car(10) + "SELECT * FROM arbre;" + car(10)}, ;
  {"Curseur → ensembliste", "-- au lieu d'un curseur : une seule instruction" + car(10) + "UPDATE S SET S.QTE = M.TOTAL" + car(10) + ;
     "FROM dbo.STOCK S" + car(10) + "JOIN (SELECT ARTICLE, SUM(QTE) AS TOTAL FROM dbo.MOUVEMENT GROUP BY ARTICLE) M ON M.ARTICLE = S.ARTICLE;" + car(10)}, ;
  {"SQL dynamique paramétré", "DECLARE @sql NVARCHAR(MAX) = N'SELECT * FROM dbo.T WHERE ID = @id';" + car(10) + ;
     "EXEC sp_executesql @sql, N'@id INT', @id = @Valeur;" + car(10)}, ;
  {"Pagination OFFSET / FETCH", "SELECT ID, NOM FROM dbo.T" + car(10) + "ORDER BY NOM" + car(10) + "OFFSET @Page * @Taille ROWS FETCH NEXT @Taille ROWS ONLY;" + car(10)}, ;
  {"Traitement par lots", "WHILE 1 = 1" + car(10) + "BEGIN" + car(10) + "    DELETE TOP (5000) FROM dbo.LOG WHERE DATE_LOG < @Limite;" + car(10) + ;
     "    IF @@ROWCOUNT = 0 BREAK;" + car(10) + "END;" + car(10)}, ;
  {"Index couvrant", "CREATE NONCLUSTERED INDEX IX_TABLE_COL ON dbo.TABLE (COL_FILTRE, COL_TRI) INCLUDE (COL_LUE);" + car(10)}, ;
  {"Procédure (modèle)", "CREATE OR ALTER PROCEDURE dbo.SP_NOUVELLE" + car(10) + "    @Param INT" + car(10) + "AS" + car(10) + "BEGIN" + car(10) + ;
     "    SET NOCOUNT ON;" + car(10) + "    SET XACT_ABORT ON;" + car(10) + "    -- contrôles" + car(10) + "    -- chargement" + car(10) + ;
     "    -- traitement" + car(10) + "    -- restitution" + car(10) + "END;" + car(10)}}

procedure EDI_SNIPPET(ev)
  locale i = edi.snippets:selection()
  si i = nul ou i <= 1
    retourner
  finsi
  si DOC_ACTIF() = nul
    NOUVEAU_SCRIPT("script.sql", "")
  finsi
  ed:inserer(SNIPPETS()[i - 1][2])
  edi.snippets:selectionner(1)
  ed:focus()
retourner

procedure EDI_RENOMMER(ev)
  && renommage intelligent dans le document : mot entier, hors chaînes et commentaires
  locale mot = rogner(ed:motcourant())
  si mot = ""
    STATUT("Placez le curseur sur un nom (variable, alias, colonne).")
    retourner
  finsi
  locale nouveau = ui.demander("Renommer « " + mot + " » en :", mot)
  si nouveau = nul ou nouveau = "" ou nouveau = mot
    retourner
  finsi
  locale r = RQ(nul, "select regexp_replace(?, ?, ?, 'g') as t", {ed:texte(), "(?i)(^|[^A-Za-z0-9_@#$])" + ;
                remplacertexte(remplacertexte(mot, "@", "\\@"), "#", "\\#") + "($|[^A-Za-z0-9_$#])", "\\1" + nouveau + "\\2"})
  locale avant = ed:texte()
  ed:fixertexte(r[1].t)
  locale n = (#r[1].t - #avant) / max(1, #nouveau - #mot)
  STATUT("« " + mot + " » renommé en « " + nouveau + " »" + sisinon(#nouveau <> #mot, " (" + arrondi(abs(n)) + " occurrence(s))", "") + ;
         " — pour un objet de la base, utilisez l'onglet Refactoring (impacts sur tout le patrimoine).")
  ANALYSE_EDITEUR()
retourner

procedure EDI_DEFINITION(ev)
  ALLER_DEFINITION(ed:motcourant())
retourner

procedure ALLER_DEFINITION(mot)
  mot = rogner(sisinon(mot = nul, "", mot))
  si mot = ""
    retourner
  finsi
  && variable ou paramètre : sa déclaration
  si edi.analyse <> nul
    pour chaque v dans edi.analyse.vars
      si majuscule(v.nom) = majuscule(mot)
        ed:aller(v.ligne, 1)
        retourner
      finsi
    suivant
  finsi
  && objet de l'entrepôt
  locale nomr = DERNIER(remplacertexte(remplacertexte(mot, "[", ""), "]", ""))
  locale r = RQ(nul, "select id from objets where lower(nom) = lower(?) and genre in ('TABLE', 'VUE', 'PROCEDURE', 'FONCTION', 'SYNONYME') " + ;
                     "order by case when serveur = ? then 0 else 1 end limit 1", {nomr, sisinon(edi.ctx = nul, "", edi.ctx.serveur)})
  si #r > 0
    OUVRIR_CODE(r[1].id)
    ALLER_OBJET(r[1].id, "definition")
  sinon
    STATUT("Définition de « " + mot + " » introuvable dans l'entrepôt.")
  finsi
retourner

procedure EDI_ENREGISTRER(ev)
  locale d = DOC_ACTIF()
  si d = nul
    retourner
  finsi
  locale p = ui.enregistrerfichier{nom = d.nom + sisinon(finitpar(minuscule(d.nom), ".sql"), "", ".sql"), filtre = "SQL|*.sql"}
  si p <> nul
    ed:enregistrer(p)
    STATUT("Enregistré : " + p)
  finsi
retourner

procedure EDI_EXECUTER(ev)
  && lecture seule : uniquement SELECT / WITH, sur la source SQL Server de l'objet
  locale txt = ed:selection()
  si txt = nul ou rogner(txt) = ""
    txt = ed:texte()
  finsi
  locale u = majuscule(rogner(txt))
  si non (commencepar(u, "SELECT") ou commencepar(u, "WITH"))
    edi.res_info.libelle = "Exécution refusée : seuls les SELECT sont exécutés (Atlas ne modifie jamais les bases analysées)."
    edi.onglets.valeur = 6
    retourner
  finsi
  locale src = nul
  si courant <> nul
    locale r = RQ(nul, "select * from sources where id = ?", {courant.source_id})
    si #r > 0
      src = r[1]
    finsi
  finsi
  si src = nul ou (src.genre <> "mssql" et src.genre <> "odbc")
    edi.res_info.libelle = "Exécution possible sur une source SQL Server réelle (la démonstration et les scripts n'ont pas de serveur)."
    edi.onglets.valeur = 6
    retourner
  finsi
  essayer
    ATTACHER(src, faux)
    locale t0 = systeme.horloge()
    locale lignes = RQ(nul, "select * from " + FONCTION_SCAN(src, rogner(txt)) + " limit 500", nul)
    edi.res:detruire()
    edi.res = edi.pres:ajouter(ui.grille())
    edi.res.ancrage = "centre"
    si #lignes > 0
      locale cles = {}
      pour chaque k, v dans lignes[1]
        edi.res:ajoutercolonne{nom = k, titre = k, largeur = 130}
        inserer(cles, k)
      suivant
      pour chaque l dans lignes
        locale cel = {}
        pour chaque k dans cles
          inserer(cel, sisinon(l[k] = nul, "∅", chaine(l[k])))
        suivant
        edi.res:ajouterligne(cel)
      suivant
    finsi
    edi.res_info.libelle = #lignes + " ligne(s) en " + DUREE_TEXTE(systeme.horloge() - t0) + " (500 au plus)"
  capturer e
    edi.res_info.libelle = "Erreur : " + COURT(e, 300)
  finessayer
  edi.onglets.valeur = 6
retourner

&&
&& Débogueur symbolique (module 13)
&&
&& Sans exécuter le code sur le serveur, le débogueur parcourt les instructions dans
&& l'ordre, entre dans les procédures appelées (pas à pas détaillé), s'arrête aux points
&& d'arrêt (F9 dans la marge) et montre à chaque pas : paramètres (valeurs saisies ou
&& capturées), variables (dernière valeur affectée, symbolique), tables temporaires,
&& curseurs, CTE, et l'historique complet de l'exécution.
&&

procedure CONSTRUIRE_DEBOGUEUR(page)
  locale haut = page:ajouter(ui.rangee())
  haut.marge = 2
  haut.ancrage = "haut"
  OUTIL(haut, "▶ Démarrer", @DBG_DEMARRER, "Démarrer le débogage du document (F5 dans l'éditeur : continuer)")
  OUTIL(haut, "Pas (F10)", @DBG_PAS, "Instruction suivante")
  OUTIL(haut, "Détaillé (F11)", @DBG_PAS_DETAILLE, "Entrer dans la procédure appelée (EXEC)")
  OUTIL(haut, "→ Curseur", @DBG_JUSQUAU_CURSEUR, "Exécuter jusqu'à la ligne du curseur")
  OUTIL(haut, "Continuer", @DBG_CONTINUER, "Jusqu'au prochain point d'arrêt (F9)")
  OUTIL(haut, "■", @DBG_ARRETER, "Arrêter")
  locale s1 = page:ajouter(ui.separateur{vertical = faux, position = 0.62})
  s1.ancrage = "centre"
  edi.dbg_etat = GRILLE(s1, {{"genre", "Genre", 110}, {"nom", "Nom", 140}, {"valeur", "Valeur (symbolique)", 300}, {"ligne", "Ligne", 50, "nombre"}})
  edi.dbg_etat:fixerrupture("genre")
  edi.dbg_hist = s1:ajouter(ui.liste())
retourner

procedure DBG_DEMARRER(ev)
  locale d = DOC_ACTIF()
  si d = nul
    STATUT("Ouvrez d'abord un objet dans l'éditeur.")
    retourner
  finsi
  ANALYSE_EDITEUR()
  locale R = edi.analyse
  && valeurs des paramètres : dernier appel capturé, sinon valeurs par défaut
  locale valeurs = {}
  pour chaque p dans R.params
    valeurs[majuscule(p.nom)] = sisinon(p.defaut = "", "NULL", p.defaut)
  suivant
  locale caps = RQ(nul, "select parametres from captures where lower(objet) like ? order by quand desc limit 1", {"%" + minuscule(d.nom)})
  si edi.params_force <> nul
    && simulation d'un appel capturé (paramètres éventuellement modifiés dans l'onglet Captures)
    caps = {{parametres = edi.params_force}}
    edi.params_force = nul
  finsi
  si #caps > 0
    essayer
      pour chaque k, v dans dejson(caps[1].parametres)
        valeurs["@" + majuscule(k)] = sisinon(v = nul, "NULL", chaine(v))
      suivant
    capturer e
    finessayer
  finsi
  edi.dbg = {pile = {{doc = d.uid, R = R, pos = 0, nom = d.nom}}, valeurs = valeurs, vars = {}, temps = {}, curseurs = {}, ctes = {}, ;
             pas = 0, debut = systeme.horloge()}
  edi.dbg_hist:vider()
  edi.dbg_hist:ajouter("▶ Débogage de " + d.nom + " (" + #R.instructions + " instructions)" + sisinon(#caps > 0, " — paramètres du dernier appel capturé", ""))
  edi.onglets.valeur = 5
  DBG_PAS(nul)
retourner

fonction DBG_CADRE()
  si edi.dbg = nul ou #edi.dbg.pile = 0
    retourner nul
  finsi
retourner edi.dbg.pile[#edi.dbg.pile]

procedure DBG_PAS(ev)
  DBG_AVANCER(faux)
retourner

procedure DBG_PAS_DETAILLE(ev)
  DBG_AVANCER(vrai)
retourner

procedure DBG_AVANCER(entrer)
  locale c = DBG_CADRE()
  si c = nul
    DBG_DEMARRER(nul)
    retourner
  finsi
  && entrer dans la procédure appelée par l'instruction courante
  si entrer et c.pos >= 1 et c.pos <= #c.R.instructions
    locale ins = c.R.instructions[c.pos]
    si ins.genre = "EXEC" ou ins.genre = "EXECUTE"
      pour chaque rf dans c.R.refs
        si rf.nature = "EXEC" et rf.ligne >= ins.l1 et rf.ligne <= ins.l2
          locale r = RQ(nul, "select id from objets where lower(nom) = lower(?) and definition is not null limit 1", {rf.p1})
          si #r > 0
            OUVRIR_CODE(r[1].id)
            locale d = DOC_ACTIF()
            inserer(edi.dbg.pile, {doc = d.uid, R = edi.analyse, pos = 0, nom = d.nom})
            edi.dbg_hist:ajouter("↘ entrée dans " + d.nom)
            c = DBG_CADRE()
          finsi
          sortir
        finsi
      suivant
    finsi
  finsi
  c.pos += 1
  si c.pos > #c.R.instructions
    && fin de la procédure : retour à l'appelant
    edi.dbg_hist:ajouter("↗ fin de " + c.nom)
    retirer(edi.dbg.pile)
    si #edi.dbg.pile = 0
      edi.dbg_hist:ajouter("■ fin du débogage — " + edi.dbg.pas + " pas")
      ed:lignexecution()
      edi.dbg = nul
      retourner
    finsi
    c = DBG_CADRE()
    ed:activer(c.doc)
  finsi
  DBG_EXECUTER_PAS(c)
retourner

procedure DBG_EXECUTER_PAS(c)
  locale ins = c.R.instructions[c.pos]
  edi.dbg.pas += 1
  ed:activer(c.doc)
  ed:lignexecution(ins.l1)
  ed:aller(ins.l1, 1)
  && effets symboliques de l'instruction
  locale t = ins.texte
  locale u = majuscule(t)
  faire cas
  cas ins.genre = "DECLARE"
    pour chaque v dans c.R.vars
      si v.ligne >= ins.l1 et v.ligne <= ins.l2
        faire cas
        cas v.genre = "curseur"
          edi.dbg.curseurs[majuscule(v.nom)] = {nom = v.nom, etat = "déclaré", ligne = v.ligne}
        cas v.genre = "variable_table"
          edi.dbg.temps[majuscule(v.nom)] = {nom = v.nom, valeur = "variable table (vide)", ligne = v.ligne}
        autrement
          edi.dbg.vars[majuscule(v.nom)] = {nom = v.nom, valeur = sisinon(v.defaut = "", "NULL", v.defaut) + sisinon(v.type = "", "", "  : " + v.type), ligne = v.ligne}
        fincas
      finsi
    suivant
  cas ins.genre = "SET" ou (ins.genre = "SELECT" et #t > 8 et commencepar(u, "SELECT @"))
    && SET @x = expr / SELECT @x = col FROM t
    pour chaque m dans decouper(souschaine(t, sisinon(ins.genre = "SET", 5, 8)), ",")
      locale e = position("=", m)
      si e > 0 et commencepar(rogner(m), "@")
        locale nomv = rogner(gauche(m, e - 1))
        locale val = rogner(souschaine(m, e + 1))
        si ins.genre = "SELECT" et " FROM " $ majuscule(val)
          val = val + "  ← lu en base"
        finsi
        edi.dbg.vars[majuscule(nomv)] = {nom = nomv, valeur = DBG_SUBSTITUER(COURT(val, 120)), ligne = ins.l1}
      finsi
    suivant
  cas ins.genre = "OPEN" ou ins.genre = "CLOSE" ou ins.genre = "DEALLOCATE"
    locale nomc = majuscule(rogner(souschaine(t, #ins.genre + 2)))
    si edi.dbg.curseurs[nomc] <> nul
      edi.dbg.curseurs[nomc].etat = sisinon(ins.genre = "OPEN", "ouvert", sisinon(ins.genre = "CLOSE", "fermé", "désalloué"))
    finsi
  cas ins.genre = "FETCH"
    locale p = position(" INTO ", u)
    si p > 0
      pour chaque v dans decouper(souschaine(t, p + 6), ",")
        edi.dbg.vars[majuscule(rogner(v))] = {nom = rogner(v), valeur = "← ligne suivante du curseur", ligne = ins.l1}
      suivant
    finsi
  cas ins.genre = "WITH"
    pour chaque v dans c.R.vars
      si v.genre = "cte" et v.ligne >= ins.l1 et v.ligne <= ins.l2
        edi.dbg.ctes[majuscule(v.nom)] = {nom = v.nom, valeur = "CTE (portée : l'instruction)", ligne = v.ligne}
      finsi
    suivant
  fincas
  && tables temporaires créées par l'instruction
  pour chaque v dans c.R.vars
    si v.genre = "table_temp" et v.ligne >= ins.l1 et v.ligne <= ins.l2
      edi.dbg.temps[majuscule(v.nom)] = {nom = v.nom, valeur = "créée (" + v.type + ")" + sisinon(ins.tables = "", "", " depuis " + COURT(ins.tables, 80)), ligne = v.ligne}
    finsi
  suivant
  si ins.genre = "INSERT" ou ins.genre = "UPDATE" ou ins.genre = "DELETE"
    pour chaque k, v dans edi.dbg.temps
      si (majuscule(v.nom) $ u)
        v.valeur = v.valeur + " · " + minuscule(ins.genre)
      finsi
    suivant
  finsi
  edi.dbg_hist:ajouter("#" + edi.dbg.pas + "  " + c.nom + " l." + ins.l1 + "  [" + ins.phase + "]  " + COURT(t, 90))
  DBG_AFFICHER(c)
retourner

fonction DBG_SUBSTITUER(expr)
  && remplace les paramètres connus par leur valeur
  locale r = expr
  pour chaque k, v dans edi.dbg.valeurs
    r = REMPLACER_CASSE(r, k, k + "⟨" + v + "⟩")
  suivant
retourner r

procedure DBG_AFFICHER(c)
  locale g = edi.dbg_etat
  g:vider()
  pour chaque p dans c.R.params
    g:ajouterligne("Paramètres", p.nom, sisinon(edi.dbg.valeurs[majuscule(p.nom)] = nul, "NULL", edi.dbg.valeurs[majuscule(p.nom)]) + "  : " + p.type, nul)
  suivant
  pour chaque k, v dans edi.dbg.vars
    g:ajouterligne("Variables", v.nom, v.valeur, v.ligne)
  suivant
  pour chaque k, v dans edi.dbg.temps
    g:ajouterligne("Tables temporaires", v.nom, v.valeur, v.ligne)
  suivant
  pour chaque k, v dans edi.dbg.curseurs
    g:ajouterligne("Curseurs", v.nom, v.etat, v.ligne)
  suivant
  pour chaque k, v dans edi.dbg.ctes
    g:ajouterligne("CTE", v.nom, v.valeur, v.ligne)
  suivant
  locale pile = {}
  pour chaque f dans edi.dbg.pile
    inserer(pile, f.nom)
  suivant
  STATUT("Débogueur : pas " + edi.dbg.pas + " · pile " + joindre(pile, " › ") + " · ligne " + c.R.instructions[c.pos].l1)
retourner

procedure DBG_CONTINUER(ev)
  && jusqu'au prochain point d'arrêt (ou la fin)
  si edi.dbg = nul
    DBG_DEMARRER(nul)
  finsi
  locale n = 0
  tantque edi.dbg <> nul et n < 5000
    DBG_AVANCER(faux)
    n += 1
    si edi.dbg = nul
      sortir
    finsi
    locale c = DBG_CADRE()
    locale pa = ed:pointsarret()
    si pa <> nul
      pour chaque l dans pa
        si l = c.R.instructions[c.pos].l1
          edi.dbg_hist:ajouter("● point d'arrêt ligne " + l)
          retourner
        finsi
      suivant
    finsi
  fintantque
retourner

procedure DBG_JUSQUAU_CURSEUR(ev)
  locale cible = ed:curseur().ligne
  si edi.dbg = nul
    DBG_DEMARRER(nul)
  finsi
  locale n = 0
  tantque edi.dbg <> nul et n < 5000
    locale c = DBG_CADRE()
    si c.pos >= 1 et c.R.instructions[c.pos].l1 >= cible
      retourner
    finsi
    DBG_AVANCER(faux)
    n += 1
  fintantque
retourner

procedure DBG_ARRETER(ev)
  si edi.dbg <> nul
    edi.dbg_hist:ajouter("■ arrêté au pas " + edi.dbg.pas)
  finsi
  edi.dbg = nul
  ed:lignexecution()
retourner

&&
&& Complétion : tables et colonnes de l'entrepôt
&&

procedure NOMS_COMPLETION
  locale noms = {}
  pour chaque r dans RQ(nul, "select distinct sch || '.' || nom as n from objets where genre in ('TABLE', 'VUE', 'PROCEDURE', 'FONCTION', 'SYNONYME') " + ;
                             "union select distinct nom from objets where genre in ('TABLE', 'VUE') " + ;
                             "union select distinct table_nom || '.' || nom from colonnes order by 1 limit 20000", nul)
    inserer(noms, r.n)
  suivant
  essayer
    ed:noms(noms)
  capturer e
  finessayer
retourner

&&
&& Refactoring assisté (module 15)
&&

procedure CONSTRUIRE_REFACTORING(page)
  globale ref
  ref = {lignes = {}}
  locale g = page:ajouter(ui.cadre("Opération", "grille"))
  g.ancrage = "haut"
  g:ajouter(ui.etiquette("Opération"))
  ref.op = g:ajouter(ui.combo("Renommer (objet ou colonne)", "Extraire la sélection en procédure", "Découper par phases", ;
                              "Fusionner avec un objet voisin", "Mutualiser un groupe de duplications"))
  ref.op:selectionner(1)
  ref.op.surselection = @REF_OPERATION
  g:ajouter(ui.etiquette("Nom actuel (objet ou colonne)"))
  ref.ancien = g:ajouter(ui.saisie{indication = "CLIENT_ID, vente.CLIENT, SP_LOG…"})
  g:ajouter(ui.etiquette("Nouveau nom"))
  ref.nouveau = g:ajouter(ui.saisie{indication = "ID_CLIENT"})
  locale r = page:ajouter(ui.rangee())
  r.ancrage = "haut"
  OUTIL(r, "Calculer l'impact", @REF_IMPACT, "Objets et lignes touchés, par genre (procédures, vues, fonctions, jobs…)")
  OUTIL(r, "Aperçu → script", @REF_SCRIPT, "Générer le script de la modification (à relire et exécuter par vous)")
  OUTIL(r, "Objet courant", @REF_COURANT, "Reprendre le nom de l'objet courant")
  ref.resume = r:ajouter(ui.etiquette(""))
  ref.resume.poids = 1
  locale s1 = page:ajouter(ui.separateur{vertical = faux, position = 0.3})
  s1.ancrage = "centre"
  ref.synthese = s1:ajouter(ui.markdown("Choisissez une opération : l'impact est calculé sur tout le patrimoine analysé, avec un **aperçu** " + ;
    "ligne par ligne avant la génération du script. Atlas n'applique jamais rien sur les serveurs."))
  ref.g = GRILLE(s1, {{"objet", "Objet", 230}, {"genre", "Genre", 90}, {"ligne", "Ligne", 50, "nombre"}, ;
                      {"avant", "Avant", 420}, {"apres", "Après", 420}})
  ref.g.surdoubleclic = @REF_OUVRIR
retourner

procedure REF_OPERATION(ev)
  locale i = ref.op:selection()
  faire cas
  cas i = 2
    ref.synthese.valeur = "Sélectionnez des instructions dans l'éditeur (onglet Code SQL), puis **Aperçu → script** : la sélection devient " + ;
      "une procédure dont les paramètres sont les variables utilisées mais déclarées ailleurs."
  cas i = 3
    ref.synthese.valeur = "La procédure de l'éditeur est découpée selon les phases de son synoptique : une sous-procédure par phase et une " + ;
      "procédure chef d'orchestre qui les appelle dans l'ordre."
  cas i = 4
    ref.synthese.valeur = "Fusionne l'objet courant avec l'objet le plus semblable (duplications) : une procédure unique avec un paramètre @Mode."
  cas i = 5
    ref.synthese.valeur = "Utilisez l'onglet **Duplications** : sélectionnez une ligne d'un groupe puis « Proposer le code mutualisé »."
  fincas
retourner

procedure REF_COURANT(ev)
  si courant <> nul
    ref.ancien.valeur = courant.nom
  finsi
retourner

procedure REF_IMPACT(ev)
  locale ancien = rogner(sisinon(ref.ancien.valeur = nul, "", ref.ancien.valeur))
  locale nouveau = rogner(sisinon(ref.nouveau.valeur = nul, "", ref.nouveau.valeur))
  si ancien = ""
    STATUT("Indiquez le nom à renommer.")
    retourner
  finsi
  locale nomc = DERNIER(ancien)
  locale objs = IMPACT_COLONNE(nomc, nul)
  ref.g:vider()
  ref.lignes = {}
  locale parg = {}
  locale nlignes = 0
  pour chaque o dans objs
    parg[o.genre] = sisinon(parg[o.genre] = nul, 0, parg[o.genre]) + 1
    pour chaque l dans OCCURRENCES_LIGNES(o.id, nomc)
      nlignes += 1
      locale apres = sisinon(nouveau = "", "", REMPLACER_MOT(l.avant, nomc, nouveau))
      ref.g:ajouterligne(o.sch + "." + o.nom, LIBELLE_GENRE(o.genre), l.ligne, rogner(l.avant), rogner(apres))
      inserer(ref.lignes, {id = o.id, ligne = l.ligne})
    suivant
  suivant
  && colonnes et tables portant ce nom
  locale cols = RQ(nul, "select serveur || ' › ' || base || '.' || sch || '.' || table_nom as t from colonnes where lower(nom) = lower(?)", {nomc})
  locale tabs = RQ(nul, "select serveur || ' › ' || base || '.' || sch || '.' || nom as t, genre from objets where lower(nom) = lower(?)", {nomc})
  locale md = {"### Objet modifié : " + MDCODE(ancien) + sisinon(nouveau = "", "", " → " + MDCODE(nouveau)), ""}
  si #tabs > 0
    inserer(md, "**Défini comme** : " + #tabs + " objet(s) (" + tabs[1].genre + " " + tabs[1].t + ")")
  finsi
  si #cols > 0
    inserer(md, "**Colonne de** : " + #cols + " table(s) — " + COURT(joindre(EXTRAIRE_CHAMP(cols, "t"), ", "), 300))
  finsi
  inserer(md, "")
  inserer(md, "**Impacts** :")
  pour chaque k, v dans parg
    inserer(md, "- **" + v + "** " + minuscule(LIBELLE_GENRE(k)) + sisinon(v > 1, "s", ""))
  suivant
  si #objs = 0
    inserer(md, "- aucun code ne cite ce nom")
  finsi
  && dépendances transitives si c'est un objet
  si #tabs > 0
    locale idt = RV(nul, "select min(id) from objets where lower(nom) = lower(?)", {nomc})
    locale tr = IMPACT_TRANSITIF(idt, 6)
    inserer(md, "")
    inserer(md, "**Impact transitif** (objets qui en dépendent, en cascade) : " + #tr)
  finsi
  inserer(md, "")
  inserer(md, "*" + nlignes + " ligne(s) à modifier : aperçu ci-dessous ; double-clic pour ouvrir le code.*")
  ref.synthese.valeur = MD(joindre(md, car(10)))
  ref.resume.libelle = #objs + " objet(s), " + nlignes + " ligne(s)"
retourner

fonction EXTRAIRE_CHAMP(l, champ)
  locale r = {}
  pour chaque x dans l
    inserer(r, x[majuscule(champ)])
  suivant
retourner r

fonction REMPLACER_MOT(ligne, mot, par)
  locale r = RQ(nul, "select regexp_replace(?, ?, ?, 'g') as t", {ligne, "(?i)(^|[^A-Za-z0-9_@#$])(\\[?)" + mot + "(\\]?)($|[^A-Za-z0-9_$#])", ;
                                                                   "\\1\\2" + par + "\\3\\4"})
retourner r[1].t

procedure REF_OUVRIR(ev)
  locale i = ref.g:selection()
  si i <> nul et i >= 1 et i <= #ref.lignes
    OUVRIR_CODE(ref.lignes[i].id, ref.lignes[i].ligne)
  finsi
retourner

procedure REF_SCRIPT(ev)
  locale op = ref.op:selection()
  faire cas
  cas op = 1
    REF_SCRIPT_RENOMMER()
  cas op = 2
    REF_EXTRAIRE()
  cas op = 3
    REF_DECOUPER()
  cas op = 4
    REF_FUSIONNER()
  cas op = 5
    VOIR_VUE("Duplications")
  fincas
retourner

procedure REF_SCRIPT_RENOMMER
  locale ancien = rogner(sisinon(ref.ancien.valeur = nul, "", ref.ancien.valeur))
  locale nouveau = rogner(sisinon(ref.nouveau.valeur = nul, "", ref.nouveau.valeur))
  si ancien = "" ou nouveau = ""
    STATUT("Indiquez le nom actuel et le nouveau nom.")
    retourner
  finsi
  locale nomc = DERNIER(ancien)
  locale l = {"-- Renommage " + ancien + " → " + nouveau + " (généré par Atlas SQL : relire, tester, puis exécuter)", ;
              "SET XACT_ABORT ON;", "BEGIN TRANSACTION;", ""}
  pour chaque c dans RQ(nul, "select base, sch, table_nom from colonnes where lower(nom) = lower(?)", {nomc})
    inserer(l, "EXEC " + c.base + ".sys.sp_rename N'" + c.sch + "." + c.table_nom + "." + nomc + "', N'" + nouveau + "', 'COLUMN';")
  suivant
  pour chaque o dans RQ(nul, "select base, sch, nom, genre from objets where lower(nom) = lower(?) and genre in ('TABLE', 'VUE', 'PROCEDURE', 'FONCTION')", {nomc})
    inserer(l, "EXEC " + o.base + ".sys.sp_rename N'" + o.sch + "." + o.nom + "', N'" + nouveau + "';")
  suivant
  inserer(l, "")
  pour chaque o dans IMPACT_COLONNE(nomc, nul)
    locale def = OBJET(o.id).definition
    locale nouv = REMPLACER_MOT(def, nomc, nouveau)
    nouv = REMPLACER_CASSE(nouv, "CREATE PROCEDURE", "CREATE OR ALTER PROCEDURE")
    nouv = REMPLACER_CASSE(nouv, "CREATE VIEW", "CREATE OR ALTER VIEW")
    nouv = REMPLACER_CASSE(nouv, "CREATE FUNCTION", "CREATE OR ALTER FUNCTION")
    nouv = REMPLACER_CASSE(nouv, "CREATE TRIGGER", "CREATE OR ALTER TRIGGER")
    inserer(l, "-- " + o.serveur + " › " + o.base + " : " + o.sch + "." + o.nom)
    inserer(l, "USE [" + o.base + "];")
    inserer(l, "GO")
    inserer(l, nouv)
    inserer(l, "GO")
    inserer(l, "")
  suivant
  inserer(l, "COMMIT TRANSACTION;")
  NOUVEAU_SCRIPT("renommage_" + nomc + ".sql", joindre(l, car(10)))
retourner

procedure REF_EXTRAIRE
  locale sel = ed:selection()
  si sel = nul ou rogner(sel) = ""
    STATUT("Sélectionnez des instructions dans l'éditeur (onglet Code SQL).")
    retourner
  finsi
  locale R = edi.analyse
  && variables utilisées dans la sélection et déclarées ailleurs : paramètres
  locale toks = JETONS_TEXTE(nul, sel)
  locale vus = {}
  locale params = {}
  pour chaque j dans toks
    si j.k = "V" et non commencepar(j.o, "@@") et vus[j.u] = nul
      vus[j.u] = vrai
      locale typ = "NVARCHAR(4000)"
      si R <> nul
        pour chaque v dans R.vars
          si majuscule(v.nom) = j.u et v.type <> ""
            typ = v.type
          finsi
        suivant
      finsi
      && déclarée dans la sélection ?
      si non (("DECLARE " + j.u) $ majuscule(sel))
        inserer(params, {nom = j.o, type = typ})
      finsi
    finsi
  suivant
  locale nom = "SP_EXTRAITE_" + entier(aleatoire() * 1000)
  locale lp = {}
  locale la = {}
  pour chaque p dans params
    inserer(lp, "    " + p.nom + " " + p.type)
    inserer(la, p.nom + " = " + p.nom)
  suivant
  locale l = {"-- Extraction (Atlas SQL) : la sélection devient une procédure", "CREATE OR ALTER PROCEDURE dbo." + nom}
  si #lp > 0
    inserer(l, joindre(lp, "," + car(10)))
  finsi
  inserer(l, "AS")
  inserer(l, "BEGIN")
  inserer(l, "    SET NOCOUNT ON;")
  inserer(l, sel)
  inserer(l, "END;")
  inserer(l, "GO")
  inserer(l, "")
  inserer(l, "-- Appel à substituer à la sélection :")
  inserer(l, "EXEC dbo." + nom + sisinon(#la > 0, " " + joindre(la, ", "), "") + ";")
  NOUVEAU_SCRIPT(nom + ".sql", joindre(l, car(10)))
retourner

procedure REF_DECOUPER
  locale d = DOC_ACTIF()
  si d = nul ou edi.analyse = nul
    STATUT("Ouvrez une procédure dans l'éditeur.")
    retourner
  finsi
  locale R = edi.analyse
  locale lignes = decouper(ed:texte(), car(10))
  && blocs de phase (comme le synoptique)
  locale blocs = {}
  locale cour = nul
  pour chaque a dans R.ast
    si a.parent = R.corps
      locale ph = sisinon(a.phase = "", "Traitements", a.phase)
      si cour = nul ou cour.phase <> ph
        cour = {phase = ph, l1 = a.l1, l2 = a.l2}
        inserer(blocs, cour)
      finsi
      cour.l2 = max(cour.l2, a.l2)
    finsi
  suivant
  locale params = {}
  pour chaque p dans R.params
    inserer(params, p.nom + " " + p.type)
  suivant
  locale l = {"-- Découpage de " + d.nom + " en " + #blocs + " phases (Atlas SQL)", ;
              "-- Les variables partagées entre phases sont à passer en paramètres OUTPUT ou dans une table temporaire.", ""}
  locale appels = {}
  locale i = 0
  pour chaque b dans blocs
    si b.phase <> "Déclarations"
      i += 1
      locale nom = d.ctx.sch + "." + d.nom + "_" + i + "_" + MAJ_SANS_ACCENT(b.phase)
      inserer(l, "CREATE OR ALTER PROCEDURE " + nom + sisinon(#params > 0, " " + joindre(params, ", "), ""))
      inserer(l, "AS")
      inserer(l, "BEGIN")
      inserer(l, "    SET NOCOUNT ON;")
      pour k = b.l1 a min(b.l2, #lignes)
        inserer(l, lignes[k])
      suivant
      inserer(l, "END;")
      inserer(l, "GO")
      inserer(l, "")
      inserer(appels, "    EXEC " + nom + sisinon(#R.params > 0, " " + joindre(EXTRAIRE_NOMS(R.params), ", "), "") + ";")
    finsi
  suivant
  inserer(l, "-- Chef d'orchestre")
  inserer(l, "CREATE OR ALTER PROCEDURE " + d.ctx.sch + "." + d.nom + sisinon(#params > 0, " " + joindre(params, ", "), ""))
  inserer(l, "AS")
  inserer(l, "BEGIN")
  inserer(l, "    SET NOCOUNT ON;")
  pour chaque a dans appels
    inserer(l, a)
  suivant
  inserer(l, "END;")
  NOUVEAU_SCRIPT(d.nom + "_decoupe.sql", joindre(l, car(10)))
retourner

fonction EXTRAIRE_NOMS(params)
  locale r = {}
  pour chaque p dans params
    inserer(r, p.nom)
  suivant
retourner r

fonction MAJ_SANS_ACCENT(s)
  locale r = majuscule(s)
  pour chaque p dans {{"É", "E"}, {"È", "E"}, {"Ê", "E"}, {"À", "A"}, {"Ô", "O"}, {"Û", "U"}, {"Ç", "C"}, {"'", ""}, {" ", "_"}}
    r = remplacertexte(r, p[1], p[2])
  suivant
retourner r

procedure REF_FUSIONNER
  si courant = nul
    STATUT("Sélectionnez d'abord un objet.")
    retourner
  finsi
  locale r = RQ(nul, "select u2.objet_id as autre, o.sch || '.' || o.nom as nom, max(u2.similarite) as sim from duplications u1 " + ;
                     "join duplications u2 on u2.groupe = u1.groupe and u2.objet_id <> u1.objet_id join objets o on o.id = u2.objet_id " + ;
                     "where u1.objet_id = ? group by all order by sim desc limit 1", {courant.id})
  si #r = 0
    STATUT("Aucun objet voisin trouvé pour " + courant.nom + " (voir l'onglet Duplications).")
    retourner
  finsi
  locale a = OBJET(courant.id)
  locale b = OBJET(r[1].autre)
  locale l = {"-- Fusion de " + a.sch + "." + a.nom + " et " + r[1].nom + " (similarité " + arrondi(r[1].sim * 100) + " %)", ;
              "-- Procédure unique : @Mode choisit la variante ; les deux anciennes deviennent des enveloppes.", "", ;
              "CREATE OR ALTER PROCEDURE " + a.sch + "." + a.nom + "_FUSION", "    @Mode TINYINT = 1  -- 1 : " + a.nom + ", 2 : " + b.nom, ;
              "    -- + l'union des paramètres des deux procédures", "AS", "BEGIN", "    SET NOCOUNT ON;", "    IF @Mode = 1", "    BEGIN", ;
              "        -- corps de " + a.nom, a.definition, "    END", "    ELSE", "    BEGIN", "        -- corps de " + b.nom, b.definition, "    END", "END;"}
  NOUVEAU_SCRIPT(a.nom + "_fusion.sql", joindre(l, car(10)))
retourner
