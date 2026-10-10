# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - tous les paquets fournis
#
# Importer ce module enregistre les paquets (effet de bord à l'initialisation).
# Pour ajouter un paquet : écrire paquets/pkg_xxx.nim (voir lexis/api.nim) et
# l'ajouter ci-dessous ; il apparaît alors dans paquet(), la complétion et l'aide.

import ../lexis/fonctions
import pkg_es, pkg_systeme, pkg_donnees, pkg_reseau, pkg_sqlite, pkg_taches, pkg_interface

export newFullInterp, LexisExit, openWindows, closeAllWindows, loopNeeded, uiState, UiState
