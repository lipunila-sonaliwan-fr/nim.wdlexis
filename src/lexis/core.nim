# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - interpréteur Lexis+ écrit en Nim
#   core : valeurs, tables, arbre syntaxique, état de l'interpréteur
#
# Les nombres sont des entiers 64 bits ou des flottants (affichés à la façon
# de Lexis+ : 5.0 s'écrit 5). Les tables ont une partie liste (index 1..n) et
# une partie dictionnaire qui conserve l'ordre d'insertion.
# Les identifiants de Lexis+ sont insensibles à la casse : t.nom et {nom = 1}
# utilisent la clef "NOM" ; t["nom"] est une clef exacte.

import std/[hashes, tables, sets, locks, atomics, math, strutils]
from std/unicode import toUpper

type
  ValueKind* = enum vkNil, vkBool, vkInt, vkNum, vkStr, vkTable, vkFunc, vkUser

  Value* = object
    case kind*: ValueKind
    of vkNil: discard
    of vkBool: b*: bool
    of vkInt: i*: int64
    of vkNum: n*: float64
    of vkStr: s*: string
    of vkTable: t*: LTable
    of vkFunc: f*: LFunc
    of vkUser: u*: LUser

  LTable* = ref object
    arr*: seq[Value]              # t[1..n]
    hkeys: seq[Value]
    hvals: seq[Value]
    hindex: Table[Value, int]
    hlive: int
    meta*: LTable

  Cell* = ref object              # variable locale d'un cadre d'appel.
    v*: Value

  NativeProc* = proc (L: Interp, args: seq[Value]): seq[Value] {.closure.}

  LFunc* = ref object
    name*: string
    case native*: bool
    of true:
      nfn*: NativeProc
    of false:
      proto*: Proto

  LUser* = ref object of RootObj  # base des données natives exposées à Lexis+.
    meta*: LTable
    tname*: string

  # arbre syntaxique

  BinOp* = enum
    opAdd = "+", opSub = "-", opMul = "*", opDiv = "/", opMod = "%", opPow = "^",
    opConcat = "..", opEq = "=", opNe = "<>", opLt = "<", opLe = "<=", opGt = ">",
    opGe = ">=", opIn = "$"

  ExprKind* = enum
    ekNil, ekTrue, ekFalse, ekInt, ekNum, ekStr,
    ekLocal,      # variable locale (case du cadre)
    ekName,       # nom résolu à l'exécution : champ de la zone courante, globale, procédure
    ekProcRef,    # @NOM : référence explicite à une procédure
    ekField,      # alias->champ
    ekIndex, ekCall, ekMethod, ekBin, ekAnd, ekOr, ekNot, ekNeg, ekLen, ekParen,
    ekTable, ekIif

  TItem* = object
    keyed*: bool
    key*, val*: Expr

  Expr* = ref object
    line*: int
    case kind*: ExprKind
    of ekInt: ival*: int64
    of ekNum: nval*: float64
    of ekStr: sval*: string
    of ekLocal:
      slot*: int
      vname*: string
    of ekName, ekProcRef: gname*: string
    of ekField:
      alias*, field*: string
    of ekIndex:
      obj*, key*: Expr
    of ekCall:
      fn*: Expr
      args*: seq[Expr]
    of ekMethod:
      mobj*: Expr
      mname*: string
      margs*: seq[Expr]
    of ekBin:
      op*: BinOp
      lhs*, rhs*: Expr
    of ekAnd, ekOr:
      a*, b*: Expr
    of ekNot, ekNeg, ekLen, ekParen:
      e*: Expr
    of ekTable: items*: seq[TItem]
    of ekIif:
      cnd*, yes*, no*: Expr
    else: discard

  StmtKind* = enum
    skLocal,      # locale x [= e]                 slots[0], e[0]?
    skAssign,     # cible = e                      e[0] cible, e[1] valeur
    skStore,      # stocker e dans c1, c2...       e[0] valeur, e[1..] cibles
    skCompound,   # cible += e / -= e              e[0] cible, e[1] valeur, op
    skCall,       # appel ou méthode               e[0]
    skPrint,      # ? e, ...  /  ?? e, ...         e, flag = saut de ligne
    skIf,         # si / sinonsi / sinon, faire cas  e = conditions, blocks (+ bloc sinon si flag)
    skWhile,      # tantque                        e[0], body
    skNumFor,     # pour i = a a b [pas c]         slots[0], e[0..2], body
    skForEach,    # pour chaque [k,] v dans e      slots (1 ou 2), e[0], body
    skBreak,      # sortir
    skContinue,   # boucler
    skReturn,     # retourner [e]
    skTry,        # essayer ... capturer [x] ... finessayer   blocks[0], blocks[1]?, slots[0]? (-1)
    skError,      # erreur e
    skParams,     # parametres a, b                slots
    skGlobal,     # globale x [= e]                name, e[0]?
    skFree,       # liberer x, y / supprimer table x   e = cibles
    skNewTable,   # nouvelle table x [= e]         e[0] cible, e[1]?
    skInsert,     # inserer v dans t [position p | clef k]   e[0] v, e[1] t, e[2]?, name
    skRemove,     # retirer [de] t [position p | clef k] [dans c]   e[0] t, e[1]?, e[2]?, name
    skAssoc,      # t:procedure NOM [comme m]      e[0] t, name, name2
    skSetMeta,    # fixermetatable t, m            e[0], e[1]
    skSql,        # sql e [avec p...] [dans c]     e[0] sql, e[1] cible ou nil, e[2..] paramètres
    skZone        # commandes de zones (utiliser, aller, parcourir...) : zk

  ZoneKind* = enum
    zkUse,        # utiliser [table [alias a] [ordre o] [filtre f]]   e[0..2] (nil possibles), name
    zkSelect,     # selectionner alias                e[0]
    zkClose,      # fermer [alias | tout]             name ("" courante, "*" toutes)
    zkGo,         # aller haut | bas | n              name ("haut"/"bas") ou e[0]
    zkSkip,       # sauter [n]                        e[0]?
    zkAppend,     # ajouter [vide | champ par v, ...] names, e
    zkReplace,    # remplacer champ par v, ...        names, e
    zkDelete,     # effacer
    zkLocate,     # localiser [pour] cond             e[0]
    zkContinue,   # continuer
    zkSeek,       # chercher v                        e[0]
    zkScan,       # parcourir [pour cond] ... finparcourir   e[0]?, body
    zkCount,      # compter [pour cond] dans cible    e[0]?, e[1]
    zkRefresh     # rafraichir

  Stmt* = ref object
    line*: int
    kind*: StmtKind
    zk*: ZoneKind
    e*: seq[Expr]
    slots*: seq[int]
    name*, name2*: string
    names*: seq[string]
    flag*: bool
    op*: BinOp
    body*: seq[Stmt]
    blocks*: seq[seq[Stmt]]

  Proto* = ref object
    name*, source*: string
    line*, lastLine*: int
    nparams*: int
    nslots*: int
    slotNames*: seq[string]
    usesArgs*: bool               # « parametres » : le cadre garde tous les arguments.
    body*: seq[Stmt]

  # exécution

  Frame* = ref object
    proto*: Proto
    fnName*: string
    slots*: seq[Cell]
    args*: seq[Value]
    line*: int
    ret*: Value

  Ctx* = ref object             # pile d'appels d'un fil (programme, tâche, événement).
    frames*: seq[Frame]
    co*: Coroutine

  Sem* = ref object             # sémaphore (non lié à un thread : utilisable en passage de relais).
    lock: Lock
    cond: Cond
    count: int

  CoStatus* = enum csSuspended = "suspendue", csRunning = "en cours",
                   csNormal = "normale", csDead = "terminee"

  Coroutine* = ref object of LUser
    L*: Interp
    fn*: Value
    status*: CoStatus
    ctx*: Ctx
    started*, killed*, errored*: bool
    transfer*: seq[Value]
    errVal*: Value
    resumeSem*, yieldSem*: Sem
    thr*: ptr Thread[Coroutine]

  StepMode* = enum smRun, smInto, smOver, smOut, smPause

  Debugger* = ref object
    lock*: Lock
    cond*: Cond
    active*: bool
    mode*: StepMode
    depth*: int
    cmd*: StepMode
    resumed*: bool
    breakpoints*: Table[string, HashSet[int]]
    lastLine*, lastDepth*: int
    lastSource*: string
    lastStmt*: pointer
    onPause*: proc (L: Interp, ctx: Ctx) {.closure.}

  Interp* = ref object
    globals*, loaded*, registry*: LTable
    builtins*: LTable                             # fonctions intégrées (appelées en dernier recours).
    procs*: Table[string, Value]                  # procédures et fonctions du programme (majuscules).
    autoload*: proc (L: Interp, name: string): Value {.closure.}   # paquet désigné par son nom
    output*: proc (s: string) {.closure.}
    errput*: proc (s: string) {.closure.}
    input*: proc (prompt: string): (bool, string) {.closure.}
    sourceProvider*: proc (path: string): (bool, string) {.closure.}
    onError*: proc (msg: string) {.closure.}     # erreurs dans les gestionnaires d'événements.
    searchDirs*: seq[string]
    dbg*: Debugger
    stopFlag*: Atomic[bool]
    parentStop*: ptr Atomic[bool]                 # arrêt demandé par un thread parent.
    gil*: Sem
    maxDepth*: int
    coroutines*: seq[Coroutine]
    ext*: Table[string, RootRef]                  # données privées des paquets.
    closers*: seq[proc () {.closure.}]
    scriptPath*: string
    args*: seq[string]
    startTime*: float
    hosted*: bool                                 # exécuté dans l'IDE (et non par le runtime).

  LexisError* = object of CatchableError
    value*: Value          # message sans position (ce que reçoit « capturer »)
    source*: string
    line*: int
    traceback*: string

  LexisStop* = object of CatchableError           # arrêt demandé, tâche fermée.

