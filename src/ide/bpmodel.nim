# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - modèle des vues « blueprint » : code Lexis+ <-> graphe de nœuds.
#
# Le code d'un fichier .prg devient un graphe à la manière des blueprints
# d'Unreal :
#   * un nœud d'entrée par procédure / fonction, plus le programme principal ;
#   * les instructions sont des nœuds « exécutables » reliés par des liens
#     d'exécution (blancs) : chaque nœud a une entrée et une sortie « suite » ;
#     les blocs (si, pour, tantque, faire cas, essayer, parcourir) ont en plus
#     une sortie par corps (alors, sinon, corps, cas 1...) ;
#   * les expressions sont des nœuds « purs » (appels, opérateurs, variables,
#     membres) reliés par des liens de données ; une valeur littérale est saisie
#     directement sur la broche (valeur par défaut).
#
# Fidélité : l'analyse conserve, pour chaque instruction, ses lignes d'origine
# (commentaires de fin de ligne, continuations, indentation relative), les
# lignes vides et les commentaires (nœuds « Commentaire »). À la génération, une
# instruction dont ni le nœud ni ses entrées n'ont été modifiés est réécrite à
# l'identique : seul ce que l'utilisateur a changé dans le graphe change dans le
# code. Une instruction que le modèle ne décompose pas reste un nœud « Code
# Lexis+ » éditable, réécrit tel quel.
#
# Le module ne dépend d'aucune interface : la vue (blueprint.nim) fournit la
# mesure du texte, l'atelier la recherche des signatures (bpSignatureOf).

import std/[strutils, tables, sets]

#
# types publics
#

type
  PinDir* = enum pdIn, pdOut
  PinKind* = enum pkExec, pkData

  Pin* = object
    pid*: int              # identifiant stable dans le nœud (les liens s'y réfèrent).
    name*: string          # libellé ("" : entrée d'exécution ; "next" : sortie « suite »).
    dir*: PinDir
    kind*: PinKind
    default*: string       # entrée de données non reliée : expression Lexis+ saisie.
    optional*: bool
    varOut*: bool          # sortie qui fournit un nom de variable (pour, paramètre...).
    varName*: string
    origName*: string      # nom lu dans le code (réécriture inutile tant qu'il est inchangé).

  NodeKind* = enum
    nkEntry = "entrée", nkComment = "commentaire", nkRaw = "code", nkPrint = "afficher",
    nkAssign = "affecter", nkLocal = "locale", nkIf = "si", nkCase = "faire cas",
    nkWhile = "tantque", nkFor = "pour", nkForEach = "pour chaque", nkScan = "parcourir",
    nkTry = "essayer", nkReturn = "retourner", nkBreak = "sortir", nkContinue = "boucler",
    nkCall = "appel", nkMethod = "méthode", nkVar = "variable", nkOp = "opérateur",
    nkUnary = "unaire", nkIndex = "index", nkMember = "membre", nkExpr = "expression"

  RawLine* = tuple[blank, ind: int, text: string]
    # ligne d'origine : lignes vides avant, indentation (relative), texte sans indentation.

  Node* = ref object
    id*: int
    kind*: NodeKind
    x*, y*, w*, h*: float
    title*: string         # entrée : nom ; appel : fonction ; méthode, membre : nom ; variable ; opérateur.
    text*: string          # entrée : paramètres ; commentaire, code, expression : texte ;
                           # affecter : cible ; locale : nom ; pour : variable ; pour chaque : noms ; essayer : variable.
    mode*: string          # entrée : procedure/fonction/principal ; afficher : ?/?? ; affecter : =/+=/-= ;
                           # locale : locale/globale ; tantque : tantque/faire tantque ; pour : a/jusqua ;
                           # retourner : retourner/retour.
    pins*: seq[Pin]
    nextPid*: int
    stmt*: bool            # appel / méthode utilisé comme instruction (broches d'exécution).
    brace*: bool           # appel écrit f{...}
    elseIf*: bool          # si écrit « sinonsi » dans la branche sinon de son parent.
    dirty*: bool           # modifié depuis l'analyse : régénéré.
    orig*: seq[RawLine]    # lignes d'origine (instruction, ou en-tête de bloc).
    mids*: Table[string, seq[RawLine]]   # lignes intermédiaires d'un bloc (sinon, cas1, autrement, capturer).
    headComments*: seq[RawLine]     # faire cas : commentaires entre l'en-tête et le premier cas.
    endLine*: RawLine
    hasEnd*: bool
    rel*: int              # indentation d'origine relative au bloc englobant (-1 : inconnue).
    blank*: int            # lignes vides avant l'instruction.
    trailing*: string      # commentaire de fin de ligne (repris si l'instruction est régénérée).
    preamble*: seq[string] # entrée : lignes (commentaires, vides) avant l'en-tête, telles quelles.
    line*: int             # ligne source (0-based), -1 pour un nœud créé dans le graphe.
    key*: string           # clé stable (conservation des positions après une nouvelle analyse).
    folded*: bool          # entrée : contenu plié (masqué dans la vue).

  Link* = object
    a*, ap*: int           # nœud et broche de sortie
    b*, bp*: int           # nœud et broche d'entrée

  Graph* = ref object
    nodes*: seq[Node]
    links*: seq[Link]
    byId*: Table[int, Node]
    nextId*: int
    mainId*: int
    entries*: seq[int]     # ordre des entrées (programme principal d'abord).
    error*: string         # erreur de structure : graphe vide et non modifiable.
    errorLine*: int
    epilogue*: seq[string] # commentaires de fin de fichier (après la dernière procédure), tels quels.
    tail*: seq[string]     # lignes vides terminant le fichier.
    stamp*: int            # incrémenté à chaque modification des liens (index ci-dessous).
    idxStamp, idxLen: int
    inMap, outMap: Table[int64, int]
    lostStamp, lostCount: int
    ownKey: int
    ownMap: Table[int, int]

  TextMeasure* = proc (s: string): float {.closure, gcsafe.}

var bpSignatureOf*: proc (name: string, isMethod: bool): string {.nimcall, gcsafe.}
  # Signature documentée d'une fonction (« f(a, [b]) »), "" si inconnue (posé par l'atelier).

#
# géométrie (unités du monde, zoom 1) : partagée par la mise en page et la vue
#

const
  HeadH* = 26.0
  SubH* = 16.0
  RowH* = 22.0
  BodyLineH* = 17.0
  MaxBodyLines* = 10
  GapX = 70.0
  GapY = 46.0
  GapData = 36.0
  WrapW = 2600.0

proc isCompact*(n: Node): bool = n.kind in {nkVar, nkOp, nkUnary, nkExpr, nkIndex, nkMember}

proc isExecNode*(n: Node): bool =
  case n.kind
  of nkEntry: false
  of nkCall, nkMethod: n.stmt
  of nkVar, nkOp, nkUnary, nkIndex, nkMember, nkExpr: false
  else: true

proc isBlock*(n: Node): bool = n.kind in {nkIf, nkCase, nkWhile, nkFor, nkForEach, nkScan, nkTry}

proc headerTitle*(n: Node): string =
  case n.kind
  of nkEntry:
    if n.mode == "principal": "Programme principal"
    elif n.mode == "suite": "Programme principal (suite)"
    else: n.mode & " " & n.title
  of nkComment: "Commentaire"
  of nkRaw: "Code Lexis+"
  of nkPrint: (if n.mode == "??": "Afficher ??" else: "Afficher ?")
  of nkAssign: "Affecter"
  of nkLocal: (if n.mode == "globale": "Globale" else: "Locale")
  of nkIf: (if n.elseIf: "Sinon si" else: "Si")
  of nkCase: "Faire cas"
  of nkWhile: "Tant que"
  of nkFor: "Pour"
  of nkForEach: "Pour chaque"
  of nkScan: "Parcourir"
  of nkTry: "Essayer"
  of nkReturn: "Retourner"
  of nkBreak: "Sortir"
  of nkContinue: "Boucler"
  of nkCall: n.title
  of nkMethod: ":" & n.title
  of nkVar: n.title
  of nkOp, nkUnary: n.title
  of nkIndex: "[ ]"
  of nkMember: "." & n.title
  of nkExpr:
    let ls = n.text.splitLines()
    if ls.len > 0: ls[0] else: ""

proc headerSub*(n: Node): string =
  case n.kind
  of nkEntry: (if n.mode in ["principal", "suite"]: "" else: "(" & n.text & ")")
  of nkAssign: n.text & " " & n.mode
  of nkLocal: n.text
  of nkFor: n.text
  of nkForEach: n.text
  of nkTry: (if n.text.len > 0: "capturer " & n.text else: "")
  of nkCall, nkMethod: (if n.stmt: "instruction" else: "")
  else: ""

proc bodyLines*(n: Node): seq[string] =
  if n.kind in {nkComment, nkRaw}:
    result = n.text.splitLines()
    if result.len > MaxBodyLines:
      result.setLen(MaxBodyLines)
      result[^1] = result[^1] & "  …"

proc headH*(n: Node): float =
  if n.isCompact: 2.0
  elif n.headerSub.len > 0: HeadH + SubH
  else: HeadH

proc pinLabel*(n: Node, p: Pin): string =
  if p.kind == pkExec:
    if p.name == "next": (if n.isBlock: "suite" else: "")
    else: p.name
  elif p.varOut: p.varName
  else: p.name

proc inputs*(n: Node): seq[int] =
  for i, p in n.pins:
    if p.dir == pdIn: result.add i

proc outputs*(n: Node): seq[int] =
  for i, p in n.pins:
    if p.dir == pdOut: result.add i

proc rowOf*(n: Node, idx: int): int =
  # Rang (0-based) de la broche dans sa colonne.
  var k = 0
  for i, p in n.pins:
    if p.dir == n.pins[idx].dir:
      if i == idx: return k
      inc k

proc pinPos*(n: Node, idx: int): tuple[x, y: float] =
  let row = n.rowOf(idx)
  let y = n.y + n.headH + float(row) * RowH + RowH / 2
  if n.pins[idx].dir == pdIn: (n.x, y) else: (n.x + n.w, y)

proc firstLine*(s: string): string =
  let ls = s.splitLines()
  if ls.len > 0: ls[0] else: ""

proc boxWidth*(tw: TextMeasure, s: string): float =
  clamp(tw(s.firstLine) + 14, 34.0, 170.0)

proc pinKey(nid, pid: int): int64 {.inline.} = (int64(nid) shl 24) or int64(pid)

proc touch*(g: Graph) {.inline.} = inc g.stamp

proc ensureIndex(g: Graph) =
  if g.idxStamp == g.stamp and g.idxLen == g.links.len and g.inMap.len + g.outMap.len > 0: return
  g.inMap = initTable[int64, int](g.links.len * 2)
  g.outMap = initTable[int64, int](g.links.len * 2)
  for i, l in g.links:
    g.inMap[pinKey(l.b, l.bp)] = i
    let k = pinKey(l.a, l.ap)
    if k notin g.outMap: g.outMap[k] = i
  g.idxStamp = g.stamp
  g.idxLen = g.links.len

proc isLinkedIn*(g: Graph, n: Node, pid: int): bool =
  g.ensureIndex()
  pinKey(n.id, pid) in g.inMap

proc measure*(g: Graph, n: Node, tw: TextMeasure) =
  # Calcule n.w et n.h (zoom 1).
  let ins = n.inputs
  let outs = n.outputs
  let rows = max(ins.len, outs.len)
  var leftW, rightW: seq[float]
  for i in ins:
    let p = n.pins[i]
    var w = 16.0 + tw(n.pinLabel(p))
    if p.kind == pkData and not g.isLinkedIn(n, p.pid):
      w += 8 + boxWidth(tw, p.default)
    leftW.add w
  for i in outs: rightW.add tw(n.pinLabel(n.pins[i])) + 18
  if n.isCompact:
    let symbol = case n.kind
      of nkOp, nkUnary: max(34.0, tw(n.title) + 18)
      of nkIndex: 30.0
      else: tw(n.headerTitle) + 20
    var lw = 0.0
    for w in leftW: lw = max(lw, w)
    n.w = clamp(lw + symbol + 22, 56.0, 300.0)
    n.h = float(max(1, rows)) * RowH + 4
    return
  var w = max(tw(n.headerTitle) + 36, tw(n.headerSub) + 24)
  if n.kind == nkEntry: w = max(w, tw(n.headerTitle) + 82)        # icônes plier et fichier
  elif n.kind in {nkCall, nkMethod, nkAssign, nkPrint, nkLocal, nkReturn}:
    w = max(w, tw(n.headerTitle) + 58)                               # icône fichier (appel, @PROC)
  for r in 0 ..< rows:
    let l = if r < leftW.len: leftW[r] else: 0.0
    let rr = if r < rightW.len: rightW[r] else: 0.0
    w = max(w, l + rr + 26)
  let body = n.bodyLines
  for b in body: w = max(w, tw(b) + 26)
  n.w = clamp(w, 130.0, 560.0)
  n.h = n.headH + float(rows) * RowH + 6 + (if body.len > 0: float(body.len) * BodyLineH + 6 else: 0.0)

