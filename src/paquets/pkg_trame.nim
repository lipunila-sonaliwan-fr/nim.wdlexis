# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet trame : images matricielles 8 / 16 bits en Nim pur
#
# Pensé pour les données d'un scanner (ou de tout capteur) : assemblage des
# lignes reçues (y compris les lignes séparées R, G, B d'un capteur CIS),
# recadrage, mise à l'échelle, niveaux (gamma, luminosité, contraste), gris,
# trait, rotation, statistiques, puis enregistrement en PNG (8 / 16 bits),
# JPEG (de base, qualité réglable), TIFF (non compressé, 8 / 16 bits),
# PNM et PDF (une ou plusieurs pages). Aucune bibliothèque C.
#
#   t = trame.nouvelle(2480, 0, 3, 8, {cis = vrai, dpi = 300})
#   t:ajouter(octets)              && lignes du capteur, au fil de la lecture
#   t:niveaux{gamma = 1.1, contraste = 10}
#   t:enregistrer("page.jpg", {qualite = 90})
#   trame.pdf("document.pdf", {t1, t2})
#
# Les données sont rangées par lignes, canaux entrelacés (RGB), 16 bits en
# petit-boutiste.

import std/[math, strutils, algorithm, os, random, times]
import ../lexis/api
import compression

type
  Trame = ref object of LUser
    w, h, ch, depth: int
    dpi: float
    cis: bool                 # t:ajouter reçoit des lignes séparées par canal
    data: string
    pending: string           # octets d'une ligne incomplète (t:ajouter)

proc bps(t: Trame): int {.inline.} = t.depth div 8
proc rowBytes(t: Trame): int {.inline.} = t.w * t.ch * t.bps

proc get(t: Trame, i: int): int {.inline.} =
  if t.depth == 8: ord(t.data[i])
  else: ord(t.data[2 * i]) or (ord(t.data[2 * i + 1]) shl 8)

proc put(t: Trame, i, v: int) {.inline.} =
  if t.depth == 8: t.data[i] = chr(clamp(v, 0, 255))
  else:
    let x = clamp(v, 0, 65535)
    t.data[2 * i] = chr(x and 0xff)
    t.data[2 * i + 1] = chr(x shr 8)

proc maxv(t: Trame): int {.inline.} = (if t.depth == 8: 255 else: 65535)

proc newTrame(w, h, ch, depth: int, dpi = 0.0): Trame =
  if w < 0 or h < 0: rtError("trame : dimensions invalides")
  if ch notin [1, 3]: rtError("trame : 1 ou 3 canaux")
  if depth notin [8, 16]: rtError("trame : profondeur 8 ou 16 bits")
  result = Trame(w: w, h: h, ch: ch, depth: depth, dpi: dpi)
  result.data = newString(w * h * ch * (depth div 8))

proc checkT(L: Interp, a: seq[Value], fname: string): Trame =
  L.checkUser[:Trame](a, 1, fname, "trame")

#
# Assemblage des lignes (CIS : une ligne par canal)
#

proc appendRows(t: Trame, raw: string) =
  var src = t.pending & raw
  t.pending = ""
  let inRow = if t.cis and t.ch == 3: t.w * t.bps else: t.rowBytes
  let group = if t.cis and t.ch == 3: 3 else: 1
  let unit = inRow * group
  if unit == 0: return
  let n = src.len div unit
  let rb = t.rowBytes
  let start = t.data.len
  t.data.setLen(start + n * rb)
  if group == 1:
    if n > 0: copyMem(addr t.data[start], addr src[0], n * rb)
  else:
    let b = t.bps
    for r in 0 ..< n:
      let dst = start + r * rb
      for c in 0 ..< 3:
        let so = r * unit + c * inRow
        for x in 0 ..< t.w:
          let d = dst + (x * 3 + c) * b
          t.data[d] = src[so + x * b]
          if b == 2: t.data[d + 1] = src[so + x * b + 1]
  t.h += n
  if src.len > n * unit: t.pending = src[n * unit .. ^1]

#
# Opérations
#

proc crop(t: Trame, x, y, w, h: int): Trame =
  let x0 = clamp(x, 0, t.w)
  let y0 = clamp(y, 0, t.h)
  let x1 = clamp(x + w, x0, t.w)
  let y1 = clamp(y + h, y0, t.h)
  result = newTrame(x1 - x0, y1 - y0, t.ch, t.depth, t.dpi)
  let pb = t.ch * t.bps
  let rb = result.rowBytes
  if rb == 0: return
  for r in 0 ..< result.h:
    copyMem(addr result.data[r * rb], addr t.data[(y0 + r) * t.rowBytes + x0 * pb], rb)

proc resample1(src: seq[float32], n, m, stride, count: int): seq[float32] =
  ## Rééchantillonne `count` vecteurs de longueur n vers m (moyenne de surface
  ## pour une réduction, interpolation linéaire pour un agrandissement).
  result = newSeq[float32](m * count)
  if n == 0 or m == 0: return
  let scale = n / m
  for j in 0 ..< m:
    if scale >= 1.0:
      let a = j.float * scale
      let b = a + scale
      var i = int(a)
      while i.float < b and i < n:
        let lo = max(a, i.float)
        let hi = min(b, (i + 1).float)
        let wgt = float32((hi - lo) / scale)
        if wgt > 0:
          for k in 0 ..< count: result[j * count + k] += src[i * count + k] * wgt
        inc i
    else:
      let p = (j.float + 0.5) * scale - 0.5
      let i0 = clamp(int(floor(p)), 0, n - 1)
      let i1 = min(i0 + 1, n - 1)
      let f = float32(clamp(p - i0.float, 0.0, 1.0))
      for k in 0 ..< count:
        result[j * count + k] = src[i0 * count + k] * (1 - f) + src[i1 * count + k] * f

