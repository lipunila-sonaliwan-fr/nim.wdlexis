# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet dessin : images, rendu SVG et dessin (sans bibliothèque)
#
#   img = dessin.svg("<svg viewBox='0 0 100 100'><circle cx='50' cy='50' r='40' fill='gold'/></svg>", 200)
#   img:enregistrer("soleil.bmp")
#   t = dessin.toile(300, 200, "white")
#   t:rectangle(0, 150, 300, 50, "#50a03c")
#   t:cercle(240, 50, 30, {255, 200, 0})
#   t:terminer():enregistrer("dessin.bmp")
#
# Couleurs : "#rrggbb", noms SVG ("skyblue"), "rgb(r,g,b)", ou table {r, g, b[, a]}
# (composantes 0..255, opacité a de 0 à 1).

import std/[strutils, os]
import ../lexis/api
import llm_objets

type
  LToile = ref object of LUser
    c: Canvas
    fini: bool

var classeToile {.threadvar.}: Classe

proc points(L: Interp, v: Value, fname: string): seq[Point] =
  ## {{x, y}, {x, y}...}, {{x=, y=}...} ou {x1, y1, x2, y2...}.
  let items = listItems(v)
  if items.len > 0 and items[0].kind == vkTable:
    for p in items:
      if p.kind != vkTable: rtError(fname & " : points attendus")
      var ok: bool
      if p.t.rawLen >= 2:
        result.add (toFloat(p.t.rawGet(intV(1)), ok), toFloat(p.t.rawGet(intV(2)), ok))
      else:
        result.add (p.t.optField("x", 0.0), p.t.optField("y", 0.0))
  else:
    let f = L.toFloats(v, fname)
    if f.len mod 2 != 0: rtError(fname & " : nombre pair de coordonnées attendu")
    var i = 0
    while i + 1 < f.len:
      result.add (float(f[i]), float(f[i + 1]))
      i += 2

proc checkToile(L: Interp, a: seq[Value], fname: string): Canvas =
  let t = checkUser[LToile](L, a, 1, fname, "toile")
  if t.fini: rtError("toile déjà terminée")
  t.c

proc toileV(c: Canvas): Value =
  if classeToile.isNil:
    let cl = newClasse("toile")
    classeToile = cl
    let m = cl.methodes
    m.fn "rectangle", proc (L: Interp, a: seq[Value]): seq[Value] =
      let c = L.checkToile(a, "rectangle")
      c.fillRect(L.checkNum(a, 2, "rectangle"), L.checkNum(a, 3, "rectangle"),
                 L.checkNum(a, 4, "rectangle"), L.checkNum(a, 5, "rectangle"), L.couleurDe(arg(a, 6)))
      @[a[0]]
    m.fn "cercle", proc (L: Interp, a: seq[Value]): seq[Value] =
      let c = L.checkToile(a, "cercle")
      c.fillCircle(L.checkNum(a, 2, "cercle"), L.checkNum(a, 3, "cercle"),
                   L.checkNum(a, 4, "cercle"), L.couleurDe(arg(a, 5)))
      @[a[0]]
    m.fn "ellipse", proc (L: Interp, a: seq[Value]): seq[Value] =
      let c = L.checkToile(a, "ellipse")
      c.fillPolygon(ellipsePoints(L.checkNum(a, 2, "ellipse"), L.checkNum(a, 3, "ellipse"),
                                  L.checkNum(a, 4, "ellipse"), L.checkNum(a, 5, "ellipse")),
                    L.couleurDe(arg(a, 6)))
      @[a[0]]
    m.fn "polygone", proc (L: Interp, a: seq[Value]): seq[Value] =
      let c = L.checkToile(a, "polygone")
      let pts = L.points(arg(a, 2), "polygone")
      if pts.len >= 3: c.fillPolygon(pts, L.couleurDe(arg(a, 3)))
      @[a[0]]
    m.fn "ligne", proc (L: Interp, a: seq[Value]): seq[Value] =
      let c = L.checkToile(a, "ligne")
      c.drawLine(L.checkNum(a, 2, "ligne"), L.checkNum(a, 3, "ligne"), L.checkNum(a, 4, "ligne"),
                 L.checkNum(a, 5, "ligne"), L.optNum(a, 6, "ligne", 1.0), L.couleurDe(arg(a, 7)))
      @[a[0]]
    m.fn "polyligne", proc (L: Interp, a: seq[Value]): seq[Value] =
      let c = L.checkToile(a, "polyligne")
      let pts = L.points(arg(a, 2), "polyligne")
      if pts.len >= 2:
        c.strokePolyline(pts, L.optNum(a, 3, "polyligne", 1.0), L.couleurDe(arg(a, 4)), optBool(a, 5, false))
      @[a[0]]
    m.fn "terminer", proc (L: Interp, a: seq[Value]): seq[Value] =
      let t = checkUser[LToile](L, a, 1, "terminer", "toile")
      if t.fini: rtError("toile déjà terminée")
      t.fini = true
      @[imageV(t.c.finish())]
    cl.getter "largeur", proc (L: Interp, u: LUser): Value = intV(LToile(u).c.img.width)
    cl.getter "hauteur", proc (L: Interp, u: LUser): Value = intV(LToile(u).c.img.height)
  classeToile.enveloppe(LToile(c: c))

