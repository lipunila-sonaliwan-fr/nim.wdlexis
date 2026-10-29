&& CC BY-NC-SA 4.0 - HyperLexis, atelier de piles pour Lexis+ (wdlexis+)
&& hl_scripts.prg : scripts (éditeur de code natif ui.editeur), analyse pendant
&& la frappe (lexis.verifier), procédures des événements.

fonction HL_FICHIERS_CODE()
  && fichiers .prg de la pile écrits à la main : scripts et bibliothèques
  && (ni les formulaires, ni les fichiers écrits par HyperLexis)
  locale l = {}
  si hl.dossier = ""
    retourner l
  finsi
  pour chaque nom dans fichier.liste(hl.dossier, vrai)
    locale n = minuscule(nom)
    si finitpar(n, ".prg") et non commencepar(n, ".") et non ("/." $ n) et non commencepar(n, "distribution/") ;
       et non commencepar(fichier.nom(n), "form_") et non contient(HL_FICHIERS_GENERES(), n)
      inserer(l, HL_P(nom))
    finsi
  suivant
retourner l
finfonction

fonction HL_FICHIERS_GENERES()
retourner {"principal.prg", "pile.prg", "pile_donnees.prg", "pile_moteur.prg"}
finfonction

fonction HL_TEXTE_DE(p)
  && document ouvert dans l'éditeur (tel qu'à l'écran), sinon le fichier
  locale uid = hlc.ed:chercherdocument(p)
  si uid <> nul
    retourner hlc.ed:texte(uid)
  finsi
retourner HL_LIRE(p)
finfonction

fonction HL_GESTIONNAIRES()
  && procédures à un paramètre (ev) : candidates aux événements
  locale l = {}
  locale vus = {}
  locale premiers = {}
  si hl.modele <> ""
    premiers = {HL_SCRIPT(hl.modele)}
  finsi
  pour chaque p dans premiers
    pour chaque n dans HL_PROCEDURES_DE(HL_TEXTE_DE(p), vrai)
      si vus[majuscule(n)] = nul
        vus[majuscule(n)] = vrai
        inserer(l, n)
      finsi
    suivant
  suivant
  pour chaque p dans HL_FICHIERS_CODE()
    pour chaque n dans HL_PROCEDURES_DE(HL_TEXTE_DE(p), vrai)
      si vus[majuscule(n)] = nul et non commencepar(majuscule(n), "SUR_")
        vus[majuscule(n)] = vrai
        inserer(l, n)
      finsi
    suivant
  suivant
retourner l
finfonction

fonction HL_TOUTES_PROCEDURES()
  locale vus = {}
  pour chaque p dans HL_FICHIERS_CODE()
    pour chaque n dans HL_PROCEDURES_DE(HL_TEXTE_DE(p), faux)
      vus[majuscule(n)] = p
    suivant
  suivant
retourner vus
finfonction

&&
&& Ouverture des scripts
&&

procedure HL_OUVRIR_SCRIPT(p)
  si non fichier.existe(p)
    retourner
  finsi
  hlc.ed:ouvrir(p)
  HL_ANALYSER(vrai)
finprocedure

procedure HL_SCRIPT_MODELE
  si hl.modele = ""
    locale c = HL_CARTE()
    si c = nul
      retourner
    finsi
    HL_OUVRIR_SCRIPT(HL_SCRIPT(c.modele))
  sinon
    HL_OUVRIR_SCRIPT(HL_SCRIPT(hl.modele))
  finsi
  HL_ONGLET("script")
finprocedure

procedure HL_SCRIPT_PILE
  si hl.dossier = ""
    retourner
  finsi
  locale p = HL_P("script_pile.prg")
  si non fichier.existe(p)
    fichier.ecrire(p, HL_TEXTE_SCRIPT_PILE())
  finsi
  HL_OUVRIR_SCRIPT(p)
  HL_ONGLET("script")
finprocedure

procedure HL_ENREGISTRER_SCRIPTS
  pour chaque d dans hlc.ed:documents()
    si d.modifie et d.chemin <> ""
      hlc.ed:enregistrer(nul, d.uid)
    finsi
  suivant
finprocedure

procedure HL_ALLER_PROCEDURE(p, nom)
  && ouvre le script et place le curseur dans la procédure
  HL_OUVRIR_SCRIPT(p)
  locale uid = hlc.ed:chercherdocument(p)
  locale l = HL_LIGNE_PROCEDURE(hlc.ed:texte(uid), nom)
  si l > 0
    hlc.ed:aller(l + 1, 1, uid)
  finsi
  HL_ONGLET("script")
  hlc.ed:focus()
