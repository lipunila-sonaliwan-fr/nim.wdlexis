# Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr
#   wdlexis+ - fonctions intégrées de Lexis+
#
# Les mêmes que sur le serveur wdGestion V (chaînes, nombres, types, dates,
# tables, JSON, SQL, sécurité, zones), plus quelques fonctions propres au
# poste de travail : paquet(), saisir(), ouvrirbase(), fermerbase(), base(),
# fonctions trigonométriques et logarithmes.

import std/[strutils, math, json, times, uri, algorithm, random, sysrand, tables]
from std/unicode import Rune, toUpper, toLower, runeLen, toRunes, `$`
import api, zones, crypto

#
# Outils
#

proc tostrArg(L: Interp, a: seq[Value], i: int): string = L.tostr(arg(a, i))

proc numOf(L: Interp, a: seq[Value], i: int, fname: string): Value =
  var ok: bool
  result = toNumber(arg(a, i), ok)
  if not ok: argError(i, fname, "nombre attendu, " & typeName(arg(a, i)) & " reçu")

proc fl(v: Value): float64 {.inline.} = (if v.kind == vkInt: float64(v.i) else: v.n)

proc numResult(f: float64): Value =
  if f == floor(f) and abs(f) < 9e15: intV(int64(f)) else: numV(f)

proc tableArg(L: Interp, a: seq[Value], i: int, fname: string): LTable = L.checkTable(a, i, fname)

proc toJsonNode*(L: Interp, v: Value, depth = 0): JsonNode =
  ## Lexis+ -> JSON : une table à index 1..n devient un tableau, sinon un objet.
  if depth > 100: rtError("json : structure trop profonde (cycle ?)")
  case v.kind
  of vkNil: newJNull()
  of vkBool: newJBool(v.b)
  of vkInt: newJInt(v.i)
  of vkNum:
    if v.n != v.n or v.n == Inf or v.n == NegInf: rtError("json : nombre non représentable")
    if v.n == floor(v.n) and abs(v.n) < 9e15: newJInt(int64(v.n)) else: newJFloat(v.n)
  of vkStr: newJString(v.s)
  of vkTable:
    let n = v.t.rawLen
    if n > 0 and v.t.count == n:
      var r = newJArray()
      for i in 1 .. n: r.add L.toJsonNode(v.t.rawGet(intV(i)), depth + 1)
      r
    else:
      var r = newJObject()
      for k, x in v.t.pairs: r[rawToString(k)] = L.toJsonNode(x, depth + 1)
      r
  of vkFunc: newJString("procedure:" & v.f.name)
  of vkUser:
    if v.u.tname == "json.nul": newJNull()
    else: rtError("json : objet " & v.u.tname & " non représentable")

proc fromJsonNode*(j: JsonNode, upperKeys = true): Value =
  ## JSON -> Lexis+ ; les clefs d'objets sont mises en majuscules (comme les identifiants).
  case j.kind
  of JNull: nilV
  of JBool: boolV(j.getBool)
  of JInt: intV(j.getBiggestInt)
  of JFloat: numV(j.getFloat)
  of JString: strV(j.getStr)
  of JArray:
    let t = newLTable(j.len)
    for x in j.elems:
      let v = fromJsonNode(x, upperKeys)
      if v.kind != vkNil: t.arr.add v
    tableV(t)
  of JObject:
    let t = newLTable()
    for k, x in j.fields:
      let v = fromJsonNode(x, upperKeys)
      if v.kind != vkNil: t.rawSet(strV(if upperKeys: toUpper(k) else: k), v)
    tableV(t)

proc htmlEscape(s: string): string =
  result = newStringOfCap(s.len + 8)
  for c in s:
    case c
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    of '\'': result.add "&#39;"
    else: result.add c

var rng {.threadvar.}: Rand
var rngReady {.threadvar.}: bool

