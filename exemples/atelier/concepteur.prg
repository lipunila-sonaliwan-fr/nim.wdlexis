&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ : concepteur de formulaires (le même que celui de l'atelier natif).
&&
&& Natif (paquet interface) : le canevas ui.concepteur (aperçu, glisser-déposer,
&& repères, poignées), la palette ui.palette, le modèle du formulaire et la
&& génération de form_<nom>.prg (format commun aux deux ateliers).
&& Ici, en Lexis+ : la fenêtre du concepteur, la hiérarchie, l'inspecteur des
&& propriétés et des événements, les procédures écrites dans le code, le câblage,
&& le renommage, les contrôles personnalisés et l'enregistrement.

&&
&& Ouverture
&&

procedure CONCEPTEUR_NOUVEAU
  CONCEPTEUR_OUVRIR(nul)
retourner

procedure CONCEPTEUR_BOUTON
  && formulaire affiché dans l'éditeur : le rouvrir ; sinon nouveau formulaire
  locale p = ed:chemin()
  si p <> "" et EST_FORMULAIRE(p)
    CONCEPTEUR_OUVRIR(p)
  sinon
    CONCEPTEUR_OUVRIR(nul)
  finsi
retourner

procedure CONCEPTEUR_CHOISIR
  si dossier = ""
    CONCEPTEUR_OUVRIR(nul)
    retourner
  finsi
  locale p = ui.ouvrirfichier{titre = "Ouvrir un formulaire", dossier = dossier, ;
                              filtre = "Formulaires Lexis+ (form_*.prg)|*.prg"}
  si p = nul
    retourner
  finsi
  si non EST_FORMULAIRE(p)
    ui.alerte("Choisissez un fichier form_<nom>.prg créé par le concepteur.", "information", "Concepteur de formulaires")
    retourner
  finsi
  CONCEPTEUR_OUVRIR(p)
retourner

fonction EST_FORMULAIRE(p)
  locale n = minuscule(fichier.nom(p))
retourner commencepar(n, "form_") et finitpar(n, ".prg")

fonction CODE_CONCEPTEUR()
  && le .prg affiché s'il est dans le projet (et n'est pas un formulaire), sinon le principal
  locale p = ed:chemin()
  si p <> "" et minuscule(fichier.extension(p)) = ".prg" et non EST_FORMULAIRE(p) ;
     et commencepar(fichier.absolu(p), fichier.absolu(dossier))
    retourner p
  finsi
  locale m = fichier.joindre(dossier, FICHIER_PRINCIPAL())
  si fichier.existe(m)
    retourner m
  finsi
retourner ""

