&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ : projet, fichiers, session (.wdlexis/atelier.json du projet)

procedure CHARGER_PROJET(d)
  globale dossier
  si dossier <> ""
    ENREGISTRER_SESSION()
  finsi
  dossier = d
  fen.titre = "wdlexis+ [S]tudio 1.8.6 - " + fichier.nom(dossier)
  ARBRE_PROJET()
  vb:projet(dossier)        && procédures du projet : palette et liens d'appel entre fichiers
  locale s = LIRE_SESSION()
  locale ouverts = 0
  pour chaque p dans s.fichiers
    si fichier.estfichier(p)
      ed:ouvrir(p)
      ouverts += 1
    finsi
  suivant
  locale principal = fichier.joindre(dossier, FICHIER_PRINCIPAL())
  si ouverts = 0 et fichier.existe(principal)
    ed:ouvrir(principal)
  finsi
  si s.actif <> "" et fichier.estfichier(s.actif)
    ed:ouvrir(s.actif)
  finsi
  ANALYSER(vrai)
  etat.libelle = "Projet : " + dossier
retourner

procedure ARBRE_PROJET
  si outils = nul
    retourner
  finsi
  arbre:vider()
  pour chaque nom dans fichier.liste(dossier, vrai)
    si finitpar(nom, "/") ou commencepar(nom, ".") ou ("/." $ nom) ou commencepar(nom, "distribution/")
      boucler
    finsi
    si minuscule(fichier.extension(nom)) $ ".prg.md.txt.json.csv.sql.ini.cfg.htm.html.png.jpg.jpeg.gif.bmp.pdf.log"
      arbre:ajouter(nom)
      locale t = TYPE_FICHIER(nom)
      si t <> nul
        arbre:icone(nom, t[1], t[2])
      finsi
    finsi
  suivant
  CADENAS()
retourner

fonction TYPE_FICHIER(nom)
  && symbole et couleur du type de fichier (comme les pastilles des onglets)
  locale x = minuscule(fichier.extension(nom))
  faire cas
  cas x = ".prg" et EST_FORMULAIRE(nom)
    retourner {"formulaire", "#F59E0B"}
  cas x = ".prg" et EST_ETAT(nom)
    retourner {"etat", "#EAB308"}
  cas x = ".prg"
    retourner {"code", "#E5484D"}
  cas x $ ".png.jpg.jpeg.gif.bmp"
    retourner {"image", "#A855F7"}
  cas x = ".md"
    retourner {"markdown", "#14B8A6"}
  cas x = ".sql"
    retourner {"sql", "#3B82F6"}
  cas x = ".pdf"
    retourner {"pdf", "#DC2626"}
  cas x $ ".txt.log.csv.json.ini.cfg.htm.html"
    retourner {"texte", "#8C8F96"}
  fincas
retourner nul

procedure CADENAS
  && cadenas fermé devant les fichiers ouverts dans l'éditeur ou l'un des concepteurs
  si outils = nul ou dossier = ""
    retourner
  finsi
  locale ouverts = {}
  pour chaque d dans ed:documents(vrai)
    si d.chemin <> nul et d.chemin <> ""
      ouverts[fichier.absolu(d.chemin)] = vrai
    finsi
  suivant
  pour chaque f dans FICHIERS_CONCEPTEURS()
    ouverts[fichier.absolu(f)] = vrai
  suivant
  pour chaque c dans arbre:feuilles()
    locale p = fichier.absolu(fichier.joindre(dossier, joindre(decouper(c, ui.sep), "/")))
    arbre:cadenas(c, ouverts[p] = vrai)
  suivant
retourner

fonction FICHIERS_CONCEPTEURS()
  locale l = {}
  si condlg <> nul et canevas <> nul
    essayer
      inserer(l, fichier.joindre(dossier, "form_" + canevas:nom() + ".prg"))
    capturer err
    finessayer
  finsi
  si etdlg <> nul et etcanevas <> nul
    essayer
      inserer(l, fichier.joindre(dossier, "etat_" + etcanevas:nom() + ".prg"))
    capturer err
    finessayer
  finsi
