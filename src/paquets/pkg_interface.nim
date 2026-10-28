# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet interface : wdgui depuis Lexis+
#
#   ui = paquet("interface")
#   fen = ui.fenetre{titre = "Bonjour", largeur = 420, hauteur = 220}
#   lbl = fen:ajouter(ui.etiquette("Cliquez le bouton", "centre"))
#   btn = fen:ajouter(ui.bouton("OK", {defaut = vrai}))
#   btn.surclic = @CLIC
#   ui.executer()
#
#   procedure CLIC(ev)
#     lbl.libelle = "Cliqué en " + ev.x + ", " + ev.y
#   retourner
#
# Chaque contrôle est un objet :
#   - propriétés lues et écrites comme dans wdgui (valeur, num, libelle, visible,
#     etat, infobulle, nom, x, y, largeur, hauteur, couleur, fond, ancrage,
#     poids, largeurfixe, hauteurfixe, etirer, marge, espacement, min, max...) ;
#   - gestionnaires sur<événement> : surclic, surchangement, surselection,
#     surdoubleclic, surclicdroit, surtouchebas, sursaisie, surfocus,
#     surfermeture... et surevenement pour tous ; ev:arreter() arrête la
#     propagation ; un gestionnaire est une référence de procédure (@NOM) ;
#   - méthodes selon la famille : liste:ajouter, tableau:ajouterligne,
#     arbre:ajouter, grille:ajoutercolonne, graphe:ajouterdonnee, onglets:ajouterpage,
#     markdown:charger, editeur:ouvrir...
#
# Les gestionnaires s'exécutent sur les fils de wdgui ; l'interpréteur les
# sérialise avec son verrou global. ui.executer() attend la fermeture des
# fenêtres (dans l'atelier) ou lance la boucle de wdgui (runtime autonome).
# Les valeurs nommées (dispositions, ancrages, icônes...) s'écrivent en
# français ; les noms anglais de wdgui sont aussi acceptés.

import std/[strutils, tables, os, locks, options, math]
import ../wdgui
import ../lexis/api
import ../ide/compat
import ../ide/[codeeditor, langdocs]
from ../ide/designer import FormCanvas, PaletteView, newFormCanvas, newPaletteView, nodeByUid, pathOfNode,
  visibleProps, canvasSetProp, select, deleteSelected, moveSelected, moveOut, showNode
from ../ide/reportdesigner import ReportCanvas, ReportPalette, SelKind, newReportCanvas, newReportPalette,
  findNode, selectedUid, selectUid, selectionTitle, inspectorRows, selectionHelp, setSelectionValue, renameNode,
  reportExampleCode, writePreview, addBand, deleteSelected, moveSelected
from ../ide/diagramme import DiagramCanvas, DiaNode, DiaLink, DiaRow, newDiagram, upsertNode, upsertLink, removeNode,
  placeNew, layout, fit, findNode, invalidate
from ../ide/etats import ReportModel, newReport, parseReportCode, generateReportCode, reportFileName
from ../ide/formmodel import FormModel, DNode, PropKind, newModel, parseModel, generateCode, loadCustomPalette,
  addCustomEntry, allNodes, getProp, handlerFor, setHandler, eventsOf, isContainerKind, findEntry, isIdent
from ../ide/lexislint import Diagnostic, Severity
from ../ide/imagedecode import decodeImageFile
from std/unicode import runeOffset

type
  UiCtl* = ref object of LUser
    rawId: ControlId     # identifiant fixe (colonnes de grille), sinon lu sur ctl / win.
    ctl*: Control
    win*: Window
    family*: string
    handlers*: LTable
    closed*: bool

  UiState* = ref object of RootObj
    ctls*: seq[UiCtl]
    windows*: seq[UiCtl]
    loopRunning*: bool
    trace*: bool          # ui.tracer(vrai) : affiche chaque événement reçu.

proc id*(c: UiCtl): ControlId =
  # Identifiant courant. wdgui n'attribue l'identifiant d'un contrôle qu'au
  # moment où il est rattaché à l'arbre d'une fenêtre : on le relit à chaque fois.
  if not c.ctl.isNil: result = c.ctl.id
  elif not c.win.isNil: result = c.win.id
  else: result = c.rawId

var uiLock: Lock
var uiInterps: seq[Interp]     # interpréteurs ayant ouvert le paquet (un par programme).
initLock(uiLock)

var ctlMeta: LTable

proc uiState*(L: Interp): UiState =
  let r = L.ext.getOrDefault("ui")
  if r.isNil:
    result = UiState()
    L.ext["ui"] = result
  else:
    result = UiState(r)

proc findCtl(st: UiState, cid: ControlId): UiCtl =
  var target: Control = nil
  when compiles(control(cid)):
    try: target = control(cid)
    except CatchableError: target = nil
  if not target.isNil:
    for c in st.ctls:
      if not c.ctl.isNil and c.ctl == target: return c
  for c in st.ctls:
    if c.id == cid: return c
  nil

proc idText(cid: ControlId): string =
  when compiles($cid): result = $cid
  elif compiles(int(cid)): result = $int(cid)
  else: result = "?"

proc openWindows*(L: Interp): int =
  ## Nombre de fenêtres du programme encore ouvertes.
  let r = L.ext.getOrDefault("ui")
  if r.isNil: return 0
  for w in UiState(r).windows:
    if not w.closed: inc result

proc closeAllWindows*(L: Interp) =
  let r = L.ext.getOrDefault("ui")
  if r.isNil: return
  for w in UiState(r).windows:
    if not w.closed:
      w.closed = true
      closeWindow(w.id)

proc loopNeeded*(L: Interp): bool =
  ## Runtime autonome : faut-il lancer la boucle wdgui après le programme ?
  let r = L.ext.getOrDefault("ui")
  not r.isNil and not UiState(r).loopRunning and L.openWindows() > 0

#
# Valeurs nommées (français, ou anglais de wdgui)
#

proc layoutOf(s: string): typeof(lkVertical) =
  case s.toLowerAscii
  of "horizontal", "h", "rangee", "ligne", "row": lkHorizontal
  of "grille", "grid": lkGrid
  of "flux", "flow": lkFlow
  of "bordure", "border": lkBorder
  of "pile", "stack": lkStack
  of "absolue", "absolu", "absolute": lkAbsolute
  else: lkVertical

proc dockOf(s: string): typeof(dkTop) =
  case s.toLowerAscii
  of "haut", "top": dkTop
  of "bas", "bottom": dkBottom
  of "gauche", "left": dkLeft
  of "droite", "right": dkRight
  else: dkCenter

proc alignOf(s: string): typeof(alCenter) =
  case s.toLowerAscii
  of "centre", "center": result = alCenter
  of "droite", "right": result = alRight
  else:
    when declared(alLeft): result = alLeft
    else: result = alCenter

proc iconOf(s: string): typeof(iconStop) =
  case s.toLowerAscii
  of "stop", "erreur", "error": iconStop
  of "attention", "exclamation", "warning": iconExclamation
  of "question": iconQuestion
  of "aucune", "none": iconNone
  else: iconInformation

proc themeOf(name: string, dark: bool): Theme =
  case name.toLowerAscii
  of "windows", "windows11", "natif", "native": result = themeNative(dark = dark)
  of "macos", "mac": result = themeMacOS(dark = dark)
  of "linux", "gnome", "adwaita": result = themeLinux(dark = dark)
  else: result = themeFor(dark)

proc chartKindOf(s: string): typeof(ckColumn) =
  case s.toLowerAscii
  of "lignes", "courbe", "line": ckLine
  of "aires", "aire", "area": ckArea
  of "secteurs", "camembert", "pie": ckPie
  else: ckColumn

proc gridKindOf(s: string): typeof(gcText) =
  case s.toLowerAscii
  of "nombre", "number": gcNumber
  of "date": gcDate
  of "image": gcImage
  of "bouton", "button": gcButton
  of "combo": gcCombo
  of "case", "coche", "check", "checkbox": gcCheck
  else: gcText

proc footerOf(s: string): typeof(fkSum) =
  case s.toLowerAscii
  of "moyenne", "average", "avg": fkAverage
  of "min": fkMin
  of "max": fkMax
  of "nombre", "count": fkCount
  else: fkSum

proc editModeOf(s: string): typeof(emInherit) =
  case s.toLowerAscii
  of "lecture", "lectureseule", "readonly": emReadOnly
  of "modifiable", "editable": emEditable
  else: emInherit

proc fillModeOf(s: string): typeof(fmProgrammed) =
  case s.toLowerAscii
  of "manuel", "manual": fmManual
  of "automatique", "automatic": fmAutomatic
  else: fmProgrammed

proc compareOf(s: string): typeof(coEquals) =
  case s.toLowerAscii
  of "=", "==", "egal", "equals": coEquals
  of "<>", "!=", "~=", "different", "notequals": coNotEquals
  of "<": coLess
  of "<=": coLessOrEqual
  of ">": coGreater
  of ">=": coGreaterOrEqual
  of "contient", "contains": coContains
  of "vide", "empty": coEmpty
  else: coNotEmpty

proc stateName(id: ControlId): string =
  when compiles(id.state):
    let s = id.state
    if s == csGrayed: result = "grise"
    elif s == csReadOnly: result = "lecture"
    else: result = "actif"
  else: result = ""

proc stateOf(s: string): typeof(csActive) =
  case s.toLowerAscii
  of "grise", "inactif", "grayed", "disabled": csGrayed
  of "lecture", "lectureseule", "readonly": csReadOnly
  else: csActive

# ---------------------------------------------------------------------------
# Accès aux propriétés (getters/setters de l'API par identifiant)
# ---------------------------------------------------------------------------

template defGetter(pname, field, conv: untyped) =
  proc pname(id: ControlId): Value =
    when compiles(id.field): result = conv(id.field)
    else: result = nilV

defGetter(gValue, value, strV)
defGetter(gNum, valueNum, numV)
defGetter(gCaption, caption, strV)
defGetter(gVisible, visible, boolV)
defGetter(gTooltip, tooltip, strV)
defGetter(gX, x, numV)
defGetter(gY, y, numV)
defGetter(gWidth, width, numV)
defGetter(gHeight, height, numV)
defGetter(gMin, minBound, numV)
defGetter(gMax, maxBound, numV)

proc gName(id: ControlId): Value =
  when compiles(name(id)): result = strV(name(id))
  else: result = nilV

proc colorOf(v: Value): Color =
  if v.kind != vkStr: rtError("couleur attendue sous la forme \"#RRGGBB\"")
  hex(v.s)

proc numOf(v: Value, what: string): float =
  var ok: bool
  result = toFloat(v, ok)
  if not ok: rtError(what & " : nombre attendu")

proc unsupported(what: string) {.noreturn.} =
  rtError("propriété « " & what & " » non prise en charge par cette version de wdgui")

# NB : `compiles((a = b))` avec doubles parenthèses ; `compiles(a = b)` serait lu
# comme un argument nommé et vaudrait toujours faux.
template setNum(lhs: untyped, v: float, what = "") =
  when compiles((lhs = v)): lhs = v
  elif compiles((lhs = typeof(lhs)(v))): lhs = typeof(lhs)(v)
  else: unsupported(what)

template setAny(lhs: untyped, v: untyped, what: string) =
  when compiles((lhs = v)): lhs = v
  else: unsupported(what)

template setVia(c: UiCtl, idExpr, objField: untyped, v: untyped, what: string) =
  # Affectation par identifiant (API de wdgui) ; à défaut, sur l'objet Control sous le verrou de wdgui.
  when compiles((idExpr = v)):
    idExpr = v
  else:
    if c.ctl.isNil: unsupported(what)
    withControl(c.id, Control, obj):
      when compiles((obj.objField = v)): obj.objField = v
      else: unsupported(what)
    requestRedraw(c.id)

template doCall(call: untyped) =
  when typeof(call) is void: call
  else: discard call

proc anyV(x: bool): Value = boolV(x)
proc anyV(x: int): Value = intV(x)
proc anyV(x: float): Value = numV(x)
proc anyV(x: string): Value = strV(x)

proc typeNameOf(id: ControlId, family: string): Value =
  when compiles(controlType(id)): result = strV(controlType(id))
  else: result = strV(family)

proc ctlOf(v: Value, what = "contrôle"): UiCtl =
  if v.kind != vkUser or not (v.u of UiCtl): rtError(what & " attendu")
  UiCtl(v.u)

const captionFamilies = ["etiquette", "bouton", "fenetre", "page", "cadre"]

proc setProp(L: Interp, c: UiCtl, key: string, v: Value) =
  let id = c.id
  case key
  of "valeur", "texte":
    let txt = L.tostr(v)
    if c.family in captionFamilies and key == "texte":
      setVia(c, id.caption, caption, txt, key)
    elif int(id) == 0 and not c.ctl.isNil:
      # pas encore ajouté à une fenêtre (sans identifiant) : directement sur l'objet.
      guarded: c.ctl.setValueText(txt)
    else:
      when compiles((id.value = txt)): id.value = txt
      else:
        if c.ctl.isNil: unsupported(key)
        withControl(c.id, Control, obj): obj.setValueText(txt)
        requestRedraw(c.id)
  of "num": setNum(id.valueNum, numOf(v, "num"), key)
  of "libelle", "titre":
    let txt = L.tostr(v)
    setVia(c, id.caption, caption, txt, key)
  of "visible":
    let b = truthy(v)
    setVia(c, id.visible, visible, b, key)
  of "etat":
    let st = stateOf(L.tostr(v))
    setVia(c, id.state, state, st, key)
  of "actif":
    let st = if truthy(v): csActive else: csGrayed
    setVia(c, id.state, state, st, key)
  of "infobulle":
    let txt = L.tostr(v)
    setVia(c, id.tooltip, tooltip, txt, key)
  of "nom":
    let txt = L.tostr(v)
    setAny(id.name, txt, key)
  of "x": setNum(id.x, numOf(v, "x"), key)
  of "y": setNum(id.y, numOf(v, "y"), key)
  of "largeur": setNum(id.width, numOf(v, "largeur"), key)
  of "hauteur": setNum(id.height, numOf(v, "hauteur"), key)
  of "couleur", "couleurtexte":
    let col = colorOf(v)
    when compiles((id.color = col)): id.color = col
    else:
      if c.ctl.isNil: unsupported(key)
      c.ctl.style.text = some(col)
      requestRedraw(id)
  of "fond":
    let col = colorOf(v)
    when compiles((id.backgroundColor = col)): id.backgroundColor = col
    else:
      if c.ctl.isNil: unsupported(key)
      c.ctl.style.background = some(col)
      requestRedraw(id)
  of "bordure":
    let col = colorOf(v)
    setAny(id.borderColor, col, key)
  of "accent":
    let col = colorOf(v)
    setAny(id.accentColor, col, key)
  of "rayon": setNum(id.radius, numOf(v, "rayon"), key)
  of "coche":
    let txt = if truthy(v): "1" else: "0"
    setAny(id.value, txt, key)
  of "min": setNum(id.minBound, numOf(v, "min"), key)
  of "max": setNum(id.maxBound, numOf(v, "max"), key)
  of "theme":
    if c.family == "fenetre":
      let th = themeOf(L.tostr(v), false)
      setAny(id.theme, th, key)
  of "ancrage", "poids", "largeurfixe", "hauteurfixe", "etirer", "marge", "espacement", "colonnes":
    let o = c.ctl
    if o.isNil: rtError("propriété « " & key & " » indisponible pour une fenêtre")
    case key
    of "ancrage":
      let dk = dockOf(L.tostr(v))
      setAny(o.dock, dk, key)
    of "poids": setNum(o.weight, numOf(v, "poids"), key)
    of "largeurfixe": setNum(o.fixedWidth, numOf(v, "largeurfixe"), key)
    of "hauteurfixe": setNum(o.fixedHeight, numOf(v, "hauteurfixe"), key)
    of "etirer":
      let b = truthy(v)
      setAny(o.stretch, b, key)
    of "marge": setNum(Container(o).margin, numOf(v, "marge"), key)
    of "espacement": setNum(Container(o).spacing, numOf(v, "espacement"), key)
    else: setNum(Container(o).columns, numOf(v, "colonnes"), key)
    requestRedraw(id)
  else:
    if key.startsWith("sur"):
      if v.kind != vkNil and not L.callable(v):
        rtError("le gestionnaire « " & key & " » doit être une procédure (@NOM)")
      c.handlers.rawSet(key, v)
    else:
      rtError("propriété inconnue « " & key & " » (" & c.family & ")")

