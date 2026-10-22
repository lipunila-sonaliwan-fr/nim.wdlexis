# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet « rapport » : génération d'états PDF dessinés avec l'éditeur
#   d'états de l'atelier (Conception > Nouvel état…).
#
#   r = rapport.debut("factures.pdf")              état « factures » (etat_factures.prg)
#   r = rapport.debut("sortie/f12.pdf", "facture") état « facture », autre fichier
#   r.ajoute("ligne", {libelle = "Stylo", prix = 2.5})
#   r.entete("entete_suite", {titre = "Suite"})    remplace l'en-tête
#   r.pied("pied_total", {total = 125})            remplace le pied
#   r.fin()                                        écrit le PDF, renvoie son chemin
#
# « r:ajoute(...) » s'écrit aussi ; « début » et « entête » sont acceptés.
# {page} et {nombre de page} sont calculés à la fin, quand toutes les pages sont connues.

import std/[tables, os, strutils]
from std/unicode import toUpper
import ../lexis/api
import ../ide/etats

proc baseDirOf(L: Interp): string =
  ## Dossier du programme s'il existe sur disque (atelier, runtime), sinon le dossier courant.
  let d = if L.scriptPath.len > 0: L.scriptPath.parentDir else: ""
  if d.len > 0 and dirExists(d): d else: getCurrentDir()

proc varsOf(L: Interp, v: Value, fname: string): Vars =
  ## {nom = valeur, ...} -> variables (noms en majuscules). Accepte aussi {{...}}.
  result = initTable[string, string]()
  if v.kind == vkNil: return
  if v.kind != vkTable: rtError(fname & " : table de variables attendue ({nom = valeur, ...})")
  var t = v.t
  var hasKeys = false
  for k, _ in t.pairs:
    if k.kind == vkStr: hasKeys = true
  if not hasKeys and t.rawLen == 1 and t.rawGet(intV(1)).kind == vkTable: t = t.rawGet(intV(1)).t
  for k, x in t.pairs:
    if k.kind == vkStr: result[toUpper(k.s)] = L.tostr(x)

proc loadDesign(L: Interp, name: string): ReportModel =
  ## La fonction ETAT_<NOM>() du projet (etat_<nom>.prg, chargé avec les autres .prg),
  ## sinon le fichier etat_<nom>.prg du dossier du programme.
  let f = L.procs.getOrDefault(reportProc(name), nilV)
  if f.kind != vkNil:
    let r = L.call(f, @[])
    if r.len > 0 and r[0].kind == vkStr:
      result = parseReportCode(r[0].s)
      if result != nil: return
  let p = L.baseDirOf / reportFileName(name)
  if fileExists(p):
    result = parseReportCode(readFile(p))
    if result != nil: return
  rtError("rapport.debut : état « " & name & " » introuvable (" & reportFileName(name) &
          " : créez-le avec Conception > Nouvel état…)")

