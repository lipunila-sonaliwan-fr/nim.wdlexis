# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - éditeur d'états (rapports PDF), sur le principe du concepteur de formulaires.
#
# * Palette (à gauche) : des zones (zone nommée, en-tête, pied) et des éléments
#   (texte, champ {variable}, rectangle, lignes, image, numéro de page, date) à
#   glisser sur une zone, ou à cliquer pour les ajouter à la zone sélectionnée.
# * Page (au centre) : les zones horizontales de l'état, les unes sous les autres,
#   à la largeur de la page (marges déduites), à l'échelle. Les éléments se
#   déplacent et se redimensionnent à la souris (repères magenta sur les bords et
#   centres des autres éléments et de la zone, sinon pas de 0,5 mm) ; le bord bas
#   d'une zone règle sa hauteur. Le texte est mis en page avec les mêmes métriques
#   que le PDF.
# * Hiérarchie et inspecteur (à droite) : état > zones > éléments ; propriétés.
# * Aperçu PDF : chaque zone trois fois, variables affichées « {nom} ».
# * Chaque modification régénère etat_<nom>.prg (fonction ETAT_<NOM>()).
import std/[strutils, os, math, options, locks, tables, sets]
import ../wdgui
import ../sdl3
import etats, pdfwriter, codeeditor, imagedecode
from formmodel import PropKind, PropDef

type
  SelKind* = enum skReport, skBand, skItem
  RDrag = enum rdNone, rdMove, rdResize, rdBand, rdNew
  Guide = tuple[x1, y1, x2, y2: float]

  ReportCanvas* = ref object of Control
    model*: ReportModel
    sel*: SelKind
    selBand*: RBand
    selItem*: RItem
    scale*: float                       # pixels par mm
    drag: RDrag
    handle: int
    startX, startY: float
    startRect: Rect                     # mm (x, y relatifs à la zone, w, h)
    startBandH: float
    moved: bool
    newKind: string
    ghost: Rect
    dropBand: RBand
    dropValid: bool
    guides: seq[Guide]
    badge: string
    baseDir*: string                    # images relatives (dossier du projet)
    images: Table[string, tuple[tex: SDL_Texture, w, h: float]]
    fonts: Table[int, TTF_Font]
    texts: Table[string, tuple[tex: SDL_Texture, w, h: float]]

  ReportPalette* = ref object of Control
    canvas*: ReportCanvas
    hoverIdx, pressIdx: int
    pressX, pressY: float
    dragging: bool
    scroll: float

const
  originX = 56.0
  topPad = 14.0
  barH = 22.0
  bandGap = 8.0
  snapPx = 6.0
  guideColor = Color(r: 255, g: 45, b: 149, a: 255)
  selColor = Color(r: 59, g: 130, b: 246, a: 255)
  paper = Color(r: 255, g: 255, b: 255, a: 255)
  PxRgba = 0x16762004'u32               # SDL_PIXELFORMAT_ABGR8888

proc toColor(s: string, fallback: Color): Color =
  let c = rgbOf(s)
  if c.isNone: return fallback
  let v = c.get
  Color(r: uint8(round(v.r * 255)), g: uint8(round(v.g * 255)), b: uint8(round(v.b * 255)), a: 255)

proc snapHalf(v: float): float = round(v * 2) / 2

proc fmt1(v: float): string =
  if abs(v - round(v)) < 0.001: $int(round(v))
  else: formatFloat(v, ffDecimal, 1)

# ------------------------------------------------------------------ géométrie

proc bodyW(c: ReportCanvas): float = c.model.bandWidth * c.scale

proc bandTop(c: ReportCanvas, b: RBand): float =
  var y = c.rect.y + topPad
  for x in c.model.bands:
    if x == b: return y
    y += barH + x.height * c.scale + bandGap
  y

proc barRect(c: ReportCanvas, b: RBand): Rect =
  rect(c.rect.x + originX, c.bandTop(b), c.bodyW, barH)

proc bodyRect(c: ReportCanvas, b: RBand): Rect =
  rect(c.rect.x + originX, c.bandTop(b) + barH, c.bodyW, b.height * c.scale)

proc itemRect(c: ReportCanvas, b: RBand, i: RItem): Rect =
  let br = c.bodyRect(b)
  rect(br.x + i.x * c.scale, br.y + i.y * c.scale, i.w * c.scale, i.h * c.scale)

proc bandOfItem*(c: ReportCanvas, i: RItem): RBand =
  for b in c.model.bands:
    if i in b.items: return b

method preferredSize*(c: ReportCanvas, d: Drawing, t: Theme): tuple[w, h: float] =
  var h = topPad + 40
  for b in c.model.bands: h += barH + b.height * c.scale + bandGap
  (c.model.bandWidth * c.scale + originX + 60, h)

proc bandAt(c: ReportCanvas, x, y: float): tuple[b: RBand, onBar: bool] =
  for b in c.model.bands:
    let br = c.barRect(b)
    if br.containsPoint(x, y): return (b, true)
    let r = c.bodyRect(b)
    if y >= r.y and y <= r.y + r.h + 1 and x >= r.x - 10 and x <= r.x + r.w + 10: return (b, false)
  (nil, false)

proc nearestBand(c: ReportCanvas, y: float): RBand =
  ## Zone dont le corps est le plus proche verticalement (dépôt entre deux zones).
  var best = Inf
  for b in c.model.bands:
    let r = c.bodyRect(b)
    let d = if y < r.y: r.y - y elif y > r.y + r.h: y - r.y - r.h else: 0.0
    if d < best:
      best = d
      result = b

proc hitRect(r: Rect): Rect =
  # les lignes ont une boîte de largeur ou de hauteur nulle : tolérance de 4 px.
  var x = r
  if x.w < 8:
    x.x -= (8 - x.w) / 2
    x.w = 8
  if x.h < 8:
    x.y -= (8 - x.h) / 2
    x.h = 8
  x

proc itemAt(c: ReportCanvas, x, y: float): tuple[b: RBand, i: RItem] =
  for b in c.model.bands:
    let br = c.bodyRect(b)
    if y < br.y - 4 or y > br.y + br.h + 4: continue
    for k in countdown(b.items.high, 0):
      let it = b.items[k]
      if hitRect(c.itemRect(b, it)).containsPoint(x, y): return (b, it)
  (nil, nil)

proc handleRects(r: Rect): array[8, Rect] =
  let s = 7.0
  let xs = [r.x, r.x + r.w / 2, r.x + r.w]
  let ys = [r.y, r.y + r.h / 2, r.y + r.h]
  let order = [(0, 0), (1, 0), (2, 0), (2, 1), (2, 2), (1, 2), (0, 2), (0, 1)]
  for i in 0 .. 7:
    let (ix, iy) = order[i]
    result[i] = rect(xs[ix] - s / 2, ys[iy] - s / 2, s, s)

proc handleAt(c: ReportCanvas, x, y: float): int =
  if c.sel != skItem or c.selItem == nil: return -1
  let b = c.bandOfItem(c.selItem)
  if b == nil: return -1
  let hs = handleRects(c.itemRect(b, c.selItem))
  for i in countdown(7, 0):
    if hs[i].shrink(-3).containsPoint(x, y): return i
  -1

proc bandEdgeAt(c: ReportCanvas, x, y: float): RBand =
  ## Bord bas d'une zone (réglage de la hauteur).
  for b in c.model.bands:
    let r = c.bodyRect(b)
    if x >= r.x and x <= r.x + r.w and abs(y - (r.y + r.h)) <= 4: return b

# ------------------------------------------------------------------ sélection, événements

proc selectNone*(c: ReportCanvas) =
  c.sel = skReport
  c.selBand = nil
  c.selItem = nil
  emit(c, evSelection, text = "")

proc selectBand*(c: ReportCanvas, b: RBand) =
  c.sel = skBand
  c.selBand = b
  c.selItem = nil
  emit(c, evSelection, text = b.name)

proc selectItem*(c: ReportCanvas, i: RItem) =
  c.sel = skItem
  c.selItem = i
  c.selBand = c.bandOfItem(i)
  emit(c, evSelection, text = i.name)

proc changed(c: ReportCanvas) = emit(c, evChange)

proc newReportCanvas*(model: ReportModel, baseDir: string): ReportCanvas =
  result = ReportCanvas(model: model, scale: 3.0, sel: skReport, baseDir: baseDir)
  initControl(result)
  result.focusable = true