var curCtx* {.threadvar.}: Ctx

template nilV*: Value = Value(kind: vkNil)

proc cle*(name: string): string {.inline.} =
  ## Clef d'un identifiant Lexis+ (insensible à la casse) : en majuscules.
  toUpper(name)

#
# Sémaphore
#

proc newSem*(initial = 0): Sem =
  result = Sem(count: initial)
  initLock(result.lock)
  initCond(result.cond)

proc wait*(s: Sem) =
  acquire(s.lock)
  while s.count <= 0: wait(s.cond, s.lock)
  dec s.count
  release(s.lock)

proc post*(s: Sem) =
  acquire(s.lock)
  inc s.count
  signal(s.cond)
  release(s.lock)

#
# Constructeurs et prédicats
#

proc boolV*(b: bool): Value {.inline.} = Value(kind: vkBool, b: b)
proc intV*(i: int64): Value {.inline.} = Value(kind: vkInt, i: i)
proc intV*(i: int): Value {.inline.} = Value(kind: vkInt, i: int64(i))
proc numV*(n: float64): Value {.inline.} = Value(kind: vkNum, n: n)
proc strV*(s: string): Value {.inline.} = Value(kind: vkStr, s: s)
proc tableV*(t: LTable): Value {.inline.} =
  if t.isNil: nilV else: Value(kind: vkTable, t: t)
