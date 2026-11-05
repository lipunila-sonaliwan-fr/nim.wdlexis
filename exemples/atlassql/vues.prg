&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atlas SQL : vues centrales.
&&   Tableau de bord, Cartographie (module 2), Dépendances (3), Dictionnaire (4),
&&   Types métier (5), Flux (12), Duplications (7), SQL dynamique (8),
&&   Performances (10), Patrimoine (16), Diagnostics.
&& (Code SQL, Refactoring : editeur.prg ; Interception : interception.prg ;
&&  Assistant : assistant.prg)

fonction TITRES_VUES()
  && libellés courts des onglets (les noms longs restent dans le menu Affichage)
retourner {"⌂ Accueil", "Carte", "Dépendances", "Dictionnaire", "Types", "Code", "Flux", ;
           "Doublons", "Dynamique", "Perfs", "Patrimoine", "Refacto", "Captures", "Assistant", "Constats"}

fonction NOMS_VUES()
retourner {"Tableau de bord", "Cartographie", "Dépendances", "Dictionnaire", "Types métier", "Code SQL", "Flux", ;
           "Duplications", "SQL dynamique", "Performances", "Patrimoine", "Refactoring", "Interception", "Assistant", ;
           "Diagnostics"}

procedure CONSTRUIRE_VUES(o)
  globale pages
  pages = {}
  locale titres = TITRES_VUES()
  locale noms = NOMS_VUES()
  pour i = 1 a #noms
    pages[noms[i]] = o:ajouterpage(titres[i], "bordure")
  suivant
  CONSTRUIRE_TABLEAU(pages["Tableau de bord"])
  CONSTRUIRE_CARTO(pages["Cartographie"])
  CONSTRUIRE_DEPENDANCES(pages["Dépendances"])
  CONSTRUIRE_DICO(pages["Dictionnaire"])
  CONSTRUIRE_TYPES_VUE(pages["Types métier"])
  CONSTRUIRE_EDITEUR(pages["Code SQL"])
  CONSTRUIRE_FLUX(pages["Flux"])
  CONSTRUIRE_DUP(pages["Duplications"])
  CONSTRUIRE_DYN(pages["SQL dynamique"])
  CONSTRUIRE_PERF(pages["Performances"])
  CONSTRUIRE_PATRIMOINE(pages["Patrimoine"])
  CONSTRUIRE_REFACTORING(pages["Refactoring"])
  CONSTRUIRE_INTERCEPTION(pages["Interception"])
  CONSTRUIRE_ASSISTANT(pages["Assistant"])
  CONSTRUIRE_DIAG(pages["Diagnostics"])
retourner

fonction INDEX_VUE(nom)
  locale l = NOMS_VUES()
  pour i = 1 a #l
    si l[i] = nom
      retourner i
    finsi
  suivant
retourner 1

procedure VOIR_VUE(nom)
  vues.valeur = INDEX_VUE(nom)
  VUE_ACTIVEE(INDEX_VUE(nom))
retourner

procedure VUE_CHANGEE(ev)
  VUE_ACTIVEE(vues.valeur)
retourner

procedure VUE_ACTIVEE(i)
  globale vueactive
  vueactive = nombre(i)
  locale nom = NOMS_VUES()[vueactive]
  faire cas
  cas nom = "Dépendances"
    REMPLIR_DEPENDANCES()
  cas nom = "Cartographie" et carto.niveau = nul
    CARTO_GLOBALE()
  cas nom = "Code SQL"
    && l'éditeur suit l'objet courant ; sans objet, un script vierge plutôt qu'un éditeur vide
    si courant <> nul et courant.id <> edi.dernier et courant.definition <> nul
      OUVRIR_CODE(courant.id)
    sinonsi sisinon(edi.ouverts = nul, 0, edi.ouverts) = 0
      NOUVEAU_SCRIPT("Script 1.sql", "-- Script libre : tapez du T-SQL, l'analyse est immédiate (synoptique, arbre, constats)." + car(10) + car(10))
    finsi
  fincas
retourner

procedure RAFRAICHIR_VUES
  REMPLIR_TABLEAU()
  CARTO_GLOBALE()
  REMPLIR_DICO()
  REMPLIR_TYPES()
  REMPLIR_FLUX()
  REMPLIR_DUP()
  REMPLIR_DYN()
  REMPLIR_PERF()
  REMPLIR_PATRIMOINE()
  REMPLIR_DIAG()
  REMPLIR_CAPTURES()
  NOMS_COMPLETION()
retourner

procedure RAFRAICHIR_VUE_OBJET
  && vues qui suivent l'objet courant
  locale nom = NOMS_VUES()[vueactive]
  faire cas
  cas nom = "Dépendances"
    REMPLIR_DEPENDANCES()
  cas nom = "Cartographie" et carto.suivre
    CARTO_OBJET(courant.id)
  cas nom = "Code SQL"
    && le code n'est ouvert qu'à la demande (double-clic, bouton Code)
  fincas
retourner

