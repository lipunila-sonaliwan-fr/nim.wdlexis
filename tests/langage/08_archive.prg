&& Paquet archive : zip, tar.gz, gzip, deflate, zlib, motifs, chemins dangereux
procedure TEST
  locale d = fichier.joindre(fichier.dossiertemp(), "wdlexis_t_archive")
  si fichier.existe(d)
    fichier.supprimer(d)
  finsi
  fichier.creerdossier(fichier.joindre(d, "src", "sous"))
  fichier.ecrire(fichier.joindre(d, "src", "a.txt"), repliquer("Lexis+ ", 200))
  fichier.ecrire(fichier.joindre(d, "src", "sous", "b.prg"), "? 1")
  pour chaque ext dans {".zip", ".tar.gz", ".tar"}
    locale chemin = fichier.joindre(d, "t" + ext)
    ? ext, archive.compresser(fichier.joindre(d, "src"), chemin, {racine = "projet"}), archive.format(chemin)
    locale a = archive.ouvrir(chemin)
    ? "  noms :", joindre(a:noms(), ", ")
    ? "  a.txt :", longueur(a:lire("projet/a.txt")), "inconnu :", a:lire("x") = nul
    a:fermer()
    locale sortie = fichier.joindre(d, "x" + ext)
    ? "  extraits :", #archive.extraire(chemin, sortie, "*.prg"), fichier.lire(fichier.joindre(sortie, "projet", "sous", "b.prg"))
  suivant
  locale w = archive.creer(fichier.joindre(d, "m.zip"), {niveau = 0, commentaire = "test"})
  w:ajoutertexte("dir/é.txt", "accentué")
  w:ajouterdossier("vide")
  ? "contient :", w:contient("dir/é.txt"), w:nombre()
  w:fermer()
  locale a = archive.ouvrir(fichier.joindre(d, "m.zip"))
  ? "commentaire :", a:commentaire(), a:lire("dir/é.txt"), a:infos("vide/").dossier
  a:fermer()
  locale s = repliquer("abcdefgh", 500)
  ? "gzip :", archive.gunzip(archive.gzip(s)) = s, longueur(archive.gzip(s)) < 200
  ? "deflate :", archive.inflate(archive.deflate(s, 9)) = s, "zlib :", archive.dezlib(archive.zlib(s)) = s
  ? "crc32 :", archive.crc32("123456789"), "adler32 :", archive.adler32("Wikipedia")
  ? "motifs :", archive.correspond("*.PRG", "x/y/z.prg"), archive.correspond("docs/*", "docs/a.md"), archive.correspond("?.md", "ab.md")
  && entrée dangereuse refusée à l'extraction
  locale z = archive.creer(fichier.joindre(d, "mal.tar"))
  z:ajoutertexte("ok.txt", "1")
  z:fermer()
  essayer
    locale w2 = archive.creer(fichier.joindre(d, "mal2.zip"))
    w2:ajoutertexte("../evasion.txt", "x")
    w2:fermer()
    ? "évasion :", archive.extraire(fichier.joindre(d, "mal2.zip"), fichier.joindre(d, "y"))
  capturer e
    ? "évasion refusée"
  finessayer
  fichier.supprimer(d)
retourner
