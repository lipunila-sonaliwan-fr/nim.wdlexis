# Archiveur : zip, tar, tar.gz et gz

Exemple du paquet `archive` : un petit gestionnaire d'archives. Le paquet est
écrit en Nim pur (deflate à codes de Huffman dynamiques, inflate, CRC-32, zip,
tar, gzip) : il ne dépend d'aucune bibliothèque et fonctionne tel quel dans les
applications générées, sur toutes les cibles.

```
wdlexisrt exemples/archives/principal.prg [archive]
```

Sans argument, l'archiveur compresse les exemples `bonjour`, `markdown` et
`archives` dans `exemples_lexis.zip` (dossier temporaire) et l'ouvre.

## Ce que montre l'exemple

| Bouton | Paquet `archive` |
| --- | --- |
| Ouvrir… | `archive.format(p)`, `archive.ouvrir(p)`, `a:liste([motif])`, `a:commentaire()` |
| aperçu d'une entrée | `a:lire(nom)` (texte, Markdown), `a:extrairefichier(nom, chemin)` (image) |
| Dossier → archive…, Fichier → archive… | `archive.compresser(source, destination, {niveau = 9})` ; le format suit l'extension (.zip, .tar, .tar.gz) |
| Ajouter…, Retirer | `archive.creer(...)`, `w:ajoutertexte(nom, a:lire(nom), date)`, `w:ajouter(fichier)`, `w:fermer()` : une archive ne se modifie pas en place, on la réécrit |
| Extraire tout… | `archive.extraire(archive, dossier, {motif = filtre})` |
| Extraire la sélection… | `a:extraire(dossier, {nom})` ou `{motif = "dossier/*"}` |
| gzip / gunzip… | `archive.gzipfichier(source, destination, 9)`, `archive.gunzipfichier(source)` |

## En quelques lignes

```lexis
&& créer
w = archive.creer("sauvegarde.zip", {niveau = 9, commentaire = "projet du jour"})
w:ajouter("mon_projet")                       && dossier et son contenu
w:ajoutertexte("VERSION", "1.2.0")
w:fermer()

&& lire sans extraire
a = archive.ouvrir("sauvegarde.zip")
pour chaque e dans a:liste("*.prg")
  ? e.nom, e.taille, e.compresse, systeme.date("%d/%m/%Y", e.date)
suivant
? a:lire("VERSION")
a:fermer()

&& en une ligne
archive.compresser({"src", "LISEZMOI.md"}, "livraison.tar.gz", {racine = "livraison"})
fichiers = archive.extraire("livraison.tar.gz", "copie")

&& en mémoire
z = archive.gzip(json.encoder(donnees))
donnees = json.decoder(archive.gunzip(z))
```

À l'extraction, les chemins dangereux (`..`, chemins absolus) sont refusés et
les liens symboliques ignorés ; dates et droits Unix sont restaurés. Les
archives Zip64 (plus de 65 535 entrées ou de 4 Go) sont lues et écrites ; les
entrées chiffrées ne sont pas prises en charge.
