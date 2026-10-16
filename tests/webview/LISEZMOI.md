# Test du paquet webview sans affichage

Deux tests complémentaires, qui ne demandent ni écran ni moteur web installé.

## 1. Le pont Lexis+ ⇄ webview (`t_webview.nim` + `wvmock.c`)

`wvmock.c` est une bibliothèque webview **factice** : elle exporte l'API C de
webview/webview 0.12 (`webview_create`, `webview_bind`, `webview_return`,
`webview_dispatch`...) utilisée par `src/paquets/pkg_webview.nim`, écrit chaque
appel sur la sortie (`[mock] ...`) et, dans `webview_run`, rejoue
`scenario.txt` : chaque ligne simule un appel JavaScript d'une fonction liée
(`js total [2,3]`), la fermeture de la fenêtre (`fermer`) ou une pause
(`attendre 300`). Les blocs séparés par `---` servent aux fenêtres successives.

```
nimble testwebview                    # ou : nim c -r -d:release tests/t_webview.nim
nim c -r tests/t_webview.nim --maj    # régénère principal.attendu
```

Le test compile `wvmock.c` avec gcc, exécute `principal.prg` et compare la
sortie à `principal.attendu` : liaisons (`f:lier`), procédures autorisées
(`lexis.appeler`) et refusées, appels mis en attente avant le chargement de la
page, rappels (`f:appeler ..., @RAPPEL`), erreurs Lexis+ renvoyées à
JavaScript, `systeme.quitter()` depuis un appel JavaScript, fermeture par
`f:fermer()` et par l'utilisateur.

Avec le runtime :

```
gcc -shared -fPIC -o webview.so tests/webview/wvmock.c
WDLEXIS_WEBVIEW=$PWD/webview.so WVMOCK_SCRIPT=tests/webview/scenario.txt ./wdlexisrt tests/webview/principal.prg
```

## 2. Le script `window.lexis` et les pages des exemples (`t_pages.js`)

Charge le script injecté par le paquet (extrait de `pkg_webview.nim`) et les
pages de `exemples/webview` dans Chromium (Playwright), avec un
`window.__lexis` simulé comme le fait webview : `_appeler`, `_evaluer`,
`_emettre`, `lexis.appeler`, `lexis.envoyer`, redirection de la console et des
erreurs, puis le fonctionnement de chaque page (46 vérifications).

```
npm i playwright && npx playwright install chromium
node tests/webview/t_pages.js
```
