# Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr
#   wdlexis+ - paquet systeme (global)
#
#   systeme.temps([date]) systeme.horloge() systeme.date([format], [t]) systeme.ecart(a, b)
#   systeme.env(nom) systeme.fixerenv(nom, v) systeme.executer(cmd) systeme.capturer(cmd)
#   systeme.supprimer(chemin) systeme.renommer(a, b) systeme.nomtemporaire()
#   systeme.quitter([code]) systeme.attendre(secondes) systeme.plateforme() systeme.args

import std/[os, osproc, times, strutils, monotimes]
from std/unicode import toRunes, `$`
import ../lexis/api

type LexisExit* = object of LexisStop
  code*: int

let progStart = getMonoTime()

const
  JoursSemaine = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
  Mois = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet",
          "août", "septembre", "octobre", "novembre", "décembre"]

proc tmField(t: LTable, name: string, def: int, required = true): int =
  let v = t.field(name)
  if v.kind == vkNil:
    if required: rtError("champ « " & name & " » manquant dans la table de date")
    return def
  var ok: bool
  result = int(toInteger(v, ok))
  if not ok: rtError("champ « " & name & " » invalide dans la table de date")

proc strftime(fmt: string, dt: DateTime): string =
  var i = 0
  let wd = (ord(dt.weekday) + 1) mod 7          # 0 = dimanche.
  while i < fmt.len:
    if fmt[i] != '%' or i + 1 >= fmt.len:
      result.add fmt[i]
      inc i
      continue
    let c = fmt[i + 1]
    i += 2
    case c
    of 'Y': result.add $dt.year
    of 'y': result.add align($(dt.year mod 100), 2, '0')
    of 'm': result.add align($ord(dt.month), 2, '0')
    of 'd': result.add align($dt.monthday, 2, '0')
    of 'H': result.add align($dt.hour, 2, '0')
    of 'M': result.add align($dt.minute, 2, '0')
    of 'S': result.add align($dt.second, 2, '0')
    of 'A': result.add JoursSemaine[wd]
    of 'a': result.add JoursSemaine[wd][0 .. 2]
    of 'B': result.add Mois[ord(dt.month) - 1]
    of 'b': result.add $Mois[ord(dt.month) - 1].toRunes[0 .. 2]
    of 'j': result.add align($(dt.yearday + 1), 3, '0')
    of 'w': result.add $wd
    of 'c': result.add JoursSemaine[wd] & " " & $dt.monthday & " " & Mois[ord(dt.month) - 1] & " " &
                       $dt.year & " " & dt.format("HH:mm:ss")
    of 'x': result.add dt.format("dd/MM/yyyy")
    of 'X', 'T': result.add dt.format("HH:mm:ss")
    of 'F': result.add dt.format("yyyy-MM-dd")
    of 'Z': result.add dt.timezone.name
    of '%': result.add '%'
    else: rtError("conversion invalide « %" & $c & " » dans systeme.date")

