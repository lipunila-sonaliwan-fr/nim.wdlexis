&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& DuckDB Studio : concepteur de connexions (nom, description, type, paramètres,
&& authentification, options), test et ping, enregistrement dans le projet.

procedure NOUVELLE_CONNEXION
  CONNEXION_DIALOGUE(nul, "duckdb")
retourner

procedure CONNEXION_DIALOGUE(c, type)
  globale condlg, conctl
  si condlg <> nul
    retourner
  finsi
  conctl = {edition = c, types = TYPES_CONNECTEURS(), champs = {}, nomsoptions = {}}
  si c <> nul
    type = c.type
  finsi
  condlg = ui.fenetre{titre = sisinon(c = nul, "Nouvelle connexion", "Connexion « " + sisinon(c = nul, "", c.nom) + " »"), ;
                      largeur = 680, hauteur = 760, disposition = "bordure", sombre = reglages.sombre}
  condlg.surfermeture = @CON_FERMETURE
  locale haut = condlg:ajouter(ui.cadre("Connexion", "grille"))
  haut.ancrage = "haut"
  haut:ajouter(ui.etiquette("Nom"))
  conctl.nom = haut:ajouter(ui.saisie{texte = sisinon(c = nul, "", c.nom), indication = "ventes"})
  haut:ajouter(ui.etiquette("Description"))
  conctl.description = haut:ajouter(ui.saisie{texte = sisinon(c = nul, "", c.description), indication = "Base des ventes"})
  haut:ajouter(ui.etiquette("Type"))
  conctl.type = haut:ajouter(ui.combo())
  pour i = 1 a #conctl.types
    conctl.type:ajouter(conctl.types[i].libelle)
    si conctl.types[i].type = type
      conctl.type:selectionner(i)
    finsi
  suivant
  conctl.type.surselection = @CON_TYPE
  && bas : état du test et boutons
  locale bas_ = condlg:ajouter(ui.rangee())
  bas_.ancrage = "bas"
  conctl.statut = bas_:ajouter(ui.etiquette(""))
  conctl.statut.poids = 1
  locale bt = bas_:ajouter(ui.bouton("Tester"))
  bt.surclic = @CON_TESTER
  locale be = bas_:ajouter(ui.bouton("Enregistrer", {defaut = vrai}))
  be.surclic = @CON_ENREGISTRER
  locale ba = bas_:ajouter(ui.bouton("Annuler", {annuler = vrai}))
  ba.surclic = @CON_ANNULER
  conctl.centre = condlg:ajouter(ui.colonne())
  conctl.centre.ancrage = "centre"
  CON_PARAMETRES()
  conctl.nom:focus()
retourner

fonction CON_CONNECTEUR()
  locale i = conctl.type:selection()
  si i = nul ou i < 1
    i = 1
  finsi
retourner conctl.types[i]

