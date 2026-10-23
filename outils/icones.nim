# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - icônes des exécutables compilés avec Nim (wdlexis+, wdlexisrt, wdlexisgen)
#
#   nimble icones                   (ou : nim r outils/icones.nim)
#       À relancer après avoir changé src/ressources/wdlexis.png (carré, 1024 px conseillé).
#       Produit dans src/ressources/ :
#         wdlexis-256.png              icône des fenêtres (incorporée par wdlexis+ et wdlexisrt)
#         windows/<exe>-<cpu>.o        ressources Windows (icône + VERSIONINFO) au format
#                                      objet COFF, pour amd64 et arm64 ; config.nims
#                                      les passe à l'éditeur de liens (MinGW, Zig, clang, MSVC)
#
#   nim r outils/icones.nim macos <exécutable>    icône du fichier dans le Finder (macOS)
#   nim r outils/icones.nim linux <exécutable>    raccourci du menu des applications (Linux)
#
# Les objets COFF sont écrits ici, en Nim (équivalent de windres / cvtres) : aucun outil
# Windows n'est nécessaire, y compris en compilation croisée depuis macOS ou Linux.

import std/[os, osproc, strutils, unicode]
import ../src/ide/imagetools

const
  Root = currentSourcePath().parentDir.parentDir
  ResDir = Root / "src" / "ressources"
  Source = ResDir / "wdlexis.png"
  Exes = [("wdlexis", "wdlexis+.exe", "wdlexis+ — atelier Lexis+"),
          ("wdlexisrt", "wdlexisrt.exe", "wdlexis+ — runtime Lexis+"),
          ("wdlexisgen", "wdlexisgen.exe", "wdlexis+ — générateur d'applications")]
  Machines = [("amd64", 0x8664, 3),     # IMAGE_REL_AMD64_ADDR32NB
              ("arm64", 0xAA64, 2)]     # IMAGE_REL_ARM64_ADDR32NB
  RtIcon = 3
  RtGroupIcon = 14
  RtVersion = 16

# ------------------------------------------------------------------ octets

proc w16(s: var string, v: int) =
  s.add char(v and 0xFF)
  s.add char((v shr 8) and 0xFF)

proc w32(s: var string, v: int) =
  for i in 0 .. 3: s.add char((v shr (8 * i)) and 0xFF)

proc set16(s: var string, at, v: int) =
  s[at] = char(v and 0xFF)
  s[at + 1] = char((v shr 8) and 0xFF)

proc set32(s: var string, at, v: int) =
  for i in 0 .. 3: s[at + i] = char((v shr (8 * i)) and 0xFF)

proc pad(s: var string, n: int) =
  while s.len mod n != 0: s.add '\0'

proc utf16z(t: string): string =
  for r in t.runes:
    let c = int(r)
    if c < 0x10000: result.w16 c
    else:
      let v = c - 0x10000
      result.w16 0xD800 or (v shr 10)
      result.w16 0xDC00 or (v and 0x3FF)
  result.w16 0

proc wcharCount(t: string): int = utf16z(t).len div 2

# ------------------------------------------------------------------ VERSIONINFO

proc vNode(key: string, value: string, valueLen, typ: int, children: seq[string]): string =
  result.w16 0                               # wLength (plus bas)
  result.w16 valueLen
  result.w16 typ
  result.add utf16z(key)
  result.pad 4
  result.add value
  for c in children:
    result.pad 4
    result.add c
  result.set16(0, result.len)

proc versionInfo(version, fileName, description: string): string =
  var parts = version.split('.')
  while parts.len < 4: parts.add "0"
  var n: array[4, int]
  for i in 0 .. 3:
    try: n[i] = parseInt(parts[i]) except ValueError: n[i] = 0
  var fixed = ""
  fixed.w32 0xFEEF04BD
  fixed.w32 0x00010000
  fixed.w32 (n[0] shl 16) or n[1]
  fixed.w32 (n[2] shl 16) or n[3]
  fixed.w32 (n[0] shl 16) or n[1]
  fixed.w32 (n[2] shl 16) or n[3]
  fixed.w32 0x3F                             # FILEFLAGSMASK
  fixed.w32 0                                # FILEFLAGS
  fixed.w32 0x40004                          # VOS_NT_WINDOWS32
  fixed.w32 1                                # VFT_APP
  fixed.w32 0
  fixed.w32 0
  fixed.w32 0
  let ver = parts[0 .. 3].join(".")
  var strings: seq[string]
  for (k, v) in [("CompanyName", "jean-marc \"jihem\" quere"),
                 ("FileDescription", description),
                 ("FileVersion", ver),
                 ("InternalName", fileName.changeFileExt("")),
                 ("LegalCopyright", "CC BY-NC-SA 4.0 - jean-marc \"jihem\" quere 2026"),
                 ("OriginalFilename", fileName),
                 ("ProductName", "wdlexis+"),
                 ("ProductVersion", ver)]:
    strings.add vNode(k, utf16z(v), wcharCount(v), 1, @[])
  let table = vNode("040C04B0", "", 0, 1, strings)
  let sfi = vNode("StringFileInfo", "", 0, 1, @[table])
  var tr = ""
  tr.w16 0x040C
  tr.w16 1200
  let vfi = vNode("VarFileInfo", "", 0, 1, @[vNode("Translation", tr, 4, 0, @[])])
  vNode("VS_VERSION_INFO", fixed, 52, 0, @[sfi, vfi])

