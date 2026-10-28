&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& hl_conception.prg : mode Conception.
&&
&& Le canevas et la palette d'outils sont ceux du concepteur de formulaires de
&& wdlexis+ (ui.concepteur, ui.palette : aperçu réel, glisser-déposer,
&& poignées, repères magenta) ; la carte est un formulaire en disposition
&& absolue. Ici : la navigation, les objets de la carte et l'inspecteur des
&& propriétés, du contenu et des événements.

&&
&& Carte affichée en conception
&&

procedure HL_ALLER_CONCEPTION(i)
  si hl.def = nul ou #hl.def.cartes = 0
    retourner
  finsi
  si i < 1
    i = 1
  finsi
  si i > #hl.def.cartes
    i = #hl.def.cartes
  finsi
  hl.index = i
  locale c = HL_CARTE()
  HL_AFFICHER_MODELE(c.modele)
  HL_MAJ_CARTES()
  HL_ARBRE()
  HL_INSPECTEUR()
  HL_MAJ_MODE()
  HL_ONGLET("interface")
finprocedure

procedure HL_ALLER(cible)
  && navigation commune aux deux modes
  si hl.def = nul
    retourner
  finsi
  si hl.mode = "execution" et MOTEUR_ACTIF()
    ALLER_CARTE(cible)
    retourner
  finsi
  locale n = #hl.def.cartes
  locale i = hl.index
  faire cas
  cas cible = "suivante"
    i = sisinon(i >= n, 1, i + 1)
  cas cible = "precedente"
    i = sisinon(i <= 1, n, i - 1)
  cas cible = "premiere"
    i = 1
  cas cible = "derniere"
    i = n
  autrement
    i = cible
  fincas
  HL_ALLER_CONCEPTION(i)
finprocedure

procedure HL_NAV_PREMIERE
  HL_ALLER("premiere")
finprocedure

procedure HL_NAV_PRECEDENTE
  HL_ALLER("precedente")
finprocedure

procedure HL_NAV_SUIVANTE
  HL_ALLER("suivante")
finprocedure

procedure HL_NAV_DERNIERE
  HL_ALLER("derniere")
finprocedure

procedure HL_COMBO_CARTE(ev)
  si hl.majcombo
    retourner
  finsi
  locale i = nombre(hlc.ccartes.valeur)
  si i <> nul et i >= 1 et i <> hl.index
    HL_ALLER(i)
  finsi
finprocedure

procedure HL_LISTE_CARTE(ev)
  si hl.majcombo
    retourner
  finsi
  locale i = hlc.lcartes:selection()
  si i <> nul et i >= 1 et i <> hl.index
    HL_ALLER(i)
  finsi
finprocedure

procedure HL_MAJ_CARTES
  && liste des cartes (onglet Cartes) et liste déroulante de la barre d'outils
  si hl.def = nul
    retourner
  finsi
  hl.majcombo = vrai
  hlc.lcartes:vider()
  hlc.ccartes:vider()
  pour i = 1 a #hl.def.cartes
    locale c = hl.def.cartes[i]
    locale lib = i + ". " + c.nom
    si majuscule(c.modele) <> majuscule(c.nom)
      lib = lib + "   (" + c.modele + ")"
    finsi
    hlc.lcartes:ajouter(lib)
    hlc.ccartes:ajouter(lib)
  suivant
  hlc.lcartes:selectionner(hl.index)
  hlc.ccartes.valeur = hl.index
  hl.majcombo = faux
  locale c = HL_CARTE()
  si c <> nul
    hlc.infocartes.libelle = #hl.def.cartes + " carte(s) · modèle « " + c.modele + " » : " + ;
                             HL_CARTES_DU_MODELE(c.modele) + " carte(s)"
  finsi
finprocedure

&&
&& Canevas et palette
&&

