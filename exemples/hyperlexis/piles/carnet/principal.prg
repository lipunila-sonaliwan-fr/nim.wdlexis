&& Pile « Carnet d'adresses » - créée avec HyperLexis (atelier de piles Lexis+).
&&
&&   wdlexisrt principal.prg            exécute la pile
&&   wdlexisgen <dossier de la pile>    application autonome (Linux, macOS, Windows)
&&
&& Le programme principal ouvre la pile ; le reste est dans les autres fichiers
&& (chargés automatiquement) : pile.prg, pile_donnees.prg, pile_moteur.prg,
&& script_pile.prg, et pour chaque modèle de carte form_<modele>.prg (dessin, à
&& modifier avec le concepteur de formulaires) et script_<modele>.prg (procédures).

PILE_DEMARRER()
interface.executer()
