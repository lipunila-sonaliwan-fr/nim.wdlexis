# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - concepteur de formulaires (adapté du concepteur d'ednim).
#
# * Palette (à gauche) : glisser une disposition ou un contrôle sur le formulaire
#   (ou cliquer pour l'ajouter à la fin du conteneur sélectionné). Les contrôles
#   personnalisés (fonctions Lexis+ du projet qui renvoient un contrôle) viennent
#   du fichier wdlexis_palette.json du projet (« Contrôle personnalisé… »).
# * Canevas (au centre) : aperçu réel construit avec les contrôles de wdgui, tels
#   que les crée le paquet interface. Clic pour sélectionner, glisser pour
#   déplacer (réordonner / changer de conteneur, position libre dans une
#   disposition absolue), poignées pour redimensionner. Les repères magenta
#   s'alignent sur les bords et centres des autres contrôles, sur leurs largeurs
#   / hauteurs et sur les proportions du conteneur (¼, ⅓, ½, ⅔, ¾, tout).
# * Hiérarchie (à droite, en haut) : l'arbre du formulaire ; Monter / Descendre
#   changent l'ordre, Sortir fait sortir un contrôle de son conteneur.
# * Inspecteur (à droite) : chaque propriété se modifie directement ; la section
#   Événements associe une procédure existante, retire une association ou crée
#   une nouvelle procédure dans le code édité.
# * Chaque modification régénère form_<nom>.prg.
import std/[strutils, os, math, options, locks]
from std/unicode import toUpper
import ../wdgui
import formmodel, codeeditor

type
  DragMode = enum
    dmNone, dmMove, dmResize, dmNew
  Guide = tuple[x1, y1, x2, y2: float]

  FormCanvas* = ref object of Container
    model*: FormModel
    selected*: DNode
    hoverNode: DNode
    formRoot: Container
    links: seq[tuple[ctl: Control, node: DNode]]
    drag: DragMode
    handle: int
    startX, startY: float
    startRect: Rect
    moved: bool
    newKind: string
    ghost: Rect
    dropParent: DNode
    dropIndex: int
    dropDock: string
    dropPos: Point
    dropMark: Rect
    dropValid: bool
    guides: seq[Guide]
    sizeLabel: string

  PaletteView* = ref object of Control
    canvas*: FormCanvas
    hoverIdx, pressIdx: int
    pressX, pressY: float
    dragging: bool
    scroll: float

const
  originX = 40.0
  originY = 66.0
  titleH = 28.0
  snapDist = 6.0
  guideColor = Color(r: 255, g: 45, b: 149, a: 255)
  selColor = Color(r: 59, g: 130, b: 246, a: 255)

# lecture des propriétés (aperçu)

proc pf(n: DNode, k: string): float =
  try: result = parseFloat(n.getProp(k).strip.replace(',', '.'))
  except ValueError: result = 0

proc pi(n: DNode, k: string): int = int(round(n.pf(k)))

proc pb(n: DNode, k: string): bool = isTrue(n.getProp(k))

proc plist(n: DNode, k: string): seq[string] = listOf(n.getProp(k))

proc layoutOf(s: string): LayoutKind =
  case s
  of "horizontal": lkHorizontal
  of "grille": lkGrid
  of "flux": lkFlow
  of "bordure": lkBorder
  of "pile": lkStack
  of "absolue": lkAbsolute
  else: lkVertical

proc alignOf(s: string): Alignment =
  case s
  of "centre": alCenter
  of "droite": alRight
  else: alLeft

proc chartOf(s: string): ChartKind =
  case s
  of "lignes": ckLine
  of "aires": ckArea
  of "secteurs": ckPie
  else: ckColumn

proc scrollbarsOf(s: string): ScrollbarMode =
  case s
  of "automatique": smAutomatic
  of "masque": smHidden
  else: smAlways

proc dockOf(s: string): Dock =
  case s
  of "haut": dkTop
  of "bas": dkBottom
  of "gauche": dkLeft
  of "droite": dkRight
  else: dkCenter

proc validColor*(s: string): bool =
  let h = s.strip
  h.startsWith("#") and h.len in [7, 9] and h[1 .. ^1].allCharsInSet(HexDigits)

proc nodeLayout(n: DNode): string =
  case baseOf(n.kind)
  of "onglets": "tab"
  of "separateur": "splitter"
  else: (if n.kind == "fenetre" or isContainerKind(n.kind): n.getProp("disposition") else: "")

# construction de l'aperçu (mêmes constructeurs que le paquet interface)

proc makeControl(n: DNode): Control =
  case baseOf(n.kind)
  of "conteneur": result = newContainer(layoutOf(n.getProp("disposition")), columns = max(1, n.pi("colonnes")))
  of "cadre": result = newCell(layoutOf(n.getProp("disposition")), n.getProp("titre"), max(1, n.pi("colonnes")))
  of "panneau": result = newPanel(layoutOf(n.getProp("disposition")), scrollbarsOf(n.getProp("defilement")),
                                  columns = max(1, n.pi("colonnes")))
  of "separateur": result = newSplitter(n.pb("vertical"), n.pf("position"))
  of "onglets": result = newTab()
  of "etiquette": result = newLabel(n.getProp("libelle"), alignOf(n.getProp("alignement")))
  of "bouton": result = newButton(n.getProp("libelle"), isDefault = n.pb("defaut"), isCancel = n.pb("annuler"))
  of "saisie":
    if n.pb("multiligne"): result = newEdit(n.getProp("texte"), multiline = true)
    else: result = newEdit(n.getProp("texte"), placeholder = n.getProp("indication"))
  of "cases":
    var o = n.plist("options")
    if o.len == 0: o = @[""]
    result = newCheckBox(o)
  of "radio": result = newRadioButton(n.plist("options"), max(0, n.pi("selection") - 1))
  of "combo": result = newComboBox(n.plist("elements"), max(0, n.pi("selection") - 1))
  of "liste": result = newListBox(n.plist("elements"), n.pb("multi"))
  of "compteur": result = newSpin(n.pf("valeur"), n.pf("min"), n.pf("max"))
  of "curseur": result = newSlider(n.pf("valeur"), n.pf("min"), n.pf("max"))
  of "plage": result = newRangeSlider(n.pf("basse"), n.pf("haute"), n.pf("min"), n.pf("max"))
  of "jauge": result = newProgressBar(n.pf("valeur"), n.pf("min"), n.pf("max"))
  of "notation": result = newRating(n.pf("valeur"))
  of "ascenseur": result = newScrollbar(true, n.pf("min"), n.pf("max"))
  of "image": result = newImage(n.getProp("chemin"))
  of "codebarre": result = newBarCode(n.getProp("texte"))
  of "calendrier": result = newCalendar(n.getProp("date"))
  of "graphe": result = newChart(chartOf(n.getProp("genre")), n.getProp("titre"))
  of "arbre":
    let t = newTreeView()
    result = t
    for p in n.plist("noeuds"):
      let parts = p.split('/')
      var path = ""
      for i, part in parts:
        path = if i == 0: part.strip else: path & $TreeSep & part.strip
        if t.findPath(path) == nil:
          let nd = t.addPath(path)
          if nd != nil: nd.expanded = true
  of "tableau":
    let t = newTable(multiSelection = false)
    for c in n.plist("colonnes"): t.addColumn(c)
    result = t
  of "grille":
    let g = newGrid(multiSelection = n.pb("multi"), editable = n.pb("modifiable"))
    for c in n.plist("colonnes"):
      let parts = c.split(':')
      discard g.addColumn(parts[0].strip, (if parts.len > 1: parts[1].strip else: parts[0].strip))
    result = g
  of "kanban":
    let k = newKanban()
    for l in n.plist("listes"): k.lists.add KanbanList(title: l)
    result = k
  of "mosaique": result = newTreeMap()
  of "gantt": result = newGantt()
  of "markdown": result = newMarkdownView(n.getProp("texte"))
  of "barremenu":
    let m = newMenuBar()
    for p in n.plist("menus"): m.addMenuPath(p.replace("/", $TreeSep))
    result = m
  else: result = newLabel(n.kind)
  if baseOf(n.kind) == "compteur" and n.pf("max") == 0 and n.pf("min") == 0: discard

