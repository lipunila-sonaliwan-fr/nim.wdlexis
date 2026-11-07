# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet publication : mise en page, PDF, HTML, importation et vectorisation
#
#   pub = paquet("publication")
#   r = pub.paginer(texte, {titre = "Guide", couverture = vrai})   -- pages SVG pour l'aperçu
#   pub.pdf("guide.pdf", texte, {titre = "Guide", qualite = "hd"})
#   html = pub.html(texte)
#   svg = pub.vectoriser("logo.png", {mode = "logo"})
#
# Un seul moteur de mise en page (wdgui/vlayout) sert l'aperçu, le SVG et le PDF : ce
# que l'on voit dans l'application est ce qui est publié.

import std/[strutils, tables, os, times, math]
import ../lexis/api
import ../wdgui/[vscene, vlayout, vpdf, mdhtml, vtrace, mdparse]
import ../ide/imagedecode

proc progPath(L: Interp, path: string): string =
  if path.len == 0 or path.isAbsolute: path
  else: (if L.scriptPath.len > 0: L.scriptPath.parentDir else: getCurrentDir()) / path

proc optsOf(a: seq[Value], i: int): LTable =
  if arg(a, i).kind == vkTable: a[i - 1].t else: nil

proc fieldStr(o: LTable, k, d: string): string = (if o == nil: d else: optField(o, k, d))
proc fieldNum(o: LTable, k: string, d: float): float = (if o == nil: d else: optField(o, k, d))
proc fieldBool(o: LTable, k: string, d: bool): bool = (if o == nil: d else: optField(o, k, d))

const Formats = {"a4": (595.28, 841.89), "a5": (419.53, 595.28), "a3": (841.89, 1190.55),
                 "letter": (612.0, 792.0), "lettre": (612.0, 792.0), "carre": (600.0, 600.0),
                 "16:9": (960.0, 540.0), "4:3": (960.0, 720.0), "livre": (432.0, 648.0)}.toTable

proc styleOf(L: Interp, o: LTable): LStyle =
  ## Gabarit : options Lexis+ -> style de mise en page.
  result = defaultStyle()
  if o == nil: return
  let fmt = fieldStr(o, "format", "a4").toLowerAscii
  if Formats.hasKey(fmt):
    (result.pageW, result.pageH) = Formats[fmt]
  if fieldBool(o, "paysage", false): swap(result.pageW, result.pageH)
  result.pageW = fieldNum(o, "largeur", result.pageW)
  result.pageH = fieldNum(o, "hauteur", result.pageH)
  let m = fieldNum(o, "marges", -1)
  if m >= 0:
    result.mTop = m; result.mBottom = m; result.mLeft = m; result.mRight = m
  result.mTop = fieldNum(o, "margehaut", result.mTop)
  result.mBottom = fieldNum(o, "margebas", result.mBottom)
  result.mLeft = fieldNum(o, "margegauche", result.mLeft)
  result.mRight = fieldNum(o, "margedroite", result.mRight)
  result.bodyFont = fieldStr(o, "policecorps", result.bodyFont)
  result.headFont = fieldStr(o, "policetitres", result.headFont)
  result.bodySize = fieldNum(o, "taille", result.bodySize)
  result.lineH = fieldNum(o, "interligne", result.lineH)
  result.paraGap = fieldNum(o, "espaceparagraphe", result.paraGap)
  let echelle = result.bodySize / 10.5
  for k in 1 .. 4: result.hSize[k] = result.hSize[k] * echelle
  result.hSize[1] = fieldNum(o, "titre1", result.hSize[1])
  result.hSize[2] = fieldNum(o, "titre2", result.hSize[2])
  result.hSize[3] = fieldNum(o, "titre3", result.hSize[3])
  result.textCol = fieldStr(o, "couleurtexte", result.textCol)
  result.headCol = fieldStr(o, "couleurtitres", result.headCol)
  result.accent = fieldStr(o, "accent", result.accent)
  result.muted = fieldStr(o, "couleurdiscrete", result.muted)
  result.codeBg = fieldStr(o, "fondcode", result.codeBg)
  result.tableHead = fieldStr(o, "fondentete", result.tableHead)
  result.justify = fieldBool(o, "justifier", result.justify)
  result.numbering = fieldBool(o, "numeroter", result.numbering)
  result.h1NewPage = fieldBool(o, "chapitrenouvellepage", result.h1NewPage)
  result.mirror = fieldBool(o, "rectoverso", result.mirror)
  result.cover = fieldBool(o, "couverture", result.cover)
  result.header = fieldStr(o, "entete", result.header)
  result.footer = fieldStr(o, "pied", result.footer)
  result.title = fieldStr(o, "titre", "")
  result.subtitle = fieldStr(o, "soustitre", "")
  result.author = fieldStr(o, "auteur", "")
  result.date = fieldStr(o, "date", "")
  result.tocTitle = fieldStr(o, "titresommaire", result.tocTitle)
  result.indexTitle = fieldStr(o, "titreindex", result.indexTitle)
  let base = fieldStr(o, "dossier", "")
  result.base = if base.len > 0: L.progPath(base) else: (if L.scriptPath.len > 0: L.scriptPath.parentDir else: getCurrentDir())