# ------------------------------------------------------------------ modifications

proc targetBand(c: ReportCanvas): RBand =
  ## Zone qui reçoit un élément cliqué dans la palette.
  if c.selBand != nil: return c.selBand
  for b in c.model.bands:
    if b.name notin ["entete", "pied"]: return b
  if c.model.bands.len > 0: c.model.bands[0] else: nil

proc newItemOfKind(c: ReportCanvas, kind: string, xmm, ymm: float): RItem =
  let m = c.model
  case kind
  of "texte":
    result = newItem(KindTexte, m.uniqueItemName(KindTexte), xmm, ymm, 40, 6)
  of "champ":
    result = newItem(KindTexte, m.uniqueItemName(KindTexte), xmm, ymm, 40, 6)
    result.setProp("texte", "{champ}")
  of "numéro de page":
    result = newItem(KindTexte, m.uniqueItemName(KindTexte), xmm, ymm, 45, 5)
    result.setProp("texte", "Page {page} / {nombre de page}")
    result.setProp("alignement", "droite")
  of "date":
    result = newItem(KindTexte, m.uniqueItemName(KindTexte), xmm, ymm, 25, 5)
    result.setProp("texte", "{date}")
  of "rectangle":
    result = newItem(KindRect, m.uniqueItemName(KindRect), xmm, ymm, 40, 15)
  of "ligne horizontale":
    result = newItem(KindLigne, m.uniqueItemName(KindLigne), xmm, ymm, 40, 0)
  of "ligne verticale":
    result = newItem(KindLigne, m.uniqueItemName(KindLigne), xmm, ymm, 0, 15)
  of "image":
    result = newItem(KindImage, m.uniqueItemName(KindImage), xmm, ymm, 30, 20)
  else:
    result = newItem(KindTexte, m.uniqueItemName(KindTexte), xmm, ymm, 40, 6)

proc clampItem(c: ReportCanvas, b: RBand, i: RItem) =
  let bw = c.model.bandWidth
  i.w = min(i.w, bw)
  i.x = clamp(i.x, 0.0, max(0.0, bw - i.w))
  i.y = max(0.0, i.y)
  if i.y + i.h > b.height: b.height = snapHalf(i.y + i.h)

proc addBand*(c: ReportCanvas, kind: string, after: RBand = nil): RBand =
  ## kind : "zone", "entete" ou "pied" (en-tête en premier, pied en dernier).
  let m = c.model
  if kind in ["entete", "pied"]:
    let existing = m.findBand(kind)
    if existing != nil:
      c.selectBand(existing)
      return existing
  let b = newBand((if kind == "zone": m.uniqueBandName("zone") else: kind), (if kind == "zone": 10.0 else: 12.0))
  case kind
  of "entete": m.bands.insert(b, 0)
  of "pied": m.bands.add b
  else:
    var at = m.bands.len
    if after != nil: at = m.bands.find(after) + 1
    let p = m.findBand("pied")
    if p != nil and at > m.bands.find(p): at = m.bands.find(p)
    let e = m.findBand("entete")
    if e != nil and at <= m.bands.find(e): at = m.bands.find(e) + 1
    m.bands.insert(b, clamp(at, 0, m.bands.len))
  c.selectBand(b)
  c.changed()
  markDirty(c)
  b

proc dropNew*(c: ReportCanvas, kind: string, x, y: float) =
  if kind in ["zone", "entete", "pied"]:
    discard c.addBand(kind, c.nearestBand(y))
    return
  var b = c.bandAt(x, y).b
  if b == nil: b = c.nearestBand(y)
  if b == nil: return
  let br = c.bodyRect(b)
  let xmm = snapHalf(max(0.0, (x - br.x) / c.scale - 2))
  let ymm = snapHalf(clamp((y - br.y) / c.scale - 1, 0.0, max(0.0, b.height - 2)))
  let it = c.newItemOfKind(kind, xmm, ymm)
  b.items.add it
  c.clampItem(b, it)
  c.selectItem(it)
  c.changed()
  markDirty(c)

proc deleteSelected*(c: ReportCanvas) =
  case c.sel
  of skItem:
    let b = c.bandOfItem(c.selItem)
    if b != nil:
      b.items.delete(b.items.find(c.selItem))
      c.selectBand(b)
      c.changed()
  of skBand:
    let i = c.model.bands.find(c.selBand)
    if i >= 0:
      c.model.bands.delete(i)
      c.selectNone()
      c.changed()
  else: discard
  markDirty(c)

proc moveSelected*(c: ReportCanvas, delta: int) =
  ## Zone : ordre des zones ; élément : ordre de dessin dans sa zone.
  case c.sel
  of skBand:
    let bs = c.model.bands
    let i = bs.find(c.selBand)
    let j = i + delta
    if i < 0 or j < 0 or j >= bs.len: return
    swap(c.model.bands[i], c.model.bands[j])
  of skItem:
    let b = c.bandOfItem(c.selItem)
    if b == nil: return
    let i = b.items.find(c.selItem)
    let j = i + delta
    if i < 0 or j < 0 or j >= b.items.len: return
    swap(b.items[i], b.items[j])
  else: return
  c.changed()
  markDirty(c)

# ------------------------------------------------------------------ repères

proc snapCandidates(c: ReportCanvas, b: RBand, exclude: RItem): tuple[xs, ys: seq[float]] =
  let bw = c.model.bandWidth
  result.xs = @[0.0, bw / 2, bw]
  result.ys = @[0.0, b.height / 2, b.height]
  for i in b.items:
    if i == exclude: continue
    result.xs.add [i.x, i.x + i.w / 2, i.x + i.w]
    result.ys.add [i.y, i.y + i.h / 2, i.y + i.h]

proc snapValue(v: float, cands: seq[float], thr: float): tuple[v: float, hit: bool, at: float] =
  var best = thr + 1
  result = (snapHalf(v), false, 0.0)
  for cnd in cands:
    if abs(cnd - v) < best:
      best = abs(cnd - v)
      result = (cnd, true, cnd)

proc snapMove(c: ReportCanvas, b: RBand, i: RItem, x, y: var float) =
  ## Aligne les bords / le centre de l'élément (mm) sur ceux des autres et de la zone.
  c.guides.setLen(0)
  let (xs, ys) = c.snapCandidates(b, i)
  let thr = snapPx / c.scale
  let br = c.bodyRect(b)
  var bestD = thr + 1
  var dx = 0.0
  var gx = -1.0
  for e in [0.0, 0.5, 1.0]:
    for cnd in xs:
      let d = cnd - (x + i.w * e)
      if abs(d) < bestD:
        bestD = abs(d)
        dx = d
        gx = cnd
  if gx >= 0: x += dx else: x = snapHalf(x)
  bestD = thr + 1
  var dy = 0.0
  var gy = -1.0
  for e in [0.0, 0.5, 1.0]:
    for cnd in ys:
      let d = cnd - (y + i.h * e)
      if abs(d) < bestD:
        bestD = abs(d)
        dy = d
        gy = cnd
  if gy >= 0: y += dy else: y = snapHalf(y)
  if gx >= 0: c.guides.add((br.x + gx * c.scale, br.y, br.x + gx * c.scale, br.y + br.h))
  if gy >= 0: c.guides.add((br.x, br.y + gy * c.scale, br.x + br.w, br.y + gy * c.scale))

# ------------------------------------------------------------------ dessin : polices et images