proc applyCommon(ctl: Control, n: DNode, parentAbsolute: bool) =
  ctl.focusable = false                         # l'aperçu ne prend jamais le focus
  case n.getProp("etat")
  of "grise": ctl.state = csGrayed
  of "lecture": ctl.state = csReadOnly
  else: discard
  if n.pf("largeurfixe") > 0: ctl.fixedWidth = n.pf("largeurfixe")
  if n.pf("hauteurfixe") > 0: ctl.fixedHeight = n.pf("hauteurfixe")
  if parentAbsolute:
    ctl.fixedX = n.pf("x")
    ctl.fixedY = n.pf("y")
  if n.pf("poids") > 0: ctl.weight = n.pf("poids")
  if n.getProp("etirer").len > 0: ctl.stretch = n.pb("etirer")
  if n.getProp("ancrage").len > 0: ctl.dock = dockOf(n.getProp("ancrage"))
  if validColor(n.getProp("couleur")): ctl.style.text = some(hex(n.getProp("couleur")))
  if validColor(n.getProp("fond")): ctl.style.background = some(hex(n.getProp("fond")))
  if ctl of Container and baseOf(n.kind) notin ["separateur", "onglets"]:
    let k = Container(ctl)
    if n.pf("marge") >= 0 and n.getProp("marge").len > 0: k.margin = n.pf("marge")
    if n.pf("espacement") >= 0 and n.getProp("espacement").len > 0: k.spacing = n.pf("espacement")

proc buildChildren(c: FormCanvas, parentCtl: Control, parentNode: DNode) =
  let absolute = nodeLayout(parentNode) == "absolue"
  for ch in parentNode.children:
    var ctl: Control
    if baseOf(ch.kind) == "page":
      if not (parentCtl of Tab): continue
      ctl = Tab(parentCtl).addPage(ch.getProp("titre"), layoutOf(ch.getProp("disposition")), max(1, ch.pi("colonnes")))
    else:
      if not (parentCtl of Container): continue
      if parentCtl of Tab: continue                   # un onglet ne contient que des pages
      ctl = makeControl(ch)
      discard Container(parentCtl).addChild(ctl)
    applyCommon(ctl, ch, absolute)
    c.links.add((ctl, ch))
    if isContainerKind(ch.kind): c.buildChildren(ctl, ch)

proc ctlOf(c: FormCanvas, n: DNode): Control =
  for l in c.links:
    if l.node == n: return l.ctl

proc rebuild*(c: FormCanvas) =
  # Reconstruit l'aperçu depuis le modèle (après tout changement de structure).
  var activePages: seq[tuple[node: DNode, page: int]]
  for l in c.links:
    if l.ctl of Tab: activePages.add((l.node, Tab(l.ctl).activePage))
  c.children.setLen(0)
  c.links.setLen(0)
  let r = c.model.root
  let root = newContainer(layoutOf(r.getProp("disposition")))
  discard c.addChild(root)
  c.formRoot = root
  c.links.add((Control(root), r))
  c.buildChildren(root, r)
  for ap in activePages:                                # garde la page affichée de chaque onglet
    let t = c.ctlOf(ap.node)
    if t != nil and t of Tab and ap.page >= 0: t.setValueText($(ap.page + 1))
  if c.selected != nil and c.selected notin c.model.allNodes: c.selected = nil
  markDirty(c)

proc newFormCanvas*(model: FormModel): FormCanvas =
  result = FormCanvas(model: model, layout: lkAbsolute, margin: 0, spacing: 0, dropIndex: -1)
  initControl(result)
  result.focusable = true
  result.rebuild()

# géométrie et recherche

proc windowRect(c: FormCanvas): Rect =
  let r = c.model.root
  rect(c.rect.x + originX, c.rect.y + originY, float(max(120, r.pi("largeur"))), float(max(80, r.pi("hauteur"))))

proc rectOf(c: FormCanvas, n: DNode): Rect =
  if n == c.model.root: return c.windowRect
  let ctl = c.ctlOf(n)
  if ctl != nil: ctl.rect else: rect(0, 0, 0, 0)

proc contentOf(c: FormCanvas, n: DNode): Rect =
  let ctl = c.ctlOf(n)
  if ctl == nil or c.win == nil: return c.rectOf(n)
  if ctl of Container: Container(ctl).contentArea(c.win.theme) else: ctl.rect

method preferredSize*(c: FormCanvas, d: Drawing, t: Theme): tuple[w, h: float] =
  let r = c.model.root
  (float(r.pi("largeur")) + originX * 2 + 40, float(r.pi("hauteur")) + originY + 60)

method layoutChildren*(c: FormCanvas, d: Drawing, t: Theme) =
  if c.formRoot != nil: layoutControl(c.formRoot, c.windowRect, d, t)

method hitChildren*(c: FormCanvas, x, y: float): bool = false    # le canevas gère tous les clics

proc nodeAt(c: FormCanvas, x, y: float): DNode =
  if c.formRoot == nil: return nil
  let wr = c.windowRect
  if rect(wr.x, wr.y - titleH, wr.w, titleH).containsPoint(x, y): return c.model.root
  var ctl = controlAt(c.formRoot, x, y)
  while ctl != nil:
    for l in c.links:
      if l.ctl == ctl: return l.node
    ctl = ctl.parent
  nil

proc containerNodeAt(c: FormCanvas, x, y: float, exclude: DNode, forPage: bool): DNode =
  var n = c.nodeAt(x, y)
  while n != nil:
    if exclude != nil and isAncestor(exclude, n):
      n = n.parent
      continue
    let base = baseOf(n.kind)
    if forPage:
      if base == "onglets": return n
    elif n.kind == "fenetre" or isContainerKind(n.kind):
      if base == "onglets":                               # les contrôles vont dans la page affichée
        let tctl = c.ctlOf(n)
        if tctl != nil and tctl of Tab:
          let ap = Tab(tctl).activePage
          if ap >= 0 and ap < n.children.len: return n.children[ap]
      else:
        return n
    n = n.parent
  nil

proc handleRects(r: Rect): array[8, Rect] =
  let s = 7.0
  let xs = [r.x, r.x + r.w / 2, r.x + r.w]
  let ys = [r.y, r.y + r.h / 2, r.y + r.h]
  let order = [(0, 0), (1, 0), (2, 0), (2, 1), (2, 2), (1, 2), (0, 2), (0, 1)]
  for i in 0 .. 7:
    let (ix, iy) = order[i]
    result[i] = rect(xs[ix] - s / 2, ys[iy] - s / 2, s, s)

proc handleAt(c: FormCanvas, x, y: float): int =
  if c.selected == nil: return -1
  let hs = handleRects(c.rectOf(c.selected))
  for i in countdown(7, 0):
    if hs[i].shrink(-3).containsPoint(x, y): return i
  -1

# cibles de dépôt

proc computeDrop(c: FormCanvas, kind: string, x, y: float, exclude: DNode) =
  c.dropValid = false
  let forPage = baseOf(kind) == "page"
  let target = c.containerNodeAt(x, y, exclude, forPage)
  if target == nil: return
  if not forPage and baseOf(target.kind) == "onglets": return
  let ca = c.contentOf(target)
  var kids: seq[DNode]
  for k in target.children:
    if k != exclude: kids.add k
  let layout = nodeLayout(target)
  if layout == "splitter" and kids.len >= 2: return
  c.dropParent = target
  c.dropValid = true
  c.dropDock = ""
  c.dropIndex = kids.len
  case layout
  of "absolue":
    c.dropPos = (x - ca.x, y - ca.y)
    c.dropMark = rect(0, 0, 0, 0)
  of "bordure":
    let fx = (x - ca.x) / max(1.0, ca.w)
    let fy = (y - ca.y) / max(1.0, ca.h)
    if fy < 0.25:
      c.dropDock = "haut"
      c.dropMark = rect(ca.x, ca.y, ca.w, ca.h * 0.25)
    elif fy > 0.75:
      c.dropDock = "bas"
      c.dropMark = rect(ca.x, ca.y + ca.h * 0.75, ca.w, ca.h * 0.25)
    elif fx < 0.25:
      c.dropDock = "gauche"
      c.dropMark = rect(ca.x, ca.y, ca.w * 0.25, ca.h)
    elif fx > 0.75:
      c.dropDock = "droite"
      c.dropMark = rect(ca.x + ca.w * 0.75, ca.y, ca.w * 0.25, ca.h)
    else:
      c.dropDock = "centre"
      c.dropMark = rect(ca.x + ca.w * 0.25, ca.y + ca.h * 0.25, ca.w * 0.5, ca.h * 0.5)
  of "tab", "pile":
    c.dropMark = ca
  else:
    let across = layout in ["horizontal", "flux"] or
                 (layout == "splitter" and target.pb("vertical"))
    for i, k in kids:
      let r = c.rectOf(k)
      let before = if across: x < r.x + r.w / 2
                   elif layout == "grille": y < r.y or (y < r.y + r.h and x < r.x + r.w / 2)
                   else: y < r.y + r.h / 2
      if before:
        c.dropIndex = i
        break
    if kids.len == 0:
      c.dropMark = rect(ca.x, ca.y, ca.w, 3)
    elif c.dropIndex < kids.len:
      let r = c.rectOf(kids[c.dropIndex])
      c.dropMark = if across: rect(r.x - 2, r.y, 3, r.h) else: rect(r.x, r.y - 2, r.w, 3)
    else:
      let r = c.rectOf(kids[^1])
      c.dropMark = if across: rect(r.x + r.w - 1, r.y, 3, r.h) else: rect(r.x, r.y + r.h - 1, r.w, 3)

