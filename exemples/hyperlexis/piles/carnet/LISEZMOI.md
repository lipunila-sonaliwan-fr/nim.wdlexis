# Carnet d'adresses

Pile créée avec **HyperLexis**, l'atelier de piles de cartes pour Lexis+.

```
wdlexisrt principal.prg          # exécuter la pile
wdlexisgen .                     # générer l'application autonome
wdlexisrt <hyperlexis>/principal.prg .   # la modifier dans HyperLexis
```

| Fichier | Rôle |
| --- | --- |
| `principal.prg` | point d'entrée : `PILE_DEMARRER()` |
| `pile.prg` | titre, taille, ordre des cartes et modèle de chacune |
| `pile_donnees.prg` / `.json` | contenu des champs de chaque carte |
| `form_<modele>.prg` | dessin d'un modèle (concepteur de formulaires de wdlexis+) |
| `script_<modele>.prg` | procédures des événements du modèle |
| `script_pile.prg` | procédures communes |
| `pile_moteur.prg` | moteur d'exécution (recopié par HyperLexis) |
