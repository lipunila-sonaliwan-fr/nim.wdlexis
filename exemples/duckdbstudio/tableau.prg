&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : tableau de bord technique. Inventaire (bases, schémas, tables, vues,
&& volumes), exécution (historique : durées moyennes et maximales, échecs, requêtes les
&& plus coûteuses), qualité (duplications, mutualisations possibles), score global et
&& recommandations par criticité.

procedure CONSTRUIRE_TABLEAU(page)
  globale tdb
  tdb = {}
  locale haut = page:ajouter(ui.rangee())
  haut.ancrage = "haut"
  OUTIL(haut, "Actualiser", @REMPLIR_TABLEAU, "Recalcule les indicateurs")
  OUTIL(haut, "Analyser", @ANALYSER_TOUT, "Relance le moteur d'expertise")
  tdb.titre = haut:ajouter(ui.etiquette(""))
  tdb.titre.poids = 1
  locale sp = page:ajouter(ui.separateur{vertical = vrai, position = 0.36})
  sp.ancrage = "centre"
  tdb.md = sp:ajouter(ui.markdown("Le tableau de bord se remplit à l'ouverture d'un projet."))
  locale g = sp:ajouter(ui.separateur{vertical = faux, position = 0.5})
  locale h = g:ajouter(ui.separateur{vertical = vrai, position = 0.5})
  locale b = g:ajouter(ui.separateur{vertical = vrai, position = 0.5})
  tdb.z1 = h:ajouter(ui.panneau{disposition = "bordure", defilement = "masque"})
  tdb.z2 = h:ajouter(ui.panneau{disposition = "bordure", defilement = "masque"})
  tdb.z3 = b:ajouter(ui.panneau{disposition = "bordure", defilement = "masque"})
  tdb.z4 = b:ajouter(ui.panneau{disposition = "bordure", defilement = "masque"})
  tdb.g = {}
retourner

procedure VOIR_TABLEAU(ev)
  REMPLIR_TABLEAU(nul)
  vues.valeur = 6
retourner

fonction GRAPHE_TDB(i, zone, genre, titre)
  si tdb.g[i] <> nul
    tdb.g[i]:detruire()
  finsi
  locale gr = zone:ajouter(ui.graphe(genre, titre))
  gr.ancrage = "centre"
  tdb.g[i] = gr
retourner gr

fonction STATS_HISTORIQUE()
  locale s = {n = 0, ok = 0, ko = 0, total = 0, max = 0, parsql = {}, ordre = {}}
  pour chaque h dans projet.historique
    s.n += 1
    si h.ok
      s.ok += 1
      locale d = sisinon(h.duree = nul, 0, h.duree)
      s.total += d
      si d > s.max
        s.max = d
      finsi
      locale k = NORMALISER(h.sql)
      si s.parsql[k] = nul
        s.parsql[k] = {sql = h.sql, n = 0, total = 0}
        inserer(s.ordre, k)
      finsi
      s.parsql[k].n += 1
      s.parsql[k].total += d
    sinon
      s.ko += 1
    finsi
  suivant
retourner s

fonction PLUS_COUTEUSE(a, b)
retourner a.total > b.total

