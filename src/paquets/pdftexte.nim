# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - extraction du texte d'un PDF, en Nim pur
#
#   Lecture des objets (y compris les flux d'objets PDF 1.5), arbre des pages,
#   flux de contenu (FlateDecode, ASCIIHex, ASCII85, LZW, prédicteurs PNG),
#   polices : table ToUnicode, encodages WinAnsi / MacRoman / Standard et
#   /Differences (noms de glyphes), polices composites (CID) à 1 ou 2 octets,
#   largeurs des glyphes pour retrouver espaces et fins de ligne, formulaires
#   (XObject /Form). Les PDF chiffrés et les pages scannées (images) n'ont pas
#   de texte lisible ici.

import std/[strutils, tables, unicode, math, sets, algorithm]
import compression

type
  PdfError* = object of CatchableError

  PKind = enum pNull, pBool, pNum, pStr, pName, pArr, pDict, pRef, pOp
  PObj = ref object
    case kind: PKind
    of pNull: discard
    of pBool: b: bool
    of pNum: n: float
    of pStr, pName, pOp: s: string
    of pArr: a: seq[PObj]
    of pDict:
      d: OrderedTable[string, PObj]
      stream: string           # données brutes du flux (si c'en est un)
      hasStream: bool
    of pRef: num, gen: int

  Pdf = ref object
    data: string
    objs: Table[int, PObj]
    offsets: Table[int, int]
    roots: seq[PObj]
    info: PObj
    encrypted: bool

  Font = ref object
    toUni: Table[int, string]
    codeBytes: int            # 1 ou 2 octets par code (police composite)
    twoByteRanges: bool
    enc: array[256, string]
    hasEnc: bool
    widths: Table[int, float]
    defaultWidth: float
    composite: bool
    spaceCode: int

  PdfDoc* = object
    pages*: seq[string]
    title*, author*: string

proc perr(msg: string) {.noreturn.} =
  raise newException(PdfError, msg)

# lexique

const
  WS = {' ', '\t', '\r', '\n', '\f', '\0'}
  Delims = {'(', ')', '<', '>', '[', ']', '{', '}', '/', '%'}

type Lexer = object
  s: ptr string
  i: int

proc skipWs(lx: var Lexer) =
  let s = lx.s
  while lx.i < s[].len:
    let c = s[][lx.i]
    if c in WS: inc lx.i
    elif c == '%':
      while lx.i < s[].len and s[][lx.i] notin {'\r', '\n'}: inc lx.i
    else: break

proc parseObj(lx: var Lexer, depth = 0): PObj

proc readLiteral(lx: var Lexer): string =
  # « ( » déjà lu
  let s = lx.s
  var depth = 1
  while lx.i < s[].len:
    let c = s[][lx.i]
    inc lx.i
    if c == '\\':
      if lx.i >= s[].len: break
      let e = s[][lx.i]
      inc lx.i
      case e
      of 'n': result.add '\n'
      of 'r': result.add '\r'
      of 't': result.add '\t'
      of 'b': result.add '\b'
      of 'f': result.add '\f'
      of '(', ')', '\\': result.add e
      of '\r':
        if lx.i < s[].len and s[][lx.i] == '\n': inc lx.i
      of '\n': discard
      of '0'..'7':
        var v = ord(e) - ord('0')
        var k = 0
        while k < 2 and lx.i < s[].len and s[][lx.i] in {'0'..'7'}:
          v = v * 8 + ord(s[][lx.i]) - ord('0')
          inc lx.i
          inc k
        result.add char(v and 0xFF)
      else: result.add e
    elif c == '(':
      inc depth
      result.add c
    elif c == ')':
      dec depth
      if depth == 0: break
      result.add c
    else: result.add c

proc hexVal(c: char): int =
  case c
  of '0'..'9': ord(c) - ord('0')
  of 'a'..'f': ord(c) - ord('a') + 10
  of 'A'..'F': ord(c) - ord('A') + 10
  else: -1

proc readHex(lx: var Lexer): string =
  # « < » déjà lu
  let s = lx.s
  var hi = -1
  while lx.i < s[].len:
    let c = s[][lx.i]
    inc lx.i
    if c == '>': break
    let v = hexVal(c)
    if v < 0: continue
    if hi < 0: hi = v
    else:
      result.add char(hi * 16 + v)
      hi = -1
  if hi >= 0: result.add char(hi * 16)

proc readName(lx: var Lexer): string =
  let s = lx.s
  while lx.i < s[].len:
    let c = s[][lx.i]
    if c in WS or c in Delims: break
    if c == '#' and lx.i + 2 < s[].len and hexVal(s[][lx.i + 1]) >= 0 and hexVal(s[][lx.i + 2]) >= 0:
      result.add char(hexVal(s[][lx.i + 1]) * 16 + hexVal(s[][lx.i + 2]))
      lx.i += 3
    else:
      result.add c
      inc lx.i

proc readToken(lx: var Lexer): string =
  let s = lx.s
  let st = lx.i
  while lx.i < s[].len and s[][lx.i] notin WS and s[][lx.i] notin Delims: inc lx.i
  s[][st ..< lx.i]

proc isNumTok(t: string): bool =
  if t.len == 0: return false
  var digits = false
  for k, c in t:
    if c in {'0'..'9'}: digits = true
    elif c == '.': discard
    elif c in {'+', '-'} and k == 0: discard
    else: return false
  digits

proc parseNumber(t: string): float =
  try: parseFloat(t)
  except ValueError:
    try: float(parseInt(t.split('.')[0]))
    except ValueError: 0.0

proc parseObj(lx: var Lexer, depth = 0): PObj =
  if depth > 200: perr("PDF : structure trop profonde")
  lx.skipWs()
  let s = lx.s
  if lx.i >= s[].len: return nil
  let c = s[][lx.i]
  case c
  of '/':
    inc lx.i
    return PObj(kind: pName, s: lx.readName())
  of '(':
    inc lx.i
    return PObj(kind: pStr, s: lx.readLiteral())
  of '<':
    if lx.i + 1 < s[].len and s[][lx.i + 1] == '<':
      lx.i += 2
      var d = PObj(kind: pDict, d: initOrderedTable[string, PObj]())
      while true:
        lx.skipWs()
        if lx.i >= s[].len: break
        if s[][lx.i] == '>' and lx.i + 1 < s[].len and s[][lx.i + 1] == '>':
          lx.i += 2
          break
        let k = lx.parseObj(depth + 1)
        if k.isNil: break
        if k.kind != pName:
          continue
        let v = lx.parseObj(depth + 1)
        if v.isNil: break
        d.d[k.s] = v
      return d
    inc lx.i
    return PObj(kind: pStr, s: lx.readHex())
  of '[':
    inc lx.i
    var a = PObj(kind: pArr)
    while true:
      lx.skipWs()
      if lx.i >= s[].len: break
      if s[][lx.i] == ']':
        inc lx.i
        break
      let v = lx.parseObj(depth + 1)
      if v.isNil: break
      a.a.add v
    return a
  of ']', '>', ')', '{', '}':
    inc lx.i
    return PObj(kind: pOp, s: $c)
  else:
    let t = lx.readToken()
    if t.len == 0:
      inc lx.i
      return PObj(kind: pOp, s: $c)
    if isNumTok(t):
      # référence « n g R » ?
      let save = lx.i
      if '.' notin t and t[0] != '-':
        lx.skipWs()
        let t2 = lx.readToken()
        if t2.len > 0 and t2.allCharsInSet({'0'..'9'}):
          lx.skipWs()
          if lx.i < s[].len and s[][lx.i] == 'R' and
             (lx.i + 1 >= s[].len or s[][lx.i + 1] in WS or s[][lx.i + 1] in Delims):
            inc lx.i
            return PObj(kind: pRef, num: parseInt(t), gen: parseInt(t2))
        lx.i = save
      return PObj(kind: pNum, n: parseNumber(t))
    case t
    of "true": PObj(kind: pBool, b: true)
    of "false": PObj(kind: pBool, b: false)
    of "null": PObj(kind: pNull)
    else: PObj(kind: pOp, s: t)

