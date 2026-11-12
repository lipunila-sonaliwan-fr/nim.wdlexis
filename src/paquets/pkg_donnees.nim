# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquets de données
#
#   fichier   fichiers et dossiers (texte et binaire)
#   binaire   données binaires : coder / decoder / taille, hexadécimal
#   csv       lecture / écriture CSV (RFC 4180)
#   json      encodage / décodage JSON (en plus de json() et dejson())

import std/[os, strutils, json, times, parsecsv, streams, tables, math, algorithm]
from std/unicode import toUpper
import ../lexis/[api, fonctions]

#
# fichier
#

proc readText(path: string): seq[Value] =
  try: @[strV(readFile(path))]
  except IOError, OSError: fail(path & " : lecture impossible")

proc writeText(path, data: string, append: bool): seq[Value] =
  try:
    if append:
      var f: File
      if not open(f, path, fmAppend): return fail(path & " : écriture impossible")
      try: f.write(data)
      finally: f.close()
    else:
      writeFile(path, data)
    @[boolV(true)]
  except IOError, OSError:
    fail(path & " : écriture impossible")

proc listDir(dir: string, recursive: bool): Value =
  let t = newLTable()
  var names: seq[string]
  if recursive:
    for f in walkDirRec(dir, relative = true): names.add f.replace('\\', '/')
  else:
    for k, p in walkDir(dir, relative = true):
      names.add(if k in {pcDir, pcLinkToDir}: p & "/" else: p)
  names.sort()
  for n in names: t.arr.add strV(n)
  tableV(t)

proc statTable(path: string): Value =
  if not (fileExists(path) or dirExists(path)): return nilV
  let info = getFileInfo(path)
  record({"taille": intV(info.size),
          "genre": strV(if info.kind in {pcDir, pcLinkToDir}: "dossier" else: "fichier"),
          "modifie": intV(info.lastWriteTime.toUnix),
          "cree": intV(info.creationTime.toUnix)})

# Lecture par blocs (fichiers de plusieurs dizaines de gigaoctets) : on ne charge
# jamais le fichier entier ; les positions sont des octets à partir de 0.

const ScanChunk = 4 * 1024 * 1024

proc fileSizeOf(path: string): int64 =
  try: getFileSize(path) except OSError: -1

proc readRange(f: File, pos: int64, n: int): string =
  result = newString(max(0, n))
  if n <= 0: return
  f.setFilePos(pos)
  let got = f.readBuffer(result[0].addr, n)
  result.setLen(got)

proc utf8Back(s: string, i: int): int =
  ## Recule `i` jusqu'au début d'un caractère UTF-8 (au plus 3 octets).
  result = i
  var k = 0
  while result > 0 and result < s.len and (ord(s[result]) and 0xC0) == 0x80 and k < 3:
    dec result
    inc k

proc cleanUtf8(s: string, cut: int, cuts: var int): string =
  ## Remplace les octets invalides par U+FFFD et NUL par « · » ; coupe les lignes plus
  ## longues que `cut` octets (0 : jamais) en insérant des retours à la ligne.
  result = newStringOfCap(s.len + s.len div 64)
  var i = 0
  var lineLen = 0
  let n = s.len
  while i < n:
    let c = ord(s[i])
    var l = 0
    if c < 0x80: l = 1
    elif (c and 0xE0) == 0xC0 and c >= 0xC2: l = 2
    elif (c and 0xF0) == 0xE0: l = 3
    elif (c and 0xF8) == 0xF0 and c <= 0xF4: l = 4
    var ok = l > 0 and i + l <= n
    if ok:
      for k in 1 ..< l:
        if (ord(s[i + k]) and 0xC0) != 0x80:
          ok = false
          break
    if cut > 0 and lineLen >= cut and c != 10:
      result.add '\n'
      inc cuts
      lineLen = 0
    if not ok:
      result.add "\xEF\xBF\xBD"
      inc i
      inc lineLen
      continue
    if c == 0:
      result.add "\xC2\xB7"            # NUL -> « · » (fichiers binaires, zones creuses)
    elif c == 10:
      result.add '\n'
      lineLen = -1
    else:
      for k in 0 ..< l: result.add s[i + k]
    i += l
    inc lineLen

