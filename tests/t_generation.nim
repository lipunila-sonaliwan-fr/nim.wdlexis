# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - test de la génération d'applications (Zig embarqué, dossier rtc/)
#
#   nimble testgeneration
#
# Génère un petit projet pour le système hôte en console puis en bibliothèque,
# exécute l'application et appelle la bibliothèque. Nécessite Zig (linZG, macZG
# ou winZG) et rtc/ dans le dossier de wdlexis+.

import std/[os, osproc, strutils, dynlib]
import ../src/ide/toolchain

let repo = currentSourcePath().parentDir.parentDir

proc hostTarget(): Target =
  when defined(windows): (when defined(arm64): tgWinArm64 else: tgWinX64)
  elif defined(macosx): (when defined(arm64): tgMacArm64 else: tgMacX64)
  else: (when defined(arm64): tgLinuxArm64 else: tgLinuxX64)

proc main(): int =
  let (zig, _, err) = findZig(repo)
  if zig.len == 0 or findRtc(repo).len == 0:
    echo "test ignoré : ", (if err.len > 0: err else: "rtc/ introuvable")
    return 0
  let proj = getTempDir() / "wdlexis_t_generation" / "essai"
  removeDir(proj.parentDir)
  createDir(proj)
  writeFile(proj / "principal.prg",
    "? \"Bonjour\", CARRE(7)\n? fichier.lire(systeme.dossierprogramme() + \"/donnees.txt\")\n")
  writeFile(proj / "outils.prg", "fonction CARRE(n)\nretourner n * n\n")
  writeFile(proj / "donnees.txt", "données")
  let info = analyzeProject(proj)
  var s = defaultSettings(info)
  s.targets = {hostTarget()}
  s.bundleLibs = false
  var errors: seq[string]
  var hooks: BuildHooks
  hooks.log = proc (k: LogKind, t: string) =
    {.cast(gcsafe).}:
      if k == lgError: errors.add t
  hooks.progress = proc (f: float, l: string) = discard
  hooks.cancelled = proc (): bool = false
  # console
  s.appType = atConsole
  if not build(info, s, repo, hooks):
    echo "échec de la génération (console) :\n", errors.join("\n")
    return 1
  let dist = proj / OutputDirName / (info.name & "-" & $hostTarget())
  let exe = dist / (when defined(windows): info.name & ".exe" else: info.name)
  let (outp, code) = execCmdEx(quoteShell(exe))
  let expected = "Bonjour 49\ndonnées\n"
  if code != 0 or outp.replace("\r\n", "\n") != expected:
    echo "sortie inattendue (code ", code, ") :\n", outp
    return 1
  echo "console : OK"
  # bibliothèque
  s.appType = atBibliotheque
  if not build(info, s, repo, hooks):
    echo "échec de la génération (bibliothèque) :\n", errors.join("\n")
    return 1
  let libName = when defined(windows): info.name & ".dll"
                elif defined(macosx): "lib" & info.name & ".dylib"
                else: "lib" & info.name & ".so"
  let h = loadLib(dist / libName)
  if h.isNil:
    echo "bibliothèque introuvable : ", dist / libName
    return 1
  type
    Appeler = proc (p, a: cstring): cstring {.cdecl, gcsafe.}
    Liberer = proc (s: cstring) {.cdecl, gcsafe.}
  let appeler = cast[Appeler](h.symAddr("wdlexis_appeler"))
  let liberer = cast[Liberer](h.symAddr("wdlexis_liberer"))
  let r = appeler("carre", "[12]")
  if r.isNil or $r != "144":
    echo "wdlexis_appeler : résultat inattendu"
    return 1
  liberer(r)
  echo "bibliothèque : OK"
  removeDir(proj.parentDir)
  0

quit main()
