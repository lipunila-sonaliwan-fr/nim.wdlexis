# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet interface : la toile vectorielle (inclus dans pkg_interface).
#
#   t = fen:ajouter(ui.toile{mode = "edition"})
#   t:chargersvg(code)            t:svg()               t:png("x.png", 640)
#   id = t:ajouter{genre = "rectangle", x = 10, y = 10, largeur = 200, hauteur = 80, remplissage = "#4f7cff"}
#   t:modifier(id, {rotation = 15})      t:forme(id)    t:formes()
#   t:outil("plume")   t:selection()   t:aligner("centre")   t:annuler()

from ../ide/imagepure import encodePngPure
from ../ide/imagedecode import nil
import std/sequtils
import ../wdgui/[vscene, vcanvas, vtrace]

template withToile(L: Interp, a: seq[Value], fname: string, v, body: untyped) =
  block:
    let c0 = L.self(a, fname)
    if c0.ctl.isNil or not (c0.ctl of VectorCanvas): rtError("« " & fname & " » : toile attendue")
    guarded:
      let v = VectorCanvas(c0.ctl)
      body
      markDirty(v)
    wakeUI()

const NumProps = ["x", "y", "largeur", "hauteur", "rotation", "opacite", "epaisseur", "rayon", "taille",
                  "interligne", "x1", "y1", "x2", "y2"]
const BoolProps = ["verrouille", "masque", "ombre", "flechedebut", "flechefin", "pairimpair", "gras", "italique"]

proc propsValue(props: seq[(string, string)]): Value =
  let t = newLTable()
  for (k, v) in props:
    if k in NumProps:
      try: t.set(k, numV(parseFloat(v)))
      except ValueError: t.set(k, strV(v))
    elif k in BoolProps: t.set(k, boolV(v == "vrai"))
    else: t.set(k, strV(v))
  tableV(t)

proc tableProps(L: Interp, t: LTable): seq[(string, string)] =
  for k, v in t.pairs:
    if k.kind != vkStr: continue
    let s = case v.kind
            of vkBool: (if v.b: "vrai" else: "faux")
            of vkNil: ""
            else: L.tostr(v)
    result.add (k.s, s)

proc idsArg(L: Interp, a: seq[Value], i: int): seq[string] =
  let v = arg(a, i)
  case v.kind
  of vkNil: discard
  of vkTable:
    for k in 1 .. v.t.rawLen: result.add L.tostr(v.t.rawGet(intV(k)))
  else:
    for p in L.tostr(v).split(','):
      if p.strip.len > 0: result.add p.strip

proc idsValue(ids: seq[string]): Value =
  let t = newLTable()
  for id in ids: t.arr.add strV(id)
  tableV(t)

