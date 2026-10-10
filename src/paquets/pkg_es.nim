# Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr
#   wdlexis+ - paquet es : entrées / sorties (global)
#
#   es.ecrire(...)              écrit sur la sortie (console de l'atelier ou terminal)
#   es.lire([format])           lit l'entrée : "l" ligne (défaut), "n" nombre
#   es.lignes([chemin])         itérateur sur les lignes (fichier ou entrée) : pour chaque l dans es.lignes(f)
#   es.ouvrir(chemin, [mode])   ouvre un fichier : "l" lecture, "e" écriture, "a" ajout, "l+", "e+"
#   f:lire([format])  f:ecrire(...)  f:lignes()  f:position([origine], [decalage])  f:vider()  f:fermer()

import std/strutils
import ../lexis/api

type
  LFile* = ref object of LUser
    f*: File
    closed*: bool
    isStd*: int          # 0 fichier, 1 sortie, 2 sortie d'erreur, 3 entrée.

var fileMethods {.threadvar.}: LTable

proc checkFile(L: Interp, a: seq[Value], fname: string): LFile =
  result = checkUser[LFile](L, a, 1, fname, "fichier")
  if result.closed: rtError("fichier fermé")

proc fmtOf(v: Value): char =
  var s = if v.kind == vkStr: v.s else: "l"
  if s.startsWith("*"): s = s[1 .. ^1]
  if s.len == 0: 'l'
  elif s[0] in {'t', 'a', 'T', 'A'}: 't'
  else: s[0]

proc readFmt(L: Interp, f: File, fmt: Value): Value =
  if fmt.kind in {vkInt, vkNum}:
    var ok: bool
    let n = int(toInteger(fmt, ok))
    if n <= 0: return (if f.endOfFile: nilV else: strV(""))
    var buf = newString(n)
    let got = f.readChars(toOpenArray(buf, 0, n - 1))
    if got == 0: return nilV
    buf.setLen(got)
    return strV(buf)
  case fmtOf(fmt)
  of 't': strV(f.readAll())
  of 'l', 'L':
    var line: string
    if f.readLine(line): strV(if fmtOf(fmt) == 'L': line & "\n" else: line) else: nilV
  of 'n':
    var line: string
    if not f.readLine(line): return nilV
    let (ok, v) = str2number(line)
    if ok: v else: nilV
  else:
    rtError("format de lecture invalide (\"l\" ligne, \"L\" ligne avec fin, \"n\" nombre, \"t\" tout, ou un nombre d'octets)")

proc consoleRead(L: Interp, fmt: Value): Value =
  var got: (bool, string)
  L.blocking:
    got = L.input("")
  if not got[0]: return nilV
  case fmtOf(fmt)
  of 'n':
    let (ok, v) = str2number(got[1])
    if ok: v else: nilV
  of 'L': strV(got[1] & "\n")
  else: strV(got[1])

proc writeTo(L: Interp, h: LFile, a: seq[Value], start: int) =
  for i in start .. a.len:
    let s = L.tostr(a[i - 1])
    case h.isStd
    of 1: L.output(s)
    of 2: L.errput(s)
    else: h.f.write(s)

proc newFile(L: Interp, f: File, std = 0): Value =
  L.wrap(LFile(f: f, isStd: std), "fichier", fileMethods)

proc fileMode(s: string): FileMode =
  case s.replace("b", "")
  of "l", "r": fmRead
  of "e", "w": fmWrite
  of "a": fmAppend
  of "l+", "r+": fmReadWriteExisting
  of "e+", "w+": fmReadWrite
  of "a+": fmAppend
  else: rtError("mode d'ouverture invalide « " & s & " » (\"l\", \"e\", \"a\", \"l+\", \"e+\")")