retourner l

fonction EST_IMAGE(p)
retourner minuscule(fichier.extension(p)) $ ".png.jpg.jpeg.gif.bmp"

procedure ARBRE(ev)
  && ev.chemin n'existe que pour les nœuds imbriqués : on découpe ev.texte
  si ev.texte = nul ou ev.texte = ""
    retourner
  finsi
  locale p = fichier.joindre(dossier, joindre(decouper(ev.texte, ui.sep), "/"))
  si non fichier.estfichier(p)
    retourner
  finsi
  faire cas
  cas EST_IMAGE(p)
    ed:image(p)                       && aperçu de l'image dans un onglet
    etat.libelle = "Aperçu de l'image " + fichier.nom(p)
  cas minuscule(fichier.extension(p)) = ".pdf"
    PDF_OUVRIR(p)
  autrement
    ed:ouvrir(p)                      && texte brut, Markdown, SQL, Lexis+
    ANALYSER(vrai)
  fincas
  CADENAS()
retourner

procedure PDF_OUVRIR(p)
  && consultation dans une fenêtre dédiée : pages, vignettes et signets, zoom, recherche,
  && sélection et copie du texte, rotation, annotations
  locale f = ui.fenetre{titre = fichier.nom(p) + " - wdlexis+", largeur = 1000, hauteur = 900, ;
                        disposition = "bordure", sombre = reglages.sombre, densite = "compacte"}
  f.marge = 0
  locale v = f:ajouter(ui.pdf())
  v.ancrage = "centre"
  essayer
    v:ouvrir(p)
    inserer(fenpdf, f)
    etat.libelle = "PDF : " + fichier.nom(p)
  capturer e
    etat.libelle = "PDF illisible : " + e
  finessayer
retourner

&&
&& Dupliquer, Renommer, Supprimer (boutons en haut de la page Projet)
&&

fonction FICHIER_CHOISI()
  locale v = arbre.valeur
  si v = nul ou v = "" ou dossier = ""
    retourner nul
  finsi
  locale p = fichier.joindre(dossier, joindre(decouper(v, ui.sep), "/"))
  si fichier.existe(p)
    retourner p
  finsi
retourner nul

fonction OUVERT_DANS_CONCEPTEUR(p)
  pour chaque f dans FICHIERS_CONCEPTEURS()
    si fichier.absolu(f) = fichier.absolu(p)
      retourner vrai
    finsi
  suivant
retourner faux

fonction FERMER_ONGLETS_DE(p)
  && ferme les onglets du fichier avant de le renommer ou de le supprimer
  locale a = fichier.absolu(p)
  pour chaque d dans ed:documents(vrai)
    si d.chemin <> nul et d.chemin <> "" et fichier.absolu(d.chemin) = a
      FERMER_DOCUMENT(d.uid)
    finsi
  suivant
  pour chaque d dans ed:documents(vrai)
    si d.chemin <> nul et d.chemin <> "" et fichier.absolu(d.chemin) = a
      retourner faux          && l'utilisateur a gardé un document modifié
    finsi
  suivant
retourner vrai

