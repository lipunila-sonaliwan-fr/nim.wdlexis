# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet archive : fichiers .zip, .tar, .tar.gz et .gz, en Nim pur
#
#   a = archive.ouvrir("livraison.zip")              && zip, tar, tar.gz ou gz
#   pour chaque e dans a:liste()
#     ? e.nom, e.taille, e.compresse
#   suivant
#   ? a:lire("LISEZMOI.md")
#   a:extraire("sortie", {motif = "*.prg"})
#   a:fermer()
#
#   w = archive.creer("sauvegarde.zip", {niveau = 9})
#   w:ajouter("exemples/bonjour")                   && dossier (récursif) ou fichier
#   w:ajoutertexte("version.txt", "1.0")
#   w:fermer()
#
#   z = archive.gzip(texte)   texte = archive.gunzip(z)
#
# Compression deflate (codes de Huffman dynamiques), Zip64, noms UTF-8, droits
# Unix, protection contre les chemins dangereux (« .. », chemins absolus) à
# l'extraction. Les entrées chiffrées ne sont pas prises en charge.

import std/[os, strutils, times, sets, algorithm]
import ../lexis/api
import compression

type
  LArchive* = ref object of LUser
    kind: ArchiveKind
    path: string
    zip: ZipReader
    tar: string
    tarEntries: seq[TarEntry]
    gzData: string
    gzName: string
    closed: bool

  LArchiveur* = ref object of LUser
    kind: ArchiveKind
    path: string
    zip: ZipWriter
    tar: string
    level: int
    names: HashSet[string]
    count: int
    closed: bool

  Info = object
    name: string
    isDir, isLink: bool
    size, csize, mtime: int64
    mode: int
    link: string

var archMethods {.threadvar.}: LTable
var writerMethods {.threadvar.}: LTable

proc protect(body: proc (): seq[Value]): seq[Value] =
  try: body()
  except CompressionError as e: rtError(e.msg)
  except IOError as e: rtError(e.msg)
  except OSError as e: rtError(e.msg)

template guard(body: untyped): untyped =
  protect(proc (): seq[Value] = body)

proc kindFromName(path, explicit: string): ArchiveKind =
  case explicit.toLowerAscii
  of "zip": return akZip
  of "tar": return akTar
  of "targz", "tar.gz", "tgz": return akTarGz
  of "gzip", "gz": return akGzip
  of "": discard
  else: rtError("format d'archive inconnu : " & explicit & " (zip, tar, targz, gzip)")
  let low = path.toLowerAscii
  if low.endsWith(".tar.gz") or low.endsWith(".tgz"): akTarGz
  elif low.endsWith(".tar"): akTar
  elif low.endsWith(".gz"): akGzip
  else: akZip

proc entries(a: LArchive): seq[Info] =
  case a.kind
  of akZip:
    for e in a.zip.entries:
      result.add Info(name: e.name, isDir: e.isDir, size: e.usize, csize: e.csize,
                      mtime: e.mtime, mode: e.mode)
  of akTar, akTarGz:
    for e in a.tarEntries:
      result.add Info(name: e.name, isDir: e.isDir, isLink: e.isLink, size: e.size, csize: e.size,
                      mtime: e.mtime, mode: e.mode, link: e.link)
  of akGzip:
    var n = a.gzName
    if n.len == 0:
      n = extractFilename(a.path)
      if n.toLowerAscii.endsWith(".gz"): n = n[0 ..< n.len - 3]
    result.add Info(name: n, size: a.gzData.len, csize: getFileSize(a.path),
                    mtime: getLastModificationTime(a.path).toUnix)
  of akNone: discard

proc infoValue(e: Info): Value =
  let t = newLTable()
  t.set "nom", strV(e.name.strip(leading = false, chars = {'/'}))
  t.set "chemin", strV(e.name)
  t.set "taille", intV(e.size)
  t.set "compresse", intV(e.csize)
  t.set "date", intV(e.mtime)
  t.set "dossier", boolV(e.isDir)
  t.set "mode", intV(e.mode)
  if e.isLink:
    t.set "lien", strV(e.link)
  tableV(t)

