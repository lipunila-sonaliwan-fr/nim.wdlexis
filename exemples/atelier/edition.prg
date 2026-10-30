&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ : analyse pendant la frappe, problèmes, structure, signaux de
&& l'éditeur, pastilles des onglets et vue blueprint, recherche, aller à la
&& ligne / à la définition, affichage.

procedure MODIFIE(ev)
  ANALYSER(faux)
retourner

procedure ANALYSER(force)
  globale problemes, symboles, analyse
  locale t0 = systeme.horloge()
  && texte(), chemin()... sans uid : le document actif, ou le code de la vue blueprint active
  locale src = ed:texte()
  locale nom = ed:chemin()
  locale uid = CODE_ACTIF()
  NATURE_DOCUMENT(uid)
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
    ARBRE_STRUCTURE(nom, uid)
    etat.libelle = fichier.nom(nom)
    retourner
  finsi
  locale pbs = lexis.verifier(src, OPTIONS_ANALYSE(sisinon(nom = "", "document", nom)))
  ed:diagnostics(pbs)
  problemes = {}
  tprob:vider()
  pour chaque p dans pbs
    p.chemin = nom
    p.uid = uid
    inserer(problemes, p)
    tprob:ajouterligne(p.genre, fichier.nom(nom), p.ligne, p.colonne, p.message)
  suivant
  && structure du fichier
  symboles = lexis.structure(src)
  ARBRE_STRUCTURE(nom, uid)
  locale ms = arrondi((systeme.horloge() - t0) * 1000, 1)
  etat.libelle = chaine(#pbs) + " problème(s) - analyse " + ms + " ms"
retourner

&&
&& Structure : fichier > Procédures / Fonctions (avec leurs variables locales)
&& > Variables globales, comme l'atelier natif. Clic : aller à la ligne.
&&

procedure ARBRE_STRUCTURE(nom, uid)
  globale cheminsstruct, clestruct
  si outils = nul
    retourner
  finsi
  locale titre = sisinon(nom = "", "document", fichier.nom(nom))
  locale cle = chaine(uid) + ":" + titre
  pour chaque s dans symboles
    cle = cle + ";" + s.nom + "@" + s.ligne
  suivant
  si cle == clestruct
    retourner                    && rien n'a changé : l'arbre garde son état (dépliage, sélection)
  finsi
  clestruct = cle
  cheminsstruct = {}
  arbrestruct:vider()
  locale routines = {}
  pour chaque s dans symboles
    si s.genre = "procédure" ou s.genre = "fonction"
      inserer(routines, s)
    finsi
  suivant
  locale groupes = {}
  pour chaque g dans {{"Procédures", "procédure"}, {"Fonctions", "fonction"}}
    pour i = 1 a #routines
      locale r = routines[i]
      si r.genre = g[2]
        locale chemin = titre + ui.sep + g[1] + ui.sep + ETIQUETTE_SYMBOLE(r)
        cheminsstruct[chemin] = r
        arbrestruct:ajouter(chemin)
        && variables locales : entre cette routine et la suivante
        locale fin = 1000000000
        si i < #routines
          fin = routines[i + 1].ligne
        finsi
        pour chaque v dans symboles
          si v.genre = "locale" et v.ligne > r.ligne et v.ligne < fin
            locale cv = chemin + ui.sep + "· " + ETIQUETTE_SYMBOLE(v)
            cheminsstruct[cv] = v
            arbrestruct:ajouter(cv)
          finsi
        suivant
        si non (g[1] $ joindre(groupes, "|"))
          inserer(groupes, g[1])
        finsi
      finsi
    suivant
  suivant
  pour chaque v dans symboles
    si v.genre = "globale"
      locale cg = titre + ui.sep + "Variables globales" + ui.sep + "● " + ETIQUETTE_SYMBOLE(v)
      cheminsstruct[cg] = v
      arbrestruct:ajouter(cg)
      si non ("Variables globales" $ joindre(groupes, "|"))
        inserer(groupes, "Variables globales")
      finsi
    finsi
  suivant
  si #groupes = 0
    arbrestruct:ajouter(titre + ui.sep + "(aucune entité)")
  finsi
  arbrestruct:deplier(titre)
  pour chaque g dans groupes
    arbrestruct:deplier(titre + ui.sep + g)
  suivant
retourner

fonction ETIQUETTE_SYMBOLE(s)
retourner s.nom + "   :" + s.ligne

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
  && ev.texte : chemin du nœud (parties séparées par ui.sep)
  si ev.texte = nul
    retourner
  finsi
  locale s = cheminsstruct[ev.texte]
  si s <> nul
    si ed:nature(ed:actif()) = "blueprint"
      vb:afficherligne(s.ligne)       && vue blueprint : centre la vue sur le nœud
    sinon
      ed:aller(s.ligne, s.colonne)
      ed:focus()
    finsi
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
    NATURE_DOCUMENT(nombre(souschaine(s, 5)))
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
  cas commencepar(cmd, "dot:")
    PASTILLE(nombre(souschaine(cmd, 5)))
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
    etat.libelle = d.signature + "  -  " + d.description
  finsi
retourner

&&
&& Pastilles des onglets et vue blueprint
&&   rouge : code Lexis+   orange : formulaire   jaune : état   bleu : blueprint
&& Un clic sur la pastille rouge ouvre la vue blueprint du code (onglet à pastille
&& bleue) : graphe éditable, palette de toutes les fonctions à glisser, liens à
&& tirer entre broches ; chaque modification réécrit le code de l'onglet rouge.
&&

fonction CODE_ACTIF()
  && document de code actif (celui que représente la vue blueprint affichée)
  locale uid = ed:actif()
  si uid >= 0 et ed:nature(uid) = "blueprint"
    retourner ed:lien(uid)
  finsi
retourner uid

procedure NATURE_DOCUMENT(uid)
  && couleur de la pastille d'après le nom du fichier
  si uid = nul ou uid < 0
    retourner
  finsi
  locale n = ed:nature(uid)
  si n = nul ou n = "blueprint"
    retourner
  finsi
  locale p = ed:chemin(uid)
  locale voulu = "texte"
  si minuscule(fichier.extension(p)) = ".prg" ou (p = "" et finitpar(minuscule(TITRE_DOCUMENT(uid)), ".prg"))
    faire cas
    cas EST_FORMULAIRE(p)
      voulu = "formulaire"
    cas EST_ETAT(p)
      voulu = "etat"
    autrement
      voulu = "code"
    fincas
  finsi
  si voulu <> n
    ed:nature(voulu, uid)
  finsi
retourner

fonction TITRE_DOCUMENT(uid)
  pour chaque d dans ed:documents(vrai)
    si d.uid = uid
      retourner d.titre
    finsi
  suivant
retourner ""

procedure PASTILLE(uid)
  && clic sur la pastille d'un onglet
  locale n = ed:nature(uid)
  faire cas
  cas n = "code"
    OUVRIR_BLUEPRINT(uid)
  cas n = "blueprint"
    ed:activer(ed:lien(uid))
  cas n = "formulaire"
    CONCEPTEUR_OUVRIR(ed:chemin(uid))
  cas n = "etat"
    ETAT_OUVRIR(ed:chemin(uid))
  autrement
    etat.libelle = "Document texte : pas de vue associée."
  fincas
retourner

procedure OUVRIR_BLUEPRINT(uid)
  si uid = nul ou uid < 0
    etat.libelle = "Ouvrez d'abord un fichier .prg."
    retourner
  finsi
  NATURE_DOCUMENT(uid)
  si vb:ouvrir(uid) = nul
    etat.libelle = "La vue blueprint s'applique au code Lexis+ (.prg)."
    retourner
  finsi
  etat.libelle = "Vue blueprint de " + TITRE_DOCUMENT(uid) + ;
                 " - glisser depuis la palette, relier les broches ; le code est réécrit à chaque modification"
retourner

procedure BLUEPRINT_BASCULER
  && menu Conception > Vue blueprint : du code à sa vue, de la vue au code
  locale uid = ed:actif()
  si uid >= 0 et ed:nature(uid) = "blueprint"
    ed:activer(ed:lien(uid))
  sinon
    OUVRIR_BLUEPRINT(uid)
  finsi
retourner

procedure SIGNAL_BLUEPRINT(ev)
  && événements de la vue blueprint (vb.surselection)
  locale s = ev.texte
  faire cas
  cas commencepar(s, "code:")
    ANALYSER(faux)              && le code a été réécrit depuis la vue
  cas commencepar(s, "statut:")
    etat.libelle = souschaine(s, 8)
  cas commencepar(s, "entite:")
    && double-clic sur l'icône fichier d'un appel : la procédure s'ouvre en blueprint
    locale p = decouper(souschaine(s, 8), ":")
    NATURE_DOCUMENT(nombre(p[2]))
    etat.libelle = p[1] + " : " + fichier.nom(ed:chemin(nombre(p[2]))) + " (vue blueprint)"
  cas commencepar(s, "cmd:")
    SIGNAL(ev)                  && raccourcis (Ctrl+S, F5...) tapés dans la vue
  fincas
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