procedure CON_PARAMETRES
  && champs du type choisi (reconstruits à chaque changement de type)
  locale k = CON_CONNECTEUR()
  locale c = conctl.edition
  si conctl.zone <> nul
    conctl.zone:detruire()
  finsi
  conctl.zone = conctl.centre:ajouter(ui.colonne())
  conctl.zone.poids = 1
  conctl.champs = {}
  locale g = conctl.zone:ajouter(ui.cadre(k.libelle + "  -  paramètres", "grille"))
  pour chaque p dans k.parametres
    g:ajouter(ui.etiquette(p.libelle + sisinon(p.secret = vrai, " (secret)", "")))
    locale v = sisinon(p.defaut = nul, "", p.defaut)
    si c <> nul et c.type = k.type
      v = VALEUR_PARAM(c, p.nom)
    finsi
    locale s = ui.saisie{texte = chaine(v), indication = sisinon(p.defaut = nul, "", chaine(p.defaut)), ;
                         motdepasse = p.secret = vrai}
    s.surchangement = @CON_APERCU
    si p.fichier = vrai ou p.dossier = vrai
      locale ligne = g:ajouter(ui.superconteneur("horizontal"))
      ligne:ajouter(s)
      s.poids = 1
      locale b = ligne:ajouter(ui.bouton("…"))
      b.infobulle = "Choisir"
      b.surclic = @CON_PARCOURIR
      conctl.parcourir = {champ = s, dossier = p.dossier = vrai}
    sinon
      g:ajouter(s)
    finsi
    conctl.champs[majuscule(p.nom)] = s
  suivant
  si #k.parametres = 0
    g:ajouter(ui.etiquette("Aucun paramètre"))
    g:ajouter(ui.etiquette(""))
  finsi
  conctl.nomsoptions = {}
  conctl.options = nul
  si k.options <> nul et #k.options > 0
    locale libelles = {}
    pour chaque o dans k.options
      inserer(libelles, o.libelle)
      inserer(conctl.nomsoptions, o.nom)
    suivant
    si #libelles = 1
      conctl.options = conctl.zone:ajouter(ui.cases(libelles[1]))
    sinonsi #libelles = 2
      conctl.options = conctl.zone:ajouter(ui.cases(libelles[1], libelles[2]))
    sinon
      conctl.options = conctl.zone:ajouter(ui.cases(libelles[1], libelles[2], libelles[3]))
    finsi
    pour i = 1 a #k.options
      locale coche = k.options[i].defaut = vrai
      si c <> nul et c.type = k.type
        coche = OPTION_COCHEE(c, k.options[i].nom)
      finsi
      conctl.options:cocher(i, coche)
    suivant
    conctl.options.surchangement = @CON_APERCU
  finsi
  && mots de passe : mémorisés sur ce poste si souhaité (chiffrés, jamais dans le projet)
  conctl.memoriser = nul
  si A_DES_SECRETS({type = k.type})
    conctl.memoriser = conctl.zone:ajouter(ui.cases("Mémoriser les mots de passe sur ce poste (chiffrés, hors du projet)"))
    conctl.memoriser:cocher(1, c <> nul et SECRETS_MEMORISES(c.nom))
    conctl.memoriser.infobulle = "Gardés dans " + FICHIER_SECRETS() + " ; décochez pour les oublier"
  finsi
  conctl.zone:ajouter(ui.etiquette("Instruction d'attachement"))
  conctl.apercu = conctl.zone:ajouter(ui.markdown(""))
  conctl.apercu.poids = 1
  CON_APERCU(nul)
retourner

fonction CON_LIRE(masquer)
  && connexion décrite par la boîte (les secrets dans secrets[], pas dans parametres)
  locale k = CON_CONNECTEUR()
  locale c = {nom = rogner(conctl.nom.valeur), description = conctl.description.valeur, type = k.type, ;
              parametres = {}, options = {}}
  si c.nom = ""
    c.nom = "nouvelle"
  finsi
  locale sec = {}
  pour chaque p dans k.parametres
    locale v = conctl.champs[majuscule(p.nom)].valeur
    si p.secret = vrai
      sec[majuscule(p.nom)] = sisinon(masquer et v <> "", "••••••", v)
    sinon
      c.parametres[majuscule(p.nom)] = v
    finsi
  suivant
  pour i = 1 a #conctl.nomsoptions
    c.options[majuscule(conctl.nomsoptions[i])] = conctl.options:coche(i)
  suivant
  secrets[majuscule(c.nom)] = sec
retourner c

procedure CON_APERCU(ev)
  locale k = CON_CONNECTEUR()
  locale c = CON_LIRE(vrai)
  locale l = {}
  si k.mode = "fichiers"
    inserer(l, "CREATE VIEW memory." + IDENT(ALIAS(c)) + ".<fichier> AS SELECT * FROM " + k.lecteur)
  sinon
    pour chaque s dans k.attacher
      inserer(l, GABARIT(s, c) + ";")
    suivant
  finsi
  locale md = "```" + car(10) + joindre(l, car(10)) + car(10) + "```" + car(10)
  si k.extension <> nul
    md = md + car(10) + "Extension DuckDB : **" + k.extension + "** (chargée, ou installée si besoin : réseau nécessaire)."
  finsi
  si k.version_min <> nul
    md = md + car(10) + car(10) + "Exige DuckDB **" + k.version_min + "** ou plus récent (actuel : " + VERSION_DUCKDB() + ")."
  finsi
  si k.aide <> nul
    md = md + car(10) + car(10) + GABARIT(k.aide, c)
  finsi
  md = md + car(10) + car(10) + "Nom SQL de la connexion : **" + ALIAS(c) + "**"
  conctl.apercu.valeur = md
retourner

procedure CON_TYPE(ev)
  CON_PARAMETRES()
retourner

procedure CON_PARCOURIR(ev)
  locale p = conctl.parcourir
  si p = nul
    retourner
  finsi
  locale r = nul
  si p.dossier
    r = ui.demander("Dossier (relatif au projet ou absolu) :", p.champ.valeur)
  sinon
    r = ui.ouvrirfichier{titre = "Choisir un fichier", dossier = dossier}
  finsi
  si r <> nul et r <> ""
    p.champ.valeur = r
    CON_APERCU(nul)
  finsi
