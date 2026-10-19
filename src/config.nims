# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
switch("path", "../../src")
switch("threads", "on")
switch("mm", "atomicArc")
# Allocateur C (thread-safe) : wdgui exécute chaque gestionnaire d'événement sur
# son propre fil, et l'interpréteur partagé y libère des valeurs allouées par
# d'autres fils (déjà terminés). Avec l'allocateur de Nim, cela finissait par
# planter (SIGSEGV dans addToSharedFreeList) sous une rafale d'événements.
switch("define", "useMalloc")
switch("define", "sdlttf")
switch("define", "ssl")          # HTTPS et TLS (OpenSSL chargé à l'exécution).
switch("stackTrace", "on")