proc headingsValue(r: LResult): Value =
  let t = newLTable()
  for h in r.headings:
    t.arr.add record({"niveau": intV(h.level), "texte": strV(h.text), "id": strV(h.id), "page": intV(h.page),
                      "y": numV(h.y)})
  tableV(t)

proc pdfOptions(o: LTable, st: LStyle): PdfOptions =
  result = PdfOptions(title: st.title, author: st.author, lang: fieldStr(o, "langue", "fr-FR"),
                      subject: fieldStr(o, "sujet", ""), keywords: fieldStr(o, "motscles", ""),
                      tagged: fieldBool(o, "accessible", true), links: true)
  case fieldStr(o, "qualite", "standard").toLowerAscii
  of "hd", "haute", "hautedefinition": result.maxImagePx = 0
  of "ecran", "web", "leger": result.maxImagePx = 1200
  of "impression", "imprimable":
    result.maxImagePx = 0
    result.cropMarks = true
  else: result.maxImagePx = 2400
  if fieldBool(o, "reperes", false): result.cropMarks = true

proc scenesOf(L: Interp, v: Value, fname: string, base: string): seq[VScene] =
  if v.kind != vkTable: rtError(fname & " : liste de SVG attendue")
  for i in 1 .. v.t.rawLen:
    let e = v.t.rawGet(intV(i))
    let code = L.tostr(e)
    if code.strip.startsWith("<"): result.add parseSvgScene(code, base)
    else:
      let p = L.progPath(code)
      try: result.add parseSvgScene(readFile(p), p.parentDir)
      except IOError, OSError: rtError(fname & " : lecture impossible de « " & p & " »")

proc traceOpts(o: LTable): TraceOptions =
  result = presetOptions(fieldStr(o, "mode", "couleurs").toLowerAscii)
  if o == nil: return
  result.colors = int(fieldNum(o, "couleurs", result.colors.float))
  result.smooth = clamp(fieldNum(o, "lissage", result.smooth), 0, 1)
  result.detail = clamp(fieldNum(o, "detail", result.detail), 0, 1)
  result.minArea = fieldNum(o, "aireminimale", result.minArea)
  result.maxSide = int(fieldNum(o, "resolution", result.maxSide.float))
  result.background = fieldBool(o, "fond", result.background)

