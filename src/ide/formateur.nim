# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - formateur de code Lexis+ (conventions réglables)
#
# Réindente les blocs, normalise les espaces et, au choix, la casse des noms.
# Conventions lues dans le fichier « .lexisformat » du dossier du projet (ou
# d'un dossier parent), une option par ligne « clef = valeur » :
#
#   indentation = 2                  espaces par niveau
#   tabulations = non                oui : une tabulation par niveau
#   corps_procedure = indente        indente | colonne0
#   retour_final = conserver         conserver : « retourner » final en colonne 0 gardé
#   espaces_operateurs = oui         a = b, a == b, a <> b, a <= b, x += 1
#   espace_apres_virgule = oui
#   lignes_vides_max = 1
#   ligne_vide_avant_procedure = oui
#   noms_procedures = conserver      conserver | majuscules | minuscules (définitions et appels)
#   casse_variables = conserver      conserver | declaration (orthographe de la déclaration)
#   fin_de_fichier = oui             saut de ligne final
#   cas_indentes = oui               « cas » indentés sous « faire cas »
#
# Garantie : si le texte d'origine est syntaxiquement correct et que le résultat
# ne l'est plus (cas imprévu), le texte d'origine est rendu inchangé.
# Les chaînes longues [[ ... ]] sur plusieurs lignes ne sont jamais modifiées.

import std/[strutils, tables, os]
import lexislang, lexisanalyse
from ../lexis/parser import parseChunk
from ../lexis/lexer import SyntaxError

type
  FormatOptions* = object
    indent*: int
    tabs*: bool
    indentProcBody*: bool
    keepFinalReturn*: bool
    spaceOps*: bool
    spaceAfterComma*: bool
    maxBlank*: int
    blankBeforeProc*: bool
    procCase*: string            # conserver, majuscules, minuscules
    varCase*: string             # conserver, declaration
    finalNewline*: bool
    indentCases*: bool           # « cas » / « autrement » indentés sous « faire cas »

  FormatResult* = object
    text*: string
    changed*: bool
    safe*: bool                  # faux : résultat refusé (syntaxe), texte d'origine rendu
    message*: string

const FormatFile* = ".lexisformat"

proc defaultFormat*(): FormatOptions =
  FormatOptions(indent: 2, tabs: false, indentProcBody: true, keepFinalReturn: true, spaceOps: true,
                spaceAfterComma: true, maxBlank: 1, blankBeforeProc: true, procCase: "conserver",
                varCase: "conserver", finalNewline: true, indentCases: true)

proc yes(v: string): bool = v.toLowerAscii in ["oui", "vrai", "1", "o", "yes", "true"]

proc parseFormatOptions*(text: string, base = defaultFormat()): FormatOptions =
  result = base
  for raw in text.splitLines():
    var l = raw.strip
    if l.len == 0 or l[0] in {'#', '&', '/', ';'}: continue
    let eq = l.find('=')
    if eq < 0: continue
    let k = l[0 ..< eq].strip.toLowerAscii.replace(' ', '_')
    let v = l[eq + 1 .. ^1].strip.toLowerAscii
    case k
    of "indentation":
      try: result.indent = max(1, min(8, parseInt(v)))
      except ValueError: discard
    of "tabulations": result.tabs = yes(v)
    of "corps_procedure": result.indentProcBody = v != "colonne0"
    of "retour_final": result.keepFinalReturn = v == "conserver"
    of "espaces_operateurs": result.spaceOps = yes(v)
    of "espace_apres_virgule": result.spaceAfterComma = yes(v)
    of "lignes_vides_max":
      try: result.maxBlank = max(0, parseInt(v))
      except ValueError: discard
    of "ligne_vide_avant_procedure": result.blankBeforeProc = yes(v)
    of "noms_procedures": result.procCase = v
    of "casse_variables": result.varCase = v
    of "fin_de_fichier": result.finalNewline = yes(v)
    of "cas_indentes": result.indentCases = yes(v)
    else: discard

proc findFormatFile*(dir: string): string =
  ## .lexisformat du dossier ou du plus proche dossier parent ("" sinon).
  var d = dir
  for _ in 0 .. 20:
    if d.len == 0: break
    let f = d / FormatFile
    if fileExists(f): return f
    let p = d.parentDir
    if p == d or p.len == 0: break
    d = p
  ""

