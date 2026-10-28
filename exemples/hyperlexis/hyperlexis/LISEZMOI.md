# HyperLexis — atelier de piles de cartes pour Lexis+

HyperLexis est un environnement de programmation visuelle dans l'esprit
des Plateformes Applicatives Orientées Cartes (PAOC), écrit en **Lexis+** et exécuté par le
runtime de wdlexis+. On y dessine des **cartes** avec une **palette d'outils**,
on règle chaque objet dans un **inspecteur de propriétés**, on écrit ses
**scripts** en Lexis+, et l'on **bascule à tout moment entre le mode Conception
et le mode Exécution**, dans la même fenêtre, sans rien relancer.

Une pile enregistrée est un **projet wdlexis+ ordinaire** : elle s'exécute avec
`wdlexisrt`, s'ouvre dans l'atelier wdlexis+ (natif ou `exemples/atelier`), ses
cartes s'ouvrent dans le concepteur de formulaires de wdlexis+, et elle se
compile en application autonome avec `wdlexisgen`.

```
wdlexisrt hyperlexis/principal.prg                        # dernière pile ouverte (ou l'exemple)
wdlexisrt hyperlexis/principal.prg ~/piles/ma_pile        # une pile donnée
wdlexisrt hyperlexis/principal.prg --exemple ~/piles/carnet   # crée la pile d'exemple puis l'ouvre
```

> Comme pour tout programme wdlexis+, le runtime doit trouver ses bibliothèques
> (`linOS/`, `macOS/`, `winOS/`, `ttf/`) : lancez-le depuis le dossier de
> wdlexis+, ou indiquez ce dossier dans la variable `WDGUI_PATH`.
> Ne placez pas le dossier d'une pile **dans** le dossier `hyperlexis/` : le
> runtime charge tous les `.prg` d'un dossier et de ses sous-dossiers.

---

## 1. Notions

| Notion | Dans HyperLexis | Fichier |
| --- | --- | --- |
| **Pile** (stack) | le dossier du projet : titre, taille des cartes, ordre des cartes | `pile.prg` |
| **Carte** (card) | une page de la pile : un nom et un modèle | (liste dans `pile.prg`) |
| **Modèle** (fond / background) | le dessin partagé par une ou plusieurs cartes, et son script | `form_<modele>.prg`, `script_<modele>.prg` |
| **Données** | le contenu des champs de *chaque* carte (texte saisi, case cochée, choix…) | `pile_donnees.prg` (+ `.json`) |
| **Script de la pile** | procédures communes et procédures appelées par le moteur | `script_pile.prg` |

Plusieurs cartes peuvent partager un modèle, comme les fiches d'un carnet
d'adresses sur un même fond : le dessin est commun, le contenu des
champs est propre à chaque carte. Une carte « à part » a simplement son propre
modèle (bouton **+ Carte**).

## 2. L'écran

```
┌ Fichier  Édition  Carte  Objet  Mode  Affichage  Aide ───────────────────────────────────────┐
│ [✎ Conception][▶ Exécution] ⏮ ◀ [carte ▾] ▶ ⏭ [+ Carte][+ Même] [Script carte] [Enregistrer]… │
├──────────────────────────────────────────────────────────┬╎┬───────────────────────────────────┤
│ Interface │ Script                                       │ ╎ │ Inspecteur │ Pile │ Outils │ Cartes │
│                                                          │ ╎ │                                   │
│   Interface : la carte (canevas du concepteur en         │ ╎ │ Inspecteur : objets, propriétés,  │
│   Conception, la pile qui fonctionne en Exécution)       │ ╎ │   contenu, événements → scripts   │
│   Script : l'éditeur de code Lexis+                      │ ╎ │ Pile : propriétés de la pile      │
│                                                          │ ╎ │ Outils : palette d'outils         │
├─────────────────────────── ⋯ ────────────────────────────┤ ╎ │ Cartes : ordre des cartes         │
│ Messages (boîte de messages) │ Problèmes                 │ ╎ │                                   │
└ barre d'état ────────────────────────────────────────────┴╎┴──────────────── mode · carte n / N ─┘
```

En haut, la barre de menus et, juste dessous, la barre de
boutons. Au centre, deux pages : **Interface** (la carte) et **Script**
(l'éditeur de code) ; dessous, **Messages** et **Problèmes**. À droite, une
colonne à onglets réunit **Inspecteur**, **Pile**, **Outils** et **Cartes**. Le
séparateur vertical (╎) et le séparateur horizontal (⋯) se glissent à la souris.
L'atelier passe tout seul à la page utile : *Interface* quand on change de carte
ou de mode, *Script* quand on crée ou ouvre une procédure.

- **Inspecteur** : objets de la carte, propriétés, contenu, événements
  (section 3).
- **Pile** : titre, taille des cartes (appliquée à tous les modèles), couleur de
  fond, barre de navigation et persistance des données de l'application —
  l'inspecteur de la pile.
- **Outils** : la palette d'outils (tous les contrôles du paquet `interface`) ;
  on glisse un outil sur la carte de la page *Interface*. Le mode se choisit avec
  les boutons ✎ Conception / ▶ Exécution de la barre (ou Ctrl+E).
- **Cartes** : l'ordre de la pile ; ▲ ▼ déplacent la carte, ⧉ la duplique (même
  modèle, mêmes données), ✕ la supprime ; *Renommer…* ; *Copier le modèle…* crée
  une carte avec une copie indépendante du dessin et du script.