procedure HL_AFFICHER_MODELE(modele)
  si hl.canevas <> nul et majuscule(hl.modele) = majuscule(modele)
    retourner
  finsi
  HL_FERMER_CANEVAS()
  locale p = HL_FORM(modele)
  essayer
    hl.canevas = ui.concepteur{projet = hl.dossier, fichier = p}
  capturer e
    HL_ETAT("Modèle illisible : " + e)
    hl.canevas = nul
    retourner
  finessayer
  hl.modele = minuscule(modele)
  hl.canevas:codeassocie("script_" + hl.modele + ".prg")
  hlc.conception:ajouter(hl.canevas)
  hl.canevas.surselection = @HL_SELECTION
  hl.canevas.surchangement = @HL_CHANGEMENT
  hlc.palette = hlc.poutils:ajouter(ui.palette(hl.canevas))
  hlc.palette.poids = 1
  && le script du modèle suit la carte
  HL_OUVRIR_SCRIPT(HL_SCRIPT(hl.modele))
  HL_SYNCHRONISER_TAILLE()
finprocedure

procedure HL_FERMER_CANEVAS
  si hl.canevas <> nul
    HL_ENREGISTRER_DESSIN()
    hl.canevas:detruire()
  finsi
  si hlc.palette <> nul
    hlc.palette:detruire()
  finsi
  hl.canevas = nul
  hlc.palette = nul
  hl.modele = ""
finprocedure

fonction HL_RACINE()
  && uid de la fenêtre du formulaire (la carte)
retourner hl.canevas:noeuds()[1].uid
finfonction

procedure HL_ENREGISTRER_DESSIN
  si hl.canevas = nul ou hl.modele = ""
    retourner
  finsi
  locale p = HL_FORM(hl.modele)
  locale code = hl.canevas:code()
  si HL_LIRE(p) <> code
    fichier.ecrire(p, code)
  finsi
finprocedure

procedure HL_SYNCHRONISER_TAILLE
  && toutes les cartes ont la taille de la pile
  si hl.canevas = nul
    retourner
  finsi
  locale l = chaine(entier(nombre(hl.def.largeur) ou 640))
  locale h = chaine(entier(nombre(hl.def.hauteur) ou 440))
  locale change = faux
  pour chaque p dans hl.canevas:proprietes(HL_RACINE())
    si p.nom = "largeur" et p.valeur <> l
      hl.canevas:fixerpropriete("largeur", l, HL_RACINE())
      change = vrai
    sinonsi p.nom = "hauteur" et p.valeur <> h
      hl.canevas:fixerpropriete("hauteur", h, HL_RACINE())
      change = vrai
    sinonsi p.nom = "disposition" et p.valeur = "vertical" et #hl.canevas:noeuds() = 1
      && formulaire neuf : la carte se dessine librement
      hl.canevas:fixerpropriete("disposition", "absolue", HL_RACINE())
      change = vrai
    finsi
  suivant
  si change
    HL_ENREGISTRER_DESSIN()
  finsi
finprocedure

procedure HL_TAILLE_PILE(l, h)
  && nouvelle taille des cartes : appliquée à tous les modèles
  l = entier(nombre(l) ou 0)
  h = entier(nombre(h) ou 0)
  si l < 120 ou h < 80
    HL_ETAT("Taille trop petite (120 × 80 au minimum)")
    retourner
  finsi
  hl.def.largeur = l
  hl.def.hauteur = h
  HL_SYNCHRONISER_TAILLE()
  pour chaque m dans HL_MODELES()
    si majuscule(m) <> majuscule(hl.modele)
      locale d = HL_DESSIN_DE(HL_LIRE(HL_FORM(m)))
      si d <> nul
        d["props"]["largeur"] = chaine(l)
        d["props"]["hauteur"] = chaine(h)
        HL_ECRIRE_DESSIN(m, d)
      finsi
    finsi
  suivant
  HL_ECRIRE_FICHIERS_PILE(hl.dossier)
  HL_ETAT("Taille des cartes : " + l + " × " + h)
finprocedure

