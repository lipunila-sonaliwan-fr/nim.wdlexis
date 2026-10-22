# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - écriture de fichiers PDF (Nim pur) pour les états.
#
#   Polices : les 12 polices standard (Helvetica, Times, Courier, en normal, gras,
#   italique, gras italique) en codage WinAnsi : tous les caractères du français
#   (é, è, ç, œ, «, », €, …) sans police embarquée. Coordonnées en points, origine
#   en bas à gauche (comme PDF).
#
#   let d = newPdf("Titre")
#   d.addPage(595.28, 841.89)                       A4 portrait
#   d.text(fHelvetica, 12, 72, 770, "Bonjour", (0.0, 0.0, 0.0))
#   d.rect(72, 700, 200, 50, stroke = some(noir), fill = none(Rgb))
#   d.image("logo.png", 72, 600, 100, 50)           PNG ou JPEG
#   d.save("sortie.pdf")

import std/[strutils, tables, os, options, times, math, unicode]
import zflate, pdfmetrics

type
  Rgb* = tuple[r, g, b: float]       # 0..1

  PdfFont* = enum
    fHelvetica, fHelveticaBold, fHelveticaOblique, fHelveticaBoldOblique,
    fTimes, fTimesBold, fTimesItalic, fTimesBoldItalic,
    fCourier, fCourierBold, fCourierOblique, fCourierBoldOblique

  PdfImage = object
    w, h: int
    data: string
    filter, colorSpace, decode: string
    alpha: string                # masque (gris 8 bits, compressé), vide si opaque

  PdfPage = object
    w, h: float
    content: string
    fonts: set[PdfFont]
    images: seq[int]

  PdfDoc* = ref object
    title*: string
    pages: seq[PdfPage]
    images: seq[PdfImage]
    imageIndex: Table[string, int]   # chemin -> image (-1 : illisible)
    imageErrors*: seq[string]

const Black*: Rgb = (0.0, 0.0, 0.0)

proc fontOf*(family: string, bold, italic: bool): PdfFont =
  ## famille : helvetica (défaut), times, courier.
  let base = case family.toLowerAscii
    of "times", "serif", "times-roman": 4
    of "courier", "mono", "monospace": 8
    else: 0
  PdfFont(base + (if bold: 1 else: 0) + (if italic: 2 else: 0))

# ------------------------------------------------------------------ texte

proc winAnsi*(s: string): string =
  ## UTF-8 -> WinAnsi (CP1252) ; caractère absent : « ? ».
  for r in s.runes:
    let c = int(r)
    if c < 0x80: result.add char(c)
    elif c >= 0xA0 and c <= 0xFF: result.add char(c)
    else:
      result.add(case c
        of 0x20AC: '\x80'
        of 0x201A: '\x82'
        of 0x0192: '\x83'
        of 0x201E: '\x84'
        of 0x2026: '\x85'
        of 0x2020: '\x86'
        of 0x2021: '\x87'
        of 0x02C6: '\x88'
        of 0x2030: '\x89'
        of 0x0160: '\x8A'
        of 0x2039: '\x8B'
        of 0x0152: '\x8C'
        of 0x017D: '\x8E'
        of 0x2018: '\x91'
        of 0x2019: '\x92'
        of 0x201C: '\x93'
        of 0x201D: '\x94'
        of 0x2022: '\x95'
        of 0x2013: '\x96'
        of 0x2014: '\x97'
        of 0x02DC: '\x98'
        of 0x2122: '\x99'
        of 0x0161: '\x9A'
        of 0x203A: '\x9B'
        of 0x0153: '\x9C'
        of 0x017E: '\x9E'
        of 0x0178: '\x9F'
        of 0x202F, 0x2007, 0x2009: '\xA0'
        else: '?')

proc ansiWidth*(f: PdfFont, size: float, ansi: string): float =
  ## Largeur (points) d'un texte déjà en WinAnsi.
  var t = 0
  for c in ansi: t += int(PdfFontWidths[ord(f)][ord(c)])
  float(t) * size / 1000.0

proc textWidth*(f: PdfFont, size: float, s: string): float =
  ## Largeur (points) d'un texte UTF-8.
  ansiWidth(f, size, winAnsi(s))

