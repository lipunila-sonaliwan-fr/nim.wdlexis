&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ : outils de développement, comme l'atelier natif (wdlexis_outils.nim)
&&   - usages du symbole (Maj+F12) : page Usages ;
&&   - formateur (Ctrl+Maj+F) et conventions du projet (.lexisformat) ;
&&   - tests unitaires (Ctrl+T) : page Tests ;
&&   - profileur (Exécuter > Profiler le programme) : page Profil ;
&&   - git : statut, comparaison, annotations, historique, fusion, conflits, validation.
&& Le service de langage, le formateur et le lanceur de tests sont natifs (paquets lexis et test).

fonction OPTIONS_SERVICE()
  && texte du document actif, rattaché à son fichier et au projet
  locale nom = ed:chemin()
retourner {nom = sisinon(nom = "", "document.prg", nom), projet = dossier}

procedure ALLER_A(r)
  && emplacement {chemin, ligne, colonne} : ouvre le fichier au besoin
  si r.chemin <> "" et r.chemin <> ed:chemin() et fichier.estfichier(r.chemin)
    ed:ouvrir(r.chemin)
  finsi
  ed:aller(r.ligne, r.colonne)
  ed:focus()
retourner

fonction CHEMIN_RELATIF(p)
  si dossier <> "" et commencepar(p, dossier)
    locale r = souschaine(p, #dossier + 1)
    si commencepar(r, "/") ou commencepar(r, car(92))
      r = souschaine(r, 2)
    finsi
    retourner r
  finsi
retourner fichier.nom(p)

&&
&& Usages
&&

procedure LISTER_USAGES
  globale usagesliste
  locale c = ed:curseur()
  locale refs = lexis.usages(ed:texte(), c.ligne, c.colonne, OPTIONS_SERVICE())
  si #refs = 0
    etat.libelle = "Aucun symbole du projet sous le curseur"
    retourner
  finsi
  usagesliste = refs
  tusages:vider()
  locale fichiers = {}
  pour chaque r dans refs
    tusages:ajouterligne(CHEMIN_RELATIF(r.chemin), r.ligne, r.colonne, r.genre, r.code)
    fichiers[r.chemin] = vrai
  suivant
  AFFICHER_ENSEMBLE("bas")
  bas.valeur = 5
  etat.libelle = #refs + " usage(s) dans " + nbelements(fichiers) + " fichier(s) - clic pour y aller"
retourner

procedure USAGE(ev)
  locale r = usagesliste[ev.index]
  si r <> nul
    ALLER_A(r)
  finsi
retourner

&&
&& Formateur
&&

procedure FORMATER_DOCUMENT
  locale nom = ed:chemin()
  si nom <> "" et minuscule(fichier.extension(nom)) <> ".prg"
    etat.libelle = "Le formateur s'applique au code Lexis+ (.prg)."
    retourner
  finsi
  locale r = lexis.formater(ed:texte(), sisinon(dossier <> "", dossier, fichier.dossier(nom)))
  si non r.ok
    etat.libelle = r.message
    retourner
  finsi
  si non r.modifie
    locale cv = lexis.conventions(dossier)
    etat.libelle = "Déjà formaté (conventions : " + sisinon(cv.fichier = "", "par défaut", CHEMIN_RELATIF(cv.fichier)) + ")"
    retourner
  finsi
  locale c = ed:curseur()
  ed:fixertexte(r.texte)
  ed:aller(c.ligne, c.colonne)
  etat.libelle = "Document formaté (Ctrl+Z pour annuler)"
retourner

procedure CONVENTIONS_FORMATAGE
  si dossier = ""
    etat.libelle = "Ouvrez d'abord un projet : les conventions sont dans son fichier .lexisformat"
    retourner
  finsi
  locale f = fichier.joindre(dossier, ".lexisformat")
  si non fichier.existe(f)
    essayer
      fichier.ecrire(f, lexis.conventions().texte)
    capturer e
      ui.alerte("Création impossible :\n" + f, "erreur")
      retourner
    finessayer
  finsi
  ed:ouvrir(f)
  etat.libelle = "Conventions de formatage du projet : .lexisformat (une option par ligne)"
retourner

&&
&& Tests unitaires
&&

procedure LANCER_TESTS(courant)
  globale testsliste
  TOUT_ENREGISTRER()
  locale fichiercible = dossier
  si courant
    fichiercible = ed:chemin()
  finsi
  si fichiercible = ""
    etat.libelle = "Ouvrez d'abord un projet (ou un fichier de test)."
    retourner
  finsi
  ttests:vider()
  AFFICHER_ENSEMBLE("bas")
  bas.valeur = 6
  lbltests.libelle = "Tests en cours…"
  locale r = test.lancer(fichiercible)
  testsliste = r.resultats
  pour chaque t dans r.resultats
    locale ou = ""
    si t.ligneerreur > 0
      si t.sourceerreur <> "" et t.sourceerreur <> t.fichier
        ou = fichier.nom(t.sourceerreur) + ":" + t.ligneerreur + " : "
      sinon
        ou = "ligne " + t.ligneerreur + " : "
      finsi
    finsi
    ttests:ajouterligne(RESULTAT_TEST(t.statut), t.nom, CHEMIN_RELATIF(t.fichier), arrondi(t.ms, 2), t.assertions, ou + t.message)
  suivant
  si r.total = 0
    lbltests.libelle = "Aucun fichier de test : test_*.prg, *_test.prg ou dossier tests/ " + ;
                       "(procédures TEST_… et assertions du paquet test)"
    retourner
  finsi
  lbltests.libelle = r.total + " test(s) : " + r.reussis + " réussi(s), " + r.echecs + " échec(s), " + ;
                     r.erreurs + " erreur(s), " + r.ignores + " ignoré(s) - double-clic : aller au test ou à l'échec"
  etat.libelle = sisinon(r.ok, "Tests réussis (" + r.reussis + ")", "Tests : " + (r.echecs + r.erreurs) + " en échec")
retourner

fonction RESULTAT_TEST(statut)
  faire cas
  cas statut = "réussi"
    retourner "✓ réussi"
  cas statut = "échec"
    retourner "✗ échec"
  cas statut = "erreur"
    retourner "! erreur"
  fincas
retourner "- ignoré"

procedure TEST_CHOISI(ev)
  globale testchoisi
  testchoisi = ev.index
retourner

procedure TEST_ALLER(ev)
  locale t = testsliste[testchoisi]
  si t = nul
    retourner
  finsi
  si (t.statut = "échec" ou t.statut = "erreur") et t.ligneerreur > 0
    ALLER_A({chemin = sisinon(t.sourceerreur <> "", t.sourceerreur, t.fichier), ligne = t.ligneerreur, colonne = 1})
  sinonsi t.ligne > 0
    ALLER_A({chemin = t.fichier, ligne = t.ligne, colonne = 1})
  finsi
retourner

&&
&& Profileur (lexis.executer{surprofil = @PROFIL_RESULTAT}, voir execution.prg)
&&

procedure PROFIL_RESULTAT(r)
  globale profilfonctions, profillignes
  profilfonctions = r.fonctions
  profillignes = r.lignes
  tprofil:vider()
  tprofillignes:vider()
  locale d = max(r.duree_ms, 0.000001)
  pour chaque f dans r.fonctions
    tprofil:ajouterligne(f.nom, f.appels, arrondi(f.total_ms, 3), arrondi(f.propre_ms, 3), ;
                         arrondi(100 * f.propre_ms / d, 1), f.tables, CHEMIN_RELATIF(f.source) + ":" + f.ligne)
  suivant
  pour chaque l dans r.lignes
    tprofillignes:ajouterligne(arrondi(l.ms, 3), l.passages, CHEMIN_RELATIF(l.source) + ":" + l.ligne, ;
                               LIGNE_SOURCE(l.source, l.ligne))
  suivant
  lblprofil.libelle = "Durée " + arrondi(r.duree_ms, 1) + " ms - mémoire résidente : départ " + ;
                      r.memoire.debut_ko + " Ko, fin " + r.memoire.fin_ko + " Ko, pic " + r.memoire.pic_ko + ;
                      " Ko - tables créées : " + r.memoire.tables + " - double-clic : aller au code"
  AFFICHER_ENSEMBLE("bas")
  bas.valeur = 7
retourner

fonction LIGNE_SOURCE(chemin, n)
  essayer
    locale l = decouper(fichier.lire(chemin), car(10))[n]
    si l <> nul
      retourner rogner(l)
    finsi
  capturer e
  finessayer
retourner ""

procedure PROFIL_CHOIX_FONCTION(ev)
  profilchoix[1] = ev.index
retourner

procedure PROFIL_CHOIX_LIGNE(ev)
  profilchoix[2] = ev.index
retourner

procedure PROFIL_ALLER_FONCTION(ev)
  locale f = profilfonctions[profilchoix[1]]
  si f <> nul et f.ligne > 0
    ALLER_A({chemin = f.source, ligne = f.ligne, colonne = 1})
  finsi
retourner

procedure PROFIL_ALLER_LIGNE(ev)
  locale l = profillignes[profilchoix[2]]
  si l <> nul et l.ligne > 0
    ALLER_A({chemin = l.source, ligne = l.ligne, colonne = 1})
  finsi
retourner

&&
&& Git (outil git en ligne de commande, dans le dossier du projet)
&&

fonction CITER(s)
  && argument de la ligne de commande
  si systeme.plateforme() = "windows"
    retourner car(34) + remplacertexte(s, car(34), car(92) + car(34)) + car(34)
  finsi
retourner "'" + remplacertexte(s, "'", "'" + car(92) + "''") + "'"

fonction GIT(args)
  && {sortie, code} de « git -C dossier args… »
  locale l = {"git", "-C", CITER(dossier)}
  pour chaque a dans args
    inserer(l, CITER(a))
  suivant
  locale r = nul
  essayer
    r = systeme.capturer(joindre(l, " ") + " 2>&1")
  capturer e
    r = {sortie = "git introuvable : " + e, code = -1}
  finessayer
retourner r

procedure GIT_MONTRER(titre, texte)
  sgit.valeur = titre + car(10) + repliquer("─", 60) + car(10) + texte
  AFFICHER_ENSEMBLE("bas")
  bas.valeur = 8
retourner

fonction GIT_PRET()
  si dossier = ""
    GIT_MONTRER("Git", "Ouvrez d'abord un projet.")
    retourner faux
  finsi
  locale r = GIT({"rev-parse", "--show-toplevel"})
  si r.code <> 0
    GIT_MONTRER("Git", "Le projet n'est pas un dépôt git (ou git est absent) :" + car(10) + r.sortie + ;
                car(10) + "Initialiser : git init dans le dossier du projet.")
    retourner faux
  finsi
retourner vrai

procedure DOCUMENT_LECTURE(titre, texte)
  && document en lecture seule (comparaison, annotations) ; remplacé s'il existe
  locale uid = nul
  pour chaque d dans ed:documents(vrai)
    si d.titre = titre
      uid = d.uid
    finsi
  suivant
  si uid = nul
    uid = ed:nouveau(titre)
  finsi
  ed:lecture(faux, uid)
  ed:fixertexte(texte, uid, vrai)
  ed:langage("texte", uid)
  ed:lecture(vrai, uid)
  ed:activer(uid)
retourner

fonction FICHIER_COURANT()
  locale p = ed:chemin()
  si p = ""
    etat.libelle = "Ouvrez un fichier enregistré du projet."
  finsi
retourner p

procedure GIT_STATUT
  si non GIT_PRET()
    retourner
  finsi
  GIT_MONTRER("Statut du dépôt", GIT({"status", "--short", "--branch"}).sortie + car(10) + ;
              "Dernières validations :" + car(10) + GIT({"log", "--oneline", "-n", "10", "--decorate"}).sortie)
retourner

procedure GIT_COMPARER(tout)
  si non GIT_PRET()
    retourner
  finsi
  TOUT_ENREGISTRER()
  locale sansdiff = "Aucune différence avec la dernière validation."
  si tout
    locale o = GIT({"diff", "HEAD", "--stat", "--patch", "--no-color"}).sortie
    DOCUMENT_LECTURE("projet (diff HEAD)", sisinon(rogner(o) = "", sansdiff, o))
    retourner
  finsi
  locale f = FICHIER_COURANT()
  si f = ""
    retourner
  finsi
  locale d = GIT({"diff", "HEAD", "--no-color", "--", f}).sortie
  DOCUMENT_LECTURE(fichier.nom(f) + " (diff HEAD)", sisinon(rogner(d) = "", sansdiff, d))
retourner

procedure GIT_ANNOTATIONS
  si non GIT_PRET()
    retourner
  finsi
  locale f = FICHIER_COURANT()
  si f = ""
    retourner
  finsi
  locale r = GIT({"blame", "--date=short", "-w", "--", f})
  DOCUMENT_LECTURE(fichier.nom(f) + " (annotations)", ;
                   sisinon(r.code <> 0, "Annotations indisponibles (fichier non validé ?) :" + car(10) + r.sortie, r.sortie))
retourner

procedure GIT_HISTORIQUE
  si non GIT_PRET()
    retourner
  finsi
  locale f = FICHIER_COURANT()
  si f = ""
    retourner
  finsi
  locale o = GIT({"log", "--follow", "--date=short", "--pretty=format:%h  %ad  %an  %s", "--", f}).sortie
  GIT_MONTRER("Historique de " + fichier.nom(f), sisinon(rogner(o) = "", "(aucune validation)", o))
retourner

procedure RECHARGER_DOCUMENTS
  && après une fusion ou un abandon : les documents non modifiés reprennent le disque
  pour chaque d dans ed:documents()
    si d.chemin <> "" et fichier.estfichier(d.chemin) et non d.modifie
      ed:fixertexte(fichier.lire(d.chemin), d.uid, vrai)
    finsi
  suivant
  ARBRE_PROJET()
  ANALYSER(vrai)
retourner

fonction GIT_CONFLITS()
  locale l = {}
  pour chaque x dans decouper(GIT({"diff", "--name-only", "--diff-filter=U"}).sortie, car(10))
    si rogner(x) <> ""
      inserer(l, rogner(x))
    finsi
  suivant
retourner l

procedure GIT_FUSIONNER
  si non GIT_PRET()
    retourner
  finsi
  si MODIFICATIONS_EN_ATTENTE()
    si non ui.confirmer("Enregistrer les fichiers modifiés avant la fusion ?")
      retourner
    finsi
    TOUT_ENREGISTRER()
  finsi
  locale cur = rogner(GIT({"branch", "--show-current"}).sortie)
  locale autres = {}
  pour chaque b dans decouper(GIT({"branch", "--format=%(refname:short)"}).sortie, car(10))
    si rogner(b) <> "" et rogner(b) <> cur
      inserer(autres, rogner(b))
    finsi
  suivant
  locale b = ui.demander("Branche à fusionner dans « " + cur + " » :" + car(10) + "(" + joindre(autres, ", ") + ")", "")
  si b = nul ou rogner(b) = ""
    retourner
  finsi
  b = rogner(b)
  locale r = GIT({"merge", "--no-ff", "--no-edit", b})
  locale conflits = GIT_CONFLITS()
  RECHARGER_DOCUMENTS()
  si #conflits > 0
    GIT_MONTRER("Fusion de " + b + " : conflits", r.sortie + car(10) + "Fichiers en conflit :" + car(10) + "  " + ;
                joindre(conflits, car(10) + "  ") + car(10) + car(10) + ;
                "Ouvrez chaque fichier et choisissez Git > Conflits : garder la version locale / " + ;
                "la version fusionnée / les deux, puis Git > Valider.")
    ed:ouvrir(fichier.joindre(dossier, conflits[1]))
  sinon
    GIT_MONTRER("Fusion de " + b, sisinon(r.code = 0, r.sortie, "Échec de la fusion :" + car(10) + r.sortie))
  finsi
retourner

procedure GIT_ABANDONNER
  si non GIT_PRET()
    retourner
  finsi
  locale r = GIT({"merge", "--abort"})
  RECHARGER_DOCUMENTS()
  GIT_MONTRER("Abandon de la fusion", sisinon(r.code = 0, "Fusion abandonnée : fichiers revenus à l'état d'avant." + car(10), "") + r.sortie)
retourner

procedure GIT_RESOUDRE(garder)
  && marques <<<<<<< ======= >>>>>>> du document actif ; garder : local, fusion ou deux
  locale lignesgardees = {}
  locale mode = 0         && 0 hors conflit, 1 partie locale, 2 partie fusionnée, 3 base (diff3)
  locale n = 0
  pour chaque l dans decouper(ed:texte(), car(10))
    faire cas
    cas commencepar(l, "<<<<<<<")
      mode = 1
      n += 1
    cas commencepar(l, "|||||||") et mode = 1
      mode = 3
    cas commencepar(l, "=======") et (mode = 1 ou mode = 3)
      mode = 2
    cas commencepar(l, ">>>>>>>") et mode = 2
      mode = 0
    cas mode = 0
      inserer(lignesgardees, l)
    cas mode = 1 et (garder = "local" ou garder = "deux")
      inserer(lignesgardees, l)
    cas mode = 2 et (garder = "fusion" ou garder = "deux")
      inserer(lignesgardees, l)
    fincas
  suivant
  si n = 0
    etat.libelle = "Aucun conflit (<<<<<<< … >>>>>>>) dans ce document"
    retourner
  finsi
  ed:fixertexte(joindre(lignesgardees, car(10)))
  etat.libelle = n + " conflit(s) résolu(s) - enregistrez, puis Git > Valider"
retourner

procedure GIT_VALIDER
  si non GIT_PRET()
    retourner
  finsi
  TOUT_ENREGISTRER()
  locale m = ui.demander("Message de validation (tous les fichiers modifiés du projet) :", "")
  si m = nul ou rogner(m) = ""
    retourner
  finsi
  locale a = GIT({"add", "-A"})
  locale r = GIT({"commit", "-m", rogner(m)})
  GIT_MONTRER("Validation", a.sortie + r.sortie + sisinon(r.code = 0, "", car(10) + "(échec de la validation)"))
retourner
