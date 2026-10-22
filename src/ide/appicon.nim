# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - icône des fenêtres de l'atelier et du runtime (src/ressources/wdlexis-256.png,
#   produite par « nimble icones »), incorporée à la compilation.

import ../wdgui, imagedecode

const IconePng = staticRead("../ressources/wdlexis-256.png")

proc useLexisIcon*() =
  try:
    let img = decodePng(IconePng)
    setApplicationIcon(img.w, img.h, img.px)
  except CatchableError: discard