fonction RELATIF(p)
  locale d = fichier.absolu(dossier)
  locale a = fichier.absolu(p)
  si commencepar(a, d + "/")
    retourner souschaine(a, #d + 2)
  finsi
retourner a

fonction PROCHAIN_FORMULAIRE()
  locale n = 1
  tantque fichier.existe(fichier.joindre(dossier, "form_" + n + ".prg"))
    n += 1
  fintantque
retourner chaine(n)

procedure CONCEPTEUR_OUVRIR(formulaire)
  globale condlg, canevas, conctl, concode
  si condlg <> nul
    etat.libelle = "Le concepteur de formulaires est déjà ouvert."
    retourner
  finsi
  si dossier = ""
    ui.alerte("Ouvrez d'abord un projet (Fichier > Ouvrir un projet…).", "information", "Concepteur de formulaires")
    retourner
  finsi
  locale code = CODE_CONCEPTEUR()
  si code = ""
    ui.alerte("Ouvrez ou créez d'abord un fichier .prg du projet : il recevra les procédures des événements.", ;
              "information", "Concepteur de formulaires")
    retourner
  finsi
  si formulaire = nul
    canevas = ui.concepteur{projet = dossier, nom = PROCHAIN_FORMULAIRE()}
  sinon
    essayer
      canevas = ui.concepteur{projet = dossier, fichier = formulaire}
    capturer e
      ui.alerte(e, "stop", "Concepteur de formulaires")
      retourner
    finessayer
    && le formulaire se souvient de son code
    locale associe = canevas:codeassocie()
    si associe <> "" et fichier.existe(fichier.joindre(dossier, associe))
      code = fichier.joindre(dossier, associe)
    finsi
  finsi
  concode = code
  canevas:codeassocie(RELATIF(code))
  CONCEPTEUR_FENETRE()
  CON_ENREGISTRER()
  CON_ARBRE()
  CON_INSPECTEUR()
  etat.libelle = "Concepteur : form_" + canevas:nom() + ".prg · code : " + fichier.nom(concode)
retourner

procedure CONCEPTEUR_FENETRE
  globale condlg, conctl
  conctl = {lignes = {}, evts = {}, noeuds = {}, nomligne = nul}
  condlg = ui.fenetre{titre = "Concepteur de formulaires", largeur = 1320, hauteur = 820, ;
                      disposition = "bordure", sombre = reglages.sombre}
  condlg.surfermeture = @CON_FERMETURE
  && barre d'outils
  locale outils = condlg:ajouter(ui.rangee())
  outils.ancrage = "haut"
  CON_OUTIL(outils, "Enregistrer", @CON_ENREGISTRER, "Régénère form_<nom>.prg")
  CON_OUTIL(outils, "Supprimer", @CON_SUPPRIMER, "Supprime le contrôle sélectionné (Suppr)")
  CON_OUTIL(outils, "Monter", @CON_MONTER, "Plus tôt dans l'ordre d'affichage")
  CON_OUTIL(outils, "Descendre", @CON_DESCENDRE, "Plus tard dans l'ordre d'affichage")
  CON_OUTIL(outils, "Sortir", @CON_SORTIR, "Sort le contrôle de son conteneur")
  CON_OUTIL(outils, "Formulaire", @CON_FORMULAIRE, "Sélectionne le formulaire (propriétés de la fenêtre)")
  CON_OUTIL(outils, "Câbler le code", @CON_CABLER, ;
            "Ajoute au code le bloc des procédures et l'appel d'ouverture (programme principal)")
  CON_OUTIL(outils, "Contrôle personnalisé…", @CON_PERSONNALISE, ;
            "Ajoute à la palette un contrôle créé par une fonction Lexis+ du projet")
  CON_OUTIL(outils, "Voir le code", @CON_VOIR_CODE, "Affiche le code édité dans l'atelier")
  && barre d'état
  conctl.etat = condlg:ajouter(ui.etiquette("Glisser depuis la palette · clic pour sélectionner · poignées pour " + ;
                                            "redimensionner · Suppr supprime · Échap sélectionne le parent"))
  conctl.etat.ancrage = "bas"
  && palette
  locale cg = condlg:ajouter(ui.colonne())
  cg.ancrage = "gauche"
  cg.largeurfixe = 200
  cg:ajouter(ui.etiquette("PALETTE"))
  conctl.palette = cg:ajouter(ui.palette(canevas))
  conctl.palette.poids = 1
  && hiérarchie et inspecteur
  locale cd = condlg:ajouter(ui.colonne())
  cd.ancrage = "droite"
  cd.largeurfixe = 360
  cd:ajouter(ui.etiquette("HIÉRARCHIE"))
  conctl.arbre = cd:ajouter(ui.arbre())
  conctl.arbre.hauteurfixe = 210
  conctl.arbre.surselection = @CON_ARBRE_CHOIX
  conctl.titre = cd:ajouter(ui.etiquette(""))
  conctl.titre.couleur = "#3B82F6"
  conctl.insp = cd:ajouter(ui.panneau{defilement = "automatique"})
  conctl.insp.poids = 1
  conctl.contenu = conctl.insp:ajouter(ui.colonne())
  && canevas
  locale centre = condlg:ajouter(ui.panneau{defilement = "automatique"})
  centre.ancrage = "centre"
  centre:ajouter(canevas)
  canevas.surselection = @CON_SELECTION
  canevas.surchangement = @CON_CHANGEMENT
  canevas:focus()
retourner

procedure CON_OUTIL(barre, libelle, proc, aide)
  locale b = barre:ajouter(ui.bouton(libelle))
  b.infobulle = aide
  b.surclic = proc
retourner

procedure CON_FERMETURE(ev)
  globale condlg, canevas
  condlg = nul
  canevas = nul
retourner

procedure CON_ETAT(message)
  si condlg <> nul
    conctl.etat.libelle = message
  finsi
retourner

&&
&& Enregistrement, procédures du projet
&&

fonction CHEMIN_FORMULAIRE(nom)
retourner fichier.joindre(dossier, "form_" + nom + ".prg")

fonction TEXTE_DE(p)
  && document ouvert dans l'éditeur (tel qu'à l'écran), sinon le fichier
  locale uid = ed:chercherdocument(p)
  si uid <> nul
    retourner ed:texte(uid)
  finsi
  essayer
    retourner fichier.lire(p)
  capturer e
  finessayer
retourner ""

procedure ECRIRE_CODE(src)
  && dans l'éditeur si le code y est ouvert (annulable), sinon sur disque
  locale uid = ed:chercherdocument(concode)
  si uid <> nul
    ed:fixertexte(src, uid)
  sinon
    fichier.ecrire(concode, src)
  finsi
retourner

procedure CON_ENREGISTRER
  si canevas = nul
    retourner
  finsi
  locale nom = canevas:nom()
  locale p = CHEMIN_FORMULAIRE(nom)
  locale nouveau = non fichier.existe(p)
  locale code = canevas:code()
  fichier.ecrire(p, code)
  locale uid = ed:chercherdocument(p)
  si uid <> nul
    ed:fixertexte(code, uid, vrai)
  finsi
  condlg.titre = "Concepteur de formulaires — form_" + nom + ".prg — " + fichier.nom(concode)
  locale manquantes = CON_MANQUANTES()
  si #manquantes > 0
    CON_ETAT("⚠ procédure(s) introuvable(s) dans le projet : " + joindre(manquantes, ", "))
  sinon
    CON_ETAT("Enregistré : form_" + nom + ".prg · code : " + fichier.nom(concode))
  finsi
  si nouveau
    ARBRE_PROJET()
  finsi
retourner

fonction FICHIERS_PRG()
  && fichiers .prg du projet hors formulaires, le code édité en premier
  locale l = {concode}
  pour chaque nom dans fichier.liste(dossier, vrai)
    si commencepar(nom, ".") ou ("/." $ nom) ou commencepar(nom, "distribution/")
      boucler
    finsi
    locale p = fichier.joindre(dossier, nom)
    si minuscule(fichier.extension(nom)) = ".prg" et non EST_FORMULAIRE(nom) ;
       et fichier.absolu(p) <> fichier.absolu(concode)
      inserer(l, p)
    finsi
  suivant
retourner l

fonction ENTETE_PROCEDURE(ligne)
  && {nom, parametres} pour « procedure NOM(a) » / « fonction NOM(a, b) », sinon nul
  locale s = rogner(ligne)
  locale reste = ""
  faire cas
  cas commencepar(s, "procedure ")
    reste = rogner(souschaine(s, 11))
  cas commencepar(s, "fonction ")
    reste = rogner(souschaine(s, 10))
  autrement
    retourner nul
  fincas
  locale o = position("(", reste)
  locale f = position(")", reste)
  si o = 0
    retourner {nom = rogner(reste), parametres = 0}
  finsi
  locale n = 0
  si f > o + 1 et rogner(souschaine(reste, o + 1, f - o - 1)) <> ""
    n = #decouper(souschaine(reste, o + 1, f - o - 1), ",")
  finsi
retourner {nom = rogner(gauche(reste, o - 1)), parametres = n}

fonction PROCEDURES_DE(src, unparametre)
  locale l = {}
  pour chaque ligne dans decouper(src, car(10))
    locale h = ENTETE_PROCEDURE(ligne)
    si h <> nul et h.nom <> "" et (non unparametre ou h.parametres = 1)
      inserer(l, h.nom)
    finsi
  suivant
retourner l

fonction CON_GESTIONNAIRES()
  && procédures à un paramètre (ev) du projet : candidates aux événements
  locale l = {}
  locale vus = {}
  pour chaque p dans FICHIERS_PRG()
    pour chaque n dans PROCEDURES_DE(TEXTE_DE(p), vrai)
      si vus[majuscule(n)] = nul
        vus[majuscule(n)] = vrai
        inserer(l, n)
      finsi
    suivant
  suivant
retourner l

fonction CON_TOUTES_PROCEDURES()
  locale vus = {}
  pour chaque p dans FICHIERS_PRG()
    pour chaque n dans PROCEDURES_DE(TEXTE_DE(p), faux)
      vus[majuscule(n)] = vrai
    suivant
  suivant
retourner vus

fonction CON_MANQUANTES()
  locale connues = CON_TOUTES_PROCEDURES()
  locale l = {}
  pour chaque n dans canevas:noeuds()
    pour chaque e dans canevas:evenements(n.uid)
      si e.procedure <> "" et connues[majuscule(e.procedure)] = nul
        inserer(l, e.procedure)
      finsi
    suivant
  suivant
retourner l

&&
&& Hiérarchie
&&

procedure CON_ARBRE
  conctl.arbre:vider()
  conctl.noeuds = {}
  locale sel = canevas:selection()
  locale chemin_sel = ""
  pour chaque n dans canevas:noeuds()
    conctl.arbre:ajouter(n.chemin)
    inserer(conctl.noeuds, {chemin = n.chemin, uid = n.uid})
    si n.uid = sel
      chemin_sel = n.chemin
    finsi
  suivant
  pour chaque n dans canevas:noeuds()
    si n.conteneur
      conctl.arbre:deplier(n.chemin)
    finsi
  suivant
  si chemin_sel <> ""
    conctl.arbre:selectionner(chemin_sel)
  finsi
retourner

procedure CON_ARBRE_CHOIX(ev)
  pour chaque n dans conctl.noeuds
    si n.chemin = ev.texte
      si n.uid <> canevas:selection()
        canevas:selectionner(n.uid)
        CON_INSPECTEUR()
      finsi
      retourner
    finsi
  suivant
retourner

&&
&& Inspecteur
&&

fonction CON_LIGNE(libelle)
  && rangée sans marge, comme l'inspecteur natif
  locale r = conctl.contenu:ajouter(ui.superconteneur("horizontal"))
  r.espacement = 6
  locale l = r:ajouter(ui.etiquette(libelle))
  l.largeurfixe = 118
retourner r

fonction AFFICHE_CHOIX(c)
  faire cas
  cas c = ""
    retourner "(défaut)"
  cas c = "true"
    retourner "vrai"
  cas c = "false"
    retourner "faux"
  fincas
retourner c

procedure CON_INSPECTEUR
  si canevas = nul
    retourner
  finsi
  locale el = canevas:element()
  && l'inspecteur est reconstruit en entier
  conctl.contenu:detruire()
  conctl.contenu = conctl.insp:ajouter(ui.superconteneur("vertical"))
  conctl.contenu.espacement = 4
  conctl.contenu.largeurfixe = 300        && pas de défilement horizontal
  conctl.lignes = {}
  conctl.evts = {}
  conctl.titre.libelle = sisinon(el.racine, "Formulaire  " + el.nom, el.genre + "  " + el.nom)
  conctl.contenu:ajouter(ui.etiquette("PROPRIÉTÉS"))
  && nom (pour la fenêtre : nom du formulaire, donne form_<nom>.prg)
  locale r = CON_LIGNE(sisinon(el.racine, "nom (fichier)", "nom"))
  locale sn = r:ajouter(ui.saisie(el.nom))
  sn.poids = 1
  sn.infobulle = "Entrée (ou sortie du champ) pour renommer"
  sn.surtouchebas = @CON_NOM_TOUCHE
  sn.surfinfocus = @CON_NOM_SORTIE
  conctl.nomligne = {ctl = sn, uid = el.uid}
  pour chaque p dans canevas:proprietes(el.uid)
    r = CON_LIGNE(p.nom)
    locale c = nul
    faire cas
    cas p.genre = "logique"
      c = r:ajouter(ui.cases(""))
      c:cocher(1, p.valeur = "true")
      c.surchangement = @CON_PROP
    cas p.genre = "choix"
      c = r:ajouter(ui.combo())
      pour chaque ch dans p.choix
        c:ajouter(AFFICHE_CHOIX(ch))
      suivant
      pour i = 1 a #p.choix
        si p.choix[i] = p.valeur
          c.valeur = i
        finsi
      suivant
      c.surselection = @CON_PROP
    autrement
      c = r:ajouter(ui.saisie(p.valeur))
      c.surchangement = @CON_PROP
    fincas
    c.poids = 1
    locale ligne = {ctl = c, prop = p.nom, genre = p.genre, choix = p.choix, uid = el.uid}
    si p.genre = "couleur"
      locale b = r:ajouter(ui.bouton("…"))
      b.largeurfixe = 36
      b.surclic = @CON_COULEUR
      ligne.bouton = b
    finsi
    inserer(conctl.lignes, ligne)
  suivant
  && événements
  conctl.contenu:ajouter(ui.etiquette("ÉVÉNEMENTS  (procédures du projet)"))
  locale gest = CON_GESTIONNAIRES()
  pour chaque e dans canevas:evenements(el.uid)
    r = CON_LIGNE(e.nom)
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
    inserer(choix, "+ nouvelle procédure…")
    locale cb = r:ajouter(ui.combo(choix))
    cb.poids = 1
    pour i = 1 a #choix
      si e.procedure <> "" et majuscule(choix[i]) = majuscule(e.procedure)
        cb.valeur = i
      finsi
    suivant
    cb.surselection = @CON_EVENEMENT
    inserer(conctl.evts, {ctl = cb, evenement = e.nom, choix = choix, uid = el.uid})
  suivant
retourner

fonction LIGNE_DE(liste, ctl)
  pour chaque l dans liste
    si l.ctl = ctl
      retourner l
    finsi
  suivant
retourner nul

procedure CON_PROP(ev)
  locale l = LIGNE_DE(conctl.lignes, ev.id)
  si l = nul
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
  locale msg = canevas:fixerpropriete(l.prop, v, l.uid)
  si msg <> nul
    CON_ETAT(msg)
    retourner
  finsi
  CON_ENREGISTRER()
retourner

procedure CON_COULEUR(ev)
  pour chaque l dans conctl.lignes
    si l.bouton <> nul et l.bouton = ev.id
      locale c = ui.couleur(sisinon(commencepar(l.ctl.valeur, "#"), l.ctl.valeur, "#3B82F6"))
      si c <> nul
        l.ctl.valeur = c
        locale msg = canevas:fixerpropriete(l.prop, c, l.uid)
        si msg <> nul
          CON_ETAT(msg)
        sinon
          CON_ENREGISTRER()
        finsi
      finsi
      retourner
    finsi
  suivant
retourner

&&
&& Nom : appliqué par Entrée ou à la sortie du champ (renommer le formulaire
&& renomme son fichier et suit dans le code)
&&

procedure CON_NOM_TOUCHE(ev)
  si ev.touche = 13 ou ev.touche = 1073741912
    CON_NOM(ev.id)
  finsi
retourner

procedure CON_NOM_SORTIE(ev)
  CON_NOM(ev.id)
retourner

procedure CON_NOM(ctl)
  locale l = conctl.nomligne
  si l = nul ou non (l.ctl = ctl)
    retourner
  finsi
  locale v = rogner(ctl.valeur)
  locale el = canevas:element(l.uid)
  si v = "" ou v = el.nom
    retourner
  finsi
  si el.racine
    CON_RENOMMER_FORMULAIRE(v)
    retourner
  finsi
  locale msg = canevas:fixerpropriete("nom", v, l.uid)
  si msg <> nul
    CON_ETAT(msg)
    retourner
  finsi
  CON_ENREGISTRER()
  CON_ARBRE()
  CON_INSPECTEUR()
retourner

procedure CON_RENOMMER_FORMULAIRE(nouveau)
  locale ancien = canevas:nom()
  si fichier.existe(CHEMIN_FORMULAIRE(nouveau))
    CON_ETAT("form_" + nouveau + ".prg existe déjà")
    retourner
  finsi
  locale msg = canevas:fixerpropriete("nom", nouveau)
  si msg <> nul
    CON_ETAT(msg)
    retourner
  finsi
  && l'ancien fichier disparaît (et son onglet), le code suit
  locale p = CHEMIN_FORMULAIRE(ancien)
  locale uid = ed:chercherdocument(p)
  si uid <> nul
    ed:fermer(uid)
  finsi
  essayer
    fichier.supprimer(p)
  capturer e
  finessayer
  locale src = TEXTE_DE(concode)
  locale renomme = RENOMMER_CABLAGE(src, ancien, nouveau)
  si renomme <> src
    ECRIRE_CODE(renomme)
  finsi
  CON_ENREGISTRER()
  ARBRE_PROJET()
  CON_ARBRE()
  CON_INSPECTEUR()
retourner

&&
&& Événements
&&

procedure CON_EVENEMENT(ev)
  locale l = LIGNE_DE(conctl.evts, ev.id)
  si l = nul
    retourner
  finsi
  locale i = nombre(l.ctl.valeur)
  si i = nul ou i < 1 ou i > #l.choix
    retourner
  finsi
  locale choix = l.choix[i]
  locale actuel = ""
  pour chaque e dans canevas:evenements(l.uid)
    si e.nom = l.evenement
      actuel = e.procedure
    finsi
  suivant
  faire cas
  cas i = 1
    si actuel = ""
      retourner
    finsi
    canevas:associer(l.evenement, "", l.uid)
    CON_ENREGISTRER()
    CON_ETAT(l.evenement + " : association retirée")
  cas i = #l.choix
    locale h = CON_NOUVELLE_PROCEDURE(l.evenement, l.uid)
    canevas:associer(l.evenement, h, l.uid)
    CON_ENREGISTRER()
    CON_INSPECTEUR()
    CON_ETAT("Procédure " + h + " créée dans " + fichier.nom(concode))
  autrement
    si majuscule(choix) = majuscule(actuel)
      retourner
    finsi
    canevas:associer(l.evenement, choix, l.uid)
    CON_ENREGISTRER()
    CON_ETAT(l.evenement + " → " + choix)
  fincas
retourner

fonction CON_NOUVELLE_PROCEDURE(evenement, uid)
  locale el = canevas:element(uid)
  locale noeud = sisinon(el.racine, VAR_FORMULAIRE(canevas:nom()), el.nom)
  locale base = majuscule(noeud + "_" + souschaine(evenement, 4))
  locale existantes = CON_TOUTES_PROCEDURES()
  locale h = base
  locale k = 2
  tantque existantes[h] <> nul
    h = base + k
    k += 1
  fintantque
  locale doc = ed:ouvrir(concode)
  locale r = INSERER_PROCEDURE(ed:texte(doc), canevas:nom(), h, evenement, noeud)
  ed:fixertexte(r.texte, doc)
  ed:aller(r.ligne, 3, doc)
retourner h

&&
&& Commandes de la barre d'outils
&&

procedure CON_SUPPRIMER
  canevas:supprimer()
retourner

procedure CON_MONTER
  canevas:monter()
retourner

procedure CON_DESCENDRE
  canevas:descendre()
retourner

procedure CON_SORTIR
  canevas:sortir()
retourner

procedure CON_FORMULAIRE
  canevas:selectionner()
  CON_ARBRE()
  CON_INSPECTEUR()
retourner

procedure CON_VOIR_CODE
  ed:ouvrir(concode)
  CON_ETAT("Code : " + concode)
retourner

procedure CON_CABLER
  locale nom = canevas:nom()
  locale src = TEXTE_DE(concode)
  locale code = ASSURER_BLOC(src, nom)
  locale r = ASSURER_APPEL(code, nom)
  locale note = ""
  si r.ajoute
    code = r.texte
    note = " ; appel " + PROC_OUVRIR(nom) + "() ajouté au programme principal"
  finsi
  si code <> src
    ECRIRE_CODE(code)
  finsi
  CON_ETAT(PROC_OUVRIR(nom) + "() ouvre le formulaire depuis " + fichier.nom(concode) + note)
retourner

procedure CON_PERSONNALISE
  locale genre = ui.demander("Nom du contrôle personnalisé (affiché dans la palette, ex. boutonrond) :", "")
  si genre = nul ou rogner(genre) = ""
    retourner
  finsi
  genre = rogner(genre)
  locale base = ui.demander("Contrôle existant dont il dérive (bouton, etiquette, saisie, conteneur…) :", "bouton")
  si base = nul
    retourner
  finsi
  locale expr = ui.demander("Expression Lexis+ qui crée le contrôle ($libelle, $texte… sont remplacés " + ;
                            "par les propriétés) :", majuscule(genre) + "($libelle)")
  si expr = nul
    retourner
  finsi
  locale msg = canevas:ajouterpersonnalise(dossier, genre, rogner(base), expr)
  si msg <> nul
    ui.alerte(msg, "stop", "Contrôle personnalisé")
    retourner
  finsi
  conctl.palette:redessiner()
  CON_ETAT(genre + " ajouté à la palette (wdlexis_palette.json)")
retourner

&&
&& Événements du canevas
&&

procedure CON_SELECTION(ev)
  CON_INSPECTEUR()
  locale sel = canevas:selection()
  pour chaque n dans conctl.noeuds
    si n.uid = sel
      conctl.arbre:selectionner(n.chemin)
    finsi
  suivant
retourner

procedure CON_CHANGEMENT(ev)
  CON_ENREGISTRER()
  CON_ARBRE()
  CON_INSPECTEUR()
retourner

&&
&& Câblage du code (bloc marqué, appel d'ouverture, renommage)
&&

fonction PROC_OUVRIR(nom)
retourner "FORM" + majuscule(nom) + "_OUVRIR"

fonction VAR_FORMULAIRE(nom)
retourner "form" + minuscule(nom)

fonction MARQUE_DEBUT(nom)
retourner "&& ---- formulaire « " + nom + " » : début (généré par le concepteur, gardez ces marques) ----"

fonction MARQUE_FIN(nom)
retourner "&& ---- formulaire « " + nom + " » : fin ----"

fonction LIGNES(src)
  locale l = decouper(src, car(10))
  si #l = 0
    l = {""}
  finsi
retourner l

fonction BLOC(l, nom)
  && {debut, fin} : lignes des marques (0 si absent)
  locale r = {debut = 0, fin = 0}
  pour i = 1 a #l
    si l[i] = MARQUE_DEBUT(nom)
      r.debut = i
    sinonsi l[i] = MARQUE_FIN(nom) et r.debut > 0
      r.fin = i
      retourner r
    finsi
  suivant
retourner r

fonction ASSURER_BLOC(src, nom)
  && ajoute le bloc marqué (vide) à la fin du code s'il manque
  locale l = LIGNES(src)
  si BLOC(l, nom).fin > 0
    retourner src
  finsi
  tantque #l > 0 et rogner(l[#l]) = ""
    retirer(l)
  fintantque
  si #l > 0
    inserer(l, "")
  finsi
  inserer(l, MARQUE_DEBUT(nom))
  inserer(l, "&& " + PROC_OUVRIR(nom) + "() ouvre le formulaire ; ses contrôles sont dans " + ;
             VAR_FORMULAIRE(nom) + " (" + VAR_FORMULAIRE(nom) + ".fenetre…).")
  inserer(l, "")
  inserer(l, MARQUE_FIN(nom))
  inserer(l, "")
retourner joindre(l, car(10))

fonction INSERER_PROCEDURE(src, nom, h, evenement, noeud)
  && procédure vide à la fin du bloc ; renvoie {texte, ligne} (ligne à compléter)
  locale l = LIGNES(ASSURER_BLOC(src, nom))
  locale f = BLOC(l, nom).fin
  locale ajout = {"procedure " + h + "(ev)", ;
                  "  && " + evenement + " de " + noeud + " (formulaire « " + nom + " »)", ;
                  "  ", "finprocedure", ""}
  pour k = #ajout a 1 pas -1
    inserer(l, ajout[k], f)
  suivant
retourner {texte = joindre(l, car(10)), ligne = f + 2}

fonction SANS_COMMENTAIRE(ligne)
  locale s = rogner(ligne)
  si commencepar(s, "&&") ou commencepar(s, "//") ou commencepar(s, "*")
    retourner ""
  finsi
  locale c = position("&&", s)
  si c > 0
    retourner gauche(s, c - 1)
  finsi
retourner s

fonction ASSURER_APPEL(src, nom)
  && programme principal : ajoute FORM<NOM>_OUVRIR() (et interface.executer()) s'il manque
  locale l = LIGNES(src)
  locale appel = minuscule(PROC_OUVRIR(nom)) + "("
  pour chaque ligne dans l
    si appel $ minuscule(SANS_COMMENTAIRE(ligne))
      retourner {texte = src, ajoute = faux}
    finsi
  suivant
  && fin du programme principal : première procédure / fonction / bloc de formulaire
  locale fin = #l + 1
  pour i = 1 a #l
    si ENTETE_PROCEDURE(l[i]) <> nul ou commencepar(l[i], "&& ---- formulaire « ")
      fin = i
      sortir
    finsi
  suivant
  && avant un ui.executer() / interface.executer() déjà présent
  pour i = 1 a fin - 1
    locale s = minuscule(SANS_COMMENTAIRE(l[i]))
    si "executer()" $ s et ("ui." $ s ou "interface." $ s)
      inserer(l, PROC_OUVRIR(nom) + "()", i)
      retourner {texte = joindre(l, car(10)), ajoute = vrai}
    finsi
  suivant
  locale a = fin
  tantque a > 1 et rogner(l[a - 1]) = ""
    a -= 1
  fintantque
  locale ajout = {PROC_OUVRIR(nom) + "()", "interface.executer()"}
  si a <= #l et rogner(l[a]) <> ""
    inserer(ajout, "")
  finsi
  si a > 1
    inserer(ajout, "", 1)
  finsi
  && nouvelle liste : lignes avant a, ajout, lignes à partir de a
  locale r = {}
  pour i = 1 a a - 1
    inserer(r, l[i])
  suivant
  pour chaque x dans ajout
    inserer(r, x)
  suivant
  pour i = a a #l
    inserer(r, l[i])
  suivant
retourner {texte = joindre(r, car(10)), ajoute = vrai}

fonction EST_LETTRE_MOT(c)
retourner c <> "" et position(c, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_") > 0

fonction REMPLACER_MOT(s, ancien, nouveau)
  && remplace le mot (insensible à la casse, limites de mot)
  locale bas = minuscule(s)
  locale cherche = minuscule(ancien)
  locale r = ""
  locale i = 1
  tantque i <= #s
    locale j = position(cherche, souschaine(bas, i))
    si j = 0
      r = r + souschaine(s, i)
      sortir
    finsi
    j = i + j - 1
    locale k = j + #cherche
    locale avant = (j = 1) ou non EST_LETTRE_MOT(souschaine(s, j - 1, 1))
    locale apres = (k > #s) ou non EST_LETTRE_MOT(souschaine(s, k, 1))
    r = r + souschaine(s, i, j - i)
    si avant et apres
      r = r + nouveau
    sinon
      r = r + souschaine(s, j, #cherche)
    finsi
    i = k
  fintantque
retourner r

fonction RENOMMER_CABLAGE(src, ancien, nouveau)
  locale r = remplacertexte(src, MARQUE_DEBUT(ancien), MARQUE_DEBUT(nouveau))
  r = remplacertexte(r, MARQUE_FIN(ancien), MARQUE_FIN(nouveau))
  r = REMPLACER_MOT(r, PROC_OUVRIR(ancien), PROC_OUVRIR(nouveau))
retourner REMPLACER_MOT(r, VAR_FORMULAIRE(ancien), VAR_FORMULAIRE(nouveau))