proc getProp(L: Interp, c: UiCtl, key: string): Value =
  let id = c.id
  case key
  of "valeur", "texte":
    if key == "texte" and c.family in captionFamilies: gCaption(id)
    else: gValue(id)
  of "num": gNum(id)
  of "libelle", "titre": gCaption(id)
  of "visible": gVisible(id)
  of "etat": strV(stateName(id))
  of "actif": boolV(stateName(id) == "actif")
  of "infobulle": gTooltip(id)
  of "nom": gName(id)
  of "x": gX(id)
  of "y": gY(id)
  of "largeur": gWidth(id)
  of "hauteur": gHeight(id)
  of "coche": boolV(id.value == "1")
  of "min": gMin(id)
  of "max": gMax(id)
  of "famille": strV(c.family)
  of "genre": typeNameOf(id, c.family)
  else:
    if key.startsWith("sur"): c.handlers.rawGet(key) else: nilV

#
# Événements
#

proc buttonName(b: typeof(mbLeft)): string =
  if b == mbRight: "droit" elif b == mbMiddle: "milieu" else: "gauche"

template evNum(t: LTable, ev: Event, field: untyped, key: string) =
  when compiles(float(ev.field)): t.set key, numV(float(ev.field))

template evInt(t: LTable, ev: Event, field: untyped, key: string) =
  when compiles(int(ev.field)): t.set key, intV(int(ev.field))

proc frenchEvent(k: string): string =
  ## Nom français d'un événement wdgui (« click » -> « clic »).
  case k
  of "click": "clic"
  of "doubleclick": "doubleclic"
  of "rightclick": "clicdroit"
  of "middleclick": "clicmilieu"
  of "rightdoubleclick": "doubleclicdroit"
  of "buttondown": "boutonbas"
  of "buttonup": "boutonhaut"
  of "mouseenter": "entree"
  of "mouseleave": "sortie"
  of "mousemove": "deplacement"
  of "wheel", "mousewheel": "molette"
  of "keydown": "touchebas"
  of "keyup": "touchehaut"
  of "textinput": "saisie"
  of "focusgained": "focus"
  of "focuslost": "finfocus"
  of "change": "changement"
  of "selection": "selection"
  of "expand": "deploiement"
  of "collapse": "repli"
  of "validate": "validation"
  of "windowopen": "ouverture"
  of "windowclose": "fermeture"
  of "windowresize": "redimension"
  of "windowactivate": "activation"
  of "windowdeactivate": "desactivation"
  else: k

proc buildEvent(L: Interp, st: UiState, ev: Event, kindName: string): LTable =
  let t = newLTable()
  t.set "genre", strV(kindName)
  let target = st.findCtl(ev.id)
  let current = st.findCtl(ev.current)
  if not target.isNil: t.set "id", userV(target)
  if not current.isNil: t.set "courant", userV(current)
  evNum(t, ev, x, "x")
  evNum(t, ev, y, "y")
  evNum(t, ev, dx, "dx")
  evNum(t, ev, dy, "dy")
  evInt(t, ev, key, "touche")
  evInt(t, ev, modifiers, "modificateurs")
  evInt(t, ev, index, "index")
  evInt(t, ev, column, "colonne")
  when compiles(ev.button == mbLeft): t.set "bouton", strV(buttonName(ev.button))
  when compiles(ev.isRepeat): t.set "repetition", boolV(ev.isRepeat)
  t.set "texte", strV(ev.text)
  if ev.text.contains(TreeSep):
    let path = newLTable()
    for p in ev.text.split(TreeSep): path.arr.add strV(p)
    t.set "chemin", tableV(path)
  t.set "arreter", fnV("arreter", proc (L: Interp, a: seq[Value]): seq[Value] =
    if arg(a, 1).kind == vkTable: a[0].t.set("arrete", boolV(true)))
  t

proc eventName(ev: Event): string =
  # Selon les versions de wdgui, $ev.kind vaut « evClick » ou « Click ».
  var k = $ev.kind
  if k.len > 2 and k.startsWith("ev") and k[2] in {'A'..'Z'}: k = k[2 .. ^1]
  frenchEvent(k.toLowerAscii)

proc scriptHandler(ev: var Event) {.nimcall, gcsafe.} =
  # Gestionnaire de toutes les fenêtres du programme. wdgui l'appelle pour la
  # cible puis pour chacun de ses parents (ev.current) ; on exécute à chaque
  # niveau le gestionnaire sur<événement> de l'objet correspondant.
  {.cast(gcsafe).}:
    var L: Interp = nil
    withLock uiLock:
      for cand in uiInterps:
        let r = cand.ext.getOrDefault("ui")
        if r.isNil: continue
        for w in UiState(r).windows:
          if w.id == ev.window:
            L = cand
            break
        if not L.isNil: break
    if L.isNil or L.stopRequested(): return
    let kindName = eventName(ev)
    L.enter()
    try:
      curCtx = Ctx()
      let st = L.uiState
      let cur = st.findCtl(ev.current)
      if st.trace and kindName notin ["deplacement", "entree", "sortie"]:
        L.output("[interface] " & kindName & " id=" & idText(ev.id) & " courant=" & idText(ev.current) &
                 " objet=" & (if cur.isNil: "aucun" else: cur.family) &
                 (if cur.isNil: "" else: " gestionnaire=" &
                    (if cur.handlers.rawGet("sur" & kindName).kind == vkNil: "non" else: "oui")) & "\n")
      if not cur.isNil:
        if ev.kind == evWindowClose and cur.family == "fenetre": cur.closed = true
        let h = cur.handlers.rawGet("sur" & kindName)
        let g = cur.handlers.rawGet("surevenement")
        if h.kind != vkNil or g.kind != vkNil:
          let evT = L.buildEvent(st, ev, kindName)
          if h.kind != vkNil: discard L.call(h, @[tableV(evT)])
          if g.kind != vkNil: discard L.call(g, @[tableV(evT)])
          if truthy(evT.get("arrete")): ev.stopPropagation()
    except LexisStop:
      discard
    except LexisError as e:
      L.onError(e.msg & "\n" & e.traceback)
    except Exception as e:
      # y compris les Defect de Nim, qui sinon tueraient le fil en silence
      L.onError("erreur interne dans le gestionnaire d'interface (" & kindName & ") : " & e.msg)
    finally:
      L.leave()

#
# Objets contrôles
#

var familyMethods: Table[string, LTable]

proc register(L: Interp, c: UiCtl): Value =
  c.handlers = newLTable()
  c.tname = "interface." & c.family
  c.meta = ctlMeta
  L.uiState.ctls.add c
  if c.family == "fenetre": L.uiState.windows.add c
  userV(c)

proc newCtl(L: Interp, ctl: Control, family: string): Value =
  L.register(UiCtl(rawId: ctl.id, ctl: ctl, family: family))

proc mfn(family, name: string, p: NativeProc) =
  if not familyMethods.hasKey(family): familyMethods[family] = newLTable()
  familyMethods[family].fn name, p

proc self(L: Interp, a: seq[Value], fname: string): UiCtl =
  let v = arg(a, 1)
  if v.kind != vkUser or not (v.u of UiCtl): rtError("« " & fname & " » : appelez-la avec « : » (objet:" & fname & "(...))")
  UiCtl(v.u)

proc strs(L: Interp, a: seq[Value], start: int, fname: string): seq[string] =
  # Arguments chaînes à partir de `start`, ou une liste de chaînes.
  if arg(a, start).kind == vkTable:
    let t = a[start - 1].t
    for i in 1 .. t.rawLen: result.add L.tostr(t.rawGet(intV(i)))
  else:
    for i in start .. a.len: result.add L.tostr(a[i - 1])

proc pathOf(L: Interp, a: seq[Value], start: int, fname: string): string =
  # Chemin d'arbre / de menu : "A", "B" ou {"A", "B"} ou "A/B".
  var parts = L.strs(a, start, fname)
  if parts.len == 1 and TreeSep notin parts[0] and '/' in parts[0]:
    parts = parts[0].split('/')
  parts.join($TreeSep)

template colArg(v: Value, body: untyped) =
  # Colonne de grille par nom ou par index.
  if v.kind == vkStr:
    let col {.inject.} = v.s
    body
  else:
    var okc: bool
    let col {.inject.} = int(toInteger(v, okc))
    if not okc: rtError("colonne attendue (nom ou index)")
    body

proc ctlIndex(L: Interp, a: seq[Value]): seq[Value] =
  let c = UiCtl(a[0].u)
  let key = arg(a, 2)
  if key.kind != vkStr: return @[nilV]
  if familyMethods.hasKey(c.family):
    let m = familyMethods[c.family].rawGet(key.s)
    if m.kind != vkNil: return @[m]
  let common = familyMethods.getOrDefault("*")
  if not common.isNil:
    let m = common.rawGet(key.s)
    if m.kind != vkNil: return @[m]
  @[L.getProp(c, key.s.toLowerAscii)]

proc ctlNewIndex(L: Interp, a: seq[Value]): seq[Value] =
  let c = UiCtl(a[0].u)
  let key = arg(a, 2)
  if key.kind != vkStr: rtError("nom de propriété attendu")
  L.setProp(c, key.s.toLowerAscii, arg(a, 3))

proc addChildTo(L: Interp, parent: UiCtl, child: UiCtl) =
  if child.ctl.isNil: rtError("une fenêtre ne peut pas être ajoutée à un conteneur")
  if parent.family == "fenetre":
    discard parent.win.addChild(child.ctl)
  elif parent.ctl of Container:
    discard Container(parent.ctl).addChild(child.ctl)
  else:
    rtError("« " & parent.family & " » n'est pas un conteneur")

proc programPath(L: Interp, path: string): string =
  ## Chemin relatif au dossier du programme (comme webview).
  if path.isAbsolute: path
  else: (if L.scriptPath.len > 0: L.scriptPath.parentDir else: getCurrentDir()) / path

proc readMarkdown(L: Interp, path, fname: string): string =
  let p = L.programPath(path)
  try: result = readFile(p)
  except IOError, OSError: rtError(fname & " : lecture impossible de « " & p & " »")

template withMarkdown(L: Interp, a: seq[Value], fname: string, v, body: untyped) =
  # Accès direct à l'objet sous le verrou de wdgui (fonctionne aussi avant
  # l'ajout du contrôle à une fenêtre, quand il n'a pas encore d'identifiant).
  block:
    let c0 = L.self(a, fname)
    if c0.ctl.isNil or not (c0.ctl of MarkdownView): rtError("« " & fname & " » : contrôle markdown attendu")
    guarded:
      let v = MarkdownView(c0.ctl)
      body
      markDirty(v)
    wakeUI()

proc edOf(L: Interp, a: seq[Value], fname: string): ControlId =
  # Identifiant de l'éditeur (l'API de l'éditeur passe par l'identifiant wdgui).
  let c = L.self(a, fname)
  if c.ctl.isNil or not (c.ctl of CodeEditor): rtError("« " & fname & " » : éditeur attendu")
  if int(c.id) == 0: rtError("« " & fname & " » : ajoutez d'abord l'éditeur à une fenêtre")
  c.id

proc uidArg(L: Interp, a: seq[Value], i: int, id: ControlId, fname: string): int =
  if arg(a, i).kind == vkNil: editorActiveUid(id) else: int(L.checkInt(a, i, fname))

proc diagOf(L: Interp, t: LTable, lines: seq[string]): Diagnostic =
  let ln = max(1, optField(t, "ligne", 1)) - 1
  let col = max(1, optField(t, "colonne", 1)) - 1
  var bcol = col
  if ln < lines.len:
    let o = runeOffset(lines[ln], col)
    bcol = if o < 0: lines[ln].len else: o
  let sev = case optField(t, "genre", "erreur").toLowerAscii
    of "avertissement", "warning": sevWarning
    of "info", "information": sevInfo
    else: sevError
  Diagnostic(line: ln, col: bcol, len: max(1, optField(t, "longueur", 1)), sev: sev,
             msg: optField(t, "message", ""))

proc findReqOf(texte: string, o: LTable, remplacement = ""): FindRequest =
  result.findText = texte
  result.replaceText = remplacement
  result.matchCase = optField(o, "casse", false)
  result.wholeWord = optField(o, "motentier", false)
  result.backwards = optField(o, "arriere", false)

template withCanvas(L: Interp, a: seq[Value], fname: string, v, body: untyped) =
  # Concepteur de formulaires : l'objet sous le verrou de wdgui.
  block:
    let c0 = L.self(a, fname)
    if c0.ctl.isNil or not (c0.ctl of FormCanvas): rtError("« " & fname & " » : concepteur attendu")
    guarded:
      let v = FormCanvas(c0.ctl)
      body
      markDirty(v)
    wakeUI()

proc nodeArg(L: Interp, c: FormCanvas, a: seq[Value], i: int, fname: string): DNode =
  # Nœud désigné par son uid (argument i), sinon le nœud sélectionné (ou la fenêtre).
  if arg(a, i).kind == vkNil:
    result = if c.selected != nil: c.selected else: c.model.root
  else:
    result = c.nodeByUid(int(L.checkInt(a, i, fname)))
    if result == nil: rtError(fname & " : élément inconnu (uid " & $L.checkInt(a, i, fname) & ")")

proc kindName(k: PropKind): string =
  case k
  of pkString: "texte"
  of pkInt: "entier"
  of pkFloat: "nombre"
  of pkBool: "logique"
  of pkEnum: "choix"
  of pkColor: "couleur"
  of pkList: "liste"

proc diaOpts(a: seq[Value], i: int): LTable =
  if arg(a, i).kind == vkTable: a[i - 1].t else: nil

template withDiagram(L: Interp, a: seq[Value], fname: string, v, body: untyped) =
  # Diagramme : le canevas sous le verrou de wdgui.
  block:
    let c0 = L.self(a, fname)
    if c0.ctl.isNil or not (c0.ctl of DiagramCanvas): rtError("« " & fname & " » : diagramme attendu")
    guarded:
      let v = DiagramCanvas(c0.ctl)
      body
      markDirty(v)
    wakeUI()

template withReport(L: Interp, a: seq[Value], fname: string, v, body: untyped) =
  # Éditeur d'états : le canevas sous le verrou de wdgui.
  block:
    let c0 = L.self(a, fname)
    if c0.ctl.isNil or not (c0.ctl of ReportCanvas): rtError("« " & fname & " » : éditeur d'état attendu")
    guarded:
      let v = ReportCanvas(c0.ctl)
      body
      markDirty(v)
    wakeUI()

proc subtree(c: Control, acc: var seq[Control]) =
  acc.add c
  if c of Container:
    for e in Container(c).children: subtree(e, acc)

