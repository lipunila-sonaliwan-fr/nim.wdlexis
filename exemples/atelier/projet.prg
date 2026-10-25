&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ : projet, fichiers, session (.wdlexis/atelier.json du projet)

procedure CHARGER_PROJET(d)
  globale dossier
  si dossier <> ""
    ENREGISTRER_SESSION()
  finsi
  dossier = d
  fen.titre = "wdlexis+ [S]tudio 1.7.3 - " + fichier.nom(dossier)
  ARBRE_PROJET()
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
  arbre:vider()
  pour chaque nom dans fichier.liste(dossier, vrai)
    si finitpar(nom, "/") ou commencepar(nom, ".") ou ("/." $ nom) ou commencepar(nom, "distribution/")
      boucler
    finsi
    si minuscule(fichier.extension(nom)) $ ".prg.md.txt.json.csv.sql.ini.cfg.htm.html"
      arbre:ajouter(nom)
    finsi
  suivant
retourner

procedure ARBRE(ev)
  && ev.chemin n'existe que pour les nœuds imbriqués : on découpe ev.texte
  si ev.texte = nul ou ev.texte = ""
    retourner
  finsi
  locale p = fichier.joindre(dossier, joindre(decouper(ev.texte, ui.sep), "/"))
  si fichier.estfichier(p)
    ed:ouvrir(p)
    ANALYSER(vrai)
  finsi
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
  ed:fermer(uid)
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
