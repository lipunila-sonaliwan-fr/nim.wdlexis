&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : cartographie globale. Sources (connexions) -> schémas -> tables ->
&& vues dépendantes, d'après les catalogues ; les vues qui citent des objets d'une autre
&& connexion (requêtes fédérées) sont reliées à travers les sources.

procedure CONSTRUIRE_CARTO(page)
  globale carto
  carto = {filtres = {}}
  locale haut = page:ajouter(ui.rangee())
  haut.ancrage = "haut"
  carto.filtre = haut:ajouter(ui.combo())
  carto.filtre.largeurfixe = 200
  carto.recherche = haut:ajouter(ui.saisie{indication = "rechercher une table, une vue…"})
  carto.recherche.largeurfixe = 220
  carto.recherche.hauteurfixe = 30
  carto.colonnes = haut:ajouter(ui.cases("Tables seules", "Vues", "Grouper par schéma"))
  carto.colonnes:cocher(2, vrai)
  carto.colonnes:cocher(3, vrai)
  OUTIL(haut, "Afficher", @VOIR_CARTO, "Recalcule la cartographie")
  OUTIL(haut, "Ajuster", @CARTO_AJUSTER, "Toute la carte dans la vue")
  carto.resume = haut:ajouter(ui.etiquette(""))
  carto.resume.poids = 1
  carto.dia = page:ajouter(ui.diagramme{modifiable = faux, direction = "droite"})
  carto.dia.ancrage = "centre"
  carto.dia.surselection = @CARTO_CHOIX
  carto.dia.surdoubleclic = @CARTO_DOUBLE
retourner

procedure CARTO_FILTRES
  locale v = carto.filtre:selection()
  carto.filtre:vider()
  carto.filtre:ajouter("Toutes les connexions")
  pour chaque c dans projet.connexions
    carto.filtre:ajouter(LIBELLE_CNX(c))
  suivant
  si v = nul ou v < 1 ou v > #projet.connexions + 1
    v = 1
  finsi
  carto.filtre:selectionner(v)
retourner

procedure CARTO_AJUSTER(ev)
  carto.dia:ajuster()
retourner

procedure VOIR_CARTO(ev)
  si ev = nul ou type(ev) <> "table" ou ev.texte = nul
    vues.valeur = 5
  finsi
  si carto.filtre:nombre() <> #projet.connexions + 1
    CARTO_FILTRES()
  finsi
  REMPLIR_CARTO()
retourner

fonction CARTO_OPTION(i)
retourner carto.colonnes:coche(i)

