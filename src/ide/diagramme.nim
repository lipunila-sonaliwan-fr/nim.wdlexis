# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - canevas de diagramme (nœuds et liens) : modèles entité-relation, plans
#   d'exécution, flux de traitement, cartographies.
#
# * Nœud : un titre (bandeau coloré), un sous-titre, des lignes (texte, détail, marque :
#   « PK », « FK »…), une pastille et une jauge facultatives. Formes : « table » (bandeau
#   et lignes) et « boite » (titre seul, coins arrondis).
# * Lien : d'un nœud (ou d'une ligne d'un nœud) vers un autre ; libellé, flèche,
#   pointillés, couleur, épaisseur. Courbe de Bézier d'un bord à l'autre.
# * Souris : clic (sélection d'un nœud, d'une ligne ou d'un lien), glisser un nœud
#   (déplacement), glisser le fond (panoramique), molette (zoom autour du pointeur),
#   glisser depuis la pastille d'un bord (en mode modifiable) : création d'un lien.
#   Clavier : Suppr signale une demande de suppression, Échap désélectionne.
# * Événements : evSelection (texte : id du nœud, « lien:<id> » ou ""), evChange
#   (texte : « deplace », « lien » ou « supprimer » ; détail dans lastAction).
# * Disposition automatique en couches (sources à gauche ou en haut), nœuds isolés
#   rangés en grille ; « ajuster » cadre l'ensemble.
#
# Le modèle est manipulé par le paquet interface (interface.diagramme) sous verrou
# (withControl) ; le dessin et la souris s'exécutent sur le fil de l'interface.

import std/[math, strutils, tables, algorithm, sequtils, os]
import ../wdgui
import ../sdl3

type
  DiaRow* = object
    text*, detail*, mark*: string
  DiaNode* = ref object
    id*, title*, subtitle*, badge*, shape*: string
    rows*: seq[DiaRow]
    x*, y*, w*, h*: float               # coordonnées logiques (zoom 1)
    color*: Color
    gauge*: float                       # 0..1 ; < 0 : pas de jauge
    measured: bool
  DiaLink* = object
    id*, src*, dst*, label*: string
    srcRow*, dstRow*: int               # 1..n : ligne ; 0 : le nœud
    dashed*, arrow*: bool
    color*: Color
    width*: float
  DDrag = enum ddNone, ddMove, ddPan, ddLink
  DAction* = tuple[action, id, src, dst: string, srcRow, dstRow: int]
  DiagramCanvas* = ref object of Control
    nodes*: seq[DiaNode]
    links*: seq[DiaLink]
    zoom*, panX*, panY*: float
    editable*: bool
    direction*: string                  # « droite » (gauche → droite) ou « bas »
    selected*: string                   # id du nœud sélectionné
    selRow*: int
    selLink*: string
    lastAction*: DAction
    drag: DDrag
    dragId: string
    startX, startY, origX, origY: float
    moved: bool
    linkFrom: string
    linkFromRow: int
    curX, curY: float
    hoverPort: tuple[id: string, row: int]
    needFit*: bool
    fitMin*: float                 # zoom minimal de fit() (0 : 0,2) ; en dessous, cadré en haut à gauche
    fonts: Table[int, TTF_Font]             # (gras * 1000 + taille en px)
    texts: Table[string, tuple[tex: SDL_Texture, w, h: float]]
    fontFiles: seq[string]

const
  HeadH = 26.0
  RowH = 19.0
  SubH = 15.0
  PadX = 10.0
  PortR = 4.5

# ------------------------------------------------------------------ texte à l'échelle

