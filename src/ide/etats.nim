# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - états (rapports PDF) : modèle, mise en page, génération.
#
# Un état est une suite de zones horizontales :
#   * « entete » : en haut de chaque page générée ;
#   * « pied » : en bas de chaque page générée ;
#   * toute autre zone, au nom choisi (« titre », « ligne », « total »…), ajoutée
#     par le programme autant de fois qu'il le faut, les unes sous les autres ;
#     une zone qui ne tient plus dans la page passe à la page suivante.
# Chaque zone contient des éléments placés librement (millimètres) : textes (avec
# des variables {nom}), rectangles, lignes et images.
#
# Variables calculées : {page}, {nombre de page} (ou {nombre de pages}), {date},
# {heure}. {montant:2} : nombre à 2 décimales (virgule décimale, espaces des milliers).
#
# Le dessin est enregistré dans etat_<nom>.prg : une fonction ETAT_<NOM>() qui
# renvoie sa description (JSON) ; le paquet « rapport » la retrouve par son nom.
#
# Ce module n'utilise pas l'interface graphique : il sert au runtime (et aux
# applications générées) comme à l'éditeur d'états (aperçu).

import std/[json, strutils, tables, os, times, math, options, unicode]
import pdfwriter
from formmodel import PropKind, PropDef

type
  RItem* = ref object
    uid*: int
    kind*: string                      # texte, rectangle, ligne, image
    name*: string
    x*, y*, w*, h*: float              # mm, relatifs à la zone
    props*: seq[tuple[key, value: string]]

  RBand* = ref object
    uid*: int
    name*: string
    height*: float                     # mm
    props*: seq[tuple[key, value: string]]
    items*: seq[RItem]

  ReportModel* = ref object
    uid*: int
    name*: string
    props*: seq[tuple[key, value: string]]
    bands*: seq[RBand]

  Vars* = Table[string, string]        # clefs en majuscules

  Slot = tuple[band: RBand, vars: Vars]

  Placed = object
    band: RBand
    vars: Vars
    y, h: float                        # mm depuis le haut de la page

  PageRec = object
    header, footer: Slot
    bodies: seq[Placed]

  ReportRun* = ref object
    model*: ReportModel
    outPath*: string
    baseDir*: string                   # images relatives
    keepMissing*: bool                 # aperçu : variable inconnue affichée « {nom} »
    pages: seq[PageRec]
    header, footer: Slot
    cursor: float
    finished*: bool

const
  ReportPrefix* = "etat_"
  KindTexte* = "texte"
  KindRect* = "rectangle"
  KindLigne* = "ligne"
  KindImage* = "image"
  MmToPt* = 72.0 / 25.4
  LineFactor* = 1.2                    # interligne : corps x 1,2
  TextPad* = 1.0                       # marge intérieure des textes (pt)

var uidCounter = 0

proc nextUid(): int =
  inc uidCounter
  uidCounter

proc prop(name: string, kind: PropKind, default = "", choices: openArray[string] = []): PropDef =
  PropDef(name: name, kind: kind, default: default, choices: @choices)

# ------------------------------------------------------------------ propriétés

proc itemProps*(kind: string): seq[PropDef] =
  case kind
  of KindTexte:
    @[prop("texte", pkString, "Texte"), prop("police", pkEnum, "helvetica", ["helvetica", "times", "courier"]),
      prop("taille", pkFloat, "10"), prop("gras", pkBool, "false"), prop("italique", pkBool, "false"),
      prop("souligne", pkBool, "false"),
      prop("alignement", pkEnum, "gauche", ["gauche", "centre", "droite"]),
      prop("vertical", pkEnum, "haut", ["haut", "milieu", "bas"]),
      prop("retour", pkBool, "true"), prop("couleur", pkColor, "#000000"), prop("fond", pkColor, ""),
      prop("bordure", pkColor, ""), prop("epaisseur", pkFloat, "0.5")]
  of KindRect:
    @[prop("bordure", pkColor, "#000000"), prop("epaisseur", pkFloat, "0.5"), prop("fond", pkColor, ""),
      prop("rayon", pkFloat, "0")]
  of KindLigne:
    @[prop("couleur", pkColor, "#000000"), prop("epaisseur", pkFloat, "0.5"), prop("pointille", pkBool, "false")]
  of KindImage:
    @[prop("chemin", pkString, ""), prop("mode", pkEnum, "ajuster", ["ajuster", "etirer", "centre"])]
  else: @[]