proc ascent*(f: PdfFont, size: float): float = float(PdfFontAscent[ord(f)]) * size / 1000.0
proc descent*(f: PdfFont, size: float): float = -float(PdfFontDescent[ord(f)]) * size / 1000.0

proc pdfString(ansi: string): string =
  result = "("
  for c in ansi:
    case c
    of '(', ')', '\\': result.add '\\' & c
    of '\r': result.add "\\r"
    of '\n': result.add "\\n"
    else: result.add c
  result.add ")"

proc num(f: float): string =
  ## Nombre PDF compact (3 décimales au plus).
  if abs(f - round(f)) < 0.0005: return $int(round(f))
  result = formatFloat(f, ffDecimal, 3)
  result = result.strip(leading = false, chars = {'0'})
  if result.endsWith("."): result.setLen(result.len - 1)
  if result == "-0": result = "0"

proc color(c: Rgb, op: string): string = num(c.r) & " " & num(c.g) & " " & num(c.b) & " " & op & "\n"

# ------------------------------------------------------------------ document

proc newPdf*(title = ""): PdfDoc =
  PdfDoc(title: title, imageIndex: initTable[string, int]())

proc pageCount*(d: PdfDoc): int = d.pages.len

proc addPage*(d: PdfDoc, w, h: float) =
  d.pages.add PdfPage(w: w, h: h)

template cur(d: PdfDoc): var PdfPage = d.pages[^1]

proc raw*(d: PdfDoc, ops: string) = d.cur.content.add ops

proc text*(d: PdfDoc, f: PdfFont, size, x, y: float, s: string, c: Rgb = Black, underline = false) =
  ## Texte sur sa ligne de base (x, y).
  let a = winAnsi(s)
  if a.len == 0: return
  d.cur.fonts.incl f
  d.cur.content.add "BT\n" & color(c, "rg") & "/F" & $(ord(f) + 1) & " " & num(size) & " Tf\n" &
                    num(x) & " " & num(y) & " Td\n" & pdfString(a) & " Tj\nET\n"
  if underline:
    let w = ansiWidth(f, size, a)
    d.cur.content.add "q\n" & color(c, "RG") & num(max(0.4, size / 18)) & " w\n" &
                      num(x) & " " & num(y - size * 0.12) & " m " & num(x + w) & " " & num(y - size * 0.12) & " l S\nQ\n"

proc line*(d: PdfDoc, x1, y1, x2, y2: float, c: Rgb = Black, width = 0.5, dashed = false) =
  d.cur.content.add "q\n" & color(c, "RG") & num(width) & " w\n" & (if dashed: "[3 2] 0 d\n" else: "") &
                    num(x1) & " " & num(y1) & " m " & num(x2) & " " & num(y2) & " l S\nQ\n"

proc rect*(d: PdfDoc, x, y, w, h: float, stroke = none(Rgb), fill = none(Rgb), width = 0.5, radius = 0.0) =
  ## Rectangle (x, y : coin bas gauche), arrondi si radius > 0.
  if stroke.isNone and fill.isNone: return
  var path = ""
  let r = min(radius, min(w, h) / 2)
  if r <= 0.01:
    path = num(x) & " " & num(y) & " " & num(w) & " " & num(h) & " re\n"
  else:
    const k = 0.5523
    let x2 = x + w
    let y2 = y + h
    path = num(x + r) & " " & num(y) & " m\n" &
           num(x2 - r) & " " & num(y) & " l\n" &
           num(x2 - r + k * r) & " " & num(y) & " " & num(x2) & " " & num(y + r - k * r) & " " & num(x2) & " " & num(y + r) & " c\n" &
           num(x2) & " " & num(y2 - r) & " l\n" &
           num(x2) & " " & num(y2 - r + k * r) & " " & num(x2 - r + k * r) & " " & num(y2) & " " & num(x2 - r) & " " & num(y2) & " c\n" &
           num(x + r) & " " & num(y2) & " l\n" &
           num(x + r - k * r) & " " & num(y2) & " " & num(x) & " " & num(y2 - r + k * r) & " " & num(x) & " " & num(y2 - r) & " c\n" &
           num(x) & " " & num(y + r) & " l\n" &
           num(x) & " " & num(y + r - k * r) & " " & num(x + r - k * r) & " " & num(y) & " " & num(x + r) & " " & num(y) & " c\nh\n"
  var s = "q\n"
  if fill.isSome: s.add color(fill.get, "rg")
  if stroke.isSome: s.add color(stroke.get, "RG") & num(width) & " w\n"
  s.add path
  s.add(if fill.isSome and stroke.isSome: "B\n" elif fill.isSome: "f\n" else: "S\n")
  s.add "Q\n"
  d.cur.content.add s