proc theRng(): var Rand =
  if not rngReady:
    var seed: array[8, byte]
    discard urandom(seed)
    rng = initRand(cast[int64](seed))
    rngReady = true
  rng

proc uuid4(): string =
  var b: array[16, byte]
  discard urandom(b)
  b[6] = (b[6] and 0x0F) or 0x40
  b[8] = (b[8] and 0x3F) or 0x80
  let h = versHex(b)
  h[0 ..< 8] & "-" & h[8 ..< 12] & "-" & h[12 ..< 16] & "-" & h[16 ..< 20] & "-" & h[20 ..< 32]

proc zoneArg(L: Interp, a: seq[Value], i: int): Zone =
  try:
    if arg(a, i).kind != vkNil: L.zoneByAlias(L.tostr(arg(a, i)))
    else: L.requireZone
  except ZoneError as e: rtError(e.msg)

#
# Enregistrement
#

proc openBase(L: Interp): Value =
  let b = L.builtins
  template def(name: string, body: untyped) {.dirty.} =
    b.fn name, proc (L: Interp, a: seq[Value]): seq[Value] = @[body]

  # ----------------------------------------------------------- chaînes
  def "majuscule": strV(toUpper(L.tostrArg(a, 1)))
  def "minuscule": strV(toLower(L.tostrArg(a, 1)))
  def "rogner": strV(L.tostrArg(a, 1).strip)
  def "rognerg": strV(L.tostrArg(a, 1).strip(trailing = false))
  def "rognerd": strV(L.tostrArg(a, 1).strip(leading = false))
  def "longueur":
    let v = arg(a, 1)
    if v.kind == vkTable: intV(v.t.rawLen) else: intV(L.tostr(v).runeLen)
  def "souschaine":
    let r = L.tostrArg(a, 1).toRunes
    let d = max(1, int(L.checkInt(a, 2, "souschaine")))
    let n = int(L.optInt(a, 3, "souschaine", r.len))
    if d > r.len or n <= 0: strV("") else: strV($r[d - 1 ..< min(r.len, d - 1 + n)])
  def "gauche":
    let r = L.tostrArg(a, 1).toRunes
    strV($r[0 ..< clamp(int(L.checkInt(a, 2, "gauche")), 0, r.len)])
  def "droite":
    let r = L.tostrArg(a, 1).toRunes
    let n = clamp(int(L.checkInt(a, 2, "droite")), 0, r.len)
    strV($r[r.len - n ..< r.len])
  def "position":
    let s = L.tostrArg(a, 2)
    let i = s.find(L.tostrArg(a, 1))
    if i < 0: intV(0) else: intV(s[0 ..< i].runeLen + 1)
  let chaineFn = proc (L: Interp, a: seq[Value]): seq[Value] =
    let v = arg(a, 1)
    if v.kind notin {vkInt, vkNum} or a.len < 2: return @[strV(L.tostr(v))]
    let width = int(L.checkInt(a, 2, "chaine"))
    let dec = int(L.optInt(a, 3, "chaine", 0))
    let t = if dec <= 0: $int64(round(fl(v))) else: formatFloat(fl(v), ffDecimal, dec)
    @[strV(t.align(width))]
  b.fn "chaine", chaineFn
  b.fn "texte", chaineFn
  def "valeur":
    var ok: bool
    let n = toNumber(arg(a, 1), ok)
    if ok and arg(a, 1).kind != vkBool: n else: intV(0)
  def "nombre":
    var ok: bool
    let n = toNumber(arg(a, 1), ok)
    if ok and arg(a, 1).kind != vkBool: n else: nilV
  def "espace": strV(spaces(max(0, int(L.checkInt(a, 1, "espace")))))
  def "repliquer": strV(L.tostrArg(a, 1).repeat(max(0, int(L.checkInt(a, 2, "repliquer")))))
  def "remplacertexte":
    if a.len < 3: rtError("remplacertexte : 3 arguments attendus")
    let old = L.tostrArg(a, 2)
    if old.len == 0: strV(L.tostrArg(a, 1)) else: strV(L.tostrArg(a, 1).replace(old, L.tostrArg(a, 3)))
  def "contient":
    let v = arg(a, 1)
    if v.kind == vkTable:
      var found = false
      for _, x in v.t.pairs:
        if L.equals(x, arg(a, 2)):
          found = true
          break
      boolV(found)
    else: boolV(L.tostr(v).contains(L.tostrArg(a, 2)))
  def "commencepar": boolV(L.tostrArg(a, 1).startsWith(L.tostrArg(a, 2)))
  def "finitpar": boolV(L.tostrArg(a, 1).endsWith(L.tostrArg(a, 2)))
  def "decouper":
    let t = newLTable()
    let s = L.tostrArg(a, 1)
    let sep = if a.len > 1 and arg(a, 2).kind != vkNil: L.tostrArg(a, 2) else: ","
    if s.len > 0:
      for p in (if sep == "": @[s] else: s.split(sep)): t.arr.add strV(p)
    tableV(t)
  def "joindre":
    let t = L.tableArg(a, 1, "joindre")
    var parts: seq[string]
    for i in 1 .. t.rawLen: parts.add L.tostr(t.rawGet(intV(i)))
    strV(parts.join(if a.len > 1: L.tostrArg(a, 2) else: ""))
  def "html": strV(htmlEscape(L.tostrArg(a, 1)))
  def "url": strV(encodeUrl(L.tostrArg(a, 1), usePlus = false))
  def "car":
    var s = ""
    for i in 1 .. a.len:
      let c = int(L.checkInt(a, i, "car"))
      if c < 0 or c > 0x10FFFF: argError(i, "car", "code de caractère invalide")
      s.add $Rune(c)
    strV(s)
  def "code":
    let r = L.tostrArg(a, 1).toRunes
    let i = int(L.optInt(a, 2, "code", 1))
    if i < 1 or i > r.len: nilV else: intV(int(r[i - 1]))

  # ----------------------------------------------------------- nombres
  def "abs":
    let x = L.numOf(a, 1, "abs")
    if x.kind == vkInt: intV(abs(x.i)) else: numV(abs(x.n))
  def "entier": numResult(trunc(fl(L.numOf(a, 1, "entier"))))
  def "arrondi":
    let d = L.optNum(a, 2, "arrondi", 0)
    let p = pow(10.0, d)
    let r = round(fl(L.numOf(a, 1, "arrondi")) * p) / p
    if d <= 0: numResult(r) else: numV(r)
  def "plancher": numResult(floor(fl(L.numOf(a, 1, "plancher"))))
  def "plafond": numResult(ceil(fl(L.numOf(a, 1, "plafond"))))
  def "racine":
    let x = fl(L.numOf(a, 1, "racine"))
    if x < 0: rtError("racine d'un nombre négatif")
    numResult(sqrt(x))
  def "mod":
    L.arith(opMod, L.numOf(a, 1, "mod"), L.numOf(a, 2, "mod"))
  let minmax = proc (isMax: bool): NativeProc =
    result = proc (L: Interp, a: seq[Value]): seq[Value] =
      if a.len == 0: rtError((if isMax: "max" else: "min") & " : au moins un argument attendu")
      var r = a[0]
      for i in 1 ..< a.len:
        if (isMax and L.lessThan(r, a[i], false, ">")) or (not isMax and L.lessThan(a[i], r, false, "<")): r = a[i]
      @[r]
  b.fn "max", minmax(true)
  b.fn "min", minmax(false)
  def "aleatoire":
    if a.len == 0 or arg(a, 1).kind == vkNil: numV(theRng().rand(1.0))
    else: intV(theRng().rand(max(1, int(L.checkInt(a, 1, "aleatoire"))) - 1) + 1)
  def "sin": numV(sin(fl(L.numOf(a, 1, "sin"))))
  def "cos": numV(cos(fl(L.numOf(a, 1, "cos"))))
  def "tan": numV(tan(fl(L.numOf(a, 1, "tan"))))
  def "asin": numV(arcsin(fl(L.numOf(a, 1, "asin"))))
  def "acos": numV(arccos(fl(L.numOf(a, 1, "acos"))))
  def "atan":
    if a.len > 1: numV(arctan2(fl(L.numOf(a, 1, "atan")), fl(L.numOf(a, 2, "atan"))))
    else: numV(arctan(fl(L.numOf(a, 1, "atan"))))
  def "exp": numV(exp(fl(L.numOf(a, 1, "exp"))))
  def "log":
    let x = fl(L.numOf(a, 1, "log"))
    if a.len > 1: numV(ln(x) / ln(fl(L.numOf(a, 2, "log")))) else: numV(ln(x))
  def "pi": numV(PI)

  # ----------------------------------------------------------- types
  def "type": strV(typeName(arg(a, 1)))
  def "estnul": boolV(arg(a, 1).kind == vkNil)
  def "vide":
    let v = arg(a, 1)
    case v.kind
    of vkNil: boolV(true)
    of vkBool: boolV(not v.b)
    of vkInt: boolV(v.i == 0)
    of vkNum: boolV(v.n == 0)
    of vkStr: boolV(v.s.strip.len == 0)
    of vkTable: boolV(v.t.count == 0)
    else: boolV(false)

  # ----------------------------------------------------------- dates
  def "date": strV(now().format("yyyy-MM-dd"))
  def "heure": strV(now().format("HH:mm:ss"))
  def "maintenant": strV(now().format("yyyy-MM-dd HH:mm:ss"))
  def "horodatage": numV(epochTime())

  # ----------------------------------------------------------- tables
  def "taille": intV(L.tableArg(a, 1, "taille").rawLen)
  def "nbelements": intV(L.tableArg(a, 1, "nbelements").count)
  def "clefs":
    let t = newLTable()
    for k, _ in L.tableArg(a, 1, "clefs").pairs: t.arr.add k
    tableV(t)
  def "valeurs":
    let t = newLTable()
    for _, v in L.tableArg(a, 1, "valeurs").pairs: t.arr.add v
    tableV(t)
  def "aclef": boolV(L.tableArg(a, 1, "aclef").rawGet(arg(a, 2)).kind != vkNil)
  def "copier": tableV(copyTable(L.tableArg(a, 1, "copier")))
  def "fixermetatable":
    let t = L.tableArg(a, 1, "fixermetatable")
    let m = arg(a, 2)
    if m.kind == vkNil: t.meta = nil
    elif m.kind == vkTable: t.meta = m.t
    else: rtError("fixermetatable : la métatable doit être une table ou nul")
    arg(a, 1)
  def "obtenirmetatable":
    let v = arg(a, 1)
    let m = L.getMeta(v)
    if m.isNil: nilV else: tableV(m)
  def "lirebrut": L.tableArg(a, 1, "lirebrut").rawGet(arg(a, 2))
  def "ecrirebrut":
    let t = L.tableArg(a, 1, "ecrirebrut")
    try: t.rawSet(arg(a, 2), arg(a, 3))
    except ValueError as e: rtError(e.msg)
    arg(a, 1)
  def "inserer":
    let t = L.tableArg(a, 1, "inserer")
    try:
      if a.len > 2: t.insertAt(int(L.checkInt(a, 3, "inserer")), arg(a, 2))
      elif arg(a, 2).kind != vkNil: t.rawSet(intV(t.rawLen + 1), arg(a, 2))
    except ValueError as e: rtError(e.msg)
    arg(a, 1)
  def "retirer":
    let t = L.tableArg(a, 1, "retirer")
    try: t.removeAt(int(L.optInt(a, 2, "retirer", t.rawLen)))
    except ValueError as e: rtError(e.msg)
  def "trier":
    let t = L.tableArg(a, 1, "trier")
    let f = arg(a, 2)
    if f.kind != vkNil and not L.callable(f): rtError("trier : procédure de comparaison attendue (@NOM)")
    var items: seq[Value]
    for i in 1 .. t.rawLen: items.add t.rawGet(intV(i))
    items.sort(proc (x, y: Value): int =
      if f.kind != vkNil:
        if truthy(first(L.call(f, @[x, y]))): -1
        elif truthy(first(L.call(f, @[y, x]))): 1
        else: 0
      elif L.lessThan(x, y, false, "<"): -1
      elif L.lessThan(y, x, false, "<"): 1
      else: 0)
    for i, v in items: t.rawSet(intV(i + 1), v)
    arg(a, 1)
  b.fn "appeler", proc (L: Interp, a: seq[Value]): seq[Value] =
    if a.len == 0: rtError("appeler : procédure attendue")
    @[first(L.call(a[0], a[1 .. ^1]))]

  # ----------------------------------------------------------- JSON
  def "json": strV($L.toJsonNode(arg(a, 1)))
  def "dejson":
    try: fromJsonNode(parseJson(L.tostrArg(a, 1)))
    except JsonParsingError, ValueError: rtError("dejson : JSON invalide")

  # ----------------------------------------------------------- base de données
  def "requete":
    if a.len == 0: rtError("requete : texte SQL attendu")
    var r: QueryResult
    try: r = L.query(L.tostrArg(a, 1), a[1 .. ^1])
    except ZoneError as e: rtError(e.msg)
    rowsToValue(r)
  def "valeursql":
    if a.len == 0: rtError("valeursql : texte SQL attendu")
    var r: QueryResult
    try: r = L.query(L.tostrArg(a, 1), a[1 .. ^1])
    except ZoneError as e: rtError(e.msg)
    r.firstValue
  def "ouvrirbase":
    try: L.openBase(L.tostrArg(a, 1))
    except DuckError as e: rtError("ouvrirbase : " & e.msg)
    strV(L.basePath)
  def "fermerbase":
    L.closeZone("*")
    L.closeBase()
    boolV(true)
  def "base": strV(L.basePath)

  # ----------------------------------------------------------- sécurité
  def "hachage":
    let s = L.tostrArg(a, 1)
    var bytes = newSeq[byte](s.len)
    for i, c in s: bytes[i] = byte(c)
    strV(versHex(sha256(bytes)))
  def "hachermdp": strV(hacherMdp(L.tostrArg(a, 1)))
  def "verifiermdp":
    boolV(verifierMdp(L.tostrArg(a, 1), (if arg(a, 2).kind == vkStr: arg(a, 2).s else: "")))
  def "mdpaleatoire": strV(mdpAleatoire(int(L.optInt(a, 1, "mdpaleatoire", 16))))
  def "uuid": strV(uuid4())

  # ----------------------------------------------------------- zones de travail
  def "fdf": boolV(L.zoneArg(a, 1).eof)
  def "ddf": boolV(L.zoneArg(a, 1).bof)
  def "numenr":
    let z = L.zoneArg(a, 1)
    intV(if z.eof: z.keys.len + 1 else: z.pos + 1)
  def "nbenr": intV(L.zoneArg(a, 1).keys.len)
  def "trouve": boolV(L.zoneArg(a, 1).found)
  def "alias": strV(L.zoneState.current)
  def "champ":
    let z = L.zoneArg(a, 2)
    let i = z.fieldIndex(toUpper(L.tostrArg(a, 1)))
    if i < 0: rtError("champ inconnu dans " & z.table & " : " & L.tostrArg(a, 1))
    try: L.field(z, i)
    except ZoneError as e: rtError(e.msg)
  def "enregistrement":
    let z = L.zoneArg(a, 1)
    var r: seq[Value]
    try: r = L.record(z)
    except ZoneError as e: rtError(e.msg)
    let t = newLTable()
    for i, c in z.upCols:
      if r[i].kind != vkNil: t.rawSet(c, r[i])
    tableV(t)

  # ----------------------------------------------------------- poste de travail
  def "paquet":
    let name = L.tostrArg(a, 1)
    let v = L.openPackage(name)
    if v.kind == vkNil: rtError("paquet inconnu : " & name)
    v
  def "saisir":
    let prompt = L.optStr(a, 1, "saisir", "")
    var got: (bool, string)
    L.blocking:
      got = L.input(prompt)
    if got[0]: strV(got[1]) else: nilV
  tableV(b)