proc bandProps*(): seq[PropDef] =
  @[prop("extensible", pkBool, "false"), prop("sautavant", pkBool, "false"), prop("fond", pkColor, "")]

proc reportProps*(): seq[PropDef] =
  @[prop("format", pkEnum, "A4", ["A4", "A5", "A3", "Lettre", "Legal"]),
    prop("orientation", pkEnum, "portrait", ["portrait", "paysage"]),
    prop("margehaut", pkFloat, "12"), prop("margebas", pkFloat, "12"),
    prop("margegauche", pkFloat, "15"), prop("margedroite", pkFloat, "15")]

proc getIn(props: seq[tuple[key, value: string]], defs: seq[PropDef], key: string): string =
  for p in props:
    if p.key == key: return p.value
  for d in defs:
    if d.name == key: return d.default
  ""

proc setIn(props: var seq[tuple[key, value: string]], key, value: string) =
  for p in props.mitems:
    if p.key == key:
      p.value = value
      return
  props.add((key, value))

proc getProp*(i: RItem, key: string): string = getIn(i.props, itemProps(i.kind), key)
proc setProp*(i: RItem, key, value: string) = setIn(i.props, key, value)
proc getProp*(b: RBand, key: string): string = getIn(b.props, bandProps(), key)
proc setProp*(b: RBand, key, value: string) = setIn(b.props, key, value)
proc getProp*(m: ReportModel, key: string): string = getIn(m.props, reportProps(), key)
proc setProp*(m: ReportModel, key, value: string) = setIn(m.props, key, value)

proc fnum*(s: string, default = 0.0): float =
  try: parseFloat(s.strip.replace(',', '.')) except ValueError: default

proc isTrueProp*(s: string): bool = s.strip.toLowerAscii in ["true", "1", "vrai", "oui", "yes"]

proc pageSize*(m: ReportModel): tuple[w, h: float] =
  ## Taille de la page (mm), selon le format et l'orientation.
  var (w, h) = case m.getProp("format").toLowerAscii
    of "a5": (148.0, 210.0)
    of "a3": (297.0, 420.0)
    of "lettre", "letter": (215.9, 279.4)
    of "legal": (215.9, 355.6)
    else: (210.0, 297.0)
  if m.getProp("orientation").toLowerAscii == "paysage": swap(w, h)
  (w, h)

proc marginLeft*(m: ReportModel): float = fnum(m.getProp("margegauche"), 15)
proc marginRight*(m: ReportModel): float = fnum(m.getProp("margedroite"), 15)
proc marginTop*(m: ReportModel): float = fnum(m.getProp("margehaut"), 12)
proc marginBottom*(m: ReportModel): float = fnum(m.getProp("margebas"), 12)
proc bandWidth*(m: ReportModel): float = m.pageSize.w - m.marginLeft - m.marginRight

proc findBand*(m: ReportModel, name: string): RBand =
  for b in m.bands:
    if cmpIgnoreCase(b.name, name) == 0: return b
  let n = name.toLowerAscii
  if n in ["entête", "en-tête"]: return m.findBand("entete")
  nil

# ------------------------------------------------------------------ création

proc newItem*(kind, name: string, x, y, w, h: float): RItem =
  RItem(uid: nextUid(), kind: kind, name: name, x: x, y: y, w: w, h: h)

proc newBand*(name: string, height: float): RBand =
  RBand(uid: nextUid(), name: name, height: height)