#
# graphe : construction et édition
#

proc node*(g: Graph, id: int): Node = g.byId.getOrDefault(id)

proc newGraph*(): Graph =
  Graph(byId: initTable[int, Node](), nextId: 1, mainId: -1)

proc addPin*(n: Node, name: string, dir: PinDir, kind: PinKind, default = "", optional = false): int {.discardable.} =
  inc n.nextPid
  n.pins.add Pin(pid: n.nextPid, name: name, dir: dir, kind: kind, default: default, optional: optional)
  n.nextPid

proc pinIndex*(n: Node, pid: int): int =
  for i, p in n.pins:
    if p.pid == pid: return i
  -1

proc findPin*(n: Node, dir: PinDir, kind: PinKind, name: string): int =
  # pid de la broche, -1 si absente.
  for p in n.pins:
    if p.dir == dir and p.kind == kind and p.name == name: return p.pid
  -1

proc execIn*(n: Node): int = n.findPin(pdIn, pkExec, "")
proc execNext*(n: Node): int = n.findPin(pdOut, pkExec, "next")
proc dataOut*(n: Node): int =
  for p in n.pins:
    if p.dir == pdOut and p.kind == pkData and not p.varOut: return p.pid
  -1

proc dataInputs*(n: Node): seq[int] =
  for p in n.pins:
    if p.dir == pdIn and p.kind == pkData: result.add p.pid

proc newNode*(g: Graph, kind: NodeKind): Node =
  result = Node(id: g.nextId, kind: kind, rel: -1, line: -1, mids: initTable[string, seq[RawLine]]())
  inc g.nextId
  g.nodes.add result
  g.byId[result.id] = result

proc linkInto*(g: Graph, nid, pid: int): int =
  g.ensureIndex()
  g.inMap.getOrDefault(pinKey(nid, pid), -1)

proc linkFrom*(g: Graph, nid, pid: int): int =
  g.ensureIndex()
  g.outMap.getOrDefault(pinKey(nid, pid), -1)

proc followExec*(g: Graph, nid, pid: int): Node =
  let i = g.linkFrom(nid, pid)
  if i >= 0: g.node(g.links[i].b) else: nil

proc canLink*(g: Graph, a, ap, b, bp: int): bool =
  let na = g.node(a)
  let nb = g.node(b)
  if na == nil or nb == nil or a == b: return false
  let ia = na.pinIndex(ap)
  let ib = nb.pinIndex(bp)
  if ia < 0 or ib < 0: return false
  let pa = na.pins[ia]
  let pb = nb.pins[ib]
  pa.dir == pdOut and pb.dir == pdIn and pa.kind == pb.kind

proc removeLinkAt(g: Graph, i: int) =
  let l = g.links[i]
  let nb = g.node(l.b)
  if nb != nil:
    let ib = nb.pinIndex(l.bp)
    if ib >= 0 and nb.pins[ib].kind == pkData: nb.dirty = true
  g.links.delete(i)
  g.touch()

proc connect*(g: Graph, a, ap, b, bp: int): bool {.discardable.} =
  # Relie une sortie à une entrée (remplace les liens incompatibles).
  if not g.canLink(a, ap, b, bp): return false
  let na = g.node(a)
  let kind = na.pins[na.pinIndex(ap)].kind
  var i = g.links.high
  while i >= 0:
    let l = g.links[i]
    if (l.b == b and l.bp == bp) or (kind == pkExec and l.a == a and l.ap == ap):
      g.removeLinkAt(i)
    dec i
  g.links.add Link(a: a, ap: ap, b: b, bp: bp)
  g.touch()
  if kind == pkData: g.node(b).dirty = true
  true

proc disconnectPin*(g: Graph, nid, pid: int) =
  var i = g.links.high
  while i >= 0:
    let l = g.links[i]
    if (l.a == nid and l.ap == pid) or (l.b == nid and l.bp == pid): g.removeLinkAt(i)
    dec i

proc removePin*(g: Graph, n: Node, pid: int) =
  g.disconnectPin(n.id, pid)
  let i = n.pinIndex(pid)
  if i >= 0: n.pins.delete(i)
  n.dirty = true

proc removeNode*(g: Graph, id: int, heal = true) =
  # Supprime un nœud ; une instruction retirée d'une chaîne la referme.
  let n = g.node(id)
  if n == nil or id == g.mainId: return
  if heal and n.isExecNode:
    let ii = g.linkInto(id, n.execIn)
    let io = g.linkFrom(id, n.execNext)
    if ii >= 0 and io >= 0:
      let a = g.links[ii]
      let b = g.links[io]
      g.links.add Link(a: a.a, ap: a.ap, b: b.b, bp: b.bp)
      g.touch()
  var i = g.links.high
  while i >= 0:
    if g.links[i].a == id or g.links[i].b == id: g.removeLinkAt(i)
    dec i
  g.byId.del(id)
  for k in 0 .. g.nodes.high:
    if g.nodes[k].id == id:
      g.nodes.delete(k)
      break
  let e = g.entries.find(id)
  if e >= 0: g.entries.delete(e)
  g.touch()

proc owners*(g: Graph): Table[int, int] =
  # Entrée « propriétaire » de chaque nœud : atteint depuis elle par l'exécution, ou
  # source de données d'un nœud qu'elle possède. Les nœuds non reliés n'y figurent pas.
  let key = g.stamp * 7919 + g.nodes.len
  if g.ownKey == key and g.ownMap.len > 0: return g.ownMap
  var own = initTable[int, int]()
  for eid in g.entries:
    var stack = @[eid]
    while stack.len > 0:
      let nid = stack.pop()
      if nid in own: continue
      let n = g.node(nid)
      if n == nil: continue
      own[nid] = eid
      for p in n.pins:
        if p.dir == pdOut and p.kind == pkExec:
          let t = g.followExec(nid, p.pid)
          if t != nil: stack.add t.id
        elif p.dir == pdIn and p.kind == pkData:
          let li = g.linkInto(nid, p.pid)
          if li >= 0:
            let src = g.node(g.links[li].a)
            if src != nil and not src.isExecNode and src.kind != nkEntry: stack.add src.id
  g.ownMap = own
  g.ownKey = key
  own

proc ownerOf*(g: Graph, id: int): int = g.owners().getOrDefault(id, -1)

proc reachableFrom*(g: Graph, id: int): seq[int] =
  # L'entrée `id` et tout ce qu'elle possède.
  for k, v in g.owners():
    if v == id: result.add k

proc isHidden*(g: Graph, n: Node): bool =
  # Nœud masqué : il appartient à une entrée pliée.
  if n.kind == nkEntry: return false
  let o = g.node(g.ownerOf(n.id))
  o != nil and o.folded

proc atRefs(s: string, acc: var seq[string]) =
  var i = 0
  while i < s.len:
    if s[i] == '@' and i + 1 < s.len and (s[i + 1] in {'a'..'z', 'A'..'Z', '_'} or ord(s[i + 1]) >= 128):
      var j = i + 1
      while j < s.len and (s[j] in {'a'..'z', 'A'..'Z', '_', '0'..'9'} or ord(s[j]) >= 128): inc j
      acc.add s[i + 1 ..< j].toUpperAscii
      i = j
    else: inc i

proc callNames*(n: Node): seq[string] =
  # Procédures appelées ou référencées (@NOM) par ce nœud (noms en majuscules).
  if n.kind == nkCall and '.' notin n.title and n.title.len > 0: result.add n.title.toUpperAscii
  for p in n.pins:
    if p.dir == pdIn and p.kind == pkData and '@' in p.default: atRefs(p.default, result)
  if n.kind == nkExpr and '@' in n.text: atRefs(n.text, result)

proc clone*(g: Graph): Graph =
  # Copie profonde (annulation).
  result = Graph(links: g.links, nextId: g.nextId, mainId: g.mainId, entries: g.entries,
                 error: g.error, errorLine: g.errorLine, tail: g.tail, epilogue: g.epilogue,
                 byId: initTable[int, Node](), stamp: g.stamp + 1)
  for n in g.nodes:
    let c = Node()
    c[] = n[]
    result.nodes.add c
    result.byId[c.id] = c

#
# signatures -> broches
#

type ParamInfo* = tuple[name: string, optional, variadic: bool]

proc splitTopLevel(s: string): seq[string] =
  var depth = 0
  var cur = ""
  var q = '\0'
  for c in s:
    if q != '\0':
      cur.add c
      if c == q: q = '\0'
      continue
    case c
    of '"', '\'':
      q = c
      cur.add c
    of '(', '{', '[':
      inc depth
      cur.add c
    of ')', '}', ']':
      dec depth
      cur.add c
    of ',':
      if depth <= 0:
        result.add cur
        cur = ""
      else: cur.add c
    else: cur.add c
  if cur.strip.len > 0: result.add cur

proc sigParams*(sig: string): seq[ParamInfo] =
  # « f(a, [b], {c=1}, ...) » -> paramètres (nom, facultatif, variable).
  let p = sig.find({'(', '{'})
  if p < 0: return
  if sig[p] == '{': return @[(name: "options", optional: true, variadic: false)]
  var depth = 0
  var q = -1
  for k in p ..< sig.len:
    if sig[k] == '(': inc depth
    elif sig[k] == ')':
      dec depth
      if depth == 0:
        q = k
        break
  if q < 0: q = sig.len
  let inner = sig[p + 1 ..< q]
  var parts: seq[(string, bool)]
  var cur = ""
  var curOpt = false
  var b = 0
  depth = 0
  for c in inner:
    case c
    of '[':
      inc b
      if cur.strip.len == 0: curOpt = true
    of ']': dec b
    of '(', '{':
      inc depth
      cur.add c
    of ')', '}':
      dec depth
      cur.add c
    of ',':
      if depth == 0:
        parts.add (cur, curOpt)
        cur = ""
        curOpt = b > 0
      else: cur.add c
    else: cur.add c
  parts.add (cur, curOpt)
  for (raw, opt0) in parts:
    var a = raw.strip
    var opt = opt0
    if a.len == 0: continue
    if a.startsWith("..."):
      result.add (name: "...", optional: true, variadic: true)
      continue
    if a.startsWith("{"):
      result.add (name: "options", optional: true, variadic: false)
      continue
    if a.endsWith("..."):
      result.add (name: a[0 ..< a.len - 3].strip, optional: true, variadic: true)
      continue
    let bar = a.find('|')
    if bar > 0: a = a[0 ..< bar].strip
    let eq = a.find('=')
    if eq > 0:
      a = a[0 ..< eq].strip
      opt = true
    if a.startsWith("@"): a = a[1 .. ^1]
    if a.len == 0: continue
    result.add (name: a, optional: opt, variadic: false)

proc signatureFor(name: string, isMethod: bool): string =
  if bpSignatureOf == nil: return ""
  {.cast(gcsafe).}:
    result = bpSignatureOf(name, isMethod)

#
# fabrique de nœuds (aussi utilisée par la palette)
#

proc addExec(n: Node, outs: openArray[string]) =
  n.addPin("", pdIn, pkExec)
  for o in outs: n.addPin(o, pdOut, pkExec)

proc setStatement*(g: Graph, n: Node, on: bool) =
  # Appel ou méthode : instruction (broches d'exécution) ou expression (résultat).
  if n.kind notin {nkCall, nkMethod} or n.stmt == on: return
  n.stmt = on
  n.dirty = true
  if on:
    let r = n.dataOut
    if r >= 0: g.removePin(n, r)
    inc n.nextPid
    n.pins.insert(Pin(pid: n.nextPid, name: "", dir: pdIn, kind: pkExec), 0)
    inc n.nextPid
    n.pins.insert(Pin(pid: n.nextPid, name: "next", dir: pdOut, kind: pkExec), 1)
  else:
    let a = n.execIn
    let b = n.execNext
    if a >= 0: g.removePin(n, a)
    if b >= 0: g.removePin(n, b)
    n.addPin("résultat", pdOut, pkData)