# objets

proc resolve(p: Pdf, o: PObj, depth = 0): PObj

proc get(d: PObj, key: string): PObj =
  if d.isNil or d.kind != pDict: return nil
  d.d.getOrDefault(key)

proc dget(p: Pdf, d: PObj, key: string): PObj = p.resolve(d.get(key))

proc num(o: PObj, def = 0.0): float =
  if not o.isNil and o.kind == pNum: o.n else: def

proc name(o: PObj): string =
  if not o.isNil and o.kind == pName: o.s else: ""

proc findEndstream(data: string, start: int): int =
  data.find("endstream", start)

proc parseIndirectAt(p: Pdf, pos: int): PObj =
  ## Objet « n g obj ... endobj » à la position donnée.
  var lx = Lexer(s: addr p.data, i: pos)
  discard lx.readToken()
  lx.skipWs()
  discard lx.readToken()
  lx.skipWs()
  if lx.readToken() != "obj": return nil
  result = lx.parseObj()
  if result.isNil: return
  lx.skipWs()
  let save = lx.i
  if result.kind == pDict and lx.readToken() == "stream":
    var st = lx.i
    if st < p.data.len and p.data[st] == '\r': inc st
    if st < p.data.len and p.data[st] == '\n': inc st
    var length = -1
    let lo = result.get("Length")
    if not lo.isNil:
      if lo.kind == pNum: length = int(lo.n)
      elif lo.kind == pRef:
        let r = p.resolve(lo)
        if not r.isNil and r.kind == pNum: length = int(r.n)
    var en = -1
    if length >= 0 and st + length <= p.data.len:
      let after = p.data[st + length ..< min(p.data.len, st + length + 20)]
      if "endstream" in after: en = st + length
    if en < 0:
      en = findEndstream(p.data, st)
      if en < 0: en = p.data.len
      var e2 = en
      while e2 > st and p.data[e2 - 1] in {'\r', '\n'}: dec e2
      en = e2
    result.stream = p.data[st ..< en]
    result.hasStream = true
  else:
    lx.i = save