proc openEs(L: Interp): Value =
  fileMethods = newLib()
  let fm = fileMethods
  fm.fn "ecrire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let h = L.checkFile(a, "ecrire")
    L.writeTo(h, a, 2)
    @[a[0]]
  fm.fn "lire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let h = L.checkFile(a, "lire")
    if h.isStd == 3: return @[L.consoleRead(arg(a, 2))]
    @[L.readFmt(h.f, (if a.len >= 2: a[1] else: strV("l")))]
  fm.fn "lignes", proc (L: Interp, a: seq[Value]): seq[Value] =
    let h = L.checkFile(a, "lignes")
    @[fnV("lignes", proc (L: Interp, x: seq[Value]): seq[Value] =
      if h.closed: return @[nilV]
      if h.isStd == 3: return @[L.consoleRead(strV("l"))]
      @[L.readFmt(h.f, strV("l"))])]
  fm.fn "position", proc (L: Interp, a: seq[Value]): seq[Value] =
    let h = L.checkFile(a, "position")
    if h.isStd != 0: rtError("position : impossible sur la console")
    let whence = L.optStr(a, 2, "position", "courant")
    let off = L.optInt(a, 3, "position", 0)
    case whence
    of "debut", "set": h.f.setFilePos(off, fspSet)
    of "fin", "end": h.f.setFilePos(off, fspEnd)
    else: h.f.setFilePos(off, fspCur)
    @[intV(h.f.getFilePos())]
  fm.fn "vider", proc (L: Interp, a: seq[Value]): seq[Value] =
    let h = L.checkFile(a, "vider")
    if h.isStd == 0: h.f.flushFile()
    @[a[0]]
  fm.fn "fermer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let h = L.checkFile(a, "fermer")
    if h.isStd == 0:
      h.f.close()
      h.closed = true
    @[boolV(true)]

  let m = newLib()
  let outV = L.newFile(nil, 1)
  let errV = L.newFile(nil, 2)
  let inV = L.newFile(nil, 3)
  m.set "sortie", outV
  m.set "erreur", errV
  m.set "entree", inV
  m.fn "ecrire", proc (L: Interp, a: seq[Value]): seq[Value] =
    L.writeTo(LFile(outV.u), a, 1)
    @[outV]
  m.fn "lire", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[L.consoleRead(arg(a, 1))]
  m.fn "ouvrir", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.checkStr(a, 1, "ouvrir")
    let mode = fileMode(L.optStr(a, 2, "ouvrir", "l"))
    var f: File
    if not open(f, path, mode): rtError(path & " : impossible d'ouvrir le fichier")
    let v = L.newFile(f)
    let h = LFile(v.u)
    L.closers.add proc () =
      if not h.closed:
        h.closed = true
        h.f.close()
    @[v]
  m.fn "lignes", proc (L: Interp, a: seq[Value]): seq[Value] =
    if arg(a, 1).kind == vkNil:
      return @[fnV("lignes", proc (L: Interp, x: seq[Value]): seq[Value] =
        @[L.consoleRead(strV("l"))])]
    let path = L.checkStr(a, 1, "lignes")
    var f: File
    if not open(f, path, fmRead): rtError(path & " : impossible d'ouvrir le fichier")
    let h = LFile(f: f)
    L.closers.add proc () =
      if not h.closed:
        h.closed = true
        h.f.close()
    @[fnV("lignes", proc (L: Interp, x: seq[Value]): seq[Value] =
      if h.closed: return @[nilV]
      var line: string
      if h.f.readLine(line): return @[strV(line)]
      h.f.close()
      h.closed = true
      @[nilV])]
  m.fn "type", proc (L: Interp, a: seq[Value]): seq[Value] =
    let v = arg(a, 1)
    if v.kind == vkUser and v.u of LFile:
      @[strV(if LFile(v.u).closed: "fichier fermé" else: "fichier")]
    else: @[nilV]
  tableV(m)

registerPackage PackageDef(name: "es", global: true, open: openEs,
  description: "Entrées / sorties : console et fichiers",
  docs: docs("es", [
    "es.ecrire(...)", "Écrit les valeurs (sans séparateur ni fin de ligne) sur la sortie : console de l'atelier ou terminal.",
    "es.lire([format])", "Lit l'entrée : \"l\" une ligne (défaut), \"n\" un nombre, \"L\" une ligne avec sa fin ; nul en fin d'entrée.",
    "es.lignes([chemin])", "Itérateur sur les lignes d'un fichier (ou de l'entrée) : pour chaque l dans es.lignes(chemin).",
    "es.ouvrir(chemin, [mode])", "Ouvre un fichier : \"l\" lecture (défaut), \"e\" écriture, \"a\" ajout, \"l+\", \"e+\".",
    "es.type(v)", "\"fichier\", \"fichier fermé\" ou nul.",
    "es.sortie", "Sortie standard.", "es.erreur", "Sortie d'erreur.", "es.entree", "Entrée standard.",
    "f:lire([format])", "Lit : \"l\", \"L\", \"n\", \"t\" (tout) ou un nombre d'octets ; nul en fin de fichier.",
    "f:ecrire(...)", "Écrit des valeurs ; renvoie le fichier.",
    "f:lignes()", "Itérateur sur les lignes restantes.",
    "f:position([origine], [decalage])", "Déplace la position (\"debut\", \"courant\", \"fin\") et la renvoie.",
    "f:vider()", "Vide les tampons.",
    "f:fermer()", "Ferme le fichier."]))