proc resize(t: Trame, nw, nh: int): Trame =
  result = newTrame(nw, nh, t.ch, t.depth, (if t.w > 0: t.dpi * nw.float / t.w.float else: t.dpi))
  if t.w == 0 or t.h == 0 or nw == 0 or nh == 0: return
  # horizontal, ligne par ligne
  var tmp = newSeq[float32](nw * t.h * t.ch)
  var row = newSeq[float32](t.w * t.ch)
  for y in 0 ..< t.h:
    for i in 0 ..< t.w * t.ch: row[i] = float32(t.get(y * t.w * t.ch + i))
    let r = resample1(row, t.w, nw, 1, t.ch)
    for i in 0 ..< nw * t.ch: tmp[y * nw * t.ch + i] = r[i]
  # vertical, les lignes entières comme vecteurs
  let rowLen = nw * t.ch
  let r = resample1(tmp, t.h, nh, 1, rowLen)
  for i in 0 ..< nw * nh * t.ch: result.put(i, int(round(r[i])))

proc to8(t: Trame): Trame =
  result = newTrame(t.w, t.h, t.ch, 8, t.dpi)
  if t.depth == 8:
    result.data = t.data
    return
  for i in 0 ..< t.w * t.h * t.ch:
    result.data[i] = chr((t.get(i) * 255 + 32767) div 65535)

proc to16(t: Trame): Trame =
  result = newTrame(t.w, t.h, t.ch, 16, t.dpi)
  if t.depth == 16:
    result.data = t.data
    return
  for i in 0 ..< t.w * t.h * t.ch: result.put(i, t.get(i) * 257)

proc gray(t: Trame): Trame =
  if t.ch == 1: return crop(t, 0, 0, t.w, t.h)
  result = newTrame(t.w, t.h, 1, t.depth, t.dpi)
  for p in 0 ..< t.w * t.h:
    let v = 0.299 * t.get(p * 3).float + 0.587 * t.get(p * 3 + 1).float + 0.114 * t.get(p * 3 + 2).float
    result.put(p, int(round(v)))

proc threshold(t: Trame, level: float): Trame =
  let g = gray(to8(t))
  result = newTrame(t.w, t.h, 1, 8, t.dpi)
  for p in 0 ..< t.w * t.h:
    result.data[p] = (if ord(g.data[p]).float >= level: '\xff' else: '\x00')

proc rotate(t: Trame, angle: int): Trame =
  let a = ((angle mod 360) + 360) mod 360
  if a notin [0, 90, 180, 270]: rtError("trame : rotation de 90, 180 ou 270 degrés")
  let (nw, nh) = if a in [90, 270]: (t.h, t.w) else: (t.w, t.h)
  result = newTrame(nw, nh, t.ch, t.depth, t.dpi)
  let pb = t.ch * t.bps
  for y in 0 ..< t.h:
    for x in 0 ..< t.w:
      let (nx, ny) = case a
        of 90: (t.h - 1 - y, x)
        of 180: (t.w - 1 - x, t.h - 1 - y)
        of 270: (y, t.w - 1 - x)
        else: (x, y)
      copyMem(addr result.data[(ny * nw + nx) * pb], addr t.data[(y * t.w + x) * pb], pb)

proc levels(t: Trame, gamma, brightness, contrast, black, white: float) =
  let mx = t.maxv
  var lut = newSeq[int](mx + 1)
  let f = (100.0 + clamp(contrast, -99.0, 99.0)) / (100.0 - clamp(contrast, -99.0, 99.0))
  let g = if gamma <= 0: 1.0 else: gamma
  for i in 0 .. mx:
    var v = i.float / mx.float
    v = (v - black) / max(white - black, 1e-6)
    v = clamp(v, 0.0, 1.0)
    v = pow(v, 1.0 / g)
    v = (v - 0.5) * f + 0.5 + brightness / 100.0
    lut[i] = int(round(clamp(v, 0.0, 1.0) * mx.float))
  for i in 0 ..< t.w * t.h * t.ch: t.put(i, lut[t.get(i)])

proc stats(t: Trame): LTable =
  result = newLTable()
  for c in 0 ..< t.ch:
    var mn = high(int)
    var mx = 0
    var s = 0.0
    for p in 0 ..< t.w * t.h:
      let v = t.get(p * t.ch + c)
      mn = min(mn, v); mx = max(mx, v); s += v.float
    let r = newLTable()
    r.set("min", intV(if t.w * t.h > 0: mn else: 0))
    r.set("max", intV(mx))
    r.set("moyenne", numV(if t.w * t.h > 0: s / float(t.w * t.h) else: 0.0))
    result.rawSet(c + 1, tableV(r))

#
# PNG
#

proc be32(x: int): string =
  result = newString(4)
  result[0] = chr((x shr 24) and 0xff); result[1] = chr((x shr 16) and 0xff)
  result[2] = chr((x shr 8) and 0xff); result[3] = chr(x and 0xff)

proc pngChunk(kind, data: string): string =
  result = be32(data.len) & kind & data
  result.add be32(int(crc32(kind & data)))

proc encodePng(t: Trame): string =
  let b = t.bps
  let rb = t.rowBytes
  var raw = newStringOfCap((rb + 1) * t.h)
  var prev = newString(rb)
  var cur = newString(rb)
  var cand: array[5, string]
  for k in 0 .. 4: cand[k] = newString(rb)
  let bpp = t.ch * b
  for y in 0 ..< t.h:
    # PNG : échantillons 16 bits en gros-boutiste
    if b == 1: copyMem(addr cur[0], unsafeAddr t.data[y * rb], rb)
    else:
      for i in 0 ..< rb div 2:
        cur[2 * i] = t.data[y * rb + 2 * i + 1]
        cur[2 * i + 1] = t.data[y * rb + 2 * i]
    var best = 0
    var bestCost = high(int)
    for f in 0 .. 4:
      var cost = 0
      for i in 0 ..< rb:
        let x = ord(cur[i])
        let a = if i >= bpp: ord(cur[i - bpp]) else: 0
        let up = if y > 0: ord(prev[i]) else: 0
        let c = if i >= bpp and y > 0: ord(prev[i - bpp]) else: 0
        let pred = case f
          of 0: 0
          of 1: a
          of 2: up
          of 3: (a + up) div 2
          else:
            let p = a + up - c
            let pa = abs(p - a)
            let pb = abs(p - up)
            let pc = abs(p - c)
            if pa <= pb and pa <= pc: a elif pb <= pc: up else: c
        let v = (x - pred) and 0xff
        cand[f][i] = chr(v)
        cost += (if v < 128: v else: 256 - v)
      if cost < bestCost: bestCost = cost; best = f
    raw.add chr(best)
    raw.add cand[best]
    swap(prev, cur)
  var ihdr = be32(t.w) & be32(t.h)
  ihdr.add chr(t.depth)
  ihdr.add chr(if t.ch == 1: 0 else: 2)
  ihdr.add "\x00\x00\x00"
  result = "\x89PNG\r\n\x1a\n" & pngChunk("IHDR", ihdr)
  if t.dpi > 0:
    let ppm = int(round(t.dpi / 0.0254))
    result.add pngChunk("pHYs", be32(ppm) & be32(ppm) & "\x01")
  result.add pngChunk("IDAT", zlibCompress2(raw, 6))
  result.add pngChunk("IEND", "")