## 3. Concevoir (mode Conception)

1. Glissez un outil de la palette sur la carte (ou cliquez-le : il est ajouté au
   conteneur sélectionné). La carte est en disposition **absolue** : l'objet se
   place librement ; poignées pour la taille, repères magenta pour l'alignement,
   flèches pour 1 pixel (Maj : 10), Suppr pour supprimer, Échap pour le parent.
2. **L'inspecteur** montre l'objet sélectionné :
   - *Propriétés* : `nom` (Entrée pour renommer ; les données des cartes
     suivent), `libelle`, `texte`, `indication`, éléments (`a;b;c`), `x`, `y`,
     `largeurfixe`, `hauteurfixe`, `couleur` et `fond` (sélecteur `…`), `etat`,
     `visible`, `infobulle`… ;
   - *Contenu sur cette carte* : pour un champ (saisie, cases, radio, combo,
     liste, compteur, curseur, notation, calendrier…), la valeur gardée pour la
     carte courante (vide : la valeur du dessin) ;
   - *Événements* : chaque événement a une liste — *(aucune)*, une procédure du
     projet, ou **+ nouveau script…**, qui écrit
     `procedure <MODELE>_<OBJET>_<EVENEMENT>(ev)` dans le script du modèle,
     l'associe et place le curseur dedans. Le bouton ✎ ouvre la procédure.
   - **✎ Modifier le script** (menu *Objet*) : ouvre ou crée la procédure de
     l'événement principal de l'objet (`surclic` d'un bouton, `surchangement`
     d'une saisie, `surselection` d'une liste, `surouverture` de la carte).
3. Sélectionnez **la carte** (bouton *Carte*, ou un clic dans le vide) pour
   renommer la carte et son modèle, changer son titre, et associer les
   événements `surouverture` / `surfermeture` de la carte.
4. *Objet > Dupliquer l'objet* (Ctrl+D) copie l'objet sélectionné, décalé, sans
   ses événements.

Le dessin est enregistré à chaque modification ; Ctrl+S enregistre tout.

## 4. Exécuter (mode Exécution)

**▶ Exécution** (ou Ctrl+E) : la pile fonctionne **dans la
fenêtre de l'atelier** — boutons, champs, scripts, navigation. Les champs saisis
sont gardés avec la carte. **✎ Conception** (Ctrl+E) revient au dessin sur la
carte affichée.

- Les boutons ⏮ ◀ ▶ ⏭ et la liste des cartes naviguent dans les deux modes
  (Ctrl+← / Ctrl+→ / Ctrl+Début / Ctrl+Fin aussi).
- Une **erreur de syntaxe** dans un script empêche le passage en Exécution :
  l'onglet *Problèmes* donne le fichier et la ligne, et l'éditeur s'y place.
- Une **erreur pendant l'exécution** d'un script est interceptée : elle
  s'affiche dans la boîte de messages, dans *Problèmes* et dans la barre d'état
  (avec l'événement, l'objet et la carte) ; l'atelier continue.
- Si un événement est associé à une procédure qui n'existe pas, l'atelier
  propose de la créer.
- **▷ Autonome** lance la pile enregistrée exactement comme `wdlexisrt`, dans sa
  propre fenêtre (paquet `lexis`, `lexis.executer`) ; sa sortie arrive dans la
  boîte de messages et ses données sont relues à sa fermeture.

### La boîte de messages

Onglet *Messages* (Ctrl+M). Elle exécute une commande
ou évalue une expression Lexis+ dans la pile en cours ; ↑ / ↓ rappellent les
commandes, un double-clic sur une ligne du journal la recopie.

```
NOMBRE_CARTES()
ALLER_CARTE("fiche_2")
? CHAMP("nom"), CARTE_COURANTE()
FIXER_CHAMP("notes", "à rappeler", "fiche_1")
compteur = 3
```

## 5. Scripts

Les scripts sont des procédures Lexis+. Les contrôles de la carte affichée sont
dans la variable `form<modele>` (celle des formulaires de wdlexis+) :