# repères (magnétisme)

proc siblingsRects(c: FormCanvas, n: DNode): seq[tuple[node: DNode, r: Rect]] =
  if n.parent == nil: return
  for s in n.parent.children:
    if s != n: result.add((s, c.rectOf(s)))

proc snapMove(c: FormCanvas, n: DNode, r: var Rect) =
  # Aligne les bords / le centre du rectangle déplacé sur ceux des voisins et du conteneur.
  c.guides.setLen(0)
  let ca = c.contentOf(n.parent)
  var xs, ys: seq[tuple[v: float, a, b: float]]
  for v in [ca.x, ca.x + ca.w / 2, ca.x + ca.w]: xs.add((v, ca.y, ca.y + ca.h))
  for v in [ca.y, ca.y + ca.h / 2, ca.y + ca.h]: ys.add((v, ca.x, ca.x + ca.w))
  for s in c.siblingsRects(n):
    for v in [s.r.x, s.r.x + s.r.w / 2, s.r.x + s.r.w]: xs.add((v, s.r.y, s.r.y + s.r.h))
    for v in [s.r.y, s.r.y + s.r.h / 2, s.r.y + s.r.h]: ys.add((v, s.r.x, s.r.x + s.r.w))
  var best = snapDist + 1
  var bestD = 0.0
  var bestG: Guide
  for e in [0.0, 0.5, 1.0]:
    let ex = r.x + r.w * e
    for cand in xs:
      let dd = cand.v - ex
      if abs(dd) < best:
        best = abs(dd)
        bestD = dd
        bestG = (cand.v, min(cand.a, r.y), cand.v, max(cand.b, r.y + r.h))
  if best <= snapDist:
    r.x += bestD
    c.guides.add bestG
  best = snapDist + 1
  for e in [0.0, 0.5, 1.0]:
    let ey = r.y + r.h * e
    for cand in ys:
      let dd = cand.v - ey
      if abs(dd) < best:
        best = abs(dd)
        bestD = dd
        bestG = (min(cand.a, r.x), cand.v, max(cand.b, r.x + r.w), cand.v)
  if best <= snapDist:
    r.y += bestD
    c.guides.add bestG

proc snapSize(c: FormCanvas, n: DNode, r: var Rect, horiz, vert, fromLeft, fromTop: bool) =
  # Ajuste la largeur / hauteur sur celle d'un voisin ou sur une proportion du conteneur.
  c.guides.setLen(0)
  c.sizeLabel = ""
  let ca = c.contentOf(n.parent)
  const fracs = [(0.25, "1/4"), (1.0 / 3, "1/3"), (0.5, "1/2"), (2.0 / 3, "2/3"), (0.75, "3/4"), (1.0, "tout")]
  var note = ""
  if horiz:
    var best = snapDist + 1
    var target = r.w
    var what = ""
    var other: Rect
    for s in c.siblingsRects(n):
      if abs(s.r.w - r.w) < best:
        best = abs(s.r.w - r.w)
        target = s.r.w
        what = "= " & s.node.name
        other = s.r
    for (f, label) in fracs:
      if abs(ca.w * f - r.w) < best:
        best = abs(ca.w * f - r.w)
        target = ca.w * f
        what = "largeur " & label
        other = rect(0, 0, 0, 0)
    if best <= snapDist:
      if fromLeft: r.x -= target - r.w
      r.w = target
      note.add " " & what
      c.guides.add((r.x, r.y + r.h + 6, r.x + r.w, r.y + r.h + 6))
      if other.w > 0: c.guides.add((other.x, other.y + other.h + 6, other.x + other.w, other.y + other.h + 6))
  if vert:
    var best = snapDist + 1
    var target = r.h
    var what = ""
    var other: Rect
    for s in c.siblingsRects(n):
      if abs(s.r.h - r.h) < best:
        best = abs(s.r.h - r.h)
        target = s.r.h
        what = "= " & s.node.name
        other = s.r
    for (f, label) in fracs:
      if abs(ca.h * f - r.h) < best:
        best = abs(ca.h * f - r.h)
        target = ca.h * f
        what = "hauteur " & label
        other = rect(0, 0, 0, 0)
    if best <= snapDist:
      if fromTop: r.y -= target - r.h
      r.h = target
      note.add " " & what
      c.guides.add((r.x + r.w + 6, r.y, r.x + r.w + 6, r.y + r.h))
      if other.w > 0: c.guides.add((other.x + other.w + 6, other.y, other.x + other.w + 6, other.y + other.h))
  c.sizeLabel = $int(round(r.w)) & " x " & $int(round(r.h)) & note

# modifications du modèle

proc select*(c: FormCanvas, n: DNode) =
  c.selected = n
  emit(c, evSelection, text = (if n != nil: n.name else: ""))

proc changed(c: FormCanvas) =
  emit(c, evChange)

proc fmtNum(f: float): string = $int(round(f))

proc dropNew*(c: FormCanvas, kind: string, x, y: float) =
  c.computeDrop(kind, x, y, nil)
  c.drag = dmNone
  if not c.dropValid: return
  let n = newNode(kind, c.model.uniqueName(kind))
  n.parent = c.dropParent
  let layout = nodeLayout(c.dropParent)
  if layout == "absolue":
    n.setProp("x", fmtNum(max(0.0, c.dropPos.x - 20)))
    n.setProp("y", fmtNum(max(0.0, c.dropPos.y - 12)))
    n.setProp("largeurfixe", (if isContainerKind(kind): "200" else: "120"))
    n.setProp("hauteurfixe", (if isContainerKind(kind): "120" else: "30"))
  if c.dropDock.len > 0: n.setProp("ancrage", c.dropDock)
  c.dropParent.children.insert(n, clamp(c.dropIndex, 0, c.dropParent.children.len))
  if baseOf(kind) == "onglets":                           # des onglets commencent avec une page
    let page = newNode("page", c.model.uniqueName("page"))
    page.parent = n
    page.setProp("titre", "Page 1")
    n.children.add page
  c.dropValid = false
  c.rebuild()
  c.select(n)
  c.changed()

proc deleteSelected*(c: FormCanvas) =
  let n = c.selected
  if n == nil or n == c.model.root or n.parent == nil: return
  let p = n.parent
  let i = p.children.find(n)
  if i >= 0: p.children.delete(i)
  c.rebuild()
  c.select(p)
  c.changed()

proc moveSelected*(c: FormCanvas, delta: int) =
  # Ordre d'affichage parmi les voisins (et superposition en disposition absolue).
  let n = c.selected
  if n == nil or n.parent == nil: return
  let sibs = n.parent.children
  let i = sibs.find(n)
  let j = i + delta
  if i < 0 or j < 0 or j >= sibs.len: return
  swap(n.parent.children[i], n.parent.children[j])
  c.rebuild()
  c.select(n)
  c.changed()

proc moveOut*(c: FormCanvas) =
  # Sort le contrôle sélectionné de son conteneur, juste après lui.
  let n = c.selected
  if n == nil or n.parent == nil or n.parent.parent == nil: return
  let p = n.parent
  var gp = p.parent
  var after = p
  if baseOf(gp.kind) == "onglets":                       # sortir d'une page : après les onglets
    if baseOf(n.kind) == "page": return
    after = gp
    gp = gp.parent
    if gp == nil: return
  if baseOf(n.kind) == "page": return
  p.children.delete(p.children.find(n))
  gp.children.insert(n, gp.children.find(after) + 1)
  n.parent = gp
  c.rebuild()
  c.select(n)
  c.changed()

