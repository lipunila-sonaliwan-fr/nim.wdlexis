# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - vue « blueprint » du code Lexis+ (à la manière d'Unreal).
#
# * BpCanvas : le graphe (bpmodel) dessiné sur une grille ; nœuds déplaçables,
#   broches à relier par glisser, sélection au lasso, zoom (Ctrl+molette) et
#   déplacement (clic droit ou milieu glissé, molette), menu contextuel,
#   annulation (Ctrl+Z / Ctrl+Y), suppression (Suppr), duplication (Ctrl+D).
# * BpPalette : toutes les fonctions (intégrées, paquets, méthodes), les
#   instructions, les blocs et les opérateurs, par catégorie, avec recherche ;
#   glisser un élément sur le graphe crée le nœud ; un clic l'ajoute après le
#   nœud sélectionné (ou sur sa première entrée libre pour une expression).
# * Détails : propriétés du nœud sélectionné (nom, cible, valeurs saisies sur
#   les broches, mode instruction / expression...).
# * DocHost : superpose la vue à l'éditeur de code quand l'onglet actif est une
#   vue blueprint (pastille bleue) ; la barre d'onglets reste celle de l'éditeur.
#
# Chaque modification du graphe régénère le code du document représenté
# (bpmodel.generate : seules les instructions touchées sont réécrites) ; une
# modification du code dans son onglet est reprise à l'activation de la vue.

import std/[strutils, tables, sets, math, os, algorithm, unicode, locks]
import ../sdl3
import ../wdgui
import bpmodel, codeeditor, langdocs, compat
export bpmodel

const
  BaseFont = 13.0
  PaletteW = 236.0
  DetailsW = 290.0

type
  BpDoc* = ref object
    uid*, srcUid*: int
    g*: Graph
    synced*: int                 # version du code représentée par le graphe
    vx*, vy*, zoom*: float       # coin haut-gauche (monde) et zoom
    sel*: HashSet[int]
    undo, redo: seq[Graph]
    laidOut*: bool
    fitted*: bool
    externals*: Table[string, tuple[path: string, line: int]]   # procédures appelées définies dans un autre fichier
    pendingLine*: int            # ligne à montrer dès la première mise en page (-1 : aucune)

  PaletteItem* = object
    header*: bool
    category*: string
    label*: string
    kind*: NodeKind
    title*, text*, mode*: string
    stmt*: bool
    brace*: bool
    doc*: string

  DragMode = enum dmNone, dmMove, dmPan, dmLink, dmBand

  BpCanvas* = ref object of Control
    docs*: Table[int, BpDoc]
    cur*: int
    editor*: CodeEditor
    drag: DragMode
    pressX, pressY, mx, my: float
    dragMoved, mutated: bool
    linkNode, linkPid: int
    linkDir: PinDir
    linkKind: PinKind
    hoverNode, hoverPinNode, hoverPin: int
    dropping*: bool              # glisser depuis la palette en cours
    dropItem*: PaletteItem
    ctxNode, ctxPin: int
    ctxX, ctxY: float
    ctxItems: seq[string]
    fontPath: string
    when defined(sdlttf):
      fonts: Table[int, TTF_Font]
      texCache: Table[string, tuple[tex: SDL_Texture, w, h: float]]
    widths: Table[string, float]
    fits: Table[string, string]
    extIcons: Table[int, seq[string]]   # nœud -> procédures d'autres fichiers (icône fichier), dernier rendu
    moveSet: seq[int]
    showCalls*: bool

  BpPalette* = ref object of Control
    canvas*: BpCanvas
    items: seq[PaletteItem]
    filter*: string
    expanded*: HashSet[string]
    scroll: float
    hoverIdx, pressIdx: int
    pressX, pressY: float
    dragging: bool
    projectProcs*: seq[string]
    built: bool

  DocHost* = ref object of Container
    editor*: CodeEditor
    pane*: Container
    canvas*: BpCanvas
    lastBp: int

var
  bpCodeChanged*: proc (srcUid: int) {.nimcall, gcsafe.}          # code régénéré (analyse, titre)
  bpGotoLine*: proc (srcUid, line: int) {.nimcall, gcsafe.}       # « voir dans le code »
  bpStatus*: proc (msg: string) {.nimcall, gcsafe.}                # barre d'état de l'atelier
  bpCommand*: proc (cmd: string) {.nimcall, gcsafe.}               # raccourcis (cmd:save, cmd:run...)
  bpLocate*: proc (name: string): tuple[path: string, line: int] {.nimcall, gcsafe.}  # définition dans le projet
  bpOpenEntity*: proc (name: string) {.nimcall, gcsafe.}           # ouvrir la procédure (autre fichier) en blueprint
  hostId, canvasId, paletteId, searchId, detailsId, editorId, infoId: ControlId
  toolIds: seq[tuple[id: ControlId, cmd: string]]
  detailRows: seq[tuple[id: ControlId, action: string]]
  multilineIds: seq[ControlId]
  pendingValues: Table[string, string]
  detailsNode: int = -1

var detailsLock: Lock
initLock(detailsLock)

proc status(msg: string) =
  if bpStatus != nil:
    {.cast(gcsafe).}: bpStatus(msg)

# ---------------------------------------------------------------------------
# signatures (pour les broches des appels)

proc apiSignature(name: string, isMethod: bool): string {.nimcall, gcsafe.} =
  var owner = ""
  var short = name
  let dot = name.rfind('.')
  if dot > 0 and not isMethod:
    owner = name[0 ..< dot]
    short = name[dot + 1 .. ^1]
  var es = apiLookup(short, isMethod, owner)
  if es.len == 0 and owner.len > 0: es = apiLookup(short, isMethod)
  if es.len == 0 and owner.len == 0 and not isMethod:
    for e in apiLookup(short, false):
      if e.owner.len == 0: es.add e
  if es.len > 0: es[0].signature else: ""

bpSignatureOf = apiSignature

proc summaryFor(title: string, isMethod: bool): string =
  ## Fiche courte d'une fonction (paquet pris en compte : « interface.executer »).
  let dot = title.rfind('.')
  if dot > 0 and not isMethod: apiSummary(title[dot + 1 .. ^1], false, title[0 ..< dot])
  else: apiSummary(title, isMethod)

# ---------------------------------------------------------------------------
# couleurs

type BpColors = object
  bg, gridMinor, gridMajor, body, border, text, textDim, boxBg, boxBorder, boxText,
    select, band, shadow: Color

proc colorsOf(t: Theme): BpColors =
  if t.dark:
    BpColors(bg: hex"#1C1D20", gridMinor: hex"#24252A", gridMajor: hex"#2E3036", body: hex"#2A2C31F2",
             border: hex"#0E0F11", text: hex"#E8EAED", textDim: hex"#9AA0A8", boxBg: hex"#18191C",
             boxBorder: hex"#454950", boxText: hex"#D6D8DC", select: hex"#F5A524",
             band: hex"#F5A52433", shadow: hex"#00000070")
  else:
    BpColors(bg: hex"#ECEEF2", gridMinor: hex"#E2E5EA", gridMajor: hex"#D4D8DF", body: hex"#FFFFFFF5",
             border: hex"#B9BEC7", text: hex"#1E2126", textDim: hex"#6B717B", boxBg: hex"#F3F4F6",
             boxBorder: hex"#C9CDD4", boxText: hex"#30343A", select: hex"#E8890C",
             band: hex"#E8890C2E", shadow: hex"#0000002A")

proc headerColor*(n: Node): Color =
  case n.kind
  of nkEntry: hex"#9B2C2C"
  of nkComment: hex"#6E6526"
  of nkRaw: hex"#6B44A8"
  of nkPrint: hex"#2F6DB5"
  of nkAssign, nkLocal: hex"#1F7F7A"
  of nkIf, nkCase, nkWhile, nkFor, nkForEach, nkScan, nkTry, nkBreak, nkContinue: hex"#5A606B"
  of nkReturn: hex"#8A3A3A"
  of nkCall, nkMethod: (if n.stmt: hex"#2F6DB5" else: hex"#2F8150")
  of nkVar: hex"#1F7F7A"
  of nkOp, nkUnary, nkIndex, nkMember: hex"#2F8150"
  of nkExpr: hex"#5E6068"

proc kindColorOf(it: PaletteItem): Color =
  var n = Node(kind: it.kind, stmt: it.stmt)
  headerColor(n)

proc literalColor(s: string): Color =
  let t = s.strip
  if t.len == 0: hex"#5DB7E8"
  elif t[0] in {'"', '\''} or t.startsWith("[["): hex"#E35EB8"
  elif t[0] in Digits or (t[0] == '-' and t.len > 1 and t[1] in Digits): hex"#7AD36F"
  elif t.toLowerAscii in ["vrai", "faux", ".v.", ".f."]: hex"#D35454"
  elif t[0] == '{': hex"#E0A23A"
  elif t[0] == '@': hex"#B48CF2"
  else: hex"#5DB7E8"

proc pinColor(g: Graph, n: Node, p: Pin): Color =
  if p.kind == pkExec: return hex"#F2F2F2"
  if p.dir == pdIn:
    if not g.isLinkedIn(n, p.pid): return literalColor(p.default)
    return hex"#5DB7E8"
  if n.kind == nkExpr: return literalColor(n.text)
  if n.kind == nkOp:
    case n.title.toLowerAscii
    of "=", "==", "<>", "!=", "#", "<", ">", "<=", ">=", "$", "et", "ou": return hex"#D35454"
    of "..": return hex"#E35EB8"
    else: return hex"#7AD36F"
  if n.kind == nkUnary and n.title.toLowerAscii == "non": return hex"#D35454"
  hex"#5DB7E8"

# ---------------------------------------------------------------------------
# canevas : polices et texte

proc newBpCanvas*(): BpCanvas =
  result = BpCanvas(cur: -1, hoverNode: -1, hoverPin: -1, hoverPinNode: -1, ctxNode: -1, ctxPin: -1,
                    showCalls: true)
  initControl(result)
  result.focusable = true

proc curDoc*(c: BpCanvas): BpDoc = c.docs.getOrDefault(c.cur)

when defined(sdlttf):
  proc fontFor(c: BpCanvas, t: Theme, px: int): TTF_Font =
    if c.fontPath.len == 0:
      for p in t.fonts:
        if fileExists(p):
          c.fontPath = p
          break
      if c.fontPath.len == 0: c.fontPath = "-"
    if c.fontPath == "-": return nil
    result = c.fonts.getOrDefault(px)
    if result == nil:
      result = TTF_OpenFont(c.fontPath.cstring, px.cfloat)
      c.fonts[px] = result

proc measureBase(c: BpCanvas, s: string): float =
  if s.len == 0: return 0
  if s in c.widths: return c.widths[s]
  result = estimateWidth(s)
  when defined(sdlttf):
    let f = c.fonts.getOrDefault(int(BaseFont))
    if f != nil:
      var w, h: cint
      if TTF_GetStringSize(f, s.cstring, csize_t(s.len), addr w, addr h): result = float(w)
      else: return
    else: return          # police pas encore chargée : mesure approchée, non mémorisée.
  if c.widths.len > 20000: c.widths.clear()
  c.widths[s] = result

proc measurer(c: BpCanvas): TextMeasure =
  let cc = c
  result = proc (s: string): float {.closure, gcsafe.} =
    {.cast(gcsafe).}: cc.measureBase(s)

const FontSteps = [8, 10, 13, 16, 20, 26, 34]

proc fontStep(px: int): int =
  ## Taille de police réellement ouverte (peu de tailles : peu de fichiers ouverts) ;
  ## le texte est ensuite mis à l'échelle demandée.
  for s in FontSteps:
    if s >= px: return s
  FontSteps[^1]

proc txt(c: BpCanvas, d: Drawing, t: Theme, x, y: float, s: string, col: Color, px: int) =
  if s.len == 0 or col.a == 0: return
  when defined(sdlttf):
    let q = fontStep(px)
    let f = c.fontFor(t, q)
    if f != nil:
      let key = $q & "|" & s
      var e = c.texCache.getOrDefault(key)
      if e.tex == nil:
        if c.texCache.len > 5000:
          for v in c.texCache.values: SDL_DestroyTexture(v.tex)
          c.texCache.clear()
        let surf = TTF_RenderText_Blended(f, s.cstring, csize_t(s.len), SDL_Color(r: 255, g: 255, b: 255, a: 255))
        if surf == nil: return
        let tex = SDL_CreateTextureFromSurface(d.ren, surf)
        SDL_DestroySurface(surf)
        if tex == nil: return
        var w, h: cfloat
        discard SDL_GetTextureSize(tex, addr w, addr h)
        e = (tex, float(w), float(h))
        c.texCache[key] = e
      discard SDL_SetTextureColorMod(e.tex, col.r, col.g, col.b)
      discard SDL_SetTextureAlphaMod(e.tex, col.a)
      let k = float(px) / float(q)
      d.drawTexture(e.tex, rect(round(x), round(y), e.w * k, e.h * k))
      return
  d.text(x, y, s, col)