proc readBlock(L: Interp, a: seq[Value]): seq[Value] =
  let path = L.checkStr(a, 1, "lirebloc")
  let size = fileSizeOf(path)
  if size < 0: return fail(path & " : lecture impossible")
  var pos = int64(L.checkNum(a, 2, "lirebloc"))
  let want = max(1, int(L.checkNum(a, 3, "lirebloc")))
  let o = if arg(a, 4).kind == vkTable: a[3].t else: nil
  let byLines = optField(o, "lignes", true)
  let asText = optField(o, "texte", true)
  let cut = optField(o, "coupe", 0)
  pos = clamp(pos, 0'i64, size)
  var f: File
  if not open(f, path, fmRead): return fail(path & " : lecture impossible")
  defer: f.close()
  var data: string
  var start = pos
  try:
    # un octet avant pour savoir si pos est en début de ligne
    let before = if pos > 0 and byLines: f.readRange(pos - 1, 1) else: ""
    data = f.readRange(pos, int(min(int64(want), size - pos)))
    var a0 = 0
    if byLines and before.len == 1 and before[0] != '\n':
      let k = data.find('\n')
      if k >= 0 and k + 1 < data.len: a0 = k + 1
      elif k < 0: a0 = utf8Back(data, 0)
    var z = data.len
    if pos + int64(data.len) < size:
      if byLines:
        let k = data.rfind('\n')
        if k >= a0: z = k + 1
        else: z = utf8Back(data, data.len - 1)
      else:
        z = utf8Back(data, data.len - 1)
    elif data.len > 0 and z < data.len: discard
    if a0 > 0 or z < data.len: data = data[a0 ..< max(a0, z)]
    start = pos + int64(a0)
  except IOError, OSError:
    return fail(path & " : lecture impossible")
  let nl = data.count('\n')
  let nuls = data.count('\0')
  var cuts = 0
  let txt = if asText: cleanUtf8(data, cut, cuts) else: data
  @[record({"texte": strV(txt), "debut": intV(start), "fin": intV(start + int64(data.len)),
            "lignes": intV(nl), "taille": intV(size), "coupees": intV(cuts), "nuls": intV(nuls)})]

proc countLinesIn(L: Interp, a: seq[Value]): seq[Value] =
  let path = L.checkStr(a, 1, "compterlignes")
  let size = fileSizeOf(path)
  if size < 0: return fail(path & " : lecture impossible")
  let pos = clamp(int64(L.optNum(a, 2, "compterlignes", 0)), 0'i64, size)
  let lenArg = arg(a, 3)
  let stop = if lenArg.kind == vkNil: size else: clamp(pos + int64(L.checkNum(a, 3, "compterlignes")), pos, size)
  var f: File
  if not open(f, path, fmRead): return fail(path & " : lecture impossible")
  defer: f.close()
  var n = 0
  var p = pos
  var buf = newString(ScanChunk)
  f.setFilePos(p)
  while p < stop:
    let want = int(min(int64(ScanChunk), stop - p))
    let got = f.readBuffer(buf[0].addr, want)
    if got <= 0: break
    for i in 0 ..< got:
      if buf[i] == '\n': inc n
    p += int64(got)
  @[intV(n)]

proc lineOffset(L: Interp, a: seq[Value]): seq[Value] =
  ## Position (octet) du début de la ligne `ligne` (à partir de 1), en partant d'un point
  ## connu {octet, ligne} ; nul au-delà de la fin du fichier.
  let path = L.checkStr(a, 1, "positionligne")
  let target = int64(L.checkNum(a, 2, "positionligne"))
  var p = int64(L.optNum(a, 3, "positionligne", 0))
  var line = int64(L.optNum(a, 4, "positionligne", 1))
  let size = fileSizeOf(path)
  if size < 0: return fail(path & " : lecture impossible")
  if target < line: return @[nilV]
  if target == line: return @[intV(p)]
  var f: File
  if not open(f, path, fmRead): return fail(path & " : lecture impossible")
  defer: f.close()
  var buf = newString(ScanChunk)
  f.setFilePos(p)
  while p < size:
    let got = f.readBuffer(buf[0].addr, int(min(int64(ScanChunk), size - p)))
    if got <= 0: break
    for i in 0 ..< got:
      if buf[i] == '\n':
        inc line
        if line == target: return @[intV(p + int64(i) + 1)]
    p += int64(got)
  @[nilV]

proc searchFile(L: Interp, a: seq[Value]): seq[Value] =
  ## fichier.rechercher(chemin, motif, [debut], [{casse=, arriere=, limite=}])
  ## -> {position (nul si absent de la zone parcourue), suite (où reprendre, nul à la fin)}.
  let path = L.checkStr(a, 1, "rechercher")
  var pat = L.checkStr(a, 2, "rechercher")
  if pat.len == 0: return fail("rechercher : motif vide")
  let size = fileSizeOf(path)
  if size < 0: return fail(path & " : lecture impossible")
  let o = if arg(a, 4).kind == vkTable: a[3].t else: nil
  let matchCase = optField(o, "casse", false)
  let backward = optField(o, "arriere", false)
  let limit = int64(optField(o, "limite", 0.0))
  var pos = clamp(int64(L.optNum(a, 3, "rechercher", (if backward: float(size) else: 0.0))), 0'i64, size)
  if not matchCase: pat = pat.toLowerAscii
  var f: File
  if not open(f, path, fmRead): return fail(path & " : lecture impossible")
  defer: f.close()
  let ov = pat.len - 1
  var scanned = 0'i64
  try:
    if not backward:
      var p = pos
      while p < size:
        let n = int(min(int64(ScanChunk + ov), size - p))
        var buf = f.readRange(p, n)
        if not matchCase: buf = buf.toLowerAscii
        let k = buf.find(pat)
        if k >= 0: return @[record({"position": intV(p + int64(k)), "suite": intV(p + int64(k) + 1)})]
        if p + int64(n) >= size: break
        p += int64(ScanChunk)
        scanned += int64(ScanChunk)
        if limit > 0 and scanned >= limit:
          return @[record({"position": nilV, "suite": intV(p)})]
      return @[record({"position": nilV, "suite": nilV})]
    else:
      var z = pos                         # fin exclue de la zone à examiner
      while z > 0:
        let st = max(0'i64, z - int64(ScanChunk))
        let n = int(min(size, z + int64(ov)) - st)
        var buf = f.readRange(st, n)
        if not matchCase: buf = buf.toLowerAscii
        var k = buf.rfind(pat)
        while k >= 0 and st + int64(k) >= z: k = (if k == 0: -1 else: buf.rfind(pat, last = k - 1))
        if k >= 0: return @[record({"position": intV(st + int64(k)), "suite": intV(st + int64(k))})]
        z = st
        scanned += int64(ScanChunk)
        if limit > 0 and scanned >= limit and z > 0:
          return @[record({"position": nilV, "suite": intV(z)})]
      return @[record({"position": nilV, "suite": nilV})]
  except IOError, OSError:
    return fail(path & " : lecture impossible")

proc openFichier(L: Interp): Value =
  let m = newLib()
  m.fn "lirebloc", proc (L: Interp, a: seq[Value]): seq[Value] = readBlock(L, a)
  m.fn "compterlignes", proc (L: Interp, a: seq[Value]): seq[Value] = countLinesIn(L, a)
  m.fn "positionligne", proc (L: Interp, a: seq[Value]): seq[Value] = lineOffset(L, a)
  m.fn "rechercher", proc (L: Interp, a: seq[Value]): seq[Value] = searchFile(L, a)
  m.fn "lire", proc (L: Interp, a: seq[Value]): seq[Value] = readText(L.checkStr(a, 1, "lire"))
  m.fn "lireoctets", proc (L: Interp, a: seq[Value]): seq[Value] = readText(L.checkStr(a, 1, "lireoctets"))
  m.fn "ecrire", proc (L: Interp, a: seq[Value]): seq[Value] =
    writeText(L.checkStr(a, 1, "ecrire"), L.checkStr(a, 2, "ecrire"), false)
  m.fn "ecrireoctets", proc (L: Interp, a: seq[Value]): seq[Value] =
    writeText(L.checkStr(a, 1, "ecrireoctets"), L.checkStr(a, 2, "ecrireoctets"), false)
  m.fn "ajouter", proc (L: Interp, a: seq[Value]): seq[Value] =
    writeText(L.checkStr(a, 1, "ajouter"), L.checkStr(a, 2, "ajouter"), true)
  m.fn "lignes", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.checkStr(a, 1, "lignes")
    try:
      let t = newLTable()
      for l in lines(path): t.arr.add strV(l)
      @[tableV(t)]
    except IOError, OSError: fail(path & " : lecture impossible")
  m.fn "ecrirelignes", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkTable(a, 2, "ecrirelignes")
    var parts: seq[string]
    for i in 1 .. t.rawLen: parts.add L.tostr(t.rawGet(intV(i)))
    writeText(L.checkStr(a, 1, "ecrirelignes"), parts.join("\n") & "\n", false)
  m.fn "existe", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkStr(a, 1, "existe")
    @[boolV(fileExists(p) or dirExists(p))]
  m.fn "estfichier", proc (L: Interp, a: seq[Value]): seq[Value] = @[boolV(fileExists(L.checkStr(a, 1, "estfichier")))]
  m.fn "estdossier", proc (L: Interp, a: seq[Value]): seq[Value] = @[boolV(dirExists(L.checkStr(a, 1, "estdossier")))]
  m.fn "taille", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkStr(a, 1, "taille")
    if not fileExists(p): return fail(p & " : fichier introuvable")
    @[intV(getFileSize(p))]
  m.fn "liste", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.optStr(a, 1, "liste", ".")
    if not dirExists(d): return fail(d & " : dossier introuvable")
    @[listDir(d, optBool(a, 2, false))]
  m.fn "creerdossier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkStr(a, 1, "creerdossier")
    try:
      createDir(d)
      @[boolV(true)]
    except OSError: fail(d & " : création impossible")
  m.fn "supprimer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkStr(a, 1, "supprimer")
    try:
      if dirExists(p): removeDir(p)
      elif fileExists(p): removeFile(p)
      else: return fail(p & " : introuvable")
      @[boolV(true)]
    except OSError: fail(p & " : suppression impossible")
  m.fn "copier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let src = L.checkStr(a, 1, "copier")
    let dst = L.checkStr(a, 2, "copier")
    try:
      if dirExists(src): copyDir(src, dst) else: copyFile(src, dst)
      @[boolV(true)]
    except OSError, IOError: fail(src & " : copie impossible")
  m.fn "deplacer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let src = L.checkStr(a, 1, "deplacer")
    let dst = L.checkStr(a, 2, "deplacer")
    try:
      if dirExists(src): moveDir(src, dst) else: moveFile(src, dst)
      @[boolV(true)]
    except OSError, IOError: fail(src & " : déplacement impossible")
  m.fn "infos", proc (L: Interp, a: seq[Value]): seq[Value] = @[statTable(L.checkStr(a, 1, "infos"))]
  m.fn "courant", proc (L: Interp, a: seq[Value]): seq[Value] = @[strV(getCurrentDir())]
  m.fn "changer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkStr(a, 1, "changer")
    try:
      setCurrentDir(d)
      @[boolV(true)]
    except OSError: fail(d & " : dossier introuvable")
  m.fn "joindre", proc (L: Interp, a: seq[Value]): seq[Value] =
    var p = ""
    for i in 1 .. a.len: p = if p.len == 0: L.checkStr(a, i, "joindre") else: p / L.checkStr(a, i, "joindre")
    @[strV(p)]
  m.fn "nom", proc (L: Interp, a: seq[Value]): seq[Value] = @[strV(extractFilename(L.checkStr(a, 1, "nom")))]
  m.fn "dossier", proc (L: Interp, a: seq[Value]): seq[Value] = @[strV(parentDir(L.checkStr(a, 1, "dossier")))]
  m.fn "extension", proc (L: Interp, a: seq[Value]): seq[Value] = @[strV(splitFile(L.checkStr(a, 1, "extension")).ext)]
  m.fn "absolu", proc (L: Interp, a: seq[Value]): seq[Value] = @[strV(absolutePath(L.checkStr(a, 1, "absolu")))]
  m.fn "dossiertemp", proc (L: Interp, a: seq[Value]): seq[Value] = @[strV(getTempDir())]
  m.fn "dossierperso", proc (L: Interp, a: seq[Value]): seq[Value] = @[strV(getHomeDir())]
  m.fn "proteger", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Lecture et écriture réservées au propriétaire (0600 ; sans effet notable sous Windows).
    let p = L.checkStr(a, 1, "proteger")
    try:
      setFilePermissions(p, {fpUserRead, fpUserWrite})
      @[boolV(true)]
    except OSError: @[boolV(false)]
  tableV(m)

registerPackage PackageDef(name: "fichier", open: openFichier,
  description: "Fichiers et dossiers (texte et binaire)",
  docs: docs("fichier", [
    "fichier.lire(chemin)", "Contenu complet d'un fichier (texte ou binaire).",
    "fichier.lireoctets(chemin)", "Contenu binaire (les chaînes sont des suites d'octets).",
    "fichier.ecrire(chemin, donnees)", "Remplace le contenu d'un fichier.",
    "fichier.ecrireoctets(chemin, donnees)", "Écrit des octets.",
    "fichier.ajouter(chemin, donnees)", "Ajoute à la fin d'un fichier.",
    "fichier.lignes(chemin)", "Liste des lignes d'un fichier.",
    "fichier.ecrirelignes(chemin, lignes)", "Écrit une liste de lignes.",
    "fichier.existe(chemin)", "Vrai si le fichier ou le dossier existe.",
    "fichier.estfichier(chemin)", "Vrai pour un fichier.", "fichier.estdossier(chemin)", "Vrai pour un dossier.",
    "fichier.taille(chemin)", "Taille en octets.",
    "fichier.liste([dossier], [recursif])", "Noms contenus dans un dossier (les dossiers finissent par /).",
    "fichier.creerdossier(chemin)", "Crée un dossier (et ses parents).",
    "fichier.supprimer(chemin)", "Supprime un fichier ou un dossier (récursif).",
    "fichier.copier(source, destination)", "Copie (dossiers récursivement).",
    "fichier.deplacer(source, destination)", "Déplace ou renomme.",
    "fichier.infos(chemin)", "Table {taille, genre (\"fichier\" ou \"dossier\"), modifie, cree} ou nul.",
    "fichier.courant()", "Dossier courant.", "fichier.changer(dossier)", "Change de dossier courant.",
    "fichier.joindre(a, b, ...)", "Assemble des chemins.", "fichier.nom(chemin)", "Nom du fichier.",
    "fichier.dossier(chemin)", "Dossier parent.", "fichier.extension(chemin)", "Extension.",
    "fichier.absolu(chemin)", "Chemin absolu.",
    "fichier.dossiertemp()", "Dossier temporaire.", "fichier.dossierperso()", "Dossier personnel.",
    "fichier.proteger(chemin)", "Réserve le fichier à son propriétaire (droits 0600 sous Linux et macOS).",
    "fichier.lirebloc(chemin, position, taille, [{lignes=, texte=, coupe=}])", "Lit au plus taille octets à partir de position (octets, à partir de 0) sans charger le fichier : {texte, debut, fin, lignes, taille, coupees, nuls}. lignes = vrai (défaut) : le bloc commence et finit sur des débuts de ligne ; texte = vrai (défaut) : UTF-8 assaini (octets invalides -> U+FFFD, NUL -> « · ») ; nuls : nombre d'octets nuls (fichier binaire) ; coupe = n : lignes de plus de n octets coupées.",
    "fichier.compterlignes(chemin, [debut], [longueur])", "Nombre de fins de ligne dans une zone du fichier (lecture par blocs de 4 Mo).",
    "fichier.positionligne(chemin, ligne, [octet], [ligne_de_depart])", "Position (octet) du début d'une ligne, en partant d'un point connu (défaut : début du fichier, ligne 1) ; nul au-delà de la fin.",
    "fichier.rechercher(chemin, motif, [debut], [{casse=, arriere=, limite=}])", "Cherche un texte dans un fichier de toute taille : {position (nul si absent de la zone parcourue), suite (où reprendre, nul à la fin)} ; limite : octets parcourus au plus par appel (recherche progressive)."]))

#
# binaire : coder / decoder
#

proc putInt(buf: var string, v: uint64, size: int, little: bool) =
  for i in 0 ..< size:
    let shift = if little: 8 * i else: 8 * (size - 1 - i)
    buf.add chr(int((v shr shift) and 0xFF))

proc getInt(s: string, pos, size: int, little: bool): uint64 =
  for i in 0 ..< size:
    let b = uint64(ord(s[pos + i]))
    let shift = if little: 8 * i else: 8 * (size - 1 - i)
    result = result or (b shl shift)

proc fmtSize(c: char, num: int): int =
  case c
  of 'b', 'B': 1
  of 'h', 'H': 2
  of 'i', 'I', 'f': 4
  of 'l', 'L', 'j', 'J', 'd', 'n': 8
  of 'c': num
  else: 0

proc readNum(fmt: string, i: var int): int =
  result = -1
  while i < fmt.len and fmt[i] in Digits:
    result = max(result, 0) * 10 + (ord(fmt[i]) - ord('0'))
    inc i

proc openBinaire(L: Interp): Value =
  let m = newLib()
  m.fn "coder", proc (L: Interp, a: seq[Value]): seq[Value] =
    let fmt = L.checkStr(a, 1, "coder")
    var little = true
    var outp = ""
    var argi = 2
    var i = 0
    while i < fmt.len:
      let c = fmt[i]
      inc i
      let num = readNum(fmt, i)
      case c
      of '<', '=': little = true
      of '>', '!': little = false
      of ' ': discard
      of 'b', 'B', 'h', 'H', 'i', 'I', 'l', 'L', 'j', 'J':
        let size = if c in {'i', 'I'} and num > 0: num else: fmtSize(c, num)
        putInt(outp, cast[uint64](L.checkInt(a, argi, "coder")), size, little)
        inc argi
      of 'f':
        let f = float32(L.checkNum(a, argi, "coder"))
        putInt(outp, uint64(cast[uint32](f)), 4, little)
        inc argi
      of 'd', 'n':
        putInt(outp, cast[uint64](L.checkNum(a, argi, "coder")), 8, little)
        inc argi
      of 'z':
        outp.add L.checkStr(a, argi, "coder") & "\0"
        inc argi
      of 's':
        let s = L.checkStr(a, argi, "coder")
        putInt(outp, uint64(s.len), (if num > 0: num else: 8), little)
        outp.add s
        inc argi
      of 'c':
        if num < 0: rtError("taille manquante pour « c » dans le format")
        var s = L.checkStr(a, argi, "coder")
        if s.len > num: argError(argi, "coder", "chaîne plus longue que la taille donnée")
        while s.len < num: s.add '\0'
        outp.add s
        inc argi
      of 'x': outp.add '\0'
      else: rtError("option de format invalide « " & $c & " »")
    @[strV(outp)]
  m.fn "decoder", proc (L: Interp, a: seq[Value]): seq[Value] =
    let fmt = L.checkStr(a, 1, "decoder")
    let s = L.checkStr(a, 2, "decoder")
    var pos = int(L.optInt(a, 3, "decoder", 1)) - 1
    var little = true
    var i = 0
    let res = newLTable()
    template need(n: int) =
      if pos + n > s.len: rtError("données trop courtes pour « decoder »")
    while i < fmt.len:
      let c = fmt[i]
      inc i
      let num = readNum(fmt, i)
      case c
      of '<', '=': little = true
      of '>', '!': little = false
      of ' ': discard
      of 'b', 'h', 'i', 'l', 'j':
        let size = if c == 'i' and num > 0: num else: fmtSize(c, num)
        need(size)
        var v = getInt(s, pos, size, little)
        if size < 8 and (v and (1'u64 shl (8 * size - 1))) != 0:
          v = v or (not 0'u64 shl (8 * size))          # extension de signe
        res.arr.add intV(cast[int64](v))
        pos += size
      of 'B', 'H', 'I', 'L', 'J':
        let size = if c == 'I' and num > 0: num else: fmtSize(c, num)
        need(size)
        res.arr.add intV(cast[int64](getInt(s, pos, size, little)))
        pos += size
      of 'f':
        need(4)
        res.arr.add numV(float64(cast[float32](uint32(getInt(s, pos, 4, little)))))
        pos += 4
      of 'd', 'n':
        need(8)
        res.arr.add numV(cast[float64](getInt(s, pos, 8, little)))
        pos += 8
      of 'z':
        let e = s.find('\0', pos)
        if e < 0: rtError("chaîne non terminée pour « z »")
        res.arr.add strV(s[pos ..< e])
        pos = e + 1
      of 's':
        let size = if num > 0: num else: 8
        need(size)
        let n = int(getInt(s, pos, size, little))
        pos += size
        need(n)
        res.arr.add strV(s[pos ..< pos + n])
        pos += n
      of 'c':
        need(num)
        res.arr.add strV(s[pos ..< pos + num])
        pos += num
      of 'x': pos += 1
      else: rtError("option de format invalide « " & $c & " »")
    res.set "suite", intV(pos + 1)
    @[tableV(res)]
  m.fn "taille", proc (L: Interp, a: seq[Value]): seq[Value] =
    let fmt = L.checkStr(a, 1, "taille")
    var total = 0
    var i = 0
    while i < fmt.len:
      let c = fmt[i]
      inc i
      let num = readNum(fmt, i)
      if c in {'s', 'z'}: rtError("taille variable pour « " & $c & " »")
      total += (if c in {'i', 'I'} and num > 0: num elif c == 'x': 1 else: fmtSize(c, num))
    @[intV(total)]
  m.fn "hex", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkStr(a, 1, "hex")
    var r = ""
    for ch in s: r.add toHex(ord(ch), 2).toLowerAscii
    @[strV(r)]
  m.fn "dehex", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkStr(a, 1, "dehex")
    if s.len mod 2 != 0: return fail("longueur hexadécimale impaire")
    var r = ""
    try:
      for i in countup(0, s.len - 2, 2): r.add chr(parseHexInt(s[i .. i + 1]))
    except ValueError: return fail("chaîne hexadécimale invalide")
    @[strV(r)]
  tableV(m)

registerPackage PackageDef(name: "binaire", open: openBinaire,
  description: "Données binaires",
  docs: docs("binaire", [
    "binaire.coder(format, ...)", "Code des valeurs en binaire. Format : < petit-boutiste, > gros-boutiste, b/B 8 bits, h/H 16, i/I 32 (iN : N octets), l/L/j/J 64, f flottant 32, d flottant 64, z chaîne terminée par zéro, s chaîne préfixée par sa longueur, cN chaîne de N octets, x octet nul.",
    "binaire.decoder(format, donnees, [position])", "Décode ; renvoie la liste des valeurs, avec le champ suite (position suivante).",
    "binaire.taille(format)", "Taille d'un format fixe.",
    "binaire.hex(donnees)", "Représentation hexadécimale.",
    "binaire.dehex(hex)", "Octets à partir de l'hexadécimal."]))

#
# json
#

proc jsonNull(L: Interp): Value =
  let existing = L.registry.rawGet("json.nul")
  if existing.kind != vkNil: return existing
  result = userV(LUser(tname: "json.nul"))
  result.u.meta = newLTable()
  result.u.meta.set "__tostring", fnV("tostring", proc (L: Interp, a: seq[Value]): seq[Value] = @[strV("null")])
  L.registry.rawSet("json.nul", result)

proc openJson(L: Interp): Value =
  let m = newLib()
  m.set "nul", L.jsonNull()
  m.fn "encoder", proc (L: Interp, a: seq[Value]): seq[Value] =
    let j = L.toJsonNode(arg(a, 1))
    @[strV(if optBool(a, 2, false): j.pretty else: $j)]
  m.fn "decoder", proc (L: Interp, a: seq[Value]): seq[Value] =
    try: @[fromJsonNode(parseJson(L.checkStr(a, 1, "decoder")), not optBool(a, 2, false))]
    except JsonParsingError, ValueError: fail("JSON invalide : " & getCurrentExceptionMsg())
  m.fn "lire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.checkStr(a, 1, "lire")
    try: @[fromJsonNode(parseFile(path), not optBool(a, 2, false))]
    except IOError, OSError: fail(path & " : lecture impossible")
    except JsonParsingError, ValueError: fail("JSON invalide : " & getCurrentExceptionMsg())
  m.fn "ecrire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.checkStr(a, 1, "ecrire")
    let j = L.toJsonNode(arg(a, 2))
    try:
      writeFile(path, if optBool(a, 3, true): j.pretty else: $j)
      @[boolV(true)]
    except IOError, OSError: fail(path & " : écriture impossible")
  tableV(m)

registerPackage PackageDef(name: "json", open: openJson,
  description: "JSON",
  docs: docs("json", [
    "json.encoder(valeur, [joli])", "Texte JSON ; une liste 1..n devient un tableau, sinon un objet (joli = vrai : indenté).",
    "json.decoder(texte, [exact])", "Valeur Lexis+ ; les clefs d'objets sont mises en majuscules sauf si exact = vrai.",
    "json.lire(chemin, [exact])", "Lit et décode un fichier JSON.",
    "json.ecrire(chemin, valeur, [joli])", "Encode et écrit un fichier JSON (indenté par défaut).",
    "json.nul", "Valeur représentant null dans les données à encoder."]))

#
# csv
#

proc csvParse(L: Interp, text: string, opts: LTable): Value =
  let sep = optField(opts, "sep", ",")
  let header = optField(opts, "entete", false)
  let convert = optField(opts, "convertir", true)
  var p: CsvParser
  var s = newStringStream(text)
  p.open(s, "csv", separator = (if sep.len > 0: sep[0] else: ','))
  let rows = newLTable()
  var names: seq[string]
  try:
    if header:
      p.readHeaderRow()
      names = p.headers
    while p.readRow():
      let r = newLTable()
      for i, cell in p.row:
        var v = strV(cell)
        if convert and cell.len > 0:
          let (ok, n) = str2number(cell)
          if ok: v = n
        if header and i < names.len: r.rawSet(strV(toUpper(names[i])), v)
        else: r.rawSet(intV(i + 1), v)
      rows.arr.add tableV(r)
  except CsvError as e:
    rtError("CSV invalide : " & e.msg)
  finally:
    p.close()
  if header:
    let h = newLTable()
    for n in names: h.arr.add strV(n)
    # l'en-tête est accessible par lignes.entete sans être parcouru par « pour chaque »
    let extra = newLTable()
    extra.set "entete", tableV(h)
    rows.meta = newLTable()
    rows.meta.set "__index", tableV(extra)
  tableV(rows)

proc csvQuote(s, sep: string): string =
  if s.contains(sep) or s.contains('"') or s.contains('\n') or s.contains('\r'):
    "\"" & s.replace("\"", "\"\"") & "\""
  else: s

proc csvEncode(L: Interp, rows: LTable, opts: LTable): string =
  let sep = optField(opts, "sep", ",")
  var cols: seq[string]
  let hv = opts.field("entete")
  if hv.kind == vkTable:
    for i in 1 .. hv.t.rawLen: cols.add rawToString(hv.t.rawGet(intV(i)))
  elif hv.kind == vkBool and hv.b and rows.rawLen > 0 and rows.rawGet(intV(1)).kind == vkTable:
    for k, _ in rows.rawGet(intV(1)).t.pairs:
      if k.kind == vkStr: cols.add k.s
  var lines: seq[string]
  if cols.len > 0:
    var hs: seq[string]
    for c in cols: hs.add csvQuote(c, sep)
    lines.add hs.join(sep)
  for i in 1 .. rows.rawLen:
    let r = rows.rawGet(intV(i))
    if r.kind != vkTable: rtError("ligne " & $i & " : table attendue")
    var cells: seq[string]
    if cols.len > 0:
      for c in cols:
        var v = r.t.rawGet(c)
        if v.kind == vkNil: v = r.t.rawGet(toUpper(c))
        cells.add csvQuote(L.tostr(v), sep)
    else:
      for k in 1 .. r.t.rawLen: cells.add csvQuote(L.tostr(r.t.rawGet(intV(k))), sep)
    lines.add cells.join(sep)
  lines.join("\r\n") & "\r\n"

proc optsArg(a: seq[Value], i: int): LTable =
  if arg(a, i).kind == vkTable: a[i - 1].t else: nil

proc openCsv(L: Interp): Value =
  let m = newLib()
  m.fn "analyser", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[L.csvParse(L.checkStr(a, 1, "analyser"), optsArg(a, 2))]
  m.fn "lire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.checkStr(a, 1, "lire")
    var text: string
    try: text = readFile(path)
    except IOError, OSError: return fail(path & " : lecture impossible")
    @[L.csvParse(text, optsArg(a, 2))]
  m.fn "encoder", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(L.csvEncode(L.checkTable(a, 1, "encoder"), optsArg(a, 2)))]
  m.fn "ecrire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.checkStr(a, 1, "ecrire")
    let text = L.csvEncode(L.checkTable(a, 2, "ecrire"), optsArg(a, 3))
    try:
      writeFile(path, text)
      @[boolV(true)]
    except IOError, OSError: fail(path & " : écriture impossible")
  tableV(m)

registerPackage PackageDef(name: "csv", open: openCsv,
  description: "Fichiers CSV",
  docs: docs("csv", [
    "csv.analyser(texte, [options])", "Liste des lignes d'un texte CSV. options : sep (\",\"), entete (faux : lignes = listes ; vrai : lignes = tables par nom de colonne, et lignes.entete donne les noms), convertir (vrai : nombres convertis).",
    "csv.lire(chemin, [options])", "Lit un fichier CSV (mêmes options).",
    "csv.encoder(lignes, [options])", "Texte CSV. options : sep, entete (liste des colonnes, ou vrai pour les déduire).",
    "csv.ecrire(chemin, lignes, [options])", "Écrit un fichier CSV."]))
