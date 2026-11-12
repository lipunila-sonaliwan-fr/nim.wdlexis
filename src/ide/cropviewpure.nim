# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - cadrage d'une image pour les programmes Lexis+ (ui.cadrage)
#
#   Même contrôle que ide/cropview (boîte « Générer l'application » de l'atelier
#   natif), mais en Nim pur : il entre dans le runtime des applications générées,
#   transpilé en C sans les en-têtes de stb. Images : PNG, JPEG (ide/imagedecode),
#   GIF (ide/imagepure).
#
#   L'image est affichée entière ; un cadre carré indique la partie retenue.
#   Glisser dans le cadre : le déplacer ; glisser la poignée (coin bas droit)
#   ou la molette : changer sa taille ; clic hors du cadre : le centrer là.
#   Chaque modification émet evChange (texte = "gauche,haut,cote").

import std/[strutils, math, os]
import ../wdgui
import ../sdl3
import imagedecode
from imagepure import decodeGif

type
  Crop* = object
    # fractions de l'image : left = x / largeur, top = y / hauteur, side = côté / min(largeur, hauteur)
    left*, top*, side*: float

proc fullCrop*(): Crop = Crop(left: 0, top: 0, side: 1)

proc normalized*(c: Crop, w, h: int): Crop =
  # Cadrage ramené dans l'image (côté au moins 1 pixel) - comme ide/imagetools.
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

proc parseCrop*(s: string, w, h: int): Crop =
  ## « gauche,haut,cote » ; vide ou invalide : le plus grand carré centré.
  result = centeredCrop(w, h)
  let n = s.split(',')
  if n.len == 3:
    try:
      result = Crop(left: parseFloat(n[0].strip), top: parseFloat(n[1].strip),
                    side: parseFloat(n[2].strip)).normalized(w, h)
    except ValueError: discard

proc loadCropImage*(path: string): RgbaImage =
  ## PNG, JPEG ou GIF (première image) ; ValueError / IOError sinon.
  let data = readFile(path)
  if data.len > 3 and data[0 .. 2] == "GIF": decodeGif(data)
  else: decodeImageData(data)

proc shrinkTo(img: RgbaImage, w, h: int): RgbaImage =
  # Réduction par moyenne des pixels (aperçu seulement).
  result = RgbaImage(w: w, h: h, px: newSeq[uint8](w * h * 4))
  for y in 0 ..< h:
    let y0 = y * img.h div h
    let y1 = max(y0 + 1, (y + 1) * img.h div h)
    for x in 0 ..< w:
      let x0 = x * img.w div w
      let x1 = max(x0 + 1, (x + 1) * img.w div w)
      var acc: array[4, int]
      for sy in y0 ..< y1:
        for sx in x0 ..< x1:
          let i = (sy * img.w + sx) * 4
          for k in 0 .. 3: acc[k] += int(img.px[i + k])
      let n = (y1 - y0) * (x1 - x0)
      let o = (y * w + x) * 4
      for k in 0 .. 3: result.px[o + k] = uint8(acc[k] div n)

const
  PixelRgba = 0x16762004'u32      # SDL_PIXELFORMAT_ABGR8888 : octets R, G, B, A en mémoire.
  MaxDisplay = 640                # l'aperçu est réduit au-delà (le cadrage reste en fractions).
  HandleSize = 12.0

type
  DragMode = enum dmNone, dmMove, dmResize

  PureCropView* = ref object of Control
    img: RgbaImage                # image d'aperçu (éventuellement réduite).
    srcW, srcH: int               # taille de l'image d'origine.
    hasImage: bool
    crop*: Crop
    tex: SDL_Texture
    texRen: SDL_Renderer
    texDirty: bool
    drag: DragMode
    grabX, grabY: float           # décalage de la saisie dans le cadre.
    placeholder*: string

proc newPureCropView*(placeholder = "Aucune image"): PureCropView =
  result = PureCropView(crop: fullCrop(), placeholder: placeholder)
  initControl(result)
  result.focusable = true

method typeName*(c: PureCropView): string = "Cadrage"

method preferredSize*(c: PureCropView, d: Drawing, t: Theme): tuple[w, h: float] = (220.0, 160.0)