proc fit(c: BpCanvas, s: string, maxW: float): string =
  ## Texte raccourci (« … ») pour tenir dans maxW (unités du monde).
  if c.measureBase(s) <= maxW: return s
  let key = $int(maxW) & "|" & s
  if key in c.fits: return c.fits[key]
  # recherche dichotomique du plus long préfixe qui tient.
  var rs = toRunes(s)
  var lo = 0
  var hi = rs.len
  while lo < hi:
    let mid = (lo + hi + 1) div 2
    if c.measureBase($rs[0 ..< mid] & "…") <= maxW: lo = mid
    else: hi = mid - 1
  result = $rs[0 ..< lo] & "…"
  if c.fits.len > 8000: c.fits.clear()
  c.fits[key] = result

# ---------------------------------------------------------------------------
# repères monde <-> écran

proc toSx(c: BpCanvas, doc: BpDoc, x: float): float = c.rect.x + (x - doc.vx) * doc.zoom
proc toSy(c: BpCanvas, doc: BpDoc, y: float): float = c.rect.y + (y - doc.vy) * doc.zoom
proc toWx(c: BpCanvas, doc: BpDoc, x: float): float = doc.vx + (x - c.rect.x) / doc.zoom
proc toWy(c: BpCanvas, doc: BpDoc, y: float): float = doc.vy + (y - c.rect.y) / doc.zoom

proc screenRect(c: BpCanvas, doc: BpDoc, n: Node): Rect =
  rect(c.toSx(doc, n.x), c.toSy(doc, n.y), n.w * doc.zoom, n.h * doc.zoom)

proc pinScreen(c: BpCanvas, doc: BpDoc, n: Node, idx: int): tuple[x, y: float] =
  let p = n.pinPos(idx)
  (c.toSx(doc, p.x), c.toSy(doc, p.y))

proc visibleBounds(g: Graph): tuple[x, y, w, h: float] =
  var x0, y0 = 1e18
  var x1, y1 = -1e18
  for n in g.nodes:
    if g.isHidden(n): continue
    x0 = min(x0, n.x)
    y0 = min(y0, n.y)
    x1 = max(x1, n.x + n.w)
    y1 = max(y1, n.y + n.h + (if n.folded: 24.0 else: 0.0))
  if x1 < x0: return (0.0, 0.0, 400.0, 300.0)
  (x0, y0, x1 - x0, y1 - y0)

proc fitView*(c: BpCanvas, doc: BpDoc, minZoom = 0.2) =
  ## Ajuste la vue au graphe (sans descendre sous minZoom : le début du graphe reste lisible).
  let b = doc.g.visibleBounds
  let w = max(200.0, c.rect.w)
  let h = max(200.0, c.rect.h)
  doc.zoom = clamp(min((w - 60) / max(1.0, b.w), (h - 60) / max(1.0, b.h)), minZoom, 1.0)
  doc.vx = b.x - 30 / doc.zoom
  doc.vy = b.y - 30 / doc.zoom

proc zoomAt(c: BpCanvas, doc: BpDoc, factor, sx, sy: float) =
  let wx = c.toWx(doc, sx)
  let wy = c.toWy(doc, sy)
  doc.zoom = clamp(doc.zoom * factor, 0.15, 2.5)
  doc.vx = wx - (sx - c.rect.x) / doc.zoom
  doc.vy = wy - (sy - c.rect.y) / doc.zoom

proc toggleFold*(doc: BpDoc, e: Node) =
  ## Plie ou déplie le contenu d'une entrée ; les entrées situées dessous remontent
  ## (ou redescendent) de la hauteur du contenu.
  let g = doc.g
  let owned = g.reachableFrom(e.id)
  var bottom = e.y + e.h
  for id in owned:
    let n = g.node(id)
    if n != nil: bottom = max(bottom, n.y + n.h)
  let delta = bottom - (e.y + e.h)
  e.folded = not e.folded
  if e.folded:
    var keep: HashSet[int]
    for id in doc.sel:
      let n = g.node(id)
      if n != nil and not g.isHidden(n): keep.incl id
    doc.sel = keep
  if delta <= 1: return
  let shift = if e.folded: -delta else: delta
  let own = g.owners()
  for n in g.nodes:
    let o = own.getOrDefault(n.id, -1)
    if o == e.id: continue
    let oe = g.node(o)
    let refY = if oe != nil: oe.y else: n.y
    if refY > e.y + 1: n.y += shift

proc foldAll*(doc: BpDoc, fold: bool) =
  var es: seq[Node]
  for id in doc.g.entries:
    let e = doc.g.node(id)
    if e != nil and e.folded != fold: es.add e
  es.sort(proc (a, b: Node): int = cmp(a.y, b.y))
  for e in es: doc.toggleFold(e)

proc focusOnNode*(c: BpCanvas, doc: BpDoc, n: Node) =
  doc.vx = n.x + n.w / 2 - (c.rect.w / 2) / doc.zoom
  doc.vy = n.y + n.h / 2 - (c.rect.h / 2) / doc.zoom

proc showLineNow(c: BpCanvas, doc: BpDoc, line: int) =
  var best: Node = nil
  for n in doc.g.nodes:
    if n.line >= 0 and n.line <= line and (n.isExecNode or n.kind == nkEntry):
      if best == nil or n.line > best.line or (n.line == best.line and n.kind == nkEntry): best = n
  if best == nil: return
  if doc.g.isHidden(best):
    let o = doc.g.node(doc.g.ownerOf(best.id))
    if o != nil: doc.toggleFold(o)
  doc.sel = [best.id].toHashSet
  if best.kind == nkEntry:
    # procédure : son début en haut à gauche de la vue.
    doc.vx = best.x - 40 / doc.zoom
    doc.vy = best.y - 40 / doc.zoom
  else: c.focusOnNode(doc, best)

proc ensureLayout(c: BpCanvas, doc: BpDoc) =
  let m = c.measurer
  if not doc.laidOut:
    doc.g.layout(m)
    doc.laidOut = true
  if not doc.fitted and c.rect.w > 50:
    c.fitView(doc, 0.7)
    doc.fitted = true
    if doc.pendingLine >= 0:
      c.showLineNow(doc, doc.pendingLine)
      doc.pendingLine = -1
      emit(c, evSelection, text = "bp:sel")

# ---------------------------------------------------------------------------
# canevas : dessin

proc bezier(d: Drawing, x1, y1, x2, y2: float, col: Color, w: float) =
  let dx = max(36.0, abs(x2 - x1) * 0.5)
  let c1x = x1 + dx
  let c2x = x2 - dx
  let length = abs(x2 - x1) + abs(y2 - y1)
  let steps = clamp(int(length / 14), 6, 28)
  var px = x1
  var py = y1
  for k in 1 .. steps:
    let t = float(k) / float(steps)
    let u = 1 - t
    let nx = u*u*u*x1 + 3*u*u*t*c1x + 3*u*t*t*c2x + t*t*t*x2
    let ny = u*u*u*y1 + 3*u*u*t*y1 + 3*u*t*t*y2 + t*t*t*y2
    d.line(px, py, nx, ny, col, w)
    px = nx
    py = ny

proc drawExecPin(d: Drawing, x, y, z: float, col: Color, filled: bool) =
  let s = 5.5 * z
  let pts = [(x - s, y - s), (x + s * 0.2, y - s), (x + s, y), (x + s * 0.2, y + s), (x - s, y + s)]
  if filled: d.fillPolygon(pts, col)
  else:
    for i in 0 ..< pts.len:
      let a = pts[i]
      let b = pts[(i + 1) mod pts.len]
      d.line(a[0], a[1], b[0], b[1], col, max(1.0, 1.4 * z))

proc drawDataPin(d: Drawing, x, y, z: float, col: Color, filled: bool) =
  let r = 5.0 * z
  if filled: d.fillCircle(x, y, r, col)
  else:
    d.strokeCircle(x, y, r, col, max(1.0, 1.5 * z))
    d.fillCircle(x, y, r * 0.35, col.withAlpha(120))

proc boxRect(c: BpCanvas, doc: BpDoc, n: Node, idx: int): Rect =
  ## Case de saisie d'une entrée de données non reliée (écran).
  let p = c.pinScreen(doc, n, idx)
  let z = doc.zoom
  let label = n.pinLabel(n.pins[idx])
  let lw = c.measureBase(label)
  let bw = boxWidth(c.measurer, n.pins[idx].default)
  rect(p.x + (12 + lw + (if label.len > 0: 6 else: 0)) * z, p.y - 8 * z, bw * z, 16 * z)

proc drawNode(c: BpCanvas, d: Drawing, t: Theme, col: BpColors, doc: BpDoc, n: Node) =
  let g = doc.g
  let z = doc.zoom
  let r = c.screenRect(doc, n)
  let selected = n.id in doc.sel
  let hc = headerColor(n)
  let px = clamp(int(round(BaseFont * z)), 5, 30)
  let small = clamp(int(round(11.0 * z)), 5, 26)
  let showText = z >= 0.32
  let radius = 6 * z
  if g.nodes.len < 600: d.shadow(r, radius + 2, col.shadow)
  if n.isCompact:
    let rr = if n.kind in {nkVar, nkExpr}: r.h / 2 else: 8 * z
    d.fillRoundRect(r, rr, mix(hc, col.body, 0.55))
    d.strokeRoundRect(r, rr, (if selected: col.select else: hc), (if selected: 2.0 else: max(1.0, 1.2 * z)))
    if showText:
      let label = case n.kind
        of nkVar, nkExpr, nkMember: c.fit(n.headerTitle, max(10.0, n.w - 30))
        else: n.headerTitle
      let ins = n.inputs
      var lw = 0.0
      for i in ins:
        let p = n.pins[i]
        var w = 16.0 + c.measureBase(n.pinLabel(p))
        if p.kind == pkData and not g.isLinkedIn(n, p.pid): w += 8 + boxWidth(c.measurer, p.default)
        lw = max(lw, w)
      let tw = c.measureBase(label)
      let big = if n.kind in {nkOp, nkUnary}: clamp(int(round(17.0 * z)), 6, 36) else: px
      let x0 = if ins.len == 0: r.x + 12 * z else: r.x + lw * z + 4 * z
      let x1 = r.x + r.w - 16 * z
      let tx = x0 + max(0.0, (x1 - x0 - tw * z * (float(big) / float(px))) / 2)
      c.txt(d, t, tx, r.y + (r.h - float(big) * 1.25) / 2, label, col.text, big)
  else:
    let hh = n.headH * z
    d.fillRoundRect(r, radius, col.body)
    d.fillRoundRect(rect(r.x, r.y, r.w, hh), radius, hc)
    d.fillRect(rect(r.x, r.y + hh - radius, r.w, radius), hc)
    d.fillRect(rect(r.x + 1, r.y + 1, r.w - 2, max(1.0, hh * 0.42)), hex"#FFFFFF14")
    # pictogramme
    let ix = r.x + 11 * z
    let iy = r.y + 13 * z
    case n.kind
    of nkEntry:
      d.fillPolygon([(ix - 4 * z, iy - 5 * z), (ix + 5 * z, iy), (ix - 4 * z, iy + 5 * z)], hex"#FFFFFF")
    of nkIf, nkCase, nkWhile, nkFor, nkForEach, nkScan, nkTry:
      d.fillPolygon([(ix, iy - 5 * z), (ix + 5 * z, iy), (ix, iy + 5 * z), (ix - 5 * z, iy)], hex"#FFFFFFD0")
    of nkComment:
      d.fillRect(rect(ix - 4 * z, iy - 4 * z, 8 * z, 2 * z), hex"#FFFFFFC0")
      d.fillRect(rect(ix - 4 * z, iy - 1 * z, 8 * z, 2 * z), hex"#FFFFFFC0")
      d.fillRect(rect(ix - 4 * z, iy + 2 * z, 5 * z, 2 * z), hex"#FFFFFFC0")
    of nkRaw:
      d.strokeRoundRect(rect(ix - 5 * z, iy - 4 * z, 10 * z, 8 * z), 2 * z, hex"#FFFFFFC0", max(1.0, z))
    else:
      d.fillCircle(ix, iy, 4 * z, hex"#FFFFFFC0")
    if showText:
      let room = if n.kind == nkEntry: n.w - 74 elif n.id in c.extIcons: n.w - 50 else: n.w - 30
      c.txt(d, t, r.x + 21 * z, r.y + (HeadH * z - float(px) * 1.25) / 2, c.fit(n.headerTitle, room),
            hex"#FFFFFF", px)
      let sub = n.headerSub
      if sub.len > 0:
        c.txt(d, t, r.x + 21 * z, r.y + (HeadH - 3) * z, c.fit(sub, n.w - 30), hex"#FFFFFFB0", small)
    # texte du commentaire / code
    let body = n.bodyLines
    if body.len > 0 and showText:
      let rows = max(n.inputs.len, n.outputs.len)
      var y = r.y + (n.headH + float(rows) * RowH + 4) * z
      d.fillRoundRect(rect(r.x + 6 * z, y - 2 * z, r.w - 12 * z, (float(body.len) * BodyLineH + 6) * z), 4 * z,
                      col.boxBg)
      for l in body:
        let cc = if n.kind != nkComment: col.boxText elif t.dark: hex"#E8D98A" else: hex"#6B5A08"
        c.txt(d, t, r.x + 12 * z, y, c.fit(l, n.w - 24), cc, small)
        y += BodyLineH * z
    d.strokeRoundRect(r, radius, (if selected: col.select else: col.border), (if selected: 2.0 else: 1.0))
  # broches
  for i, p in n.pins:
    let pp = c.pinScreen(doc, n, i)
    let linked = if p.dir == pdIn: g.isLinkedIn(n, p.pid) else: g.linkFrom(n.id, p.pid) >= 0
    let pc = g.pinColor(n, p)
    if n.id == c.hoverPinNode and p.pid == c.hoverPin:
      d.fillCircle(pp.x, pp.y, 9 * z, pc.withAlpha(60))
    if p.kind == pkExec: drawExecPin(d, pp.x, pp.y, z, pc, linked)
    else: drawDataPin(d, pp.x, pp.y, z, pc, linked)
    if not showText: continue
    let label = n.pinLabel(p)
    if p.dir == pdIn:
      if label.len > 0 and not n.isCompact:
        c.txt(d, t, pp.x + 12 * z, pp.y - float(small) * 0.65, label, (if p.optional: col.textDim else: col.text), small)
      if p.kind == pkData and not linked:
        let b = c.boxRect(doc, n, i)
        let br = if n.isCompact: rect(pp.x + 12 * z, b.y, b.w, b.h) else: b
        d.fillRoundRect(br, 3 * z, col.boxBg)
        d.strokeRoundRect(br, 3 * z, col.boxBorder, 1.0)
        let v = p.default.firstLine
        if v.len > 0: c.txt(d, t, br.x + 5 * z, br.y + (br.h - float(small) * 1.25) / 2, c.fit(v, br.w / z - 10),
                            col.boxText, small)
    else:
      if label.len > 0 and not n.isCompact:
        let w = c.measureBase(label) * z * (float(small) / BaseFont)
        c.txt(d, t, pp.x - 12 * z - w, pp.y - float(small) * 0.65, label, col.text, small)

