&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : planificateur (lot 2).
&&
&& Un travail exécute un pipeline, une requête SQL ou un script .sql du projet.
&& Déclencheurs : manuel, toutes les N minutes, chaque jour à HH:MM, ou après
&& d'autres travaux (chaînage). Dépendances : le travail attend que ses
&& prérequis aient réussi. Reprises : n nouvelles tentatives espacées de
&& `attente` secondes après un échec. Chaque exécution est journalisée
&& (projet.executions) et affichée dans un diagramme de Gantt horaire.
&& Une minuterie (ui.minuterie) examine les échéances toutes les 20 secondes
&& tant que le planificateur est démarré.

fonction TRAVAIL_VIDE()
retourner {nom = "", genre = "pipeline", cible = "", declencheur = "manuel", minutes = 60, heure = "02:00", ;
           apres = "", dependances = "", reprises = 0, attente = 60, actif = vrai, etat = "", ;
           dernier = nul, tentative = 0, reprise_a = nul}

fonction TRAVAIL_NOMME(nom)
  pour chaque t dans projet.travaux
    si minuscule(t.nom) = minuscule(rogner(nom))
      retourner t
    finsi
  suivant
retourner nul

fonction NOMS_LISTE(s)
  locale l = {}
  si s = nul
    retourner l
  finsi
  pour chaque x dans decouper(chaine(s), ",")
    si rogner(x) <> ""
      inserer(l, rogner(x))
    finsi
  suivant
retourner l

fonction MINUIT(t)
  locale d = systeme.date("*t", t)
retourner systeme.temps({annee = d.annee, mois = d.mois, jour = d.jour, heure = 0, minute = 0, seconde = 0})

