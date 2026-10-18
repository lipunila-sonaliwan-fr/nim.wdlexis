# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - images de l'atelier (icônes des applications générées)
#
#   loadImage(chemin)                     PNG, JPEG, BMP, GIF, TGA -> RGBA
#   cropImage(img, cadrage)               partie carrée retenue de l'image
#   resized(img, n)                       redimensionnement n x n (filtre sRGB)
#   encodePng(img)                        PNG (chaîne binaire)
#   makeIco(img) / makeIcns(img)          icônes Windows / macOS
#   deflateRaw(données)                   compression « deflate » (archives)
#
# Repose sur stb_image, stb_image_resize2 et stb_image_write (domaine public / MIT).

import std/[strutils, math]

{.compile: "stb/stb_impl.c".}

type
  RgbaImage* = object
    w*, h*: int
    px*: seq[uint8]              # RGBA, ligne par ligne (w * h * 4 octets).

  Crop* = object
    # Cadrage carré, en fractions de l'image : left = x / largeur,
    # top = y / hauteur, side = côté / min(largeur, hauteur).
    left*, top*, side*: float

proc stbi_load_from_memory(buf: ptr uint8, len: cint, x, y, comp: ptr cint,
                           req: cint): ptr UncheckedArray[uint8] {.importc, cdecl.}
proc stbi_failure_reason(): cstring {.importc, cdecl.}
proc wdlx_stb_free(p: pointer) {.importc, cdecl.}
proc wdlx_stb_png_level(level: cint) {.importc, cdecl.}
proc stbir_resize_uint8_srgb(input: ptr uint8, iw, ih, istride: cint, output: ptr uint8,
                             ow, oh, ostride: cint, layout: cint): ptr uint8 {.importc, cdecl.}
type StbWriteFunc = proc (ctx: pointer, data: pointer, size: cint) {.cdecl.}
proc stbi_write_png_to_func(f: StbWriteFunc, ctx: pointer, w, h, comp: cint, data: pointer,
                            stride: cint): cint {.importc, cdecl.}
proc stbi_zlib_compress(data: ptr uint8, len: cint, outLen: ptr cint,
                        quality: cint): ptr UncheckedArray[uint8] {.importc, cdecl.}

const StbirRgba = 4.cint

proc fullCrop*(): Crop = Crop(left: 0, top: 0, side: 1)

proc decodeImage*(data: string): RgbaImage =
  if data.len == 0: raise newException(ValueError, "image vide")
  var w, h, comp: cint
  let p = stbi_load_from_memory(cast[ptr uint8](unsafeAddr data[0]), cint(data.len),
                                addr w, addr h, addr comp, 4)
  if p.isNil:
    raise newException(ValueError, "format d'image non reconnu (" & $stbi_failure_reason() & ")")
  result.w = int(w)
  result.h = int(h)
  result.px = newSeq[uint8](result.w * result.h * 4)
  copyMem(addr result.px[0], p, result.px.len)
  wdlx_stb_free(p)

proc loadImage*(path: string): RgbaImage =
  decodeImage(readFile(path))

proc normalized*(c: Crop, w, h: int): Crop =
  # Cadrage ramené dans l'image (côté au moins 1 pixel).
  result = c
  let m = float(min(w, h))
  if m <= 0: return fullCrop()
  if result.side <= 0 or result.side > 1: result.side = 1
  let sidePx = max(1.0, result.side * m)
  result.side = sidePx / m
  let maxLeft = max(0.0, (float(w) - sidePx) / float(w))
  let maxTop = max(0.0, (float(h) - sidePx) / float(h))
  result.left = clamp(result.left, 0.0, maxLeft)
  result.top = clamp(result.top, 0.0, maxTop)

proc centeredCrop*(w, h: int): Crop =
  # Plus grand carré centré.
  let m = float(min(w, h))
  Crop(left: (float(w) - m) / 2 / float(max(1, w)), top: (float(h) - m) / 2 / float(max(1, h)), side: 1)

proc cropImage*(img: RgbaImage, c0: Crop): RgbaImage =
  let c = c0.normalized(img.w, img.h)
  let side = max(1, int(round(c.side * float(min(img.w, img.h)))))
  let x0 = clamp(int(round(c.left * float(img.w))), 0, max(0, img.w - side))
  let y0 = clamp(int(round(c.top * float(img.h))), 0, max(0, img.h - side))
  result.w = side
  result.h = side
  result.px = newSeq[uint8](side * side * 4)
  for y in 0 ..< side:
    copyMem(addr result.px[y * side * 4], unsafeAddr img.px[((y0 + y) * img.w + x0) * 4], side * 4)

