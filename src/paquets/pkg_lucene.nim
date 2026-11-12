# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet lucene : index de recherche plein texte (Lucene++)
#
# Repose sur Lucene++ (https://github.com/luceneplusplus/LucenePlusPlus, portage
# C++ d'Apache Lucene 3.0, double licence LGPL 3 / Apache 2.0), par une petite
# bibliothèque C, « wdlexis_lucene » (lucene/wdlexis_lucene.cpp, Lucene++ et Boost
# liés statiquement), chargée à l'exécution comme le client Firebird : aucune
# dépendance de compilation, rien à installer d'autre que cette bibliothèque.
# Les index sont au format Lucene 3.0 (lisibles par Luke 3.x et Lucene++).
#
#   lc = paquet("lucene")
#   idx = lc.ouvrir("index_livres", {analyseur = "francais", schema = {id = "cle", annee = "entier"}})
#   idx:ajouter({id = "1", titre = "Les Misérables", auteur = "Victor Hugo", annee = 1862})
#   r = idx:chercher("hugo AND annee:[1800 TO 1870]", {max = 20, tri = "annee"})
#   pour chaque x dans r.resultats
#     ? x.score, x.document.titre
#   suivant
#   idx:fermer()
#
# La bibliothèque (libwdlexis_lucene.so / libwdlexis_lucene.dylib /
# wdlexis_lucene.dll) est cherchée : lucene.configurer{bibliotheque=}, variable
# WDLEXIS_LUCENE (chemin complet), dossier linOS / macOS / winOS à côté de
# l'exécutable, du dossier courant ou du programme, puis bibliothèques du
# système. outils/lucenepp.sh la construit.

import std/[dynlib, os, strutils, json, locks]
import ../lexis/api
from std/unicode import toLower
from ../lexis/fonctions import toJsonNode, fromJsonNode
from ../lexis/duck import osDir

const
  LibFile = when defined(windows): "wdlexis_lucene.dll"
            elif defined(macosx): "libwdlexis_lucene.dylib"
            else: "libwdlexis_lucene.so"

type
  AppelFn = proc (req: cstring): cstring {.cdecl, gcsafe.}
  LibererFn = proc (rep: cstring) {.cdecl, gcsafe.}

var
  lLock: Lock
  appel: AppelFn
  liberer: LibererFn
  loadError: string
  cfgLib: string                      # lucene.configurer{bibliotheque=}
initLock(lLock)

proc candidates(extra: openArray[string]): seq[string] =
  if cfgLib.len > 0:
    result.add(if dirExists(cfgLib): cfgLib / LibFile else: cfgLib)
  let env = getEnv("WDLEXIS_LUCENE")
  if env.len > 0: result.add(if dirExists(env): env / LibFile else: env)
  let exe = getAppDir()
  result.add exe / osDir / LibFile
  result.add exe / LibFile
  when defined(macosx):
    result.add exe / ".." / "Frameworks" / LibFile
    result.add exe / ".." / "Resources" / osDir / LibFile
  result.add getCurrentDir() / osDir / LibFile
  for d in extra:
    if d.len > 0:
      result.add d / osDir / LibFile
      result.add d / LibFile
  result.add LibFile

proc loadLucene(extra: openArray[string]): bool =
  ## Charge (une fois) la bibliothèque ; loadError explique un échec.
  if appel != nil: return true
  var lib: LibHandle
  for c in candidates(extra):
    if c.isAbsolute and not fileExists(c): continue
    lib = loadLib(c)
    if lib != nil: break
  if lib == nil:
    loadError = "bibliothèque Lucene++ (" & LibFile & ") introuvable : placez-la dans le dossier « " & osDir &
                " » à côté de l'exécutable ou du programme, ou indiquez son chemin avec " &
                "lucene.configurer{bibliotheque = \"...\"} ou la variable WDLEXIS_LUCENE (outils/lucenepp.sh la construit)"
    return false
  appel = cast[AppelFn](lib.symAddr("wdlx_lucene_appel"))
  liberer = cast[LibererFn](lib.symAddr("wdlx_lucene_liberer"))
  if appel == nil or liberer == nil:
    appel = nil
    loadError = LibFile & " invalide (wdlx_lucene_appel absent)"
    return false
  loadError = ""
  true

proc call(L: Interp, req: JsonNode): JsonNode =
  ## Envoie une requête au pont ; erreur Lexis+ si Lucene la refuse.
  let payload = $req
  var answer = ""
  var failure = ""
  L.blocking:
    withLock lLock:
      {.cast(gcsafe).}:
        if not loadLucene(L.searchDirs): failure = loadError
        else:
          let r = appel(payload.cstring)
          if r == nil: failure = "réponse vide de Lucene++"
          else:
            answer = $r
            liberer(r)
  if failure.len > 0: rtError("lucene : " & failure)
  let j = parseJson(answer)
  if not j{"ok"}.getBool: rtError("lucene : " & j{"erreur"}.getStr.strip.splitLines()[0])
  j{"r"}

