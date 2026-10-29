# HyperLexis

Atelier de piles de cartes pour Lexis+, dans l'esprit d'HyperCard / LiveCode,
écrit en Lexis+ : palette d'outils, inspecteur de propriétés, scripts Lexis+,
bascule en direct entre Conception et Exécution. Les piles sont des projets
wdlexis+ (wdlexisrt, atelier, concepteur de formulaires, wdlexisgen).

| Dossier | Contenu |
| --- | --- |
| `hyperlexis/` | l'atelier (9 fichiers `.prg`) et sa documentation `LISEZMOI.md` |
| `piles/carnet/` | pile d'exemple : un carnet d'adresses (2 modèles, 4 cartes) |
| `captures/` | captures d'écran |

Installation : copiez les deux dossiers dans le dossier de wdlexis+ (à côté de
`exemples/`), puis :

```
./wdlexisrt hyperlexis/principal.prg piles/carnet     # l'atelier, sur la pile d'exemple
./wdlexisrt piles/carnet/principal.prg                # la pile seule
./wdlexisgen piles/carnet                             # l'application autonome
```