proc foldIconRect(c: BpCanvas, doc: BpDoc, n: Node): Rect =
  let z = doc.zoom
  rect(c.toSx(doc, n.x + n.w - 23), c.toSy(doc, n.y + 5), 16 * z, 16 * z)

proc fileIconRect(c: BpCanvas, doc: BpDoc, n: Node): Rect =
  let z = doc.zoom
  let off = if n.kind == nkEntry: 44.0 else: 21.0
  rect(c.toSx(doc, n.x + n.w - off), c.toSy(doc, n.y + 4), 14 * z, 18 * z)

proc localEntries(g: Graph): Table[string, int] =
  for id in g.entries:
    let e = g.node(id)
    if e != nil and e.mode in ["procedure", "fonction"]: result[e.title.toUpperAscii] = id

proc computeCalls(c: BpCanvas, doc: BpDoc): seq[tuple[a, b: int]] =
  ## Liens d'appel (appelant -> entrée appelée, dans ce fichier) et icônes « fichier »
  ## (appels de procédures d'autres fichiers) ; un appelant plié est représenté par son entrée.
  let g = doc.g
  let locals = g.localEntries
  c.extIcons.clear()
  var seen: HashSet[(int, int)]
  for n in g.nodes:
    let names = n.callNames
    if names.len == 0: continue
    var anchor = n.id
    if g.isHidden(n): anchor = g.ownerOf(n.id)
    for nm in names:
      if nm in locals:
        let target = locals[nm]
        if target != anchor and (anchor, target) notin seen:
          seen.incl (anchor, target)
          result.add (anchor, target)
      elif nm in doc.externals:
        let lst = c.extIcons.mgetOrPut(anchor, @[])
        if nm notin lst: c.extIcons[anchor].add nm

proc dashedBezier(d: Drawing, x1, y1, x2, y2: float, col: Color, w: float) =
  let dx = max(max(60.0, abs(x2 - x1) * 0.4), (if x2 < x1 + 40: abs(y2 - y1) * 0.45 + 40 else: 0.0))
  let c1x = x1 + dx
  let c2x = x2 - dx
  let steps = clamp(int((abs(x2 - x1) + abs(y2 - y1)) / 9), 10, 90)
  var px = x1
  var py = y1
  for k in 1 .. steps:
    let t = float(k) / float(steps)
    let u = 1 - t
    let nx = u*u*u*x1 + 3*u*u*t*c1x + 3*u*t*t*c2x + t*t*t*x2
    let ny = u*u*u*y1 + 3*u*u*t*y1 + 3*u*t*t*y2 + t*t*t*y2
    if k mod 2 == 1: d.line(px, py, nx, ny, col, w)
    px = nx
    py = ny

proc drawFileIcon(d: Drawing, r: Rect, col, bg: Color) =
  let f = r.w * 0.38
  d.fillPolygon([(r.x, r.y), (r.x + r.w - f, r.y), (r.x + r.w, r.y + f), (r.x + r.w, r.y + r.h), (r.x, r.y + r.h)], col)
  d.fillPolygon([(r.x + r.w - f, r.y), (r.x + r.w, r.y + f), (r.x + r.w - f, r.y + f)], bg)
  for k in 1 .. 3:
    let y = r.y + r.h * (0.3 + 0.17 * float(k))
    d.fillRect(rect(r.x + r.w * 0.2, y, r.w * 0.6, max(1.0, r.h * 0.07)), bg)

proc drawIcons(c: BpCanvas, d: Drawing, t: Theme, col: BpColors, doc: BpDoc, n: Node) =
  let z = doc.zoom
  if n.kind == nkEntry:
    let r = c.foldIconRect(doc, n)
    d.fillRoundRect(r, 3 * z, hex"#00000055")
    d.strokeRoundRect(r, 3 * z, hex"#FFFFFFB0", max(1.0, z))
    let cx = r.x + r.w / 2
    let cy = r.y + r.h / 2
    d.fillRect(rect(r.x + 4 * z, cy - 0.8 * z, r.w - 8 * z, max(1.0, 1.6 * z)), hex"#FFFFFF")
    if n.folded:
      d.fillRect(rect(cx - 0.8 * z, r.y + 4 * z, max(1.0, 1.6 * z), r.h - 8 * z), hex"#FFFFFF")
      let hidden = doc.g.reachableFrom(n.id).len - 1
      if hidden > 0 and z >= 0.32:
        c.txt(d, t, c.toSx(doc, n.x + 4), c.toSy(doc, n.y + n.h + 3),
              "▸ " & $hidden & " nœud(s) masqué(s) - icône + pour déplier", col.textDim,
              clamp(int(round(11 * z)), 5, 20))
  if n.id in c.extIcons:
    let r = c.fileIconRect(doc, n)
    drawFileIcon(d, r, hex"#8FB8FF", headerColor(n))

method preferredSize*(c: BpCanvas, d: Drawing, t: Theme): tuple[w, h: float] = (600.0, 400.0)

method typeName*(c: BpCanvas): string = "Blueprint"

method draw*(c: BpCanvas, d: Drawing, t: Theme) =
  let col = colorsOf(t)
  let r = c.rect
  d.fillRect(r, col.bg)
  when defined(sdlttf):
    discard c.fontFor(t, int(BaseFont))
  let doc = c.curDoc
  if doc == nil:
    c.txt(d, t, r.x + 20, r.y + 20, "Vue blueprint en préparation…", col.textDim, int(BaseFont))
    return
  c.ensureLayout(doc)
  let z = doc.zoom
  d.pushClip(r)
  # grille
  let minor = 16.0 * z
  if minor >= 7:
    var gx = c.toSx(doc, floor(doc.vx / 16) * 16)
    while gx < r.x + r.w:
      d.fillRect(rect(gx, r.y, 1, r.h), col.gridMinor)
      gx += minor
    var gy = c.toSy(doc, floor(doc.vy / 16) * 16)
    while gy < r.y + r.h:
      d.fillRect(rect(r.x, gy, r.w, 1), col.gridMinor)
      gy += minor
  let major = 128.0 * z
  var mx = c.toSx(doc, floor(doc.vx / 128) * 128)
  while mx < r.x + r.w:
    d.fillRect(rect(mx, r.y, 1, r.h), col.gridMajor)
    mx += major
  var my = c.toSy(doc, floor(doc.vy / 128) * 128)
  while my < r.y + r.h:
    d.fillRect(rect(r.x, my, r.w, 1), col.gridMajor)
    my += major
  let g = doc.g
  # liens (données puis exécution)
  for pass in 0 .. 1:
    for l in g.links:
      let a = g.node(l.a)
      let b = g.node(l.b)
      if a == nil or b == nil: continue
      let ia = a.pinIndex(l.ap)
      let ib = b.pinIndex(l.bp)
      if ia < 0 or ib < 0: continue
      if g.isHidden(a) or g.isHidden(b): continue
      let isExec = a.pins[ia].kind == pkExec
      if (pass == 0) == isExec: continue
      let p1 = c.pinScreen(doc, a, ia)
      let p2 = c.pinScreen(doc, b, ib)
      if max(p1.x, p2.x) < r.x - 60 or min(p1.x, p2.x) > r.x + r.w + 60 or
         max(p1.y, p2.y) < r.y - 60 or min(p1.y, p2.y) > r.y + r.h + 60: continue
      let hot = a.id in doc.sel or b.id in doc.sel
      let lc = if isExec: (if t.dark: hex"#E8E8E8" else: hex"#4A4E57") else: g.pinColor(a, a.pins[ia])
      bezier(d, p1.x + 5 * z, p1.y, p2.x - 5 * z, p2.y, (if hot: lc else: lc.withAlpha(200)),
             max(1.2, (if isExec: 2.6 else: 2.0) * z * (if hot: 1.3 else: 1.0)))
  # liens d'appel (procédures de ce fichier), en pointillés
  let calls = c.computeCalls(doc)
  if c.showCalls:
    let cc = if t.dark: hex"#B794F6" else: hex"#7C4DDB"
    for (ai, bi) in calls:
      let a = g.node(ai)
      let b = g.node(bi)
      if a == nil or b == nil: continue
      let x1 = c.toSx(doc, a.x + a.w)
      let y1 = c.toSy(doc, a.y + 13)
      let x2 = c.toSx(doc, b.x) - 2
      let y2 = c.toSy(doc, b.y + 13)
      if max(x1, x2) < r.x - 60 or min(x1, x2) > r.x + r.w + 60 or
         max(y1, y2) < r.y - 60 or min(y1, y2) > r.y + r.h + 60: continue
      let hot = a.id in doc.sel or b.id in doc.sel
      let lc = if hot: cc else: cc.withAlpha(150)
      dashedBezier(d, x1, y1, x2, y2, lc, max(1.2, (if hot: 2.4 else: 1.6) * z))
      d.fillPolygon([(x2 - 9 * z, y2 - 5 * z), (x2, y2), (x2 - 9 * z, y2 + 5 * z)], lc)
  # lien en cours
  if c.drag == dmLink:
    let a = g.node(c.linkNode)
    if a != nil:
      let ia = a.pinIndex(c.linkPid)
      if ia >= 0:
        let p = c.pinScreen(doc, a, ia)
        let lc = if c.linkKind == pkExec: hex"#FFFFFF" else: g.pinColor(a, a.pins[ia])
        if c.linkDir == pdOut: bezier(d, p.x, p.y, c.mx, c.my, lc, max(1.5, 2.2 * z))
        else: bezier(d, c.mx, c.my, p.x, p.y, lc, max(1.5, 2.2 * z))
  # nœuds (mesurés quand ils sont visibles : la taille suit les liens et les valeurs saisies)
  var selectedNodes: seq[Node]
  let m = c.measurer
  for n in g.nodes:
    if g.isHidden(n): continue
    var sr = c.screenRect(doc, n)
    if sr.x > r.x + r.w + 200 or sr.y > r.y + r.h + 200 or sr.x + sr.w < r.x - 200 or sr.y + sr.h < r.y - 200: continue
    g.measure(n, m)
    sr = c.screenRect(doc, n)
    if sr.x > r.x + r.w or sr.y > r.y + r.h + 40 or sr.x + sr.w < r.x or sr.y + sr.h < r.y: continue
    if n.id in doc.sel: selectedNodes.add n
    else:
      c.drawNode(d, t, col, doc, n)
      c.drawIcons(d, t, col, doc, n)
  for n in selectedNodes:
    c.drawNode(d, t, col, doc, n)
    c.drawIcons(d, t, col, doc, n)
  # lasso
  if c.drag == dmBand:
    let br = rect(min(c.pressX, c.mx), min(c.pressY, c.my), abs(c.mx - c.pressX), abs(c.my - c.pressY))
    d.fillRect(br, col.band)
    d.strokeRect(br, col.select)
  # fantôme d'un élément de palette
  if c.dropping and r.containsPoint(c.mx, c.my):
    let gr = rect(c.mx - 70 * z, c.my - 14 * z, 140 * z, 28 * z)
    d.fillRoundRect(gr, 6 * z, kindColorOf(c.dropItem).withAlpha(170))
    c.txt(d, t, gr.x + 8 * z, gr.y + 6 * z, c.fit(c.dropItem.label, 124), hex"#FFFFFF",
          clamp(int(round(BaseFont * z)), 6, 26))
  # bandeau d'information
  let info = $int(round(z * 100)) & " %  ·  " & $g.nodes.len & " nœuds"
  let lost = g.unreachable
  let infoText = info & (if lost > 0: "  ·  " & $lost & " instruction(s) non reliée(s), ignorée(s) dans le code" else: "")
  let iw = c.measureBase(infoText) * 12 / BaseFont + 16
  d.fillRoundRect(rect(r.x + 4, r.y + r.h - 26, iw, 22), 6, col.bg.withAlpha(225))
  c.txt(d, t, r.x + 12, r.y + r.h - 23, infoText, (if lost > 0: col.select else: col.textDim), 12)
  if g.error.len > 0:
    let w = min(r.w - 40, 620.0)
    let er = rect(r.x + (r.w - w) / 2, r.y + r.h / 3, w, 96)
    d.fillRoundRect(er, 8, (if t.dark: hex"#3A1F22" else: hex"#FCE8E8"))
    d.strokeRoundRect(er, 8, hex"#E5484D", 1.5)
    c.txt(d, t, er.x + 16, er.y + 14, "Ce code ne peut pas être affiché en blueprint :", col.text, 14)
    c.txt(d, t, er.x + 16, er.y + 40, c.fit(g.error, w - 32), hex"#E5484D", 13)
    c.txt(d, t, er.x + 16, er.y + 66, "Corrigez-le dans l'onglet de code (pastille bleue), puis revenez ici.",
          col.textDim, 12)
  d.popClip()