#
# JPEG de base (DCT flottante AAN, tables de Huffman standard, 4:4:4)
#

const
  zigzag = [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48,
            41, 34, 27, 20, 13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23,
            30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63]
  qLuma = [16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40,
           57, 69, 56, 14, 17, 22, 29, 51, 87, 80, 62, 18, 22, 37, 56, 68, 109, 103, 77, 24, 35,
           55, 64, 81, 104, 113, 92, 49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112,
           100, 103, 99]
  qChroma = [17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99, 24, 26, 56, 99,
             99, 99, 99, 99, 47, 66, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
             99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
             99, 99]
  dcLumaBits = [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0]
  dcChromaBits = [0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0]
  dcVals = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
  acLumaBits = [0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7d]
  acLumaVals = [
    0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
    0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xa1, 0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0,
    0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28,
    0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
    0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
    0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
    0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
    0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5,
    0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2,
    0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
    0xf9, 0xfa]
  acChromaBits = [0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77]
  acChromaVals = [
    0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71,
    0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0,
    0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16, 0x24, 0x34, 0xe1, 0x25, 0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26,
    0x27, 0x28, 0x29, 0x2a, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
    0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
    0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
    0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5,
    0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3,
    0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda,
    0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
    0xf9, 0xfa]
  aan = [1.0, 1.387039845, 1.306562965, 1.175875602, 1.0, 0.785694958, 0.541196100, 0.275899379]

type
  HuffTable = object
    code: array[256, int]
    size: array[256, int]
  BitWriter = object
    buf: string
    acc: int
    n: int

proc buildHuff(bits: openArray[int], vals: openArray[int]): HuffTable =
  var code = 0
  var k = 0
  for l in 1 .. 16:
    for i in 0 ..< bits[l - 1]:
      result.code[vals[k]] = code
      result.size[vals[k]] = l
      inc code; inc k
    code = code shl 1

proc writeBits(w: var BitWriter, code, size: int) {.inline.} =
  w.acc = (w.acc shl size) or (code and ((1 shl size) - 1))
  w.n += size
  while w.n >= 8:
    let b = (w.acc shr (w.n - 8)) and 0xff
    w.buf.add chr(b)
    if b == 0xff: w.buf.add '\x00'
    w.n -= 8
  w.acc = w.acc and ((1 shl w.n) - 1)

proc flushBits(w: var BitWriter) =
  if w.n > 0: w.writeBits(0x7f, 8 - w.n)

proc category(v: int): int {.inline.} =
  var a = abs(v)
  while a > 0:
    inc result
    a = a shr 1

proc fdct(d: var array[64, float32]) =
  for pass in 0 .. 1:
    for i in 0 .. 7:
      let (o, s) = if pass == 0: (i * 8, 1) else: (i, 8)
      template at(k: int): untyped = d[o + k * s]
      let tmp0 = at(0) + at(7)
      let tmp7 = at(0) - at(7)
      let tmp1 = at(1) + at(6)
      let tmp6 = at(1) - at(6)
      let tmp2 = at(2) + at(5)
      let tmp5 = at(2) - at(5)
      let tmp3 = at(3) + at(4)
      let tmp4 = at(3) - at(4)
      var tmp10 = tmp0 + tmp3
      let tmp13 = tmp0 - tmp3
      var tmp11 = tmp1 + tmp2
      var tmp12 = tmp1 - tmp2
      at(0) = tmp10 + tmp11
      at(4) = tmp10 - tmp11
      let z1 = (tmp12 + tmp13) * 0.707106781'f32
      at(2) = tmp13 + z1
      at(6) = tmp13 - z1
      tmp10 = tmp4 + tmp5
      tmp11 = tmp5 + tmp6
      tmp12 = tmp6 + tmp7
      let z5 = (tmp10 - tmp12) * 0.382683433'f32
      let z2 = 0.541196100'f32 * tmp10 + z5
      let z4 = 1.306562965'f32 * tmp12 + z5
      let z3 = tmp11 * 0.707106781'f32
      let z11 = tmp7 + z3
      let z13 = tmp7 - z3
      at(5) = z13 + z2
      at(3) = z13 - z2
      at(1) = z11 + z4
      at(7) = z11 - z4

proc scaledQ(base: openArray[int], quality: int): array[64, int] =
  let q = clamp(quality, 1, 100)
  let scale = if q < 50: 5000 div q else: 200 - 2 * q
  for i in 0 ..< 64: result[i] = clamp((base[i] * scale + 50) div 100, 1, 255)

