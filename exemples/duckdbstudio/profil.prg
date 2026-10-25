&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : profil d'exécution. EXPLAIN (ANALYZE, FORMAT JSON) exécute la requête
&& et renvoie l'arbre des opérateurs (temps, lignes produites et lues, mémoire) ; il est
&& affiché en graphe (ui.diagramme), en tableau et en histogramme, puis passé au moteur
&& d'expertise.

procedure CONSTRUIRE_PROFIL(page)
  globale prof
  prof = {}
  locale haut = page:ajouter(ui.rangee())
  haut.ancrage = "haut"
  prof.resume = haut:ajouter(ui.etiquette("Placez le curseur dans une requête SELECT puis Profiler (F6)."))
  prof.resume.poids = 1
  locale b = haut:ajouter(ui.bouton("Profiler"))
  b.surclic = @PROFILER
  locale b2 = haut:ajouter(ui.bouton("Ajuster"))
  b2.surclic = @PROFIL_AJUSTER
  locale sp = page:ajouter(ui.separateur{vertical = vrai, position = 0.62})
  sp.ancrage = "centre"
  prof.graphe = sp:ajouter(ui.diagramme{modifiable = faux, direction = "bas"})
  prof.graphe.surselection = @PROFIL_CHOIX
  locale droite_ = sp:ajouter(ui.separateur{vertical = faux, position = 0.55})
  prof.ctab = droite_:ajouter(ui.panneau{disposition = "bordure", defilement = "masque"})
  prof.chisto = droite_:ajouter(ui.panneau{disposition = "bordure", defilement = "masque"})
  prof.table = nul
  prof.histo = nul
  NOUVELLE_TABLE_PROFIL()
retourner

procedure NOUVELLE_TABLE_PROFIL
  si prof.table <> nul
    prof.table:detruire()
  finsi
  prof.table = prof.ctab:ajouter(ui.tableau())
  prof.table.ancrage = "centre"
  prof.table:ajoutercolonne("Opérateur", 190)
  prof.table:ajoutercolonne("Temps (ms)", 90, "droite")
  prof.table:ajoutercolonne("%", 50, "droite")
  prof.table:ajoutercolonne("Lignes", 80, "droite")
  prof.table:ajoutercolonne("Lues", 80, "droite")
  si prof.histo <> nul
    prof.histo:detruire()
  finsi
  prof.histo = prof.chisto:ajouter(ui.graphe("colonnes", "Temps par opérateur (ms)"))
  prof.histo.ancrage = "centre"
retourner

procedure PROFIL_AJUSTER(ev)
  prof.graphe:ajuster()
retourner

fonction INSTRUCTION_COURANTE()
  && sélection, sinon l'instruction qui contient le curseur
  locale sel = ed:selection()
  si sel <> nul et rogner(sel) <> ""
    retourner rogner(sel)
  finsi
  locale texte = ed:texte()
  locale c = ed:curseur()
  locale lignes = decouper(texte, car(10))
  locale pos = 0
  pour i = 1 a c.ligne - 1
    pos += longueur(lignes[i]) + 1
  suivant
  pos += c.colonne
  locale l = DECOUPER_SQL(texte)
  locale choisie = nul
  pour chaque ins dans l
    si ins.debut <= pos + 1
      choisie = ins.sql
    finsi
  suivant
  si choisie = nul et #l > 0
    choisie = l[1].sql
  finsi
retourner choisie

procedure PROFILER
  locale s = INSTRUCTION_COURANTE()
  si s = nul ou non EST_REQUETE(s)
    STATUT("Profiler : placez le curseur dans une requête SELECT (ou sélectionnez-la).")
    retourner
  finsi
  PROFILER_SQL(s)
retourner

procedure PROFILER_SQL(s)
  globale dernierplan
  locale t0 = systeme.horloge()
  essayer
    locale r = requete("EXPLAIN (ANALYZE, FORMAT JSON) " + s)
    locale j = dejson(r[1].explain_value)
    locale duree = systeme.horloge() - t0
    && la racine porte les totaux ; son enfant EXPLAIN_ANALYZE contient le plan
    locale racine = j
    tantque racine.children <> nul et #racine.children = 1 et ;
            (racine.operator_type = nul ou racine.operator_type = "EXPLAIN_ANALYZE" ou racine.operator_type = "QUERY")
      racine = racine.children[1]
    fintantque
    locale ops = {}
    APLATIR_PLAN(racine, nul, 0, ops)
    locale total = 0
    pour chaque o dans ops
      total += o.temps
    suivant
    dernierplan = {sql = s, ops = ops, total = total, latence = j.latency, cpu = j.cpu_time, ;
                   memoire = j.system_peak_buffer_memory, temporaire = j.system_peak_temp_dir_size, ;
                   lues = j.cumulative_rows_scanned, quand = maintenant()}
    HISTORISER(s, duree, 0, vrai, "profil")
    AFFICHER_PLAN(dernierplan)
    vues.valeur = 3
    && expertise immédiate du plan
    ANALYSER_PLAN(dernierplan)
  capturer e
    ERREUR(e)
  finessayer
retourner