# ---------------------------------------------------------------------------
# canevas : édition

proc emitChange(c: BpCanvas) = emit(c, evChange, text = "graph")
proc emitSel(c: BpCanvas) = emit(c, evSelection, text = "bp:sel")

proc mutate*(doc: BpDoc) =
  ## À appeler avant toute modification du graphe (annulation).
  doc.undo.add doc.g.clone
  if doc.undo.len > 60: doc.undo.delete(0)
  doc.redo.setLen(0)

proc undoDoc*(doc: BpDoc): bool =
  if doc.undo.len == 0: return false
  doc.redo.add doc.g.clone
  doc.g = doc.undo.pop()
  var keep: HashSet[int]
  for id in doc.sel:
    if doc.g.node(id) != nil: keep.incl id
  doc.sel = keep
  true

proc redoDoc*(doc: BpDoc): bool =
  if doc.redo.len == 0: return false
  doc.undo.add doc.g.clone
  doc.g = doc.redo.pop()
  var keep: HashSet[int]
  for id in doc.sel:
    if doc.g.node(id) != nil: keep.incl id
  doc.sel = keep
  true

proc nodeAt(c: BpCanvas, doc: BpDoc, x, y: float): Node =
  for i in countdown(doc.g.nodes.high, 0):
    let n = doc.g.nodes[i]
    if c.screenRect(doc, n).containsPoint(x, y) and not doc.g.isHidden(n): return n

proc pinAt(c: BpCanvas, doc: BpDoc, x, y: float): tuple[node, pid: int] =
  result = (-1, -1)
  var best = (max(10.0, 11 * doc.zoom)) * (max(10.0, 11 * doc.zoom))
  for i in countdown(doc.g.nodes.high, 0):
    let n = doc.g.nodes[i]
    let r = c.screenRect(doc, n)
    if x < r.x - 16 or x > r.x + r.w + 16 or y < r.y - 4 or y > r.y + r.h + 4: continue
    if doc.g.isHidden(n): continue
    for k, p in n.pins:
      let pp = c.pinScreen(doc, n, k)
      let dd = (pp.x - x) * (pp.x - x) + (pp.y - y) * (pp.y - y)
      if dd <= best:
        best = dd
        result = (n.id, p.pid)

proc boxAt(c: BpCanvas, doc: BpDoc, n: Node, x, y: float): int =
  ## Broche dont la case de saisie est sous (x, y), -1 sinon.
  result = -1
  for i, p in n.pins:
    if p.dir == pdIn and p.kind == pkData and not doc.g.isLinkedIn(n, p.pid):
      var b = c.boxRect(doc, n, i)
      if n.isCompact:
        let pp = c.pinScreen(doc, n, i)
        b = rect(pp.x + 12 * doc.zoom, b.y, b.w, b.h)
      if b.containsPoint(x, y): return p.pid

proc uniqueEntryName(g: Graph, base: string): string =
  var k = 1
  while true:
    let name = base & $k
    var used = false
    for id in g.entries:
      let e = g.node(id)
      if e != nil and cmpIgnoreCase(e.title, name) == 0: used = true
    if not used: return name
    inc k

proc createFromItem(c: BpCanvas, doc: BpDoc, it: PaletteItem): Node =
  let g = doc.g
  case it.kind
  of nkEntry:
    result = g.makeNode(nkEntry, title = g.uniqueEntryName(if it.mode == "fonction": "FONCTION" else: "PROCEDURE"),
                        mode = it.mode)
    g.entries.add result.id
  of nkCall, nkMethod:
    result = g.makeNode(it.kind, title = it.title, stmt = it.stmt)
    result.brace = it.brace
    if it.brace:
      for p in result.pins.mitems:
        if p.dir == pdIn and p.kind == pkData:
          p.default = "{}"
          break
  of nkVar:
    result = g.makeNode(nkVar, title = (if it.title.len > 0: it.title else: "x"))
  of nkExpr:
    result = g.makeNode(nkExpr, text = (if it.text.len > 0: it.text else: "\"texte\""))
  else:
    result = g.makeNode(it.kind, title = it.title, text = it.text, mode = it.mode)
  g.measure(result, c.measurer)

proc placeNode(c: BpCanvas, doc: BpDoc, n: Node, wx, wy: float) =
  n.x = wx - n.w / 2
  n.y = wy - 12

proc autoInsert(c: BpCanvas, doc: BpDoc, n: Node): bool =
  ## Relie un nouveau nœud au nœud sélectionné : instruction insérée après lui,
  ## expression branchée sur sa première entrée libre.
  if doc.sel.len != 1: return false
  var sid = -1
  for id in doc.sel: sid = id
  let s = doc.g.node(sid)
  if s == nil or s.id == n.id: return false
  let g = doc.g
  if n.isExecNode and (s.isExecNode or s.kind == nkEntry):
    let outPid = s.execNext
    if outPid < 0: return false
    let nxt = g.followExec(s.id, outPid)
    g.connect(s.id, outPid, n.id, n.execIn)
    if nxt != nil: g.connect(n.id, n.execNext, nxt.id, nxt.execIn)
    n.x = s.x + 20
    n.y = s.y + s.h + 50
    return true
  if not n.isExecNode and n.kind != nkEntry and n.dataOut >= 0:
    for p in s.pins:
      if p.dir == pdIn and p.kind == pkData and not g.isLinkedIn(s, p.pid) and p.default.strip.len == 0:
        g.connect(n.id, n.dataOut, s.id, p.pid)
        n.x = s.x - n.w - 40
        n.y = s.y + s.headH + float(s.rowOf(s.pinIndex(p.pid))) * RowH
        return true
  false

proc addItem*(c: BpCanvas, it: PaletteItem, atX = NaN, atY = NaN) =
  ## Ajoute un nœud de palette : au point donné (écran), sinon relié au nœud sélectionné
  ## ou au centre de la vue.
  let doc = c.curDoc
  if doc == nil or doc.g.error.len > 0: return
  doc.mutate()
  let n = c.createFromItem(doc, it)
  if not atX.isNaN:
    c.placeNode(doc, n, c.toWx(doc, atX), c.toWy(doc, atY))
  elif not c.autoInsert(doc, n):
    c.placeNode(doc, n, c.toWx(doc, c.rect.x + c.rect.w / 2), c.toWy(doc, c.rect.y + c.rect.h / 2))
  doc.sel = [n.id].toHashSet
  markDirty(c)
  c.emitChange()
  c.emitSel()

proc deleteSelection*(c: BpCanvas) =
  let doc = c.curDoc
  if doc == nil or doc.sel.len == 0: return
  doc.mutate()
  var gone: seq[int]
  for id in doc.sel:
    if id == doc.g.mainId: continue
    let n = doc.g.node(id)
    if n != nil and n.kind == nkEntry: gone.add doc.g.reachableFrom(id)     # procédure entière
    else: gone.add id
  for id in gone: doc.g.removeNode(id, heal = id in doc.sel)
  doc.sel.clear()
  c.emitChange()
  c.emitSel()

proc duplicateSelection*(c: BpCanvas) =
  let doc = c.curDoc
  if doc == nil or doc.sel.len == 0: return
  doc.mutate()
  var fresh: HashSet[int]
  for id in doc.sel:
    let n = doc.g.node(id)
    if n == nil or n.kind == nkEntry: continue
    let m = doc.g.newNode(n.kind)
    let keepId = m.id
    m[] = n[]
    m.id = keepId
    m.x += 30
    m.y += 30
    m.dirty = true
    m.orig = @[]
    m.line = -1
    m.key = ""
    doc.g.byId[m.id] = m
    for i in 0 ..< doc.g.nodes.len:
      if doc.g.nodes[i].id == keepId: doc.g.nodes[i] = m
    fresh.incl m.id
  if fresh.len > 0: doc.sel = fresh
  c.emitChange()
  c.emitSel()

proc relayout*(c: BpCanvas) =
  let doc = c.curDoc
  if doc == nil: return
  doc.g.layout(c.measurer)
  doc.laidOut = true
  c.fitView(doc, 0.7)

proc openContext(c: BpCanvas, doc: BpDoc, x, y: float) =
  c.ctxX = c.toWx(doc, x)
  c.ctxY = c.toWy(doc, y)
  let pin = c.pinAt(doc, x, y)
  c.ctxNode = -1
  c.ctxPin = -1
  var items: seq[string]
  if pin.node >= 0:
    c.ctxNode = pin.node
    c.ctxPin = pin.pid
    items = @["Rompre les liens de cette broche"]
  else:
    let n = c.nodeAt(doc, x, y)
    if n != nil:
      c.ctxNode = n.id
      if n.id notin doc.sel:
        doc.sel = [n.id].toHashSet
        c.emitSel()
      if n.kind == nkEntry: items.add (if n.folded: "Déplier" else: "Plier")
      items.add "Voir dans le code"
      if n.kind in {nkCall, nkMethod}:
        items.add (if n.stmt: "Utiliser comme expression (résultat)" else: "Utiliser comme instruction")
      if n.kind == nkIf: items.add (if n.elseIf: "Écrire « si » (imbriqué)" else: "Écrire « sinonsi » dans un sinon")
      items.add "Rompre tous les liens"
      if n.kind != nkEntry or n.id != doc.g.mainId:
        items.add "Dupliquer"
        items.add "Supprimer"
    else:
      items = @["Ajouter : Afficher", "Ajouter : Affecter", "Ajouter : Si", "Ajouter : Pour",
                "Ajouter : Pour chaque", "Ajouter : Tant que", "Ajouter : Appel de procédure",
                "Ajouter : Commentaire", "Ajouter : Code Lexis+", "Nouvelle procédure", "-",
                "Réorganiser", "Tout voir", "Tout plier", "Tout déplier"]
  c.ctxItems = items
  openPopupList(c, items, x, y, 220)

method onPopupChoice*(c: BpCanvas, i: int, text: string) =
  let doc = c.curDoc
  if doc == nil: return
  let g = doc.g
  let n = g.node(c.ctxNode)
  let sx = c.toSx(doc, c.ctxX)
  let sy = c.toSy(doc, c.ctxY)
  case text
  of "Rompre les liens de cette broche":
    if n != nil:
      doc.mutate()
      g.disconnectPin(n.id, c.ctxPin)
      c.emitChange()
  of "Voir dans le code":
    if n != nil: emit(c, evSelection, text = "bp:goto:" & $n.line)
  of "Utiliser comme expression (résultat)", "Utiliser comme instruction":
    if n != nil:
      doc.mutate()
      g.setStatement(n, not n.stmt)
      c.emitChange()
      c.emitSel()
  of "Écrire « si » (imbriqué)", "Écrire « sinonsi » dans un sinon":
    if n != nil:
      doc.mutate()
      n.elseIf = not n.elseIf
      n.dirty = true
      c.emitChange()
  of "Rompre tous les liens":
    if n != nil:
      doc.mutate()
      for p in n.pins: g.disconnectPin(n.id, p.pid)
      c.emitChange()
  of "Dupliquer": c.duplicateSelection()
  of "Supprimer": c.deleteSelection()
  of "Réorganiser": c.relayout()
  of "Tout voir": c.fitView(doc)
  of "Plier", "Déplier":
    if n != nil and n.kind == nkEntry: doc.toggleFold(n)
  of "Tout plier": doc.foldAll(true)
  of "Tout déplier": doc.foldAll(false)
  of "Nouvelle procédure":
    doc.sel.clear()
    c.addItem(PaletteItem(kind: nkEntry, mode: "procedure", label: "Nouvelle procédure"), sx, sy)
  else:
    if text.startsWith("Ouvrir ") and " (" in text:
      emit(c, evSelection, text = "bp:open:" & text[7 ..< text.find(" (")])
      return
    if text.startsWith("Ajouter : "):
      doc.sel.clear()
      let what = text[10 .. ^1]
      var it = PaletteItem(label: what)
      case what
      of "Afficher": it.kind = nkPrint
      of "Affecter": it.kind = nkAssign
      of "Si": it.kind = nkIf
      of "Pour": it.kind = nkFor
      of "Pour chaque": it.kind = nkForEach
      of "Tant que": it.kind = nkWhile
      of "Appel de procédure":
        it.kind = nkCall
        it.title = "PROCEDURE"
        it.stmt = true
      of "Commentaire":
        it.kind = nkComment
        it.text = "commentaire"
      of "Code Lexis+":
        it.kind = nkRaw
        it.text = "? \"code\""
      else: return
      c.addItem(it, sx, sy)
  markDirty(c)