proc callPins(n: Node, params: seq[ParamInfo], argCount: int) =
  var k = 0
  for p in params:
    if p.variadic:
      let base = if p.name == "...": "valeur" else: p.name
      let count = max(1, argCount - k)
      for j in 0 ..< count:
        n.addPin(base & " " & $(j + 1), pdIn, pkData, optional = true)
        inc k
      continue
    n.addPin(p.name, pdIn, pkData, optional = p.optional)
    inc k
  while k < argCount:
    n.addPin("arg " & $(k + 1), pdIn, pkData)
    inc k

proc setEntryParams*(g: Graph, n: Node, params: string) =
  # Paramètres d'une entrée : une sortie de données par paramètre (liens gardés par nom).
  var names: seq[string]
  for p in params.split(','):
    let s = p.strip
    if s.len > 0: names.add s
  var gone: seq[int]
  for p in n.pins:
    if p.varOut:
      var found = false
      for s in names:
        if cmpIgnoreCase(s, p.varName) == 0: found = true
      if not found: gone.add p.pid
  for pid in gone: g.removePin(n, pid)
  for s in names:
    var found = false
    for p in n.pins:
      if p.varOut and cmpIgnoreCase(p.varName, s) == 0: found = true
    if not found:
      let pid = n.addPin(s, pdOut, pkData)
      n.pins[n.pinIndex(pid)].varOut = true
      n.pins[n.pinIndex(pid)].varName = s
  n.text = names.join(", ")

proc setVarOuts*(g: Graph, n: Node, names: seq[string]) =
  # Sorties « nom de variable » d'un bloc (pour, pour chaque, capturer).
  var olds: seq[int]
  for p in n.pins:
    if p.varOut: olds.add p.pid
  for i, s in names:
    if i < olds.len:
      let k = n.pinIndex(olds[i])
      n.pins[k].varName = s
      n.pins[k].name = s
    else:
      let pid = n.addPin(s, pdOut, pkData)
      n.pins[n.pinIndex(pid)].varOut = true
      n.pins[n.pinIndex(pid)].varName = s
  for i in names.len ..< olds.len: g.removePin(n, olds[i])

proc splitNames*(s: string): seq[string] =
  for p in s.split(','):
    if p.strip.len > 0: result.add p.strip

proc makeNode*(g: Graph, kind: NodeKind, title = "", text = "", mode = "", argCount = -1,
               stmt = false): Node =
  # Crée un nœud prêt à l'emploi (palette) ; argCount < 0 : d'après la signature.
  let n = g.newNode(kind)
  n.title = title
  n.text = text
  n.mode = mode
  n.dirty = true
  case kind
  of nkEntry:
    if n.mode.len == 0: n.mode = "procedure"
    n.addPin("next", pdOut, pkExec)
    g.setEntryParams(n, text)
  of nkComment, nkRaw, nkBreak, nkContinue: n.addExec(["next"])
  of nkPrint:
    if n.mode.len == 0: n.mode = "?"
    n.addExec(["next"])
    for i in 1 .. max(1, argCount): n.addPin("valeur " & $i, pdIn, pkData)
  of nkAssign:
    if n.mode.len == 0: n.mode = "="
    n.addExec(["next"])
    n.addPin("valeur", pdIn, pkData)
  of nkLocal:
    if n.mode.len == 0: n.mode = "locale"
    n.addExec(["next"])
    n.addPin("valeur", pdIn, pkData, optional = true)
  of nkIf:
    n.addPin("", pdIn, pkExec)
    n.addPin("condition", pdIn, pkData)
    for o in ["alors", "sinon", "next"]: n.addPin(o, pdOut, pkExec)
  of nkCase:
    n.addPin("", pdIn, pkExec)
    let c = max(1, argCount)
    for i in 1 .. c: n.addPin("cas " & $i, pdIn, pkData)
    for i in 1 .. c: n.addPin("cas " & $i, pdOut, pkExec)
    for o in ["autrement", "next"]: n.addPin(o, pdOut, pkExec)
  of nkWhile:
    if n.mode.len == 0: n.mode = "tantque"
    n.addPin("", pdIn, pkExec)
    n.addPin("condition", pdIn, pkData)
    for o in ["corps", "next"]: n.addPin(o, pdOut, pkExec)
  of nkFor:
    if n.text.len == 0: n.text = "i"
    n.addPin("", pdIn, pkExec)
    n.addPin("début", pdIn, pkData, "1")
    n.addPin("fin", pdIn, pkData, "10")
    n.addPin("pas", pdIn, pkData, optional = true)
    for o in ["corps", "next"]: n.addPin(o, pdOut, pkExec)
    g.setVarOuts(n, @[n.text])
  of nkForEach:
    if n.text.len == 0: n.text = "v"
    n.addPin("", pdIn, pkExec)
    n.addPin("collection", pdIn, pkData)
    for o in ["corps", "next"]: n.addPin(o, pdOut, pkExec)
    g.setVarOuts(n, splitNames(n.text))
  of nkScan:
    n.addPin("", pdIn, pkExec)
    n.addPin("pour", pdIn, pkData, optional = true)
    for o in ["corps", "next"]: n.addPin(o, pdOut, pkExec)
  of nkTry:
    n.addPin("", pdIn, pkExec)
    for o in ["essayer", "capturer", "next"]: n.addPin(o, pdOut, pkExec)
    if n.text.len > 0: g.setVarOuts(n, @[n.text])
  of nkReturn:
    if n.mode.len == 0: n.mode = "retourner"
    n.addExec(["next"])
    n.addPin("valeur", pdIn, pkData, optional = true)
  of nkCall, nkMethod:
    n.stmt = stmt
    if stmt: n.addExec(["next"])
    if kind == nkMethod: n.addPin("objet", pdIn, pkData)
    let params = sigParams(signatureFor(title, kind == nkMethod))
    n.callPins(params, max(0, argCount))
    if not stmt: n.addPin("résultat", pdOut, pkData)
  of nkVar, nkExpr:
    n.addPin("valeur", pdOut, pkData)
  of nkOp:
    if n.title.len == 0: n.title = "+"
    n.addPin("a", pdIn, pkData)
    n.addPin("b", pdIn, pkData)
    n.addPin("", pdOut, pkData)
  of nkUnary:
    if n.title.len == 0: n.title = "non"
    n.addPin("x", pdIn, pkData)
    n.addPin("", pdOut, pkData)
  of nkIndex:
    n.addPin("objet", pdIn, pkData)
    n.addPin("clé", pdIn, pkData)
    n.addPin("", pdOut, pkData)
  of nkMember:
    n.addPin("objet", pdIn, pkData)
    n.addPin("", pdOut, pkData)
  result = n

#
# analyse lexicale fidèle (positions en octets, commentaires conservés)
#

type
  BtKind = enum btName, btNum, btStr, btOp, btComment, btEol, btEof
  BTok = object
    kind: BtKind
    text: string      # nom (mots pointés normalisés), opérateur, ou texte source
    a, b: int         # [a, b) dans la source
    line, lastLine: int

  BpError* = object of CatchableError
    line*: int

proc bpErr(line: int, msg: string) {.noreturn.} =
  var e = newException(BpError, msg)
  e.line = line
  raise e

proc isIdStart(c: char): bool {.inline.} = c in {'a'..'z', 'A'..'Z', '_'} or ord(c) >= 128
proc isIdChar(c: char): bool {.inline.} = c in {'a'..'z', 'A'..'Z', '_', '0'..'9'} or ord(c) >= 128

const dottedWords = ["et", "ou", "non", "v", "f", "t", "vrai", "faux", "nul", "and", "or", "not"]

proc bpTokenize(src: string): seq[BTok] =
  var toks: seq[BTok]
  var i = 0
  var line = 0
  var depth = 0
  var startOfInstr = true
  let n = src.len
  template push(k: BtKind, t: string, a0, b0: int, l0: int) =
    toks.add BTok(kind: k, text: t, a: a0, b: b0, line: l0, lastLine: line)
    if k != btComment: startOfInstr = false
  template eol() =
    if depth == 0 and toks.len > 0 and toks[^1].kind != btEol:
      toks.add BTok(kind: btEol, a: i, b: i, line: line, lastLine: line)
    if depth == 0: startOfInstr = true
  if src.startsWith("#!"):
    while i < n and src[i] != '\n': inc i
    push(btComment, src[0 ..< i], 0, i, 0)
  while i < n:
    let c = src[i]
    if c == '\n':
      eol()
      inc line
      inc i
      continue
    if c in {' ', '\t', '\r', '\f', '\v'}:
      inc i
      continue
    if (c == '*' and startOfInstr) or (c == '&' and i + 1 < n and src[i + 1] == '&') or
       (c == '/' and i + 1 < n and src[i + 1] == '/'):
      let a0 = i
      while i < n and src[i] != '\n': inc i
      push(btComment, src[a0 ..< i], a0, i, line)
      continue
    if c == ';':
      var j = i + 1
      while j < n and src[j] in {' ', '\t', '\r'}: inc j
      var ca = -1
      if j + 1 < n and src[j] == '&' and src[j + 1] == '&':
        ca = j
        while j < n and src[j] != '\n': inc j
      if j >= n or src[j] == '\n':
        if ca >= 0: push(btComment, src[ca ..< j], ca, j, line)
        i = j
        if i < n:
          inc line
          inc i
        continue
      if depth > 0: push(btOp, ";", i, i + 1, line)
      else: eol()
      inc i
      continue
    if c in Digits:
      var j = i
      while j < n and src[j] in Digits: inc j
      if j + 1 < n and src[j] == '.' and src[j + 1] in Digits:
        inc j
        while j < n and src[j] in Digits: inc j
      if j < n and src[j] in {'e', 'E'}:
        var k = j + 1
        if k < n and src[k] in {'+', '-'}: inc k
        if k < n and src[k] in Digits:
          j = k
          while j < n and src[j] in Digits: inc j
      push(btNum, src[i ..< j], i, j, line)
      i = j
      continue
    if c in {'"', '\''}:
      var j = i + 1
      while j < n and src[j] != c and src[j] != '\n':
        if src[j] == '\\' and j + 1 < n and src[j + 1] != '\n': j += 2
        else: inc j
      if j < n and src[j] == c: inc j
      push(btStr, src[i ..< j], i, j, line)
      i = j
      continue
    if c == '[' and i + 1 < n and src[i + 1] == '[':
      var fin = src.find("]]", i + 2)
      let l0 = line
      if fin < 0: fin = n - 2
      for k in i ..< min(n, fin):
        if src[k] == '\n': inc line
      let j = min(n, fin + 2)
      push(btStr, src[i ..< j], i, j, l0)
      i = j
      continue
    if c == '.' and i + 1 < n and src[i + 1] in {'a'..'z', 'A'..'Z'}:
      var j = i + 1
      while j < n and src[j] in {'a'..'z', 'A'..'Z'}: inc j
      if j < n and src[j] == '.':
        let w = src[i + 1 ..< j].toLowerAscii
        if w in dottedWords:
          let m = case w
                  of "v", "t", "vrai": "vrai"
                  of "f", "faux": "faux"
                  of "and": "et"
                  of "or": "ou"
                  of "not": "non"
                  else: w
          push(btName, m, i, j + 1, line)
          i = j + 1
          continue
    if isIdStart(c):
      var j = i
      while j < n and isIdChar(src[j]): inc j
      var t = src[i ..< j]
      if t == "à": t = "a"
      push(btName, t, i, j, line)
      i = j
      continue
    var op = ""
    if i + 2 < n and src[i ..< i + 3] == "...": op = "..."
    elif i + 1 < n:
      let two = src[i ..< i + 2]
      if two in ["==", "<>", "!=", "<=", ">=", "->", "..", "**", "??", "+=", "-="]: op = two
    if op == "":
      var j = i + 1
      while j < n and (ord(src[j]) and 0xC0) == 0x80: inc j
      op = src[i ..< j]
    case op
    of "(", "[", "{": inc depth
    of ")", "]", "}":
      if depth > 0: dec depth
    else: discard
    push(btOp, op, i, i + op.len, line)
    i += op.len
  eol()
  toks.add BTok(kind: btEof, a: n, b: n, line: line, lastLine: line)
  toks

#
# expressions
#

type
  EK = enum exLit, exPath, exCall, exMethod, exBin, exUnary, exParen, exIndex, exMember, exRaw
  Ex = ref object
    kind: EK
    a, b: Ex
    args: seq[Ex]
    op, name: string
    s0, s1: int
    brace: bool

  EP = object
    t: seq[BTok]
    p: int
    src: string