proc fontFiles(family: string, style: int): seq[string] =
  # style : 0 normal, 1 gras, 2 italique, 3 gras italique.
  let lib = ["Regular", "Bold", "Italic", "BoldItalic"][style]
  case family
  of "times":
    @["/usr/share/fonts/truetype/liberation/LiberationSerif-" & lib & ".ttf",
      "/usr/share/fonts/truetype/liberation2/LiberationSerif-" & lib & ".ttf",
      "/System/Library/Fonts/Supplemental/" & ["Times New Roman.ttf", "Times New Roman Bold.ttf",
        "Times New Roman Italic.ttf", "Times New Roman Bold Italic.ttf"][style],
      "C:/Windows/Fonts/" & ["times.ttf", "timesbd.ttf", "timesi.ttf", "timesbi.ttf"][style],
      "/usr/share/fonts/truetype/dejavu/" & ["DejaVuSerif.ttf", "DejaVuSerif-Bold.ttf",
        "DejaVuSerif-Italic.ttf", "DejaVuSerif-BoldItalic.ttf"][style]]
  of "courier":
    @["/usr/share/fonts/truetype/liberation/LiberationMono-" & lib & ".ttf",
      "/usr/share/fonts/truetype/liberation2/LiberationMono-" & lib & ".ttf",
      "/System/Library/Fonts/Supplemental/" & ["Courier New.ttf", "Courier New Bold.ttf",
        "Courier New Italic.ttf", "Courier New Bold Italic.ttf"][style],
      "C:/Windows/Fonts/" & ["cour.ttf", "courbd.ttf", "couri.ttf", "courbi.ttf"][style],
      "/usr/share/fonts/truetype/dejavu/" & ["DejaVuSansMono.ttf", "DejaVuSansMono-Bold.ttf",
        "DejaVuSansMono-Oblique.ttf", "DejaVuSansMono-BoldOblique.ttf"][style]]
  else:
    @["/usr/share/fonts/truetype/liberation/LiberationSans-" & lib & ".ttf",
      "/usr/share/fonts/truetype/liberation2/LiberationSans-" & lib & ".ttf",
      "/System/Library/Fonts/Supplemental/" & ["Arial.ttf", "Arial Bold.ttf", "Arial Italic.ttf",
        "Arial Bold Italic.ttf"][style],
      "C:/Windows/Fonts/" & ["arial.ttf", "arialbd.ttf", "ariali.ttf", "arialbi.ttf"][style],
      "/usr/share/fonts/truetype/dejavu/" & ["DejaVuSans.ttf", "DejaVuSans-Bold.ttf",
        "DejaVuSans-Oblique.ttf", "DejaVuSans-BoldOblique.ttf"][style]]

proc fontFor(c: ReportCanvas, t: Theme, family: string, style, px: int): TTF_Font =
  let fam = case family
    of "times": 1
    of "courier": 2
    else: 0
  let key = (fam * 4 + style) * 1000 + px
  if c.fonts.hasKey(key): return c.fonts[key]
  result = nil
  for p in fontFiles(family, style):
    if fileExists(p):
      result = TTF_OpenFont(p.cstring, cfloat(px))
      if result != nil: break
  if result == nil:
    for p in t.fonts:
      if fileExists(p):
        result = TTF_OpenFont(p.cstring, cfloat(px))
        if result != nil:
          TTF_SetFontStyle(result, uint32(style))
          break
  c.fonts[key] = result

proc drawTtf(c: ReportCanvas, d: Drawing, f: TTF_Font, key, s: string, x, y: float, col: Color): tuple[w, h: float] =
  if f == nil or s.len == 0: return (0.0, 0.0)
  var e = c.texts.getOrDefault(key)
  if e.tex == nil:
    if c.texts.len > 2000:
      for o in c.texts.values: SDL_DestroyTexture(o.tex)
      c.texts.clear()
    let surf = TTF_RenderText_Blended(f, s.cstring, csize_t(s.len), SDL_Color(r: 255, g: 255, b: 255, a: 255))
    if surf == nil: return
    let tex = SDL_CreateTextureFromSurface(d.ren, surf)
    SDL_DestroySurface(surf)
    if tex == nil: return
    var w, h: cfloat
    discard SDL_GetTextureSize(tex, addr w, addr h)
    e = (tex, float(w), float(h))
    c.texts[key] = e
  discard SDL_SetTextureColorMod(e.tex, col.r, col.g, col.b)
  d.drawTexture(e.tex, rect(round(x), round(y), e.w, e.h))
  (e.w, e.h)

proc imageFor(c: ReportCanvas, d: Drawing, path: string): tuple[tex: SDL_Texture, w, h: float] =
  if c.images.hasKey(path): return c.images[path]
  result = (nil, 0.0, 0.0)
  try:
    let img = decodeImageFile(path)
    if img.w <= 0 or img.h <= 0: raise newException(ValueError, "image vide")
    let tex = SDL_CreateTexture(d.ren, PxRgba, SDL_TEXTUREACCESS_STATIC, cint(img.w), cint(img.h))
    if tex != nil:
      discard SDL_UpdateTexture(tex, nil, unsafeAddr img.px[0], cint(img.w * 4))
      result = (tex, float(img.w), float(img.h))
  except CatchableError: discard
  c.images[path] = result

# ------------------------------------------------------------------ dessin

proc dashedLine(d: Drawing, x1, y1, x2, y2: float, col: Color) =
  let len = hypot(x2 - x1, y2 - y1)
  if len < 1: return
  var t = 0.0
  while t < len:
    let t2 = min(len, t + 4)
    d.line(x1 + (x2 - x1) * t / len, y1 + (y2 - y1) * t / len,
           x1 + (x2 - x1) * t2 / len, y1 + (y2 - y1) * t2 / len, col)
    t += 7

proc dashedRect(d: Drawing, r: Rect, col: Color) =
  d.dashedLine(r.x, r.y, r.x + r.w, r.y, col)
  d.dashedLine(r.x + r.w, r.y, r.x + r.w, r.y + r.h, col)
  d.dashedLine(r.x + r.w, r.y + r.h, r.x, r.y + r.h, col)
  d.dashedLine(r.x, r.y + r.h, r.x, r.y, col)

proc drawText(c: ReportCanvas, d: Drawing, t: Theme, i: RItem, r: Rect) =
  let txt = i.getProp("texte")
  let f = i.textFont
  let size = i.textSize
  let k = c.scale / MmToPt                       # pixels par point
  let wPt = r.w / k
  let lines = layoutLines(txt, f, size, max(1.0, wPt - 2 * TextPad), isTrueProp(i.getProp("retour")))
  let lh = size * LineFactor * k
  let total = float(lines.len) * lh
  var y0 = case i.getProp("vertical")
    of "milieu": (r.h - total) / 2
    of "bas": r.h - total
    else: 0.0
  y0 = max(0.0, y0)
  let style = (if isTrueProp(i.getProp("gras")): 1 else: 0) + (if isTrueProp(i.getProp("italique")): 2 else: 0)
  let px = max(4, int(floor(size * k)))     # arrondi inférieur : jamais plus large que le PDF
  let font = c.fontFor(t, i.getProp("police"), style, px)
  let col = toColor(i.getProp("couleur"), Color(r: 0, g: 0, b: 0, a: 255))
  d.pushClip(r)
  for n, l in lines:
    let lwPx = textWidth(f, size, l) * k
    let x = case i.getProp("alignement")
      of "centre": r.x + (r.w - lwPx) / 2
      of "droite": r.x + r.w - TextPad * k - lwPx
      else: r.x + TextPad * k
    let top = r.y + y0 + float(n) * lh
    if font != nil:
      let key = $ord(f) & "/" & $px & "/" & l
      var th = float(TTF_GetFontHeight(font))
      discard c.drawTtf(d, font, key, l, x, top + (lh - th) / 2, col)
    else:
      d.text(x, top + (lh - d.textHeight) / 2, l, col)
    if isTrueProp(i.getProp("souligne")):
      let ub = top + lh * 0.82
      d.line(x, ub, x + lwPx, ub, col)
  d.popClip()