proc readEntry(a: LArchive, name: string): (bool, string) =
  let n = name.replace('\\', '/')
  case a.kind
  of akZip:
    var i = a.zip.find(n)
    if i < 0: i = a.zip.find(n & "/")
    if i < 0: return (false, "")
    (true, a.zip.read(a.zip.entries[i]))
  of akTar, akTarGz:
    for e in a.tarEntries:
      if e.name == n or e.name == n & "/": return (true, tarRead(a.tar, e))
    for e in a.tarEntries:
      if e.name.toLowerAscii == n.toLowerAscii: return (true, tarRead(a.tar, e))
    (false, "")
  of akGzip:
    if a.entries()[0].name == n or n.len == 0: (true, a.gzData) else: (false, "")
  of akNone: (false, "")

proc checkArch(L: Interp, a: seq[Value], fname: string): LArchive =
  result = checkUser[LArchive](L, a, 1, fname, "archive")
  if result.closed: rtError("archive fermée")

proc checkWriter(L: Interp, a: seq[Value], fname: string): LArchiveur =
  result = checkUser[LArchiveur](L, a, 1, fname, "archiveur")
  if result.closed: rtError("archive déjà fermée")

proc closeArch(a: LArchive) =
  if not a.closed:
    a.closed = true
    if a.kind == akZip and not a.zip.isNil: a.zip.close()
    a.tar = ""
    a.gzData = ""

proc openArchive(L: Interp, path: string): LArchive =
  if not fileExists(path): rtError("archive introuvable : " & path)
  let k = detectKind(path)
  result = LArchive(kind: k, path: path)
  case k
  of akZip: result.zip = openZip(path)
  of akTar:
    result.tar = readFile(path)
    result.tarEntries = tarList(result.tar)
  of akTarGz:
    result.tar = gzipDecompress(readFile(path))
    result.tarEntries = tarList(result.tar)
  of akGzip:
    result.gzData = gzipDecompress(readFile(path), result.gzName)
  of akNone: rtError("format d'archive non reconnu : " & path & " (zip, tar, tar.gz, gz)")

#
# extraction
#

type ExtractOpts = object
  patterns: seq[string]
  names: HashSet[string]
  overwrite: bool
  flatten: bool

proc parseExtractOpts(L: Interp, v: Value): ExtractOpts =
  result.overwrite = true
  result.names = initHashSet[string]()
  case v.kind
  of vkStr: result.patterns.add v.s
  of vkTable:
    let t = v.t
    if t.rawLen > 0 and t.field("motif").kind == vkNil:
      for i in 1 .. t.rawLen:
        let x = t.rawGet(i)
        if x.kind == vkStr: result.names.incl x.s.replace('\\', '/')
    else:
      let m = t.field("motif")
      if m.kind == vkStr: result.patterns.add m.s
      elif m.kind == vkTable:
        for i in 1 .. m.t.rawLen: result.patterns.add L.tostr(m.t.rawGet(i))
      result.overwrite = optField(t, "ecraser", true)
      result.flatten = optField(t, "aplatir", false)
  else: discard

proc wanted(o: ExtractOpts, name: string): bool =
  let n = name.strip(leading = false, chars = {'/'})
  if o.names.len > 0 and n notin o.names and name notin o.names: return false
  if o.patterns.len == 0: return true
  for p in o.patterns:
    if globMatch(p, n): return true
  false

proc extractTo(L: Interp, a: LArchive, dest: string, o: ExtractOpts): seq[string] =
  let base = if dest.len == 0: getCurrentDir() else: dest
  createDir(base)
  var dirTimes: seq[(string, int64)]
  for e in a.entries():
    if not o.wanted(e.name): continue
    let rel = safeRelative(e.name).strip(leading = false, chars = {'/'})
    if rel.len == 0: continue
    var target = if o.flatten: base / extractFilename(rel) else: base / rel
    if e.isDir:
      if not o.flatten:
        createDir(target)
        dirTimes.add (target, e.mtime)
      continue
    if e.isLink: continue                 # liens symboliques ignorés (sécurité)
    if not o.overwrite and fileExists(target): continue
    let (ok, data) = a.readEntry(e.name)
    if not ok: continue
    createDir(parentDir(target))
    writeFile(target, data)
    when not defined(windows):
      if e.mode != 0:
        try:
          var perms: set[FilePermission]
          let m = e.mode
          if (m and 0o400) != 0: perms.incl fpUserRead
          if (m and 0o200) != 0: perms.incl fpUserWrite
          if (m and 0o100) != 0: perms.incl fpUserExec
          if (m and 0o040) != 0: perms.incl fpGroupRead
          if (m and 0o020) != 0: perms.incl fpGroupWrite
          if (m and 0o010) != 0: perms.incl fpGroupExec
          if (m and 0o004) != 0: perms.incl fpOthersRead
          if (m and 0o002) != 0: perms.incl fpOthersWrite
          if (m and 0o001) != 0: perms.incl fpOthersExec
          if fpUserRead in perms: setFilePermissions(target, perms)
        except OSError: discard
    if e.mtime > 0:
      try: setLastModificationTime(target, fromUnix(e.mtime))
      except OSError: discard
    result.add target
  for (d, t) in dirTimes:
    if t > 0:
      try: setLastModificationTime(d, fromUnix(t))
      except OSError: discard

