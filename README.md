Lexis+ &
wdlexis+ - l'atelier du langage Lexis+<br/>
© 2026 Jean‑Marc "jihem"Quéré, sonaliwan.fr<br/>
SIRET 13033319800013<br/>
Distribué sous licence CC BY‑NC‑SA 4.0.<br/>

Les utilisations commerciales ne sont pas couvertes par cette licence.<br/>
Pour obtenir une autorisation d'utilisation commerciale,<br/>
contactez l'auteur : metalab (at) sonaliwan.fr.<br/>

[![](wdlexis.png)]()

# wdlexis+ - l'atelier du langage Lexis+

**Lexis+ - Développez naturellement vos applications métier**

Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr<br/>
SIRET 13033319800013 - contact : metalab (at) sonaliwan.fr<br/>

wdlexis+ est le langage du serveur wdGestion V : instructions en français, procédures,
tables et métatables, base de données DuckDB manipulée en SQL ou enregistrement
par enregistrement à la manière de dBase. On y trouve :

- un **interpréteur Lexis+ écrit en Nim** (dossier `lexis/`), intégré à l'atelier
  et disponible en runtime autonome ;
- un **atelier** (`wdlexis.nim`) : éditeur avec coloration, complétion et analyse en
  continu, exécution directe ou **pas à pas** (points d'arrêt, variables, pile
  d'appels, zone de base de données courante), console avec saisie, et un
  **concepteur de formulaires** (menu *Conception*) qui dessine les fenêtres à la
  souris et génère le code Lexis+, et un **éditeur d'états** : des zones (en-tête,
  pied, zones nommées) dessinées au millimètre, remplies par le programme avec le
  paquet `rapport` pour produire des PDF de plusieurs pages ;
- des **paquets** écrits en Nim, aux noms français : entrées / sorties, système,
  fichiers, binaire, CSV, JSON, réseau (TCP/UDP, HTTP/HTTPS, FTP, SSH/SFTP),
  SQLite, **Firebird**, tâches, fils d'exécution, **l'interface graphique wdgui** et
  des **pages web** (HTML / JavaScript) dans une fenêtre native avec `webview` ;
- des paquets d'**intelligence artificielle** construits sur la bibliothèque
  **nimllm** (100 % Nim, intégrée) : modèles de langage GGUF (Llama 3, Mistral,
  Qwen) avec dialogue, pièces jointes, réponses JSON / image / audio (`llm`),
  fichiers GGUF et quantification (`gguf`), images et SVG (`dessin`), synthèse
  vocale (`audio`), tenseurs à gradients (`tenseur`) et création ou
  spécialisation de modèles (`entrainement`).

Les programmes du serveur wdGestion V s'exécutent tels quels (sauf les
instructions propres aux pages web : `envoyer`, `rediriger`, `statut`, `entete`,
`deconnecter`). La documentation complète est dans `DOCUMENTATION.md`.

## Un premier programme

```
&& principal.prg
? "Bonjour !"
pour i = 1 a 3
  ? i, CARRE(i)
suivant

fonction CARRE(n)
retourner n * n
```

## Arborescence

