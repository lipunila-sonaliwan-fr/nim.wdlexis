# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# Dossier de base des ressources (bibliothèques linOS/macOS/winOS, polices ttf/) :
#   1. la variable d'environnement WDGUI_PATH si elle désigne un dossier ;
#   2. le dossier de l'exécutable (lancement par double-clic depuis le Finder, où
#      le dossier courant est le dossier personnel), ou ../Resources dans un .app ;
#   3. le dossier courant (comportement historique).
import std/os

proc wdguiBase*(probe: string): string =
  ## probe : chemin relatif d'une ressource attendue (ex. "macOS/libSDL3.dylib").
  let env = getEnv("WDGUI_PATH")
  if env.len > 0 and dirExists(env): return env
  let app = getAppDir()
  for d in [app, app / ".." / "Resources", getCurrentDir()]:
    if fileExists(d / probe) or dirExists(d / probe): return d
  "."
