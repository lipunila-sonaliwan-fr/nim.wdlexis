# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - archives des distributions : .zip (Windows) et .tar.gz (Linux, macOS)
#
#   writeZip(archive, dossier, racine, exécutables)
#   writeTarGz(archive, dossier, racine, exécutables)
#
# `racine` est le nom du dossier de tête dans l'archive ; `exécutables` les
# chemins relatifs (séparateur « / ») à marquer exécutables (0755), ce que le
# système de fichiers d'un hôte Windows ne sait pas indiquer.

import std/[os, strutils, times, algorithm, sets]
import imagetools

const StoreAbove = 256 * 1024 * 1024    # au-delà : fichier stocké sans compression.

type ArchEntry = object
  rel: string
  path: string
  isDir: bool
  mode: int
  mtime: Time

proc collect(srcDir: string, execs: HashSet[string]): seq[ArchEntry] =
  var dirs, files: seq[string]
  for p in walkDirRec(srcDir, yieldFilter = {pcFile, pcDir, pcLinkToFile}, relative = true):
    let rel = p.replace('\\', '/')
    if dirExists(srcDir / p): dirs.add rel else: files.add rel
  dirs.sort()
  files.sort()
  for d in dirs:
    result.add ArchEntry(rel: d, path: srcDir / d, isDir: true, mode: 0o755,
                         mtime: getLastModificationTime(srcDir / d))
  for f in files:
    var mode = 0o644
    when not defined(windows):
      if fpUserExec in getFilePermissions(srcDir / f): mode = 0o755
    if f in execs: mode = 0o755
    result.add ArchEntry(rel: f, path: srcDir / f, isDir: false, mode: mode,
                         mtime: getLastModificationTime(srcDir / f))

proc le16(s: var string, v: int) =
  s.add char(v and 0xFF)
  s.add char((v shr 8) and 0xFF)

proc le32(s: var string, v: int64) =
  for i in 0 .. 3: s.add char(int((v shr (8 * i)) and 0xFF))

proc dosTime(t: Time): (int, int) =
  let d = t.local
  let y = max(1980, d.year)
  ((d.hour shl 11) or (d.minute shl 5) or (d.second div 2),
   ((y - 1980) shl 9) or (ord(d.month) shl 5) or d.monthday)

proc writeZip*(archive, srcDir, top: string, execs: HashSet[string] = initHashSet[string]()) =
  ## Archive zip (noms UTF-8, attributs Unix pour les exécutables).
  let entries = collect(srcDir, execs)
  var f = open(archive, fmWrite)
  defer: f.close()
  var central = ""
  var offset = 0'i64
  var count = 0
  proc emit(s: string) =
    f.write s
    offset += s.len
  for e in @[ArchEntry(rel: "", path: srcDir, isDir: true, mode: 0o755,
                       mtime: getLastModificationTime(srcDir))] & entries:
    let name = (if e.rel.len > 0: top & "/" & e.rel else: top) & (if e.isDir: "/" else: "")
    var data, packed: string
    var crc = 0'u32
    var meth = 0
    if not e.isDir:
      data = readFile(e.path)
      if data.len.int64 >= 0xFFFFFFFF'i64:
        raise newException(IOError, "fichier trop volumineux pour une archive zip : " & e.rel)
      crc = crc32(data)
      packed = data
      if data.len > 0 and data.len < StoreAbove:
        let z = deflateRaw(data)
        if z.len < data.len:
          packed = z
          meth = 8
    let (tm, dt) = dosTime(e.mtime)
    let here = offset
    var h = "PK\x03\x04"
    h.le16 20
    h.le16 0x0800                      # noms en UTF-8
    h.le16 meth
    h.le16 tm
    h.le16 dt
    h.le32 int64(crc)
    h.le32 packed.len
    h.le32 data.len
    h.le16 name.len
    h.le16 0
    h.add name
    emit h
    if packed.len > 0: emit packed
    var c = "PK\x01\x02"
    c.le16 (3 shl 8) or 20             # créé par : Unix, version 2.0
    c.le16 20
    c.le16 0x0800
    c.le16 meth
    c.le16 tm
    c.le16 dt
    c.le32 int64(crc)
    c.le32 packed.len
    c.le32 data.len
    c.le16 name.len
    c.le16 0
    c.le16 0
    c.le16 0
    c.le16 0
    let unixMode = (if e.isDir: 0o040000 else: 0o100000) or e.mode
    c.le32 (int64(unixMode) shl 16) or (if e.isDir: 0x10'i64 else: 0'i64)
    c.le32 here
    c.add name
    central.add c
    inc count
  let cdStart = offset
  emit central
  var t = "PK\x05\x06"
  t.le16 0
  t.le16 0
  t.le16 count
  t.le16 count
  t.le32 central.len
  t.le32 cdStart
  t.le16 0
  emit t

proc octal(v: int64, width: int): string =
  result = toOct(v, width - 1) & "\0"

proc tarHeader(name: string, size: int64, mode: int, mtime: int64, typ: char): string =
  var nm = name
  var prefix = ""
  if nm.len > 100:
    # ustar : préfixe (155) + nom (100), coupés sur un « / ».
    var cut = nm.len - 101
    while cut < nm.len and nm[cut] != '/': inc cut
    if cut >= nm.len or cut > 155: raise newException(IOError, "chemin trop long pour l'archive : " & name)
    prefix = nm[0 ..< cut]
    nm = nm[cut + 1 .. ^1]
  var h = newString(512)
  proc put(s: string, at: int) =
    for i, c in s: h[at + i] = c
  put(nm, 0)
  put(octal(mode, 8), 100)
  put(octal(0, 8), 108)
  put(octal(0, 8), 116)
  put(octal(size, 12), 124)
  put(octal(mtime, 12), 136)
  put("        ", 148)
  h[156] = typ
  put("ustar\x0000", 257)
  put("wdlexis", 265)
  put("wdlexis", 297)
  put(prefix, 345)
  var sum = 0
  for c in h: sum += ord(c)
  put(toOct(sum, 6) & "\0 ", 148)
  h

proc writeTarGz*(archive, srcDir, top: string, execs: HashSet[string] = initHashSet[string]()) =
  ## Archive tar (ustar) compressée en gzip.
  let entries = collect(srcDir, execs)
  var tar = tarHeader(top & "/", 0, 0o755, getLastModificationTime(srcDir).toUnix, '5')
  for e in entries:
    let name = top & "/" & e.rel & (if e.isDir: "/" else: "")
    if e.isDir:
      tar.add tarHeader(name, 0, e.mode, e.mtime.toUnix, '5')
    else:
      let data = readFile(e.path)
      tar.add tarHeader(name, data.len, e.mode, e.mtime.toUnix, '0')
      tar.add data
      if data.len mod 512 != 0: tar.add repeat('\0', 512 - data.len mod 512)
  tar.add repeat('\0', 1024)
  var gz = "\x1f\x8b\x08\x00"
  gz.le32 getTime().toUnix
  gz.add "\x00\x03"                    # Unix
  gz.add deflateRaw(tar)
  gz.le32 int64(crc32(tar))
  gz.le32 int64(tar.len and 0xFFFFFFFF)
  writeFile(archive, gz)