retourner

procedure CON_TESTER(ev)
  locale c = CON_LIRE(faux)
  conctl.statut.libelle = "Test en cours…"
  locale r = ATTACHER(c, faux)
  si non r.ok
    conctl.statut.libelle = "✗ " + gauche(remplacertexte(r.message, car(10), " "), 120)
    conctl.statut.couleur = "#DC2626"
    retourner
  finsi
  locale ping = PING(c)
  locale cat = catalogue[majuscule(c.nom)]
  locale nt = 0
  locale nv = 0
  si cat <> nul
    pour chaque s dans cat.schemas
      nt += #s.tables
      nv += #s.vues
    suivant
  finsi
  conctl.statut.couleur = "#16A34A"
  conctl.statut.libelle = "✓ " + r.message + sisinon(ping = nul, "", " · ping " + ping + " ms") + ;
                          " · " + nt + " table(s), " + nv + " vue(s)"
  && le test ne garde pas la connexion si elle n'est pas enregistrée
  si conctl.edition = nul ou conctl.edition.nom <> c.nom
    DETACHER(c)
    catalogue[majuscule(c.nom)] = nul
  finsi
retourner

procedure CON_ENREGISTRER(ev)
  locale c = CON_LIRE(faux)
  si rogner(conctl.nom.valeur) = ""
    conctl.statut.libelle = "Donnez un nom à la connexion."
    retourner
  finsi
  && nom unique
  pour chaque x dans projet.connexions
    si minuscule(x.nom) = minuscule(c.nom) et (conctl.edition = nul ou x <> conctl.edition)
      conctl.statut.libelle = "Une connexion « " + c.nom + " » existe déjà."
      retourner
    finsi
  suivant
  si conctl.edition <> nul
    si minuscule(conctl.edition.nom) <> minuscule(c.nom)
      OUBLIER_SECRETS(conctl.edition.nom)
    finsi
    DETACHER(conctl.edition)
    catalogue[majuscule(conctl.edition.nom)] = nul
    pour i = 1 a #projet.connexions
      si projet.connexions[i] = conctl.edition
        projet.connexions[i] = c
      finsi
    suivant
    c.num = conctl.edition.num
  sinon
    c.num = NUMERO_LIBRE()
    inserer(projet.connexions, c)
  finsi
  si conctl.memoriser <> nul
    MEMORISER_SECRETS(c, conctl.memoriser:coche(1))
  finsi
  locale r = ATTACHER(c, vrai)
  ENREGISTRER_PROJET()
  REMPLIR_EXPLORATEUR()
  NOMS_COMPLETION()
  si r.ok
    STATUT("Connexion « " + c.nom + " » " + r.message)
  sinon
    ERREUR(c.nom + " : " + r.message)
  finsi
  condlg:fermer()
retourner

procedure CON_ANNULER(ev)
  condlg:fermer()
retourner

procedure CON_FERMETURE(ev)
  globale condlg
  condlg = nul
retourner

procedure SUPPRIMER_CONNEXION(c)
  si non ui.confirmer("Retirer la connexion « " + c.nom + " » du projet ? (la source n'est pas modifiée)")
    retourner
  finsi
  DETACHER(c)
  OUBLIER_SECRETS(c.nom)
  catalogue[majuscule(c.nom)] = nul
  locale l = {}
  pour chaque x dans projet.connexions
    si x <> c
      inserer(l, x)
    finsi
  suivant
  projet.connexions = l
  ENREGISTRER_PROJET()
  REMPLIR_EXPLORATEUR()
  NOMS_COMPLETION()
retourner

&&
&& Mots de passe mémorisés sur ce poste (facultatif)
&&
&& Fichier ~/.duckdbstudio/secrets.json, réservé à l'utilisateur (0600) : une entrée par
&& projet et par connexion, chiffrée et authentifiée (chiffrer()) avec la clé locale
&& ~/.duckdbstudio/cle (aléatoire, 0600). Le projet (duckstudio.json) n'en contient
&& jamais : on peut le partager sans risque. Protection contre une lecture fortuite ou
&& un partage du dossier, pas contre quelqu'un qui accède au compte de l'utilisateur.

