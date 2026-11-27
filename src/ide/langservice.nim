# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - service de langage Lexis+ (atelier et serveur LSP)
#
# Un espace de travail (dossier du projet) garde le texte et l'analyse de chaque
# fichier .prg ; les documents ouverts dans l'éditeur remplacent le disque.
# Fournit : infobulles, aller à la définition, usages (références), renommage,
# complétion, aide à la signature, symboles du document, diagnostics, formatage.
# Positions : lignes 0-based, colonnes en octets (le serveur LSP convertit en UTF-16).

import std/[strutils, tables, sets, os, algorithm]
import lexislang, langdocs, lexisanalyse, lexislint, formateur
from lsptypes import CompletionItem

type
  WsFile = object
    text: string
    fa: FileAnalysis
    opened: bool

  Workspace* = ref object
    root*: string
    files: Table[string, WsFile]

  RefLoc* = object
    file*: string
    line*, col*, len*: int
    kind*: OccKind
    decl*: bool

  HoverInfo* = object
    found*: bool
    markdown*: string
    line*, col*, len*: int

  SymbolInfo* = object
    name*, detail*: string
    kind*: string                # procedure, fonction, globale
    line*, col*, lastLine*: int

  SignatureInfo* = object
    found*: bool
    label*, doc*: string
    params*: seq[string]
    active*: int

proc norm*(p: string): string =
  if p.len == 0: "" else: absolutePath(p).normalizedPath

proc hiddenRel(rel: string): bool =
  for part in rel.split({'/', '\\'}):
    if part.startsWith("."): return true

proc newWorkspace*(root: string): Workspace =
  result = Workspace(root: (if root.len > 0: norm(root) else: ""), files: initTable[string, WsFile]())
  if result.root.len > 0 and dirExists(result.root):
    for f in walkDirRec(result.root, relative = true):
      if f.toLowerAscii.endsWith(".prg") and not hiddenRel(f):
        let full = result.root / f
        try:
          let t = readFile(full)
          result.files[norm(full)] = WsFile(text: t, fa: analyseText(t))
        except IOError, OSError: discard

proc setText*(ws: Workspace, path, text: string, opened = true) =
  ws.files[norm(path)] = WsFile(text: text, fa: analyseText(text), opened: opened)

proc closeFile*(ws: Workspace, path: string) =
  let p = norm(path)
  if p in ws.files:
    try:
      let t = readFile(p)
      ws.files[p] = WsFile(text: t, fa: analyseText(t))
    except IOError, OSError: ws.files.del p

proc removeFile*(ws: Workspace, path: string) = ws.files.del norm(path)

proc ensure(ws: Workspace, path: string): bool =
  let p = norm(path)
  if p in ws.files: return true
  try:
    let t = readFile(p)
    ws.files[p] = WsFile(text: t, fa: analyseText(t))
    true
  except IOError, OSError: false

proc textOf*(ws: Workspace, path: string): string =
  if ws.ensure(path): ws.files[norm(path)].text else: ""

proc paths*(ws: Workspace): seq[string] =
  for p in ws.files.keys: result.add p
  result.sort()

proc projectIndex*(ws: Workspace): ProjectIndex =
  result = initProjectIndex()
  for p, f in ws.files: result.indexFile(p, f.text)

#
# Symboles
#

proc defsOf(ws: Workspace, name: string): seq[RefLoc] =
  # Définitions d'un nom global : procédure, puis globale déclarée, puis 1re affectation.
  var procs, globs, assigns: seq[RefLoc]
  for p in ws.paths:
    let fa = ws.files[p].fa
    for o in fa.occs:
      if o.name != name: continue
      let r = RefLoc(file: p, line: o.line, col: o.col, len: o.text.len, kind: o.kind, decl: true)
      if o.kind == okProcDef: procs.add r
      elif o.kind == okGlobalDecl: globs.add r
      elif o.kind == okAssign and not o.local:
        if o.scope == 0: assigns.insert(r, 0) else: assigns.add r
  if procs.len > 0: return procs
  if globs.len > 0: return globs
  if assigns.len > 0: return @[assigns[0]]

proc keyAt(ws: Workspace, path: string, line, col: int): (string, int) =
  if not ws.ensure(path): return ("", -1)
  let fa = ws.files[norm(path)].fa
  var i = fa.occAt(line, col)
  if i < 0 and col > 0: i = fa.occAt(line, col - 1)
  if i < 0: return ("", -1)
  (fa.symbolKey(fa.occs[i]), i)