proc finishMove(c: FormCanvas, x, y: float) =
  let n = c.selected
  c.computeDrop(n.kind, x, y, n)
  let sameAbsolute = c.dropValid and c.dropParent == n.parent and nodeLayout(n.parent) == "absolue"
  if not c.dropValid:
    c.rebuild()
    return
  if not sameAbsolute:
    let old = n.parent
    old.children.delete(old.children.find(n))
    c.dropParent.children.insert(n, clamp(c.dropIndex, 0, c.dropParent.children.len))
    n.parent = c.dropParent
    if nodeLayout(c.dropParent) == "absolue":
      n.setProp("x", fmtNum(max(0.0, c.ghost.x - c.contentOf(c.dropParent).x)))
      n.setProp("y", fmtNum(max(0.0, c.ghost.y - c.contentOf(c.dropParent).y)))
    if c.dropDock.len > 0: n.setProp("ancrage", c.dropDock)
  c.dropValid = false
  c.rebuild()
  c.select(n)
  c.changed()

# dessin

proc dashedLine(d: Drawing, x1, y1, x2, y2: float, c: Color) =
  let len = hypot(x2 - x1, y2 - y1)
  if len < 1: return
  var t = 0.0
  while t < len:
    let t2 = min(len, t + 4)
    d.line(x1 + (x2 - x1) * t / len, y1 + (y2 - y1) * t / len,
           x1 + (x2 - x1) * t2 / len, y1 + (y2 - y1) * t2 / len, c)
    t += 7

proc dashedRect(d: Drawing, r: Rect, c: Color) =
  d.dashedLine(r.x, r.y, r.x + r.w, r.y, c)
  d.dashedLine(r.x + r.w, r.y, r.x + r.w, r.y + r.h, c)
  d.dashedLine(r.x + r.w, r.y + r.h, r.x, r.y + r.h, c)
  d.dashedLine(r.x, r.y + r.h, r.x, r.y, c)

method draw*(c: FormCanvas, d: Drawing, t: Theme) =
  d.fillRect(c.rect, mix(t.windowBg, t.text, 0.06))
  var y = c.rect.y + 8
  while y < c.rect.y + c.rect.h:                          # fond pointillé
    var x = c.rect.x + 8
    while x < c.rect.x + c.rect.w:
      d.fillRect(rect(x, y, 1.5, 1.5), t.text.withAlpha(35))
      x += 16
    y += 16
  let wr = c.windowRect
  let frame = rect(wr.x, wr.y - titleH, wr.w, wr.h + titleH)
  d.shadow(frame, 10, t.shadow)
  d.fillRoundRect(frame, 10, t.border)
  d.fillRoundRect(frame.shrink(1), 9, t.header)
  d.fillRect(wr, t.windowBg)
  for i, col in [hex"#FF5F57", hex"#FEBC2E", hex"#28C840"]:
    d.fillCircle(wr.x + 16 + float(i) * 20, wr.y - titleH / 2, 6, col)
  d.textIn(rect(wr.x, wr.y - titleH, wr.w, titleH), c.model.root.getProp("titre"), t.textSecondary, alCenter)

method drawOverlay*(c: FormCanvas, d: Drawing, t: Theme) =
  let root = c.model.root
  # structure : contours pointillés des conteneurs.
  for l in c.links:
    if l.node != root and isContainerKind(l.node.kind):
      d.dashedRect(l.ctl.rect, t.textSecondary.withAlpha(110))
  if c.hoverNode != nil and c.hoverNode != c.selected and c.drag == dmNone:
    d.strokeRect(c.rectOf(c.hoverNode), selColor.withAlpha(110), 1)
  # indicateur de dépôt
  if c.dropValid:
    let pr = c.rectOf(c.dropParent)
    d.strokeRect(pr, selColor.withAlpha(160), 2)
    if c.dropMark.w > 0: d.fillRect(c.dropMark, selColor.withAlpha(if c.dropMark.h > 4 and c.dropMark.w > 4: 50 else: 230))
  # fantôme du contrôle déplacé / nouveau.
  if (c.drag == dmNew or (c.drag == dmMove and c.moved and c.dropValid)) and c.ghost.w > 0:
    d.fillRoundRect(c.ghost, 4, selColor.withAlpha(40))
    d.strokeRect(c.ghost, selColor.withAlpha(200), 1)
    if c.newKind.len > 0: d.textIn(c.ghost, c.newKind, selColor, alCenter)
  # sélection et poignées.
  if c.selected != nil:
    let r = c.rectOf(c.selected)
    d.strokeRect(r.shrink(-1), selColor, 2)
    let label = (if c.selected == root: "formulaire " else: c.selected.kind & "  ") & c.selected.name
    let lw = d.textWidth(label) + 14
    let lr = rect(r.x - 1, r.y - t.lineHeight - 2, lw, t.lineHeight)
    d.fillRoundRect(lr, 4, selColor)
    d.textIn(lr, label, White, alCenter)
    let hs = handleRects(r)
    for i, h in hs:
      if c.selected == root and i notin [3, 4, 5]: continue
      d.fillRect(h, White)
      d.strokeRect(h, selColor, 1)
  # repères
  for g in c.guides: d.dashedLine(g.x1, g.y1, g.x2, g.y2, guideColor)
  if c.sizeLabel.len > 0 and c.selected != nil:
    let r = c.rectOf(c.selected)
    let w = d.textWidth(c.sizeLabel) + 14
    let lr = rect(r.x + r.w / 2 - w / 2, r.y + r.h + 10, w, t.lineHeight)
    d.fillRoundRect(lr, 4, guideColor)
    d.textIn(lr, c.sizeLabel, White, alCenter)

# souris et clavier

method onMouse*(c: FormCanvas, e: MouseEvent) =
  case e.action
  of maPress:
    c.guides.setLen(0)
    c.sizeLabel = ""
    if e.button != mbLeft:
      c.select(c.nodeAt(e.x, e.y))
      return
    let h = c.handleAt(e.x, e.y)
    if h >= 0 and (c.selected != c.model.root or h in [3, 4, 5]):
      c.drag = dmResize
      c.handle = h
      c.startX = e.x
      c.startY = e.y
      c.startRect = c.rectOf(c.selected)
      return
    let n = c.nodeAt(e.x, e.y)
    # un clic sur l'en-tête d'onglets affiche la page (l'aperçu ne reçoit pas les clics).
    if n != nil and baseOf(n.kind) == "onglets":
      let tctl = c.ctlOf(n)
      if tctl != nil and tctl of Tab:
        let tb = Tab(tctl)
        let rs = tb.tabRects(c.win.drawing, c.win.theme)
        for i, hr in rs:
          if hr.containsPoint(e.x, e.y) and i < n.children.len:
            tb.setValueText($(i + 1))
            c.select(n.children[i])
            markDirty(c)
            return
    c.select(n)
    if n != nil and n != c.model.root:
      c.drag = dmMove
      c.startX = e.x
      c.startY = e.y
      c.startRect = c.rectOf(n)
      c.moved = false
  of maMove:
    case c.drag
    of dmResize:
      let n = c.selected
      var r = c.startRect
      let dx = e.x - c.startX
      let dy = e.y - c.startY
      let hh = c.handle
      let left = hh in [0, 6, 7]
      let top = hh in [0, 1, 2]
      let horiz = hh in [0, 2, 3, 4, 6, 7]
      let vert = hh in [0, 1, 2, 4, 5, 6]
      if left:
        r.x += dx
        r.w -= dx
      elif horiz: r.w += dx
      if top:
        r.y += dy
        r.h -= dy
      elif vert: r.h += dy
      r.w = max(12.0, r.w)
      r.h = max(8.0, r.h)
      if n == c.model.root:
        n.setProp("largeur", fmtNum(r.w))
        n.setProp("hauteur", fmtNum(r.h))
        c.sizeLabel = fmtNum(r.w) & " x " & fmtNum(r.h)
      else:
        c.snapSize(n, r, horiz, vert, left, top)
        let ctl = c.ctlOf(n)
        if horiz:
          n.setProp("largeurfixe", fmtNum(r.w))
          if ctl != nil: ctl.fixedWidth = round(r.w)
        if vert:
          n.setProp("hauteurfixe", fmtNum(r.h))
          if ctl != nil: ctl.fixedHeight = round(r.h)
        if nodeLayout(n.parent) == "absolue" and (left or top):
          let ca = c.contentOf(n.parent)
          n.setProp("x", fmtNum(r.x - ca.x))
          n.setProp("y", fmtNum(r.y - ca.y))
          if ctl != nil:
            ctl.fixedX = round(r.x - ca.x)
            ctl.fixedY = round(r.y - ca.y)
    of dmMove:
      let dx = e.x - c.startX
      let dy = e.y - c.startY
      if not c.moved and abs(dx) + abs(dy) < 4: return
      c.moved = true
      let n = c.selected
      var r = rect(c.startRect.x + dx, c.startRect.y + dy, c.startRect.w, c.startRect.h)
      let under = c.containerNodeAt(e.x, e.y, n, baseOf(n.kind) == "page")
      if under == n.parent and nodeLayout(n.parent) == "absolue":
        c.snapMove(n, r)         # placement libre avec repères.
        let ca = c.contentOf(n.parent)
        n.setProp("x", fmtNum(r.x - ca.x))
        n.setProp("y", fmtNum(r.y - ca.y))
        let ctl = c.ctlOf(n)
        if ctl != nil:
          ctl.fixedX = round(r.x - ca.x)
          ctl.fixedY = round(r.y - ca.y)
        c.sizeLabel = fmtNum(r.x - ca.x) & ", " & fmtNum(r.y - ca.y)
        c.dropValid = false
      else:
        c.guides.setLen(0)
        c.sizeLabel = ""
        c.computeDrop(n.kind, e.x, e.y, n)
        c.ghost = rect(e.x - c.startRect.w / 2, e.y - c.startRect.h / 2, c.startRect.w, c.startRect.h)
    else:
      c.hoverNode = c.nodeAt(e.x, e.y)
  of maRelease:
    case c.drag
    of dmMove:
      if c.moved:
        if c.dropValid or nodeLayout(c.selected.parent) != "absolue": c.finishMove(e.x, e.y)
        else: c.changed()
    of dmResize: c.changed()
    else: discard
    c.drag = dmNone
    c.dropValid = false
    c.guides.setLen(0)
    c.sizeLabel = ""

