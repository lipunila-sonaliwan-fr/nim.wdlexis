# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - API pour écrire des paquets en Nim
#
# Un paquet est un module Nim qui s'enregistre à l'initialisation :
#
#   import ../lexis/api
#   proc ouvrirSalut(L: Interp): Value =
#     let m = newLib()
#     m.fn "bonjour", proc (L: Interp, a: seq[Value]): seq[Value] =
#       ret strV("Bonjour " & L.checkStr(a, 1, "bonjour"))
#     tableV(m)
#   registerPackage PackageDef(name: "salut", open: ouvrirSalut,
#     docs: docs("salut", ["salut.bonjour(nom)", "Renvoie une salutation."]))
#
# Côté Lexis+ :  s = paquet("salut")   puis   ? s.bonjour("Ada")
# (un paquet déclaré `global = true` est installé comme variable globale).
# Les noms (fonctions, méthodes, champs) sont enregistrés en majuscules :
# Lexis+ est insensible à la casse. Le même enregistrement alimente la
# complétion et l'aide de l'atelier.

import std/[strutils, tables]
import core, interp

export core, interp

type
  ApiDoc* = object
    name*: string        # nom de la fonction / méthode.
    owner*: string       # paquet (« pkg.f ») ou type (« obj:f »), "" = fonction intégrée.
    isMethod*: bool
    signature*: string
    doc*: string
    section*: string     # nom du paquet.

  PackageDef* = object
    name*: string
    description*: string
    global*: bool        # installé comme variable globale au démarrage.
    open*: proc (L: Interp): Value {.nimcall.}
    docs*: seq[ApiDoc]

var registeredPackages: seq[PackageDef]

proc registerPackage*(p: PackageDef) =
  ## À appeler à l'initialisation du module (thread principal).
  registeredPackages.add p

proc packages*(): seq[PackageDef] =
  {.cast(gcsafe).}:
    result = registeredPackages

proc docs*(section: string, items: openArray[string]): seq[ApiDoc] =
  ## Paires « signature », « description ». Le nom et le propriétaire sont
  ## déduits de la signature : f(...), pkg.f(...), obj:f(...).
  var i = 0
  while i + 1 < items.len:
    let sig = items[i]
    let head = sig.split({'(', '{'})[0].strip()
    var d = ApiDoc(signature: sig, doc: items[i + 1], section: section, name: head)
    let c = head.rfind(':')
    let dpos = head.rfind('.')
    if c >= 0:
      d.isMethod = true
      d.owner = head[0 ..< c]
      d.name = head[c + 1 .. ^1]
    elif dpos >= 0:
      d.owner = head[0 ..< dpos]
      d.name = head[dpos + 1 .. ^1]
    result.add d
    i += 2

proc allDocs*(): seq[ApiDoc] =
  for p in packages(): result.add p.docs

#
# Construction de bibliothèques
#

proc newLib*(): LTable = newLTable()

proc fn*(t: LTable, name: string, p: NativeProc) =
  t.rawSet(cle(name), fnV(name, p))

proc set*(t: LTable, name: string, v: Value) = t.rawSet(cle(name), v)
proc get*(t: LTable, name: string): Value = t.rawGet(cle(name))

proc ret*(vs: varargs[Value]): seq[Value] = @vs
proc retNone*(): seq[Value] = @[]

proc toV*(x: bool): Value = boolV(x)
proc toV*(x: int): Value = intV(x)
proc toV*(x: int64): Value = intV(x)
proc toV*(x: float): Value = numV(x)
proc toV*(x: string): Value = strV(x)
proc toV*(x: LTable): Value = tableV(x)
proc toV*(x: seq[string]): Value =
  let t = newLTable(x.len)
  for s in x: t.arr.add strV(s)
  tableV(t)

proc fail*(msg: string): seq[Value] =
  ## Échec d'une opération : erreur Lexis+ (interceptée par essayer ... capturer).
  rtError(msg)

proc record*(pairs: openArray[(string, Value)]): Value =
  ## Table de champs (noms en majuscules).
  let t = newLTable()
  for (k, v) in pairs: t.set(k, v)
  tableV(t)

#
# Vérification des arguments
#

proc arg*(a: seq[Value], i: int): Value {.inline.} =
  if i >= 1 and i <= a.len: a[i - 1] else: nilV

proc argError*(i: int, fname, msg: string) {.noreturn.} =
  rtError("argument n°" & $i & " invalide pour « " & fname & " » (" & msg & ")")

proc checkAny*(L: Interp, a: seq[Value], i: int, fname: string): Value =
  if i > a.len: argError(i, fname, "valeur attendue")
  a[i - 1]

proc checkStr*(L: Interp, a: seq[Value], i: int, fname: string): string =
  let v = arg(a, i)
  case v.kind
  of vkStr: v.s
  of vkInt, vkNum, vkBool: rawToString(v)
  of vkTable, vkUser: L.tostr(v)
  else: argError(i, fname, "chaîne attendue, " & typeName(v) & " reçu")