proc definition*(ws: Workspace, path: string, line, col: int): seq[RefLoc] =
  let (key, i) = ws.keyAt(path, line, col)
  if key.len == 0: return
  let p = norm(path)
  let fa = ws.files[p].fa
  if key[0] == 'L':
    let o = fa.occs[i]
    let d = fa.occs[fa.scopes[o.scope].locals[o.name]]
    return @[RefLoc(file: p, line: d.line, col: d.col, len: d.text.len, kind: d.kind, decl: true)]
  ws.defsOf(key[2 .. ^1])

proc references*(ws: Workspace, path: string, line, col: int, includeDecl = true): seq[RefLoc] =
  let (key, i) = ws.keyAt(path, line, col)
  if key.len == 0: return
  let p = norm(path)
  if key[0] == 'L':
    let fa = ws.files[p].fa
    for o in fa.occs:
      if fa.symbolKey(o) == key and (includeDecl or not o.isDecl):
        result.add RefLoc(file: p, line: o.line, col: o.col, len: o.text.len, kind: o.kind, decl: o.isDecl)
    return
  for fp in ws.paths:
    let fa = ws.files[fp].fa
    for o in fa.occs:
      if o.name == key[2 .. ^1] and fa.symbolKey(o) == key and (includeDecl or not o.isDecl):
        result.add RefLoc(file: fp, line: o.line, col: o.col, len: o.text.len, kind: o.kind, decl: o.isDecl)
  discard i

proc rename*(ws: Workspace, path: string, line, col: int, newName: string): (bool, string, seq[RefLoc]) =
  ## Toutes les occurrences à remplacer par newName (ok, message, emplacements).
  if newName.len == 0 or not (newName[0] in {'a'..'z', 'A'..'Z', '_'} or ord(newName[0]) >= 128):
    return (false, "nom invalide : « " & newName & " »", @[])
  for c in newName:
    if not isIdentChar(c): return (false, "nom invalide : « " & newName & " »", @[])
  if isKeyword(newName): return (false, "« " & newName & " » est un mot-clé", @[])
  let (key, i) = ws.keyAt(path, line, col)
  if key.len == 0: return (false, "aucun symbole renommable à cet endroit", @[])
  let name = key.split(':', 1)[1]
  if key[0] == 'G' and ws.defsOf(name).len == 0:
    return (false, "« " & name.toLowerAscii & " » n'est pas défini dans le projet (paquet ou fonction intégrée)", @[])
  discard i
  (true, "", ws.references(path, line, col, true))

proc documentSymbols*(ws: Workspace, path: string): seq[SymbolInfo] =
  if not ws.ensure(path): return
  let fa = ws.files[norm(path)].fa
  for sc in fa.scopes[1 .. ^1]:
    if sc.name.len > 0:
      result.add SymbolInfo(name: sc.display, detail: sc.doc.splitLines()[0], kind: sc.kind,
                            line: sc.line, col: sc.col, lastLine: sc.lastLine)
  for (n, l, c) in globalsOf(fa):
    var o: Occ
    for x in fa.occs:
      if x.name == n and x.line == l and x.col == c: o = x
    result.add SymbolInfo(name: o.text, detail: (if o.typ.len > 0: o.typ else: ""), kind: "globale",
                          line: l, col: c, lastLine: l)
  result.sort(proc (a, b: SymbolInfo): int = cmp(a.line, b.line))

proc workspaceSymbols*(ws: Workspace, query: string): seq[(string, SymbolInfo)] =
  let q = query.toLowerAscii
  for p in ws.paths:
    for s in ws.documentSymbols(p):
      if q.len == 0 or q in s.name.toLowerAscii: result.add (p, s)

#
# Infobulles
#

proc relName(ws: Workspace, p: string): string =
  if ws.root.len > 0 and p.startsWith(ws.root): relativePath(p, ws.root).replace('\\', '/') else: extractFilename(p)

proc procMarkdown(ws: Workspace, d: RefLoc): string =
  let fa = ws.files[d.file].fa
  for sc in fa.scopes:
    if sc.line == d.line and sc.name.len > 0:
      result = "```lexis\n" & sc.kind & " " & sc.display & "\n```\n"
      if sc.doc.len > 0: result.add "\n" & sc.doc & "\n"
      result.add "\n*" & ws.relName(d.file) & ":" & $(d.line + 1) & "*"
      return

proc apiMarkdown(docs: seq[ApiDoc]): string =
  var sigs: seq[string]
  for e in docs:
    if e.signature notin sigs: sigs.add e.signature
  if sigs.len > 4: sigs.setLen(4)
  "```lexis\n" & sigs.join("\n") & "\n```\n\n" & docs[0].doc & "\n\n*paquet " & docs[0].section & "*"