registerPackage PackageDef(name: "base", global: true, open: openBase,
  description: "Fonctions intégrées de Lexis+",
  docs: docs("base", [
    "majuscule(s)", "Texte en majuscules (accents compris).",
    "minuscule(s)", "Texte en minuscules.",
    "rogner(s)", "Retire les espaces aux deux bouts (ALLTRIM).",
    "rognerg(s)", "Retire les espaces à gauche (LTRIM).",
    "rognerd(s)", "Retire les espaces à droite (RTRIM).",
    "longueur(s)", "Nombre de caractères (ou d'éléments d'une liste).",
    "souschaine(s, debut, [n])", "Extrait n caractères à partir de debut (SUBSTR) ; positions à partir de 1.",
    "gauche(s, n)", "Les n premiers caractères.",
    "droite(s, n)", "Les n derniers caractères.",
    "position(sous, s)", "Position de sous dans s, 0 si absente (AT).",
    "chaine(v, [largeur], [decimales])", "Texte d'une valeur ; avec largeur : nombre aligné à droite (STR).",
    "texte(v)", "Texte d'une valeur (utilise __tostring).",
    "valeur(s)", "Nombre d'un texte (virgule décimale admise), 0 si impossible (VAL).",
    "nombre(s)", "Nombre d'un texte, nul si impossible.",
    "espace(n)", "n espaces (SPACE).",
    "repliquer(s, n)", "s répété n fois (REPLICATE).",
    "remplacertexte(s, a, b)", "Remplace toutes les occurrences de a par b (STRTRAN).",
    "contient(s, sous)", "Vrai si s contient sous ; avec une table : vrai si la valeur y figure.",
    "commencepar(s, debut)", "Vrai si s commence par debut.",
    "finitpar(s, fin)", "Vrai si s finit par fin.",
    "decouper(s, [separateur])", "Liste des morceaux (séparateur « , » par défaut).",
    "joindre(liste, [separateur])", "Texte des éléments d'une liste.",
    "html(s)", "Échappe < > & \" ' pour le HTML.",
    "url(s)", "Encode un texte pour une URL.",
    "car(code, ...)", "Caractères à partir de leurs codes Unicode.",
    "code(s, [i])", "Code Unicode du i-ème caractère.",
    "abs(x)", "Valeur absolue.",
    "entier(x)", "Partie entière, vers zéro (INT).",
    "arrondi(x, [decimales])", "Arrondi (0 décimale par défaut).",
    "plancher(x)", "Entier inférieur.", "plafond(x)", "Entier supérieur.",
    "racine(x)", "Racine carrée.",
    "mod(a, b)", "Reste de la division, du signe du diviseur.",
    "max(a, b, ...)", "Plus grande valeur (nombres ou chaînes).",
    "min(a, b, ...)", "Plus petite valeur.",
    "aleatoire([n])", "Réel entre 0 et 1, ou entier entre 1 et n.",
    "sin(x)", "Sinus (radians).", "cos(x)", "Cosinus.", "tan(x)", "Tangente.",
    "asin(x)", "Arc sinus.", "acos(x)", "Arc cosinus.", "atan(y, [x])", "Arc tangente (atan2 avec deux arguments).",
    "exp(x)", "Exponentielle.", "log(x, [base])", "Logarithme (népérien par défaut).", "pi()", "π.",
    "type(v)", "\"nul\", \"logique\", \"nombre\", \"chaine\", \"table\", \"procedure\", \"objet\" ou \"tache\".",
    "estnul(v)", "Vrai si v vaut nul.",
    "vide(v)", "Vrai pour nul, faux, 0, une chaîne blanche ou une table sans élément (EMPTY).",
    "sisinon(condition, si_vrai, si_faux)", "Valeur selon la condition ; seule la branche choisie est calculée (IIF).",
    "date()", "Date du jour, AAAA-MM-JJ.",
    "heure()", "Heure, HH:MM:SS.",
    "maintenant()", "Date et heure.",
    "horodatage()", "Secondes depuis le 1er janvier 1970 (avec décimales).",
    "taille(t)", "Nombre d'éléments de la partie liste (#t).",
    "nbelements(t)", "Nombre total d'éléments.",
    "clefs(t)", "Liste des clefs.", "valeurs(t)", "Liste des valeurs.",
    "aclef(t, k)", "Vrai si la clef existe.",
    "copier(t)", "Copie de premier niveau.",
    "fixermetatable(t, mt)", "Donne une métatable ; renvoie t.",
    "obtenirmetatable(t)", "La métatable ou nul.",
    "lirebrut(t, k)", "Lecture sans métaméthode.",
    "ecrirebrut(t, k, v)", "Écriture sans métaméthode ; renvoie t.",
    "inserer(t, v, [position])", "Ajoute v (à la fin ou à la position) ; renvoie t.",
    "retirer(t, [position])", "Enlève et renvoie un élément (le dernier par défaut).",
    "trier(t, [@comparer])", "Trie la liste sur place ; renvoie t.",
    "appeler(@proc, ...)", "Appelle une procédure référencée.",
    "json(v)", "Texte JSON d'une valeur.",
    "dejson(s)", "Valeur d'un texte JSON (clefs d'objets en majuscules).",
    "requete(sql, ...)", "Liste des lignes d'une requête DuckDB (paramètres « ? »).",
    "valeursql(sql, ...)", "Première valeur de la première ligne, ou nul.",
    "ouvrirbase(chemin)", "Ouvre une base DuckDB (\":memoire:\" pour une base en mémoire) ; par défaut donnees.duckdb du dossier du programme.",
    "fermerbase()", "Ferme la base et les zones.",
    "base()", "Chemin de la base ouverte (\"\" si aucune).",
    "hachage(s)", "Empreinte SHA-256 en hexadécimal (pas pour les mots de passe).",
    "hachermdp(mdp)", "Empreinte PBKDF2-SHA256 salée d'un mot de passe.",
    "verifiermdp(mdp, empreinte)", "Vérifie un mot de passe (temps constant).",
    "mdpaleatoire([n])", "Mot de passe aléatoire (16 caractères par défaut).",
    "uuid()", "Identifiant unique aléatoire.",
    "fdf([alias])", "Fin de fichier de la zone (EOF).",
    "ddf([alias])", "Début de fichier (BOF).",
    "numenr([alias])", "Numéro de l'enregistrement courant (RECNO).",
    "nbenr([alias])", "Nombre d'enregistrements (RECCOUNT).",
    "trouve([alias])", "Résultat du dernier chercher / localiser (FOUND).",
    "alias()", "Alias de la zone courante.",
    "champ(nom, [alias])", "Valeur d'un champ par son nom (FIELD).",
    "enregistrement([alias])", "L'enregistrement courant sous forme de table.",
    "paquet(nom)", "Charge un paquet : interface, fichier, json, csv, http, reseau, tache...",
    "saisir([invite])", "Lit une ligne saisie (console de l'atelier ou terminal) ; nul en fin d'entrée."]))

proc newFullInterp*(): Interp =
  ## Interpréteur avec les fonctions intégrées et les paquets globaux.
  result = newInterp()
  openGlobals(result)