proc openSysteme(L: Interp): Value =
  let m = newLib()
  m.fn "temps", proc (L: Interp, a: seq[Value]): seq[Value] =
    if arg(a, 1).kind != vkTable: return @[intV(getTime().toUnix)]
    let t = a[0].t
    let dt = dateTime(tmField(t, "annee", 0), Month(tmField(t, "mois", 1)),
                      MonthdayRange(tmField(t, "jour", 1)),
                      HourRange(tmField(t, "heure", 12, false)),
                      MinuteRange(tmField(t, "minute", 0, false)),
                      SecondRange(tmField(t, "seconde", 0, false)), zone = local())
    @[intV(dt.toTime.toUnix)]
  m.fn "horloge", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[numV(float64(inNanoseconds(getMonoTime() - progStart)) / 1e9)]
  m.fn "date", proc (L: Interp, a: seq[Value]): seq[Value] =
    var fmt = L.optStr(a, 1, "date", "%c")
    let tm = if arg(a, 2).kind == vkNil: getTime() else: fromUnix(L.checkInt(a, 2, "date"))
    var utc = false
    if fmt.startsWith("!"):
      utc = true
      fmt = fmt[1 .. ^1]
    let dt = if utc: tm.utc else: tm.local
    if fmt.startsWith("*t"):
      return @[record({"annee": intV(dt.year), "mois": intV(ord(dt.month)), "jour": intV(dt.monthday),
                       "heure": intV(dt.hour), "minute": intV(dt.minute), "seconde": intV(dt.second),
                       "joursemaine": intV((ord(dt.weekday) + 1) mod 7 + 1),
                       "jourannee": intV(dt.yearday + 1), "ete": boolV(dt.isDst)})]
    @[strV(strftime(fmt, dt))]
  m.fn "ecart", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[numV(L.checkNum(a, 1, "ecart") - L.optNum(a, 2, "ecart", 0))]
  m.fn "env", proc (L: Interp, a: seq[Value]): seq[Value] =
    let n = L.checkStr(a, 1, "env")
    if existsEnv(n): @[strV(getEnv(n))] else: @[nilV]
  m.fn "fixerenv", proc (L: Interp, a: seq[Value]): seq[Value] =
    putEnv(L.checkStr(a, 1, "fixerenv"), L.checkStr(a, 2, "fixerenv"))
  m.fn "executer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let cmd = L.checkStr(a, 1, "executer")
    var code: int
    L.blocking:
      code = execShellCmd(cmd)
    @[intV(code)]
  m.fn "capturer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let cmd = L.checkStr(a, 1, "capturer")
    var res: tuple[output: string, exitCode: int]
    L.blocking:
      res = execCmdEx(cmd)
    @[record({"sortie": strV(res.output), "code": intV(res.exitCode)})]
  m.fn "supprimer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkStr(a, 1, "supprimer")
    try:
      if dirExists(p): removeDir(p)
      elif fileExists(p): removeFile(p)
      else: return fail(p & " : fichier introuvable")
      @[boolV(true)]
    except OSError: fail(p & " : suppression impossible")
  m.fn "renommer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkStr(a, 1, "renommer")
    try:
      moveFile(x, L.checkStr(a, 2, "renommer"))
      @[boolV(true)]
    except OSError, IOError: fail(x & " : renommage impossible")
  m.fn "nomtemporaire", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(getTempDir() / "wdlexis_" & $getCurrentProcessId() & "_" & $int(epochTime() * 1000))]
  m.fn "quitter", proc (L: Interp, a: seq[Value]): seq[Value] =
    var e = newException(LexisExit, "systeme.quitter")
    let v = arg(a, 1)
    e.code = if v.kind == vkBool: (if v.b: 0 else: 1) else: int(L.optInt(a, 1, "quitter", 0))
    raise e
  m.fn "attendre", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkNum(a, 1, "attendre")
    var left = int(s * 1000)
    L.blocking:
      while left > 0 and not L.stopRequested():
        sleep(min(left, 50))
        left -= 50
    L.checkStop()
  m.fn "plateforme", proc (L: Interp, a: seq[Value]): seq[Value] = @[strV(hostOS)]
  m.fn "dossierprogramme", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(if L.scriptPath.len > 0: L.scriptPath.parentDir else: getCurrentDir())]
  let argsT = newLTable()
  for i, s in L.args: argsT.rawSet(intV(i + 1), strV(s))
  argsT.rawSet(intV(0), strV(L.scriptPath))
  m.set "args", tableV(argsT)
  tableV(m)

registerPackage PackageDef(name: "systeme", global: true, open: openSysteme,
  description: "Système d'exploitation",
  docs: docs("systeme", [
    "systeme.temps([date])", "Heure actuelle (secondes Unix), ou date d'une table {annee, mois, jour, heure, minute, seconde}.",
    "systeme.horloge()", "Temps écoulé depuis le lancement, en secondes (horloge monotone).",
    "systeme.date([format], [t])", "Date formatée : %Y %m %d %H %M %S %A (jour) %B (mois) %F %T %x... ; \"*t\" renvoie une table ; \"!\" en tête pour l'heure UTC.",
    "systeme.ecart(t2, t1)", "Différence en secondes.",
    "systeme.env(nom)", "Variable d'environnement (nul si absente).",
    "systeme.fixerenv(nom, valeur)", "Définit une variable d'environnement.",
    "systeme.executer(commande)", "Exécute une commande système ; renvoie son code de retour.",
    "systeme.capturer(commande)", "Exécute une commande ; renvoie {sortie, code}.",
    "systeme.supprimer(chemin)", "Supprime un fichier ou un dossier.",
    "systeme.renommer(ancien, nouveau)", "Renomme un fichier.",
    "systeme.nomtemporaire()", "Nom de fichier temporaire.",
    "systeme.quitter([code])", "Termine le programme.",
    "systeme.attendre(secondes)", "Pause (les fenêtres restent réactives).",
    "systeme.plateforme()", "\"linux\", \"macosx\", \"windows\"...",
    "systeme.dossierprogramme()", "Dossier du programme principal.",
    "systeme.args", "Arguments du programme ; systeme.args[0] est le chemin du programme."]))
