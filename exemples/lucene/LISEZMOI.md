# Bibliothèque : recherche plein texte avec Lucene++

Exemple du paquet `lucene` : un petit catalogue de classiques de la littérature,
indexé par [Lucene++](https://github.com/luceneplusplus/LucenePlusPlus) (portage
C++ d'Apache Lucene 3.0) et interrogé pendant la frappe.

```
wdlexisrt exemples/lucene/principal.prg
```

## Prérequis

La bibliothèque du paquet, `wdlexis_lucene` (Lucene++ et Boost liés
statiquement) : `libwdlexis_lucene.so` (Linux), `libwdlexis_lucene.dylib`
(macOS) ou `wdlexis_lucene.dll` (Windows), dans le dossier `linOS` (`macOS`,
`winOS`) à côté de l'exécutable ou de ce programme, ou indiquée par la variable
`WDLEXIS_LUCENE`. Pour la construire : `sh outils/lucenepp.sh` à la racine de
wdlexis+ (git, cmake, compilateur C++17 ; sous Windows, shell MSYS2 MINGW64).

## Ce que montre l'exemple

| Fichier | Rôle |
| --- | --- |
| `principal.prg` | fenêtre de recherche : saisie, tri, résultats, fiche, termes indexés |
| `livres.prg` | le corpus (24 livres, résumés originaux) |

- `lucene.ouvrir(dossier, {analyseur = "francais", schema = {...}})` : l'index
  est créé dans le dossier personnel (`bibliotheque_lucene`) ; le schéma déclare
  l'identifiant et le genre comme valeurs exactes (`cle`), l'année et le nombre
  de pages comme nombres (`entier`).
- `idx:remplacer(livre)` : ajout ou mise à jour par identifiant ;
  `idx:valider()` : écriture sur disque.
- `idx:chercher(requete, {max, tri, inverse})` à chaque caractère saisi ;
  une requête incomplète (guillemet ou parenthèse non fermés) est ignorée.
- `idx:analyser(requete)` : la requête Lucene effectivement exécutée (barre
  d'état) ; `idx:termes(champ, prefixe)` : suggestions d'autocomplétion.

## Exemples de recherches

| Saisie | Résultat |
| --- | --- |
| `hugo` | les trois livres de Victor Hugo |
| `mer` | « mer » et « mers » (racines françaises) |
| `"comte de monte-cristo"` | la phrase exacte |
| `paris -hugo` | Paris, sans Victor Hugo |
| `annee:[1850 TO 1880]` | livres parus entre 1850 et 1880 |
| `genre:aventure` | les romans d'aventure |
| `voyag*`, `baudelair~` | joker, recherche floue |

L'index est au format Lucene 3.0 : Luke 3.x peut l'ouvrir pour en explorer les champs et les termes.
