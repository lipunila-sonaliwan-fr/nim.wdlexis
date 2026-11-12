&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ : « Vue projet » (menu Conception), comme l'atelier natif.
&&
&& Une colonne par fichier .prg (dans l'ordre des chemins, dossiers cachés exclus) :
&& en tête le fichier (son code de premier niveau), puis ses procédures et
&& fonctions dans l'ordre du source. Les liens pointillés relient chaque appelant
&& aux procédures du projet qu'il appelle (ou référence par @NOM) ; en bleu quand
&& l'appel change de fichier. Clic : appels (orange) et appelants (vert), détails
&& dans la barre d'état ; double-clic : ouvre le code à la définition.
&& L'analyse est celle de l'atelier natif : lexis.graphe(dossier).

&& mêmes dimensions et couleurs que l'atelier natif (projectview.nim)
fonction VP_STYLE()
retourner {colonne = 330, haut = 86, pas = 62, ;
           fichier = "#475569", procedure = "#2563EB", fonction = "#7C3AED", ;
           lien = "#94A3B8A0", croise = "#0EA5E9C0", ;
           appelee = "#F59E0B", appelant = "#22C55E", estompe = "#94A3B830"}

procedure VUE_PROJET
  && Conception > Vue projet… : ouvre la fenêtre (ou la ramène devant et la relit)
  globale vpfen, vpdia, vpetat, vpappels
  si dossier = nul ou dossier = ""
    etat.libelle = "Ouvrez d'abord un projet (Fichier > Ouvrir un projet…)."
    retourner
  finsi
  si vpfen <> nul
    vpfen.titre = "Vue projet - " + fichier.nom(dossier)
    vpfen:restaurer()
    VP_RELIRE()
    retourner
  finsi
  si vpappels = nul
    vpappels = vrai
  finsi
  vpfen = ui.fenetre{titre = "Vue projet - " + fichier.nom(dossier), largeur = 1320, hauteur = 820, ;
                     disposition = "bordure", sombre = reglages.sombre, densite = "compacte"}
  vpfen.marge = 0
  vpfen.espacement = 0
  vpfen.surfermeture = @VP_FERMETURE
  && barre d'outils : symboles, libellés en infobulle
  locale outils = vpfen:ajouter(ui.rangee())
  outils.ancrage = "haut"
  outils.marge = 2
  outils.espacement = 1
  OUTIL_SYMBOLE(outils, "actualiser", "Actualiser", "Relit les fichiers du projet", @VP_RELIRE)
  OUTIL_SYMBOLE(outils, "ajuster", "Tout voir", "Ajuste le zoom à l'ensemble du projet", @VP_TOUT_VOIR)
  OUTIL_SYMBOLE(outils, "zoommoins", "Zoom −", "Molette pour zoomer autour du pointeur", @VP_ZOOM_MOINS)
  OUTIL_SYMBOLE(outils, "zoomplus", "Zoom +", "Molette pour zoomer autour du pointeur", @VP_ZOOM_PLUS)
  OUTIL_SYMBOLE(outils, "k-link", "Appels", ;
                "Affiche ou masque les liens d'appel (pointillés ; bleus : vers un autre fichier)", @VP_APPELS)
  ESPACE(outils, 8)
  OUTIL_SYMBOLE(outils, "code", "Ouvrir le code", ;
                "Ouvre dans l'atelier le fichier sélectionné, à la définition (ou double-clic)", @VP_CODE)
  OUTIL_SYMBOLE(outils, "blueprint", "Ouvrir en blueprint", ;
                "Ouvre le fichier sélectionné dans la fenêtre Blueprint", @VP_BLUEPRINT)
  locale info = outils:ajouter(ui.etiquette("  une colonne par fichier · procédures dans l'ordre du source"))
  info.poids = 1
  info.couleur = "#8A8F98"
  && barre d'état
  vpetat = vpfen:ajouter(ui.etiquette(""))
  vpetat.ancrage = "bas"
  vpetat.hauteurfixe = 20
  && graphe
  vpdia = vpfen:ajouter(ui.diagramme{modifiable = faux})
  vpdia.ancrage = "centre"
  vpdia.surselection = @VP_SELECTION
  vpdia.surdoubleclic = @VP_DOUBLE
  vpdia:focus()
  VP_RELIRE()
  etat.libelle = "Vue projet de " + fichier.nom(dossier) + " (fenêtre Vue projet)"
retourner

procedure VP_FERMETURE(ev)
  globale vpfen, vpdia, vpetat
  vpfen = nul
  vpdia = nul
  vpetat = nul
retourner

procedure VP_SUIVRE
  && projet modifié (fichier enregistré, renommé…, autre projet) : la vue ouverte se met à jour
  si vpfen <> nul et dossier <> nul et dossier <> ""
    vpfen.titre = "Vue projet - " + fichier.nom(dossier)
    VP_RELIRE()
  finsi
retourner

procedure VP_RELIRE
  && colonnes, nœuds et liens d'appel à partir de lexis.graphe(dossier)
  globale vpinfos, vpliens
  si vpdia = nul
    retourner
  finsi
  locale st = VP_STYLE()
  locale g = lexis.graphe(dossier)
  vpdia:vider()
  vpinfos = {}
  vpliens = {}
  locale ou = {}                 && NOM -> ids des définitions
  locale fichierde = {}          && id -> fichier
  locale appelants = {}          && id -> titres des appelants
  pour chaque f dans g.fichiers
    pour chaque e dans f.entites
      locale id = "e:" + f.relatif + ":" + e.nom
      si ou[e.nom] = nul
        ou[e.nom] = {}
      finsi
      inserer(ou[e.nom], id)
      fichierde[id] = f.relatif
    suivant
  suivant
  && une colonne par fichier
  locale ne = 0
  pour col = 1 a #g.fichiers
    locale f = g.fichiers[col]
    locale x = (col - 1) * st.colonne
    locale fid = "f:" + f.relatif
    locale sous = chaine(#f.entites) + " entité" + sisinon(#f.entites > 1, "s", "") + " · " + chaine(f.lignes) + " lignes"
    vpdia:noeud{id = fid, titre = f.relatif, soustitre = sous, forme = "boite", couleur = st.fichier, x = x, y = 0}
    vpinfos[fid] = {chemin = f.chemin, ligne = 1, texte = f.relatif + " : " + sous}
    pour i = 1 a #f.entites
      locale e = f.entites[i]
      locale id = "e:" + f.relatif + ":" + e.nom
      vpdia:noeud{id = id, titre = e.affichage, soustitre = "ligne " + chaine(e.ligne), forme = "boite", ;
                  couleur = sisinon(e.genre = "fonction", st.fonction, st.procedure), ;
                  x = x, y = st.haut + (i - 1) * st.pas}
      vpinfos[id] = {chemin = f.chemin, ligne = e.ligne, ;
                     texte = e.affichage + " - " + sisinon(e.genre = "fonction", "fonction", "procédure") + ;
                             " de " + f.relatif + ", ligne " + chaine(e.ligne)}
      ne += 1
    suivant
  suivant
  && liens d'appel : du code principal du fichier et de chaque entité
  pour chaque f dans g.fichiers
    locale sources = {{id = "f:" + f.relatif, titre = f.relatif + " (code principal)", appels = f.appels}}
    pour chaque e dans f.entites
      inserer(sources, {id = "e:" + f.relatif + ":" + e.nom, titre = e.affichage, appels = e.appels})
    suivant
    pour chaque s dans sources
      pour chaque nom dans s.appels
        locale cible = VP_CIBLE(ou[nom], fichierde, f.relatif)
        si cible <> "" et cible <> s.id
          si appelants[cible] = nul
            appelants[cible] = {}
          finsi
          inserer(appelants[cible], s.titre)
          si vpappels
            locale croise = fichierde[cible] <> f.relatif
            locale l = {id = s.id + ">" + cible, de = s.id, a = cible, croise = croise}
            inserer(vpliens, l)
            vpdia:lien{id = l.id, de = l.de, a = l.a, fleche = vrai, pointille = vrai, epaisseur = 1.4, ;
                       couleur = sisinon(croise, st.croise, st.lien)}
          finsi
        finsi
      suivant
    suivant
  suivant
  pour chaque id, qui dans appelants
    si vpinfos[id] <> nul
      vpinfos[id].texte = vpinfos[id].texte + " - appelée par " + joindre(qui, ", ")
    finsi
  suivant
  vpdia:ajuster(35)
  vpetat.libelle = chaine(#g.fichiers) + " fichier" + sisinon(#g.fichiers > 1, "s", "") + " · " + ;
                   chaine(ne) + " procédures et fonctions" + ;
                   sisinon(vpappels, " · " + chaine(#vpliens) + " liens d'appel", "") + ;
                   "   -   clic : détails · double-clic : ouvrir le code · glisser le fond : déplacer · molette : zoom"
retourner

fonction VP_CIBLE(ids, fichierde, rel)
  && définition appelée : de préférence dans le même fichier
  si ids = nul ou #ids = 0
    retourner ""
  finsi
  pour chaque id dans ids
    si fichierde[id] = rel
      retourner id
    finsi
  suivant
retourner ids[1]

procedure VP_SELECTION(ev)
  && liens du nœud sélectionné en évidence (orange : appelées, vert : appelants), les autres estompés
  locale st = VP_STYLE()
  locale id = ev.texte
  si id = nul ou commencepar(id, "lien:")
    id = ""
  finsi
  pour chaque l dans vpliens
    locale c = sisinon(l.croise, st.croise, st.lien)
    locale ep = 1.4
    faire cas
    cas id = ""
      ep = 1.4                   && pas de sélection : couleurs ordinaires
    cas l.de = id
      c = st.appelee
      ep = 2.4
    cas l.a = id
      c = st.appelant
      ep = 2.4
    autrement
      c = st.estompe
      ep = 1.2
    fincas
    vpdia:lien{id = l.id, de = l.de, a = l.a, fleche = vrai, pointille = vrai, epaisseur = ep, couleur = c}
  suivant
  locale info = vpinfos[id]
  si info <> nul
    vpetat.libelle = info.texte + "   (orange : appelées · vert : appelants)"
  finsi
retourner

fonction VP_CHOIX()
  && fichier ou procédure sélectionné : {chemin, ligne, texte} ou nul
  locale s = vpdia:selection()
  si s.genre <> "noeud"
    retourner nul
  finsi
retourner vpinfos[s.id]

procedure VP_DOUBLE(ev)
  VP_OUVRIR(VP_CHOIX(), faux)
retourner

procedure VP_CODE(ev)
  VP_OUVRIR(VP_CHOIX(), faux)
retourner

procedure VP_BLUEPRINT(ev)
  VP_OUVRIR(VP_CHOIX(), vrai)
retourner

procedure VP_OUVRIR(info, blueprint)
  && ouvre le fichier dans l'atelier à la définition (ou dans la fenêtre Blueprint)
  si info = nul
    vpetat.libelle = "Sélectionnez d'abord un fichier ou une procédure."
    retourner
  finsi
  locale uid = -1
  pour chaque d dans ed:documents()
    si d.chemin = info.chemin
      uid = d.uid
    finsi
  suivant
  si uid < 0
    uid = ed:ouvrir(info.chemin)
  finsi
  NATURE_DOCUMENT(uid)
  si blueprint
    OUVRIR_BLUEPRINT(uid)
    si vb:courant() = uid et info.ligne > 1
      vb:afficherligne(info.ligne, uid)
    finsi
  sinon
    ed:activer(uid)
    ed:aller(info.ligne, 1, uid)
    fen:restaurer()
    ed:focus()
    ANALYSER(vrai)
    CADENAS()
  finsi
retourner

procedure VP_TOUT_VOIR(ev)
  vpdia:ajuster(35)
retourner

procedure VP_ZOOM_PLUS(ev)
  vpdia:zoom(1.25)
retourner

procedure VP_ZOOM_MOINS(ev)
  vpdia:zoom(1 / 1.25)
retourner

procedure VP_APPELS(ev)
  globale vpappels
  vpappels = non vpappels
  VP_RELIRE()
retourner