proc encodeJpeg(t0: Trame, quality: int): string =
  let t = to8(t0)
  let ncomp = t.ch
  let ql = scaledQ(qLuma, quality)
  let qc = scaledQ(qChroma, quality)
  var divL, divC: array[64, float32]
  for v in 0 .. 7:
    for u in 0 .. 7:
      let k = v * 8 + u
      divL[k] = float32(1.0 / (ql[k].float * aan[u] * aan[v] * 8.0))
      divC[k] = float32(1.0 / (qc[k].float * aan[u] * aan[v] * 8.0))
  let hdl = buildHuff(dcLumaBits, dcVals)
  let hal = buildHuff(acLumaBits, acLumaVals)
  let hdc = buildHuff(dcChromaBits, dcVals)
  let hac = buildHuff(acChromaBits, acChromaVals)
  # en-têtes
  var o = "\xff\xd8"
  let dens = int(round(if t.dpi > 0: t.dpi else: 72.0))
  o.add "\xff\xe0\x00\x10JFIF\x00\x01\x01\x01"
  o.add chr(dens shr 8); o.add chr(dens and 0xff); o.add chr(dens shr 8); o.add chr(dens and 0xff)
  o.add "\x00\x00"
  proc dqt(o: var string, id: int, q: array[64, int]) =
    o.add "\xff\xdb\x00\x43"; o.add chr(id)
    for k in 0 ..< 64: o.add chr(q[zigzag[k]])
  o.dqt(0, ql)
  if ncomp == 3: o.dqt(1, qc)
  o.add "\xff\xc0"
  let sofLen = 8 + 3 * ncomp
  o.add chr(sofLen shr 8); o.add chr(sofLen and 0xff); o.add '\x08'
  o.add chr(t.h shr 8); o.add chr(t.h and 0xff); o.add chr(t.w shr 8); o.add chr(t.w and 0xff)
  o.add chr(ncomp)
  for c in 0 ..< ncomp:
    o.add chr(c + 1); o.add '\x11'; o.add chr(if c == 0: 0 else: 1)
  proc dht(o: var string, cls, id: int, bits, vals: openArray[int]) =
    let n = 19 + vals.len
    o.add "\xff\xc4"; o.add chr(n shr 8); o.add chr(n and 0xff)
    o.add chr(cls * 16 + id)
    for b in bits: o.add chr(b)
    for v in vals: o.add chr(v)
  o.dht(0, 0, dcLumaBits, dcVals)
  o.dht(1, 0, acLumaBits, acLumaVals)
  if ncomp == 3:
    o.dht(0, 1, dcChromaBits, dcVals)
    o.dht(1, 1, acChromaBits, acChromaVals)
  let sosLen = 6 + 2 * ncomp
  o.add "\xff\xda"; o.add chr(sosLen shr 8); o.add chr(sosLen and 0xff); o.add chr(ncomp)
  for c in 0 ..< ncomp:
    o.add chr(c + 1); o.add chr(if c == 0: 0x00 else: 0x11)
  o.add "\x00\x3f\x00"
  # données
  var w = BitWriter(buf: newStringOfCap(t.w * t.h div 4))
  var prevDC: array[3, int]
  var blk: array[64, float32]
  let bw = (t.w + 7) div 8
  let bh = (t.h + 7) div 8
  for by in 0 ..< bh:
    for bx in 0 ..< bw:
      for c in 0 ..< ncomp:
        for y in 0 .. 7:
          let sy = min(by * 8 + y, t.h - 1)
          for x in 0 .. 7:
            let sx = min(bx * 8 + x, t.w - 1)
            let p = (sy * t.w + sx) * ncomp
            var v: float32
            if ncomp == 1: v = float32(ord(t.data[p])) - 128
            else:
              let r = float32(ord(t.data[p]))
              let g = float32(ord(t.data[p + 1]))
              let b = float32(ord(t.data[p + 2]))
              v = case c
                of 0: 0.299'f32 * r + 0.587'f32 * g + 0.114'f32 * b - 128
                of 1: -0.168736'f32 * r - 0.331264'f32 * g + 0.5'f32 * b
                else: 0.5'f32 * r - 0.418688'f32 * g - 0.081312'f32 * b
            blk[y * 8 + x] = v
        fdct(blk)
        let dv = if c == 0: divL else: divC
        var q: array[64, int]
        for k in 0 ..< 64: q[k] = int(round(blk[k] * dv[k]))
        let (hd, ha) = if c == 0: (hdl, hal) else: (hdc, hac)
        let diff = q[0] - prevDC[c]
        prevDC[c] = q[0]
        let cat = category(diff)
        w.writeBits(hd.code[cat], hd.size[cat])
        if cat > 0: w.writeBits(if diff < 0: diff - 1 else: diff, cat)
        var run = 0
        for k in 1 ..< 64:
          let v = q[zigzag[k]]
          if v == 0:
            inc run
          else:
            while run > 15:
              w.writeBits(ha.code[0xf0], ha.size[0xf0])
              run -= 16
            let ct = category(v)
            let sym = run * 16 + ct
            w.writeBits(ha.code[sym], ha.size[sym])
            w.writeBits(if v < 0: v - 1 else: v, ct)
            run = 0
        if run > 0: w.writeBits(ha.code[0], ha.size[0])
  w.flushBits()
  o.add w.buf
  o.add "\xff\xd9"
  o

#
# TIFF (non compressé) et PNM
#

proc le16(x: int): string = chr(x and 0xff) & chr((x shr 8) and 0xff)
proc le32(x: int): string = le16(x and 0xffff) & le16((x shr 16) and 0xffff)

proc encodeTiff(t: Trame): string =
  let dataLen = t.data.len
  let n = 12
  let ifdOff = 8
  let extra = ifdOff + 2 + n * 12 + 4
  let bpsOff = extra
  let resOff = bpsOff + 6
  let dataOff = resOff + 16
  proc entry(tag, typ, count, value: int): string =
    result = le16(tag) & le16(typ) & le32(count)
    if typ == 3 and count == 1: result.add le16(value) & "\x00\x00"
    else: result.add le32(value)
  var o = "II*\x00" & le32(ifdOff) & le16(n)
  o.add entry(256, 4, 1, t.w)
  o.add entry(257, 4, 1, t.h)
  o.add(if t.ch == 1: entry(258, 3, 1, t.depth) else: entry(258, 3, 3, bpsOff))
  o.add entry(259, 3, 1, 1)
  o.add entry(262, 3, 1, if t.ch == 1: 1 else: 2)
  o.add entry(273, 4, 1, dataOff)
  o.add entry(277, 3, 1, t.ch)
  o.add entry(278, 4, 1, t.h)
  o.add entry(279, 4, 1, dataLen)
  o.add entry(282, 5, 1, resOff)
  o.add entry(283, 5, 1, resOff + 8)
  o.add entry(296, 3, 1, 2)
  o.add le32(0)
  o.add le16(t.depth) & le16(t.depth) & le16(t.depth)
  let d = int(round(if t.dpi > 0: t.dpi * 100 else: 7200))
  o.add le32(d) & le32(100) & le32(d) & le32(100)
  o.add t.data
  o

