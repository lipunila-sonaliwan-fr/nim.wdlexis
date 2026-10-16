# Exemples webview

Des pages HTML / CSS / JavaScript dans une fenêtre native, reliées à Lexis+
dans les deux sens (voir le chapitre 5.1 de `DOCUMENTATION.md`).

| Dossier | Ce qu'il montre |
| --- | --- |
| `01_bonjour` | Le minimum : page HTML écrite dans le programme, un bouton qui appelle une procédure Lexis+ (`f:lier`) et affiche sa réponse. |
| `02_lexis_vers_js` | **Lexis+ → JavaScript** : `f:appeler` (avec et sans rappel, fonction asynchrone, chemin `app.theme`), `f:evaluer`, `f:emettre` ; la page demande à Lexis+ d'agir avec `lexis.envoyer`, et Lexis+ la met à jour. |
| `03_js_vers_lexis` | **JavaScript → Lexis+** : fonctions liées (`await calculerTTC(ht, taux)`), procédures autorisées (`lexis.appeler("ENREGISTRER", fiche)`), erreurs Lexis+ reçues comme des `Promise` rejetées, appel refusé, console. |
| `04_application` | Une liste de tâches : la page est l'interface, Lexis+ garde les données (règles, `taches.json`) et prévient la page à chaque changement (`f:emettre`). |

## Lancer un exemple

```
wdlexisrt exemples/webview/02_lexis_vers_js/principal.prg
```

ou, sous Windows et Linux, depuis l'atelier (`./wdlexis+ exemples/webview/02_lexis_vers_js`,
puis *Ctrl+R*). Sous macOS, utilisez le runtime : une fenêtre web doit appartenir
au fil principal du processus.

La bibliothèque webview est cherchée dans `winOS/`, `macOS/` ou `linOS/` à côté
de l'exécutable ou du programme (celles du dossier racine du projet conviennent :
copiez le dossier à côté de `wdlexis+` / `wdlexisrt`), ou dans la variable
`WDLEXIS_WEBVIEW`. Il faut aussi le moteur web du système :

- **Windows 10 / 11** : runtime WebView2 (présent par défaut sur les systèmes à jour) ;
- **macOS** : WKWebView, toujours présent ;
- **Linux** : WebKitGTK 4.1 (`sudo apt install libwebkit2gtk-4.1-0` sous Debian / Ubuntu).

Les messages `console.log` de la page et les erreurs JavaScript s'affichent dans
la console de l'atelier ou du terminal (`[js] ...`). `debogage = vrai` dans
`webview.fenetre{...}` active les outils de développement (clic droit, *Inspecter*).