#
# écriture
#

proc fileMode(path: string): int =
  when defined(windows): 0
  else:
    try:
      let p = getFilePermissions(path)
      if fpUserRead in p: result = result or 0o400
      if fpUserWrite in p: result = result or 0o200
      if fpUserExec in p: result = result or 0o100
      if fpGroupRead in p: result = result or 0o040
      if fpGroupWrite in p: result = result or 0o020
      if fpGroupExec in p: result = result or 0o010
      if fpOthersRead in p: result = result or 0o004
      if fpOthersWrite in p: result = result or 0o002
      if fpOthersExec in p: result = result or 0o001
    except OSError: result = 0

proc writeOne(w: LArchiveur, name, data: string, mtime: int64, mode: int, isDir: bool) =
  var n = name.replace('\\', '/')
  while n.startsWith("./"): n = n[2 .. ^1]
  while n.startsWith("/"): n = n[1 .. ^1]
  if n.len == 0: return
  let key = n.strip(leading = false, chars = {'/'})
  if key in w.names: rtError("entrée déjà présente dans l'archive : " & key)
  w.names.incl key
  case w.kind
  of akZip: w.zip.addEntry(n, data, mtime, mode, isDir)
  of akTar, akTarGz: w.tar.tarAdd(n, data, mtime, mode, isDir)
  of akGzip:
    if isDir: rtError("un fichier .gz ne contient qu'un fichier")
    if w.count > 0: rtError("un fichier .gz ne contient qu'un fichier (utilisez zip ou targz)")
    w.tar = data
    w.names.incl "\0" & n
  of akNone: discard
  inc w.count

proc addPath(L: Interp, w: LArchiveur, src: string, inName: string, patterns: seq[string]): int =
  ## Ajoute un fichier, ou un dossier et son contenu ; renvoie le nombre d'entrées.
  if fileExists(src):
    let nm = if inName.len > 0: inName else: extractFilename(src)
    w.writeOne(nm, readFile(src), getLastModificationTime(src).toUnix, fileMode(src), false)
    return 1
  if not dirExists(src): rtError("fichier ou dossier introuvable : " & src)
  let top = if inName.len > 0: inName.strip(chars = {'/', '\\'})
            else: extractFilename(src.strip(leading = false, chars = {'/', '\\'}))
  var items: seq[string]
  for p in walkDirRec(src, yieldFilter = {pcFile, pcDir, pcLinkToFile}, relative = true):
    items.add p
  items.sort()
  if top.len > 0 and patterns.len == 0:
    w.writeOne(top & "/", "", getLastModificationTime(src).toUnix, fileMode(src), true)
    inc result
  for p in items:
    let rel = p.replace('\\', '/')
    let full = src / p
    let nm = if top.len > 0: top & "/" & rel else: rel
    if dirExists(full):
      if patterns.len > 0: continue
      w.writeOne(nm & "/", "", getLastModificationTime(full).toUnix, fileMode(full), true)
    else:
      if patterns.len > 0:
        var ok = false
        for pt in patterns:
          if globMatch(pt, rel): ok = true
        if not ok: continue
      w.writeOne(nm, readFile(full), getLastModificationTime(full).toUnix, fileMode(full), false)
    inc result