proc encodePnm(t: Trame): string =
  result = (if t.ch == 1: "P5\n" else: "P6\n") & $t.w & " " & $t.h & "\n" & $t.maxv & "\n"
  if t.depth == 8: result.add t.data
  else:
    for i in 0 ..< t.data.len div 2:
      result.add t.data[2 * i + 1]; result.add t.data[2 * i]

#
# PDF (une image par page)
#

proc encodePdf(pages: seq[Trame], quality: int, lossless: bool): string =
  var objs: seq[string]
  var kids: seq[int]
  # 1 catalogue, 2 pages, puis 3 objets par page
  for i, t in pages:
    let pageId = 3 + i * 3
    kids.add pageId
  for i, t0 in pages:
    let t = to8(t0)
    let dpi = if t.dpi > 0: t.dpi else: 300.0
    let wpt = t.w.float * 72.0 / dpi
    let hpt = t.h.float * 72.0 / dpi
    let pageId = 3 + i * 3
    let contId = pageId + 1
    let imgId = pageId + 2
    let f = formatFloat(wpt, ffDecimal, 3)
    let g = formatFloat(hpt, ffDecimal, 3)
    objs.add "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " & f & " " & g & "] /Resources << /XObject << /Im0 " &
             $imgId & " 0 R >> >> /Contents " & $contId & " 0 R >>"
    let content = "q " & f & " 0 0 " & g & " 0 0 cm /Im0 Do Q"
    objs.add "<< /Length " & $content.len & " >>\nstream\n" & content & "\nendstream"
    let cs = if t.ch == 1: "/DeviceGray" else: "/DeviceRGB"
    var img, filt: string
    if lossless:
      img = zlibCompress2(t.data, 6); filt = "/FlateDecode"
    else:
      img = encodeJpeg(t, quality); filt = "/DCTDecode"
    objs.add "<< /Type /XObject /Subtype /Image /Width " & $t.w & " /Height " & $t.h &
             " /ColorSpace " & cs & " /BitsPerComponent 8 /Filter " & filt & " /Length " & $img.len &
             " >>\nstream\n" & img & "\nendstream"
  var all = @["<< /Type /Catalog /Pages 2 0 R >>"]
  var k = "<< /Type /Pages /Count " & $pages.len & " /Kids ["
  for id in kids: k.add $id & " 0 R "
  k.add "] >>"
  all.add k
  all.add objs
  result = "%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"
  var offsets: seq[int]
  for i, ob in all:
    offsets.add result.len
    result.add $(i + 1) & " 0 obj\n" & ob & "\nendobj\n"
  let xref = result.len
  result.add "xref\n0 " & $(all.len + 1) & "\n0000000000 65535 f \n"
  for off in offsets: result.add align($off, 10, '0') & " 00000 n \n"
  result.add "trailer\n<< /Size " & $(all.len + 1) & " /Root 1 0 R >>\nstartxref\n" & $xref & "\n%%EOF\n"

proc save(t: Trame, path: string, quality: int, lossless: bool) =
  let ext = path.splitFile.ext.toLowerAscii
  let data = case ext
    of ".png": encodePng(t)
    of ".jpg", ".jpeg": encodeJpeg(t, quality)
    of ".tif", ".tiff": encodeTiff(t)
    of ".pnm", ".ppm", ".pgm": encodePnm(t)
    of ".pdf": encodePdf(@[t], quality, lossless)
    else: rtError("trame : format inconnu « " & ext & " » (png, jpg, tif, pnm, pdf)")
  try: writeFile(path, data)
  except IOError as e: rtError("trame : écriture de " & path & " : " & e.msg)

#
# Mire et capteur simulé (essais d'un pilote sans matériel)
#

proc testChart(w, h: int, dpi: float): Trame =
  ## Mire : fond papier, bandes de couleurs, dégradé de gris, cercles, grille,
  ## blocs de « texte ».
  result = newTrame(w, h, 3, 8, dpi)
  let mm = dpi / 25.4
  for y in 0 ..< h:
    for x in 0 ..< w:
      var r, g, b: float
      r = 245; g = 243; b = 236                          # papier
      let fx = x.float / w.float
      let fy = y.float / h.float
      if fy > 0.06 and fy < 0.16:                        # bandes de couleurs
        let k = int(fx * 8)
        let cols = [(230.0, 40.0, 40.0), (240.0, 150.0, 30.0), (240.0, 220.0, 40.0), (60.0, 170.0, 70.0),
                    (40.0, 170.0, 200.0), (40.0, 70.0, 190.0), (130.0, 60.0, 160.0), (30.0, 30.0, 30.0)]
        (r, g, b) = cols[min(k, 7)]
      elif fy > 0.18 and fy < 0.24:                      # dégradé de gris
        let v = 255 * (1 - fx)
        r = v; g = v; b = v
      else:
        let cx = 0.5 * w.float
        let cy = 0.5 * h.float
        let d = sqrt((x.float - cx) ^ 2 + (y.float - cy) ^ 2) / mm
        if d < 60 and int(d / 4) mod 2 == 0:             # cercles concentriques
          r = 200 - d; g = 60 + d * 2; b = 90 + d
        if fy > 0.72 and fy < 0.92 and fx > 0.08 and fx < 0.92:   # lignes de texte
          let line = int((y.float / mm - 0.72 * h.float / mm) / 6)
          let ly = (y.float / mm - 0.72 * h.float / mm) - line.float * 6
          let word = int(x.float / mm / 7 + line.float * 1.7)
          if ly > 1.5 and ly < 4.0 and (word mod 5) != 4 and int(x.float / mm * 1.3) mod 2 == 0:
            r = 25; g = 25; b = 30
      if (x.float / mm) mod 20.0 < 0.25 or (y.float / mm) mod 20.0 < 0.25:  # grille de 2 cm
        r *= 0.8; g *= 0.85; b *= 0.95
      let p = (y * w + x) * 3
      result.data[p] = chr(clamp(int(r), 0, 255))
      result.data[p + 1] = chr(clamp(int(g), 0, 255))
      result.data[p + 2] = chr(clamp(int(b), 0, 255))