proc cur(e: EP): BTok = (if e.p < e.t.len: e.t[e.p] else: BTok(kind: btEof))
proc peek(e: EP, k = 1): BTok = (if e.p + k < e.t.len: e.t[e.p + k] else: BTok(kind: btEof))
proc isOp(t: BTok, o: string): bool = t.kind == btOp and t.text == o
proc isWord(t: BTok, w: string): bool = t.kind == btName and t.text == w
proc atEnd(e: EP): bool = e.p >= e.t.len
proc fail(e: EP, msg = "expression invalide") {.noreturn.} =
  bpErr((if e.p < e.t.len: e.t[e.p].line else: (if e.t.len > 0: e.t[^1].line else: 0)), msg)

proc lastB(e: EP): int = e.t[max(0, e.p - 1)].b

proc expr(e: var EP): Ex

proc skipBalanced(e: var EP) =
  # Saute un groupe ( ... ), [ ... ] ou { ... } (le jeton courant ouvre).
  var depth = 0
  while not e.atEnd:
    let t = e.cur
    if t.kind == btOp and t.text in ["(", "[", "{"]: inc depth
    elif t.kind == btOp and t.text in [")", "]", "}"]:
      dec depth
      if depth == 0:
        inc e.p
        return
    inc e.p
  e.fail("groupe non fermé")

proc callArgs(e: var EP): seq[Ex] =
  inc e.p                        # (
  if e.cur.isOp(")"):
    inc e.p
    return
  while true:
    result.add e.expr()
    if e.cur.isOp(","):
      inc e.p
      continue
    if e.cur.isOp(")"):
      inc e.p
      return
    e.fail("« , » ou « ) » attendu")

proc primary(e: var EP): Ex =
  let t = e.cur
  case t.kind
  of btNum, btStr:
    inc e.p
    result = Ex(kind: exLit, s0: t.a, s1: t.b)
  of btName:
    inc e.p
    if t.text in ["vrai", "faux", "nul"]: result = Ex(kind: exLit, s0: t.a, s1: t.b)
    else: result = Ex(kind: exPath, name: e.src[t.a ..< t.b], s0: t.a, s1: t.b)
  of btOp:
    case t.text
    of "(":
      inc e.p
      let inner = e.expr()
      if not e.cur.isOp(")"): e.fail("« ) » attendu")
      inc e.p
      result = Ex(kind: exParen, a: inner, s0: t.a, s1: e.lastB)
    of "{":
      e.skipBalanced()
      result = Ex(kind: exLit, s0: t.a, s1: e.lastB)
    of "@":
      inc e.p
      if e.cur.kind != btName: e.fail("nom de procédure attendu après @")
      inc e.p
      result = Ex(kind: exLit, s0: t.a, s1: e.lastB)
    of "...":
      inc e.p
      result = Ex(kind: exLit, s0: t.a, s1: t.b)
    else: e.fail()
  else: e.fail()

proc postfix(e: var EP): Ex =
  var r = e.primary()
  while true:
    let t = e.cur
    if t.isOp("."):
      let id = e.peek()
      if id.kind != btName: e.fail("nom attendu après « . »")
      e.p += 2
      if r.kind == exPath:
        r = Ex(kind: exPath, name: e.src[r.s0 ..< id.b], s0: r.s0, s1: id.b)
      else:
        r = Ex(kind: exMember, a: r, name: e.src[id.a ..< id.b], s0: r.s0, s1: id.b)
    elif t.isOp("["):
      inc e.p
      let k = e.expr()
      if not e.cur.isOp("]"): e.fail("« ] » attendu")
      inc e.p
      r = Ex(kind: exIndex, a: r, b: k, s0: r.s0, s1: e.lastB)
    elif t.isOp("("):
      let args = e.callArgs()
      if r.kind == exPath: r = Ex(kind: exCall, name: r.name, args: args, s0: r.s0, s1: e.lastB)
      else: r = Ex(kind: exRaw, s0: r.s0, s1: e.lastB)
    elif t.isOp("{") and r.kind in {exPath, exIndex, exMember}:
      let a0 = t.a
      e.skipBalanced()
      let tbl = Ex(kind: exLit, s0: a0, s1: e.lastB)
      if r.kind == exPath: r = Ex(kind: exCall, name: r.name, args: @[tbl], brace: true, s0: r.s0, s1: e.lastB)
      else: r = Ex(kind: exRaw, s0: r.s0, s1: e.lastB)
    elif t.isOp(":"):
      if e.peek().isWord("procedure"): break
      let id = e.peek()
      if id.kind != btName: e.fail("nom de méthode attendu après « : »")
      e.p += 2
      var args: seq[Ex]
      var brace = false
      if e.cur.isOp("{"):
        let a0 = e.cur.a
        e.skipBalanced()
        args = @[Ex(kind: exLit, s0: a0, s1: e.lastB)]
        brace = true
      elif e.cur.isOp("("): args = e.callArgs()
      else: e.fail("« ( » attendu après la méthode")
      r = Ex(kind: exMethod, a: r, name: e.src[id.a ..< id.b], args: args, brace: brace, s0: r.s0, s1: e.lastB)
    elif t.isOp("->"):
      let id = e.peek()
      if id.kind != btName: e.fail("nom de champ attendu après « -> »")
      e.p += 2
      r = Ex(kind: exRaw, s0: r.s0, s1: id.b)
    else: break
  r

proc unary(e: var EP): Ex

proc power(e: var EP): Ex =
  var r = e.postfix()
  if e.cur.isOp("^") or e.cur.isOp("**"):
    let op = e.cur.text
    inc e.p
    let rhs = e.unary()
    r = Ex(kind: exBin, op: op, a: r, b: rhs, s0: r.s0, s1: rhs.s1)
  r

proc unary(e: var EP): Ex =
  let t = e.cur
  if t.isOp("-"):
    inc e.p
    let x = e.unary()
    if x.kind == exLit and e.src[x.s0] in Digits: return Ex(kind: exLit, s0: t.a, s1: x.s1)
    return Ex(kind: exUnary, op: "-", a: x, s0: t.a, s1: x.s1)
  if t.isOp("#"):
    inc e.p
    let x = e.unary()
    return Ex(kind: exUnary, op: "#", a: x, s0: t.a, s1: x.s1)
  if t.isOp("+"):
    inc e.p
    return e.unary()
  e.power()

proc multiplicative(e: var EP): Ex =
  var r = e.unary()
  while e.cur.kind == btOp and e.cur.text in ["*", "/", "%"]:
    let op = e.cur.text
    inc e.p
    let rhs = e.unary()
    r = Ex(kind: exBin, op: op, a: r, b: rhs, s0: r.s0, s1: rhs.s1)
  r

proc additive(e: var EP): Ex =
  var r = e.multiplicative()
  while e.cur.kind == btOp and e.cur.text in ["+", "-"]:
    let op = e.cur.text
    inc e.p
    let rhs = e.multiplicative()
    r = Ex(kind: exBin, op: op, a: r, b: rhs, s0: r.s0, s1: rhs.s1)
  r

proc concat(e: var EP): Ex =
  var r = e.additive()
  if e.cur.isOp(".."):
    inc e.p
    let rhs = e.concat()
    r = Ex(kind: exBin, op: "..", a: r, b: rhs, s0: r.s0, s1: rhs.s1)
  r

proc comparison(e: var EP): Ex =
  var r = e.concat()
  while e.cur.kind == btOp and e.cur.text in ["=", "==", "<>", "!=", "#", "<", ">", "<=", ">=", "$"]:
    let op = e.cur.text
    inc e.p
    let rhs = e.concat()
    r = Ex(kind: exBin, op: op, a: r, b: rhs, s0: r.s0, s1: rhs.s1)
  r

proc negation(e: var EP): Ex =
  let t = e.cur
  if t.isWord("non"):
    inc e.p
    let x = e.negation()
    return Ex(kind: exUnary, op: e.src[t.a ..< t.b], a: x, s0: t.a, s1: x.s1)
  e.comparison()

proc conjunction(e: var EP): Ex =
  var r = e.negation()
  while e.cur.isWord("et"):
    let op = e.src[e.cur.a ..< e.cur.b]
    inc e.p
    let rhs = e.negation()
    r = Ex(kind: exBin, op: op, a: r, b: rhs, s0: r.s0, s1: rhs.s1)
  r

proc expr(e: var EP): Ex =
  var r = e.conjunction()
  while e.cur.isWord("ou"):
    let op = e.src[e.cur.a ..< e.cur.b]
    inc e.p
    let rhs = e.conjunction()
    r = Ex(kind: exBin, op: op, a: r, b: rhs, s0: r.s0, s1: rhs.s1)
  r

proc parseWhole(toks: seq[BTok], src: string): Ex =
  # Expression occupant tous les jetons ; lève BpError sinon.
  if toks.len == 0: bpErr(0, "expression vide")
  var e = EP(t: toks, src: src)
  result = e.expr()
  if not e.atEnd: e.fail("fin d'expression attendue")

proc normOp(op: string): string =
  let l = op.toLowerAscii
  case l
  of ".et.", "and": "et"
  of ".ou.", "or": "ou"
  of ".non.", "not": "non"
  else: l

proc binPrec*(op: string): int =
  case normOp(op)
  of "ou": 1
  of "et": 2
  of "=", "==", "<>", "!=", "#", "<", ">", "<=", ">=", "$": 4
  of "..": 5
  of "+", "-": 6
  of "*", "/", "%": 7
  of "^", "**": 9
  else: 4

proc childPrecs(op: string): (int, int) =
  case binPrec(op)
  of 1: (1, 2)
  of 2: (2, 3)
  of 4: (4, 5)
  of 5: (6, 5)
  of 6: (6, 7)
  of 7: (7, 8)
  of 9: (10, 8)
  else: (4, 5)

proc exPrec(x: Ex): int =
  case x.kind
  of exBin: binPrec(x.op)
  of exUnary: (if normOp(x.op) == "non": 3 else: 8)
  else: 10

proc cleanToks(s: string): seq[BTok] =
  for t in bpTokenize(s):
    if t.kind notin {btEol, btEof, btComment}: result.add t

proc textPrec*(s: string): int =
  # Priorité de l'expression écrite dans `s` (0 : non analysable).
  let st = s.strip
  if st.len == 0: return 10
  try:
    result = exPrec(parseWhole(cleanToks(st), st))
  except BpError:
    result = 0

proc isExpression*(s: string): bool =
  # Vrai si `s` est une expression Lexis+ complète.
  let st = s.strip
  if st.len == 0: return false
  try:
    discard parseWhole(cleanToks(st), st)
    result = true
  except BpError:
    result = false

#
# instructions
#

type
  LLine = object
    toks: seq[BTok]          # sans les commentaires
    comment: string          # commentaire final
    isComment: bool          # ligne de commentaire seule
    first, last: int         # lignes source
    blank: int               # lignes vides avant
    shared: bool             # plusieurs instructions sur la même ligne

  SK = enum skComment, skRaw, skPrint, skAssign, skLocal, skCall, skIf, skCase, skWhile, skFor,
            skForEach, skScan, skTry, skReturn, skBreak, skContinue

  St = ref object
    kind: SK
    ex: seq[Ex]
    target, mode, names: string
    elseIf: bool
    blocks: seq[seq[St]]
    hasElse: bool
    head: seq[RawLine]       # lignes d'origine (indentation absolue)
    mids: Table[string, seq[RawLine]]
    headComments: seq[RawLine]
    endLine: RawLine
    hasEnd: bool
    blank: int
    trailing: string
    line: int
    shared: bool
    own: string              # texte propre de l'instruction (lignes partagées)

  SP = object
    src: string
    lines: seq[string]
    ll: seq[LLine]
    i: int

const
  instrWords = [
    "si", "tantque", "pour", "sortir", "boucler", "faire", "parametres",
    "locale", "local", "globale", "retourner", "retour", "stocker",
    "nouvelle", "supprimer", "inserer", "retirer", "fixermetatable", "sql", "utiliser",
    "selectionner", "fermer", "aller", "sauter", "ajouter", "remplacer", "effacer",
    "localiser", "continuer", "chercher", "parcourir", "compter", "liberer",
    "erreur", "essayer", "rafraichir",
    "envoyer", "inclure", "rediriger", "statut", "entete", "deconnecter",
    "sinon", "sinonsi", "finsi", "fintantque", "suivant", "finpour", "cas",
    "autrement", "fincas", "finparcourir", "capturer", "finessayer",
    "procedure", "fonction", "finprocedure", "finfonction"]
  procWords = ["procedure", "fonction", "finprocedure", "finfonction"]