fonction PROCHAINE(t)
  && prochaine échéance (secondes Unix) ou nul
  si t.reprise_a <> nul
    retourner t.reprise_a
  finsi
  si non t.actif
    retourner nul
  finsi
  locale maintenant_ = systeme.temps()
  faire cas
  cas t.declencheur = "intervalle"
    locale base = sisinon(t.dernier = nul, planif.depart, t.dernier)
    retourner base + max(1, valeur(chaine(t.minutes))) * 60
  cas t.declencheur = "quotidien"
    locale hm = decouper(chaine(t.heure), ":")
    locale h = valeur(hm[1])
    locale m = sisinon(#hm >= 2, valeur(hm[2]), 0)
    locale cible = MINUIT(maintenant_) + h * 3600 + m * 60
    si t.dernier <> nul et t.dernier >= cible
      cible += 86400
    sinonsi t.dernier = nul et cible < planif.depart
      cible += 86400
    finsi
    retourner cible
  fincas
retourner nul

fonction DECLENCHEUR_TEXTE(t)
  faire cas
  cas t.declencheur = "intervalle"
    retourner "toutes les " + t.minutes + " min"
  cas t.declencheur = "quotidien"
    retourner "chaque jour à " + t.heure
  cas t.declencheur = "apres"
    retourner "après " + t.apres
  fincas
retourner "manuel"

fonction HEURE_DE(t)
  si t = nul
    retourner ""
  finsi
  si MINUIT(t) = MINUIT(systeme.temps())
    retourner systeme.date("%H:%M:%S", t)
  finsi
retourner systeme.date("%d/%m %H:%M", t)

&&
&& Exécution
&&

fonction EXECUTER_SCRIPT_SQL(texte, ses)
  locale n = 0
  pour chaque ins dans DECOUPER_SQL(texte)
    si ses = nul
      requete(ins.sql)
    sinon
      ses:requete(ins.sql)
    finsi
    n += 1
  suivant
retourner n

fonction EXECUTER_CIBLE_TRAVAIL(t, ses)
  && {ok, message}
  essayer
    faire cas
    cas t.genre = "pipeline"
      locale p = PIPELINE_NOMME(t.cible)
      si p = nul
        retourner {ok = faux, message = "pipeline « " + t.cible + " » introuvable"}
      finsi
      retourner EXECUTER_PIPELINE(p, ses)
    cas t.genre = "script"
      locale chemin = t.cible
      si non commencepar(chemin, "/") et non contient(chemin, ":")
        chemin = fichier.joindre(dossier, chemin)
      finsi
      si non fichier.existe(chemin)
        retourner {ok = faux, message = "script « " + t.cible + " » introuvable"}
      finsi
      locale n = EXECUTER_SCRIPT_SQL(fichier.lire(chemin), ses)
      retourner {ok = vrai, message = n + " instruction(s)"}
    fincas
    locale n = EXECUTER_SCRIPT_SQL(t.cible, ses)
    retourner {ok = vrai, message = n + " instruction(s)"}
  capturer e
    retourner {ok = faux, message = e}
  finessayer
retourner nul

procedure LANCER_TRAVAIL(t, motif)
  && un travail ne s'exécute qu'une fois à la fois (la minuterie continue pendant l'exécution)
  si t.etat = "en cours"
    JOURNAL("Planificateur : « " + t.nom + " » est déjà en cours (" + motif + " ignoré)")
    retourner
  finsi
  && dépendances : chacune doit avoir réussi sa dernière exécution
  pour chaque d dans NOMS_LISTE(t.dependances)
    locale x = TRAVAIL_NOMME(d)
    si x = nul ou x.etat <> "ok"
      t.etat = "bloqué"
      t.dernier = systeme.temps()
      JOURNAL("Planificateur : « " + t.nom + " » attend « " + d + " » (" + sisinon(x = nul, "inconnu", sisinon(x.etat = "", "jamais exécuté", x.etat)) + ")")
      PLANIF_ACTUALISER()
      retourner
    finsi
  suivant
  locale debut = systeme.temps()
  locale h0 = systeme.horloge()
  t.etat = "en cours"
  PLANIF_ACTUALISER()
  && session propre : le travail s'exécute en même temps que les requêtes, interruptible
  locale ses = sessionsql()
  locale tache = OPERATION_DEBUT("travail « " + t.nom + " »", ses)
  locale r = EXECUTER_CIBLE_TRAVAIL(t, ses)
  si tache.arret
    r = {ok = faux, message = "arrêté par l'utilisateur"}
  finsi
  OPERATION_FIN(tache)
  ses:fermer()
  locale duree = systeme.horloge() - h0
  t.dernier = debut
  locale tentative = sisinon(t.tentative = nul, 0, t.tentative) + 1
  inserer(projet.executions, {travail = t.nom, debut = debut, fin = debut + duree, duree = duree, ok = r.ok, ;
                              message = r.message, tentative = tentative, motif = motif})
  tantque #projet.executions > 500
    retirer(projet.executions, 1)
  fintantque
  si r.ok
    t.etat = "ok"
    t.tentative = 0
    t.reprise_a = nul
    JOURNAL("Planificateur : « " + t.nom + " » réussi en " + MS(duree) + " — " + r.message)
  sinon
    t.etat = "échec"
    si tentative <= max(0, valeur(chaine(t.reprises)))
      t.tentative = tentative
      t.reprise_a = debut + max(1, valeur(chaine(t.attente)))
      JOURNAL("Planificateur : « " + t.nom + " » en échec (" + r.message + "), nouvelle tentative à " + HEURE_DE(t.reprise_a))
    sinon
      t.tentative = 0
      t.reprise_a = nul
      ERREUR("Planificateur : « " + t.nom + " » en échec — " + r.message)
    finsi
  finsi
  ENREGISTRER_PROJET()
  PLANIF_ACTUALISER()
  && chaînage : travaux déclenchés « après » celui-ci, dont tous les prédécesseurs ont réussi
  si r.ok
    pour chaque x dans projet.travaux
      si x.actif et x.declencheur = "apres" et contient(NOMS_MIN(x.apres), minuscule(t.nom))
        locale pret = vrai
        pour chaque a dans NOMS_LISTE(x.apres)
          locale y = TRAVAIL_NOMME(a)
          si y = nul ou y.etat <> "ok"
            pret = faux
          finsi
        suivant
        si pret
          LANCER_TRAVAIL(x, "après " + t.nom)
        finsi
      finsi
    suivant
  finsi
retourner

fonction NOMS_MIN(s)
  locale l = {}
  pour chaque x dans NOMS_LISTE(s)
    inserer(l, minuscule(x))
  suivant
retourner l

procedure PLANIF_TOP(ev)
  && minuterie : lance les travaux arrivés à échéance
  si non planif.actif ou dossier = ""
    retourner
  finsi
  locale n = systeme.temps()
  pour chaque t dans copier(projet.travaux)
    locale p = PROCHAINE(t)
    si p <> nul et p <= n et t.etat <> "en cours"
      LANCER_TRAVAIL(t, sisinon(t.reprise_a <> nul, "reprise", "planifié"))
    finsi
  suivant
retourner

&&
&& Interface
&&

procedure CONSTRUIRE_PLANIF(page)
  globale planif
  planif = {actif = faux, depart = systeme.temps(), dlg = nul, ctl = {}}
  locale haut = page:ajouter(ui.rangee())
  haut.ancrage = "haut"
  OUTIL(haut, "+ Travail", @PLANIF_NOUVEAU, "Nouveau travail planifié")
  OUTIL(haut, "Modifier", @PLANIF_MODIFIER, "Modifier le travail sélectionné")
  OUTIL(haut, "✕", @PLANIF_SUPPRIMER, "Supprimer le travail sélectionné")
  OUTIL(haut, "▶ Maintenant", @PLANIF_MAINTENANT, "Exécuter le travail sélectionné (et sa chaîne)")
  planif.bouton = OUTIL(haut, "Démarrer", @PLANIF_BASCULER, "Démarrer / arrêter le planificateur")
  OUTIL(haut, "Vider le journal", @PLANIF_VIDER, "Efface le journal des exécutions")
  planif.etat = haut:ajouter(ui.etiquette("Planificateur arrêté"))
  planif.etat.poids = 1
  locale sp = page:ajouter(ui.separateur{vertical = faux, position = 0.45})
  sp.ancrage = "centre"
  locale h = sp:ajouter(ui.separateur{vertical = vrai, position = 0.62})
  planif.ztab = h:ajouter(ui.panneau{disposition = "bordure", defilement = "masque"})
  planif.table = nul
  planif.dia = h:ajouter(ui.diagramme{modifiable = faux, direction = "droite"})
  planif.dia.surselection = @PLANIF_DIA_CHOIX
  planif.gantt = sp:ajouter(ui.gantt())
  planif.gantt:horaire(vrai)
  planif.gantt:largeurlibelles(190)
  planif.minuterie = ui.minuterie(20000, @PLANIF_TOP)
  PLANIF_TABLE()
retourner

procedure PLANIF_TABLE
  si planif.table <> nul
    planif.table:detruire()
  finsi
  planif.table = planif.ztab:ajouter(ui.tableau())
  planif.table.ancrage = "centre"
  planif.table:ajoutercolonne("Travail", 130)
  planif.table:ajoutercolonne("Exécute", 150)
  planif.table:ajoutercolonne("Déclencheur", 140)
  planif.table:ajoutercolonne("Dépend de", 100)
  planif.table:ajoutercolonne("Prochaine", 90)
  planif.table:ajoutercolonne("Dernière", 90)
  planif.table:ajoutercolonne("État", 80)
  planif.table.surdoubleclic = @PLANIF_MODIFIER
retourner

fonction COULEUR_ETAT(e)
  faire cas
  cas e = "ok"
    retourner "#16A34A"
  cas e = "échec"
    retourner "#DC2626"
  cas e = "bloqué"
    retourner "#F59E0B"
  cas e = "en cours"
    retourner "#2563EB"
  fincas
retourner "#64748B"

procedure PLANIF_ACTUALISER
  si planif = nul ou planif.table = nul
    retourner
  finsi
  locale sel = planif.table:selection()
  PLANIF_TABLE()
  pour chaque t dans projet.travaux
    locale cible = sisinon(t.genre = "sql", "SQL : " + gauche(RESUME(t.cible), 30), t.genre + " " + t.cible)
    planif.table:ajouterligne(t.nom + sisinon(t.actif, "", " (inactif)"), cible, DECLENCHEUR_TEXTE(t), ;
                              t.dependances, HEURE_DE(PROCHAINE(t)), HEURE_DE(t.dernier), ;
                              sisinon(t.etat = "", "—", t.etat) + sisinon(t.reprise_a <> nul, " ↻", ""))
  suivant
  si sel <> nul et sel >= 1 et sel <= #projet.travaux
    planif.table:selectionner(sel)
  finsi
  && graphe des dépendances et des chaînages
  locale d = planif.dia
  d:vider()
  pour chaque t dans projet.travaux
    d:noeud{id = t.nom, titre = t.nom, soustitre = DECLENCHEUR_TEXTE(t), forme = "boite", couleur = COULEUR_ETAT(t.etat), ;
            pastille = sisinon(t.etat = "", "", t.etat)}
  suivant
  pour chaque t dans projet.travaux
    pour chaque a dans NOMS_LISTE(t.apres)
      si TRAVAIL_NOMME(a) <> nul et t.declencheur = "apres"
        d:lien{de = TRAVAIL_NOMME(a).nom, a = t.nom, couleur = "#2563EB", libelle = "puis"}
      finsi
    suivant
    pour chaque a dans NOMS_LISTE(t.dependances)
      si TRAVAIL_NOMME(a) <> nul
        d:lien{de = TRAVAIL_NOMME(a).nom, a = t.nom, pointille = vrai, couleur = "#F59E0B", libelle = "requiert"}
      finsi
    suivant
  suivant
  d:disposer("droite")
  d:ajuster()
  && Gantt : les 40 dernières exécutions et les échéances à venir
  locale g = planif.gantt
  g:vider()
  locale minuit = MINUIT(systeme.temps())
  locale debut = max(1, #projet.executions - 39)
  pour i = debut a #projet.executions
    locale x = projet.executions[i]
    locale coul = sisinon(x.ok, "#16A34A", "#DC2626")
    locale duree_h = max(x.duree / 3600, 1 / 3600)
    g:ajoutertache(x.travail + "  " + systeme.date("%H:%M:%S", x.debut), (x.debut - minuit) / 3600, duree_h, 1, coul, ;
                   sisinon(x.ok, "", "échec ") + MS(x.duree) + sisinon(x.tentative > 1, " · tentative " + x.tentative, "") + ;
                   sisinon(x.motif = nul, "", " · " + x.motif))
  suivant
  pour chaque t dans projet.travaux
    locale p = PROCHAINE(t)
    si p <> nul et p - systeme.temps() < 6 * 3600
      g:ajoutertache(t.nom + "  (prévu)", (p - minuit) / 3600, 1 / 60, 0, "#94A3B8", "prévu " + HEURE_DE(p))
    finsi
  suivant
  planif.etat.libelle = sisinon(planif.actif, "Planificateur démarré", "Planificateur arrêté") + " · " + ;
                        #projet.travaux + " travail(aux) · " + #projet.executions + " exécution(s) journalisée(s)"
retourner

procedure PLANIF_CHARGER
  planif.depart = systeme.temps()
  planif.actif = projet.planificateur = vrai
  planif.bouton.libelle = sisinon(planif.actif, "Arrêter", "Démarrer")
  && un travail « en cours » à l'enregistrement a été interrompu
  pour chaque t dans projet.travaux
    si t.etat = "en cours"
      t.etat = "échec"
    finsi
  suivant
  PLANIF_ACTUALISER()
retourner

procedure PLANIF_BASCULER(ev)
  planif.actif = non planif.actif
  projet.planificateur = planif.actif
  planif.depart = systeme.temps()
  planif.bouton.libelle = sisinon(planif.actif, "Arrêter", "Démarrer")
  ENREGISTRER_PROJET()
  PLANIF_ACTUALISER()
  si planif.actif
    PLANIF_TOP(nul)
  finsi
retourner

procedure PLANIF_VIDER(ev)
  si ui.confirmer("Effacer le journal des " + #projet.executions + " exécution(s) ?")
    projet.executions = {}
    ENREGISTRER_PROJET()
    PLANIF_ACTUALISER()
  finsi
retourner

fonction TRAVAIL_SELECTIONNE()
  locale i = planif.table:selection()
  si i = nul ou i < 1 ou i > #projet.travaux
    retourner nul
  finsi
retourner projet.travaux[i]

procedure PLANIF_DIA_CHOIX(ev)
  pour i = 1 a #projet.travaux
    si projet.travaux[i].nom = ev.texte
      planif.table:selectionner(i)
    finsi
  suivant
retourner

procedure PLANIF_MAINTENANT(ev)
  locale t = TRAVAIL_SELECTIONNE()
  si t = nul
    STATUT("Sélectionnez un travail.")
    retourner
  finsi
  LANCER_TRAVAIL(t, "manuel")
retourner

procedure PLANIF_SUPPRIMER(ev)
  locale t = TRAVAIL_SELECTIONNE()
  si t = nul
    retourner
  finsi
  si non ui.confirmer("Supprimer le travail « " + t.nom + " » ?")
    retourner
  finsi
  locale l = {}
  pour chaque x dans projet.travaux
    si x <> t
      inserer(l, x)
    finsi
  suivant
  projet.travaux = l
  ENREGISTRER_PROJET()
  PLANIF_ACTUALISER()
retourner

procedure PLANIF_NOUVEAU(ev)
  TRAVAIL_DIALOGUE(nul)
retourner

procedure PLANIF_MODIFIER(ev)
  locale t = TRAVAIL_SELECTIONNE()
  si t <> nul
    TRAVAIL_DIALOGUE(t)
  finsi
retourner

&&
&& Boîte « travail »
&&

fonction GENRES_TRAVAIL()
retourner {{genre = "pipeline", libelle = "Pipeline"}, {genre = "sql", libelle = "Requête SQL"}, ;
           {genre = "script", libelle = "Script .sql du projet"}}

fonction DECLENCHEURS()
retourner {{genre = "manuel", libelle = "Manuel"}, {genre = "intervalle", libelle = "Toutes les N minutes"}, ;
           {genre = "quotidien", libelle = "Chaque jour à HH:MM"}, {genre = "apres", libelle = "Après d'autres travaux"}}

procedure TRAVAIL_DIALOGUE(t)
  si planif.dlg <> nul
    retourner
  finsi
  locale x = sisinon(t = nul, TRAVAIL_VIDE(), t)
  planif.edition = t
  locale c = {}
  planif.ctl = c
  planif.dlg = ui.fenetre{titre = sisinon(t = nul, "Nouveau travail", "Travail « " + x.nom + " »"), ;
                          largeur = 680, hauteur = 840, disposition = "bordure", sombre = reglages.sombre}
  planif.dlg.surfermeture = @TRAVAIL_FERMETURE
  locale g = planif.dlg:ajouter(ui.cadre("Travail", "grille"))
  g.ancrage = "haut"
  g:ajouter(ui.etiquette("Nom"))
  c.nom = g:ajouter(ui.saisie{texte = x.nom, indication = "chargement nocturne"})
  g:ajouter(ui.etiquette("Exécute"))
  c.genre = g:ajouter(ui.combo())
  pour i = 1 a #GENRES_TRAVAIL()
    c.genre:ajouter(GENRES_TRAVAIL()[i].libelle)
    si GENRES_TRAVAIL()[i].genre = x.genre
      c.genre:selectionner(i)
    finsi
  suivant
  g:ajouter(ui.etiquette("Choisir"))
  c.choix = g:ajouter(ui.combo())
  c.choix.surselection = @TRAVAIL_CHOIX
  c.genre.surselection = @TRAVAIL_GENRE
  g:ajouter(ui.etiquette("Déclencheur"))
  c.decl = g:ajouter(ui.combo())
  pour i = 1 a #DECLENCHEURS()
    c.decl:ajouter(DECLENCHEURS()[i].libelle)
    si DECLENCHEURS()[i].genre = x.declencheur
      c.decl:selectionner(i)
    finsi
  suivant
  g:ajouter(ui.etiquette("Minutes (intervalle)"))
  c.minutes = g:ajouter(ui.saisie{texte = chaine(x.minutes)})
  g:ajouter(ui.etiquette("Heure (quotidien)"))
  c.heure = g:ajouter(ui.saisie{texte = chaine(x.heure), indication = "02:00"})
  g:ajouter(ui.etiquette("Après (travaux, séparés par des virgules)"))
  c.apres = g:ajouter(ui.saisie{texte = x.apres})
  g:ajouter(ui.etiquette("Dépend de (doivent avoir réussi)"))
  c.dependances = g:ajouter(ui.saisie{texte = x.dependances})
  g:ajouter(ui.etiquette("Reprises après échec"))
  c.reprises = g:ajouter(ui.saisie{texte = chaine(x.reprises)})
  g:ajouter(ui.etiquette("Attente entre reprises (s)"))
  c.attente = g:ajouter(ui.saisie{texte = chaine(x.attente)})
  g:ajouter(ui.etiquette("Actif"))
  c.actif = g:ajouter(ui.cases("planifié"))
  c.actif:cocher(1, x.actif)
  locale bas_ = planif.dlg:ajouter(ui.rangee())
  bas_.ancrage = "bas"
  c.statut = bas_:ajouter(ui.etiquette(""))
  c.statut.poids = 1
  locale be = bas_:ajouter(ui.bouton("Enregistrer", {defaut = vrai}))
  be.surclic = @TRAVAIL_ENREGISTRER
  locale ba = bas_:ajouter(ui.bouton("Annuler", {annuler = vrai}))
  ba.surclic = @TRAVAIL_ANNULER
  locale centre = planif.dlg:ajouter(ui.colonne())
  centre.ancrage = "centre"
  centre:ajouter(ui.etiquette("Cible : nom du pipeline, texte SQL ou chemin du script"))
  c.cible = centre:ajouter(ui.editeur{minicarte = faux, taille = 12})
  c.cible.poids = 1
  c.cible:nouveau("cible")
  c.cible:langage("sql")
  c.cible:fixertexte(x.cible)
  TRAVAIL_GENRE(nul)
  c.nom:focus()
retourner

fonction GENRE_CHOISI()
  locale i = planif.ctl.genre:selection()
retourner GENRES_TRAVAIL()[max(1, sisinon(i = nul, 1, i))].genre

procedure TRAVAIL_GENRE(ev)
  && propositions selon le genre : pipelines du projet, scripts .sql, modèles de requêtes
  locale c = planif.ctl
  c.choix:vider()
  c.propositions = {}
  locale g = GENRE_CHOISI()
  si g = "pipeline"
    pour chaque p dans projet.pipelines
      c.choix:ajouter(p.nom)
      inserer(c.propositions, p.nom)
    suivant
  sinonsi g = "script"
    pour chaque f dans fichier.liste(dossier, faux)
      si minuscule(fichier.extension(f)) = ".sql"
        c.choix:ajouter(f)
        inserer(c.propositions, f)
      finsi
    suivant
  sinon
    c.choix:ajouter("Rafraîchir une table d'agrégats")
    inserer(c.propositions, "CREATE OR REPLACE TABLE agregats AS" + car(10) + "SELECT /* ... */ count(*) AS nb FROM ma_table GROUP BY ALL;")
    c.choix:ajouter("Exporter en Parquet")
    inserer(c.propositions, "COPY ma_table TO 'export.parquet' (FORMAT parquet);")
    c.choix:ajouter("Contrôle de qualité")
    inserer(c.propositions, "SELECT CASE WHEN count(*) = 0 THEN error('table vide') END FROM ma_table;")
  finsi
retourner

procedure TRAVAIL_CHOIX(ev)
  locale c = planif.ctl
  locale i = c.choix:selection()
  si i >= 1 et i <= #c.propositions
    c.cible:fixertexte(c.propositions[i])
    si rogner(c.nom.valeur) = "" et GENRE_CHOISI() <> "sql"
      c.nom.valeur = c.propositions[i]
    finsi
  finsi
retourner

procedure TRAVAIL_ENREGISTRER(ev)
  locale c = planif.ctl
  locale nom = rogner(c.nom.valeur)
  si nom = ""
    c.statut.libelle = "Donnez un nom au travail."
    retourner
  finsi
  locale autre = TRAVAIL_NOMME(nom)
  si autre <> nul et autre <> planif.edition
    c.statut.libelle = "Un travail « " + nom + " » existe déjà."
    retourner
  finsi
  locale t = sisinon(planif.edition = nul, TRAVAIL_VIDE(), planif.edition)
  t.nom = nom
  t.genre = GENRE_CHOISI()
  t.cible = rogner(c.cible:texte())
  locale k = c.decl:selection()
  t.declencheur = DECLENCHEURS()[max(1, sisinon(k = nul, 1, k))].genre
  t.minutes = max(1, valeur(sisinon(c.minutes.valeur = "", "60", c.minutes.valeur)))
  t.heure = rogner(c.heure.valeur)
  t.apres = rogner(c.apres.valeur)
  t.dependances = rogner(c.dependances.valeur)
  t.reprises = max(0, valeur(sisinon(c.reprises.valeur = "", "0", c.reprises.valeur)))
  t.attente = max(1, valeur(sisinon(c.attente.valeur = "", "60", c.attente.valeur)))
  t.actif = c.actif:coche(1)
  si t.declencheur = "apres" et #NOMS_LISTE(t.apres) = 0
    c.statut.libelle = "Indiquez les travaux après lesquels exécuter celui-ci."
    retourner
  finsi
  si t.cible = ""
    c.statut.libelle = "Indiquez ce que le travail exécute."
    retourner
  finsi
  si planif.edition = nul
    inserer(projet.travaux, t)
  finsi
  ENREGISTRER_PROJET()
  PLANIF_ACTUALISER()
  planif.dlg:fermer()
retourner

procedure TRAVAIL_ANNULER(ev)
  planif.dlg:fermer()
retourner

procedure TRAVAIL_FERMETURE(ev)
  planif.dlg = nul
retourner
