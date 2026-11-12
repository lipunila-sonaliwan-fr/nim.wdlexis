# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - « Vue projet » : graphe de l'ensemble du projet.
#
# Une colonne par fichier .prg (dans l'ordre des chemins, dossiers cachés exclus) :
# en tête le fichier (son code de premier niveau), puis ses procédures et fonctions
# dans l'ordre du source. Les liens pointillés relient chaque appelant aux procédures
# du projet qu'il appelle (ou référence par @NOM) ; en bleu quand l'appel change de
# fichier. Clic : détails dans la barre d'état ; double-clic : ouvre le code à la
# définition. L'analyse (lexislint.projectGraph) est la même que celle de
# lexis.graphe, utilisée par l'atelier écrit en Lexis+ pour la même vue.

import std/[strutils, tables, sets, os]
import ../wdgui
import diagramme, dockpane, lexislint

const
  PvColW* = 330.0           # largeur d'une colonne (nœud + marge)
  PvTopY* = 86.0            # première entité sous l'en-tête du fichier
  PvRowH* = 62.0            # pas vertical des entités
  PvFileColor* = "#475569"  # fichier (code de premier niveau)
  PvProcColor* = "#2563EB"  # procédure
  PvFuncColor* = "#7C3AED"  # fonction
  PvLinkColor* = "#94A3B8A0"   # appel dans le même fichier
  PvCrossColor* = "#0EA5E9C0"  # appel vers un autre fichier
  PvOutColor* = "#F59E0B"      # sélection : procédures appelées
  PvInColor* = "#22C55E"       # sélection : appelants
  PvFadeColor* = "#94A3B830"   # sélection : autres liens

type
  PvInfo = object
    path: string
    line: int
    text: string

var
  pvOpenCode*: proc (path: string, line: int) {.nimcall, gcsafe.}        # double-clic, « Ouvrir le code »
  pvOpenBlueprint*: proc (path: string, line: int) {.nimcall, gcsafe.}   # « Ouvrir en blueprint »
  pvWin, pvCanvas, pvStatus: ControlId
  pvOpen: bool
  pvRoot: string
  pvCalls = true
  pvTools: seq[tuple[id: ControlId, cmd: string]]
  pvInfos: Table[string, PvInfo]
  pvCross: HashSet[string]       # liens d'un fichier à un autre

proc fileId*(rel: string): string = "f:" & rel
proc entityId*(rel, name: string): string = "e:" & rel & ":" & name

proc kindName(k: SymKind): string = (if k == symFunc: "fonction" else: "procédure")

proc fill(c: DiagramCanvas, g: ProjectGraph, calls: bool, infos: var Table[string, PvInfo],
          crossIds: var HashSet[string]) =
  # Nœuds en colonnes (un fichier par colonne) et liens d'appel.
  c.nodes.setLen(0)
  c.links.setLen(0)
  c.selected = ""
  c.selLink = ""
  infos.clear()
  crossIds.clear()
  var where = initTable[string, seq[string]]()        # NOM -> ids des définitions
  var fileOf = initTable[string, string]()            # id -> fichier
  var callers = initTable[string, seq[string]]()      # id -> appelants (titres)
  for f in g.files:
    for e in f.entities:
      where.mgetOrPut(e.name, @[]).add entityId(f.rel, e.name)
      fileOf[entityId(f.rel, e.name)] = f.rel
  proc target(name, rel: string): string =
    let ids = where.getOrDefault(name)
    if ids.len == 0: return ""
    for id in ids:
      if fileOf.getOrDefault(id) == rel: return id    # de préférence dans le même fichier
    ids[0]
  for col, f in g.files:
    let x = col.float * PvColW
    let fid = fileId(f.rel)
    let n = c.upsertNode(fid)
    n.title = f.rel
    n.subtitle = $f.entities.len & " entité" & (if f.entities.len > 1: "s" else: "") & " · " & $f.lines & " lignes"
    n.shape = "boite"
    n.color = hex(PvFileColor)
    n.x = x
    n.y = 0
    infos[fid] = PvInfo(path: f.path, line: 0, text: f.rel & " : " & n.subtitle)
    for i, e in f.entities:
      let id = entityId(f.rel, e.name)
      let m = c.upsertNode(id)
      m.title = e.display
      m.subtitle = "ligne " & $(e.line + 1)
      m.shape = "boite"
      m.color = hex(if e.kind == symFunc: PvFuncColor else: PvProcColor)
      m.x = x
      m.y = PvTopY + i.float * PvRowH
      infos[id] = PvInfo(path: f.path, line: e.line,
                         text: e.display & " - " & kindName(e.kind) & " de " & f.rel & ", ligne " & $(e.line + 1))
  for f in g.files:
    var srcs = @[(fileId(f.rel), f.rel & " (code principal)", f.calls)]
    for e in f.entities: srcs.add (entityId(f.rel, e.name), e.display, e.calls)
    for (sid, title, names) in srcs:
      for nm in names:
        let tid = target(nm, f.rel)
        if tid.len == 0 or tid == sid: continue
        callers.mgetOrPut(tid, @[]).add title
        if calls:
          let cross = fileOf.getOrDefault(tid) != f.rel
          if cross: crossIds.incl sid & ">" & tid
          c.upsertLink DiaLink(id: sid & ">" & tid, src: sid, dst: tid, arrow: true, dashed: true,
                               color: hex(if cross: PvCrossColor else: PvLinkColor), width: 1.4)
  for id, who in callers:
    if id in infos: infos[id].text.add " - appelée par " & who.join(", ")
  c.needFit = true