proc newReport*(name: string): ReportModel =
  ## État neuf : un en-tête, une zone « ligne » et un pied, prêts à compléter.
  result = ReportModel(uid: nextUid(), name: name)
  let w = result.bandWidth
  let ent = newBand("entete", 22)
  let titre = newItem(KindTexte, "titre", 0, 2, w * 0.6, 10)
  titre.setProp("texte", "{titre}")
  titre.setProp("taille", "16")
  titre.setProp("gras", "true")
  ent.items.add titre
  let dt = newItem(KindTexte, "date", w * 0.6, 4, w * 0.4, 6)
  dt.setProp("texte", "Le {date}")
  dt.setProp("alignement", "droite")
  ent.items.add dt
  let trait = newItem(KindLigne, "trait", 0, 18, w, 0)
  trait.setProp("epaisseur", "1")
  ent.items.add trait
  let ligne = newBand("ligne", 7)
  let lib = newItem(KindTexte, "libelle", 0, 1, w * 0.7, 5)
  lib.setProp("texte", "{libelle}")
  ligne.items.add lib
  let val = newItem(KindTexte, "valeur", w * 0.7, 1, w * 0.3, 5)
  val.setProp("texte", "{valeur}")
  val.setProp("alignement", "droite")
  ligne.items.add val
  let pied = newBand("pied", 10)
  let tp = newItem(KindLigne, "trait", 0, 1, w, 0)
  tp.setProp("couleur", "#888888")
  pied.items.add tp
  let pg = newItem(KindTexte, "page", w * 0.5, 3, w * 0.5, 5)
  pg.setProp("texte", "Page {page} / {nombre de page}")
  pg.setProp("alignement", "droite")
  pg.setProp("taille", "8")
  pied.items.add pg
  result.bands = @[ent, ligne, pied]

proc allItems*(m: ReportModel): seq[RItem] =
  for b in m.bands:
    for i in b.items: result.add i

proc uniqueItemName*(m: ReportModel, kind: string): string =
  let prefix = case kind
    of KindTexte: "texte"
    of KindRect: "cadre"
    of KindLigne: "trait"
    of KindImage: "image"
    else: "element"
  var n = 1
  while true:
    let cand = prefix & $n
    var used = false
    for i in m.allItems:
      if cmpIgnoreCase(i.name, cand) == 0: used = true
    if not used: return cand
    inc n

proc uniqueBandName*(m: ReportModel, base = "zone"): string =
  if m.findBand(base) == nil: return base
  var n = 2
  while m.findBand(base & $n) != nil: inc n
  base & $n

proc isName*(s: string): bool =
  if s.len == 0 or not s[0].isAlphaAscii: return false
  for c in s:
    if not (c.isAlphaNumeric or c == '_'): return false
  true

# ------------------------------------------------------------------ JSON

proc propsJson(props: seq[tuple[key, value: string]]): JsonNode =
  result = newJObject()
  for p in props: result[p.key] = %p.value

proc toJson*(m: ReportModel): JsonNode =
  var bands = newJArray()
  for b in m.bands:
    var items = newJArray()
    for i in b.items:
      items.add %*{"kind": i.kind, "name": i.name, "x": i.x, "y": i.y, "w": i.w, "h": i.h,
                   "props": propsJson(i.props)}
    bands.add %*{"name": b.name, "height": b.height, "props": propsJson(b.props), "items": items}
  %*{"etat": m.name, "props": propsJson(m.props), "zones": bands}

proc readProps(j: JsonNode): seq[tuple[key, value: string]] =
  if j != nil and j.kind == JObject:
    for k, v in j.pairs: result.add((k, (if v.kind == JString: v.getStr else: $v)))

proc fromJson*(j: JsonNode): ReportModel =
  result = ReportModel(uid: nextUid(), name: j{"etat"}.getStr("etat"), props: readProps(j{"props"}))
  if j{"zones"} != nil:
    for jb in j{"zones"}:
      let b = newBand(jb{"name"}.getStr("zone"), jb{"height"}.getFloat(10))
      b.props = readProps(jb{"props"})
      if jb{"items"} != nil:
        for ji in jb{"items"}:
          let i = newItem(ji{"kind"}.getStr(KindTexte), ji{"name"}.getStr("element"), ji{"x"}.getFloat,
                          ji{"y"}.getFloat, ji{"w"}.getFloat(20), ji{"h"}.getFloat(5))
          i.props = readProps(ji{"props"})
          b.items.add i
      result.bands.add b

proc reportFileName*(name: string): string = ReportPrefix & name & ".prg"
proc reportProc*(name: string): string = "ETAT_" & name.toUpperAscii

proc isReportFile*(path: string): bool =
  let f = extractFilename(path).toLowerAscii
  f.startsWith(ReportPrefix) and f.endsWith(".prg")