proc indentOf(s: string): int =
  while result < s.len and s[result] == ' ': inc result

proc isBlankLine(s: string): bool = s.strip.len == 0

proc logicalLines(src: string, lines: seq[string]): seq[LLine] =
  let toks = bpTokenize(src)
  var cur: seq[BTok]
  var prevLast = -1
  for t in toks:
    if t.kind in {btEol, btEof}:
      if cur.len > 0:
        var L = LLine(first: cur[0].line, last: cur[0].lastLine)
        var lastCode = -1
        for k, x in cur:
          L.last = max(L.last, x.lastLine)
          if x.kind != btComment:
            L.toks.add x
            lastCode = k
        if L.toks.len == 0:
          L.isComment = true
          L.comment = cur[0].text
        elif lastCode < cur.high:
          var parts: seq[string]
          for k in lastCode + 1 .. cur.high: parts.add cur[k].text
          L.comment = parts.join(" ")
        for l in prevLast + 1 ..< L.first:
          if l >= 0 and l < lines.len and lines[l].isBlankLine: inc L.blank
        if L.first <= prevLast:
          L.shared = true
          if result.len > 0: result[^1].shared = true
        prevLast = max(prevLast, L.last)
        result.add L
      cur.setLen(0)
    else:
      cur.add t

proc rawLines(sp: SP, L: LLine): seq[RawLine] =
  for l in L.first .. L.last:
    if l >= sp.lines.len: break
    let s = sp.lines[l]
    result.add (blank: (if l == L.first: L.blank else: 0), ind: indentOf(s), text: s.strip)

proc rawLine(sp: SP, L: LLine): RawLine =
  let s = sp.lines[L.first]
  (blank: L.blank, ind: indentOf(s), text: s.strip)

proc word(L: LLine, k = 0): string =
  if k < L.toks.len and L.toks[k].kind == btName: L.toks[k].text else: ""

proc isKeywordUse(L: LLine): bool =
  # Premier mot pris comme mot-clé (même règle que l'analyseur de l'interpréteur).
  if L.isComment or L.toks.len == 0: return false
  let w = L.word
  if w notin instrWords: return false
  if L.toks.len > 1:
    let n = L.toks[1]
    if n.kind == btOp and n.text in ["=", ".", "[", "+=", "-=", ":"]: return false
    if w in ["fixermetatable", "inserer", "retirer"] and n.isOp("("): return false
  true

proc exprOrRaw(sp: SP, toks: seq[BTok]): Ex =
  # Expression ; à défaut, texte brut (jamais d'échec).
  if toks.len == 0: return nil
  try:
    result = parseWhole(toks, sp.src)
  except BpError:
    result = Ex(kind: exRaw, s0: toks[0].a, s1: toks[^1].b)

proc splitTopCommas(toks: seq[BTok]): seq[seq[BTok]] =
  var depth = 0
  var cur: seq[BTok]
  for t in toks:
    if t.kind == btOp and t.text in ["(", "[", "{"]: inc depth
    elif t.kind == btOp and t.text in [")", "]", "}"]: dec depth
    if depth == 0 and t.isOp(","):
      result.add cur
      cur = @[]
    else: cur.add t
  result.add cur

proc parseBlock(sp: var SP, ends: openArray[string]): seq[St]

proc closeWith(sp: var SP, st: St, words: openArray[string], opener: string, openLine: int) =
  if sp.i >= sp.ll.len or sp.ll[sp.i].isComment or sp.ll[sp.i].word notin words:
    bpErr(openLine, "« " & words[0] & " » manquant pour « " & opener & " » (ligne " & $(openLine + 1) & ")")
  st.endLine = sp.rawLine(sp.ll[sp.i])
  st.hasEnd = true
  inc sp.i

proc newSt(sp: SP, kind: SK, L: LLine): St =
  result = St(kind: kind, line: L.first, blank: L.blank, trailing: L.comment, shared: L.shared,
              head: sp.rawLines(L), mids: initTable[string, seq[RawLine]]())
  if L.shared and L.toks.len > 0:
    result.own = sp.src[L.toks[0].a ..< L.toks[^1].b]
    if L.comment.len > 0: result.own.add "  " & L.comment

proc parseStmt(sp: var SP): St =
  let L = sp.ll[sp.i]
  if L.isComment:
    # commentaires consécutifs (même indentation, sans ligne vide) : un seul nœud.
    result = sp.newSt(skComment, L)
    inc sp.i
    let ind = indentOf(sp.lines[L.first])
    while sp.i < sp.ll.len and sp.ll[sp.i].isComment and sp.ll[sp.i].blank == 0 and
          not sp.ll[sp.i].shared and indentOf(sp.lines[sp.ll[sp.i].first]) == ind:
      result.head.add sp.rawLines(sp.ll[sp.i])
      inc sp.i
    return
  let t = L.toks
  inc sp.i
  if t[0].kind == btOp and t[0].text in ["?", "??"]:
    result = sp.newSt(skPrint, L)
    result.mode = t[0].text
    if t.len > 1:
      for part in splitTopCommas(t[1 .. ^1]):
        if part.len == 0:
          result.kind = skRaw
          return
        try: result.ex.add parseWhole(part, sp.src)
        except BpError:
          result.kind = skRaw
          return
    return
  if L.isKeywordUse:
    let w = L.word
    case w
    of "si":
      result = sp.newSt(skIf, L)
      result.ex.add sp.exprOrRaw(t[1 .. ^1])
      var node = result
      while true:
        node.blocks.add sp.parseBlock(["sinonsi", "sinon", "finsi"])
        if sp.i >= sp.ll.len: break
        let M = sp.ll[sp.i]
        if M.isComment: break
        if M.word == "sinonsi" or (M.word == "sinon" and M.word(1) == "si"):
          let sub = sp.newSt(skIf, M)
          sub.elseIf = true
          let skip = if M.word == "sinonsi": 1 else: 2
          sub.ex.add sp.exprOrRaw(M.toks[skip .. ^1])
          inc sp.i
          node.blocks.add @[sub]
          node.hasElse = true
          node = sub
          continue
        if M.word == "sinon":
          node.mids["sinon"] = sp.rawLines(M)
          node.hasElse = true
          inc sp.i
          node.blocks.add sp.parseBlock(["finsi"])
        break
      sp.closeWith(result, ["finsi"], "si", L.first)
    of "tantque":
      result = sp.newSt(skWhile, L)
      result.mode = "tantque"
      result.ex.add sp.exprOrRaw(t[1 .. ^1])
      result.blocks.add sp.parseBlock(["fintantque"])
      sp.closeWith(result, ["fintantque"], "tantque", L.first)
    of "faire":
      if L.word(1) == "tantque":
        result = sp.newSt(skWhile, L)
        result.mode = "faire tantque"
        result.ex.add sp.exprOrRaw(t[2 .. ^1])
        result.blocks.add sp.parseBlock(["fintantque"])
        sp.closeWith(result, ["fintantque"], "faire tantque", L.first)
      elif L.word(1) == "cas":
        result = sp.newSt(skCase, L)
        while sp.i < sp.ll.len and sp.ll[sp.i].isComment:
          result.headComments.add sp.rawLines(sp.ll[sp.i])
          inc sp.i
        var k = 0
        while sp.i < sp.ll.len and not sp.ll[sp.i].isComment and sp.ll[sp.i].word == "cas":
          let C = sp.ll[sp.i]
          inc k
          result.mids["cas" & $k] = sp.rawLines(C)
          result.ex.add sp.exprOrRaw(C.toks[1 .. ^1])
          inc sp.i
          result.blocks.add sp.parseBlock(["cas", "autrement", "fincas"])
        if sp.i < sp.ll.len and not sp.ll[sp.i].isComment and sp.ll[sp.i].word == "autrement":
          result.mids["autrement"] = sp.rawLines(sp.ll[sp.i])
          result.hasElse = true
          inc sp.i
          result.blocks.add sp.parseBlock(["fincas"])
        sp.closeWith(result, ["fincas"], "faire cas", L.first)
      else:
        result = sp.newSt(skRaw, L)
    of "pour":
      if L.word(1) == "chaque":
        result = sp.newSt(skForEach, L)
        var k = 2
        var names: seq[string]
        while k < t.len and t[k].kind == btName and t[k].text != "dans":
          names.add sp.src[t[k].a ..< t[k].b]
          inc k
          if k < t.len and t[k].isOp(","): inc k
        if k >= t.len or not t[k].isWord("dans") or names.len == 0:
          bpErr(L.first, "« pour chaque » mal formé (ligne " & $(L.first + 1) & ")")
        result.names = names.join(", ")
        result.ex.add sp.exprOrRaw(t[k + 1 .. ^1])
      else:
        result = sp.newSt(skFor, L)
        if t.len < 4 or t[1].kind != btName or not t[2].isOp("="):
          bpErr(L.first, "« pour » mal formé (ligne " & $(L.first + 1) & ")")
        result.names = sp.src[t[1].a ..< t[1].b]
        var e = EP(t: t, p: 3, src: sp.src)
        try:
          result.ex.add e.expr()
          if not (e.cur.isWord("a") or e.cur.isWord("jusqua")): e.fail("« a » attendu")
          result.mode = e.cur.text
          inc e.p
          result.ex.add e.expr()
          if e.cur.isWord("pas"):
            inc e.p
            result.ex.add e.expr()
          if not e.atEnd: e.fail()
        except BpError:
          bpErr(L.first, "« pour » mal formé (ligne " & $(L.first + 1) & ")")
      result.blocks.add sp.parseBlock(["suivant", "finpour"])
      sp.closeWith(result, ["suivant", "finpour"], (if result.kind == skFor: "pour" else: "pour chaque"), L.first)
    of "parcourir":
      result = sp.newSt(skScan, L)
      if t.len > 1 and t[1].isWord("pour"): result.ex.add sp.exprOrRaw(t[2 .. ^1])
      result.blocks.add sp.parseBlock(["finparcourir"])
      sp.closeWith(result, ["finparcourir"], "parcourir", L.first)
    of "essayer":
      result = sp.newSt(skTry, L)
      result.blocks.add sp.parseBlock(["capturer", "finessayer"])
      if sp.i < sp.ll.len and not sp.ll[sp.i].isComment and sp.ll[sp.i].word == "capturer":
        let C = sp.ll[sp.i]
        result.mids["capturer"] = sp.rawLines(C)
        if C.toks.len > 1 and C.toks[1].kind == btName: result.names = sp.src[C.toks[1].a ..< C.toks[1].b]
        result.hasElse = true
        inc sp.i
        result.blocks.add sp.parseBlock(["finessayer"])
      sp.closeWith(result, ["finessayer"], "essayer", L.first)
    of "retourner", "retour":
      result = sp.newSt(skReturn, L)
      result.mode = w
      if t.len > 1:
        try: result.ex.add parseWhole(t[1 .. ^1], sp.src)
        except BpError: result.kind = skRaw
    of "sortir": result = sp.newSt(skBreak, L)
    of "boucler": result = sp.newSt(skContinue, L)
    of "locale", "local", "globale":
      result = sp.newSt(skLocal, L)
      result.mode = w
      let parts = splitTopCommas(t[1 .. ^1])
      if parts.len != 1 or parts[0].len == 0 or parts[0][0].kind != btName:
        result.kind = skRaw
        return
      let p = parts[0]
      result.names = sp.src[p[0].a ..< p[0].b]
      if p.len > 1:
        if not p[1].isOp("=") or p.len < 3:
          result.kind = skRaw
          return
        try: result.ex.add parseWhole(p[2 .. ^1], sp.src)
        except BpError: result.kind = skRaw
    of "sinon", "sinonsi", "finsi", "fintantque", "suivant", "finpour", "cas", "autrement",
       "fincas", "finparcourir", "capturer", "finessayer":
      bpErr(L.first, "« " & w & " » inattendu ligne " & $(L.first + 1) & " (bloc non ouvert ?)")
    else:
      result = sp.newSt(skRaw, L)
    return
  # affectation ou appel
  var e = EP(t: t, src: sp.src)
  try:
    let target = e.postfix()
    if e.atEnd:
      if target.kind in {exCall, exMethod}:
        result = sp.newSt(skCall, L)
        result.ex.add target
      else: result = sp.newSt(skRaw, L)
      return
    let op = e.cur
    if op.kind == btOp and op.text in ["=", "+=", "-="] and target.kind in {exPath, exIndex, exMember}:
      inc e.p
      let v = parseWhole(t[e.p .. ^1], sp.src)
      result = sp.newSt(skAssign, L)
      result.target = sp.src[target.s0 ..< target.s1]
      result.mode = op.text
      result.ex.add v
      return
  except BpError: discard
  result = sp.newSt(skRaw, L)