proc hover*(ws: Workspace, path: string, line, col: int): HoverInfo =
  if not ws.ensure(path): return
  let p = norm(path)
  let fa = ws.files[p].fa
  var i = fa.occAt(line, col)
  if i < 0 and col > 0: i = fa.occAt(line, col - 1)
  if i < 0: return
  let o = fa.occs[i]
  result = HoverInfo(found: true, line: o.line, col: o.col, len: o.text.len)
  case o.kind
  of okMember:
    var docs = apiLookup(o.name, o.isMethod, o.owner)
    if docs.len == 0 and o.owner.len > 0: docs = apiLookup(o.name, o.isMethod)
    if docs.len == 0 and not o.isMethod: docs = apiLookup(o.name, true)
    if docs.len > 0: result.markdown = apiMarkdown(docs)
    else: result.found = false
    return
  of okType:
    result.markdown = "type **" & o.text & "**" &
      (if isTypeName(o.name): " (type de base, contrôlé à l'exécution)" else: " (nom d'objet natif)")
    return
  else: discard
  let key = fa.symbolKey(o)
  if key.len > 0 and key[0] == 'L':
    let d = fa.occs[fa.scopes[o.scope].locals[o.name]]
    let sc = fa.scopes[o.scope]
    result.markdown = "```lexis\n(" & $d.kind & ") " & d.text & (if d.typ.len > 0: " : " & d.typ else: "") &
                      "\n```\n" & (if sc.name.len > 0: "dans " & sc.kind & " " & sc.display else: "programme principal") &
                      " - déclarée ligne " & $(d.line + 1)
    return
  let defs = ws.defsOf(o.name)
  if defs.len > 0 and defs[0].kind == okProcDef:
    result.markdown = ws.procMarkdown(defs[0])
    if defs.len > 1: result.markdown.add "\n\n⚠ définie " & $defs.len & " fois"
    return
  let bk = builtinKind(o.name)
  if bk == "paquet":
    var desc = ""
    for pk in packageNames():
      if pk == o.name.toLowerAscii: desc = pk
    var n = 0
    for e in membersOf(o.name): inc n
    result.markdown = "**paquet " & o.name.toLowerAscii & "** - " & $n & " fonctions (" & o.name.toLowerAscii & ".…)"
    if defs.len > 0: result.markdown.add "\n\n⚠ masqué par une variable globale du projet"
    return
  if bk.len > 0:
    let docs = apiLookup(o.name, false)
    if docs.len > 0:
      result.markdown = apiMarkdown(docs)
      return
  if defs.len > 0:
    let d = defs[0]
    var typ = ""
    for x in ws.files[d.file].fa.occs:
      if x.line == d.line and x.col == d.col: typ = x.typ
    result.markdown = "```lexis\n(variable globale) " & o.text & (if typ.len > 0: " : " & typ else: "") &
                      "\n```\n" & (if d.kind == okGlobalDecl: "déclarée" else: "affectée") & " " &
                      ws.relName(d.file) & ":" & $(d.line + 1)
    return
  if isKeyword(o.text):
    result.found = false
    return
  result.markdown = "« " & o.text & " » : nom inconnu (variable globale non affectée dans le projet ?)"

proc plainHover*(md: string): string =
  ## Infobulle sur une ligne (l'infobulle de l'interface n'affiche pas les sauts de ligne).
  var o: seq[string]
  for l in md.splitLines():
    if l.startsWith("```") or l.strip.len == 0: continue
    o.add l.replace("**", "").replace("*", "").strip
  result = o.join("  ·  ")
  if result.len > 240: result = result[0 ..< 237] & "…"

#
# Complétion et signature
#

proc identBefore(line: string, col: int): (string, int) =
  var a = min(col, line.len)
  while a > 0 and isIdentChar(line[a - 1]): dec a
  (line[a ..< min(col, line.len)], a)