proc checkInt*(L: Interp, a: seq[Value], i: int, fname: string): int64 =
  let v = arg(a, i)
  var ok: bool
  result = toInteger(v, ok)
  if not ok:
    if v.kind == vkNum: argError(i, fname, "nombre entier attendu")
    argError(i, fname, "nombre attendu, " & typeName(v) & " reçu")

proc checkNum*(L: Interp, a: seq[Value], i: int, fname: string): float64 =
  let v = arg(a, i)
  var ok: bool
  result = toFloat(v, ok)
  if not ok: argError(i, fname, "nombre attendu, " & typeName(v) & " reçu")

proc checkTable*(L: Interp, a: seq[Value], i: int, fname: string): LTable =
  let v = arg(a, i)
  if v.kind != vkTable: argError(i, fname, "table attendue, " & typeName(v) & " reçu")
  v.t

proc checkFunc*(L: Interp, a: seq[Value], i: int, fname: string): Value =
  let v = arg(a, i)
  if not L.callable(v): argError(i, fname, "procédure attendue (@NOM), " & typeName(v) & " reçu")
  v

proc optStr*(L: Interp, a: seq[Value], i: int, fname: string, def: string): string =
  if arg(a, i).kind == vkNil: def else: L.checkStr(a, i, fname)

proc optInt*(L: Interp, a: seq[Value], i: int, fname: string, def: int64): int64 =
  if arg(a, i).kind == vkNil: def else: L.checkInt(a, i, fname)

proc optNum*(L: Interp, a: seq[Value], i: int, fname: string, def: float64): float64 =
  if arg(a, i).kind == vkNil: def else: L.checkNum(a, i, fname)

proc optBool*(a: seq[Value], i: int, def: bool): bool =
  let v = arg(a, i)
  if v.kind == vkNil: def else: truthy(v)

proc checkUser*[T: LUser](L: Interp, a: seq[Value], i: int, fname: string, typeName: string): T =
  let v = arg(a, i)
  if v.kind != vkUser or not (v.u of T):
    argError(i, fname, typeName & " attendu (appelez la méthode avec « : »)")
  T(v.u)

# champs d'une table d'options (noms insensibles à la casse)

proc optField*(t: LTable, name: string, def: string): string =
  if t.isNil: return def
  let v = t.rawGet(cle(name))
  if v.kind in {vkStr, vkInt, vkNum, vkBool}: rawToString(v) else: def

proc optField*(t: LTable, name: string, def: int): int =
  if t.isNil: return def
  var ok: bool
  let n = toInteger(t.rawGet(cle(name)), ok)
  if ok: int(n) else: def

proc optField*(t: LTable, name: string, def: float): float =
  if t.isNil: return def
  var ok: bool
  let n = toFloat(t.rawGet(cle(name)), ok)
  if ok: n else: def

proc optField*(t: LTable, name: string, def: bool): bool =
  if t.isNil: return def
  let v = t.rawGet(cle(name))
  if v.kind == vkNil: def else: truthy(v)

proc field*(t: LTable, name: string): Value =
  if t.isNil: nilV else: t.rawGet(cle(name))

#
# Types natifs (objets)
#

proc userMeta*(L: Interp, tname: string, methods: LTable): LTable =
  ## Métatable partagée d'un type natif : __index = méthodes, __name = tname.
  let key = "meta:" & tname
  let existing = L.registry.rawGet(key)
  if existing.kind == vkTable: return existing.t
  result = newLTable()
  result.set("__index", tableV(methods))
  result.set("__name", strV(tname))
  L.registry.rawSet(key, tableV(result))

proc wrap*(L: Interp, u: LUser, tname: string, methods: LTable): Value =
  u.tname = tname
  u.meta = L.userMeta(tname, methods)
  userV(u)

#
# Ouverture des paquets
#

proc openPackage*(L: Interp, name: string): Value =
  let n = name.toLowerAscii
  let cached = L.loaded.rawGet(n)
  if cached.kind != vkNil: return cached
  for p in packages():
    if p.name == n:
      result = p.open(L)
      if result.kind == vkNil: result = boolV(true)
      L.loaded.rawSet(n, result)
      return
  nilV

proc openGlobals*(L: Interp) =
  ## Installe les paquets déclarés globaux (fonctions intégrées, es, systeme...) ;
  ## les autres paquets s'ouvrent à la première utilisation de leur nom
  ## (fichier.lire(...)) ou par paquet("nom").
  L.autoload = proc (L: Interp, name: string): Value =
    let n = name.toLowerAscii
    for p in packages():
      if p.name == n and p.name != "base": return L.openPackage(n)
    nilV
  for p in packages():
    if p.global:
      let v = L.openPackage(p.name)
      if v.kind == vkTable and p.name != "base":
        L.globals.rawSet(cle(p.name), v)