proc parseBlock(sp: var SP, ends: openArray[string]): seq[St] =
  while sp.i < sp.ll.len:
    let L = sp.ll[sp.i]
    if not L.isComment and L.toks.len > 0 and L.toks[0].kind == btName:
      let w = L.word
      if w in ends: break
      if w in procWords and L.isKeywordUse: break
    result.add sp.parseStmt()

#
# construction du graphe
#

type Builder = object
  g: Graph
  src: string
  procParams: Table[string, seq[string]]
  scopes: seq[tuple[name: string, node, pid: int]]   # variables de boucle visibles (câblées)

proc relLines(lines: seq[RawLine], base: int): seq[RawLine] =
  for l in lines: result.add (blank: l.blank, ind: l.ind - base, text: l.text)

proc relLine(l: RawLine, base: int): RawLine = (blank: l.blank, ind: l.ind - base, text: l.text)

proc exText(b: Builder, x: Ex): string = b.src[x.s0 ..< x.s1]

proc bindInput(b: var Builder, n: Node, pid: int, x: Ex, key: string)

proc buildExpr(b: var Builder, x: Ex, key: string): Node =
  # Nœud pur pour une expression non littérale.
  let g = b.g
  case x.kind
  of exParen: return b.buildExpr(x.a, key)
  of exPath:
    result = g.makeNode(nkVar, title = x.name)
  of exCall:
    let n = g.newNode(nkCall)
    n.title = x.name
    n.brace = x.brace
    var params = sigParams(signatureFor(x.name, false))
    if params.len == 0:
      let up = x.name.toUpperAscii
      if up in b.procParams:
        for p in b.procParams[up]: params.add (name: p, optional: false, variadic: false)
    n.callPins(params, x.args.len)
    n.addPin("résultat", pdOut, pkData)
    let ins = n.dataInputs
    for k, a in x.args:
      if k < ins.len: b.bindInput(n, ins[k], a, key & ">" & $k)
    result = n
  of exMethod:
    let n = g.newNode(nkMethod)
    n.title = x.name
    n.brace = x.brace
    n.addPin("objet", pdIn, pkData)
    n.callPins(sigParams(signatureFor(x.name, true)), x.args.len)
    n.addPin("résultat", pdOut, pkData)
    let ins = n.dataInputs
    b.bindInput(n, ins[0], x.a, key & ">o")
    for k, a in x.args:
      if k + 1 < ins.len: b.bindInput(n, ins[k + 1], a, key & ">" & $k)
    result = n
  of exBin:
    let n = g.makeNode(nkOp, title = x.op)
    b.bindInput(n, n.pins[0].pid, x.a, key & ">a")
    b.bindInput(n, n.pins[1].pid, x.b, key & ">b")
    result = n
  of exUnary:
    let n = g.makeNode(nkUnary, title = x.op)
    b.bindInput(n, n.pins[0].pid, x.a, key & ">x")
    result = n
  of exIndex:
    let n = g.makeNode(nkIndex)
    b.bindInput(n, n.pins[0].pid, x.a, key & ">o")
    b.bindInput(n, n.pins[1].pid, x.b, key & ">k")
    result = n
  of exMember:
    let n = g.makeNode(nkMember, title = x.name)
    b.bindInput(n, n.pins[0].pid, x.a, key & ">o")
    result = n
  of exRaw, exLit:
    result = g.makeNode(nkExpr, text = b.exText(x))
  result.dirty = false
  result.key = key

proc bindInput(b: var Builder, n: Node, pid: int, x: Ex, key: string) =
  if x == nil: return
  var y = x
  while y.kind == exParen and y.a.kind == exLit: y = y.a
  let i = n.pinIndex(pid)
  if y.kind == exLit:
    n.pins[i].default = b.exText(y)
    return
  if y.kind == exPath and '.' notin y.name:
    # variable de boucle : câblée depuis la sortie du bloc qui la déclare.
    let up = y.name.toUpperAscii
    for k in countdown(b.scopes.high, 0):
      if b.scopes[k].name == up:
        b.g.links.add Link(a: b.scopes[k].node, ap: b.scopes[k].pid, b: n.id, bp: pid)
        return
  let src = b.buildExpr(y, key)
  b.g.links.add Link(a: src.id, ap: src.dataOut, b: n.id, bp: pid)

proc buildChain(b: var Builder, fromId, fromPid: int, sts: seq[St], baseInd: int, key: string)

proc buildStmt(b: var Builder, s: St, baseInd: int, key: string): Node =
  let g = b.g
  let headInd = if s.head.len > 0: s.head[0].ind else: baseInd
  var n: Node
  case s.kind
  of skComment:
    var texts: seq[string]
    for h in s.head:
      var t = h.text
      if t.startsWith("&&") or t.startsWith("//"): t = t[2 .. ^1]
      elif t.startsWith("*"): t = t[1 .. ^1]
      if t.startsWith(" "): t = t[1 .. ^1]
      texts.add t
    n = g.makeNode(nkComment, text = texts.join("\n"))
  of skRaw:
    if s.shared and s.own.len > 0:
      n = g.makeNode(nkRaw, text = s.own)
    else:
      var texts: seq[string]
      for h in s.head: texts.add spaces(max(0, h.ind - headInd)) & h.text
      n = g.makeNode(nkRaw, text = texts.join("\n"))
  of skPrint:
    n = g.makeNode(nkPrint, mode = s.mode, argCount = s.ex.len)
    if s.ex.len == 0:
      for pid in n.dataInputs: g.removePin(n, pid)
    let ins = n.dataInputs
    for k, x in s.ex: b.bindInput(n, ins[k], x, key & ">" & $k)
  of skAssign:
    n = g.makeNode(nkAssign, text = s.target, mode = s.mode)
    b.bindInput(n, n.dataInputs[0], s.ex[0], key & ">v")
  of skLocal:
    n = g.makeNode(nkLocal, text = s.names, mode = s.mode)
    if s.ex.len > 0: b.bindInput(n, n.dataInputs[0], s.ex[0], key & ">v")
  of skCall:
    n = b.buildExpr(s.ex[0], key)
    g.setStatement(n, true)
  of skIf:
    n = g.makeNode(nkIf)
    n.elseIf = s.elseIf
    b.bindInput(n, n.dataInputs[0], s.ex[0], key & ">c")
  of skCase:
    n = g.makeNode(nkCase, argCount = s.ex.len)
    let ins = n.dataInputs
    for k, x in s.ex: b.bindInput(n, ins[k], x, key & ">c" & $k)
  of skWhile:
    n = g.makeNode(nkWhile, mode = s.mode)
    b.bindInput(n, n.dataInputs[0], s.ex[0], key & ">c")
  of skFor:
    n = g.makeNode(nkFor, text = s.names, mode = s.mode)
    let ins = n.dataInputs
    for k in 0 ..< ins.len: n.pins[n.pinIndex(ins[k])].default = ""
    for k, x in s.ex:
      if k < ins.len: b.bindInput(n, ins[k], x, key & ">" & $k)
  of skForEach:
    n = g.makeNode(nkForEach, text = s.names)
    b.bindInput(n, n.dataInputs[0], s.ex[0], key & ">c")
  of skScan:
    n = g.makeNode(nkScan)
    if s.ex.len > 0: b.bindInput(n, n.dataInputs[0], s.ex[0], key & ">c")
  of skTry:
    n = g.makeNode(nkTry, text = s.names)
  of skReturn:
    n = g.makeNode(nkReturn, mode = s.mode)
    if s.ex.len > 0: b.bindInput(n, n.dataInputs[0], s.ex[0], key & ">v")
  of skBreak: n = g.makeNode(nkBreak)
  of skContinue: n = g.makeNode(nkContinue)
  n.dirty = s.shared
  n.key = key
  n.line = s.line
  n.blank = s.blank
  n.trailing = s.trailing
  n.rel = headInd - baseInd
  n.orig = relLines(s.head, headInd)
  if n.orig.len > 0: n.orig[0].blank = 0
  for k, v in s.mids: n.mids[k] = relLines(v, headInd)
  n.headComments = relLines(s.headComments, headInd)
  n.hasEnd = s.hasEnd
  if s.hasEnd: n.endLine = relLine(s.endLine, headInd)
  # variables de boucle : nom d'origine (et portée pour le câblage des corps).
  var pushed = 0
  for p in n.pins.mitems:
    if p.varOut:
      p.origName = p.varName
      if s.kind in {skFor, skForEach}:
        b.scopes.add (p.varName.toUpperAscii, n.id, p.pid)
        inc pushed
  # corps des blocs
  case s.kind
  of skIf:
    if s.blocks.len > 0: b.buildChain(n.id, n.findPin(pdOut, pkExec, "alors"), s.blocks[0], headInd, key & "/a")
    if s.blocks.len > 1: b.buildChain(n.id, n.findPin(pdOut, pkExec, "sinon"), s.blocks[1], headInd, key & "/s")
  of skCase:
    for k in 0 ..< s.ex.len:
      if k < s.blocks.len:
        b.buildChain(n.id, n.findPin(pdOut, pkExec, "cas " & $(k + 1)), s.blocks[k], headInd, key & "/c" & $k)
    if s.hasElse and s.blocks.len > s.ex.len:
      b.buildChain(n.id, n.findPin(pdOut, pkExec, "autrement"), s.blocks[^1], headInd, key & "/e")
  of skWhile, skFor, skForEach, skScan:
    if s.blocks.len > 0: b.buildChain(n.id, n.findPin(pdOut, pkExec, "corps"), s.blocks[0], headInd, key & "/b")
  of skTry:
    if s.blocks.len > 0: b.buildChain(n.id, n.findPin(pdOut, pkExec, "essayer"), s.blocks[0], headInd, key & "/t")
    if s.blocks.len > 1:
      for p in n.pins:
        if p.varOut:
          b.scopes.add (p.varName.toUpperAscii, n.id, p.pid)
          inc pushed
      b.buildChain(n.id, n.findPin(pdOut, pkExec, "capturer"), s.blocks[1], headInd, key & "/x")
  else: discard
  b.scopes.setLen(b.scopes.len - pushed)
  n

proc buildChain(b: var Builder, fromId, fromPid: int, sts: seq[St], baseInd: int, key: string) =
  var prevId = fromId
  var prevPid = fromPid
  for k, s in sts:
    let n = b.buildStmt(s, baseInd, key & "/" & $k)
    b.g.links.add Link(a: prevId, ap: prevPid, b: n.id, bp: n.execIn)
    prevId = n.id
    prevPid = n.execNext

proc takeTrailingComments(sp: SP, sts: var seq[St]): seq[string] =
  # Commentaires (et lignes vides) en fin de corps : ils précèdent la procédure suivante.
  var k = sts.len
  while k > 0 and sts[k - 1].kind == skComment: dec k
  if k == sts.len: return
  for j in k ..< sts.len:
    for h in sts[j].head:
      for _ in 0 ..< h.blank: result.add ""
      result.add spaces(h.ind) & h.text
  sts.setLen(k)

proc parseHeader(sp: SP, L: LLine): tuple[kind, name, params: string] =
  let t = L.toks
  if t.len < 2 or t[1].kind != btName:
    bpErr(L.first, "nom de procédure attendu ligne " & $(L.first + 1))
  result.kind = t[0].text
  result.name = sp.src[t[1].a ..< t[1].b]
  if t.len > 2:
    if not t[2].isOp("(") or not t[^1].isOp(")"):
      bpErr(L.first, "paramètres mal formés ligne " & $(L.first + 1))
    var names: seq[string]
    for k in 3 ..< t.len - 1:
      if t[k].kind == btName: names.add sp.src[t[k].a ..< t[k].b]
      elif not t[k].isOp(","): bpErr(L.first, "paramètres mal formés ligne " & $(L.first + 1))
    result.params = names.join(", ")