proc completion*(ws: Workspace, path: string, line, col: int, lineText: string): seq[CompletionItem] =
  discard ws.ensure(path)
  let p = norm(path)
  let (prefix, start) = identBefore(lineText, col)
  let pu = upper(prefix)
  var seen = initHashSet[string]()
  template push(lbl, det, ins, doc: string, k: int) =
    if upper(lbl).startsWith(pu) and upper(lbl) notin seen:
      seen.incl upper(lbl)
      result.add CompletionItem(label: lbl, detail: det, insertText: ins, documentation: doc, kind: k)
  let before = if start > 0: lineText[start - 1] else: ' '
  if before in {'.', ':'}:
    let (owner, _) = identBefore(lineText, start - 1)
    if before == '.' and owner.len > 0:
      for e in membersOf(owner): push(e.name, e.signature, e.name, e.doc, 3)
      if result.len > 0: return
    if before == ':':
      for e in methodEntries(): push(e.name, e.signature, e.name, e.doc, 2)
      return
    for k in UiProps: push(k, "propriété", k, "", 10)
    return
  # après « : » dans une déclaration : types
  let head = lineText[0 ..< start].strip
  if head.endsWith(":") and (head.startsWith("locale") or head.startsWith("globale") or head.startsWith("local") or
                             head.startsWith("procedure") or head.startsWith("fonction")):
    for t in ["nombre", "entier", "decimal", "chaine", "logique", "table", "liste", "procedure", "objet", "tache", "quelconque"]:
      push(t, "type", t, "", 7)
    return
  # locales visibles
  if p in ws.files:
    let fa = ws.files[p].fa
    let sc = fa.scopeAt(line)
    for n, idx in fa.scopes[sc].locals:
      let d = fa.occs[idx]
      if d.line <= line: push(d.text, $d.kind & (if d.typ.len > 0: " : " & d.typ else: ""), d.text, "", 6)
  # procédures du projet
  for fp in ws.paths:
    let fa = ws.files[fp].fa
    for sc in fa.scopes[1 .. ^1]:
      if sc.name.len > 0:
        let nm = sc.display.split('(')[0]
        push(nm, sc.kind & " " & sc.display, nm & "(", sc.doc, 3)
  # globales du projet
  for fp in ws.paths:
    for (n, l, c) in globalsOf(ws.files[fp].fa):
      var txt = n.toLowerAscii
      for o in ws.files[fp].fa.occs:
        if o.line == l and o.col == c: txt = o.text
      push(txt, "variable globale", txt, "", 6)
  for k in Keywords: push(k, "mot-clé", k, "", 14)
  for pk in packageNames(): push(pk, "paquet", pk, "", 9)
  for e in apiEntries():
    if e.owner.len == 0 and not e.isMethod: push(e.name, e.signature, e.name & "(", e.doc, 3)

proc signatureHelp*(ws: Workspace, path: string, line, col: int, lineText: string): SignatureInfo =
  # Appel ouvert avant le curseur : NOM( a, b|
  var depth = 0
  var commas = 0
  var i = min(col, lineText.len) - 1
  var inStr = false
  while i >= 0:
    let c = lineText[i]
    if c == '"': inStr = not inStr
    elif not inStr:
      if c in {')', ']', '}'}: inc depth
      elif c in {'(', '['}:
        if depth == 0:
          if c == '[': return
          break
        dec depth
      elif c == ',' and depth == 0: inc commas
    dec i
  if i < 0: return
  let (name, s) = identBefore(lineText, i)
  if name.len == 0: return
  var owner = ""
  var isMethod = false
  if s > 0 and lineText[s - 1] in {'.', ':'}:
    isMethod = lineText[s - 1] == ':'
    owner = identBefore(lineText, s - 1)[0]
  if owner.len == 0 and not isMethod:
    let defs = ws.defsOf(upper(name))
    if defs.len > 0 and defs[0].kind == okProcDef:
      for sc in ws.files[defs[0].file].fa.scopes:
        if sc.line == defs[0].line and sc.name == upper(name):
          var ps: seq[string]
          for k, pn in sc.params:
            ps.add(if k < sc.paramTypes.len and sc.paramTypes[k].len > 0: pn & " : " & sc.paramTypes[k] else: pn)
          return SignatureInfo(found: true, label: sc.display, doc: sc.doc, params: ps, active: commas)
  var docs = apiLookup(name, isMethod, owner)
  if docs.len == 0: docs = apiLookup(name, isMethod)
  if docs.len == 0: return
  let sg = docs[0].signature
  var ps: seq[string]
  let a = sg.find('(')
  let b = sg.rfind(')')
  if a >= 0 and b > a:
    for x in sg[a + 1 ..< b].split(','):
      if x.strip.len > 0: ps.add x.strip
  SignatureInfo(found: true, label: sg, doc: docs[0].doc, params: ps, active: commas)

#
# Diagnostics et formatage
#

proc diagnostics*(ws: Workspace, path: string, opts = LintOptions(flagGlobals: true, unknownCalls: true)):
    seq[lexislint.Diagnostic] =
  if not ws.ensure(path): return
  let p = norm(path)
  let text = ws.files[p].text
  let lines = text.replace("\r\n", "\n").split('\n')
  let (toks, _) = lexAll(lines)
  let (_, local) = collectSymbols(lines, toks)
  let idx = ws.projectIndex()
  lint(lines, toks, idx.knownNamesFor(local), opts, p, idx)

proc format*(ws: Workspace, path: string): FormatResult =
  let dir = if ws.root.len > 0: ws.root else: path.parentDir
  formatText(ws.textOf(path), loadFormatOptions(dir))