# ------------------------------------------------------------------ objet COFF

type Res = tuple[typ, id: int, data: string]

proc iconResources(pngs: seq[(int, string)]): seq[Res] =
  # RT_ICON (une image PNG par taille, Windows Vista et suivants) + RT_GROUP_ICON.
  var group = ""
  group.w16 0
  group.w16 1
  group.w16 pngs.len
  for i, (n, png) in pngs:
    result.add (RtIcon, i + 1, png)
    group.add char(if n >= 256: 0 else: n)
    group.add char(if n >= 256: 0 else: n)
    group.add char(0)
    group.add char(0)
    group.w16 1
    group.w16 32
    group.w32 png.len
    group.w16 i + 1
  result.add (RtGroupIcon, 1, group)

proc coffResources(machine, relocType: int, res: seq[Res], lang = 0): string =
  # Section .rsrc : arborescence type / identifiant / langue, entrées de données
  # (adresses relatives, relogées par rapport au symbole de section), puis données.
  var types: seq[int]
  for r in res:
    if r.typ notin types: types.add r.typ
  for i in 0 ..< types.len:                  # tri croissant (exigé par Windows)
    for j in i + 1 ..< types.len:
      if types[j] < types[i]: swap(types[i], types[j])
  var byType: seq[seq[int]]                  # indices dans res, par type, ids croissants
  for t in types:
    var l: seq[int]
    for i, r in res:
      if r.typ == t: l.add i
    for a in 0 ..< l.len:
      for b in a + 1 ..< l.len:
        if res[l[b]].id < res[l[a]].id: swap(l[a], l[b])
    byType.add l
  let rootSize = 16 + 8 * types.len
  var typeDirOff: seq[int]
  var off = rootSize
  for l in byType:
    typeDirOff.add off
    off += 16 + 8 * l.len
  var langDirOff = newSeq[int](res.len)
  for l in byType:
    for i in l:
      langDirOff[i] = off
      off += 16 + 8
  var entryOff = newSeq[int](res.len)
  for l in byType:
    for i in l:
      entryOff[i] = off
      off += 16
  var dataOff = newSeq[int](res.len)
  for l in byType:
    for i in l:
      while off mod 8 != 0: inc off
      dataOff[i] = off
      off += res[i].data.len
  var sec = ""
  proc dirHeader(s: var string, ids: int) =
    s.w32 0                                  # Characteristics
    s.w32 0                                  # TimeDateStamp
    s.w16 0
    s.w16 0
    s.w16 0                                  # entrées nommées
    s.w16 ids                                # entrées numériques
  sec.dirHeader(types.len)
  for k, t in types:
    sec.w32 t
    sec.w32 typeDirOff[k] or int(0x80000000'u32)
  for l in byType:
    sec.dirHeader(l.len)
    for i in l:
      sec.w32 res[i].id
      sec.w32 langDirOff[i] or int(0x80000000'u32)
  for l in byType:
    for i in l:
      sec.dirHeader(1)
      sec.w32 lang
      sec.w32 entryOff[i]
  var relocs: seq[int]
  for l in byType:
    for i in l:
      relocs.add sec.len
      sec.w32 dataOff[i]                     # adresse relative (+ RVA de la section)
      sec.w32 res[i].data.len
      sec.w32 0                              # page de code
      sec.w32 0
  for l in byType:
    for i in l:
      sec.pad 8
      assert sec.len == dataOff[i]
      sec.add res[i].data
  sec.pad 4
  # fichier : en-tête, en-tête de section, données, relogements, symboles, chaînes
  const hdr = 20
  const shdr = 40
  let rawPtr = hdr + shdr
  let relPtr = rawPtr + sec.len
  let symPtr = relPtr + 10 * relocs.len
  result.w16 machine
  result.w16 1                               # sections
  result.w32 0                               # date
  result.w32 symPtr
  result.w32 2                               # symboles (symbole de section + auxiliaire)
  result.w16 0                               # pas d'en-tête optionnel
  result.w16 0
  result.add ".rsrc\0\0\0"
  result.w32 0                               # VirtualSize
  result.w32 0                               # VirtualAddress
  result.w32 sec.len
  result.w32 rawPtr
  result.w32 relPtr
  result.w32 0
  result.w16 relocs.len
  result.w16 0
  result.w32 0x40000040                      # données initialisées, lecture
  result.add sec
  for r in relocs:
    result.w32 r
    result.w32 0                             # symbole 0 : .rsrc
    result.w16 relocType
  result.add ".rsrc\0\0\0"
  result.w32 0                               # valeur
  result.w16 1                               # section 1
  result.w16 0                               # type
  result.add char(3)                         # IMAGE_SYM_CLASS_STATIC
  result.add char(1)                         # un symbole auxiliaire
  result.w32 sec.len                         # auxiliaire : définition de section
  result.w16 relocs.len
  result.w16 0
  result.w32 0
  result.w16 0
  result.add char(0)
  result.add "\0\0\0"
  result.w32 4                               # table des chaînes vide

# ------------------------------------------------------------------ commandes

proc nimbleVersion(): string =
  for line in readFile(Root / "wdlexis.nimble").splitLines:
    let l = line.strip
    if l.startsWith("version"):
      let p = l.find('"')
      if p >= 0: return l[p + 1 ..< l.rfind('"')]
  "1.0.0"

proc generate() =
  if not fileExists(Source): quit("image source introuvable : " & Source, 1)
  let img0 = loadImage(Source)
  let img = cropImage(img0, centeredCrop(img0.w, img0.h)).resized(1024)
  writeFile(ResDir / "wdlexis-256.png", encodePng(img.resized(256)))
  var pngs: seq[(int, string)]
  for n in IcoSizes: pngs.add (n, encodePng(img.resized(n)))
  let version = nimbleVersion()
  createDir(ResDir / "windows")
  for (exe, fileName, description) in Exes:
    var res = iconResources(pngs)
    res.add (RtVersion, 1, versionInfo(version, fileName, description))
    for (cpu, machine, reloc) in Machines:
      writeFile(ResDir / "windows" / (exe & "-" & cpu & ".o"), coffResources(machine, reloc, res))
  echo "icônes : ", ResDir, " (version ", version, ")"

proc escapeJson(s: string): string =
  result = "\""
  for c in s:
    case c
    of '"': result.add "\\\""
    of '\\': result.add "\\\\"
    else: result.add c
  result.add "\""

proc macosIcon(exe: string) =
  # Icône personnalisée du fichier (Finder), via NSWorkspace ; sans effet ailleurs.
  let png = ResDir / "wdlexis.png"
  let script = "ObjC.import('AppKit');" &
    "var i = $.NSImage.alloc.initWithContentsOfFile(" & escapeJson(png) & ");" &
    "$.NSWorkspace.sharedWorkspace.setIconForFileOptions(i, " & escapeJson(absolutePath(exe)) & ", 0) ? 'ok' : 'échec'"
  let (o, code) = execCmdEx(quoteShellCommand(["osascript", "-l", "JavaScript", "-e", script]))
  if code != 0 or "ok" notin o: echo "icône Finder non appliquée à ", exe, " : ", o.strip
  else: echo "icône Finder : ", exe

proc linuxShortcut(exe: string) =
  let path = absolutePath(exe)
  let name = extractFilename(exe)
  let dir = getHomeDir() / ".local" / "share" / "applications"
  createDir(dir)
  let desktop = dir / (name.replace("+", "plus") & ".desktop")
  writeFile(desktop, "[Desktop Entry]\nType=Application\nName=" & name & "\n" &
    "Comment=" & (if name.startsWith("wdlexisrt"): "Runtime Lexis+" else: "Atelier Lexis+") & "\n" &
    "Exec=\"" & path & "\"\nPath=" & path.parentDir & "\nIcon=" & ResDir / "wdlexis.png" & "\n" &
    "Terminal=false\nCategories=Development;IDE;\nStartupWMClass=" & name & "\n")
  echo "raccourci : ", desktop

when isMainModule:
  let args = commandLineParams()
  if args.len == 0: generate()
  elif args.len == 2 and args[0] == "macos": macosIcon(args[1])
  elif args.len == 2 and args[0] == "linux": linuxShortcut(args[1])
  else: quit("usage : icones [macos|linux <exécutable>]", 1)