fonction GRILLE(parent, colonnes)
  && colonnes : {{nom, titre, largeur[, genre]}…}
  locale g = parent:ajouter(ui.grille())
  pour chaque c dans colonnes
    g:ajoutercolonne{nom = c[1], titre = c[2], largeur = c[3], genre = sisinon(#c >= 4, c[4], "texte")}
  suivant
retourner g

procedure FORMATS_NIVEAU(g, col)
  g:ajouterformat(col, "=", "⬤ critique", {texte = "#FCA5A5", ligneentiere = vrai})
  g:ajouterformat(col, "=", "▲ important", {texte = "#FDBA74"})
  g:ajouterformat(col, "=", "◇ opportunité", {texte = "#FDE68A"})
retourner

fonction NIVEAU_TEXTE(n)
  faire cas
  cas n = "critique"
    retourner "⬤ critique"
  cas n = "important"
    retourner "▲ important"
  cas n = "opportunite"
    retourner "◇ opportunité"
  fincas
retourner "○ " + chaine(n)

&&
&& Tableau de bord
&&

procedure CONSTRUIRE_TABLEAU(page)
  globale tab
  tab = {}
  locale haut = page:ajouter(ui.rangee())
  haut.ancrage = "haut"
  haut.marge = 2
  tab.cartes = {}
  pour chaque c dans {{"objets", "Objets", "#60A5FA"}, {"serveurs", "Serveurs · bases", "#22D3EE"}, ;
                      {"code", "Modules", "#A78BFA"}, {"relations", "Relations", "#2DD4BF"}, ;
                      {"interserveur", "Inter-serveurs", "#FB923C"}, {"rgpd", "Tables RGPD", "#F472B6"}, ;
                      {"critiques", "Critiques", "#F87171"}, {"dette", "Dette", "#FACC15"}, ;
                      {"duplication", "Duplication", "#C084FC"}}
    locale k = haut:ajouter(ui.colonne())
    k.fond = "#1F2937"
    k.rayon = 8
    k.marge = 6
    k.espacement = 0
    k.poids = 1
    locale v = k:ajouter(ui.etiquette("–"))
    v.couleur = c[3]
    locale l = k:ajouter(ui.etiquette(c[2]))
    l.couleur = "#9CA3AF"
    tab.cartes[c[1]] = v
  suivant
  locale centre = page:ajouter(ui.separateur{vertical = faux, position = 0.6})
  centre.ancrage = "centre"
  tab.graphes = centre:ajouter(ui.rangee())
  locale bas_ = centre:ajouter(ui.separateur{vertical = vrai, position = 0.58})
  locale cr = bas_:ajouter(ui.colonne())
  locale lr = cr:ajouter(ui.etiquette("Objets à risque (score : complexité, couplage, dette, criticité)"))
  lr.couleur = "#9CA3AF"
  tab.risques = GRILLE(cr, {{"objet", "Objet", 260}, {"genre", "Genre", 90}, {"score", "Score", 60, "nombre"}, ;
                            {"classe", "Classement", 260}, {"dette", "Dette (min)", 80, "nombre"}})
  tab.risques.poids = 1
  tab.risques.surdoubleclic = @TAB_RISQUE
  tab.synthese = bas_:ajouter(ui.markdown(""))
retourner

procedure CARTE(cle, valeur)
  tab.cartes[cle].libelle = chaine(valeur)
retourner

procedure REMPLIR_TABLEAU
  locale n = RV(nul, "select count(*) from objets", nul)
  CARTE("objets", NB(n))
  CARTE("serveurs", RV(nul, "select count(distinct serveur) from objets", nul) + " · " + ;
        RV(nul, "select count(distinct serveur || base) from objets where genre = 'TABLE'", nul))
  CARTE("code", NB(RV(nul, "select count(*) from metriques where lignes_code > 0", nul)))
  CARTE("relations", NB(RV(nul, "select count(*) from dependances", nul)))
  CARTE("interserveur", NB(RV(nul, "select count(*) from dependances where interserveur", nul)))
  CARTE("rgpd", NB(RV(nul, "select count(*) from dico_tables where rgpd", nul)))
  CARTE("critiques", NB(RV(nul, "select count(*) from diagnostics where niveau = 'critique'", nul)))
  locale dette = RV(nul, "select valeur from meta where cle = 'dette_h'", nul)
  CARTE("dette", sisinon(dette = nul, "–", dette + " h"))
  locale dup = RV(nul, "select valeur from meta where cle = 'dup_pct'", nul)
  CARTE("duplication", sisinon(dup = nul, "–", dup + " %"))
  && graphes (recréés : les graphes n'ont pas de « vider »)
  si tab.g1 <> nul
    tab.g1:detruire()
    tab.g2:detruire()
    tab.g3:detruire()
  finsi
  tab.g1 = tab.graphes:ajouter(ui.graphe("secteurs", "Objets par genre"))
  tab.g1.poids = 1
  locale i = 0
  pour chaque r dans RQ(nul, "select genre, count(*) as n from objets where genre in ('TABLE', 'VUE', 'PROCEDURE', 'FONCTION', " + ;
                             "'DECLENCHEUR', 'SYNONYME', 'JOB', 'INDEX') group by genre order by n desc", nul)
    i += 1
    tab.g1:ajouterdonnee(1, i, r.n)
    tab.g1:libellecategorie(i, LIBELLE_GENRE(r.genre))
  suivant
  tab.g2 = tab.graphes:ajouter(ui.graphe("colonnes", "Constats par module"))
  tab.g2.poids = 1
  i = 0
  locale niveaux = {"critique", "important", "opportunite"}
  pour s = 1 a 3
    tab.g2:libelleserie(s, NIVEAU_TEXTE(niveaux[s]))
  suivant
  pour chaque r dans RQ(nul, "select module, sum(case when niveau = 'critique' then 1 else 0 end) as c, " + ;
                             "sum(case when niveau = 'important' then 1 else 0 end) as i, " + ;
                             "sum(case when niveau = 'opportunite' then 1 else 0 end) as o from diagnostics group by module order by module", nul)
    i += 1
    tab.g2:libellecategorie(i, r.module)
    tab.g2:ajouterdonnee(1, i, r.c)
    tab.g2:ajouterdonnee(2, i, r.i)
    tab.g2:ajouterdonnee(3, i, r.o)
  suivant
  tab.g3 = tab.graphes:ajouter(ui.mosaique())
  tab.g3.poids = 1
  tab.g3.infobulle = "Volume des bases (Mo)"
  pour chaque r dans RQ(nul, "select serveur || ' › ' || base as b, round(sum(coalesce(taille_ko, 0)) / 1024)::bigint as mo from objets " + ;
                             "where genre = 'TABLE' group by 1 order by 2 desc", nul)
    tab.g3:ajouter(r.b + " · " + NB(r.mo) + " Mo", max(1, r.mo))
  suivant
  && objets à risque
  tab.risques:vider()
  tab.risque_ids = {}
  pour chaque r dans RQ(nul, "select o.id, o.sch || '.' || o.nom as nom, o.genre, round(m.score) as score, m.classe, round(m.dette_min) as dette " + ;
                             "from metriques m join objets o on o.id = m.objet_id where m.score is not null order by m.score desc limit 25", nul)
    tab.risques:ajouterligne(r.nom, LIBELLE_GENRE(r.genre), r.score, r.classe, r.dette)
    inserer(tab.risque_ids, r.id)
  suivant
  tab.synthese.valeur = SYNTHESE()
retourner

procedure TAB_RISQUE(ev)
  locale i = tab.risques:selection()
  si i <> nul et i >= 1 et i <= #tab.risque_ids
    ALLER_OBJET(tab.risque_ids[i], "tableau")
  finsi
retourner

fonction SYNTHESE()
  locale md = {"### Synthèse", ""}
  si RV(nul, "select count(*) from objets", nul) = 0
    inserer(md, "Aucune analyse : ajoutez une source (+ Source) puis lancez l'analyse (▶ Analyser, F5).")
    retourner joindre(md, car(10))
  finsi
  pour chaque r dans RQ(nul, "select serveur, count(distinct base) as b, count(*) as n from objets group by serveur order by serveur", nul)
    inserer(md, "- 🖥 **" + r.serveur + "** : " + r.b + " base(s), " + r.n + " objets")
  suivant
  inserer(md, "")
  locale x = RQ(nul, "select (select count(*) from dependances where interbase) as ib, (select count(*) from dependances where interserveur) as isv, " + ;
                     "(select count(*) from sql_dynamique) as dyn, (select count(*) from dependances where vers_id is null) as nr, " + ;
                     "(select count(*) from metriques where classe like '%Inutilisé%') as inu, " + ;
                     "(select count(*) from metriques where classe like '%Obsolète%') as obs", nul)[1]
  inserer(md, "- **" + x.ib + "** dépendances inter-bases, **" + x.isv + "** inter-serveurs (serveurs liés, OPENQUERY, synonymes)")
  inserer(md, "- **" + x.dyn + "** SQL dynamiques reconstitués, **" + x.nr + "** références introuvables")
  inserer(md, "- **" + x.inu + "** objets inutilisés, **" + x.obs + "** obsolètes")
  inserer(md, "")
  inserer(md, "**À traiter en priorité**")
  pour chaque d dans RQ(nul, "select o.sch || '.' || o.nom as nom, d.message from diagnostics d left join objets o on o.id = d.objet_id " + ;
                             "where d.niveau = 'critique' order by d.module limit 8", nul)
    inserer(md, "- ⬤ " + sisinon(d.nom = nul, "", "**" + d.nom + "** — ") + MDCELL(d.message))
  suivant
retourner joindre(md, car(10))

&&
&& Cartographie (module 2) : globale, serveur, base, schéma, objet
&&

procedure CONSTRUIRE_CARTO(page)
  globale carto
  carto = {niveau = nul, suivre = vrai, cible = nul, ids = {}}
  locale haut = page:ajouter(ui.rangee())
  haut.marge = 2
  haut.ancrage = "haut"
  carto.vue = haut:ajouter(ui.combo("Vue globale", "Vue serveur", "Vue base", "Vue schéma", "Vue objet"))
  carto.vue.largeurfixe = 140
  carto.vue:selectionner(1)
  carto.vue.surselection = @CARTO_VUE
  && options sur une seule ligne : une case par option
  carto.opt = {}
  pour chaque lib dans {"Tables", "Vues", "Code", "Profondeur 2"}
    locale cc = haut:ajouter(ui.cases(lib))
    cc:cocher(1, lib <> "Profondeur 2")
    cc.surchangement = @CARTO_REFAIRE
    inserer(carto.opt, cc)
  suivant
  OUTIL(haut, "Disposer", @CARTO_DISPOSER, "Disposition automatique en couches")
  OUTIL(haut, "Ajuster", @CARTO_AJUSTER, "Tout le graphe dans la vue")
  OUTIL(haut, "−", @CARTO_ZOOM_MOINS, "Zoom arrière (molette)")
  OUTIL(haut, "+", @CARTO_ZOOM_PLUS, "Zoom avant (molette)")
  OUTIL(haut, "⧉ Fenêtre", @CARTO_FENETRE, "Ouvrir cette cartographie dans une nouvelle fenêtre (second écran)")
  carto.resume = haut:ajouter(ui.etiquette(""))
  carto.resume.poids = 1
  carto.resume.couleur = "#9CA3AF"
  carto.dia = page:ajouter(ui.diagramme{modifiable = faux, direction = "droite"})
  carto.dia.ancrage = "centre"
  carto.dia.surselection = @CARTO_CHOIX
  carto.dia.surdoubleclic = @CARTO_DOUBLE
retourner

fonction CARTO_OPTION(i)
retourner carto.opt[i]:coche(1)

procedure CARTO_AJUSTER(ev)
  carto.dia:ajuster(35)
retourner

procedure CARTO_DISPOSER(ev)
  carto.dia:disposer()
  carto.dia:ajuster(35)
retourner

procedure CARTO_ZOOM_PLUS(ev)
  carto.dia:zoom(1.25)
retourner

procedure CARTO_ZOOM_MOINS(ev)
  carto.dia:zoom(0.8)
retourner

procedure CARTO_VUE(ev)
  locale i = carto.vue:selection()
  faire cas
  cas i = 1
    CARTO_GLOBALE()
  cas i = 5 et courant <> nul
    CARTO_OBJET(courant.id)
  cas courant <> nul
    locale niveaux = {nul, {genre = "SERVEUR", serveur = courant.serveur}, {genre = "BASE", serveur = courant.serveur, base = courant.base}, ;
                      {genre = "SCHEMA", serveur = courant.serveur, base = courant.base, sch = courant.sch}}
    CARTO_NIVEAU(niveaux[i])
  fincas
retourner

procedure CARTO_REFAIRE(ev)
  si carto.niveau <> nul
    CARTO_NIVEAU(carto.niveau)
  finsi
retourner

procedure CARTO_NIVEAU(nd)
  && nd : {genre = SERVEUR | BASE | SCHEMA | OBJET, …}
  si nd = nul
    CARTO_GLOBALE()
    retourner
  finsi
  vues.valeur = INDEX_VUE("Cartographie")
  faire cas
  cas nd.genre = "SERVEUR"
    CARTO_SERVEUR(nd.serveur)
  cas nd.genre = "BASE"
    CARTO_BASE(nd.serveur, nd.base)
  cas nd.genre = "SCHEMA"
    CARTO_SCHEMA(nd.serveur, nd.base, nd.sch)
  cas nd.genre = "OBJET"
    CARTO_OBJET(nd.id)
  fincas
retourner

procedure RECENTRER(ev)
  si courant <> nul
    vues.valeur = INDEX_VUE("Cartographie")
    CARTO_OBJET(courant.id)
  finsi
retourner

procedure CARTO_GLOBALE
  carto.niveau = {genre = "GLOBAL"}
  carto.vue:selectionner(1)
  locale d = carto.dia
  d:vider()
  carto.ids = {}
  locale srvs = RQ(nul, "select serveur, base, count(*) as n, sum(case when genre = 'TABLE' then 1 else 0 end) as t, " + ;
                        "sum(case when genre in ('PROCEDURE', 'FONCTION', 'VUE', 'DECLENCHEUR') then 1 else 0 end) as c " + ;
                        "from objets where base <> '' and genre <> 'JOB' group by serveur, base order by serveur, base", nul)
  locale parsrv = {}
  pour chaque r dans srvs
    si parsrv[r.serveur] = nul
      parsrv[r.serveur] = {}
    finsi
    inserer(parsrv[r.serveur], {texte = "🗄 " + r.base, detail = r.t + " tables · " + r.c + " modules"})
  suivant
  pour chaque k, lignes dans parsrv
    locale nj = RV(nul, "select count(*) from objets where serveur = ? and genre = 'JOB'", {k})
    d:noeud{id = "S:" + k, titre = "🖥 " + k, soustitre = sisinon(nj > 0, nj + " jobs SQL Agent", "serveur"), lignes = lignes, ;
            couleur = "#0EA5E9"}
  suivant
  && serveurs connus seulement par un serveur lié
  pour chaque r dans RQ(nul, "select distinct cible from objets where genre = 'SERVEUR_LIE' and cible not in (select serveur from objets)", nul)
    d:noeud{id = "S:" + r.cible, titre = "🖥 " + r.cible, soustitre = "non analysé", lignes = {}, couleur = "#6B7280"}
  suivant
  && liens inter-serveurs
  locale nl = 0
  pour chaque r dans RQ(nul, "select a.serveur as s1, coalesce(b.serveur, split_part(d.vers_nom, '.', 1)) as s2, count(*) as n, " + ;
                             "string_agg(distinct d.nature, ', ') as natures from dependances d join objets a on a.id = d.de_id " + ;
                             "left join objets b on b.id = d.vers_id where d.interserveur group by all", nul)
    si r.s1 <> r.s2
      nl += 1
      d:lien{de = "S:" + r.s1, a = "S:" + r.s2, libelle = r.n + " · " + r.natures, couleur = "#F97316", epaisseur = min(6, 1 + r.n / 2), fleche = vrai}
    finsi
  suivant
  pour chaque r dans RQ(nul, "select serveur, nom, cible from objets where genre = 'SERVEUR_LIE'", nul)
    d:lien{id = "LS:" + r.serveur + ">" + r.nom, de = "S:" + r.serveur, a = "S:" + r.cible, libelle = "⇄ " + r.nom, pointille = vrai, couleur = "#94A3B8", fleche = vrai}
  suivant
  d:disposer("droite")
  d:ajuster(40)
  carto.resume.libelle = "Vue globale : " + #RQ(nul, "select distinct serveur from objets", nul) + " serveurs · liens inter-serveurs en orange, serveurs liés en pointillé · double-clic : descendre"
retourner

procedure CARTO_SERVEUR(serveur)
  carto.niveau = {genre = "SERVEUR", serveur = serveur}
  carto.vue:selectionner(2)
  locale d = carto.dia
  d:vider()
  pour chaque r dans RQ(nul, "select base, sch, count(*) as n from objets where serveur = ? and base <> '' and genre in " + ;
                             "('TABLE', 'VUE', 'PROCEDURE', 'FONCTION', 'DECLENCHEUR', 'SYNONYME') group by base, sch order by base, sch", {serveur})
    locale id = "B:" + serveur + "|" + r.base
    si carto.ids[id] = nul
      carto.ids[id] = {}
    finsi
    inserer(carto.ids[id], {texte = r.sch, detail = r.n + " objets"})
  suivant
  pour chaque k, lignes dans carto.ids
    si commencepar(k, "B:" + serveur + "|")
      d:noeud{id = k, titre = "🗄 " + decouper(k, "|")[2], soustitre = serveur, lignes = lignes, couleur = "#2563EB"}
    finsi
  suivant
  && dépendances entre bases (et vers d'autres serveurs)
  pour chaque r dans RQ(nul, "select a.base as b1, coalesce(b.serveur, '?') as s2, coalesce(b.base, split_part(d.vers_nom, '.', 2)) as b2, count(*) as n, " + ;
                             "string_agg(distinct d.nature, ', ') as natures from dependances d join objets a on a.id = d.de_id " + ;
                             "left join objets b on b.id = d.vers_id where a.serveur = ? and (d.interbase or d.interserveur) group by all", {serveur})
    locale dst = "B:" + r.s2 + "|" + r.b2
    si r.s2 <> serveur
      d:noeud{id = dst, titre = "🗄 " + r.b2, soustitre = "🖥 " + r.s2 + " (autre serveur)", lignes = {}, couleur = "#6B7280"}
    finsi
    d:lien{de = "B:" + serveur + "|" + r.b1, a = dst, libelle = r.n + " · " + r.natures, ;
           couleur = sisinon(r.s2 <> serveur, "#F97316", "#EF4444"), pointille = r.s2 <> serveur, epaisseur = min(6, 1 + r.n / 3), fleche = vrai}
  suivant
  d:disposer("droite")
  d:ajuster(40)
  carto.resume.libelle = "Serveur " + serveur + " : bases et schémas · liens inter-bases (rouge) et inter-serveurs (orange)"
retourner

procedure CARTO_BASE(serveur, base)
  carto.niveau = {genre = "BASE", serveur = serveur, base = base}
  carto.vue:selectionner(3)
  locale d = carto.dia
  d:vider()
  pour chaque r dans RQ(nul, "select sch, genre, count(*) as n from objets where serveur = ? and base = ? and genre in " + ;
                             "('TABLE', 'VUE', 'PROCEDURE', 'FONCTION', 'DECLENCHEUR', 'SYNONYME', 'SEQUENCE', 'TYPE') group by sch, genre order by sch, genre", ;
                             {serveur, base})
    locale id = "C:" + serveur + "|" + base + "|" + r.sch
    d:noeud{id = id, titre = r.sch, soustitre = "schéma de " + base, couleur = "#7C3AED"}
  suivant
  && contenu des schémas
  locale contenu = {}
  pour chaque r dans RQ(nul, "select sch, genre, count(*) as n from objets where serveur = ? and base = ? and genre in " + ;
                             "('TABLE', 'VUE', 'PROCEDURE', 'FONCTION', 'DECLENCHEUR', 'SYNONYME', 'SEQUENCE', 'TYPE') group by sch, genre order by sch, genre", ;
                             {serveur, base})
    si contenu[r.sch] = nul
      contenu[r.sch] = {}
    finsi
    inserer(contenu[r.sch], {texte = ICONE_GENRE(r.genre) + " " + LIBELLE_GENRE(r.genre), detail = chaine(r.n)})
  suivant
  pour chaque k, l dans contenu
    d:noeud{id = "C:" + serveur + "|" + base + "|" + k, titre = k, soustitre = "schéma de " + base, lignes = l, couleur = "#7C3AED"}
  suivant
  pour chaque r dans RQ(nul, "select a.sch as s1, coalesce(b.serveur, '') as srv2, coalesce(b.base, '') as b2, coalesce(b.sch, split_part(d.vers_nom, '.', 3)) as s2, " + ;
                             "count(*) as n from dependances d join objets a on a.id = d.de_id left join objets b on b.id = d.vers_id " + ;
                             "where a.serveur = ? and a.base = ? and (b.sch is null or b.sch <> a.sch or b.base <> a.base) group by all", {serveur, base})
    locale dst = "C:" + sisinon(r.srv2 = "", serveur, r.srv2) + "|" + sisinon(r.b2 = "", base, r.b2) + "|" + r.s2
    si r.b2 <> "" et (r.b2 <> base ou r.srv2 <> serveur)
      d:noeud{id = dst, titre = r.b2 + "." + r.s2, soustitre = sisinon(r.srv2 <> serveur, "🖥 " + r.srv2, "autre base"), couleur = "#6B7280"}
    finsi
    d:lien{de = "C:" + serveur + "|" + base + "|" + r.s1, a = dst, libelle = chaine(r.n), fleche = vrai, ;
           couleur = sisinon(r.b2 <> base et r.b2 <> "", "#EF4444", "#94A3B8"), pointille = r.b2 <> base et r.b2 <> ""}
  suivant
  d:disposer("droite")
  d:ajuster(40)
  carto.resume.libelle = "Base " + serveur + " › " + base + " : schémas et dépendances"
retourner

fonction COULEUR_NATURE(n)
  faire cas
  cas n = "SELECT"
    retourner "#3B82F6"
  cas n = "INSERT" ou n = "MERGE"
    retourner "#22C55E"
  cas n = "UPDATE"
    retourner "#F59E0B"
  cas n = "DELETE"
    retourner "#EF4444"
  cas n = "EXEC" ou n = "APPEL"
    retourner "#A855F7"
  cas n = "FK"
    retourner "#64748B"
  cas n = "OPENQUERY" ou n = "SYNONYME"
    retourner "#F97316"
  fincas
retourner "#94A3B8"

fonction GENRES_CARTO()
  locale g = {}
  si CARTO_OPTION(1)
    inserer(g, "'TABLE'")
  finsi
  si CARTO_OPTION(2)
    inserer(g, "'VUE'")
  finsi
  si CARTO_OPTION(3)
    inserer(g, "'PROCEDURE'")
    inserer(g, "'FONCTION'")
    inserer(g, "'DECLENCHEUR'")
    inserer(g, "'JOB'")
    inserer(g, "'SYNONYME'")
    inserer(g, "'SERVEUR_LIE'")
  finsi
  si #g = 0
    inserer(g, "'TABLE'")
  finsi
retourner "(" + joindre(g, ", ") + ")"

procedure NOEUD_OBJET(d, o, centre)
  locale lignes = {}
  locale meta = ""
  si o.genre = "TABLE" ou o.genre = "VUE"
    pour chaque c dans RQ(nul, "select nom, type_sql, pk, fk_vers from colonnes where objet_id = ? order by ordre limit 12", {o.id})
      inserer(lignes, {texte = c.nom, detail = c.type_sql, marque = sisinon(c.pk, "PK", sisinon(c.fk_vers = nul, "", "FK"))})
    suivant
    meta = sisinon(o.lignes = nul, "", NB(o.lignes) + " lignes")
  finsi
  d:noeud{id = "O:" + o.id, titre = ICONE_GENRE(o.genre) + " " + o.nom, ;
          soustitre = o.base + "." + o.sch + sisinon(meta = "", "", " · " + meta), lignes = lignes, ;
          couleur = sisinon(centre, "#F59E0B", COULEUR_GENRE(o.genre)), forme = sisinon(#lignes > 0, "table", "boite"), ;
          pastille = sisinon(o.classe = nul ou o.classe = "", "", sisinon("Critique" $ o.classe, "◆", "") + sisinon("Sensible" $ o.classe, "🔒", ""))}
retourner

procedure CARTO_SCHEMA(serveur, base, sch)
  carto.niveau = {genre = "SCHEMA", serveur = serveur, base = base, sch = sch}
  carto.vue:selectionner(4)
  locale d = carto.dia
  d:vider()
  locale objs = RQ(nul, "select o.id, o.nom, o.genre, o.base, o.sch, o.lignes, m.classe from objets o left join metriques m on m.objet_id = o.id " + ;
                        "where o.serveur = ? and o.base = ? and o.sch = ? and o.genre in " + GENRES_CARTO() + " order by o.genre, o.nom limit 150", ;
                        {serveur, base, sch})
  locale ids = {}
  pour chaque o dans objs
    o.serveur = serveur
    NOEUD_OBJET(d, o, faux)
    inserer(ids, o.id)
  suivant
  si #ids > 0
    pour chaque r dans RQ(nul, "select de_id, vers_id, string_agg(distinct nature, ', ') as natures, bool_or(interbase) as ib from dependances " + ;
                               "where list_contains(string_split(?, ',')::integer[], de_id) and list_contains(string_split(?, ',')::integer[], vers_id) " + ;
                               "and de_id <> vers_id group by all", {joindre(ids, ","), joindre(ids, ",")})
      d:lien{de = "O:" + r.de_id, a = "O:" + r.vers_id, libelle = r.natures, fleche = vrai, couleur = COULEUR_NATURE(decouper(r.natures, ",")[1])}
    suivant
  finsi
  d:disposer("droite")
  d:ajuster(35)
  carto.resume.libelle = "Schéma " + base + "." + sch + " : " + #objs + " objets · couleur des liens : lecture bleu, écriture vert/orange, suppression rouge, appel violet"
retourner

procedure CARTO_OBJET(id)
  locale o = OBJET(id)
  si o = nul
    retourner
  finsi
  carto.niveau = {genre = "OBJET", id = id}
  carto.vue:selectionner(5)
  locale d = carto.dia
  d:vider()
  locale cl = RV(nul, "select classe from metriques where objet_id = ?", {id})
  o.classe = cl
  NOEUD_OBJET(d, o, vrai)
  locale vus = {}
  vus[chaine(id)] = vrai
  locale frontiere = {id}
  locale prof = sisinon(CARTO_OPTION(4), 2, 1)
  locale nliens = 0
  pour niveau = 1 a prof
    locale suivante = {}
    pour chaque fid dans frontiere
      pour chaque r dans RQ(nul, "select d.de_id, d.vers_id, string_agg(distinct d.nature, ', ') as natures, bool_or(d.interbase) as ib, " + ;
                                 "bool_or(d.interserveur) as isv, max(d.frequence) as f from dependances d where (d.de_id = ? or d.vers_id = ?) " + ;
                                 "and d.vers_id is not null and d.de_id <> d.vers_id group by all limit 80", {fid, fid})
        pour chaque autre dans {r.de_id, r.vers_id}
          si vus[chaine(autre)] = nul
            locale x = RQ(nul, "select o.*, m.classe from objets o left join metriques m on m.objet_id = o.id where o.id = ? and o.genre in " + GENRES_CARTO(), {autre})
            si #x > 0
              vus[chaine(autre)] = vrai
              NOEUD_OBJET(d, x[1], faux)
              inserer(suivante, autre)
            finsi
          finsi
        suivant
        si vus[chaine(r.de_id)] <> nul et vus[chaine(r.vers_id)] <> nul
          nliens += 1
          d:lien{de = "O:" + r.de_id, a = "O:" + r.vers_id, libelle = r.natures + sisinon(r.f = nul, "", " · " + NB(r.f) + "×"), fleche = vrai, ;
                 couleur = COULEUR_NATURE(decouper(r.natures, ",")[1]), pointille = r.ib ou r.isv, ;
                 epaisseur = sisinon(r.f = nul, 1.5, min(5, 1 + log(1 + r.f) / 3))}
        finsi
      suivant
    suivant
    frontiere = suivante
  suivant
  d:disposer("droite")
  d:ajuster(45)
  d:selectionner("O:" + id)
  carto.resume.libelle = o.nom + " : " + nliens + " relations (pointillé : inter-base ou inter-serveur ; épaisseur : fréquence)"
retourner

procedure CARTO_CHOIX(ev)
  locale t = ev.texte
  si t = nul ou t = ""
    retourner
  finsi
  si commencepar(t, "O:")
    locale id = nombre(souschaine(t, 3))
    && sans recentrer la carte : l'objet devient courant (propriétés, fil d'Ariane)
    locale s = carto.suivre
    carto.suivre = faux
    ALLER_OBJET(id, "carto")
    carto.suivre = s
  sinonsi commencepar(t, "S:")
    FICHE_CONTENEUR({genre = "SERVEUR", serveur = souschaine(t, 3)})
  sinonsi commencepar(t, "B:")
    locale p = decouper(souschaine(t, 3), "|")
    FICHE_CONTENEUR({genre = "BASE", serveur = p[1], base = p[2]})
  sinonsi commencepar(t, "C:")
    locale p2 = decouper(souschaine(t, 3), "|")
    FICHE_CONTENEUR({genre = "SCHEMA", serveur = p2[1], base = p2[2], sch = p2[3]})
  finsi
retourner

procedure CARTO_DOUBLE(ev)
  locale sel = carto.dia:selection()
  si sel = nul ou sel.genre <> "noeud"
    retourner
  finsi
  locale t = sel.id
  faire cas
  cas commencepar(t, "S:")
    CARTO_SERVEUR(souschaine(t, 3))
  cas commencepar(t, "B:")
    locale p = decouper(souschaine(t, 3), "|")
    CARTO_BASE(p[1], p[2])
  cas commencepar(t, "C:")
    locale p2 = decouper(souschaine(t, 3), "|")
    CARTO_SCHEMA(p2[1], p2[2], p2[3])
  cas commencepar(t, "O:")
    CARTO_OBJET(nombre(souschaine(t, 3)))
  fincas
retourner

procedure CARTO_FENETRE(ev)
  && une cartographie indépendante dans sa fenêtre (écrans multiples)
  locale w = ui.fenetre{titre = "Atlas SQL — Cartographie " + sisinon(courant = nul, "globale", courant.nom), largeur = 1100, hauteur = 760, ;
                        disposition = "bordure", sombre = reglages.sombre, densite = "compacte"}
  locale d2 = w:ajouter(ui.diagramme{modifiable = faux, direction = "droite"})
  d2.ancrage = "centre"
  && copie des nœuds et des liens de la carte affichée
  pour chaque n dans carto.dia:noeuds()
    d2:noeud{id = n.id, titre = n.titre, x = n.x, y = n.y}
  suivant
  pour chaque l dans carto.dia:liens()
    d2:lien{de = l.de, a = l.a, libelle = l.libelle, fleche = vrai}
  suivant
  d2:ajuster(35)
retourner

&&
&& Dépendances (module 3)
&&

procedure CONSTRUIRE_DEPENDANCES(page)
  globale dep
  dep = {}
  locale haut = page:ajouter(ui.rangee())
  haut.marge = 2
  haut.ancrage = "haut"
  dep.titre = haut:ajouter(ui.etiquette("Sélectionnez un objet"))
  dep.titre.largeurfixe = 360
  dep.question = haut:ajouter(ui.combo("Toutes les relations", "Qui lit ?", "Qui écrit ?", "Qui supprime ?", "Qui met à jour ?", ;
                                       "Qui insère ?", "Qui appelle ?"))
  dep.question:selectionner(1)
  dep.question.surselection = @DEP_QUESTION
  dep.question.largeurfixe = 180
  OUTIL(haut, "Impact transitif", @IMPACT_COURANT, "Tous les objets touchés si celui-ci change (dépendances en cascade)")
  dep.resume = haut:ajouter(ui.etiquette(""))
  dep.resume.poids = 1
  dep.resume.couleur = "#9CA3AF"
  locale s1 = page:ajouter(ui.separateur{vertical = vrai, position = 0.5})
  s1.ancrage = "centre"
  locale g = s1:ajouter(ui.colonne())
  locale lg = g:ajouter(ui.etiquette("➜ UTILISE (ce dont l'objet dépend)"))
  lg.couleur = "#60A5FA"
  dep.sortant = GRILLE(g, COLONNES_DEP())
  dep.sortant.poids = 1
  dep.sortant.surdoubleclic = @DEP_ALLER_SORTANT
  locale dr = s1:ajouter(ui.separateur{vertical = faux, position = 0.55})
  locale dd = dr:ajouter(ui.colonne())
  locale ld = dd:ajouter(ui.etiquette("⬅ UTILISÉ PAR (qui dépend de l'objet)"))
  ld.couleur = "#34D399"
  dep.entrant = GRILLE(dd, COLONNES_DEP())
  dep.entrant.poids = 1
  dep.entrant.surdoubleclic = @DEP_ALLER_ENTRANT
  locale di = dr:ajouter(ui.colonne())
  dep.limpact = di:ajouter(ui.etiquette("IMPACT TRANSITIF"))
  dep.limpact.couleur = "#F59E0B"
  dep.impact = GRILLE(di, {{"niveau", "Niv.", 40, "nombre"}, {"objet", "Objet", 300}, {"genre", "Genre", 100}, {"base", "Serveur › base", 180}})
  dep.impact.poids = 1
  dep.impact.surdoubleclic = @DEP_ALLER_IMPACT
  dep.ids_s = {}
  dep.ids_e = {}
  dep.ids_i = {}
retourner

fonction COLONNES_DEP()
retourner {{"nature", "Nature", 80}, {"objet", "Objet", 270}, {"genre", "Genre", 90}, {"frequence", "Fréquence", 80, "nombre"}, ;
           {"vmoy", "Vol. moyen", 80, "nombre"}, {"vmax", "Vol. max", 80, "nombre"}, {"cx", "Complexité", 70, "nombre"}, ;
           {"portee", "Portée", 90}, {"origine", "Origine", 90}, {"ligne", "Ligne", 50, "nombre"}}

fonction QUESTION_DEP()
retourner {"", "lit", "ecrit", "supprime", "metajour", "insere", "appelle"}[max(1, dep.question:selection())]

procedure DEP_QUESTION(ev)
  REMPLIR_DEPENDANCES()
retourner

procedure REMPLIR_DEP_GRILLE(g, lignes, ids)
  g:vider()
  pour chaque r dans lignes
    g:ajouterligne(r.nature, sisinon(r.nom = nul, "?", r.nom), LIBELLE_GENRE(r.genre), r.frequence, ;
                   sisinon(r.volume_moy = nul, nul, arrondi(r.volume_moy)), sisinon(r.volume_max = nul, nul, arrondi(r.volume_max)), ;
                   r.complexite, sisinon(r.interserveur, "serveurs", sisinon(r.interbase, "bases", "locale")), r.origine, r.ligne)
    inserer(ids, r.id)
  suivant
retourner

procedure REMPLIR_DEPENDANCES
  si courant = nul
    retourner
  finsi
  dep.titre.libelle = ICONE_GENRE(courant.genre) + " " + courant.base + "." + courant.sch + "." + courant.nom
  locale q = QUESTION_DEP()
  dep.ids_s = {}
  dep.ids_e = {}
  locale ls = RELATIONS(courant.id, "sortant", q)
  locale le = RELATIONS(courant.id, "entrant", q)
  REMPLIR_DEP_GRILLE(dep.sortant, ls, dep.ids_s)
  REMPLIR_DEP_GRILLE(dep.entrant, le, dep.ids_e)
  locale txt = #ls + " relation(s) sortante(s), " + #le + " entrante(s)"
  si q <> ""
    txt = txt + " — question : " + dep.question.valeur
  finsi
  dep.resume.libelle = txt
retourner

procedure DEP_ALLER(g, ids)
  locale i = g:selection()
  si i <> nul et i >= 1 et i <= #ids et ids[i] <> nul
    ALLER_OBJET(ids[i], "dependances")
  finsi
retourner

procedure DEP_ALLER_SORTANT(ev)
  DEP_ALLER(dep.sortant, dep.ids_s)
retourner

procedure DEP_ALLER_ENTRANT(ev)
  DEP_ALLER(dep.entrant, dep.ids_e)
retourner

procedure DEP_ALLER_IMPACT(ev)
  DEP_ALLER(dep.impact, dep.ids_i)
retourner

procedure IMPACT_COURANT(ev)
  si courant = nul
    STATUT("Sélectionnez d'abord un objet.")
    retourner
  finsi
  vues.valeur = INDEX_VUE("Dépendances")
  REMPLIR_DEPENDANCES()
  locale l = IMPACT_TRANSITIF(courant.id, 6)
  dep.impact:vider()
  dep.ids_i = {}
  locale parg = {}
  pour chaque r dans l
    dep.impact:ajouterligne(r.niveau, r.sch + "." + r.nom, LIBELLE_GENRE(r.genre), r.serveur + " › " + r.base)
    inserer(dep.ids_i, r.id)
    parg[r.genre] = sisinon(parg[r.genre] = nul, 0, parg[r.genre]) + 1
  suivant
  locale t = {}
  pour chaque k, v dans parg
    inserer(t, v + " " + minuscule(LIBELLE_GENRE(k)) + sisinon(v > 1, "s", ""))
  suivant
  dep.limpact.libelle = "IMPACT TRANSITIF de " + courant.nom + " : " + sisinon(#t = 0, "aucun objet", joindre(t, ", "))
retourner

&&
&& Dictionnaire (module 4)
&&

procedure CONSTRUIRE_DICO(page)
  globale dico
  dico = {ids = {}}
  locale haut = page:ajouter(ui.rangee())
  haut.marge = 2
  haut.ancrage = "haut"
  dico.famille = haut:ajouter(ui.combo("Toutes les familles"))
  dico.famille.largeurfixe = 190
  dico.famille.surselection = @DICO_FILTRE
  dico.nature = haut:ajouter(ui.combo("Toutes les natures"))
  dico.nature.largeurfixe = 190
  dico.nature.surselection = @DICO_FILTRE
  dico.rgpd = haut:ajouter(ui.cases("Données personnelles seulement"))
  dico.rgpd.surchangement = @DICO_FILTRE
  dico.filtre = haut:ajouter(ui.saisie{indication = "filtrer (table, objet métier…)"})
  dico.filtre.largeurfixe = 200
  dico.filtre.surchangement = @DICO_FILTRE
  OUTIL(haut, "Exporter (Markdown)…", @DICO_EXPORTER, "Documentation complète du dictionnaire dans un fichier .md")
  dico.resume = haut:ajouter(ui.etiquette(""))
  dico.resume.poids = 1
  locale s1 = page:ajouter(ui.separateur{vertical = vrai, position = 0.46})
  s1.ancrage = "centre"
  dico.tables = GRILLE(s1, {{"base", "Serveur › base", 150}, {"table", "Table", 190}, {"objet", "Objet métier", 140}, ;
                            {"famille", "Famille", 120}, {"nature", "Nature", 140}, {"sens", "Sensibilité", 90}, ;
                            {"lignes", "Lignes", 80, "nombre"}})
  dico.tables:ajouterformat("sens", "=", "très élevée", {texte = "#FCA5A5", ligneentiere = vrai})
  dico.tables:ajouterformat("sens", "=", "élevée", {texte = "#FDBA74"})
  dico.tables.surselection = @DICO_TABLE
  dico.colonnes = GRILLE(s1, {{"colonne", "Colonne", 150}, {"description", "Description", 260}, {"type", "Type SQL", 110}, ;
                              {"metier", "Type métier", 160}, {"null", "Null", 40}, {"card", "Cardinalité", 170}, ;
                              {"sens", "Sensibilité", 90}, {"rgpd", "Catégorie RGPD", 190}, {"ex", "Exemples", 220}})
  dico.colonnes:ajouterformat("sens", "=", "très élevée", {texte = "#FCA5A5", ligneentiere = vrai})
  dico.colonnes:ajouterformat("sens", "=", "élevée", {texte = "#FDBA74", ligneentiere = vrai})
retourner

procedure REMPLIR_DICO
  dico.famille:vider()
  dico.famille:ajouter("Toutes les familles")
  pour chaque r dans RQ(nul, "select distinct famille from dico_tables order by 1", nul)
    dico.famille:ajouter(r.famille)
  suivant
  dico.famille:selectionner(1)
  dico.nature:vider()
  dico.nature:ajouter("Toutes les natures")
  pour chaque r dans RQ(nul, "select distinct nature from dico_tables order by 1", nul)
    dico.nature:ajouter(r.nature)
  suivant
  dico.nature:selectionner(1)
  DICO_FILTRE(nul)
retourner

procedure DICO_FILTRE(ev)
  locale cond = {}
  locale p = {}
  si dico.famille:selection() > 1
    inserer(cond, "d.famille = ?")
    inserer(p, dico.famille.valeur)
  finsi
  si dico.nature:selection() > 1
    inserer(cond, "d.nature = ?")
    inserer(p, dico.nature.valeur)
  finsi
  si dico.rgpd:coche(1)
    inserer(cond, "d.rgpd")
  finsi
  locale f = rogner(sisinon(dico.filtre.valeur = nul, "", dico.filtre.valeur))
  si f <> ""
    inserer(cond, "(o.nom ilike ? or d.objet_metier ilike ? or d.description ilike ?)")
    inserer(p, "%" + f + "%")
    inserer(p, "%" + f + "%")
    inserer(p, "%" + f + "%")
  finsi
  locale w = sisinon(#cond = 0, "", " where " + joindre(cond, " and "))
  dico.tables:vider()
  dico.ids = {}
  pour chaque r dans RQ(nul, "select o.id, o.serveur || ' › ' || o.base as b, o.sch || '.' || o.nom as t, d.objet_metier, d.famille, d.nature, " + ;
                             "d.sensibilite, o.lignes from dico_tables d join objets o on o.id = d.objet_id" + w + " order by o.serveur, o.base, o.sch, o.nom", p)
    dico.tables:ajouterligne(r.b, r.t, r.objet_metier, r.famille, r.nature, r.sensibilite, r.lignes)
    inserer(dico.ids, r.id)
  suivant
  dico.resume.libelle = #dico.ids + " table(s) / vue(s)"
retourner

procedure DICO_TABLE(ev)
  locale i = dico.tables:selection()
  si i = nul ou i < 1 ou i > #dico.ids
    retourner
  finsi
  locale id = dico.ids[i]
  dico.colonnes:vider()
  pour chaque r dans RQ(nul, "select c.nom, d.description, c.type_sql, d.type_metier, c.nullable, d.cardinalite, d.sensibilite, d.categorie_rgpd, c.exemples " + ;
                             "from colonnes c left join dico_colonnes d on d.objet_id = c.objet_id and d.colonne = c.nom where c.objet_id = ? order by c.ordre", {id})
    dico.colonnes:ajouterligne(r.nom, r.description, r.type_sql, r.type_metier, sisinon(r.nullable, "oui", "non"), r.cardinalite, ;
                               r.sensibilite, r.categorie_rgpd, r.exemples)
  suivant
  ALLER_OBJET(id, "dictionnaire")
retourner

procedure DICO_EXPORTER(ev)
  locale p = ui.enregistrerfichier{nom = "dictionnaire.md", filtre = "Markdown|*.md"}
  si p = nul
    retourner
  finsi
  locale md = {"# Dictionnaire de données", "", "*Généré par Atlas SQL le " + date() + ".*", ""}
  locale tcour = nul
  pour chaque r dans RQ(nul, "select o.id, o.serveur, o.base, o.sch, o.nom, o.lignes, d.objet_metier, d.famille, d.nature, d.sensibilite, d.description " + ;
                             "from dico_tables d join objets o on o.id = d.objet_id order by o.serveur, o.base, o.sch, o.nom", nul)
    inserer(md, "## " + r.serveur + " › " + r.base + " › " + r.sch + "." + r.nom)
    inserer(md, "")
    inserer(md, r.description)
    inserer(md, "")
    inserer(md, "- Objet métier : **" + r.objet_metier + "** (" + r.famille + ") · nature : " + r.nature + " · sensibilité : " + r.sensibilite)
    inserer(md, "")
    inserer(md, "| Colonne | Description | Type SQL | Type métier | Null | Cardinalité | Sensibilité |")
    inserer(md, "|---|---|---|---|---|---|---|")
    pour chaque c dans RQ(nul, "select c.nom, d.description, c.type_sql, d.type_metier, c.nullable, d.cardinalite, d.sensibilite, d.categorie_rgpd " + ;
                               "from colonnes c left join dico_colonnes d on d.objet_id = c.objet_id and d.colonne = c.nom where c.objet_id = ? order by c.ordre", {r.id})
      inserer(md, "| " + c.nom + " | " + MDCELL(c.description) + " | " + MDCELL(c.type_sql) + " | " + MDCELL(c.type_metier) + " | " + ;
                  sisinon(c.nullable, "oui", "non") + " | " + MDCELL(c.cardinalite) + " | " + MDCELL(c.sensibilite) + ;
                  sisinon(c.categorie_rgpd = nul ou c.categorie_rgpd = "", "", " (" + c.categorie_rgpd + ")") + " |")
    suivant
    inserer(md, "")
  suivant
  fichier.ecrire(p, joindre(md, car(10)))
  STATUT("Dictionnaire exporté : " + p)
retourner

&&
&& Types métier (module 5)
&&

procedure CONSTRUIRE_TYPES_VUE(page)
  globale tym
  tym = {}
  locale haut = page:ajouter(ui.rangee())
  haut.marge = 2
  haut.ancrage = "haut"
  tym.resume = haut:ajouter(ui.etiquette(""))
  tym.resume.poids = 1
  OUTIL(haut, "Script des types…", @TYPES_SCRIPT, "CREATE TYPE pour chaque type métier (dans l'éditeur)")
  tym.g = GRILLE(page, {{"code", "Type métier", 220}, {"libelle", "Libellé", 200}, {"type", "Type SQL", 120}, ;
                        {"occ", "Occurrences", 80, "nombre"}, {"util", "Tables", 60, "nombre"}, {"cols", "Colonnes", 330}, ;
                        {"var", "Types SQL rencontrés", 220}})
  tym.g.ancrage = "centre"
  tym.g:ajouterformat("var", "contient", ",", {texte = "#FDBA74", ligneentiere = vrai})
retourner

procedure REMPLIR_TYPES
  tym.g:vider()
  locale n = 0
  pour chaque r dans RQ(nul, "select * from types_metier order by occurrences desc, code", nul)
    tym.g:ajouterligne(r.code, r.libelle, r.type_sql, r.occurrences, r.utilisations, r.colonnes, r.variantes)
    n += 1
  suivant
  locale inc = RV(nul, "select count(*) from types_metier where variantes like '%,%'", nul)
  tym.resume.libelle = n + " types métier réutilisables · " + inc + " avec des types SQL incohérents (orange) · " + ;
                       "exemple : CODE_CLIENT, CLIENT_CODE, CODCLI, CLI_CODE → TYPE_CODE_CLIENT"
retourner

procedure TYPES_SCRIPT(ev)
  locale l = {"-- Types métier proposés par Atlas SQL", ""}
  pour chaque r dans RQ(nul, "select code, type_sql, colonnes from types_metier order by code", nul)
    inserer(l, "-- " + r.colonnes)
    inserer(l, "CREATE TYPE dbo." + r.code + " FROM " + r.type_sql + ";")
  suivant
  NOUVEAU_SCRIPT("types_metier.sql", joindre(l, car(10)))
retourner

&&
&& Flux (module 12) : flux, Sankey, pipeline, chronologie
&&

procedure CONSTRUIRE_FLUX(page)
  globale flux
  flux = {}
  locale haut = page:ajouter(ui.rangee())
  haut.marge = 2
  haut.ancrage = "haut"
  flux.mode = haut:ajouter(ui.combo("Vue flux", "Vue Sankey (volumes)", "Vue pipeline", "Vue temporelle (jobs)"))
  flux.mode:selectionner(1)
  flux.mode.largeurfixe = 200
  flux.mode.surselection = @FLUX_MODE
  flux.base = haut:ajouter(ui.combo("Toutes les bases"))
  flux.base.largeurfixe = 160
  flux.base.surselection = @FLUX_MODE
  OUTIL(haut, "Ajuster", @FLUX_AJUSTER, "Tout dans la vue")
  flux.resume = haut:ajouter(ui.etiquette(""))
  flux.resume.poids = 1
  flux.resume.couleur = "#9CA3AF"
  flux.zone = page:ajouter(ui.colonne())
  flux.zone.ancrage = "centre"
  flux.dia = flux.zone:ajouter(ui.diagramme{modifiable = faux, direction = "droite"})
  flux.dia.poids = 1
  flux.dia.surselection = @FLUX_CHOIX
  flux.gantt = flux.zone:ajouter(ui.gantt())
  flux.gantt.poids = 1
  flux.gantt.visible = faux
retourner

procedure FLUX_AJUSTER(ev)
  flux.dia:ajuster(35)
retourner

procedure FLUX_MODE(ev)
  REMPLIR_FLUX_VUE()
retourner

procedure REMPLIR_FLUX
  flux.base:vider()
  flux.base:ajouter("Toutes les bases")
  pour chaque r dans RQ(nul, "select distinct base from objets where genre = 'TABLE' order by 1", nul)
    flux.base:ajouter(r.base)
  suivant
  flux.base:selectionner(1)
  REMPLIR_FLUX_VUE()
retourner

procedure REMPLIR_FLUX_VUE
  locale m = flux.mode:selection()
  si m = 4
    flux.dia.visible = faux
    flux.gantt.visible = vrai
    FLUX_TEMPOREL()
    retourner
  finsi
  flux.dia.visible = vrai
  flux.gantt.visible = faux
  locale d = flux.dia
  d:vider()
  locale b = sisinon(flux.base:selection() > 1, flux.base.valeur, "")
  locale lignes = FLUX(b)
  locale vmax = 1
  pour chaque r dans lignes
    vmax = max(vmax, sisinon(r.volume = nul, 0, r.volume))
  suivant
  locale vus = {}
  pour chaque r dans lignes
    pour chaque x dans {{r.src_id, r.source}, {r.dst_id, r.destination}}
      si vus[chaine(x[1])] = nul
        vus[chaine(x[1])] = vrai
        locale p = decouper(x[2], ".")
        locale dm = RV(nul, "select objet_metier from dico_tables where objet_id = ?", {x[1]})
        d:noeud{id = "O:" + x[1], titre = "▦ " + p[4], soustitre = p[1] + " › " + p[2] + sisinon(dm = nul, "", " · " + dm), ;
                couleur = sisinon(p[1] = "SRV-DWH" ou p[2] = "DWH", "#0D9488", sisinon(p[2] = "COMPTA", "#CA8A04", "#2563EB")), forme = "boite"}
      finsi
    suivant
    si m = 2
      && Sankey : épaisseur proportionnelle au volume
      d:lien{de = "O:" + r.src_id, a = "O:" + r.dst_id, libelle = r.traitement + " · " + NB(r.volume), fleche = vrai, ;
             couleur = "#38BDF8", epaisseur = 1 + 10 * sisinon(r.volume = nul, 0, r.volume) / vmax}
    sinon
      d:lien{de = "O:" + r.src_id, a = "O:" + r.dst_id, libelle = r.traitement, fleche = vrai, couleur = COULEUR_NATURE(r.nature)}
    finsi
  suivant
  d:disposer(sisinon(m = 3, "bas", "droite"))
  d:ajuster(35)
  flux.resume.libelle = #lignes + " flux table → traitement → table" + sisinon(m = 2, " · épaisseur : volume (lignes × exécutions)", "") + ;
                        sisinon(m = 3, " · pipeline : sources en haut, destinations en bas", "")
retourner

procedure FLUX_CHOIX(ev)
  si commencepar(ev.texte, "O:")
    ALLER_OBJET(nombre(souschaine(ev.texte, 3)), "flux")
  finsi
retourner

procedure FLUX_TEMPOREL
  && jobs SQL Agent : heure de début et durée moyenne de chaque étape (axe en heures)
  locale g = flux.gantt
  g:vider()
  g:horaire(vrai)
  g:largeurlibelles(260)
  locale n = 0
  pour chaque r dans RQ(nul, "select serveur, job, etape, nom_etape, heure_debut, duree_moy_s from ext_jobs order by heure_debut, serveur, job, etape", nul)
    locale h = entier(r.heure_debut / 10000) + (entier(r.heure_debut / 100) % 100) / 60 + (r.heure_debut % 100) / 3600
    n += 1
    g:ajoutertache(r.job + " · " + r.nom_etape, h, max(0.02, sisinon(r.duree_moy_s = nul, 60, r.duree_moy_s) / 3600), 1, ;
                   sisinon(r.serveur = "SRV-DWH", "#14B8A6", sisinon(r.serveur = "SRV-COMPTA", "#EAB308", "#3B82F6")), ;
                   r.serveur + " · " + DUREE_TEXTE(r.duree_moy_s))
  suivant
  flux.resume.libelle = n + " étapes de jobs SQL Agent (durée moyenne observée) : repérez les chevauchements et la chaîne nocturne"
retourner

&&
&& Duplications (module 7)
&&

procedure CONSTRUIRE_DUP(page)
  globale dupv
  dupv = {ids = {}}
  locale haut = page:ajouter(ui.rangee())
  haut.marge = 2
  haut.ancrage = "haut"
  dupv.genre = haut:ajouter(ui.combo("Tout", "Instructions identiques", "Instructions voisines", "Jointures récurrentes", "Règles dupliquées"))
  dupv.genre:selectionner(1)
  dupv.genre.surselection = @DUP_FILTRE
  dupv.genre.largeurfixe = 200
  OUTIL(haut, "Proposer le code mutualisé", @DUP_PROPOSER, "Squelette de vue / fonction pour le groupe sélectionné (dans l'éditeur)")
  dupv.resume = haut:ajouter(ui.etiquette(""))
  dupv.resume.poids = 1
  dupv.g = GRILLE(page, {{"groupe", "Groupe", 60, "nombre"}, {"genre", "Genre", 90}, {"objet", "Objet", 230}, {"ligne", "Ligne", 50, "nombre"}, ;
                         {"sim", "Similarité", 70, "nombre"}, {"extrait", "Extrait", 480}, {"prop", "Proposition", 300}})
  dupv.g.ancrage = "centre"
  dupv.g.surdoubleclic = @DUP_OUVRIR
  dupv.g:fixerrupture("groupe")
retourner

procedure REMPLIR_DUP
  DUP_FILTRE(nul)
retourner

procedure DUP_FILTRE(ev)
  locale genres = {"", "identique", "voisine", "jointure", "regle"}
  locale g = genres[max(1, dupv.genre:selection())]
  dupv.g:vider()
  dupv.ids = {}
  pour chaque r dans RQ(nul, "select u.groupe, u.genre, u.objet_id, o.sch || '.' || o.nom as nom, u.ligne, round(u.similarite * 100) as sim, " + ;
                             "u.extrait, u.proposition from duplications u join objets o on o.id = u.objet_id where ? = '' or u.genre = ? " + ;
                             "order by u.groupe, o.nom limit 2000", {g, g})
    dupv.g:ajouterligne(r.groupe, r.genre, r.nom, r.ligne, r.sim, r.extrait, r.proposition)
    inserer(dupv.ids, {id = r.objet_id, ligne = r.ligne, groupe = r.groupe, extrait = r.extrait, genre = r.genre, prop = r.proposition})
  suivant
  locale pct = RV(nul, "select valeur from meta where cle = 'dup_pct'", nul)
  locale ng = RV(nul, "select count(distinct groupe) from duplications", nul)
  locale ma = RV(nul, "select round(avg(maintenabilite)) from metriques where maintenabilite is not null", nul)
  locale mu = RV(nul, "select round(100.0 * count(distinct groupe) / greatest(count(*), 1)) from duplications", nul)
  dupv.resume.libelle = "Duplication : " + sisinon(pct = nul, "–", pct) + " % des instructions · " + ng + " groupes · indice de maintenance " + ;
                        sisinon(ma = nul, "–", ma) + "/100 · indice de mutualisation " + sisinon(mu = nul, "–", 100 - mu) + " %"
retourner

procedure DUP_OUVRIR(ev)
  locale i = dupv.g:selection()
  si i <> nul et i >= 1 et i <= #dupv.ids
    OUVRIR_CODE(dupv.ids[i].id, dupv.ids[i].ligne)
  finsi
retourner

procedure DUP_PROPOSER(ev)
  locale i = dupv.g:selection()
  si i = nul ou i < 1 ou i > #dupv.ids
    STATUT("Sélectionnez une ligne d'un groupe.")
    retourner
  finsi
  locale x = dupv.ids[i]
  locale objets_ = {}
  pour chaque r dans RQ(nul, "select distinct o.sch || '.' || o.nom as n from duplications u join objets o on o.id = u.objet_id where u.groupe = ?", {x.groupe})
    inserer(objets_, r.n)
  suivant
  locale l = {"-- Groupe " + x.groupe + " (" + x.genre + ") : " + joindre(objets_, ", "), "-- " + x.prop, ""}
  faire cas
  cas x.genre = "jointure"
    locale p = decouper(x.extrait, " ")
    inserer(l, "CREATE VIEW dbo.V_" + p[1] + "_" + p[3] + " AS")
    inserer(l, "SELECT *  -- lister les colonnes utiles")
    inserer(l, "FROM " + p[1] + " JOIN " + p[3] + " " + souschaine(x.extrait, position(" ON ", x.extrait) + 1) + ";")
  cas x.genre = "regle"
    inserer(l, "CREATE FUNCTION dbo.FN_REGLE_" + x.groupe + " (@valeur DECIMAL(15,2))")
    inserer(l, "RETURNS VARCHAR(20)")
    inserer(l, "AS")
    inserer(l, "BEGIN")
    inserer(l, "  RETURN (" + x.extrait + ");  -- remplacer les colonnes par @valeur")
    inserer(l, "END;")
  autrement
    inserer(l, "CREATE PROCEDURE dbo.SP_MUTUALISEE_" + x.groupe)
    inserer(l, "  -- paramètres : les valeurs qui varient entre les copies")
    inserer(l, "AS")
    inserer(l, "BEGIN")
    inserer(l, "  SET NOCOUNT ON;")
    inserer(l, "  " + x.extrait + ";")
    inserer(l, "END;")
  fincas
  NOUVEAU_SCRIPT("mutualisation_" + x.groupe + ".sql", joindre(l, car(10)))
retourner

&&
&& SQL dynamique (module 8)
&&

procedure CONSTRUIRE_DYN(page)
  globale dynv
  dynv = {ids = {}}
  locale s1 = page:ajouter(ui.separateur{vertical = faux, position = 0.55})
  s1.ancrage = "centre"
  dynv.g = GRILLE(s1, {{"objet", "Objet", 220}, {"ligne", "Ligne", 50, "nombre"}, {"mode", "Mode", 100}, ;
                       {"sql", "SQL final reconstitué", 520}, {"params", "Paramètres", 260}, {"types", "Types", 160}})
  dynv.g.surselection = @DYN_CHOIX
  dynv.g.surdoubleclic = @DYN_OUVRIR
  dynv.detail = s1:ajouter(ui.markdown("Sélectionnez un SQL dynamique : variantes retrouvées et valeurs observées (captures)."))
retourner

procedure REMPLIR_DYN
  dynv.g:vider()
  dynv.ids = {}
  pour chaque r dans RQ(nul, "select d.*, o.sch || '.' || o.nom as nom from sql_dynamique d join objets o on o.id = d.objet_id order by o.nom, d.ligne", nul)
    dynv.g:ajouterligne(r.nom, r.ligne, r.mode, r.sql_reconstitue, r.parametres, r.types)
    inserer(dynv.ids, r)
  suivant
retourner

procedure DYN_CHOIX(ev)
  locale i = dynv.g:selection()
  si i = nul ou i < 1 ou i > #dynv.ids
    retourner
  finsi
  locale d = dynv.ids[i]
  locale md = {"### " + d.nom + " · ligne " + d.ligne + " · " + d.mode, "", "```sql", d.sql_reconstitue, "```", ""}
  si d.parametres <> ""
    inserer(md, "**Paramètres** : " + MDCELL(d.parametres))
    inserer(md, "")
  finsi
  && valeurs observées : appels capturés de cet objet
  locale caps = RQ(nul, "select quand, parametres, duree_ms from captures where lower(objet) = lower(?) order by quand desc limit 12", {d.nom})
  si #caps > 0
    inserer(md, "**Valeurs observées** (" + #caps + " derniers appels capturés)")
    inserer(md, "")
    inserer(md, "| Quand | Paramètres | Durée |")
    inserer(md, "|---|---|---:|")
    pour chaque c dans caps
      inserer(md, "| " + gauche(chaine(c.quand), 16) + " | " + MDCELL(c.parametres) + " | " + arrondi(c.duree_ms) + " ms |")
    suivant
    inserer(md, "")
    inserer(md, "**SQL final avec les dernières valeurs**")
    inserer(md, "```sql")
    inserer(md, SQL_AVEC_VALEURS(d.sql_reconstitue, caps[1].parametres))
    inserer(md, "```")
  finsi
  locale vars = RQ(nul, "select sql, premiere, derniere, occurrences, origine from dyn_variantes where objet_id = ? order by derniere desc", {d.objet_id})
  si #vars > 0
    inserer(md, "")
    inserer(md, "**Historique des variantes** (" + #vars + ")")
    pour chaque v dans vars
      inserer(md, "- " + gauche(chaine(v.premiere), 16) + " → " + gauche(chaine(v.derniere), 16) + " · " + v.occurrences + "× · " + v.origine + " : " + ;
                  MDCODE(COURT(v.sql, 140)))
    suivant
  finsi
  dynv.detail.valeur = MD(joindre(md, car(10)))
retourner

fonction SQL_AVEC_VALEURS(sql, params_json)
  && remplace {@Param} par la valeur observée du paramètre de même nom
  locale r = sql
  essayer
    locale p = dejson(params_json)
    pour chaque k, v dans p
      locale val = sisinon(v = nul, "NULL", sisinon(type(v) = "nombre", chaine(v), "'" + remplacertexte(chaine(v), "'", "''") + "'"))
      pour chaque forme dans {"{@" + k + "}", "{@" + minuscule(k) + "}", "{QUOTENAME(@" + k + ")}", "{CAST(@" + k + "ASVARCHAR(4))}"}
        r = remplacertexte(r, forme, val)
      suivant
      && formes mixtes (casse des noms de paramètres)
      r = REMPLACER_CASSE(r, "{@" + k + "}", val)
      r = REMPLACER_CASSE(r, "{QUOTENAME(@" + k + ")}", "[" + chaine(v) + "]")
    suivant
  capturer e
  finessayer
retourner r

fonction REMPLACER_CASSE(texte_, motif, par)
  && remplacement insensible à la casse (petits textes)
  locale u = majuscule(texte_)
  locale m = majuscule(motif)
  locale p = position(m, u)
  tantque p > 0
    texte_ = gauche(texte_, p - 1) + par + souschaine(texte_, p + #motif)
    u = majuscule(texte_)
    p = position(m, u)
  fintantque
retourner texte_

procedure DYN_OUVRIR(ev)
  locale i = dynv.g:selection()
  si i <> nul et i >= 1 et i <= #dynv.ids
    OUVRIR_CODE(dynv.ids[i].objet_id, dynv.ids[i].ligne)
  finsi
retourner

&&
&& Performances (module 10)
&&

procedure CONSTRUIRE_PERF(page)
  globale perf
  perf = {ids = {}, recos = {}}
  locale haut = page:ajouter(ui.rangee())
  haut.marge = 2
  haut.ancrage = "haut"
  perf.resume = haut:ajouter(ui.etiquette(""))
  perf.resume.poids = 1
  OUTIL(haut, "Script des corrections", @PERF_SCRIPT, "Toutes les corrections proposées (CREATE INDEX…) dans un script")
  locale s1 = page:ajouter(ui.separateur{vertical = faux, position = 0.5})
  s1.ancrage = "centre"
  perf.g = GRILLE(s1, {{"objet", "Requête / objet", 230}, {"ex", "Exécutions", 80, "nombre"}, {"cout", "Coût estimé", 80, "nombre"}, ;
                       {"lignes", "Lignes", 80, "nombre"}, {"temps", "Temps (ms)", 80, "nombre"}, {"cpu", "CPU (ms)", 80, "nombre"}, ;
                       {"mem", "Mémoire (Ko)", 90, "nombre"}, {"io", "Lectures (E/S)", 100, "nombre"}, {"ops", "Opérateurs du plan", 300}})
  perf.g:ajouterformat("ops", "contient", "Scan", {texte = "#FDBA74"})
  perf.g.surdoubleclic = @PERF_OBJET
  perf.r = GRILLE(s1, {{"niveau", "Niveau", 110}, {"regle", "Règle", 150}, {"objet", "Objet", 200}, {"message", "Constat", 430}, ;
                       {"suggestion", "Optimisation proposée", 380}, {"correctif", "Correctif SQL", 380}})
  FORMATS_NIVEAU(perf.r, "niveau")
  perf.r.surdoubleclic = @PERF_RECO
retourner

procedure REMPLIR_PERF
  perf.g:vider()
  perf.ids = {}
  pour chaque r dans RQ(nul, "select q.objet_id, coalesce(o.sch || '.' || o.nom, left(q.texte, 60)) as nom, sum(q.executions) as ex, max(q.cout) as cout, " + ;
                             "sum(q.lignes) / greatest(sum(q.executions), 1) as lignes, sum(q.duree_ms) / greatest(sum(q.executions), 1) as temps, " + ;
                             "sum(q.cpu_ms) / greatest(sum(q.executions), 1) as cpu, max(q.memoire_ko) as mem, " + ;
                             "sum(q.lectures) / greatest(sum(q.executions), 1) as io, max(q.operateurs) as ops " + ;
                             "from stats_requetes q left join objets o on o.id = q.objet_id group by all order by sum(q.cpu_ms) desc limit 300", nul)
    perf.g:ajouterligne(r.nom, r.ex, arrondi(sisinon(r.cout = nul, 0, r.cout), 2), arrondi(r.lignes), arrondi(r.temps, 1), ;
                        arrondi(r.cpu, 1), r.mem, arrondi(r.io), r.ops)
    inserer(perf.ids, r.objet_id)
  suivant
  perf.r:vider()
  perf.recos = {}
  pour chaque r dans RQ(nul, "select d.*, o.sch || '.' || o.nom as nom from diagnostics d left join objets o on o.id = d.objet_id " + ;
                             "where d.module = 'performances' order by case d.niveau when 'critique' then 1 when 'important' then 2 else 3 end, d.regle", nul)
    perf.r:ajouterligne(NIVEAU_TEXTE(r.niveau), r.regle, r.nom, r.message, r.suggestion, r.correctif)
    inserer(perf.recos, r)
  suivant
  perf.resume.libelle = #perf.ids + " requêtes / objets mesurés (statistiques SQL Server, plans en cache) · " + #perf.recos + " recommandations"
retourner

procedure PERF_OBJET(ev)
  locale i = perf.g:selection()
  si i <> nul et i >= 1 et i <= #perf.ids et perf.ids[i] <> nul
    ALLER_OBJET(perf.ids[i], "performances")
  finsi
retourner

procedure PERF_RECO(ev)
  locale i = perf.r:selection()
  si i = nul ou i < 1 ou i > #perf.recos
    retourner
  finsi
  locale r = perf.recos[i]
  si r.correctif <> nul et r.correctif <> ""
    NOUVEAU_SCRIPT("correctif.sql", "-- " + r.message + car(10) + "-- " + r.suggestion + car(10) + r.correctif + car(10))
  sinonsi r.objet_id <> nul
    OUVRIR_CODE(r.objet_id, r.ligne)
  finsi
retourner

procedure PERF_SCRIPT(ev)
  locale l = {"-- Corrections proposées par Atlas SQL (à vérifier avant exécution)", ""}
  pour chaque r dans RQ(nul, "select message, correctif from diagnostics where correctif is not null and correctif <> '' order by module", nul)
    inserer(l, "-- " + r.message)
    inserer(l, r.correctif)
    inserer(l, "")
  suivant
  NOUVEAU_SCRIPT("optimisations.sql", joindre(l, car(10)))
retourner

&&
&& Patrimoine (module 16)
&&

procedure CONSTRUIRE_PATRIMOINE(page)
  globale pat
  pat = {ids = {}}
  locale haut = page:ajouter(ui.rangee())
  haut.marge = 2
  haut.ancrage = "haut"
  pat.classe = haut:ajouter(ui.combo("Tous les objets", "Critiques", "Sensibles", "Obsolètes", "Inutilisés", "À refactoriser"))
  pat.classe:selectionner(1)
  pat.classe.largeurfixe = 170
  pat.classe.surselection = @PAT_FILTRE
  pat.resume = haut:ajouter(ui.etiquette(""))
  pat.resume.poids = 1
  locale s1 = page:ajouter(ui.separateur{vertical = vrai, position = 0.34})
  s1.ancrage = "centre"
  pat.zone = s1:ajouter(ui.colonne())
  pat.g = GRILLE(s1, {{"objet", "Objet", 220}, {"genre", "Genre", 80}, {"lignes", "Lignes", 55, "nombre"}, {"cx", "Complexité", 70, "nombre"}, ;
                      {"ent", "Entrant", 55, "nombre"}, {"sor", "Sortant", 55, "nombre"}, {"coh", "Cohésion", 60, "nombre"}, ;
                      {"dette", "Dette (min)", 70, "nombre"}, {"mi", "Maintenab.", 70, "nombre"}, {"reu", "Réutil.", 55, "nombre"}, ;
                      {"classe", "Classement", 250}, {"score", "Risque", 55, "nombre"}})
  pat.g:ajouterformat("classe", "contient", "Critique", {texte = "#FCA5A5"})
  pat.g:ajouterformat("classe", "contient", "Inutilisé", {texte = "#9CA3AF"})
  pat.g.surdoubleclic = @PAT_OBJET
retourner

procedure REMPLIR_PATRIMOINE
  PAT_FILTRE(nul)
  && mosaïque : dette par schéma
  si pat.mos <> nul
    pat.mos:detruire()
    pat.gc:detruire()
  finsi
  pat.gc = pat.zone:ajouter(ui.graphe("colonnes", "Objets par classement"))
  pat.gc.poids = 1
  locale i = 0
  pour chaque c dans {"Critique", "Sensible", "Obsolète", "Inutilisé", "À refactoriser"}
    i += 1
    pat.gc:libellecategorie(i, c)
    pat.gc:ajouterdonnee(1, i, RV(nul, "select count(*) from metriques where classe like ?", {"%" + c + "%"}))
  suivant
  pat.mos = pat.zone:ajouter(ui.mosaique())
  pat.mos.poids = 1
  pat.mos.infobulle = "Dette technique par schéma (minutes)"
  pour chaque r dans RQ(nul, "select o.base || '.' || o.sch as s, sum(m.dette_min) as d from metriques m join objets o on o.id = m.objet_id " + ;
                             "group by 1 having sum(m.dette_min) > 0 order by 2 desc", nul)
    pat.mos:ajouter(r.s + " · " + arrondi(r.d / 60, 1) + " h", r.d)
  suivant
retourner

procedure PAT_FILTRE(ev)
  locale classes = {"", "Critique", "Sensible", "Obsolète", "Inutilisé", "À refactoriser"}
  locale c = classes[max(1, pat.classe:selection())]
  pat.g:vider()
  pat.ids = {}
  pour chaque r dans RQ(nul, "select o.id, o.sch || '.' || o.nom as nom, o.genre, m.* from metriques m join objets o on o.id = m.objet_id " + ;
                             "where ? = '' or m.classe like ? order by m.score desc nulls last limit 1000", {c, "%" + c + "%"})
    pat.g:ajouterligne(r.nom, LIBELLE_GENRE(r.genre), r.lignes_code, r.complexite, r.entrant, r.sortant, ;
                       sisinon(r.cohesion = nul, nul, arrondi(r.cohesion, 2)), sisinon(r.dette_min = nul, nul, arrondi(r.dette_min)), ;
                       sisinon(r.maintenabilite = nul, nul, arrondi(r.maintenabilite)), sisinon(r.reutilisation = nul, nul, arrondi(r.reutilisation, 2)), ;
                       r.classe, sisinon(r.score = nul, nul, arrondi(r.score)))
    inserer(pat.ids, r.id)
  suivant
  locale dette = RV(nul, "select valeur from meta where cle = 'dette_h'", nul)
  pat.resume.libelle = #pat.ids + " objet(s) · dette technique " + sisinon(dette = nul, "–", dette + " h") + ;
                       " · couplage = entrant + sortant · maintenabilité 0-100 (volume, complexité, taille)"
retourner

procedure PAT_OBJET(ev)
  locale i = pat.g:selection()
  si i <> nul et i >= 1 et i <= #pat.ids
    ALLER_OBJET(pat.ids[i], "patrimoine")
  finsi
retourner

&&
&& Diagnostics (tous modules)
&&

procedure CONSTRUIRE_DIAG(page)
  globale diag
  diag = {ids = {}}
  locale haut = page:ajouter(ui.rangee())
  haut.marge = 2
  haut.ancrage = "haut"
  diag.module = haut:ajouter(ui.combo("Tous les modules"))
  diag.module.largeurfixe = 170
  diag.module.surselection = @DIAG_FILTRE
  diag.niveau = haut:ajouter(ui.combo("Tous les niveaux", "Critique", "Important", "Opportunité"))
  diag.niveau:selectionner(1)
  diag.niveau.largeurfixe = 150
  diag.niveau.surselection = @DIAG_FILTRE
  diag.resume = haut:ajouter(ui.etiquette(""))
  diag.resume.poids = 1
  diag.g = GRILLE(page, {{"niveau", "Niveau", 110}, {"module", "Module", 100}, {"regle", "Règle", 160}, {"objet", "Objet", 220}, ;
                         {"ligne", "Ligne", 50, "nombre"}, {"message", "Constat", 460}, {"suggestion", "Suggestion", 420}})
  diag.g.ancrage = "centre"
  FORMATS_NIVEAU(diag.g, "niveau")
  diag.g.surdoubleclic = @DIAG_OUVRIR
retourner

procedure REMPLIR_DIAG
  diag.module:vider()
  diag.module:ajouter("Tous les modules")
  pour chaque r dans RQ(nul, "select distinct module from diagnostics order by 1", nul)
    diag.module:ajouter(r.module)
  suivant
  diag.module:selectionner(1)
  DIAG_FILTRE(nul)
retourner

procedure DIAG_FILTRE(ev)
  locale m = sisinon(diag.module:selection() > 1, diag.module.valeur, "")
  locale n = {"", "critique", "important", "opportunite"}[max(1, diag.niveau:selection())]
  diag.g:vider()
  diag.ids = {}
  pour chaque r dans RQ(nul, "select d.*, o.sch || '.' || o.nom as nom from diagnostics d left join objets o on o.id = d.objet_id " + ;
                             "where (? = '' or d.module = ?) and (? = '' or d.niveau = ?) order by case d.niveau when 'critique' then 1 " + ;
                             "when 'important' then 2 else 3 end, d.module, nom limit 3000", {m, m, n, n})
    diag.g:ajouterligne(NIVEAU_TEXTE(r.niveau), r.module, r.regle, r.nom, r.ligne, r.message, r.suggestion)
    inserer(diag.ids, r)
  suivant
  diag.resume.libelle = #diag.ids + " constat(s)"
retourner

procedure DIAG_OUVRIR(ev)
  locale i = diag.g:selection()
  si i <> nul et i >= 1 et i <= #diag.ids et diag.ids[i].objet_id <> nul
    OUVRIR_CODE(diag.ids[i].objet_id, diag.ids[i].ligne)
  finsi
retourner