proc openDessin(L: Interp): Value =
  let m = newLib()
  m.fn "svg", proc (L: Interp, a: seq[Value]): seq[Value] =
    let code = L.checkStr(a, 1, "svg")
    var img: Image
    protege "svg":
      img = renderSvg(code, int(L.optInt(a, 2, "svg", 0)), int(L.optInt(a, 3, "svg", 0)),
                      L.couleurDe(arg(a, 4), rgb(255, 255, 255)))
    @[imageV(img)]
  m.fn "image", proc (L: Interp, a: seq[Value]): seq[Value] =
    let w = int(L.checkInt(a, 1, "image"))
    let h = int(L.checkInt(a, 2, "image"))
    if w <= 0 or h <= 0 or w > 20000 or h > 20000: rtError("image : dimensions invalides")
    @[imageV(newImage(w, h, L.couleurDe(arg(a, 3), rgb(255, 255, 255))))]
  m.fn "toile", proc (L: Interp, a: seq[Value]): seq[Value] =
    let w = int(L.checkInt(a, 1, "toile"))
    let h = int(L.checkInt(a, 2, "toile"))
    if w <= 0 or h <= 0 or w > 10000 or h > 10000: rtError("toile : dimensions invalides")
    @[toileV(newCanvas(w, h, L.couleurDe(arg(a, 3), rgb(255, 255, 255)),
                       int(L.optInt(a, 4, "toile", 3))))]
  m.fn "lire", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Lit une image BMP, PPM ou PNG.
    let p = L.checkStr(a, 1, "lire")
    var img: Image
    protege "lire":
      case p.splitFile.ext.toLowerAscii
      of ".bmp": img = readBmp(p)
      of ".ppm", ".pnm": img = readPpm(p)
      of ".png": img = decodePng(readFile(p))
      else: raise newException(IOError, "format non pris en charge (bmp, ppm, png) : " & p)
    if img.isNil: rtError("lire : image illisible : " & p)
    @[imageV(img)]
  m.fn "extrairesvg", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = extractSvg(L.checkStr(a, 1, "extrairesvg"))
    @[(if s.len == 0: nilV else: strV(s))]
  m.fn "taillesvg", proc (L: Interp, a: seq[Value]): seq[Value] =
    let (w, h) = svgSize(L.checkStr(a, 1, "taillesvg"))
    @[record({"largeur": numV(w), "hauteur": numV(h)})]
  m.fn "couleur", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Couleur {r=, g=, b=, a=} à partir d'un texte ou de composantes.
    var c: Color
    if arg(a, 1).kind in {vkInt, vkNum}:
      c = rgb(int(L.checkInt(a, 1, "couleur")), int(L.checkInt(a, 2, "couleur")),
              int(L.checkInt(a, 3, "couleur")), L.optNum(a, 4, "couleur", 1.0))
    else:
      c = L.couleurDe(arg(a, 1))
    @[record({"r": intV(int(c.r * 255 + 0.5)), "g": intV(int(c.g * 255 + 0.5)),
              "b": intV(int(c.b * 255 + 0.5)), "a": numV(float(c.a))})]
  tableV(m)

registerPackage PackageDef(name: "dessin", open: openDessin,
  description: "Images BMP/PPM/PNG, rendu SVG et dessin vectoriel",
  docs: docs("dessin", [
    "dessin.svg(code[, largeur, hauteur, fond])", "Rastérise un dessin SVG ; renvoie une image.",
    "dessin.image(largeur, hauteur[, fond])", "Image unie.",
    "dessin.toile(largeur, hauteur[, fond, lissage=3])", "Surface de dessin anticrénelée.",
    "dessin.lire(chemin)", "Lit une image BMP, PPM ou PNG.",
    "dessin.extrairesvg(texte)", "Code SVG contenu dans un texte (réponse d'un modèle) ou nul.",
    "dessin.taillesvg(code)", "Dimensions déclarées d'un SVG : {largeur=, hauteur=}.",
    "dessin.couleur(texte | r, g, b[, a])", "Couleur sous forme de table {r=, g=, b=, a=}.",
    "t:rectangle(x, y, largeur, hauteur, couleur)", "Rectangle plein.",
    "t:cercle(cx, cy, rayon, couleur)", "Disque.",
    "t:ellipse(cx, cy, rx, ry, couleur)", "Ellipse pleine.",
    "t:polygone(points, couleur)", "Polygone plein ; points : {{x, y}, ...}.",
    "t:ligne(x0, y0, x1, y1, epaisseur, couleur)", "Segment.",
    "t:polyligne(points, epaisseur, couleur[, fermee])", "Ligne brisée.",
    "t:terminer()", "Termine le dessin et renvoie l'image.",
    "img:enregistrer(chemin)", "Enregistre selon l'extension (.bmp ou .ppm).",
    "img:enregistrerbmp(chemin)", "Enregistre en BMP.",
    "img:enregistrerppm(chemin)", "Enregistre en PPM.",
    "img:pixel(x, y)", "Couleur d'un pixel : {r=, g=, b=}.",
    "img:fixerpixel(x, y, couleur)", "Colore un pixel.",
    "img:decrire([largeur])", "Description textuelle (couleurs, aperçu en caractères) ; propriétés largeur, hauteur."]))