proc parseGraph*(text: string): Graph =
  # Analyse un fichier Lexis+ ; en cas d'erreur de structure, g.error est renseigné.
  result = newGraph()
  let g = result
  var sp = SP(src: text, lines: text.split('\n'))
  try:
    sp.ll = logicalLines(text, sp.lines)
    var b = Builder(g: g, src: text, procParams: initTable[string, seq[string]]())
    # paramètres des procédures du fichier (broches des appels).
    for L in sp.ll:
      if not L.isComment and L.word in ["procedure", "fonction"] and L.isKeywordUse:
        try:
          let h = sp.parseHeader(L)
          b.procParams[h.name.toUpperAscii] = splitNames(h.params)
        except BpError: discard
    var mainSts = sp.parseBlock(["finprocedure", "finfonction"])
    if sp.i < sp.ll.len and sp.ll[sp.i].word in ["finprocedure", "finfonction"]:
      bpErr(sp.ll[sp.i].first, "« " & sp.ll[sp.i].word & " » sans procédure ouverte (ligne " &
            $(sp.ll[sp.i].first + 1) & ")")
    var preamble: seq[string]
    if sp.i < sp.ll.len: preamble = sp.takeTrailingComments(mainSts)
    let main = g.makeNode(nkEntry, mode = "principal")
    main.dirty = false
    main.key = "M"
    main.line = 0
    g.mainId = main.id
    g.entries.add main.id
    b.buildChain(main.id, main.execNext, mainSts, 0, "M")
    var suites = 0
    while sp.i < sp.ll.len:
      let L = sp.ll[sp.i]
      if L.isComment or L.word notin ["procedure", "fonction"] or not L.isKeywordUse:
        # instructions après un « finprocedure » : programme principal (suite).
        var sts = sp.parseBlock(procWords)
        if sp.i < sp.ll.len and sp.ll[sp.i].word in ["finprocedure", "finfonction"] and
           sp.ll[sp.i].isKeywordUse and sp.ll[sp.i].first == L.first:
          bpErr(L.first, "« " & L.word & " » sans procédure ouverte (ligne " & $(L.first + 1) & ")")
        let pre = sp.takeTrailingComments(sts)
        if sts.len == 0:
          if sp.i < sp.ll.len: preamble.add pre
          else: g.epilogue = preamble & pre
          continue
        inc suites
        let e = g.makeNode(nkEntry, mode = "suite")
        e.dirty = false
        e.key = "S" & $suites
        e.line = L.first
        e.preamble = preamble
        preamble = @[]
        g.entries.add e.id
        b.buildChain(e.id, e.execNext, sts, 0, e.key)
        if sp.i < sp.ll.len: preamble = pre
        else: g.epilogue = pre
        continue
      let h = sp.parseHeader(L)
      inc sp.i
      var body = sp.parseBlock(procWords)
      let e = g.makeNode(nkEntry, title = h.name, text = h.params, mode = h.kind)
      e.dirty = false
      e.key = "P:" & h.name.toUpperAscii
      e.line = L.first
      for _ in 0 ..< L.blank: preamble.add ""
      e.preamble = preamble
      preamble = @[]
      let hl = sp.rawLines(L)
      let headInd = if hl.len > 0: hl[0].ind else: 0
      e.orig = relLines(hl, headInd)
      if e.orig.len > 0: e.orig[0].blank = 0
      e.trailing = L.comment
      if sp.i < sp.ll.len and not sp.ll[sp.i].isComment and sp.ll[sp.i].word in ["finprocedure", "finfonction"] and
         sp.ll[sp.i].isKeywordUse:
        e.hasEnd = true
        e.endLine = relLine(sp.rawLine(sp.ll[sp.i]), headInd)
        inc sp.i
      if sp.i < sp.ll.len: preamble = sp.takeTrailingComments(body)
      g.entries.add e.id
      b.buildChain(e.id, e.execNext, body, headInd, e.key)
    # lignes vides de fin
    let lastLine = if sp.ll.len > 0: sp.ll[^1].last else: -1
    for _ in lastLine + 1 .. sp.lines.high: g.tail.add ""
  except BpError as e:
    let line = e.line
    result = newGraph()
    result.error = e.msg
    result.errorLine = line
    let main = result.makeNode(nkEntry, mode = "principal")
    main.dirty = false
    result.mainId = main.id
    result.entries.add main.id


#
# génération du code
#

type Gen = object
  g: Graph
  curLine: int
  outp: seq[string]
  visiting: HashSet[int]
  visited: HashSet[int]

proc paren(s: string, prec, need: int): string =
  if prec < need: "(" & s & ")" else: s

proc genOut(gen: var Gen, n: Node, pid: int): tuple[s: string, prec: int]

proc genInput(gen: var Gen, n: Node, pid: int, need: int): string =
  # Texte d'une entrée de données ("" : non reliée et vide).
  let li = gen.g.linkInto(n.id, pid)
  if li >= 0:
    let l = gen.g.links[li]
    let src = gen.g.node(l.a)
    if src == nil: return "nul"
    let r = gen.genOut(src, l.ap)
    return paren(r.s, r.prec, need)
  let i = n.pinIndex(pid)
  if i < 0: return ""
  let d = n.pins[i].default.strip
  if d.len == 0: return ""
  paren(d, textPrec(d), need)

proc argList(gen: var Gen, n: Node, skipFirst: bool): string =
  var args: seq[string]
  var first = true
  for p in n.pins:
    if p.dir != pdIn or p.kind != pkData: continue
    if skipFirst and first:
      first = false
      continue
    first = false
    args.add gen.genInput(n, p.pid, 0)
  while args.len > 0 and args[^1].len == 0: args.setLen(args.len - 1)
  for a in args.mitems:
    if a.len == 0: a = "nul"
  args.join(", ")

proc callText(gen: var Gen, n: Node): string =
  var head: string
  if n.kind == nkMethod:
    var objPid = -1
    for p in n.pins:
      if p.dir == pdIn and p.kind == pkData:
        objPid = p.pid
        break
    var obj = if objPid >= 0: gen.genInput(n, objPid, 10) else: ""
    if obj.len == 0: obj = "nul"
    head = obj & ":" & n.title
  else: head = n.title
  let args = gen.argList(n, n.kind == nkMethod)
  if n.brace and args.startsWith("{") and args.endsWith("}") and textPrec(args) == 10 and
     splitTopLevel(args).len == 1:
    head & args
  else:
    head & "(" & args & ")"

proc genOut(gen: var Gen, n: Node, pid: int): tuple[s: string, prec: int] =
  let i = n.pinIndex(pid)
  if i >= 0 and n.pins[i].varOut: return (n.pins[i].varName, 10)
  if n.id in gen.visiting: return ("nul", 10)        # cycle de données
  n.line = gen.curLine
  gen.visiting.incl n.id
  defer: gen.visiting.excl n.id
  case n.kind
  of nkVar: (n.title, 10)
  of nkExpr: (n.text, textPrec(n.text))
  of nkCall, nkMethod: (gen.callText(n), 10)
  of nkOp:
    let (l, r) = childPrecs(n.title)
    var a = gen.genInput(n, n.pins[0].pid, l)
    var b = gen.genInput(n, n.pins[1].pid, r)
    if a.len == 0: a = "nul"
    if b.len == 0: b = "nul"
    (a & " " & n.title & " " & b, binPrec(n.title))
  of nkUnary:
    let negate = normOp(n.title) == "non"
    var x = gen.genInput(n, n.pins[0].pid, (if negate: 3 else: 8))
    if x.len == 0: x = "nul"
    ((if negate: n.title & " " & x else: n.title & x), (if negate: 3 else: 8))
  of nkIndex:
    var o = gen.genInput(n, n.pins[0].pid, 10)
    var k = gen.genInput(n, n.pins[1].pid, 0)
    if o.len == 0: o = "nul"
    if k.len == 0: k = "nul"
    (o & "[" & k & "]", 10)
  of nkMember:
    var o = gen.genInput(n, n.pins[0].pid, 10)
    if o.len == 0: o = "nul"
    (o & "." & n.title, 10)
  else: ("nul", 10)

proc inputsClean(gen: var Gen, n: Node, depth = 0): bool =
  if depth > 200: return false
  for l in gen.g.links:
    if l.b != n.id: continue
    let src = gen.g.node(l.a)
    if src == nil: return false
    let i = src.pinIndex(l.ap)
    if i < 0 or src.pins[i].kind == pkExec: continue
    if src.pins[i].varOut:
      if src.pins[i].varName != src.pins[i].origName: return false
      continue
    if src.dirty: return false
    if not gen.inputsClean(src, depth + 1): return false
  true

proc reusable(gen: var Gen, n: Node): bool =
  n.orig.len > 0 and not n.dirty and gen.inputsClean(n)

proc emit(gen: var Gen, ind: int, s: string) = gen.outp.add spaces(max(0, ind)) & s

proc emitRaw(gen: var Gen, base: int, l: RawLine) =
  for _ in 0 ..< l.blank: gen.outp.add ""
  gen.emit(base + l.ind, l.text)

proc withTrailing(n: Node, s: string): string =
  if n.trailing.len > 0: s & "  " & n.trailing else: s

proc stmtText(gen: var Gen, n: Node): string =
  # Instruction simple régénérée (sans indentation).
  case n.kind
  of nkPrint:
    var args: seq[string]
    for p in n.pins:
      if p.dir == pdIn and p.kind == pkData: args.add gen.genInput(n, p.pid, 0)
    while args.len > 0 and args[^1].len == 0: args.setLen(args.len - 1)
    for a in args.mitems:
      if a.len == 0: a = "nul"
    if args.len == 0: n.mode else: n.mode & " " & args.join(", ")
  of nkAssign:
    var v = gen.genInput(n, n.dataInputs[0], 0)
    if v.len == 0: v = "nul"
    (if n.text.strip.len > 0: n.text.strip else: "x") & " " & n.mode & " " & v
  of nkLocal:
    let v = gen.genInput(n, n.dataInputs[0], 0)
    n.mode & " " & (if n.text.strip.len > 0: n.text.strip else: "x") & (if v.len > 0: " = " & v else: "")
  of nkCall, nkMethod: gen.callText(n)
  of nkReturn:
    let v = gen.genInput(n, n.dataInputs[0], 0)
    (if n.mode.len > 0: n.mode else: "retourner") & (if v.len > 0: " " & v else: "")
  of nkBreak: "sortir"
  of nkContinue: "boucler"
  else: ""

proc genChain(gen: var Gen, fromId, fromPid: int, base, defRel: int)

proc genBody(gen: var Gen, n: Node, pin: string, headInd: int) =
  let pid = n.findPin(pdOut, pkExec, pin)
  if pid >= 0: gen.genChain(n.id, pid, headInd, 2)

proc condOf(gen: var Gen, n: Node, k = 0): string =
  let ins = n.dataInputs
  if k >= ins.len: return "nul"
  result = gen.genInput(n, ins[k], 0)
  if result.len == 0: result = "nul"

proc midLine(gen: var Gen, n: Node, key, fallback: string, headInd: int, reuse = true) =
  if reuse and key in n.mids:
    for l in n.mids[key]: gen.emitRaw(headInd, l)
  else: gen.emit(headInd, fallback)

proc endLineOf(gen: var Gen, n: Node, fallback: string, headInd: int) =
  if n.hasEnd: gen.emitRaw(headInd, n.endLine)
  else: gen.emit(headInd, fallback)

proc genIfTail(gen: var Gen, n: Node, headInd: int) =
  # Branche sinon d'un si (avec « sinonsi » si elle ne contient qu'un si marqué).
  let sp = n.findPin(pdOut, pkExec, "sinon")
  let first = gen.g.followExec(n.id, sp)
  if first == nil: return
  if first.kind == nkIf and first.elseIf and gen.g.followExec(first.id, first.execNext) == nil and
     first.id notin gen.visited:
    gen.visited.incl first.id
    for _ in 0 ..< first.blank: gen.outp.add ""
    first.line = gen.outp.len
    gen.curLine = first.line
    if gen.reusable(first):
      for l in first.orig: gen.emitRaw(headInd, l)
    else: gen.emit(headInd, first.withTrailing("sinonsi " & gen.condOf(first)))
    gen.genBody(first, "alors", headInd)
    gen.genIfTail(first, headInd)
    return
  gen.midLine(n, "sinon", "sinon", headInd)
  gen.genBody(n, "sinon", headInd)

