&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ : ensembles de pages affichés, masqués ou détachés dans une fenêtre
&& dédiée, comme le panneau Objets / Chercher / Favoris / Récents / Propriétés d'Atlas SQL.
&&
&& Un ensemble = un emplacement (hote, dans un séparateur de la fenêtre principale) qui
&& contient des onglets (contenu), un bouton à deux états << / >> (masquer / afficher) et
&& un bouton « fenêtre dédiée » (détacher / rattacher). Fermer la fenêtre dédiée rattache.
&& Le séparateur garde sa position : l'ensemble revient à la même taille.

&& La table globale « ensembles » (par nom : GAUCHE, BAS, PALETTE, PALETTEETAT) est
&& déclarée dans principal.prg.

fonction ENSEMBLE(nom, titre, hote, contenu, bmasquer, bfenetre, largeur, hauteur, icmasque, icaffiche)
  locale e = {nom = nom, titre = titre, hote = hote, contenu = contenu, bmasquer = bmasquer, ;
              bfenetre = bfenetre, largeur = largeur, hauteur = hauteur, masque = faux, ;
              icmasque = icmasque, icaffiche = icaffiche}
  ensembles[majuscule(nom)] = e
  ENSEMBLE_ETAT(e)
retourner e

procedure ENSEMBLE_ETAT(e)
  && symboles et infobulles des deux boutons selon l'état
  locale detache = e.fen <> nul
  si detache
    e.bmasquer.icone = e.icmasque
    e.bmasquer.infobulle = "Rattacher « " + e.titre + " » à la fenêtre principale"
    e.bfenetre.icone = "rattacher"
    e.bfenetre.infobulle = "Rattacher « " + e.titre + " » à la fenêtre principale"
  sinon
    e.bmasquer.icone = sisinon(e.masque, e.icaffiche, e.icmasque)
    e.bmasquer.infobulle = sisinon(e.masque, "Afficher « " + e.titre + " » (>>)", ;
                                   "Masquer « " + e.titre + " » (<<)")
    e.bfenetre.icone = "fenetre"
    e.bfenetre.infobulle = "Afficher « " + e.titre + " » dans une fenêtre dédiée"
  finsi
retourner

procedure ENSEMBLE_MASQUER(e, v)
  e.masque = v
  si e.fen = nul
    e.hote.visible = non v
  finsi
  ENSEMBLE_ETAT(e)
retourner

procedure ENSEMBLE_BASCULER(e)
  && bouton à deux états : masque ou affiche (détaché : rattache)
  si e.fen <> nul
    ENSEMBLE_RATTACHER(e)
  sinon
    ENSEMBLE_MASQUER(e, non e.masque)
  finsi
retourner

procedure ENSEMBLE_FENETRE(e, gestionnaire)
  && détache les pages dans une fenêtre dédiée (ou les rattache si elles le sont déjà)
  si e.fen <> nul
    ENSEMBLE_RATTACHER(e)
    retourner
  finsi
  locale f = ui.fenetre{titre = e.titre + " - wdlexis+", largeur = e.largeur, hauteur = e.hauteur, ;
                        disposition = "bordure", sombre = reglages.sombre, densite = "compacte"}
  f.marge = 0
  f.surfermeture = gestionnaire
  f.surtouchebas = @TOUCHE_FENETRE
  e.fen = f
  f:ajouter(e.contenu)
  e.contenu.ancrage = "centre"
  e.hote.visible = faux
  ENSEMBLE_ETAT(e)
retourner

procedure ENSEMBLE_RATTACHER(e)
  && ramène les pages dans la fenêtre principale, puis ferme la fenêtre dédiée
  locale f = e.fen
  e.fen = nul
  e.masque = faux
  e.hote:ajouter(e.contenu)
  e.contenu.ancrage = "centre"
  e.hote.visible = vrai
  si f <> nul
    essayer
      f:fermer()
    capturer err
    finessayer
  finsi
  ENSEMBLE_ETAT(e)
retourner

procedure ENSEMBLE_FERME(e)
  && fenêtre fermée par sa case : les pages reviennent dans la fenêtre principale
  si e.fen <> nul
    e.fen = nul
    e.masque = faux
    e.hote:ajouter(e.contenu)
    e.contenu.ancrage = "centre"
    e.hote.visible = vrai
    ENSEMBLE_ETAT(e)
  finsi
retourner

procedure ENSEMBLE_THEME(sombre)
  && thème clair / sombre des fenêtres dédiées ouvertes
  pour chaque k, e dans ensembles
    si e.fen <> nul
      e.fen:fixertheme("natif", sombre, "compacte")
    finsi
  suivant
retourner

&& Gestionnaires des boutons et des fenêtres (un par ensemble)

procedure GAUCHE_BASCULER(ev)
  ENSEMBLE_BASCULER(ensembles.gauche)
retourner

procedure GAUCHE_FENETRE(ev)
  ENSEMBLE_FENETRE(ensembles.gauche, @GAUCHE_FERME)
retourner

procedure GAUCHE_FERME(ev)
  ENSEMBLE_FERME(ensembles.gauche)
retourner

procedure BAS_BASCULER(ev)
  ENSEMBLE_BASCULER(ensembles.bas)
retourner

procedure BAS_FENETRE(ev)
  ENSEMBLE_FENETRE(ensembles.bas, @BAS_FERME)
retourner

procedure BAS_FERME(ev)
  ENSEMBLE_FERME(ensembles.bas)
retourner

procedure PALETTE_BASCULER(ev)
  ENSEMBLE_BASCULER(ensembles.palette)
retourner

procedure PALETTE_FENETRE(ev)
  ENSEMBLE_FENETRE(ensembles.palette, @PALETTE_FERME)
retourner

procedure PALETTE_FERME(ev)
  ENSEMBLE_FERME(ensembles.palette)
retourner

procedure PALETTEETAT_BASCULER(ev)
  ENSEMBLE_BASCULER(ensembles.paletteetat)
retourner

procedure PALETTEETAT_FENETRE(ev)
  ENSEMBLE_FENETRE(ensembles.paletteetat, @PALETTEETAT_FERME)
retourner

procedure PALETTEETAT_FERME(ev)
  ENSEMBLE_FERME(ensembles.paletteetat)
retourner

procedure AFFICHER_ENSEMBLE(nom)
  && rend visible un ensemble masqué (ex. Variables à l'arrêt du débogueur)
  locale e = ensembles[majuscule(nom)]
  si e <> nul et e.masque et e.fen = nul
    ENSEMBLE_MASQUER(e, faux)
  finsi
retourner

&& Barre à symboles : bouton plat, libellé en infobulle
fonction OUTIL_SYMBOLE(barre_, icone, libelle, bulle, proc)
  locale b = barre_:ajouter(ui.bouton(libelle, {icone = icone, bulle = bulle}))
  si proc <> nul
    b.surclic = proc
  finsi
retourner b

procedure ESPACE(barre_, largeur)
  locale s = barre_:ajouter(ui.etiquette(""))
  si largeur = nul
    s.poids = 1
  sinon
    s.largeurfixe = largeur
  finsi
retourner