proc finish(w: LArchiveur): int64 =
  if w.closed: return 0
  w.closed = true
  case w.kind
  of akZip:
    w.zip.close()
  of akTar:
    w.tar.tarFinish()
    writeFile(w.path, w.tar)
  of akTarGz:
    w.tar.tarFinish()
    var inner = extractFilename(w.path)
    if inner.toLowerAscii.endsWith(".tgz"): inner = inner[0 ..< inner.len - 4] & ".tar"
    elif inner.toLowerAscii.endsWith(".gz"): inner = inner[0 ..< inner.len - 3]
    writeFile(w.path, gzipCompress(w.tar, w.level, inner, getTime().toUnix))
  of akGzip:
    var nm = ""
    for n in w.names:
      if n.startsWith("\0"): nm = n[1 .. ^1]
    writeFile(w.path, gzipCompress(w.tar, w.level, extractFilename(nm), getTime().toUnix))
  of akNone: discard
  w.tar = ""
  getFileSize(w.path)

proc newWriter(L: Interp, path: string, opts: LTable): LArchiveur =
  let k = kindFromName(path, optField(opts, "format", ""))
  result = LArchiveur(kind: k, path: path, level: max(0, min(9, optField(opts, "niveau", 6))),
                      names: initHashSet[string]())
  let dir = parentDir(path)
  if dir.len > 0: createDir(dir)
  if k == akZip:
    result.zip = createZip(path, result.level)
    result.zip.comment = optField(opts, "commentaire", "")
  let w = result
  L.closers.add proc () =
    try: discard w.finish()
    except CatchableError: discard

proc sourcesOf(L: Interp, v: Value): seq[string] =
  if v.kind == vkStr: return @[v.s]
  if v.kind == vkTable:
    for i in 1 .. v.t.rawLen: result.add L.tostr(v.t.rawGet(i))
    return
  rtError("archive : fichier, dossier ou liste de chemins attendu")

proc patternsOf(L: Interp, opts: LTable): seq[string] =
  let m = opts.field("motif")
  if m.kind == vkStr: result.add m.s
  elif m.kind == vkTable:
    for i in 1 .. m.t.rawLen: result.add L.tostr(m.t.rawGet(i))

#
# paquet
#