```lexis
procedure FICHE_OUVERTURE(ev)
  && surouverture de la carte
  formfiche.rang.libelle = "Carte " + NUMERO_CARTE() + " / " + NOMBRE_CARTES()
finprocedure

procedure FICHE_SUIVANTE_CLIC(ev)
  CARTE_SUIVANTE()
finprocedure
```

### Fonctions du moteur (`pile_moteur.prg`)

| Appel | Rôle |
| --- | --- |
| `ALLER_CARTE(cible)` | nom, numéro, `"suivante"`, `"precedente"`, `"premiere"`, `"derniere"`, `"retour"` |
| `CARTE_SUIVANTE()` `CARTE_PRECEDENTE()` `PREMIERE_CARTE()` `DERNIERE_CARTE()` `CARTE_RETOUR()` | navigation (`CARTE_RETOUR` : historique) |
| `CARTE_COURANTE()` `NUMERO_CARTE()` `NOMBRE_CARTES()` `LISTE_CARTES()` `MODELE_CARTE([carte])` | où l'on est |
| `NOUVELLE_CARTE([modele], [nom])` | ajoute une carte après la carte courante (même modèle par défaut) et y va |
| `SUPPRIMER_CARTE([nom])` | supprime une carte et ses données |
| `CONTROLE(nom)` | contrôle de la carte affichée |
| `CHAMP(nom, [carte])` / `FIXER_CHAMP(nom, valeur, [carte])` | contenu d'un champ, de la carte affichée ou d'une autre |
| `DONNEE(cle)` / `FIXER_DONNEE(cle, valeur)` | données de la pile, enregistrées avec elle |
| `TROUVER(texte)` | comme *find* : va à la prochaine carte dont un champ contient le texte |
| `MESSAGE(texte)` | boîte de messages (atelier) ou console (application) |
| `ENREGISTRER_PILE()` `QUITTER_PILE()` | application autonome |

Procédures facultatives, appelées si elles existent (dans `script_pile.prg` par
exemple) : `SUR_OUVERTURE_PILE()`, `SUR_FERMETURE_PILE()`,
`SUR_OUVERTURE_CARTE(nom)`, `SUR_FERMETURE_CARTE(nom)`.

Tout Lexis+ reste disponible (`interface.alerte`, `interface.demander`, `sql`,
`fichier`, `http`, `rapport`…). Dans une pile, écrivez `interface.` plutôt que
`ui.` (la variable `ui` n'existe que si un script la définit).

## 6. La sauvegarde : un projet wdlexis+

| Fichier | Contenu | Écrit par |
| --- | --- | --- |
| `principal.prg` | point d'entrée : `PILE_DEMARRER()` puis `interface.executer()` | HyperLexis (s'il manque) |
| `pile.prg` | `PILE_DEFINITION()` : titre, largeur, hauteur, couleur, navigation, persistance, cartes `{nom, modele}` | HyperLexis ; modifiable à la main |
| `pile_donnees.prg` | `PILE_DONNEES_INITIALES()` : contenu des champs de chaque carte | HyperLexis |
| `pile_donnees.json` | même contenu ; l'application autonome y garde son état | HyperLexis, l'application |
| `pile_moteur.prg` | moteur d'exécution (copie de celui de l'atelier) | HyperLexis |
| `form_<modele>.prg` | dessin d'un modèle : fonction `FORM<MODELE>_OUVRIR()` et lignes `&&§` | concepteur (HyperLexis ou wdlexis+) |
| `script_<modele>.prg` | procédures des événements, dans le bloc marqué du concepteur | vous |
| `script_pile.prg` | procédures communes | vous |
| `.wdlexis/application.ini` | réglages de *Générer l'application* (type graphique) | HyperLexis, wdlexis+ |
| `.wdlexis/atelier.json` | session de l'atelier wdlexis+ (scripts ouverts) | HyperLexis, atelier |