proc openPublication(L: Interp): Value =
  let m = newLib()
  m.fn "paginer", proc (L: Interp, a: seq[Value]): seq[Value] =
    # paginer(markdown, {gabarit}) : {pages = {svg...}, titres = {...}, nbpages, largeur, hauteur, duree}
    let md = L.checkStr(a, 1, "paginer")
    let st = L.styleOf(optsOf(a, 2))
    let t0 = epochTime()
    let r = layoutMarkdown(md, st)
    let pages = newLTable()
    for p in r.pages: pages.arr.add strV(p.toSvg(false, false))
    @[record({"pages": tableV(pages), "titres": headingsValue(r), "nbpages": intV(r.pages.len),
              "largeur": numV(st.pageW), "hauteur": numV(st.pageH), "duree": numV(round((epochTime() - t0) * 1000)),
              "dossier": strV(st.base)})]
  m.fn "pdf", proc (L: Interp, a: seq[Value]): seq[Value] =
    # pdf(chemin, markdown, {gabarit, qualite = standard | hd | ecran | impression, accessible = vrai})
    let path = L.progPath(L.checkStr(a, 1, "pdf"))
    let md = L.checkStr(a, 2, "pdf")
    let o = optsOf(a, 3)
    let st = L.styleOf(o)
    let r = layoutMarkdown(md, st)
    var po = pdfOptions(o, st)
    po.anchors = r.anchors
    for h in r.headings:
      if h.level <= 3: po.outlines.add PdfOutline(level: h.level, title: h.text, page: h.page, y: h.y)
    let w = newPdfWriter(po)
    for p in r.pages: w.addScene(p)
    var size = 0
    try:
      let bytes = w.toBytes
      size = bytes.len
      writeFile(path, bytes)
    except IOError, OSError: rtError("pdf : écriture impossible de « " & path & " »")
    @[record({"chemin": strV(path), "pages": intV(r.pages.len), "octets": intV(size), "titres": headingsValue(r)})]
  m.fn "pdfsvg", proc (L: Interp, a: seq[Value]): seq[Value] =
    # pdfsvg(chemin, {svg ou chemins...}, {titre=, auteur=, signets = {{titre=, page=, niveau=}}, qualite=})
    let path = L.progPath(L.checkStr(a, 1, "pdfsvg"))
    let o = optsOf(a, 3)
    let base = L.progPath(fieldStr(o, "dossier", "."))
    let scenes = L.scenesOf(arg(a, 2), "pdfsvg", base)
    var st = defaultStyle()
    st.title = fieldStr(o, "titre", "")
    st.author = fieldStr(o, "auteur", "")
    var po = pdfOptions(o, st)
    po.tagged = fieldBool(o, "accessible", false)
    if o != nil and field(o, "signets").kind == vkTable:
      let sg = field(o, "signets").t
      for i in 1 .. sg.rawLen:
        let e = sg.rawGet(intV(i))
        if e.kind == vkTable:
          po.outlines.add PdfOutline(level: optField(e.t, "niveau", 1), title: optField(e.t, "titre", ""),
                                     page: optField(e.t, "page", i), y: 0)
    let w = newPdfWriter(po)
    for s in scenes: w.addScene(s)
    try: w.save(path)
    except IOError, OSError: rtError("pdfsvg : écriture impossible de « " & path & " »")
    @[intV(scenes.len)]
  m.fn "html", proc (L: Interp, a: seq[Value]): seq[Value] =
    # html(markdown, [prefixeimages]) : fragment HTML (titres avec ancres, tableaux, figures...).
    @[strV(markdownToHtml(L.checkStr(a, 1, "html"), L.optStr(a, 2, "html", "")))]
  m.fn "titres", proc (L: Interp, a: seq[Value]): seq[Value] =
    # titres(markdown) : {{niveau, texte, id}} sans mise en page (plan, navigation).
    let t = newLTable()
    for b in parseMd(L.checkStr(a, 1, "titres")):
      if b.kind == bkHead:
        t.arr.add record({"niveau": intV(b.level), "texte": strV(plainText(b.text)),
                          "id": strV(if b.id.len > 0: b.id else: slugify(plainText(b.text)))})
    @[tableV(t)]
  m.fn "textebrut", proc (L: Interp, a: seq[Value]): seq[Value] =
    # textebrut(markdown) : texte sans balisage (recherche, résumé, comptage).
    var res = ""
    for b in parseMd(L.checkStr(a, 1, "textebrut")):
      case b.kind
      of bkPara, bkHead: res.add plainText(b.text) & "\n"
      of bkList:
        for it in b.items: res.add plainText(it.text) & "\n"
      of bkQuote, bkCallout:
        for c in b.children: res.add plainText(c.text) & "\n"
      of bkTable:
        for r in b.rows: res.add r.join(" ") & "\n"
      of bkCode: res.add b.lines.join("\n") & "\n"
      else: discard
    @[strV(res)]
  m.fn "ancre", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(slugify(L.checkStr(a, 1, "ancre")))]
  m.fn "mesurer", proc (L: Interp, a: seq[Value]): seq[Value] =
    # mesurer(texte, [police], [taille], [gras]) : largeur du texte (points).
    let s = L.checkStr(a, 1, "mesurer")
    @[numV(measureText(L.optStr(a, 2, "mesurer", "Poppins"), L.optNum(a, 3, "mesurer", 12), optBool(a, 4, false), false, s))]
  m.fn "png", proc (L: Interp, a: seq[Value]): seq[Value] =
    # png(svg, chemin, [largeur]) : rendu d'un SVG en PNG (miniatures, export).
    let code = L.checkStr(a, 1, "png")
    let path = L.progPath(L.checkStr(a, 2, "png"))
    let sc = parseSvgScene(code, L.progPath(L.optStr(a, 4, "png", ".")))
    let w = int(L.optNum(a, 3, "png", sc.width))
    let h = max(1, int(round(sc.height * w.float / max(1.0, sc.width))))
    let px = renderToRgba(sc, w, h)
    @[boolV(savePng(RgbaImage(w: w, h: h, px: px), path))]
  m.fn "importer", proc (L: Interp, a: seq[Value]): seq[Value] =
    # importer(source, destination.png, [{page=, largeur=}]) : PNG, JPEG, GIF, BMP, WEBP, PDF -> PNG.
    let src = L.progPath(L.checkStr(a, 1, "importer"))
    let dst = L.progPath(L.checkStr(a, 2, "importer"))
    let o = optsOf(a, 3)
    let page = int(fieldNum(o, "page", 1))
    var img: RgbaImage
    if src.toLowerAscii.endsWith(".pdf"): img = pdfPageImage(src, page, int(fieldNum(o, "largeur", 1600)))
    else: img = importImage(src)
    if img.w <= 0: return @[nilV]
    if not savePng(img, dst): return @[nilV]
    @[record({"chemin": strV(dst), "largeur": intV(img.w), "hauteur": intV(img.h)})]
  m.fn "pagespdf", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(pdfPageCount(L.progPath(L.checkStr(a, 1, "pagespdf"))))]
  m.fn "tailleimage", proc (L: Interp, a: seq[Value]): seq[Value] =
    # tailleimage(chemin) : {largeur, hauteur} (SVG : dimensions déclarées).
    let p = L.progPath(L.checkStr(a, 1, "tailleimage"))
    if p.toLowerAscii.endsWith(".svg"):
      let sc = loadSvgScene(p)
      if sc == nil: return @[nilV]
      return @[record({"largeur": numV(sc.width), "hauteur": numV(sc.height)})]
    let img = loadRgba(p)
    if img.w <= 0: return @[nilV]
    @[record({"largeur": numV(img.w.float), "hauteur": numV(img.h.float)})]
  m.fn "vectoriser", proc (L: Interp, a: seq[Value]): seq[Value] =
    # vectoriser(image, {mode = mono | gris | couleurs | logo | technique | illustration, couleurs=,
    #            lissage=0..1, detail=0..1, aireminimale=, fond=}) : code SVG.
    let src = L.progPath(L.checkStr(a, 1, "vectoriser"))
    let o = optsOf(a, 2)
    let img = importImage(src, int(fieldNum(o, "page", 1)))
    if img.w <= 0: rtError("vectoriser : image illisible « " & src & " »")
    let sc = vectorize(img, traceOpts(o))
    @[strV(sc.toSvg(false, false))]
  m.fn "optimisersvg", proc (L: Interp, a: seq[Value]): seq[Value] =
    # optimisersvg(svg, {simplifier = tolérance, fusionner = vrai, nettoyer = aire}) : SVG propre.
    let code = L.checkStr(a, 1, "optimisersvg")
    let o = optsOf(a, 2)
    let sc = parseSvgScene(code)
    let n0 = code.len
    let tol = fieldNum(o, "simplifier", 0)
    if tol > 0: sc.simplifyScene(tol)
    let area = fieldNum(o, "nettoyer", 0)
    if area > 0: sc.cleanScene(area)
    if fieldBool(o, "fusionner", false): sc.mergeScene()
    let res = sc.toSvg(fieldBool(o, "images", false), fieldBool(o, "lisible", false))
    @[record({"svg": strV(res), "avant": intV(n0), "apres": intV(res.len)})]
  tableV(m)