method mouseCursor*(c: BpCanvas, x, y: float): int =
  if c.drag == dmPan: return SDL_SYSTEM_CURSOR_MOVE
  if c.hoverPin >= 0 or c.drag == dmLink: return SDL_SYSTEM_CURSOR_POINTER
  SDL_SYSTEM_CURSOR_DEFAULT

method onMouse*(c: BpCanvas, e: MouseEvent) =
  let doc = c.curDoc
  if doc == nil: return
  let g = doc.g
  let editable = g.error.len == 0
  case e.action
  of maPress:
    c.pressX = e.x
    c.pressY = e.y
    c.mx = e.x
    c.my = e.y
    c.dragMoved = false
    c.mutated = false
    if e.button in {mbRight, mbMiddle}:
      c.drag = dmPan
      return
    if e.button != mbLeft or not editable: return
    let alt = (e.mods and KMOD_ALT) != 0
    let addSel = (e.mods and (KMOD_SHIFT or KMOD_CTRL)) != 0
    let hit = c.pinAt(doc, e.x, e.y)
    if hit.node >= 0:
      let n = g.node(hit.node)
      let p = n.pins[n.pinIndex(hit.pid)]
      if alt:
        doc.mutate()
        g.disconnectPin(n.id, p.pid)
        c.emitChange()
        return
      if p.dir == pdIn and g.isLinkedIn(n, p.pid):
        # reprise d'un lien existant depuis sa source.
        let li = g.linkInto(n.id, p.pid)
        let l = g.links[li]
        doc.mutate()
        c.mutated = true
        g.disconnectPin(n.id, p.pid)
        let src = g.node(l.a)
        c.linkNode = l.a
        c.linkPid = l.ap
        c.linkDir = pdOut
        c.linkKind = src.pins[src.pinIndex(l.ap)].kind
      else:
        c.linkNode = n.id
        c.linkPid = p.pid
        c.linkDir = p.dir
        c.linkKind = p.kind
      c.drag = dmLink
      return
    let n = c.nodeAt(doc, e.x, e.y)
    if n != nil:
      # icône plier / déplier d'une procédure
      if n.kind == nkEntry and c.foldIconRect(doc, n).shrink(-3).containsPoint(e.x, e.y):
        doc.toggleFold(n)
        c.drag = dmNone
        c.emitSel()
        return
      # icône fichier : procédure d'un autre fichier (double-clic : l'ouvrir en blueprint)
      if n.id in c.extIcons and c.fileIconRect(doc, n).shrink(-3).containsPoint(e.x, e.y):
        c.drag = dmNone
        if e.clicks >= 2:
          let names = c.extIcons[n.id]
          if names.len == 1: emit(c, evSelection, text = "bp:open:" & names[0])
          else:
            var items: seq[string]
            for nm in names:
              items.add "Ouvrir " & nm & " (" & extractFilename(doc.externals[nm].path) & ")"
            c.ctxItems = items
            openPopupList(c, items, e.x, e.y, 240)
        return
      if e.clicks >= 2:
        let box = c.boxAt(doc, n, e.x, e.y)
        doc.sel = [n.id].toHashSet
        c.emitSel()
        if box >= 0: emit(c, evSelection, text = "bp:edit:" & $n.id & ":" & $box)
        elif n.kind in {nkComment, nkRaw, nkExpr}: emit(c, evSelection, text = "bp:edit:" & $n.id & ":0")
        else: emit(c, evSelection, text = "bp:goto:" & $n.line)
        c.drag = dmNone
        return
      if addSel:
        if n.id in doc.sel: doc.sel.excl n.id else: doc.sel.incl n.id
      elif n.id notin doc.sel:
        doc.sel = [n.id].toHashSet
      c.drag = dmMove
      # une procédure pliée emporte son contenu masqué.
      c.moveSet.setLen(0)
      var moved: HashSet[int]
      for id in doc.sel:
        let m = g.node(id)
        if m != nil and m.kind == nkEntry and m.folded:
          for o in g.reachableFrom(id): moved.incl o
        moved.incl id
      for id in moved: c.moveSet.add id
      c.emitSel()
    else:
      if not addSel and doc.sel.len > 0:
        doc.sel.clear()
        c.emitSel()
      c.drag = dmBand
  of maMove:
    let dx = e.x - c.mx
    let dy = e.y - c.my
    if abs(e.x - c.pressX) + abs(e.y - c.pressY) > 4: c.dragMoved = true
    case c.drag
    of dmPan:
      doc.vx -= dx / doc.zoom
      doc.vy -= dy / doc.zoom
    of dmMove:
      for id in c.moveSet:
        let n = g.node(id)
        if n != nil:
          n.x += dx / doc.zoom
          n.y += dy / doc.zoom
    else: discard
    c.mx = e.x
    c.my = e.y
    let hp = c.pinAt(doc, e.x, e.y)
    c.hoverPinNode = hp.node
    c.hoverPin = hp.pid
    if c.drag == dmNone and not c.dropping:
      let n = c.nodeAt(doc, e.x, e.y)
      var tip = ""
      if n != nil and n.kind == nkEntry and c.foldIconRect(doc, n).shrink(-3).containsPoint(e.x, e.y):
        tip = (if n.folded: "Déplier : afficher le contenu de " else: "Plier : masquer le contenu de ") &
              n.headerTitle & " (ses appels partent alors de la procédure)"
      elif n != nil and n.id in c.extIcons and c.fileIconRect(doc, n).shrink(-3).containsPoint(e.x, e.y):
        var parts: seq[string]
        for nm in c.extIcons[n.id]:
          if nm in doc.externals: parts.add nm & " (" & extractFilename(doc.externals[nm].path) & ")"
        tip = "Défini dans un autre fichier : " & parts.join(", ") & "  ·  double-clic : l'ouvrir en blueprint"
      elif hp.node >= 0:
        let pn = g.node(hp.node)
        let p = pn.pins[pn.pinIndex(hp.pid)]
        tip = (if p.kind == pkExec: "exécution" else: "donnée") & (if p.dir == pdIn: " (entrée)" else: " (sortie)") &
              (if pn.pinLabel(p).len > 0: " : " & pn.pinLabel(p) else: "") &
              (if p.optional: " - facultative" else: "") & "  ·  Alt+clic : rompre les liens"
      elif n != nil:
        if n.kind in {nkCall, nkMethod}:
          let s = summaryFor(n.title, n.kind == nkMethod)
          tip = if s.len > 0: s else: n.headerTitle
        elif n.kind == nkExpr: tip = n.text
        elif n.line >= 0: tip = n.headerTitle & "  ·  ligne " & $(n.line + 1) & "  ·  double-clic : voir dans le code"
      c.tooltip = tip
  of maRelease:
    case c.drag
    of dmPan:
      if not c.dragMoved and e.button == mbRight and editable: c.openContext(doc, e.x, e.y)
    of dmLink:
      let hit = c.pinAt(doc, e.x, e.y)
      var ok = false
      if hit.node >= 0:
        var (a, ap, b, bp) = (c.linkNode, c.linkPid, hit.node, hit.pid)
        if c.linkDir == pdIn: (a, ap, b, bp) = (hit.node, hit.pid, c.linkNode, c.linkPid)
        let na = g.node(a)
        let nb = g.node(b)
        # un appel en mode expression devient instruction quand on lui branche l'exécution (et inversement).
        if na != nil and nb != nil:
          let pa = na.pinIndex(ap)
          let pb = nb.pinIndex(bp)
          if pa >= 0 and pb >= 0 and na.pins[pa].kind != nb.pins[pb].kind:
            discard
          if g.canLink(a, ap, b, bp):
            if not c.mutated: doc.mutate()
            g.connect(a, ap, b, bp)
            ok = true
      if ok or c.mutated: c.emitChange()
    of dmBand:
      let x0 = min(c.pressX, e.x)
      let y0 = min(c.pressY, e.y)
      let br = rect(x0, y0, abs(e.x - c.pressX), abs(e.y - c.pressY))
      if br.w > 3 or br.h > 3:
        for n in g.nodes:
          if g.isHidden(n): continue
          let r = c.screenRect(doc, n)
          if r.x < br.x + br.w and r.x + r.w > br.x and r.y < br.y + br.h and r.y + r.h > br.y:
            doc.sel.incl n.id
        c.emitSel()
    else: discard
    c.drag = dmNone
  markDirty(c)

method onWheel*(c: BpCanvas, dx, dy: float): bool =
  let doc = c.curDoc
  if doc == nil: return false
  let mods = SDL_GetModState()
  if (mods and (KMOD_CTRL or KMOD_CMD)) != 0:
    c.zoomAt(doc, pow(1.12, dy), c.mx, c.my)
  else:
    var h = dx
    var v = dy
    if h == 0 and (mods and KMOD_SHIFT) != 0:
      h = v
      v = 0
    doc.vx -= h * 40 / doc.zoom
    doc.vy -= v * 40 / doc.zoom
  markDirty(c)
  true

method onKey*(c: BpCanvas, e: KeyEvent): bool =
  let doc = c.curDoc
  if doc == nil: return false
  let ctrl = (e.mods and (KMOD_CTRL or KMOD_CMD)) != 0
  let shift = (e.mods and KMOD_SHIFT) != 0
  let k = int(e.key)
  # raccourcis de l'atelier (comme dans l'éditeur de code)
  var shortcut = ""
  case k
  of KF5: shortcut = (if shift: "cmd:stop" else: "cmd:debug")
  of KF10: shortcut = "cmd:stepover"
  of KF11: shortcut = (if shift: "cmd:stepout" else: "cmd:stepinto")
  else:
    if ctrl:
      case k
      of ord('s'): shortcut = (if shift: "cmd:saveas" else: "cmd:save")
      of ord('r'): shortcut = "cmd:run"
      of ord('n'): shortcut = "cmd:new"
      of ord('o'): shortcut = "cmd:open"
      else: discard
  if shortcut.len > 0:
    emit(c, evSelection, text = shortcut)
    return true
  if ctrl and k == KTab and c.editor != nil and c.editor.docs.len > 1:
    let ed = c.editor
    var i = 0
    for j, d in ed.docs:
      if d.uid == c.cur: i = j
    let nxt = (i + (if shift: ed.docs.len - 1 else: 1)) mod ed.docs.len
    editorActivate(ed.id, ed.docs[nxt].uid)
    return true
  let editable = doc.g.error.len == 0
  if ctrl and (k == ord('z') or k == ord('y')):
    let ok = if k == ord('y') or shift: doc.redoDoc() else: doc.undoDoc()
    if ok:
      c.emitChange()
      c.emitSel()
    return true
  if ctrl and k == ord('d') and editable:
    c.duplicateSelection()
    return true
  if ctrl and k == ord('a'):
    for n in doc.g.nodes:
      if not doc.g.isHidden(n): doc.sel.incl n.id
    c.emitSel()
    return true
  if ctrl and k in [ord('+'), ord('='), KKpPlus]:
    c.zoomAt(doc, 1.2, c.rect.x + c.rect.w / 2, c.rect.y + c.rect.h / 2)
    return true
  if ctrl and k in [ord('-'), KKpMinus]:
    c.zoomAt(doc, 1 / 1.2, c.rect.x + c.rect.w / 2, c.rect.y + c.rect.h / 2)
    return true
  case e.key
  of SDLK_DELETE, SDLK_BACKSPACE:
    if editable: c.deleteSelection()
    return true
  of SDLK_ESCAPE:
    doc.sel.clear()
    c.emitSel()
    return true
  of SDLK_LEFT, SDLK_RIGHT, SDLK_UP, SDLK_DOWN:
    let step = if shift: 64.0 else: 16.0
    if doc.sel.len == 0:
      case e.key
      of SDLK_LEFT: doc.vx -= step * 2
      of SDLK_RIGHT: doc.vx += step * 2
      of SDLK_UP: doc.vy -= step * 2
      else: doc.vy += step * 2
    else:
      for id in doc.sel:
        let n = doc.g.node(id)
        if n == nil: continue
        case e.key
        of SDLK_LEFT: n.x -= step
        of SDLK_RIGHT: n.x += step
        of SDLK_UP: n.y -= step
        else: n.y += step
    markDirty(c)
    return true
  else: discard
  if not ctrl and (k == ord('f') or k == KHome):
    if doc.sel.len == 1:
      for id in doc.sel:
        let n = doc.g.node(id)
        if n != nil: c.focusOnNode(doc, n)
    else: c.fitView(doc)
    markDirty(c)
    return true
  false