procedure HL_SELECTION(ev)
  HL_INSPECTEUR()
  locale sel = hl.canevas:selection()
  pour chaque n dans hl.noeuds
    si n.uid = sel
      hlc.arbre:selectionner(n.chemin)
    finsi
  suivant
finprocedure

procedure HL_CHANGEMENT(ev)
  HL_ENREGISTRER_DESSIN()
  && la taille de la fenêtre du formulaire est celle de la pile
  pour chaque p dans hl.canevas:proprietes(HL_RACINE())
    si p.nom = "largeur" et nombre(p.valeur) <> nul et nombre(p.valeur) <> nombre(hl.def.largeur)
      HL_TAILLE_PILE(p.valeur, hl.def.hauteur)
      HL_MAJ_PAGE_PILE()
    sinonsi p.nom = "hauteur" et nombre(p.valeur) <> nul et nombre(p.valeur) <> nombre(hl.def.hauteur)
      HL_TAILLE_PILE(hl.def.largeur, p.valeur)
      HL_MAJ_PAGE_PILE()
    finsi
  suivant
  HL_ARBRE()
  HL_INSPECTEUR()
finprocedure

&&
&& Objets de la carte
&&

procedure HL_ARBRE
  hlc.arbre:vider()
  hl.noeuds = {}
  si hl.canevas = nul ou hl.mode = "execution"
    retourner
  finsi
  locale sel = hl.canevas:selection()
  locale chemin_sel = ""
  pour chaque n dans hl.canevas:noeuds()
    hlc.arbre:ajouter(n.chemin)
    inserer(hl.noeuds, {chemin = n.chemin, uid = n.uid})
    si n.uid = sel
      chemin_sel = n.chemin
    finsi
  suivant
  pour chaque n dans hl.canevas:noeuds()
    si n.conteneur
      hlc.arbre:deplier(n.chemin)
    finsi
  suivant
  si chemin_sel <> ""
    hlc.arbre:selectionner(chemin_sel)
  finsi
finprocedure

procedure HL_ARBRE_CHOIX(ev)
  pour chaque n dans hl.noeuds
    si n.chemin = ev.texte
      si n.uid <> hl.canevas:selection()
        hl.canevas:selectionner(n.uid)
        HL_INSPECTEUR()
      finsi
      retourner
    finsi
  suivant
finprocedure

procedure HL_SELECTIONNER_CARTE
  si hl.canevas <> nul
    hl.canevas:selectionner()
    HL_ARBRE()
    HL_INSPECTEUR()
  finsi
finprocedure

procedure HL_SUPPRIMER_OBJET
  si hl.canevas <> nul et hl.mode = "conception"
    hl.canevas:supprimer()
  finsi
finprocedure

procedure HL_OBJET_MONTER
  si hl.canevas <> nul et hl.mode = "conception"
    hl.canevas:monter()
  finsi
finprocedure

procedure HL_OBJET_DESCENDRE
  si hl.canevas <> nul et hl.mode = "conception"
    hl.canevas:descendre()
  finsi
finprocedure