proc lowerKeys(j: JsonNode): JsonNode =
  ## Noms de champs Lucene en minuscules (Lexis+ est insensible à la casse).
  if j.kind != JsonNodeKind.JObject: return j
  result = newJObject()
  for k, v in j.pairs: result[toLower(k)] = v

type
  LIndex = ref object of LUser
    h: int64
    closed: bool

proc checkIdx(L: Interp, a: seq[Value], fname: string): LIndex =
  result = checkUser[LIndex](L, a, 1, fname, "index lucene")
  if result.closed: rtError(fname & " : index fermé")

proc req(op: string, h: int64 = 0): JsonNode =
  result = %*{"op": op}
  if h != 0: result["h"] = %h

proc optsArg(a: seq[Value], i: int): LTable =
  if arg(a, i).kind == vkTable: a[i - 1].t else: nil

proc strList(L: Interp, v: Value): JsonNode =
  result = newJArray()
  case v.kind
  of vkStr:
    for p in v.s.split(','):
      if p.strip.len > 0: result.add %toLower(p.strip)
  of vkTable:
    for i in 1 .. v.t.rawLen: result.add %toLower(L.tostr(v.t.rawGet(intV(i))))
  else: discard

proc openLucene(L: Interp): Value =
  let im = newLib()
  im.fn "ajouter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkIdx(a, "ajouter")
    let d = L.checkTable(a, 2, "ajouter")
    var r = req("ajouter", x.h)
    r["doc"] = lowerKeys(L.toJsonNode(tableV(d)))
    discard L.call(r)
    @[boolV(true)]
  im.fn "remplacer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkIdx(a, "remplacer")
    let d = L.checkTable(a, 2, "remplacer")
    var r = req("remplacer", x.h)
    r["doc"] = lowerKeys(L.toJsonNode(tableV(d)))
    if arg(a, 3).kind == vkStr: r["cle"] = %toLower(a[2].s)
    discard L.call(r)
    @[boolV(true)]
  im.fn "supprimer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkIdx(a, "supprimer")
    var r = req("supprimer", x.h)
    if arg(a, 3).kind == vkNil: r["requete"] = %L.checkStr(a, 2, "supprimer")
    else:
      r["champ"] = %toLower(L.checkStr(a, 2, "supprimer"))
      r["valeur"] = L.toJsonNode(a[2])
    discard L.call(r)
    @[boolV(true)]
  im.fn "chercher", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkIdx(a, "chercher")
    var r = req("chercher", x.h)
    r["requete"] = %L.optStr(a, 2, "chercher", "*")
    let o = optsArg(a, 3)
    if o != nil:
      r["max"] = %o.optField("max", 10)
      r["debut"] = %o.optField("debut", 0)
      let tri = o.optField("tri", "")
      if tri.len > 0: r["tri"] = %toLower(tri)
      r["inverse"] = %o.optField("inverse", false)
      let c = o.field("champs")
      if c.kind != vkNil: r["champs"] = L.strList(c)
    @[fromJsonNode(L.call(r))]
  im.fn "compter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkIdx(a, "compter")
    var r = req("compter", x.h)
    r["requete"] = %L.optStr(a, 2, "compter", "*")
    @[fromJsonNode(L.call(r))]
  im.fn "analyser", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkIdx(a, "analyser")
    var r = req("analyser", x.h)
    r["requete"] = %L.checkStr(a, 2, "analyser")
    @[fromJsonNode(L.call(r))]
  im.fn "termes", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkIdx(a, "termes")
    var r = req("termes", x.h)
    r["champ"] = %toLower(L.checkStr(a, 2, "termes"))
    r["prefixe"] = %L.optStr(a, 3, "termes", "")
    r["max"] = %L.optInt(a, 4, "termes", 20)
    @[fromJsonNode(L.call(r))]
  im.fn "nombre", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkIdx(a, "nombre")
    @[fromJsonNode(L.call(req("nombre", x.h)))]
  im.fn "valider", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkIdx(a, "valider")
    @[fromJsonNode(L.call(req("valider", x.h)))]
  im.fn "vider", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkIdx(a, "vider")
    @[fromJsonNode(L.call(req("vider", x.h)))]
  im.fn "optimiser", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkIdx(a, "optimiser")
    @[fromJsonNode(L.call(req("optimiser", x.h)))]
  im.fn "schema", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.checkIdx(a, "schema")
    @[fromJsonNode(L.call(req("schema", x.h)))]
  im.fn "fermer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = checkUser[LIndex](L, a, 1, "fermer", "index lucene")
    if x.closed: return @[boolV(false)]
    x.closed = true
    discard L.call(req("fermer", x.h))
    @[boolV(true)]

  discard L.userMeta("lucene", im)
  let m = newLib()
  m.fn "configurer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = L.checkTable(a, 1, "configurer")
    var loaded = false
    withLock lLock:
      {.cast(gcsafe).}:
        loaded = appel != nil
        let b = o.optField("bibliotheque", "")
        if b.len > 0 and not loaded:
          cfgLib = (if b.isAbsolute or L.searchDirs.len == 0: b else: L.searchDirs[0] / b)
    @[boolV(not loaded)]
  m.fn "disponible", proc (L: Interp, a: seq[Value]): seq[Value] =
    var ok = false
    withLock lLock:
      {.cast(gcsafe).}: ok = loadLucene(L.searchDirs)
    @[boolV(ok)]
  m.fn "erreur", proc (L: Interp, a: seq[Value]): seq[Value] =
    var err = ""
    withLock lLock:
      {.cast(gcsafe).}: err = loadError
    @[(if err.len > 0: strV(err) else: nilV)]
  m.fn "version", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[fromJsonNode(L.call(req("version")))]
  m.fn "ouvrir", proc (L: Interp, a: seq[Value]): seq[Value] =
    var dossier = L.optStr(a, 1, "ouvrir", "")
    if dossier.len > 0 and not dossier.isAbsolute:
      dossier = (if L.searchDirs.len > 0: L.searchDirs[0] else: getCurrentDir()) / dossier
    let o = optsArg(a, 2)
    var r = req("ouvrir")
    r["dossier"] = %dossier
    if o != nil:
      r["analyseur"] = %o.optField("analyseur", "")
      r["creer"] = %o.optField("creer", true)
      let s = o.field("schema")
      if s.kind == vkTable: r["schema"] = lowerKeys(L.toJsonNode(s))
    let h = L.call(r).getBiggestInt
    let x = LIndex(h: h)
    L.closers.add proc () =
      if not x.closed:
        x.closed = true
        try: discard L.call(req("fermer", x.h))
        except CatchableError: discard
    @[L.wrap(x, "lucene", im)]
  tableV(m)

