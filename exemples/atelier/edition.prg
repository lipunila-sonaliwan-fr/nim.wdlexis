&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ : analyse pendant la frappe, problèmes, structure, signaux de
&& l'éditeur, recherche, aller à la ligne / à la définition, affichage.

procedure MODIFIE(ev)
  ANALYSER(faux)
retourner

procedure ANALYSER(force)
  globale problemes, symboles, analyse
  locale t0 = systeme.horloge()
  locale src = ed:texte()
  locale nom = ed:chemin()
  && Pendant une frappe rapide les événements s'accumulent, mais l'éditeur
  && contient déjà le texte final : seule la première analyse est utile.
  locale empreinte = hachage(nom + car(10) + src)
  si analyse == empreinte et non force
    retourner
  finsi
  analyse = empreinte
  si nom <> "" et minuscule(fichier.extension(nom)) <> ".prg"
    && .md, .json, .csv... : pas d'analyse Lexis+
    ed:diagnostics({})
    problemes = {}
    tprob:vider()
    symboles = {}
    lstruct:vider()
    etat.libelle = fichier.nom(nom)
    retourner
  finsi
  locale pbs = lexis.verifier(src, OPTIONS_ANALYSE(sisinon(nom = "", "document", nom)))
  ed:diagnostics(pbs)
  problemes = {}
  tprob:vider()
  pour chaque p dans pbs
    p.chemin = nom
    p.uid = ed:actif()
    inserer(problemes, p)
    tprob:ajouterligne(p.genre, fichier.nom(nom), p.ligne, p.colonne, p.message)
  suivant
  && structure du fichier
  symboles = lexis.structure(src)
  lstruct:vider()
  pour chaque s dans symboles
    lstruct:ajouter(s.nom + "   — " + s.genre + ", ligne " + s.ligne)
  suivant
  locale ms = arrondi((systeme.horloge() - t0) * 1000, 1)
  etat.libelle = chaine(#pbs) + " problème(s) — analyse " + ms + " ms"
retourner

fonction OPTIONS_ANALYSE(nom)
  locale o = {nom = nom, projet = dossier}
  o.globales = reglages.globales
  o.appelsinconnus = reglages.appelsinconnus
retourner o

procedure PROBLEME(ev)
  locale p = problemes[ev.index]
  si p = nul
    retourner
  finsi
  si p.chemin <> "" et p.chemin <> ed:chemin()
    ed:ouvrir(p.chemin)
  finsi
  ed:aller(p.ligne, p.colonne)
  ed:focus()
retourner

procedure SYMBOLE(ev)
  locale s = symboles[ev.index]
  si s <> nul
    ed:aller(s.ligne, s.colonne)
    ed:focus()
  finsi
retourner

procedure VERIFIER_TOUT
  globale problemes
  problemes = {}
  tprob:vider()
  locale n = 0
  pour chaque d dans ed:documents()
    si minuscule(fichier.extension(d.titre)) = ".prg"
      pour chaque p dans lexis.verifier(ed:texte(d.uid), OPTIONS_ANALYSE(sisinon(d.chemin = "", d.titre, d.chemin)))
        p.chemin = d.chemin
        inserer(problemes, p)
        tprob:ajouterligne(p.genre, d.titre, p.ligne, p.colonne, p.message)
        n += 1
      suivant
    finsi
  suivant
  bas.valeur = 1
  etat.libelle = chaine(n) + " problème(s) dans les fichiers ouverts"
retourner

&&
&& Signaux de l'éditeur : position, document actif, points d'arrêt, raccourcis
&&

procedure SIGNAL(ev)
  locale s = ev.texte
  locale cmd = ""
  si commencepar(s, "cmd:")
    cmd = souschaine(s, 5)
  finsi
  faire cas
  cas commencepar(s, "pos:")
    && un fil par événement : l'ordre n'est pas garanti, on relit la position réelle
    locale c = ed:curseur()
    lblpos.libelle = "Ln " + c.ligne + ", Col " + c.colonne
    AIDE_MOT()
  cas commencepar(s, "doc:")
    ANALYSER(vrai)
  cas commencepar(s, "bp:")
    POINTS_ARRET_MODIFIES(nombre(souschaine(s, 4)))
  cas cmd = "save"
    ENREGISTRER()
  cas cmd = "saveas"
    ENREGISTRER_SOUS()
  cas cmd = "new"
    NOUVEAU_FICHIER()
  cas cmd = "open"
    OUVRIR_FICHIER()
  cas cmd = "run"
    EXECUTER()
  cas cmd = "debug"
    DEBOGUER_OU_CONTINUER()
  cas cmd = "stepinto"
    PAS()
  cas cmd = "stepover"
    PASSER()
  cas cmd = "stepout"
    SORTIR()
  cas cmd = "stop"
    ARRETER()
  cas cmd = "find"
    RECHERCHER(faux)
  cas cmd = "replace"
    RECHERCHER(vrai)
  cas cmd = "findnext"
    SUIVANT_TROUVE(faux)
  cas cmd = "findprev"
    SUIVANT_TROUVE(vrai)
  cas cmd = "goto"
    ALLER_LIGNE()
  cas cmd = "fontbigger"
    POLICE(1)
  cas cmd = "fontsmaller"
    POLICE(-1)
  cas cmd = "fontreset"
    POLICE(0)
  cas commencepar(cmd, "close:")
    FERMER_DOCUMENT(nombre(souschaine(cmd, 7)))
  cas commencepar(cmd, "definition:")
    ALLER_DEFINITION(souschaine(cmd, 12))
  fincas
retourner

procedure AIDE_MOT
  && signature de la fonction sous le curseur, comme l'atelier natif
  locale m = majuscule(ed:motcourant())
  si m = ""
    retourner
  finsi
  locale d = docsparnom[m]
  si d <> nul
    etat.libelle = d.signature + "  —  " + d.description
  finsi
retourner

&&
&& Recherche
&&

procedure RECHERCHER(remplacer)
  globale recherche
  locale sel = ed:selection()
  si sel <> "" et non (car(10) $ sel)
    recherche.texte = sel
  finsi
  locale r = ui.rechercher{texte = recherche.texte, remplacement = recherche.remplacement, ;
                           remplacer = remplacer, casse = recherche.casse, motentier = recherche.motentier}
  si r = nul
    retourner
  finsi
  recherche = r
  faire cas
  cas r.action = "toutremplacer"
    etat.libelle = chaine(ed:remplacertout(r.texte, r.remplacement, r)) + " remplacement(s)"
  cas r.action = "remplacer"
    ed:remplacer(r.texte, r.remplacement, r)
  autrement
    si non ed:chercher(r.texte, r)
      etat.libelle = "« " + r.texte + " » introuvable"
    finsi
  fincas
  ed:focus()            && la boîte fermée, le clavier revient à l'éditeur (Ctrl+H, F3)
retourner

procedure SUIVANT_TROUVE(arriere)
  si recherche.texte = ""
    RECHERCHER(faux)
    retourner
  finsi
  locale o = copier(recherche)
  o.arriere = arriere
  si non ed:chercher(recherche.texte, o)
    etat.libelle = "« " + recherche.texte + " » introuvable"
  finsi
retourner

procedure ALLER_LIGNE
  locale c = ed:curseur()
  locale s = ui.demander("Aller à la ligne :", chaine(c.ligne))
  locale n = nombre(s)
  si n <> nul
    ed:aller(n)
  finsi
retourner

procedure ALLER_DEFINITION(mot)
  mot = majuscule(remplacertexte(rogner(mot), "@", ""))
  si mot = ""
    retourner
  finsi
  && fichier actif d'abord, puis les fichiers .prg du projet
  pour chaque s dans lexis.structure(ed:texte())
    si NOM_SYMBOLE(s) = mot
      ed:aller(s.ligne, s.colonne)
      retourner
    finsi
  suivant
  pour chaque nom dans fichier.liste(dossier, vrai)
    si minuscule(fichier.extension(nom)) = ".prg"
      locale p = fichier.joindre(dossier, nom)
      pour chaque s dans lexis.structure(fichier.lire(p))
        si NOM_SYMBOLE(s) = mot et s.genre <> "globale"
          ed:ouvrir(p)
          ed:aller(s.ligne, s.colonne)
          retourner
        finsi
      suivant
    finsi
  suivant
  etat.libelle = "Définition de « " + mot + " » introuvable dans le projet"
retourner

fonction NOM_SYMBOLE(s)
retourner majuscule(rogner(decouper(s.nom, "(")[1]))

&&
&& Affichage
&&

procedure POLICE(delta)
  si delta = 0
    reglages.police = 14
  sinon
    reglages.police = max(9, min(28, reglages.police + delta))
  finsi
  ed:taillepolice(reglages.police)
  etat.libelle = "Police : " + reglages.police + " pt dans l'éditeur"
retourner

procedure BASCULER_MINICARTE
  reglages.minicarte = non reglages.minicarte
  ed:minicarte(reglages.minicarte)
retourner

procedure BASCULER_THEME
  reglages.sombre = non reglages.sombre
  fen:fixertheme("natif", reglages.sombre)
retourner

procedure BASCULER_GLOBALES
  reglages.globales = non reglages.globales
  ANALYSER(vrai)
  etat.libelle = sisinon(reglages.globales, "Variables globales implicites signalées", ;
                         "Variables globales implicites non signalées")
retourner

procedure BASCULER_INCONNUES
  reglages.appelsinconnus = non reglages.appelsinconnus
  ANALYSER(vrai)
  etat.libelle = sisinon(reglages.appelsinconnus, "Procédures inconnues signalées", ;
                         "Procédures inconnues non signalées")
retourner