proc genNode(gen: var Gen, n: Node, base, defRel: int) =
  let ind = base + (if n.rel >= 0: n.rel else: defRel)
  for _ in 0 ..< n.blank: gen.outp.add ""
  n.line = gen.outp.len
  gen.curLine = n.line
  let reuse = gen.reusable(n)
  case n.kind
  of nkComment:
    if not n.dirty and n.orig.len > 0:
      for l in n.orig: gen.emitRaw(ind, l)
    else:
      for l in n.text.splitLines():
        gen.emit(ind, (if l.len > 0: "&& " & l else: "&&"))
  of nkRaw:
    if not n.dirty and n.orig.len > 0:
      for l in n.orig: gen.emitRaw(ind, l)
    else:
      let ls = n.text.splitLines()
      let cut = if ls.len > 0: indentOf(ls[0]) else: 0
      for l in ls:
        let k = min(cut, indentOf(l))
        gen.emit(ind, l[k .. ^1])
  of nkPrint, nkAssign, nkLocal, nkCall, nkMethod, nkReturn, nkBreak, nkContinue:
    if reuse:
      for l in n.orig: gen.emitRaw(ind, l)
    else: gen.emit(ind, n.withTrailing(gen.stmtText(n)))
  of nkIf:
    if reuse and not n.elseIf:
      for l in n.orig: gen.emitRaw(ind, l)
    else: gen.emit(ind, n.withTrailing("si " & gen.condOf(n)))
    gen.genBody(n, "alors", ind)
    gen.genIfTail(n, ind)
    gen.endLineOf(n, "finsi", ind)
  of nkCase:
    if reuse:
      for l in n.orig: gen.emitRaw(ind, l)
    else: gen.emit(ind, n.withTrailing("faire cas"))
    for l in n.headComments: gen.emitRaw(ind, l)
    var k = 0
    for p in n.pins:
      if p.dir == pdOut and p.kind == pkExec and p.name.startsWith("cas "):
        inc k
        let key = "cas" & $k
        if reuse and key in n.mids:
          for l in n.mids[key]: gen.emitRaw(ind, l)
        else: gen.emit(ind, "cas " & gen.condOf(n, k - 1))
        gen.genChain(n.id, p.pid, ind, 2)
    let ap = n.findPin(pdOut, pkExec, "autrement")
    if ap >= 0 and (gen.g.followExec(n.id, ap) != nil or "autrement" in n.mids):
      gen.midLine(n, "autrement", "autrement", ind)
      gen.genChain(n.id, ap, ind, 2)
    gen.endLineOf(n, "fincas", ind)
  of nkWhile:
    if reuse:
      for l in n.orig: gen.emitRaw(ind, l)
    else: gen.emit(ind, n.withTrailing((if n.mode.len > 0: n.mode else: "tantque") & " " & gen.condOf(n)))
    gen.genBody(n, "corps", ind)
    gen.endLineOf(n, "fintantque", ind)
  of nkFor:
    if reuse:
      for l in n.orig: gen.emitRaw(ind, l)
    else:
      let ins = n.dataInputs
      var a = gen.genInput(n, ins[0], 0)
      var z = gen.genInput(n, ins[1], 0)
      let s = if ins.len > 2: gen.genInput(n, ins[2], 0) else: ""
      if a.len == 0: a = "1"
      if z.len == 0: z = "1"
      let v = if n.text.strip.len > 0: n.text.strip else: "i"
      gen.emit(ind, n.withTrailing("pour " & v & " = " & a & " " & (if n.mode.len > 0: n.mode else: "a") & " " & z &
               (if s.len > 0: " pas " & s else: "")))
    gen.genBody(n, "corps", ind)
    gen.endLineOf(n, "suivant", ind)
  of nkForEach:
    if reuse:
      for l in n.orig: gen.emitRaw(ind, l)
    else:
      let v = if n.text.strip.len > 0: n.text.strip else: "v"
      gen.emit(ind, n.withTrailing("pour chaque " & v & " dans " & gen.condOf(n)))
    gen.genBody(n, "corps", ind)
    gen.endLineOf(n, "suivant", ind)
  of nkScan:
    if reuse:
      for l in n.orig: gen.emitRaw(ind, l)
    else:
      let c = gen.genInput(n, n.dataInputs[0], 0)
      gen.emit(ind, n.withTrailing("parcourir" & (if c.len > 0: " pour " & c else: "")))
    gen.genBody(n, "corps", ind)
    gen.endLineOf(n, "finparcourir", ind)
  of nkTry:
    if reuse:
      for l in n.orig: gen.emitRaw(ind, l)
    else: gen.emit(ind, n.withTrailing("essayer"))
    gen.genBody(n, "essayer", ind)
    let cp = n.findPin(pdOut, pkExec, "capturer")
    if n.text.strip.len > 0 or gen.g.followExec(n.id, cp) != nil or "capturer" in n.mids:
      gen.midLine(n, "capturer", "capturer" & (if n.text.strip.len > 0: " " & n.text.strip else: ""), ind,
                  reuse = not n.dirty)
      gen.genChain(n.id, cp, ind, 2)
    gen.endLineOf(n, "finessayer", ind)
  else: discard

proc genChain(gen: var Gen, fromId, fromPid: int, base, defRel: int) =
  var n = gen.g.followExec(fromId, fromPid)
  while n != nil and n.id notin gen.visited and n.isExecNode:
    gen.visited.incl n.id
    gen.genNode(n, base, defRel)
    let nx = n.execNext
    if nx < 0: break
    n = gen.g.followExec(n.id, nx)

proc generate*(g: Graph): string =
  # Code Lexis+ du graphe.
  var gen = Gen(g: g)
  for eid in g.entries:
    let e = g.node(eid)
    if e == nil: continue
    if e.mode == "principal":
      gen.genChain(e.id, e.execNext, 0, 0)
      continue
    if e.mode == "suite":
      for l in e.preamble: gen.outp.add l
      gen.genChain(e.id, e.execNext, 0, 0)
      continue
    for l in e.preamble: gen.outp.add l
    if e.preamble.len == 0 and gen.outp.len > 0 and e.orig.len == 0:
      gen.outp.add ""
    e.line = gen.outp.len
    if not e.dirty and e.orig.len > 0:
      for l in e.orig: gen.emitRaw(0, l)
    else:
      let params = e.text.strip
      gen.emit(0, e.withTrailing((if e.mode.len > 0: e.mode else: "procedure") & " " &
               (if e.title.strip.len > 0: e.title.strip else: "SANS_NOM") &
               (if params.len > 0: "(" & params & ")" else: "")))
    gen.genChain(e.id, e.execNext, 0, 2)
    if e.hasEnd: gen.emitRaw(0, e.endLine)
    elif e.orig.len == 0:
      # nouvelle procédure : « retourner » final si la chaîne ne s'arrête pas déjà sur un retour.
      var last: Node = nil
      var n = g.followExec(e.id, e.execNext)
      var guard = 0
      while n != nil and guard < 100000:
        last = n
        inc guard
        let nx = n.execNext
        if nx < 0: break
        n = g.followExec(n.id, nx)
      if last == nil or last.kind != nkReturn: gen.emit(0, "retourner")
  for l in g.epilogue: gen.outp.add l
  for t in g.tail: gen.outp.add t
  gen.outp.join("\n")

proc unreachable*(g: Graph): int =
  # Nombre d'instructions non reliées à une entrée (ignorées par la génération).
  let key = g.stamp * 7919 + g.nodes.len
  if g.lostStamp == key: return g.lostCount
  var gen = Gen(g: g)
  for eid in g.entries:
    let e = g.node(eid)
    if e != nil: gen.genChain(e.id, e.execNext, 0, 0)
  for n in g.nodes:
    if n.isExecNode and n.id notin gen.visited: inc result
  g.lostStamp = key
  g.lostCount = result

#
# mise en page automatique
#

proc dataSources(g: Graph, n: Node): seq[Node] =
  for p in n.pins:
    if p.dir != pdIn or p.kind != pkData: continue
    let li = g.linkInto(n.id, p.pid)
    if li < 0: continue
    let s = g.node(g.links[li].a)
    if s != nil and not s.isExecNode and s.kind != nkEntry: result.add s

type LayoutCtx = object
  placed: HashSet[int]

proc treeExtent(g: Graph, n: Node, ctx: var LayoutCtx, depth = 0): tuple[w, h: float] =
  # Largeur (à gauche du nœud) et hauteur de l'arbre de données qui l'alimente.
  if depth > 60: return (0.0, 0.0)
  var w = 0.0
  var h = 0.0
  for s in g.dataSources(n):
    if s.id in ctx.placed: continue
    let sub = g.treeExtent(s, ctx, depth + 1)
    w = max(w, s.w + GapData + sub.w)
    h += max(s.h, sub.h) + 12
  (w, max(0.0, h - 12))

proc placeTree(g: Graph, n: Node, ctx: var LayoutCtx, top: float, depth = 0) =
  # Place les sources de données de n à sa gauche, de haut en bas à partir de `top`.
  if depth > 60: return
  var y = top
  for s in g.dataSources(n):
    if s.id in ctx.placed: continue
    ctx.placed.incl s.id
    s.x = n.x - GapData - s.w
    s.y = y
    let sub = g.treeExtent(s, ctx, depth + 1)
    g.placeTree(s, ctx, y, depth + 1)
    y += max(s.h, sub.h) + 12

proc layoutChain(g: Graph, fromId, fromPid: int, x, y: float, ctx: var LayoutCtx): tuple[endX, bottom: float] =
  var cx = x
  var top = y
  var bottom = y
  var n = g.followExec(fromId, fromPid)
  var guard = 0
  while n != nil and n.id notin ctx.placed and guard < 100000:
    inc guard
    ctx.placed.incl n.id
    let ext = g.treeExtent(n, ctx)
    n.x = cx + ext.w + (if ext.w > 0: GapData else: 0.0)
    n.y = top
    let dataTop = top + n.headH + RowH + 10
    g.placeTree(n, ctx, dataTop)
    bottom = max(bottom, max(top + n.h, dataTop + ext.h))
    var right = n.x + n.w
    if n.isBlock:
      var by = top
      for p in n.pins:
        if p.dir != pdOut or p.kind != pkExec or p.name == "next": continue
        if g.followExec(n.id, p.pid) == nil: continue
        let r = g.layoutChain(n.id, p.pid, n.x + n.w + GapX, by, ctx)
        right = max(right, r.endX)
        by = max(by + RowH * 2, r.bottom + GapY)
        bottom = max(bottom, r.bottom)
    cx = right + GapX
    let nx = n.execNext
    if nx < 0: break
    n = g.followExec(n.id, nx)
    if n != nil and cx - x > WrapW:
      cx = x
      top = bottom + GapY * 2
  (cx - GapX, bottom)

proc layout*(g: Graph, tw: TextMeasure) =
  # Mise en page automatique : entrées les unes sous les autres, instructions
  # de gauche à droite, corps des blocs à droite et en dessous, données à gauche.
  for n in g.nodes: g.measure(n, tw)
  var ctx = LayoutCtx()
  var y = 0.0
  for eid in g.entries:
    let e = g.node(eid)
    if e == nil: continue
    ctx.placed.incl e.id
    e.x = 0
    e.y = y
    let r = g.layoutChain(e.id, e.execNext, e.w + GapX + 40, y, ctx)
    y = (if e.folded: y + e.h else: max(y + e.h, r.bottom)) + GapY * 3
  # nœuds restants (non reliés) : en bas.
  var x = 0.0
  for n in g.nodes:
    if n.id in ctx.placed: continue
    ctx.placed.incl n.id
    n.x = x
    n.y = y
    x += n.w + 40

proc keepPositions*(g, old: Graph): bool =
  # Reprend les positions des nœuds de même clé ; vrai si tous les nœuds ont été retrouvés.
  if old == nil: return false
  var pos = initTable[string, (float, float)]()
  var folds: HashSet[string]
  for n in old.nodes:
    if n.key.len > 0: pos[n.key] = (n.x, n.y)
    if n.folded and n.key.len > 0: folds.incl n.key
  result = true
  for n in g.nodes:
    if n.key in folds: n.folded = true
    if n.key.len > 0 and n.key in pos:
      (n.x, n.y) = pos[n.key]
    else: result = false

proc bounds*(g: Graph): tuple[x, y, w, h: float] =
  if g.nodes.len == 0: return (0.0, 0.0, 400.0, 300.0)
  var x0 = 1e18
  var y0 = 1e18
  var x1 = -1e18
  var y1 = -1e18
  for n in g.nodes:
    x0 = min(x0, n.x)
    y0 = min(y0, n.y)
    x1 = max(x1, n.x + n.w)
    y1 = max(y1, n.y + n.h)
  (x0, y0, x1 - x0, y1 - y0)

proc estimateWidth*(s: string): float {.gcsafe.} =
  # Mesure approchée (tests, absence de police).
  var n = 0
  for c in s:
    if (ord(c) and 0xC0) != 0x80: inc n
  float(n) * 7.2