registerPackage PackageDef(name: "lucene", open: openLucene,
  description: "Index de recherche plein texte (Lucene++)",
  docs: docs("lucene", [
    "lucene.ouvrir([dossier], [{analyseur=, schema=, creer=vrai}])", "Ouvre (ou crée) l'index Lucene du dossier (relatif : au dossier du programme) ; sans dossier, index en mémoire. analyseur : \"standard\" (défaut), \"francais\", \"anglais\", \"allemand\", \"espagnol\", \"italien\", \"portugais\", \"neerlandais\", \"russe\", \"bresilien\", \"simple\", \"espaces\". schema : {champ = type} avec les types \"texte\" (analysé, stocké), \"cle\" (valeur exacte, identifiant, tri), \"entier\", \"reel\" (intervalles, tri), \"stocke\" (non indexé), \"index\" (analysé, non stocké). Un champ absent du schéma prend son type à la première valeur (texte, entier, reel). Schéma et analyseur sont enregistrés dans l'index.",
    "lucene.configurer({bibliotheque=})", "Avant le premier usage : chemin (ou dossier) de la bibliothèque wdlexis_lucene. Faux si elle est déjà chargée.",
    "lucene.disponible()", "Vrai si la bibliothèque Lucene++ (wdlexis_lucene) est trouvée.",
    "lucene.erreur()", "Pourquoi Lucene n'est pas disponible (nul sinon).",
    "lucene.version()", "Version de Lucene++ (ex. \"Lucene++ 3.0.9\").",
    "idx:ajouter(document)", "Ajoute un document : table champ = valeur (texte, nombre, booléen, ou liste pour un champ à plusieurs valeurs).",
    "idx:remplacer(document, [champ])", "Remplace le document de même clé (premier champ « cle » du schéma, ou champ) ou l'ajoute.",
    "idx:supprimer(requete) | idx:supprimer(champ, valeur)", "Supprime les documents trouvés par la requête, ou ceux dont le champ vaut exactement valeur.",
    "idx:chercher([requete], [{max=10, debut=0, tri=, inverse=faux, champs=}])", "Recherche (syntaxe Lucene : mots, \"phrase exacte\", champ:mot, ET/OU via AND OR NOT + -, joker* et ?, flou~, intervalles annee:[1800 TO 1900], annee:{1800 TO *}). Tous les mots sont requis par défaut ; sans champ, les champs « texte » sont interrogés (ou ceux de champs). Renvoie {total, resultats} ; chaque résultat : {score, numero, document}. tri : champ cle, entier ou reel (défaut : pertinence).",
    "idx:compter([requete])", "Nombre de documents trouvés.",
    "idx:analyser(requete)", "Requête Lucene produite (après analyse), pour comprendre un résultat.",
    "idx:termes(champ, [prefixe], [max=20])", "Termes indexés d'un champ (après analyse) avec leur nombre de documents : {terme, documents} ; utile pour l'autocomplétion.",
    "idx:nombre()", "Nombre de documents de l'index.",
    "idx:schema()", "Types des champs : {champ = type}.",
    "idx:valider()", "Enregistre les modifications sur disque (commit) ; les recherches les voient déjà.",
    "idx:vider()", "Supprime tous les documents.",
    "idx:optimiser()", "Fusionne les segments (index plus compact, recherches plus rapides).",
    "idx:fermer()", "Valide puis ferme l'index (automatique à la fin du programme)."]))