proc resized*(img: RgbaImage, w, h: int): RgbaImage =
  result.w = w
  result.h = h
  result.px = newSeq[uint8](w * h * 4)
  if img.w == w and img.h == h:
    result.px = img.px
    return
  let r = stbir_resize_uint8_srgb(unsafeAddr img.px[0], cint(img.w), cint(img.h), cint(img.w * 4),
                                  addr result.px[0], cint(w), cint(h), cint(w * 4), StbirRgba)
  if r.isNil: raise newException(ValueError, "redimensionnement impossible")

proc resized*(img: RgbaImage, n: int): RgbaImage = img.resized(n, n)

proc pngWrite(ctx: pointer, data: pointer, size: cint) {.cdecl.} =
  let s = cast[ptr string](ctx)
  let old = s[].len
  s[].setLen(old + int(size))
  if size > 0: copyMem(addr s[][old], data, int(size))

proc encodePng*(img: RgbaImage): string =
  wdlx_stb_png_level(9)
  if stbi_write_png_to_func(pngWrite, addr result, cint(img.w), cint(img.h), 4,
                            unsafeAddr img.px[0], cint(img.w * 4)) == 0:
    raise newException(ValueError, "écriture PNG impossible")

#
# Icônes
#

proc le16(s: var string, v: int) =
  s.add char(v and 0xFF)
  s.add char((v shr 8) and 0xFF)

proc le32(s: var string, v: int) =
  for i in 0 .. 3: s.add char((v shr (8 * i)) and 0xFF)

proc be32(s: var string, v: int) =
  for i in countdown(3, 0): s.add char((v shr (8 * i)) and 0xFF)

const IcoSizes* = [16, 24, 32, 48, 64, 128, 256]

proc makeIco*(square: RgbaImage): string =
  # Icône Windows (.ico) : une entrée PNG par taille (Windows Vista et suivants).
  var pngs: seq[string]
  for n in IcoSizes: pngs.add encodePng(square.resized(n))
  result.le16 0
  result.le16 1                         # type : icône
  result.le16 IcoSizes.len
  var offset = 6 + 16 * IcoSizes.len
  for i, n in IcoSizes:
    result.add char(if n >= 256: 0 else: n)
    result.add char(if n >= 256: 0 else: n)
    result.add char(0)                  # palette
    result.add char(0)
    result.le16 1                       # plans
    result.le16 32                      # bits par pixel
    result.le32 pngs[i].len
    result.le32 offset
    offset += pngs[i].len
  for p in pngs: result.add p

proc makeIcns*(square: RgbaImage): string =
  # Icône macOS (.icns) : entrées PNG (macOS 10.7 et suivants).
  const entries = [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256),
                   ("ic09", 512), ("ic10", 1024), ("ic11", 32), ("ic12", 64), ("ic13", 256),
                   ("ic14", 512)]
  var cache: seq[(int, string)]
  proc pngOf(n: int): string =
    for (k, v) in cache:
      if k == n: return v
    result = encodePng(square.resized(n))
    cache.add (n, result)
  var body = ""
  for (kind, n) in entries:
    let p = pngOf(n)
    body.add kind
    body.be32(p.len + 8)
    body.add p
  result = "icns"
  result.be32(body.len + 8)
  result.add body

#
# Compression
#

proc deflateRaw*(data: string, quality = 8): string =
  # Flux « deflate » brut (sans en-tête zlib), pour zip et gzip.
  if data.len == 0: return "\x03\x00"                             # bloc final fixe vide.
  var outLen: cint
  let p = stbi_zlib_compress(cast[ptr uint8](unsafeAddr data[0]), cint(data.len), addr outLen, cint(quality))
  if p.isNil or outLen < 6: raise newException(ValueError, "compression impossible")
  result = newString(int(outLen) - 6)
  if result.len > 0: copyMem(addr result[0], addr p[2], result.len)   # en-tête zlib (2) et adler32 (4) retirés.
  wdlx_stb_free(p)

var crcTable: array[256, uint32]
block:
  for i in 0 ..< 256:
    var c = uint32(i)
    for _ in 0 ..< 8:
      c = if (c and 1) != 0: 0xEDB88320'u32 xor (c shr 1) else: c shr 1
    crcTable[i] = c

proc crc32*(data: string): uint32 =
  var c = 0xFFFFFFFF'u32
  {.cast(gcsafe).}:
    for ch in data: c = crcTable[int((c xor uint32(ord(ch))) and 0xFF)] xor (c shr 8)
  c xor 0xFFFFFFFF'u32

proc isImageFile*(path: string): bool =
  path.toLowerAscii.endsWith(".png") or path.toLowerAscii.endsWith(".jpg") or
    path.toLowerAscii.endsWith(".jpeg") or path.toLowerAscii.endsWith(".bmp") or
    path.toLowerAscii.endsWith(".gif") or path.toLowerAscii.endsWith(".tga")
