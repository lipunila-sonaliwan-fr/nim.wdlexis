# wdlexis+ écrit en Lexis+

L'atelier wdlexis+ réécrit dans son propre langage.

```
wdlexisrt principal.prg [dossier_du_projet]
```

Sans dossier, l'atelier rouvre le dernier projet (ou, au premier lancement, son
propre dossier).

## Fonctions de l'atelier natif reprises

| Atelier natif | Ici |
| --- | --- |
| Menus Fichier, Édition, Recherche, Exécuter, Affichage, Aide | mêmes menus, mêmes libellés (`menus.prg`) |
| Barre d'outils, barre d'état, position du curseur | oui |
| Onglet Projet (arbre des fichiers) | oui |
| Onglet Structure (procédures, fonctions, globales) | oui (`lexis.structure`) |
| Onglet Référence + fiche Markdown, double-clic pour insérer | oui ; les fiches sont générées en Lexis+ (`reference.prg`) |
| Éditeur à onglets, coloration, complétion, minicarte | contrôle natif `ui.editeur` |
| Problèmes pendant la frappe, soulignés, clic pour aller à la ligne | oui (`lexis.verifier`) |
| Vérifier les fichiers ouverts | oui |
| Exécuter, console avec saisie, erreur → ligne fautive | oui (`lexis.executer`) |
| Débogueur : F5, F9, F10, F11, Maj+F11, Pause, Arrêter | oui (`surpause`, `x:pas()`…) |
| Variables, Pile d'appels (clic : variables du cadre) | oui |
| Rechercher, Remplacer, F3 / Ctrl+H, Aller à la ligne, F12 définition | oui (`ui.rechercher`, `ed:chercher`…) |
| Police, minicarte, thème sombre / clair, options d'analyse | oui, conservés dans `~/.wdlexis-atelier.json` |
| Session (fichiers ouverts), arguments, fichier principal | oui, dans `.wdlexis/atelier.json` du projet |
| Générer l'application | boîte en Lexis+, compilation par l'outil `wdlexisgen` ; mêmes réglages (`.wdlexis/application.ini`) |
| Concepteur de formulaires (menu Conception, double-clic sur un `form_<nom>.prg`) | oui (`concepteur.prg`) ; mêmes fichiers `form_<nom>.prg` que l'atelier natif |
| Éditeur d'états PDF (menu Conception, double-clic sur un `etat_<nom>.prg`) | oui (`etats.prg`) ; mêmes fichiers `etat_<nom>.prg` que l'atelier natif |

## Ce qui est en Lexis+ et ce qui est natif

| Partie | Où |
| --- | --- |
| Toute l'interface, les menus, la logique d'atelier | les 9 fichiers `.prg` (environ 3 000 lignes) |
| Éditeur de code | natif : `ui.editeur` (`ide/codeeditor.nim`) |
| Analyse du langage | natif : `lexis.verifier`, `lexis.structure` (`ide/lexislint.nim`) |
| Exécution et débogage dans un interpréteur séparé | natif : `lexis.executer` (`paquets/pkg_lexis.nim`) |
| Compilation de l'application | outil `wdlexisgen` (chaîne Zig) |
| Concepteur : canevas, palette, modèle, génération de `form_<nom>.prg` | natif : `ui.concepteur`, `ui.palette` (`ide/designer.nim`, `ide/formmodel.nim`) |
| Concepteur : fenêtre, hiérarchie, inspecteur, procédures, câblage, renommage | `concepteur.prg` |
| États : canevas, palette, modèle, mise en page, PDF | natif : `ui.etat`, `ui.paletteetat` (`ide/reportdesigner.nim`, `ide/etats.nim`, `ide/pdfwriter.nim`) |
| États : fenêtre, hiérarchie, inspecteur, renommage, aperçu, code d'exemple | `etats.prg` |

## Mesures (Linux, écran virtuel, frappe simulée à ~30 caractères/s)

| Fichier | Analyse + problèmes + structure |
| --- | --- |
| 14 lignes | 1 à 2 ms |
| 2 000 lignes | 54 à 96 ms ; l'affichage rattrape la frappe en moins de 0,3 s |

La frappe reste instantanée : l'éditeur est natif. Pendant une rafale de
frappes, l'atelier n'analyse pas deux fois le même texte.

## Différences connues avec l'atelier natif

- Les fichiers modifiés sont enregistrés avant l'exécution (l'atelier natif
  exécute les documents tels qu'à l'écran, même non enregistrés).
- Pendant la génération, le détail s'affiche dans la Console de l'atelier
  une fois l'outil terminé, pas au fil de l'eau.
- Les gestionnaires d'événements s'exécutent chacun sur leur fil, dans un ordre
  non garanti : l'atelier relit l'état réel (`ed:curseur()`) au lieu de se fier
  à l'ordre d'arrivée.