proc clip*(d: PdfDoc, x, y, w, h: float) =
  ## Limite le dessin suivant au rectangle (jusqu'au unclip correspondant).
  d.cur.content.add "q\n" & num(x) & " " & num(y) & " " & num(w) & " " & num(h) & " re W n\n"

proc unclip*(d: PdfDoc) = d.cur.content.add "Q\n"

# ------------------------------------------------------------------ images

proc be32(s: string, i: int): int =
  (ord(s[i]) shl 24) or (ord(s[i + 1]) shl 16) or (ord(s[i + 2]) shl 8) or ord(s[i + 3])

proc loadJpeg(data: string): PdfImage =
  var i = 2
  while i + 9 < data.len:
    if data[i] != '\xFF':
      inc i
      continue
    let m = ord(data[i + 1])
    if m in [0xD8, 0x01] or (m >= 0xD0 and m <= 0xD7):
      i += 2
      continue
    let len = (ord(data[i + 2]) shl 8) or ord(data[i + 3])
    if m in [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]:
      result.h = (ord(data[i + 5]) shl 8) or ord(data[i + 6])
      result.w = (ord(data[i + 7]) shl 8) or ord(data[i + 8])
      let comps = ord(data[i + 9])
      result.colorSpace = case comps
        of 1: "/DeviceGray"
        of 4: "/DeviceCMYK"
        else: "/DeviceRGB"
      if comps == 4: result.decode = "/Decode [1 0 1 0 1 0 1 0]"   # JPEG Adobe : CMJN inversé
      result.data = data
      result.filter = "/DCTDecode"
      return
    i += 2 + len
  raise newException(ValueError, "JPEG sans dimensions")

proc paeth(a, b, c: int): int =
  let p = a + b - c
  let pa = abs(p - a)
  let pb = abs(p - b)
  let pc = abs(p - c)
  if pa <= pb and pa <= pc: a elif pb <= pc: b else: c