finprocedure

&&
&& Événements de l'inspecteur
&&

procedure HL_EVENEMENT(ev)
  locale l = HL_LIGNE_DE(hl.evts, ev.id)
  si l = nul ou hl.canevas = nul
    retourner
  finsi
  locale i = nombre(l.ctl.valeur)
  si i = nul ou i < 1 ou i > #l.choix
    retourner
  finsi
  locale choix = l.choix[i]
  locale actuel = ""
  pour chaque e dans hl.canevas:evenements(l.uid)
    si e.nom = l.evenement
      actuel = e.procedure
    finsi
  suivant
  faire cas
  cas i = 1
    si actuel = ""
      retourner
    finsi
    hl.canevas:associer(l.evenement, "", l.uid)
    HL_ENREGISTRER_DESSIN()
    HL_INSPECTEUR()
    HL_ETAT(l.evenement + " : association retirée")
  cas i = #l.choix
    locale h = HL_NOUVELLE_PROCEDURE(l.evenement, l.uid, nul)
    hl.canevas:associer(l.evenement, h, l.uid)
    HL_ENREGISTRER_DESSIN()
    HL_INSPECTEUR()
    HL_ETAT("Procédure " + h + " créée dans script_" + hl.modele + ".prg")
  autrement
    si majuscule(choix) = majuscule(actuel)
      retourner
    finsi
    hl.canevas:associer(l.evenement, choix, l.uid)
    HL_ENREGISTRER_DESSIN()
    HL_INSPECTEUR()
    HL_ETAT(l.evenement + " → " + choix)
  fincas
finprocedure

procedure HL_VOIR_GESTIONNAIRE(ev)
  locale l = HL_LIGNE_DE(hl.evts, ev.id)
  si l = nul
    retourner
  finsi
  locale fic = HL_TOUTES_PROCEDURES()[majuscule(l.procedure)]
  si fic = nul
    HL_ETAT("Procédure introuvable : " + l.procedure + " (le mode Exécution propose de la créer)")
    retourner
  finsi
  HL_ALLER_PROCEDURE(fic, l.procedure)
finprocedure

fonction HL_EVENEMENT_PRINCIPAL(genre)
  faire cas
  cas genre = "fenetre"
    retourner "surouverture"
  cas contient({"saisie", "cases", "radio", "compteur", "curseur", "plage", "notation", "ascenseur", "calendrier", ;
                "separateur", "onglets"}, genre)
    retourner "surchangement"
  cas contient({"combo", "liste", "arbre", "tableau", "grille", "kanban", "markdown", "barremenu"}, genre)
    retourner "surselection"
  fincas
retourner "surclic"
finfonction

procedure HL_MODIFIER_SCRIPT
  && LiveCode « Edit Script » : la procédure de l'événement principal de l'objet
  si hl.canevas = nul
    retourner
  finsi
  locale el = hl.canevas:element()
  locale evn = HL_EVENEMENT_PRINCIPAL(el.genre)
  locale actuel = ""
  locale existe = faux
  pour chaque e dans hl.canevas:evenements(el.uid)
    si e.nom = evn
      existe = vrai
      actuel = e.procedure
    finsi
  suivant
  si non existe
    && genre sans cet événement : le premier proposé
    locale evs = hl.canevas:evenements(el.uid)
    si #evs = 0
      retourner
    finsi
    evn = evs[1].nom
    actuel = evs[1].procedure
  finsi
  si actuel <> ""
    locale fic = HL_TOUTES_PROCEDURES()[majuscule(actuel)]
    si fic <> nul
      HL_ALLER_PROCEDURE(fic, actuel)
      retourner
    finsi
  finsi
  locale h = HL_NOUVELLE_PROCEDURE(evn, el.uid, actuel)
  hl.canevas:associer(evn, h, el.uid)
  HL_ENREGISTRER_DESSIN()
  HL_INSPECTEUR()
  HL_ETAT("Procédure " + h + " (" + evn + " de " + el.nom + ") dans script_" + hl.modele + ".prg")
finprocedure

