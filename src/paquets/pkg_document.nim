# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet document : lire et analyser des documents, en Nim pur
#
#   d = document.lire("rapport.pdf")          && pdf, html, md, txt, docx, odt, epub...
#   ? d.titre, d.pages, d.langue, longueur(d.texte)
#   passages = document.decouper(d.texte, {taille = 900, chevauchement = 150})
#   c = document.concepts(listes_de_textes, {max = 40})   && carte des concepts
#   pos = document.disposer(noeuds, liens, {largeur = 1600, hauteur = 1000})
#
# Sert de base aux applications de recherche documentaire (RAG) : extraction du
# texte, découpage en passages, mots-clés, concepts et cooccurrences, phrases
# les plus pertinentes pour une question, langue.

import std/[os, strutils, tables, unicode, math, algorithm, sets, uri, sequtils]
import ../lexis/api
import compression, pdftexte

#
# normalisation
#

proc stripAccentRune(r: Rune): Rune =
  let c = int(r)
  if c < 0xC0: return r
  case c
  of 0xC0..0xC5: Rune('A')
  of 0xC7: Rune('C')
  of 0xC8..0xCB: Rune('E')
  of 0xCC..0xCF: Rune('I')
  of 0xD1: Rune('N')
  of 0xD2..0xD6, 0xD8: Rune('O')
  of 0xD9..0xDC: Rune('U')
  of 0xDD: Rune('Y')
  of 0xE0..0xE5: Rune('a')
  of 0xE7: Rune('c')
  of 0xE8..0xEB: Rune('e')
  of 0xEC..0xEF: Rune('i')
  of 0xF1: Rune('n')
  of 0xF2..0xF6, 0xF8: Rune('o')
  of 0xF9..0xFC: Rune('u')
  of 0xFD, 0xFF: Rune('y')
  of 0x152: Rune('O')
  of 0x153: Rune('o')
  else: r

proc foldKey*(w: string): string =
  ## Minuscules sans accents, pluriel simple retiré : clef de comparaison.
  for r in w.toLower.runes:
    let c = int(r)
    if c == 0x153: result.add "oe"
    elif c == 0xE6: result.add "ae"
    elif c == 0xDF: result.add "ss"
    else: result.add stripAccentRune(r)
  # pluriels : -s (sauf -ss, -us : stress, corpus) ; -x seulement après eau, eu, ou
  # (bateaux, jeux, bijoux ; pas index, flux, prix) ; -aux -> -al (chevaux)
  if result.len > 4 and result[^1] == 's' and result[^2] notin {'s', 'u'}:
    result.setLen(result.len - 1)
  elif result.len > 4 and result.endsWith("eaux"):
    result.setLen(result.len - 1)
  elif result.len > 5 and result.endsWith("aux"):
    result = result[0 ..< result.len - 3] & "al"
  elif result.len > 3 and (result.endsWith("eux") or result.endsWith("oux")):
    result.setLen(result.len - 1)

const StopFr = strutils.splitWhitespace("""a à afin ai aie aient aies ait alors après as au aucun aucune aujourd auprès aussi autre autres aux avaient avais avait avant avec avez aviez avions avoir avons ayant beaucoup bien c ça car ce ceci cela celle celles celui cependant certain certaines certains ces cet cette ceux chacun chaque chez ci comme comment contre d dans de depuis des dès deux devant doit donc dont du durant elle elles en encore entre es est et étaient étais était étant été être eu eux fait faire fois font hors il ils j je jusqu l la là laquelle le lequel les lesquelles lesquels leur leurs lors lorsque lui m ma mais me même mêmes mes moi moins mon n ne ni non nos notre nous on ont or ou où par parce parmi pas pendant peu peut peuvent plus plusieurs pour pourquoi puis qu quand que quel quelle quelles quels qui quoi s sa sans se selon ses si sien sienne soi soit son sont sous souvent sur t ta tandis tant te tes toi ton tous tout toute toutes très tu un une vers voici voilà vos votre vous y ainsi également aussi déjà dont celui-ci celle-ci autant tel telle tels telles toujours jamais rien cet entre peu été ici ceux-ci afin lequel avoir être fait faites faits dit dits elle-même lui-même autrement chaque cela ceci ça trop bon bonne mieux sinon via""")

const StopEn = strutils.splitWhitespace("""a about above after again against all am an and any are aren as at be because been before being below between both but by can cannot could did do does doing don down during each few for from further had has have having he her here hers herself him himself his how i if in into is isn it its itself just let me more most my myself no nor not now of off on once only or other ought our ours ourselves out over own same she should so some such than that the their theirs them themselves then there these they this those through to too under until up very was we were what when where which while who whom why will with would you your yours yourself yourselves also may might must shall one two new used use using many much however within without upon""")

var stopSet {.threadvar.}: HashSet[string]
var stopFrSet {.threadvar.}: HashSet[string]
var stopEnSet {.threadvar.}: HashSet[string]

proc ensureStops() =
  if stopSet.len > 0: return
  for w in StopFr:
    stopFrSet.incl w
    stopSet.incl w
    stopSet.incl foldKey(w)
  for w in StopEn:
    stopEnSet.incl w
    stopSet.incl w

proc isStop(w: string): bool =
  ensureStops()
  w in stopSet or w.len <= 2

const Elisions = ["l'", "d'", "qu'", "j'", "n'", "s'", "c'", "m'", "t'", "l’", "d’", "qu’", "j’", "n’", "s’", "c’", "m’", "t’"]

proc wordsWithSurface(text: string, surfaces: var seq[string]): seq[string] =
  ## Mots d'un texte en minuscules, élisions retirées (l'atelier -> atelier) ;
  ## `surfaces` garde la forme écrite, élision comprise (pour l'affichage).
  var cur = ""
  proc flush(cur: var string, res, surf: var seq[string]) =
    if cur.len == 0: return
    let full = cur.strip(chars = {'-', '\'', '.'})
    var w = full
    for e in Elisions:
      if w.startsWith(e) and w.len > e.len:
        w = w[e.len .. ^1]
        break
    if w.len > 0:
      res.add w
      surf.add full
    cur = ""
  for r in text.runes:
    if r.isAlpha or (int(r) < 128 and char(int(r)) in {'0'..'9'}):
      cur.add $r.toLower
    elif (int(r) == ord('-') or int(r) == ord('\'') or int(r) == 0x2019) and cur.len > 0:
      cur.add(if int(r) == 0x2019: "'" else: $r)
    else:
      flush(cur, result, surfaces)
  flush(cur, result, surfaces)

proc words*(text: string): seq[string] =
  ## Mots d'un texte (lettres, chiffres, traits d'union internes), en minuscules,
  ## élisions françaises retirées (l'atelier -> atelier).
  var surf: seq[string]
  wordsWithSurface(text, surf)

proc isNumberWord(w: string): bool =
  for c in w:
    if c notin {'0'..'9', '-'}: return false
  true

#
# langue
#