proc generateReportCode*(m: ReportModel): string =
  ## etat_<nom>.prg : une fonction qui renvoie la description de l'état.
  var js = m.toJson.pretty
  # « ]] » fermerait la chaîne longue : il ne peut venir que d'un texte (le JSON
  # mis en forme ne colle jamais deux crochets fermants).
  js = js.replace("]]", "]\\u005D")
  result = "&& État « " & m.name & " » — généré par l'éditeur d'états de wdlexis+.\n" &
           "&& Régénéré à chaque modification dans l'éditeur : modifiez le dessin là-bas, pas ce fichier.\n" &
           "&&   r = rapport.debut(\"" & m.name & ".pdf\")\n" &
           "&&   r.ajoute(\"zone\", {variable = valeur, ...})       zones de l'état : " &
           (block:
             var names: seq[string]
             for b in m.bands: names.add b.name
             names.join(", ")) & "\n" &
           "&&   r.fin()                                         écrit le PDF\n\n" &
           "fonction " & reportProc(m.name) & "()\n" &
           "retourner [[\n" & js & "\n]]\n" &
           "finfonction\n"

proc parseReportCode*(text: string): ReportModel =
  ## Relit etat_<nom>.prg (ou la description JSON seule) ; nil si illisible.
  var js = text
  let a = text.find("[[")
  let b = text.rfind("]]")
  if a >= 0 and b > a: js = text[a + 2 ..< b]
  try:
    let j = parseJson(js)
    if j.kind != JObject or j{"zones"} == nil: return nil
    result = fromJson(j)
  except CatchableError:
    result = nil

proc nextReportName*(root: string): string =
  var n = 1
  while fileExists(root / reportFileName("etat" & $n)): inc n
  "etat" & $n

# ------------------------------------------------------------------ variables

proc frenchNumber(v: float, decimals: int): string =
  let neg = v < 0
  let s = formatFloat(abs(v), ffDecimal, decimals)
  let dot = s.find('.')
  let ent = if dot >= 0: s[0 ..< dot] else: s
  var g = ""
  for i, c in ent:
    if i > 0 and (ent.len - i) mod 3 == 0: g.add " "
    g.add c
  result = (if neg: "-" else: "") & g
  if dot >= 0: result.add "," & s[dot + 1 .. ^1]

proc substitute*(text: string, vars: Vars, page, pages: int, keepMissing = false): string =
  ## Remplace les {variables} ; {page}, {nombre de page}, {date}, {heure} sont calculées.
  var i = 0
  while i < text.len:
    let c = text[i]
    if c == '{':
      let j = text.find('}', i + 1)
      if j > i and '{' notin text[i + 1 ..< j]:
        var name = text[i + 1 ..< j].strip
        var decimals = -1
        let colon = name.rfind(':')
        if colon > 0:
          try:
            decimals = parseInt(name[colon + 1 .. ^1].strip)
            name = name[0 ..< colon].strip
          except ValueError: discard
        let key = unicode.toUpper(name)
        var val = ""
        var found = true
        case key
        of "PAGE": val = $page
        of "NOMBRE DE PAGE", "NOMBRE DE PAGES", "NOMBREDEPAGES", "NOMBRE_DE_PAGES", "PAGES": val = $pages
        of "DATE": val = now().format("dd/MM/yyyy")
        of "HEURE": val = now().format("HH:mm")
        else:
          if vars.hasKey(key): val = vars[key]
          elif vars.hasKey(key.replace(" ", "_")): val = vars[key.replace(" ", "_")]
          else: found = false
        if not found:
          result.add(if keepMissing: "{" & name & "}" else: "")
        elif decimals >= 0:
          try: result.add frenchNumber(parseFloat(val.strip.replace(',', '.')), decimals)
          except ValueError: result.add val
        else: result.add val
        i = j + 1
        continue
    result.add c
    inc i

# ------------------------------------------------------------------ texte

proc textFont*(i: RItem): PdfFont =
  fontOf(i.getProp("police"), isTrueProp(i.getProp("gras")), isTrueProp(i.getProp("italique")))

proc textSize*(i: RItem): float = max(3.0, fnum(i.getProp("taille"), 10))