proc loadPng(data: string): PdfImage =
  if data.len < 33 or data[0 ..< 8] != "\x89PNG\r\n\x1a\n": raise newException(ValueError, "PNG invalide")
  var w, h, depth, ctype, interlace = 0
  var plte, trns, idat = ""
  var i = 8
  while i + 8 <= data.len:
    let len = be32(data, i)
    let typ = data[i + 4 ..< i + 8]
    if i + 8 + len > data.len: break
    let body = data[i + 8 ..< i + 8 + len]
    case typ
    of "IHDR":
      w = be32(body, 0)
      h = be32(body, 4)
      depth = ord(body[8])
      ctype = ord(body[9])
      interlace = ord(body[12])
    of "PLTE": plte = body
    of "tRNS": trns = body
    of "IDAT": idat.add body
    of "IEND": break
    else: discard
    i += 12 + len
  if w <= 0 or h <= 0: raise newException(ValueError, "PNG sans dimensions")
  if interlace != 0: raise newException(ValueError, "PNG entrelacé non pris en charge")
  let channels = case ctype
    of 0: 1
    of 2: 3
    of 3: 1
    of 4: 2
    of 6: 4
    else: raise newException(ValueError, "type de couleur PNG inconnu")
  let bitsPx = channels * depth
  let stride = (w * bitsPx + 7) div 8
  let bpp = max(1, bitsPx div 8)
  let raw = zlibDecompress(idat)
  if raw.len < h * (stride + 1): raise newException(ValueError, "PNG tronqué")
  # défiltrage
  var pix = newString(h * stride)
  var prevRow = newString(stride)
  for y in 0 ..< h:
    let f = ord(raw[y * (stride + 1)])
    var row = raw[y * (stride + 1) + 1 ..< (y + 1) * (stride + 1)]
    for x in 0 ..< stride:
      let a = if x >= bpp: ord(row[x - bpp]) else: 0
      let b = ord(prevRow[x])
      let c = if x >= bpp: ord(prevRow[x - bpp]) else: 0
      let v = ord(row[x])
      row[x] = char(case f
        of 1: (v + a) and 0xFF
        of 2: (v + b) and 0xFF
        of 3: (v + (a + b) div 2) and 0xFF
        of 4: (v + paeth(a, b, c)) and 0xFF
        else: v)
    copyMem(addr pix[y * stride], addr row[0], stride)
    prevRow = row
  # échantillon n°k d'une ligne (profondeurs 1, 2, 4, 8, 16 -> 0..255 ou index)
  proc sample(y, k: int): int =
    case depth
    of 8: ord(pix[y * stride + k])
    of 16: ord(pix[y * stride + k * 2])
    else:
      let bit = k * depth
      let byte = ord(pix[y * stride + bit div 8])
      let v = (byte shr (8 - depth - bit mod 8)) and ((1 shl depth) - 1)
      if ctype == 3: v else: v * 255 div ((1 shl depth) - 1)
  var rgb = newStringOfCap(w * h * 3)
  var alpha = newStringOfCap(w * h)
  var hasAlpha = false
  for y in 0 ..< h:
    for x in 0 ..< w:
      var r, g, b, a = 255
      case ctype
      of 0:
        r = sample(y, x)
        g = r
        b = r
        if trns.len >= 2 and depth <= 8 and r == ord(trns[1]) * (if depth < 8: 255 div ((1 shl depth) - 1) else: 1): a = 0
      of 2:
        r = sample(y, x * 3)
        g = sample(y, x * 3 + 1)
        b = sample(y, x * 3 + 2)
      of 3:
        let idx = sample(y, x)
        if idx * 3 + 2 < plte.len:
          r = ord(plte[idx * 3])
          g = ord(plte[idx * 3 + 1])
          b = ord(plte[idx * 3 + 2])
        if idx < trns.len: a = ord(trns[idx])
      of 4:
        r = sample(y, x * 2)
        g = r
        b = r
        a = sample(y, x * 2 + 1)
      else:
        r = sample(y, x * 4)
        g = sample(y, x * 4 + 1)
        b = sample(y, x * 4 + 2)
        a = sample(y, x * 4 + 3)
      rgb.add char(r)
      rgb.add char(g)
      rgb.add char(b)
      alpha.add char(a)
      if a != 255: hasAlpha = true
  result.w = w
  result.h = h
  result.colorSpace = "/DeviceRGB"
  result.filter = "/FlateDecode"
  result.data = zlibCompress(rgb)
  if hasAlpha: result.alpha = zlibCompress(alpha)

proc imageRef(d: PdfDoc, path: string): int =
  if d.imageIndex.hasKey(path): return d.imageIndex[path]
  result = -1
  try:
    let data = readFile(path)
    var img: PdfImage
    if data.len > 3 and data[0 .. 2] == "\xFF\xD8\xFF": img = loadJpeg(data)
    elif data.len > 8 and data[0 .. 3] == "\x89PNG": img = loadPng(data)
    else: raise newException(ValueError, "format non pris en charge (PNG ou JPEG)")
    d.images.add img
    result = d.images.high
  except CatchableError as e:
    d.imageErrors.add extractFilename(path) & " : " & e.msg
  d.imageIndex[path] = result

proc imageSize*(d: PdfDoc, path: string): tuple[w, h: int] =
  ## Dimensions en pixels (0, 0 si l'image est illisible).
  let i = d.imageRef(path)
  if i >= 0: (d.images[i].w, d.images[i].h) else: (0, 0)

proc image*(d: PdfDoc, path: string, x, y, w, h: float): bool =
  ## Image dans le rectangle (x, y : coin bas gauche) ; faux si illisible.
  let i = d.imageRef(path)
  if i < 0: return false
  if i notin d.cur.images: d.cur.images.add i
  d.cur.content.add "q\n" & num(w) & " 0 0 " & num(h) & " " & num(x) & " " & num(y) & " cm\n/Im" & $(i + 1) & " Do\nQ\n"
  true