proc detectLang*(text: string): string =
  ensureStops()
  const de = ["der", "die", "und", "das", "ist", "nicht", "mit", "ein", "eine", "den", "von", "zu", "auf", "für"]
  const es = ["el", "los", "las", "una", "del", "por", "con", "para", "que", "es", "como", "pero", "su", "más"]
  const it = ["il", "gli", "della", "che", "di", "per", "una", "sono", "con", "non", "come", "anche", "del", "nel"]
  var fr, en, d, e, i = 0
  var n = 0
  for w in words(text):
    inc n
    if n > 3000: break
    if w in ["le", "la", "les", "des", "est", "et", "une", "dans", "pour", "qui", "sur", "avec", "pas", "du"]: inc fr
    if w in ["the", "and", "of", "is", "to", "in", "that", "with", "for", "are", "this", "was", "be", "on"]: inc en
    if w in de: inc d
    if w in es: inc e
    if w in it: inc i
  let best = max([fr, en, d, e, i])
  if best < 3: return ""
  if best == fr: "fr" elif best == en: "en" elif best == d: "de" elif best == e: "es" else: "it"

#
# HTML
#

const Entities = {"amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
  "eacute": "é", "egrave": "è", "ecirc": "ê", "euml": "ë", "agrave": "à", "acirc": "â", "auml": "ä",
  "ccedil": "ç", "icirc": "î", "iuml": "ï", "ocirc": "ô", "ouml": "ö", "ugrave": "ù", "ucirc": "û",
  "uuml": "ü", "yuml": "ÿ", "Eacute": "É", "Egrave": "È", "Ecirc": "Ê", "Agrave": "À", "Acirc": "Â",
  "Ccedil": "Ç", "Ocirc": "Ô", "Ucirc": "Û", "oelig": "œ", "OElig": "Œ", "aelig": "æ", "szlig": "ß",
  "ntilde": "ñ", "aacute": "á", "iacute": "í", "oacute": "ó", "uacute": "ú", "laquo": "«", "raquo": "»",
  "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "sbquo": "‚", "bdquo": "„", "hellip": "…",
  "mdash": "—", "ndash": "–", "euro": "€", "copy": "©", "reg": "®", "trade": "™", "deg": "°",
  "middot": "·", "bull": "•", "times": "×", "divide": "÷", "plusmn": "±", "frac12": "½", "sect": "§",
  "para": "¶", "shy": "", "zwnj": "", "zwj": "", "thinsp": " ", "ensp": " ", "emsp": " ",
  "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "hArr": "⇔", "rArr": "⇒", "le": "≤", "ge": "≥",
  "ne": "≠", "minus": "−", "infin": "∞", "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ",
  "lambda": "λ", "mu": "μ", "pi": "π", "sigma": "σ", "omega": "ω", "iexcl": "¡", "iquest": "¿",
  "pound": "£", "yen": "¥", "cent": "¢", "micro": "µ", "prime": "′", "Prime": "″"}.toTable

proc decodeEntities*(s: string): string =
  var i = 0
  while i < s.len:
    if s[i] == '&':
      let e = s.find(';', i + 1)
      if e > i + 1 and e - i <= 12:
        let name = s[i + 1 ..< e]
        if name.startsWith("#"):
          try:
            let cp = if name.len > 1 and name[1] in {'x', 'X'}: parseHexInt(name[2 .. ^1]) else: parseInt(name[1 .. ^1])
            if cp > 0 and cp < 0x110000: result.add $Rune(cp)
            i = e + 1
            continue
          except ValueError: discard
        elif Entities.hasKey(name):
          result.add Entities[name]
          i = e + 1
          continue
    result.add s[i]
    inc i

type HtmlDoc* = object
  text*, title*, description*: string
  links*: seq[(string, string)]   # texte, adresse

proc attrValue(tag, name: string): string =
  let low = tag.toLowerAscii
  var p = 0
  while true:
    let k = low.find(name & "=", p)
    if k < 0: return ""
    if k > 0 and low[k - 1] notin {' ', '\t', '\n', '\r'}:
      p = k + 1
      continue
    var j = k + name.len + 1
    if j >= tag.len: return ""
    if tag[j] in {'"', '\''}:
      let q = tag[j]
      let e = tag.find(q, j + 1)
      if e < 0: return tag[j + 1 .. ^1]
      return tag[j + 1 ..< e]
    var e = j
    while e < tag.len and tag[e] notin {' ', '>', '\t', '\n'}: inc e
    return tag[j ..< e]