proc sensorLine(src: Trame, o: LTable): string =
  ## Une ligne lue par un capteur simulé (voir la documentation de t:capter).
  let x0 = optField(o, "x", 0.0)            # pouces
  let y = optField(o, "y", 0.0)             # pouces
  let n = optField(o, "pixels", 0)
  let xres = optField(o, "resolution", 300.0)
  let canal = optField(o, "canal", -1)       # 0, 1, 2 ; -1 : somme des trois (gris)
  let depth = optField(o, "profondeur", 16)
  let lampe = optField(o, "lampe", true)
  let gain = optField(o, "gain", 1.0)
  let noir = optField(o, "noir", 0.03)
  let bruit = optField(o, "bruit", 0.004)
  let vign = optField(o, "vignetage", 0.15)
  let ombrage = optField(o, "ombrage", "")   # 4 octets par pixel : noir, gain (petit-boutiste)
  let coeff = optField(o, "coefficient", 0x4000)
  let gamma = optField(o, "gamma", "")       # 256 mots de 16 bits par canal (R, G, B à la suite)
  let decalage = optField(o, "decalage", 0.0)  # pouces : position du document sous la vitre
  result = newString(n * (depth div 8))
  var rng = initRand(int(y * 100003.0) + canal * 7919 + n)
  for i in 0 ..< n:
    let x = x0 + i.float / xres
    var refl: float
    let yd = y - decalage
    if yd < 0 or yd * src.dpi >= src.h.float:
      refl = if yd < 0: 0.93 else: 0.95       # bande blanche d'étalonnage / capot blanc
    else:
      let sx = clamp(int(x * src.dpi), 0, src.w - 1)
      let sy = clamp(int(yd * src.dpi), 0, src.h - 1)
      let p = (sy * src.w + sx) * src.ch
      if canal < 0 or src.ch == 1:
        var s = 0.0
        for c in 0 ..< src.ch: s += src.get(p + c).float
        refl = s / (src.ch.float * src.maxv.float)
      else:
        refl = src.get(p + canal).float / src.maxv.float
    # sensibilité propre à chaque pixel du capteur CIS
    let sens = 1.0 - vign * (0.5 + 0.5 * cos(x * 2.1)) - 0.03 * sin(x * 37.0)
    var v = if lampe: refl * sens * gain else: 0.0
    v += noir + bruit * (rng.rand(2.0) - 1.0)
    var code = clamp(int(v * 65535), 0, 65535)
    if ombrage.len >= (i + 1) * 4:
      let dk = ord(ombrage[i * 4]) or (ord(ombrage[i * 4 + 1]) shl 8)
      let gn = ord(ombrage[i * 4 + 2]) or (ord(ombrage[i * 4 + 3]) shl 8)
      code = clamp((code - dk) * gn div coeff, 0, 65535)
    if depth == 8:
      if gamma.len >= 512 * (max(canal, 0) + 1):
        let off = max(canal, 0) * 512
        let k = code shr 8
        let gv = ord(gamma[off + 2 * k]) or (ord(gamma[off + 2 * k + 1]) shl 8)
        result[i] = chr(gv shr 8)
      else:
        result[i] = chr(code shr 8)
    else:
      result[2 * i] = chr(code and 0xff)
      result[2 * i + 1] = chr(code shr 8)

#
# Statistiques sur des mots de 16 bits (étalonnage)
#

proc words(s: string): seq[int] =
  result = newSeq[int](s.len div 2)
  for i in 0 ..< result.len: result[i] = ord(s[2 * i]) or (ord(s[2 * i + 1]) shl 8)