proc reportObject(L: Interp, run: ReportRun): Value =
  let obj = newLTable()
  let selfV = tableV(obj)
  # r.f(...) ou r:f(...) : avec « : », le premier argument est l'objet lui-même.
  proc args(a: seq[Value]): seq[Value] =
    if a.len > 0 and a[0].kind == vkTable and a[0].t == obj: a[1 .. ^1] else: a
  proc zoneArg(L: Interp, a: seq[Value], fname: string): string =
    if arg(a, 1).kind == vkNil: "" else: L.checkStr(a, 1, fname)
  let ajoute = proc (L: Interp, a0: seq[Value]): seq[Value] =
    let a = args(a0)
    try: run.add(L.checkStr(a, 1, "ajoute"), L.varsOf(arg(a, 2), "ajoute"))
    except ValueError as e: rtError("ajoute : " & e.msg)
  let entete = proc (L: Interp, a0: seq[Value]): seq[Value] =
    let a = args(a0)
    try: run.setHeader(L.zoneArg(a, "entete"), L.varsOf(arg(a, 2), "entete"))
    except ValueError as e: rtError("entete : " & e.msg)
  let pied = proc (L: Interp, a0: seq[Value]): seq[Value] =
    let a = args(a0)
    try: run.setFooter(L.zoneArg(a, "pied"), L.varsOf(arg(a, 2), "pied"))
    except ValueError as e: rtError("pied : " & e.msg)
  let fin = proc (L: Interp, a0: seq[Value]): seq[Value] =
    if run.finished: rtError("fin : l'état est déjà terminé (" & run.outPath & ")")
    var p = ""
    try: p = run.finish()
    except CatchableError as e: rtError("fin : écriture impossible de « " & run.outPath & " » (" & e.msg & ")")
    @[strV(p)]
  obj.fn "ajoute", ajoute
  obj.fn "ajouter", ajoute
  obj.fn "entete", entete
  obj.fn "entête", entete
  obj.fn "pied", pied
  obj.fn "fin", fin
  obj.fn "terminer", fin
  obj.fn "nombrepages", proc (L: Interp, a: seq[Value]): seq[Value] = @[intV(run.pageCount)]
  obj.fn "page", proc (L: Interp, a: seq[Value]): seq[Value] = @[intV(max(1, run.pageCount))]
  obj.set "chemin", strV(run.outPath)
  obj.set "etat", strV(run.model.name)
  selfV

proc openRapport(L: Interp): Value =
  let m = newLib()
  let debut = proc (L: Interp, a: seq[Value]): seq[Value] =
    var pdf = L.checkStr(a, 1, "rapport.debut")
    var name = if arg(a, 2).kind == vkNil: "" else: L.checkStr(a, 2, "rapport.debut")
    if name.len == 0:
      name = extractFilename(pdf)
      if name.toLowerAscii.endsWith(".pdf"): name = name[0 ..< name.len - 4]
    if not pdf.toLowerAscii.endsWith(".pdf"): pdf.add ".pdf"
    let base = L.baseDirOf
    if not pdf.isAbsolute: pdf = base / pdf
    let model = L.loadDesign(name)
    @[L.reportObject(newRun(model, pdf, base))]
  m.fn "debut", debut
  m.fn "début", debut
  m.fn "etats", proc (L: Interp, a: seq[Value]): seq[Value] =
    # Noms des états du projet (fonctions ETAT_…).
    let t = newLTable()
    for k, _ in L.procs.pairs:
      if k.startsWith("ETAT_"): t.arr.add strV(k[5 .. ^1].toLowerAscii)
    @[tableV(t)]
  tableV(m)

const rapportDocs = [
  "rapport.debut(pdf, [etat])", "Commence un état PDF dessiné avec l'éditeur d'états (Conception > Nouvel état…) : etat_<etat>.prg du projet ; sans etat, le nom du PDF sans « .pdf ». Chemin relatif : dans le dossier du programme. « début » s'écrit aussi. Renvoie l'état en cours (r).",
  "r.ajoute(zone, {variable = valeur, ...})", "Ajoute une zone à la suite (r:ajoute s'écrit aussi) ; si elle ne tient plus dans la page, nouvelle page (avec en-tête et pied). Ses {variables} sont remplacées.",
  "r.entete(zone, {variable = valeur, ...})", "Remplace l'en-tête (zone « entete » au départ) : pour la page en cours si rien n'y est encore placé, sinon à partir de la suivante. zone nul : plus d'en-tête. « entête » s'écrit aussi.",
  "r.pied(zone, {variable = valeur, ...})", "Remplace le pied (zone « pied » au départ), pour la page en cours et les suivantes ; zone nul : plus de pied.",
  "r.fin()", "Calcule {page} et {nombre de page}, écrit le PDF et renvoie son chemin.",
  "r.nombrepages()", "Nombre de pages (définitif après r.fin()).",
  "rapport.etats()", "Noms des états du projet."]

registerPackage PackageDef(name: "rapport", open: openRapport,
  description: "États PDF : zones dessinées dans l'éditeur d'états, remplies par le programme",
  docs: docs("rapport", rapportDocs))