proc fontAt(c: DiagramCanvas, px: int, bold: bool): TTF_Font =
  let key = (if bold: 1000 else: 0) + px
  if c.fonts.hasKey(key): return c.fonts[key]
  result = nil
  for p in c.fontFiles:
    if fileExists(p):
      result = TTF_OpenFont(p.cstring, cfloat(px))
      if result != nil:
        if bold: TTF_SetFontStyle(result, 1'u32)
        break
  c.fonts[key] = result

proc textW(c: DiagramCanvas, d: Drawing, s: string, px: int, bold = false): float =
  if s.len == 0: return 0
  let f = c.fontAt(px, bold)
  if f == nil: return d.textWidth(s) * px.float / 13.0
  var w, h: cint
  if TTF_GetStringSize(f, s.cstring, csize_t(s.len), addr w, addr h): float(w) else: 0.0

proc fitText(c: DiagramCanvas, d: Drawing, s: string, px: int, bold: bool, maxW: float): string =
  if c.textW(d, s, px, bold) <= maxW: return s
  var r = s
  while r.len > 0:
    var k = r.len - 1
    while k > 0 and (ord(r[k]) and 0xC0) == 0x80: dec k
    r = r[0 ..< k]
    if c.textW(d, r & "…", px, bold) <= maxW: return r & "…"
  ""

proc drawT(c: DiagramCanvas, d: Drawing, s: string, r: Rect, px: int, bold: bool, col: Color, al = alLeft) =
  ## Texte à la taille px (déjà multipliée par le zoom), centré verticalement dans r.
  if s.len == 0 or px < 5 or r.w <= 4: return
  let f = c.fontAt(px, bold)
  if f == nil:
    d.textIn(r, d.ellipsize(s, r.w), col, al)
    return
  let txt = c.fitText(d, s, px, bold, r.w)
  if txt.len == 0: return
  let key = $px & (if bold: "b" else: "") & "|" & txt
  var e = c.texts.getOrDefault(key)
  if e.tex == nil:
    if c.texts.len > 3000:
      for o in c.texts.values: SDL_DestroyTexture(o.tex)
      c.texts.clear()
    let surf = TTF_RenderText_Blended(f, txt.cstring, csize_t(txt.len), SDL_Color(r: 255, g: 255, b: 255, a: 255))
    if surf == nil: return
    let tex = SDL_CreateTextureFromSurface(d.ren, surf)
    SDL_DestroySurface(surf)
    if tex == nil: return
    var w, h: cfloat
    discard SDL_GetTextureSize(tex, addr w, addr h)
    e = (tex, float(w), float(h))
    c.texts[key] = e
  discard SDL_SetTextureColorMod(e.tex, col.r, col.g, col.b)
  discard SDL_SetTextureAlphaMod(e.tex, col.a)
  let x = case al
    of alCenter: r.x + (r.w - e.w) / 2
    of alRight: r.x + r.w - e.w
    else: r.x
  d.drawTexture(e.tex, rect(round(x), round(r.y + (r.h - e.h) / 2), e.w, e.h))

proc newDiagram*(editable = true, direction = "droite"): DiagramCanvas =
  result = DiagramCanvas(zoom: 1.0, editable: editable, direction: direction, selRow: 0)
  initControl(result)
  result.focusable = true

method preferredSize*(c: DiagramCanvas, d: Drawing, t: Theme): tuple[w, h: float] = (400.0, 300.0)

proc findNode*(c: DiagramCanvas, id: string): DiaNode =
  for n in c.nodes:
    if n.id == id: return n

proc estimate(n: DiaNode) =
  ## Taille approchée (avant la première mesure par le dessin).
  if n.measured: return
  var wmax = n.title.len.float * 7.6 + 2 * PadX + (if n.badge.len > 0: n.badge.len.float * 6.5 + 14 else: 0)
  if n.shape != "boite":
    for r in n.rows:
      wmax = max(wmax, (r.text.len + r.detail.len).float * 6.6 + 3 * PadX + (if r.mark.len > 0: 26.0 else: 0))
  n.w = clamp(wmax, 120, 360)
  n.h = (if n.shape == "boite": 36.0 + (if n.subtitle.len > 0: SubH else: 0) else:
           HeadH + (if n.subtitle.len > 0: SubH else: 0) + n.rows.len.float * RowH + 6)

proc measure(c: DiagramCanvas, n: DiaNode, d: Drawing) =
  var w = c.textW(d, n.title, 13, true) + 2 * PadX + (if n.badge.len > 0: c.textW(d, n.badge, 11) + 18 else: 0)
  if n.subtitle.len > 0: w = max(w, c.textW(d, n.subtitle, 11) + 2 * PadX)
  if n.shape != "boite":
    for r in n.rows:
      w = max(w, c.textW(d, r.text, 12) + c.textW(d, r.detail, 11) + 3 * PadX + 8 + (if r.mark.len > 0: 26.0 else: 0))
  n.w = clamp(w, 120, 420)
  n.h = (if n.shape == "boite": 36.0 + (if n.subtitle.len > 0: SubH else: 0) else:
           HeadH + (if n.subtitle.len > 0: SubH else: 0) + n.rows.len.float * RowH + 6)
  n.measured = true

proc invalidate*(n: DiaNode) = n.measured = false

# ------------------------------------------------------------------ géométrie

proc toScreen(c: DiagramCanvas, x, y: float): (float, float) =
  (c.rect.x + c.panX + x * c.zoom, c.rect.y + c.panY + y * c.zoom)

proc toLogical(c: DiagramCanvas, sx, sy: float): (float, float) =
  ((sx - c.rect.x - c.panX) / c.zoom, (sy - c.rect.y - c.panY) / c.zoom)

proc rowsTop(n: DiaNode): float = n.y + HeadH + (if n.subtitle.len > 0: SubH else: 0)

proc rowCenterY(n: DiaNode, row: int): float =
  if row <= 0 or row > n.rows.len or n.shape == "boite": n.y + min(n.h, HeadH) / 2
  else: n.rowsTop + (row.float - 0.5) * RowH

proc anchor(n: DiaNode, row: int, right: bool): (float, float) =
  ((if right: n.x + n.w else: n.x), n.rowCenterY(row))

proc bez(p0, p1, p2, p3: (float, float), t: float): (float, float) =
  let u = 1 - t
  (u*u*u*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t*t*t*p3[0],
   u*u*u*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t*t*t*p3[1])

proc linkPoints(c: DiagramCanvas, l: DiaLink): seq[(float, float)] =
  ## Points logiques de la courbe d'un lien (bord droit de la source vers bord gauche
  ## de la cible, ou l'inverse selon leurs positions ; en disposition « bas » : du bas
  ## vers le haut quand le lien porte sur les nœuds entiers).
  let a = c.findNode(l.src)
  let b = c.findNode(l.dst)
  if a == nil or b == nil: return
  var p0, p3, p1, p2: (float, float)
  if c.direction == "bas" and l.srcRow == 0 and l.dstRow == 0 and b.y >= a.y + a.h - 1:
    p0 = (a.x + a.w / 2, a.y + a.h)
    p3 = (b.x + b.w / 2, b.y)
    let k = max(30.0, (p3[1] - p0[1]) / 2)
    p1 = (p0[0], p0[1] + k)
    p2 = (p3[0], p3[1] - k)
  else:
    let overlap = b.x < a.x + a.w and b.x + b.w > a.x
    var fromRight, toRight: bool
    if overlap:
      fromRight = true
      toRight = true
    elif b.x + b.w / 2 >= a.x + a.w / 2:
      fromRight = true
      toRight = false
    else:
      fromRight = false
      toRight = true
    p0 = a.anchor(l.srcRow, fromRight)
    p3 = b.anchor(l.dstRow, toRight)
    let k = max(40.0, abs(p3[0] - p0[0]) / 2)
    p1 = (p0[0] + (if fromRight: k else: -k), p0[1])
    p2 = (p3[0] + (if toRight: k else: -k), p3[1])
  for i in 0 .. 20: result.add bez(p0, p1, p2, p3, i / 20)

proc distSeg(px, py, ax, ay, bx, by: float): float =
  let dx = bx - ax
  let dy = by - ay
  let L = dx * dx + dy * dy
  var t = if L == 0: 0.0 else: ((px - ax) * dx + (py - ay) * dy) / L
  t = clamp(t, 0.0, 1.0)
  hypot(px - (ax + t * dx), py - (ay + t * dy))

proc nodeAt(c: DiagramCanvas, lx, ly: float): DiaNode =
  for i in countdown(c.nodes.high, 0):
    let n = c.nodes[i]
    if lx >= n.x and lx <= n.x + n.w and ly >= n.y and ly <= n.y + n.h: return n

proc rowAt(n: DiaNode, ly: float): int =
  if n.shape == "boite" or n.rows.len == 0: return 0
  let r = int(floor((ly - n.rowsTop) / RowH)) + 1
  if r >= 1 and r <= n.rows.len: r else: 0

proc portAt(c: DiagramCanvas, lx, ly: float): tuple[id: string, row: int] =
  ## Pastille de bord droit (titre ou ligne) sous le pointeur, en mode modifiable.
  if not c.editable: return ("", 0)
  let tol = 7.0 / c.zoom
  for i in countdown(c.nodes.high, 0):
    let n = c.nodes[i]
    if abs(lx - (n.x + n.w)) <= tol:
      if ly >= n.y and ly <= n.y + HeadH: return (n.id, 0)
      let r = n.rowAt(ly)
      if r > 0: return (n.id, r)
  ("", 0)

proc linkAt(c: DiagramCanvas, lx, ly: float): string =
  let tol = 5.0 / c.zoom
  for l in c.links:
    let pts = c.linkPoints(l)
    for i in 1 ..< pts.len:
      if distSeg(lx, ly, pts[i-1][0], pts[i-1][1], pts[i][0], pts[i][1]) <= tol: return l.id

# ------------------------------------------------------------------ disposition

proc bounds*(c: DiagramCanvas): tuple[x, y, w, h: float] =
  if c.nodes.len == 0: return (0.0, 0.0, 0.0, 0.0)
  var x0, y0 = Inf
  var x1, y1 = -Inf
  for n in c.nodes:
    n.estimate()
    x0 = min(x0, n.x)
    y0 = min(y0, n.y)
    x1 = max(x1, n.x + n.w)
    y1 = max(y1, n.y + n.h)
  (x0, y0, x1 - x0, y1 - y0)

proc fit*(c: DiagramCanvas) =
  ## Cadre l'ensemble dans le contrôle (zoom ≤ 1).
  if c.nodes.len == 0 or c.rect.w < 10 or c.rect.h < 10:
    c.needFit = true
    return
  let b = c.bounds
  let zmin = if c.fitMin > 0: min(c.fitMin, 1.0) else: 0.2
  let z = clamp(min((c.rect.w - 40) / max(1.0, b.w), (c.rect.h - 40) / max(1.0, b.h)), zmin, 1.0)
  c.zoom = z
  c.panX = (c.rect.w - b.w * z) / 2 - b.x * z
  c.panY = (c.rect.h - b.h * z) / 2 - b.y * z
  # trop grand pour la vue : on montre le début (gauche, ou haut en mode « bas »)
  if b.w * z > c.rect.w - 40: c.panX = 20 - b.x * z
  if b.h * z > c.rect.h - 40: c.panY = 20 - b.y * z
  c.needFit = false

proc layout*(c: DiagramCanvas, direction = "") =
  ## Disposition en couches : chaque nœud un cran après ses prédécesseurs (plus long
  ## chemin), ordre dans la couche par barycentre ; nœuds isolés en grille à la suite.
  if direction.len > 0: c.direction = direction
  let horiz = c.direction != "bas"
  var idx = initTable[string, int]()
  for i, n in c.nodes:
    idx[n.id] = i
    n.estimate()
  var succ = newSeq[seq[int]](c.nodes.len)
  var pred = newSeq[seq[int]](c.nodes.len)
  for l in c.links:
    if l.src == l.dst or not idx.hasKey(l.src) or not idx.hasKey(l.dst): continue
    let a = idx[l.src]
    let b = idx[l.dst]
    if b notin succ[a]:
      succ[a].add b
      pred[b].add a
  # couches (cycles ignorés : arêtes vers un nœud en cours de visite)
  var layer = newSeq[int](c.nodes.len)
  var state = newSeq[int](c.nodes.len)          # 0 : neuf, 1 : en cours, 2 : fait
  proc visit(i: int) =
    state[i] = 1
    var lv = 0
    for p in pred[i]:
      if state[p] == 1: continue
      if state[p] == 0: visit(p)
      lv = max(lv, layer[p] + 1)
    layer[i] = lv
    state[i] = 2
  for i in 0 ..< c.nodes.len:
    if state[i] == 0: visit(i)
  var isolated: seq[int]
  var maxLayer = 0
  for i in 0 ..< c.nodes.len:
    if succ[i].len == 0 and pred[i].len == 0: isolated.add i
    else: maxLayer = max(maxLayer, layer[i])
  var layers = newSeq[seq[int]](maxLayer + 1)
  for i in 0 ..< c.nodes.len:
    if not (succ[i].len == 0 and pred[i].len == 0): layers[layer[i]].add i
  # ordre par barycentre (quelques passes descendantes puis montantes)
  var pos = newSeq[float](c.nodes.len)
  for L in layers:
    for k, i in L: pos[i] = k.float
  for pass in 0 ..< 4:
    let rng = if pass mod 2 == 0: toSeq(1 .. maxLayer) else: toSeq(countdown(maxLayer - 1, 0))
    for li in rng:
      var keyed: seq[(float, int)]
      for i in layers[li]:
        let nb = if pass mod 2 == 0: pred[i] else: succ[i]
        var s = 0.0
        for j in nb: s += pos[j]
        keyed.add ((if nb.len > 0: s / nb.len.float else: pos[i]), i)
      keyed.sort(proc (a, b: (float, int)): int = cmp(a[0], b[0]))
      layers[li].setLen(0)
      for k, e in keyed:
        layers[li].add e[1]
        pos[e[1]] = k.float
  # coordonnées
  const gapMain = 90.0
  const gapCross = 28.0
  var main = 0.0
  var extent = 0.0
  var sizes: seq[float]
  for L in layers:
    var s = 0.0
    for i in L: s += (if horiz: c.nodes[i].h else: c.nodes[i].w) + gapCross
    sizes.add s
    extent = max(extent, s)
  for li, L in layers:
    var cross = (extent - sizes[li]) / 2
    var thick = 0.0
    for i in L:
      let n = c.nodes[i]
      if horiz:
        n.x = main
        n.y = cross
        cross += n.h + gapCross
        thick = max(thick, n.w)
      else:
        n.x = cross
        n.y = main
        cross += n.w + gapCross
        thick = max(thick, n.h)
    main += thick + gapMain
  # nœuds isolés : grille après les couches (ou seuls)
  if isolated.len > 0:
    let cols = max(1, int(ceil(sqrt(isolated.len.float * (if horiz: 1.6 else: 0.8)))))
    var colW = 0.0
    var rowH = 0.0
    for i in isolated:
      colW = max(colW, c.nodes[i].w)
      rowH = max(rowH, c.nodes[i].h)
    let x0 = if horiz: main else: 0.0
    let y0 = if horiz: 0.0 else: main
    for k, i in isolated:
      let n = c.nodes[i]
      n.x = x0 + (k mod cols).float * (colW + 40)
      n.y = y0 + (k div cols).float * (rowH + 30)
  c.needFit = true

# ------------------------------------------------------------------ dessin

proc textColorOn(bg: Color): Color =
  if 0.299 * bg.r.float + 0.587 * bg.g.float + 0.114 * bg.b.float > 160: rgb(20, 24, 40) else: rgb(255, 255, 255)

proc drawArrow(d: Drawing, tip, from0: (float, float), size: float, col: Color) =
  let ang = arctan2(tip[1] - from0[1], tip[0] - from0[0])
  let a1 = ang + 2.65
  let a2 = ang - 2.65
  d.fillPolygon([(tip[0], tip[1]), (tip[0] + cos(a1) * size, tip[1] + sin(a1) * size),
                 (tip[0] + cos(a2) * size, tip[1] + sin(a2) * size)], col)

method draw*(c: DiagramCanvas, d: Drawing, t: Theme) =
  let r = c.rect
  d.pushClip(r)
  let bg = if t.dark: rgb(28, 31, 38) else: rgb(246, 248, 252)
  d.fillRect(r, bg)
  # quadrillage léger
  let gcol = if t.dark: rgb(44, 48, 58) else: rgb(229, 233, 242)
  let step = 24.0 * c.zoom
  if step >= 8:
    var gx = r.x + floorMod(c.panX, step)
    while gx < r.x + r.w:
      var gy = r.y + floorMod(c.panY, step)
      while gy < r.y + r.h:
        d.fillRect(rect(gx, gy, 1.5, 1.5), gcol)
        gy += step
      gx += step
  for n in c.nodes:
    if not n.measured: c.measure(n, d)
  if c.needFit and c.nodes.len > 0: c.fit()
  if c.fontFiles.len == 0: c.fontFiles = t.fonts
  let z = c.zoom
  let showText = z >= 0.3
  template px(base: float): int = int(round(base * z))
  let fg = t.text
  # liens
  for l in c.links:
    let pts = c.linkPoints(l)
    if pts.len < 2: continue
    let sel = l.id == c.selLink and l.id.len > 0
    let col = if sel: t.accent elif l.color.a == 0: (if t.dark: rgb(140, 150, 175) else: rgb(120, 130, 155)) else: l.color
    let ep = max(1.0, (if l.width > 0: l.width else: 1.6) * z) + (if sel: 1.0 else: 0.0)
    var prev = c.toScreen(pts[0][0], pts[0][1])
    for i in 1 ..< pts.len:
      let p = c.toScreen(pts[i][0], pts[i][1])
      if not l.dashed or i mod 2 == 1: d.line(prev[0], prev[1], p[0], p[1], col, ep)
      prev = p
    if l.arrow:
      let tip = c.toScreen(pts[^1][0], pts[^1][1])
      let fr = c.toScreen(pts[^3][0], pts[^3][1])
      drawArrow(d, tip, fr, max(6.0, 9 * z), col)
    if l.label.len > 0 and showText:
      let m = c.toScreen(pts[10][0], pts[10][1])
      let tw = c.textW(d, l.label, px(11)) + 10 * z
      let th = 16 * z
      let lr = rect(m[0] - tw / 2, m[1] - th / 2, tw, th)
      d.fillRoundRect(lr, 4 * z, (if t.dark: rgb(40, 44, 54) else: rgb(255, 255, 255)))
      d.strokeRoundRect(lr, 4 * z, col, 1)
      c.drawT(d, l.label, lr, px(11), false, fg, alCenter)
  # nœuds
  for n in c.nodes:
    let (sx, sy) = c.toScreen(n.x, n.y)
    let nr = rect(sx, sy, n.w * z, n.h * z)
    if d.isClippedOut(nr): continue
    let sel = n.id == c.selected
    let head = if n.color.a == 0: t.accent else: n.color
    let body = if t.dark: rgb(38, 42, 52) else: rgb(255, 255, 255)
    d.shadow(nr, 6 * z, rgb(0, 0, 0, 40))
    if n.shape == "boite":
      d.fillRoundRect(nr, 8 * z, head)
      if showText:
        let tc = textColorOn(head)
        let hh = if n.subtitle.len > 0: nr.h - SubH * z else: nr.h
        c.drawT(d, n.title, rect(nr.x + PadX * z, nr.y, nr.w - 2 * PadX * z, hh), px(13), true, tc, alCenter)
        if n.subtitle.len > 0:
          c.drawT(d, n.subtitle, rect(nr.x + PadX * z, nr.y + hh - 5 * z, nr.w - 2 * PadX * z, SubH * z), px(11), false, tc.withAlpha(210), alCenter)
    else:
      d.fillRoundRect(nr, 7 * z, body)
      let hr = rect(nr.x, nr.y, nr.w, HeadH * z)
      d.fillRoundRect(hr, 7 * z, head)
      d.fillRect(rect(hr.x, hr.y + hr.h - 7 * z, hr.w, 7 * z), head)
      if showText:
        let tc = textColorOn(head)
        var tw = nr.w - 2 * PadX * z
        if n.badge.len > 0:
          let bw = c.textW(d, n.badge, px(11)) + 10 * z
          let br = rect(hr.x + hr.w - bw - 6 * z, hr.y + (hr.h - 16 * z) / 2, bw, 16 * z)
          d.fillRoundRect(br, 8 * z, rgb(255, 255, 255, 60))
          c.drawT(d, n.badge, br, px(11), false, tc, alCenter)
          tw -= bw + 6 * z
        c.drawT(d, n.title, rect(hr.x + PadX * z, hr.y, tw, hr.h), px(13), true, tc)
      var yy = nr.y + HeadH * z
      if n.subtitle.len > 0:
        if showText:
          c.drawT(d, n.subtitle, rect(nr.x + PadX * z, yy, nr.w - 2 * PadX * z, SubH * z), px(11), false, t.textSecondary)
        yy += SubH * z
      if n.gauge >= 0:
        let gw = (nr.w - 2 * PadX * z) * clamp(n.gauge, 0.0, 1.0)
        d.fillRect(rect(nr.x + PadX * z, nr.y + HeadH * z - 3 * z, gw, 3 * z), rgb(255, 255, 255, 190))
      for i, row in n.rows:
        let rr = rect(nr.x, yy + i.float * RowH * z, nr.w, RowH * z)
        if sel and c.selRow == i + 1: d.fillRect(rr, t.accent.withAlpha(50))
        if showText:
          var x = rr.x + PadX * z
          if row.mark.len > 0:
            let mc = if row.mark == "PK": rgb(245, 184, 61) elif row.mark == "FK": rgb(96, 165, 250) else: rgb(160, 170, 190)
            let mr = rect(x, rr.y + (rr.h - 14 * z) / 2, 22 * z, 14 * z)
            d.fillRoundRect(mr, 3 * z, mc)
            c.drawT(d, row.mark, mr, px(9), true, rgb(20, 24, 40), alCenter)
            x += 26 * z
          let dw = if row.detail.len > 0: c.textW(d, row.detail, px(11)) + 6 * z else: 0.0
          c.drawT(d, row.text, rect(x, rr.y, rr.x + rr.w - x - dw - PadX * z, rr.h), px(12), false, fg)
          if dw > 0: c.drawT(d, row.detail, rect(rr.x + rr.w - dw - PadX * z, rr.y, dw, rr.h), px(11), false, t.textSecondary, alRight)
        if i > 0: d.fillRect(rect(rr.x + 6, rr.y, rr.w - 12, 1), (if t.dark: rgb(52, 56, 68) else: rgb(236, 239, 245)))
    d.strokeRoundRect(nr, (if n.shape == "boite": 8 else: 7) * z, (if sel: t.accent else: (if t.dark: rgb(70, 76, 92) else: rgb(206, 213, 228))), (if sel: 2.0 else: 1.0))
    # pastilles de liaison (mode modifiable, nœud sélectionné ou survolé)
    if c.editable and (sel or c.hoverPort.id == n.id):
      for row in 0 .. (if n.shape == "boite": 0 else: n.rows.len):
        let (px, py) = c.toScreen(n.x + n.w, n.rowCenterY(row))
        let hot = c.hoverPort.id == n.id and c.hoverPort.row == row
        d.fillCircle(px, py, PortR * (if hot: 1.5 else: 1.0), (if hot: t.accent else: rgb(150, 160, 185)))
  # lien en cours de création
  if c.drag == ddLink:
    let a = c.findNode(c.linkFrom)
    if a != nil:
      let (ax, ay) = c.toScreen(a.x + a.w, a.rowCenterY(c.linkFromRow))
      d.line(ax, ay, c.curX, c.curY, t.accent, 2)
      d.fillCircle(c.curX, c.curY, 4, t.accent)
  # zoom
  if c.nodes.len > 0:
    let zt = $int(round(z * 100)) & " %"
    let zw = d.textWidth(zt) + 12
    let zr = rect(r.x + r.w - zw - 8, r.y + r.h - d.textHeight - 12, zw, d.textHeight + 4)
    d.fillRoundRect(zr, 4, (if t.dark: rgb(40, 44, 54, 220) else: rgb(255, 255, 255, 220)))
    d.textIn(zr, zt, t.textSecondary, alCenter)
  d.popClip()

# ------------------------------------------------------------------ souris et clavier

proc select(c: DiagramCanvas, id: string, row = 0, link = "") =
  c.selected = id
  c.selRow = row
  c.selLink = link
  emit(c, evSelection, index = row, text = (if link.len > 0: "lien:" & link else: id))

method onMouse*(c: DiagramCanvas, e: MouseEvent) =
  let (lx, ly) = c.toLogical(e.x, e.y)
  case e.action
  of maPress:
    c.startX = e.x
    c.startY = e.y
    c.moved = false
    if e.button != mbLeft: return
    let p = c.portAt(lx, ly)
    if p.id.len > 0:
      c.drag = ddLink
      c.linkFrom = p.id
      c.linkFromRow = p.row
      c.curX = e.x
      c.curY = e.y
      markDirty(c)
      return
    let n = c.nodeAt(lx, ly)
    if n != nil:
      let row = n.rowAt(ly)
      if n.id != c.selected or row != c.selRow or c.selLink.len > 0: c.select(n.id, row)
      # au premier plan
      let k = c.nodes.find(n)
      if k >= 0 and k != c.nodes.high:
        c.nodes.delete(k)
        c.nodes.add n
      if c.editable:
        c.drag = ddMove
        c.dragId = n.id
        c.origX = n.x
        c.origY = n.y
      else:
        c.drag = ddPan
        c.origX = c.panX
        c.origY = c.panY
      markDirty(c)
      return
    let l = c.linkAt(lx, ly)
    if l.len > 0:
      c.select("", 0, l)
      markDirty(c)
      return
    if c.selected.len > 0 or c.selLink.len > 0: c.select("")
    c.drag = ddPan
    c.origX = c.panX
    c.origY = c.panY
    markDirty(c)
  of maMove:
    case c.drag
    of ddMove:
      let n = c.findNode(c.dragId)
      if n == nil: return
      if abs(e.x - c.startX) + abs(e.y - c.startY) > 2: c.moved = true
      n.x = c.origX + (e.x - c.startX) / c.zoom
      n.y = c.origY + (e.y - c.startY) / c.zoom
      markDirty(c)
    of ddPan:
      c.panX = c.origX + (e.x - c.startX)
      c.panY = c.origY + (e.y - c.startY)
      markDirty(c)
    of ddLink:
      c.curX = e.x
      c.curY = e.y
      let n = c.nodeAt(lx, ly)
      c.hoverPort = if n != nil: (n.id, n.rowAt(ly)) else: ("", 0)
      markDirty(c)
    of ddNone:
      let p = c.portAt(lx, ly)
      var hp = p
      if p.id.len == 0:
        let n = c.nodeAt(lx, ly)
        if n != nil: hp = (n.id, -1)
      if hp != c.hoverPort:
        c.hoverPort = hp
        markDirty(c)
  of maRelease:
    case c.drag
    of ddMove:
      if c.moved:
        let n = c.findNode(c.dragId)
        if n != nil:
          n.x = round(n.x / 4) * 4
          n.y = round(n.y / 4) * 4
          c.lastAction = (action: "deplace", id: n.id, src: "", dst: "", srcRow: 0, dstRow: 0)
          emit(c, evChange, text = "deplace")
    of ddLink:
      let n = c.nodeAt(lx, ly)
      if n != nil and n.id != c.linkFrom:
        c.lastAction = (action: "lien", id: "", src: c.linkFrom, dst: n.id, srcRow: c.linkFromRow, dstRow: n.rowAt(ly))
        emit(c, evChange, text = "lien")
    else: discard
    c.drag = ddNone
    c.hoverPort = ("", 0)
    markDirty(c)

method onWheel*(c: DiagramCanvas, dx, dy: float): bool =
  let f = if dy > 0: 1.15 elif dy < 0: 1 / 1.15 else: 1.0
  if f == 1.0: return false
  let nz = clamp(c.zoom * f, 0.15, 3.0)
  # zoom autour du centre du contrôle
  let cx = c.rect.w / 2
  let cy = c.rect.h / 2
  c.panX = cx - (cx - c.panX) * nz / c.zoom
  c.panY = cy - (cy - c.panY) * nz / c.zoom
  c.zoom = nz
  markDirty(c)
  true

method onKey*(c: DiagramCanvas, e: KeyEvent): bool =
  case e.key
  of SDLK_DELETE, SDLK_BACKSPACE:
    if c.selected.len > 0 or c.selLink.len > 0:
      c.lastAction = (action: "supprimer", id: (if c.selLink.len > 0: c.selLink else: c.selected),
                      src: "", dst: "", srcRow: 0, dstRow: 0)
      emit(c, evChange, text = "supprimer")
      return true
  of SDLK_ESCAPE:
    c.select("")
    markDirty(c)
    return true
  else: discard
  false

# ------------------------------------------------------------------ modèle

proc upsertNode*(c: DiagramCanvas, id: string): DiaNode =
  result = c.findNode(id)
  if result == nil:
    result = DiaNode(id: id, title: id, shape: "table", gauge: -1, x: Inf, y: Inf)
    c.nodes.add result
  result.measured = false

proc removeNode*(c: DiagramCanvas, id: string): bool =
  for i, n in c.nodes:
    if n.id == id:
      c.nodes.delete(i)
      var k = 0
      while k < c.links.len:
        if c.links[k].src == id or c.links[k].dst == id: c.links.delete(k) else: inc k
      if c.selected == id: c.selected = ""
      return true
  for i, l in c.links:
    if l.id == id:
      c.links.delete(i)
      if c.selLink == id: c.selLink = ""
      return true

proc upsertLink*(c: DiagramCanvas, l: DiaLink) =
  for x in c.links.mitems:
    if x.id == l.id:
      x = l
      return
  c.links.add l

proc placeNew*(c: DiagramCanvas) =
  ## Nœuds sans position (ajoutés sans x/y) : à droite de l'existant, en colonne.
  var maxX = 0.0
  var any = false
  for n in c.nodes:
    if n.x != Inf:
      maxX = max(maxX, n.x + max(n.w, 120))
      any = true
  var y = 0.0
  for n in c.nodes:
    if n.x == Inf or n.y == Inf:
      n.estimate()
      n.x = if any: maxX + 60 else: 0.0
      n.y = y
      y += n.h + 24