proc htmlToText*(html: string, baseUrl = ""): HtmlDoc =
  const blocks = ["p", "div", "br", "li", "ul", "ol", "tr", "table", "section", "article", "main",
                  "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "dt", "dd", "hr", "header",
                  "footer", "figure", "figcaption", "dl", "td", "th", "form", "address", "title"]
  const skip = ["script", "style", "noscript", "svg", "template", "iframe", "object", "canvas", "select", "button"]
  const noise = ["nav", "aside", "footer", "header", "form"]
  var src = html
  # contenu principal : <main> ou le plus grand <article>
  let low = html.toLowerAscii
  block mainContent:
    var best = ""
    for t in ["<article", "<main"]:
      var p = 0
      while true:
        let a = low.find(t, p)
        if a < 0: break
        let closeTag = "</" & t[1 .. ^1] & ">"
        let b = low.find(closeTag, a)
        if b < 0: break
        if b - a > best.len: best = html[a ..< b]
        p = b
    if best.len > 2000: src = best
  # titre et description
  let ta = low.find("<title")
  if ta >= 0:
    let s = low.find('>', ta)
    let e = low.find("</title>", s)
    if s > 0 and e > s: result.title = decodeEntities(html[s + 1 ..< e]).strip
  var mp = 0
  while true:
    let m = low.find("<meta", mp)
    if m < 0: break
    let e = low.find('>', m)
    if e < 0: break
    let tag = html[m .. e]
    let nm = attrValue(tag, "name").toLowerAscii & attrValue(tag, "property").toLowerAscii
    if nm in ["description", "og:description"] and result.description.len == 0:
      result.description = decodeEntities(attrValue(tag, "content")).strip
    if nm == "og:title" and result.title.len == 0:
      result.title = decodeEntities(attrValue(tag, "content")).strip
    mp = e
  var o = ""
  var i = 0
  var skipUntil = ""
  var noiseDepth = 0
  var inPre = false
  var linkHref = ""
  var linkText = ""
  var inLink = false
  let lsrc = src.toLowerAscii
  var base: Uri
  if baseUrl.len > 0: base = parseUri(baseUrl)
  while i < src.len:
    let c = src[i]
    if c == '<':
      if src.continuesWith("<!--", i):
        let e = src.find("-->", i + 4)
        i = if e < 0: src.len else: e + 3
        continue
      var e = i + 1
      var q = '\0'
      while e < src.len:
        if q != '\0':
          if src[e] == q: q = '\0'
        elif src[e] in {'"', '\''}: q = src[e]
        elif src[e] == '>': break
        inc e
      let tag = src[i + 1 ..< min(e, src.len)]
      i = e + 1
      var nameEnd = 0
      let closing = tag.startsWith("/")
      let t0 = if closing: 1 else: 0
      nameEnd = t0
      while nameEnd < tag.len and tag[nameEnd] notin {' ', '\t', '\n', '\r', '/', '>'}: inc nameEnd
      let name = tag[t0 ..< nameEnd].toLowerAscii
      if skipUntil.len > 0:
        if closing and name == skipUntil: skipUntil = ""
        continue
      if not closing and name in skip and not tag.endsWith("/"):
        skipUntil = name
        # recherche directe de la fermeture
        let ce = lsrc.find("</" & name, i)
        if ce >= 0:
          let ge = src.find('>', ce)
          i = if ge < 0: src.len else: ge + 1
          skipUntil = ""
        continue
      if name in noise and src.len != html.len:
        discard           # dans <main>/<article>, on garde tout
      elif name in noise:
        if closing: noiseDepth = max(0, noiseDepth - 1)
        elif not tag.endsWith("/"): inc noiseDepth
        continue
      if noiseDepth > 0: continue
      if name == "pre": inPre = not closing
      if name == "a":
        if not closing:
          inLink = true
          linkText = ""
          linkHref = decodeEntities(attrValue(tag, "href"))
        else:
          if inLink and linkHref.len > 0 and not linkHref.startsWith("#") and
             not linkHref.toLowerAscii.startsWith("javascript:"):
            var url = linkHref
            if baseUrl.len > 0:
              try: url = $combine(base, parseUri(linkHref))
              except CatchableError: discard
            result.links.add (strutils.splitWhitespace(linkText).join(" "), url)
          inLink = false
      if name in blocks:
        if not o.endsWith("\n"): o.add "\n"
        if not closing:
          if name == "li": o.add "- "
          elif name.len == 2 and name[0] == 'h' and name[1] in {'1'..'6'}:
            if not o.endsWith("\n\n"): o.add "\n"
          elif name in ["td", "th"]: discard
        elif name in ["p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "table"]:
          o.add "\n"
      elif name in ["td", "th"] and not closing: o.add " "
      continue
    if skipUntil.len > 0 or noiseDepth > 0:
      inc i
      continue
    var e = src.find('<', i)
    if e < 0: e = src.len
    var t = decodeEntities(src[i ..< e])
    if not inPre:
      var compact = ""
      var sp = false
      for ch in t:
        if ch in {' ', '\t', '\n', '\r'}:
          sp = true
        else:
          if sp and compact.len > 0: compact.add ' '
          elif sp and compact.len == 0 and o.len > 0 and not o.endsWith("\n") and not o.endsWith(" "): compact.add ' '
          sp = false
          compact.add ch
      if sp and compact.len > 0: compact.add ' '
      t = compact
    o.add t
    if inLink: linkText.add t
    i = e
  # lignes nettoyées, au plus une ligne vide entre deux paragraphes
  var lines: seq[string]
  var blank = 0
  for ln in o.splitLines:
    let s = ln.strip
    if s.len == 0:
      inc blank
      if blank == 1 and lines.len > 0: lines.add ""
    else:
      blank = 0
      lines.add s
  result.text = lines.join("\n").strip

#
# Markdown
#

proc markdownToText*(md: string): string =
  var lines: seq[string]
  var inCode = false
  for raw in md.splitLines:
    var l = raw
    if l.strip.startsWith("```") or l.strip.startsWith("~~~"):
      inCode = not inCode
      continue
    if inCode:
      lines.add l
      continue
    var s = l.strip
    while s.startsWith("#"): s = s[1 .. ^1]
    s = s.strip
    if s.startsWith("> "): s = s[2 .. ^1]
    if s.allCharsInSet({'-', '|', ':', ' ', '='}) and s.len > 0 and ('-' in s or '=' in s): continue
    if s.startsWith("|"): s = s.strip(chars = {'|', ' '}).replace("|", " - ")
    # images, liens, emphase, code
    var o = ""
    var i = 0
    while i < s.len:
      if s[i] == '!' and i + 1 < s.len and s[i + 1] == '[':
        let e = s.find("](", i)
        let e2 = if e >= 0: s.find(')', e) else: -1
        if e >= 0 and e2 >= 0:
          o.add s[i + 2 ..< e]
          i = e2 + 1
          continue
      if s[i] == '[':
        let e = s.find("](", i)
        let e2 = if e >= 0: s.find(')', e) else: -1
        if e >= 0 and e2 >= 0:
          o.add s[i + 1 ..< e]
          i = e2 + 1
          continue
      if s[i] in {'*', '_', '`'}:
        if not (s[i] == '_' and i > 0 and i + 1 < s.len and s[i - 1].isAlphaNumeric and s[i + 1].isAlphaNumeric):
          inc i
          continue
      o.add s[i]
      inc i
    lines.add o
  result = lines.join("\n")
  # balises HTML éventuelles
  if '<' in result and '>' in result:
    var r = ""
    var i = 0
    while i < result.len:
      if result[i] == '<':
        let e = result.find('>', i)
        if e > i and e - i < 200 and (i + 1 < result.len and (result[i + 1].isAlphaAscii or result[i + 1] == '/')):
          i = e + 1
          continue
      r.add result[i]
      inc i
    result = r

#
# XML (docx, odt, epub)
#

proc xmlText(xml: string, paraTags: openArray[string], tabTag, brTag: string): string =
  var i = 0
  while i < xml.len:
    if xml[i] == '<':
      let e = xml.find('>', i)
      if e < 0: break
      let tag = xml[i + 1 ..< e]
      let closing = tag.startsWith("/")
      var name = tag
      if closing: name = name[1 .. ^1]
      let sp = name.find({' ', '/'})
      if sp >= 0: name = name[0 ..< sp]
      if closing and name in paraTags: result.add "\n"
      elif name == tabTag: result.add "\t"
      elif name == brTag: result.add "\n"
      elif name == "text:s":
        let c = attrValue(tag, "text:c")
        result.add repeat(' ', if c.len > 0: (try: parseInt(c) except ValueError: 1) else: 1)
      i = e + 1
    else:
      var e = xml.find('<', i)
      if e < 0: e = xml.len
      result.add decodeEntities(xml[i ..< e])
      i = e

proc officeText(path: string, kind: var string, title: var string): string =
  let z = openZip(path)
  defer: z.close()
  var i = z.find("word/document.xml")
  if i >= 0:
    kind = "docx"
    let ci = z.find("docProps/core.xml")
    if ci >= 0:
      let core = z.read(z.entries[ci])
      let a = core.find("<dc:title>")
      let b = core.find("</dc:title>")
      if a >= 0 and b > a: title = decodeEntities(core[a + 10 ..< b]).strip
    return xmlText(z.read(z.entries[i]), ["w:p"], "w:tab", "w:br").strip
  i = z.find("content.xml")
  if i >= 0:
    kind = "odt"
    let mi = z.find("meta.xml")
    if mi >= 0:
      let meta = z.read(z.entries[mi])
      let a = meta.find("<dc:title>")
      let b = meta.find("</dc:title>")
      if a >= 0 and b > a: title = decodeEntities(meta[a + 10 ..< b]).strip
    return xmlText(z.read(z.entries[i]), ["text:p", "text:h"], "text:tab", "text:line-break").strip
  i = z.find("ppt/presentation.xml")
  if i >= 0:
    kind = "pptx"
    var slides: seq[string]
    for e in z.entries:
      if e.name.startsWith("ppt/slides/slide") and e.name.endsWith(".xml"): slides.add e.name
    slides.sort(proc (a, b: string): int =
      let na = try: parseInt(a[16 ..< a.len - 4]) except ValueError: 0
      let nb = try: parseInt(b[16 ..< b.len - 4]) except ValueError: 0
      cmp(na, nb))
    for s in slides:
      result.add xmlText(z.read(z.entries[z.find(s)]), ["a:p"], "a:tab", "a:br").strip
      result.add "\n\n"
    return result.strip
  # epub : ordre de lecture du fichier OPF
  let ci = z.find("META-INF/container.xml")
  if ci >= 0:
    kind = "epub"
    let cont = z.read(z.entries[ci])
    let opfPath = attrValue(cont[cont.find("<rootfile") .. ^1], "full-path")
    let oi = z.find(opfPath)
    if oi < 0: return ""
    let opf = z.read(z.entries[oi])
    let dir = if '/' in opfPath: opfPath[0 .. opfPath.rfind('/')] else: ""
    let a = opf.find("<dc:title")
    if a >= 0:
      let s = opf.find('>', a)
      let e = opf.find("</dc:title>", s)
      if e > s: title = decodeEntities(opf[s + 1 ..< e]).strip
    var items = initTable[string, string]()
    var p = 0
    while true:
      let k = opf.find("<item ", p)
      if k < 0: break
      let e = opf.find('>', k)
      let tag = opf[k .. e]
      items[attrValue(tag, "id")] = attrValue(tag, "href")
      p = e
    p = 0
    while true:
      let k = opf.find("<itemref", p)
      if k < 0: break
      let e = opf.find('>', k)
      let idref = attrValue(opf[k .. e], "idref")
      if items.hasKey(idref):
        let hi = z.find(dir & decodeUrl(items[idref]))
        if hi >= 0:
          result.add htmlToText(z.read(z.entries[hi])).text
          result.add "\n\n"
      p = e
    return result.strip
  kind = "zip"
  ""

#
# lecture
#

type DocInfo = object
  text, title, author, kind: string
  pages: seq[string]

proc looksBinary(s: string): bool =
  var bad = 0
  for k in 0 ..< min(s.len, 4096):
    if s[k] == '\0': return true
    if ord(s[k]) < 9: inc bad
  bad > 20

proc lineShape(l: string): string =
  ## Ligne ramenée à sa forme (chiffres remplacés) : « page 3 / 40 » = « page 12 / 40 ».
  for c in l.strip:
    if c in {'0'..'9'}:
      if not result.endsWith("#"): result.add '#'
    elif c notin {' ', '\t'}: result.add c

proc removeRepeatedLines*(pages: seq[string]): seq[string] =
  ## En-têtes et pieds de page : lignes (forme sans chiffres) présentes sur au
  ## moins 3 pages et 30 % d'entre elles.
  if pages.len < 4: return pages
  var counts = initCountTable[string]()
  for pg in pages:
    var seen = initHashSet[string]()
    for l in pg.splitLines:
      let sh = lineShape(l)
      if sh.len >= 2 and sh notin seen:
        seen.incl sh
        counts.inc sh
  let limit = max(3, (pages.len * 3 + 9) div 10)
  for pg in pages:
    var kept: seq[string]
    for l in pg.splitLines:
      if counts.getOrDefault(lineShape(l)) < limit: kept.add l
    result.add kept.join("\n").strip

proc readDocument*(path: string, maxPages = 0): DocInfo =
  let data = readFile(path)
  let ext = path.splitFile.ext.toLowerAscii
  if data.startsWith("%PDF") or ext == ".pdf":
    let d = extractPdf(data, maxPages)
    result.kind = "pdf"
    result.pages = removeRepeatedLines(d.pages)
    result.text = result.pages.join("\n\n").strip
    result.title = d.title
    result.author = d.author
  elif data.startsWith("PK\x03\x04"):
    result.text = officeText(path, result.kind, result.title)
  elif ext in [".html", ".htm", ".xhtml"] or data[0 ..< min(data.len, 512)].toLowerAscii.contains("<html"):
    let h = htmlToText(data)
    result.kind = "html"
    result.text = h.text
    result.title = h.title
  elif ext in [".md", ".markdown"]:
    result.kind = "markdown"
    result.text = markdownToText(data)
    for l in data.splitLines:
      if l.startsWith("# "):
        result.title = l[2 .. ^1].strip
        break
  elif data.isGzip:
    result.kind = "gzip"
    result.text = gzipDecompress(data)
  else:
    if looksBinary(data): raise newException(IOError, "format non pris en charge : " & extractFilename(path))
    result.kind = "texte"
    result.text = data
    if result.text.startsWith("\xEF\xBB\xBF"): result.text = result.text[3 .. ^1]
    if result.text.validateUtf8 != -1:
      # Latin-1 / Windows-1252 -> UTF-8
      var t = ""
      for c in result.text:
        if ord(c) < 128: t.add c else: t.add $Rune(ord(c))
      result.text = t
  if result.title.len == 0:
    for l in result.text.splitLines:
      let s = l.strip
      if s.len >= 3:
        result.title = if s.runeLen > 120: s.runeSubStr(0, 120) & "…" else: s
        break

#
# phrases, passages
#

proc sentences*(text: string): seq[string] =
  ## Découpe en phrases (fin : . ! ? … suivis d'un espace et d'une majuscule,
  ## d'un chiffre ou d'un guillemet ; fins de paragraphe).
  const abbrev = ["m", "mme", "mlle", "dr", "pr", "st", "ex", "etc", "cf", "p", "vol", "fig", "env", "mr", "mrs", "vs", "no", "n°"]
  var cur = ""
  var curBroken = false        # la phrase en cours a déjà franchi une fin de ligne
  var curAtLine = true         # la phrase en cours a commencé en début de ligne
  let t = text.replace("\r", "")
  var i = 0
  while i < t.len:
    let c = t[i]
    if c == '\n' and i + 1 < t.len and t[i + 1] == '\n':
      if cur.strip.len > 0: result.add cur.strip
      cur = ""
      curBroken = false
      curAtLine = true
      i += 2
      continue
    if c == '\n' and cur.len > 300:
      # bloc sans ponctuation (code, liste, tableau) : coupé à la fin de ligne
      if cur.strip.len > 0: result.add cur.strip
      cur = ""
      curBroken = false
      curAtLine = true
      inc i
      continue
    if c == '\n' and not curBroken and curAtLine:
      # titre : ligne entière, courte, sans ponctuation finale, suivie d'une
      # ligne qui commence par une majuscule ou un chiffre
      let s = cur.strip
      if s.len > 0 and s.len < 120 and s[^1] notin {'.', ',', ';', ':', '!', '?', '-', '(', '\'', '"'}:
        var k = i + 1
        while k < t.len and t[k] in {' ', '\t'}: inc k
        if k < t.len and (t[k] in {'A'..'Z', '0'..'9'} or
                          (t[k] == '\xC3' and k + 1 < t.len and t[k + 1] in {'\x80'..'\x9E'})):
          result.add s
          cur = ""
          curAtLine = true
          inc i
          continue
    if c == '\n': curBroken = true
    cur.add(if c == '\n': ' ' else: c)
    var endSent = false
    if c in {'.', '!', '?'} or (c == '\xA6' and cur.endsWith("…")):
      var j = i + 1
      while j < t.len and t[j] in {'"', ')', '\'', '\xBB'}: inc j
      if j >= t.len: endSent = true
      elif t[j] in {' ', '\n', '\t'}:
        var k = j
        while k < t.len and t[k] in {' ', '\n', '\t'}: inc k
        if k >= t.len or t[k] in {'A'..'Z', '0'..'9', '"', '-', '\xC2', '\xC3', '\xE2', '('}:
          endSent = true
          if c == '.':
            let ws = strutils.splitWhitespace(cur[0 ..< cur.len - 1])
            if ws.len > 0:
              let last = ws[^1].toLowerAscii.strip(chars = {'(', '"'})
              if last in abbrev or (last.len == 1 and last[0].isAlphaAscii): endSent = false
    if endSent:
      if cur.strip.len > 0: result.add cur.strip
      cur = ""
      curBroken = false
      # la phrase suivante commence-t-elle sur une nouvelle ligne ?
      var k = i + 1
      curAtLine = false
      while k < t.len and t[k] in {' ', '\t', '\n', '"', ')', '\''}:
        if t[k] == '\n': curAtLine = true
        inc k
    inc i
  if cur.strip.len > 0: result.add cur.strip

type Chunk = object
  text: string
  start, stop: int

proc chunkText*(text: string, size = 900, overlap = 150): seq[Chunk] =
  ## Passages d'environ `size` caractères, coupés entre paragraphes ou phrases,
  ## qui se recouvrent d'environ `overlap` caractères.
  var paras: seq[(int, string)]
  var pos = 0
  for p in text.split("\n\n"):
    let s = p.strip
    if s.len > 0:
      let at = text.find(s, pos)
      paras.add (max(0, at), s)
      if at >= 0: pos = at + s.len
  var units: seq[(int, string)]
  for (at, p) in paras:
    if p.len <= size: units.add (at, p)
    else:
      var off = at
      for s in sentences(p):
        let k = text.find(s[0 ..< min(s.len, 30)], off)
        let here = if k >= 0: k else: off
        if s.len <= size: units.add (here, s)
        else:
          var j = 0
          while j < s.len:
            var e = min(s.len, j + size)
            if e < s.len:
              let sp = s.rfind(' ', e)
              if sp > j + size div 2: e = sp
            units.add (here + j, s[j ..< e].strip)
            j = e
        off = here
  var cur: seq[(int, string)]
  var curLen = 0
  proc emit(cur: seq[(int, string)], res: var seq[Chunk]) =
    if cur.len == 0: return
    var t = ""
    for k, (_, u) in cur:
      if k > 0: t.add "\n"
      t.add u
    res.add Chunk(text: t, start: cur[0][0], stop: cur[^1][0] + cur[^1][1].len)
  for u in units:
    if curLen > 0 and curLen + u[1].len > size:
      emit(cur, result)
      # recouvrement : dernières unités jusqu'à `overlap` caractères
      var keep: seq[(int, string)]
      var kl = 0
      var k = cur.high
      while k >= 0 and kl + cur[k][1].len <= overlap:
        keep.insert(cur[k], 0)
        kl += cur[k][1].len
        dec k
      if keep.len == 0 and overlap > 0 and cur.len > 0:
        let last = cur[^1][1]
        let ss = sentences(last)
        if ss.len > 1 and ss[^1].len <= overlap: keep.add (cur[^1][0] + last.len - ss[^1].len, ss[^1])
      cur = keep
      curLen = kl
    cur.add u
    curLen += u[1].len + 1
  emit(cur, result)

#
# termes et concepts
#

type Term = object
  key, display: string
  count: int

proc candidateTerms(text: string, maxN = 3): seq[(string, string)] =
  ## (clef, forme) de chaque terme candidat : mots pleins, paires de mots
  ## pleins, et « X de Y » (bases de données).
  ensureStops()
  var surf: seq[string]
  let ws = wordsWithSurface(text, surf)
  var keys = newSeq[string](ws.len)
  var good = newSeq[bool](ws.len)
  for k, w in ws:
    keys[k] = foldKey(w)
    good[k] = w.runeLen >= 3 and not isStop(w) and not isStop(keys[k]) and not isNumberWord(w)
  for k, w in ws:
    if good[k]: result.add (keys[k], w)
    if maxN >= 2 and k + 1 < ws.len and good[k] and good[k + 1]:
      result.add (keys[k] & " " & keys[k + 1], w & " " & ws[k + 1])
    if maxN >= 3 and k + 2 < ws.len and good[k] and good[k + 2] and ws[k + 1] in ["de", "du", "des", "d", "of", "à", "en"]:
      result.add (keys[k] & " " & ws[k + 1] & " " & keys[k + 2], w & " " & ws[k + 1] & " " & surf[k + 2])

proc keywords*(text: string, maxTerms = 20): seq[Term] =
  var counts = initTable[string, int]()
  var forms = initTable[string, CountTable[string]]()
  for (k, f) in candidateTerms(text):
    counts.mgetOrPut(k, 0) += 1
    forms.mgetOrPut(k, initCountTable[string]()).inc f
  var terms: seq[(float, string)]
  for k, c in counts:
    let n = k.count(' ') + 1
    if n > 1 and c < 2: continue
    terms.add (float(c) * (if n == 1: 1.0 elif n == 2: 1.8 else: 2.2), k)
  terms.sort(proc (a, b: (float, string)): int = cmp(b[0], a[0]))
  var chosen: seq[string]
  for (s, k) in terms:
    if chosen.len >= maxTerms: break
    # un mot déjà couvert par une expression plus longue et presque aussi fréquente
    var covered = false
    for c in chosen:
      if (c.startsWith(k & " ") or c.endsWith(" " & k)) and float(counts[c]) * 1.5 >= float(counts[k]): covered = true
    if covered: continue
    chosen.add k
    result.add Term(key: k, display: forms[k].largest[0], count: counts[k])

type ConceptRes = object
  terms: seq[(string, string, float, int, int, seq[string])]   # clef, forme, poids, fréquence, passages, sources
  links: seq[(string, string, float, int)]

proc concepts*(passages: seq[(string, string)], maxConcepts = 40, minDocs = 2, maxLinks = 4,
               minLink = 0.12): ConceptRes =
  ## passages : (texte, source). TF-IDF des termes, puis cooccurrences dans les
  ## passages (cosinus) pour les liens. Les passages sont pondérés par source
  ## (1 / racine du nombre de passages de leur document) : un long document ne
  ## recouvre pas la carte, et un terme commun à plusieurs documents est favorisé.
  let n = passages.len
  if n == 0: return
  var tf = initTable[string, int]()
  var tfw = initTable[string, float]()
  var df = initTable[string, int]()
  var forms = initTable[string, CountTable[string]]()
  var sets = newSeq[HashSet[string]](n)
  var sources = initTable[string, HashSet[string]]()
  var perSource = initCountTable[string]()
  for (_, src) in passages: perSource.inc src
  let avgPassages = float(n) / float(max(1, perSource.len))
  for i, (text, src) in passages:
    sets[i] = initHashSet[string]()
    let w = sqrt(avgPassages / float(max(1, perSource[src])))
    for (k, f) in candidateTerms(text):
      tf.mgetOrPut(k, 0) += 1
      tfw.mgetOrPut(k, 0.0) += w
      forms.mgetOrPut(k, initCountTable[string]()).inc f
      if k notin sets[i]:
        sets[i].incl k
        df.mgetOrPut(k, 0) += 1
        if src.len > 0: sources.mgetOrPut(k, initHashSet[string]()).incl src
  let need = if n < 4: 1 else: minDocs
  var scored: seq[(float, string)]
  for k, c in tf:
    let d = df[k]
    # trop rare : sauf un terme répété dans un passage (petit document)
    if d < need and c < 2: continue
    let words = k.count(' ') + 1
    if words > 1 and c < 2: continue
    if d > max(3, int(float(n) * 0.85)) and n >= 8: continue      # présent partout : peu informatif
    let idf = ln((float(n) + 1) / (float(d) + 0.5)) + 0.5
    let nsrc = if sources.hasKey(k): sources[k].len else: 1
    let shared = min(2.5, 1.0 + 0.35 * float(nsrc - 1))
    scored.add (tfw[k] * idf * shared * (if words == 1: 1.0 elif words == 2: 1.7 else: 2.0), k)
  scored.sort(proc (a, b: (float, string)): int = cmp(b[0], a[0]))
  var chosen: seq[string]
  var weights: seq[float]
  for (s, k) in scored:
    if chosen.len >= maxConcepts: break
    var covered = false
    for c in chosen:
      if (c.startsWith(k & " ") or c.endsWith(" " & k) or k.startsWith(c & " ") or k.endsWith(" " & c)) and
         float(df[c]) * 1.6 >= float(df[k]) and float(df[k]) * 1.6 >= float(df[c]):
        covered = true
    if covered: continue
    chosen.add k
    weights.add s
  if chosen.len == 0: return
  let top = weights[0]
  for i, k in chosen:
    var srcs: seq[string]
    if sources.hasKey(k):
      for s in sources[k]: srcs.add s
      srcs.sort()
    result.terms.add (k, forms[k].largest[0], weights[i] / top, tf[k], df[k], srcs)
  # cooccurrences
  var idx = initTable[string, int]()
  for i, k in chosen: idx[k] = i
  var co = initTable[(int, int), int]()
  for s in sets:
    var present: seq[int]
    for k in s:
      if idx.hasKey(k): present.add idx[k]
    present.sort()
    for a in 0 ..< present.len:
      for b in a + 1 ..< present.len:
        co.mgetOrPut((present[a], present[b]), 0) += 1
  var cand: seq[(float, int, int, int)]
  for (ab, c) in co.pairs:
    let (a, b) = ab
    # deux termes dont l'un contient l'autre : lien trivial
    if chosen[a].contains(chosen[b]) or chosen[b].contains(chosen[a]): continue
    let w = float(c) / sqrt(float(df[chosen[a]]) * float(df[chosen[b]]))
    let rare = min(df[chosen[a]], df[chosen[b]]) <= 2
    if w >= minLink and c >= (if n < 4 or rare: 1 else: 2): cand.add (w, a, b, c)
  cand.sort(proc (x, y: (float, int, int, int)): int = cmp(y[0], x[0]))
  var deg = newSeq[int](chosen.len)
  for (w, a, b, c) in cand:
    if deg[a] >= maxLinks and deg[b] >= maxLinks: continue
    inc deg[a]
    inc deg[b]
    result.links.add (chosen[a], chosen[b], w, c)

#
# disposition
#

proc layoutGraph*(ids: seq[string], sizes: seq[float], edges: seq[(int, int, float)],
                  w, h: float, iterations = 300, init: seq[(bool, float, float)] = @[]): seq[(float, float)] =
  ## Fruchterman-Reingold (forces de ressort et de répulsion), départ en cercle
  ## déterministe, attraction douce vers le centre pour les nœuds isolés.
  let n = ids.len
  result = newSeq[(float, float)](n)
  if n == 0: return
  var deg = newSeq[int](n)
  for (a, b, _) in edges:
    inc deg[a]
    inc deg[b]
  var order = toSeq(0 ..< n)
  order.sort(proc (a, b: int): int = cmp(deg[b], deg[a]))
  var px = newSeq[float](n)
  var py = newSeq[float](n)
  var known = 0
  for rank, i in order:
    if i < init.len and init[i][0]:
      px[i] = init[i][1]
      py[i] = init[i][2]
      inc known
      continue
    let ang = float(rank) * 2.399963          # angle d'or
    let r = sqrt(float(rank) + 0.5) / sqrt(float(n)) * min(w, h) * 0.45
    px[i] = w / 2 + r * cos(ang)
    py[i] = h / 2 + r * sin(ang)
  # nouveaux nœuds reliés à des nœuds placés : à côté de leur voisin
  if known > 0:
    for (a, b, _) in edges:
      for (x, y) in [(a, b), (b, a)]:
        if x < init.len and not init[x][0] and y < init.len and init[y][0]:
          px[x] = px[y] + float((x * 37) mod 80) - 40
          py[x] = py[y] + float((x * 53) mod 80) - 40
  let k = sqrt(w * h / float(n)) * 0.75
  # carte déjà en grande partie placée : petits déplacements seulement
  var temp = if known * 2 >= n: min(w, h) / 30 else: min(w, h) / 8
  let cool = temp / float(iterations + 1)
  var dx = newSeq[float](n)
  var dy = newSeq[float](n)
  for it in 0 ..< iterations:
    for i in 0 ..< n:
      dx[i] = 0
      dy[i] = 0
    for i in 0 ..< n:
      for j in i + 1 ..< n:
        var ex = px[i] - px[j]
        var ey = py[i] - py[j]
        var d = sqrt(ex * ex + ey * ey)
        if d < 0.01:
          ex = 0.01 * float((i * 7 + j * 3) mod 5 - 2)
          ey = 0.01
          d = 0.02
        let extra = (sizes[i] + sizes[j]) * 0.5
        let f = k * k / max(d - extra * 0.3, d * 0.3)
        dx[i] += ex / d * f
        dy[i] += ey / d * f
        dx[j] -= ex / d * f
        dy[j] -= ey / d * f
    for (a, b, wt) in edges:
      let ex = px[a] - px[b]
      let ey = py[a] - py[b]
      let d = max(0.01, sqrt(ex * ex + ey * ey))
      let f = d * d / k * (0.5 + wt)
      dx[a] -= ex / d * f
      dy[a] -= ey / d * f
      dx[b] += ex / d * f
      dy[b] += ey / d * f
    for i in 0 ..< n:
      # gravité vers le centre
      dx[i] -= (px[i] - w / 2) * 0.03 * (if deg[i] == 0: 3.0 else: 1.0)
      dy[i] -= (py[i] - h / 2) * 0.03 * (if deg[i] == 0: 3.0 else: 1.0)
      let d = sqrt(dx[i] * dx[i] + dy[i] * dy[i])
      if d > 0:
        px[i] += dx[i] / d * min(d, temp)
        py[i] += dy[i] / d * min(d, temp)
      px[i] = max(0.0, min(w, px[i]))
      py[i] = max(0.0, min(h, py[i]))
    temp = max(1.0, temp - cool)
  for i in 0 ..< n: result[i] = (px[i], py[i])

#
# extraits
#

proc bestSentences*(texts: seq[(string, string)], question: string, n: int): seq[(string, string, float)] =
  ## Phrases (phrase, source, score) qui partagent le plus de termes (pondérés
  ## par leur rareté) avec la question.
  ensureStops()
  var q = initHashSet[string]()
  for w in words(question):
    if not isStop(w): q.incl foldKey(w)
  if q.len == 0: return
  var all: seq[(string, string, HashSet[string])]
  var df = initTable[string, int]()
  for (t, src) in texts:
    for s in sentences(t):
      if s.runeLen < 25: continue
      var ks = initHashSet[string]()
      for w in words(s): ks.incl foldKey(w)
      for k in ks:
        if k in q: df.mgetOrPut(k, 0) += 1
      all.add (s, src, ks)
  let total = float(max(1, all.len))
  var scored: seq[(float, int)]
  for i, (s, src, ks) in all:
    var sc = 0.0
    var hits = 0
    for k in q:
      if k in ks:
        sc += ln(1 + total / float(df.getOrDefault(k, 1)))
        inc hits
    if hits == 0: continue
    sc *= (1 + float(hits) / float(q.len))
    sc /= pow(max(1.0, float(s.runeLen) / 160), 0.6)
    scored.add (sc, i)
  scored.sort(proc (a, b: (float, int)): int = cmp(b[0], a[0]))
  var seen = initHashSet[string]()
  for (sc, i) in scored:
    if result.len >= n: break
    if all[i][0] in seen: continue
    seen.incl all[i][0]
    result.add (all[i][0], all[i][1], sc)

#
# paquet
#

proc textsOf(L: Interp, v: Value, fname: string): seq[(string, string)] =
  if v.kind == vkStr: return @[(v.s, "")]
  if v.kind != vkTable: argError(1, fname, "texte ou liste de passages attendu")
  for i in 1 .. v.t.rawLen:
    let x = v.t.rawGet(i)
    if x.kind == vkTable:
      result.add (L.tostr(x.t.field("texte")), (let s = x.t.field("source"); if s.kind == vkNil: "" else: L.tostr(s)))
    else: result.add (L.tostr(x), "")

proc protectDoc(body: proc (): seq[Value]): seq[Value] =
  try: body()
  except PdfError as e: rtError(e.msg)
  except CompressionError as e: rtError(e.msg)
  except IOError as e: rtError(e.msg)
  except OSError as e: rtError(e.msg)

proc openDocument(L: Interp): Value =
  let m = newLib()
  m.fn "lire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.checkStr(a, 1, "lire")
    let o = if arg(a, 2).kind == vkTable: a[1].t else: nil
    let maxPages = optField(o, "pages", 0)
    protectDoc proc (): seq[Value] =
      if not fileExists(path): rtError("document introuvable : " & path)
      var d: DocInfo
      L.blocking: d = readDocument(path, maxPages)
      let t = newLTable()
      t.set "texte", strV(d.text)
      t.set "titre", strV(d.title)
      t.set "auteur", strV(d.author)
      t.set "type", strV(d.kind)
      t.set "chemin", strV(path)
      t.set "taille", intV(getFileSize(path))
      t.set "langue", strV(detectLang(d.text))
      t.set "mots", intV(words(d.text).len)
      if d.pages.len > 0:
        t.set "pages", intV(d.pages.len)
        t.set "textepages", toV(d.pages)
      @[tableV(t)]
  m.fn "texte", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.checkStr(a, 1, "texte")
    protectDoc proc (): seq[Value] =
      var d: DocInfo
      L.blocking: d = readDocument(path)
      @[strV(d.text)]
  m.fn "pdf", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.checkStr(a, 1, "pdf")
    let maxPages = int(L.optInt(a, 2, "pdf", 0))
    protectDoc proc (): seq[Value] =
      var d: PdfDoc
      L.blocking: d = extractPdf(readFile(path), maxPages)
      @[record({"texte": strV(d.pages.join("\n\n").strip), "pages": toV(d.pages),
                "titre": strV(d.title), "auteur": strV(d.author), "nombre": intV(d.pages.len)})]
  m.fn "html", proc (L: Interp, a: seq[Value]): seq[Value] =
    let h = htmlToText(L.checkStr(a, 1, "html"), L.optStr(a, 2, "html", ""))
    let links = newLTable()
    for (t, u) in h.links: links.arr.add record({"texte": strV(t), "url": strV(u)})
    @[record({"texte": strV(h.text), "titre": strV(h.title), "description": strV(h.description),
              "liens": tableV(links)})]
  m.fn "markdown", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(markdownToText(L.checkStr(a, 1, "markdown")))]
  m.fn "entites", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(decodeEntities(L.checkStr(a, 1, "entites")))]
  m.fn "langue", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(detectLang(L.checkStr(a, 1, "langue")))]
  m.fn "mots", proc (L: Interp, a: seq[Value]): seq[Value] =
    let all = optBool(a, 2, false)
    var r: seq[string]
    for w in words(L.checkStr(a, 1, "mots")):
      if all or not isStop(w): r.add w
    @[toV(r)]
  m.fn "cle", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(foldKey(L.checkStr(a, 1, "cle")))]
  m.fn "phrases", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[toV(sentences(L.checkStr(a, 1, "phrases")))]
  m.fn "decouper", proc (L: Interp, a: seq[Value]): seq[Value] =
    let text = L.checkStr(a, 1, "decouper")
    let o = if arg(a, 2).kind == vkTable: a[1].t else: nil
    let size = max(100, optField(o, "taille", 900))
    let ov = max(0, min(size div 2, optField(o, "chevauchement", 150)))
    let t = newLTable()
    for i, c in chunkText(text, size, ov):
      t.arr.add record({"texte": strV(c.text), "debut": intV(c.start + 1), "fin": intV(c.stop),
                        "numero": intV(i + 1)})
    @[tableV(t)]
  m.fn "motscles", proc (L: Interp, a: seq[Value]): seq[Value] =
    let text = L.checkStr(a, 1, "motscles")
    let n = int(L.optInt(a, 2, "motscles", 20))
    let t = newLTable()
    for x in keywords(text, n):
      t.arr.add record({"terme": strV(x.display), "cle": strV(x.key), "nombre": intV(x.count)})
    @[tableV(t)]
  m.fn "concepts", proc (L: Interp, a: seq[Value]): seq[Value] =
    let texts = L.textsOf(arg(a, 1), "concepts")
    let o = if arg(a, 2).kind == vkTable: a[1].t else: nil
    var r: ConceptRes
    let mx = optField(o, "max", 40)
    let md = optField(o, "min", 2)
    let ml = optField(o, "liens", 4)
    let mw = optField(o, "seuil", 0.12)
    L.blocking: r = concepts(texts, mx, md, ml, mw)
    let ct = newLTable()
    for (k, f, w, c, d, srcs) in r.terms:
      ct.arr.add record({"terme": strV(f), "cle": strV(k), "poids": numV(w), "frequence": intV(c),
                         "passages": intV(d), "sources": toV(srcs)})
    let lt = newLTable()
    for (x, y, w, c) in r.links:
      lt.arr.add record({"a": strV(x), "b": strV(y), "poids": numV(w), "nombre": intV(c)})
    @[record({"concepts": tableV(ct), "liens": tableV(lt)})]
  m.fn "disposer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let nv = L.checkTable(a, 1, "disposer")
    let lv = if arg(a, 2).kind == vkTable: a[1].t else: newLTable()
    let o = if arg(a, 3).kind == vkTable: a[2].t else: nil
    var ids: seq[string]
    var sizes: seq[float]
    var init: seq[(bool, float, float)]
    var index = initTable[string, int]()
    for i in 1 .. nv.rawLen:
      let x = nv.rawGet(i)
      var id: string
      var sz = 0.0
      var pos = (false, 0.0, 0.0)
      if x.kind == vkTable:
        id = L.tostr(x.t.field("id"))
        var ok = false
        sz = toFloat(x.t.field("taille"), ok)
        if not ok: sz = 0
        var okx, oky = false
        let px = toFloat(x.t.field("x"), okx)
        let py = toFloat(x.t.field("y"), oky)
        if okx and oky: pos = (true, px, py)
      else: id = L.tostr(x)
      index[id] = ids.len
      ids.add id
      sizes.add sz
      init.add pos
    var edges: seq[(int, int, float)]
    for i in 1 .. lv.rawLen:
      let x = lv.rawGet(i)
      if x.kind != vkTable: continue
      let ea = L.tostr(x.t.field("a"))
      let eb = L.tostr(x.t.field("b"))
      if index.hasKey(ea) and index.hasKey(eb) and ea != eb:
        var ok = false
        var w = toFloat(x.t.field("poids"), ok)
        if not ok: w = 0.5
        edges.add (index[ea], index[eb], w)
    let w = optField(o, "largeur", 1200.0)
    let h = optField(o, "hauteur", 800.0)
    let it = optField(o, "iterations", 300)
    var pos: seq[(float, float)]
    L.blocking: pos = layoutGraph(ids, sizes, edges, w, h, it, init)
    let t = newLTable()
    for i, id in ids:
      t.rawSet(strV(id), record({"x": numV(round(pos[i][0], 1)), "y": numV(round(pos[i][1], 1))}))
    @[tableV(t)]
  m.fn "extraits", proc (L: Interp, a: seq[Value]): seq[Value] =
    let texts = L.textsOf(arg(a, 1), "extraits")
    let q = L.checkStr(a, 2, "extraits")
    let n = int(L.optInt(a, 3, "extraits", 3))
    var r: seq[(string, string, float)]
    L.blocking: r = bestSentences(texts, q, n)
    let t = newLTable()
    for (s, src, sc) in r:
      t.arr.add record({"phrase": strV(s), "source": strV(src), "score": numV(round(sc, 3))})
    @[tableV(t)]
  tableV(m)

