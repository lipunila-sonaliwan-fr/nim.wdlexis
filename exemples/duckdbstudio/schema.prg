&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : concepteur de schéma (modèle entité-relation).
&&
&& * Catalogue -> modèle : tables, colonnes, types, clés primaires et étrangères, index,
&&   vues (et leurs dépendances), lus dans le catalogue d'une connexion.
&& * Script SQL -> modèle : les instructions CREATE du script sont exécutées dans une base
&&   en mémoire jetable (analyseur de DuckDB), puis relues : réversibilité fidèle.
&& * Modèle -> SQL : CREATE TABLE (clés comprises, dans l'ordre des dépendances),
&&   CREATE INDEX, CREATE VIEW.
&& * À la souris : déplacer les tables, tirer une clé étrangère d'une colonne vers une
&&   colonne d'une autre table, Suppr pour supprimer (après analyse d'impact).

procedure CONSTRUIRE_SCHEMA(page)
  globale sch
  sch = {sources = {}}
  locale haut = page:ajouter(ui.rangee())
  haut.ancrage = "haut"
  sch.source = haut:ajouter(ui.combo())
  sch.source.largeurfixe = 200
  OUTIL(haut, "Charger", @SCHEMA_CHARGER, "Modèle du schéma choisi, lu dans le catalogue")
  OUTIL(haut, "+ Table", @SCHEMA_NOUVELLE_TABLE, "Ajoute une table au modèle")
  OUTIL(haut, "Script → modèle", @SCHEMA_DEPUIS_SCRIPT, "Reconstruit le modèle à partir du script SQL actif")
  OUTIL(haut, "Modèle → SQL", @SCHEMA_GENERER, "CREATE TABLE / INDEX / VIEW dans une nouvelle requête")
  OUTIL(haut, "Impact", @SCHEMA_IMPACT, "Ce qui dépend de la table (ou de la colonne) sélectionnée")
  OUTIL(haut, "Disposer", @SCHEMA_DISPOSER, "Disposition automatique")
  OUTIL(haut, "Ajuster", @SCHEMA_AJUSTER, "Tout le modèle dans la vue")
  locale sp = page:ajouter(ui.separateur{vertical = vrai, position = 0.64})
  sp.ancrage = "centre"
  sch.dia = sp:ajouter(ui.diagramme{modifiable = vrai, direction = "droite"})
  sch.dia.surselection = @SCHEMA_SELECTION
  sch.dia.surchangement = @SCHEMA_ACTION
  locale droite_ = sp:ajouter(ui.separateur{vertical = faux, position = 0.62})
  locale insp = droite_:ajouter(ui.colonne())
  sch.titre = insp:ajouter(ui.etiquette("Aucun modèle"))
  locale r = insp:ajouter(ui.rangee())
  sch.nom = r:ajouter(ui.saisie{indication = "nom de la table"})
  sch.nom.poids = 1
  locale ba = r:ajouter(ui.bouton("Appliquer"))
  ba.surclic = @SCHEMA_APPLIQUER
  ba.infobulle = "Applique le nom et les colonnes au modèle"
  locale bc = r:ajouter(ui.bouton("+"))
  bc.surclic = @SCHEMA_AJOUTER_COLONNE
  bc.infobulle = "Ajoute une colonne à la table sélectionnée"
  sch.zonecols = insp:ajouter(ui.panneau{disposition = "bordure", defilement = "masque"})
  sch.zonecols.poids = 1
  sch.cols = nul
  sch.fiche = droite_:ajouter(ui.markdown("Chargez un schéma, ou reconstruisez-le depuis un script."))
  SCHEMA_GRILLE(nul)
retourner