proc funcV*(f: LFunc): Value {.inline.} = Value(kind: vkFunc, f: f)
proc userV*(u: LUser): Value {.inline.} =
  if u.isNil: nilV else: Value(kind: vkUser, u: u)

proc fnV*(name: string, p: NativeProc): Value =
  Value(kind: vkFunc, f: LFunc(name: name, native: true, nfn: p))

proc isNil*(v: Value): bool {.inline.} = v.kind == vkNil
proc truthy*(v: Value): bool {.inline.} =
  ## Seuls nul et faux sont faux (0 et "" sont vrais).
  not (v.kind == vkNil or (v.kind == vkBool and not v.b))
proc isNumber*(v: Value): bool {.inline.} = v.kind in {vkInt, vkNum}

proc first*(vs: seq[Value]): Value {.inline.} =
  if vs.len > 0: vs[0] else: nilV

proc typeName*(v: Value): string =
  case v.kind
  of vkNil: "nul"
  of vkBool: "logique"
  of vkInt, vkNum: "nombre"
  of vkStr: "chaine"
  of vkTable: "table"
  of vkFunc: "procedure"
  of vkUser:
    if v.u of Coroutine: "tache" else: "objet"

#
# Égalité brute et hachage (clés de table)
#

proc rawEquals*(a, b: Value): bool =
  if a.kind != b.kind:
    if a.kind == vkInt and b.kind == vkNum: return float64(a.i) == b.n
    if a.kind == vkNum and b.kind == vkInt: return a.n == float64(b.i)
    return false
  case a.kind
  of vkNil: true
  of vkBool: a.b == b.b
  of vkInt: a.i == b.i
  of vkNum: a.n == b.n
  of vkStr: a.s == b.s
  of vkTable: a.t == b.t
  of vkFunc: a.f == b.f
  of vkUser: a.u == b.u