# ---------------------------------------------------------------------------
# palette

proc paletteItems(p: BpPalette): seq[PaletteItem] =
  template item(cat, lbl: string, k: NodeKind, ti = "", te = "", mo = "", st = false, dc = "") =
    result.add PaletteItem(category: cat, label: lbl, kind: k, title: ti, text: te, mode: mo, stmt: st, doc: dc)
  let c1 = "Procédures"
  item(c1, "Nouvelle procédure", nkEntry, mo = "procedure", dc = "procedure NOM(paramètres) ... retourner")
  item(c1, "Nouvelle fonction", nkEntry, mo = "fonction", dc = "fonction NOM(paramètres) ... retourner valeur")
  item(c1, "Retourner", nkReturn, dc = "retourner [valeur]")
  for name in p.projectProcs:
    item(c1, name & "()", nkCall, ti = name, st = true, dc = "procédure du projet")
  let c2 = "Instructions"
  item(c2, "Afficher  ?", nkPrint, mo = "?", dc = "? valeur, ... (puis fin de ligne)")
  item(c2, "Afficher sans retour  ??", nkPrint, mo = "??", dc = "?? valeur, ...")
  item(c2, "Affecter  x = valeur", nkAssign, te = "x", mo = "=", dc = "cible = valeur")
  item(c2, "Ajouter à  x += valeur", nkAssign, te = "x", mo = "+=", dc = "cible += valeur")
  item(c2, "Retirer de  x -= valeur", nkAssign, te = "x", mo = "-=", dc = "cible -= valeur")
  item(c2, "Locale", nkLocal, te = "x", mo = "locale", dc = "locale x [= valeur]")
  item(c2, "Globale", nkLocal, te = "x", mo = "globale", dc = "globale x [= valeur]")
  item(c2, "Commentaire", nkComment, te = "commentaire", dc = "&& texte")
  item(c2, "Code Lexis+", nkRaw, te = "? \"code\"", dc = "instruction écrite telle quelle")
  let c3 = "Contrôle"
  item(c3, "Si", nkIf, dc = "si condition ... sinon ... finsi")
  item(c3, "Faire cas", nkCase, dc = "faire cas / cas condition ... autrement ... fincas")
  item(c3, "Tant que", nkWhile, mo = "tantque", dc = "tantque condition ... fintantque")
  item(c3, "Pour", nkFor, te = "i", dc = "pour i = début a fin [pas p] ... suivant")
  item(c3, "Pour chaque", nkForEach, te = "v", dc = "pour chaque [clef,] valeur dans collection ... suivant")
  item(c3, "Parcourir", nkScan, dc = "parcourir [pour condition] ... finparcourir")
  item(c3, "Essayer", nkTry, te = "e", dc = "essayer ... capturer e ... finessayer")
  item(c3, "Sortir", nkBreak, dc = "sortir : quitte la boucle")
  item(c3, "Boucler", nkContinue, dc = "boucler : tour suivant")
  let c4 = "Valeurs et opérateurs"
  item(c4, "Variable", nkVar, ti = "x", dc = "nom de variable (ou chemin a.b)")
  item(c4, "Valeur (expression)", nkExpr, te = "\"texte\"", dc = "expression Lexis+ quelconque")
  item(c4, "Membre  objet.nom", nkMember, ti = "nom", dc = "objet.nom")
  item(c4, "Index  objet[clé]", nkIndex, dc = "objet[clé]")
  for op in ["+", "-", "*", "/", "%", "^", "..", "=", "<>", "<", "<=", ">", ">=", "$", "et", "ou"]:
    item(c4, "a " & op & " b", nkOp, ti = op, dc = "opérateur " & op)
  item(c4, "non x", nkUnary, ti = "non", dc = "négation logique")
  item(c4, "- x", nkUnary, ti = "-", dc = "opposé")
  item(c4, "# x  (longueur)", nkUnary, ti = "#", dc = "longueur d'une chaîne ou d'une liste")
  item(c4, "sisinon(c, a, b)", nkCall, ti = "sisinon", dc = "a si c, sinon b")
  # fonctions documentées
  var secs: seq[string]
  var entries = apiEntries()
  entries.sort(proc (a, b: ApiDoc): int = cmp(a.signature.toLower, b.signature.toLower))
  for e in entries:
    if e.section notin secs: secs.add e.section
  secs.sort(proc (a, b: string): int = cmp(a.toLower, b.toLower))   # paquets par ordre alphabétique
  for sec in secs:
    let cat = if sec == "base": "Fonctions intégrées" else: "Paquet " & sec
    for e in entries:
      if e.section != sec: continue
      let callable = e.signature.find({'(', '{'}) >= 0
      if e.isMethod:
        item(cat, ":" & e.name & "  (" & e.owner & ")", nkMethod, ti = e.name, dc = e.signature & " - " & e.doc)
      elif not callable:
        item(cat, e.signature, nkVar, ti = e.signature, dc = e.doc)
      else:
        let title = if e.owner.len > 0: e.owner & "." & e.name else: e.name
        var it = PaletteItem(category: cat, label: (if e.owner.len > 0: e.owner & "." & e.name else: e.name) & "()",
                             kind: nkCall, title: title, doc: e.signature & " - " & e.doc)
        it.brace = e.signature.find('{') >= 0 and (e.signature.find('(') < 0 or
                   e.signature.find('{') < e.signature.find('('))
        result.add it

proc newBpPalette*(canvas: BpCanvas): BpPalette =
  result = BpPalette(canvas: canvas, hoverIdx: -1, pressIdx: -1)
  result.expanded = ["Procédures", "Instructions", "Contrôle", "Valeurs et opérateurs"].toHashSet
  initControl(result)

proc norm(s: string): string =
  result = s.toLower
  for (a, b) in [("é", "e"), ("è", "e"), ("ê", "e"), ("à", "a"), ("â", "a"), ("ù", "u"), ("û", "u"),
                 ("ô", "o"), ("î", "i"), ("ï", "i"), ("ç", "c")]:
    result = result.replace(a, b)

proc rows(p: BpPalette): seq[PaletteItem] =
  if not p.built:
    p.items = p.paletteItems()
    p.built = true
  let f = p.filter.strip.norm
  var lastCat = ""
  for it in p.items:
    if f.len > 0 and f notin norm(it.label & " " & it.title & " " & it.category): continue
    if it.category != lastCat:
      lastCat = it.category
      result.add PaletteItem(header: true, category: it.category, label: it.category)
    if f.len > 0 or it.category in p.expanded: result.add it

proc rebuildPalette*(p: BpPalette) = p.built = false

proc rowH(t: Theme): float = t.lineHeight + 1

proc rowAt(p: BpPalette, t: Theme, y: float): int =
  let i = int(floor((y - p.rect.y - 4 + p.scroll) / rowH(t)))
  let rs = p.rows
  if i >= 0 and i < rs.len: i else: -1

method preferredSize*(p: BpPalette, d: Drawing, t: Theme): tuple[w, h: float] = (PaletteW, 400.0)

method typeName*(p: BpPalette): string = "BlueprintPalette"

method draw*(p: BpPalette, d: Drawing, t: Theme) =
  d.fillRect(p.rect, t.header)
  d.pushClip(p.rect)
  let rh = rowH(t)
  if not p.hovered: p.hoverIdx = -1
  let rs = p.rows
  let total = float(rs.len) * rh + 8
  p.scroll = clamp(p.scroll, 0.0, max(0.0, total - p.rect.h))
  for i, it in rs:
    let y = p.rect.y + 4 + float(i) * rh - p.scroll
    if y + rh < p.rect.y or y > p.rect.y + p.rect.h: continue
    let rr = rect(p.rect.x + 4, y, p.rect.w - 8, rh)
    if it.header:
      if i == p.hoverIdx: d.fillRoundRect(rr, 5, t.surfaceHover)
      let open = p.filter.strip.len > 0 or it.category in p.expanded
      d.triangle(rr.x + 9, y + rh / 2, 4.5, (if open: 'v' else: '>'), t.textSecondary)
      d.textIn(rect(rr.x + 18, y, rr.w - 18, rh), it.label.toUpper, t.textSecondary)
      continue
    if i == p.hoverIdx: d.fillRoundRect(rr, 5, t.surfaceHover)
    let badge = rect(rr.x + 8, y + (rh - 12) / 2, 12, 12)
    d.fillRoundRect(badge, 3, kindColorOf(it))
    d.textIn(rect(rr.x + 26, y, rr.w - 28, rh), it.label, t.text)
  d.popClip()
  drawScrollIndicator(d, t, rect(p.rect.x + p.rect.w - 9, p.rect.y, 8, p.rect.h), total, p.rect.h, p.scroll)

method onMouse*(p: BpPalette, e: MouseEvent) =
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
      let rs = p.rows
      if p.pressIdx < rs.len and not rs[p.pressIdx].header:
        if not p.dragging and abs(e.x - p.pressX) + abs(e.y - p.pressY) > 5: p.dragging = true
        if p.dragging:
          c.dropping = true
          c.dropItem = rs[p.pressIdx]
          c.mx = e.x
          c.my = e.y
          markDirty(c)
    else:
      p.hoverIdx = p.rowAt(t, e.y)
      let rs = p.rows
      p.tooltip = if p.hoverIdx >= 0 and p.hoverIdx < rs.len and not rs[p.hoverIdx].header: rs[p.hoverIdx].doc else: ""
  of maRelease:
    let rs = p.rows
    if p.pressIdx >= 0 and p.pressIdx < rs.len:
      let it = rs[p.pressIdx]
      if it.header:
        if p.rowAt(t, e.y) == p.pressIdx and p.filter.strip.len == 0:
          if it.category in p.expanded: p.expanded.excl it.category else: p.expanded.incl it.category
      elif p.dragging:
        if c.rect.containsPoint(e.x, e.y): c.addItem(it, e.x, e.y)
      elif p.rowAt(t, e.y) == p.pressIdx:
        c.addItem(it)
    c.dropping = false
    p.pressIdx = -1
    p.dragging = false
    markDirty(c)

method onWheel*(p: BpPalette, dx, dy: float): bool =
  p.scroll = max(0.0, p.scroll - dy * 36)
  true

# ---------------------------------------------------------------------------
# hôte : éditeur + vue blueprint superposée

method layoutChildren*(h: DocHost, d: Drawing, t: Theme) =
  let r = h.rect
  layoutControl(h.editor, r, d, t)
  let doc = h.editor.doc
  let isBp = doc != nil and doc.kind == dkBlueprint
  h.pane.visible = isBp
  if isBp:
    h.canvas.cur = doc.uid
    layoutControl(h.pane, rect(r.x, r.y + EditorTabBarH, r.w, max(0.0, r.h - EditorTabBarH)), d, t)
  let now = if isBp: doc.uid else: -1
  if now != h.lastBp and h.win != nil:
    if isBp: setFocusInternal(h.win, h.canvas)
    elif h.win.focusedControl != nil:
      var p = h.win.focusedControl
      var inside = false
      while p != nil:
        if p == h.pane: inside = true
        p = p.parent
      if inside: setFocusInternal(h.win, h.editor)
  h.lastBp = now

method typeName*(h: DocHost): string = "DocHost"

method preferredSize*(h: DocHost, d: Drawing, t: Theme): tuple[w, h: float] = (600.0, 400.0)

