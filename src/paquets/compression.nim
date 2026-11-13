# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - compression et archives en Nim pur (aucune bibliothèque C) :
#   utilisées par les paquets « archive » et « document », donc aussi par les
#   applications générées.
#
#   deflate(données, niveau)        flux deflate brut (RFC 1951) : LZ77 à chaînes de
#                                   hachage, correspondances paresseuses, blocs à codes
#                                   de Huffman dynamiques, fixes ou stockés (le plus court)
#   inflate(données)                décompression rapide (tables de décodage)
#   gzipCompress / gzipDecompress   RFC 1952 (plusieurs membres acceptés)
#   zlibCompress2 / zlibDecompress2 RFC 1950
#   crc32 / adler32
#   ZipReader / ZipWriter           archives .zip (UTF-8, Zip64, attributs Unix)
#   tarRead / tarWrite              archives .tar (ustar, noms longs GNU et pax)

import std/[strutils, times]

type CompressionError* = object of CatchableError

proc cerr(msg: string) {.noreturn.} =
  raise newException(CompressionError, msg)


#
# sommes
#

var crcTab: array[256, uint32]
block:
  for i in 0 ..< 256:
    var c = uint32(i)
    for _ in 0 ..< 8:
      c = if (c and 1) != 0: 0xEDB88320'u32 xor (c shr 1) else: c shr 1
    crcTab[i] = c

proc crc32Update*(crc: uint32, data: openArray[char]): uint32 =
  var c = not crc
  {.cast(gcsafe).}:
    for ch in data: c = crcTab[int((c xor uint32(ord(ch))) and 0xFF)] xor (c shr 8)
  not c

proc crc32*(data: string): uint32 = crc32Update(0, data)

proc adler32*(data: string): uint32 =
  var a = 1'u32
  var b = 0'u32
  var i = 0
  while i < data.len:
    let n = min(5552, data.len - i)
    for k in i ..< i + n:
      a += uint32(ord(data[k]))
      b += a
    a = a mod 65521
    b = b mod 65521
    i += n
  (b shl 16) or a

# tables deflate

const
  LenBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59,
             67, 83, 99, 115, 131, 163, 195, 227, 258]
  LenExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
  DistBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
              1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
  DistExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10,
               11, 11, 12, 12, 13, 13]
  ClOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

var lenCode: array[259, uint8]     # longueur (3..258) -> indice dans LenBase
var distCodeLo: array[512, uint8]  # distance-1 < 512, puis (distance-1) shr 7
block:
  for li in 0 ..< LenBase.len:
    let hi = if li + 1 < LenBase.len: LenBase[li + 1] - 1 else: 258
    for l in LenBase[li] .. min(hi, 258): lenCode[l] = uint8(li)
  lenCode[258] = 28
  for di in 0 ..< DistBase.len:
    let hi = if di + 1 < DistBase.len: DistBase[di + 1] - 1 else: 32768
    for d in DistBase[di] .. hi:
      let x = d - 1
      if x < 256: distCodeLo[x] = uint8(di)
      else: distCodeLo[256 + (x shr 7)] = uint8(di)

proc distCode(d: int): int {.inline.} =
  {.cast(gcsafe).}:
    let x = d - 1
    if x < 256: int(distCodeLo[x]) else: int(distCodeLo[256 + (x shr 7)])

proc lenSym(l: int): int {.inline.} =
  {.cast(gcsafe).}: int(lenCode[l])

# écriture de bits

type BitOut = object
  buf: string
  acc: uint64
  n: int

proc put(w: var BitOut, v: uint64, count: int) {.inline.} =
  w.acc = w.acc or (v shl w.n)
  w.n += count
  while w.n >= 8:
    w.buf.add char(w.acc and 0xFF)
    w.acc = w.acc shr 8
    w.n -= 8

proc alignByte(w: var BitOut) =
  if w.n > 0:
    w.buf.add char(w.acc and 0xFF)
    w.acc = 0
    w.n = 0

proc reverseBits(code, len: int): int {.inline.} =
  var c = code
  for _ in 0 ..< len:
    result = (result shl 1) or (c and 1)
    c = c shr 1

#
# Huffman
#

proc huffLengths(freq: openArray[int], limit: int): seq[int] =
  ## Longueurs de codes de Huffman limitées à `limit` bits (fréquences réduites
  ## de moitié tant que l'arbre est trop profond).
  result = newSeq[int](freq.len)
  var f = newSeq[int](freq.len)
  for i, x in freq: f[i] = x
  while true:
    var used: seq[int]
    for i, x in f:
      if x > 0: used.add i
    for i in 0 ..< result.len: result[i] = 0
    if used.len == 0: return
    if used.len == 1:
      result[used[0]] = 1
      return
    # nœuds : poids, parent ; feuilles 0..used.len-1
    var weight = newSeq[int]()
    var parent = newSeq[int]()
    for s in used:
      weight.add f[s]
      parent.add -1
    var active = newSeq[int]()
    for i in 0 ..< used.len: active.add i
    while active.len > 1:
      # deux plus petits poids (balayage linéaire : au plus 286 symboles)
      var a = -1
      var b = -1
      for k, node in active:
        if a < 0 or weight[node] < weight[active[a]]:
          b = a
          a = k
        elif b < 0 or weight[node] < weight[active[b]]:
          b = k
      let na = active[a]
      let nb = active[b]
      let nn = weight.len
      weight.add weight[na] + weight[nb]
      parent.add -1
      parent[na] = nn
      parent[nb] = nn
      let hiK = max(a, b)
      let loK = min(a, b)
      active.delete(hiK)
      active.delete(loK)
      active.add nn
    var maxLen = 0
    for i, s in used:
      var d = 0
      var p = parent[i]
      while p >= 0:
        inc d
        p = parent[p]
      result[s] = d
      maxLen = max(maxLen, d)
    if maxLen <= limit: return
    for i in 0 ..< f.len:
      if f[i] > 0: f[i] = max(1, f[i] div 2)

proc canonicalCodes(lengths: openArray[int]): seq[int] =
  ## Codes canoniques, déjà renversés (bits de poids faible d'abord).
  result = newSeq[int](lengths.len)
  var blCount: array[16, int]
  for l in lengths:
    if l > 0: inc blCount[l]
  var next: array[16, int]
  var code = 0
  for bits in 1 .. 15:
    code = (code + blCount[bits - 1]) shl 1
    next[bits] = code
  for s, l in lengths:
    if l > 0:
      result[s] = reverseBits(next[l], l)
      inc next[l]