proc imageRect(c: PureCropView): Rect =
  let r = c.rect.shrink(4)
  if not c.hasImage or c.img.w == 0 or c.img.h == 0: return r
  let k = min(r.w / float(c.img.w), r.h / float(c.img.h))
  let w = float(c.img.w) * k
  let h = float(c.img.h) * k
  rect(r.x + (r.w - w) / 2, r.y + (r.h - h) / 2, w, h)

proc cropRect(c: PureCropView): Rect =
  let ir = c.imageRect
  let side = c.crop.side * min(ir.w, ir.h)
  rect(ir.x + c.crop.left * ir.w, ir.y + c.crop.top * ir.h, side, side)

method draw*(c: PureCropView, d: Drawing, t: Theme) =
  let r = c.rect
  d.fillRoundRect(r, 6, t.border)
  d.fillRoundRect(r.shrink(1), 5, if t.dark: hex"#2A2A2E" else: hex"#ECECEF")
  if not c.hasImage:
    d.textIn(r, c.placeholder, t.textDisabled, alCenter)
    return
  if c.texDirty or c.tex == nil or c.texRen != d.ren:
    if c.tex != nil: SDL_DestroyTexture(c.tex)
    c.tex = SDL_CreateTexture(d.ren, PixelRgba, SDL_TEXTUREACCESS_STATIC, cint(c.img.w), cint(c.img.h))
    if c.tex != nil:
      discard SDL_UpdateTexture(c.tex, nil, addr c.img.px[0], cint(c.img.w * 4))
    c.texRen = d.ren
    c.texDirty = false
  let ir = c.imageRect
  if c.tex != nil: d.drawTexture(c.tex, ir)
  let cr = c.cropRect
  let shade = withAlpha(Black, if c.isGrayed: 150 else: 120)
  # assombrit ce qui n'est pas retenu
  d.fillRect(rect(ir.x, ir.y, ir.w, max(0.0, cr.y - ir.y)), shade)
  d.fillRect(rect(ir.x, cr.y + cr.h, ir.w, max(0.0, ir.y + ir.h - cr.y - cr.h)), shade)
  d.fillRect(rect(ir.x, cr.y, max(0.0, cr.x - ir.x), cr.h), shade)
  d.fillRect(rect(cr.x + cr.w, cr.y, max(0.0, ir.x + ir.w - cr.x - cr.w), cr.h), shade)
  if c.isGrayed: return
  let acc = c.style.accent.get(t.accent)
  d.strokeRect(cr, White, 2)
  d.strokeRect(cr.shrink(-1), acc, 1)
  # tiers (aide au cadrage)
  for i in 1 .. 2:
    let fx = cr.x + cr.w * float(i) / 3
    let fy = cr.y + cr.h * float(i) / 3
    d.line(fx, cr.y, fx, cr.y + cr.h, withAlpha(White, 90))
    d.line(cr.x, fy, cr.x + cr.w, fy, withAlpha(White, 90))
  d.fillRect(rect(cr.x + cr.w - HandleSize / 2, cr.y + cr.h - HandleSize / 2, HandleSize, HandleSize), acc)
  d.strokeRect(rect(cr.x + cr.w - HandleSize / 2, cr.y + cr.h - HandleSize / 2, HandleSize, HandleSize), White, 1)

proc changed(c: PureCropView) =
  c.crop = c.crop.normalized(c.srcW, c.srcH)
  emit(c, evChange, text = formatFloat(c.crop.left, ffDecimal, 5) & "," &
       formatFloat(c.crop.top, ffDecimal, 5) & "," & formatFloat(c.crop.side, ffDecimal, 5))

proc setFromDisplay(c: PureCropView, x, y, side: float) =
  ## Cadre exprimé en pixels d'affichage -> fractions de l'image.
  let ir = c.imageRect
  let m = min(ir.w, ir.h)
  if m <= 0: return
  let s = clamp(side, min(16.0, m), m)
  let lx = clamp(x, ir.x, ir.x + ir.w - s)
  let ty = clamp(y, ir.y, ir.y + ir.h - s)
  c.crop = Crop(left: (lx - ir.x) / ir.w, top: (ty - ir.y) / ir.h, side: s / m)