proc `==`*(a, b: Value): bool = rawEquals(a, b)

proc hash*(v: Value): Hash =
  case v.kind
  of vkNil: hash(0)
  of vkBool: hash(v.b)
  of vkInt: hash(v.i)
  of vkNum: hash(v.n)
  of vkStr: hash(v.s)
  of vkTable: hash(cast[pointer](v.t))
  of vkFunc: hash(cast[pointer](v.f))
  of vkUser: hash(cast[pointer](v.u))

#
# Tables
#

proc newLTable*(narr = 0): LTable =
  result = LTable(hindex: initTable[Value, int]())
  if narr > 0: result.arr = newSeqOfCap[Value](narr)

proc normKey(k: Value): Value {.inline.} =
  if k.kind == vkNum:
    let f = k.n
    if f == floor(f) and f >= -9.2e18 and f <= 9.2e18:
      return Value(kind: vkInt, i: int64(f))
  k

proc hget(t: LTable, k: Value): Value {.inline.} =
  let p = t.hindex.getOrDefault(k, -1)
  if p >= 0: t.hvals[p] else: nilV

proc compact(t: LTable) =
  var ks, vs: seq[Value]
  var idx = initTable[Value, int]()
  for i in 0 ..< t.hkeys.len:
    if t.hvals[i].kind != vkNil:
      idx[t.hkeys[i]] = ks.len
      ks.add t.hkeys[i]
      vs.add t.hvals[i]
  t.hkeys = ks
  t.hvals = vs
  t.hindex = idx
  t.hlive = ks.len

proc hset(t: LTable, k, v: Value) =
  let p = t.hindex.getOrDefault(k, -1)
  if p >= 0:
    if t.hvals[p].kind == vkNil and v.kind != vkNil: inc t.hlive
    elif t.hvals[p].kind != vkNil and v.kind == vkNil: dec t.hlive
    t.hvals[p] = v
  elif v.kind != vkNil:
    if t.hkeys.len > 16 and t.hkeys.len > 2 * t.hlive: t.compact()
    t.hindex[k] = t.hkeys.len
    t.hkeys.add k
    t.hvals.add v
    inc t.hlive

proc rawGet*(t: LTable, key: Value): Value =
  let k = normKey(key)
  case k.kind
  of vkInt:
    if k.i >= 1 and k.i <= t.arr.len: return t.arr[k.i - 1]
  of vkNil: return nilV
  else: discard
  t.hget(k)

proc rawGet*(t: LTable, key: string): Value {.inline.} = t.hget(strV(key))
proc rawGet*(t: LTable, key: int): Value {.inline.} = t.rawGet(intV(key))

proc rawSet*(t: LTable, key, v: Value) =
  let k = normKey(key)
  if k.kind == vkNil: raise newException(ValueError, "clef de table nulle")
  if k.kind == vkNum and k.n != k.n: raise newException(ValueError, "clef de table invalide (nan)")
  if k.kind == vkInt:
    let n = t.arr.len
    if k.i >= 1 and k.i <= n:
      if v.kind == vkNil and k.i < n:
        # trou au milieu de la liste : la suite passe dans le dictionnaire (#t = k - 1)
        for j in int(k.i) ..< n:
          if t.arr[j].kind != vkNil: t.hset(intV(j + 1), t.arr[j])
        t.arr.setLen(k.i - 1)
        return
      t.arr[k.i - 1] = v
      if v.kind == vkNil and k.i == n:
        while t.arr.len > 0 and t.arr[^1].kind == vkNil: t.arr.setLen(t.arr.len - 1)
      return
    if k.i == n + 1 and v.kind != vkNil:
      t.arr.add v
      if t.hlive > 0:
        t.hset(k, nilV)
        var nk = intV(k.i + 1)
        while true:
          let nv = t.hget(nk)
          if nv.kind == vkNil: break
          t.arr.add nv
          t.hset(nk, nilV)
          inc nk.i
      return
  t.hset(k, v)

