# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - préparation des sources C du runtime des applications (dossier rtc/)
#
#   nimble rtc            (ou : nim r outils/rtc.nim [dossier_de_sortie])
#
# Transpile src/wdlexisapp.nim en C (nim --compileOnly --noMain:on) pour chaque
# cible et chaque variante, puis range les fichiers dans rtc/ :
#
#   rtc/VERSION                       versions de Nim et de wdlexis+, date
#   rtc/include/nimbase.h             en-tête de Nim
#   rtc/compat/darwin/...             compléments pour macOS (compilation croisée)
#   rtc/pool/<empreinte>.c            sources C, une seule copie par contenu
#   rtc/<cible>-<variante>.txt        manifeste : options C, options d'édition
#                                     de liens, puis « empreinte nom_d_origine »
#
# Cibles : linux-x64 linux-arm64 macos-x64 macos-arm64 windows-x64 windows-arm64
# Variantes : cli (console, service, bibliothèque), gui (interface wdgui)
#
# Le dossier rtc/ est livré avec wdlexis+ : l'utilisateur n'a besoin que de Zig.

import std/[os, osproc, json, strutils, tables, times, sets, hashes]

const
  Targets = [("linux-x64", "linux", "amd64"), ("linux-arm64", "linux", "arm64"),
             ("macos-x64", "macosx", "amd64"), ("macos-arm64", "macosx", "arm64"),
             ("windows-x64", "windows", "amd64"), ("windows-arm64", "windows", "arm64")]
  Variants = [("cli", ""), ("gui", "-d:wdlxGui")]

proc fnv64(s: string): uint64 =
  result = 0xcbf29ce484222325'u64
  for c in s:
    result = (result xor uint64(ord(c))) * 0x100000001b3'u64

proc keepCFlag(f: string): bool =
  if f.len == 0: return false
  if f in ["-c", "-w"] or f.startsWith("-O") or f.startsWith("-fmax-errors") or
     f.startsWith("-ferror-limit") or f.startsWith("-I") or f.startsWith("-o"): return false
  f.startsWith("-D") or f.startsWith("-f") or f.startsWith("-m") or f == "-pthread"

proc main() =
  let repo = currentSourcePath().parentDir.parentDir
  let outDir = if paramCount() >= 1: absolutePath(paramStr(1)) else: repo / "rtc"
  let tmp = getTempDir() / "wdlexis-rtc"
  let nimExe = findExe("nim")
  if nimExe.len == 0: quit "nim introuvable dans le PATH"
  let nimLib = nimExe.parentDir.parentDir / "lib"
  if not fileExists(nimLib / "nimbase.h"): quit "nimbase.h introuvable : " & nimLib
  removeDir(outDir / "pool")
  createDir(outDir / "pool")
  createDir(outDir / "include")
  copyFile(nimLib / "nimbase.h", outDir / "include" / "nimbase.h")
  # compléments macOS
  let compat = repo / "outils" / "compat"
  if dirExists(compat):
    removeDir(outDir / "compat")
    copyDir(compat, outDir / "compat")
  var pool = initTable[string, string]()     # empreinte -> contenu (contrôle des collisions)
  var total, unique = 0
  for (tname, os, cpu) in Targets:
    for (vname, vdef) in Variants:
      let cache = tmp / (tname & "-" & vname)
      removeDir(cache)
      let cmd = quoteShellCommand(@[nimExe, "c", "-d:release", "--hints:off", "--warnings:off",
        "--noMain:on", "--compileOnly", "--os:" & os, "--cpu:" & cpu, "--nimcache:" & cache] &
        (if vdef.len > 0: @[vdef] else: @[]) & @[repo / "src" / "wdlexisapp.nim"])
      echo "• ", tname, " ", vname
      let (outp, code) = execCmdEx(cmd)
      if code != 0:
        echo outp
        quit "échec de la transpilation : " & tname & " " & vname
      let j = parseFile(cache / "wdlexisapp.json")
      var cflags: seq[string]
      var lines: seq[string]
      for item in j["compile"]:
        let src = item[0].getStr
        let parts = item[1].getStr.splitWhitespace
        for f in parts:
          if keepCFlag(f) and f notin cflags: cflags.add f
        let data = readFile(src)
        var key = toHex(fnv64(data)).toLowerAscii & toHex(data.len, 6).toLowerAscii
        var n = 0
        while pool.hasKey(key) and pool[key] != data:
          inc n
          key = key[0 ..< 22] & "-" & $n
        if not pool.hasKey(key):
          pool[key] = data
          writeFile(outDir / "pool" / key & ".c", data)
          inc unique
        inc total
        lines.add key & " " & extractFilename(src)
      var ldflags: seq[string]
      let link = j["linkcmd"].getStr.splitWhitespace
      var i = 0
      while i < link.len:
        let f = link[i]
        if f == "-framework" and i + 1 < link.len:
          if link[i + 1] != "Security": ldflags.add f & " " & link[i + 1]   # Security : remplacé par compat
          inc i
        elif f.startsWith("-l") and f != "-lpthread": ldflags.add f
        elif f == "-pthread": ldflags.add f
        inc i
      var m = "# wdlexis+ rtc " & tname & " " & vname & "\n"
      m.add "cflags: " & cflags.join(" ") & "\n"
      m.add "ldflags: " & ldflags.join(" ") & "\n"
      m.add lines.join("\n") & "\n"
      writeFile(outDir / (tname & "-" & vname & ".txt"), m)
  let (nv, _) = execCmdEx(quoteShellCommand([nimExe, "-v"]))
  writeFile(outDir / "VERSION",
    "wdlexis+ runtime C (rtc)\n" &
    "nim: " & nv.splitLines()[0] & "\n" &
    "date: " & now().format("yyyy-MM-dd HH:mm") & "\n" &
    "fichiers: " & $total & " (" & $unique & " distincts)\n")
  echo "rtc : ", total, " fichiers, ", unique, " distincts -> ", outDir

main()