procedure APLATIR_PLAN(n, parent, profondeur, ops)
  locale id = "op" + (#ops + 1)
  locale info = {}
  si n.extra_info <> nul
    pour chaque k, v dans n.extra_info
      inserer(info, {clef = k, valeur = sisinon(type(v) = "table", joindre(v, ", "), chaine(v))})
    suivant
  finsi
  locale o = {id = id, parent = parent, nom = sisinon(n.operator_name = nul, n.operator_type, n.operator_name), ;
              type = n.operator_type, temps = sisinon(n.operator_timing = nul, 0, n.operator_timing), ;
              lignes = sisinon(n.operator_cardinality = nul, 0, n.operator_cardinality), ;
              lues = sisinon(n.operator_rows_scanned = nul, 0, n.operator_rows_scanned), ;
              info = info, profondeur = profondeur, enfants = {}}
  inserer(ops, o)
  si n.children <> nul
    pour chaque enfant dans n.children
      inserer(o.enfants, APLATIR_PLAN_ID(enfant, id, profondeur + 1, ops))
    suivant
  finsi
retourner

fonction APLATIR_PLAN_ID(n, parent, profondeur, ops)
  locale avant = #ops
  APLATIR_PLAN(n, parent, profondeur, ops)
retourner ops[avant + 1].id

fonction INFO(o, clef)
  pour chaque i dans o.info
    si majuscule(i.clef) = majuscule(clef)
      retourner i.valeur
    finsi
  suivant
retourner nul

fonction COULEUR_OPERATEUR(t)
  faire cas
  cas contient(t, "SCAN")
    retourner "#16A34A"
  cas contient(t, "JOIN") ou contient(t, "CROSS")
    retourner "#EA580C"
  cas contient(t, "AGGREGATE") ou contient(t, "GROUP")
    retourner "#7C3AED"
  cas contient(t, "ORDER") ou contient(t, "TOP_N") ou contient(t, "SORT")
    retourner "#DC2626"
  cas contient(t, "FILTER")
    retourner "#2563EB"
  cas contient(t, "WINDOW")
    retourner "#DB2777"
  fincas
retourner "#64748B"

procedure AFFICHER_PLAN(p)
  locale g = prof.graphe
  g:vider()
  NOUVELLE_TABLE_PROFIL()
  locale tot = max(p.total, 0.000001)
  pour chaque o dans p.ops
    locale lignes = {{texte = "temps", detail = arrondi(o.temps * 1000, 2) + " ms (" + arrondi(o.temps * 100 / tot) + " %)"}, ;
                     {texte = "lignes", detail = LIGNES_TEXTE(o.lignes)}}
    si o.lues > 0
      inserer(lignes, {texte = "lues", detail = LIGNES_TEXTE(o.lues)})
    finsi
    pour chaque clef dans {"Table", "Join Type", "Conditions", "Filters", "Aggregates", "Groups", "Order By", "Estimated Cardinality"}
      locale v = INFO(o, clef)
      si v <> nul et v <> ""
        inserer(lignes, {texte = minuscule(clef), detail = gauche(remplacertexte(v, car(10), " "), 38)})
      finsi
    suivant
    g:noeud{id = o.id, titre = o.nom, couleur = COULEUR_OPERATEUR(o.type), lignes = lignes, ;
            pastille = arrondi(o.temps * 100 / tot) + " %", jauge = o.temps / tot}
    si o.parent <> nul
      && le flux de données monte des enfants vers le parent
      g:lien{de = o.id, a = o.parent, fleche = vrai, libelle = LIGNES_TEXTE(o.lignes)}
    finsi
    prof.table:ajouterligne(espace(o.profondeur * 2) + o.nom, arrondi(o.temps * 1000, 2), ;
                            arrondi(o.temps * 100 / tot), LIGNES_TEXTE(o.lignes), sisinon(o.lues > 0, LIGNES_TEXTE(o.lues), ""))
  suivant
  g:disposer("bas")
  g:ajuster()
  && plan profond : lisible plutôt qu'entier, centré sur l'opérateur le plus coûteux
  locale z = g:zoom(1)
  si z < 60
    g:zoom(60 / z)
  finsi
  && histogramme : les 8 opérateurs les plus coûteux
  locale tri = copier(p.ops)
  trier(tri, @PLUS_LENT)
  pour i = 1 a min(8, #tri)
    prof.histo:ajouterdonnee(1, i, arrondi(tri[i].temps * 1000, 2))
    prof.histo:libellecategorie(i, gauche(tri[i].nom, 14))
  suivant
  prof.histo:libelleserie(1, "ms")
  si #tri > 0 et z < 60
    g:selectionner(tri[1].id)
  finsi
  prof.resume.libelle = "Latence " + arrondi(p.latence * 1000, 1) + " ms · CPU " + arrondi(p.cpu * 1000, 1) + ;
                        " ms · mémoire " + OCTETS(p.memoire) + " · lignes lues " + LIGNES_TEXTE(p.lues) + ;
                        sisinon(p.temporaire > 0, " · disque temporaire " + OCTETS(p.temporaire), "")
retourner

fonction PLUS_LENT(a, b)
retourner a.temps > b.temps

fonction OCTETS(n)
  si n = nul
    retourner "?"
  finsi
  si n >= 1073741824
    retourner arrondi(n / 1073741824, 1) + " Gio"
  sinonsi n >= 1048576
    retourner arrondi(n / 1048576, 1) + " Mio"
  sinonsi n >= 1024
    retourner arrondi(n / 1024) + " Kio"
  finsi
retourner n + " o"

procedure PROFIL_CHOIX(ev)
  si dernierplan = nul
    retourner
  finsi
  pour chaque o dans dernierplan.ops
    si o.id = ev.texte
      locale l = {}
      pour chaque i dans o.info
        inserer(l, i.clef + " : " + remplacertexte(i.valeur, car(10), " "))
      suivant
      STATUT(o.nom + " - " + arrondi(o.temps * 1000, 2) + " ms, " + LIGNES_TEXTE(o.lignes) + " lignes" + ;
             sisinon(#l > 0, " - " + gauche(joindre(l, " · "), 220), ""))
    finsi
  suivant
retourner