#
# compression
#

type
  Params = tuple[good, lazy, nice, chain: int]

const LevelParams: array[10, Params] = [
  (0, 0, 0, 0), (4, 0, 8, 4), (4, 0, 16, 8), (4, 0, 32, 32),
  (4, 4, 16, 16), (8, 16, 32, 32), (8, 16, 128, 128), (8, 32, 128, 256),
  (32, 128, 258, 1024), (32, 258, 258, 4096)]

const
  WSize = 32768
  WMask = WSize - 1
  HBits = 15
  HSize = 1 shl HBits
  MaxSyms = 16384 * 2

type Deflater = object
  w: BitOut
  litlen: seq[uint16]     # symbole 0..255 littéral, sinon longueur
  dists: seq[uint16]      # 0 : littéral
  blockStart: int

var fixedLitLen, fixedDistLen: seq[int]
var fixedLitCodes, fixedDistCodes: seq[int]
block:
  fixedLitLen = newSeq[int](288)
  for i in 0 ..< 288: fixedLitLen[i] = (if i < 144: 8 elif i < 256: 9 elif i < 280: 7 else: 8)
  fixedDistLen = newSeq[int](30)
  for i in 0 ..< 30: fixedDistLen[i] = 5
  fixedLitCodes = canonicalCodes(fixedLitLen)
  fixedDistCodes = canonicalCodes(fixedDistLen)

proc emitSymbols(d: var Deflater, ll, dl, lc, dc: openArray[int]) =
  for i in 0 ..< d.litlen.len:
    let dist = int(d.dists[i])
    if dist == 0:
      let s = int(d.litlen[i])
      d.w.put(uint64(lc[s]), ll[s])
    else:
      let length = int(d.litlen[i])
      let li = lenSym(length)
      d.w.put(uint64(lc[257 + li]), ll[257 + li])
      if LenExtra[li] > 0: d.w.put(uint64(length - LenBase[li]), LenExtra[li])
      let di = distCode(dist)
      d.w.put(uint64(dc[di]), dl[di])
      if DistExtra[di] > 0: d.w.put(uint64(dist - DistBase[di]), DistExtra[di])
  d.w.put(uint64(lc[256]), ll[256])

