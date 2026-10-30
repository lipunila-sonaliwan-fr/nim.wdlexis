# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# Tests du modèle blueprint (sans interface) : aller-retour code -> graphe -> code
# sur tous les .prg des exemples, puis régénération forcée (tous les nœuds
# modifiés) vérifiée par l'analyseur de l'interpréteur.
#   nim c -r -d:release tests/t_blueprint.nim
import std/[os, strutils, algorithm]
import ../src/ide/bpmodel
import ../src/lexis/[parser, lexer, core]

proc tokensOf(src: string): seq[string] =
  for t in tokenize(src, "x"):
    if t.kind == tkEOL: result.add "⏎"
    elif t.kind != tkEOF: result.add (if t.kind == tkName: t.up else: t.text)

proc normalize(ts: seq[string]): seq[string] =
  # parenthèses et « sinon si » peuvent changer à la régénération.
  var i = 0
  while i < ts.len:
    let t = ts[i]
    if t in ["(", ")"]:
      inc i
      continue
    if t == "SINON" and i + 1 < ts.len and ts[i + 1] == "SI":
      result.add "SINONSI"
      i += 2
      continue
    if t == "⏎" and result.len > 0 and result[^1] == "⏎":
      inc i
      continue
    result.add t
    inc i

proc dumpE(e: Expr): string =
  if e == nil: return "∅"
  case e.kind
  of ekParen: dumpE(e.e)
  of ekInt: "i" & $e.ival
  of ekNum: "n" & $e.nval
  of ekStr: "s" & e.sval.escape
  of ekLocal: "L" & e.vname.toUpperAscii
  of ekName, ekProcRef: $e.kind & ":" & e.gname
  of ekField: "F" & e.alias & "." & e.field
  of ekIndex: "[" & dumpE(e.obj) & " " & dumpE(e.key) & "]"
  of ekCall:
    var a: seq[string]
    for x in e.args: a.add dumpE(x)
    "call(" & dumpE(e.fn) & "|" & a.join(",") & ")"
  of ekMethod:
    var a: seq[string]
    for x in e.margs: a.add dumpE(x)
    "meth(" & dumpE(e.mobj) & ":" & e.mname & "|" & a.join(",") & ")"
  of ekBin: "(" & dumpE(e.lhs) & " " & $e.op & " " & dumpE(e.rhs) & ")"
  of ekAnd, ekOr: "(" & dumpE(e.a) & " " & $e.kind & " " & dumpE(e.b) & ")"
  of ekNot, ekNeg, ekLen: $e.kind & "(" & dumpE(e.e) & ")"
  of ekTable:
    var a: seq[string]
    for it in e.items: a.add (if it.keyed: dumpE(it.key) & "=" else: "") & dumpE(it.val)
    "{" & a.join(",") & "}"
  of ekIif: "iif(" & dumpE(e.cnd) & "," & dumpE(e.yes) & "," & dumpE(e.no) & ")"
  else: $e.kind

proc dumpS(ss: seq[Stmt], ind = 0): string =
  for s in ss:
    result.add repeat(' ', ind) & $s.kind & (if s.kind == skZone: "/" & $s.zk else: "") &
      " f=" & $s.flag & " op=" & $s.op & " n=" & s.name & "/" & s.name2 & " " & s.names.join(",") &
      " slots=" & $s.slots.len & " :"
    for e in s.e: result.add " " & dumpE(e)
    result.add "\n"
    if s.body.len > 0: result.add dumpS(s.body, ind + 2)
    for b in s.blocks:
      result.add repeat(' ', ind + 1) & "|\n" & dumpS(b, ind + 2)

proc dumpP(p: Program): string =
  result = dumpS(p.main.body)
  for pr in p.procs:
    result.add "PROC " & pr.name & " " & $pr.nparams & "\n" & dumpS(pr.body, 2)

var files: seq[string]
let root = currentSourcePath().parentDir.parentDir
for f in walkDirRec(root / "exemples"):
  if f.endsWith(".prg"): files.add f
for f in walkDirRec(root / "tests"):
  if f.endsWith(".prg"): files.add f
