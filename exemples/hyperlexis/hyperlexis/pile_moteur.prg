&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& pile_moteur.prg : moteur d'exécution des piles de cartes.
&&
&& Ce fichier est le même dans l'atelier HyperLexis et dans chaque pile
&& enregistrée (il y est recopié à chaque enregistrement) : une pile se lance
&& donc sans l'atelier, avec wdlexisrt, l'atelier wdlexis+ ou une application
&& générée par wdlexisgen.
&&
&& Une pile est une suite de cartes. Chaque carte utilise un modèle : le
&& formulaire form_<modele>.prg dessiné avec le concepteur (format commun avec
&& wdlexis+), dont les événements appellent les procédures de
&& script_<modele>.prg. Plusieurs cartes peuvent partager un modèle (comme les
&& cartes d'un même fond) : chacune garde alors ses propres données
&& (le contenu de ses champs).
&&
&& La carte est construite par la fonction FORM<MODELE>_OUVRIR() du formulaire,
&& appelée telle quelle : pendant l'appel, interface.fenetre est remplacée par
&& MOTEUR_HOTE, qui renvoie un panneau de la fenêtre de la pile au lieu d'ouvrir
&& une nouvelle fenêtre. Les contrôles restent donc dans la variable globale
&& form<modele> (formfiche.nom.valeur...), comme pour un formulaire ordinaire.
&&
&& Fonctions pour les scripts :
&&   ALLER_CARTE(cible)          nom, numéro, "suivante", "precedente", "premiere", "derniere", "retour"
&&   CARTE_SUIVANTE()  CARTE_PRECEDENTE()  PREMIERE_CARTE()  DERNIERE_CARTE()  CARTE_RETOUR()
&&   CARTE_COURANTE()  NUMERO_CARTE()  NOMBRE_CARTES()  LISTE_CARTES()  MODELE_CARTE([carte])
&&   NOUVELLE_CARTE([modele], [nom])   SUPPRIMER_CARTE([nom])
&&   CONTROLE(nom)               contrôle de la carte affichée
&&   CHAMP(nom, [carte])         contenu d'un champ ; FIXER_CHAMP(nom, valeur, [carte])
&&   DONNEE(cle)                 donnée de la pile ; FIXER_DONNEE(cle, valeur)
&&   TROUVER(texte)              va à la prochaine carte qui contient le texte
&&   MESSAGE(texte)              boîte de messages (atelier) ou console
&&   ENREGISTRER_PILE()  QUITTER_PILE()
&& Procédures facultatives du script de la pile (script_pile.prg) :
&&   SUR_OUVERTURE_PILE()  SUR_FERMETURE_PILE()
&&   SUR_OUVERTURE_CARTE(nom)  SUR_FERMETURE_CARTE(nom)
&& Les événements surouverture / surfermeture du formulaire (la « fenêtre » du
&& concepteur) sont ceux de la carte : appelés quand elle s'affiche et quand on
&& la quitte.

&&
&& Application autonome : point d'entrée appelé par principal.prg
&&

procedure PILE_DEMARRER
  globale hl_pile
  locale def = PILE_DEFINITION()
  locale dossier = systeme.dossierprogramme()
  locale donnees = MOTEUR_LIRE_JSON(dossier)
  si donnees = nul
    donnees = {}
    locale init = lexis.procedure("PILE_DONNEES_INITIALES")
    si init <> nul
      donnees = appeler(init)
    finsi
  finsi
  si donnees._CARTES <> nul et #donnees._CARTES > 0
    def.cartes = donnees._CARTES
  finsi
  locale larg = nombre(def.largeur) ou 640
  locale haut = nombre(def.hauteur) ou 480
  locale nav = def.navigation <> faux
  locale fen = interface.fenetre{titre = def.titre ou "Pile", largeur = larg + 24, ;
                                 hauteur = haut + 28 + sisinon(nav, 58, 0), disposition = "bordure"}
  fen.surfermeture = @MOTEUR_FERMETURE
  fen.surtouchebas = @MOTEUR_TOUCHE
  locale barre = nul
  si nav
    barre = fen:ajouter(interface.rangee())
    barre.ancrage = "bas"
  finsi
  locale vue = fen:ajouter(interface.panneau{defilement = "automatique"})
  vue.ancrage = "centre"
  vue.marge = 0
  MOTEUR_INITIALISER(vue, def, donnees, {fenetre = fen, persistance = def.persistance <> faux, dossier = dossier})
  si barre <> nul
    MOTEUR_BARRE(barre)
  finsi
  MOTEUR_CROCHET("SUR_OUVERTURE_PILE")
  ALLER_CARTE(1)
finprocedure

procedure MOTEUR_BARRE(barre)
  locale b = barre:ajouter(interface.bouton("⏮"))
  b.infobulle = "Première carte (Ctrl+Début)"
  b.surclic = @MOTEUR_NAV_PREMIERE
  b = barre:ajouter(interface.bouton("◀"))
  b.infobulle = "Carte précédente (Ctrl+←)"
  b.surclic = @MOTEUR_NAV_PRECEDENTE
  hl_pile.lblnav = barre:ajouter(interface.etiquette("", "centre"))
  hl_pile.lblnav.poids = 1
  b = barre:ajouter(interface.bouton("▶"))
  b.infobulle = "Carte suivante (Ctrl+→)"
  b.surclic = @MOTEUR_NAV_SUIVANTE
  b = barre:ajouter(interface.bouton("⏭"))
  b.infobulle = "Dernière carte (Ctrl+Fin)"
  b.surclic = @MOTEUR_NAV_DERNIERE
finprocedure

procedure MOTEUR_NAV_PREMIERE(ev)
  PREMIERE_CARTE()
finprocedure

procedure MOTEUR_NAV_PRECEDENTE(ev)
  CARTE_PRECEDENTE()
finprocedure

procedure MOTEUR_NAV_SUIVANTE(ev)
  CARTE_SUIVANTE()
finprocedure

procedure MOTEUR_NAV_DERNIERE(ev)
  DERNIERE_CARTE()
finprocedure

procedure MOTEUR_FERMETURE(ev)
  si hl_pile <> nul et hl_pile.actif
    MOTEUR_ARRETER()
  finsi
finprocedure

fonction MOTEUR_CTRL(m)
  && Ctrl (bits 0x00C0) ou Cmd (bits 0x0C00) dans les modificateurs SDL
  si m = nul
    retourner faux
  finsi
retourner (entier(m / 64) % 4 <> 0) ou (entier(m / 1024) % 4 <> 0)
finfonction

procedure MOTEUR_TOUCHE(ev)
  si non MOTEUR_CTRL(ev.modificateurs)
    retourner
  finsi
  si ev.id <> nul et ev.id.famille = "saisie"
    retourner                           && Ctrl+flèche dans un champ : déplacement par mot
  finsi
  faire cas
  cas ev.touche = 1073741903            && →
    CARTE_SUIVANTE()
  cas ev.touche = 1073741904            && ←
    CARTE_PRECEDENTE()
  cas ev.touche = 1073741898            && Début
    PREMIERE_CARTE()
  cas ev.touche = 1073741901            && Fin
    DERNIERE_CARTE()
  fincas
finprocedure

&&
&& Démarrage et arrêt (application autonome, ou mode Exécution de l'atelier)
&&

procedure MOTEUR_INITIALISER(vue, def, donnees, opts)
  && vue : conteneur qui reçoit la carte ; def : PILE_DEFINITION() ;
  && donnees : table des données (partagée, modifiée sur place) ;
  && opts : {fenetre, persistance, dossier, surmessage, surerreur, surcarte, surcartes}
  globale hl_pile
  si opts = nul
    opts = {}
  finsi
  si donnees._PILE = nul
    donnees._PILE = {}
  finsi
  hl_pile = {def = def, donnees = donnees, vue = vue, opts = opts, fenetre = opts.fenetre, ;
             hote = nul, f = nul, carte = "", index = 0, relais = {}, defauts = {}, ;
             historique = {}, actif = vrai, hotes = {}, lblnav = nul}
finprocedure

procedure MOTEUR_ARRETER
  && quitte la carte affichée (ses données sont relevées) et arrête la pile
  si hl_pile = nul ou non hl_pile.actif
    retourner
  finsi
  MOTEUR_QUITTER_CARTE()
  MOTEUR_CROCHET("SUR_FERMETURE_PILE")
  MOTEUR_ENREGISTRER()
  hl_pile.actif = faux
finprocedure

fonction MOTEUR_ACTIF()
retourner hl_pile <> nul et hl_pile.actif
finfonction

procedure MOTEUR_VERIFIER
  si hl_pile = nul ou non hl_pile.actif
    erreur "la pile n'est pas en exécution (mode Exécution de l'atelier, ou application lancée)"
  finsi
finprocedure

&&
&& Navigation
&&

fonction MOTEUR_CARTES()
retourner hl_pile.def.cartes
finfonction

fonction MOTEUR_INDEX(nom)
  locale n = majuscule(chaine(nom))
  locale l = MOTEUR_CARTES()
  pour i = 1 a #l
    si majuscule(l[i].nom) = n
      retourner i
    finsi
  suivant
retourner 0
finfonction

fonction MOTEUR_RESOUDRE(cible)
  && numéro de carte (0 si introuvable)
  locale n = #MOTEUR_CARTES()
  si n = 0
    retourner 0
  finsi
  si type(cible) = "nombre"
    retourner sisinon(cible >= 1 et cible <= n, entier(cible), 0)
  finsi
  locale c = minuscule(rogner(chaine(cible)))
  faire cas
  cas c = "suivante"
    retourner sisinon(hl_pile.index >= n, 1, hl_pile.index + 1)
  cas c = "precedente" ou c = "précédente"
    retourner sisinon(hl_pile.index <= 1, n, hl_pile.index - 1)
  cas c = "premiere" ou c = "première"
    retourner 1
  cas c = "derniere" ou c = "dernière"
    retourner n
  fincas
  si nombre(c) <> nul
    retourner MOTEUR_RESOUDRE(nombre(c))
  finsi
retourner MOTEUR_INDEX(c)
finfonction

fonction ALLER_CARTE(cible)
  MOTEUR_VERIFIER()
  si minuscule(chaine(cible)) = "retour"
    retourner CARTE_RETOUR()
  finsi
  locale i = MOTEUR_RESOUDRE(cible)
  si i = 0
    MOTEUR_ERREUR("carte introuvable : " + chaine(cible), "ALLER_CARTE")
    retourner faux
  finsi
  si hl_pile.carte <> ""
    inserer(hl_pile.historique, hl_pile.carte)
    si #hl_pile.historique > 100
      retirer(hl_pile.historique, 1)
    finsi
  finsi
retourner MOTEUR_AFFICHER(i)
finfonction

fonction CARTE_SUIVANTE()
retourner ALLER_CARTE("suivante")
finfonction

fonction CARTE_PRECEDENTE()
retourner ALLER_CARTE("precedente")
finfonction

fonction PREMIERE_CARTE()
retourner ALLER_CARTE("premiere")
finfonction

fonction DERNIERE_CARTE()
retourner ALLER_CARTE("derniere")
finfonction

fonction CARTE_RETOUR()
  MOTEUR_VERIFIER()
  tantque #hl_pile.historique > 0
    locale nom = retirer(hl_pile.historique)
    locale i = MOTEUR_INDEX(nom)
    si i > 0
      retourner MOTEUR_AFFICHER(i)
    finsi
  fintantque
retourner faux
finfonction

fonction CARTE_COURANTE()
  si hl_pile = nul
    retourner ""
  finsi
retourner hl_pile.carte
finfonction

fonction NUMERO_CARTE()
  si hl_pile = nul
    retourner 0
  finsi
retourner hl_pile.index
finfonction

fonction NOMBRE_CARTES()
  si hl_pile = nul
    retourner 0
  finsi
retourner #MOTEUR_CARTES()
finfonction

fonction LISTE_CARTES()
  locale l = {}
  pour chaque c dans MOTEUR_CARTES()
    inserer(l, c.nom)
  suivant
retourner l
finfonction

fonction MODELE_CARTE(carte)
  si carte = nul
    carte = hl_pile.carte
  finsi
  locale i = MOTEUR_INDEX(carte)
  si i = 0
    retourner ""
  finsi
retourner MOTEUR_CARTES()[i].modele
finfonction

&&
&& Affichage d'une carte
&&

fonction MOTEUR_AFFICHER(i)
  locale entree = MOTEUR_CARTES()[i]
  MOTEUR_QUITTER_CARTE()
  hl_pile.index = i
  hl_pile.carte = entree.nom
  si non MOTEUR_CONSTRUIRE(entree)
    retourner faux
  finsi
  locale titre = hl_pile.def.titre ou "Pile"
  si hl_pile.titrecarte <> nul et hl_pile.titrecarte <> ""
    titre = titre + " - " + hl_pile.titrecarte
  finsi
  si hl_pile.fenetre <> nul
    hl_pile.fenetre.titre = titre
  finsi
  si hl_pile.lblnav <> nul
    hl_pile.lblnav.libelle = "Carte " + i + " / " + #MOTEUR_CARTES() + "  ·  " + entree.nom
  finsi
  && la carte est prête : ses procédures d'ouverture
  MOTEUR_APPELER(hl_pile.ouverture, {genre = "ouverture", carte = entree.nom}, "surouverture de la carte " + entree.nom)
  MOTEUR_CROCHET("SUR_OUVERTURE_CARTE", entree.nom)
  si hl_pile.opts.surcarte <> nul
    appeler(hl_pile.opts.surcarte, entree.nom, i)
  finsi
retourner vrai
finfonction

fonction MOTEUR_HOTE(o)
  && remplace interface.fenetre pendant FORM<MODELE>_OUVRIR() : la « fenêtre » du
  && formulaire est un panneau de la pile, à la taille de la carte
  si o = nul
    o = {}
  finsi
  locale h = hl_pile.vue:ajouter(interface.panneau{disposition = o.disposition ou "absolue", defilement = "masque"})
  h.marge = 0
  h.largeurfixe = nombre(o.largeur) ou nombre(hl_pile.def.largeur) ou 640
  h.hauteurfixe = nombre(o.hauteur) ou nombre(hl_pile.def.hauteur) ou 480
  h.fond = hl_pile.def.couleur ou "#FFFFFF"
  hl_pile.hote = h
  hl_pile.titrecarte = o.titre
retourner h
finfonction

fonction MOTEUR_EVENEMENTS()
retourner {"surclic", "surdoubleclic", "surclicdroit", "surentree", "sursortie", "surfocus", "surfinfocus", ;
           "surtouchebas", "surchangement", "sursaisie", "surselection", "surdeploiement", "surrepli", "survalidation"}
finfonction

fonction MOTEUR_EST_DONNEE(famille)
  && contrôles dont la valeur est une donnée de la carte (conservée avec la pile)
retourner contient({"saisie", "cases", "radio", "combo", "liste", "compteur", "curseur", "plage", "jauge", ;
                    "notation", "ascenseur", "calendrier"}, famille)
finfonction

fonction MOTEUR_CONSTRUIRE(entree)
  globale hl_pile
  locale modele = entree.modele ou entree.nom
  locale p = lexis.procedure("FORM" + majuscule(modele) + "_OUVRIR")
  si p = nul
    MOTEUR_ERREUR("modèle introuvable : form_" + modele + ".prg (fonction FORM" + majuscule(modele) + "_OUVRIR)", ;
                  "carte " + entree.nom)
    retourner faux
  finsi
  hl_pile.hote = nul
  hl_pile.titrecarte = ""
  locale ancien = interface.fenetre
  interface.fenetre = @MOTEUR_HOTE
  locale f = nul
  locale echec = nul
  essayer
    f = appeler(p)
  capturer e
    echec = e
  finessayer
  interface.fenetre = ancien
  si echec <> nul
    si hl_pile.hote <> nul
      hl_pile.hote:detruire()
      hl_pile.hote = nul
    finsi
    MOTEUR_ERREUR(echec, "construction de la carte " + entree.nom + " (form_" + modele + ".prg)")
    retourner faux
  finsi
  hl_pile.f = f
  && événements : chaque gestionnaire passe par MOTEUR_RELAIS (erreurs interceptées)
  hl_pile.relais = {}
  hl_pile.defauts = {}
  locale hote = hl_pile.hote
  pour chaque k, c dans f
    si k <> "FENETRE" et type(c) = "objet"
      pour chaque evn dans MOTEUR_EVENEMENTS()
        locale h = c[evn]
        si h <> nul
          inserer(hl_pile.relais, {ctl = c, ev = evn, proc = h, nom = minuscule(k)})
          c[evn] = @MOTEUR_RELAIS
        finsi
      suivant
      si MOTEUR_EST_DONNEE(c.famille)
        hl_pile.defauts[k] = chaine(c.valeur)
      finsi
    finsi
  suivant
  hl_pile.ouverture = nul
  hl_pile.fermeture = nul
  si hote <> nul
    hl_pile.ouverture = hote.surouverture
    hl_pile.fermeture = hote.surfermeture
    hote.surouverture = nul
    hote.surfermeture = nul
    pour chaque evn dans {"surtouchebas", "surclic", "surredimension"}
      locale h = hote[evn]
      si h <> nul
        inserer(hl_pile.relais, {ctl = hote, ev = evn, proc = h, nom = "carte"})
        hote[evn] = @MOTEUR_RELAIS
      finsi
    suivant
  finsi
  && données de la carte
  locale d = hl_pile.donnees[majuscule(entree.nom)]
  si d <> nul
    pour chaque k, v dans d
      locale c = f[k]
      si c <> nul et type(c) = "objet"
        essayer
          c.valeur = v
        capturer e
        finessayer
      finsi
    suivant
  finsi
retourner vrai
finfonction

procedure MOTEUR_RELAIS(ev)
  pour chaque r dans hl_pile.relais
    si r.ctl = ev.courant et r.ev = "sur" + ev.genre
      MOTEUR_APPELER(r.proc, ev, r.ev + " de " + r.nom + " (carte " + hl_pile.carte + ")")
      retourner
    finsi
  suivant
finprocedure

procedure MOTEUR_QUITTER_CARTE
  && relève les données, appelle les procédures de fermeture et retire la carte
  si hl_pile.hote = nul
    retourner
  finsi
  locale nom = hl_pile.carte
  MOTEUR_APPELER(hl_pile.fermeture, {genre = "fermeture", carte = nom}, "surfermeture de la carte " + nom)
  MOTEUR_CROCHET("SUR_FERMETURE_CARTE", nom)
  MOTEUR_CAPTURER()
  si hl_pile.hote <> nul
    hl_pile.hote:detruire()
  finsi
  hl_pile.hote = nul
  hl_pile.f = nul
  hl_pile.relais = {}
  && application autonome : l'état est écrit à chaque changement de carte
  MOTEUR_ENREGISTRER()
finprocedure

procedure MOTEUR_CAPTURER
  && contenu des champs de la carte affichée -> données (seules les valeurs
  && différentes de celles du dessin sont gardées)
  si hl_pile.f = nul ou hl_pile.carte = ""
    retourner
  finsi
  locale cle = majuscule(hl_pile.carte)
  locale d = hl_pile.donnees[cle]
  si d = nul
    d = {}
  finsi
  pour chaque k, defaut dans hl_pile.defauts
    locale c = hl_pile.f[k]
    si c <> nul
      locale v = nul
      essayer
        v = chaine(c.valeur)
      capturer e
        v = nul
      finessayer
      si v <> nul
        si v = defaut
          d[k] = nul
        sinon
          d[k] = v
        finsi
      finsi
    finsi
  suivant
  si nbelements(d) > 0
    hl_pile.donnees[cle] = d
  sinon
    hl_pile.donnees[cle] = nul
  finsi
finprocedure

&&
&& Cartes créées ou supprimées pendant l'exécution
&&

fonction MOTEUR_NOM_LIBRE(base)
  locale n = 1
  tantque MOTEUR_INDEX(base + "_" + n) > 0
    n += 1
  fintantque
retourner base + "_" + n
finfonction

fonction NOUVELLE_CARTE(modele, nom)
  MOTEUR_VERIFIER()
  si modele = nul ou modele = ""
    modele = MODELE_CARTE()
  finsi
  si lexis.procedure("FORM" + majuscule(modele) + "_OUVRIR") = nul
    MOTEUR_ERREUR("modèle introuvable : " + modele, "NOUVELLE_CARTE")
    retourner ""
  finsi
  si nom = nul ou rogner(nom) = ""
    nom = MOTEUR_NOM_LIBRE(modele)
  finsi
  si MOTEUR_INDEX(nom) > 0
    MOTEUR_ERREUR("une carte s'appelle déjà « " + nom + " »", "NOUVELLE_CARTE")
    retourner ""
  finsi
  locale pos = hl_pile.index + 1
  inserer(MOTEUR_CARTES(), {nom = nom, modele = modele}, pos)
  MOTEUR_CARTES_MODIFIEES()
  ALLER_CARTE(pos)
retourner nom
finfonction

fonction SUPPRIMER_CARTE(nom)
  MOTEUR_VERIFIER()
  si nom = nul
    nom = hl_pile.carte
  finsi
  locale i = MOTEUR_INDEX(nom)
  si i = 0 ou #MOTEUR_CARTES() <= 1
    retourner faux
  finsi
  locale courante = (i = hl_pile.index)
  si courante
    MOTEUR_QUITTER_CARTE()
  finsi
  retirer(MOTEUR_CARTES(), i)
  hl_pile.donnees[majuscule(nom)] = nul
  MOTEUR_CARTES_MODIFIEES()
  si courante
    hl_pile.carte = ""
    MOTEUR_AFFICHER(min(i, #MOTEUR_CARTES()))
  sinonsi i < hl_pile.index
    hl_pile.index -= 1
  finsi
retourner vrai
finfonction

procedure MOTEUR_CARTES_MODIFIEES
  si hl_pile.opts.persistance
    hl_pile.donnees._CARTES = MOTEUR_CARTES()
  finsi
  si hl_pile.opts.surcartes <> nul
    appeler(hl_pile.opts.surcartes)
  finsi
finprocedure

&&
&& Contrôles, champs et données
&&

fonction CONTROLE(nom)
  MOTEUR_VERIFIER()
  si hl_pile.f = nul
    retourner nul
  finsi
retourner hl_pile.f[majuscule(nom)]
finfonction

fonction CHAMP(nom, carte)
  MOTEUR_VERIFIER()
  si carte = nul ou majuscule(carte) = majuscule(hl_pile.carte)
    locale c = CONTROLE(nom)
    si c <> nul
      retourner c.valeur
    finsi
    retourner nul
  finsi
  locale d = hl_pile.donnees[majuscule(carte)]
  si d = nul
    retourner nul
  finsi
retourner d[majuscule(nom)]
finfonction

procedure FIXER_CHAMP(nom, v, carte)
  MOTEUR_VERIFIER()
  si carte = nul ou majuscule(carte) = majuscule(hl_pile.carte)
    locale c = CONTROLE(nom)
    si c <> nul
      c.valeur = v
    finsi
    retourner
  finsi
  locale cle = majuscule(carte)
  si hl_pile.donnees[cle] = nul
    hl_pile.donnees[cle] = {}
  finsi
  hl_pile.donnees[cle][majuscule(nom)] = chaine(v)
finprocedure

fonction DONNEE(cle)
  si hl_pile = nul
    retourner nul
  finsi
retourner hl_pile.donnees._PILE[majuscule(cle)]
finfonction

procedure FIXER_DONNEE(cle, v)
  MOTEUR_VERIFIER()
  hl_pile.donnees._PILE[majuscule(cle)] = v
finprocedure

fonction TROUVER(quoi)
  && comme « find » des applications orientées cartes : à partir de la carte suivante,
  && la première carte dont un champ contient le texte (sans tenir compte de la casse)
  MOTEUR_VERIFIER()
  locale t = minuscule(chaine(quoi))
  si t = ""
    retourner faux
  finsi
  MOTEUR_CAPTURER()
  locale l = MOTEUR_CARTES()
  locale n = #l
  pour k = 1 a n
    locale i = ((hl_pile.index + k - 1) % n) + 1
    locale d = hl_pile.donnees[majuscule(l[i].nom)]
    si d <> nul
      pour chaque cle, v dans d
        si t $ minuscule(chaine(v))
          si i <> hl_pile.index
            ALLER_CARTE(i)
          finsi
          locale c = CONTROLE(cle)
          si c <> nul
            essayer
              c:focus()
            capturer e
            finessayer
          finsi
          retourner vrai
        finsi
      suivant
    finsi
  suivant
retourner faux
finfonction

procedure MESSAGE(t)
  si hl_pile <> nul et hl_pile.opts.surmessage <> nul
    appeler(hl_pile.opts.surmessage, texte(t))
  sinon
    ? t
  finsi
finprocedure

procedure ENREGISTRER_PILE
  MOTEUR_CAPTURER()
  MOTEUR_ENREGISTRER()
finprocedure

procedure QUITTER_PILE
  si hl_pile <> nul et hl_pile.fenetre <> nul
    MOTEUR_ARRETER()
    hl_pile.fenetre:fermer()
  sinon
    MESSAGE("QUITTER_PILE : sans effet dans l'atelier (revenez en mode Conception)")
  finsi
finprocedure

&&
&& Persistance : pile_donnees.json à côté du programme (application autonome)
&&

fonction MOTEUR_FICHIER_JSON(dossier)
retourner fichier.joindre(dossier, "pile_donnees.json")
finfonction

fonction MOTEUR_LIRE_JSON(dossier)
  locale p = MOTEUR_FICHIER_JSON(dossier)
  si non fichier.existe(p)
    retourner nul
  finsi
  essayer
    retourner dejson(fichier.lire(p))
  capturer e
  finessayer
retourner nul
finfonction

procedure MOTEUR_ENREGISTRER
  si hl_pile = nul ou non hl_pile.opts.persistance ou hl_pile.opts.dossier = nul
    retourner
  finsi
  essayer
    fichier.ecrire(MOTEUR_FICHIER_JSON(hl_pile.opts.dossier), json(hl_pile.donnees))
  capturer e
    && dossier en lecture seule (paquet .app...) : les données restent en mémoire
  finessayer
finprocedure

&&
&& Appels protégés
&&

procedure MOTEUR_APPELER(proc, arg, contexte)
  si proc = nul
    retourner
  finsi
  essayer
    appeler(proc, arg)
  capturer e
    MOTEUR_ERREUR(e, contexte)
  finessayer
finprocedure

procedure MOTEUR_CROCHET(nom, arg)
  && procédure facultative du script de la pile (SUR_OUVERTURE_PILE...)
  locale p = lexis.procedure(nom)
  si p = nul
    retourner
  finsi
  essayer
    appeler(p, arg)
  capturer e
    MOTEUR_ERREUR(e, nom)
  finessayer
finprocedure

procedure MOTEUR_ERREUR(message, contexte)
  locale m = texte(message)
  si contexte <> nul et contexte <> ""
    m = m + "  [" + contexte + "]"
  finsi
  si hl_pile <> nul et hl_pile.opts.surerreur <> nul
    appeler(hl_pile.opts.surerreur, m)
  sinon
    ? "[erreur] " + m
    essayer
      interface.alerte(m, "stop", "Erreur dans la pile")
    capturer e
    finessayer
  finsi
finprocedure