proc defineToileMethods() =
  mfn "toile", "chargerpages", proc (L: Interp, a: seq[Value]): seq[Value] =
    # chargerpages({svg...}, {colonnes=1, ecart=28, legendes={...}, dossier=, choisie=}) : planche de pages
    # (aperçu de document, trieuse de diapositives, storyboard) ; chaque page est le groupe « page-N ».
    let v = arg(a, 2)
    if v.kind != vkTable: rtError("chargerpages : liste de SVG attendue")
    let o = optsArg(a, 3)
    let base = L.programPath(optField(o, "dossier", "."))
    var pages: seq[VScene]
    for i in 1 .. v.t.rawLen:
      let code = L.tostr(v.t.rawGet(intV(i)))
      if code.strip.startsWith("<"): pages.add parseSvgScene(code, base)
      else:
        let p = L.programPath(code)
        var txt = ""
        try: txt = readFile(p)
        except IOError, OSError: discard
        pages.add parseSvgScene(txt, p.parentDir)
    var caps: seq[string]
    if o != nil and field(o, "legendes").kind == vkTable:
      let t = field(o, "legendes").t
      for i in 1 .. t.rawLen: caps.add L.tostr(t.rawGet(intV(i)))
    let cols = optField(o, "colonnes", 1)
    let gap = optField(o, "ecart", 28.0)
    let sel = optField(o, "choisie", 0) - 1
    let keep = optField(o, "garderposition", false)
    L.withToile(a, "chargerpages", c):
      let z = c.zoom
      let py = c.panY
      c.loadPages(pages, cols, gap, caps, sel)
      if keep and c.rect.w > 10:
        c.fitWidth = true
        c.fit
        c.panY = clamp(py, min(8.0, c.rect.h - c.scene.height * c.zoom - 8), 8)
        discard z
        c.needFit = false
    @[intV(pages.len)]
  mfn "toile", "montrer", proc (L: Interp, a: seq[Value]): seq[Value] =
    # montrer(groupe | id) : fait défiler la vue jusqu'au groupe (page-N) ou à la forme.
    let id = L.checkStr(a, 2, "montrer")
    L.withToile(a, "montrer", c):
      var x0 = Inf
      var y0 = Inf
      var y1 = -Inf
      for s in c.scene.shapes:
        if s.group == id or s.id == id:
          let b = s.bounds
          x0 = min(x0, b.x); y0 = min(y0, b.y); y1 = max(y1, b.y + b.h)
      if y0 != Inf and c.rect.h > 0:
        let top = c.panY + y0 * c.zoom
        let bot = c.panY + y1 * c.zoom
        if top < 0 or bot > c.rect.h:
          c.panY = 12 - y0 * c.zoom
  mfn "toile", "chargersvg", proc (L: Interp, a: seq[Value]): seq[Value] =
    # chargersvg(code [, dossier]) : remplace la scène ; le dossier résout les images relatives.
    let code = L.checkStr(a, 2, "chargersvg")
    let base = L.optStr(a, 3, "chargersvg", "")
    let sc = parseSvgScene(code, (if base.len > 0: L.programPath(base) else: ""))
    L.withToile(a, "chargersvg", c):
      let v = c.scene.version
      c.scene = sc
      c.scene.version = v + 1
      if c.scene.layers.len == 0: c.scene.ensureLayer("Calque 1")
      c.selection.setLen(0)
      c.editText = ""
      c.clearHistory
      c.needFit = true
  mfn "toile", "chargerfichier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.programPath(L.checkStr(a, 2, "chargerfichier"))
    var code = ""
    try: code = readFile(path)
    except IOError, OSError: rtError("chargerfichier : lecture impossible de « " & path & " »")
    let sc = parseSvgScene(code, path.parentDir)
    L.withToile(a, "chargerfichier", c):
      let v = c.scene.version
      c.scene = sc
      c.scene.version = v + 1
      if c.scene.layers.len == 0: c.scene.ensureLayer("Calque 1")
      c.selection.setLen(0)
      c.clearHistory
      c.needFit = true
  mfn "toile", "svg", proc (L: Interp, a: seq[Value]): seq[Value] =
    # svg([{images = vrai, compact = vrai, selection = vrai}]) : le SVG standard de la scène
    # (selection : les formes choisies seules, recadrées sur leur boîte).
    let o = optsArg(a, 2)
    let emb = optField(o, "images", false)
    let compact = optField(o, "compact", false)
    let onlySel = optField(o, "selection", false)
    var s = ""
    L.withToile(a, "svg", c):
      if onlySel and c.selection.len > 0:
        let b = c.selectionBox
        let pad = 2.0
        var sub = VScene(width: b.w + 2 * pad, height: b.h + 2 * pad, layers: c.scene.layers, base: c.scene.base)
        for sh in c.selectedShapes:
          let n = sh.clone
          n.moveShape(pad - b.x, pad - b.y)
          sub.shapes.add n
        s = sub.toSvg(emb, not compact)
      else:
        s = c.scene.toSvg(emb, not compact)
    @[strV(s)]
  mfn "toile", "booleen", proc (L: Interp, a: seq[Value]): seq[Value] =
    # booleen(union | difference | intersection | exclusion) : remplace la sélection par le résultat.
    let op = L.checkStr(a, 2, "booleen").toLowerAscii
    var id = ""
    L.withToile(a, "booleen", c):
      let sel = c.selectedShapes
      if sel.len >= 2:
        let r = booleanShapes(c.scene, sel, op)
        if r != nil:
          c.pushUndo
          let ids = c.selection
          var at = c.scene.shapes.len
          for i, sh in c.scene.shapes:
            if sh.id in ids:
              at = i
              break
          c.scene.shapes = c.scene.shapes.filterIt(it.id notin ids)
          c.scene.shapes.insert(r, min(at, c.scene.shapes.len))
          c.invalidate
          c.setSelection(@[r.id], false)
          c.lastAction = "booleen"
          c.lastIds = @[r.id]
          id = r.id
    @[(if id.len > 0: strV(id) else: nilV)]
  mfn "toile", "png", proc (L: Interp, a: seq[Value]): seq[Value] =
    # png(chemin [, largeur]) : rendu de la planche en PNG.
    let path = L.programPath(L.checkStr(a, 2, "png"))
    let w0 = if arg(a, 3).kind == vkNil: 0 else: int(L.checkNum(a, 3, "png"))
    var sc: VScene
    L.withToile(a, "png", c):
      sc = c.scene.cloneScene
    let w = if w0 > 0: w0 else: int(sc.width)
    let h = max(1, int(round(sc.height * w.float / max(1.0, sc.width))))
    let px = renderToRgba(sc, w, h)
    try: writeFile(path, encodePngPure(imagedecode.RgbaImage(w: w, h: h, px: px)))
    except IOError, OSError: return @[boolV(false)]
    @[boolV(true)]
  mfn "toile", "dimensions", proc (L: Interp, a: seq[Value]): seq[Value] =
    # dimensions([largeur, hauteur]) : renvoie {largeur, hauteur}.
    let setIt = arg(a, 2).kind != vkNil
    let w = if setIt: L.checkNum(a, 2, "dimensions") else: 0.0
    let h = if setIt: L.checkNum(a, 3, "dimensions") else: 0.0
    var r: Value
    L.withToile(a, "dimensions", c):
      if setIt:
        c.scene.width = max(1.0, w)
        c.scene.height = max(1.0, h)
        c.needFit = true
        c.invalidate
      r = record({"largeur": numV(c.scene.width), "hauteur": numV(c.scene.height)})
    @[r]
  mfn "toile", "fond", proc (L: Interp, a: seq[Value]): seq[Value] =
    let col = L.optStr(a, 2, "fond", "")
    L.withToile(a, "fond", c):
      c.pushUndo
      c.scene.background = col
      c.invalidate
  mfn "toile", "formes", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = newLTable()
    L.withToile(a, "formes", c):
      for s in c.scene.shapes: t.arr.add propsValue(s.shapeProps)
    @[tableV(t)]
  mfn "toile", "forme", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.checkStr(a, 2, "forme")
    var r = nilV
    L.withToile(a, "forme", c):
      let s = c.scene.findShape(id)
      if s != nil: r = propsValue(s.shapeProps)
    @[r]
  mfn "toile", "ajouter", proc (L: Interp, a: seq[Value]): seq[Value] =
    # ajouter{genre=, x=, y=, largeur=, hauteur=, ...} : renvoie l'id de la forme.
    let t = L.checkTable(a, 2, "ajouter")
    let props = L.tableProps(t)
    let kind = optField(t, "genre", "rectangle")
    let select = optField(t, "selectionner", true)
    let s = shapeFromProps(kind, props.filterIt(it[0] notin ["genre", "selectionner"]))
    L.withToile(a, "ajouter", c):
      c.pushUndo
      c.addShape(s, select)
      c.lastAction = "creation"
      c.lastIds = @[s.id]
    @[strV(s.id)]
  mfn "toile", "modifier", proc (L: Interp, a: seq[Value]): seq[Value] =
    # modifier(id | {ids}, {propriété = valeur, ...}) ; les saisies successives s'annulent en une fois.
    let ids = L.idsArg(a, 2)
    let props = L.tableProps(L.checkTable(a, 3, "modifier"))
    var n = 0
    L.withToile(a, "modifier", c):
      c.pushUndo("prop:" & ids.join(",") & ":" & props.mapIt(it[0]).join(","))
      for id in ids:
        let s = c.scene.findShape(id)
        if s == nil: continue
        for (k, v) in props:
          if s.setShapeProp(k, v): inc n
        if s.kind == vkText: s.fitTextHeight
      c.invalidate
    @[intV(n)]
  mfn "toile", "supprimer", proc (L: Interp, a: seq[Value]): seq[Value] =
    # supprimer([id | {ids}]) : sans argument, la sélection.
    let ids = L.idsArg(a, 2)
    L.withToile(a, "supprimer", c):
      if ids.len > 0: c.setSelection(ids, false)
      c.deleteSelection
  mfn "toile", "vider", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withToile(a, "vider", c):
      c.pushUndo
      c.scene.shapes.setLen(0)
      c.selection.setLen(0)
      c.invalidate
  mfn "toile", "selection", proc (L: Interp, a: seq[Value]): seq[Value] =
    var ids: seq[string]
    L.withToile(a, "selection", c):
      ids = c.selection
    @[idsValue(ids)]
  mfn "toile", "selectionner", proc (L: Interp, a: seq[Value]): seq[Value] =
    # selectionner(id | {ids} | "groupe:<g>") : sans argument, désélectionne.
    let ids = L.idsArg(a, 2)
    L.withToile(a, "selectionner", c):
      var res: seq[string]
      for id in ids:
        if id.startsWith("groupe:"):
          for s in c.scene.shapes:
            if s.group == id[7 .. ^1]: res.add s.id
        else: res.add id
      c.setSelection(res, false)
  mfn "toile", "outil", proc (L: Interp, a: seq[Value]): seq[Value] =
    # outil([nom [, {href=, donnees=, ratio=, maintenir=}]]) : renvoie l'outil actif.
    let name = L.optStr(a, 2, "outil", "")
    let o = optsArg(a, 3)
    var r = ""
    L.withToile(a, "outil", c):
      if name.len > 0:
        var found = false
        for t in VTool:
          if $t == name.toLowerAscii.replace("è", "e").replace("œ", "oe"):
            c.tool = t
            found = true
        if not found: rtError("outil : « " & name & " » inconnu (selection, rectangle, ellipse, ligne, fleche, plume, texte, image, main, noeuds)")
        if o != nil:
          c.pendingHref = optField(o, "href", "")
          c.pendingData = optField(o, "donnees", "")
          c.pendingRatio = optField(o, "ratio", 0.0)
          c.stickyTool = optField(o, "maintenir", false)
        if c.tool != vtNodes: c.nodeId = ""
      r = $c.tool
    @[strV(r)]
  mfn "toile", "style", proc (L: Interp, a: seq[Value]): seq[Value] =
    # style{remplissage=, contour=, epaisseur=, police=, taille=} : style des nouvelles formes.
    let o = optsArg(a, 2)
    L.withToile(a, "style", c):
      if o != nil:
        c.newFill = optField(o, "remplissage", c.newFill)
        c.newStroke = optField(o, "contour", c.newStroke)
        c.newStrokeWidth = optField(o, "epaisseur", c.newStrokeWidth)
        c.newFont = optField(o, "police", c.newFont)
        c.newFontSize = optField(o, "taille", c.newFontSize)
  mfn "toile", "mode", proc (L: Interp, a: seq[Value]): seq[Value] =
    let name = L.optStr(a, 2, "mode", "")
    var r = ""
    L.withToile(a, "mode", c):
      for m in VMode:
        if $m == name:
          c.mode = m
          c.focusable = m == vmEdit
          c.needFit = true
      r = $c.mode
    @[strV(r)]
  mfn "toile", "zoom", proc (L: Interp, a: seq[Value]): seq[Value] =
    # zoom([pourcentage]) : renvoie le zoom en %.
    let has = arg(a, 2).kind != vkNil
    let z = if has: L.checkNum(a, 2, "zoom") / 100 else: 0.0
    var r = 0.0
    L.withToile(a, "zoom", c):
      if has: c.setZoomAt(z, c.rect.x + c.rect.w / 2, c.rect.y + c.rect.h / 2)
      r = c.zoom * 100
    @[numV(round(r))]
  mfn "toile", "ajuster", proc (L: Interp, a: seq[Value]): seq[Value] =
    let largeur = optBool(a, 2, false)
    L.withToile(a, "ajuster", c):
      c.fitWidth = largeur
      c.fit
      c.needFit = c.rect.w < 10
  mfn "toile", "grille", proc (L: Interp, a: seq[Value]): seq[Value] =
    # grille{taille=, visible=, magnetisme=, objets=}
    let o = optsArg(a, 2)
    var r: Value
    L.withToile(a, "grille", c):
      if o != nil:
        c.gridSize = optField(o, "taille", c.gridSize)
        c.showGrid = optField(o, "visible", c.showGrid)
        c.snapGrid = optField(o, "magnetisme", c.snapGrid)
        c.snapObjects = optField(o, "objets", c.snapObjects)
      r = record({"taille": numV(c.gridSize), "visible": boolV(c.showGrid), "magnetisme": boolV(c.snapGrid),
                  "objets": boolV(c.snapObjects)})
    @[r]
  mfn "toile", "guide", proc (L: Interp, a: seq[Value]): seq[Value] =
    # guide("v" | "h", position) ; guide() : supprime les guides.
    let dir = L.optStr(a, 2, "guide", "")
    let pos = if arg(a, 3).kind == vkNil: 0.0 else: L.checkNum(a, 3, "guide")
    L.withToile(a, "guide", c):
      if dir.len == 0: c.guides.setLen(0)
      else: c.guides.add (dir.toLowerAscii.startsWith("v"), pos)
  mfn "toile", "calques", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = newLTable()
    L.withToile(a, "calques", c):
      for l in c.scene.layers:
        var n = 0
        for s in c.scene.shapes:
          if s.layer == l.name: inc n
        t.arr.add record({"nom": strV(l.name), "visible": boolV(l.visible), "verrouille": boolV(l.locked),
                          "formes": intV(n)})
    @[tableV(t)]
  mfn "toile", "calque", proc (L: Interp, a: seq[Value]): seq[Value] =
    # calque(nom, {visible=, verrouille=, renommer=, supprimer=, monter=, descendre=, actif=})
    # Crée le calque s'il n'existe pas ; actif : les nouvelles formes y vont (calque placé en dernier).
    let name = L.checkStr(a, 2, "calque")
    let o = optsArg(a, 3)
    L.withToile(a, "calque", c):
      c.pushUndo("calque:" & name)
      c.scene.ensureLayer(name)
      var i = c.scene.layerOf(name)
      if o != nil:
        if field(o, "visible").kind != vkNil: c.scene.layers[i].visible = optField(o, "visible", true)
        if field(o, "verrouille").kind != vkNil: c.scene.layers[i].locked = optField(o, "verrouille", false)
        let nn = optField(o, "renommer", "")
        if nn.len > 0 and c.scene.layerOf(nn) < 0:
          for s in c.scene.shapes:
            if s.layer == name: s.layer = nn
          c.scene.layers[i].name = nn
        if optField(o, "supprimer", false) and c.scene.layers.len > 1:
          let ln = c.scene.layers[i].name
          c.scene.shapes = c.scene.shapes.filterIt(it.layer != ln)
          c.scene.layers.delete(i)
          c.selection = c.selection.filterIt(c.scene.findShape(it) != nil)
        else:
          if optField(o, "monter", false) and i < c.scene.layers.high:
            swap(c.scene.layers[i], c.scene.layers[i + 1])
          elif optField(o, "descendre", false) and i > 0:
            swap(c.scene.layers[i], c.scene.layers[i - 1])
          # ordre de dessin : formes regroupées par calque
          var sh: seq[VShape]
          for l in c.scene.layers:
            for s in c.scene.shapes:
              if s.layer == l.name: sh.add s
          for s in c.scene.shapes:
            if c.scene.layerOf(s.layer) < 0: sh.add s
          c.scene.shapes = sh
      c.invalidate
  mfn "toile", "ordre", proc (L: Interp, a: seq[Value]): seq[Value] =
    let how = L.checkStr(a, 2, "ordre")
    L.withToile(a, "ordre", c): c.reorder(how)
  mfn "toile", "aligner", proc (L: Interp, a: seq[Value]): seq[Value] =
    let how = L.checkStr(a, 2, "aligner")
    L.withToile(a, "aligner", c): c.alignSelection(how)
  mfn "toile", "grouper", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withToile(a, "grouper", c): c.groupSelection
  mfn "toile", "degrouper", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withToile(a, "degrouper", c): c.ungroupSelection
  mfn "toile", "dupliquer", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withToile(a, "dupliquer", c): c.duplicateSelection
  mfn "toile", "copier", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withToile(a, "copier", c): c.copySelection
  mfn "toile", "coller", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withToile(a, "coller", c): c.paste
  mfn "toile", "annuler", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withToile(a, "annuler", c): c.undo
  mfn "toile", "retablir", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withToile(a, "retablir", c): c.redo
  mfn "toile", "historique", proc (L: Interp, a: seq[Value]): seq[Value] =
    # {annuler = logique, retablir = logique}
    var r: Value
    L.withToile(a, "historique", c):
      r = record({"annuler": boolV(c.canUndo), "retablir": boolV(c.canRedo)})
    @[r]
  mfn "toile", "memoriser", proc (L: Interp, a: seq[Value]): seq[Value] =
    # memoriser() : instantané d'annulation avant une modification faite par programme.
    L.withToile(a, "memoriser", c): c.pushUndo
  mfn "toile", "action", proc (L: Interp, a: seq[Value]): seq[Value] =
    # {action, ids} : la dernière modification faite à la souris ou au clavier.
    var r: Value
    L.withToile(a, "action", c):
      r = record({"action": strV(c.lastAction), "ids": idsValue(c.lastIds)})
    @[r]
  mfn "toile", "ensaisie", proc (L: Interp, a: seq[Value]): seq[Value] =
    # ensaisie() : vrai pendant la saisie d'un texte dans la toile (les lettres sont du texte).
    var r = false
    L.withToile(a, "ensaisie", c): r = c.editText.len > 0
    @[boolV(r)]
  mfn "toile", "editertexte", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.checkStr(a, 2, "editertexte")
    L.withToile(a, "editertexte", c): c.beginTextEdit(id)
  mfn "toile", "boite", proc (L: Interp, a: seq[Value]): seq[Value] =
    # boite([id]) : {x, y, largeur, hauteur} de la forme ou de la sélection (scène).
    let id = L.optStr(a, 2, "boite", "")
    var r: Value
    L.withToile(a, "boite", c):
      var b = (x: 0.0, y: 0.0, w: 0.0, h: 0.0)
      if id.len > 0:
        let s = c.scene.findShape(id)
        if s != nil: b = s.bounds
      else: b = c.selectionBox
      r = record({"x": numV(b.x), "y": numV(b.y), "largeur": numV(b.w), "hauteur": numV(b.h)})
    @[r]
  mfn "toile", "versecran", proc (L: Interp, a: seq[Value]): seq[Value] =
    # versecran(x, y) : point de la scène en coordonnées de la fenêtre.
    let x = L.checkNum(a, 2, "versecran")
    let y = L.checkNum(a, 3, "versecran")
    var r: Value
    L.withToile(a, "versecran", c):
      let p = c.toScreen(x, y)
      r = record({"x": numV(p.x), "y": numV(p.y)})
    @[r]
  mfn "toile", "versscene", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkNum(a, 2, "versscene")
    let y = L.checkNum(a, 3, "versscene")
    var r: Value
    L.withToile(a, "versscene", c):
      let p = c.toScene(x, y)
      r = record({"x": numV(p.x), "y": numV(p.y)})
    @[r]