procedure SCHEMA_SOURCES
  sch.source:vider()
  sch.sources = {}
  pour chaque c dans projet.connexions
    locale cat = catalogue[majuscule(c.nom)]
    si cat <> nul
      pour chaque s dans cat.schemas
        sch.source:ajouter(LIBELLE_CNX(c) + " · " + s.nom)
        inserer(sch.sources, {cnx = c, schema = s.nom})
        si modele <> nul et modele.clef = c.nom + "." + s.nom
          sch.source:selectionner(#sch.sources)
        finsi
      suivant
    finsi
  suivant
  si sch.source:selection() < 1 et #sch.sources > 0
    sch.source:selectionner(1)
  finsi
retourner

procedure SCHEMA_CHARGER(ev)
  SCHEMA_SOURCES_SI_VIDE()
  locale i = sch.source:selection()
  si i = nul ou i < 1 ou i > #sch.sources
    STATUT("Choisissez une connexion et un schéma.")
    retourner
  finsi
  SCHEMA_DEPUIS_CATALOGUE(sch.sources[i].cnx, sch.sources[i].schema)
retourner

procedure SCHEMA_SOURCES_SI_VIDE
  si #sch.sources = 0
    SCHEMA_SOURCES()
  finsi
retourner

&&
&& Modèle
&&

fonction MODELE_VIDE(cnx, schema)
retourner {cnx = cnx, schema = schema, tables = {}, vues = {}, clef = sisinon(cnx = nul, "script", cnx.nom) + "." + schema}

fonction TABLE_MODELE(nom)
  pour chaque t dans modele.tables
    si minuscule(t.nom) = minuscule(nom)
      retourner t
    finsi
  suivant
retourner nul

fonction MODELE_DEPUIS_CAT(cat, cnx, schema)
  locale m = MODELE_VIDE(cnx, schema)
  pour chaque s dans cat.schemas
    si schema = "" ou s.nom = schema
      pour chaque t dans s.tables
        locale cols = {}
        pour chaque c dans t.colonnes
          inserer(cols, {nom = c.nom, type = c.type, pk = contient(sisinon(t.pk = nul, {}, t.pk), c.nom), ;
                         nonnul = c.nul = faux, defaut = sisinon(c.defaut = nul, "", c.defaut)})
        suivant
        locale fks = {}
        pour chaque f dans t.fk
          pour i = 1 a #f.colonnes
            inserer(fks, {colonne = f.colonnes[i], table = f.table, refcolonne = sisinon(i <= #f.refs, f.refs[i], f.refs[1])})
          suivant
        suivant
        inserer(m.tables, {nom = t.nom, colonnes = cols, fk = fks, index = t.index, lignes = sisinon(cnx = nul, nul, t.lignes)})
      suivant
      pour chaque v dans s.vues
        inserer(m.vues, {nom = v.nom, sql = v.sql, colonnes = v.colonnes})
      suivant
    finsi
  suivant
retourner m

procedure SCHEMA_DEPUIS_CATALOGUE(cnx, schema)
  globale modele
  locale cat = catalogue[majuscule(cnx.nom)]
  si cat = nul
    STATUT("Catalogue de « " + cnx.nom + " » indisponible : connectez-vous (↻).")
    retourner
  finsi
  si schema = "" et #cat.schemas > 0
    schema = cat.schemas[1].nom
  finsi
  modele = MODELE_DEPUIS_CAT(cat, cnx, schema)
  sch.titre.libelle = cnx.nom + " · " + schema + " - " + #modele.tables + " table(s), " + #modele.vues + " vue(s)"
  SCHEMA_SOURCES()
  AFFICHER_MODELE(vrai)
  vues.valeur = 2
retourner

fonction DEPENDANCES_VUE(v)
  && tables et vues du modèle citées par le texte de la vue
  locale l = {}
  locale t = " " + minuscule(remplacertexte(remplacertexte(v.sql, car(10), " "), car(34), " ")) + " "
  pour chaque x dans modele.tables
    si contient(t, " " + minuscule(x.nom) + " ") ou contient(t, "." + minuscule(x.nom) + " ") ou ;
       contient(t, " " + minuscule(x.nom) + ",") ou contient(t, "." + minuscule(x.nom) + ",")
      inserer(l, x.nom)
    finsi
  suivant
  pour chaque x dans modele.vues
    si x.nom <> v.nom et (contient(t, " " + minuscule(x.nom) + " ") ou contient(t, "." + minuscule(x.nom) + " "))
      inserer(l, "vue:" + x.nom)
    finsi
  suivant
retourner l

fonction INDEX_COLONNE(t, nom)
  pour i = 1 a #t.colonnes
    si minuscule(t.colonnes[i].nom) = minuscule(nom)
      retourner i
    finsi
  suivant
retourner 0

procedure AFFICHER_MODELE(disposer)
  locale d = sch.dia
  d:vider()
  locale pos = projet.positions[modele.clef]
  locale places = 0
  pour chaque t dans modele.tables
    locale lignes = {}
    pour chaque c dans t.colonnes
      locale marque = ""
      si c.pk
        marque = "PK"
      finsi
      pour chaque f dans t.fk
        si minuscule(f.colonne) = minuscule(c.nom)
          marque = sisinon(marque = "", "FK", "PF")
        finsi
      suivant
      inserer(lignes, {texte = c.nom + sisinon(c.nonnul et non c.pk, " *", ""), detail = minuscule(c.type), marque = marque})
    suivant
    locale o = {id = t.nom, titre = t.nom, couleur = "#2F5BE0", lignes = lignes, ;
                soustitre = sisinon(t.lignes = nul, "", LIGNES_TEXTE(t.lignes) + " lignes")}
    si pos <> nul et pos[t.nom] <> nul
      o.x = pos[t.nom].x
      o.y = pos[t.nom].y
      places += 1
    finsi
    d:noeud(o)
  suivant
  pour chaque v dans modele.vues
    locale o = {id = "vue:" + v.nom, titre = v.nom, soustitre = "vue", forme = "boite", couleur = "#F5B83D"}
    si pos <> nul et pos["vue:" + v.nom] <> nul
      o.x = pos["vue:" + v.nom].x
      o.y = pos["vue:" + v.nom].y
      places += 1
    finsi
    d:noeud(o)
  suivant
  pour chaque t dans modele.tables
    pour chaque f dans t.fk
      locale cible = TABLE_MODELE(f.table)
      si cible <> nul
        d:lien{de = t.nom, deligne = INDEX_COLONNE(t, f.colonne), a = cible.nom, aligne = INDEX_COLONNE(cible, f.refcolonne), ;
               couleur = "#60A5FA"}
      finsi
    suivant
  suivant
  pour chaque v dans modele.vues
    pour chaque dep dans DEPENDANCES_VUE(v)
      d:lien{de = dep, a = "vue:" + v.nom, pointille = vrai, couleur = "#F59E0B"}
    suivant
  suivant
  si disposer et places < #modele.tables + #modele.vues
    d:disposer("droite")
  finsi
  d:ajuster(50)
retourner

procedure SCHEMA_DISPOSER(ev)
  si modele <> nul
    sch.dia:disposer("droite")
    sch.dia:ajuster()
    SCHEMA_MEMORISER_POSITIONS()
  finsi
retourner

procedure SCHEMA_AJUSTER(ev)
  sch.dia:ajuster()
retourner

procedure SCHEMA_MEMORISER_POSITIONS
  si modele = nul
    retourner
  finsi
  locale p = {}
  pour chaque n dans sch.dia:noeuds()
    p[n.id] = {x = n.x, y = n.y}
  suivant
  projet.positions[modele.clef] = p
retourner

&&
&& Sélection, inspecteur
&&

procedure SCHEMA_SELECTION(ev)
  globale tablecourante
  si modele = nul
    retourner
  finsi
  locale t = TABLE_MODELE(ev.texte)
  tablecourante = t
  si t = nul
    && vue : son texte
    pour chaque v dans modele.vues
      si "vue:" + v.nom = ev.texte
        sch.fiche.valeur = "### Vue " + v.nom + car(10) + car(10) + "```" + car(10) + v.sql + car(10) + "```"
      finsi
    suivant
    retourner
  finsi
  sch.nom.valeur = t.nom
  SCHEMA_GRILLE(t)
  locale md = "### " + t.nom + car(10)
  si #t.fk > 0
    md = md + car(10) + "Clés étrangères :" + car(10)
    pour chaque f dans t.fk
      md = md + "- `" + f.colonne + "` → `" + f.table + "." + f.refcolonne + "`" + car(10)
    suivant
  finsi
  si t.index <> nul et #t.index > 0
    md = md + car(10) + "Index : " + #t.index + car(10)
  finsi
  md = md + car(10) + "Tirez une pastille de colonne vers une colonne d'une autre table pour créer une clé étrangère."
  sch.fiche.valeur = md
retourner

procedure SCHEMA_GRILLE(t)
  si sch.cols <> nul
    sch.cols:detruire()
  finsi
  sch.cols = sch.zonecols:ajouter(ui.grille())
  sch.cols.ancrage = "centre"
  sch.cols:ajoutercolonne{nom = "nom", titre = "Colonne", largeur = 120}
  sch.cols:ajoutercolonne{nom = "type", titre = "Type", largeur = 100, genre = "combo", ;
                          choix = {"INTEGER", "BIGINT", "VARCHAR", "DECIMAL(12,2)", "DOUBLE", "DATE", "TIMESTAMP", "BOOLEAN", "UUID", "JSON", "BLOB"}}
  sch.cols:ajoutercolonne{nom = "pk", titre = "PK", largeur = 40, genre = "case"}
  sch.cols:ajoutercolonne{nom = "nonnul", titre = "Requis", largeur = 55, genre = "case"}
  sch.cols:ajoutercolonne{nom = "defaut", titre = "Défaut", largeur = 80}
  sch.cols:fixermodifiable(vrai)
  si t <> nul
    pour chaque c dans t.colonnes
      sch.cols:ajouterligne(c.nom, c.type, sisinon(c.pk, "1", "0"), sisinon(c.nonnul, "1", "0"), c.defaut)
    suivant
  finsi
retourner

procedure SCHEMA_AJOUTER_COLONNE(ev)
  si tablecourante = nul
    STATUT("Sélectionnez une table du modèle.")
    retourner
  finsi
  sch.cols:ajouterligne("colonne" + (sch.cols:nombre() + 1), "VARCHAR", "0", "0", "")
retourner

fonction VRAI_CELLULE(v)
retourner v = "1" ou minuscule(v) = "vrai" ou minuscule(v) = "true" ou v = vrai

procedure SCHEMA_APPLIQUER(ev)
  locale t = tablecourante
  si t = nul
    retourner
  finsi
  locale ancien = t.nom
  locale nouveau = rogner(sch.nom.valeur)
  locale cols = {}
  pour i = 1 a sch.cols:nombre()
    locale nom = rogner(sch.cols:cellule(i, "nom"))
    si nom <> ""
      inserer(cols, {nom = nom, type = sch.cols:cellule(i, "type"), pk = VRAI_CELLULE(sch.cols:cellule(i, "pk")), ;
                     nonnul = VRAI_CELLULE(sch.cols:cellule(i, "nonnul")), defaut = sch.cols:cellule(i, "defaut")})
    finsi
  suivant
  t.colonnes = cols
  si nouveau <> "" et nouveau <> ancien
    && renommage : propagé aux clés étrangères des autres tables
    t.nom = nouveau
    pour chaque x dans modele.tables
      pour chaque f dans x.fk
        si minuscule(f.table) = minuscule(ancien)
          f.table = nouveau
        finsi
      suivant
    suivant
    JOURNAL("Renommage " + ancien + " → " + nouveau + " propagé aux clés étrangères")
  finsi
  && clés étrangères dont la colonne n'existe plus
  locale fks = {}
  pour chaque f dans t.fk
    si INDEX_COLONNE(t, f.colonne) > 0
      inserer(fks, f)
    sinon
      JOURNAL("Clé étrangère retirée : " + t.nom + "." + f.colonne + " (colonne supprimée)")
    finsi
  suivant
  t.fk = fks
  SCHEMA_MEMORISER_POSITIONS()
  si nouveau <> ancien et projet.positions[modele.clef] <> nul
    projet.positions[modele.clef][nouveau] = projet.positions[modele.clef][ancien]
  finsi
  AFFICHER_MODELE(faux)
  sch.dia:selectionner(t.nom)
retourner

procedure SCHEMA_NOUVELLE_TABLE(ev)
  globale modele
  si modele = nul
    modele = MODELE_VIDE(nul, "main")
  finsi
  locale nom = ui.demander("Nom de la nouvelle table :", "table" + (#modele.tables + 1))
  si nom = nul ou rogner(nom) = ""
    retourner
  finsi
  inserer(modele.tables, {nom = rogner(nom), colonnes = {{nom = "id", type = "INTEGER", pk = vrai, nonnul = vrai, defaut = ""}}, ;
                          fk = {}, index = {}})
  sch.dia:noeud{id = rogner(nom), titre = rogner(nom), couleur = "#2F5BE0", lignes = {{texte = "id", detail = "integer", marque = "PK"}}}
  sch.dia:selectionner(rogner(nom))
  tablecourante = TABLE_MODELE(nom)
  sch.nom.valeur = rogner(nom)
  SCHEMA_GRILLE(tablecourante)
retourner

&&
&& Actions à la souris : déplacement, liaison (clé étrangère), suppression
&&

procedure SCHEMA_ACTION(ev)
  si modele = nul
    retourner
  finsi
  locale a = sch.dia:action()
  faire cas
  cas a.action = "deplace"
    SCHEMA_MEMORISER_POSITIONS()
  cas a.action = "lien"
    locale t = TABLE_MODELE(a.de)
    locale cible = TABLE_MODELE(a.a)
    si t = nul ou cible = nul
      retourner
    finsi
    locale col = sisinon(a.deligne > 0, t.colonnes[max(1, a.deligne)].nom, "")
    locale ref = sisinon(a.aligne > 0, cible.colonnes[max(1, a.aligne)].nom, "")
    si ref = ""
      && vers la clé primaire de la cible
      pour chaque c dans cible.colonnes
        si c.pk
          ref = c.nom
        finsi
      suivant
    finsi
    si col = "" ou ref = ""
      STATUT("Liaison : partez d'une colonne et arrivez sur une colonne (ou une table avec clé primaire).")
      retourner
    finsi
    si ui.confirmer("Clé étrangère " + t.nom + "." + col + " → " + cible.nom + "." + ref + " ?")
      inserer(t.fk, {colonne = col, table = cible.nom, refcolonne = ref})
      JOURNAL("Clé étrangère ajoutée : " + t.nom + "." + col + " → " + cible.nom + "." + ref)
      SCHEMA_MEMORISER_POSITIONS()
      AFFICHER_MODELE(faux)
    finsi
  cas a.action = "supprimer"
    SCHEMA_SUPPRIMER(a.id)
  fincas
retourner

procedure SCHEMA_SUPPRIMER(id)
  && un lien : la clé étrangère ; un nœud : la table, après analyse d'impact
  pour chaque t dans modele.tables
    locale garde = {}
    locale retire = faux
    pour chaque f dans t.fk
      si t.nom + ">" + f.table + "#" + INDEX_COLONNE(t, f.colonne) + ":" + INDEX_COLONNE(TABLE_MODELE(f.table), f.refcolonne) = id
        retire = vrai
      sinon
        inserer(garde, f)
      finsi
    suivant
    si retire
      t.fk = garde
      AFFICHER_MODELE(faux)
      retourner
    finsi
  suivant
  locale t = TABLE_MODELE(id)
  si t = nul
    retourner
  finsi
  locale imp = IMPACT(t.nom, "")
  si non ui.confirmer("Supprimer la table « " + t.nom + " » du modèle ?" + car(10) + car(10) + imp.resume)
    retourner
  finsi
  locale l = {}
  pour chaque x dans modele.tables
    si x <> t
      locale fks = {}
      pour chaque f dans x.fk
        si minuscule(f.table) <> minuscule(t.nom)
          inserer(fks, f)
        finsi
      suivant
      x.fk = fks
      inserer(l, x)
    finsi
  suivant
  modele.tables = l
  AFFICHER_MODELE(faux)
  sch.fiche.valeur = imp.md
retourner

&&
&& Analyse d'impact (suppression, modification, renommage)
&&

fonction IMPACT(table, colonne)
  locale nl = car(10)
  locale cible = minuscule(table)
  locale col = minuscule(colonne)
  locale lignes = {}
  locale n = 0
  pour chaque t dans modele.tables
    pour chaque f dans t.fk
      si minuscule(f.table) = cible et (col = "" ou minuscule(f.refcolonne) = col)
        inserer(lignes, "- clé étrangère **" + t.nom + "." + f.colonne + "** → " + table + "." + f.refcolonne)
        n += 1
      finsi
    suivant
  suivant
  pour chaque v dans modele.vues
    locale s = minuscule(v.sql)
    si contient(s, cible) et (col = "" ou contient(s, col))
      inserer(lignes, "- vue **" + v.nom + "** (son texte cite " + table + sisinon(col = "", "", "." + colonne) + ")")
      n += 1
    finsi
  suivant
  locale nh = 0
  pour chaque h dans projet.historique
    locale s = minuscule(h.sql)
    si contient(s, cible) et (col = "" ou contient(s, col))
      nh += 1
    finsi
  suivant
  si nh > 0
    inserer(lignes, "- **" + nh + "** requête(s) de l'historique")
  finsi
  pour chaque f dans fichier.liste(dossier, faux)
    si minuscule(fichier.extension(f)) = ".sql"
      locale s = minuscule(fichier.lire(fichier.joindre(dossier, f)))
      si contient(s, cible) et (col = "" ou contient(s, col))
        inserer(lignes, "- script **" + f + "**")
        n += 1
      finsi
    finsi
  suivant
  locale titre = "Impact de " + table + sisinon(colonne = "", "", "." + colonne)
  locale md = "### " + titre + nl + nl + sisinon(#lignes = 0, "Aucune dépendance trouvée.", joindre(lignes, nl))
  locale resume = sisinon(#lignes = 0, "Aucune dépendance trouvée.", n + " objet(s) dépendant(s), " + nh + " requête(s) de l'historique.")
retourner {md = md, resume = resume, nombre = n}

procedure SCHEMA_IMPACT(ev)
  si modele = nul
    retourner
  finsi
  locale s = sch.dia:selection()
  locale t = TABLE_MODELE(s.id)
  si t = nul
    STATUT("Sélectionnez une table (ou une colonne) du modèle.")
    retourner
  finsi
  locale col = sisinon(s.ligne > 0 et s.ligne <= #t.colonnes, t.colonnes[max(1, s.ligne)].nom, "")
  locale imp = IMPACT(t.nom, col)
  sch.fiche.valeur = imp.md
  JOURNAL(imp.resume)
  && objets dépendants en rouge
  pour chaque x dans modele.tables
    pour chaque f dans x.fk
      si minuscule(f.table) = minuscule(t.nom) et (col = "" ou minuscule(f.refcolonne) = minuscule(col))
        sch.dia:noeud{id = x.nom, couleur = "#DC2626"}
      finsi
    suivant
  suivant
  pour chaque v dans modele.vues
    si contient(minuscule(v.sql), minuscule(t.nom)) et (col = "" ou contient(minuscule(v.sql), minuscule(col)))
      sch.dia:noeud{id = "vue:" + v.nom, couleur = "#DC2626"}
    finsi
  suivant
retourner

&&
&& Modèle -> SQL
&&

fonction ORDRE_TABLES()
  && tables référencées d'abord (tri topologique ; cycles : ordre d'origine)
  locale fait = {}
  locale l = {}
  locale tours = 0
  tantque #l < #modele.tables et tours <= #modele.tables
    tours += 1
    pour chaque t dans modele.tables
      si fait[t.nom] = nul
        locale pret = vrai
        pour chaque f dans t.fk
          si f.table <> t.nom et fait[f.table] = nul et TABLE_MODELE(f.table) <> nul
            pret = faux
          finsi
        suivant
        si pret ou tours = #modele.tables
          fait[t.nom] = vrai
          inserer(l, t)
        finsi
      finsi
    suivant
  fintantque
retourner l

fonction SQL_MODELE()
  locale nl = car(10)
  locale out = {"-- Modèle " + modele.clef + " généré par DuckDB [S]tudio le " + maintenant()}
  pour chaque t dans ORDRE_TABLES()
    locale l = {}
    locale pks = {}
    pour chaque c dans t.colonnes
      inserer(l, "  " + IDENT(c.nom) + " " + c.type + sisinon(c.nonnul et non c.pk, " NOT NULL", "") + ;
              sisinon(c.defaut <> nul et c.defaut <> "", " DEFAULT " + c.defaut, ""))
      si c.pk
        inserer(pks, IDENT(c.nom))
      finsi
    suivant
    si #pks > 0
      inserer(l, "  PRIMARY KEY (" + joindre(pks, ", ") + ")")
    finsi
    pour chaque f dans t.fk
      inserer(l, "  FOREIGN KEY (" + IDENT(f.colonne) + ") REFERENCES " + IDENT(f.table) + " (" + IDENT(f.refcolonne) + ")")
    suivant
    inserer(out, "CREATE TABLE " + IDENT(t.nom) + " (" + nl + joindre(l, "," + nl) + nl + ");")
    si t.index <> nul
      pour chaque ix dans t.index
        si ix.sql <> nul et ix.sql <> ""
          inserer(out, ix.sql + sisinon(finitpar(rogner(ix.sql), ";"), "", ";"))
        finsi
      suivant
    finsi
  suivant
  pour chaque v dans ORDRE_VUES()
    locale s = rogner(v.sql)
    inserer(out, s + sisinon(finitpar(s, ";"), "", ";"))
  suivant
retourner joindre(out, nl + nl) + nl

fonction ORDRE_VUES()
  && une vue après celles qu'elle cite
  locale fait = {}
  locale l = {}
  pour tour = 1 a #modele.vues + 1
    pour chaque v dans modele.vues
      si fait[v.nom] = nul
        locale pret = vrai
        pour chaque d_ dans DEPENDANCES_VUE(v)
          si commencepar(d_, "vue:") et fait[souschaine(d_, 5)] = nul
            pret = faux
          finsi
        suivant
        si pret ou tour > #modele.vues
          fait[v.nom] = vrai
          inserer(l, v)
        finsi
      finsi
    suivant
  suivant
retourner l

procedure SCHEMA_GENERER(ev)
  si modele = nul
    STATUT("Aucun modèle.")
    retourner
  finsi
  NOUVELLE_REQUETE()
  ed:fixertexte(SQL_MODELE())
  STATUT("SQL du modèle généré (" + #modele.tables + " table(s), " + #modele.vues + " vue(s)).")
retourner

&&
&& Script SQL -> modèle (réversibilité par l'analyseur de DuckDB)
&&

fonction INSTRUCTION_DE_DEFINITION(s)
  locale m = PREMIER_MOT(s)
  si m <> "create" et m <> "alter" et m <> "comment"
    retourner faux
  finsi
  && cible qualifiée par une autre base (a.b.c) : refusée par prudence
  locale tete = minuscule(gauche(SANS_COMMENTAIRES(s), 120))
  locale p = position("(", tete)
  locale q = position(" as ", tete)
  locale fin_ = longueur(tete)
  si p > 0
    fin_ = p
  finsi
  si q > 0 et q < fin_
    fin_ = q
  finsi
  locale segment = gauche(tete, fin_)
  locale points = longueur(segment) - longueur(remplacertexte(segment, ".", ""))
retourner points < 2

procedure SCHEMA_DEPUIS_SCRIPT(ev)
  globale modele
  locale texte = ed:texte()
  locale l = DECOUPER_SQL(texte)
  locale c = {nom = "modele_tmp", type = "memoire", parametres = {}, options = {}}
  locale ok = 0
  locale ko = {}
  essayer
    requete("DETACH DATABASE IF EXISTS modele_tmp")
    requete("ATTACH ':memory:' AS modele_tmp")
    requete("USE modele_tmp")
    && plusieurs passes : une vue (ou une clé) qui cite un objet défini plus loin réussit au tour suivant
    locale reste = {}
    pour chaque ins dans l
      si INSTRUCTION_DE_DEFINITION(ins.sql)
        inserer(reste, ins.sql)
      finsi
    suivant
    locale progres = vrai
    tantque #reste > 0 et progres
      progres = faux
      ko = {}
      locale suivants = {}
      pour chaque q dans reste
        essayer
          requete(q)
          ok += 1
          progres = vrai
        capturer e
          inserer(suivants, q)
          inserer(ko, RESUME(q) + " : " + e)
        finessayer
      suivant
      reste = suivants
    fintantque
    requete("USE memory")
    INTROSPECTER(c)
    locale cat = catalogue["MODELE_TMP"]
    modele = MODELE_DEPUIS_CAT(cat, nul, "main")
    modele.clef = "script." + sisinon(ed:chemin() = "", "sans_titre", fichier.nom(ed:chemin()))
    catalogue["MODELE_TMP"] = nul
    requete("DETACH DATABASE modele_tmp")
  capturer e
    essayer
      requete("USE memory")
    capturer e2
    finessayer
    ERREUR("Script → modèle : " + e)
    retourner
  finessayer
  pour chaque k dans ko
    JOURNAL("ignorée : " + k)
  suivant
  sch.titre.libelle = "Modèle du script - " + #modele.tables + " table(s), " + #modele.vues + " vue(s)"
  AFFICHER_MODELE(vrai)
  vues.valeur = 2
  STATUT(ok + " instruction(s) de définition relue(s)" + sisinon(#ko > 0, ", " + #ko + " ignorée(s) (voir Messages)", ""))
retourner