proc openTrame(L: Interp): Value =
  let tm = newLib()
  tm.fn "largeur", proc (L: Interp, a: seq[Value]): seq[Value] = @[intV(L.checkT(a, "largeur").w)]
  tm.fn "hauteur", proc (L: Interp, a: seq[Value]): seq[Value] = @[intV(L.checkT(a, "hauteur").h)]
  tm.fn "canaux", proc (L: Interp, a: seq[Value]): seq[Value] = @[intV(L.checkT(a, "canaux").ch)]
  tm.fn "profondeur", proc (L: Interp, a: seq[Value]): seq[Value] = @[intV(L.checkT(a, "profondeur").depth)]
  tm.fn "dpi", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkT(a, "dpi")
    if arg(a, 2).kind != vkNil: t.dpi = L.checkNum(a, 2, "dpi")
    @[numV(t.dpi)]
  tm.fn "octets", proc (L: Interp, a: seq[Value]): seq[Value] = @[strV(L.checkT(a, "octets").data)]
  tm.fn "ajouter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkT(a, "ajouter")
    let d = L.checkStr(a, 2, "ajouter")
    L.blocking:
      t.appendRows(d)
    @[intV(t.h)]
  tm.fn "copier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkT(a, "copier")
    @[L.wrap(crop(t, 0, 0, t.w, t.h), "trame", tm)]
  tm.fn "recadrer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkT(a, "recadrer")
    let x = int(L.checkInt(a, 2, "recadrer"))
    let y = int(L.checkInt(a, 3, "recadrer"))
    let w = int(L.checkInt(a, 4, "recadrer"))
    let h = int(L.checkInt(a, 5, "recadrer"))
    var r: Trame
    L.blocking:
      r = crop(t, x, y, w, h)
    @[L.wrap(r, "trame", tm)]
  tm.fn "redimensionner", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkT(a, "redimensionner")
    var w = int(L.optInt(a, 2, "redimensionner", 0))
    var h = int(L.optInt(a, 3, "redimensionner", 0))
    if w <= 0 and h <= 0: rtError("trame : redimensionner : largeur ou hauteur attendue")
    if w <= 0: w = max(1, int(round(t.w.float * h.float / max(t.h, 1).float)))
    if h <= 0: h = max(1, int(round(t.h.float * w.float / max(t.w, 1).float)))
    var r: Trame
    L.blocking:
      r = resize(t, w, h)
    @[L.wrap(r, "trame", tm)]
  tm.fn "en8bits", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkT(a, "en8bits")
    var r: Trame
    L.blocking:
      r = to8(t)
    @[L.wrap(r, "trame", tm)]
  tm.fn "en16bits", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkT(a, "en16bits")
    var r: Trame
    L.blocking:
      r = to16(t)
    @[L.wrap(r, "trame", tm)]
  tm.fn "gris", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkT(a, "gris")
    var r: Trame
    L.blocking:
      r = gray(t)
    @[L.wrap(r, "trame", tm)]
  tm.fn "trait", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkT(a, "trait")
    let s = L.optNum(a, 2, "trait", 128)
    var r: Trame
    L.blocking:
      r = threshold(t, s)
    @[L.wrap(r, "trame", tm)]
  tm.fn "pivoter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkT(a, "pivoter")
    let ang = int(L.checkInt(a, 2, "pivoter"))
    var r: Trame
    L.blocking:
      r = rotate(t, ang)
    @[L.wrap(r, "trame", tm)]
  tm.fn "niveaux", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkT(a, "niveaux")
    let o = if arg(a, 2).kind == vkTable: a[1].t else: nil
    let g = optField(o, "gamma", 1.0)
    let b = optField(o, "luminosite", 0.0)
    let c = optField(o, "contraste", 0.0)
    let bk = optField(o, "noir", 0.0)
    let wh = optField(o, "blanc", 1.0)
    L.blocking:
      t.levels(g, b, c, bk, wh)
    @[a[0]]
  tm.fn "statistiques", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkT(a, "statistiques")
    var r: LTable
    L.blocking:
      r = stats(t)
    @[tableV(r)]
  tm.fn "pixel", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkT(a, "pixel")
    let x = int(L.checkInt(a, 2, "pixel"))
    let y = int(L.checkInt(a, 3, "pixel"))
    if x < 0 or y < 0 or x >= t.w or y >= t.h: return @[nilV()]
    let r = newLTable()
    for c in 0 ..< t.ch: r.rawSet(c + 1, intV(t.get((y * t.w + x) * t.ch + c)))
    @[tableV(r)]
  tm.fn "enregistrer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkT(a, "enregistrer")
    let path = L.checkStr(a, 2, "enregistrer")
    let o = if arg(a, 3).kind == vkTable: a[2].t else: nil
    let q = optField(o, "qualite", 88)
    let ll = optField(o, "sansperte", false)
    if o != nil and field(o, "dpi").kind != vkNil: t.dpi = optField(o, "dpi", t.dpi)
    L.blocking:
      t.save(path, q, ll)
    @[intV(int(getFileSize(path)))]
  tm.fn "capter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkT(a, "capter")
    let o = L.checkTable(a, 2, "capter")
    var r: string
    L.blocking:
      r = sensorLine(t, o)
    @[strV(r)]
  discard L.userMeta("trame", tm)

  let m = newLib()
  m.fn "nouvelle", proc (L: Interp, a: seq[Value]): seq[Value] =
    let w = int(L.checkInt(a, 1, "nouvelle"))
    let h = int(L.checkInt(a, 2, "nouvelle"))
    let ch = int(L.optInt(a, 3, "nouvelle", 3))
    let d = int(L.optInt(a, 4, "nouvelle", 8))
    let o = if arg(a, 5).kind == vkTable: a[4].t else: nil
    let t = newTrame(w, h, ch, d, optField(o, "dpi", 0.0))
    t.cis = optField(o, "cis", false)
    let fill = optField(o, "valeur", -1)
    if fill >= 0:
      for i in 0 ..< w * h * ch: t.put(i, fill)
    @[L.wrap(t, "trame", tm)]
  m.fn "depuisoctets", proc (L: Interp, a: seq[Value]): seq[Value] =
    let d = L.checkStr(a, 1, "depuisoctets")
    let w = int(L.checkInt(a, 2, "depuisoctets"))
    let ch = int(L.optInt(a, 4, "depuisoctets", 3))
    let dep = int(L.optInt(a, 5, "depuisoctets", 8))
    let o = if arg(a, 6).kind == vkTable: a[5].t else: nil
    let t = newTrame(w, 0, ch, dep, optField(o, "dpi", 0.0))
    t.cis = optField(o, "cis", false)
    L.blocking:
      t.appendRows(d)
    if arg(a, 3).kind != vkNil:
      let h = int(L.checkInt(a, 3, "depuisoctets"))
      if h != t.h: rtError("trame : depuisoctets : " & $t.h & " lignes complètes au lieu de " & $h)
    @[L.wrap(t, "trame", tm)]
  m.fn "mire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let w = int(L.checkInt(a, 1, "mire"))
    let h = int(L.checkInt(a, 2, "mire"))
    let dpi = L.optNum(a, 3, "mire", 100)
    var t: Trame
    L.blocking:
      t = testChart(w, h, dpi)
    @[L.wrap(t, "trame", tm)]
  m.fn "pdf", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.checkStr(a, 1, "pdf")
    let lst = L.checkTable(a, 2, "pdf")
    let o = if arg(a, 3).kind == vkTable: a[2].t else: nil
    var pages: seq[Trame]
    for i in 1 .. lst.rawLen:
      let v = lst.rawGet(i)
      if v.kind != vkUser or not (v.u of Trame): rtError("trame : pdf : liste de trames attendue")
      pages.add Trame(v.u)
    if pages.len == 0: rtError("trame : pdf : aucune page")
    let q = optField(o, "qualite", 85)
    let ll = optField(o, "sansperte", false)
    var data: string
    L.blocking:
      data = encodePdf(pages, q, ll)
    try: writeFile(path, data)
    except IOError as e: rtError("trame : pdf : " & e.msg)
    @[intV(data.len)]
  m.fn "mediane16", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## mediane16(octets, lignes, elements, [centile=0.5]) : valeur choisie par colonne
    let d = L.checkStr(a, 1, "mediane16")
    let lines = int(L.checkInt(a, 2, "mediane16"))
    let elems = int(L.checkInt(a, 3, "mediane16"))
    let pc = L.optNum(a, 4, "mediane16", 0.5)
    if lines < 1 or elems < 1 or d.len < lines * elems * 2:
      rtError("trame : mediane16 : données trop courtes (" & $d.len & " octets pour " &
              $lines & " × " & $elems & " mots)")
    var res = newSeq[int](elems)
    L.blocking:
      let w = words(d)
      let sel = min(int(lines.float * pc), lines - 1)
      var col = newSeq[int](lines)
      for x in 0 ..< elems:
        for y in 0 ..< lines: col[y] = w[y * elems + x]
        col.sort()
        res[x] = col[sel]
    let r = newLTable(elems)
    for i, v in res: r.rawSet(i + 1, intV(v))
    @[tableV(r)]
  m.fn "moyennes16", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## moyennes16(octets, segments) : moyenne de chacun des segments consécutifs
    let d = L.checkStr(a, 1, "moyennes16")
    let segs = int(L.optInt(a, 2, "moyennes16", 1))
    let w = words(d)
    if segs < 1 or w.len < segs: rtError("trame : moyennes16 : données insuffisantes")
    let n = w.len div segs
    let r = newLTable()
    for s in 0 ..< segs:
      var t = 0.0
      for i in 0 ..< n: t += w[s * n + i].float
      r.rawSet(s + 1, numV(t / n.float))
    @[tableV(r)]
  tableV(m)