```
wdlexis/
  wdlexis.nim            atelier (fenêtre principale) -> exécutable wdlexis+
  wdlexisrt.nim          runtime autonome
  wdlexis.nimble         tâches de compilation et de test
  config.nims            options de compilation (chemin de wdgui)
  lexis/                 interpréteur Lexis+
    core.nim             valeurs, tables, arbre syntaxique, état
    lexer.nim            analyse lexicale
    parser.nim           analyse syntaxique et résolution des variables locales
    interp.nim           évaluation, métatables, zones, tâches, débogueur
    fonctions.nim        fonctions intégrées (majuscule, requete, json, hachermdp...)
    zones.nim            base DuckDB et zones de travail (utiliser, parcourir...)
    duck.nim             liaison DuckDB chargée à l'exécution
    crypto.nim           SHA-256 et PBKDF2 (mots de passe)
    api.nim              API pour écrire des paquets en Nim
  nimllm/, nimllm.nim    bibliothèque LLM (inférence GGUF, dialogue, entraînement)
  paquets/               paquets fournis (tous.nim les enregistre tous)
    pkg_firebird.nim     client Firebird (bibliothèque fbclient chargée à l'exécution)
    pkg_webview.nim      pages HTML / JavaScript dans une fenêtre native (bibliothèque webview
                         chargée à l'exécution), pont JavaScript <-> Lexis+
    pkg_llm.nim ...      llm, gguf, dessin, audio, tenseur, entrainement
                         (llm_commun.nim, llm_objets.nim : objets partagés)
  ide/                   éditeur, coloration, analyse, session de débogage
  exemples/              programmes d'exemple (un dossier par projet)
    llm/                 20 exemples d'IA (01_bonjour ... 20_reprise_entrainement)
    firebird/            base Firebird
    webview/             pages web : bonjour, Lexis+ -> JS, JS -> Lexis+, application
    formulaire/          fiche client dessinée avec le concepteur de formulaires
    etats/               facture PDF de deux pages (éditeur d'états, paquet rapport)
    duckdbstudio/        atelier DuckDB : SQL, profil, recommandations, schéma, pipelines,
                         planification, BI, assistant IA, extensions
  tests/                 tests du langage (sans interface graphique) ;
                         tests/firebird : liaison Firebird testée avec un client simulé ;
                         tests/webview : pont webview testé avec une bibliothèque simulée
  linOS/, macOS/, winOS/ bibliothèques webview (webview.so, .dylib, .dll)
  wdlexisapp.nim         runtime des applications générées (projet embarqué)
  wdlexisgen.nim         génération d'applications en ligne de commande
  ide/toolchain.nim      chaîne de génération : projet -> C -> Zig -> distribution
  ide/generer.nim        boîte « Générer l'application » (menu Exécuter)
  ide/designer.nim, ide/formmodel.nim
                         concepteur de formulaires (menu Conception) : canevas,
                         palette, repères, hiérarchie, inspecteur ; modèle et
                         génération de form_<nom>.prg
  ide/reportdesigner.nim éditeur d'états (menu Conception)
  ide/etats.nim          états : modèle, mise en page, pagination (sans interface)
  ide/pdfwriter.nim, ide/pdfmetrics.nim, ide/zflate.nim
                         écriture PDF en Nim pur : polices standard, images PNG / JPEG,
                         compression zlib
  paquets/pkg_rapport.nim  paquet rapport (rapport.debut, r.ajoute, r.entete, r.pied, r.fin)
  ide/shellview.nim, ide/cropview.nim, ide/imagetools.nim, ide/archives.nim
                         journal coloré, cadrage d'icône, images (stb), zip / tar.gz
  rtc/                   runtime Lexis+ pré-transpilé en C, pour chaque cible
                         (généré par « nimble rtc »)
  linZG/, macZG/, winZG/ Zig embarqué pour l'hôte Linux, macOS, Windows :
                         <arch>/zig[.exe] et lib/
  outils/                rtc.nim (génère rtc/), compat/ (macOS), elaguer_zig.sh,
                         preparer_zig.sh / .ps1 (installe Zig pour un hôte),
                         distribution.sh (archive wdlexis+ + Zig)
```

## Générer une application (Linux, macOS, Windows)

*Exécuter > Générer l'application…* produit, depuis n'importe quel système, des
exécutables pour **Linux x64 / arm64, macOS x64 / Apple Silicon et Windows x64 /
arm64** : type console, graphique (avec icône), service ou bibliothèque,
distribution en dossier ou en archive, bibliothèques et polices intégrées. Le
projet est transpilé en C puis compilé par **Zig 0.17.0**, embarqué dans
wdlexis+ ; aucune autre installation n'est nécessaire. Détails : section 8.1 de
`DOCUMENTATION.md`.

| Dossier | Contenu |
| --- | --- |
| `linZG/x86_64`, `linZG/aarch64` + `linZG/lib` | Zig pour un hôte Linux x64 / arm64 |
| `macZG/aarch64` + `macZG/lib` | Zig pour un hôte macOS Apple Silicon |
| `winZG/x86_64` + `winZG/lib` | Zig pour un hôte Windows x64 (aussi utilisé, émulé, sous Windows arm64) |
| `rtc/` | runtime Lexis+ en C (6 cibles x 2 variantes : sans / avec interface) |

`outils/preparer_zig.sh` installe Zig pour un hôte absent de la distribution
(macOS Intel, Windows arm64) depuis ziglang.org, avec contrôle de l'empreinte
SHA-256.

## Compilation

**IMPORTANT**\
Pour pouvoir compiler :
- vers Linux, décompressez l'archive 7-Zip nommée **linZG.7z** (→ crée un dossier `linZG` au même niveau que le dossier `linOS`),
- vers macOS, décompressez l'archive 7-Zip nommée **macZG.7z** (→ crée un dossier `macZG` au même niveau que le dossier `macOS`),
- vers Windows, décompressez l'archive 7-Zip nommée **winZG.7z** (→ crée un dossier `winZG` au même niveau que le dossier `winOS`).