proc openArchivePkg(L: Interp): Value =
  archMethods = newLib()
  writerMethods = newLib()
  let am = archMethods
  am.fn "liste", proc (L: Interp, a: seq[Value]): seq[Value] =
    let ar = L.checkArch(a, "liste")
    let motif = L.optStr(a, 2, "liste", "")
    let t = newLTable()
    for e in ar.entries():
      if motif.len == 0 or globMatch(motif, e.name.strip(leading = false, chars = {'/'})):
        t.arr.add infoValue(e)
    @[tableV(t)]
  am.fn "noms", proc (L: Interp, a: seq[Value]): seq[Value] =
    let ar = L.checkArch(a, "noms")
    var s: seq[string]
    for e in ar.entries():
      if not e.isDir: s.add e.name
    @[toV(s)]
  am.fn "nombre", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(L.checkArch(a, "nombre").entries().len)]
  am.fn "existe", proc (L: Interp, a: seq[Value]): seq[Value] =
    let ar = L.checkArch(a, "existe")
    let n = L.checkStr(a, 2, "existe").replace('\\', '/').strip(leading = false, chars = {'/'})
    for e in ar.entries():
      if e.name.strip(leading = false, chars = {'/'}) == n: return @[boolV(true)]
    @[boolV(false)]
  am.fn "infos", proc (L: Interp, a: seq[Value]): seq[Value] =
    let ar = L.checkArch(a, "infos")
    let n = L.checkStr(a, 2, "infos").replace('\\', '/').strip(leading = false, chars = {'/'})
    for e in ar.entries():
      if e.name.strip(leading = false, chars = {'/'}) == n: return @[infoValue(e)]
    @[nilV]
  am.fn "lire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let ar = L.checkArch(a, "lire")
    let n = L.optStr(a, 2, "lire", "")
    guard:
      var res: seq[Value]
      L.blocking:
        let (ok, data) = ar.readEntry(n)
        res = @[if ok: strV(data) else: nilV]
      res
  am.fn "extraire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let ar = L.checkArch(a, "extraire")
    let dest = L.optStr(a, 2, "extraire", "")
    let o = parseExtractOpts(L, arg(a, 3))
    guard:
      var files: seq[string]
      L.blocking: files = extractTo(L, ar, dest, o)
      @[toV(files)]
  am.fn "extrairefichier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let ar = L.checkArch(a, "extrairefichier")
    let n = L.checkStr(a, 2, "extrairefichier")
    let dest = L.checkStr(a, 3, "extrairefichier")
    guard:
      let (ok, data) = ar.readEntry(n)
      if not ok: return @[boolV(false)]
      let d = parentDir(dest)
      if d.len > 0: createDir(d)
      writeFile(dest, data)
      @[boolV(true)]
  am.fn "format", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(kindName(L.checkArch(a, "format").kind))]
  am.fn "chemin", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(L.checkArch(a, "chemin").path)]
  am.fn "commentaire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let ar = L.checkArch(a, "commentaire")
    @[strV(if ar.kind == akZip: ar.zip.comment else: "")]
  am.fn "fermer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let ar = checkUser[LArchive](L, a, 1, "fermer", "archive")
    ar.closeArch()
    @[boolV(true)]

  let wm = writerMethods
  wm.fn "ajouter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let w = L.checkWriter(a, "ajouter")
    let srcs = L.sourcesOf(arg(a, 2))
    var inName = ""
    var pats: seq[string]
    let o = arg(a, 3)
    if o.kind == vkStr: inName = o.s
    elif o.kind == vkTable:
      inName = optField(o.t, "nom", "")
      pats = L.patternsOf(o.t)
    guard:
      var n = 0
      L.blocking:
        for s in srcs: n += L.addPath(w, s, (if srcs.len == 1: inName else: ""), pats)
      @[intV(n)]
  wm.fn "ajoutertexte", proc (L: Interp, a: seq[Value]): seq[Value] =
    let w = L.checkWriter(a, "ajoutertexte")
    let n = L.checkStr(a, 2, "ajoutertexte")
    let data = L.tostr(arg(a, 3))
    let t = if arg(a, 4).kind == vkNil: getTime().toUnix else: L.checkInt(a, 4, "ajoutertexte")
    guard:
      w.writeOne(n, data, t, 0, false)
      @[boolV(true)]
  wm.fn "ajouterdossier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let w = L.checkWriter(a, "ajouterdossier")
    let n = L.checkStr(a, 2, "ajouterdossier")
    guard:
      w.writeOne(n.strip(leading = false, chars = {'/'}) & "/", "", getTime().toUnix, 0, true)
      @[boolV(true)]
  wm.fn "nombre", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(checkUser[LArchiveur](L, a, 1, "nombre", "archiveur").count)]
  wm.fn "contient", proc (L: Interp, a: seq[Value]): seq[Value] =
    let w = checkUser[LArchiveur](L, a, 1, "contient", "archiveur")
    @[boolV(L.checkStr(a, 2, "contient").replace('\\', '/').strip(chars = {'/'}) in w.names)]
  wm.fn "fermer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let w = checkUser[LArchiveur](L, a, 1, "fermer", "archiveur")
    if w.closed: return @[nilV]
    guard:
      var sz = 0'i64
      L.blocking: sz = w.finish()
      @[intV(sz)]

  discard L.userMeta("archive", archMethods)
  discard L.userMeta("archiveur", writerMethods)

  let m = newLib()
  m.fn "ouvrir", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.checkStr(a, 1, "ouvrir")
    guard:
      var ar: LArchive
      L.blocking: ar = L.openArchive(path)
      let x = ar
      L.closers.add proc () = x.closeArch()
      @[L.wrap(ar, "archive", archMethods)]
  m.fn "creer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.checkStr(a, 1, "creer")
    let opts = if arg(a, 2).kind == vkTable: a[1].t else: nil
    guard:
      @[L.wrap(L.newWriter(path, opts), "archiveur", writerMethods)]
  m.fn "compresser", proc (L: Interp, a: seq[Value]): seq[Value] =
    let srcs = L.sourcesOf(arg(a, 1))
    let path = L.checkStr(a, 2, "compresser")
    let opts = if arg(a, 3).kind == vkTable: a[2].t else: nil
    let pats = L.patternsOf(opts)
    let racine = optField(opts, "racine", "")
    guard:
      let w = L.newWriter(path, opts)
      var n = 0
      L.blocking:
        for s in srcs:
          var nm = ""
          if racine.len > 0:
            nm = if srcs.len == 1 and dirExists(s): racine
                 else: racine & "/" & extractFilename(s.strip(leading = false, chars = {'/', '\\'}))
          n += L.addPath(w, s, nm, pats)
        discard w.finish()
      @[intV(n)]
  m.fn "extraire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.checkStr(a, 1, "extraire")
    let dest = L.optStr(a, 2, "extraire", "")
    let o = parseExtractOpts(L, arg(a, 3))
    guard:
      var files: seq[string]
      L.blocking:
        let ar = L.openArchive(path)
        try: files = extractTo(L, ar, dest, o)
        finally: ar.closeArch()
      @[toV(files)]
  m.fn "liste", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.checkStr(a, 1, "liste")
    guard:
      let ar = L.openArchive(path)
      let t = newLTable()
      try:
        for e in ar.entries(): t.arr.add infoValue(e)
      finally: ar.closeArch()
      @[tableV(t)]
  m.fn "format", proc (L: Interp, a: seq[Value]): seq[Value] =
    let k = detectKind(L.checkStr(a, 1, "format"))
    @[if k == akNone: nilV else: strV(kindName(k))]
  m.fn "gzip", proc (L: Interp, a: seq[Value]): seq[Value] =
    let data = L.tostr(arg(a, 1))
    let lvl = int(L.optInt(a, 2, "gzip", 6))
    var r = ""
    L.blocking: r = gzipCompress(data, lvl)
    @[strV(r)]
  m.fn "gunzip", proc (L: Interp, a: seq[Value]): seq[Value] =
    let data = L.checkStr(a, 1, "gunzip")
    guard:
      var r = ""
      L.blocking: r = gzipDecompress(data)
      @[strV(r)]
  m.fn "gzipfichier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let src = L.checkStr(a, 1, "gzipfichier")
    let dest = L.optStr(a, 2, "gzipfichier", src & ".gz")
    let lvl = int(L.optInt(a, 3, "gzipfichier", 6))
    guard:
      L.blocking:
        writeFile(dest, gzipCompress(readFile(src), lvl, extractFilename(src),
                                     getLastModificationTime(src).toUnix))
      @[strV(dest)]
  m.fn "gunzipfichier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let src = L.checkStr(a, 1, "gunzipfichier")
    var dest = L.optStr(a, 2, "gunzipfichier", "")
    guard:
      L.blocking:
        var nm = ""
        let data = gzipDecompress(readFile(src), nm)
        if dest.len == 0:
          dest = if src.toLowerAscii.endsWith(".gz"): src[0 ..< src.len - 3]
                 elif nm.len > 0: parentDir(src) / extractFilename(nm)
                 else: src & ".out"
        writeFile(dest, data)
      @[strV(dest)]
  m.fn "deflate", proc (L: Interp, a: seq[Value]): seq[Value] =
    let data = L.tostr(arg(a, 1))
    let lvl = int(L.optInt(a, 2, "deflate", 6))
    var r = ""
    L.blocking: r = deflate(data, lvl)
    @[strV(r)]
  m.fn "inflate", proc (L: Interp, a: seq[Value]): seq[Value] =
    let data = L.checkStr(a, 1, "inflate")
    guard: @[strV(inflate(data))]
  m.fn "zlib", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(zlibCompress2(L.tostr(arg(a, 1)), int(L.optInt(a, 2, "zlib", 6))))]
  m.fn "dezlib", proc (L: Interp, a: seq[Value]): seq[Value] =
    let data = L.checkStr(a, 1, "dezlib")
    guard: @[strV(zlibDecompress2(data))]
  m.fn "crc32", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(int64(crc32(L.tostr(arg(a, 1)))))]
  m.fn "adler32", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(int64(adler32(L.tostr(arg(a, 1)))))]
  m.fn "correspond", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[boolV(globMatch(L.checkStr(a, 1, "correspond"), L.checkStr(a, 2, "correspond")))]
  tableV(m)