proc layoutLines*(text: string, f: PdfFont, size, widthPt: float, wrap: bool): seq[string] =
  ## Lignes d'un texte dans une largeur (points), mots coupés au besoin.
  for para in text.split('\n'):
    if not wrap or textWidth(f, size, para) <= widthPt:
      result.add para
      continue
    var line = ""
    for word in para.split(' '):
      let cand = if line.len == 0: word else: line & " " & word
      if textWidth(f, size, cand) <= widthPt:
        line = cand
        continue
      if line.len > 0:
        result.add line
        line = ""
      # mot trop long : coupé par caractères
      var w = word
      while textWidth(f, size, w) > widthPt and w.runeLen > 1:
        var head = ""
        for r in w.runes:
          if head.len > 0 and textWidth(f, size, head & $r) > widthPt: break
          head.add $r
        result.add head
        w = w[head.len .. ^1]
      line = w
    result.add line

proc textHeightMm*(i: RItem, text: string): float =
  ## Hauteur (mm) nécessaire au texte dans la largeur de l'élément.
  let f = i.textFont
  let size = i.textSize
  let lines = layoutLines(text, f, size, max(1.0, i.w * MmToPt - 2 * TextPad), isTrueProp(i.getProp("retour")))
  float(lines.len) * size * LineFactor / MmToPt

proc growthOf*(b: RBand, vars: Vars, page, pages: int, keepMissing = false): tuple[delta, below: float] =
  ## Zone extensible : de combien ses textes l'agrandissent (delta, mm), et à partir
  ## de quelle ordonnée (below) les éléments situés dessous descendent d'autant.
  result = (0.0, Inf)
  if not isTrueProp(b.getProp("extensible")): return
  for i in b.items:
    if i.kind == KindTexte and isTrueProp(i.getProp("retour")):
      let need = i.textHeightMm(substitute(i.getProp("texte"), vars, page, pages, keepMissing))
      if need > i.h + 0.01:
        result.delta = max(result.delta, need - i.h)
        result.below = min(result.below, i.y + i.h)

proc bandHeightFor*(b: RBand, vars: Vars, page, pages: int, keepMissing = false): float =
  ## Hauteur de la zone : fixe, ou agrandie par ses textes si elle est extensible.
  b.height + growthOf(b, vars, page, pages, keepMissing).delta

# ------------------------------------------------------------------ couleurs

proc rgbOf*(s: string): Option[Rgb] =
  let h = s.strip
  if h.len in [7, 9] and h[0] == '#':
    try:
      let r = parseHexInt(h[1 .. 2])
      let g = parseHexInt(h[3 .. 4])
      let b = parseHexInt(h[5 .. 6])
      return some((float(r) / 255, float(g) / 255, float(b) / 255))
    except ValueError: discard
  none(Rgb)

# ------------------------------------------------------------------ dessin

