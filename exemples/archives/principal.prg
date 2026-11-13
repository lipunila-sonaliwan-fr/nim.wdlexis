&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Archiveur : ouvrir, créer, modifier et extraire des archives zip, tar, tar.gz
&& et gz avec le paquet archive (Nim pur, aucune bibliothèque externe).
&&
&&   wdlexisrt exemples/archives/principal.prg [archive]
&&
&& Sans argument, l'archiveur compresse les exemples bonjour et markdown dans une
&& archive de démonstration (dossier temporaire) et l'ouvre.
&&   - un clic sur une entrée : aperçu (texte, Markdown, image) ;
&&   - « Ajouter… » et « Retirer » réécrivent l'archive
&&     (lecture de chaque entrée, écriture d'une nouvelle archive, remplacement) ;
&&   - le filtre accepte les jokers : *.prg, docs/*, ?ouvelle*.

ui = paquet("interface")

chemin = ""             && archive ouverte
entrees = {}            && entrées affichées (dans l'ordre du tableau)
apercutemp = fichier.joindre(fichier.dossiertemp(), "archiveur_apercu")

fen = ui.fenetre{titre = "Archiveur", largeur = 1180, hauteur = 640, disposition = "bordure"}

barre = fen:ajouter(ui.rangee())
barre.ancrage = "haut"
barre.marge = 6
barre.espacement = 4
BOUTON("Ouvrir…", @OUVRIR)
BOUTON("Dossier → archive…", @COMPRESSER_DOSSIER)
BOUTON("Fichier → archive…", @COMPRESSER_FICHIER)
BOUTON("Ajouter…", @AJOUTER)
BOUTON("Retirer", @SUPPRIMER)
BOUTON("Extraire tout…", @EXTRAIRE_TOUT)
BOUTON("Extraire la sélection…", @EXTRAIRE_SELECTION)
BOUTON("gzip / gunzip…", @GZIP)

ligne = fen:ajouter(ui.rangee())
ligne.ancrage = "haut"
ligne.marge = 6
ligne.espacement = 8
ligne:ajouter(ui.etiquette("Filtre :"))
filtre = ligne:ajouter(ui.saisie{indication = "*.prg, docs/*, *.png… (vide : tout)"})
filtre.poids = 1
filtre.surchangement = @AFFICHER
infos = ligne:ajouter(ui.etiquette(""))
infos.couleur = "#8A8F98"

etat = fen:ajouter(ui.etiquette(""))
etat.ancrage = "bas"

sep = fen:ajouter(ui.separateur{vertical = vrai, position = 0.63})
sep.ancrage = "centre"
tab = sep:ajouter(ui.tableau())
tab:ajoutercolonne("Nom", 280)
tab:ajoutercolonne("Taille", 90, "droite")
tab:ajoutercolonne("Compressé", 90, "droite")
tab:ajoutercolonne("Gain", 56, "droite")
tab:ajoutercolonne("Modifié le", 128)
tab.surselection = @APERCU
droite = sep:ajouter(ui.colonne())
image = droite:ajouter(ui.image(""))
image.visible = faux
image.hauteurfixe = 220
apercu = droite:ajouter(ui.markdown("Ouvrez une archive (zip, tar, tar.gz, gz) ou créez-en une."))
apercu.poids = 1

si #systeme.args >= 1 et fichier.existe(systeme.args[1])
  OUVRIR_CHEMIN(systeme.args[1])
sinon
  DEMONSTRATION()
finsi
ui.executer()

procedure BOUTON(libelle, action)
  locale b = barre:ajouter(ui.bouton(libelle, {plat = vrai}))
  b.surclic = action
retourner

&& Archive de démonstration : deux exemples voisins, compressés au niveau 9.
procedure DEMONSTRATION
  locale racine = fichier.dossier(systeme.dossierprogramme())
  locale dest = fichier.joindre(fichier.dossiertemp(), "exemples_lexis.zip")
  locale w = archive.creer(dest, {niveau = 9, commentaire = "Archive de démonstration de l'archiveur Lexis+"})
  pour chaque nom dans {"bonjour", "markdown", "archives"}
    si fichier.estdossier(fichier.joindre(racine, nom))
      w:ajouter(fichier.joindre(racine, nom), "exemples/" + nom)
    finsi
  suivant
  w:ajoutertexte("LISEZMOI.txt", "Archive créée par l'archiveur Lexis+ le " + systeme.date("%d/%m/%Y à %H:%M") + "." + car(10))
  w:fermer()
  OUVRIR_CHEMIN(dest)
retourner

procedure OUVRIR(ev)
  locale p = ui.ouvrirfichier{titre = "Ouvrir une archive", ;
                              filtre = "Archives|*.zip;*.tar;*.tar.gz;*.tgz;*.gz|Tous les fichiers|*"}
  si p <> nul
    OUVRIR_CHEMIN(p)
  finsi
retourner

procedure OUVRIR_CHEMIN(p)
  globale chemin
  locale f = archive.format(p)
  si f = nul
    ui.alerte(fichier.nom(p) + " n'est pas une archive reconnue (zip, tar, tar.gz, gz).", "attention")
    retourner
  finsi
  chemin = p
  fen.titre = "Archiveur - " + fichier.nom(p)
  AFFICHER()
retourner

&& Remplit le tableau (filtre appliqué) et le résumé.
procedure AFFICHER(ev)
  globale entrees
  tab:vider()
  entrees = {}
  si chemin = ""
    retourner
  finsi
  locale a, motif = rogner(filtre.valeur)
  essayer
    a = archive.ouvrir(chemin)
  capturer e
    etat.libelle = "Lecture impossible : " + e
    retourner
  finessayer
  locale total = 0, comp = 0, nfichiers = 0
  pour chaque x dans a:liste(sisinon(motif = "", nul, motif))
    inserer(entrees, x)
    tab:ajouterligne(sisinon(x.dossier, x.nom + "/", x.nom), sisinon(x.dossier, "", OCTETS(x.taille)), ;
                     sisinon(x.dossier, "", OCTETS(x.compresse)), sisinon(x.dossier, "", GAIN(x)), ;
                     systeme.date("%d/%m/%Y %H:%M", x.date))
    si non x.dossier
      total += x.taille
      comp += x.compresse
      nfichiers += 1
    finsi
  suivant
  infos.libelle = majuscule(a:format()) + " - " + nfichiers + " fichier(s), " + OCTETS(total) + ;
                  " -> " + OCTETS(fichier.taille(chemin)) + " sur disque"
  locale c = a:commentaire()
  etat.libelle = chemin + sisinon(c = "", "", "   -   « " + c + " »")
  a:fermer()
  si #entrees > 0
    && première entrée qui est un fichier
    locale k = 1
    tantque k < #entrees et entrees[k].dossier
      k += 1
    fintantque
    tab:selectionner(k)
    APERCU()
  sinon
    apercu.valeur = "*Aucune entrée" + sisinon(motif = "", ".*", " ne correspond au filtre.*")
    image.visible = faux
  finsi
retourner

fonction OCTETS(n)
  si n < 1024
    retourner chaine(n) + " o"
  sinonsi n < 1048576
    retourner chaine(arrondi(n / 1024, 1)) + " Ko"
  finsi
retourner chaine(arrondi(n / 1048576, 1)) + " Mo"

fonction GAIN(x)
  si x.taille = 0
    retourner ""
  finsi
retourner chaine(arrondi(100 - 100 * x.compresse / x.taille)) + " %"

fonction SELECTION()
  locale i = tab:selection()
  si i < 1 ou i > #entrees
    retourner nul
  finsi
retourner entrees[i]

&& Aperçu de l'entrée sélectionnée : image extraite dans un dossier temporaire,
&& texte affiché (Markdown tel quel, le reste dans un bloc de code).
procedure APERCU(ev)
  locale x = SELECTION()
  image.visible = faux
  si x = nul
    retourner
  finsi
  locale md = "### " + x.nom + car(10) + car(10) + ;
              "Taille : **" + OCTETS(x.taille) + "**, compressé : **" + OCTETS(x.compresse) + "**" + ;
              sisinon(x.mode > 0, ", droits : `" + DROITS(x.mode) + "`", "") + car(10) + car(10)
  si x.dossier
    apercu.valeur = md + "*Dossier.*"
    retourner
  finsi
  locale ext = minuscule(fichier.extension(x.nom))
  locale a = archive.ouvrir(chemin)
  si contient({".png", ".jpg", ".jpeg", ".bmp"}, ext)
    locale p = fichier.joindre(apercutemp, "image" + ext)
    a:extrairefichier(x.chemin, p)
    image.valeur = p
    image.visible = vrai
    apercu.valeur = md
  sinonsi x.taille > 200000
    apercu.valeur = md + "*Fichier volumineux : pas d'aperçu.*"
  sinon
    locale contenu = a:lire(x.chemin)
    si contient(contenu, car(0))
      apercu.valeur = md + "*Contenu binaire.*"
    sinonsi ext = ".md"
      apercu.valeur = md + "---" + car(10) + car(10) + contenu
    sinon
      apercu.valeur = md + "```" + car(10) + contenu + car(10) + "```"
    finsi
  finsi
  a:fermer()
retourner

fonction DROITS(m)
  locale s = "", lettres = "rwx"
  pour i = 8 a 0 pas -1
    si mod(entier(m / (2 ^ i)), 2) = 1
      s = s + souschaine(lettres, 3 - mod(i, 3), 1)
    sinon
      s = s + "-"
    finsi
  suivant
retourner s

&& Nom de l'archive à créer, avec le format choisi par l'extension.
fonction DESTINATION(nom)
retourner ui.enregistrerfichier{nom = nom + ".zip", ;
                               filtre = "Zip|*.zip|Tar compressé|*.tar.gz|Tar|*.tar"}

procedure COMPRESSER_DOSSIER(ev)
  locale src = ui.demander("Dossier à compresser :", fichier.dossier(systeme.dossierprogramme()))
  si src = nul ou rogner(src) = ""
    retourner
  finsi
  si non fichier.estdossier(src)
    ui.alerte(src + " n'est pas un dossier.", "attention")
    retourner
  finsi
  locale dest = DESTINATION(fichier.nom(src))
  si dest <> nul
    locale t0 = systeme.horloge()
    locale n = archive.compresser(src, dest, {niveau = 9})
    OUVRIR_CHEMIN(dest)
    etat.libelle = n + " entrée(s) compressée(s) en " + arrondi(systeme.horloge() - t0, 2) + " s : " + dest
  finsi
retourner

procedure COMPRESSER_FICHIER(ev)
  locale src = ui.ouvrirfichier{titre = "Fichier à compresser"}
  si src <> nul
    locale dest = DESTINATION(fichier.nom(src))
    si dest <> nul
      archive.compresser(src, dest)
      OUVRIR_CHEMIN(dest)
    finsi
  finsi
retourner

&& Les archives ne se modifient pas en place : on recopie les entrées gardées
&& dans une nouvelle archive (même format), puis on remplace l'ancienne.
procedure REECRIRE(sauf, ajouts)
  locale a = archive.ouvrir(chemin)
  locale f = a:format()
  si f = "gzip"
    a:fermer()
    ui.alerte("Un fichier .gz ne contient qu'un fichier : utilisez une archive zip ou tar.gz.", "attention")
    retourner
  finsi
  locale tmp = chemin + ".tmp"
  locale w = archive.creer(tmp, {format = f, niveau = 9, commentaire = a:commentaire()})
  pour chaque x dans a:liste()
    si x.chemin = sauf ou (sauf <> nul et commencepar(x.chemin, sauf + "/"))
      boucler
    finsi
    si x.dossier
      w:ajouterdossier(x.chemin)
    sinon
      w:ajoutertexte(x.chemin, a:lire(x.chemin), x.date)
    finsi
  suivant
  a:fermer()
  pour chaque p dans ajouts
    si w:contient(fichier.nom(p))
      etat.libelle = fichier.nom(p) + " existe déjà dans l'archive : ignoré."
    sinon
      w:ajouter(p)
    finsi
  suivant
  w:fermer()
  fichier.supprimer(chemin)
  fichier.deplacer(tmp, chemin)
  AFFICHER()
retourner

procedure AJOUTER(ev)
  si chemin = ""
    retourner
  finsi
  locale p = ui.ouvrirfichier{titre = "Fichier à ajouter à " + fichier.nom(chemin)}
  si p <> nul
    REECRIRE(nul, {p})
  finsi
retourner

procedure SUPPRIMER(ev)
  locale x = SELECTION()
  si x <> nul et ui.confirmer("Retirer " + x.nom + sisinon(x.dossier, " et son contenu", "") + " de l'archive ?", "question")
    REECRIRE(x.chemin, {})
  finsi
retourner

fonction DOSSIER_EXTRACTION()
  locale nom = fichier.nom(chemin)
  pour chaque ext dans {".tar.gz", ".tgz", ".zip", ".tar", ".gz"}
    si finitpar(minuscule(nom), ext)
      nom = gauche(nom, longueur(nom) - longueur(ext))
      sortir
    finsi
  suivant
retourner ui.demander("Extraire dans le dossier :", fichier.joindre(fichier.dossier(chemin), nom))

procedure EXTRAIRE_TOUT(ev)
  si chemin <> ""
    locale d = DOSSIER_EXTRACTION()
    si d <> nul
      locale fichiers = archive.extraire(chemin, d, {motif = sisinon(rogner(filtre.valeur) = "", nul, rogner(filtre.valeur))})
      etat.libelle = #fichiers + " fichier(s) extrait(s) dans " + d
    finsi
  finsi
retourner

procedure EXTRAIRE_SELECTION(ev)
  locale x = SELECTION()
  si x <> nul
    locale d = DOSSIER_EXTRACTION()
    si d <> nul
      locale a = archive.ouvrir(chemin)
      locale fichiers = a:extraire(d, sisinon(x.dossier, {motif = x.chemin + "*"}, {x.chemin}))
      a:fermer()
      etat.libelle = #fichiers + " fichier(s) extrait(s) dans " + d
    finsi
  finsi
retourner

&& gzip d'un fichier quelconque, ou décompression d'un .gz.
procedure GZIP(ev)
  locale p = ui.ouvrirfichier{titre = "Fichier à compresser (gzip) ou à décompresser (.gz)"}
  si p = nul
    retourner
  finsi
  locale t0 = systeme.horloge()
  si archive.format(p) = "gzip"
    locale d = archive.gunzipfichier(p)
    etat.libelle = "Décompressé : " + d + " (" + OCTETS(fichier.taille(d)) + ")"
  sinon
    locale d = archive.gzipfichier(p, p + ".gz", 9)
    etat.libelle = "Compressé : " + d + " - " + OCTETS(fichier.taille(p)) + " -> " + ;
                   OCTETS(fichier.taille(d)) + " en " + arrondi(systeme.horloge() - t0, 2) + " s"
    OUVRIR_CHEMIN(d)
  finsi
retourner
