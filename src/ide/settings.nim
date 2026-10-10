# Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr
#   wdlexis+ - atelier : préférences persistantes (JSON dans le dossier de configuration)

import std/[json, os]

type
  Settings* = object
    dark*: bool
    minimap*: bool
    flagGlobals*: bool       # signaler les variables non déclarées dans les procédures.
    unknownCalls*: bool      # signaler les appels de procédures inconnues.
    lastProject*: string
    programArgs*: string     # arguments passés au programme (séparés par des espaces).
    mainFile*: string        # fichier lancé par Exécuter ("" = principal.prg, sinon le fichier actif).

proc defaultSettings*(): Settings =
  Settings(dark: true, minimap: true, flagGlobals: true, unknownCalls: true)

proc settingsPath(): string = getConfigDir() / "wdlexis" / "reglages.json"

proc loadSettings*(): Settings =
  result = defaultSettings()
  try:
    let j = parseFile(settingsPath())
    template get(field: untyped, kind: untyped) =
      if j.hasKey(astToStr(field)): result.field = j[astToStr(field)].kind
    get(dark, getBool)
    get(minimap, getBool)
    get(flagGlobals, getBool)
    get(unknownCalls, getBool)
    get(lastProject, getStr)
    get(programArgs, getStr)
    get(mainFile, getStr)
  except CatchableError:
    discard

proc saveSettings*(s: Settings) =
  try:
    createDir(settingsPath().parentDir)
    writeFile(settingsPath(), pretty(%*s))
  except CatchableError:
    discard