proc rawSet*(t: LTable, key: string, v: Value) {.inline.} = t.hset(strV(key), v)
proc rawSet*(t: LTable, key: int, v: Value) {.inline.} = t.rawSet(intV(key), v)

proc rawLen*(t: LTable): int =
  result = t.arr.len
  if result == 0 and t.hlive > 0:
    # liste construite par la partie dictionnaire (t[1] affecté après t[2]).
    var i = 1
    while t.hget(intV(i)).kind != vkNil: inc i
    result = i - 1

proc count*(t: LTable): int =
  ## Nombre total d'éléments (liste et dictionnaire).
  var n = 0
  for v in t.arr:
    if v.kind != vkNil: inc n
  n + t.hlive

proc next*(t: LTable, key: Value, ok: var bool): (Value, Value) =
  ## Paire suivant `key` (nul = début). ok = false si la clef est invalide.
  ok = true
  var start = 0
  var k = normKey(key)
  if k.kind == vkNil:
    start = 0
  elif k.kind == vkInt and k.i >= 1 and k.i <= t.arr.len:
    start = int(k.i)
  else:
    let p = t.hindex.getOrDefault(k, -1)
    if p < 0:
      ok = false
      return (nilV, nilV)
    for j in p + 1 ..< t.hkeys.len:
      if t.hvals[j].kind != vkNil: return (t.hkeys[j], t.hvals[j])
    return (nilV, nilV)
  for i in start ..< t.arr.len:
    if t.arr[i].kind != vkNil: return (intV(i + 1), t.arr[i])
  for j in 0 ..< t.hkeys.len:
    if t.hvals[j].kind != vkNil: return (t.hkeys[j], t.hvals[j])
  (nilV, nilV)

iterator pairs*(t: LTable): (Value, Value) =
  for i in 0 ..< t.arr.len:
    if t.arr[i].kind != vkNil: yield (intV(i + 1), t.arr[i])
  var j = 0
  while j < t.hkeys.len:
    if t.hvals[j].kind != vkNil: yield (t.hkeys[j], t.hvals[j])
    inc j

proc snapshotPairs*(t: LTable): seq[(Value, Value)] =
  ## Copie des paires : le parcours tolère les modifications de la table.
  for k, v in t.pairs: result.add (k, v)

proc tableFrom*(vals: openArray[Value]): LTable =
  result = newLTable(vals.len)
  for v in vals: result.arr.add v
  while result.arr.len > 0 and result.arr[^1].kind == vkNil: result.arr.setLen(result.arr.len - 1)

proc insertAt*(t: LTable, pos: int, v: Value) =
  ## Insère v en position pos (1..n+1) en décalant la suite. Lève ValueError.
  if v.kind == vkNil: return
  let n = t.rawLen
  if pos < 1 or pos > n + 1:
    raise newException(ValueError, "position d'insertion hors limites : " & $pos)
  if t.arr.len == n:
    t.arr.insert(v, pos - 1)
    if t.hlive > 0:
      t.hset(intV(t.arr.len), nilV)
  else:
    var i = n
    while i >= pos:
      t.rawSet(intV(i + 1), t.rawGet(intV(i)))
      dec i
    t.rawSet(intV(pos), v)

proc removeAt*(t: LTable, pos: int): Value =
  ## Retire et renvoie l'élément en position pos (1..n), la suite est décalée.
  let n = t.rawLen
  if n == 0: return nilV
  if pos < 1 or pos > n:
    raise newException(ValueError, "position de retrait hors limites : " & $pos)
  result = t.rawGet(intV(pos))
  if t.arr.len == n:
    t.arr.delete(pos - 1)
  else:
    for i in pos ..< n: t.rawSet(intV(i), t.rawGet(intV(i + 1)))
    t.rawSet(intV(n), nilV)

proc copyTable*(t: LTable): LTable =
  ## Copie de premier niveau (avec la métatable).
  result = newLTable(t.arr.len)
  for k, v in t.pairs: result.rawSet(k, v)
  result.meta = t.meta