proc drawItem(c: ReportCanvas, d: Drawing, t: Theme, b: RBand, i: RItem) =
  let r = c.itemRect(b, i)
  let k = c.scale / MmToPt
  case i.kind
  of KindTexte:
    let fond = i.getProp("fond")
    if rgbOf(fond).isSome: d.fillRect(r, toColor(fond, paper))
    let bord = i.getProp("bordure")
    if rgbOf(bord).isSome: d.strokeRect(r, toColor(bord, paper), max(1.0, fnum(i.getProp("epaisseur"), 0.5) * k))
    else: d.dashedRect(r, Color(r: 200, g: 205, b: 215, a: 255))
    c.drawText(d, t, i, r)
  of KindRect:
    let rad = fnum(i.getProp("rayon")) * c.scale
    let fond = i.getProp("fond")
    if rgbOf(fond).isSome: d.fillRoundRect(r, rad, toColor(fond, paper))
    let bord = i.getProp("bordure")
    if rgbOf(bord).isSome:
      d.strokeRoundRect(r, rad, toColor(bord, paper), max(1.0, fnum(i.getProp("epaisseur"), 0.5) * k))
  of KindLigne:
    let col = toColor(i.getProp("couleur"), Color(r: 0, g: 0, b: 0, a: 255))
    if isTrueProp(i.getProp("pointille")): d.dashedLine(r.x, r.y, r.x + r.w, r.y + r.h, col)
    else: d.line(r.x, r.y, r.x + r.w, r.y + r.h, col, max(1.0, fnum(i.getProp("epaisseur"), 0.5) * k))
  of KindImage:
    var p = i.getProp("chemin")
    if p.len > 0 and not p.isAbsolute and c.baseDir.len > 0: p = c.baseDir / p
    let im = if p.len > 0 and '{' notin p: c.imageFor(d, p) else: (nil, 0.0, 0.0)
    if im.tex != nil:
      var dst = r
      case i.getProp("mode")
      of "etirer": discard
      of "centre":
        dst.w = min(r.w, im.w * 0.75 * k)
        dst.h = min(r.h, im.h * 0.75 * k)
        dst.x = r.x + (r.w - dst.w) / 2
        dst.y = r.y + (r.h - dst.h) / 2
      else:
        let s = min(r.w / im.w, r.h / im.h)
        dst.w = im.w * s
        dst.h = im.h * s
        dst.x = r.x + (r.w - dst.w) / 2
        dst.y = r.y + (r.h - dst.h) / 2
      d.drawTexture(im.tex, dst)
    else:
      let g = Color(r: 170, g: 175, b: 185, a: 255)
      d.strokeRect(r, g)
      d.line(r.x, r.y, r.x + r.w, r.y + r.h, g)
      d.line(r.x + r.w, r.y, r.x, r.y + r.h, g)
      d.textIn(r, (if i.getProp("chemin").len > 0: extractFilename(i.getProp("chemin")) else: "image"),
               Color(r: 120, g: 125, b: 135, a: 255), alCenter)
  else: discard

proc bandColor(b: RBand): Color =
  case b.name
  of "entete": Color(r: 59, g: 130, b: 246, a: 255)
  of "pied": Color(r: 22, g: 163, b: 74, a: 255)
  else: Color(r: 120, g: 113, b: 108, a: 255)

proc drawSelection(c: ReportCanvas, d: Drawing, t: Theme)

method draw*(c: ReportCanvas, d: Drawing, t: Theme) =
  d.fillRect(c.rect, mix(t.windowBg, t.text, 0.06))
  let m = c.model
  for b in m.bands:
    let bar = c.barRect(b)
    let body = c.bodyRect(b)
    let col = bandColor(b)
    let selected = c.sel == skBand and c.selBand == b
    d.fillRoundRect(rect(bar.x, bar.y, bar.w, bar.h + 4), 5, (if selected: col else: col.withAlpha(150)))
    var label = "▾ " & b.name & "   " & fmt1(b.height) & " mm"
    if isTrueProp(b.getProp("extensible")): label.add "   · extensible"
    if isTrueProp(b.getProp("sautavant")): label.add "   · nouvelle page avant"
    if b.name == "entete": label.add "   (haut de chaque page)"
    elif b.name == "pied": label.add "   (bas de chaque page)"
    d.textIn(bar, label, White, alLeft, 8)
    d.fillRect(body, toColor(b.getProp("fond"), paper))
    # quadrillage tous les 5 mm
    let g = Color(r: 225, g: 228, b: 234, a: 255)
    var gx = 0.0
    while gx <= m.bandWidth + 0.01:
      var gy = 0.0
      while gy <= b.height + 0.01:
        d.fillRect(rect(body.x + gx * c.scale - 0.5, body.y + gy * c.scale - 0.5, 1.2, 1.2), g)
        gy += 5
      gx += 5
    # règle à gauche : graduations tous les 5 mm, valeurs tous les 10
    var ry = 0.0
    while ry <= b.height + 0.01:
      let yy = body.y + ry * c.scale
      let long = abs(ry mod 10) < 0.01
      d.line(body.x - (if long: 10 else: 5), yy, body.x - 1, yy, t.textSecondary)
      if long and ry > 0: d.textIn(rect(c.rect.x + 2, yy - 8, originX - 16, 16), fmt1(ry), t.textSecondary, alRight)
      ry += 5
    d.pushClip(body)
    for i in b.items: c.drawItem(d, t, b, i)
    d.popClip()
    d.strokeRect(body, (if selected: col else: t.border))
  c.drawSelection(d, t)

proc drawSelection(c: ReportCanvas, d: Drawing, t: Theme) =
  if c.sel == skItem and c.selItem != nil:
    let b = c.bandOfItem(c.selItem)
    if b != nil:
      let r = c.itemRect(b, c.selItem)
      d.strokeRect(r.shrink(-1), selColor, 2)
      let label = c.selItem.kind & "  " & c.selItem.name
      let lw = d.textWidth(label) + 14
      let lr = rect(r.x - 1, r.y - t.lineHeight - 2, lw, t.lineHeight)
      d.fillRoundRect(lr, 4, selColor)
      d.textIn(lr, label, White, alCenter)
      for h in handleRects(r):
        d.fillRect(h, White)
        d.strokeRect(h, selColor, 1)
  if c.sel == skBand and c.selBand != nil:
    let r = c.bodyRect(c.selBand)
    let h = rect(r.x + r.w / 2 - 14, r.y + r.h - 3, 28, 6)
    d.fillRoundRect(h, 3, bandColor(c.selBand))
  if c.dropValid and c.dropBand != nil:
    d.strokeRect(c.bodyRect(c.dropBand), selColor.withAlpha(180), 2)
  if c.drag == rdNew and c.ghost.w > 0:
    d.fillRoundRect(c.ghost, 4, selColor.withAlpha(40))
    d.strokeRect(c.ghost, selColor.withAlpha(200), 1)
    d.textIn(c.ghost, c.newKind, selColor, alCenter)
  for g in c.guides: d.dashedLine(g.x1, g.y1, g.x2, g.y2, guideColor)
  if c.badge.len > 0:
    var r: Rect
    if c.sel == skItem and c.selItem != nil and c.bandOfItem(c.selItem) != nil:
      r = c.itemRect(c.bandOfItem(c.selItem), c.selItem)
    elif c.selBand != nil:
      r = c.bodyRect(c.selBand)
    let w = d.textWidth(c.badge) + 14
    let lr = rect(r.x + r.w / 2 - w / 2, r.y + r.h + 8, w, t.lineHeight)
    d.fillRoundRect(lr, 4, guideColor)
    d.textIn(lr, c.badge, White, alCenter)

# ------------------------------------------------------------------ souris et clavier

method mouseCursor*(c: ReportCanvas, x, y: float): int =
  if c.drag == rdBand or c.bandEdgeAt(x, y) != nil: SDL_SYSTEM_CURSOR_NS_RESIZE
  elif c.handleAt(x, y) >= 0: SDL_SYSTEM_CURSOR_MOVE
  else: SDL_SYSTEM_CURSOR_DEFAULT