registerPackage PackageDef(name: "document", open: openDocument,
  description: "Texte des documents (PDF, HTML, Markdown, DOCX, ODT, EPUB), passages, concepts",
  docs: docs("document", [
    "document.lire(chemin, [{pages=}])", "Lit un document et en extrait le texte : PDF (Nim pur : polices, ToUnicode, flux compressés ; pas les pages scannées), HTML, Markdown, texte, DOCX, ODT, PPTX, EPUB. Renvoie {texte, titre, auteur, type, chemin, taille, langue, mots, pages, textepages}. pages : nombre maximal de pages PDF lues.",
    "document.texte(chemin)", "Texte seul d'un document.",
    "document.pdf(chemin, [pages])", "Texte d'un PDF : {texte, pages (liste, une entrée par page), titre, auteur, nombre}.",
    "document.html(html, [url])", "Texte d'une page HTML (contenu principal, sans scripts ni menus) : {texte, titre, description, liens = {{texte, url}}} ; url : adresse de la page, pour rendre les liens absolus.",
    "document.markdown(texte)", "Texte brut d'un document Markdown (sans balisage).",
    "document.entites(texte)", "Remplace les entités HTML (&eacute; &#233; &amp;...).",
    "document.langue(texte)", "Langue probable : \"fr\", \"en\", \"de\", \"es\", \"it\" ou \"\".",
    "document.mots(texte, [tous])", "Mots en minuscules (élisions retirées) ; sans les mots vides (le, de, the...) sauf si tous = vrai.",
    "document.cle(mot)", "Clef de comparaison d'un mot : minuscules, sans accents, sans pluriel simple (« Données » -> « donnee »).",
    "document.phrases(texte)", "Liste des phrases.",
    "document.decouper(texte, [{taille=900, chevauchement=150}])", "Passages d'environ taille caractères, coupés entre paragraphes ou phrases et qui se recouvrent : liste de {texte, debut, fin, numero}.",
    "document.motscles(texte, [max=20])", "Termes caractéristiques d'un texte (mots et expressions) : {terme, cle, nombre}.",
    "document.concepts(passages, [{max=40, min=2, liens=4, seuil=0.12}])", "Carte des concepts d'un ensemble de passages (textes ou {texte=, source=}) : {concepts = {{terme, cle, poids (0 à 1), frequence, passages, sources}}, liens = {{a, b, poids, nombre}}} ; a et b sont des clefs de concepts, reliés quand ils apparaissent dans les mêmes passages.",
    "document.disposer(noeuds, liens, [{largeur=1200, hauteur=800, iterations=300}])", "Disposition d'un graphe par forces (noeuds : identifiants ou {id=, taille=, x=, y=} ; liens : {a=, b=, poids=}) ; renvoie {id = {x, y}}. Des nœuds déjà placés (x, y) bougent peu : une carte qui grandit reste reconnaissable.",
    "document.extraits(textes, question, [n=3])", "Phrases les plus proches d'une question (termes communs pondérés par leur rareté) : liste de {phrase, source, score}. textes : texte ou liste de {texte=, source=}."]))