fonction DOSSIER_LOCAL()
  locale d = fichier.joindre(fichier.dossierperso(), ".duckdbstudio")
  si non fichier.estdossier(d)
    fichier.creerdossier(d)
  finsi
retourner d

fonction FICHIER_SECRETS()
retourner fichier.joindre(DOSSIER_LOCAL(), "secrets.json")

fonction CLE_LOCALE()
  globale clelocale
  si clelocale <> nul
    retourner clelocale
  finsi
  locale p = fichier.joindre(DOSSIER_LOCAL(), "cle")
  si fichier.existe(p)
    clelocale = rogner(fichier.lire(p))
  finsi
  si clelocale = nul ou longueur(clelocale) < 32
    clelocale = mdpaleatoire(64)
    fichier.ecrire(p, clelocale)
  finsi
  fichier.proteger(p)
retourner clelocale

fonction LIRE_SECRETS_LOCAUX()
  && {version, entrees = {CLEF -> texte chiffré}}
  locale p = FICHIER_SECRETS()
  si fichier.existe(p)
    essayer
      locale t = dejson(fichier.lire(p))
      si t <> nul et t.entrees <> nul
        retourner t
      finsi
    capturer e
      JOURNAL("Mots de passe mémorisés illisibles : " + e)
    finessayer
  finsi
retourner {version = 1, entrees = {}}

procedure ECRIRE_SECRETS_LOCAUX(t)
  locale p = FICHIER_SECRETS()
  essayer
    fichier.ecrire(p, json(t))
    fichier.proteger(p)
  capturer e
    ERREUR("enregistrement des mots de passe impossible : " + e)
  finessayer
retourner

fonction CLEF_SECRET(nom)
retourner majuscule(dossier + "|" + nom)

fonction SECRETS_MEMORISES(nom)
  locale t = LIRE_SECRETS_LOCAUX()
retourner t.entrees[CLEF_SECRET(nom)] <> nul

procedure CHARGER_SECRETS_LOCAUX
  && au chargement du projet : secrets mémorisés de ses connexions
  locale t = LIRE_SECRETS_LOCAUX()
  pour chaque c dans projet.connexions
    locale v = t.entrees[CLEF_SECRET(c.nom)]
    si v <> nul
      locale clair = dechiffrer(v, CLE_LOCALE())
      si clair = nul
        JOURNAL("Mots de passe mémorisés de « " + c.nom + " » illisibles (clé locale changée ?) : ignorés.")
      sinon
        secrets[majuscule(c.nom)] = dejson(clair)
      finsi
    finsi
  suivant
retourner

procedure MEMORISER_SECRETS(c, oui)
  si non oui
    OUBLIER_SECRETS(c.nom)
    retourner
  finsi
  locale s = secrets[majuscule(c.nom)]
  si s = nul
    retourner
  finsi
  locale propres = {}
  locale n = 0
  pour chaque k, v dans s
    si v <> nul et v <> "" et v <> "••••••"
      propres[k] = v
      n += 1
    finsi
  suivant
  si n = 0
    retourner
  finsi
  locale t = LIRE_SECRETS_LOCAUX()
  t.entrees[CLEF_SECRET(c.nom)] = chiffrer(json(propres), CLE_LOCALE())
  ECRIRE_SECRETS_LOCAUX(t)
  JOURNAL("Mots de passe de « " + c.nom + " » mémorisés sur ce poste.")
retourner

procedure OUBLIER_SECRETS(nom)
  locale t = LIRE_SECRETS_LOCAUX()
  si t.entrees[CLEF_SECRET(nom)] <> nul
    t.entrees[CLEF_SECRET(nom)] = nul
    ECRIRE_SECRETS_LOCAUX(t)
    JOURNAL("Mots de passe de « " + nom + " » oubliés.")
  finsi
retourner

procedure OUBLIER_TOUS_SECRETS
  && menu : oublie les mots de passe mémorisés des connexions du projet
  si non ui.confirmer("Oublier les mots de passe mémorisés sur ce poste pour les connexions de ce projet ?")
    retourner
  finsi
  locale t = LIRE_SECRETS_LOCAUX()
  locale n = 0
  pour chaque c dans projet.connexions
    si t.entrees[CLEF_SECRET(c.nom)] <> nul
      t.entrees[CLEF_SECRET(c.nom)] = nul
      n += 1
    finsi
  suivant
  ECRIRE_SECRETS_LOCAUX(t)
  STATUT(n + " connexion(s) : mots de passe oubliés sur ce poste.")
retourner