registerPackage PackageDef(name: "trame", open: openTrame,
  description: "Images matricielles 8 / 16 bits (scanner, capteur) : assemblage, retouches, PNG, JPEG, TIFF, PDF",
  docs: docs("trame", [
    "trame.nouvelle(largeur, hauteur, [canaux=3, profondeur=8, {dpi=, cis=, valeur=}])", "Nouvelle image (canaux 1 ou 3, profondeur 8 ou 16 bits). hauteur 0 et cis = vrai : image à remplir par t:ajouter avec des lignes séparées R, G, B (capteur CIS).",
    "trame.depuisoctets(octets, largeur, [hauteur, canaux=3, profondeur=8, {dpi=, cis=}])", "Image à partir de données brutes (lignes, canaux entrelacés, 16 bits petit-boutistes ; cis : une ligne par canal).",
    "trame.mire(largeur, hauteur, [dpi=100])", "Mire de test en couleurs (bandes, dégradé, cercles, grille de 2 cm, lignes de texte).",
    "trame.pdf(chemin, {trames}, [{qualite=85, sansperte=faux}])", "PDF d'une page par image (taille selon le dpi de chaque image) ; JPEG, ou Flate avec sansperte.",
    "trame.mediane16(octets, lignes, elements, [centile=0.5])", "Pour des mots de 16 bits rangés en lignes : la valeur au centile de chaque colonne (moyenne robuste d'étalonnage).",
    "trame.moyennes16(octets, [segments=1])", "Moyenne des mots de 16 bits de chacun des segments consécutifs (ex. lignes R, G, B).",
    "t:largeur()", "Largeur en pixels.",
    "t:hauteur()", "Hauteur en pixels.",
    "t:canaux()", "1 (gris) ou 3 (RGB).",
    "t:profondeur()", "8 ou 16 bits.",
    "t:dpi([valeur])", "Résolution enregistrée dans les fichiers (la change si valeur est donnée).",
    "t:octets()", "Données brutes.",
    "t:ajouter(octets)", "Ajoute des lignes complètes (les octets d'une ligne incomplète sont gardés pour l'appel suivant) ; renvoie la hauteur.",
    "t:copier()", "Copie.",
    "t:recadrer(x, y, largeur, hauteur)", "Nouvelle image : la zone donnée (pixels).",
    "t:redimensionner(largeur, [hauteur])", "Nouvelle image mise à l'échelle (moyenne de surface en réduction, interpolation linéaire en agrandissement) ; une dimension à 0 garde les proportions.",
    "t:en8bits()", "Nouvelle image en 8 bits.",
    "t:en16bits()", "Nouvelle image en 16 bits.",
    "t:gris()", "Nouvelle image en niveaux de gris (luminance).",
    "t:trait([seuil=128])", "Nouvelle image noir et blanc (0 / 255).",
    "t:pivoter(angle)", "Nouvelle image tournée de 90, 180 ou 270 degrés (sens horaire).",
    "t:niveaux({gamma=1, luminosite=0, contraste=0, noir=0, blanc=1})", "Corrige l'image sur place : noir et blanc (fractions), gamma, contraste et luminosité (-100 à 100).",
    "t:statistiques()", "Par canal : {min, max, moyenne}.",
    "t:pixel(x, y)", "Valeurs des canaux d'un pixel.",
    "t:enregistrer(chemin, [{qualite=88, dpi=, sansperte=}])", "Enregistre selon l'extension : .png (8 / 16 bits), .jpg (qualité 1 à 100), .tif (non compressé, 8 / 16 bits), .pnm / .ppm / .pgm, .pdf ; renvoie la taille du fichier.",
    "t:capter({x=, y=, pixels=, resolution=, canal=, profondeur=16, lampe=vrai, gain=1, noir=0.03, bruit=0.004, decalage=0, vignetage=0.15, ombrage=, coefficient=0x4000, gamma=})", "Simulation d'un capteur de scanner lisant l'image comme un document posé sur la vitre : une ligne de pixels (16 ou 8 bits) à la position y (pouces), avec sensibilité inégale des pixels, courant d'obscurité, bruit, correction d'ombrage (4 octets par pixel : noir, gain) et table gamma comme le ferait le circuit du scanner. Sert à essayer un pilote sans le matériel."]))