registerPackage PackageDef(name: "archive", open: openArchivePkg,
  description: "Archives zip, tar, tar.gz et gzip (Nim pur)",
  docs: docs("archive", [
    "archive.ouvrir(chemin)", "Ouvre une archive .zip, .tar, .tar.gz (.tgz) ou .gz (format reconnu au contenu) ; renvoie une archive.",
    "archive.creer(chemin, [{format=, niveau=6, commentaire=}])", "Crée une archive à remplir (format d'après l'extension : .zip, .tar, .tar.gz, .tgz, .gz ; ou format = \"zip\", \"tar\", \"targz\", \"gzip\") ; niveau de compression 0 (stocké) à 9. Renvoie un archiveur, à fermer par w:fermer().",
    "archive.compresser(sources, chemin, [{format=, niveau=, racine=, motif=}])", "Crée une archive en une fois à partir d'un fichier, d'un dossier ou d'une liste ; racine : dossier de tête dans l'archive ; motif : \"*.prg\" ou liste de motifs (fichiers des dossiers retenus). Renvoie le nombre d'entrées.",
    "archive.extraire(chemin, [dossier], [motif | {noms} | {motif=, ecraser=vrai, aplatir=faux}])", "Extrait tout ou partie d'une archive (dossier courant par défaut) ; renvoie la liste des fichiers écrits. Les chemins dangereux (.., absolus) sont refusés, les liens ignorés.",
    "archive.liste(chemin)", "Contenu d'une archive : liste de {nom, chemin, taille, compresse, date, dossier, mode, lien}.",
    "archive.format(chemin)", "\"zip\", \"tar\", \"targz\", \"gzip\" ou nul.",
    "archive.gzip(donnees, [niveau])", "Compresse des données au format gzip.",
    "archive.gunzip(donnees)", "Décompresse des données gzip (membres successifs acceptés).",
    "archive.gzipfichier(source, [destination], [niveau])", "Compresse un fichier (destination : source.gz) ; renvoie la destination.",
    "archive.gunzipfichier(source, [destination])", "Décompresse un fichier .gz ; renvoie la destination.",
    "archive.deflate(donnees, [niveau])", "Flux deflate brut (RFC 1951).",
    "archive.inflate(donnees)", "Décompresse un flux deflate brut.",
    "archive.zlib(donnees, [niveau])", "Flux zlib (RFC 1950).",
    "archive.dezlib(donnees)", "Décompresse un flux zlib.",
    "archive.crc32(donnees)", "Somme CRC-32 (entier).",
    "archive.adler32(donnees)", "Somme Adler-32 (entier).",
    "archive.correspond(motif, nom)", "Vrai si le nom correspond au motif (* et ?, sans distinction de casse ; un motif sans / s'applique aussi au seul nom du fichier).",
    "a:liste([motif])", "Entrées : liste de {nom, chemin, taille, compresse, date (secondes Unix), dossier, mode, lien}.",
    "a:noms()", "Noms des fichiers (sans les dossiers).",
    "a:nombre()", "Nombre d'entrées.",
    "a:existe(nom)", "Vrai si l'entrée existe.",
    "a:infos(nom)", "Fiche d'une entrée ou nul.",
    "a:lire([nom])", "Contenu d'une entrée (texte ou octets), nul si elle n'existe pas ; sans nom pour un .gz.",
    "a:extraire([dossier], [motif | {noms} | {motif=, ecraser=, aplatir=}])", "Extrait tout ou partie ; renvoie la liste des fichiers écrits.",
    "a:extrairefichier(nom, chemin)", "Extrait une entrée vers un fichier ; faux si elle n'existe pas.",
    "a:format()", "\"zip\", \"tar\", \"targz\" ou \"gzip\".",
    "a:chemin()", "Chemin de l'archive.",
    "a:commentaire()", "Commentaire d'une archive zip.",
    "a:fermer()", "Ferme l'archive (automatique à la fin du programme).",
    "w:ajouter(source | {sources}, [nom_dans_archive | {nom=, motif=}])", "Ajoute un fichier, ou un dossier et son contenu ; renvoie le nombre d'entrées ajoutées.",
    "w:ajoutertexte(nom, contenu, [date])", "Ajoute une entrée à partir d'un texte ou d'octets.",
    "w:ajouterdossier(nom)", "Ajoute un dossier vide.",
    "w:nombre()", "Nombre d'entrées ajoutées.",
    "w:contient(nom)", "Vrai si l'entrée a déjà été ajoutée.",
    "w:fermer()", "Écrit l'archive et la ferme ; renvoie sa taille en octets (fait aussi à la fin du programme)."]))