fonction HL_NOM_CONTROLE_LIBRE(d, base)
  && base1, base2... (le chiffre final de base est retiré)
  tantque #base > 1 et position(droite(base, 1), "0123456789") > 0
    base = gauche(base, #base - 1)
  fintantque
  locale n = 1
  tantque HL_NOEUD_NOMME(d, base + n) <> nul
    n += 1
  fintantque
retourner base + n
finfonction

procedure HL_RENOMMER_COPIE(d, n)
  n["name"] = HL_NOM_CONTROLE_LIBRE(d, n["name"])
  n["events"] = {}
  pour chaque c dans n["children"]
    HL_RENOMMER_COPIE(d, c)
  suivant
finprocedure

procedure HL_DUPLIQUER_OBJET
  && copie de l'objet sélectionné, décalée, juste devant lui (sans ses événements)
  si hl.canevas = nul ou hl.mode <> "conception"
    retourner
  finsi
  locale el = hl.canevas:element()
  si el.racine
    HL_DUPLIQUER_CARTE()
    retourner
  finsi
  locale d = HL_DESSIN_DE(hl.canevas:code())
  locale n = HL_NOEUD_NOMME(d, el.nom)
  si n = nul
    retourner
  finsi
  locale parent = HL_PARENT_DE(d, n)
  locale copie = json.decoder(HL_DESSIN_JSON(n), vrai)
  HL_RENOMMER_COPIE(d, copie)
  pour chaque k dans {"x", "y"}
    si copie["props"][k] <> nul
      copie["props"][k] = chaine((nombre(copie["props"][k]) ou 0) + 16)
    finsi
  suivant
  locale pos = 1
  pour i = 1 a #parent["children"]
    si parent["children"][i] = n
      pos = i + 1
    finsi
  suivant
  inserer(parent["children"], copie, pos)
  HL_ENREGISTRER_DESSIN()
  HL_ECRIRE_DESSIN(hl.modele, d)
  && le canevas relit le dessin et sélectionne la copie
  locale m = hl.modele
  hl.canevas:detruire()
  hlc.palette:detruire()
  hl.canevas = nul
  hl.modele = ""
  HL_AFFICHER_MODELE(m)
  pour chaque x dans hl.canevas:noeuds()
    si x.nom = copie["name"]
      hl.canevas:selectionner(x.uid)
    finsi
  suivant
  HL_ARBRE()
  HL_INSPECTEUR()
  HL_ETAT("Objet dupliqué : " + copie["name"])
finprocedure

&&
&& Inspecteur : propriétés, contenu de la carte, événements
&&

fonction HL_LIGNE_INSP(libelle)
  locale r = hlc.contenu:ajouter(ui.superconteneur("horizontal"))
  r.espacement = 6
  locale l = r:ajouter(ui.etiquette(libelle))
  l.largeurfixe = 112
retourner r
finfonction

procedure HL_TITRE_INSP(t)
  locale l = hlc.contenu:ajouter(ui.etiquette(t))
  l.couleur = "#64748B"
finprocedure

fonction HL_AFFICHE_CHOIX(c)
  faire cas
  cas c = ""
    retourner "(défaut)"
  cas c = "true"
    retourner "vrai"
  cas c = "false"
    retourner "faux"
  fincas
retourner c
finfonction

fonction HL_PROP_CACHEE(el, nom, niveau)
  && propriétés sans objet sur une carte (disposition absolue, taille de la pile)
  si el.racine
    retourner contient({"disposition", "theme", "sombre", "largeur", "hauteur"}, nom)
  finsi
  si niveau = 1
    retourner contient({"poids", "etirer", "ancrage"}, nom)
  finsi
retourner faux
finfonction

fonction HL_NIVEAU(uid)
  pour chaque n dans hl.canevas:noeuds()
    si n.uid = uid
      retourner n.niveau
    finsi
  suivant
retourner 0
finfonction

fonction HL_GENRE_DONNEE(genre)
retourner contient({"saisie", "cases", "radio", "combo", "liste", "compteur", "curseur", "plage", "jauge", ;
                    "notation", "ascenseur", "calendrier"}, genre)
finfonction

procedure HL_INSPECTEUR
  hlc.contenu:detruire()
  hlc.contenu = hlc.insp:ajouter(ui.superconteneur("vertical"))
  hlc.contenu.espacement = 4
  hlc.contenu.largeurfixe = 330
  hl.lignes = {}
  hl.evts = {}
  hl.ligneNom = nul
  si hl.mode = "execution"
    hlc.titreinsp.libelle = "Mode Exécution"
    hlc.contenu:ajouter(ui.etiquette("La pile fonctionne : cliquez, saisissez."))
    hlc.contenu:ajouter(ui.etiquette("✎ Conception (Ctrl+E) pour modifier la carte."))
    hlc.contenu:ajouter(ui.etiquette("Les champs saisis sont gardés avec la carte."))
    retourner
  finsi
  si hl.canevas = nul
    hlc.titreinsp.libelle = ""
    retourner
  finsi
  locale el = hl.canevas:element()
  locale carte = HL_CARTE()
  locale niveau = HL_NIVEAU(el.uid)
  si el.racine
    hlc.titreinsp.libelle = "Carte « " + carte.nom + " »  ·  modèle « " + hl.modele + " »"
    HL_TITRE_INSP("CARTE")
    locale r = HL_LIGNE_INSP("nom de la carte")
    locale sc = r:ajouter(ui.saisie(carte.nom))
    sc.poids = 1
    sc.infobulle = "Entrée pour renommer la carte (ses données suivent)"
    sc.surtouchebas = @HL_NOM_TOUCHE
    sc.surfinfocus = @HL_NOM_SORTIE
    inserer(hl.lignes, {ctl = sc, prop = "#carte"})
    r = HL_LIGNE_INSP("numéro")
    r:ajouter(ui.etiquette(hl.index + " / " + #hl.def.cartes))
    HL_TITRE_INSP("MODÈLE (partagé par " + HL_CARTES_DU_MODELE(carte.modele) + " carte(s))")
    r = HL_LIGNE_INSP("nom du modèle")
    locale sm = r:ajouter(ui.saisie(hl.modele))
    sm.poids = 1
    sm.infobulle = "Entrée pour renommer le modèle (form_<nom>.prg, script_<nom>.prg et les scripts suivent)"
    sm.surtouchebas = @HL_NOM_TOUCHE
    sm.surfinfocus = @HL_NOM_SORTIE
    inserer(hl.lignes, {ctl = sm, prop = "#modele"})
  sinon
    hlc.titreinsp.libelle = el.genre + "  " + el.nom
    HL_TITRE_INSP("PROPRIÉTÉS")
    locale r = HL_LIGNE_INSP("nom")
    locale sn = r:ajouter(ui.saisie(el.nom))
    sn.poids = 1
    sn.infobulle = "Entrée (ou sortie du champ) pour renommer"
    sn.surtouchebas = @HL_NOM_TOUCHE
    sn.surfinfocus = @HL_NOM_SORTIE
    hl.ligneNom = {ctl = sn, uid = el.uid}
  finsi
  pour chaque p dans hl.canevas:proprietes(el.uid)
    si non HL_PROP_CACHEE(el, p.nom, niveau)
      HL_LIGNE_PROPRIETE(p, el.uid)
    finsi
  suivant
  && contenu de ce contrôle sur la carte courante (données de la carte)
  si non el.racine et HL_GENRE_DONNEE(el.genre)
    HL_TITRE_INSP("CONTENU SUR CETTE CARTE")
    locale d = hl.donnees[majuscule(carte.nom)]
    locale v = nul
    si d <> nul
      v = d[majuscule(el.nom)]
    finsi
    locale r = HL_LIGNE_INSP("contenu")
    locale sv = r:ajouter(ui.saisie{texte = v ou "", indication = "(valeur du dessin)"})
    sv.poids = 1
    sv.infobulle = "Contenu de " + el.nom + " sur la carte « " + carte.nom + " » (vide : valeur du dessin)"
    sv.surchangement = @HL_CONTENU
    inserer(hl.lignes, {ctl = sv, prop = "#contenu", nom = el.nom})
  finsi
  && événements
  HL_TITRE_INSP("ÉVÉNEMENTS (script du modèle)")
  locale gest = HL_GESTIONNAIRES()
  pour chaque e dans hl.canevas:evenements(el.uid)
    locale r = HL_LIGNE_INSP(e.nom)
    locale choix = {"(aucune)"}
    locale present = faux
    pour chaque g dans gest
      inserer(choix, g)
      si majuscule(g) = majuscule(e.procedure)
        present = vrai
      finsi
    suivant
    si e.procedure <> "" et non present
      inserer(choix, e.procedure)
    finsi
    inserer(choix, "+ nouveau script…")
    locale cb = r:ajouter(ui.combo(choix))
    cb.poids = 1
    pour i = 1 a #choix
      si e.procedure <> "" et majuscule(choix[i]) = majuscule(e.procedure)
        cb.valeur = i
      finsi
    suivant
    cb.surselection = @HL_EVENEMENT
    inserer(hl.evts, {ctl = cb, evenement = e.nom, choix = choix, uid = el.uid})
    si e.procedure <> ""
      locale bv = r:ajouter(ui.bouton("✎"))
      bv.largeurfixe = 30
      bv.infobulle = "Voir " + e.procedure + " dans le script"
      bv.surclic = @HL_VOIR_GESTIONNAIRE
      inserer(hl.evts, {ctl = bv, evenement = e.nom, procedure = e.procedure, uid = el.uid, voir = vrai})
    finsi
  suivant
  locale rb = hlc.contenu:ajouter(ui.rangee())
  locale b = rb:ajouter(ui.bouton("✎ Modifier le script"))
  b.infobulle = "Ouvre (ou crée) la procédure de l'événement principal de l'objet"
  b.surclic = @HL_MODIFIER_SCRIPT
finprocedure

procedure HL_LIGNE_PROPRIETE(p, uid)
  locale r = HL_LIGNE_INSP(p.nom)
  locale c = nul
  faire cas
  cas p.genre = "logique"
    c = r:ajouter(ui.cases(""))
    c:cocher(1, p.valeur = "true")
    c.surchangement = @HL_PROP
  cas p.genre = "choix"
    c = r:ajouter(ui.combo())
    pour chaque ch dans p.choix
      c:ajouter(HL_AFFICHE_CHOIX(ch))
    suivant
    pour i = 1 a #p.choix
      si p.choix[i] = p.valeur
        c.valeur = i
      finsi
    suivant
    c.surselection = @HL_PROP
  autrement
    c = r:ajouter(ui.saisie(p.valeur))
    c.surchangement = @HL_PROP
    si p.genre = "liste"
      c.infobulle = "Éléments séparés par ;"
    finsi
  fincas
  c.poids = 1
  locale ligne = {ctl = c, prop = p.nom, genre = p.genre, choix = p.choix, uid = uid}
  si p.genre = "couleur"
    locale b = r:ajouter(ui.bouton("…"))
    b.largeurfixe = 30
    b.surclic = @HL_COULEUR
    ligne.bouton = b
  finsi
  inserer(hl.lignes, ligne)
finprocedure

fonction HL_LIGNE_DE(liste, ctl)
  pour chaque l dans liste
    si l.ctl = ctl
      retourner l
    finsi
  suivant
retourner nul
finfonction

procedure HL_PROP(ev)
  locale l = HL_LIGNE_DE(hl.lignes, ev.id)
  si l = nul ou hl.canevas = nul
    retourner
  finsi
  locale v = ""
  faire cas
  cas l.genre = "logique"
    v = sisinon(l.ctl:coche(1), "true", "false")
  cas l.genre = "choix"
    locale i = nombre(l.ctl.valeur)
    si i = nul ou i < 1 ou i > #l.choix
      retourner
    finsi
    v = l.choix[i]
  autrement
    v = l.ctl.valeur
  fincas
  locale msg = hl.canevas:fixerpropriete(l.prop, v, l.uid)
  si msg <> nul
    HL_ETAT(msg)
    retourner
  finsi
  HL_ENREGISTRER_DESSIN()
finprocedure

procedure HL_COULEUR(ev)
  pour chaque l dans hl.lignes
    si l.bouton <> nul et l.bouton = ev.id
      locale c = ui.couleur(sisinon(commencepar(l.ctl.valeur, "#"), l.ctl.valeur, "#3B82F6"))
      si c <> nul
        l.ctl.valeur = c
        locale msg = hl.canevas:fixerpropriete(l.prop, c, l.uid)
        si msg <> nul
          HL_ETAT(msg)
        sinon
          HL_ENREGISTRER_DESSIN()
        finsi
      finsi
      retourner
    finsi
  suivant
finprocedure

procedure HL_CONTENU(ev)
  locale l = HL_LIGNE_DE(hl.lignes, ev.id)
  si l = nul
    retourner
  finsi
  locale carte = HL_CARTE()
  locale cle = majuscule(carte.nom)
  si hl.donnees[cle] = nul
    hl.donnees[cle] = {}
  finsi
  si l.ctl.valeur = ""
    hl.donnees[cle][majuscule(l.nom)] = nul
  sinon
    hl.donnees[cle][majuscule(l.nom)] = l.ctl.valeur
  finsi
  HL_ETAT("Contenu de " + l.nom + " sur la carte « " + carte.nom + " » : enregistré avec la pile")
finprocedure

&& noms : appliqués par Entrée ou à la sortie du champ

procedure HL_NOM_TOUCHE(ev)
  si ev.touche = 13 ou ev.touche = 1073741912
    HL_NOM(ev.id)
  finsi
finprocedure

procedure HL_NOM_SORTIE(ev)
  HL_NOM(ev.id)
finprocedure

procedure HL_NOM(ctl)
  locale v = rogner(ctl.valeur)
  locale l = HL_LIGNE_DE(hl.lignes, ctl)
  si l <> nul et l.prop = "#carte"
    locale carte = HL_CARTE()
    si v <> "" et minuscule(v) <> carte.nom
      locale msg = HL_NOM_VALIDE(minuscule(v), faux)
      si msg <> nul
        HL_ETAT(msg)
        retourner
      finsi
      hl.donnees[majuscule(minuscule(v))] = hl.donnees[majuscule(carte.nom)]
      hl.donnees[majuscule(carte.nom)] = nul
      carte.nom = minuscule(v)
      HL_ECRIRE_FICHIERS_PILE(hl.dossier)
      HL_MAJ_CARTES()
      HL_ETAT("Carte renommée : « " + carte.nom + " »")
    finsi
    retourner
  finsi
  si l <> nul et l.prop = "#modele"
    si v <> "" et minuscule(v) <> hl.modele
      HL_RENOMMER_MODELE(v)
    finsi
    retourner
  finsi
  locale ln = hl.ligneNom
  si ln = nul ou non (ln.ctl = ctl)
    retourner
  finsi
  locale el = hl.canevas:element(ln.uid)
  si v = "" ou v = el.nom
    retourner
  finsi
  locale ancien = el.nom
  locale msg = hl.canevas:fixerpropriete("nom", v, ln.uid)
  si msg <> nul
    HL_ETAT(msg)
    retourner
  finsi
  && les données des cartes suivent le nouveau nom
  pour chaque c dans hl.def.cartes
    si majuscule(c.modele) = majuscule(hl.modele)
      locale d = hl.donnees[majuscule(c.nom)]
      si d <> nul et d[majuscule(ancien)] <> nul
        d[majuscule(v)] = d[majuscule(ancien)]
        d[majuscule(ancien)] = nul
      finsi
    finsi
  suivant
  HL_ENREGISTRER_DESSIN()
  HL_ARBRE()
  HL_INSPECTEUR()
finprocedure

&&
&& Page « Pile » : propriétés de la pile
&&

procedure HL_CONSTRUIRE_PAGE_PILE(page)
  hlc.pile = {}
  page:ajouter(ui.etiquette("PROPRIÉTÉS DE LA PILE"))
  hlc.pile.titre = HL_CHAMP_PILE(page, "titre", "Titre de la fenêtre de l'application")
  hlc.pile.largeur = HL_CHAMP_PILE(page, "largeur", "Largeur des cartes (pixels)")
  hlc.pile.hauteur = HL_CHAMP_PILE(page, "hauteur", "Hauteur des cartes (pixels)")
  hlc.pile.couleur = HL_CHAMP_PILE(page, "couleur", "Couleur de fond des cartes (#RRGGBB)")
  hlc.pile.options = page:ajouter(ui.cases("Barre de navigation", "Garder les données saisies"))
  hlc.pile.options.infobulle = "Application autonome : barre ⏮ ◀ ▶ ⏭ en bas ; données dans pile_donnees.json"
  hlc.pile.options.surchangement = @HL_PILE_OPTIONS
  locale b = page:ajouter(ui.bouton("Appliquer la taille"))
  b.surclic = @HL_PILE_TAILLE
  page:ajouter(ui.etiquette(""))
  page:ajouter(ui.etiquette("FICHIERS"))
  hlc.pile.dossier = page:ajouter(ui.etiquette(""))
  locale b2 = page:ajouter(ui.bouton("Script de la pile"))
  b2.surclic = @HL_SCRIPT_PILE
finprocedure

fonction HL_CHAMP_PILE(page, libelle, aide)
  page:ajouter(ui.etiquette(libelle))
  locale s = page:ajouter(ui.saisie(""))
  s.infobulle = aide
  s.surtouchebas = @HL_PILE_TOUCHE
  s.surfinfocus = @HL_PILE_SORTIE
retourner s
finfonction

procedure HL_MAJ_PAGE_PILE
  si hl.def = nul
    retourner
  finsi
  hlc.pile.titre.valeur = hl.def.titre
  hlc.pile.largeur.valeur = chaine(hl.def.largeur)
  hlc.pile.hauteur.valeur = chaine(hl.def.hauteur)
  hlc.pile.couleur.valeur = hl.def.couleur ou "#FFFFFF"
  hlc.pile.options:cocher(1, hl.def.navigation <> faux)
  hlc.pile.options:cocher(2, hl.def.persistance <> faux)
  hlc.pile.dossier.libelle = fichier.nom(hl.dossier)
  hlc.pile.dossier.infobulle = hl.dossier
finprocedure

procedure HL_PILE_TOUCHE(ev)
  si ev.touche = 13 ou ev.touche = 1073741912
    HL_PILE_APPLIQUER(ev.id)
  finsi
finprocedure

procedure HL_PILE_SORTIE(ev)
  HL_PILE_APPLIQUER(ev.id)
finprocedure

procedure HL_PILE_APPLIQUER(ctl)
  si hl.def = nul
    retourner
  finsi
  faire cas
  cas ctl = hlc.pile.titre
    si rogner(ctl.valeur) <> "" et rogner(ctl.valeur) <> hl.def.titre
      hl.def.titre = rogner(ctl.valeur)
      hlc.fen.titre = "HyperLexis - " + hl.def.titre + "  (" + hl.dossier + ")"
      HL_ECRIRE_FICHIERS_PILE(hl.dossier)
      HL_ETAT("Titre de la pile : " + hl.def.titre)
    finsi
  cas ctl = hlc.pile.couleur
    locale c = rogner(ctl.valeur)
    si c <> hl.def.couleur et commencepar(c, "#") et (#c = 7 ou #c = 9)
      hl.def.couleur = c
      HL_ECRIRE_FICHIERS_PILE(hl.dossier)
      HL_ETAT("Couleur des cartes : " + c + " (visible en mode Exécution)")
    finsi
  cas ctl = hlc.pile.largeur ou ctl = hlc.pile.hauteur
    HL_PILE_TAILLE()
  fincas
finprocedure

procedure HL_PILE_TAILLE
  locale l = nombre(hlc.pile.largeur.valeur)
  locale h = nombre(hlc.pile.hauteur.valeur)
  si l = nul ou h = nul
    retourner
  finsi
  si l <> nombre(hl.def.largeur) ou h <> nombre(hl.def.hauteur)
    HL_TAILLE_PILE(l, h)
  finsi
finprocedure

procedure HL_PILE_OPTIONS(ev)
  hl.def.navigation = hlc.pile.options:coche(1)
  hl.def.persistance = hlc.pile.options:coche(2)
  HL_ECRIRE_FICHIERS_PILE(hl.dossier)
finprocedure
