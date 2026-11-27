# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet profileur : temps et mémoire d'un programme Lexis+
#
#   profileur.demarrer()
#   CALCUL_LONG()
#   r = profileur.arreter()
#   ? profileur.texte(r)
#
#   r = profileur.mesurer(@CALCUL_LONG, 1000)      && profil d'un seul appel
#
# Ligne de commande : wdlexisrt --profil programme.prg ; atelier : Exécuter › Profiler.

import std/[strutils, os]
import ../lexis/[api, profiler]

proc reportV*(p: Profiler): Value =
  let fns = newLTable()
  for f in p.functionsByTime:
    fns.arr.add record({"nom": strV(f.name.toLowerAscii), "source": strV(f.source), "ligne": intV(f.line),
                        "appels": intV(f.calls), "total_ms": numV(f.total * 1000), "propre_ms": numV(f.self * 1000),
                        "tables": intV(f.tables)})
  let lns = newLTable()
  for l in p.linesByTime(200):
    lns.arr.add record({"source": strV(l.source), "ligne": intV(l.line), "passages": intV(l.hits),
                        "ms": numV(l.time * 1000)})
  let mem = record({"debut_ko": intV(p.rss0), "fin_ko": intV(p.rss1), "pic_ko": intV(p.rssPeak),
                    "tables": intV(p.tables1 - p.tables0)})
  let curve = newLTable()
  for (t, kb) in p.samples:
    curve.arr.add record({"s": numV(t), "ko": intV(kb)})
  record({"duree_ms": numV(p.duration * 1000), "fonctions": tableV(fns), "lignes": tableV(lns),
          "memoire": mem, "courbe": tableV(curve), "texte": strV(p.report())})

proc current(L: Interp): Profiler =
  if not L.prof.isNil and L.prof of Profiler: Profiler(L.prof) else: nil

proc openProfileur(L: Interp): Value =
  let m = newLib()
  m.fn "demarrer", proc (L: Interp, a: seq[Value]): seq[Value] =
    if not L.current.isNil: discard L.stopProfiler()
    discard L.startProfiler()
  m.fn "arreter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.stopProfiler()
    if p.isNil: return @[nilV]
    @[reportV(p)]
  m.fn "actif", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[boolV(not L.current.isNil)]
  m.fn "rapport", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.current
    if p.isNil: return @[nilV]
    @[reportV(p)]
  m.fn "mesurer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let f = L.checkFunc(a, 1, "profileur.mesurer")
    if not L.current.isNil: discard L.stopProfiler()
    discard L.startProfiler()
    var p: Profiler
    try:
      discard L.call(f, (if a.len > 1: a[1 .. ^1] else: @[]))
    finally:
      p = L.stopProfiler()
    @[reportV(p)]
  m.fn "texte", proc (L: Interp, a: seq[Value]): seq[Value] =
    let r = arg(a, 1)
    if r.kind == vkTable: return @[r.t.rawGet(cle("texte"))]
    let p = L.current
    if p.isNil: return @[strV("")]
    @[strV(p.report())]
  m.fn "memoire", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(residentKb())]
  tableV(m)

const profDocs = [
  "profileur.demarrer()", "Démarre la mesure (temps par procédure et par ligne, mémoire).",
  "profileur.arreter()", "Arrête la mesure ; renvoie le rapport {duree_ms, fonctions, lignes, memoire, courbe, texte}. fonctions : {nom, source, ligne, appels, total_ms, propre_ms, tables} triées par temps propre ; lignes : {source, ligne, passages, ms} ; memoire : {debut_ko, fin_ko, pic_ko, tables}.",
  "profileur.mesurer(@PROC, arguments...)", "Profil d'un appel : renvoie le rapport.",
  "profileur.rapport()", "Rapport intermédiaire (profileur en marche).",
  "profileur.texte([rapport])", "Rapport texte lisible (tableau des procédures et des lignes les plus coûteuses).",
  "profileur.actif()", "Vrai si la mesure est en cours.",
  "profileur.memoire()", "Mémoire résidente du processus, en Ko."]

registerPackage PackageDef(name: "profileur", open: openProfileur,
  description: "Profileur : temps par procédure et par ligne, mémoire",
  docs: docs("profileur", profDocs))