proc newDocHost*(editor: CodeEditor, theme: Theme): DocHost =
  ## Éditeur de code + vue blueprint (barre d'outils, palette, canevas, détails).
  result = DocHost(layout: lkAbsolute, margin: 0, spacing: 0, lastBp: -1, editor: editor)
  initControl(result)
  editor.kindDots = true
  discard result.addChild(editor)
  let pane = newContainer(lkBorder, 0, 0)
  result.pane = pane
  discard result.addChild(pane)
  pane.visible = false
  # barre d'outils
  let tb = pane.addChild(newToolbar())
  tb.dock = dkTop
  toolIds.setLen(0)
  for (caption, cmd, tip) in [("Voir le code", "code", "Revenir à l'onglet du code (ou cliquer la pastille bleue)"),
                              ("Annuler", "undo", "Ctrl+Z"), ("Rétablir", "redo", "Ctrl+Y"),
                              ("Supprimer", "delete", "Suppr : supprime les nœuds sélectionnés"),
                              ("Réorganiser", "layout", "Mise en page automatique du graphe"),
                              ("Tout voir", "fit", "F ou Origine : ajuste le zoom au graphe (ou au nœud sélectionné)"),
                              ("Zoom −", "zoomout", "Ctrl+molette ou Ctrl+-"), ("Zoom +", "zoomin", "Ctrl+molette ou Ctrl++"),
                              ("Recharger", "reload", "Relit le code de l'onglet (positions conservées si possible)"),
                              ("Tout plier", "foldall", "Plie toutes les procédures (leurs appels partent alors de la procédure)"),
                              ("Tout déplier", "unfoldall", "Déplie toutes les procédures"),
                              ("Appels", "calls", "Affiche ou masque les liens d'appel entre procédures (pointillés)")]:
    let b = tb.addTool(caption, tip)
    toolIds.add (b.id, cmd)
  let info = tb.addChild(newLabel("  glisser depuis la palette · relier les broches · clic droit : menu"))
  info.weight = 1
  info.style.text = some(theme.textSecondary)
  infoId = info.id
  # palette
  let canvas = newBpCanvas()
  canvas.editor = editor
  result.canvas = canvas
  let left = pane.addChild(newContainer(lkBorder, 4, 4))
  left.dock = dkLeft
  left.fixedWidth = PaletteW
  let search = left.addChild(newEdit(placeholder = "Rechercher (fonction, paquet…)"))
  search.dock = dkTop
  searchId = search.id
  let pal = newBpPalette(canvas)
  pal.dock = dkCenter
  discard left.addChild(pal)
  paletteId = pal.id
  # détails
  let right = pane.addChild(newPanel(lkVertical, smAutomatic, 8, 6))
  right.dock = dkRight
  right.fixedWidth = DetailsW
  detailsId = right.id
  # canevas
  canvas.dock = dkCenter
  discard pane.addChild(canvas)
  canvasId = canvas.id
  editorId = editor.id

method onAttach*(h: DocHost, w: Window) =
  hostId = h.id

# ---------------------------------------------------------------------------
# API de l'atelier (sûre entre fils)

proc bpCanvasId*(): ControlId = canvasId

proc bpHostInUse*(): bool =
  ## Vrai si une vue blueprint a déjà été créée dans ce processus (l'état est global).
  int(canvasId) != 0

proc bpIsLoaded*(bpUid: int): bool =
  readControl(canvasId, BpCanvas, c): result = bpUid in c.docs

proc bpRefreshExternals*(bpUid: int) =
  ## Procédures appelées par la vue et définies dans un autre fichier du projet.
  var names: seq[string]
  var locals: HashSet[string]
  var src = -1
  readControl(canvasId, BpCanvas, c):
    let doc = c.docs.getOrDefault(bpUid)
    if doc == nil: return
    src = doc.srcUid
    for n in doc.g.nodes:
      for nm in n.callNames:
        if nm notin names: names.add nm
    for k in doc.g.localEntries.keys: locals.incl k
  if bpLocate == nil: return
  let srcPath = editorInfo(editorId, src).path
  var ext = initTable[string, tuple[path: string, line: int]]()
  for nm in names:
    if nm in locals: continue
    var loc: tuple[path: string, line: int]
    {.cast(gcsafe).}: loc = bpLocate(nm)
    if loc.path.len == 0: continue
    if srcPath.len > 0 and normalizedPath(absolutePath(loc.path)) == normalizedPath(absolutePath(srcPath)): continue
    ext[nm] = loc
  withControl(canvasId, BpCanvas, c):
    let doc = c.docs.getOrDefault(bpUid)
    if doc != nil: doc.externals = ext

proc loadDoc(bpUid, srcUid: int, text: string, version: int, force: bool)

proc bpOpen*(bpUid, srcUid: int, text: string, version: int, force = false) =
  ## Charge (ou recharge si le code a changé) la vue bpUid du document srcUid.
  loadDoc(bpUid, srcUid, text, version, force)
  bpRefreshExternals(bpUid)

proc loadDoc(bpUid, srcUid: int, text: string, version: int, force: bool) =
  var need = force
  readControl(canvasId, BpCanvas, c):
    let doc = c.docs.getOrDefault(bpUid)
    need = need or doc == nil or doc.synced != version
  if not need: return
  let g = parseGraph(text)
  withControl(canvasId, BpCanvas, c):
    var doc = c.docs.getOrDefault(bpUid)
    if doc == nil:
      doc = BpDoc(uid: bpUid, srcUid: srcUid, zoom: 1.0, pendingLine: -1)
      c.docs[bpUid] = doc
    let old = doc.g
    doc.undo.setLen(0)
    doc.redo.setLen(0)
    doc.g = g
    doc.synced = version
    doc.srcUid = srcUid
    if old != nil and doc.laidOut and g.keepPositions(old):
      doc.laidOut = true
    else:
      doc.laidOut = false
      if old == nil: doc.fitted = false
    var keep: HashSet[int]
    doc.sel = keep

proc bpClose*(bpUid: int) =
  withControl(canvasId, BpCanvas, c):
    c.docs.del(bpUid)

proc bpSourceOf*(bpUid: int): int =
  result = -1
  readControl(canvasId, BpCanvas, c):
    let doc = c.docs.getOrDefault(bpUid)
    if doc != nil: result = doc.srcUid

proc bpSync*() =
  ## Régénère le code du document représenté par la vue affichée.
  var code = ""
  var src = -1
  var bp = -1
  var bad = false
  readControl(canvasId, BpCanvas, c):
    let doc = c.curDoc
    if doc != nil:
      bad = doc.g.error.len > 0
      if not bad:
        code = generate(doc.g)
        src = doc.srcUid
        bp = doc.uid
  if src < 0 or bad: return
  discard editorSetText(editorId, src, code)
  let v = editorInfo(editorId, src).version
  withControl(canvasId, BpCanvas, c):
    let doc = c.docs.getOrDefault(bp)
    if doc != nil: doc.synced = v
  bpRefreshExternals(bp)
  if bpCodeChanged != nil:
    {.cast(gcsafe).}: bpCodeChanged(src)

proc bpSetProjectProcs*(names: seq[string]) =
  withControl(paletteId, BpPalette, p):
    if p.projectProcs != names:
      p.projectProcs = names
      p.rebuildPalette()

proc bpInsertApi*(e: ApiDoc) =
  ## Ajoute à la vue affichée un nœud pour une entrée de la référence.
  var it = PaletteItem(label: e.name, doc: e.signature)
  if e.isMethod:
    it.kind = nkMethod
    it.title = e.name
  elif e.signature.find({'(', '{'}) < 0:
    it.kind = nkVar
    it.title = e.signature
  else:
    it.kind = nkCall
    it.title = if e.owner.len > 0: e.owner & "." & e.name else: e.name
    it.brace = e.signature.find('{') >= 0 and (e.signature.find('(') < 0 or e.signature.find('{') < e.signature.find('('))
  withControl(canvasId, BpCanvas, c): c.addItem(it)

proc bpShowLine*(bpUid, line: int) =
  ## Sélectionne et montre le nœud de l'instruction de la ligne `line` (0-based).
  withControl(canvasId, BpCanvas, c):
    let doc = c.docs.getOrDefault(bpUid)
    if doc != nil:
      if doc.laidOut and doc.fitted and c.rect.w > 0: c.showLineNow(doc, line)
      else: doc.pendingLine = line          # montrée après la première mise en page

# ---------------------------------------------------------------------------
# panneau des détails

type NodeInfo = object
  ok: bool
  count: int
  id: int
  kind: NodeKind
  title, text, mode, header: string
  stmt, isMain, elseIf: bool
  pins: seq[tuple[pid: int, label, default: string, linked, optional: bool]]
  variadic: bool
  line: int

proc selectedInfo(): NodeInfo =
  readControl(canvasId, BpCanvas, c):
    let doc = c.curDoc
    if doc == nil: return
    result.count = doc.sel.len
    if doc.sel.len != 1: return
    var id = -1
    for x in doc.sel: id = x
    let n = doc.g.node(id)
    if n == nil: return
    result.ok = true
    result.id = n.id
    result.kind = n.kind
    result.title = n.title
    result.text = n.text
    result.mode = n.mode
    result.stmt = n.stmt
    result.elseIf = n.elseIf
    result.header = n.headerTitle
    result.line = n.line
    result.isMain = n.id == doc.g.mainId or (n.kind == nkEntry and n.mode == "suite")
    for p in n.pins:
      if p.dir == pdIn and p.kind == pkData:
        result.pins.add (p.pid, p.name, p.default, doc.g.isLinkedIn(n, p.pid), p.optional)
    result.variadic = n.kind in {nkPrint, nkCase, nkCall, nkMethod}

proc addDetail(label: string, ctl: Control, action: string, height = 0.0) =
  let row = newContainer(lkVertical, 0, 2)
  row.fixedWidth = DetailsW - 26
  if label.len > 0:
    let l = newLabel(label)
    discard row.addChild(l)
  if height > 0:
    ctl.fixedHeight = height
    multilineIds.add ctl.id
  discard row.addChild(ctl)
  discard addChild(detailsId, row)
  if action.len > 0: detailRows.add (ctl.id, action)

proc addButtons(buttons: openArray[(string, string)]) =
  let row = newSupercontrol(lkFlow, 6)
  row.fixedWidth = DetailsW - 26
  for (caption, action) in buttons:
    let b = newButton(caption)
    discard row.addChild(b)
    detailRows.add (b.id, action)
  discard addChild(detailsId, row)

var docView: MarkdownView
  ## Vue Markdown unique du panneau des détails, réutilisée à chaque reconstruction
  ## (chaque nouvelle vue ouvrirait ses propres polices).

proc showDoc(md: string, height: float) =
  guarded:
    if docView == nil: docView = newMarkdownView(md)
    else: docView.setValueText(md)
    docView.fixedHeight = height
    docView.fixedWidth = DetailsW - 26
  discard addChild(detailsId, docView)

proc kindLabel(k: NodeKind): string =
  case k
  of nkEntry: "point d'entrée"
  of nkCall: "appel de fonction"
  of nkMethod: "appel de méthode"
  of nkVar: "variable"
  of nkOp: "opérateur"
  of nkUnary: "opérateur unaire"
  of nkExpr: "expression"
  of nkIndex: "index"
  of nkMember: "membre"
  of nkComment: "commentaire"
  of nkRaw: "code Lexis+ tel quel"
  else: "instruction « " & $k & " »"

proc rebuildDetailsLocked()

proc bpRebuildDetails*() =
  {.cast(gcsafe).}:
    withLock detailsLock: rebuildDetailsLocked()

proc rebuildDetailsLocked() =
  let info = selectedInfo()
  for id in children(detailsId): deleteControl(id)
  detailRows.setLen(0)
  multilineIds.setLen(0)
  pendingValues.clear()
  detailsNode = if info.ok: info.id else: -1
  let theme = theme(windowOf(detailsId))
  if not info.ok:
    let title = newLabel(if info.count > 1: $info.count & " nœuds sélectionnés" else: "DÉTAILS")
    title.style.text = some(theme.accent)
    discard addChild(detailsId, title)
    if info.count > 1:
      addButtons([("Supprimer", "delete"), ("Dupliquer", "duplicate")])
    else:
      showDoc("""Sélectionnez un **nœud** pour modifier ses propriétés.

- **Glisser** un élément de la palette sur le graphe, ou le **cliquer** pour l'ajouter après le nœud sélectionné.
- **Relier** : glisser d'une broche à une autre (blanc : exécution, couleurs : données).
- Une valeur saisie dans la **case** d'une entrée tient lieu de lien (double-clic pour l'éditer ici).
- **Alt+clic** sur une broche : rompre ses liens.
- **Clic droit** : menu ; glisser avec le clic droit : déplacer la vue.
- **Ctrl+molette** : zoom ; **F** : tout voir ; **Suppr** ; **Ctrl+Z / Ctrl+Y**.
- Chaque modification réécrit le code de l'onglet à pastille rouge.""", 380)
    return
  let title = newLabel(info.header)
  title.style.text = some(theme.accent)
  discard addChild(detailsId, title)
  discard addChild(detailsId, newLabel(kindLabel(info.kind) & (if info.line >= 0: "  ·  ligne " & $(info.line + 1) else: "")))
  case info.kind
  of nkEntry:
    if not info.isMain:
      addDetail("Nom", newEdit(info.title), "title")
      addDetail("Paramètres (séparés par des virgules)", newEdit(info.text), "params")
      addDetail("Genre", newComboBox(["procedure", "fonction"], (if info.mode == "fonction": 1 else: 0)), "mode")
  of nkComment:
    addDetail("Texte", newEdit(info.text, multiline = true), "text", 150)
    addButtons([("Appliquer", "apply:text")])
  of nkRaw:
    addDetail("Code Lexis+", newEdit(info.text, multiline = true), "text", 170)
    addButtons([("Appliquer", "apply:text")])
  of nkPrint:
    addDetail("Affichage", newComboBox(["? (avec fin de ligne)", "?? (sans fin de ligne)"],
                                        (if info.mode == "??": 1 else: 0)), "mode")
  of nkAssign:
    addDetail("Cible (variable, objet.propriété, t[i])", newEdit(info.text), "text")
    addDetail("Opération", newComboBox(["=", "+=", "-="], max(0, ["=", "+=", "-="].find(info.mode))), "mode")
  of nkLocal:
    addDetail("Nom", newEdit(info.text), "text")
    addDetail("Portée", newComboBox(["locale", "globale"], (if info.mode == "globale": 1 else: 0)), "mode")
  of nkFor: addDetail("Variable", newEdit(info.text), "forvar")
  of nkForEach: addDetail("Variables ([clef,] valeur)", newEdit(info.text), "names")
  of nkTry: addDetail("Variable d'erreur (capturer)", newEdit(info.text), "tryvar")
  of nkWhile:
    addDetail("Forme", newComboBox(["tantque", "faire tantque"], (if info.mode == "faire tantque": 1 else: 0)), "mode")
  of nkCall, nkMethod:
    addDetail((if info.kind == nkCall: "Fonction ou procédure" else: "Méthode"), newEdit(info.title), "title")
    discard addChild(detailsId, newLabel(""))
    let cb = newCheckBox("Instruction (appel seul, sans résultat)", info.stmt)
    addDetail("", cb, "stmt")
    let s = summaryFor(info.title, info.kind == nkMethod)
    if s.len > 0:
      showDoc(s.replace("*", "\\*"), 110)
  of nkVar: addDetail("Nom (ou chemin a.b)", newEdit(info.title), "title")
  of nkMember: addDetail("Membre", newEdit(info.title), "title")
  of nkExpr: addDetail("Expression Lexis+", newEdit(info.text, multiline = true), "text", 90)
  of nkOp:
    let ops = ["+", "-", "*", "/", "%", "^", "..", "=", "==", "<>", "!=", "#", "<", "<=", ">", ">=", "$", "et", "ou"]
    addDetail("Opérateur", newComboBox(ops, max(0, ops.find(info.title.toLowerAscii))), "op")
  of nkUnary:
    let ops = ["non", "-", "#"]
    addDetail("Opérateur", newComboBox(ops, max(0, ops.find(info.title.toLowerAscii))), "op")
  else: discard
  if info.pins.len > 0:
    let l = newLabel("ENTRÉES  (valeurs Lexis+ : 12, \"texte\", vrai, {…}, @PROC)")
    l.style.text = some(theme.textSecondary)
    discard addChild(detailsId, l)
    for p in info.pins:
      if p.linked:
        addDetail(p.label, newLabel("   ← relié"), "")
      else:
        addDetail(p.label & (if p.optional: " (facultatif)" else: ""), newEdit(p.default), "pin:" & $p.pid)
  if info.variadic:
    addButtons([("+ entrée", "addpin"), ("− entrée", "delpin")])
  var btns: seq[(string, string)]
  if info.line >= 0: btns.add ("Voir dans le code", "goto")
  if not info.isMain: btns.add ("Supprimer", "delete")
  if btns.len > 0: addButtons(btns)