proc decodeLzw(data: string, early = 1): string =
  var dict: seq[string]
  proc reset(d: var seq[string]) =
    d.setLen(0)
    for i in 0 .. 255: d.add $char(i)
    d.add ""
    d.add ""
  dict.reset()
  var bits = 9
  var acc = 0'u32
  var n = 0
  var prev = ""
  var i = 0
  while true:
    while n < bits and i < data.len:
      acc = (acc shl 8) or uint32(ord(data[i]))
      n += 8
      inc i
    if n < bits: break
    let code = int((acc shr (n - bits)) and ((1'u32 shl bits) - 1))
    n -= bits
    if code == 256:
      dict.reset()
      bits = 9
      prev = ""
      continue
    if code == 257: break
    var entry: string
    if code < dict.len: entry = dict[code]
    elif code == dict.len and prev.len > 0: entry = prev & prev[0]
    else: break
    result.add entry
    if prev.len > 0:
      dict.add prev & entry[0]
    prev = entry
    let limit = dict.len + early
    if limit >= (1 shl bits) and bits < 12: inc bits

proc unpredict(data: string, parms: PObj, p: Pdf): string =
  let pred = int(p.dget(parms, "Predictor").num(1))
  if pred < 10: return data
  let colors = int(p.dget(parms, "Colors").num(1))
  let bpc = int(p.dget(parms, "BitsPerComponent").num(8))
  let columns = int(p.dget(parms, "Columns").num(1))
  let bpp = max(1, colors * bpc div 8)
  let row = (columns * colors * bpc + 7) div 8
  var prevRow = newString(row)
  var i = 0
  while i + 1 + row <= data.len:
    let ft = ord(data[i])
    var cur = data[i + 1 .. i + row]
    for k in 0 ..< row:
      let a = if k >= bpp: ord(cur[k - bpp]) else: 0
      let b = ord(prevRow[k])
      let c = if k >= bpp: ord(prevRow[k - bpp]) else: 0
      var v = ord(cur[k])
      case ft
      of 1: v += a
      of 2: v += b
      of 3: v += (a + b) div 2
      of 4:
        let pp = a + b - c
        let pa = abs(pp - a)
        let pb = abs(pp - b)
        let pc = abs(pp - c)
        v += (if pa <= pb and pa <= pc: a elif pb <= pc: b else: c)
      else: discard
      cur[k] = char(v and 0xFF)
    result.add cur
    prevRow = cur
    i += 1 + row

proc decodeStream(p: Pdf, d: PObj): string =
  if d.isNil or not d.hasStream: return ""
  result = d.stream
  var filters: seq[string]
  var parms: seq[PObj]
  let f = p.dget(d, "Filter")
  let dp = p.dget(d, "DecodeParms")
  if not f.isNil:
    if f.kind == pName:
      filters.add f.s
      parms.add p.resolve(dp)
    elif f.kind == pArr:
      for k, x in f.a:
        filters.add p.resolve(x).name
        if not dp.isNil and dp.kind == pArr and k < dp.a.len: parms.add p.resolve(dp.a[k])
        else: parms.add nil
  for k, flt in filters:
    case flt
    of "FlateDecode", "Fl":
      var ok = false
      try:
        if result.len >= 2 and (ord(result[0]) and 0x0F) == 8:
          var used = 0
          result = inflateAt(result, 2, used)
          ok = true
      except CatchableError: discard
      if not ok:
        try: result = inflate(result)
        except CatchableError:
          return ""
      if not parms[k].isNil: result = unpredict(result, parms[k], p)
    of "ASCIIHexDecode", "AHx":
      var lx = Lexer(s: addr result, i: 0)
      var tmp = result & ">"
      lx.s = addr tmp
      result = lx.readHex()
    of "ASCII85Decode", "A85":
      var o = ""
      var grp: seq[int]
      var i = 0
      var s = result
      if s.startsWith("<~"): s = s[2 .. ^1]
      while i < s.len:
        let c = s[i]
        inc i
        if c == '~': break
        if c in WS: continue
        if c == 'z' and grp.len == 0:
          o.add "\0\0\0\0"
          continue
        grp.add ord(c) - 33
        if grp.len == 5:
          var v = 0'u64
          for x in grp: v = v * 85 + uint64(x)
          for sh in [24, 16, 8, 0]: o.add char((v shr sh) and 0xFF)
          grp.setLen(0)
      if grp.len > 1:
        let m = grp.len
        while grp.len < 5: grp.add 84
        var v = 0'u64
        for x in grp: v = v * 85 + uint64(x)
        for j, sh in [24, 16, 8, 0]:
          if j < m - 1: o.add char((v shr sh) and 0xFF)
      result = o
    of "LZWDecode", "LZW":
      let early = if parms[k].isNil: 1 else: int(p.dget(parms[k], "EarlyChange").num(1))
      result = decodeLzw(result, early)
      if not parms[k].isNil: result = unpredict(result, parms[k], p)
    of "RunLengthDecode", "RL":
      var o = ""
      var i = 0
      while i < result.len:
        let l = ord(result[i])
        inc i
        if l == 128: break
        if l < 128:
          o.add result[i ..< min(result.len, i + l + 1)]
          i += l + 1
        elif i < result.len:
          o.add repeat(result[i], 257 - l)
          inc i
      result = o
    else:
      return ""                      # images (DCT, JBIG2...) : sans texte

proc loadObjStm(p: Pdf, st: PObj) =
  let data = p.decodeStream(st)
  if data.len == 0: return
  let n = int(p.dget(st, "N").num(0))
  let first = int(p.dget(st, "First").num(0))
  var lx = Lexer(s: addr data, i: 0)
  var pairs: seq[(int, int)]
  for _ in 0 ..< n:
    lx.skipWs()
    let a = lx.readToken()
    lx.skipWs()
    let b = lx.readToken()
    if not isNumTok(a) or not isNumTok(b): break
    pairs.add (parseInt(a), parseInt(b))
  for (num, off) in pairs:
    if p.objs.hasKey(num) and p.offsets.getOrDefault(num, -1) >= 0: continue
    var l2 = Lexer(s: addr data, i: first + off)
    if first + off >= data.len: continue
    let o = l2.parseObj()
    if not o.isNil: p.objs[num] = o

proc resolve(p: Pdf, o: PObj, depth = 0): PObj =
  if o.isNil or o.kind != pRef: return o
  if depth > 30: return nil
  if p.objs.hasKey(o.num):
    let r = p.objs[o.num]
    if r.isNil: return nil
    return p.resolve(r, depth + 1)
  let off = p.offsets.getOrDefault(o.num, -1)
  if off < 0: return nil
  p.objs[o.num] = nil                  # garde contre les cycles
  let r = p.parseIndirectAt(off)
  p.objs[o.num] = r
  p.resolve(r, depth + 1)

proc openPdf(data: string): Pdf =
  if not data.startsWith("%PDF") and data.find("%PDF") notin 0 .. 1024:
    perr("pas un fichier PDF")
  result = Pdf(data: data)
  let p = result
  # recensement de tous les « n g obj » (le dernier l'emporte : mises à jour)
  var i = 0
  let d = p.data
  var k = -2
  var k2 = -2
  while true:
    # deux curseurs : chaque motif n'est recherché qu'une fois au-delà de i
    if k != -1 and k < i: k = d.find(" obj", i)
    if k2 != -1 and k2 < i: k2 = d.find("\nobj", i)
    var at = k
    if at < 0 or (k2 >= 0 and k2 < at): at = k2
    if at < 0: break
    # remonter : « num gen »
    var j = at - 1
    while j >= 0 and d[j] in {' ', '\r', '\n', '\t'}: dec j
    let genEnd = j + 1
    while j >= 0 and d[j] in {'0'..'9'}: dec j
    let genStart = j + 1
    while j >= 0 and d[j] in {' ', '\r', '\n', '\t'}: dec j
    let numEnd = j + 1
    while j >= 0 and d[j] in {'0'..'9'}: dec j
    let numStart = j + 1
    if genStart < genEnd and numStart < numEnd and numEnd < genStart and
       (numStart == 0 or d[numStart - 1] in WS or d[numStart - 1] in Delims):
      try:
        let num = parseInt(d[numStart ..< numEnd])
        p.offsets[num] = numStart
      except ValueError: discard
    i = at + 4
  # flux d'objets et dictionnaires de fin (trailer, flux XRef)
  var nums: seq[int]
  for n in p.offsets.keys: nums.add n
  nums.sort()
  for n in nums:
    let o = p.resolve(PObj(kind: pRef, num: n))
    if o.isNil or o.kind != pDict: continue
    let t = o.get("Type").name
    if t == "ObjStm" and o.hasStream: p.loadObjStm(o)
    elif t == "XRef":
      if not o.get("Root").isNil: p.roots.add o
      if not o.get("Encrypt").isNil: p.encrypted = true
  i = 0
  while true:
    let t = d.find("trailer", i)
    if t < 0: break
    var lx = Lexer(s: addr p.data, i: t + 7)
    let o = lx.parseObj()
    if not o.isNil and o.kind == pDict:
      p.roots.add o
      if not o.get("Encrypt").isNil: p.encrypted = true
    i = t + 7
  # catalogue introuvable par les dictionnaires de fin : on cherche /Type /Catalog
  if p.roots.len == 0:
    for n in nums:
      let o = p.resolve(PObj(kind: pRef, num: n))
      if not o.isNil and o.kind == pDict and o.get("Type").name == "Catalog":
        var fake = PObj(kind: pDict, d: initOrderedTable[string, PObj]())
        fake.d["Root"] = PObj(kind: pRef, num: n)
        p.roots.add fake

# encodages

const WinAnsiHigh: array[128, int] = [
  0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0, 0x017D, 0,
  0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0, 0x017E, 0x0178,
  0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF,
  0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF,
  0xC0, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCE, 0xCF,
  0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE, 0xDF,
  0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xEB, 0xEC, 0xED, 0xEE, 0xEF,
  0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF]

const MacRomanHigh: array[128, int] = [
  0xC4, 0xC5, 0xC7, 0xC9, 0xD1, 0xD6, 0xDC, 0xE1, 0xE0, 0xE2, 0xE4, 0xE3, 0xE5, 0xE7, 0xE9, 0xE8,
  0xEA, 0xEB, 0xED, 0xEC, 0xEE, 0xEF, 0xF1, 0xF3, 0xF2, 0xF4, 0xF6, 0xF5, 0xFA, 0xF9, 0xFB, 0xFC,
  0x2020, 0xB0, 0xA2, 0xA3, 0xA7, 0x2022, 0xB6, 0xDF, 0xAE, 0xA9, 0x2122, 0xB4, 0xA8, 0x2260, 0xC6, 0xD8,
  0x221E, 0xB1, 0x2264, 0x2265, 0xA5, 0xB5, 0x2202, 0x2211, 0x220F, 0x3C0, 0x222B, 0xAA, 0xBA, 0x3A9, 0xE6, 0xF8,
  0xBF, 0xA1, 0xAC, 0x221A, 0x192, 0x2248, 0x2206, 0xAB, 0xBB, 0x2026, 0xA0, 0xC0, 0xC3, 0xD5, 0x152, 0x153,
  0x2013, 0x2014, 0x201C, 0x201D, 0x2018, 0x2019, 0xF7, 0x25CA, 0xFF, 0x178, 0x2044, 0x20AC, 0x2039, 0x203A, 0xFB01, 0xFB02,
  0x2021, 0xB7, 0x201A, 0x201E, 0x2030, 0xC2, 0xCA, 0xC1, 0xCB, 0xC8, 0xCD, 0xCE, 0xCF, 0xCC, 0xD3, 0xD4,
  0xF8FF, 0xD2, 0xDA, 0xDB, 0xD9, 0x131, 0x2C6, 0x2DC, 0xAF, 0x2D8, 0x2D9, 0x2DA, 0xB8, 0x2DD, 0x2DB, 0x2C7]

const GlyphNames = {
  "space": " ", "exclam": "!", "quotedbl": "\"", "numbersign": "#", "dollar": "$", "percent": "%",
  "ampersand": "&", "quotesingle": "'", "quoteright": "’", "parenleft": "(", "parenright": ")",
  "asterisk": "*", "plus": "+", "comma": ",", "hyphen": "-", "period": ".", "slash": "/",
  "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6",
  "seven": "7", "eight": "8", "nine": "9", "colon": ":", "semicolon": ";", "less": "<", "equal": "=",
  "greater": ">", "question": "?", "at": "@", "bracketleft": "[", "backslash": "\\",
  "bracketright": "]", "asciicircum": "^", "underscore": "_", "grave": "`", "quoteleft": "‘",
  "braceleft": "{", "bar": "|", "braceright": "}", "asciitilde": "~", "bullet": "•",
  "endash": "–", "emdash": "—", "ellipsis": "…", "quotedblleft": "“", "quotedblright": "”",
  "quotesinglbase": "‚", "quotedblbase": "„", "guillemotleft": "«", "guillemotright": "»",
  "guilsinglleft": "‹", "guilsinglright": "›", "fi": "fi", "fl": "fl", "ff": "ff", "ffi": "ffi",
  "ffl": "ffl", "Euro": "€", "degree": "°", "copyright": "©", "registered": "®", "trademark": "™",
  "section": "§", "paragraph": "¶", "periodcentered": "·", "minus": "−", "multiply": "×",
  "divide": "÷", "plusminus": "±", "nbspace": " ", "dagger": "†", "daggerdbl": "‡",
  "oe": "œ", "OE": "Œ", "ae": "æ", "AE": "Æ", "germandbls": "ß", "dotlessi": "ı",
  "exclamdown": "¡", "questiondown": "¿", "cent": "¢", "sterling": "£", "yen": "¥",
  "florin": "ƒ", "perthousand": "‰", "onehalf": "½", "onequarter": "¼", "threequarters": "¾",
  "mu": "µ", "lslash": "ł", "Lslash": "Ł", "oslash": "ø", "Oslash": "Ø", "eth": "ð", "thorn": "þ",
  "Eth": "Ð", "Thorn": "Þ", "ordfeminine": "ª", "ordmasculine": "º", "logicalnot": "¬",
  "brokenbar": "¦", "dieresis": "¨", "acute": "´", "cedilla": "¸", "macron": "¯",
  "circumflex": "ˆ", "tilde": "˜", "fraction": "⁄", "currency": "¤", "breve": "˘",
  "dotaccent": "˙", "ring": "˚", "ogonek": "˛", "caron": "ˇ", "hungarumlaut": "˝"}.toTable

const AccentedGlyphs = {"Aacute": "Á", "Agrave": "À", "Acircumflex": "Â", "Adieresis": "Ä", "Atilde": "Ã", "Aring": "Å", "Acaron": "Ǎ", "Amacron": "Ā", "Abreve": "Ă", "Aogonek": "Ą", "Adotaccent": "Ȧ", "Bdotaccent": "Ḃ", "Cacute": "Ć", "Ccircumflex": "Ĉ", "Ccedilla": "Ç", "Ccaron": "Č", "Cdotaccent": "Ċ", "Dcedilla": "Ḑ", "Dcaron": "Ď", "Ddotaccent": "Ḋ", "Eacute": "É", "Egrave": "È", "Ecircumflex": "Ê", "Edieresis": "Ë", "Etilde": "Ẽ", "Ecedilla": "Ȩ", "Ecaron": "Ě", "Emacron": "Ē", "Ebreve": "Ĕ", "Eogonek": "Ę", "Edotaccent": "Ė", "Fdotaccent": "Ḟ", "Gacute": "Ǵ", "Gcircumflex": "Ĝ", "Gcedilla": "Ģ", "Gcaron": "Ǧ", "Gmacron": "Ḡ", "Gbreve": "Ğ", "Gdotaccent": "Ġ", "Hcircumflex": "Ĥ", "Hdieresis": "Ḧ", "Hcedilla": "Ḩ", "Hcaron": "Ȟ", "Hdotaccent": "Ḣ", "Iacute": "Í", "Igrave": "Ì", "Icircumflex": "Î", "Idieresis": "Ï", "Itilde": "Ĩ", "Icaron": "Ǐ", "Imacron": "Ī", "Ibreve": "Ĭ", "Iogonek": "Į", "Idotaccent": "İ", "Jcircumflex": "Ĵ", "Kacute": "Ḱ", "Kcedilla": "Ķ", "Kcaron": "Ǩ", "Lacute": "Ĺ", "Lcedilla": "Ļ", "Lcaron": "Ľ", "Macute": "Ḿ", "Mdotaccent": "Ṁ", "Nacute": "Ń", "Ngrave": "Ǹ", "Ntilde": "Ñ", "Ncedilla": "Ņ", "Ncaron": "Ň", "Ndotaccent": "Ṅ", "Oacute": "Ó", "Ograve": "Ò", "Ocircumflex": "Ô", "Odieresis": "Ö", "Otilde": "Õ", "Ocaron": "Ǒ", "Omacron": "Ō", "Obreve": "Ŏ", "Oogonek": "Ǫ", "Odotaccent": "Ȯ", "Pacute": "Ṕ", "Pdotaccent": "Ṗ", "Racute": "Ŕ", "Rcedilla": "Ŗ", "Rcaron": "Ř", "Rdotaccent": "Ṙ", "Sacute": "Ś", "Scircumflex": "Ŝ", "Scedilla": "Ş", "Scaron": "Š", "Sdotaccent": "Ṡ", "Tcedilla": "Ţ", "Tcaron": "Ť", "Tdotaccent": "Ṫ", "Uacute": "Ú", "Ugrave": "Ù", "Ucircumflex": "Û", "Udieresis": "Ü", "Utilde": "Ũ", "Uring": "Ů", "Ucaron": "Ǔ", "Umacron": "Ū", "Ubreve": "Ŭ", "Uogonek": "Ų", "Vtilde": "Ṽ", "Wacute": "Ẃ", "Wgrave": "Ẁ", "Wcircumflex": "Ŵ", "Wdieresis": "Ẅ", "Wdotaccent": "Ẇ", "Xdieresis": "Ẍ", "Xdotaccent": "Ẋ", "Yacute": "Ý", "Ygrave": "Ỳ", "Ycircumflex": "Ŷ", "Ydieresis": "Ÿ", "Ytilde": "Ỹ", "Ymacron": "Ȳ", "Ydotaccent": "Ẏ", "Zacute": "Ź", "Zcircumflex": "Ẑ", "Zcaron": "Ž", "Zdotaccent": "Ż", "aacute": "á", "agrave": "à", "acircumflex": "â", "adieresis": "ä", "atilde": "ã", "aring": "å", "acaron": "ǎ", "amacron": "ā", "abreve": "ă", "aogonek": "ą", "adotaccent": "ȧ", "bdotaccent": "ḃ", "cacute": "ć", "ccircumflex": "ĉ", "ccedilla": "ç", "ccaron": "č", "cdotaccent": "ċ", "dcedilla": "ḑ", "dcaron": "ď", "ddotaccent": "ḋ", "eacute": "é", "egrave": "è", "ecircumflex": "ê", "edieresis": "ë", "etilde": "ẽ", "ecedilla": "ȩ", "ecaron": "ě", "emacron": "ē", "ebreve": "ĕ", "eogonek": "ę", "edotaccent": "ė", "fdotaccent": "ḟ", "gacute": "ǵ", "gcircumflex": "ĝ", "gcedilla": "ģ", "gcaron": "ǧ", "gmacron": "ḡ", "gbreve": "ğ", "gdotaccent": "ġ", "hcircumflex": "ĥ", "hdieresis": "ḧ", "hcedilla": "ḩ", "hcaron": "ȟ", "hdotaccent": "ḣ", "iacute": "í", "igrave": "ì", "icircumflex": "î", "idieresis": "ï", "itilde": "ĩ", "icaron": "ǐ", "imacron": "ī", "ibreve": "ĭ", "iogonek": "į", "jcircumflex": "ĵ", "jcaron": "ǰ", "kacute": "ḱ", "kcedilla": "ķ", "kcaron": "ǩ", "lacute": "ĺ", "lcedilla": "ļ", "lcaron": "ľ", "macute": "ḿ", "mdotaccent": "ṁ", "nacute": "ń", "ngrave": "ǹ", "ntilde": "ñ", "ncedilla": "ņ", "ncaron": "ň", "ndotaccent": "ṅ", "oacute": "ó", "ograve": "ò", "ocircumflex": "ô", "odieresis": "ö", "otilde": "õ", "ocaron": "ǒ", "omacron": "ō", "obreve": "ŏ", "oogonek": "ǫ", "odotaccent": "ȯ", "pacute": "ṕ", "pdotaccent": "ṗ", "racute": "ŕ", "rcedilla": "ŗ", "rcaron": "ř", "rdotaccent": "ṙ", "sacute": "ś", "scircumflex": "ŝ", "scedilla": "ş", "scaron": "š", "sdotaccent": "ṡ", "tdieresis": "ẗ", "tcedilla": "ţ", "tcaron": "ť", "tdotaccent": "ṫ", "uacute": "ú", "ugrave": "ù", "ucircumflex": "û", "udieresis": "ü", "utilde": "ũ", "uring": "ů", "ucaron": "ǔ", "umacron": "ū", "ubreve": "ŭ", "uogonek": "ų", "vtilde": "ṽ", "wacute": "ẃ", "wgrave": "ẁ", "wcircumflex": "ŵ", "wdieresis": "ẅ", "wring": "ẘ", "wdotaccent": "ẇ", "xdieresis": "ẍ", "xdotaccent": "ẋ", "yacute": "ý", "ygrave": "ỳ", "ycircumflex": "ŷ", "ydieresis": "ÿ", "ytilde": "ỹ", "yring": "ẙ", "ymacron": "ȳ", "ydotaccent": "ẏ", "zacute": "ź", "zcircumflex": "ẑ", "zcaron": "ž", "zdotaccent": "ż"}.toTable

proc glyphToUnicode(nm: string): string =
  if nm.len == 1: return nm
  if GlyphNames.hasKey(nm): return GlyphNames[nm]
  if nm.startsWith("uni") and nm.len >= 7:
    var r = ""
    var k = 3
    while k + 4 <= nm.len:
      try: r.add $Rune(parseHexInt(nm[k ..< k + 4]))
      except ValueError: return ""
      k += 4
    return r
  if nm.startsWith("u") and nm.len in 5 .. 7:
    try: return $Rune(parseHexInt(nm[1 .. ^1]))
    except ValueError: discard
  if AccentedGlyphs.hasKey(nm): return AccentedGlyphs[nm]
  let dot = nm.find('.')
  if dot > 0: return glyphToUnicode(nm[0 ..< dot])
  let us = nm.find('_')
  if us > 0:
    for part in nm.split('_'): result.add glyphToUnicode(part)
    return
  ""

proc baseEncoding(f: Font, name: string) =
  for c in 0 .. 255:
    if c < 128:
      f.enc[c] = if c >= 32 and c < 127: $char(c) else: ""
    else:
      let cp = if name == "MacRomanEncoding": MacRomanHigh[c - 128] else: WinAnsiHigh[c - 128]
      f.enc[c] = if cp > 0: $Rune(cp) else: ""
  if name == "StandardEncoding":
    f.enc[0x27] = "’"
    f.enc[0x60] = "‘"
  f.hasEnc = true

# CMap ToUnicode

proc utf16beToUtf8(s: string): string =
  var i = 0
  while i + 1 < s.len:
    var cp = (ord(s[i]) shl 8) or ord(s[i + 1])
    i += 2
    if cp >= 0xD800 and cp <= 0xDBFF and i + 1 < s.len:
      let lo = (ord(s[i]) shl 8) or ord(s[i + 1])
      if lo >= 0xDC00 and lo <= 0xDFFF:
        cp = 0x10000 + ((cp - 0xD800) shl 10) + (lo - 0xDC00)
        i += 2
    if cp != 0: result.add $Rune(cp)
  if i < s.len and s.len == 1: result.add $Rune(ord(s[0]))

proc codeOf(s: string): int =
  for c in s: result = (result shl 8) or ord(c)

proc parseToUnicode(f: Font, cmap: string) =
  var lx = Lexer(s: addr cmap, i: 0)
  var stack: seq[PObj]
  var mode = ""
  var count = 0
  while lx.i < cmap.len:
    let o = lx.parseObj()
    if o.isNil: break
    if o.kind == pOp:
      case o.s
      of "begincodespacerange":
        mode = "space"
        stack.setLen(0)
      of "endcodespacerange":
        var k = 0
        while k + 1 < stack.len:
          if stack[k].kind == pStr and stack[k].s.len >= 2: f.codeBytes = 2
          k += 2
        mode = ""
        stack.setLen(0)
      of "beginbfchar", "beginbfrange":
        mode = o.s
        stack.setLen(0)
      of "endbfchar":
        var k = 0
        while k + 1 < stack.len:
          let src = stack[k]
          let dst = stack[k + 1]
          if src.kind == pStr:
            if src.s.len >= 2: f.twoByteRanges = true
            if dst.kind == pStr: f.toUni[codeOf(src.s)] = utf16beToUtf8(dst.s)
            elif dst.kind == pName: f.toUni[codeOf(src.s)] = glyphToUnicode(dst.s)
          k += 2
        stack.setLen(0)
        mode = ""
      of "endbfrange":
        var k = 0
        while k + 2 < stack.len:
          let lo = stack[k]
          let hi = stack[k + 1]
          let dst = stack[k + 2]
          if lo.kind == pStr and hi.kind == pStr:
            if lo.s.len >= 2: f.twoByteRanges = true
            let a = codeOf(lo.s)
            let b = min(codeOf(hi.s), a + 65535)
            if dst.kind == pStr:
              var base = dst.s
              for c in a .. b:
                f.toUni[c] = utf16beToUtf8(base)
                inc count
                if base.len >= 2:
                  # incrément du dernier caractère UTF-16
                  var v = (ord(base[^2]) shl 8) or ord(base[^1])
                  inc v
                  base[^2] = char((v shr 8) and 0xFF)
                  base[^1] = char(v and 0xFF)
            elif dst.kind == pArr:
              for j, x in dst.a:
                if a + j > b: break
                if x.kind == pStr: f.toUni[a + j] = utf16beToUtf8(x.s)
          k += 3
        stack.setLen(0)
        mode = ""
      else:
        if mode.len > 0: discard
    else:
      if mode.len > 0: stack.add o

# polices

proc loadFont(p: Pdf, fd: PObj): Font =
  result = Font(codeBytes: 1, defaultWidth: 500, spaceCode: 32)
  let f = result
  if fd.isNil or fd.kind != pDict: return
  let subtype = p.dget(fd, "Subtype").name
  var descendant: PObj = nil
  if subtype == "Type0":
    f.composite = true
    f.codeBytes = 2
    f.defaultWidth = 1000
    let df = p.dget(fd, "DescendantFonts")
    if not df.isNil and df.kind == pArr and df.a.len > 0: descendant = p.resolve(df.a[0])
    if not descendant.isNil:
      f.defaultWidth = p.dget(descendant, "DW").num(1000)
      let w = p.dget(descendant, "W")
      if not w.isNil and w.kind == pArr:
        var k = 0
        while k < w.a.len:
          let first = int(p.resolve(w.a[k]).num(0))
          if k + 1 >= w.a.len: break
          let nx = p.resolve(w.a[k + 1])
          if not nx.isNil and nx.kind == pArr:
            for j, x in nx.a: f.widths[first + j] = p.resolve(x).num(f.defaultWidth)
            k += 2
          else:
            if k + 2 >= w.a.len: break
            let last = int(nx.num(0))
            let wv = p.resolve(w.a[k + 2]).num(f.defaultWidth)
            for c in first .. min(last, first + 65535): f.widths[c] = wv
            k += 3
    let encName = p.dget(fd, "Encoding").name
    if encName.len > 0 and not encName.startsWith("Identity") and not encName.endsWith("-H") and not encName.endsWith("-V"):
      f.codeBytes = 1
  else:
    let fc = int(p.dget(fd, "FirstChar").num(0))
    let ws = p.dget(fd, "Widths")
    var scale = 1.0
    if subtype == "Type3":
      # largeurs dans l'espace des glyphes : FontMatrix les ramène en millièmes
      let fm = p.dget(fd, "FontMatrix")
      if not fm.isNil and fm.kind == pArr and fm.a.len >= 1: scale = abs(p.resolve(fm.a[0]).num(0.001)) * 1000
    if not ws.isNil and ws.kind == pArr:
      for j, x in ws.a: f.widths[fc + j] = p.resolve(x).num(0) * scale
    let desc = p.dget(fd, "FontDescriptor")
    let mw = p.dget(desc, "MissingWidth").num(0)
    if mw > 0: f.defaultWidth = mw
    # encodage
    let enc = p.dget(fd, "Encoding")
    var baseName = "StandardEncoding"
    let flags = int(p.dget(desc, "Flags").num(0))
    if (flags and 4) != 0 and subtype != "TrueType": baseName = "Symbolic"
    if subtype == "TrueType" or subtype == "Type1" or subtype == "MMType1": baseName = "WinAnsiEncoding"
    if not enc.isNil and enc.kind == pName: baseName = enc.s
    elif not enc.isNil and enc.kind == pDict:
      let be = p.dget(enc, "BaseEncoding").name
      if be.len > 0: baseName = be
    f.baseEncoding(baseName)
    if not enc.isNil and enc.kind == pDict:
      let diffs = p.dget(enc, "Differences")
      if not diffs.isNil and diffs.kind == pArr:
        var code = 0
        for x0 in diffs.a:
          let x = p.resolve(x0)
          if x.isNil: continue
          if x.kind == pNum: code = int(x.n)
          elif x.kind == pName:
            if code in 0 .. 255:
              let u = glyphToUnicode(x.s)
              f.enc[code] = u
              if x.s == "space": f.spaceCode = code
            inc code
  let tu = p.dget(fd, "ToUnicode")
  if not tu.isNil and tu.kind == pDict and tu.hasStream:
    let cm = p.decodeStream(tu)
    let wasComposite = f.composite
    let before = f.codeBytes
    f.codeBytes = if wasComposite: before else: 1
    f.parseToUnicode(cm)
    if not wasComposite: f.codeBytes = (if f.twoByteRanges: 2 else: 1)
    elif f.codeBytes != before and not f.twoByteRanges: f.codeBytes = before

proc decodeText(f: Font, s: string): seq[(int, string)] =
  ## Codes et texte Unicode de chaque glyphe.
  var i = 0
  let nb = if f.isNil: 1 else: f.codeBytes
  while i < s.len:
    var code: int
    if nb == 2 and i + 1 < s.len:
      code = (ord(s[i]) shl 8) or ord(s[i + 1])
      i += 2
    else:
      code = ord(s[i])
      inc i
    var u = ""
    if not f.isNil and f.toUni.hasKey(code):
      u = f.toUni[code]
      # zone à usage privé (variantes de glyphes) : le nom du glyphe dit mieux
      if u.len > 0 and f.hasEnc and code < 256 and f.enc[code].len > 0:
        let r = u.runeAt(0).int
        if r >= 0xE000 and r <= 0xF8FF: u = f.enc[code]
    elif not f.isNil and f.hasEnc and code < 256: u = f.enc[code]
    elif f.isNil or not f.composite:
      if code >= 32 and code < 127: u = $char(code)
      elif code >= 128 and code < 256 and WinAnsiHigh[code - 128] > 0: u = $Rune(WinAnsiHigh[code - 128])
    result.add (code, u)

proc width(f: Font, code: int): float =
  if f.isNil: return 500
  f.widths.getOrDefault(code, f.defaultWidth)

# contenu

type
  Mat = array[6, float]
  GState = object
    ctm: Mat

  TextRun = object
    x, y: float           # début (espace page)
    xend: float
    size: float
    text: string

  Extractor = object
    p: Pdf
    runs: seq[TextRun]
    fonts: Table[string, Font]
    depth: int

const Ident: Mat = [1.0, 0, 0, 1, 0, 0]

proc mul(a, b: Mat): Mat =
  [a[0] * b[0] + a[1] * b[2], a[0] * b[1] + a[1] * b[3],
   a[2] * b[0] + a[3] * b[2], a[2] * b[1] + a[3] * b[3],
   a[4] * b[0] + a[5] * b[2] + b[4], a[4] * b[1] + a[5] * b[3] + b[5]]

proc fontFor(e: var Extractor, res: PObj, name: string): Font =
  let fontsDict = e.p.dget(res, "Font")
  let fref = fontsDict.get(name)
  var key = name
  if not fref.isNil and fref.kind == pRef: key = "#" & $fref.num
  if e.fonts.hasKey(key): return e.fonts[key]
  result = e.p.loadFont(e.p.resolve(fref))
  e.fonts[key] = result

const PdfDocHigh: array[0x80 .. 0xA0, int] = [
  0x2022, 0x2020, 0x2021, 0x2026, 0x2014, 0x2013, 0x0192, 0x2044, 0x2039, 0x203A, 0x2212,
  0x2030, 0x201E, 0x201C, 0x201D, 0x2018, 0x2019, 0x201A, 0x2122, 0xFB01, 0xFB02, 0x0141,
  0x0152, 0x0160, 0x0178, 0x017D, 0x0131, 0x0142, 0x0153, 0x0161, 0x017E, 0, 0x20AC]

proc pdfStringFwd(s: string): string =
  ## Chaîne de texte PDF (Info, ActualText) : UTF-16BE avec BOM, UTF-8 avec BOM
  ## (PDF 2.0) ou PDFDocEncoding (Latin-1, sauf 0x80-0xA0).
  if s.len >= 2 and s[0] == '\xFE' and s[1] == '\xFF': return utf16beToUtf8(s[2 .. ^1])
  if s.len >= 3 and s[0] == '\xEF' and s[1] == '\xBB' and s[2] == '\xBF': return s[3 .. ^1]
  for c in s:
    let o = ord(c)
    if o < 128: result.add c
    elif o <= 0xA0:
      if PdfDocHigh[o] > 0: result.add $Rune(PdfDocHigh[o])
    else: result.add $Rune(o)

proc runContent(e: var Extractor, content: string, res: PObj, base: Mat) =
  inc e.depth
  if e.depth > 12:
    dec e.depth
    return
  var lx = Lexer(s: addr content, i: 0)
  var operands: seq[PObj]
  var gs = GState(ctm: base)
  var stack: seq[GState]
  var tm, tlm: Mat = Ident
  var font: Font = nil
  var fsize = 12.0
  var charSp, wordSp, leading, rise = 0.0
  var hscale = 1.0
  var inText = false
  var marks: seq[tuple[active: bool, text: string, emitted: bool]]   # BDC/BMC ... EMC
  proc showString(e: var Extractor, s: string, tm: var Mat) =
    if s.len == 0: return
    let trm = mul([fsize * hscale, 0, 0, fsize, 0, rise], mul(tm, gs.ctm))
    let size = sqrt(trm[2] * trm[2] + trm[3] * trm[3])
    var txt = ""
    var adv = 0.0
    for (code, u) in font.decodeText(s):
      txt.add u
      var w = font.width(code) / 1000.0 * fsize + charSp
      if (font.isNil or font.codeBytes == 1) and code == 32: w += wordSp
      adv += w * hscale
    let x0 = trm[4]
    let y0 = trm[5]
    tm = mul([1.0, 0, 0, 1, adv, 0], tm)
    let tEnd = mul([fsize * hscale, 0, 0, fsize, 0, rise], mul(tm, gs.ctm))
    # repère de lecture : u = direction d'écriture (texte tourné, vertical)
    var ux = trm[0]
    var uy = trm[1]
    let nu = sqrt(ux * ux + uy * uy)
    if nu > 0:
      ux /= nu
      uy /= nu
    else:
      ux = 1
      uy = 0
    let along = x0 * ux + y0 * uy
    let across = -x0 * uy + y0 * ux
    let alongEnd = tEnd[4] * ux + tEnd[5] * uy
    # /ActualText : le texte remplace celui des glyphes du marquage
    for k in countdown(marks.high, 0):
      if marks[k].active:
        txt = if marks[k].emitted: "" else: marks[k].text
        marks[k].emitted = true
        break
    e.runs.add TextRun(x: along, y: across, xend: alongEnd, size: max(1.0, size), text: txt)
  while true:
    lx.skipWs()
    if lx.i >= content.len: break
    # images en ligne : BI ... ID <données> EI
    let o = lx.parseObj()
    if o.isNil: break
    if o.kind != pOp:
      operands.add o
      continue
    let op = o.s
    template nArg(k: int): float =
      (if operands.len > k and operands[k].kind == pNum: operands[k].n else: 0.0)
    case op
    of "BDC":
      var t = ""
      var act = false
      if operands.len >= 2:
        var pd = operands[1]
        if pd.kind == pName: pd = e.p.dget(e.p.dget(res, "Properties"), pd.s)
        let at = e.p.dget(pd, "ActualText")
        if not at.isNil and at.kind == pStr:
          t = pdfStringFwd(at.s)
          act = true
      marks.add (act, t, false)
    of "BMC": marks.add (false, "", false)
    of "EMC":
      if marks.len > 0: discard marks.pop()
    of "BI":
      let ei = content.find("EI", lx.i)
      lx.i = if ei < 0: content.len else: ei + 2
    of "q": stack.add gs
    of "Q":
      if stack.len > 0: gs = stack.pop()
    of "cm":
      if operands.len >= 6:
        gs.ctm = mul([nArg(0), nArg(1), nArg(2), nArg(3), nArg(4), nArg(5)], gs.ctm)
    of "BT":
      inText = true
      tm = Ident
      tlm = Ident
    of "ET": inText = false
    of "Tf":
      if operands.len >= 2:
        if operands[0].kind == pName: font = e.fontFor(res, operands[0].s)
        fsize = nArg(1)
        if fsize == 0: fsize = 1
    of "Tc": charSp = nArg(0)
    of "Tw": wordSp = nArg(0)
    of "Tz": hscale = nArg(0) / 100.0
    of "TL": leading = nArg(0)
    of "Ts": rise = nArg(0)
    of "Td":
      tlm = mul([1.0, 0, 0, 1, nArg(0), nArg(1)], tlm)
      tm = tlm
    of "TD":
      leading = -nArg(1)
      tlm = mul([1.0, 0, 0, 1, nArg(0), nArg(1)], tlm)
      tm = tlm
    of "Tm":
      if operands.len >= 6:
        tlm = [nArg(0), nArg(1), nArg(2), nArg(3), nArg(4), nArg(5)]
        tm = tlm
    of "T*":
      tlm = mul([1.0, 0, 0, 1, 0, -leading], tlm)
      tm = tlm
    of "Tj":
      if operands.len >= 1 and operands[0].kind == pStr: e.showString(operands[0].s, tm)
    of "'":
      tlm = mul([1.0, 0, 0, 1, 0, -leading], tlm)
      tm = tlm
      if operands.len >= 1 and operands[^1].kind == pStr: e.showString(operands[^1].s, tm)
    of "\"":
      if operands.len >= 3:
        wordSp = nArg(0)
        charSp = nArg(1)
      tlm = mul([1.0, 0, 0, 1, 0, -leading], tlm)
      tm = tlm
      if operands.len >= 1 and operands[^1].kind == pStr: e.showString(operands[^1].s, tm)
    of "TJ":
      if operands.len >= 1 and operands[0].kind == pArr:
        for x in operands[0].a:
          if x.kind == pStr: e.showString(x.s, tm)
          elif x.kind == pNum:
            let shift = -x.n / 1000.0 * fsize * hscale
            tm = mul([1.0, 0, 0, 1, shift, 0], tm)
    of "Do":
      if operands.len >= 1 and operands[0].kind == pName:
        let xo = e.p.dget(e.p.dget(res, "XObject"), operands[0].s)
        if not xo.isNil and xo.kind == pDict and e.p.dget(xo, "Subtype").name == "Form" and xo.hasStream:
          var m = Ident
          let mo = e.p.dget(xo, "Matrix")
          if not mo.isNil and mo.kind == pArr and mo.a.len == 6:
            for k in 0 .. 5: m[k] = e.p.resolve(mo.a[k]).num(0)
          var r2 = e.p.dget(xo, "Resources")
          if r2.isNil: r2 = res
          let saved = e.fonts
          e.runContent(e.p.decodeStream(xo), r2, mul(m, gs.ctm))
          e.fonts = saved
    else: discard
    operands.setLen(0)
  dec e.depth

proc assemble(runs: seq[TextRun]): string =
  ## Lignes reconstituées d'après les positions : tri par ligne (y décroissant),
  ## puis par x ; espaces d'après les écarts, paragraphes d'après les interlignes.
  if runs.len == 0: return ""
  # regroupement en lignes dans l'ordre du flux (la plupart des PDF écrivent
  # dans l'ordre de lecture) ; une forte remontée de y ou un saut crée une ligne.
  var lines: seq[seq[TextRun]]
  var cur: seq[TextRun]
  var lineY = runs[0].y
  var lineSize = runs[0].size
  for r in runs:
    if r.text.len == 0: continue
    if cur.len > 0 and abs(r.y - lineY) > max(lineSize, r.size) * 0.5:
      lines.add cur
      cur = @[]
    if cur.len == 0:
      lineY = r.y
      lineSize = r.size
    cur.add r
  if cur.len > 0: lines.add cur
  var prevY = NaN
  var prevSize = 0.0
  for ln in lines:
    var s = ""
    var lastEnd = NaN
    var lastSize = ln[0].size
    # écart typique entre glyphes de la ligne (texte espacé : titres en capitales),
    # seulement si la ligne est faite de glyphes isolés : quand chaque morceau est
    # un mot (texte justifié mot à mot), les écarts sont des espaces.
    var gaps: seq[float]
    var single = 0
    for k in 0 ..< ln.len:
      if ln[k].text.runeLen <= 1: inc single
      if k > 0:
        let g = ln[k].x - ln[k - 1].xend
        if g > 0: gaps.add g / ln[k].size
    var typical = 0.0
    if gaps.len >= 4 and single * 10 >= ln.len * 6:
      gaps.sort()
      typical = gaps[gaps.len div 3]
    let wordGap = max(0.18, typical * 1.6 + 0.06)
    for r in ln:
      if s.len > 0 and not lastEnd.isNaN:
        let gap = r.x - lastEnd
        if gap > r.size * wordGap and not s.endsWith(" ") and not r.text.startsWith(" "): s.add " "
        elif gap < -r.size * 2 and not s.endsWith(" "): s.add " "
      s.add r.text
      lastEnd = r.xend
      lastSize = r.size
    let y = ln[0].y
    if result.len > 0:
      let dy = abs(prevY - y)
      if not prevY.isNaN and dy > max(prevSize, lastSize) * 1.9: result.add "\n\n"
      else: result.add "\n"
    result.add s.strip(leading = false)
    prevY = y
    prevSize = lastSize

proc pageList(p: Pdf, node: PObj, inheritedRes: PObj, acc: var seq[(PObj, PObj)], seen: var HashSet[int], depth = 0) =
  if node.isNil or depth > 50: return
  var res = p.dget(node, "Resources")
  if res.isNil: res = inheritedRes
  let t = p.dget(node, "Type").name
  let kids = p.dget(node, "Kids")
  if t == "Page" or (kids.isNil and not p.dget(node, "Contents").isNil):
    acc.add (node, res)
    return
  if not kids.isNil and kids.kind == pArr:
    for k in kids.a:
      if k.kind == pRef:
        if k.num in seen: continue
        seen.incl k.num
      p.pageList(p.resolve(k), res, acc, seen, depth + 1)

proc pdfString(s: string): string = pdfStringFwd(s)

proc dehyphenate(s: string): string =
  ## « exem-\nple » -> « exemple » (coupure de fin de ligne suivie d'une minuscule).
  var i = 0
  while i < s.len:
    if s[i] == '-' and i + 1 < s.len and s[i + 1] == '\n' and i > 0 and s[i - 1] in Letters and
       i + 2 < s.len and s[i + 2] in {'a'..'z'}:
      i += 2
      continue
    result.add s[i]
    inc i

proc extractPdf*(data: string, maxPages = 0): PdfDoc =
  let p = openPdf(data)
  if p.encrypted: perr("PDF chiffré : texte inaccessible")
  var root: PObj = nil
  for t in countdown(p.roots.high, 0):
    let r = p.dget(p.roots[t], "Root")
    if not r.isNil and r.kind == pDict:
      root = r
      let inf = p.dget(p.roots[t], "Info")
      if not inf.isNil: p.info = inf
      break
  if root.isNil: perr("PDF illisible : catalogue introuvable")
  if not p.info.isNil:
    let ti = p.dget(p.info, "Title")
    if not ti.isNil and ti.kind == pStr: result.title = pdfString(ti.s).strip
    let au = p.dget(p.info, "Author")
    if not au.isNil and au.kind == pStr: result.author = pdfString(au.s).strip
  var pages: seq[(PObj, PObj)]
  var seen = initHashSet[int]()
  p.pageList(p.dget(root, "Pages"), nil, pages, seen)
  for k, (pg, res) in pages:
    if maxPages > 0 and k >= maxPages: break
    var e = Extractor(p: p)
    let c = p.dget(pg, "Contents")
    var content = ""
    if not c.isNil:
      if c.kind == pArr:
        for x in c.a:
          content.add p.decodeStream(p.resolve(x))
          content.add "\n"
      else: content = p.decodeStream(c)
    try:
      e.runContent(content, res, Ident)
    except CatchableError: discard
    result.pages.add dehyphenate(assemble(e.runs))