proc highlight(c: DiagramCanvas, id: string, crossIds: HashSet[string]) =
  ## Liens du nœud sélectionné en évidence (orange : appelées, vert : appelants), les
  ## autres estompés ; sans sélection, couleurs ordinaires.
  for l in c.links.mitems:
    let cross = l.id in crossIds
    if id.len == 0:
      l.color = hex(if cross: PvCrossColor else: PvLinkColor)
      l.width = 1.4
    elif l.src == id:
      l.color = hex(PvOutColor)
      l.width = 2.4
    elif l.dst == id:
      l.color = hex(PvInColor)
      l.width = 2.4
    else:
      l.color = hex(PvFadeColor)
      l.width = 1.2

proc pvStatusText(msg: string) =
  var s: ControlId
  guarded: s = pvStatus
  if int(s) != 0: s.caption = msg

proc reload() =
  var root = ""
  var calls = true
  guarded:
    root = pvRoot
    calls = pvCalls
  let g = projectGraph(root)
  var infos = initTable[string, PvInfo]()
  var crossIds = initHashSet[string]()
  var nf, ne, nl = 0
  withControl(pvCanvas, DiagramCanvas, c):
    c.fill(g, calls, infos, crossIds)
    nl = c.links.len
  for f in g.files:
    inc nf
    ne += f.entities.len
  guarded:
    pvInfos = infos
    pvCross = crossIds
  pvStatusText($nf & " fichier" & (if nf > 1: "s" else: "") & " · " & $ne & " procédures et fonctions" &
               (if calls: " · " & $nl & " liens d'appel" else: "") &
               "   -   clic : détails · double-clic : ouvrir le code · glisser le fond : déplacer · molette : zoom")

proc selectedInfo(): (bool, PvInfo) =
  var id = ""
  readControl(pvCanvas, DiagramCanvas, c): id = c.selected
  guarded:
    if id in pvInfos: result = (true, pvInfos[id])

proc command(cmd: string) =
  case cmd
  of "reload": reload()
  of "fit":
    withControl(pvCanvas, DiagramCanvas, c): c.fit()
  of "zoomin", "zoomout":
    withControl(pvCanvas, DiagramCanvas, c):
      let f = if cmd == "zoomin": 1.25 else: 1 / 1.25
      let z = clamp(c.zoom * f, 0.15, 3.0)
      # zoom autour du centre de la vue
      let cx = c.rect.w / 2
      let cy = c.rect.h / 2
      c.panX = cx - (cx - c.panX) * z / c.zoom
      c.panY = cy - (cy - c.panY) * z / c.zoom
      c.zoom = z
  of "calls":
    guarded: pvCalls = not pvCalls
    reload()
  of "code", "blueprint":
    let (ok, info) = selectedInfo()
    if not ok:
      pvStatusText("Sélectionnez d'abord un fichier ou une procédure.")
      return
    let cb = if cmd == "code": pvOpenCode else: pvOpenBlueprint
    if cb != nil:
      {.cast(gcsafe).}: cb(info.path, info.line)
  else: discard