method onKey*(c: FormCanvas, e: KeyEvent): bool =
  let n = c.selected
  if n == nil: return false
  case e.key
  of SDLK_DELETE, SDLK_BACKSPACE:
    c.deleteSelected()
  of SDLK_ESCAPE:
    if n.parent != nil: c.select(n.parent)
  of SDLK_LEFT, SDLK_RIGHT, SDLK_UP, SDLK_DOWN:
    if n.parent == nil or nodeLayout(n.parent) != "absolue": return false
    let step = if (e.mods and KMOD_SHIFT) != 0: 10.0 else: 1.0
    var x = n.pf("x")
    var y = n.pf("y")
    case e.key
    of SDLK_LEFT: x -= step
    of SDLK_RIGHT: x += step
    of SDLK_UP: y -= step
    else: y += step
    n.setProp("x", fmtNum(max(0.0, x)))
    n.setProp("y", fmtNum(max(0.0, y)))
    c.rebuild()
    c.changed()
  else: return false
  true

# API du canevas (aussi utilisée par le paquet interface : concepteur de l'atelier en Lexis+)

proc nodeByUid*(c: FormCanvas, uid: int): DNode =
  for n in c.model.allNodes:
    if n.uid == uid: return n

proc pathOfNode*(n: DNode): string =
  var parts: seq[string]
  var p = n
  while p != nil:
    parts.insert((if p.parent == nil: "formulaire " & p.name else: p.name), 0)
    p = p.parent
  parts.join($TreeSep)

proc showNode*(c: FormCanvas, n: DNode) =
  ## Affiche dans l'aperçu les pages d'onglets qui contiennent `n`.
  var p = n
  while p != nil and p.parent != nil:
    if baseOf(p.kind) == "page":
      let t = c.ctlOf(p.parent)
      if t != nil and t of Tab: t.setValueText($(p.parent.children.find(p) + 1))
    p = p.parent

proc parentLayoutOf*(n: DNode): string =
  if n != nil and n.parent != nil: nodeLayout(n.parent) else: ""

proc visibleProps*(n: DNode): seq[PropDef] =
  ## Propriétés montrées par l'inspecteur : x / y en disposition absolue, ancrage en bordure.
  let pl = parentLayoutOf(n)
  for d in allProps(n.kind):
    if d.name in ["x", "y"] and pl != "absolue": continue
    if d.name == "ancrage" and pl != "bordure": continue
    result.add d

proc canvasRename*(c: FormCanvas, n: DNode, newName: string): string =
  ## Renomme un nœud (ou le formulaire) ; "" si c'est fait, sinon le message d'erreur.
  ## Les fichiers (form_<nom>.prg) et le code sont l'affaire de l'appelant.
  let v = newName.strip
  if n == c.model.root:
    if not isFormName(v): return "Nom du formulaire : lettres, chiffres et _ seulement"
  else:
    for x in c.model.allNodes:
      if x != n and cmpIgnoreCase(x.name, v) == 0: return "« " & v & " » est déjà utilisé"
    if not isIdent(v): return "Nom invalide (lettre, puis lettres, chiffres ou _)"
  n.name = v
  c.rebuild()
  ""

proc canvasSetProp*(c: FormCanvas, n: DNode, key, value: string): string =
  ## Modifie une propriété et reconstruit l'aperçu ; "" si c'est fait, sinon le message.
  if key == "name": return canvasRename(c, n, value)
  var kind = pkString
  for d in allProps(n.kind):
    if d.name == key: kind = d.kind
  if kind == pkColor and value.strip.len > 0 and not validColor(value):
    return "Couleur : #RRGGBB ou #RRGGBBAA"
  n.setProp(key, value)
  c.rebuild()
  ""

# palette

type PaletteRow = tuple[header: bool, text: string, kind: string, letter: string]

proc rows(p: PaletteView): seq[PaletteRow] =
  var cats: seq[string]
  {.cast(gcsafe).}:
    if palette.len == 0: discard findEntry("etiquette")        # initialise la palette native.
    for e in palette:
      if e.category notin cats: cats.add e.category
    for cat in cats:
      result.add((true, cat.toUpper, "", ""))
      for e in palette:
        if e.category == cat: result.add((false, e.kind, e.kind, e.letter))

proc rowH(t: Theme): float = t.lineHeight + 2

proc rowAt(p: PaletteView, t: Theme, y: float): int =
  let i = int(floor((y - p.rect.y - 4 + p.scroll) / rowH(t)))
  let rs = p.rows
  if i >= 0 and i < rs.len and not rs[i].header: i else: -1

proc newPaletteView*(canvas: FormCanvas): PaletteView =
  result = PaletteView(canvas: canvas, hoverIdx: -1, pressIdx: -1)
  initControl(result)

method preferredSize*(p: PaletteView, d: Drawing, t: Theme): tuple[w, h: float] = (190.0, 400.0)

method draw*(p: PaletteView, d: Drawing, t: Theme) =
  d.fillRect(p.rect, t.header)
  d.pushClip(p.rect)
  let rh = rowH(t)
  if not p.hovered: p.hoverIdx = -1
  for i, r in p.rows:
    let y = p.rect.y + 4 + float(i) * rh - p.scroll
    if y + rh < p.rect.y or y > p.rect.y + p.rect.h: continue
    let rr = rect(p.rect.x + 6, y, p.rect.w - 12, rh)
    if r.header:
      d.textIn(rr, r.text, t.textSecondary, alLeft, 4)
      continue
    if i == p.hoverIdx: d.fillRoundRect(rr, 5, t.surfaceHover)
    let badge = rect(rr.x + 4, y + (rh - 20) / 2, 26, 20)
    d.fillRoundRect(badge, 5, t.accent.withAlpha(50))
    d.textIn(badge, r.letter, t.accent, alCenter)
    d.textIn(rect(rr.x + 36, y, rr.w - 36, rh), r.text, t.text)
  d.popClip()