proc loadFormatOptions*(dir: string): FormatOptions =
  result = defaultFormat()
  let f = findFormatFile(dir)
  if f.len > 0:
    try: result = parseFormatOptions(readFile(f))
    except IOError, OSError: discard

proc formatOptionsText*(o: FormatOptions): string =
  ## Contenu d'un fichier .lexisformat reprenant les options.
  proc b(x: bool): string = (if x: "oui" else: "non")
  "# Conventions du formateur Lexis+ (atelier : Édition › Formater le document)\n" &
  "indentation = " & $o.indent & "\n" &
  "tabulations = " & b(o.tabs) & "\n" &
  "corps_procedure = " & (if o.indentProcBody: "indente" else: "colonne0") & "\n" &
  "retour_final = " & (if o.keepFinalReturn: "conserver" else: "indente") & "\n" &
  "espaces_operateurs = " & b(o.spaceOps) & "\n" &
  "espace_apres_virgule = " & b(o.spaceAfterComma) & "\n" &
  "lignes_vides_max = " & $o.maxBlank & "\n" &
  "ligne_vide_avant_procedure = " & b(o.blankBeforeProc) & "\n" &
  "noms_procedures = " & o.procCase & "\n" &
  "casse_variables = " & o.varCase & "\n" &
  "fin_de_fichier = " & b(o.finalNewline) & "\n" &
  "cas_indentes = " & b(o.indentCases) & "\n"

const
  SpacedOps = ["=", "==", "<>", "!=", "<=", ">=", "+=", "-=", "<", ">"]
  Openers = ["si", "tantque", "pour", "essayer", "parcourir"]
  Closers = ["finsi", "fintantque", "suivant", "finpour", "finessayer", "finparcourir"]

type
  Blk = object
    kind: string
    base: int                    # niveau de l'en-tête du bloc

proc leadingWidth(s: string): int =
  for c in s:
    if c == ' ': inc result
    elif c == '\t': result += 4
    else: break

proc rebuild(line: string, toks: seq[Token], o: FormatOptions,
             renames: Table[int, string]): string =
  # Ligne sans indentation, espaces normalisés.
  var sig: seq[Token]
  for t in toks:
    if t.kind != tkSpace: sig.add t
  if sig.len == 0: return ""
  for t in sig:
    if t.kind == tkError: return line.strip(trailing = false).strip(leading = false)   # inchangée
  # opérateurs arithmétiques binaires (précédés d'une valeur) : espacés comme les comparaisons
  var binary = newSeq[bool](sig.len)
  if o.spaceOps:
    for i in 1 ..< sig.len:
      let t = sig[i]
      let txt = tokText(line, t)
      if t.kind == tkOperator and txt in ["+", "-", "*", "/", "%", "^", ".."]:
        let p = sig[i - 1]
        let ptxt = tokText(line, p)
        binary[i] = p.kind in {tkIdent, tkBuiltin, tkNumber, tkString} or ptxt in [")", "]", "}"] or
                    (p.kind == tkKeyword and ptxt in ["vrai", "faux", "nul"])
  var res = ""
  for i, t in sig:
    var txt = tokText(line, t)
    if t.start in renames: txt = renames[t.start]
    if i > 0:
      let p = sig[i - 1]
      let ptxt = tokText(line, p)
      let gapRaw = t.start - (p.start + p.len)
      let hadSpace = gapRaw > 0
      var sep = if hadSpace: " " else: ""
      if t.kind == tkComment:
        sep = if hadSpace: line[p.start + p.len ..< t.start] else: ""
      elif t.kind == tkEscape or p.kind == tkEscape or
           (t.kind == tkString and p.kind == tkString and gapRaw == 0):
        sep = ""                                  # morceaux d'une même chaîne
      elif ptxt == ",":
        sep = if o.spaceAfterComma: " " else: sep
      elif txt == ",": sep = ""
      elif txt == ";": sep = " "                  # suite de ligne : « a + ; »
      elif ptxt in ["(", "["]: sep = ""
      elif txt in [")", "]"]: sep = ""
      elif i == 1 and p.kind == tkPicoOp and ptxt in ["?", "??"]:
        sep = " "
      elif binary[i] or binary[i - 1]:
        sep = " "
      elif o.spaceOps and ((t.kind == tkOperator and txt in SpacedOps) or
                           (p.kind == tkOperator and ptxt in SpacedOps)):
        # « - » unaire après un opérateur : pas touché (x = -1 reste x = -1)
        sep = " "
      res.add sep
    res.add txt
  res

