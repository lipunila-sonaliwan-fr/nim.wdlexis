&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ : éditeur d'états (le même que celui de l'atelier natif).
&&
&& Natif (paquet interface) : le canevas ui.etat (zones à l'échelle, glisser-déposer,
&& poignées, repères, hauteur des zones), la palette ui.paletteetat, le modèle de
&& l'état, la mise en page et l'écriture du PDF (aperçu), la génération de
&& etat_<nom>.prg (format commun aux deux ateliers).
&& Ici, en Lexis+ : la fenêtre de l'éditeur, la hiérarchie, l'inspecteur, le
&& renommage, l'enregistrement, l'aperçu dans la visionneuse PDF et l'insertion
&& du code d'exemple dans l'éditeur.
&& Les procédures TEXTE_DE, CON_OUTIL, AFFICHE_CHOIX et LIGNE_DE sont celles de concepteur.prg.

&&
&& Ouverture
&&

procedure ETAT_NOUVEAU
  ETAT_OUVRIR(nul)
retourner

procedure ETAT_CHOISIR
  si dossier = ""
    ETAT_OUVRIR(nul)
    retourner
  finsi
  locale p = ui.ouvrirfichier{titre = "Ouvrir un état", dossier = dossier, filtre = "États Lexis+ (etat_*.prg)|*.prg"}
  si p = nul
    retourner
  finsi
  si non EST_ETAT(p)
    ui.alerte("Choisissez un fichier etat_<nom>.prg créé par l'éditeur d'états.", "information", "Éditeur d'états")
    retourner
  finsi
  ETAT_OUVRIR(p)
retourner

fonction EST_ETAT(p)
  locale n = minuscule(fichier.nom(p))
retourner commencepar(n, "etat_") et finitpar(n, ".prg")

fonction PROCHAIN_ETAT()
  locale n = 1
  tantque fichier.existe(fichier.joindre(dossier, "etat_etat" + n + ".prg"))
    n += 1
  fintantque
retourner "etat" + n

fonction CHEMIN_ETAT(nom)
retourner fichier.joindre(dossier, "etat_" + nom + ".prg")

procedure ETAT_OUVRIR(chemin)
  globale etdlg, etcanevas
  si etdlg <> nul
    etat.libelle = "L'éditeur d'états est déjà ouvert."
    retourner
  finsi
  si dossier = ""
    ui.alerte("Ouvrez d'abord un projet (Fichier > Ouvrir un projet…).", "information", "Éditeur d'états")
    retourner
  finsi
  essayer
    si chemin = nul
      etcanevas = ui.etat{projet = dossier, nom = PROCHAIN_ETAT()}
    sinon
      && le document ouvert dans l'éditeur fait foi s'il a été modifié
      locale uid = ed:chercherdocument(chemin)
      si uid <> nul et ed:modifie(uid)
        ed:enregistrer(nul, uid)
      finsi
      etcanevas = ui.etat{projet = dossier, fichier = chemin}
    finsi
  capturer e
    ui.alerte(e, "stop", "Éditeur d'états")
    retourner
  finessayer
  ETAT_FENETRE()
  ET_ENREGISTRER()
  ET_ARBRE()
  ET_INSPECTEUR()
  etat.libelle = "Éditeur d'états : etat_" + etcanevas:nom() + ".prg"
retourner

