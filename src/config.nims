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

# Icône et informations de version des exécutables Windows (wdlexis+, wdlexisrt,
# wdlexisgen) : ressources précompilées au format objet COFF, produites par
# « nimble icones » à partir de src/ressources/wdlexis.png. Acceptées telles quelles
# par MinGW (ld), Zig, clang (lld) et MSVC (link), y compris en compilation croisée.
when defined(windows):
  block:
    let exe = projectName()
    let cpu = when defined(amd64): "amd64" elif defined(arm64): "arm64" else: ""
    let res = thisDir() & "/ressources/windows/" & exe & "-" & cpu & ".o"
    if exe in ["wdlexis", "wdlexisrt", "wdlexisgen"] and cpu.len > 0 and fileExists(res):
      switch("passL", "\"" & res & "\"")
