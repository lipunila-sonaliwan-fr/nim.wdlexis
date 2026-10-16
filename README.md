Lexis+ &
wdlexis+ — l'atelier du langage Lexis+<br/>
© 2026 Jean‑Marc "jihem"Quéré, sonaliwan.fr<br/>
SIRET 13033319800013<br/>
Distribué sous licence CC BY‑NC‑SA 4.0.<br/>

Les utilisations commerciales ne sont pas couvertes par cette licence.<br/>
Pour obtenir une autorisation d'utilisation commerciale,<br/>
contactez l'auteur : metalab (at) sonaliwan.fr.<br/>

[![](wdlexis.png)]()

# wdlexis+ — l'atelier du langage Lexis+

**Lexis+ — Développez naturellement vos applications métier**

Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr<br/>
SIRET 13033319800013 — contact : metalab (at) sonaliwan.fr<br/>

wdlexis+ est le langage du serveur wdGestion V : instructions en français, procédures,
tables et métatables, base de données DuckDB manipulée en SQL ou enregistrement
par enregistrement à la manière de dBase. On y trouve :

- un **interpréteur Lexis+ écrit en Nim** (dossier `lexis/`), intégré à l'atelier
  et disponible en runtime autonome ;
- un **atelier** (`wdlexis.nim`) : éditeur avec coloration, complétion et analyse en
  continu, exécution directe ou **pas à pas** (points d'arrêt, variables, pile
  d'appels, zone de base de données courante), console avec saisie ;
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
  tests/                 tests du langage (sans interface graphique) ;
                         tests/firebird : liaison Firebird testée avec un client simulé ;
                         tests/webview : pont webview testé avec une bibliothèque simulée
  linOS/, macOS/, winOS/ bibliothèques webview (webview.so, .dylib, .dll)
```

## Compilation

```
cd apps/wdlexis
nimble atelier            # ou : nim c -d:release -o:wdlexis+ wdlexis.nim
nimble runtime            # ou : nim c -d:release wdlexisrt.nim
nimble test               # tests du langage, sans interface graphique
nimble testwebview        # pont webview, avec une bibliothèque simulée (gcc)
./wdlexis+ exemples/gestion
./wdlexisrt exemples/gestion/principal.prg
```

Le nom de l'exécutable de l'atelier est `wdlexis+` ; le source s'appelle
`wdlexis.nim` car le signe "+" est interdit dans un nom de module Nim.

Options utilisées : `--threads:on --mm:atomicArc -d:sdlttf -d:ssl`.

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
