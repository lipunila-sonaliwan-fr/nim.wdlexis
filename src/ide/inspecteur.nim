# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - débogueur : consultation et modification des valeurs d'un programme en pause
#
# Partagé par l'atelier natif (ide/session.nim) et le paquet lexis (x:table,
# x:modifiertable : atelier écrit en Lexis+). Clefs de table codées en texte :
# s:texte, i:3, n:1.5, b:vrai.

import std/[strutils, algorithm]
import ../lexis/api

type
  EntryInfo* = object
    name*, value*, kind*, key*: string
    expandable*: bool

proc shortValue*(L: Interp, v: Value, depth = 0): string =
  case v.kind
  of vkStr:
    var s = v.s
    if s.len > 80: s = s[0 ..< 80] & "…"
    "\"" & s.replace("\n", "\\n") & "\""
  of vkTable:
    if depth > 0: return "{…}"
    var parts: seq[string]
    var n = 0
    for k, x in v.t.pairs:
      inc n
      if parts.len < 8:
        let ks = if k.kind == vkStr: k.s else: "[" & rawToString(k) & "]"
        parts.add ks & "=" & L.shortValue(x, depth + 1)
    "{" & parts.join(", ") & (if n > 8: ", … (" & $n & ")" else: "") & "}"
  of vkFunc:
    if v.f.native: "fonction intégrée " & v.f.name else: "@" & v.f.name
  of vkUser: rawToString(v)
  else: display(v)

proc kindName*(v: Value): string =
  case v.kind
  of vkInt: "entier"
  of vkNum: "décimal"
  else: typeName(v)

proc parseLike*(old: Value, text: string): (bool, Value, string) =
  # Nouvelle valeur du même type que l'ancienne (chaîne, entier ; aussi décimal et booléen).
  let t = text.strip
  case old.kind
  of vkStr:
    var s = text
    if s.len >= 2 and s[0] == '"' and s[^1] == '"': s = s[1 .. ^2].replace("\\n", "\n")
    (true, strV(s), "")
  of vkInt:
    try: (true, intV(parseBiggestInt(t)), "")
    except ValueError: (false, old, "entier attendu : « " & t & " »")
  of vkNum:
    try: (true, numV(parseFloat(t.replace(',', '.'))), "")
    except ValueError: (false, old, "nombre décimal attendu : « " & t & " »")
  of vkBool:
    case t.toLowerAscii
    of "vrai", "true", "1", "oui": (true, boolV(true), "")
    of "faux", "false", "0", "non": (true, boolV(false), "")
    else: (false, old, "vrai ou faux attendu")
  else: (false, old, "seules les chaînes, les entiers, les décimaux et les booléens se modifient ici")

proc parseLiteral*(text: string): (bool, Value, string) =
  ## Littéral Lexis+ : nul, vrai, faux, nombre, "chaîne", {} (table vide).
  let t = text.strip
  case t.toLowerAscii
  of "nul": return (true, nilV, "")
  of "vrai": return (true, boolV(true), "")
  of "faux": return (true, boolV(false), "")
  of "{}": return (true, tableV(newLTable()), "")
  else: discard
  if t.len >= 2 and t[0] == '"' and t[^1] == '"':
    return (true, strV(t[1 .. ^2].replace("\\n", "\n")), "")
  try: return (true, intV(parseBiggestInt(t)), "")
  except ValueError: discard
  try: return (true, numV(parseFloat(t.replace(',', '.'))), "")
  except ValueError: discard
  (false, nilV, "valeur attendue : nombre, \"chaîne\", vrai, faux, nul ou {}")

proc parseValue*(old: Value, text: string): (bool, Value, string) =
  # Même type que l'ancienne valeur si possible, sinon littéral (changement de type).
  let t = text.strip
  if old.kind in {vkStr, vkInt, vkNum, vkBool}:
    let isLit = t.toLowerAscii in ["nul", "{}"] or (old.kind != vkStr and t.len >= 2 and t[0] == '"')
    if not isLit:
      let (ok, v, msg) = parseLike(old, text)
      if ok: return (ok, v, msg)
  parseLiteral(text)