procedure FICHIER_DUPLIQUER(ev)
  locale p = FICHIER_CHOISI()
  si p = nul
    etat.libelle = "Choisissez d'abord un fichier dans la page Projet."
    retourner
  finsi
  locale x = fichier.extension(p)
  locale base = souschaine(p, 1, #p - #x)
  locale n = 1
  tantque fichier.existe(base + n + x)
    n += 1
  fintantque
  locale dest = base + n + x
  si non ui.confirmer("Dupliquer « " + fichier.nom(p) + " » en « " + fichier.nom(dest) + " » ?")
    retourner
  finsi
  si fichier.copier(p, dest) = nul
    ui.alerte("Copie impossible : " + fichier.nom(p), "erreur", "Dupliquer")
    retourner
  finsi
  ARBRE_PROJET()
  ANALYSER(vrai)
  etat.libelle = "Copie créée : " + fichier.nom(dest)
retourner

procedure FICHIER_RENOMMER(ev)
  locale p = FICHIER_CHOISI()
  si p = nul
    etat.libelle = "Choisissez d'abord un fichier dans la page Projet."
    retourner
  finsi
  si OUVERT_DANS_CONCEPTEUR(p)
    ui.alerte("« " + fichier.nom(p) + " » est ouvert dans un concepteur : fermez-le d'abord.", "information", "Renommer")
    retourner
  finsi
  locale nom = ui.demander("Nouveau nom de « " + fichier.nom(p) + " » :", fichier.nom(p))
  si nom = nul ou nom = "" ou nom = fichier.nom(p)
    retourner
  finsi
  si "/" $ nom ou "\\" $ nom
    ui.alerte("Le nom ne doit pas contenir de séparateur de dossier.", "erreur", "Renommer")
    retourner
  finsi
  locale dest = fichier.joindre(fichier.dossier(p), nom)
  si fichier.existe(dest)
    ui.alerte("« " + nom + " » existe déjà.", "erreur", "Renommer")
    retourner
  finsi
  locale etaitouvert = faux
  pour chaque d dans ed:documents()
    si d.chemin <> "" et fichier.absolu(d.chemin) = fichier.absolu(p)
      etaitouvert = vrai
    finsi
  suivant
  si non FERMER_ONGLETS_DE(p)
    retourner
  finsi
  si fichier.deplacer(p, dest) = nul
    ui.alerte("Renommage impossible : " + fichier.nom(p), "erreur", "Renommer")
    retourner
  finsi
  ARBRE_PROJET()
  si etaitouvert
    ed:ouvrir(dest)
  finsi
  ANALYSER(vrai)
  etat.libelle = "Renommé : " + fichier.nom(p) + " → " + nom
retourner

procedure FICHIER_SUPPRIMER(ev)
  locale p = FICHIER_CHOISI()
  si p = nul
    etat.libelle = "Choisissez d'abord un fichier dans la page Projet."
    retourner
  finsi
  si OUVERT_DANS_CONCEPTEUR(p)
    ui.alerte("« " + fichier.nom(p) + " » est ouvert dans un concepteur : fermez-le d'abord.", "information", "Supprimer")
    retourner
  finsi
  si non ui.confirmer("Supprimer définitivement « " + fichier.nom(p) + " » ?", "attention")
    retourner
  finsi
  si non FERMER_ONGLETS_DE(p)
    retourner
  finsi
  si fichier.supprimer(p) = nul
    ui.alerte("Suppression impossible : " + fichier.nom(p), "erreur", "Supprimer")
    retourner
  finsi
  ARBRE_PROJET()
  ANALYSER(vrai)
  etat.libelle = "Supprimé : " + fichier.nom(p)
retourner

&& configuration du projet : arguments, fichier principal, session
procedure ARBRE_DOUBLE(ev)
  && double-clic sur un formulaire ou un état : son éditeur
  locale v = arbre.valeur
  si v = nul ou v = ""
    retourner
  finsi
  locale p = fichier.joindre(dossier, joindre(decouper(v, ui.sep), "/"))
  si fichier.estfichier(p) et EST_FORMULAIRE(p)
    CONCEPTEUR_OUVRIR(p)
  sinonsi fichier.estfichier(p) et EST_ETAT(p)
    ETAT_OUVRIR(p)
  finsi
retourner

fonction FICHIER_PROJET()
retourner fichier.joindre(dossier, ".wdlexis", "atelier.json")

fonction LIRE_SESSION()
  locale s = {fichiers = {}, actif = "", arguments = "", principal = ""}
  locale p = FICHIER_PROJET()
  si fichier.existe(p)
    essayer
      pour chaque k, v dans dejson(fichier.lire(p))
        s[majuscule(k)] = v
      suivant
    capturer e
    finessayer
  finsi
retourner s

procedure ECRIRE_SESSION(s)
  essayer
    fichier.creerdossier(fichier.joindre(dossier, ".wdlexis"))
    fichier.ecrire(FICHIER_PROJET(), json(s))
  capturer e
    etat.libelle = "Session non enregistrée : " + e
  finessayer
retourner

procedure ENREGISTRER_SESSION
  si dossier = ""
    retourner
  finsi
  locale s = LIRE_SESSION()
  s.fichiers = {}
  pour chaque d dans ed:documents()
    si d.chemin <> ""
      inserer(s.fichiers, d.chemin)
    finsi
  suivant
  s.actif = ed:chemin()
  ECRIRE_SESSION(s)
retourner

fonction FICHIER_PRINCIPAL()
  locale s = LIRE_SESSION()
  si s.principal <> nul et s.principal <> ""
    retourner s.principal
  finsi
retourner "principal.prg"

&&
&& Fichiers
&&

procedure NOUVEAU_PROJET
  locale p = ui.demander("Dossier du nouveau projet :", fichier.joindre(fichier.dossierperso(), "projet_lexis"))
  si p = nul ou p = ""
    retourner
  finsi
  fichier.creerdossier(p)
  locale principal = fichier.joindre(p, "principal.prg")
  si non fichier.existe(principal)
    fichier.ecrire(principal, MODELE_PROJET())
  finsi
  CHARGER_PROJET(fichier.absolu(p))
retourner

procedure OUVRIR_PROJET
  locale p = ui.ouvrirfichier{titre = "Choisir un fichier du projet", dossier = dossier, ;
                              filtre = "Lexis+|*.prg|Tous les fichiers|*"}
  si p <> nul
    CHARGER_PROJET(fichier.dossier(p))
    ed:ouvrir(p)
  finsi
retourner

procedure OUVRIR_DOSSIER
  locale p = ui.demander("Chemin du dossier du projet :", dossier)
  si p <> nul et p <> ""
    si fichier.estdossier(p)
      CHARGER_PROJET(fichier.absolu(p))
    sinon
      ui.alerte("Dossier introuvable : " + p, "attention")
    finsi
  finsi
retourner

procedure OUVRIR_FICHIER
  locale p = ui.ouvrirfichier{titre = "Ouvrir", dossier = dossier, filtre = "Lexis+|*.prg|Tous les fichiers|*"}
  si p <> nul
    ed:ouvrir(p)
    ANALYSER(vrai)
  finsi
retourner

procedure NOUVEAU_FICHIER
  locale nom = ui.demander("Nom du nouveau fichier (dans le projet) :", "nouveau.prg")
  si nom = nul ou nom = ""
    retourner
  finsi
  si fichier.extension(nom) = ""
    nom = nom + ".prg"
  finsi
  locale p = fichier.joindre(dossier, nom)
  si fichier.existe(p)
    ui.alerte("Ce fichier existe déjà : " + nom, "attention")
    retourner
  finsi
  fichier.creerdossier(fichier.dossier(p))
  fichier.ecrire(p, "&& " + fichier.nom(p) + car(10))
  ARBRE_PROJET()
  ed:ouvrir(p)
  vb:projet(dossier)
retourner

procedure ENREGISTRER
  si ed:actif() < 0
    retourner
  finsi
  si ed:chemin() = ""
    ENREGISTRER_SOUS()
    retourner
  finsi
  essayer
    locale p = ed:enregistrer()
    etat.libelle = "Enregistré : " + fichier.nom(p)
    vb:projet(dossier)      && les procédures ont pu changer
  capturer e
    ui.alerte("Enregistrement impossible : " + e, "stop")
  finessayer
retourner

procedure ENREGISTRER_SOUS
  locale nom = sisinon(ed:chemin() = "", "sans_titre.prg", fichier.nom(ed:chemin()))
  locale p = ui.enregistrerfichier{nom = nom, filtre = "Lexis+|*.prg|Tous les fichiers|*"}
  si p <> nul
    ed:enregistrer(p)
    ARBRE_PROJET()
    etat.libelle = "Enregistré sous : " + p
  finsi
retourner

procedure TOUT_ENREGISTRER
  locale n = 0
  pour chaque d dans ed:documents()
    si d.modifie et d.chemin <> ""
      ed:enregistrer(nul, d.uid)
      n += 1
    finsi
  suivant
  etat.libelle = chaine(n) + " fichier(s) enregistré(s)"
retourner

procedure FERMER_DOCUMENT(uid)
  si uid = nul ou uid < 0
    retourner
  finsi
  && vue blueprint : seul son onglet se ferme, le code reste ouvert
  si ed:nature(uid) = "blueprint"
    vb:fermer(uid)
    retourner
  finsi
  && vue aperçu (Markdown) ou image : rien à enregistrer
  si ed:nature(uid) = "apercu" ou ed:nature(uid) = "image"
    ed:fermer(uid)
    CADENAS()
    retourner
  finsi
  locale d = nul
  pour chaque x dans ed:documents()
    si x.uid = uid
      d = x
    finsi
  suivant
  si d = nul
    retourner
  finsi
  si d.modifie
    si non ui.confirmer("« " + d.titre + " » a des modifications non enregistrées. Fermer quand même ?")
      retourner
    finsi
  finsi
  vb:fermer(uid)            && sa vue blueprint éventuelle
  locale lien = ed:lien(uid)
  si lien <> nul et ed:nature(lien) = "apercu"
    ed:fermer(lien)        && sa vue aperçu éventuelle
  finsi
  ed:fermer(uid)
  CADENAS()
retourner

fonction MODIFICATIONS_EN_ATTENTE()
  pour chaque d dans ed:documents()
    si d.modifie
      retourner vrai
    finsi
  suivant
retourner faux

procedure QUITTER
  si MODIFICATIONS_EN_ATTENTE()
    si non ui.confirmer("Des fichiers ont des modifications non enregistrées. Quitter quand même ?")
      retourner
    finsi
  finsi
  FERMETURE(nul)
  fen:fermer()
retourner

fonction MODELE_PROJET()
  locale l = {}
  inserer(l, "&& principal.prg : point d'entrée du projet")
  inserer(l, "&& Le programme principal s'écrit en tête du fichier, les procédures ensuite.")
  inserer(l, "")
  inserer(l, "? " + car(34) + "Bonjour depuis wdlexis+ !" + car(34))
  inserer(l, "")
  inserer(l, "ui = paquet(" + car(34) + "interface" + car(34) + ")")
  inserer(l, "fen = ui.fenetre{titre = " + car(34) + "Bonjour" + car(34) + ", largeur = 420, hauteur = 200}")
  inserer(l, "lbl = fen:ajouter(ui.etiquette(" + car(34) + "Cliquez sur le bouton" + car(34) + ", " + car(34) + "centre" + car(34) + "))")
  inserer(l, "nb = 0")
  inserer(l, "btn = fen:ajouter(ui.bouton(" + car(34) + "Compter" + car(34) + ", {defaut = vrai}))")
  inserer(l, "btn.surclic = @COMPTER")
  inserer(l, "ui.executer()")
  inserer(l, "")
  inserer(l, "procedure COMPTER(ev)")
  inserer(l, "  nb += 1")
  inserer(l, "  lbl.valeur = " + car(34) + "Clics : " + car(34) + " + nb")
  inserer(l, "retourner")
retourner joindre(l, car(10)) + car(10)
