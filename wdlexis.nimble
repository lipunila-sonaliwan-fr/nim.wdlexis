# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
version       = "1.6.0"
author        = "Jean-Marc QUÉRÉ, sonaliwan.fr"
description   = "wdlexis+ : atelier et runtime du langage Lexis+"
license       = "Propriétaire - tous droits réservés"
bin           = @[]
requires      "nim >= 2.2.0"

# Icônes : sous Windows, l'icône et les informations de version sont liées à
# l'exécutable (src/config.nims) ; sous macOS, l'icône est posée sur le fichier
# (Finder) après la compilation ; sous Linux, voir « nimble raccourci ».
proc iconeFinder(exe: string) =
  when defined(macosx):
    exec "nim r --hints:off outils/icones.nim macos " & exe

task atelier, "Compile l'atelier (exécutable wdlexis+)":
  exec "nim c -d:release -d:sdlttf -o:wdlexis+ src/wdlexis.nim"
  iconeFinder("wdlexis+")

task runtime, "Compile le runtime autonome (wdlexisrt)":
  exec "nim c -d:release -d:sdlttf src/wdlexisrt.nim"
  iconeFinder("src/wdlexisrt")

task icones, "Régénère les icônes et ressources Windows depuis src/ressources/wdlexis.png":
  exec "nim r --hints:off outils/icones.nim"

task raccourci, "Linux : ajoute wdlexis+ (avec son icône) au menu des applications":
  exec "nim r --hints:off outils/icones.nim linux wdlexis+"

task test, "Tests du langage Lexis+ (sans interface graphique)":
  exec "nim c -r -d:release tests/t_langage.nim"

task testwebview, "Test du paquet webview (bibliothèque webview simulée, sans affichage)":
  exec "nim c -r -d:release tests/t_webview.nim"

task rtc, "Runtime C des applications générées (dossier rtc/, toutes les cibles)":
  exec "nim r --hints:off outils/rtc.nim"

task generateur, "Outil de génération d'applications en ligne de commande (wdlexisgen)":
  exec "nim c -d:release -o:wdlexisgen src/wdlexisgen.nim"
  iconeFinder("wdlexisgen")

task testgeneration, "Génération d'une application pour l'hôte (Zig embarqué et rtc/ requis)":
  exec "nim c -r -d:release --hints:off -o:tests/t_generation tests/t_generation.nim"