proc isIdentLike(s: string, dotted = false): bool =
  if s.len == 0: return false
  for i, ch in s:
    if ch in {'a'..'z', 'A'..'Z', '_'} or ord(ch) >= 128: continue
    if ch in {'0'..'9'} and i > 0: continue
    if dotted and ch == '.' and i > 0 and i < s.high: continue
    return false
  true

proc applyDetail(action, value: string) =
  ## Applique la valeur d'un champ des détails au nœud affiché.
  var msg = ""
  var structural = false
  var changed = false
  withControl(canvasId, BpCanvas, c):
    let doc = c.curDoc
    if doc == nil: return
    let n = doc.g.node(detailsNode)
    if n == nil: return
    let g = doc.g
    let v = value.strip
    template change(body: untyped) =
      doc.mutate()
      body
      n.dirty = true
      changed = true
    if action.startsWith("pin:"):
      let pid = parseInt(action[4 .. ^1])
      let i = n.pinIndex(pid)
      if i >= 0 and n.pins[i].default != v:
        if v.len > 0 and not isExpression(v): msg = "« " & v & " » n'est pas une expression Lexis+ valide"
        else: change: n.pins[i].default = v
    else:
      case action
      of "title":
        let dotted = n.kind in {nkCall, nkVar}
        if v == n.title: discard
        elif n.kind == nkEntry and not isIdentLike(v): msg = "Nom de procédure invalide"
        elif n.kind != nkEntry and not isIdentLike(v, dotted): msg = "Nom invalide"
        else: change: n.title = v
      of "params":
        var ok = true
        for p in splitNames(v):
          if not isIdentLike(p): ok = false
        if not ok: msg = "Paramètres : noms séparés par des virgules"
        elif v != n.text:
          change: g.setEntryParams(n, v)
          structural = true
      of "mode":
        let m = case n.kind
          of nkEntry: (if value == "2": "fonction" else: "procedure")
          of nkPrint: (if value == "2": "??" else: "?")
          of nkAssign: ["=", "+=", "-="][clamp(parseInt(value) - 1, 0, 2)]
          of nkLocal: (if value == "2": "globale" else: "locale")
          of nkWhile: (if value == "2": "faire tantque" else: "tantque")
          else: n.mode
        if m != n.mode: change: n.mode = m
      of "op":
        let ops = if n.kind == nkOp: @["+", "-", "*", "/", "%", "^", "..", "=", "==", "<>", "!=", "#", "<", "<=", ">",
                                       ">=", "$", "et", "ou"]
                  else: @["non", "-", "#"]
        let o = ops[clamp(parseInt(value) - 1, 0, ops.high)]
        if o != n.title: change: n.title = o
      of "text":
        let raw = value.strip(leading = false)
        if raw == n.text: discard
        elif n.kind == nkExpr and not isExpression(raw): msg = "Expression Lexis+ invalide"
        elif n.kind in {nkAssign, nkLocal} and v.len == 0: msg = "Nom attendu"
        else: change: n.text = (if n.kind in {nkComment, nkRaw, nkExpr}: raw else: v)
      of "forvar":
        if not isIdentLike(v): msg = "Nom de variable invalide"
        elif v != n.text:
          change:
            n.text = v
            g.setVarOuts(n, @[v])
      of "names":
        let ns = splitNames(v)
        var ok = ns.len in 1 .. 2
        for x in ns:
          if not isIdentLike(x): ok = false
        if not ok: msg = "Une ou deux variables : valeur, ou clef, valeur"
        elif ns.join(", ") != n.text:
          change:
            n.text = ns.join(", ")
            g.setVarOuts(n, ns)
          structural = true
      of "tryvar":
        if v.len > 0 and not isIdentLike(v): msg = "Nom de variable invalide"
        elif v != n.text:
          change:
            n.text = v
            g.setVarOuts(n, (if v.len > 0: @[v] else: @[]))
          structural = true
      of "stmt":
        let on = value == "1"
        if on != n.stmt:
          change: g.setStatement(n, on)
          structural = true
      of "addpin":
        change:
          case n.kind
          of nkPrint: n.addPin("valeur " & $(n.dataInputs.len + 1), pdIn, pkData)
          of nkCase:
            let k = n.dataInputs.len + 1
            n.addPin("cas " & $k, pdIn, pkData)
            inc n.nextPid
            var at = n.pins.len
            for i, p in n.pins:
              if p.dir == pdOut and p.name == "autrement": at = i
            n.pins.insert(Pin(pid: n.nextPid, name: "cas " & $k, dir: pdOut, kind: pkExec), at)
          of nkCall, nkMethod: n.addPin("arg " & $(n.dataInputs.len + (if n.kind == nkMethod: 0 else: 1)), pdIn, pkData,
                                        optional = true)
          else: discard
        structural = true
      of "delpin":
        let ins = n.dataInputs
        if ins.len > (if n.kind in {nkMethod, nkCase}: 1 else: 0):
          change:
            if n.kind == nkCase:
              let name = n.pins[n.pinIndex(ins[^1])].name
              g.removePin(n, ins[^1])
              let o = n.findPin(pdOut, pkExec, name)
              if o >= 0: g.removePin(n, o)
            else: g.removePin(n, ins[^1])
          structural = true
      else: discard
    if changed: g.measure(n, c.measurer)
  if msg.len > 0: status(msg)
  if changed:
    bpSync()
    if structural: bpRebuildDetails()

proc detailAction(id: ControlId): string =
  for r in detailRows:
    if r.id == id: return r.action

proc toolCommand(cmd: string) =
  var src = -1
  var resync = false
  var reload = false
  withControl(canvasId, BpCanvas, c):
    let doc = c.curDoc
    if doc == nil: return
    src = doc.srcUid
    case cmd
    of "undo": resync = doc.undoDoc()
    of "redo": resync = doc.redoDoc()
    of "delete":
      if doc.sel.len > 0 and doc.g.error.len == 0:
        c.deleteSelection()
    of "layout": c.relayout()
    of "foldall": doc.foldAll(true)
    of "unfoldall": doc.foldAll(false)
    of "calls": c.showCalls = not c.showCalls
    of "fit": c.fitView(doc)
    of "zoomin": c.zoomAt(doc, 1.25, c.rect.x + c.rect.w / 2, c.rect.y + c.rect.h / 2)
    of "zoomout": c.zoomAt(doc, 1 / 1.25, c.rect.x + c.rect.w / 2, c.rect.y + c.rect.h / 2)
    of "reload": reload = true
    else: discard
  case cmd
  of "code":
    if src >= 0: editorActivate(editorId, src)
  of "reload":
    if src >= 0:
      var bp = -1
      readControl(canvasId, BpCanvas, c): bp = c.cur
      bpOpen(bp, src, editorText(editorId, src), editorInfo(editorId, src).version, force = true)
      status("Vue blueprint relue depuis le code")
  else: discard
  if resync:
    bpSync()
    bpRebuildDetails()

proc bpHandleEvent*(ev: var Event): bool =
  ## Événements de la vue blueprint ; vrai si l'événement a été traité.
  if ev.id == canvasId:
    case ev.kind
    of evChange:
      bpSync()
      bpRebuildDetails()
    of evSelection:
      let t = ev.text
      if t == "bp:sel": bpRebuildDetails()
      elif t.startsWith("bp:goto:"):
        let line = try: parseInt(t[8 .. ^1]) except ValueError: -1
        var src = -1
        readControl(canvasId, BpCanvas, c):
          let doc = c.curDoc
          if doc != nil: src = doc.srcUid
        if line >= 0 and src >= 0 and bpGotoLine != nil:
          {.cast(gcsafe).}: bpGotoLine(src, line)
      elif t.startsWith("bp:open:"):
        if bpOpenEntity != nil:
          {.cast(gcsafe).}: bpOpenEntity(t[8 .. ^1])
      elif t.startsWith("bp:edit:"):
        let parts = t[8 .. ^1].split(':')
        if parts.len == 2:
          let pid = try: parseInt(parts[1]) except ValueError: 0
          let want = if pid > 0: "pin:" & $pid else: "text"
          for r in detailRows:
            if r.action == want or (pid == 0 and r.action == "title"):
              setFocus(r.id)
              break
      elif t.startsWith("cmd:"):
        if bpCommand != nil:
          {.cast(gcsafe).}: bpCommand(t)
    else: discard
    return true
  if ev.id == searchId:
    if ev.kind == evChange:
      let v = searchId.value
      withControl(paletteId, BpPalette, p):
        p.filter = v
        p.scroll = 0
    return true
  if ev.id == paletteId: return true
  for t in toolIds:
    if t.id == ev.id:
      if ev.kind == evClick: toolCommand(t.cmd)
      return true
  let action = detailAction(ev.id)
  if action.len == 0: return false
  case ev.kind
  of evClick:
    case action
    of "delete": toolCommand("delete")
    of "duplicate":
      withControl(canvasId, BpCanvas, c): c.duplicateSelection()
    of "goto":
      var line = -1
      var src = -1
      readControl(canvasId, BpCanvas, c):
        let doc = c.curDoc
        if doc != nil:
          src = doc.srcUid
          let n = doc.g.node(detailsNode)
          if n != nil: line = n.line
      if line >= 0 and src >= 0 and bpGotoLine != nil:
        {.cast(gcsafe).}: bpGotoLine(src, line)
    of "addpin", "delpin": applyDetail(action, "")
    else:
      if action.startsWith("apply:"):
        let target = action[6 .. ^1]
        for r in detailRows:
          if r.action == target: applyDetail(target, r.id.value)
  of evChange:
    case action
    of "stmt": applyDetail(action, ev.id.value)
    else: pendingValues[action] = ev.id.value
  of evSelection:
    if action in ["mode", "op"]: applyDetail(action, $listSelect(ev.id))
  of evKeyDown:
    if int(ev.key) in [0x0D, 0x40000058] and ev.id notin multilineIds:
      applyDetail(action, ev.id.value)
  of evFocusLost:
    if action in pendingValues: applyDetail(action, pendingValues[action])
  else: discard
  true


method dispose*(c: BpCanvas) =
  ## Polices (quelques tailles) et textes rendus.
  when defined(sdlttf):
    for f in c.fonts.values:
      if f != nil: TTF_CloseFont(f)
    c.fonts.clear()
    for v in c.texCache.values: SDL_DestroyTexture(v.tex)
    c.texCache.clear()
  c.widths.clear()
  c.fits.clear()