proc isKeywordUse(sig: seq[Sig]): bool =
  sig.len > 0 and sig[0].kind == tkKeyword and
    not (sig.len > 1 and sig[1].text in ["=", ".", "[", "+=", "-=", ":"])

proc formatText*(text: string, o = defaultFormat()): FormatResult =
  let src = text.replace("\r\n", "\n")
  let lines = src.split('\n')
  let (toks, states) = lexAll(lines)
  var renames = newSeq[Table[int, string]](lines.len)
  for i in 0 ..< lines.len: renames[i] = initTable[int, string]()

  # casse des noms : procédures du fichier et variables
  if o.procCase in ["majuscules", "minuscules"] or o.varCase == "declaration":
    let fa = analyse(lines, toks)
    var procNames = initTable[string, bool]()
    for sc in fa.scopes:
      if sc.name.len > 0: procNames[sc.name] = true
    var declSpelling = initTable[string, string]()
    if o.varCase == "declaration":
      for oc in fa.occs:
        if oc.isDecl and oc.kind != okProcDef:
          let k = fa.symbolKey(oc)
          if k.len > 0 and k notin declSpelling: declSpelling[k] = oc.text
    for oc in fa.occs:
      var nt = ""
      if oc.kind in {okProcDef, okCall, okRef} and oc.name in procNames and not oc.local:
        case o.procCase
        of "majuscules": nt = upper(oc.text)
        of "minuscules": nt = oc.text.toLowerAscii
        else: discard
      elif o.varCase == "declaration" and oc.isVariableOcc:
        let k = fa.symbolKey(oc)
        if k in declSpelling: nt = declSpelling[k]
      if nt.len > 0 and nt != oc.text and oc.line < lines.len:
        let col = if oc.kind == okRef: oc.col - 1 else: oc.col
        renames[oc.line][col] = (if oc.kind == okRef: "@" & nt else: nt)

  proc pad(level: int): string =
    if level <= 0: "" elif o.tabs: repeat('\t', level) else: repeat(' ', level * o.indent)

  var outp: seq[string]
  var level = 0
  var stack: seq[Blk]
  var inProc = false
  var contDelta = 0                 # décalage appliqué aux lignes de suite (« ; »)
  var inCont = false
  var depth = 0                     # parenthèses ouvertes (l'instruction continue à la ligne)
  var blank = 0
  proc depthOf(sig: seq[Sig]): int =
    for x in sig:
      if x.text in ["(", "[", "{"]: inc result
      elif x.text in [")", "]", "}"]: dec result
  let body = if o.indentProcBody: 1 else: 0
  for i, line in lines:
    # ligne commençant dans une chaîne longue : inchangée
    if states[i].mode == lmLongString:
      outp.add line
      blank = 0
      continue
    var sig: seq[Sig]
    for t in toks[i]:
      if t.kind notin {tkSpace, tkComment, tkPod}:
        sig.add Sig(kind: t.kind, text: tokText(line, t), line: i, col: t.start)
    let opensLong = states[i + 1].mode == lmLongString
    var content = if opensLong: line.strip(trailing = false) else: rebuild(line, toks[i], o, renames[i])
    if opensLong and renames[i].len > 0:
      content = rebuild(line, toks[i], o, renames[i])
    if content.strip.len == 0:
      inc blank
      if blank <= o.maxBlank: outp.add ""
      continue
    blank = 0
    if inCont:
      # ligne de suite : même décalage que la première ligne de l'instruction
      let w = max(0, leadingWidth(line) + contDelta)
      outp.add (if o.tabs: pad(w div max(1, o.indent)) & repeat(' ', w mod max(1, o.indent)) else: repeat(' ', w)) & content
      depth = max(0, depth + depthOf(sig))
      inCont = (sig.len > 0 and sig[^1].text == ";") or depth > 0
      continue
    var lineLevel = level
    var after = level
    if sig.len == 0:
      # commentaire : niveau courant, sauf juste avant une procédure (colonne 0)
      var j = i + 1
      while j < lines.len:
        let s = lines[j].strip
        if s.len == 0 or s.startsWith("&&") or s.startsWith("//"):
          inc j
          continue
        let fw = s.split({' ', '(', '\t'})[0]
        if fw in ["procedure", "fonction", "finprocedure", "finfonction"] and leadingWidth(line) == 0:
          lineLevel = 0
        break
    elif sig[0].kind == tkKeyword and isKeywordUse(sig):
      let w = sig[0].text
      if w in ["procedure", "fonction"]:
        lineLevel = 0
        stack.setLen(0)
        inProc = true
        after = body
        if o.blankBeforeProc and outp.len > 0:
          # ligne vide avant la procédure (et avant ses commentaires)
          var k = outp.len
          while k > 0 and outp[k - 1].strip.len > 0 and
                (outp[k - 1].strip.startsWith("&&") or outp[k - 1].strip.startsWith("//")) and
                not outp[k - 1].startsWith(" "):
            dec k
          if k > 0 and outp[k - 1].strip.len > 0: outp.insert("", k)
      elif w in ["finprocedure", "finfonction"]:
        lineLevel = 0
        stack.setLen(0)
        inProc = false
        after = 0
      elif w in Openers or (w == "faire" and sig.len > 1 and sig[1].text == "tantque"):
        stack.add Blk(kind: (if w == "faire": "tantque" else: w), base: level)
        after = level + 1
      elif w == "faire" and sig.len > 1 and sig[1].text == "cas":
        stack.add Blk(kind: "cas", base: level)
        after = level + 1
      elif w in ["cas", "autrement"] and stack.len > 0 and stack[^1].kind == "cas":
        lineLevel = stack[^1].base + (if o.indentCases: 1 else: 0)
        after = lineLevel + 1
      elif w == "fincas" and stack.len > 0 and stack[^1].kind == "cas":
        lineLevel = stack.pop().base
        after = lineLevel
      elif w in ["sinon", "sinonsi"] and stack.len > 0 and stack[^1].kind == "si":
        lineLevel = stack[^1].base
        after = lineLevel + 1
      elif w == "capturer" and stack.len > 0 and stack[^1].kind == "essayer":
        lineLevel = stack[^1].base
        after = lineLevel + 1
      elif w in Closers and stack.len > 0:
        lineLevel = stack.pop().base
        after = lineLevel
      elif w in ["retourner", "retour"] and o.keepFinalReturn and inProc and stack.len == 0 and
           leadingWidth(line) == 0 and body > 0:
        # style « retourner » final en colonne 0 : gardé s'il termine la procédure
        var j = i + 1
        var last = true
        while j < lines.len:
          let s = lines[j].strip
          let prev = lines[j - 1].strip
          if s.len == 0 or s.startsWith("&&") or s.startsWith("//") or states[j].mode == lmLongString or
             prev.endsWith(";"):
            inc j
            continue
          let fw = s.split({' ', '(', '\t'})[0]
          last = fw in ["procedure", "fonction", "finprocedure", "finfonction"]
          break
        if last: lineLevel = 0
    outp.add pad(lineLevel) & content
    let nowW = (if o.tabs: lineLevel * 4 else: lineLevel * o.indent)
    contDelta = nowW - leadingWidth(line)
    depth = max(0, depthOf(sig))
    inCont = (sig.len > 0 and sig[^1].text == ";") or depth > 0
    level = after
  # lignes vides finales
  while outp.len > 0 and outp[^1].strip.len == 0: discard outp.pop()
  var res = outp.join("\n")
  if o.finalNewline: res.add "\n"
  # trailing spaces (hors chaînes longues : déjà gérées)
  var fixed: seq[string]
  let rl = res.split('\n')
  let (_, st2) = lexAll(rl)
  for k, l in rl:
    if st2[k + 1].mode == lmLongString or st2[k].mode == lmLongString: fixed.add l
    else: fixed.add l.strip(leading = false)
  res = fixed.join("\n")
  result = FormatResult(text: res, changed: res != src, safe: true)
  # garde-fou : la syntaxe doit rester correcte
  var origOk = true
  try: discard parseChunk(src, "formatage")
  except SyntaxError: origOk = false
  if origOk:
    try: discard parseChunk(res, "formatage")
    except SyntaxError as e:
      result = FormatResult(text: src, changed: false, safe: false,
                            message: "formatage annulé (le résultat ne serait plus correct) : " & e.msg)