method onMouse*(c: ReportCanvas, e: MouseEvent) =
  case e.action
  of maPress:
    c.guides.setLen(0)
    c.badge = ""
    let h = c.handleAt(e.x, e.y)
    if h >= 0 and e.button == mbLeft:
      let b = c.bandOfItem(c.selItem)
      c.drag = rdResize
      c.handle = h
      c.startX = e.x
      c.startY = e.y
      c.startRect = rect(c.selItem.x, c.selItem.y, c.selItem.w, c.selItem.h)
      c.startBandH = b.height
      return
    let edge = c.bandEdgeAt(e.x, e.y)
    if edge != nil and e.button == mbLeft:
      if not (c.sel == skBand and c.selBand == edge): c.selectBand(edge)
      c.drag = rdBand
      c.startY = e.y
      c.startBandH = edge.height
      return
    let hit = c.itemAt(e.x, e.y)
    if hit.i != nil:
      if not (c.sel == skItem and c.selItem == hit.i): c.selectItem(hit.i)
      if e.button == mbLeft:
        c.drag = rdMove
        c.startX = e.x
        c.startY = e.y
        c.startRect = rect(hit.i.x, hit.i.y, hit.i.w, hit.i.h)
        c.moved = false
      return
    let ba = c.bandAt(e.x, e.y)
    if ba.b != nil:
      if not (c.sel == skBand and c.selBand == ba.b): c.selectBand(ba.b)
    elif c.sel != skReport: c.selectNone()
  of maMove:
    case c.drag
    of rdResize:
      let i = c.selItem
      let b = c.bandOfItem(i)
      if b == nil: return
      var r = c.startRect
      let dx = (e.x - c.startX) / c.scale
      let dy = (e.y - c.startY) / c.scale
      let hh = c.handle
      let left = hh in [0, 6, 7]
      let top = hh in [0, 1, 2]
      let horiz = hh in [0, 2, 3, 4, 6, 7]
      let vert = hh in [0, 1, 2, 4, 5, 6]
      let (xs, ys) = c.snapCandidates(b, i)
      let thr = snapPx / c.scale
      c.guides.setLen(0)
      let br = c.bodyRect(b)
      if horiz:
        let edge = if left: r.x + dx else: r.x + r.w + dx
        let s = snapValue(edge, xs, thr)
        if s.hit: c.guides.add((br.x + s.at * c.scale, br.y, br.x + s.at * c.scale, br.y + br.h))
        if left:
          let right = r.x + r.w
          r.x = min(s.v, right)
          r.w = right - r.x
        else: r.w = max(0.0, s.v - r.x)
      if vert:
        let edge = if top: r.y + dy else: r.y + r.h + dy
        let s = snapValue(edge, ys, thr)
        if s.hit: c.guides.add((br.x, br.y + s.at * c.scale, br.x + br.w, br.y + s.at * c.scale))
        if top:
          let bottom = r.y + r.h
          r.y = min(max(0.0, s.v), bottom)
          r.h = bottom - r.y
        else: r.h = max(0.0, s.v - r.y)
      i.x = r.x
      i.y = r.y
      i.w = r.w
      i.h = r.h
      c.clampItem(b, i)
      c.badge = fmt1(i.w) & " x " & fmt1(i.h) & " mm"
      markDirty(c)
    of rdMove:
      if not c.moved and abs(e.x - c.startX) + abs(e.y - c.startY) < 4: return
      c.moved = true
      let i = c.selItem
      var b = c.bandOfItem(i)
      # changement de zone sous le pointeur
      let under = c.bandAt(e.x, e.y).b
      if under != nil and under != b:
        let oldBody = c.bodyRect(b)
        let newBody = c.bodyRect(under)
        b.items.delete(b.items.find(i))
        under.items.add i
        c.startRect.y += (oldBody.y - newBody.y) / c.scale
        b = under
        c.selBand = under
      var x = c.startRect.x + (e.x - c.startX) / c.scale
      var y = c.startRect.y + (e.y - c.startY) / c.scale
      c.snapMove(b, i, x, y)
      i.x = x
      i.y = y
      c.clampItem(b, i)
      c.badge = fmt1(i.x) & " ; " & fmt1(i.y) & " mm"
      markDirty(c)
    of rdBand:
      let b = c.selBand
      if b == nil: return
      var hmm = max(2.0, c.startBandH + (e.y - c.startY) / c.scale)
      var lowest = 0.0
      for i in b.items: lowest = max(lowest, i.y + i.h)
      c.guides.setLen(0)
      if abs(hmm - lowest) <= snapPx / c.scale and lowest > 0:
        hmm = lowest
        let r = c.bodyRect(b)
        c.guides.add((r.x, r.y + lowest * c.scale, r.x + r.w, r.y + lowest * c.scale))
      else: hmm = snapHalf(hmm)
      b.height = max(hmm, lowest)
      c.badge = "hauteur " & fmt1(b.height) & " mm"
      markDirty(c)
    else: discard
  of maRelease:
    let was = c.drag
    c.drag = rdNone
    c.guides.setLen(0)
    c.badge = ""
    if was == rdResize or was == rdBand or (was == rdMove and c.moved): c.changed()
    markDirty(c)

method onKey*(c: ReportCanvas, e: KeyEvent): bool =
  case e.key
  of SDLK_DELETE, SDLK_BACKSPACE:
    c.deleteSelected()
  of SDLK_ESCAPE:
    case c.sel
    of skItem: c.selectBand(c.bandOfItem(c.selItem))
    of skBand: c.selectNone()
    else: discard
  of SDLK_LEFT, SDLK_RIGHT, SDLK_UP, SDLK_DOWN:
    if c.sel != skItem or c.selItem == nil: return false
    let step = if (e.mods and KMOD_SHIFT) != 0: 5.0 else: 0.5
    let i = c.selItem
    case e.key
    of SDLK_LEFT: i.x -= step
    of SDLK_RIGHT: i.x += step
    of SDLK_UP: i.y -= step
    else: i.y += step
    c.clampItem(c.bandOfItem(i), i)
    c.changed()
    markDirty(c)
  else: return false
  true

# ------------------------------------------------------------------ palette

const PaletteRows = [("ZONES", ""), ("zone", "▤"), ("entete", "▔"), ("pied", "▁"),
                     ("ÉLÉMENTS", ""), ("texte", "A"), ("champ", "{}"), ("rectangle", "▭"),
                     ("ligne horizontale", "-"), ("ligne verticale", "│"), ("image", "▣"),
                     ("numéro de page", "#"), ("date", "▦")]

proc rowH(t: Theme): float = t.lineHeight + 2

proc rowAt(p: ReportPalette, t: Theme, y: float): int =
  let i = int(floor((y - p.rect.y - 4 + p.scroll) / rowH(t)))
  if i >= 0 and i < PaletteRows.len and PaletteRows[i][1].len > 0: i else: -1

proc newReportPalette*(canvas: ReportCanvas): ReportPalette =
  result = ReportPalette(canvas: canvas, hoverIdx: -1, pressIdx: -1)
  initControl(result)

method preferredSize*(p: ReportPalette, d: Drawing, t: Theme): tuple[w, h: float] = (190.0, 360.0)

method draw*(p: ReportPalette, d: Drawing, t: Theme) =
  d.fillRect(p.rect, t.header)
  d.pushClip(p.rect)
  let rh = rowH(t)
  if not p.hovered: p.hoverIdx = -1
  for i, r in PaletteRows:
    let y = p.rect.y + 4 + float(i) * rh - p.scroll
    let rr = rect(p.rect.x + 6, y, p.rect.w - 12, rh)
    if r[1].len == 0:
      d.textIn(rr, r[0], t.textSecondary, alLeft, 4)
      continue
    if i == p.hoverIdx: d.fillRoundRect(rr, 5, t.surfaceHover)
    let badge = rect(rr.x + 4, y + (rh - 20) / 2, 26, 20)
    d.fillRoundRect(badge, 5, t.accent.withAlpha(50))
    d.textIn(badge, r[1], t.accent, alCenter)
    d.textIn(rect(rr.x + 36, y, rr.w - 36, rh), r[0], t.text)
  d.popClip()

method onMouse*(p: ReportPalette, e: MouseEvent) =
  let t = p.win.theme
  let c = p.canvas
  case e.action
  of maPress:
    p.pressIdx = p.rowAt(t, e.y)
    p.pressX = e.x
    p.pressY = e.y
    p.dragging = false
  of maMove:
    if p.pressIdx >= 0 and p.pressed:
      if not p.dragging and abs(e.x - p.pressX) + abs(e.y - p.pressY) > 5: p.dragging = true
      if p.dragging:
        let kind = PaletteRows[p.pressIdx][0]
        c.drag = rdNew
        c.newKind = kind
        let isZone = kind in ["zone", "entete", "pied"]
        let w = if isZone: c.bodyW else: 120.0
        let h = if isZone: 24.0 else: 22.0
        c.ghost = rect(e.x - w / 2, e.y - h / 2, w, h)
        if c.rect.containsPoint(e.x, e.y):
          c.dropBand = if isZone: nil else: c.nearestBand(e.y)
          c.dropValid = c.dropBand != nil
        else:
          c.dropValid = false
        markDirty(c)
    else:
      p.hoverIdx = p.rowAt(t, e.y)
  of maRelease:
    if p.pressIdx >= 0:
      let kind = PaletteRows[p.pressIdx][0]
      if p.dragging:
        c.drag = rdNone
        if c.rect.containsPoint(e.x, e.y): c.dropNew(kind, e.x, e.y)
      elif p.rowAt(t, e.y) == p.pressIdx:
        c.drag = rdNone
        if kind in ["zone", "entete", "pied"]:
          discard c.addBand(kind, c.selBand)
        else:
          let b = c.targetBand()
          if b != nil:
            let br = c.bodyRect(b)
            var off = 2.0
            for i in b.items:
              if abs(i.x - off) < 0.1 and abs(i.y - 1) < 0.1: off += 4
            c.dropNew(kind, br.x + (off + 2) * c.scale, br.y + 2 * c.scale)
    c.drag = rdNone
    c.newKind = ""
    c.dropValid = false
    c.dropBand = nil
    c.ghost = rect(0, 0, 0, 0)
    p.pressIdx = -1
    p.dragging = false
    markDirty(c)