method onMouse*(p: PaletteView, e: MouseEvent) =
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
        let kind = p.rows[p.pressIdx].kind
        c.drag = dmNew
        c.newKind = kind
        let isCont = isContainerKind(kind)
        let w = if isCont: 200.0 else: 120.0
        let h = if isCont: 110.0 else: 30.0
        c.ghost = rect(e.x - w / 2, e.y - h / 2, w, h)
        if c.rect.containsPoint(e.x, e.y): c.computeDrop(kind, e.x, e.y, nil)
        else: c.dropValid = false
        markDirty(c)
    else:
      p.hoverIdx = p.rowAt(t, e.y)
  of maRelease:
    if p.pressIdx >= 0:
      let kind = p.rows[p.pressIdx].kind
      if p.dragging:
        if c.rect.containsPoint(e.x, e.y): c.dropNew(kind, e.x, e.y)
      elif p.rowAt(t, e.y) == p.pressIdx:
        # clic : ajout à la fin du conteneur sélectionné (ou du formulaire).
        var target = c.selected
        if baseOf(kind) == "page":
          while target != nil and baseOf(target.kind) != "onglets": target = target.parent
          if target == nil and c.selected != nil:
            for ch in c.selected.children:
              if baseOf(ch.kind) == "onglets": target = ch
        else:
          while target != nil and not (target.kind == "fenetre" or isContainerKind(target.kind)) or
                (target != nil and baseOf(target.kind) == "onglets"):
            if baseOf(target.kind) == "onglets":
              let tctl = c.ctlOf(target)
              let ap = if tctl != nil and tctl of Tab: Tab(tctl).activePage else: 0
              if ap >= 0 and ap < target.children.len:
                target = target.children[ap]
                break
            target = target.parent
          if target == nil: target = c.model.root
        if target != nil:
          let r = c.contentOf(target)
          if baseOf(kind) == "page":
            let tctl = c.ctlOf(target)
            if tctl != nil:
              let tr = tctl.rect
              c.dropNew(kind, tr.x + tr.w / 2, tr.y + tr.h / 2)
          else:
            c.dropNew(kind, r.x + r.w / 2, r.y + r.h - 4)
    c.drag = dmNone
    c.newKind = ""
    c.dropValid = false
    c.ghost = rect(0, 0, 0, 0)
    p.pressIdx = -1
    p.dragging = false
    markDirty(c)

method onWheel*(p: PaletteView, dx, dy: float): bool =
  let t = p.win.theme
  let total = float(p.rows.len) * rowH(t) + 8
  p.scroll = clamp(p.scroll - dy * 30, 0.0, max(0.0, total - p.rect.h))
  true

# fenêtre du concepteur

var
  dWin, dCanvas, dPalette, dTree, dInspector, dTitle, dStatus: ControlId
  dRoot, dCodePath: string
  dEditor: ControlId
  dOpen: bool
  dRows: seq[tuple[id: ControlId, prop: string, kind: PropKind, choices: seq[string]]]
  dEventRows: seq[tuple[id: ControlId, event: string, choices: seq[string]]]
  dColorButtons: seq[tuple[id: ControlId, prop: string, edit: ControlId]]
  dTreePaths: seq[tuple[path: string, uid: int]]
  dTools: seq[tuple[id: ControlId, cmd: string]]
  dNameRow: tuple[id: ControlId, uid: int, text: string]   # champ « nom » de l'inspecteur.
  designerFileCreated*: proc (path: string) {.nimcall, gcsafe.}   # posé par l'atelier (arbre du projet).
  designerCodeChanged*: proc (path: string) {.nimcall, gcsafe.}   # posé par l'atelier (analyse, index).

var dOpLock: Lock
initLock(dOpLock)

const newHandlerChoice = "+ nouvelle procédure…"
const noHandlerChoice = "(aucune)"

proc status(s: string) = dStatus.caption = s

proc docUid(path: string): int = editorUidOf(dEditor, path)

proc fileText(path: string): string =
  let uid = docUid(path)
  if uid >= 0: return editorText(dEditor, uid)
  try: result = readFile(path)
  except CatchableError: result = ""

proc codeText(): string = fileText(dCodePath)

proc writeCode(text: string) =
  let uid = docUid(dCodePath)
  if uid >= 0:
    discard editorSetText(dEditor, uid, text)
  else:
    try: writeFile(dCodePath, text)
    except CatchableError: status("Écriture impossible : " & dCodePath)
  if designerCodeChanged != nil: designerCodeChanged(dCodePath)

proc formName(): string =
  readControl(dCanvas, FormCanvas, c): result = c.model.root.name

proc projectPrgFiles(): seq[string] =
  # Fichiers .prg du projet (hors formulaires), le code édité en premier.
  result.add dCodePath
  if dRoot.len == 0 or not dirExists(dRoot): return
  for f in walkDirRec(dRoot):
    let rel = relativePath(f, dRoot).replace('\\', '/')
    if rel.startsWith(".") or "/." in rel: continue
    if f.toLowerAscii.endsWith(".prg") and not isFormFile(f) and
       normalizedPath(absolutePath(f)) != dCodePath:
      result.add f

proc projectHandlers(): seq[string] =
  # Procédures à un paramètre du projet : celles du code édité d'abord.
  for f in projectPrgFiles():
    for h in existingHandlers(fileText(f)):
      var dup = false
      for x in result:
        if cmpIgnoreCase(x, h) == 0: dup = true
      if not dup: result.add h

proc missingHandlers(): seq[string] =
  var wanted: seq[string]
  readControl(dCanvas, FormCanvas, c):
    for n in c.model.allNodes:
      for e in n.events: wanted.add e.handler
  if wanted.len == 0: return
  let known = projectHandlers()
  for w in wanted:
    var found = false
    for k in known:
      if cmpIgnoreCase(k, w) == 0: found = true
    if not found:
      for f in projectPrgFiles():
        if definesProc(fileText(f), w):
          found = true
          break
    if not found and w notin result: result.add w

proc saveForm() =
  var code, name: string
  readControl(dCanvas, FormCanvas, c):
    c.model.code = relativePath(dCodePath, dRoot).replace('\\', '/')
    code = generateCode(c.model)
    name = c.model.root.name
  let path = normalizedPath(absolutePath(dRoot / formFileName(name)))
  let isNew = not fileExists(path)
  try:
    writeFile(path, code)
  except CatchableError:
    status("Écriture impossible : " & path)
    return
  let uid = docUid(path)
  if uid >= 0: discard editorSetText(dEditor, uid, code, modified = false)
  dWin.caption = "Concepteur de formulaires — " & formFileName(name) & " — " & extractFilename(dCodePath)
  let missing = missingHandlers()
  if missing.len > 0:
    status("⚠ procédure(s) introuvable(s) dans le projet : " & missing.join(", "))
  else:
    status("Enregistré : " & formFileName(name) & " · code : " & extractFilename(dCodePath))
  if isNew and designerFileCreated != nil: designerFileCreated(path)
  elif designerCodeChanged != nil: designerCodeChanged(path)

proc rebuildTree() =
  var items: seq[tuple[path: string, uid: int, container: bool]]
  var sel = ""
  readControl(dCanvas, FormCanvas, c):
    for n in c.model.allNodes: items.add((pathOfNode(n), n.uid, n.children.len > 0))
    if c.selected != nil: sel = pathOfNode(c.selected)
  treeDeleteAll(dTree)
  guarded: dTreePaths.setLen(0)
  for it in items:
    treeAdd(dTree, it.path, it.container)
    guarded: dTreePaths.add((it.path, it.uid))
  if sel.len > 0: treeSelectPlus(dTree, sel)

proc addRow(label: string, editorCtl: Control, extra: Control = nil) =
  let row = newSupercontrol(lkHorizontal, 6)
  row.fixedWidth = 318          # tient dans l'inspecteur (360 px) : pas de défilement horizontal
  let l = newLabel(label)
  l.fixedWidth = 118
  discard row.addChild(l)
  editorCtl.weight = 1
  discard row.addChild(editorCtl)
  if extra != nil: discard row.addChild(extra)
  discard addChild(dInspector, row)