files.sort()
var okSame, okForced, failed, structErr, total = 0
for f in files:
  let src = readFile(f).replace("\r\n", "\n").replace("\t", "  ")
  inc total
  let g = parseGraph(src)
  if g.error.len > 0:
    # le vrai analyseur doit aussi refuser ce fichier
    var realOk = true
    try: discard parseChunk(src, f)
    except SyntaxError: realOk = false
    if realOk:
      echo "ERREUR STRUCTURE (accepté par l'interpréteur) ", f, " : ", g.error
      inc failed
    else: inc structErr
    continue
  let back = generate(g)
  if back == src: inc okSame
  else:
    inc failed
    echo "DIFF identité ", f
    let a = src.split('\n')
    let b = back.split('\n')
    for i in 0 ..< max(a.len, b.len):
      let x = if i < a.len: a[i] else: "<fin>"
      let y = if i < b.len: b[i] else: "<fin>"
      if x != y:
        echo "  ligne ", i + 1, "\n   - ", x, "\n   + ", y
        break
    continue
  # régénération forcée
  for n in g.nodes: n.dirty = true
  let forced = generate(g)
  var realOk = true
  var msg = ""
  try: discard parseChunk(src, f)
  except SyntaxError as e:
    realOk = false
  if realOk:
    try:
      let da = dumpP(parseChunk(src, f))
      let db = dumpP(parseChunk(forced, f))
      if da == db: inc okForced
      else:
        inc failed
        echo "DIFF AST (forcé) ", f
        let la = da.split('\n')
        let lb = db.split('\n')
        for i in 0 ..< max(la.len, lb.len):
          let x = if i < la.len: la[i] else: "<fin>"
          let y = if i < lb.len: lb[i] else: "<fin>"
          if x != y:
            echo "  - ", x, "\n  + ", y
            break
        writeFile("/tmp/claude-0/scratch/forced_fail.prg", forced)
    except SyntaxError as e:
      inc failed
      msg = e.msg
      echo "ÉCHEC analyse (forcé) ", f, " : ", msg
      writeFile("/tmp/claude-0/scratch/forced_fail.prg", forced)
  else: inc okForced
  # mise en page
  g.layout(proc (s: string): float = estimateWidth(s))
echo "fichiers : ", total, "  identiques : ", okSame, "  forcés valides : ", okForced,
     "  erreurs de structure (refusés aussi par l'interpréteur) : ", structErr, "  échecs : ", failed
if failed > 0: quit 1

# ---------------------------------------------------------------- éditions
proc check(name, got, want: string) =
  if got != want:
    echo "ÉCHEC ", name, "\n--- obtenu\n", got, "\n--- attendu\n", want
    quit 1
  try: discard parseChunk(got, name)
  except SyntaxError as e:
    echo "ÉCHEC analyse ", name, " : ", e.msg
    quit 1

block:
  # insertion d'une affectation après un affichage
  let g = parseGraph("? \"a\"\n? \"b\"\n")
  let main = g.node(g.mainId)
  let p1 = g.followExec(main.id, main.execNext)
  let p2 = g.followExec(p1.id, p1.execNext)
  let a = g.makeNode(nkAssign, text = "x")
  a.pins[a.pinIndex(a.dataInputs[0])].default = "5"
  g.connect(p1.id, p1.execNext, a.id, a.execIn)
  g.connect(a.id, a.execNext, p2.id, p2.execIn)
  check("insertion", generate(g), "? \"a\"\nx = 5\n? \"b\"\n")
  # suppression : la chaîne se referme
  g.removeNode(a.id)
  check("suppression", generate(g), "? \"a\"\n? \"b\"\n")

block:
  # valeur modifiée sur une broche : seule la ligne change (commentaire conservé)
  let g = parseGraph("x = 1 + 2   && somme\n? x\n")
  var op: Node
  for n in g.nodes:
    if n.kind == nkOp: op = n
  op.pins[0].default = "10"
  op.dirty = true
  check("valeur", generate(g), "x = 10 + 2  && somme\n? x\n")