method onWheel*(p: ReportPalette, dx, dy: float): bool =
  let t = p.win.theme
  let total = float(PaletteRows.len) * rowH(t) + 8
  p.scroll = clamp(p.scroll - dy * 30, 0.0, max(0.0, total - p.rect.h))
  true

# ------------------------------------------------------------------ API du canevas
# (aussi utilisée par le paquet interface : éditeur d'états de l'atelier en Lexis+)

proc findNode*(c: ReportCanvas, uid: int): tuple[found: bool, kind: SelKind, band: RBand, item: RItem] =
  if c.model.uid == uid: return (true, skReport, nil, nil)
  for b in c.model.bands:
    if b.uid == uid: return (true, skBand, b, nil)
    for i in b.items:
      if i.uid == uid: return (true, skItem, b, i)

proc selectedUid*(c: ReportCanvas): int =
  case c.sel
  of skItem: (if c.selItem != nil: c.selItem.uid else: c.model.uid)
  of skBand: (if c.selBand != nil: c.selBand.uid else: c.model.uid)
  else: c.model.uid

proc selectUid*(c: ReportCanvas, uid: int) =
  ## Sélection sans événement (hiérarchie).
  let n = c.findNode(uid)
  if not n.found: return
  c.sel = n.kind
  c.selBand = n.band
  c.selItem = n.item
  markDirty(c)

proc selectionTitle*(c: ReportCanvas): string =
  case c.sel
  of skReport: "État  " & c.model.name & "   (" & fmt1(c.model.pageSize.w) & " x " & fmt1(c.model.pageSize.h) & " mm)"
  of skBand: "Zone  " & c.selBand.name
  of skItem: c.selItem.kind & "  " & c.selItem.name

proc inspectorRows*(c: ReportCanvas): seq[tuple[target: string, d: PropDef, v: string]] =
  ## Lignes de l'inspecteur pour la sélection : géométrie (mm), puis propriétés.
  case c.sel
  of skReport:
    for d in reportProps(): result.add(("prop", d, c.model.getProp(d.name)))
  of skBand:
    let b = c.selBand
    result.add(("geom", PropDef(name: "hauteur", kind: pkFloat), fmt1(b.height)))
    for d in bandProps(): result.add(("prop", d, b.getProp(d.name)))
  of skItem:
    let i = c.selItem
    result.add(("geom", PropDef(name: "x", kind: pkFloat), fmt1(i.x)))
    result.add(("geom", PropDef(name: "y", kind: pkFloat), fmt1(i.y)))
    result.add(("geom", PropDef(name: "largeur", kind: pkFloat), fmt1(i.w)))
    result.add(("geom", PropDef(name: "hauteur", kind: pkFloat), fmt1(i.h)))
    for d in itemProps(i.kind): result.add(("prop", d, i.getProp(d.name)))

proc selectionHelp*(c: ReportCanvas): string =
  if c.sel == skItem and c.selItem != nil:
    if c.selItem.kind == KindTexte:
      return "{nom} : variable donnée à r.ajoute(zone, {nom = …}) ; {nom:2} : nombre à 2 décimales ; " &
             "{page}, {nombre de page}, {date}, {heure} : calculées."
    if c.selItem.kind == KindImage:
      return "chemin : PNG ou JPEG, relatif au dossier du programme ; peut contenir une {variable}."

proc setSelectionValue*(c: ReportCanvas, target, prop: string, value: string): string =
  ## Modifie la sélection (target "geom" : position, taille, hauteur ; "prop" : propriété).
  ## "" si c'est fait, sinon le message.
  var kind = pkString
  case c.sel
  of skReport:
    for d in reportProps():
      if d.name == prop: kind = d.kind
  of skBand:
    for d in bandProps():
      if d.name == prop: kind = d.kind
  of skItem:
    for d in itemProps(c.selItem.kind):
      if d.name == prop: kind = d.kind
  if kind == pkColor and value.strip.len > 0 and rgbOf(value).isNone: return "Couleur : #RRGGBB"
  case c.sel
  of skReport:
    c.model.setProp(prop, value)
  of skBand:
    let b = c.selBand
    if target == "geom":
      var lowest = 0.0
      for i in b.items: lowest = max(lowest, i.y + i.h)
      b.height = max(max(2.0, lowest), fnum(value, b.height))
    else: b.setProp(prop, value)
  of skItem:
    let i = c.selItem
    if target == "geom":
      if fnum(value, -1) >= 0:
        let v = fnum(value, 0)
        case prop
        of "x": i.x = v
        of "y": i.y = v
        of "largeur": i.w = v
        else: i.h = v
        c.clampItem(c.bandOfItem(i), i)
    else: i.setProp(prop, value)
  markDirty(c)
  ""

proc renameNode*(c: ReportCanvas, uid: int, newName, root: string): tuple[msg, oldReport: string] =
  ## Renomme l'état, une zone ou un élément. Pour l'état, oldReport donne l'ancien nom :
  ## l'appelant supprime alors l'ancien fichier etat_<ancien>.prg.
  let v = newName.strip
  let m = c.model
  let n = c.findNode(uid)
  if not n.found: return ("élément introuvable", "")
  case n.kind
  of skReport:
    if not isName(v): return ("Nom de l'état : lettre, puis lettres, chiffres ou _", "")
    if v == m.name: return ("", "")
    if fileExists(root / reportFileName(v)): return (reportFileName(v) & " existe déjà", "")
    result.oldReport = m.name
    m.name = v
  of skBand:
    if not isName(v): return ("Nom de zone : lettre, puis lettres, chiffres ou _", "")
    let other = m.findBand(v)
    if other != nil and other != n.band: return ("« " & v & " » existe déjà", "")
    n.band.name = v
  of skItem:
    if not isName(v): return ("Nom : lettre, puis lettres, chiffres ou _", "")
    n.item.name = v
  markDirty(c)

proc reportExampleCode*(m: ReportModel): string =
  ## Code Lexis+ qui remplit l'état : une ligne par zone, avec ses variables.
  proc varsOf(b: RBand): seq[string] =
    var seen = initHashSet[string]()
    for i in b.items:
      var s = i.getProp("texte") & " " & i.getProp("chemin")
      var k = 0
      while true:
        let a = s.find('{', k)
        if a < 0: break
        let z = s.find('}', a + 1)
        if z < 0: break
        var n = s[a + 1 ..< z].strip
        if ':' in n: n = n[0 ..< n.rfind(':')].strip
        let low = n.toLowerAscii
        if low notin ["page", "nombre de page", "nombre de pages", "date", "heure", "pages"] and
           isName(n) and low notin seen:
          seen.incl low
          result.add n
        k = z + 1
  proc call(fn: string, b: RBand): string =
    var parts: seq[string]
    for v in varsOf(b): parts.add v & " = \"\""
    "r." & fn & "(\"" & b.name & "\", {" & parts.join(", ") & "})"
  var l = @["&& état « " & m.name & " » (" & reportFileName(m.name) & ")",
            "r = rapport.debut(\"" & m.name & ".pdf\")"]
  for b in m.bands:
    if b.name == "entete" and varsOf(b).len > 0: l.add call("entete", b)
    elif b.name == "pied" and varsOf(b).len > 0: l.add call("pied", b)
  for b in m.bands:
    if b.name notin ["entete", "pied"]: l.add call("ajoute", b)
  l.add "? \"PDF :\", r.fin()"
  l.join("\n") & "\n"

proc writePreview*(m: ReportModel, path, root: string): seq[string] =
  ## Aperçu PDF (chaque zone trois fois, variables affichées) ; renvoie les images illisibles.
  let run = sampleRun(m, path, root)
  let d = run.render()
  d.save(path)
  d.imageErrors

# ------------------------------------------------------------------ fenêtre de l'éditeur

type ReportFrame = ref object of Container
  ## Conteneur du canevas.
  canvas: ReportCanvas