procedure ETAT_FENETRE
  globale etdlg, etctl
  etctl = {lignes = {}, noeuds = {}, nomligne = nul}
  etdlg = ui.fenetre{titre = "Éditeur d'états", largeur = 1320, hauteur = 860, ;
                     disposition = "bordure", sombre = reglages.sombre}
  etdlg.surfermeture = @ET_FERMETURE
  && barre d'outils
  locale outils = etdlg:ajouter(ui.rangee())
  outils.ancrage = "haut"
  CON_OUTIL(outils, "Enregistrer", @ET_ENREGISTRER, "Régénère etat_<nom>.prg")
  CON_OUTIL(outils, "Supprimer", @ET_SUPPRIMER, "Supprime l'élément ou la zone sélectionné (Suppr)")
  CON_OUTIL(outils, "Monter", @ET_MONTER, "Zone : plus haut dans l'état ; élément : dessiné plus tôt")
  CON_OUTIL(outils, "Descendre", @ET_DESCENDRE, "Zone : plus bas dans l'état ; élément : dessiné plus tard")
  CON_OUTIL(outils, "Nouvelle zone", @ET_ZONE, "Ajoute une zone nommée après la zone sélectionnée")
  CON_OUTIL(outils, "État", @ET_ETAT, "Sélectionne l'état (format, orientation, marges)")
  CON_OUTIL(outils, "Aperçu PDF", @ET_APERCU, "Génère le PDF avec chaque zone trois fois, variables affichées")
  CON_OUTIL(outils, "Insérer le code", @ET_CODE, "Insère dans l'éditeur le code Lexis+ qui remplit l'état")
  CON_OUTIL(outils, "Zoom +", @ET_ZOOM_PLUS, "Agrandit la page")
  CON_OUTIL(outils, "Zoom −", @ET_ZOOM_MOINS, "Réduit la page")
  && barre d'état
  etctl.etat = etdlg:ajouter(ui.etiquette("Glisser depuis la palette · bord bas d'une zone : hauteur · " + ;
                                          "Suppr supprime · flèches : 0,5 mm (Maj : 5 mm)"))
  etctl.etat.ancrage = "bas"
  && palette
  locale cg = etdlg:ajouter(ui.colonne())
  cg.ancrage = "gauche"
  cg.largeurfixe = 200
  cg:ajouter(ui.etiquette("PALETTE"))
  etctl.palette = cg:ajouter(ui.paletteetat(etcanevas))
  etctl.palette.poids = 1
  && hiérarchie et inspecteur
  locale cd = etdlg:ajouter(ui.colonne())
  cd.ancrage = "droite"
  cd.largeurfixe = 360
  cd:ajouter(ui.etiquette("HIÉRARCHIE"))
  etctl.arbre = cd:ajouter(ui.arbre())
  etctl.arbre.hauteurfixe = 220
  etctl.arbre.surselection = @ET_ARBRE_CHOIX
  etctl.titre = cd:ajouter(ui.etiquette(""))
  etctl.titre.couleur = "#3B82F6"
  etctl.insp = cd:ajouter(ui.panneau{defilement = "automatique"})
  etctl.insp.poids = 1
  etctl.contenu = etctl.insp:ajouter(ui.superconteneur("vertical"))
  && page de l'état
  locale centre = etdlg:ajouter(ui.panneau{defilement = "automatique"})
  centre.ancrage = "centre"
  centre:ajouter(etcanevas)
  etcanevas.surselection = @ET_SELECTION
  etcanevas.surchangement = @ET_CHANGEMENT
  etcanevas:focus()
retourner

procedure ET_FERMETURE(ev)
  globale etdlg, etcanevas
  etdlg = nul
  etcanevas = nul
retourner

procedure ET_ETAT_MESSAGE(message)
  si etdlg <> nul
    etctl.etat.libelle = message
  finsi
retourner

&&
&& Enregistrement : etat_<nom>.prg (fonction ETAT_<NOM>() lue par rapport.debut)
&&

procedure ET_ENREGISTRER
  si etcanevas = nul
    retourner
  finsi
  locale nom = etcanevas:nom()
  locale p = CHEMIN_ETAT(nom)
  locale nouveau = non fichier.existe(p)
  locale code = etcanevas:code()
  fichier.ecrire(p, code)
  locale uid = ed:chercherdocument(p)
  si uid <> nul
    ed:fixertexte(code, uid, vrai)
  finsi
  etdlg.titre = "Éditeur d'états - etat_" + nom + ".prg"
  ET_ETAT_MESSAGE("Enregistré : etat_" + nom + ".prg  ·  rapport.debut(" + car(34) + nom + ".pdf" + car(34) + ")")
  si nouveau
    ARBRE_PROJET()
  finsi
retourner

&&
&& Hiérarchie : état > zones > éléments
&&

procedure ET_ARBRE
  etctl.arbre:vider()
  etctl.noeuds = {}
  locale sel = etcanevas:selection()
  locale chemin_sel = ""
  pour chaque n dans etcanevas:noeuds()
    etctl.arbre:ajouter(n.chemin)
    inserer(etctl.noeuds, {chemin = n.chemin, uid = n.uid})
    si n.uid = sel
      chemin_sel = n.chemin
    finsi
  suivant
  pour chaque n dans etcanevas:noeuds()
    si n.conteneur
      etctl.arbre:deplier(n.chemin)
    finsi
  suivant
  si chemin_sel <> ""
    etctl.arbre:selectionner(chemin_sel)
  finsi