proc defineMethods() =
  # communs
  mfn "*", "ajouter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.self(a, "ajouter")
    for i in 2 .. a.len:
      L.addChildTo(p, ctlOf(a[i - 1], "contrôle à ajouter"))
    @[arg(a, 2)]
  mfn "*", "focus", proc (L: Interp, a: seq[Value]): seq[Value] =
    setFocus(L.self(a, "focus").id)
  mfn "*", "menucontextuel", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.self(a, "menucontextuel")
    openContextMenu(c.id, L.strs(a, 2, "menucontextuel"))
  mfn "*", "detruire", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Retire le contrôle (et son contenu) de sa fenêtre.
    let c = L.self(a, "detruire")
    if c.ctl.isNil: rtError("detruire : utilisez fen:fermer() pour une fenêtre")
    var gone: seq[Control]
    guarded: subtree(c.ctl, gone)
    if int(c.id) != 0: deleteControl(c.id)
    else:
      guarded:
        if c.ctl.parent != nil:
          let i = c.ctl.parent.children.find(c.ctl)
          if i >= 0: c.ctl.parent.children.delete(i)
          c.ctl.parent = nil
    let st = L.uiState
    var keep: seq[UiCtl]
    for x in st.ctls:
      if x.ctl.isNil or x.ctl notin gone: keep.add x
    st.ctls = keep
  mfn "*", "redessiner", proc (L: Interp, a: seq[Value]): seq[Value] =
    requestRedraw(L.self(a, "redessiner").id)

  # fenêtre
  mfn "fenetre", "fermer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let w = L.self(a, "fermer")
    if not w.closed:
      w.closed = true
      closeWindow(w.id)
  mfn "fenetre", "fixertheme", proc (L: Interp, a: seq[Value]): seq[Value] =
    let w = L.self(a, "fixertheme")
    let th = themeOf(L.optStr(a, 2, "fixertheme", "natif"), optBool(a, 3, false))
    setAny(w.id.theme, th, "theme")

  # onglets
  mfn "onglets", "ajouterpage", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.self(a, "ajouterpage")
    let page = typeof(newTab())(t.ctl).addPage(L.checkStr(a, 2, "ajouterpage"),
                                               layoutOf(L.optStr(a, 3, "ajouterpage", "vertical")))
    @[L.newCtl(page, "page")]

  # listes et combos
  for fam in ["liste", "combo"]:
    mfn fam, "ajouter", proc (L: Interp, a: seq[Value]): seq[Value] =
      let c = L.self(a, "ajouter")
      var last = 0
      for s in L.strs(a, 2, "ajouter"): last = listAdd(c.id, s)
      @[intV(last)]
    mfn fam, "inserer", proc (L: Interp, a: seq[Value]): seq[Value] =
      let c = L.self(a, "inserer")
      let idx = int(L.checkInt(a, 2, "inserer"))
      let item = L.checkStr(a, 3, "inserer")
      listInsert(c.id, item, idx)
    mfn fam, "supprimer", proc (L: Interp, a: seq[Value]): seq[Value] =
      listDelete(L.self(a, "supprimer").id, int(L.checkInt(a, 2, "supprimer")))
    mfn fam, "vider", proc (L: Interp, a: seq[Value]): seq[Value] =
      listDeleteAll(L.self(a, "vider").id)
    mfn fam, "selectionner", proc (L: Interp, a: seq[Value]): seq[Value] =
      listSelectPlus(L.self(a, "selectionner").id, int(L.checkInt(a, 2, "selectionner")))
    mfn fam, "deselectionner", proc (L: Interp, a: seq[Value]): seq[Value] =
      listSelectMinus(L.self(a, "deselectionner").id, int(L.checkInt(a, 2, "deselectionner")))
    mfn fam, "selection", proc (L: Interp, a: seq[Value]): seq[Value] =
      let v = L.self(a, "selection").id.value
      try: @[intV(parseInt(v))] except ValueError: @[intV(0)]
    mfn fam, "nombre", proc (L: Interp, a: seq[Value]): seq[Value] =
      @[intV(listCount(L.self(a, "nombre").id))]
    mfn fam, "element", proc (L: Interp, a: seq[Value]): seq[Value] =
      @[strV(listItem(L.self(a, "element").id, int(L.checkInt(a, 2, "element"))))]
    mfn fam, "modifier", proc (L: Interp, a: seq[Value]): seq[Value] =
      listModify(L.self(a, "modifier").id, L.checkStr(a, 3, "modifier"), int(L.checkInt(a, 2, "modifier")))
    mfn fam, "chercher", proc (L: Interp, a: seq[Value]): seq[Value] =
      @[intV(listSeek(L.self(a, "chercher").id, L.checkStr(a, 2, "chercher")))]

  # tableau simple
  mfn "tableau", "ajoutercolonne", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.self(a, "ajoutercolonne")
    let title = L.checkStr(a, 2, "ajoutercolonne")
    let w = L.optNum(a, 3, "ajoutercolonne", 120)
    let al = alignOf(L.optStr(a, 4, "ajoutercolonne", "gauche"))
    tableAddColumn(c.id, title, w, al)
  mfn "tableau", "ajouterligne", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[anyV(tableAddLine(L.self(a, "ajouterligne").id, L.strs(a, 2, "ajouterligne")))]
  mfn "tableau", "insererligne", proc (L: Interp, a: seq[Value]): seq[Value] =
    tableInsertLine(L.self(a, "insererligne").id, int(L.checkInt(a, 2, "insererligne")), L.strs(a, 3, "insererligne"))
  mfn "tableau", "supprimer", proc (L: Interp, a: seq[Value]): seq[Value] =
    tableDelete(L.self(a, "supprimer").id, int(L.checkInt(a, 2, "supprimer")))
  mfn "tableau", "vider", proc (L: Interp, a: seq[Value]): seq[Value] =
    tableDeleteAll(L.self(a, "vider").id)
  mfn "tableau", "selection", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(tableSelect(L.self(a, "selection").id))]
  mfn "tableau", "selectionner", proc (L: Interp, a: seq[Value]): seq[Value] =
    tableSelectPlus(L.self(a, "selectionner").id, int(L.checkInt(a, 2, "selectionner")))
  mfn "tableau", "nombre", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(tableCount(L.self(a, "nombre").id))]
  mfn "tableau", "cellule", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(tableCell(L.self(a, "cellule").id, int(L.checkInt(a, 2, "cellule")), int(L.checkInt(a, 3, "cellule"))))]
  mfn "tableau", "fixercellule", proc (L: Interp, a: seq[Value]): seq[Value] =
    tableSetCell(L.self(a, "fixercellule").id, int(L.checkInt(a, 2, "fixercellule")),
                 int(L.checkInt(a, 3, "fixercellule")), L.checkStr(a, 4, "fixercellule"))
  mfn "tableau", "ligne", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[toV(tableLine(L.self(a, "ligne").id, int(L.checkInt(a, 2, "ligne"))))]
  mfn "tableau", "trier", proc (L: Interp, a: seq[Value]): seq[Value] =
    tableSort(L.self(a, "trier").id, int(L.checkInt(a, 2, "trier")), ascending = optBool(a, 3, true))

  # arbre
  mfn "arbre", "ajouter", proc (L: Interp, a: seq[Value]): seq[Value] =
    treeAdd(L.self(a, "ajouter").id, L.pathOf(a, 2, "ajouter"))
  mfn "arbre", "supprimer", proc (L: Interp, a: seq[Value]): seq[Value] =
    treeDelete(L.self(a, "supprimer").id, L.pathOf(a, 2, "supprimer"))
  mfn "arbre", "vider", proc (L: Interp, a: seq[Value]): seq[Value] =
    treeDeleteAll(L.self(a, "vider").id)
  mfn "arbre", "deplier", proc (L: Interp, a: seq[Value]): seq[Value] =
    treeExpand(L.self(a, "deplier").id, L.pathOf(a, 2, "deplier"))
  mfn "arbre", "replier", proc (L: Interp, a: seq[Value]): seq[Value] =
    treeCollapse(L.self(a, "replier").id, L.pathOf(a, 2, "replier"))
  mfn "arbre", "estdeplie", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[boolV(treeIsExpanded(L.self(a, "estdeplie").id, L.pathOf(a, 2, "estdeplie")))]
  mfn "arbre", "selectionner", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.self(a, "selectionner")
    when compiles(treeSelectPlus(c.id, "")): treeSelectPlus(c.id, L.pathOf(a, 2, "selectionner"))
  mfn "arbre", "nombre", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.self(a, "nombre")
    when compiles(treeCount(c.id)): result = @[intV(treeCount(c.id))]

  # menu
  mfn "barremenu", "ajouter", proc (L: Interp, a: seq[Value]): seq[Value] =
    menuAdd(L.self(a, "ajouter").id, L.pathOf(a, 2, "ajouter"))

  # cases à cocher, boutons radio
  mfn "cases", "coche", proc (L: Interp, a: seq[Value]): seq[Value] =
    let v = checkBoxValue(L.self(a, "coche").id, int(L.optInt(a, 2, "coche", 1)))
    when v is bool: result = @[boolV(v)]
    elif v is string: result = @[boolV(v == "1")]
    else: result = @[boolV(v != 0)]
  mfn "cases", "cocher", proc (L: Interp, a: seq[Value]): seq[Value] =
    checkBoxSet(L.self(a, "cocher").id, int(L.checkInt(a, 2, "cocher")), optBool(a, 3, true))
  mfn "cases", "ajouteroption", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.self(a, "ajouteroption")
    doCall(checkBoxAdd(c.id, L.checkStr(a, 2, "ajouteroption")))
  mfn "radio", "ajouteroption", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.self(a, "ajouteroption")
    doCall(radioAdd(c.id, L.checkStr(a, 2, "ajouteroption")))

  # graphe, calendrier, planning
  mfn "graphe", "ajouterdonnee", proc (L: Interp, a: seq[Value]): seq[Value] =
    grAddData(L.self(a, "ajouterdonnee").id, int(L.checkInt(a, 2, "ajouterdonnee")),
              int(L.checkInt(a, 3, "ajouterdonnee")), L.checkNum(a, 4, "ajouterdonnee"))
  mfn "graphe", "libellecategorie", proc (L: Interp, a: seq[Value]): seq[Value] =
    grCategoryLabel(L.self(a, "libellecategorie").id, int(L.checkInt(a, 2, "libellecategorie")),
                    L.checkStr(a, 3, "libellecategorie"))
  mfn "graphe", "libelleserie", proc (L: Interp, a: seq[Value]): seq[Value] =
    grSeriesLabel(L.self(a, "libelleserie").id, int(L.checkInt(a, 2, "libelleserie")), L.checkStr(a, 3, "libelleserie"))
  mfn "graphe", "fixergenre", proc (L: Interp, a: seq[Value]): seq[Value] =
    grType(L.self(a, "fixergenre").id, chartKindOf(L.checkStr(a, 2, "fixergenre")))
  mfn "calendrier", "afficher", proc (L: Interp, a: seq[Value]): seq[Value] =
    calendarShow(L.self(a, "afficher").id, int(L.checkInt(a, 2, "afficher")), int(L.checkInt(a, 3, "afficher")))
  mfn "kanban", "ajouterliste", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[anyV(kanbanAddList(L.self(a, "ajouterliste").id, L.checkStr(a, 2, "ajouterliste")))]
  mfn "kanban", "ajouter", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[anyV(kanbanAdd(L.self(a, "ajouter").id, int(L.checkInt(a, 2, "ajouter")), L.checkStr(a, 3, "ajouter")))]
  mfn "mosaique", "ajouter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.self(a, "ajouter")
    let lbl = L.checkStr(a, 2, "ajouter")
    let v = L.checkNum(a, 3, "ajouter")
    treeMapAdd(c.id, lbl, v)
  mfn "gantt", "ajoutertache", proc (L: Interp, a: seq[Value]): seq[Value] =
    # ajoutertache(libelle, debut, duree, [avancement], [couleur], [detail])
    let col = if arg(a, 6).kind == vkStr and a[5].s.len > 0: colorOf(a[5]) else: Color()
    @[anyV(ganttAddTask(L.self(a, "ajoutertache").id, L.checkStr(a, 2, "ajoutertache"),
                        start = L.checkNum(a, 3, "ajoutertache"), duration = L.checkNum(a, 4, "ajoutertache"),
                        progress = L.optNum(a, 5, "ajoutertache", 0), color = col,
                        detail = L.optStr(a, 7, "ajoutertache", "")))]
  mfn "gantt", "vider", proc (L: Interp, a: seq[Value]): seq[Value] =
    ganttDeleteAll(L.self(a, "vider").id)
  mfn "gantt", "horaire", proc (L: Interp, a: seq[Value]): seq[Value] =
    ganttClockAxis(L.self(a, "horaire").id, optBool(a, 2, true))
  mfn "gantt", "largeurlibelles", proc (L: Interp, a: seq[Value]): seq[Value] =
    ganttLabelWidth(L.self(a, "largeurlibelles").id, L.checkNum(a, 2, "largeurlibelles"))
  mfn "gantt", "fixeravancement", proc (L: Interp, a: seq[Value]): seq[Value] =
    ganttSetProgress(L.self(a, "fixeravancement").id, int(L.checkInt(a, 2, "fixeravancement")),
                     L.checkNum(a, 3, "fixeravancement"))

  # panneau défilant
  mfn "panneau", "defilera", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.self(a, "defilera")
    let x = L.checkNum(a, 2, "defilera")
    let y = L.checkNum(a, 3, "defilera")
    panelScrollTo(c.id, x, y)
  mfn "panneau", "defilerde", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.self(a, "defilerde")
    let x = L.checkNum(a, 2, "defilerde")
    let y = L.checkNum(a, 3, "defilerde")
    panelScrollBy(c.id, x, y)
  mfn "panneau", "rendrevisible", proc (L: Interp, a: seq[Value]): seq[Value] =
    panelEnsureVisible(L.self(a, "rendrevisible").id, ctlOf(arg(a, 2)).id)

  # grille
  mfn "grille", "ajoutercolonne", proc (L: Interp, a: seq[Value]): seq[Value] =
    let g = L.self(a, "ajoutercolonne")
    var name, title, kind: string
    var width = 120.0
    var choices: seq[string]
    var decimals = -1
    if arg(a, 2).kind == vkTable:
      let o = a[1].t
      name = optField(o, "nom", "")
      title = optField(o, "titre", name)
      kind = optField(o, "genre", "texte")
      width = optField(o, "largeur", 120.0)
      decimals = optField(o, "decimales", -1)
      let ch = o.field("choix")
      if ch.kind == vkTable:
        for i in 1 .. ch.t.rawLen: choices.add L.tostr(ch.t.rawGet(intV(i)))
    else:
      name = L.checkStr(a, 2, "ajoutercolonne")
      title = L.optStr(a, 3, "ajoutercolonne", name)
      kind = L.optStr(a, 4, "ajoutercolonne", "texte")
      width = L.optNum(a, 5, "ajoutercolonne", 120)
    var colId: ControlId
    let gk = gridKindOf(kind)
    when compiles(gridAddColumn(g.id, name, title, gk, width, choices = choices, decimals = decimals)):
      colId = gridAddColumn(g.id, name, title, gk, width, choices = choices, decimals = decimals)
    else:
      colId = gridAddColumn(g.id, name, title, gk, width)
      if choices.len > 0: gridSetChoices(g.id, name, choices)
      if decimals >= 0: gridSetDecimals(g.id, name, decimals)
    @[L.register(UiCtl(rawId: colId, family: "colonnegrille"))]
  mfn "grille", "ajouterligne", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[anyV(gridAddLine(L.self(a, "ajouterligne").id, L.strs(a, 2, "ajouterligne")))]
  mfn "grille", "insererligne", proc (L: Interp, a: seq[Value]): seq[Value] =
    gridInsertLine(L.self(a, "insererligne").id, int(L.checkInt(a, 2, "insererligne")), L.strs(a, 3, "insererligne"))
  mfn "grille", "modifierligne", proc (L: Interp, a: seq[Value]): seq[Value] =
    gridModifyLine(L.self(a, "modifierligne").id, int(L.checkInt(a, 2, "modifierligne")), L.strs(a, 3, "modifierligne"))
  mfn "grille", "supprimerligne", proc (L: Interp, a: seq[Value]): seq[Value] =
    gridDeleteLine(L.self(a, "supprimerligne").id, int(L.checkInt(a, 2, "supprimerligne")))
  mfn "grille", "vider", proc (L: Interp, a: seq[Value]): seq[Value] =
    gridDeleteAll(L.self(a, "vider").id)
  mfn "grille", "cellule", proc (L: Interp, a: seq[Value]): seq[Value] =
    let g = L.self(a, "cellule")
    let row = int(L.checkInt(a, 2, "cellule"))
    colArg(arg(a, 3)):
      result = @[strV(gridCell(g.id, row, col))]
  mfn "grille", "fixercellule", proc (L: Interp, a: seq[Value]): seq[Value] =
    let g = L.self(a, "fixercellule")
    let row = int(L.checkInt(a, 2, "fixercellule"))
    let v = L.tostr(arg(a, 4))
    colArg(arg(a, 3)):
      gridSetCell(g.id, row, col, v)
  mfn "grille", "ligne", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[toV(gridLine(L.self(a, "ligne").id, int(L.checkInt(a, 2, "ligne"))))]
  mfn "grille", "nombre", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(gridCount(L.self(a, "nombre").id))]
  mfn "grille", "nombrecolonnes", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(gridColumnCount(L.self(a, "nombrecolonnes").id))]
  mfn "grille", "colonne", proc (L: Interp, a: seq[Value]): seq[Value] =
    let g = L.self(a, "colonne")
    var cid: ControlId
    colArg(arg(a, 2)):
      cid = gridColumn(g.id, col)
    let existing = L.uiState.findCtl(cid)
    if not existing.isNil: return @[userV(existing)]
    @[L.register(UiCtl(rawId: cid, family: "colonnegrille"))]
  mfn "grille", "selection", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(gridSelect(L.self(a, "selection").id, int(L.optInt(a, 2, "selection", 1))))]
  mfn "grille", "nombreselection", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(gridSelectCount(L.self(a, "nombreselection").id))]
  mfn "grille", "selectionner", proc (L: Interp, a: seq[Value]): seq[Value] =
    gridSelectPlus(L.self(a, "selectionner").id, int(L.checkInt(a, 2, "selectionner")))
  mfn "grille", "deselectionner", proc (L: Interp, a: seq[Value]): seq[Value] =
    gridSelectMinus(L.self(a, "deselectionner").id, int(L.checkInt(a, 2, "deselectionner")))
  mfn "grille", "toutselectionner", proc (L: Interp, a: seq[Value]): seq[Value] =
    gridSelectAll(L.self(a, "toutselectionner").id)
  mfn "grille", "trier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let g = L.self(a, "trier")
    let asc = optBool(a, 3, true)
    colArg(arg(a, 2)):
      gridSort(g.id, col, ascending = asc)
  mfn "grille", "chercher", proc (L: Interp, a: seq[Value]): seq[Value] =
    let g = L.self(a, "chercher")
    let value = L.checkStr(a, 3, "chercher")
    let exact = optBool(a, 4, true)
    let start = int(L.optInt(a, 5, "chercher", 1))
    colArg(arg(a, 2)):
      result = @[intV(gridSeek(g.id, col, value, exact = exact, start = start))]
  mfn "grille", "trouver", proc (L: Interp, a: seq[Value]): seq[Value] =
    let f = gridFind(L.self(a, "trouver").id, L.checkStr(a, 2, "trouver"))
    @[record({"ligne": intV(f.row), "colonne": intV(f.column)})]
  mfn "grille", "fixerpied", proc (L: Interp, a: seq[Value]): seq[Value] =
    let g = L.self(a, "fixerpied")
    let k = footerOf(L.optStr(a, 3, "fixerpied", "somme"))
    colArg(arg(a, 2)):
      gridSetFooter(g.id, col, k)
  mfn "grille", "valeurpied", proc (L: Interp, a: seq[Value]): seq[Value] =
    let g = L.self(a, "valeurpied")
    let kv = arg(a, 3)
    colArg(arg(a, 2)):
      if kv.kind == vkNil: result = @[strV($gridFooterValue(g.id, col))]
      else: result = @[strV($gridFooterValue(g.id, col, footerOf(L.tostr(kv))))]
  mfn "grille", "ajouterformat", proc (L: Interp, a: seq[Value]): seq[Value] =
    let g = L.self(a, "ajouterformat")
    let op = compareOf(L.checkStr(a, 3, "ajouterformat"))
    let value = L.optStr(a, 4, "ajouterformat", "")
    let o = if arg(a, 5).kind == vkTable: a[4].t else: nil
    let bg = optField(o, "fond", "")
    let fg = optField(o, "texte", "")
    let whole = optField(o, "ligneentiere", false)
    let bgc = if bg.len > 0: hex(bg) else: Transparent
    let fgc = if fg.len > 0: hex(fg) else: Transparent
    colArg(arg(a, 2)):
      when compiles(gridAddFormat(g.id, col, op, value, background = bgc, text = fgc, wholeRow = whole)):
        gridAddFormat(g.id, col, op, value, background = bgc, text = fgc, wholeRow = whole)
      elif compiles(gridAddFormat(g.id, col, op, value, bgc, fgc, whole)):
        gridAddFormat(g.id, col, op, value, bgc, fgc, whole)
      else:
        rtError("grille:ajouterformat : signature de gridAddFormat non reconnue")
  mfn "grille", "effacerformats", proc (L: Interp, a: seq[Value]): seq[Value] =
    gridClearFormats(L.self(a, "effacerformats").id)
  mfn "grille", "fixerrupture", proc (L: Interp, a: seq[Value]): seq[Value] =
    let g = L.self(a, "fixerrupture")
    if arg(a, 2).kind == vkNil: gridSetBreak(g.id, "")
    else:
      colArg(arg(a, 2)):
        gridSetBreak(g.id, col)
  mfn "grille", "fixermodifiable", proc (L: Interp, a: seq[Value]): seq[Value] =
    gridSetEditable(L.self(a, "fixermodifiable").id, optBool(a, 2, true))
  mfn "grille", "fixermodecolonne", proc (L: Interp, a: seq[Value]): seq[Value] =
    let g = L.self(a, "fixermodecolonne")
    let m = editModeOf(L.checkStr(a, 3, "fixermodecolonne"))
    colArg(arg(a, 2)):
      gridSetColumnEdit(g.id, col, m)
  mfn "grille", "fixermodeligne", proc (L: Interp, a: seq[Value]): seq[Value] =
    gridSetLineEdit(L.self(a, "fixermodeligne").id, int(L.checkInt(a, 2, "fixermodeligne")),
                    editModeOf(L.checkStr(a, 3, "fixermodeligne")))
  mfn "grille", "fixerremplissage", proc (L: Interp, a: seq[Value]): seq[Value] =
    gridSetFillMode(L.self(a, "fixerremplissage").id, fillModeOf(L.checkStr(a, 2, "fixerremplissage")))
  mfn "grille", "fixerlibellebouton", proc (L: Interp, a: seq[Value]): seq[Value] =
    let g = L.self(a, "fixerlibellebouton")
    let cap = L.checkStr(a, 3, "fixerlibellebouton")
    colArg(arg(a, 2)):
      gridSetButtonCaption(g.id, col, cap)
  mfn "grille", "modifiercellule", proc (L: Interp, a: seq[Value]): seq[Value] =
    let g = L.self(a, "modifiercellule")
    let row = int(L.checkInt(a, 2, "modifiercellule"))
    colArg(arg(a, 3)):
      gridStartEdit(g.id, row, col)
  mfn "grille", "verscsv", proc (L: Interp, a: seq[Value]): seq[Value] =
    let sep = L.optStr(a, 2, "verscsv", ",")
    @[strV(gridToCsv(L.self(a, "verscsv").id, sep = sep[0], header = optBool(a, 3, true)))]
  mfn "grille", "decsv", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[anyV(gridFromCsv(L.self(a, "decsv").id, L.checkStr(a, 2, "decsv"), append = optBool(a, 3, false)))]
  mfn "grille", "chargercsv", proc (L: Interp, a: seq[Value]): seq[Value] =
    let sep = L.optStr(a, 3, "chargercsv", ",")
    @[anyV(gridLoadCsv(L.self(a, "chargercsv").id, L.checkStr(a, 2, "chargercsv"), sep = sep[0]))]
  mfn "grille", "enregistrercsv", proc (L: Interp, a: seq[Value]): seq[Value] =
    let sep = L.optStr(a, 3, "enregistrercsv", ",")
    @[anyV(gridSaveCsv(L.self(a, "enregistrercsv").id, L.checkStr(a, 2, "enregistrercsv"), sep = sep[0]))]
  mfn "grille", "versjson", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(gridToJson(L.self(a, "versjson").id, pretty = optBool(a, 2, true)))]
  mfn "grille", "chargerjson", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[anyV(gridLoadJson(L.self(a, "chargerjson").id, L.checkStr(a, 2, "chargerjson")))]
  mfn "grille", "enregistrerjson", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[anyV(gridSaveJson(L.self(a, "enregistrerjson").id, L.checkStr(a, 2, "enregistrerjson")))]

  # visionneuse PDF
  mfn "pdf", "ouvrir", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[anyV(pdfOpen(L.self(a, "ouvrir").id, L.checkStr(a, 2, "ouvrir"), L.optStr(a, 3, "ouvrir", "")))]
  mfn "pdf", "nouveau", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.self(a, "nouveau")
    let w = L.optNum(a, 2, "nouveau", 595)
    let h = L.optNum(a, 3, "nouveau", 842)
    @[boolV(pdfNew(c.id, w, h))]
  mfn "pdf", "enregistrer", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[anyV(pdfSave(L.self(a, "enregistrer").id, L.optStr(a, 2, "enregistrer", "")))]
  mfn "pdf", "fermer", proc (L: Interp, a: seq[Value]): seq[Value] =
    doCall(pdfClose(L.self(a, "fermer").id))
  mfn "pdf", "nombrepages", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[anyV(pdfPageCount(L.self(a, "nombrepages").id))]
  mfn "pdf", "page", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[anyV(pdfCurrentPage(L.self(a, "page").id))]
  mfn "pdf", "allera", proc (L: Interp, a: seq[Value]): seq[Value] =
    doCall(pdfGoto(L.self(a, "allera").id, int(L.checkInt(a, 2, "allera"))))
  mfn "pdf", "zoom", proc (L: Interp, a: seq[Value]): seq[Value] =
    doCall(pdfSetZoom(L.self(a, "zoom").id, L.checkNum(a, 2, "zoom")))
  mfn "pdf", "ajoutertexte", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = L.self(a, "ajoutertexte")
    let pg = int(L.checkInt(a, 2, "ajoutertexte"))
    let x = L.checkNum(a, 3, "ajoutertexte")
    let y = L.checkNum(a, 4, "ajoutertexte")
    let txt = L.checkStr(a, 5, "ajoutertexte")
    let size = L.optNum(a, 6, "ajoutertexte", 14)
    pdfAddText(c.id, pg, x, y, txt, size)
  mfn "pdf", "importerpages", proc (L: Interp, a: seq[Value]): seq[Value] =
    let err = pdfImportPages(L.self(a, "importerpages").id, L.checkStr(a, 2, "importerpages"),
                             L.optStr(a, 3, "importerpages", ""), int(L.optInt(a, 4, "importerpages", 1)))
    if err.len > 0: fail(err) else: @[boolV(true)]

  # éditeur de code Lexis+ (multi-documents)
  mfn "editeur", "ouvrir", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.edOf(a, "ouvrir")
    let p = absolutePath(L.programPath(L.checkStr(a, 2, "ouvrir"))).normalizedPath
    var txt = ""
    if fileExists(p):
      try: txt = readFile(p)
      except IOError, OSError: rtError("editeur:ouvrir : lecture impossible de « " & p & " »")
    elif not optBool(a, 3, false): rtError("editeur:ouvrir : fichier introuvable « " & p & " »")
    @[intV(editorOpen(id, p, txt))]
  mfn "editeur", "nouveau", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(editorNew(L.edOf(a, "nouveau"), L.optStr(a, 2, "nouveau", "sans titre")))]
  mfn "editeur", "texte", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.edOf(a, "texte")
    @[strV(editorText(id, L.uidArg(a, 2, id, "texte")))]
  mfn "editeur", "enregistrer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.edOf(a, "enregistrer")
    let uid = L.uidArg(a, 3, id, "enregistrer")
    let info = editorInfo(id, uid)
    var p = if arg(a, 2).kind == vkNil: info.path else: L.programPath(L.checkStr(a, 2, "enregistrer"))
    if p.len == 0: rtError("editeur:enregistrer : document sans chemin (indiquez-en un)")
    p = absolutePath(p).normalizedPath
    let snap = editorSnapshot(id, uid)
    try: writeFile(p, snap.lines.join("\n"))
    except IOError, OSError: rtError("editeur:enregistrer : écriture impossible de « " & p & " »")
    editorMarkSaved(id, uid, snap.version, p)
    @[strV(p)]
  mfn "editeur", "fixertexte", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Remplace le texte d'un document (annulable) ; enregistre = vrai : marqué enregistré.
    let id = L.edOf(a, "fixertexte")
    let txt = L.checkStr(a, 2, "fixertexte")
    @[boolV(editorSetText(id, L.uidArg(a, 3, id, "fixertexte"), txt, modified = not optBool(a, 4, false)))]
  mfn "editeur", "fermer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.edOf(a, "fermer")
    editorClose(id, L.uidArg(a, 2, id, "fermer"))
  mfn "editeur", "actif", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(editorActiveUid(L.edOf(a, "actif")))]
  mfn "editeur", "activer", proc (L: Interp, a: seq[Value]): seq[Value] =
    editorActivate(L.edOf(a, "activer"), int(L.checkInt(a, 2, "activer")))
  mfn "editeur", "documents", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = newLTable()
    for d in editorDocs(L.edOf(a, "documents")):
      t.arr.add record({"uid": intV(d.uid), "chemin": strV(d.path), "titre": strV(d.title),
                        "modifie": boolV(d.dirty)})
    @[tableV(t)]
  mfn "editeur", "chemin", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.edOf(a, "chemin")
    @[strV(editorInfo(id, L.uidArg(a, 2, id, "chemin")).path)]
  mfn "editeur", "modifie", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.edOf(a, "modifie")
    @[boolV(editorInfo(id, L.uidArg(a, 2, id, "modifie")).dirty)]
  mfn "editeur", "chercherdocument", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.edOf(a, "chercherdocument")
    let p = L.checkStr(a, 2, "chercherdocument")
    var uid = editorUidOf(id, p)
    if uid < 0: uid = editorUidOf(id, absolutePath(L.programPath(p)).normalizedPath)
    @[(if uid < 0: nilV else: intV(uid))]
  mfn "editeur", "aller", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.edOf(a, "aller")
    let uid = L.uidArg(a, 4, id, "aller")
    let ln = max(1, int(L.checkInt(a, 2, "aller"))) - 1
    var col = max(1, int(L.optInt(a, 3, "aller", 1))) - 1
    let lines = editorText(id, uid).split('\n')
    if ln < lines.len:
      let o = runeOffset(lines[ln], col)
      col = if o < 0: lines[ln].len else: o
    editorGoto(id, uid, ln, col)
  mfn "editeur", "curseur", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = editorCursor(L.edOf(a, "curseur"))
    @[record({"ligne": intV(c.line + 1), "colonne": intV(c.col + 1)})]
  mfn "editeur", "inserer", proc (L: Interp, a: seq[Value]): seq[Value] =
    editorInsert(L.edOf(a, "inserer"), L.checkStr(a, 2, "inserer"))
  mfn "editeur", "selection", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(editorSelection(L.edOf(a, "selection")))]
  mfn "editeur", "motcourant", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(editorWordAtCursor(L.edOf(a, "motcourant")))]
  mfn "editeur", "commande", proc (L: Interp, a: seq[Value]): seq[Value] =
    let fr = L.checkStr(a, 2, "commande").toLowerAscii
    let cmd = case fr
      of "annuler": "undo"
      of "retablir": "redo"
      of "couper": "cut"
      of "copier": "copy"
      of "coller": "paste"
      of "toutselectionner": "selectall"
      of "dupliquer": "dup"
      of "commenter": "comment"
      of "indenter": "indent"
      of "desindenter": "outdent"
      else: fr
    editorCommand(L.edOf(a, "commande"), cmd)
  mfn "editeur", "diagnostics", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.edOf(a, "diagnostics")
    let uid = L.uidArg(a, 3, id, "diagnostics")
    let lines = editorText(id, uid).split('\n')
    var ds: seq[Diagnostic]
    if arg(a, 2).kind == vkTable:
      let t = a[1].t
      for i in 1 .. t.rawLen:
        let v = t.rawGet(intV(i))
        if v.kind == vkTable: ds.add L.diagOf(v.t, lines)
    editorSetDiagnostics(id, uid, editorInfo(id, uid).version, ds)
  mfn "editeur", "pointsarret", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.edOf(a, "pointsarret")
    let t = newLTable()
    for l in editorBreakpoints(id, L.uidArg(a, 2, id, "pointsarret")): t.arr.add intV(l + 1)
    @[tableV(t)]
  mfn "editeur", "chercher", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.edOf(a, "chercher")
    let o = if arg(a, 3).kind == vkTable: a[2].t else: nil
    @[boolV(editorFind(id, findReqOf(L.checkStr(a, 2, "chercher"), o)))]
  mfn "editeur", "remplacer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.edOf(a, "remplacer")
    let o = if arg(a, 4).kind == vkTable: a[3].t else: nil
    @[boolV(editorReplace(id, findReqOf(L.checkStr(a, 2, "remplacer"), o, L.checkStr(a, 3, "remplacer"))))]
  mfn "editeur", "remplacertout", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.edOf(a, "remplacertout")
    let o = if arg(a, 4).kind == vkTable: a[3].t else: nil
    @[intV(editorReplaceAll(id, findReqOf(L.checkStr(a, 2, "remplacertout"), o,
                                          L.checkStr(a, 3, "remplacertout"))))]
  mfn "editeur", "lignexecution", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.edOf(a, "lignexecution")
    let ln = int(L.optInt(a, 2, "lignexecution", 0))
    if ln <= 0: editorSetExecLine(id, -1, -1)
    else: editorSetExecLine(id, L.uidArg(a, 3, id, "lignexecution"), ln - 1)
  mfn "editeur", "basculerpointarret", proc (L: Interp, a: seq[Value]): seq[Value] =
    editorToggleBreakpoint(L.edOf(a, "basculerpointarret"))
  mfn "editeur", "effacerpointsarret", proc (L: Interp, a: seq[Value]): seq[Value] =
    editorClearBreakpoints(L.edOf(a, "effacerpointsarret"))
  mfn "editeur", "pressepapiers", proc (L: Interp, a: seq[Value]): seq[Value] =
    editorCopyToClipboard(L.edOf(a, "pressepapiers"), L.checkStr(a, 2, "pressepapiers"))
  mfn "editeur", "taillepolice", proc (L: Interp, a: seq[Value]): seq[Value] =
    editorSetFontSize(L.edOf(a, "taillepolice"), L.checkNum(a, 2, "taillepolice"))
  mfn "editeur", "minicarte", proc (L: Interp, a: seq[Value]): seq[Value] =
    editorSetOptions(L.edOf(a, "minicarte"), optBool(a, 2, true), false)
  mfn "editeur", "langage", proc (L: Interp, a: seq[Value]): seq[Value] =
    # ed:langage() : langage du document actif ; ed:langage("sql" | "lexis" | "", [uid]) : l'impose.
    let id = L.edOf(a, "langage")
    if arg(a, 2).kind == vkNil: return @[strV(editorLanguage(id, -1))]
    let lang = L.checkStr(a, 2, "langage").toLowerAscii
    if lang notin ["sql", "lexis", ""]: rtError("editeur:langage : « sql », « lexis » ou \"\" attendu")
    let uid = if arg(a, 3).kind == vkNil: -1 else: int(L.checkInt(a, 3, "langage"))
    editorSetLanguage(id, uid, lang)
  mfn "editeur", "pastille", proc (L: Interp, a: seq[Value]): seq[Value] =
    # ed:pastille(texte, [uid], [couleur]) : pastille après le titre de l'onglet ("" : aucune).
    let id = L.edOf(a, "pastille")
    let txt = L.optStr(a, 2, "pastille", "")
    let uid = if arg(a, 3).kind == vkNil: -1 else: int(L.checkInt(a, 3, "pastille"))
    let col = if arg(a, 4).kind == vkStr and a[3].s.len > 0: colorOf(a[3]) else: Color()
    editorSetBadge(id, uid, txt, col)
  mfn "editeur", "noms", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Noms proposés par la complétion (SQL : « table » et « table.colonne »).
    let id = L.edOf(a, "noms")
    var names: seq[string]
    let v = arg(a, 2)
    if v.kind == vkTable:
      for i in 1 .. v.t.rawLen: names.add L.tostr(v.t.rawGet(intV(i)))
    editorSetProjectNames(id, names)

  # visionneuse Markdown
  mfn "markdown", "charger", proc (L: Interp, a: seq[Value]): seq[Value] =
    let txt = L.readMarkdown(L.checkStr(a, 2, "charger"), "markdown:charger")
    L.withMarkdown(a, "charger", v): v.setValueText(txt)
  mfn "markdown", "ajouter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let parts = L.strs(a, 2, "ajouter")
    L.withMarkdown(a, "ajouter", v):
      for t in parts: v.appendMarkdown(t)
  mfn "markdown", "vider", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withMarkdown(a, "vider", v): v.setValueText("")
  mfn "markdown", "defilera", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = arg(a, 2)
    let where = if p.kind == vkStr: p.s.toLowerAscii else: ""
    let y = if p.kind == vkStr: 0.0 else: L.checkNum(a, 2, "defilera")
    if p.kind == vkStr and where notin ["debut", "fin"]:
      rtError("markdown:defilera : nombre, \"debut\" ou \"fin\" attendu")
    L.withMarkdown(a, "defilera", v):
      if where == "fin": v.scrollToEnd() else: v.scrollTo(y)
  mfn "markdown", "position", proc (L: Interp, a: seq[Value]): seq[Value] =
    var y = 0.0
    L.withMarkdown(a, "position", v): y = v.scrollPosition
    @[numV(y)]

  # éditeur d'états (canevas) : modèle, mise en page et PDF natifs ; la fenêtre de
  # l'éditeur s'écrit en Lexis+ (exemples/atelier/etats.prg).
  mfn "etat", "nom", proc (L: Interp, a: seq[Value]): seq[Value] =
    var r = ""
    L.withReport(a, "nom", c): r = c.model.name
    @[strV(r)]
  mfn "etat", "code", proc (L: Interp, a: seq[Value]): seq[Value] =
    var r = ""
    L.withReport(a, "code", c): r = generateReportCode(c.model)
    @[strV(r)]
  mfn "etat", "codeexemple", proc (L: Interp, a: seq[Value]): seq[Value] =
    var r = ""
    L.withReport(a, "codeexemple", c): r = reportExampleCode(c.model)
    @[strV(r)]
  mfn "etat", "noeuds", proc (L: Interp, a: seq[Value]): seq[Value] =
    # {uid, nom, genre, chemin, niveau, conteneur} : l'état, ses zones, leurs éléments.
    let t = newLTable()
    L.withReport(a, "noeuds", c):
      let m = c.model
      let top = "état " & m.name
      t.arr.add record({"uid": intV(m.uid), "nom": strV(m.name), "genre": strV("etat"), "chemin": strV(top),
                        "niveau": intV(0), "conteneur": boolV(true)})
      for b in m.bands:
        let pb = top & $TreeSep & b.name
        t.arr.add record({"uid": intV(b.uid), "nom": strV(b.name), "genre": strV("zone"), "chemin": strV(pb),
                          "niveau": intV(1), "conteneur": boolV(b.items.len > 0)})
        for i in b.items:
          t.arr.add record({"uid": intV(i.uid), "nom": strV(i.name), "genre": strV(i.kind),
                            "chemin": strV(pb & $TreeSep & i.name), "niveau": intV(2), "conteneur": boolV(false)})
    @[tableV(t)]
  mfn "etat", "selection", proc (L: Interp, a: seq[Value]): seq[Value] =
    var r = 0
    L.withReport(a, "selection", c): r = c.selectedUid
    @[intV(r)]
  mfn "etat", "selectionner", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Sélectionne l'état, une zone ou un élément (uid) ; sans argument : l'état. Pas d'événement.
    L.withReport(a, "selectionner", c):
      c.selectUid(if arg(a, 2).kind == vkNil: c.model.uid else: int(L.checkInt(a, 2, "selectionner")))
  mfn "etat", "element", proc (L: Interp, a: seq[Value]): seq[Value] =
    # {uid, nom, genre (etat, zone, texte, rectangle, ligne, image), titre, aide} de la sélection.
    var r = nilV
    L.withReport(a, "element", c):
      let uid = c.selectedUid
      let n = c.findNode(uid)
      let (nom, genre) = case n.kind
        of skReport: (c.model.name, "etat")
        of skBand: (n.band.name, "zone")
        of skItem: (n.item.name, n.item.kind)
      r = record({"uid": intV(uid), "nom": strV(nom), "genre": strV(genre), "titre": strV(c.selectionTitle),
                  "aide": strV(c.selectionHelp)})
    @[r]
  mfn "etat", "proprietes", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Propriétés de la sélection : {nom, genre, valeur, choix, cible} ; cible « geom » :
    # position, taille ou hauteur (mm).
    let t = newLTable()
    L.withReport(a, "proprietes", c):
      for r in c.inspectorRows:
        let ch = newLTable()
        for x in r.d.choices: ch.arr.add strV(x)
        t.arr.add record({"nom": strV(r.d.name), "genre": strV(kindName(r.d.kind)), "valeur": strV(r.v),
                          "choix": tableV(ch), "cible": strV(r.target)})
    @[tableV(t)]
  mfn "etat", "fixerpropriete", proc (L: Interp, a: seq[Value]): seq[Value] =
    # fixerpropriete(nom, valeur, [cible]) sur la sélection ; nul si c'est fait, sinon le message.
    let key = L.checkStr(a, 2, "fixerpropriete")
    let v = L.tostr(arg(a, 3))
    let target = if arg(a, 4).kind == vkNil: "prop" else: L.checkStr(a, 4, "fixerpropriete")
    var msg = ""
    L.withReport(a, "fixerpropriete", c): msg = c.setSelectionValue(target, key, v)
    @[(if msg.len > 0: strV(msg) else: nilV)]
  mfn "etat", "renommer", proc (L: Interp, a: seq[Value]): seq[Value] =
    # renommer(uid, nom, projet) : {message, ancien} ; ancien : ancien nom de l'état renommé
    # (son fichier etat_<ancien>.prg est à supprimer).
    let uid = int(L.checkInt(a, 2, "renommer"))
    let nv = L.checkStr(a, 3, "renommer")
    let root = L.optStr(a, 4, "renommer", "")
    var r: tuple[msg, oldReport: string]
    L.withReport(a, "renommer", c): r = c.renameNode(uid, nv, root)
    @[record({"message": (if r.msg.len > 0: strV(r.msg) else: nilV),
              "ancien": (if r.oldReport.len > 0: strV(r.oldReport) else: nilV)})]
  mfn "etat", "supprimer", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withReport(a, "supprimer", c): c.deleteSelected()
  mfn "etat", "monter", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withReport(a, "monter", c): c.moveSelected(-1)
  mfn "etat", "descendre", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withReport(a, "descendre", c): c.moveSelected(1)
  mfn "etat", "nouvellezone", proc (L: Interp, a: seq[Value]): seq[Value] =
    # nouvellezone([genre]) : "zone" (défaut), "entete" ou "pied".
    let kind = L.optStr(a, 2, "nouvellezone", "zone")
    L.withReport(a, "nouvellezone", c): discard c.addBand(kind, c.selBand)
  # diagramme (nœuds et liens)
  mfn "diagramme", "noeud", proc (L: Interp, a: seq[Value]): seq[Value] =
    # noeud{id=, titre=, soustitre=, lignes=, x=, y=, couleur=, forme=, pastille=, jauge=} : ajoute ou met à jour.
    let o = diaOpts(a, 2)
    if o.isNil: rtError("noeud : table {id=, titre=, ...} attendue")
    let id = optField(o, "id", "")
    if id.len == 0: rtError("noeud : id attendu")
    var rows: seq[DiaRow]
    var hasRows = false
    let lv = field(o, "lignes")
    if lv.kind == vkTable:
      hasRows = true
      for i in 1 .. lv.t.rawLen:
        let e = lv.t.rawGet(intV(i))
        if e.kind == vkTable:
          rows.add DiaRow(text: optField(e.t, "texte", ""), detail: optField(e.t, "detail", ""), mark: optField(e.t, "marque", ""))
        else: rows.add DiaRow(text: L.tostr(e))
    let col = field(o, "couleur")
    L.withDiagram(a, "noeud", c):
      let n = c.upsertNode(id)
      n.title = optField(o, "titre", if n.title.len > 0: n.title else: id)
      if field(o, "soustitre").kind != vkNil: n.subtitle = optField(o, "soustitre", "")
      if field(o, "pastille").kind != vkNil: n.badge = optField(o, "pastille", "")
      if field(o, "forme").kind != vkNil: n.shape = optField(o, "forme", "table")
      if field(o, "jauge").kind != vkNil: n.gauge = optField(o, "jauge", -1.0)
      if col.kind == vkStr: n.color = hex(col.s)
      if hasRows: n.rows = rows
      if field(o, "x").kind != vkNil: n.x = optField(o, "x", 0.0)
      if field(o, "y").kind != vkNil: n.y = optField(o, "y", 0.0)
      c.placeNew()
  mfn "diagramme", "lien", proc (L: Interp, a: seq[Value]): seq[Value] =
    # lien{id=, de=, a=, deligne=, aligne=, libelle=, fleche=, pointille=, couleur=, epaisseur=}
    let o = diaOpts(a, 2)
    if o.isNil: rtError("lien : table {de=, a=, ...} attendue")
    var l = DiaLink(src: optField(o, "de", ""), dst: optField(o, "a", ""), srcRow: optField(o, "deligne", 0),
                  dstRow: optField(o, "aligne", 0), label: optField(o, "libelle", ""),
                  arrow: optField(o, "fleche", true), dashed: optField(o, "pointille", false),
                  width: optField(o, "epaisseur", 0.0))
    if l.src.len == 0 or l.dst.len == 0: rtError("lien : de= et a= attendus")
    l.id = optField(o, "id", l.src & ">" & l.dst & (if l.srcRow > 0 or l.dstRow > 0: "#" & $l.srcRow & ":" & $l.dstRow else: ""))
    let col = field(o, "couleur")
    if col.kind == vkStr: l.color = hex(col.s)
    L.withDiagram(a, "lien", c):
      c.upsertLink(l)
    @[strV(l.id)]
  mfn "diagramme", "supprimer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.checkStr(a, 2, "supprimer")
    var ok = false
    L.withDiagram(a, "supprimer", c):
      ok = c.removeNode(id)
    @[boolV(ok)]
  mfn "diagramme", "vider", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withDiagram(a, "vider", c):
      c.nodes.setLen(0)
      c.links.setLen(0)
      c.selected = ""
      c.selLink = ""
  mfn "diagramme", "noeuds", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = newLTable()
    L.withDiagram(a, "noeuds", c):
      for n in c.nodes:
        t.arr.add record({"id": strV(n.id), "titre": strV(n.title), "x": numV(n.x), "y": numV(n.y),
                          "largeur": numV(n.w), "hauteur": numV(n.h)})
    @[tableV(t)]
  mfn "diagramme", "liens", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = newLTable()
    L.withDiagram(a, "liens", c):
      for l in c.links:
        t.arr.add record({"id": strV(l.id), "de": strV(l.src), "a": strV(l.dst), "deligne": intV(l.srcRow),
                          "aligne": intV(l.dstRow), "libelle": strV(l.label)})
    @[tableV(t)]
  mfn "diagramme", "selection", proc (L: Interp, a: seq[Value]): seq[Value] =
    # {genre = "noeud" | "lien" | "", id, ligne}
    var r: Value
    L.withDiagram(a, "selection", c):
      r = if c.selLink.len > 0: record({"genre": strV("lien"), "id": strV(c.selLink), "ligne": intV(0)})
          elif c.selected.len > 0: record({"genre": strV("noeud"), "id": strV(c.selected), "ligne": intV(c.selRow)})
          else: record({"genre": strV(""), "id": strV(""), "ligne": intV(0)})
    @[r]
  mfn "diagramme", "selectionner", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = if arg(a, 2).kind == vkNil: "" else: L.checkStr(a, 2, "selectionner")
    L.withDiagram(a, "selectionner", c):
      c.selected = id
      c.selLink = ""
      c.selRow = if arg(a, 3).kind == vkNil: 0 else: int(L.checkInt(a, 3, "selectionner"))
      let n = c.findNode(id)
      if n != nil and c.rect.w > 0:
        # amène le nœud dans la vue
        let sx = c.panX + n.x * c.zoom
        let sy = c.panY + n.y * c.zoom
        if sx < 0 or sy < 0 or sx + n.w * c.zoom > c.rect.w or sy + n.h * c.zoom > c.rect.h:
          c.panX = c.rect.w / 2 - (n.x + n.w / 2) * c.zoom
          c.panY = c.rect.h / 2 - (n.y + n.h / 2) * c.zoom
  mfn "diagramme", "action", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Dernière action de l'utilisateur : {action = "deplace" | "lien" | "supprimer", id, de, a, deligne, aligne}.
    var r: Value
    L.withDiagram(a, "action", c):
      let x = c.lastAction
      r = record({"action": strV(x.action), "id": strV(x.id), "de": strV(x.src), "a": strV(x.dst),
                  "deligne": intV(x.srcRow), "aligne": intV(x.dstRow)})
    @[r]
  mfn "diagramme", "disposer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let dir = if arg(a, 2).kind == vkNil: "" else: L.checkStr(a, 2, "disposer")
    if dir.len > 0 and dir notin ["droite", "bas"]: rtError("disposer : « droite » ou « bas » attendu")
    L.withDiagram(a, "disposer", c):
      c.layout(dir)
  mfn "diagramme", "ajuster", proc (L: Interp, a: seq[Value]): seq[Value] =
    let zmin = if arg(a, 2).kind == vkNil: 0.0 else: L.checkNum(a, 2, "ajuster") / 100
    L.withDiagram(a, "ajuster", c):
      c.fitMin = zmin
      c.fit()
  mfn "diagramme", "zoom", proc (L: Interp, a: seq[Value]): seq[Value] =
    var r = 0.0
    let f = if arg(a, 2).kind == vkNil: 1.0 else: L.checkNum(a, 2, "zoom")
    L.withDiagram(a, "zoom", c):
      c.zoom = clamp(c.zoom * f, 0.15, 3.0)
      r = c.zoom * 100
    @[numV(round(r))]
  mfn "diagramme", "position", proc (L: Interp, a: seq[Value]): seq[Value] =
    let id = L.checkStr(a, 2, "position")
    let x = L.checkNum(a, 3, "position")
    let y = L.checkNum(a, 4, "position")
    L.withDiagram(a, "position", c):
      let n = c.findNode(id)
      if n != nil:
        n.x = x
        n.y = y
  mfn "diagramme", "modifiable", proc (L: Interp, a: seq[Value]): seq[Value] =
    let b = optBool(a, 2, true)
    L.withDiagram(a, "modifiable", c):
      c.editable = b
  mfn "etat", "zoom", proc (L: Interp, a: seq[Value]): seq[Value] =
    # zoom([facteur]) : multiplie l'échelle ; renvoie le zoom en %.
    var r = 0.0
    let f = if arg(a, 2).kind == vkNil: 1.0 else: L.checkNum(a, 2, "zoom")
    L.withReport(a, "zoom", c):
      c.scale = clamp(c.scale * f, 1.5, 8.0)
      r = c.scale / 3.0 * 100
    @[numV(round(r))]
  mfn "etat", "apercu", proc (L: Interp, a: seq[Value]): seq[Value] =
    # apercu(chemin, [projet]) : PDF d'aperçu (chaque zone trois fois) ; {chemin, erreurs}.
    let path = L.checkStr(a, 2, "apercu")
    let root = L.optStr(a, 3, "apercu", "")
    var errs: seq[string]
    var fail = ""
    L.withReport(a, "apercu", c):
      try: errs = writePreview(c.model, path, root)
      except CatchableError as e: fail = e.msg
    if fail.len > 0: rtError("apercu : " & fail)
    @[record({"chemin": strV(path), "erreurs": strV(errs.join("; "))})]

  # concepteur de formulaires (canevas) : le modèle et la génération sont natifs,
  # la fenêtre du concepteur s'écrit en Lexis+ (exemples/atelier/concepteur.prg).
  mfn "concepteur", "nom", proc (L: Interp, a: seq[Value]): seq[Value] =
    var r = ""
    L.withCanvas(a, "nom", c): r = c.model.root.name
    @[strV(r)]
  mfn "concepteur", "code", proc (L: Interp, a: seq[Value]): seq[Value] =
    var r = ""
    L.withCanvas(a, "code", c): r = generateCode(c.model)
    @[strV(r)]
  mfn "concepteur", "codeassocie", proc (L: Interp, a: seq[Value]): seq[Value] =
    var r = ""
    let nv = arg(a, 2)
    let s2 = if nv.kind == vkNil: "" else: L.checkStr(a, 2, "codeassocie")
    L.withCanvas(a, "codeassocie", c):
      if nv.kind != vkNil: c.model.code = s2
      r = c.model.code
    @[strV(r)]
  mfn "concepteur", "noeuds", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = newLTable()
    L.withCanvas(a, "noeuds", c):
      for n in c.model.allNodes:
        var depth = 0
        var p = n.parent
        while p != nil:
          inc depth
          p = p.parent
        t.arr.add record({"uid": intV(n.uid), "nom": strV(n.name), "genre": strV(n.kind),
                          "chemin": strV(pathOfNode(n)), "niveau": intV(depth),
                          "conteneur": boolV(n.children.len > 0)})
    @[tableV(t)]
  mfn "concepteur", "selection", proc (L: Interp, a: seq[Value]): seq[Value] =
    var r = -1
    L.withCanvas(a, "selection", c):
      r = if c.selected != nil: c.selected.uid else: c.model.root.uid
    @[intV(r)]
  mfn "concepteur", "selectionner", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Sélectionne un élément (par uid) ; sans argument : la fenêtre. Pas d'événement.
    L.withCanvas(a, "selectionner", c):
      let n = L.nodeArg(c, a, 2, "selectionner")
      c.selected = if arg(a, 2).kind == vkNil: c.model.root else: n
      c.showNode(c.selected)
  mfn "concepteur", "element", proc (L: Interp, a: seq[Value]): seq[Value] =
    # {uid, nom, genre, racine, parent} d'un élément (sélectionné par défaut).
    var r = nilV
    L.withCanvas(a, "element", c):
      let n = L.nodeArg(c, a, 2, "element")
      r = record({"uid": intV(n.uid), "nom": strV(n.name), "genre": strV(n.kind),
                  "racine": boolV(n == c.model.root),
                  "conteneur": boolV(n.kind == "fenetre" or isContainerKind(n.kind))})
    @[r]
  mfn "concepteur", "proprietes", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Propriétés à montrer : liste de {nom, genre, valeur, choix} (genre : texte, entier,
    # nombre, logique, choix, couleur, liste).
    let t = newLTable()
    L.withCanvas(a, "proprietes", c):
      let n = L.nodeArg(c, a, 2, "proprietes")
      for d in visibleProps(n):
        let ch = newLTable()
        for x in d.choices: ch.arr.add strV(x)
        t.arr.add record({"nom": strV(d.name), "genre": strV(kindName(d.kind)),
                          "valeur": strV(n.getProp(d.name)), "choix": tableV(ch)})
    @[tableV(t)]
  mfn "concepteur", "fixerpropriete", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Modifie une propriété (« nom » : renomme) ; nul si c'est fait, sinon le message.
    let key = L.checkStr(a, 2, "fixerpropriete")
    let v = L.tostr(arg(a, 3))
    var msg = ""
    L.withCanvas(a, "fixerpropriete", c):
      let n = L.nodeArg(c, a, 4, "fixerpropriete")
      msg = canvasSetProp(c, n, (if key == "nom": "name" else: key), v)
    @[(if msg.len > 0: strV(msg) else: nilV)]
  mfn "concepteur", "evenements", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = newLTable()
    L.withCanvas(a, "evenements", c):
      let n = L.nodeArg(c, a, 2, "evenements")
      for e in eventsOf(n.kind):
        t.arr.add record({"nom": strV(e), "procedure": strV(n.handlerFor(e))})
    @[tableV(t)]
  mfn "concepteur", "associer", proc (L: Interp, a: seq[Value]): seq[Value] =
    # associer(evenement, procedure) ; procédure "" ou nul : retire l'association.
    let ev = L.checkStr(a, 2, "associer")
    let h = if arg(a, 3).kind == vkNil: "" else: L.tostr(arg(a, 3))
    L.withCanvas(a, "associer", c):
      let n = L.nodeArg(c, a, 4, "associer")
      n.setHandler(ev, h)
  mfn "concepteur", "supprimer", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withCanvas(a, "supprimer", c): c.deleteSelected()
  mfn "concepteur", "monter", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withCanvas(a, "monter", c): c.moveSelected(-1)
  mfn "concepteur", "descendre", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withCanvas(a, "descendre", c): c.moveSelected(1)
  mfn "concepteur", "sortir", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.withCanvas(a, "sortir", c): c.moveOut()
  mfn "concepteur", "ajouterpersonnalise", proc (L: Interp, a: seq[Value]): seq[Value] =
    # ajouterpersonnalise(projet, genre, base, expression) : contrôle créé par une fonction
    # Lexis+ ; enregistré dans wdlexis_palette.json. Renvoie nul ou le message d'erreur.
    let root = L.checkStr(a, 2, "ajouterpersonnalise")
    let kind = L.checkStr(a, 3, "ajouterpersonnalise")
    let base = L.checkStr(a, 4, "ajouterpersonnalise")
    let ctor = L.checkStr(a, 5, "ajouterpersonnalise")
    if not isIdent(kind): return @[strV("nom invalide : « " & kind & " »")]
    if findEntry(base).base != base or base in ["fenetre", "page"]:
      return @[strV("contrôle de base inconnu : « " & base & " »")]
    if ctor.strip.len == 0: return @[strV("expression vide")]
    var ok = false
    {.cast(gcsafe).}:
      guarded: ok = addCustomEntry(root, kind, base, ctor.strip)
    @[(if ok: nilV else: strV("écriture impossible de wdlexis_palette.json"))]

proc optsArg(a: seq[Value], i: int): LTable =
  if arg(a, i).kind == vkTable: a[i - 1].t else: nil

#
# Minuterie : appelle une procédure à intervalle régulier (fil dédié), comme
# un gestionnaire d'événement.
#

type
  UiTimer = ref object of LUser
    owner: Interp
    handler: Value
    period: int                   # millisecondes
    repeat: bool
    lock: Lock
    stopped: bool
    ticks: int
    thr: ptr Thread[UiTimer]

var timerMethods: LTable

proc timerAlive(t: UiTimer): bool =
  {.cast(gcsafe).}:
    withLock t.lock:
      if t.stopped: return false
    withLock uiLock: result = t.owner in uiInterps
    if result and t.owner.stopRequested(): result = false

proc timerMain(t: UiTimer) {.thread.} =
  {.cast(gcsafe).}:
    while true:
      var waited = 0
      while waited < t.period:
        let step = min(50, t.period - waited)
        sleep(step)
        waited += step
        if not t.timerAlive(): return
      let L = t.owner
      var failed = false
      L.enter()
      try:
        if t.timerAlive():
          curCtx = Ctx()
          var n = 0
          withLock t.lock:
            inc t.ticks
            n = t.ticks
          let ev = newLTable()
          ev.set "tops", intV(n)
          discard L.call(t.handler, @[tableV(ev)])
      except LexisStop:
        failed = true
      except LexisError as e:
        failed = true
        L.onError(e.msg & "\n" & e.traceback)
      except Exception as e:
        failed = true
        L.onError("erreur interne dans une minuterie : " & e.msg)
      finally:
        L.leave()
      if failed or not t.repeat:
        withLock t.lock: t.stopped = true
        return

proc checkTimer(L: Interp, a: seq[Value], fname: string): UiTimer =
  let v = arg(a, 1)
  if v.kind != vkUser or not (v.u of UiTimer): rtError("« " & fname & " » : appelez-la avec « : » (minuterie:" & fname & "())")
  UiTimer(v.u)

proc defineTimerMethods() =
  timerMethods = newLib()
  timerMethods.fn "arreter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkTimer(a, "arreter")
    withLock t.lock: t.stopped = true
  timerMethods.fn "actif", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkTimer(a, "actif")
    var r = false
    withLock t.lock: r = not t.stopped
    @[boolV(r)]
  timerMethods.fn "tops", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkTimer(a, "tops")
    var r = 0
    withLock t.lock: r = t.ticks
    @[intV(r)]

proc newTimer(L: Interp, ms: int, h: Value, repeat: bool): Value =
  if h.kind == vkNil: rtError("interface.minuterie(millisecondes, @PROCEDURE, [repeter]) : procédure attendue")
  let t = UiTimer(owner: L, handler: h, period: max(10, ms), repeat: repeat)
  initLock(t.lock)
  t.thr = createShared(Thread[UiTimer])
  createThread(t.thr[], timerMain, t)
  L.closers.add proc () =
    {.cast(gcsafe).}:
      withLock t.lock: t.stopped = true
  L.wrap(t, "interface.minuterie", timerMethods)

proc openInterface(L: Interp): Value =
  if familyMethods.len == 0: defineMethods()
  ctlMeta = newLTable()
  ctlMeta.set "__index", fnV("interface.index", ctlIndex)
  ctlMeta.set "__newindex", fnV("interface.newindex", ctlNewIndex)
  ctlMeta.set "__name", strV("interface.controle")
  ctlMeta.set "__eq", fnV("interface.eq", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[boolV(UiCtl(a[0].u).id == UiCtl(a[1].u).id)])
  if timerMethods.isNil: defineTimerMethods()
  discard L.userMeta("interface.minuterie", timerMethods)
  withLock uiLock: uiInterps.add L
  L.closers.add proc () =
    {.cast(gcsafe).}:
      withLock uiLock:
        let i = uiInterps.find(L)
        if i >= 0: uiInterps.delete(i)

  let m = newLib()
  m.set "sep", strV($TreeSep)

  template ctor(name, family: string, body: untyped) {.dirty.} =
    m.fn name, proc (L: Interp, a: seq[Value]): seq[Value] =
      let made: Control = body
      @[L.newCtl(made, family)]

  m.fn "fenetre", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = optsArg(a, 1)
    let title = if arg(a, 1).kind == vkStr: a[0].s else: optField(o, "titre", "wdlexis+")
    let w = newWindow(title, optField(o, "largeur", 640), optField(o, "hauteur", 480), scriptHandler,
                      layout = layoutOf(optField(o, "disposition", "vertical")),
                      theme = themeOf(optField(o, "theme", "natif"), optField(o, "sombre", false)))
    @[L.register(UiCtl(rawId: w.id, win: w, family: "fenetre"))]
  ctor("etiquette", "etiquette"):
    newLabel(L.optStr(a, 1, "etiquette", ""), alignOf(L.optStr(a, 2, "etiquette", "gauche")))
  m.fn "bouton", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = optsArg(a, 2)
    let b = newButton(L.optStr(a, 1, "bouton", "OK"), isDefault = optField(o, "defaut", false),
                      isCancel = optField(o, "annuler", false))
    @[L.newCtl(b, "bouton")]
  m.fn "saisie", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = optsArg(a, 1)
    let txt = if arg(a, 1).kind == vkStr: a[0].s else: optField(o, "texte", "")
    var e: Control
    if optField(o, "multiligne", false): e = newMultilineEdit(txt)
    else:
      e = newEdit(txt, placeholder = optField(o, "indication", ""),
                  inputKind = (if optField(o, "motdepasse", false): ikPassword else: ikText))
    @[L.newCtl(e, "saisie")]
  ctor("cases", "cases"):
    newCheckBox(L.strs(a, 1, "cases"))
  ctor("radio", "radio"):
    newRadioButtonCompat(L.strs(a, 1, "radio"))
  ctor("liste", "liste"):
    newListBox(multiSelection = optBool(a, 1, false))
  ctor("combo", "combo"):
    newComboBox(L.strs(a, 1, "combo"))
  ctor("tableau", "tableau"):
    newTable(multiSelection = false)
  ctor("arbre", "arbre"):
    newTreeView()
  m.fn "grille", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = optsArg(a, 1)
    let g = newGrid(multiSelection = optField(o, "multi", false),
                    fillMode = fillModeOf(optField(o, "remplissage", "programme")))
    @[L.newCtl(g, "grille")]
  ctor("jauge", "jauge"):
    newProgressBar()
  ctor("curseur", "curseur"):
    newControlCompat("slider")
  ctor("plage", "plage"):
    newControlCompat("rangeslider")
  ctor("ascenseur", "ascenseur"):
    newControlCompat("scrollbar")
  ctor("compteur", "compteur"):
    newControlCompat("spin")
  ctor("notation", "notation"):
    newControlCompat("rating")
  ctor("image", "image"):
    newImageCompat(L.optStr(a, 1, "image", ""))
  ctor("codebarre", "codebarre"):
    newBarCodeCompat(L.optStr(a, 1, "codebarre", ""))
  ctor("graphe", "graphe"):
    newChart(chartKindOf(L.optStr(a, 1, "graphe", "colonnes")), L.optStr(a, 2, "graphe", ""))
  ctor("calendrier", "calendrier"):
    newCalendar(L.optStr(a, 1, "calendrier", ""))
  ctor("kanban", "kanban"):
    newControlCompat("kanban")
  ctor("mosaique", "mosaique"):
    newControlCompat("treemap")
  ctor("gantt", "gantt"):
    newControlCompat("gantt")
  ctor("barremenu", "barremenu"):
    newMenuBar()
  ctor("onglets", "onglets"):
    newTab()
  m.fn "separateur", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = optsArg(a, 1)
    let sp = newSplitter(vertical = optField(o, "vertical", true), position = optField(o, "position", 0.5))
    @[L.newCtl(sp, "separateur")]
  ctor("conteneur", "conteneur"):
    newContainer(layoutOf(L.optStr(a, 1, "conteneur", "vertical")), columns = int(L.optInt(a, 2, "conteneur", 2)))
  ctor("colonne", "conteneur"):
    newContainer(lkVertical)
  ctor("rangee", "conteneur"):
    newContainer(lkHorizontal)
  ctor("superconteneur", "conteneur"):
    newSupercontrol(layoutOf(L.optStr(a, 1, "superconteneur", "vertical")))
  ctor("cadre", "cadre"):
    newCell(layoutOf(L.optStr(a, 2, "cadre", "vertical")), L.optStr(a, 1, "cadre", ""))
  m.fn "panneau", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = optsArg(a, 1)
    var sb = smAlways
    case optField(o, "defilement", "toujours").toLowerAscii
    of "automatique", "automatic": sb = smAutomatic
    of "masque", "cache", "hidden": sb = smHidden
    else: discard
    let lk = layoutOf(optField(o, "disposition", "vertical"))
    var pn: Control
    when compiles(newPanel(lk, scrollbars = sb, columns = 2)):
      pn = newPanel(lk, scrollbars = sb, columns = optField(o, "colonnes", 2))
    else:
      pn = newPanel(lk, scrollbars = sb)
    @[L.newCtl(pn, "panneau")]
  ctor("pdf", "pdf"):
    newPdfViewer()
  m.fn "editeur", proc (L: Interp, a: seq[Value]): seq[Value] =
    initLangDocs()     # complétion et aide : fonctions intégrées et paquets.
    let o = optsArg(a, 1)
    let ed = newLexisEditor()
    ed.showMinimap = optField(o, "minicarte", true)
    ed.fontSize = optField(o, "taille", 14.0)
    @[L.newCtl(ed, "editeur")]
  m.fn "markdown", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = optsArg(a, 1)
    var txt = if arg(a, 1).kind == vkStr: a[0].s else: optField(o, "texte", "")
    let path = optField(o, "fichier", "")
    if path.len > 0: txt = L.readMarkdown(path, "interface.markdown")
    @[L.newCtl(newMarkdownView(txt), "markdown")]
  m.fn "concepteur", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Canevas du concepteur de formulaires : {projet=, fichier=} rouvre form_<nom>.prg,
    # {projet=, nom=} crée un formulaire neuf.
    let o = optsArg(a, 1)
    let root = optField(o, "projet", "")
    let path = optField(o, "fichier", "")
    var model: FormModel
    {.cast(gcsafe).}:
      guarded:
        if root.len > 0: loadCustomPalette(root)
      if path.len > 0:
        var txt = ""
        try: txt = readFile(L.programPath(path))
        except IOError, OSError: rtError("interface.concepteur : lecture impossible de « " & path & " »")
        model = parseModel(txt)
        if model == nil: rtError("interface.concepteur : « " & path & " » ne contient pas de dessin de formulaire")
      else:
        model = newModel(optField(o, "nom", "1"))
    let cv = newFormCanvas(model)
    cv.selected = model.root
    @[L.newCtl(cv, "concepteur")]
  m.fn "etat", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Canevas de l'éditeur d'états : {projet=, fichier=} rouvre etat_<nom>.prg, {projet=, nom=} : état neuf.
    let o = optsArg(a, 1)
    let root = optField(o, "projet", "")
    let path = optField(o, "fichier", "")
    var model: ReportModel
    if path.len > 0:
      var txt = ""
      try: txt = readFile(L.programPath(path))
      except IOError, OSError: rtError("interface.etat : lecture impossible de « " & path & " »")
      model = parseReportCode(txt)
      if model == nil: rtError("interface.etat : « " & path & " » ne contient pas de description d'état")
    else:
      model = newReport(optField(o, "nom", "etat1"))
    @[L.newCtl(newReportCanvas(model, root), "etat")]
  m.fn "diagramme", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Canevas de diagramme : nœuds et liens, déplacement, zoom, liaisons à la souris.
    let o = optsArg(a, 1)
    @[L.newCtl(newDiagram(optField(o, "modifiable", true), optField(o, "direction", "droite")), "diagramme")]
  m.fn "paletteetat", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Palette de l'éditeur d'états : glisser une zone ou un élément sur l'état, ou cliquer.
    let c = ctlOf(arg(a, 1), "etat")
    if c.ctl.isNil or not (c.ctl of ReportCanvas): rtError("interface.paletteetat : éditeur d'état attendu")
    @[L.newCtl(newReportPalette(ReportCanvas(c.ctl)), "paletteetat")]
  m.fn "palette", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Palette du concepteur : glisser un contrôle sur le canevas, ou cliquer pour l'ajouter.
    let c = ctlOf(arg(a, 1), "concepteur")
    if c.ctl.isNil or not (c.ctl of FormCanvas): rtError("interface.palette : concepteur attendu")
    @[L.newCtl(newPaletteView(FormCanvas(c.ctl)), "palette")]

  # boucle et dialogues
  m.fn "executer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let st = L.uiState
    if L.hosted:
      L.blocking:
        while L.openWindows() > 0 and not L.stopRequested(): sleep(30)
    elif not st.loopRunning:
      st.loopRunning = true
      L.blocking: runApplication()
    L.checkStop()
  m.fn "quitter", proc (L: Interp, a: seq[Value]): seq[Value] =
    if L.hosted: L.closeAllWindows() else: quitApplication()
  m.fn "icone", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.optStr(a, 1, "icone", "")
    try:
      let img = decodeImageFile(path)
      if not L.hosted: setApplicationIcon(img.w, img.h, img.px)   # dans l'atelier : celle de l'atelier
      result = @[boolV(true)]
    except CatchableError, IOError:
      result = @[boolV(false)]
  m.fn "fenetres", proc (L: Interp, a: seq[Value]): seq[Value] = @[intV(L.openWindows())]
  m.fn "minuterie", proc (L: Interp, a: seq[Value]): seq[Value] =
    var ok: bool
    let ms = int(toInteger(arg(a, 1), ok))
    if not ok: rtError("interface.minuterie : durée en millisecondes attendue")
    @[L.newTimer(ms, arg(a, 2), optBool(a, 3, true))]
  m.fn "tracer", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.uiState.trace = optBool(a, 1, true)
  m.fn "alerte", proc (L: Interp, a: seq[Value]): seq[Value] =
    let msg = L.tostr(arg(a, 1))
    let icon = iconOf(L.optStr(a, 2, "alerte", "information"))
    let title = L.optStr(a, 3, "alerte", "")
    L.blocking:
      if title.len > 0: alert(icon, msg, title = title) else: alert(icon, msg)
  m.fn "confirmer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let msg = L.tostr(arg(a, 1))
    let icon = iconOf(L.optStr(a, 2, "confirmer", "question"))
    var ok = false
    L.blocking: ok = confirm(icon, msg) == drOk
    @[boolV(ok)]
  m.fn "demander", proc (L: Interp, a: seq[Value]): seq[Value] =
    let msg = L.tostr(arg(a, 1))
    let def = L.optStr(a, 2, "demander", "")
    var r = ""
    L.blocking: r = prompt(iconQuestion, msg, def)
    @[strV(r)]
  m.fn "demandersecret", proc (L: Interp, a: seq[Value]): seq[Value] =
    # demandersecret(message, [{memoriser = libellé, coche = booléen, titre =}]) :
    # saisie masquée ; nul si annulée, sinon {valeur, memoriser}.
    let msg = L.tostr(arg(a, 1))
    let o = optsArg(a, 2)
    let lab = optField(o, "memoriser", "")
    var rem = optField(o, "coche", false)
    var v = ""
    var ok = false
    L.blocking: ok = promptSecret(iconQuestion, msg, v, rem, lab, optField(o, "titre", "Secret"))
    if not ok: return @[nilV]
    @[record({"valeur": strV(v), "memoriser": boolV(rem)})]
  m.fn "ouvrirfichier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = optsArg(a, 1)
    var p = ""
    L.blocking:
      p = openFileDialog(title = optField(o, "titre", "Ouvrir"), folder = optField(o, "dossier", ""),
                         filter = optField(o, "filtre", "Tous les fichiers|*"))
    @[(if p.len > 0: strV(p) else: nilV)]
  m.fn "enregistrerfichier", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = optsArg(a, 1)
    var p = ""
    L.blocking:
      p = saveFileDialog(defaultName = optField(o, "nom", ""),
                         filter = optField(o, "filtre", "Tous les fichiers|*"))
    @[(if p.len > 0: strV(p) else: nilV)]
  m.fn "rechercher", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = optsArg(a, 1)
    var req = findReqOf(optField(o, "texte", ""), o, optField(o, "remplacement", ""))
    let repl = optField(o, "remplacer", false)
    var r = drCancel
    L.blocking: r = findDialog(req, replace = repl)
    if r != drOk or req.action == faNone: return @[nilV]
    let act = case req.action
      of faReplace: "remplacer"
      of faReplaceAll: "toutremplacer"
      else: "chercher"
    @[record({"action": strV(act), "texte": strV(req.findText), "remplacement": strV(req.replaceText),
              "casse": boolV(req.matchCase), "motentier": boolV(req.wholeWord),
              "arriere": boolV(req.backwards)})]
  m.fn "couleur", proc (L: Interp, a: seq[Value]): seq[Value] =
    var c = hex(L.optStr(a, 1, "couleur", "#005FB8"))
    var ok = false
    L.blocking: ok = colorDialog(c) == drOk
    @[(if ok: strV(hexOf(c)) else: nilV)]
  m.fn "police", proc (L: Interp, a: seq[Value]): seq[Value] =
    var f = FontChoice(family: L.optStr(a, 1, "police", "DejaVuSans"))
    setNum(f.size, L.optNum(a, 2, "police", 14))
    var ok = false
    L.blocking: ok = fontDialog(f) == drOk
    if not ok: return @[nilV]
    let t = newLTable()
    t.set "famille", strV(f.family)
    t.set "taille", numV(float(f.size))
    when compiles(f.bold): t.set "gras", boolV(f.bold)
    when compiles(f.italic): t.set "italique", boolV(f.italic)
    when compiles(f.path): t.set "chemin", strV(f.path)
    @[tableV(t)]
  tableV(m)

const uiDocs = [
  "interface.fenetre{titre=, largeur=, hauteur=, disposition=, theme=, sombre=}", "Crée une fenêtre. disposition : vertical, horizontal, grille, flux, bordure, pile, absolue ; theme : windows, macos, linux, natif.",
  "interface.executer()", "Attend la fermeture des fenêtres (atelier) ou lance la boucle de wdgui (runtime).",
  "interface.quitter()", "Ferme toutes les fenêtres du programme.",
  "interface.fenetres()", "Nombre de fenêtres ouvertes.",
  "interface.minuterie(millisecondes, @PROCEDURE, [repeter])", "Appelle la procédure (avec ev.tops) toutes les n millisecondes, comme un gestionnaire d'événement ; repeter = faux : une seule fois. Renvoie la minuterie : m:arreter(), m:actif(), m:tops().",
  "interface.icone(chemin)", "Icône des fenêtres du programme (PNG ou JPEG, carrée, 256 px conseillé) : barre de titre, barre des tâches, Dock. Rend faux si l'image est illisible. Sans effet sur les fenêtres de l'atelier quand le programme y est exécuté.",
  "interface.tracer([actif])", "Affiche dans la console chaque événement reçu (diagnostic).",
  "interface.etiquette(texte, [alignement])", "Libellé (alignement : gauche, centre, droite).",
  "interface.bouton(libelle, [{defaut=, annuler=}])", "Bouton.",
  "interface.demandersecret(message, [{memoriser=, coche=, titre=}])", "Saisie masquée (mot de passe) avec case « mémoriser » facultative ; nul si annulée, sinon {valeur, memoriser}.",
  "interface.saisie(texte | {texte=, indication=, multiligne=, motdepasse=})", "Champ de saisie (motdepasse = vrai : caractères masqués, copie interdite).",
  "interface.cases(option, ...)", "Cases à cocher ; valeur = masque de bits.",
  "interface.radio(option, ...)", "Boutons radio ; valeur = index choisi.",
  "interface.liste([multi])", "Liste.", "interface.combo(element, ...)", "Liste déroulante.",
  "interface.tableau()", "Tableau simple.", "interface.arbre()", "Arbre.",
  "interface.grille{multi=, remplissage=\"programme|manuel|automatique\"}", "Grille de saisie.",
  "interface.jauge()", "Jauge.", "interface.curseur()", "Potentiomètre.", "interface.plage()", "Potentiomètre de plage.",
  "interface.ascenseur()", "Ascenseur.", "interface.compteur()", "Compteur à flèches.", "interface.notation()", "Notation.",
  "interface.image(chemin)", "Image.", "interface.codebarre(texte)", "Code-barres.",
  "interface.graphe([genre], [titre])", "Graphe : colonnes, lignes, aires, secteurs.",
  "interface.calendrier([\"AAAAMMJJ\"])", "Calendrier.", "interface.kanban()", "Kanban.",
  "interface.mosaique()", "Mosaïque proportionnelle (treemap).", "interface.gantt()", "Gantt : g:ajoutertache(libelle, debut, duree, [avancement], [couleur], [detail]), g:fixeravancement(i, a), g:vider(), g:horaire([b]) (unités en heures, axe HH:MM), g:largeurlibelles(px) ; surselection : ev.index.",
  "interface.barremenu()", "Barre de menus.", "interface.onglets()", "Onglets.",
  "interface.separateur{vertical=, position=}", "Séparateur (deux enfants).",
  "interface.conteneur([disposition], [colonnes])", "Conteneur.", "interface.colonne()", "Conteneur vertical.",
  "interface.rangee()", "Conteneur horizontal.",
  "interface.superconteneur([disposition])", "Conteneur sans marge.", "interface.cadre(titre, [disposition])", "Cadre de groupe.",
  "interface.panneau{disposition=, defilement=, colonnes=}", "Conteneur défilant (defilement : toujours, automatique, masque).",
  "interface.pdf()", "Visionneuse PDF (PDFium).",
  "interface.editeur([{minicarte=, taille=}])", "Éditeur de code Lexis+ à onglets (coloration, complétion, structure, minicarte, points d'arrêt). valeur : texte du document actif. surchangement : texte modifié ; surselection : signal dans ev.texte (\"pos:L:C\", \"doc:UID\", \"cmd:save\", \"cmd:run\"...).",
  "interface.markdown(texte | {texte=, fichier=})", "Visionneuse Markdown en lecture seule (titres, listes, citations, code, gras, italique, liens), avec retour à la ligne automatique et ascenseur vertical. valeur : le texte Markdown ; surselection : URL du lien cliqué dans ev.texte ; fichier : relatif au dossier du programme.",
  "interface.alerte(message, [icone], [titre])", "Message (icone : information, question, attention, stop, aucune).",
  "interface.confirmer(message, [icone])", "OK / Annuler ; renvoie un logique.",
  "interface.demander(message, [defaut])", "Saisie d'un texte.",
  "interface.ouvrirfichier{titre=, filtre=, dossier=}", "Choix d'un fichier à ouvrir ; nul si annulé.",
  "interface.enregistrerfichier{nom=, filtre=}", "Choix d'un fichier à enregistrer ; nul si annulé.",
  "interface.rechercher{texte=, remplacement=, remplacer=, casse=, motentier=}", "Boîte Rechercher (et Remplacer) ; renvoie {action, texte, remplacement, casse, motentier, arriere} ou nul. action : chercher, remplacer, toutremplacer.",
  "interface.couleur([\"#RRGGBB\"])", "Sélecteur de couleur.",
  "interface.police([famille], [taille])", "Sélecteur de police : {famille, taille, gras, italique}.",
  "interface.sep", "Séparateur des chemins d'arbre et de menu.",
  "c:ajouter(enfant, ...)", "Ajoute des contrôles à un conteneur ou une fenêtre ; renvoie le premier.",
  "c:focus()", "Donne le focus.", "c:menucontextuel(element, ...)", "Menu contextuel ; le choix arrive dans surselection.",
  "c:redessiner()", "Redessine le contrôle.",
  "fen:fermer()", "Ferme la fenêtre.", "fen:fixertheme(nom, [sombre])", "Change le thème.",
  "onglets:ajouterpage(titre, [disposition])", "Ajoute une page ; renvoie son conteneur.",
  "liste:ajouter(element, ...)", "Ajoute (listes et combos).", "liste:inserer(i, element)", "Insère.",
  "liste:supprimer(i)", "Supprime.", "liste:vider()", "Vide.", "liste:selectionner(i)", "Sélectionne.",
  "liste:selection()", "Index sélectionné.", "liste:nombre()", "Nombre d'éléments.",
  "liste:element(i)", "Texte d'un élément.", "liste:modifier(i, texte)", "Modifie.", "liste:chercher(texte)", "Recherche.",
  "tableau:ajoutercolonne(titre, [largeur], [alignement])", "Ajoute une colonne.",
  "tableau:ajouterligne(cellule, ...)", "Ajoute une ligne.",
  "tableau:cellule(ligne, colonne)", "Texte d'une cellule.", "tableau:fixercellule(ligne, colonne, texte)", "Modifie une cellule.",
  "tableau:selection()", "Ligne sélectionnée.", "tableau:trier(colonne, [croissant])", "Trie.",
  "arbre:ajouter(chemin...)", "Ajoute un nœud (\"A\", \"B\" ou \"A/B\").", "arbre:deplier(chemin...)", "Déplie.",
  "arbre:replier(chemin...)", "Replie.", "arbre:supprimer(chemin...)", "Supprime.", "arbre:vider()", "Vide.",
  "barremenu:ajouter(chemin...)", "Ajoute un élément de menu (\"Fichier\", \"Ouvrir\") ; le choix arrive dans surselection (ev.chemin).",
  "cases:coche([i])", "État d'une case.", "cases:cocher(i, [b])", "Coche une case.",
  "graphe:ajouterdonnee(serie, categorie, valeur)", "Ajoute une donnée.",
  "graphe:libellecategorie(i, texte)", "Libellé de catégorie.",
  "graphe:libelleserie(i, texte)", "Libellé de série.", "graphe:fixergenre(genre)", "Genre de graphe.",
  "grille:ajoutercolonne{nom=, titre=, genre=, largeur=, choix=, decimales=}", "Ajoute une colonne (genre : texte, nombre, date, image, bouton, combo, case) ; renvoie la colonne.",
  "grille:ajouterligne(cellule, ...)", "Ajoute une ligne.", "grille:cellule(ligne, colonne)", "Valeur d'une cellule (colonne = nom ou index).",
  "grille:fixercellule(ligne, colonne, valeur)", "Modifie une cellule.", "grille:nombre()", "Nombre de lignes.",
  "grille:trier(colonne, [croissant])", "Trie.", "grille:chercher(colonne, valeur, [exact], [debut])", "Cherche une ligne.",
  "grille:fixerpied(colonne, genre)", "Pied de colonne : somme, moyenne, min, max, nombre.",
  "grille:ajouterformat(colonne, operateur, valeur, {fond=, texte=, ligneentiere=})", "Mise en forme conditionnelle.",
  "grille:fixermodifiable([b])", "Mode saisie.", "grille:verscsv([sep])", "Export CSV.",
  "grille:chargercsv(chemin, [sep])", "Import CSV.",
  "grille:versjson()", "Export JSON.", "grille:chargerjson(chemin)", "Import JSON.",
  "panneau:defilera(x, y)", "Fait défiler.", "pdf:ouvrir(chemin)", "Ouvre un PDF.", "pdf:enregistrer([chemin])", "Enregistre.",
  "editeur:ouvrir(chemin, [creer])", "Ouvre (ou active) un fichier dans un onglet ; renvoie l'uid du document. creer = vrai : fichier absent accepté.",
  "editeur:nouveau([titre])", "Nouveau document vide ; renvoie son uid.",
  "editeur:texte([uid])", "Texte d'un document (actif par défaut).",
  "editeur:enregistrer([chemin], [uid])", "Écrit le document sur disque et le marque enregistré ; renvoie le chemin.",
  "editeur:fermer([uid])", "Ferme un document.", "editeur:actif()", "uid du document actif.",
  "editeur:activer(uid)", "Active un document.",
  "editeur:documents()", "Documents ouverts : liste de {uid, chemin, titre, modifie}.",
  "editeur:chemin([uid])", "Chemin d'un document.", "editeur:modifie([uid])", "Vrai si le document a des modifications non enregistrées.",
  "editeur:chercherdocument(chemin)", "uid du document ouvert sur ce chemin (ou ce titre) ; nul sinon.",
  "editeur:aller(ligne, [colonne], [uid])", "Place le curseur (lignes et colonnes à partir de 1).",
  "editeur:curseur()", "Position du curseur : {ligne, colonne}.",
  "editeur:inserer(texte)", "Insère du texte au curseur.", "editeur:selection()", "Texte sélectionné.",
  "editeur:motcourant()", "Mot sous le curseur.",
  "editeur:commande(nom)", "annuler, retablir, couper, copier, coller, toutselectionner, dupliquer, commenter, indenter, desindenter.",
  "editeur:diagnostics(liste, [uid])", "Souligne des problèmes : liste de {ligne, colonne, longueur, genre, message} (celle de lexis.verifier).",
  "editeur:pointsarret([uid])", "Lignes des points d'arrêt (F9).",
  "editeur:chercher(texte, [{casse=, motentier=, arriere=}])", "Sélectionne l'occurrence suivante ; vrai si trouvée.",
  "editeur:remplacer(texte, remplacement, [options])", "Remplace la sélection si elle correspond, puis cherche la suivante.",
  "editeur:remplacertout(texte, remplacement, [options])", "Remplace toutes les occurrences ; renvoie leur nombre.",
  "editeur:lignexecution([ligne], [uid])", "Surligne la ligne d'exécution du débogueur (sans ligne : l'efface).",
  "editeur:basculerpointarret()", "Pose ou retire un point d'arrêt sur la ligne du curseur.",
  "editeur:effacerpointsarret()", "Retire tous les points d'arrêt.",
  "editeur:pressepapiers(texte)", "Copie un texte dans le presse-papiers.",
  "editeur:taillepolice(taille)", "Taille de la police.", "editeur:minicarte([b])", "Affiche ou masque la minicarte.",
  "editeur:langage([langage], [uid])", "Langage d'un document : « sql » (coloration, complétion et commentaires SQL) ou « lexis » ; \"\" : d'après l'extension (.sql). Sans argument : langage du document actif.",
  "editeur:pastille(texte, [uid], [couleur])", "Pastille colorée après le titre de l'onglet d'un document (\"\" : aucune) ; couleur \"#RRGGBB\" (défaut : accent du thème).",
  "editeur:noms(liste)", "Noms proposés par la complétion ; en SQL, « table » et « table.colonne » (les colonnes sont proposées après « table. »).",
  "markdown:charger(chemin)", "Remplace le contenu par celui d'un fichier .md (relatif au dossier du programme) et revient en haut.",
  "markdown:ajouter(texte, ...)", "Ajoute du texte Markdown à la fin, chacun sur une nouvelle ligne ; le défilement est conservé.",
  "markdown:vider()", "Efface le contenu.",
  "markdown:defilera(position)", "Fait défiler : nombre de pixels depuis le haut, \"debut\" ou \"fin\".",
  "markdown:position()", "Défilement actuel en pixels depuis le haut.",
  "c:detruire()", "Retire le contrôle (et son contenu) de sa fenêtre.",
  "editeur:fixertexte(texte, [uid], [enregistre])", "Remplace le texte d'un document (annulable) ; enregistre = vrai le marque enregistré.",
  "interface.concepteur{projet=, fichier= | nom=}", "Canevas du concepteur de formulaires : aperçu réel, glisser-déposer, repères, poignées. fichier : form_<nom>.prg à rouvrir ; nom : nouveau formulaire. surselection : élément sélectionné ; surchangement : dessin modifié à la souris ou au clavier.",
  "interface.palette(concepteur)", "Palette du concepteur : glisser un contrôle sur le canevas, ou cliquer pour l'ajouter au conteneur sélectionné.",
  "concepteur:nom()", "Nom du formulaire.", "concepteur:code()", "Texte de form_<nom>.prg (fonction FORM<NOM>_OUVRIR et dessin).",
  "concepteur:codeassocie([chemin])", "Fichier de code du formulaire (relatif au projet) ; avec un argument : le fixe.",
  "concepteur:noeuds()", "Éléments du formulaire : liste de {uid, nom, genre, chemin, niveau, conteneur} (chemin : celui de la hiérarchie).",
  "concepteur:selection()", "uid de l'élément sélectionné.", "concepteur:selectionner([uid])", "Sélectionne un élément (sans argument : la fenêtre).",
  "concepteur:element([uid])", "{uid, nom, genre, racine, conteneur} d'un élément (sélectionné par défaut).",
  "concepteur:proprietes([uid])", "Propriétés à montrer : liste de {nom, genre, valeur, choix} ; genre : texte, entier, nombre, logique, choix, couleur, liste.",
  "concepteur:fixerpropriete(nom, valeur, [uid])", "Modifie une propriété (« nom » renomme) ; nul si c'est fait, sinon le message d'erreur.",
  "concepteur:evenements([uid])", "Événements de l'élément : liste de {nom, procedure}.",
  "concepteur:associer(evenement, procedure, [uid])", "Associe une procédure à un événement (\"\" : retire l'association).",
  "concepteur:supprimer()", "Supprime l'élément sélectionné.", "concepteur:monter()", "Plus tôt dans l'ordre d'affichage.",
  "concepteur:descendre()", "Plus tard dans l'ordre d'affichage.", "concepteur:sortir()", "Sort l'élément de son conteneur.",
  "interface.etat{projet=, fichier= | nom=}", "Canevas de l'éditeur d'états : zones à l'échelle, glisser-déposer, poignées, repères, hauteur des zones. fichier : etat_<nom>.prg à rouvrir ; nom : état neuf. surselection : sélection ; surchangement : état modifié à la souris ou au clavier.",
  "interface.diagramme([{modifiable=, direction=}])", "Canevas de diagramme (nœuds et liens) : glisser un nœud le déplace, glisser le fond déplace la vue, la molette zoome ; en mode modifiable, glisser depuis la pastille d'un bord (titre ou ligne) vers un autre nœud crée un lien (surchangement, d:action()). direction : droite (défaut) ou bas. surselection : ev.texte = id du nœud, « lien:<id> » ou \"\" ; ev.index = ligne.",
  "diagramme:noeud{id=, titre=, soustitre=, lignes=, x=, y=, couleur=, forme=, pastille=, jauge=}", "Ajoute ou met à jour un nœud. lignes : liste de textes ou de {texte=, detail=, marque=} (marque : PK, FK…) ; forme : table (défaut) ou boite ; pastille : texte en haut à droite ; jauge : 0 à 1 ; sans x/y, placé à droite de l'existant.",
  "diagramme:lien{id=, de=, a=, deligne=, aligne=, libelle=, fleche=, pointille=, couleur=, epaisseur=}", "Ajoute ou met à jour un lien (deligne, aligne : ligne de départ et d'arrivée, 0 = le nœud) ; renvoie son id.",
  "diagramme:supprimer(id)", "Supprime un nœud (et ses liens) ou un lien.", "diagramme:vider()", "Supprime tout.",
  "diagramme:noeuds()", "Liste de {id, titre, x, y, largeur, hauteur}.", "diagramme:liens()", "Liste de {id, de, a, deligne, aligne, libelle}.",
  "diagramme:selection()", "{genre = noeud | lien | \"\", id, ligne}.", "diagramme:selectionner([id], [ligne])", "Sélectionne un nœud et l'amène dans la vue.",
  "diagramme:action()", "Dernière action de l'utilisateur (surchangement) : {action = deplace | lien | supprimer, id, de, a, deligne, aligne}.",
  "diagramme:disposer([direction])", "Disposition automatique en couches (droite ou bas), nœuds isolés en grille.",
  "diagramme:ajuster([zoom_min])", "Cadre tout le diagramme dans la vue ; zoom_min (en %) : un grand diagramme reste lisible, cadré sur son début.", "diagramme:zoom([facteur])", "Multiplie le zoom ; renvoie le zoom en %.",
  "diagramme:position(id, x, y)", "Place un nœud.", "diagramme:modifiable([b])", "Autorise ou non le déplacement et la création de liens.",
  "interface.paletteetat(etat)", "Palette de l'éditeur d'états : zones et éléments à glisser sur l'état, ou à cliquer.",
  "etat:nom()", "Nom de l'état.", "etat:code()", "Texte de etat_<nom>.prg (fonction ETAT_<NOM>).",
  "etat:codeexemple()", "Code Lexis+ qui remplit l'état (rapport.debut, r.ajoute… avec les variables de chaque zone).",
  "etat:noeuds()", "L'état, ses zones et leurs éléments : liste de {uid, nom, genre, chemin, niveau, conteneur}.",
  "etat:selection()", "uid de la sélection.", "etat:selectionner([uid])", "Sélectionne (sans argument : l'état).",
  "etat:element()", "{uid, nom, genre, titre, aide} de la sélection (genre : etat, zone, texte, rectangle, ligne, image).",
  "etat:proprietes()", "Propriétés de la sélection : liste de {nom, genre, valeur, choix, cible} (cible geom : position, taille, hauteur en mm).",
  "etat:fixerpropriete(nom, valeur, [cible])", "Modifie la sélection ; nul si c'est fait, sinon le message d'erreur.",
  "etat:renommer(uid, nom, projet)", "Renomme l'état, une zone ou un élément : {message, ancien} (ancien : ancien nom de l'état, dont le fichier est à supprimer).",
  "etat:supprimer()", "Supprime la sélection.", "etat:monter()", "Zone plus haut, élément dessiné plus tôt.",
  "etat:descendre()", "Zone plus bas, élément dessiné plus tard.", "etat:nouvellezone([genre])", "Ajoute une zone (zone, entete ou pied).",
  "etat:zoom([facteur])", "Multiplie l'échelle ; renvoie le zoom en %.",
  "etat:apercu(chemin, [projet])", "Écrit un PDF d'aperçu (chaque zone trois fois) : {chemin, erreurs}.",
  "concepteur:ajouterpersonnalise(projet, genre, base, expression)", "Ajoute à la palette un contrôle créé par une fonction Lexis+ (wdlexis_palette.json) ; nul ou le message d'erreur."]

registerPackage PackageDef(name: "interface", open: openInterface,
  description: "Interface graphique wdgui", docs: docs("interface", uiDocs))