var
  rWin, rCanvas, rTree, rInspector, rTitle, rStatus: ControlId
  rRoot: string
  rEditor: ControlId
  rOpen: bool
  rTheme: Theme
  rRows: seq[tuple[id: ControlId, target: string, prop: string, kind: PropKind, choices: seq[string]]]
  rColorButtons: seq[tuple[id: ControlId, prop: string, edit: ControlId]]
  rTreePaths: seq[tuple[path: string, kind: SelKind, uid: int]]
  rTools: seq[tuple[id: ControlId, cmd: string]]
  rNameRow: tuple[id: ControlId, kind: SelKind, uid: int, text: string]
  reportFileCreated*: proc (path: string) {.nimcall, gcsafe.}     # posé par l'atelier (arbre du projet).
  rOpLock: Lock
initLock(rOpLock)

proc status(s: string) = rStatus.caption = s

proc reportName(): string =
  readControl(rCanvas, ReportCanvas, c): result = c.model.name

proc saveReport() =
  var code, name: string
  readControl(rCanvas, ReportCanvas, c):
    code = generateReportCode(c.model)
    name = c.model.name
  let path = normalizedPath(absolutePath(rRoot / reportFileName(name)))
  let isNew = not fileExists(path)
  try: writeFile(path, code)
  except CatchableError:
    status("Écriture impossible : " & path)
    return
  let uid = editorUidOf(rEditor, path)
  if uid >= 0: discard editorSetText(rEditor, uid, code, modified = false)
  rWin.caption = "Éditeur d'états - " & reportFileName(name)
  status("Enregistré : " & reportFileName(name) & "  ·  rapport.debut(\"" & name & ".pdf\")")
  if isNew and reportFileCreated != nil: reportFileCreated(path)

proc treePath(m: ReportModel, b: RBand, i: RItem): string =
  result = "état " & m.name
  if b != nil: result.add $TreeSep & b.name
  if i != nil: result.add $TreeSep & i.name

proc rebuildTree() =
  var items: seq[tuple[path: string, kind: SelKind, uid: int, container: bool]]
  var sel = ""
  readControl(rCanvas, ReportCanvas, c):
    let m = c.model
    items.add((treePath(m, nil, nil), skReport, m.uid, true))
    for b in m.bands:
      items.add((treePath(m, b, nil), skBand, b.uid, true))
      for i in b.items: items.add((treePath(m, b, i), skItem, i.uid, false))
    sel = case c.sel
      of skItem: (if c.selItem != nil: treePath(m, c.bandOfItem(c.selItem), c.selItem) else: "")
      of skBand: (if c.selBand != nil: treePath(m, c.selBand, nil) else: "")
      else: treePath(m, nil, nil)
  treeDeleteAll(rTree)
  guarded: rTreePaths.setLen(0)
  for it in items:
    treeAdd(rTree, it.path, it.container)
    guarded: rTreePaths.add((it.path, it.kind, it.uid))
  if sel.len > 0: treeSelectPlus(rTree, sel)

proc addRow(label: string, editorCtl: Control, extra: Control = nil) =
  let row = newSupercontrol(lkHorizontal, 6)
  row.fixedWidth = 318          # tient dans l'inspecteur (360 px) : pas de défilement horizontal
  let l = newLabel(label)
  l.fixedWidth = 112
  discard row.addChild(l)
  editorCtl.weight = 1
  discard row.addChild(editorCtl)
  if extra != nil: discard row.addChild(extra)
  discard addChild(rInspector, row)

proc propRow(target: string, d: PropDef, v: string) =
  var ctl: Control
  var extra: Control = nil
  case d.kind
  of pkBool: ctl = newCheckBox("", isTrueProp(v))
  of pkEnum: ctl = newComboBox(d.choices, max(0, d.choices.find(v)))
  of pkInt: ctl = newEdit(v, ikInteger)
  of pkFloat: ctl = newEdit(v, ikReal)
  of pkColor:
    ctl = newEdit(v, placeholder = "#RRGGBB")
    extra = newButton("…")
    extra.fixedWidth = 36
  of pkList, pkString:
    ctl = newEdit(v)
  addRow(d.name, ctl, extra)
  guarded:
    rRows.add((ctl.id, target, d.name, d.kind, d.choices))
    if extra != nil: rColorButtons.add((extra.id, d.name, ctl.id))

proc rebuildInspector() =
  var sel: SelKind
  var name, title, help: string
  var uid = 0
  var rows: seq[tuple[target: string, d: PropDef, v: string]]
  readControl(rCanvas, ReportCanvas, c):
    sel = c.sel
    uid = c.selectedUid
    name = case sel
      of skReport: c.model.name
      of skBand: c.selBand.name
      of skItem: c.selItem.name
    title = c.selectionTitle
    rows = c.inspectorRows
    help = c.selectionHelp
  for id in children(rInspector): deleteControl(id)
  guarded:
    rRows.setLen(0)
    rColorButtons.setLen(0)
  rTitle.caption = title
  discard addChild(rInspector, newLabel("PROPRIÉTÉS" & (if sel == skItem or sel == skBand: "   (mm)" else: "")))
  let nameEdit = newEdit(name)
  nameEdit.tooltip = "Entrée (ou sortie du champ) pour renommer"
  addRow((if sel == skReport: "nom (fichier)" else: "nom"), nameEdit)
  guarded: rNameRow = (nameEdit.id, sel, uid, name)
  for r in rows: propRow(r.target, r.d, r.v)
  if help.len > 0:
    let l = newMarkdownView(help)       # revient à la ligne dans la largeur de l'inspecteur
    l.fixedWidth = 318
    l.fixedHeight = 70
    discard addChild(rInspector, l)

proc applyValue(target, prop: string, kind: PropKind, value: string) =
  var msg = ""
  withControl(rCanvas, ReportCanvas, c): msg = c.setSelectionValue(target, prop, value)
  if msg.len > 0:
    status(msg)
    return
  saveReport()

proc applyName(kind: SelKind, uid: int, value: string) =
  var r: tuple[msg, oldReport: string]
  withControl(rCanvas, ReportCanvas, c): r = c.renameNode(uid, value, rRoot)
  if r.msg.len > 0:
    status(r.msg)
    return
  let newReport = if r.oldReport.len > 0: reportName() else: ""
  if r.oldReport.len > 0:
    let old = rRoot / reportFileName(r.oldReport)
    let u = editorUidOf(rEditor, old)
    if u >= 0: editorClose(rEditor, u)
    try:
      if fileExists(old): removeFile(old)
    except CatchableError: discard
  saveReport()
  if newReport.len > 0:
    if reportFileCreated != nil: reportFileCreated(rRoot / reportFileName(newReport))
    status("État renommé : " & reportFileName(newReport) & " (pensez à rapport.debut(\"" & newReport & ".pdf\"))")
  rebuildTree()
  rebuildInspector()

proc exampleCode(): string =
  readControl(rCanvas, ReportCanvas, c): result = reportExampleCode(c.model)

proc previewPdf() =
  var path = ""
  var errs: seq[string]
  var name = ""
  readControl(rCanvas, ReportCanvas, c):
    name = c.model.name
    path = getTempDir() / ("wdlexis_apercu_" & name & ".pdf")
    try:
      errs = writePreview(c.model, path, rRoot)
    except CatchableError as e:
      errs.add e.msg
      path = ""
  if path.len == 0:
    status("Aperçu impossible : " & errs.join("; "))
    return
  if errs.len > 0: status("Images illisibles : " & errs.join("; "))
  if not pdfAvailable():
    alert(iconInformation, "Aperçu écrit dans :\n" & path & "\n\n(" & pdfError() & ")", title = "Aperçu PDF")
    return
  var vid: ControlId
  guarded:
    let w = newWindow("Aperçu - " & name & ".pdf", 860, 860, nil, rTheme, lkVertical)
    w.root.margin = 0
    let v = w.addChild(newPdfViewer())
    v.weight = 1
    vid = v.id
  discard pdfOpen(vid, path)

proc readZoom(): float =
  readControl(rCanvas, ReportCanvas, c): result = c.scale / 3.0 * 100

