# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - génération d'applications en ligne de commande (sans interface)
#
#   wdlexisgen <dossier_du_projet> [options]
#     --type=console|graphique|service|bibliotheque
#     --cibles=linux-x64,linux-arm64,macos-x64,macos-arm64,windows-x64,windows-arm64|toutes
#     --archive                 distribution en archive (zip / tar.gz) au lieu d'un dossier
#     --sans-bibliotheques      ne pas intégrer linOS / macOS / winOS et ttf
#     --icone=image.png         icône (type graphique) ; --cadrage=gauche,haut,cote (fractions)
#     --principal=fichier.prg   fichier principal (défaut : principal.prg)
#     --sauver                  enregistre ces paramètres dans le projet (.wdlexis/application.ini)
#
# Sans option, les paramètres enregistrés par l'atelier (bouton [Sauver]) sont utilisés.
# Même chaîne que la boîte « Générer l'application » de l'atelier (ide/toolchain.nim).

import std/[os, strutils, terminal]
import ide/[toolchain, imagetools]

proc usage() =
  echo "wdlexisgen <dossier_du_projet> [--type=...] [--cibles=...] [--archive] [--sans-bibliotheques]"
  echo "           [--icone=image] [--cadrage=g,h,c] [--principal=fichier.prg] [--sauver]"

proc main(): int =
  var root, mainRel = ""
  var opts: seq[(string, string)]
  for i in 1 .. paramCount():
    let a = paramStr(i)
    if a.startsWith("--"):
      let p = a.find('=')
      if p > 0: opts.add (a[2 ..< p], a[p + 1 .. ^1]) else: opts.add (a[2 .. ^1], "")
    elif root.len == 0: root = a
  if root.len == 0 or not dirExists(root):
    usage()
    return 1
  for (k, v) in opts:
    if k == "principal": mainRel = v
  let info = analyzeProject(root, mainRel)
  var s = loadSettings(info)
  var save = false
  for (k, v) in opts:
    case k
    of "type":
      for a in AppType:
        if $a == v: s.appType = a
    of "cibles":
      s.targets = {}
      for c in v.split(','):
        if c == "toutes": s.targets = {tgLinuxX64 .. tgWinArm64}
        for t in Target:
          if $t == c.strip: s.targets.incl t
    of "archive": s.dist = dmArchive
    of "dossier": s.dist = dmFolder
    of "sans-bibliotheques": s.bundleLibs = false
    of "bibliotheques": s.bundleLibs = true
    of "icone": s.iconPath = absolutePath(v)
    of "cadrage":
      let n = v.split(',')
      if n.len == 3: s.crop = Crop(left: parseFloat(n[0]), top: parseFloat(n[1]), side: parseFloat(n[2]))
    of "sauver": save = true
    of "principal": discard
    of "aide", "help":
      usage()
      return 0
    else:
      stderr.writeLine "option inconnue : --", k
      return 1
  if info.usesUi: s.appType = atGraphique
  if save: saveSettings(info, s)
  let color = isatty(stdout)
  var hooks: BuildHooks
  hooks.log = proc (kind: LogKind, text: string) =
    {.cast(gcsafe).}:
      let (pre, post) =
        if not color: ("", "")
        else:
          case kind
          of lgStep: ("\e[33m", "\e[0m")
          of lgWarning: ("\e[38;5;208m", "\e[0m")
          of lgError: ("\e[31m", "\e[0m")
          of lgDone, lgFinal: ("\e[32m", "\e[0m")
          of lgCommand: ("\e[37m$ ", "\e[0m")
          else: ("", "")
      if kind in {lgStep, lgDone, lgFinal}: echo ""
      echo pre, (if kind == lgCommand and not color: "$ " else: ""), text, post
      if kind in {lgStep, lgDone}: echo ""
  hooks.progress = proc (f: float, label: string) = discard
  hooks.cancelled = proc (): bool = false
  if build(info, s, getAppDir(), hooks): 0 else: 2

when isMainModule:
  quit main()