proc drawItem(d: PdfDoc, run: ReportRun, i: RItem, bandTopMm, bandHMm, pageHMm: float,
              vars: Vars, page, pages: int, extensible: bool, shift = 0.0) =
  let m = run.model
  let left = m.marginLeft
  let xPt = (left + i.x) * MmToPt
  let wPt = i.w * MmToPt
  var hMm = i.h
  let topMm = bandTopMm + i.y + shift
  template yPdf(mm: float): float = (pageHMm - mm) * MmToPt
  case i.kind
  of KindTexte:
    let txt = substitute(i.getProp("texte"), vars, page, pages, run.keepMissing)
    let f = i.textFont
    let size = i.textSize
    let lines = layoutLines(txt, f, size, max(1.0, wPt - 2 * TextPad), isTrueProp(i.getProp("retour")))
    let lh = size * LineFactor
    if extensible and isTrueProp(i.getProp("retour")):
      hMm = max(hMm, float(lines.len) * lh / MmToPt)
    let hPt = hMm * MmToPt
    let fond = rgbOf(i.getProp("fond"))
    let bord = rgbOf(i.getProp("bordure"))
    if fond.isSome or bord.isSome:
      d.rect(xPt, yPdf(topMm + hMm), wPt, hPt, stroke = bord, fill = fond,
             width = fnum(i.getProp("epaisseur"), 0.5))
    let col = rgbOf(i.getProp("couleur")).get(Black)
    let total = float(lines.len) * lh
    var y0 = case i.getProp("vertical")
      of "milieu": (hPt - total) / 2
      of "bas": hPt - total
      else: 0.0
    y0 = max(0.0, y0)
    d.clip(xPt, yPdf(topMm + hMm), wPt, hPt + 0.01)
    for k, l in lines:
      let lw = textWidth(f, size, l)
      let x = case i.getProp("alignement")
        of "centre": xPt + (wPt - lw) / 2
        of "droite": xPt + wPt - TextPad - lw
        else: xPt + TextPad
      # ligne de base : haut de la ligne + (interligne - corps) / 2 + jambage supérieur
      let base = yPdf(topMm) - y0 - float(k) * lh - (lh - size) / 2 - ascent(f, size) -
                 (size - ascent(f, size) - descent(f, size)) / 2
      d.text(f, size, x, base, l, col, underline = isTrueProp(i.getProp("souligne")))
    d.unclip()
  of KindRect:
    d.rect(xPt, yPdf(topMm + hMm), wPt, hMm * MmToPt, stroke = rgbOf(i.getProp("bordure")),
           fill = rgbOf(i.getProp("fond")), width = fnum(i.getProp("epaisseur"), 0.5),
           radius = fnum(i.getProp("rayon")) * MmToPt)
  of KindLigne:
    d.line(xPt, yPdf(topMm), xPt + wPt, yPdf(topMm + hMm), rgbOf(i.getProp("couleur")).get(Black),
           fnum(i.getProp("epaisseur"), 0.5), isTrueProp(i.getProp("pointille")))
  of KindImage:
    var p = substitute(i.getProp("chemin"), vars, page, pages)
    if p.len == 0: return
    if not p.isAbsolute and run.baseDir.len > 0: p = run.baseDir / p
    let (iw, ih) = d.imageSize(p)
    if iw <= 0:
      d.rect(xPt, yPdf(topMm + hMm), wPt, hMm * MmToPt, stroke = some((0.7, 0.7, 0.7)))
      return
    var w = wPt
    var h = hMm * MmToPt
    var x = xPt
    var y = yPdf(topMm + hMm)
    case i.getProp("mode")
    of "etirer": discard
    of "centre":
      w = min(wPt, float(iw) * 0.75)
      h = min(hMm * MmToPt, float(ih) * 0.75)
      x = xPt + (wPt - w) / 2
      y = y + (hMm * MmToPt - h) / 2
    else:
      let k = min(wPt / float(iw), hMm * MmToPt / float(ih))
      w = float(iw) * k
      h = float(ih) * k
      x = xPt + (wPt - w) / 2
      y = y + (hMm * MmToPt - h) / 2
    discard d.image(p, x, y, w, h)
  else: discard

proc drawBand(d: PdfDoc, run: ReportRun, b: RBand, vars: Vars, topMm, hMm, pageHMm: float, page, pages: int) =
  let m = run.model
  let fond = rgbOf(b.getProp("fond"))
  if fond.isSome:
    d.rect(m.marginLeft * MmToPt, (pageHMm - topMm - hMm) * MmToPt, m.bandWidth * MmToPt, hMm * MmToPt, fill = fond)
  let ext = isTrueProp(b.getProp("extensible"))
  let g = growthOf(b, vars, page, pages, run.keepMissing)
  for i in b.items:
    # les éléments placés sous un texte qui s'allonge descendent d'autant
    let shift = if g.delta > 0 and i.y >= g.below - 0.01: g.delta else: 0.0
    d.drawItem(run, i, topMm, hMm, pageHMm, vars, page, pages, ext, shift)

# ------------------------------------------------------------------ génération

proc slotHeight(run: ReportRun, s: Slot): float =
  if s.band == nil: 0.0 else: bandHeightFor(s.band, s.vars, 1, 1, run.keepMissing)

proc newRun*(m: ReportModel, outPath: string, baseDir = ""): ReportRun =
  result = ReportRun(model: m, outPath: outPath, baseDir: baseDir)
  let e = m.findBand("entete")
  let p = m.findBand("pied")
  result.header = (e, initTable[string, string]())
  result.footer = (p, initTable[string, string]())