proc flushBlock(d: var Deflater, data: string, blockEnd: int, final: bool, stored = false) =
  var lf = newSeq[int](286)
  var df = newSeq[int](30)
  for i in 0 ..< d.litlen.len:
    if d.dists[i] == 0: inc lf[int(d.litlen[i])]
    else:
      inc lf[257 + lenSym(int(d.litlen[i]))]
      inc df[distCode(int(d.dists[i]))]
  lf[256] = 1
  var ll = huffLengths(lf, 15)
  var dl = huffLengths(df, 15)
  # au moins deux codes par arbre (certains décodeurs refusent un arbre à un code).
  proc atLeastTwo(l: var seq[int]) =
    var n = 0
    for x in l:
      if x > 0: inc n
    if n < 2:
      var k = 0
      while n < 2 and k < l.len:
        if l[k] == 0:
          l[k] = 1
          inc n
        inc k
      for i in 0 ..< l.len:
        if l[i] > 0: l[i] = 1
  atLeastTwo(dl)
  atLeastTwo(ll)
  var hlit = 286
  while hlit > 257 and ll[hlit - 1] == 0: dec hlit
  var hdist = 30
  while hdist > 1 and dl[hdist - 1] == 0: dec hdist
  # longueurs codées (RLE 16/17/18)
  var all: seq[int]
  for i in 0 ..< hlit: all.add ll[i]
  for i in 0 ..< hdist: all.add dl[i]
  var clSyms: seq[(int, int)]      # (symbole, extra)
  var i = 0
  while i < all.len:
    let v = all[i]
    var run = 1
    while i + run < all.len and all[i + run] == v: inc run
    if v == 0:
      var r = run
      while r >= 11:
        let n = min(r, 138)
        clSyms.add (18, n - 11)
        r -= n
      while r >= 3:
        let n = min(r, 10)
        clSyms.add (17, n - 3)
        r -= n
      for _ in 0 ..< r: clSyms.add (0, 0)
    else:
      clSyms.add (v, 0)
      var r = run - 1
      while r >= 3:
        let n = min(r, 6)
        clSyms.add (16, n - 3)
        r -= n
      for _ in 0 ..< r: clSyms.add (v, 0)
    i += run
  var cf = newSeq[int](19)
  for (s, _) in clSyms: inc cf[s]
  var cl = huffLengths(cf, 7)
  atLeastTwo(cl)
  var hclen = 19
  while hclen > 4 and cl[ClOrder[hclen - 1]] == 0: dec hclen
  # coûts en bits
  var dynBits = 3 + 5 + 5 + 4 + 3 * hclen
  for (s, _) in clSyms:
    dynBits += cl[s] + (if s == 16: 2 elif s == 17: 3 elif s == 18: 7 else: 0)
  var fixBits = 3
  for s in 0 ..< 286:
    if lf[s] > 0:
      dynBits += lf[s] * ll[s]
      fixBits += lf[s] * fixedLitLen[s]
      if s >= 257:
        dynBits += lf[s] * LenExtra[s - 257]
        fixBits += lf[s] * LenExtra[s - 257]
  for s in 0 ..< 30:
    if df[s] > 0:
      dynBits += df[s] * (dl[s] + DistExtra[s])
      fixBits += df[s] * (5 + DistExtra[s])
  let rawLen = blockEnd - d.blockStart
  let storedBits = (rawLen div 65535 + 1) * 40 + rawLen * 8 + 8
  let fin = uint64(if final: 1 else: 0)
  if stored or (storedBits <= dynBits and storedBits <= fixBits):
    var p = d.blockStart
    while true:
      let n = min(65535, blockEnd - p)
      let last = p + n >= blockEnd
      d.w.put(if last: fin else: 0'u64, 1)
      d.w.put(0, 2)
      d.w.alignByte()
      d.w.buf.add char(n and 0xFF)
      d.w.buf.add char(n shr 8)
      d.w.buf.add char((not n) and 0xFF)
      d.w.buf.add char(((not n) shr 8) and 0xFF)
      if n > 0: d.w.buf.add data[p ..< p + n]
      p += n
      if last: break
  elif fixBits <= dynBits:
    d.w.put(fin, 1)
    d.w.put(1, 2)
    {.cast(gcsafe).}:
      d.emitSymbols(fixedLitLen, fixedDistLen, fixedLitCodes, fixedDistCodes)
  else:
    d.w.put(fin, 1)
    d.w.put(2, 2)
    d.w.put(uint64(hlit - 257), 5)
    d.w.put(uint64(hdist - 1), 5)
    d.w.put(uint64(hclen - 4), 4)
    for k in 0 ..< hclen: d.w.put(uint64(cl[ClOrder[k]]), 3)
    let cc = canonicalCodes(cl)
    for (s, e) in clSyms:
      d.w.put(uint64(cc[s]), cl[s])
      if s == 16: d.w.put(uint64(e), 2)
      elif s == 17: d.w.put(uint64(e), 3)
      elif s == 18: d.w.put(uint64(e), 7)
    d.emitSymbols(ll, dl, canonicalCodes(ll), canonicalCodes(dl))
  d.litlen.setLen(0)
  d.dists.setLen(0)
  d.blockStart = blockEnd

proc deflate*(data: string, level = 6): string =
  ## Flux deflate brut. niveau 0 : stocké ; 1 à 3 : rapide ; 4 à 9 : correspondances
  ## paresseuses, chaînes plus longues.
  let lvl = max(0, min(9, level))
  var d = Deflater()
  if lvl == 0 or data.len == 0:
    d.flushBlock(data, data.len, true, stored = lvl == 0)
    d.w.alignByte()
    return d.w.buf
  let p = LevelParams[lvl]
  var head = newSeq[int32](HSize)
  for k in 0 ..< HSize: head[k] = -1
  var prev = newSeq[int32](WSize)
  let n = data.len
  template hashAt(i: int): int =
    ((ord(data[i]) shl 10) xor (ord(data[i + 1]) shl 5) xor ord(data[i + 2])) and (HSize - 1)
  template insert(i: int) =
    if i + 2 < n:
      let h = hashAt(i)
      prev[i and WMask] = head[h]
      head[h] = int32(i)
  proc longest(i, prevLen: int, chainMax: int): (int, int) =
    var bestLen = prevLen
    var bestDist = 0
    if i + 2 >= n: return (0, 0)
    let maxL = min(258, n - i)
    var cand = int(head[hashAt(i)])
    var chain = if prevLen >= p.good: chainMax shr 2 else: chainMax
    while cand >= 0 and i - cand <= WSize and cand < i and chain > 0:
      if data[cand + bestLen] == data[i + bestLen] or bestLen == 0:
        var l = 0
        while l < maxL and data[cand + l] == data[i + l]: inc l
        if l > bestLen:
          bestLen = l
          bestDist = i - cand
          if l >= p.nice or l == maxL: break
      let nx = int(prev[cand and WMask])
      if nx >= cand: break
      cand = nx
      dec chain
    if bestDist == 0: (0, 0) else: (bestLen, bestDist)
  template lit(i: int) =
    d.litlen.add uint16(ord(data[i]))
    d.dists.add 0
  template match(l, dist: int) =
    d.litlen.add uint16(l)
    d.dists.add uint16(dist)
  var i = 0
  if p.lazy == 0:
    while i < n:
      let (l, dist) = longest(i, 0, p.chain)
      if l >= 3 and not (l == 3 and dist > 4096):
        match(l, dist)
        for k in 0 ..< l: insert(i + k)
        i += l
      else:
        lit(i)
        insert(i)
        inc i
      if d.litlen.len >= MaxSyms: d.flushBlock(data, i, false)
  else:
    var prevLen = 0
    var prevDist = 0
    var havePrev = false
    while i < n:
      var (l, dist) = (0, 0)
      if not havePrev or prevLen < p.lazy:
        (l, dist) = longest(i, 0, p.chain)
        if l == 3 and dist > 4096: l = 0
      insert(i)
      if havePrev and prevLen >= 3 and l <= prevLen:
        # la correspondance précédente (en i-1) est gardée.
        match(prevLen, prevDist)
        for k in i + 1 ..< i - 1 + prevLen: insert(k)
        i = i - 1 + prevLen
        havePrev = false
        prevLen = 0
      else:
        if havePrev: lit(i - 1)
        if l >= 3:
          havePrev = true
          prevLen = l
          prevDist = dist
          inc i
        else:
          havePrev = false
          prevLen = 0
          lit(i)
          inc i
      if d.litlen.len >= MaxSyms and not havePrev: d.flushBlock(data, i, false)
  d.flushBlock(data, n, true)
  d.w.alignByte()
  d.w.buf

#
# décompression
#

type
  HTable = object
    bits: int
    ent: seq[uint16]          # (symbole shl 4) or longueur ; 0 = code absent

  BitIn = object
    data: ptr UncheckedArray[char]
    len: int
    pos: int
    acc: uint64
    n: int

proc refill(r: var BitIn) {.inline.} =
  while r.n <= 56 and r.pos < r.len:
    r.acc = r.acc or (uint64(ord(r.data[r.pos])) shl r.n)
    inc r.pos
    r.n += 8

proc getBits(r: var BitIn, count: int): int {.inline.} =
  if count == 0: return 0
  if r.n < count:
    r.refill()
    if r.n < count: cerr("flux deflate tronqué")
  result = int(r.acc and ((1'u64 shl count) - 1))
  r.acc = r.acc shr count
  r.n -= count

proc buildTable(lengths: openArray[int]): HTable =
  var maxLen = 0
  for l in lengths: maxLen = max(maxLen, l)
  if maxLen == 0: maxLen = 1
  result.bits = maxLen
  result.ent = newSeq[uint16](1 shl maxLen)
  let codes = canonicalCodes(lengths)
  for s, l in lengths:
    if l > 0:
      let e = uint16((s shl 4) or l)
      var c = codes[s]
      let step = 1 shl l
      while c < (1 shl maxLen):
        result.ent[c] = e
        c += step

proc decodeSym(r: var BitIn, t: HTable): int {.inline.} =
  if r.n < t.bits: r.refill()
  let e = t.ent[int(r.acc and ((1'u64 shl t.bits) - 1))]
  let l = int(e and 15)
  if l == 0 or l > r.n: cerr("code de Huffman invalide")
  r.acc = r.acc shr l
  r.n -= l
  int(e shr 4)

var fixedLitT, fixedDistT: HTable
block:
  fixedLitT = buildTable(fixedLitLen)
  fixedDistT = buildTable(fixedDistLen)

proc inflateAt*(data: string, start: int, consumed: var int, sizeHint = 0): string =
  ## Décompresse un flux deflate brut commençant à `start` ; `consumed` reçoit la
  ## position qui suit le flux (octet entier).
  var r = BitIn(len: data.len, pos: start)
  if data.len > 0: r.data = cast[ptr UncheckedArray[char]](unsafeAddr data[0])
  var o = newString(max(1024, if sizeHint > 0: sizeHint else: (data.len - start) * 3))
  var olen = 0
  template ensure(extra: int) =
    if olen + extra > o.len: o.setLen(max(o.len * 2, olen + extra))
  while true:
    let final = r.getBits(1)
    let typ = r.getBits(2)
    case typ
    of 0:
      # retour à la frontière d'octet : les bits restants de l'octet courant sont perdus.
      let drop = r.n mod 8
      discard r.getBits(drop)
      var hdr: array[4, int]
      for k in 0 .. 3: hdr[k] = r.getBits(8)
      let ln = hdr[0] or (hdr[1] shl 8)
      let nln = hdr[2] or (hdr[3] shl 8)
      if (ln xor 0xFFFF) != nln: cerr("bloc stocké invalide")
      ensure(ln)
      var k = 0
      while k < ln and r.n >= 8:
        o[olen] = char(r.acc and 0xFF)
        r.acc = r.acc shr 8
        r.n -= 8
        inc olen
        inc k
      let rest = ln - k
      if r.pos + rest > r.len: cerr("flux deflate tronqué")
      if rest > 0:
        copyMem(addr o[olen], addr r.data[r.pos], rest)
        olen += rest
        r.pos += rest
    of 1, 2:
      var lit, dist: HTable
      if typ == 1:
        {.cast(gcsafe).}:
          lit = fixedLitT
          dist = fixedDistT
      else:
        let hlit = r.getBits(5) + 257
        let hdist = r.getBits(5) + 1
        let hclen = r.getBits(4) + 4
        var cl = newSeq[int](19)
        for k in 0 ..< hclen: cl[ClOrder[k]] = r.getBits(3)
        let clt = buildTable(cl)
        var lens = newSeq[int]()
        while lens.len < hlit + hdist:
          let s = r.decodeSym(clt)
          if s < 16: lens.add s
          elif s == 16:
            if lens.len == 0: cerr("longueurs de codes invalides")
            let pv = lens[^1]
            for _ in 0 ..< 3 + r.getBits(2): lens.add pv
          elif s == 17:
            for _ in 0 ..< 3 + r.getBits(3): lens.add 0
          else:
            for _ in 0 ..< 11 + r.getBits(7): lens.add 0
        if lens.len > hlit + hdist: cerr("longueurs de codes invalides")
        lit = buildTable(lens[0 ..< hlit])
        dist = buildTable(lens[hlit ..< hlit + hdist])
      while true:
        let s = r.decodeSym(lit)
        if s < 256:
          ensure(1)
          o[olen] = char(s)
          inc olen
        elif s == 256: break
        else:
          let li = s - 257
          if li >= LenBase.len: cerr("longueur invalide")
          let length = LenBase[li] + r.getBits(LenExtra[li])
          let di = r.decodeSym(dist)
          if di >= DistBase.len: cerr("distance invalide")
          let dd = DistBase[di] + r.getBits(DistExtra[di])
          if dd > olen: cerr("distance invalide")
          ensure(length)
          var from0 = olen - dd
          if dd >= length:
            copyMem(addr o[olen], addr o[from0], length)
            olen += length
          else:
            for _ in 0 ..< length:
              o[olen] = o[from0]
              inc olen
              inc from0
    else: cerr("bloc deflate invalide")
    if final == 1: break
  # octets lus d'avance rendus
  consumed = r.pos - (r.n div 8)
  o.setLen(olen)
  o

proc inflate*(data: string, sizeHint = 0): string =
  var c = 0
  inflateAt(data, 0, c, sizeHint)

# gzip, zlib

proc le32s(v: uint32): string =
  result = newString(4)
  for i in 0 .. 3: result[i] = char((v shr (8 * i)) and 0xFF)

proc rd16(s: string, i: int): int {.inline.} = ord(s[i]) or (ord(s[i + 1]) shl 8)
proc rd32(s: string, i: int): uint32 {.inline.} =
  uint32(ord(s[i])) or (uint32(ord(s[i + 1])) shl 8) or (uint32(ord(s[i + 2])) shl 16) or
    (uint32(ord(s[i + 3])) shl 24)
proc rd64(s: string, i: int): int64 {.inline.} =
  int64(rd32(s, i)) or (int64(rd32(s, i + 4)) shl 32)

proc gzipCompress*(data: string, level = 6, name = "", mtime = 0'i64): string =
  result = "\x1f\x8b\x08"
  result.add char(if name.len > 0: 8 else: 0)
  result.add le32s(uint32(max(0'i64, mtime) and 0xFFFFFFFF'i64))
  result.add char(if level >= 9: 2 elif level <= 1: 4 else: 0)
  result.add '\x03'
  if name.len > 0:
    result.add name.replace("\0", "")
    result.add '\0'
  result.add deflate(data, level)
  result.add le32s(crc32(data))
  result.add le32s(uint32(data.len and 0xFFFFFFFF))

proc isGzip*(data: string): bool = data.len >= 3 and data[0] == '\x1f' and data[1] == '\x8b'

proc gzipDecompress*(data: string, name: var string): string =
  ## Décompresse un fichier gzip (membres successifs concaténés) ; `name` : nom
  ## d'origine s'il est enregistré.
  var p = 0
  name = ""
  var first = true
  while p < data.len:
    if p + 10 > data.len or data[p] != '\x1f' or data[p + 1] != '\x8b':
      if first: cerr("pas un fichier gzip")
      break                                # remplissage final toléré
    if data[p + 2] != '\x08': cerr("méthode gzip non prise en charge")
    let flg = ord(data[p + 3])
    var q = p + 10
    if (flg and 4) != 0:
      if q + 2 > data.len: cerr("en-tête gzip tronqué")
      q += 2 + rd16(data, q)
    if (flg and 8) != 0:
      let e = data.find('\0', q)
      if e < 0: cerr("en-tête gzip tronqué")
      if first: name = data[q ..< e]
      q = e + 1
    if (flg and 16) != 0:
      let e = data.find('\0', q)
      if e < 0: cerr("en-tête gzip tronqué")
      q = e + 1
    if (flg and 2) != 0: q += 2
    if q > data.len: cerr("en-tête gzip tronqué")
    var used = 0
    let part = inflateAt(data, q, used)
    if used + 8 > data.len: cerr("fichier gzip tronqué")
    if rd32(data, used) != crc32(part): cerr("gzip : somme de contrôle incorrecte")
    result.add part
    p = used + 8
    first = false

proc gzipDecompress*(data: string): string =
  var n: string
  gzipDecompress(data, n)

proc zlibCompress2*(data: string, level = 6): string =
  result = "\x78" & (if level >= 7: "\xDA" elif level <= 1: "\x01" else: "\x9C")
  result.add deflate(data, level)
  let a = adler32(data)
  for s in [24, 16, 8, 0]: result.add char((a shr s) and 0xFF)

proc zlibDecompress2*(data: string): string =
  if data.len < 2 or (ord(data[0]) and 0x0F) != 8 or ((ord(data[0]) shl 8) or ord(data[1])) mod 31 != 0:
    cerr("pas un flux zlib")
  if (ord(data[1]) and 0x20) != 0: cerr("zlib : dictionnaire prédéfini non pris en charge")
  var used = 0
  result = inflateAt(data, 2, used)

#
# dates DOS
#

proc dosToUnix*(tm, dt: int): int64 =
  let year = 1980 + (dt shr 9)
  let month = max(1, min(12, (dt shr 5) and 15))
  let day = max(1, min(28 + 3, dt and 31))
  let hour = min(23, tm shr 11)
  let minute = min(59, (tm shr 5) and 63)
  let sec = min(59, (tm and 31) * 2)
  try:
    let d = dateTime(year, Month(month), MonthdayRange(min(day, getDaysInMonth(Month(month), year))),
                     HourRange(hour), MinuteRange(minute), SecondRange(sec), zone = local())
    d.toTime.toUnix
  except CatchableError: 0

proc unixToDos*(t: int64): (int, int) =
  let d = fromUnix(t).local
  let y = max(1980, min(2107, d.year))
  ((d.hour shl 11) or (d.minute shl 5) or (d.second div 2),
   ((y - 1980) shl 9) or (ord(d.month) shl 5) or d.monthday)

# noms d'entrées

proc cp437ToUtf8(s: string): string =
  const hi = ["Ç","ü","é","â","ä","à","å","ç","ê","ë","è","ï","î","ì","Ä","Å",
              "É","æ","Æ","ô","ö","ò","û","ù","ÿ","Ö","Ü","¢","£","¥","₧","ƒ",
              "á","í","ó","ú","ñ","Ñ","ª","º","¿","⌐","¬","½","¼","¡","«","»",
              "░","▒","▓","│","┤","╡","╢","╖","╕","╣","║","╗","╝","╜","╛","┐",
              "└","┴","┬","├","─","┼","╞","╟","╚","╔","╩","╦","╠","═","╬","╧",
              "╨","╤","╥","╙","╘","╒","╓","╫","╪","┘","┌","█","▄","▌","▐","▀",
              "α","ß","Γ","π","Σ","σ","µ","τ","Φ","Θ","Ω","δ","∞","φ","ε","∩",
              "≡","±","≥","≤","⌠","⌡","÷","≈","°","∙","·","√","ⁿ","²","■"," "]
  for c in s:
    if ord(c) < 128: result.add c else: result.add hi[ord(c) - 128]

proc validUtf8(s: string): bool =
  var i = 0
  while i < s.len:
    let c = ord(s[i])
    var n = 0
    if c < 0x80: n = 0
    elif (c and 0xE0) == 0xC0: n = 1
    elif (c and 0xF0) == 0xE0: n = 2
    elif (c and 0xF8) == 0xF0: n = 3
    else: return false
    if i + n >= s.len + (if n == 0: 1 else: 0) and n > 0: return false
    for k in 1 .. n:
      if i + k >= s.len or (ord(s[i + k]) and 0xC0) != 0x80: return false
    i += n + 1
  true

proc safeRelative*(name: string): string =
  ## Chemin relatif sûr pour l'extraction (refuse « .. », chemins absolus, lecteurs).
  var n = name.replace('\\', '/')
  while n.startsWith("./"): n = n[2 .. ^1]
  if n.startsWith("/") or (n.len >= 2 and n[1] == ':'):
    cerr("chemin absolu refusé dans l'archive : " & name)
  for part in n.split('/'):
    if part == "..": cerr("chemin dangereux refusé dans l'archive : " & name)
  n

#
# zip : lecture
#

type
  ZipEntry* = object
    name*: string
    isDir*: bool
    meth*: int
    crc*: uint32
    csize*, usize*: int64
    offset*: int64
    mtime*: int64
    mode*: int          # droits Unix (0 = inconnus)
    encrypted*: bool
    comment*: string

  ZipReader* = ref object
    path*: string
    f: File
    opened: bool
    entries*: seq[ZipEntry]
    comment*: string

proc readAt(f: File, pos: int64, n: int): string =
  result = newString(n)
  if n == 0: return
  f.setFilePos(pos)
  let got = f.readBuffer(addr result[0], n)
  if got < n: result.setLen(got)

proc openZip*(path: string): ZipReader =
  result = ZipReader(path: path)
  if not open(result.f, path, fmRead): cerr("impossible d'ouvrir " & path)
  result.opened = true
  let size = getFileSize(result.f)
  if size < 22: cerr("pas une archive zip : " & path)
  let tailLen = int(min(size, 65557'i64))
  let tail = readAt(result.f, size - tailLen, tailLen)
  var e = -1
  var k = tail.len - 22
  while k >= 0:
    if tail[k] == 'P' and tail[k + 1] == 'K' and tail[k + 2] == '\x05' and tail[k + 3] == '\x06':
      e = k
      break
    dec k
  if e < 0: cerr("pas une archive zip (fin de répertoire introuvable) : " & path)
  var count = int64(rd16(tail, e + 10))
  var cdSize = int64(rd32(tail, e + 12))
  var cdOff = int64(rd32(tail, e + 16))
  let clen = rd16(tail, e + 20)
  if e + 22 + clen <= tail.len: result.comment = tail[e + 22 ..< e + 22 + clen]
  # Zip64
  if e >= 20 and tail[e - 20 ..< e - 16] == "PK\x06\x07":
    let z64 = rd64(tail, e - 20 + 8)
    let rec = readAt(result.f, z64, 56)
    if rec.len >= 56 and rec[0 ..< 4] == "PK\x06\x06":
      count = rd64(rec, 32)
      cdSize = rd64(rec, 40)
      cdOff = rd64(rec, 48)
  # archives précédées de données (auto-extractibles) : décalage
  let eocdPos = size - tailLen + e
  var shift = 0'i64
  if cdOff + cdSize < eocdPos and e >= 0:
    let probe = readAt(result.f, cdOff, 4)
    if probe != "PK\x01\x02":
      shift = eocdPos - (cdOff + cdSize)
  let cd = readAt(result.f, cdOff + shift, int(cdSize))
  var p = 0
  for _ in 0 ..< count:
    if p + 46 > cd.len or cd[p ..< p + 4] != "PK\x01\x02": cerr("répertoire zip corrompu : " & path)
    let made = rd16(cd, p + 4) shr 8
    let flags = rd16(cd, p + 8)
    var en = ZipEntry(meth: rd16(cd, p + 10), crc: rd32(cd, p + 16),
                      csize: int64(rd32(cd, p + 20)), usize: int64(rd32(cd, p + 24)),
                      encrypted: (flags and 1) != 0)
    en.mtime = dosToUnix(rd16(cd, p + 12), rd16(cd, p + 14))
    let nlen = rd16(cd, p + 28)
    let xlen = rd16(cd, p + 30)
    let mlen = rd16(cd, p + 32)
    let ext = rd32(cd, p + 38)
    en.offset = int64(rd32(cd, p + 42))
    var nm = cd[p + 46 ..< p + 46 + nlen]
    if (flags and 0x800) == 0 and not validUtf8(nm): nm = cp437ToUtf8(nm)
    en.name = nm.replace('\\', '/')
    # champs supplémentaires : Zip64 (0x0001), temps Unix étendu (0x5455)
    var x = p + 46 + nlen
    let xend = x + xlen
    while x + 4 <= xend:
      let id = rd16(cd, x)
      let sz = rd16(cd, x + 2)
      var q = x + 4
      if id == 1:
        if en.usize == 0xFFFFFFFF'i64 and q + 8 <= x + 4 + sz:
          en.usize = rd64(cd, q); q += 8
        if en.csize == 0xFFFFFFFF'i64 and q + 8 <= x + 4 + sz:
          en.csize = rd64(cd, q); q += 8
        if en.offset == 0xFFFFFFFF'i64 and q + 8 <= x + 4 + sz:
          en.offset = rd64(cd, q); q += 8
      elif id == 0x5455 and sz >= 5 and (ord(cd[q]) and 1) != 0:
        en.mtime = int64(rd32(cd, q + 1))
      x += 4 + sz
    en.offset += shift
    if mlen > 0: en.comment = cd[xend ..< xend + mlen]
    if made == 3: en.mode = int((ext shr 16) and 0o7777)
    en.isDir = en.name.endsWith("/") or (ext and 0x10) != 0 or (made == 3 and ((ext shr 16) and 0o170000) == 0o040000)
    result.entries.add en
    p = xend + mlen

proc close*(z: ZipReader) =
  if z.opened:
    z.f.close()
    z.opened = false

proc find*(z: ZipReader, name: string): int =
  let n = name.replace('\\', '/')
  for i, e in z.entries:
    if e.name == n: return i
  for i, e in z.entries:
    if e.name.toLowerAscii == n.toLowerAscii: return i
  -1

proc read*(z: ZipReader, e: ZipEntry): string =
  if not z.opened: cerr("archive fermée")
  if e.isDir: return ""
  if e.encrypted: cerr("entrée chiffrée non prise en charge : " & e.name)
  let lh = readAt(z.f, e.offset, 30)
  if lh.len < 30 or lh[0 ..< 4] != "PK\x03\x04": cerr("entrée zip corrompue : " & e.name)
  let start = e.offset + 30 + rd16(lh, 26) + rd16(lh, 28)
  let packed = readAt(z.f, start, int(e.csize))
  if packed.len < e.csize: cerr("entrée zip tronquée : " & e.name)
  case e.meth
  of 0: result = packed
  of 8:
    var used = 0
    result = inflateAt(packed, 0, used, int(e.usize))
  else: cerr("méthode de compression " & $e.meth & " non prise en charge : " & e.name)
  if crc32(result) != e.crc: cerr("somme de contrôle incorrecte : " & e.name)

#
# zip : écriture
#

type
  ZipWriter* = ref object
    path*: string
    f: File
    opened: bool
    offset: int64
    central: string
    count*: int
    level*: int
    names: seq[string]
    comment*: string

proc le16(s: var string, v: int) =
  s.add char(v and 0xFF)
  s.add char((v shr 8) and 0xFF)

proc le32(s: var string, v: int64) =
  for i in 0 .. 3: s.add char(int((v shr (8 * i)) and 0xFF))

proc le64(s: var string, v: int64) =
  for i in 0 .. 7: s.add char(int((v shr (8 * i)) and 0xFF))

proc createZip*(path: string, level = 6): ZipWriter =
  result = ZipWriter(path: path, level: level)
  if not open(result.f, path, fmWrite): cerr("impossible de créer " & path)
  result.opened = true

proc emit(z: ZipWriter, s: string) =
  if s.len > 0: z.f.write s
  z.offset += s.len

proc contains*(z: ZipWriter, name: string): bool = name in z.names

proc addEntry*(z: ZipWriter, name0: string, data: string, mtime: int64, mode = 0, isDir = false) =
  if not z.opened: cerr("archive fermée")
  var name = name0.replace('\\', '/')
  while name.startsWith("/"): name = name[1 .. ^1]
  if isDir and not name.endsWith("/"): name.add "/"
  if name.len == 0: cerr("nom d'entrée vide")
  z.names.add name
  var packed = data
  var meth = 0
  if not isDir and data.len > 0 and z.level > 0:
    let c = deflate(data, z.level)
    if c.len < data.len:
      packed = c
      meth = 8
  let crc = if isDir: 0'u32 else: crc32(data)
  let (tm, dt) = unixToDos(mtime)
  let big = data.len.int64 >= 0xFFFFFFFF'i64 or packed.len.int64 >= 0xFFFFFFFF'i64
  let farOff = z.offset >= 0xFFFFFFFF'i64
  let here = z.offset
  var utime = ""
  utime.le16 0x5455
  utime.le16 5
  utime.add '\x01'
  utime.le32 mtime
  var h = "PK\x03\x04"
  h.le16 (if big: 45 else: 20)
  h.le16 0x0800                          # noms en UTF-8
  h.le16 meth
  h.le16 tm
  h.le16 dt
  h.le32 int64(crc)
  var x = utime
  if big:
    h.le32 0xFFFFFFFF'i64
    h.le32 0xFFFFFFFF'i64
    x.le16 1
    x.le16 16
    x.le64 data.len
    x.le64 packed.len
  else:
    h.le32 packed.len
    h.le32 data.len
  h.le16 name.len
  h.le16 x.len
  h.add name
  h.add x
  z.emit h
  z.emit packed
  var cx = utime
  var c = "PK\x01\x02"
  c.le16 (3 shl 8) or (if big or farOff: 45 else: 20)
  c.le16 (if big or farOff: 45 else: 20)
  c.le16 0x0800
  c.le16 meth
  c.le16 tm
  c.le16 dt
  c.le32 int64(crc)
  if big or farOff:
    var z64 = ""
    if big:
      z64.le64 data.len
      z64.le64 packed.len
    if farOff: z64.le64 here
    cx.le16 1
    cx.le16 z64.len
    cx.add z64
  if big:
    c.le32 0xFFFFFFFF'i64
    c.le32 0xFFFFFFFF'i64
  else:
    c.le32 packed.len
    c.le32 data.len
  c.le16 name.len
  c.le16 cx.len
  c.le16 0
  c.le16 0
  c.le16 0
  let m = if mode != 0: mode elif isDir: 0o755 else: 0o644
  let unixMode = (if isDir: 0o040000 else: 0o100000) or m
  c.le32 (int64(unixMode) shl 16) or (if isDir: 0x10'i64 else: 0'i64)
  c.le32 (if farOff: 0xFFFFFFFF'i64 else: here)
  c.add name
  c.add cx
  z.central.add c
  inc z.count

proc close*(z: ZipWriter) =
  if not z.opened: return
  let cdStart = z.offset
  z.emit z.central
  let cdLen = z.offset - cdStart
  let need64 = z.count >= 0xFFFF or cdStart >= 0xFFFFFFFF'i64 or cdLen >= 0xFFFFFFFF'i64
  if need64:
    let recPos = z.offset
    var r = "PK\x06\x06"
    r.le64 44
    r.le16 (3 shl 8) or 45
    r.le16 45
    r.le32 0
    r.le32 0
    r.le64 z.count
    r.le64 z.count
    r.le64 cdLen
    r.le64 cdStart
    var loc = "PK\x06\x07"
    loc.le32 0
    loc.le64 recPos
    loc.le32 1
    z.emit r & loc
  var t = "PK\x05\x06"
  t.le16 0
  t.le16 0
  t.le16 min(z.count, 0xFFFF)
  t.le16 min(z.count, 0xFFFF)
  t.le32 min(cdLen, 0xFFFFFFFF'i64)
  t.le32 min(cdStart, 0xFFFFFFFF'i64)
  let cm = z.comment[0 ..< min(z.comment.len, 65535)]
  t.le16 cm.len
  t.add cm
  z.emit t
  z.f.close()
  z.opened = false

proc size*(z: ZipWriter): int64 = z.offset

#
# tar
#

type
  TarEntry* = object
    name*: string
    isDir*: bool
    isLink*: bool
    link*: string
    size*: int64
    mtime*: int64
    mode*: int
    dataPos*: int        # position des données dans le tar décompressé

proc parseOctal(s: string): int64 =
  if s.len > 0 and (ord(s[0]) and 0x80) != 0:
    # base 256 (GNU) pour les grandes tailles
    result = int64(ord(s[0]) and 0x7F)
    for k in 1 ..< s.len: result = (result shl 8) or int64(ord(s[k]))
    return
  for c in s:
    if c in {'0'..'7'}: result = result * 8 + int64(ord(c) - ord('0'))
    elif c in {'\0', ' '}:
      if result > 0: break
    else: break

proc cstr(s: string): string =
  let z = s.find('\0')
  if z >= 0: s[0 ..< z] else: s

proc tarList*(tar: string): seq[TarEntry] =
  var p = 0
  var longName = ""
  var longLink = ""
  var paxPath = ""
  while p + 512 <= tar.len:
    let h = tar[p ..< p + 512]
    if h.allCharsInSet({'\0'}): break
    var sum = 0
    for k in 0 ..< 512: sum += (if k >= 148 and k < 156: 32 else: ord(h[k]))
    if parseOctal(h[148 ..< 156]) != sum: cerr("en-tête tar invalide (somme de contrôle)")
    let size = parseOctal(h[124 ..< 136])
    let typ = h[156]
    let dataPos = p + 512
    let next = dataPos + int((size + 511) div 512 * 512)
    if dataPos + size > tar.len: cerr("archive tar tronquée")
    case typ
    of 'L': longName = cstr(tar[dataPos ..< dataPos + int(size)])
    of 'K': longLink = cstr(tar[dataPos ..< dataPos + int(size)])
    of 'x':
      for rec in tar[dataPos ..< dataPos + int(size)].split('\n'):
        let sp = rec.find(' ')
        if sp < 0: continue
        let kv = rec[sp + 1 .. ^1]
        if kv.startsWith("path="): paxPath = kv[5 .. ^1]
        elif kv.startsWith("linkpath="): longLink = kv[9 .. ^1]
    of 'g': discard
    else:
      var name = cstr(h[0 ..< 100])
      if h[257 ..< 262] == "ustar":
        let prefix = cstr(h[345 ..< 500])
        if prefix.len > 0: name = prefix & "/" & name
      if longName.len > 0: name = longName
      if paxPath.len > 0: name = paxPath
      var e = TarEntry(name: name, size: size, mtime: parseOctal(h[136 ..< 148]),
                       mode: int(parseOctal(h[100 ..< 108]) and 0o7777), dataPos: dataPos)
      e.isDir = typ == '5' or (typ in {'0', '\0'} and name.endsWith("/"))
      e.isLink = typ in {'1', '2'}
      if e.isLink: e.link = if longLink.len > 0: longLink else: cstr(h[157 ..< 257])
      if typ in {'0', '\0', '5', '1', '2', '7'}:
        if e.isDir or e.isLink: e.size = 0
        result.add e
      longName = ""
      longLink = ""
      paxPath = ""
    p = next

proc tarRead*(tar: string, e: TarEntry): string =
  if e.isDir or e.isLink: "" else: tar[e.dataPos ..< e.dataPos + int(e.size)]

proc octalField(v: int64, width: int): string =
  toOct(v, width - 1) & "\0"

proc tarHeader(name: string, size: int64, mode: int, mtime: int64, typ: char, link = ""): string =
  var h = newString(512)
  proc put(s: string, at: int) =
    for i, c in s: h[at + i] = c
  put(name[0 ..< min(name.len, 100)], 0)
  put(octalField(mode, 8), 100)
  put(octalField(0, 8), 108)
  put(octalField(0, 8), 116)
  if size >= 0o77777777777'i64:
    h[124] = char(0x80)
    for k in 0 ..< 8: h[135 - k] = char((size shr (8 * k)) and 0xFF)
  else:
    put(octalField(size, 12), 124)
  put(octalField(max(0'i64, mtime), 12), 136)
  put("        ", 148)
  h[156] = typ
  put(link[0 ..< min(link.len, 100)], 157)
  put("ustar\x0000", 257)
  put("wdlexis", 265)
  put("wdlexis", 297)
  var sum = 0
  for c in h: sum += ord(c)
  put(toOct(sum, 6) & "\0 ", 148)
  h

proc tarAdd*(tar: var string, name0: string, data: string, mtime: int64, mode = 0, isDir = false) =
  var name = name0.replace('\\', '/')
  while name.startsWith("/"): name = name[1 .. ^1]
  if isDir and not name.endsWith("/"): name.add "/"
  let m = if mode != 0: mode elif isDir: 0o755 else: 0o644
  if name.len > 100:
    # nom long : enregistrement pax « longueur path=nom\n » (la longueur se compte elle-même)
    let body = " path=" & name & "\n"
    var n = body.len + 1
    while ($n).len + body.len != n: n = ($n).len + body.len
    let rec = $n & body
    tar.add tarHeader("PaxHeader/" & name[max(0, name.len - 80) .. ^1], rec.len, 0o644, mtime, 'x')
    tar.add rec
    if rec.len mod 512 != 0: tar.add repeat('\0', 512 - rec.len mod 512)
  tar.add tarHeader(name, if isDir: 0 else: data.len, m, mtime, if isDir: '5' else: '0')
  if not isDir:
    tar.add data
    if data.len mod 512 != 0: tar.add repeat('\0', 512 - data.len mod 512)

proc tarFinish*(tar: var string) =
  tar.add repeat('\0', 1024)

#
# motifs
#

proc globMatch*(pattern, s: string): bool =
  ## Joker « * » (toute suite, « / » compris), « ? » (un caractère) ; sans
  ## distinction de casse. Un motif sans « / » s'applique aussi au seul nom.
  let p = pattern.toLowerAscii
  let t = s.toLowerAscii
  proc m(pi, ti: int): bool =
    var pi = pi
    var ti = ti
    var starP = -1
    var starT = 0
    while ti < t.len:
      if pi < p.len and (p[pi] == '?' or p[pi] == t[ti]):
        inc pi
        inc ti
      elif pi < p.len and p[pi] == '*':
        starP = pi
        starT = ti
        inc pi
      elif starP >= 0:
        pi = starP + 1
        inc starT
        ti = starT
      else: return false
    while pi < p.len and p[pi] == '*': inc pi
    pi == p.len
  if m(0, 0): return true
  if '/' notin p:
    let base = t.strip(leading = false, chars = {'/'})
    let k = base.rfind('/')
    if k >= 0:
      let tt = base[k + 1 .. ^1]
      return globMatch(pattern, tt)
  false

#
# format
#

type ArchiveKind* = enum akNone, akZip, akTar, akTarGz, akGzip

proc detectKind*(path: string): ArchiveKind =
  var f: File
  if not open(f, path, fmRead): return akNone
  defer: f.close()
  var head = newString(512)
  let n = f.readBuffer(addr head[0], 512)
  head.setLen(n)
  if n >= 4 and head[0 ..< 4] in ["PK\x03\x04", "PK\x05\x06", "PK\x07\x08"]: return akZip
  if n >= 2 and head[0] == '\x1f' and head[1] == '\x8b':
    let low = path.toLowerAscii
    if low.endsWith(".tgz") or low.endsWith(".tar.gz"): return akTarGz
    # contenu tar ? on décompresse le début
    try:
      let all = readFile(path)
      let d = gzipDecompress(all)
      if d.len >= 512 and d[257 ..< 262] == "ustar": return akTarGz
    except CatchableError: discard
    return akGzip
  if n >= 262 and head[257 ..< 262] == "ustar": return akTar
  if path.toLowerAscii.endsWith(".zip"):
    # zip précédé de données (auto-extractible)
    try:
      let z = openZip(path)
      z.close()
      return akZip
    except CatchableError: discard
  if path.toLowerAscii.endsWith(".tar") and n == 512:
    try:
      discard tarList(readFile(path))
      return akTar
    except CatchableError: discard
  akNone

proc kindName*(k: ArchiveKind): string =
  case k
  of akZip: "zip"
  of akTar: "tar"
  of akTarGz: "targz"
  of akGzip: "gzip"
  of akNone: ""