retourner

procedure ET_ARBRE_CHOIX(ev)
  pour chaque n dans etctl.noeuds
    si n.chemin = ev.texte
      si n.uid <> etcanevas:selection()
        etcanevas:selectionner(n.uid)
        ET_INSPECTEUR()
      finsi
      retourner
    finsi
  suivant
retourner

&&
&& Inspecteur
&&

fonction ET_LIGNE(libelle)
  locale r = etctl.contenu:ajouter(ui.superconteneur("horizontal"))
  r.espacement = 6
  locale l = r:ajouter(ui.etiquette(libelle))
  l.largeurfixe = 112
retourner r

procedure ET_INSPECTEUR
  si etcanevas = nul
    retourner
  finsi
  locale el = etcanevas:element()
  etctl.contenu:detruire()
  etctl.contenu = etctl.insp:ajouter(ui.superconteneur("vertical"))
  etctl.contenu.espacement = 4
  etctl.contenu.largeurfixe = 300
  etctl.lignes = {}
  etctl.titre.libelle = el.titre
  etctl.contenu:ajouter(ui.etiquette(sisinon(el.genre = "etat", "PROPRIÉTÉS", "PROPRIÉTÉS   (mm)")))
  && nom (pour l'état : nom du fichier etat_<nom>.prg)
  locale r = ET_LIGNE(sisinon(el.genre = "etat", "nom (fichier)", "nom"))
  locale sn = r:ajouter(ui.saisie(el.nom))
  sn.poids = 1
  sn.infobulle = "Entrée (ou sortie du champ) pour renommer"
  sn.surtouchebas = @ET_NOM_TOUCHE
  sn.surfinfocus = @ET_NOM_SORTIE
  etctl.nomligne = {ctl = sn, uid = el.uid}
  pour chaque p dans etcanevas:proprietes()
    r = ET_LIGNE(p.nom)
    locale c = nul
    faire cas
    cas p.genre = "logique"
      c = r:ajouter(ui.cases(""))
      c:cocher(1, p.valeur = "true")
      c.surchangement = @ET_PROP
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
      c.surselection = @ET_PROP
    autrement
      c = r:ajouter(ui.saisie(p.valeur))
      c.surchangement = @ET_PROP
    fincas
    c.poids = 1
    locale ligne = {ctl = c, prop = p.nom, genre = p.genre, choix = p.choix, cible = p.cible}
    si p.genre = "couleur"
      locale b = r:ajouter(ui.bouton("…"))
      b.largeurfixe = 36
      b.surclic = @ET_COULEUR
      ligne.bouton = b
    finsi
    inserer(etctl.lignes, ligne)
  suivant
  si el.aide <> ""
    locale aide = etctl.contenu:ajouter(ui.etiquette(el.aide))
    aide.couleur = "#8A8F98"
  finsi
retourner

procedure ET_PROP(ev)
  locale l = LIGNE_DE(etctl.lignes, ev.id)
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
  locale msg = etcanevas:fixerpropriete(l.prop, v, l.cible)
  si msg <> nul
    ET_ETAT_MESSAGE(msg)
    retourner
  finsi
  ET_ENREGISTRER()
  && hauteur, format, orientation ou marges : la hiérarchie et la page changent
  si l.cible = "geom" ou l.prop = "format" ou l.prop = "orientation"
    ET_ARBRE()
  finsi
retourner

procedure ET_COULEUR(ev)
  pour chaque l dans etctl.lignes
    si l.bouton <> nul et l.bouton = ev.id
      locale c = ui.couleur(sisinon(commencepar(l.ctl.valeur, "#"), l.ctl.valeur, "#000000"))
      si c <> nul
        l.ctl.valeur = c
        locale msg = etcanevas:fixerpropriete(l.prop, c, l.cible)
        si msg <> nul
          ET_ETAT_MESSAGE(msg)
        sinon
          ET_ENREGISTRER()
        finsi
      finsi
      retourner
    finsi
  suivant
retourner

&&
&& Nom : appliqué par Entrée ou à la sortie du champ (renommer l'état renomme son fichier)
&&

procedure ET_NOM_TOUCHE(ev)
  si ev.touche = 13 ou ev.touche = 1073741912
    ET_NOM(ev.id)
  finsi
retourner

procedure ET_NOM_SORTIE(ev)
  ET_NOM(ev.id)
retourner

procedure ET_NOM(ctl)
  locale l = etctl.nomligne
  si l = nul ou non (l.ctl = ctl)
    retourner
  finsi
  locale v = rogner(ctl.valeur)
  si v = ""
    retourner
  finsi
  locale r = etcanevas:renommer(l.uid, v, dossier)
  si r.message <> nul
    ET_ETAT_MESSAGE(r.message)
    retourner
  finsi
  si r.ancien <> nul
    && l'ancien fichier disparaît, avec son onglet
    locale p = CHEMIN_ETAT(r.ancien)
    locale uid = ed:chercherdocument(p)
    si uid <> nul
      ed:fermer(uid)
    finsi
    essayer
      fichier.supprimer(p)
    capturer e
    finessayer
  finsi
  ET_ENREGISTRER()
  si r.ancien <> nul
    ARBRE_PROJET()
    ET_ETAT_MESSAGE("État renommé : etat_" + v + ".prg (pensez à rapport.debut(" + car(34) + v + ".pdf" + car(34) + "))")
  finsi
  ET_ARBRE()
  ET_INSPECTEUR()
retourner

&&
&& Barre d'outils
&&

procedure ET_SUPPRIMER
  etcanevas:supprimer()
retourner

procedure ET_MONTER
  etcanevas:monter()
retourner

procedure ET_DESCENDRE
  etcanevas:descendre()
retourner

procedure ET_ZONE
  etcanevas:nouvellezone()
retourner

procedure ET_ETAT
  etcanevas:selectionner()
  ET_ARBRE()
  ET_INSPECTEUR()
retourner

procedure ET_ZOOM_PLUS
  ET_ETAT_MESSAGE("Zoom : " + etcanevas:zoom(1.25) + " %")
retourner

procedure ET_ZOOM_MOINS
  ET_ETAT_MESSAGE("Zoom : " + etcanevas:zoom(0.8) + " %")
retourner

procedure ET_CODE
  si ed:actif() = nul ou ed:actif() < 0
    ET_ETAT_MESSAGE("Ouvrez d'abord un fichier .prg dans l'atelier")
    retourner
  finsi
  ed:inserer(etcanevas:codeexemple())
  ET_ETAT_MESSAGE("Code d'exemple inséré dans l'éditeur, au curseur")
retourner

procedure ET_APERCU
  locale p = fichier.joindre(fichier.dossiertemp(), "wdlexis_apercu_" + etcanevas:nom() + ".pdf")
  locale r = nul
  essayer
    r = etcanevas:apercu(p, dossier)
  capturer e
    ET_ETAT_MESSAGE("Aperçu impossible : " + e)
    retourner
  finessayer
  si r.erreurs <> ""
    ET_ETAT_MESSAGE("Images illisibles : " + r.erreurs)
  finsi
  && visionneuse PDF (PDFium) ; à défaut, le chemin du fichier
  locale f = ui.fenetre{titre = "Aperçu - " + etcanevas:nom() + ".pdf", largeur = 860, hauteur = 860, ;
                        sombre = reglages.sombre}
  locale v = f:ajouter(ui.pdf())
  v.poids = 1
  si non v:ouvrir(r.chemin)
    f:fermer()
    ui.alerte("Aperçu écrit dans :" + car(10) + r.chemin + car(10) + car(10) + ;
              "(visionneuse PDF indisponible : bibliothèque PDFium absente)", "information", "Aperçu PDF")
  finsi
retourner

&&
&& Événements du canevas
&&

procedure ET_SELECTION(ev)
  ET_INSPECTEUR()
  locale sel = etcanevas:selection()
  pour chaque n dans etctl.noeuds
    si n.uid = sel
      etctl.arbre:selectionner(n.chemin)
    finsi
  suivant
retourner

procedure ET_CHANGEMENT(ev)
  ET_ENREGISTRER()
  ET_ARBRE()
  ET_INSPECTEUR()
retourner