proc startPage(run: ReportRun) =
  if run.pages.len > 0: run.pages[^1].footer = run.footer
  run.pages.add PageRec(header: run.header)
  run.cursor = run.model.marginTop + run.slotHeight(run.header)

proc pageCount*(run: ReportRun): int = run.pages.len

proc bandOf(run: ReportRun, zone: string): RBand =
  result = run.model.findBand(zone)
  if result == nil:
    var names: seq[string]
    for b in run.model.bands: names.add b.name
    raise newException(ValueError, "zone « " & zone & " » inconnue dans l'état « " & run.model.name &
                       " » (zones : " & names.join(", ") & ")")

proc add*(run: ReportRun, zone: string, vars: Vars) =
  ## Ajoute une zone à la suite ; nouvelle page si elle ne tient plus.
  if run.finished: raise newException(ValueError, "l'état est déjà terminé")
  let b = run.bandOf(zone)
  if run.pages.len == 0: run.startPage()
  let h = bandHeightFor(b, vars, run.pages.len, 0, run.keepMissing)
  let bottom = run.model.pageSize.h - run.model.marginBottom - run.slotHeight(run.footer)
  let pg = run.pages[^1]
  if pg.bodies.len > 0 and (isTrueProp(b.getProp("sautavant")) or run.cursor + h > bottom + 0.001):
    run.startPage()
  run.pages[^1].bodies.add Placed(band: b, vars: vars, y: run.cursor, h: h)
  run.cursor += h

proc setHeader*(run: ReportRun, zone: string, vars: Vars) =
  ## Remplace l'en-tête : pour la page en cours si rien n'y est encore placé,
  ## sinon à partir de la page suivante. Zone "" : plus d'en-tête.
  if run.finished: raise newException(ValueError, "l'état est déjà terminé")
  run.header = ((if zone.len == 0: nil else: run.bandOf(zone)), vars)
  if run.pages.len > 0 and run.pages[^1].bodies.len == 0:
    run.pages[^1].header = run.header
    run.cursor = run.model.marginTop + run.slotHeight(run.header)

proc setFooter*(run: ReportRun, zone: string, vars: Vars) =
  ## Remplace le pied : il s'applique à la page en cours (dessinée à la fin) et aux suivantes.
  if run.finished: raise newException(ValueError, "l'état est déjà terminé")
  run.footer = ((if zone.len == 0: nil else: run.bandOf(zone)), vars)

proc render*(run: ReportRun): PdfDoc =
  ## Dessine toutes les pages ({nombre de page} est alors connu).
  if run.pages.len == 0: run.startPage()
  if not run.finished:
    run.pages[^1].footer = run.footer
    run.finished = true
  let m = run.model
  let (pw, ph) = m.pageSize
  let total = run.pages.len
  result = newPdf(m.name)
  for n, pg in run.pages:
    let page = n + 1
    result.addPage(pw * MmToPt, ph * MmToPt)
    if pg.header.band != nil:
      let h = bandHeightFor(pg.header.band, pg.header.vars, page, total, run.keepMissing)
      result.drawBand(run, pg.header.band, pg.header.vars, m.marginTop, h, ph, page, total)
    for b in pg.bodies:
      result.drawBand(run, b.band, b.vars, b.y, b.h, ph, page, total)
    if pg.footer.band != nil:
      let h = bandHeightFor(pg.footer.band, pg.footer.vars, page, total, run.keepMissing)
      result.drawBand(run, pg.footer.band, pg.footer.vars, ph - m.marginBottom - h, h, ph, page, total)

proc finish*(run: ReportRun): string =
  ## Écrit le PDF ; renvoie son chemin.
  let d = run.render()
  d.save(run.outPath)
  run.outPath

proc sampleRun*(m: ReportModel, outPath, baseDir: string): ReportRun =
  ## Aperçu : chaque zone (hors en-tête et pied) trois fois, variables affichées « {nom} ».
  result = newRun(m, outPath, baseDir)
  result.keepMissing = true
  for b in m.bands:
    if b.name in ["entete", "pied"]: continue
    for k in 1 .. 3: result.add(b.name, initTable[string, string]())