proc rebuildInspector() =
  var node: DNode
  var isRoot = false
  var parentLayout = ""
  readControl(dCanvas, FormCanvas, c):
    node = if c.selected != nil: c.selected else: c.model.root
    isRoot = node == c.model.root
    if node != nil and node.parent != nil: parentLayout = nodeLayout(node.parent)
  if node == nil: return
  for id in children(dInspector): deleteControl(id)
  guarded:
    dRows.setLen(0)
    dEventRows.setLen(0)
    dColorButtons.setLen(0)
  dTitle.caption = (if isRoot: "Formulaire  " & node.name else: node.kind & "  " & node.name)
  discard addChild(dInspector, newLabel("PROPRIÉTÉS"))
  # nom (pour la fenêtre : nom du formulaire, donne form_<nom>.prg).
  let nameEdit = newEdit(node.name)
  nameEdit.tooltip = "Entrée (ou sortie du champ) pour renommer"
  addRow((if isRoot: "nom (fichier)" else: "nom"), nameEdit)
  guarded: dNameRow = (nameEdit.id, node.uid, node.name)
  for d in allProps(node.kind):
    if d.name in ["x", "y"] and parentLayout != "absolue": continue
    if d.name == "ancrage" and parentLayout != "bordure": continue
    let v = node.getProp(d.name)
    var ctl: Control
    var extra: Control = nil
    case d.kind
    of pkBool: ctl = newCheckBox("", isTrue(v))
    of pkEnum:
      var shown: seq[string]
      for ch in d.choices: shown.add(if ch.len == 0: "(défaut)" elif ch == "true": "vrai" elif ch == "false": "faux" else: ch)
      ctl = newComboBox(shown, max(0, d.choices.find(v)))
    of pkInt: ctl = newEdit(v, ikInteger)
    of pkFloat: ctl = newEdit(v, ikReal)
    of pkColor:
      ctl = newEdit(v, placeholder = "#RRGGBB")
      extra = newButton("…")
      extra.fixedWidth = 36
    of pkList: ctl = newEdit(v, placeholder = "a;b;c")
    of pkString: ctl = newEdit(v)
    addRow(d.name, ctl, extra)
    guarded:
      dRows.add((ctl.id, d.name, d.kind, d.choices))
      if extra != nil: dColorButtons.add((extra.id, d.name, ctl.id))
  # événements.
  discard addChild(dInspector, newLabel("ÉVÉNEMENTS  (procédures du projet)"))
  let handlers = projectHandlers()
  for ev in eventsOf(node.kind):
    let current = node.handlerFor(ev)
    var choices = @[noHandlerChoice]
    for h in handlers: choices.add h
    if current.len > 0:
      var present = false
      for h in choices:
        if cmpIgnoreCase(h, current) == 0: present = true
      if not present: choices.add current
    choices.add newHandlerChoice
    var sel = 0
    for i, h in choices:
      if current.len > 0 and cmpIgnoreCase(h, current) == 0: sel = i
    let cb = newComboBox(choices, sel)
    addRow(ev, cb)
    guarded: dEventRows.add((cb.id, ev, choices))

proc applyProp(prop: string, kind: PropKind, value: string, uid = -1) =
  ## uid >= 0 : nœud visé (sinon le nœud sélectionné).
  var oldForm, newForm: string
  var ok = true
  var msg = ""
  withControl(dCanvas, FormCanvas, c):
    var n = if c.selected != nil: c.selected else: c.model.root
    if uid >= 0:
      for x in c.model.allNodes:
        if x.uid == uid: n = x
    if prop == "name":
      let v = value.strip
      if n == c.model.root:
        if not isFormName(v):
          ok = false
          msg = "Nom du formulaire : lettres, chiffres et _ seulement"
        elif v != n.name:
          if fileExists(dRoot / formFileName(v)):
            ok = false
            msg = formFileName(v) & " existe déjà"
          else:
            oldForm = n.name
            newForm = v
            n.name = v
      else:
        var used = false
        for x in c.model.allNodes:
          if x != n and cmpIgnoreCase(x.name, v) == 0: used = true
        if not isIdent(v) or used:
          ok = false
          msg = if used: "« " & v & " » est déjà utilisé" else: "Nom invalide (lettre, puis lettres, chiffres ou _)"
        else:
          n.name = v
    elif kind == pkColor and value.strip.len > 0 and not validColor(value):
      ok = false
      msg = "Couleur : #RRGGBB ou #RRGGBBAA"
    else:
      n.setProp(prop, value)
    if ok: c.rebuild()
  if not ok:
    status(msg)
    return
  if newForm.len > 0:            # le formulaire a été renommé.
    let oldPath = dRoot / formFileName(oldForm)
    try:
      if fileExists(oldPath): removeFile(oldPath)
    except CatchableError: discard
    let uid = docUid(oldPath)
    if uid >= 0: editorClose(dEditor, uid)
    let code = codeText()
    let renamed = renameWiring(code, oldForm, newForm)
    if renamed != code: writeCode(renamed)
  saveForm()
  if newForm.len > 0 and designerFileCreated != nil:
    designerFileCreated(dRoot / formFileName(newForm))
  if prop == "name":
    rebuildTree()
    rebuildInspector()

proc applyEvent(event, choice: string) =
  var nodeName, form: string
  var handler = ""
  readControl(dCanvas, FormCanvas, c):
    let n = if c.selected != nil: c.selected else: c.model.root
    nodeName = if n == c.model.root: formVar(c.model.root.name) else: n.name
    form = c.model.root.name
  var stubLine = 0
  if choice == noHandlerChoice:
    handler = ""
  elif choice == newHandlerChoice:
    var existing: seq[string]
    for f in projectPrgFiles():
      for l in fileText(f).splitLines:
        let s = l.strip
        if s.startsWith("procedure ") or s.startsWith("fonction "): existing.add s.toUpperAscii
    let base = nodeName.toUpperAscii & "_" & event[3 .. ^1].toUpperAscii
    handler = base
    var k = 2
    while true:
      var taken = false
      for e in existing:
        if e.startsWith("PROCEDURE " & handler & "(") or e.startsWith("FONCTION " & handler & "(") or
           e == "PROCEDURE " & handler or e == "FONCTION " & handler: taken = true
      if not taken: break
      handler = base & $k
      inc k
    let r = insertStub(codeText(), form, handlerStub(handler, event, nodeName, form))
    writeCode(r.text)
    stubLine = r.line
  else:
    handler = choice
  withControl(dCanvas, FormCanvas, c):
    let n = if c.selected != nil: c.selected else: c.model.root
    n.setHandler(event, handler)
  saveForm()
  if stubLine > 0:
    rebuildInspector()
    let uid = docUid(dCodePath)
    if uid >= 0:
      editorGoto(dEditor, uid, stubLine - 1, 2)
      editorFlush(dEditor)
    status("Procédure " & handler & " créée dans " & extractFilename(dCodePath) & " (ligne " & $stubLine & ")")
  elif handler.len > 0: status(event & " → " & handler)
  else: status(event & " : association retirée")

proc designerCommand(cmd: string) =
  case cmd
  of "save":
    saveForm()
  of "wire":
    let name = formName()
    var code = ensureBlock(codeText(), name)
    let r = ensureOpenCall(code, name)
    var note = ""
    if r.added:
      code = r.text
      note = " ; appel " & openProc(name) & "() ajouté au programme principal"
    if code != codeText(): writeCode(code)
    status(openProc(name) & "() ouvre le formulaire depuis " & extractFilename(dCodePath) & note)
  of "delete", "up", "down", "out", "form":
    withControl(dCanvas, FormCanvas, c):
      case cmd
      of "delete": c.deleteSelected()
      of "up": c.moveSelected(-1)
      of "down": c.moveSelected(1)
      of "out": c.moveOut()
      else: c.select(c.model.root)
  of "custom":
    let kind = prompt(iconQuestion, "Nom du contrôle personnalisé (affiché dans la palette, ex. boutonrond) :",
                      "", "Contrôle personnalisé")
    if not isIdent(kind): return
    let base = prompt(iconQuestion, "Contrôle existant dont il dérive (bouton, etiquette, saisie, conteneur…) :",
                      "bouton", "Contrôle personnalisé")
    if findEntry(base).base != base or base == "fenetre" or base == "page":
      alert(iconStop, "Contrôle de base inconnu : « " & base & " ».")
      return
    let ctor = prompt(iconQuestion, "Expression Lexis+ qui crée le contrôle ($libelle, $texte… sont remplacés " &
                      "par les propriétés) :", kind.toUpperAscii & "($libelle)", "Contrôle personnalisé")
    if ctor.strip.len == 0: return
    if addCustomEntry(dRoot, kind, base, ctor.strip):
      withControl(dPalette, PaletteView, _): discard
      status(kind & " ajouté à la palette (" & PaletteFile & ")")
  of "code":
    var uid = docUid(dCodePath)
    if uid < 0 and fileExists(dCodePath): uid = editorOpen(dEditor, dCodePath, fileText(dCodePath))
    if uid >= 0:
      editorActivate(dEditor, uid)
      status("Code : " & dCodePath)
  else: discard