registerPackage PackageDef(name: "publication", open: openPublication,
  description: "Mise en page Markdown, PDF vectoriel balisé, HTML, importation d'images et vectorisation",
  docs: docs("publication", [
    "publication.paginer(markdown[, gabarit])", "Met en page : {pages = {svg...}, titres = {{niveau, texte, id, page}}, nbpages, largeur, hauteur, duree (ms)}.",
    "publication.pdf(chemin, markdown[, gabarit])", "PDF vectoriel (texte réel, polices incorporées, signets, liens, sommaire, index, renvois, balisage d'accessibilité). qualite : standard, hd, ecran, impression (repères de coupe).",
    "publication.pdfsvg(chemin, pages[, options])", "PDF d'une suite de SVG (diapositives, planches) : pages = liste de codes SVG ou de chemins ; signets = {{titre=, page=}}.",
    "publication.html(markdown[, prefixe])", "Fragment HTML (ancres, tableaux, encadrés, figures ; prefixe ajouté aux chemins d'images).",
    "publication.titres(markdown)", "Plan du document : {{niveau, texte, id}}.",
    "publication.textebrut(markdown)", "Texte sans balisage.",
    "publication.ancre(texte)", "Ancre d'un titre (minuscules sans accents, tirets).",
    "publication.mesurer(texte[, police, taille, gras])", "Largeur d'un texte en points.",
    "publication.png(svg, chemin[, largeur, dossier])", "Rendu PNG d'un SVG (miniatures).",
    "publication.importer(source, destination[, {page=, largeur=}])", "Convertit PNG, JPEG, GIF, BMP, WEBP (SDL3_image) ou une page de PDF en PNG ; {chemin, largeur, hauteur}.",
    "publication.pagespdf(chemin)", "Nombre de pages d'un PDF.",
    "publication.tailleimage(chemin)", "Dimensions d'une image ou d'un SVG.",
    "publication.vectoriser(image[, options])", "Vectorise une image : mode = mono, gris, couleurs, logo, technique, illustration ; couleurs, lissage (0..1), detail (0..1), aireminimale, fond. Renvoie le SVG.",
    "publication.optimisersvg(svg[, options])", "Nettoie un SVG : simplifier (tolérance), nettoyer (aire minimale), fusionner (même couleur) ; {svg, avant, apres}.",
    "gabarit", "format (a4, a5, a3, lettre, livre, carre, 16:9), paysage, marges, margehaut…, policecorps, policetitres, taille, interligne, accent, couleurtexte, couleurtitres, justifier, numeroter, chapitrenouvellepage, rectoverso, couverture, titre, soustitre, auteur, date, entete et pied (« gauche|centre|droite » avec {titre}, {chapitre}, {page}, {pages}), dossier (images relatives)."]))