- Les **données des pages/écrans sont conservées** : ce qui est saisi en mode
  Exécution (ou dans l'inspecteur, *Contenu sur cette carte*) est écrit dans
  `pile_donnees.prg` — embarqué dans l'application générée — et dans
  `pile_donnees.json`. Clefs : `NOMCARTE → {NOMCONTROLE → valeur}` ; seules les
  valeurs différentes de celles du dessin sont gardées.
- L'application autonome repart de `pile_donnees.json` s'il existe (sinon de
  `pile_donnees.prg`) et l'écrit à chaque changement de carte et à la
  fermeture ; les cartes créées par `NOUVELLE_CARTE` y sont gardées
  (`_CARTES`). En rouvrant la pile, HyperLexis reprend cet état.
- Les modèles sont au **format du concepteur de formulaires de wdlexis+** :
  un double-clic sur `form_fiche.prg` dans l'atelier l'ouvre dans son concepteur,
  avec `script_fiche.prg` comme code associé ; ce que l'un enregistre, l'autre le
  relit.
- *Carte > Importer un formulaire wdlexis+…* ajoute un `form_<nom>.prg` existant
  comme modèle d'une nouvelle carte (quelle que soit sa disposition).
- Une carte supprimée avec son dernier modèle est rangée dans `.corbeille/`
  (extension `.txt` : elle n'est plus chargée).

### Exécuter, déboguer, compiler

```
wdlexisrt ~/piles/carnet/principal.prg            # exécuter
wdlexisrt exemples/atelier/principal.prg ~/piles/carnet   # ouvrir dans l'atelier Lexis+ (débogueur, F5…)
wdlexisgen ~/piles/carnet --cibles=linux-x64,windows-x64  # application autonome (dossier distribution/)
```

ou, depuis HyperLexis, **Générer…** (mêmes réglages que la boîte de wdlexis+,
dans `.wdlexis/application.ini` ; l'outil `wdlexisgen` doit être à côté du
runtime, avec sa chaîne Zig et le dossier `rtc/`).

## 7. Comment ça marche

- **Conception** : le canevas et la palette sont ceux du concepteur de
  formulaires de wdlexis+ (`ui.concepteur`, `ui.palette`) ; chaque modèle de
  carte est un formulaire en disposition absolue. Tout le reste — fenêtre,
  navigation, hiérarchie, inspecteur, contenu des cartes, scripts, renommages,
  copies — est en Lexis+.
- **Exécution** : la carte est construite par la fonction même du formulaire,
  `FORM<MODELE>_OUVRIR()`. Pendant l'appel, le moteur remplace
  `interface.fenetre` par `MOTEUR_HOTE`, qui renvoie un panneau de la fenêtre de
  la pile : le formulaire s'y construit au lieu d'ouvrir une fenêtre. Chaque
  gestionnaire d'événement passe ensuite par `MOTEUR_RELAIS`, qui l'appelle dans
  un `essayer` (une erreur de script n'arrête ni l'atelier ni l'application).
- **Bascule en direct** : l'atelier réunit formulaires, scripts et
  bibliothèques de la pile dans `~/.hyperlexis/exec/pile_exec.prg` et les charge
  par `lexis.charger` (recharger le même fichier remplace les procédures) ; les
  numéros de ligne des erreurs sont ramenés au vrai fichier.
- Le **même moteur** (`pile_moteur.prg`) sert dans l'atelier et dans
  l'application : ce que l'on voit en mode Exécution est ce que fera la pile
  autonome.

| Fichier de l'atelier | Rôle |
| --- | --- |
| `principal.prg` | fenêtre, réglages (`~/.hyperlexis/reglages.json`), démarrage |
| `hl_menus.prg` | menus, raccourcis, aide, pile d'exemple |
| `hl_pile.prg` | ouverture, enregistrement, fichiers de la pile |
| `hl_cartes.prg` | cartes et modèles : créer, dupliquer, copier, renommer, ordonner, importer |
| `hl_conception.prg` | canevas, palette, objets, inspecteur, page Pile |
| `hl_scripts.prg` | éditeur de scripts, analyse pendant la frappe, procédures des événements |
| `hl_execution.prg` | mode Exécution, boîte de messages, pile autonome, génération |
| `hl_outils.prg` | outils communs (littéraux, dessin JSON, blocs marqués) |
| `pile_moteur.prg` | moteur d'exécution des piles (recopié dans chaque pile) |

## 8. Raccourcis

| Touche | Action |
| --- | --- |
| Ctrl+E | bascule Conception / Exécution |
| Ctrl+S | enregistre la pile |
| Ctrl+N | nouvelle carte sur le même modèle |
| Ctrl+D | duplique l'objet sélectionné |
| Ctrl+M | boîte de messages |
| Ctrl+← / Ctrl+→, Ctrl+Début / Ctrl+Fin | carte précédente / suivante, première / dernière |
| Suppr, Échap, flèches | (canevas) supprimer, parent, déplacer |
| Ctrl+R, Ctrl+Espace | (script) bascule le mode, complétion |

## 9. Limites connues

- En Conception, le canevas montre le **dessin du modèle**, commun à ses
  cartes ; le contenu propre à chaque carte se voit en Exécution et, objet par
  objet, dans l'inspecteur (*Contenu sur cette carte*).
- Une erreur d'exécution est signalée sans numéro de ligne (`capturer` de
  Lexis+ ne donne que le message) ; les erreurs de syntaxe ont fichier et ligne.
- Seuls les gestionnaires associés dans le dessin sont protégés par le relais ;
  un gestionnaire posé par un script (`formfiche.ok.surclic = @X`) est appelé
  directement.
- En mode Exécution, un script qui appelle `systeme.quitter()` ou
  `interface.quitter()` ferme aussi l'atelier (ils partagent le programme).
- Les modèles sont les `form_*.prg` de la racine de la pile.
