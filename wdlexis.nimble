# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
version       = "1.5.0"
author        = "Jean-Marc QUÉRÉ, sonaliwan.fr"
description   = "wdlexis+ : atelier et runtime du langage Lexis+"
license       = "Propriétaire - tous droits réservés"
bin           = @[]
requires      "nim >= 2.2.0"

task atelier, "Compile l'atelier (exécutable wdlexis+)":
  exec "nim c -d:release -d:sdlttf -o:wdlexis+ src/wdlexis.nim"

task runtime, "Compile le runtime autonome (wdlexisrt)":
  exec "nim c -d:release -d:sdlttf src/wdlexisrt.nim"

task test, "Tests du langage Lexis+ (sans interface graphique)":
  exec "nim c -r -d:release tests/t_langage.nim"