proc designerEvent(ev: var Event) =
  block:
    if ev.id == dCanvas:
      case ev.kind
      of evSelection:
        rebuildInspector()
        var sel = ""
        readControl(dCanvas, FormCanvas, c):
          if c.selected != nil: sel = pathOfNode(c.selected)
        if sel.len > 0: treeSelectPlus(dTree, sel)
      of evChange:
        saveForm()
        rebuildTree()
        rebuildInspector()
      else: discard
      return
    if ev.id == dTree and ev.kind == evSelection:
      var uid = -1
      guarded:
        for p in dTreePaths:
          if p.path == ev.text: uid = p.uid
      withControl(dCanvas, FormCanvas, c):
        for n in c.model.allNodes:
          if n.uid == uid:
            c.selected = n
            # page d'onglets : l'afficher dans l'aperçu.
            var p = n
            while p != nil and p.parent != nil:
              if baseOf(p.kind) == "page":
                let t = c.ctlOf(p.parent)
                if t != nil and t of Tab: t.setValueText($(p.parent.children.find(p) + 1))
              p = p.parent
      rebuildInspector()
      return
    if ev.kind == evWindowClose and ev.id == dWin:
      guarded: dOpen = false
      return
    if ev.kind == evClick:
      var cmd = ""
      guarded:
        for t in dTools:
          if t.id == ev.id: cmd = t.cmd
      if cmd.len > 0:
        designerCommand(cmd)
        return
      var colorProp = ""
      var colorEdit: ControlId
      guarded:
        for cbt in dColorButtons:
          if cbt.id == ev.id:
            colorProp = cbt.prop
            colorEdit = cbt.edit
      if colorProp.len > 0:
        var col = if validColor(colorEdit.value): hex(colorEdit.value) else: hex"#3B82F6"
        if colorDialog(col) == drOk:
          colorEdit.value = hexOf(col)
          applyProp(colorProp, pkColor, hexOf(col))
      return
    var nameRow: tuple[id: ControlId, uid: int, text: string]
    guarded: nameRow = dNameRow
    if ev.id == nameRow.id:
      # nom : appliqué par Entrée ou à la sortie du champ, pas à chaque frappe
      # (renommer le formulaire renomme son fichier et suit dans le code).
      case ev.kind
      of evChange:
        let v = ev.id.value
        guarded: dNameRow.text = v
      of evKeyDown, evFocusLost:
        if ev.kind == evKeyDown and int(ev.key) notin [0x0D, 0x40000058]: return   # Entrée, Entrée du pavé
        let v = (if ev.kind == evKeyDown: ev.id.value else: nameRow.text).strip
        var cur = ""
        readControl(dCanvas, FormCanvas, c):
          for x in c.model.allNodes:
            if x.uid == nameRow.uid: cur = x.name
        if v.len > 0 and cur.len > 0 and v != cur: applyProp("name", pkString, v, nameRow.uid)
      else: discard
      return
    if ev.kind in {evChange, evSelection}:
      var prop = ""
      var kind = pkString
      var choices: seq[string]
      var event = ""
      var evChoices: seq[string]
      guarded:
        for r in dRows:
          if r.id == ev.id:
            prop = r.prop
            kind = r.kind
            choices = r.choices
        for r in dEventRows:
          if r.id == ev.id:
            event = r.event
            evChoices = r.choices
      if prop.len > 0:
        var value = ev.id.value
        case kind
        of pkBool: value = (if value == "1": "true" else: "false")
        of pkEnum:
          let i = listSelect(ev.id) - 1
          value = if i >= 0 and i < choices.len: choices[i] else: ""
        else: discard
        applyProp(prop, kind, value)
      elif event.len > 0 and ev.kind == evSelection:
        let i = listSelect(ev.id) - 1
        if i >= 0 and i < evChoices.len: applyEvent(event, evChoices[i])

proc designerHandler(ev: var Event) {.nimcall, gcsafe.} =
  # L'état du concepteur est protégé par le verrou de wdgui (guarded / withControl).
  # Le corps est dans une procédure à part : avec Nim 2.2, un {.cast(gcsafe).}
  # imbriqué (celui de guarded) rétablit le contrôle pour la suite du bloc englobant.
  # Les événements sont traités un à un (un fil par événement dans wdgui) : pendant
  # une frappe rapide, chacun relit la valeur actuelle du champ et le dernier
  # appliqué est donc toujours le plus récent.
  if ev.current != ev.id: return
  {.cast(gcsafe).}:
    withLock dOpLock: designerEvent(ev)

proc openDesigner*(root, codePath, formFile: string, editorId: ControlId, theme: Theme): bool =
  ## Ouvre le concepteur pour `codePath` (le code qui reçoit les procédures).
  ## `formFile` : un form_<nom>.prg existant à rouvrir, ou "" pour un nouveau
  ## formulaire nommé d'après le premier numéro libre.
  var already = false
  guarded: already = dOpen
  if already: return false
  loadCustomPalette(root)
  var model: FormModel = nil
  if formFile.len > 0:
    let uid = editorUidOf(editorId, formFile)
    model = if uid >= 0: parseModel(editorText(editorId, uid)) else: loadModel(formFile)
    if model == nil: return false
  if model == nil: model = newModel(nextFormName(root))
  var code = codePath
  if formFile.len > 0 and model.code.len > 0 and fileExists(root / model.code): code = root / model.code
  guarded:
    dOpen = true
    dRoot = root
    dCodePath = normalizedPath(absolutePath(code))
    dEditor = editorId
    dTools.setLen(0)
    let win = newWindow("Concepteur de formulaires", 1320, 820, designerHandler, theme, lkBorder)
    win.root.margin = 0
    win.root.spacing = 0
    dWin = win.id
    # barre d'outils
    let tb = win.addChild(newToolbar())
    tb.dock = dkTop
    for (caption, cmd, tip) in [("Enregistrer", "save", "Régénère form_<nom>.prg"),
                                ("Supprimer", "delete", "Supprime le contrôle sélectionné (Suppr)"),
                                ("Monter", "up", "Plus tôt dans l'ordre d'affichage"),
                                ("Descendre", "down", "Plus tard dans l'ordre d'affichage"),
                                ("Sortir", "out", "Sort le contrôle de son conteneur"),
                                ("Formulaire", "form", "Sélectionne le formulaire (propriétés de la fenêtre)"),
                                ("Câbler le code", "wire",
                                 "Ajoute au code le bloc des procédures et l'appel d'ouverture (programme principal)"),
                                ("Contrôle personnalisé…", "custom",
                                 "Ajoute à la palette un contrôle créé par une fonction Lexis+ du projet"),
                                ("Voir le code", "code", "Affiche le code édité dans l'atelier")]:
      let b = tb.addTool(caption, tip)
      dTools.add((b.id, cmd))
    # barre d'état.
    let st = win.addChild(newLabel("Glisser depuis la palette · clic pour sélectionner · poignées pour " &
                                   "redimensionner · Suppr supprime · Échap sélectionne le parent"))
    st.dock = dkBottom
    dStatus = st.id
    # canevas (défilant), palette, hiérarchie et inspecteur.
    let canvas = newFormCanvas(model)
    canvas.selected = model.root
    let pal = newPaletteView(canvas)
    let left = win.addChild(newContainer(lkBorder, 0, 0))
    left.dock = dkLeft
    left.fixedWidth = 200
    let lt = left.addChild(newLabel("  PALETTE"))
    lt.dock = dkTop
    pal.dock = dkCenter
    discard left.addChild(pal)
    dPalette = pal.id
    let right = win.addChild(newContainer(lkBorder, 6, 6))
    right.dock = dkRight
    right.fixedWidth = 360
    let top = right.addChild(newContainer(lkVertical, 0, 4))
    top.dock = dkTop
    discard top.addChild(newLabel("HIÉRARCHIE"))
    let tree = top.addChild(newTreeView())
    tree.fixedHeight = 210
    dTree = tree.id
    let title = top.addChild(newLabel(""))
    title.style.text = some(theme.accent)
    dTitle = title.id
    let insp = right.addChild(newPanel(lkVertical, smAutomatic, 2, 4))
    insp.dock = dkCenter
    dInspector = insp.id
    let area = win.addChild(newPanel(lkVertical, smAutomatic, 0, 0))
    area.dock = dkCenter
    discard area.addChild(canvas)
    dCanvas = canvas.id
    win.focusedControl = canvas
    canvas.focus = true
  saveForm()
  rebuildTree()
  rebuildInspector()
  true

proc designerIsOpen*(): bool =
  guarded: result = dOpen

proc closeDesigner*() =
  var w: ControlId
  var open = false
  guarded:
    open = dOpen
    w = dWin
  if open: closeWindow(w)