procedure REMPLIR_CARTO
  locale d = carto.dia
  d:vider()
  carto.objets = {}
  locale choix = carto.filtre:selection()
  locale seule = sisinon(choix = nul ou choix <= 1, "", projet.connexions[choix - 1].nom)
  locale cherche = minuscule(rogner(sisinon(carto.recherche.valeur = nul, "", carto.recherche.valeur)))
  locale grouper = CARTO_OPTION(3)
  locale avecvues = CARTO_OPTION(2) et non CARTO_OPTION(1)
  locale nt = 0
  locale nv = 0
  locale nl = 0
  locale volume = 0
  locale tous = {}     && nom qualifié en minuscules -> id du nœud (pour relier les vues)
  locale lesvues = {}
  pour chaque c dans projet.connexions
    locale cat = catalogue[majuscule(c.nom)]
    si (seule = "" ou seule = c.nom) et cat <> nul
      locale con = CONNECTEUR(c.type)
      locale idc = "c:" + c.nom
      locale ntab = 0
      locale ldet = {}
      pour chaque s dans cat.schemas
        ntab += #s.tables
      suivant
      d:noeud{id = idc, titre = LIBELLE_CNX(c), soustitre = sisinon(con = nul, c.type, con.libelle), forme = "boite", ;
              couleur = sisinon(con = nul, "#334155", con.couleur), pastille = sisinon(con = nul, "", con.sigle), ;
              lignes = {{texte = "schémas", detail = "" + #cat.schemas}, {texte = "tables", detail = "" + ntab}}}
      carto.objets[idc] = {genre = "connexion", cnx = c}
      pour chaque s dans cat.schemas
        locale parent = idc
        si grouper et #cat.schemas > 1
          parent = "s:" + c.nom + "." + s.nom
          d:noeud{id = parent, titre = s.nom, soustitre = "schéma", forme = "boite", couleur = "#64748B"}
          d:lien{de = idc, a = parent, couleur = "#94A3B8"}
        finsi
        pour chaque t dans s.tables
          locale ok = cherche = "" ou contient(minuscule(t.nom), cherche)
          si ok
            locale idt = "t:" + c.nom + "." + s.nom + "." + t.nom
            locale lg = sisinon(t.lignes = nul, 0, t.lignes)
            volume += lg
            d:noeud{id = idt, titre = t.nom, soustitre = LIGNES_TEXTE(lg) + " lignes · " + #t.colonnes + " col.", ;
                    couleur = "#2F5BE0", jauge = min(1, lg / 10000000)}
            d:lien{de = parent, a = idt, couleur = "#94A3B8"}
            carto.objets[idt] = {genre = "table", cnx = c, schema = s.nom, nom = t.nom}
            tous[minuscule(t.nom)] = idt
            tous[minuscule(s.nom + "." + t.nom)] = idt
            tous[minuscule(ALIAS(c) + "." + s.nom + "." + t.nom)] = idt
            tous[minuscule(ALIAS(c) + "." + t.nom)] = idt
            nt += 1
          finsi
        suivant
        si avecvues
          pour chaque v dans s.vues
            locale idv = "v:" + c.nom + "." + s.nom + "." + v.nom
            inserer(lesvues, {id = idv, vue_ = v, parent = parent, cnx = c, schema = s.nom})
            tous[minuscule(v.nom)] = idv
            tous[minuscule(ALIAS(c) + "." + s.nom + "." + v.nom)] = idv
          suivant
        finsi
      suivant
    finsi
  suivant
  && vues : reliées aux objets qu'elles citent (même connexion ou non)
  pour chaque x dans lesvues
    locale deps = CITATIONS(x.vue_.sql, tous, x.id)
    si cherche = "" ou contient(minuscule(x.vue_.nom), cherche) ou #deps > 0 et CARTO_UN_PRESENT(deps)
      d:noeud{id = x.id, titre = x.vue_.nom, soustitre = "vue · " + #x.vue_.colonnes + " col.", forme = "boite", couleur = "#F5B83D"}
      carto.objets[x.id] = {genre = "vue", cnx = x.cnx, schema = x.schema, nom = x.vue_.nom, sql = x.vue_.sql}
      nv += 1
      si #deps = 0
        d:lien{de = x.parent, a = x.id, couleur = "#94A3B8"}
      finsi
      pour chaque dep dans deps
        locale federe = gauche(dep, 2) = "t:" et non commencepar(dep, "t:" + x.cnx.nom + ".")
        d:lien{de = dep, a = x.id, pointille = vrai, couleur = sisinon(federe, "#DC2626", "#F59E0B"), ;
               libelle = sisinon(federe, "fédéré", "")}
        nl += 1
      suivant
    finsi
  suivant
  d:disposer("droite")
  d:ajuster(50)
  carto.resume.libelle = #projet.connexions + " connexion(s) · " + nt + " table(s) · " + nv + " vue(s) · " + ;
                         nl + " dépendance(s) · " + LIGNES_TEXTE(volume) + " lignes"
retourner

fonction CARTO_UN_PRESENT(deps)
  pour chaque d_ dans deps
    si carto.objets[d_] <> nul
      retourner vrai
    finsi
  suivant
retourner faux

fonction CITATIONS(sql, tous, soi)
  && identifiants (éventuellement qualifiés) du texte présents dans l'index `tous`
  locale l = {}
  locale vus = {}
  locale t = minuscule(sisinon(sql = nul, "", sql))
  locale mot = ""
  pour i = 1 a longueur(t) + 1
    locale ch = sisinon(i <= longueur(t), souschaine(t, i, 1), " ")
    si (ch >= "a" et ch <= "z") ou (ch >= "0" et ch <= "9") ou ch = "_" ou ch = "."
      mot = mot + ch
    sinonsi ch = car(34)
      && identifiant entre guillemets : on garde son contenu
    sinon
      si mot <> ""
        locale id = tous[mot]
        si id <> nul et id <> soi et vus[id] = nul
          vus[id] = vrai
          inserer(l, id)
        finsi
      finsi
      mot = ""
    finsi
  suivant
retourner l

procedure CARTO_CHOIX(ev)
  locale o = carto.objets[ev.texte]
  si o = nul
    retourner
  finsi
  faire cas
  cas o.genre = "connexion"
    STATUT("Connexion " + o.cnx.nom + " (" + o.cnx.type + ")" + sisinon(o.cnx.description = nul ou o.cnx.description = "", "", " - " + o.cnx.description))
  cas o.genre = "table"
    STATUT("Table " + NOM_QUALIFIE(ALIAS(o.cnx), o.schema, o.nom, CONNECTEUR(o.cnx.type).mode = "fichiers") + " - double-clic : interroger")
  cas o.genre = "vue"
    STATUT("Vue " + o.nom + " : " + gauche(remplacertexte(o.sql, car(10), " "), 200))
  fincas
retourner

procedure CARTO_DOUBLE(ev)
  locale o = carto.objets[ev.texte]
  si o = nul
    retourner
  finsi
  si o.genre = "connexion"
    SCHEMA_DEPUIS_CATALOGUE(o.cnx, "")
  sinon
    locale q = "SELECT * FROM " + NOM_QUALIFIE(ALIAS(o.cnx), o.schema, o.nom, CONNECTEUR(o.cnx.type).mode = "fichiers") + " LIMIT 100;"
    vues.valeur = 1
    ed:inserer(car(10) + q)
    EXECUTER_TEXTE(q)
  finsi
retourner