Toutes les versions de wdLexis+ (Linux, macOS et Windows) peuvent générer des exécutables pour toutes ces plates-formes (et pas seulement celle où wdLexis+ est utilisée).

```
cd apps/wdlexis
nimble atelier            # ou : nim c -d:release -o:wdlexis+ wdlexis.nim
nimble runtime            # ou : nim c -d:release wdlexisrt.nim
nimble test               # tests du langage, sans interface graphique
nimble testwebview        # pont webview, avec une bibliothèque simulée (gcc)
nimble rtc                # régénère rtc/ (runtime C des applications) après
                          # une modification de l'interpréteur ou des paquets
nimble generateur         # outil en ligne de commande wdlexisgen
nimble icones             # régénère les icônes après avoir changé src/ressources/wdlexis.png
nimble raccourci          # Linux : ajoute wdlexis+ (avec son icône) au menu des applications
./wdlexis+ exemples/gestion
./wdlexisrt exemples/gestion/principal.prg
```

Le nom de l'exécutable de l'atelier est `wdlexis+` ; le source s'appelle
`wdlexis.nim` car le signe "+" est interdit dans un nom de module Nim.

Options utilisées : `--threads:on --mm:atomicArc -d:useMalloc -d:sdlttf -d:ssl`.

### Icônes

L'icône vient de `src/ressources/wdlexis.png` (carrée, 1024 px). Ce que voit chaque système :

| Système | Icône du fichier | Icône des fenêtres |
| --- | --- | --- |
| Windows | liée à l'exécutable par `src/config.nims` (ressources `src/ressources/windows/<exe>-<amd64\|arm64>.o`, avec les informations de version) : Explorateur, raccourcis | barre de titre, barre des tâches |
| macOS | posée sur le fichier par `nimble atelier` / `runtime` / `generateur` (Finder) | Dock |
| Linux | menu des applications après `nimble raccourci` | barre des tâches, sélecteur de fenêtres |

Les ressources Windows sont des objets COFF écrits par `outils/icones.nim` (sans
`windres`) : elles sont prises en compte aussi avec un simple `nim c`, avec MinGW,
Zig, clang ou MSVC, et en compilation croisée. L'icône des fenêtres est incorporée à
`wdlexis+` et `wdlexisrt` ; un programme Lexis+ peut choisir la sienne avec
`interface.icone(chemin)`.

Bibliothèques chargées à l'exécution, seulement si le programme s'en sert :

| Bibliothèque | Pour | Où la placer |
| --- | --- | --- |
| DuckDB (`libduckdb.dylib`, `.so`, `duckdb.dll`) | `sql`, `utiliser`, `requete`... | dossier `macOS/` (`linOS/`, `winOS/`) à côté de l'exécutable ou du programme, ou chemin dans `WDLEXIS_DUCKDB` |
| SDL3, SDL3_ttf | wdgui | comme pour wdgui |
| OpenSSL | HTTPS, TLS | bibliothèque du système |
| SQLite 3 | paquet `sqlite` | bibliothèque du système |
| Client Firebird (`libfbclient.so`, `.dylib`, `fbclient.dll`) | paquet `firebird` | client Firebird installé, dossier `linOS/` (`macOS/`, `winOS/`) à côté de l'exécutable ou du programme, ou chemin dans `WDLEXIS_FIREBIRD` |
| webview (`webview.so`, `webview.dylib`, `webview.dll`) | paquet `webview` | dossier `linOS/` (`macOS/`, `winOS/`) à côté de l'exécutable ou du programme (fournies), ou chemin dans `WDLEXIS_WEBVIEW` ; moteur web du système : WebView2 (Windows 10/11), WKWebView (macOS), WebKitGTK 4.1 (Linux : `libwebkit2gtk-4.1-0`) |

Les paquets d'IA (`llm`, `gguf`, `dessin`, `audio`, `tenseur`, `entrainement`)
n'utilisent aucune bibliothèque externe ; il suffit d'un modèle au format GGUF
(par exemple Llama-3.2-1B-Instruct-Q4_K_M.gguf, ou celui que crée
`exemples/llm/17_creer_modele`). Pour une compilation destinée à la seule
machine locale, `--passC:-march=native` accélère encore les calculs.

SSH et SFTP utilisent le client OpenSSH installé.

Sans DuckDB, l'atelier et le runtime démarrent normalement ; seules les
instructions de base de données signalent l'absence de la bibliothèque.