proc reportCommand(cmd: string) =
  case cmd
  of "save": saveReport()
  of "delete":
    withControl(rCanvas, ReportCanvas, c): c.deleteSelected()
  of "up":
    withControl(rCanvas, ReportCanvas, c): c.moveSelected(-1)
  of "down":
    withControl(rCanvas, ReportCanvas, c): c.moveSelected(1)
  of "zone":
    withControl(rCanvas, ReportCanvas, c): discard c.addBand("zone", c.selBand)
  of "report":
    withControl(rCanvas, ReportCanvas, c): c.selectNone()
  of "preview": previewPdf()
  of "code":
    let code = exampleCode()
    if editorActiveUid(rEditor) >= 0:
      editorInsert(rEditor, code)
      editorFlush(rEditor)
      status("Code d'exemple inséré dans l'éditeur, au curseur")
    else:
      status("Ouvrez d'abord un fichier .prg dans l'atelier")
  of "zoomin", "zoomout":
    withControl(rCanvas, ReportCanvas, c):
      c.scale = clamp(c.scale * (if cmd == "zoomin": 1.25 else: 0.8), 1.5, 8.0)
      c.texts.clear()
    status("Zoom : " & $int(round(readZoom())) & " %")
  else: discard

proc reportEvent(ev: var Event) =
  block:
    if ev.id == rCanvas:
      case ev.kind
      of evSelection:
        rebuildInspector()
        rebuildTree()
      of evChange:
        saveReport()
        rebuildTree()
        rebuildInspector()
      else: discard
      return
    if ev.id == rTree and ev.kind == evSelection:
      var kind = skReport
      var uid = -1
      guarded:
        for p in rTreePaths:
          if p.path == ev.text:
            kind = p.kind
            uid = p.uid
      if uid < 0: return
      withControl(rCanvas, ReportCanvas, c): c.selectUid(uid)
      rebuildInspector()
      return
    if ev.kind == evWindowClose and ev.id == rWin:
      guarded: rOpen = false
      return
    var nameRow: tuple[id: ControlId, kind: SelKind, uid: int, text: string]
    guarded: nameRow = rNameRow
    if ev.id == nameRow.id:
      case ev.kind
      of evChange:
        let v = ev.id.value
        guarded: rNameRow.text = v
      of evKeyDown, evFocusLost:
        if ev.kind == evKeyDown and int(ev.key) notin [0x0D, 0x40000058]: return
        let v = (if ev.kind == evKeyDown: ev.id.value else: nameRow.text).strip
        if v.len > 0: applyName(nameRow.kind, nameRow.uid, v)
      else: discard
      return
    if ev.kind == evClick:
      var cmd = ""
      guarded:
        for t in rTools:
          if t.id == ev.id: cmd = t.cmd
      if cmd.len > 0:
        reportCommand(cmd)
        return
      var colorProp = ""
      var colorEdit: ControlId
      guarded:
        for cb in rColorButtons:
          if cb.id == ev.id:
            colorProp = cb.prop
            colorEdit = cb.edit
      if colorProp.len > 0:
        var col = if rgbOf(colorEdit.value).isSome: hex(colorEdit.value) else: hex"#000000"
        if colorDialog(col) == drOk:
          colorEdit.value = hexOf(col)
          applyValue("prop", colorProp, pkColor, hexOf(col))
      return
    if ev.kind in {evChange, evSelection}:
      var target, prop = ""
      var kind = pkString
      var choices: seq[string]
      guarded:
        for r in rRows:
          if r.id == ev.id:
            target = r.target
            prop = r.prop
            kind = r.kind
            choices = r.choices
      if prop.len == 0: return
      var value = ev.id.value
      case kind
      of pkBool: value = (if value == "1": "true" else: "false")
      of pkEnum:
        let i = listSelect(ev.id) - 1
        value = if i >= 0 and i < choices.len: choices[i] else: ""
      else: discard
      applyValue(target, prop, kind, value)
      if target == "geom" or prop in ["extensible", "sautavant", "format", "orientation"] or prop.startsWith("marge"):
        rebuildTree()

proc reportHandler(ev: var Event) {.nimcall, gcsafe.} =
  # Un événement à la fois (un fil par événement dans wdgui) ; corps à part : voir designer.nim.
  if ev.current != ev.id: return
  {.cast(gcsafe).}:
    withLock rOpLock: reportEvent(ev)

proc openReportDesigner*(root, reportFile: string, editorId: ControlId, theme: Theme): string =
  ## Ouvre l'éditeur d'états ; reportFile : etat_<nom>.prg à rouvrir, "" pour un état neuf.
  ## Renvoie "" si c'est fait, sinon la raison.
  var already = false
  guarded: already = rOpen
  if already: return "L'éditeur d'états est déjà ouvert."
  var model: ReportModel = nil
  if reportFile.len > 0:
    let uid = editorUidOf(editorId, reportFile)
    try:
      model = parseReportCode(if uid >= 0: editorText(editorId, uid) else: readFile(reportFile))
    except CatchableError: model = nil
    if model == nil: return "« " & extractFilename(reportFile) & " » ne contient pas de description d'état."
  else:
    model = newReport(nextReportName(root))
  guarded:
    rOpen = true
    rRoot = root
    rEditor = editorId
    rTheme = theme
    rTools.setLen(0)
    let win = newWindow("Éditeur d'états", 1320, 860, reportHandler, theme, lkBorder)
    win.root.margin = 0
    win.root.spacing = 0
    rWin = win.id
    let tb = win.addChild(newToolbar())
    tb.dock = dkTop
    for (caption, cmd, tip) in [("Enregistrer", "save", "Régénère etat_<nom>.prg"),
                                ("Supprimer", "delete", "Supprime l'élément ou la zone sélectionné (Suppr)"),
                                ("Monter", "up", "Zone : plus haut dans l'état ; élément : dessiné plus tôt"),
                                ("Descendre", "down", "Zone : plus bas dans l'état ; élément : dessiné plus tard"),
                                ("Nouvelle zone", "zone", "Ajoute une zone nommée après la zone sélectionnée"),
                                ("État", "report", "Sélectionne l'état (format, orientation, marges)"),
                                ("Aperçu PDF", "preview", "Génère le PDF avec chaque zone trois fois, variables affichées"),
                                ("Insérer le code", "code", "Insère dans l'éditeur le code Lexis+ qui remplit l'état"),
                                ("Zoom +", "zoomin", "Agrandit la page"), ("Zoom −", "zoomout", "Réduit la page")]:
      let b = tb.addTool(caption, tip)
      rTools.add((b.id, cmd))
    let st = win.addChild(newLabel("Glisser depuis la palette · bord bas d'une zone : hauteur · Suppr supprime · " &
                                   "flèches : 0,5 mm (Maj : 5 mm)"))
    st.dock = dkBottom
    rStatus = st.id
    let canvas = newReportCanvas(model, root)
    let pal = newReportPalette(canvas)
    let left = win.addChild(newContainer(lkBorder, 0, 0))
    left.dock = dkLeft
    left.fixedWidth = 200
    let lt = left.addChild(newLabel("  PALETTE"))
    lt.dock = dkTop
    pal.dock = dkCenter
    discard left.addChild(pal)
    let right = win.addChild(newContainer(lkBorder, 6, 6))
    right.dock = dkRight
    right.fixedWidth = 360
    let top = right.addChild(newContainer(lkVertical, 0, 4))
    top.dock = dkTop
    discard top.addChild(newLabel("HIÉRARCHIE"))
    let tree = top.addChild(newTreeView())
    tree.fixedHeight = 220
    rTree = tree.id
    let title = top.addChild(newLabel(""))
    title.style.text = some(theme.accent)
    rTitle = title.id
    let insp = right.addChild(newPanel(lkVertical, smAutomatic, 2, 4))
    insp.dock = dkCenter
    rInspector = insp.id
    let area = win.addChild(newPanel(lkVertical, smAutomatic, 0, 0))
    area.dock = dkCenter
    let frame = ReportFrame(layout: lkVertical, margin: 0, spacing: 0, canvas: canvas)
    initControl(frame)
    discard area.addChild(frame)
    discard frame.addChild(canvas)
    rCanvas = canvas.id
    win.focusedControl = canvas
    canvas.focus = true
  saveReport()
  rebuildTree()
  rebuildInspector()
  ""

proc reportDesignerIsOpen*(): bool =
  guarded: result = rOpen

proc closeReportDesigner*() =
  var w: ControlId
  var open = false
  guarded:
    open = rOpen
    w = rWin
  if open: closeWindow(w)


method dispose*(c: ReportCanvas) =
  for f in c.fonts.values:
    if f != nil: TTF_CloseFont(f)
  c.fonts.clear()
  for e in c.texts.values: SDL_DestroyTexture(e.tex)
  c.texts.clear()
  for e in c.images.values: SDL_DestroyTexture(e.tex)
  c.images.clear()
