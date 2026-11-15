&& Littéraux hexadécimaux et binaires, paquets binaire (bits, octets), trame et usb
procedure TEST
  ? "littéraux :", 0x1f, 0XFF, 0b101, 0b1010_0001, 0x10 + 1
  ? "bits :", binaire.et(0xf3, 0x0f), binaire.ou(0x10, 0x01, 0x80), binaire.oux(0xff, 0x0f), binaire.non(0x10, 8)
  ? "décalages :", binaire.decaler(1, 12), binaire.decaler(0x8000, -4), binaire.bit(0x04, 2), binaire.bit(0x04, 1)
  ? "masque :", binaire.masquer(0xa5, 0x03, 0x0f)
  locale s = binaire.depuisoctets({200, 0, 255, 7})
  ? "octets :", binaire.longueur(s), binaire.octet(s, 3), binaire.octet(s, 9) = nul, joindre(binaire.octets(s, 2, 2), " ")
  ? "extraire :", binaire.hex(binaire.extraire(s, 2, 2)), binaire.hex(binaire.extraire(s, 4))
  ? "mots :", joindre(binaire.mots(binaire.depuismots({1, 65535, 300})), " "), binaire.crc32("123456789")
  && trame : lignes CIS (R, G puis B), 2 lignes de 3 pixels sur 16 bits
  locale d = binaire.depuismots({100, 101, 102, 200, 201, 202, 300, 301, 302, 1, 2, 3, 4, 5, 6, 7, 8, 9})
  locale t = trame.nouvelle(3, 0, 3, 16, {cis = vrai, dpi = 300})
  ? "cis :", t:ajouter(binaire.extraire(d, 1, 10)), t:ajouter(binaire.extraire(d, 11)), joindre(t:pixel(2, 0), " "), joindre(t:pixel(0, 1), " ")
  locale h = t:en8bits()
  ? "8 bits :", h:profondeur(), joindre(h:pixel(2, 0), " "), t:dpi()
  locale m = trame.mire(400, 300, 50)
  locale r = m:redimensionner(100)
  ? "redimensionner :", r:largeur(), r:hauteur(), arrondi(r:dpi(), 1)
  ? "pivoter :", m:pivoter(90):largeur(), m:pivoter(90):hauteur(), m:recadrer(10, 20, 50, 40):largeur()
  locale g = m:gris()
  ? "gris :", g:canaux(), m:trait(128):canaux(), joindre(m:trait(128):pixel(0, 0), " ")
  locale st = trame.nouvelle(4, 2, 1, 8, {valeur = 40}):statistiques()
  ? "statistiques :", st[1].min, st[1].max, st[1].moyenne
  locale n = trame.nouvelle(2, 2, 1, 8, {valeur = 100})
  n:niveaux({gamma = 1, contraste = 0, luminosite = 10})
  ? "niveaux :", joindre(n:pixel(1, 1), " ")
  ? "médiane :", joindre(trame.mediane16(binaire.depuismots({1, 9, 5, 7, 3, 2, 8, 4, 6}), 3, 3), " ")
  ? "moyennes :", joindre(trame.moyennes16(binaire.depuismots({10, 20, 30, 50}), 2), " ")
  locale dossier = fichier.joindre(fichier.dossiertemp(), "test_trame_lexis")
  fichier.creerdossier(dossier)
  locale formats = {}
  pour chaque ext dans {"png", "jpg", "tif", "pgm", "pdf"}
    locale f = fichier.joindre(dossier, "mire." + ext)
    locale img = m
    si ext = "pgm"
      img = g
    finsi
    inserer(formats, ext + "=" + sisinon(img:enregistrer(f, {qualite = 80}) > 100 et fichier.existe(f), "ok", "?"))
  suivant
  ? "formats :", joindre(formats, " "), sisinon(trame.pdf(fichier.joindre(dossier, "deux.pdf"), {m, g}) > 1000, "pdf2=ok", "?")
  locale ligne = m:capter({x = 0, y = 1, pixels = 10, resolution = 50, canal = 1, profondeur = 16})
  ? "capteur :", binaire.longueur(ligne)
  ? "usb :", type(usb.disponible()), type(usb.erreur())
  essayer
    trame.nouvelle(2, 2, 2, 8)
  capturer e
    ? "erreur :", e
  finessayer
retourner