# ------------------------------------------------------------------ sortie

proc toBytes*(d: PdfDoc): string =
  var objs: seq[string]                 # objets 1..n (corps sans « n 0 obj »)
  proc reserve(): int =
    objs.add ""
    objs.len
  let catalog = reserve()
  let pagesObj = reserve()
  let info = reserve()
  var fontObj: array[PdfFont, int]
  var used: set[PdfFont]
  for p in d.pages: used = used + p.fonts
  for f in PdfFont:
    if f in used:
      fontObj[f] = reserve()
      objs[fontObj[f] - 1] = "<< /Type /Font /Subtype /Type1 /BaseFont /" & PdfFontNames[ord(f)] &
                             " /Encoding /WinAnsiEncoding >>"
  var imgObj = newSeq[int](d.images.len)
  for i, img in d.images:
    var smask = ""
    if img.alpha.len > 0:
      let m = reserve()
      objs[m - 1] = "<< /Type /XObject /Subtype /Image /Width " & $img.w & " /Height " & $img.h &
                    " /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode /Length " &
                    $img.alpha.len & " >>\nstream\n" & img.alpha & "\nendstream"
      smask = " /SMask " & $m & " 0 R"
    imgObj[i] = reserve()
    objs[imgObj[i] - 1] = "<< /Type /XObject /Subtype /Image /Width " & $img.w & " /Height " & $img.h &
                          " /ColorSpace " & img.colorSpace & " /BitsPerComponent 8 /Filter " & img.filter &
                          (if img.decode.len > 0: " " & img.decode else: "") & smask &
                          " /Length " & $img.data.len & " >>\nstream\n" & img.data & "\nendstream"
  var kids: seq[string]
  for p in d.pages:
    let c = reserve()
    let z = zlibCompress(p.content)
    objs[c - 1] = "<< /Length " & $z.len & " /Filter /FlateDecode >>\nstream\n" & z & "\nendstream"
    var fonts = ""
    for f in p.fonts: fonts.add " /F" & $(ord(f) + 1) & " " & $fontObj[f] & " 0 R"
    var xobj = ""
    for i in p.images: xobj.add " /Im" & $(i + 1) & " " & $imgObj[i] & " 0 R"
    let po = reserve()
    objs[po - 1] = "<< /Type /Page /Parent " & $pagesObj & " 0 R /MediaBox [0 0 " & num(p.w) & " " & num(p.h) &
                   "] /Resources << /ProcSet [/PDF /Text /ImageB /ImageC]" &
                   (if fonts.len > 0: " /Font <<" & fonts & " >>" else: "") &
                   (if xobj.len > 0: " /XObject <<" & xobj & " >>" else: "") &
                   " >> /Contents " & $c & " 0 R >>"
    kids.add $po & " 0 R"
  objs[catalog - 1] = "<< /Type /Catalog /Pages " & $pagesObj & " 0 R >>"
  objs[pagesObj - 1] = "<< /Type /Pages /Kids [" & kids.join(" ") & "] /Count " & $d.pages.len & " >>"
  let now = now()
  objs[info - 1] = "<< /Producer (wdlexis+) /Creator (wdlexis+ - rapports)" &
                   (if d.title.len > 0: " /Title " & pdfString(winAnsi(d.title)) else: "") &
                   " /CreationDate (D:" & now.format("yyyyMMddHHmmss") & ") >>"
  result = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n"
  var offsets: seq[int]
  for i, o in objs:
    offsets.add result.len
    result.add $(i + 1) & " 0 obj\n" & o & "\nendobj\n"
  let xref = result.len
  result.add "xref\n0 " & $(objs.len + 1) & "\n0000000000 65535 f \n"
  for o in offsets: result.add align($o, 10, '0') & " 00000 n \n"
  result.add "trailer\n<< /Size " & $(objs.len + 1) & " /Root " & $catalog & " 0 R /Info " & $info &
             " 0 R >>\nstartxref\n" & $xref & "\n%%EOF\n"

proc save*(d: PdfDoc, path: string) =
  let dir = path.parentDir
  if dir.len > 0 and not dirExists(dir): createDir(dir)
  writeFile(path, d.toBytes)