procedure REMPLIR_TABLEAU(ev)
  locale nl = car(10)
  && inventaire
  locale nb = 0
  locale ns = 0
  locale nt = 0
  locale nv = 0
  locale nc = 0
  locale vol = 0
  locale parcnx = {}
  pour chaque c dans projet.connexions
    locale cat = catalogue[majuscule(c.nom)]
    si cat <> nul
      nb += 1
      locale v = 0
      pour chaque s dans cat.schemas
        ns += 1
        nt += #s.tables
        nv += #s.vues
        pour chaque t dans s.tables
          nc += #t.colonnes
          v += sisinon(t.lignes = nul, 0, t.lignes)
        suivant
      suivant
      vol += v
      inserer(parcnx, {nom = LIBELLE_CNX(c), lignes = v})
    finsi
  suivant
  && exécution
  locale st = STATS_HISTORIQUE()
  locale requetes = {}
  pour chaque k dans st.ordre
    inserer(requetes, st.parsql[k])
  suivant
  trier(requetes, @PLUS_COUTEUSE)
  locale dup = 0
  pour chaque r dans requetes
    si r.n > 1
      dup += 1
    finsi
  suivant
  && recommandations
  locale niv = {CRITIQUE = 0, IMPORTANT = 0, OPPORTUNITE = 0}
  locale gain = 0
  pour chaque r dans recos
    si r.niveau = "Critique"
      niv.CRITIQUE += 1
    sinonsi r.niveau = "Important"
      niv.IMPORTANT += 1
    sinon
      niv.OPPORTUNITE += 1
    finsi
    si r.actuel <> nul et r.apres <> nul et r.actuel > r.apres
      gain += r.actuel - r.apres
    finsi
  suivant
  locale score = SCORE_GLOBAL(recos)
  tdb.titre.libelle = "Projet " + fichier.nom(dossier) + " - score " + score + " / 100 - " + maintenant()
  locale md = "## Score global : " + score + " / 100" + nl + nl
  md = md + "### Inventaire" + nl
  md = md + "- **" + nb + "** base(s) connectée(s) sur " + #projet.connexions + nl
  md = md + "- **" + ns + "** schéma(s), **" + nt + "** table(s), **" + nv + "** vue(s), **" + nc + "** colonne(s)" + nl
  md = md + "- volume : **" + LIGNES_TEXTE(vol) + "** lignes" + nl + nl
  md = md + "### Exécution" + nl
  md = md + "- **" + st.n + "** requête(s) historisée(s), " + st.ko + " en échec" + nl
  si st.ok > 0
    md = md + "- durée moyenne **" + MS(st.total / st.ok / 1000) + "**, maximale **" + MS(st.max / 1000) + "**, cumulée **" + MS(st.total / 1000) + "**" + nl
  finsi
  md = md + "- **" + #requetes + "** requête(s) distincte(s), **" + dup + "** répétée(s)" + nl + nl
  md = md + "### Recommandations" + nl
  md = md + "- critiques : **" + niv.CRITIQUE + "**" + nl
  md = md + "- importantes : **" + niv.IMPORTANT + "**" + nl
  md = md + "- opportunités : **" + niv.OPPORTUNITE + "**" + nl
  si gain > 0
    md = md + "- gain estimé : **" + MS(gain) + "** par cycle d'exécution de l'historique" + nl
  finsi
  si #requetes > 0
    md = md + nl + "### Requêtes les plus coûteuses" + nl
    pour i = 1 a min(5, #requetes)
      locale r = requetes[i]
      md = md + i + ". " + MS(r.total / 1000) + " (" + r.n + "×) - `" + gauche(RESUME(r.sql), 70) + "`" + nl
    suivant
  finsi
  tdb.md.valeur = md
  && graphes
  locale g1 = GRAPHE_TDB(1, tdb.z1, "secteurs", "Volume par connexion (lignes)")
  pour i = 1 a #parcnx
    g1:ajouterdonnee(1, i, parcnx[i].lignes)
    g1:libellecategorie(i, parcnx[i].nom)
  suivant
  locale g2 = GRAPHE_TDB(2, tdb.z2, "colonnes", "Requêtes les plus coûteuses (ms cumulées)")
  pour i = 1 a min(8, #requetes)
    g2:ajouterdonnee(1, i, arrondi(requetes[i].total, 1))
    g2:libellecategorie(i, "R" + i)
  suivant
  g2:libelleserie(1, "ms")
  locale g3 = GRAPHE_TDB(3, tdb.z3, "colonnes", "Recommandations par criticité")
  g3:ajouterdonnee(1, 1, niv.CRITIQUE)
  g3:ajouterdonnee(1, 2, niv.IMPORTANT)
  g3:ajouterdonnee(1, 3, niv.OPPORTUNITE)
  g3:libellecategorie(1, "Critique")
  g3:libellecategorie(2, "Important")
  g3:libellecategorie(3, "Opportunité")
  g3:libelleserie(1, "nombre")
  locale g4 = GRAPHE_TDB(4, tdb.z4, "lignes", "Durée des dernières requêtes (ms)")
  locale debut = max(1, #projet.historique - 29)
  locale k = 0
  pour i = debut a #projet.historique
    locale h = projet.historique[i]
    k += 1
    g4:ajouterdonnee(1, k, sisinon(h.duree = nul, 0, arrondi(h.duree, 1)))
    g4:libellecategorie(k, "" + k)
  suivant
  g4:libelleserie(1, "ms")
retourner