method mouseCursor*(c: PureCropView, x, y: float): int =
  if not c.hasImage: return SDL_SYSTEM_CURSOR_DEFAULT
  let cr = c.cropRect
  if abs(x - (cr.x + cr.w)) <= HandleSize and abs(y - (cr.y + cr.h)) <= HandleSize: return SDL_SYSTEM_CURSOR_NS_RESIZE
  if cr.containsPoint(x, y): return SDL_SYSTEM_CURSOR_MOVE
  SDL_SYSTEM_CURSOR_POINTER

method onMouse*(c: PureCropView, e: MouseEvent) =
  if not c.hasImage or not c.isActive: return
  let cr = c.cropRect
  case e.action
  of maPress:
    if e.button != mbLeft: return
    if abs(e.x - (cr.x + cr.w)) <= HandleSize and abs(e.y - (cr.y + cr.h)) <= HandleSize:
      c.drag = dmResize
    elif cr.containsPoint(e.x, e.y):
      c.drag = dmMove
      c.grabX = e.x - cr.x
      c.grabY = e.y - cr.y
    else:
      c.setFromDisplay(e.x - cr.w / 2, e.y - cr.h / 2, cr.w)
      c.drag = dmMove
      c.grabX = cr.w / 2
      c.grabY = cr.h / 2
      c.changed()
  of maMove:
    case c.drag
    of dmMove:
      c.setFromDisplay(e.x - c.grabX, e.y - c.grabY, cr.w)
      markDirty(c)
    of dmResize:
      c.setFromDisplay(cr.x, cr.y, max(e.x - cr.x, e.y - cr.y))
      markDirty(c)
    of dmNone: discard
  of maRelease:
    if c.drag != dmNone:
      c.drag = dmNone
      c.changed()

method onWheel*(c: PureCropView, dx, dy: float): bool =
  if not c.hasImage or not c.isActive: return false
  let cr = c.cropRect
  let ns = cr.w * (if dy > 0: 1.06 else: 1 / 1.06)
  c.setFromDisplay(cr.x + cr.w / 2 - ns / 2, cr.y + cr.h / 2 - ns / 2, ns)
  c.changed()
  true

method onKey*(c: PureCropView, e: KeyEvent): bool =
  if not c.hasImage: return false
  let cr = c.cropRect
  let step = (if (e.mods and KMOD_SHIFT) != 0: 10.0 else: 2.0)
  case e.key
  of SDLK_LEFT: c.setFromDisplay(cr.x - step, cr.y, cr.w)
  of SDLK_RIGHT: c.setFromDisplay(cr.x + step, cr.y, cr.w)
  of SDLK_UP: c.setFromDisplay(cr.x, cr.y - step, cr.w)
  of SDLK_DOWN: c.setFromDisplay(cr.x, cr.y + step, cr.w)
  else: return false
  c.changed()
  true

method valueText*(c: PureCropView): string =
  formatFloat(c.crop.left, ffDecimal, 5) & "," & formatFloat(c.crop.top, ffDecimal, 5) & "," &
    formatFloat(c.crop.side, ffDecimal, 5)

# accès par identifiant

proc pureCropHasImage*(id: ControlId): bool =
  readControl(id, PureCropView, c): result = c.hasImage


proc pureCropSetImage*(id: ControlId, img: RgbaImage, crop: Crop) =
  var shown = img
  let m = max(img.w, img.h)
  if m > MaxDisplay:
    let k = MaxDisplay / m
    shown = img.shrinkTo(max(1, int(round(float(img.w) * k))), max(1, int(round(float(img.h) * k))))
  withControl(id, PureCropView, c):
    c.img = shown
    c.srcW = img.w
    c.srcH = img.h
    c.hasImage = true
    c.crop = crop.normalized(img.w, img.h)
    c.texDirty = true

proc pureCropClear*(id: ControlId) =
  withControl(id, PureCropView, c):
    c.hasImage = false
    c.img = RgbaImage()
    c.crop = fullCrop()
    c.texDirty = true

proc pureCropValue*(id: ControlId): Crop =
  readControl(id, PureCropView, c): result = c.crop


method dispose*(c: PureCropView) =
  if c.tex != nil: SDL_DestroyTexture(c.tex)
  c.tex = nil
  c.texDirty = true