fonction HL_NOUVELLE_PROCEDURE(evenement, uid, nomvoulu)
  && écrit « procedure <MODELE>_<OBJET>_<EVENEMENT>(ev) » dans le script du modèle
  locale el = hl.canevas:element(uid)
  locale noeud = sisinon(el.racine, "carte", el.nom)
  locale base = nomvoulu
  si base = nul ou base = ""
    base = sisinon(el.racine, majuscule(hl.modele + "_" + souschaine(evenement, 4)), ;
                   majuscule(hl.modele + "_" + el.nom + "_" + souschaine(evenement, 4)))
  finsi
  locale existantes = HL_TOUTES_PROCEDURES()
  locale h = base
  locale k = 2
  si nomvoulu = nul ou nomvoulu = ""
    tantque existantes[majuscule(h)] <> nul
      h = base + k
      k += 1
    fintantque
  finsi
  locale p = HL_SCRIPT(hl.modele)
  si non fichier.existe(p)
    fichier.ecrire(p, HL_TEXTE_SCRIPT_MODELE(hl.modele))
  finsi
  HL_OUVRIR_SCRIPT(p)
  locale doc = hlc.ed:chercherdocument(p)
  locale corps = HL_CORPS_EXEMPLE(el, evenement)
  locale r = HL_INSERER_PROCEDURE(hlc.ed:texte(doc), hl.modele, h, evenement, noeud, corps)
  hlc.ed:fixertexte(r.texte, doc)
  hlc.ed:enregistrer(nul, doc)
  hlc.ed:aller(r.ligne, 3, doc)
  HL_ONGLET("script")
  HL_ANALYSER(vrai)
  hlc.ed:focus()
retourner h
finfonction

fonction HL_CORPS_EXEMPLE(el, evenement)
  && une ligne commentée pour démarrer
  locale v = HL_VAR_FORMULAIRE(hl.modele)
  faire cas
  cas el.racine et evenement = "surouverture"
    retourner {"&& la carte " + Q() + Q() + " + CARTE_COURANTE() vient de s'afficher", ""}
  cas el.genre = "bouton"
    retourner {"&& CARTE_SUIVANTE()   ALLER_CARTE(" + Q() + "accueil" + Q() + ")   MESSAGE(" + Q() + "Bonjour" + Q() + ")", ""}
  cas el.genre = "saisie"
    retourner {"&& " + v + "." + el.nom + ".valeur : texte saisi", ""}
  fincas
retourner {""}
finfonction

&&
&& Analyse pendant la frappe et onglet Problèmes
&&

procedure HL_SCRIPT_MODIFIE(ev)
  HL_ANALYSER(faux)
finprocedure

procedure HL_ANALYSER(force)
  si hlc.ed:actif() < 0
    retourner
  finsi
  locale src = hlc.ed:texte()
  locale chemin = hlc.ed:chemin()
  locale cle = chemin + "|" + #src + "|" + hachage(src)
  si non force et cle = hl.analyse
    retourner
  finsi
  hl.analyse = cle
  locale pbs = {}
  essayer
    pbs = lexis.verifier(src, {nom = fichier.nom(chemin), projet = hl.dossier})
  capturer e
    pbs = {}
  finessayer
  hlc.ed:diagnostics(pbs)
  locale l = {}
  pour chaque p dans pbs
    inserer(l, {genre = p.genre, chemin = chemin, ligne = p.ligne, message = p.message})
  suivant
  HL_PROBLEMES(l)
finprocedure

procedure HL_PROBLEMES(l)
  hl.problemes = l
  hlc.tprob:vider()
  pour chaque p dans l
    hlc.tprob:ajouterligne(p.genre, fichier.nom(p.chemin), p.ligne, p.message)
  suivant
  locale n = 0
  pour chaque p dans l
    si p.genre = "erreur" ou p.genre = "exécution"
      n += 1
    finsi
  suivant
  hlc.pprob.titre = sisinon(#l = 0, "Problèmes", "Problèmes (" + #l + ")")
finprocedure

procedure HL_PROBLEME(ev)
  locale i = hlc.tprob:selection()
  si i = nul ou i < 1 ou i > #hl.problemes
    retourner
  finsi
  locale p = hl.problemes[i]
  si p.chemin <> "" et fichier.existe(p.chemin) et finitpar(minuscule(p.chemin), ".prg")
    hlc.ed:ouvrir(p.chemin)
    si p.ligne > 0
      hlc.ed:aller(p.ligne, 1)
    finsi
    HL_ONGLET("script")
  finsi
finprocedure

procedure HL_SIGNAL_EDITEUR(ev)
  locale t = ev.texte
  si t = nul
    retourner
  finsi
  faire cas
  cas t = "cmd:save"
    HL_ENREGISTRER(vrai)
  cas t = "cmd:run"
    HL_BASCULER_MODE()
  cas commencepar(t, "pos:")
    locale p = decouper(t, ":")
    hlc.lblmode.libelle = HL_LIBELLE_MODE() + "   ·   Ln " + p[2] + ", Col " + p[3]
  cas commencepar(t, "doc:")
    HL_ANALYSER(vrai)
  fincas
finprocedure