proc pvEvent(ev: var Event) =
  var win, canvas: ControlId
  var tools: seq[tuple[id: ControlId, cmd: string]]
  guarded:
    win = pvWin
    canvas = pvCanvas
    tools = pvTools
  if ev.id == win:
    if ev.kind == evWindowClose:
      guarded:
        pvOpen = false
        pvWin = NoControl
        pvCanvas = NoControl
        pvStatus = NoControl
        pvTools.setLen(0)
    return
  if ev.id == canvas:
    case ev.kind
    of evSelection:
      withControl(canvas, DiagramCanvas, c): c.highlight(c.selected, pvCross)
      let (ok, info) = selectedInfo()
      if ok: pvStatusText(info.text & "   (orange : appelées · vert : appelants)")
    of evDoubleClick:
      let (ok, info) = selectedInfo()
      if ok and pvOpenCode != nil:
        {.cast(gcsafe).}: pvOpenCode(info.path, info.line)
    else: discard
    return
  if ev.kind == evClick:
    for t in tools:
      if t.id == ev.id:
        command(t.cmd)
        return

proc pvHandler(ev: var Event) {.nimcall, gcsafe.} =
  if ev.current != ev.id: return
  {.cast(gcsafe).}: pvEvent(ev)

proc projectViewIsOpen*(): bool =
  guarded: result = pvOpen

proc projectViewWindowIds*(): seq[ControlId] =
  guarded:
    if pvOpen: result.add pvWin

proc refreshProjectView*(root: string) =
  # Projet modifié (fichier enregistré, renommé…, autre projet ouvert) : la vue ouverte se met à jour.
  if not projectViewIsOpen() or root.len == 0: return
  var w: ControlId
  guarded:
    pvRoot = root
    w = pvWin
  w.caption = "Vue projet - " & extractFilename(root)
  reload()

proc openProjectView*(root, projectName: string, theme: Theme): bool =
  # Ouvre la vue projet (ou la ramène au premier plan et la relit).
  if root.len == 0: return false
  var already = false
  var w: ControlId
  guarded:
    already = pvOpen
    w = pvWin
    pvRoot = root
  if already:
    w.caption = "Vue projet - " & projectName
    setWindowState(w, wsNormal)
    reload()
    return true
  guarded:
    pvOpen = true
    pvTools.setLen(0)
    let win = newWindow("Vue projet - " & projectName, 1320, 820, pvHandler, theme, lkBorder)
    win.root.margin = 0
    win.root.spacing = 0
    pvWin = win.id
    let tb = win.addChild(newToolbar())
    tb.dock = dkTop
    tb.margin = 2
    tb.spacing = 2
    for (icon, caption, cmd, tip) in [
        ("actualiser", "Actualiser", "reload", "Relit les fichiers du projet"),
        ("ajuster", "Tout voir", "fit", "Ajuste le zoom à l'ensemble du projet"),
        ("zoommoins", "Zoom −", "zoomout", "Molette pour zoomer autour du pointeur"),
        ("zoomplus", "Zoom +", "zoomin", "Molette pour zoomer autour du pointeur"),
        ("k-link", "Appels", "calls", "Affiche ou masque les liens d'appel (pointillés ; bleus : vers un autre fichier)")]:
      let b = tb.iconTool(icon, caption, tip)
      pvTools.add (b.id, cmd)
    tb.toolSeparator()
    for (icon, caption, cmd, tip) in [
        ("code", "Ouvrir le code", "code", "Ouvre dans l'atelier le fichier sélectionné, à la définition (ou double-clic)"),
        ("blueprint", "Ouvrir en blueprint", "blueprint", "Ouvre le fichier sélectionné dans la fenêtre Blueprint")]:
      let b = tb.iconTool(icon, caption, tip)
      pvTools.add (b.id, cmd)
    let info = tb.addChild(newLabel("  une colonne par fichier · procédures dans l'ordre du source"))
    info.weight = 1
    info.style.text = some(theme.textSecondary)
    let st = win.addChild(newLabel(""))
    st.dock = dkBottom
    st.fixedHeight = 20
    pvStatus = st.id
    let canvas = newDiagram(editable = false)
    canvas.dock = dkCenter
    canvas.fitMin = 0.35
    discard win.addChild(canvas)
    pvCanvas = canvas.id
    win.focusedControl = canvas
    canvas.focus = true
  reload()
  true

proc closeProjectView*() =
  var w: ControlId
  var open = false
  guarded:
    open = pvOpen
    w = pvWin
  if open: closeWindow(w)
