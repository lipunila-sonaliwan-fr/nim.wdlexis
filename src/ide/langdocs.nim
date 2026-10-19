# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - documentation du langage pour l'atelier
#
# Source unique : les paquets enregistrés (lexis/api.nim). La coloration, la
# complétion, l'aide à la signature et le panneau des paquets en dérivent.
# Lexis+ étant insensible à la casse, les recherches se font en majuscules.

import std/[sets, strutils]
from std/unicode import toUpper
import ../lexis/api

export ApiDoc

const
  UiHandlers* = ["surclic", "surdoubleclic", "surclicdroit", "surclicmilieu", "surdoubleclicdroit",
    "surboutonbas", "surboutonhaut", "surentree", "sursortie", "surdeplacement", "surmolette",
    "surtouchebas", "surtouchehaut", "sursaisie", "surfocus", "surfinfocus", "surchangement",
    "surselection", "surdeploiement", "surrepli", "survalidation", "surouverture", "surfermeture",
    "surredimension", "suractivation", "surdesactivation", "surevenement"]
  UiProps* = ["valeur", "num", "libelle", "texte", "titre", "visible", "etat", "actif",
    "infobulle", "nom", "x", "y", "largeur", "hauteur", "couleur", "fond", "bordure",
    "accent", "rayon", "coche", "min", "max", "ancrage", "poids", "largeurfixe",
    "hauteurfixe", "etirer", "marge", "espacement", "colonnes", "famille", "genre", "theme"]
  ExtraBuiltins = ["sisinon", "session"]

var
  entries: seq[ApiDoc]
  builtins: HashSet[string]       # majuscules
  pkgNames: seq[string]

var ready: bool

proc initLangDocs*() =
  ## À appeler au démarrage (après l'import des paquets) ; les appels suivants
  ## sont sans effet (l'atelier, ui.editeur et le paquet lexis l'appellent).
  {.cast(gcsafe).}:
    if ready: return
    ready = true
  entries = allDocs()
  builtins = initHashSet[string]()
  for d in entries:
    if d.owner.len == 0 and not d.isMethod: builtins.incl toUpper(d.name)
  for p in packages():
    if p.name != "base":
      builtins.incl toUpper(p.name)
      pkgNames.add p.name
  for n in ExtraBuiltins: builtins.incl toUpper(n)

proc isBuiltin*(name: string): bool =
  {.cast(gcsafe).}:
    result = toUpper(name) in builtins

proc apiEntries*(): seq[ApiDoc] =
  {.cast(gcsafe).}:
    result = entries

proc packageNames*(): seq[string] =
  {.cast(gcsafe).}:
    result = pkgNames

proc sameName(a, b: string): bool = cmpIgnoreCase(a, b) == 0 or toUpper(a) == toUpper(b)

proc apiLookup*(name: string, wantMethod = false, owner = ""): seq[ApiDoc] =
  for e in apiEntries():
    if e.name.sameName(name) and e.isMethod == wantMethod and (owner.len == 0 or e.owner.sameName(owner)):
      result.add e

proc apiSummary*(name: string, wantMethod = false, owner = ""): string =
  var es = apiLookup(name, wantMethod, owner)
  if es.len == 0 and owner.len > 0: es = apiLookup(name, wantMethod)
  if es.len == 0:
    if name.toLowerAscii in UiHandlers:
      return name.toLowerAscii & " = @PROCEDURE — gestionnaire d'événement de l'interface (procedure P(ev) : ev.genre, ev.x, ev.y, ev.texte, ev.index, ev:arreter())"
    if name.toLowerAscii == "sisinon":
      return "sisinon(condition, si_vrai, si_faux) — valeur selon la condition ; seule la branche choisie est calculée"
    return ""
  var sigs: seq[string]
  for e in es:
    if e.signature notin sigs: sigs.add e.signature
  if sigs.len > 3: sigs.setLen(3)
  sigs.join("  |  ") & "  —  " & es[0].doc

proc membersOf*(owner: string): seq[ApiDoc] =
  ## Fonctions « owner.f » d'un paquet.
  for e in apiEntries():
    if e.owner.sameName(owner) and not e.isMethod: result.add e

proc methodEntries*(): seq[ApiDoc] =
  for e in apiEntries():
    if e.isMethod: result.add e

proc sections*(): seq[string] =
  for e in apiEntries():
    if e.section notin result: result.add e.section