proc encodeKey*(k: Value): string =
  case k.kind
  of vkStr: "s:" & k.s
  of vkInt: "i:" & $k.i
  of vkNum: "n:" & $k.n
  of vkBool: "b:" & (if k.b: "vrai" else: "faux")
  else: ""

proc decodeKey*(s: string): Value =
  if s.len < 2: return nilV
  let v = s[2 .. ^1]
  case s[0]
  of 's': strV(v)
  of 'i': (try: intV(parseBiggestInt(v)) except ValueError: nilV)
  of 'n': (try: numV(parseFloat(v)) except ValueError: nilV)
  of 'b': boolV(v == "vrai")
  else: nilV

proc keyShown*(k: Value): string =
  if k.kind == vkStr: k.s.toLowerAscii else: "[" & rawToString(k) & "]"

proc rootValue*(L: Interp, c: Ctx, frameIdx: int, name, scope: string): (bool, Value) =
  if scope == "globale":
    for k, v in L.globals.pairs:
      if k.kind == vkStr and cmpIgnoreCase(k.s, name) == 0: return (true, v)
    return (false, nilV)
  var n = 0
  for i in countdown(c.frames.high, 0):
    let f = c.frames[i]
    if f.proto.isNil: continue
    if n == frameIdx:
      for j, cell in f.slots:
        if not cell.isNil and j < f.proto.slotNames.len and cmpIgnoreCase(f.proto.slotNames[j], name) == 0:
          return (true, cell.v)
      return (false, nilV)
    inc n
  (false, nilV)

proc walk*(root: Value, path: seq[string]): (bool, Value) =
  var v = root
  for k in path:
    if v.kind != vkTable: return (false, nilV)
    v = v.t.rawGet(decodeKey(k))
  (true, v)


proc tableEntries*(L: Interp, root: Value, path: seq[string]): (bool, seq[EntryInfo], string) =
  ## Entrées de la table root[path...] : partie liste puis clefs triées.
  let (ok, v) = walk(root, path)
  if not ok or v.kind != vkTable: return (false, @[], "ce n'est plus une table")
  var rows, others: seq[EntryInfo]
  for k, x in v.t.pairs:
    let e = EntryInfo(name: keyShown(k), value: L.shortValue(x), kind: kindName(x), key: encodeKey(k),
                      expandable: x.kind == vkTable)
    if k.kind == vkInt: rows.add e else: others.add e
  others.sort(proc (a, b: EntryInfo): int = cmp(a.name, b.name))
  (true, rows & others, "")

proc setEntry*(L: Interp, root: Value, path: seq[string], key, text: string, remove = false): (bool, string) =
  ## Modifie ou supprime l'entrée `key` (clef codée, ou saisie : entier -> clef numérique,
  ## "texte" exact, sinon nom en majuscules) de la table root[path...].
  let (ok, v) = walk(root, path)
  if not ok or v.kind != vkTable: return (false, "ce n'est plus une table")
  var k = decodeKey(key)
  if k.kind == vkNil or key.len < 2 or key[1] != ':':
    let kt = key.strip
    if kt.len == 0: return (false, "clef vide")
    try: k = intV(parseBiggestInt(kt))
    except ValueError:
      k = strV(if kt.len >= 2 and kt[0] == '"' and kt[^1] == '"': kt[1 .. ^2] else: cle(kt))
  if remove:
    v.t.rawSet(k, nilV)
    return (true, "")
  let (okv, nv, msg) = parseValue(v.t.rawGet(k), text)
  if not okv: return (false, msg)
  try: v.t.rawSet(k, nv)
  except ValueError as e: return (false, e.msg)
  (true, L.shortValue(nv))