block:
  # priorités : (a + b) * c reconstruit avec parenthèses
  let g = newGraph()
  let main = g.makeNode(nkEntry, mode = "principal")
  g.mainId = main.id
  g.entries.add main.id
  let pr = g.makeNode(nkPrint)
  g.connect(main.id, main.execNext, pr.id, pr.execIn)
  let mul = g.makeNode(nkOp, title = "*")
  let add = g.makeNode(nkOp, title = "+")
  add.pins[0].default = "a"
  add.pins[1].default = "b"
  mul.pins[1].default = "c"
  g.connect(add.id, add.dataOut, mul.id, mul.pins[0].pid)
  g.connect(mul.id, mul.dataOut, pr.id, pr.dataInputs[0])
  check("priorités", generate(g), "? (a + b) * c")
  # appel : instruction puis expression
  let c = g.makeNode(nkCall, title = "majuscule", argCount = 1)
  c.pins[0].default = "\"x\""
  g.connect(c.id, c.dataOut, pr.id, pr.dataInputs[0])
  check("appel", generate(g), "? majuscule(\"x\")")
  g.setStatement(c, true)
  g.connect(pr.id, pr.execNext, c.id, c.execIn)
  check("instruction", generate(g), "?\nmajuscule(\"x\")")

block:
  # nouvelle procédure avec paramètre relié
  let g = parseGraph("SALUER(\"Ada\")\n")
  let e = g.makeNode(nkEntry, title = "SALUER", text = "qui")
  g.entries.add e.id
  let pr = g.makeNode(nkPrint, argCount = 2)
  pr.pins[pr.pinIndex(pr.dataInputs[0])].default = "\"Bonjour\""
  var qui = -1
  for p in e.pins:
    if p.varOut: qui = p.pid
  g.connect(e.id, qui, pr.id, pr.dataInputs[1])
  g.connect(e.id, e.execNext, pr.id, pr.execIn)
  check("procédure", generate(g), "SALUER(\"Ada\")\n\nprocedure SALUER(qui)\n  ? \"Bonjour\", qui\nretourner\n")

block:
  # si / sinonsi / sinon : édition d'une condition de sinonsi
  let src = "si n > 2\n  ? \"a\"\nsinonsi n > 1   && deux\n  ? \"b\"\nsinon\n  ? \"c\"\nfinsi\n"
  let g = parseGraph(src)
  check("si identité", generate(g), src)
  for n in g.nodes:
    if n.kind == nkIf and n.elseIf:
      for p in g.nodes:
        if p.kind == nkOp and g.links[g.linkFrom(p.id, p.dataOut)].b == n.id:
          p.pins[1].default = "0"
          p.dirty = true
  check("sinonsi", generate(g), "si n > 2\n  ? \"a\"\nsinonsi n > 0  && deux\n  ? \"b\"\nsinon\n  ? \"c\"\nfinsi\n")

block:
  # variable de boucle câblée : la renommer renomme ses usages
  let g = parseGraph("pour i = 1 a 3   && boucle\n  ? i * 2, \"x\"\nsuivant\n")
  var f: Node
  for n in g.nodes:
    if n.kind == nkFor: f = n
  var wired = 0
  for l in g.links:
    if l.a == f.id and f.pins[f.pinIndex(l.ap)].varOut: inc wired
  if wired != 1:
    echo "ÉCHEC câblage de la variable de boucle : ", wired
    quit 1
  f.text = "k"
  g.setVarOuts(f, @["k"])
  f.dirty = true
  check("variable de boucle", generate(g), "pour k = 1 a 3  && boucle\n  ? k * 2, \"x\"\nsuivant\n")

block:
  # appartenance, pliage, appels
  let g = parseGraph("A()\n\nprocedure A\n  ? 1 + 2\n  B(@C)\nretourner\n\nprocedure B(x)\nretourner\n")
  var a, b: Node
  for id in g.entries:
    let e = g.node(id)
    if e.title == "A": a = e
    if e.title == "B": b = e
  var calls: seq[string]
  var hiddenBefore = 0
  for n in g.nodes:
    if g.ownerOf(n.id) == a.id and n.kind != nkEntry:
      calls.add n.callNames
      if g.isHidden(n): inc hiddenBefore
  if calls != @["B", "C"] or hiddenBefore != 0:
    echo "ÉCHEC appels / appartenance : ", calls
    quit 1
  a.folded = true
  var hidden = 0
  for n in g.nodes:
    if g.isHidden(n): inc hidden
  if hidden != g.reachableFrom(a.id).len - 1 or hidden < 4:
    echo "ÉCHEC pliage : ", hidden
    quit 1

echo "éditions : OK"