#
# Nombres
#

proc fmtNumber*(f: float64): string =
  ## Affichage Lexis+ : les flottants entiers s'écrivent sans décimale.
  if f != f: return "nan"
  if f == Inf: return "inf"
  if f == NegInf: return "-inf"
  if f == floor(f) and abs(f) < 1e15: return $int64(f)
  result = $f

proc str2number*(str: string): (bool, Value) =
  ## Conversion texte -> nombre : entiers, décimaux (point ou virgule décimale
  ## à la française « 12,5 »), exposants, hexadécimal 0x et binaire 0b.
  var s = str.strip()
  if s.len == 0: return (false, nilV)
  if ',' in s and '.' notin s and s.count(',') == 1: s = s.replace(',', '.')
  var i = 0
  var neg = false
  if s[i] in {'+', '-'}:
    neg = s[i] == '-'
    inc i
  if i + 1 < s.len and s[i] == '0' and s[i + 1] in {'x', 'X', 'b', 'B'}:
    let base = if s[i + 1] in {'x', 'X'}: 16 else: 2
    i += 2
    if i >= s.len: return (false, nilV)
    var m: uint64 = 0
    while i < s.len:
      let c = s[i]
      var d: int
      if c in Digits: d = ord(c) - ord('0')
      elif base == 16 and c in {'a'..'f'}: d = ord(c) - ord('a') + 10
      elif base == 16 and c in {'A'..'F'}: d = ord(c) - ord('A') + 10
      else: return (false, nilV)
      if d >= base: return (false, nilV)
      m = m * uint64(base) + uint64(d)
      inc i
    let v = cast[int64](m)
    return (true, intV(if neg: -v else: v))
  let body = s[i .. ^1]
  if body.len == 0: return (false, nilV)
  var isInt = true
  for c in body:
    if c notin Digits: isInt = false
  if isInt:
    try:
      let v = parseBiggestInt(body)
      return (true, intV(if neg: -v else: v))
    except ValueError:
      discard   # dépassement : flottant.
  for c in body:
    if c notin Digits + {'.', 'e', 'E', '+', '-'}: return (false, nilV)
  try:
    let f = parseFloat(body)
    (true, numV(if neg: -f else: f))
  except ValueError:
    (false, nilV)

proc toInteger*(v: Value, ok: var bool): int64 =
  ## Conversion exacte en entier (flottants à valeur entière, chaînes numériques).
  ok = true
  case v.kind
  of vkInt: v.i
  of vkNum:
    if v.n == floor(v.n) and v.n >= -9.2233720368547758e18 and v.n < 9.2233720368547758e18:
      int64(v.n)
    else:
      ok = false
      0
  of vkStr:
    let (good, n) = str2number(v.s)
    if good: toInteger(n, ok)
    else:
      ok = false
      0
  of vkBool: (if v.b: 1 else: 0)
  else:
    ok = false
    0

proc toFloat*(v: Value, ok: var bool): float64 =
  ok = true
  case v.kind
  of vkInt: float64(v.i)
  of vkNum: v.n
  of vkStr:
    let (good, n) = str2number(v.s)
    if not good:
      ok = false
      0.0
    elif n.kind == vkInt: float64(n.i)
    else: n.n
  of vkBool: (if v.b: 1.0 else: 0.0)
  else:
    ok = false
    0.0

proc rawToString*(v: Value): string =
  ## Conversion sans métaméthode (nul donne une chaîne vide, comme en Lexis+).
  case v.kind
  of vkNil: ""
  of vkBool: (if v.b: "vrai" else: "faux")
  of vkInt: $v.i
  of vkNum: fmtNumber(v.n)
  of vkStr: v.s
  of vkTable: "table: 0x" & toHex(cast[int](v.t), 12).toLowerAscii
  of vkFunc: "procedure: " & v.f.name
  of vkUser:
    (if v.u.tname.len > 0: v.u.tname else: typeName(v)) & ": 0x" &
      toHex(cast[int](v.u), 12).toLowerAscii

proc display*(v: Value): string =
  ## Forme lisible pour le débogueur et les messages (nul s'écrit « nul »).
  if v.kind == vkNil: "nul" else: rawToString(v)
