# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet gguf : inspection et quantification de fichiers GGUF
#   (format des modèles de llama.cpp, Ollama, LM Studio)
#
#   g = gguf.ouvrir("modele.gguf")
#   ? g:decrire(8)
#   ? g:texte("general.architecture")
#   pour chaque t dans g:tenseurs()
#     ? t.nom, t.type, t.elements
#   suivant
#   g:fermer()
#   gguf.quantifiermodele("modele-f32.gguf", "modele-q4_k.gguf", "q4_k")

import std/[strutils, tables, os]
import ../lexis/api
import llm_objets

type
  LGguf = ref object of LUser
    g: GgufFile
    ferme: bool

var classeGguf {.threadvar.}: Classe

proc ggufValeur(v: GgufValue): Value =
  if v.isNil: return nilV
  case v.kind
  of gvU8, gvI8, gvU16, gvI16, gvU32, gvI32, gvU64, gvI64: intV(v.i)
  of gvF32, gvF64: numV(v.f)
  of gvBool: boolV(v.b)
  of gvString: strV(v.s)
  of gvArray:
    var vs: seq[Value]
    for x in v.arr: vs.add ggufValeur(x)
    listV(vs)

proc checkGguf(L: Interp, a: seq[Value], fname: string): GgufFile =
  let x = checkUser[LGguf](L, a, 1, fname, "fichier gguf")
  if x.ferme: rtError("fichier gguf fermé")
  x.g

proc ggufV(g: GgufFile): Value =
  if classeGguf.isNil:
    let c = newClasse("gguf")
    classeGguf = c
    let m = c.methodes
    m.fn "decrire", proc (L: Interp, a: seq[Value]): seq[Value] =
      @[strV(L.checkGguf(a, "decrire").describe(int(L.optInt(a, 2, "decrire", 10))))]
    m.fn "existe", proc (L: Interp, a: seq[Value]): seq[Value] =
      @[boolV(L.checkGguf(a, "existe").has(L.checkStr(a, 2, "existe")))]
    m.fn "valeur", proc (L: Interp, a: seq[Value]): seq[Value] =
      let g = L.checkGguf(a, "valeur")
      @[ggufValeur(g.kv.getOrDefault(L.checkStr(a, 2, "valeur")))]
    m.fn "texte", proc (L: Interp, a: seq[Value]): seq[Value] =
      @[strV(L.checkGguf(a, "texte").getStr(L.checkStr(a, 2, "texte"), L.optStr(a, 3, "texte", "")))]
    m.fn "entier", proc (L: Interp, a: seq[Value]): seq[Value] =
      @[intV(L.checkGguf(a, "entier").getInt(L.checkStr(a, 2, "entier"), int(L.optInt(a, 3, "entier", 0))))]
    m.fn "reel", proc (L: Interp, a: seq[Value]): seq[Value] =
      @[numV(L.checkGguf(a, "reel").getFloat(L.checkStr(a, 2, "reel"), L.optNum(a, 3, "reel", 0.0)))]
    m.fn "cles", proc (L: Interp, a: seq[Value]): seq[Value] =
      var s: seq[string]
      for k in L.checkGguf(a, "cles").kv.keys: s.add k
      @[stringsV(s)]
    m.fn "tenseurs", proc (L: Interp, a: seq[Value]): seq[Value] =
      var vs: seq[Value]
      for nom, t in L.checkGguf(a, "tenseurs").tensors:
        vs.add record({"nom": strV(nom), "type": strV(nomType(t.typ)), "dims": intsV(t.dims),
                       "elements": intV(t.numElements), "octets": intV(t.byteSize)})
      @[listV(vs)]
    m.fn "tenseur", proc (L: Interp, a: seq[Value]): seq[Value] =
      ## Valeurs d'un tenseur, déquantifiées en nombres (limite facultative).
      let g = L.checkGguf(a, "tenseur")
      let nom = L.checkStr(a, 2, "tenseur")
      let maxi = int(L.optInt(a, 3, "tenseur", 0))
      var v: seq[float32]
      protege "tenseur":
        relache(L): v = g.tensorF32(nom)
      if maxi > 0 and v.len > maxi: v.setLen(maxi)
      @[floatsV(v)]
    m.fn "fermer", proc (L: Interp, a: seq[Value]): seq[Value] =
      let x = checkUser[LGguf](L, a, 1, "fermer", "fichier gguf")
      if not x.ferme:
        x.ferme = true
        x.g.close()
      @[boolV(true)]
    c.getter "version", proc (L: Interp, u: LUser): Value = intV(LGguf(u).g.version)
    c.getter "chemin", proc (L: Interp, u: LUser): Value = strV(LGguf(u).g.path)
    c.getter "alignement", proc (L: Interp, u: LUser): Value = intV(LGguf(u).g.alignment)
    c.getter "architecture", proc (L: Interp, u: LUser): Value = strV(LGguf(u).g.getStr("general.architecture"))
  classeGguf.enveloppe(LGguf(g: g))

proc openGgufLib(L: Interp): Value =
  let m = newLib()
  m.fn "ouvrir", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkStr(a, 1, "ouvrir")
    var g: GgufFile
    protege "ouvrir": g = openGguf(p)
    let v = ggufV(g)
    let x = LGguf(v.u)
    L.closers.add proc () =
      if not x.ferme:
        x.ferme = true
        x.g.close()
    @[v]
  m.fn "quantifiermodele", proc (L: Interp, a: seq[Value]): seq[Value] =
    let src = L.checkStr(a, 1, "quantifiermodele")
    let dst = L.checkStr(a, 2, "quantifiermodele")
    let t = typeDe(L.optStr(a, 3, "quantifiermodele", "q4_k"))
    let garder = optBool(a, 4, true)
    protege "quantifiermodele":
      relache(L): quantizeModel(src, dst, t, garder)
    @[strV(dst)]
  m.fn "fusionnerlora", proc (L: Interp, a: seq[Value]): seq[Value] =
    let base = L.checkStr(a, 1, "fusionnerlora")
    let adapt = L.checkStr(a, 2, "fusionnerlora")
    let dst = L.checkStr(a, 3, "fusionnerlora")
    let t = typeDe(L.optStr(a, 4, "fusionnerlora", "q8_0"))
    protege "fusionnerlora":
      relache(L): mergeLora(base, adapt, dst, t)
    @[strV(dst)]
  m.fn "types", proc (L: Interp, a: seq[Value]): seq[Value] =
    var s: seq[string]
    for t in quantizableTypes: s.add nomType(t)
    @[stringsV(s)]
  m.fn "bitsparpoids", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[numV(bitsPerWeight(typeDe(L.checkStr(a, 1, "bitsparpoids"))))]
  m.fn "quantifier", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Aller-retour d'une liste de valeurs : {octets = taille quantifiée,
    ## valeurs = valeurs relues, erreur = écart maximal}.
    let t = typeDe(L.checkStr(a, 1, "quantifier"))
    let v = L.toFloats(arg(a, 2), "quantifier")
    let bs = blockSize(t)
    if v.len == 0 or v.len mod bs != 0:
      rtError("quantifier : le nombre de valeurs doit être un multiple de " & $bs & " pour " & nomType(t))
    var q: seq[uint8]
    var back: seq[float32]
    protege "quantifier":
      q = quantize(t, v)
      back = dequantRow(t, unsafeAddr q[0], v.len)
    var e = 0.0
    for i in 0 ..< v.len: e = max(e, abs(float(v[i]) - float(back[i])))
    @[record({"octets": intV(q.len), "valeurs": floatsV(back), "erreur": numV(e)})]
  tableV(m)

registerPackage PackageDef(name: "gguf", open: openGgufLib,
  description: "Fichiers GGUF : métadonnées, tenseurs, quantification, fusion LoRA",
  docs: docs("gguf", [
    "gguf.ouvrir(chemin)", "Ouvre un fichier GGUF (lecture seule, mappé en mémoire).",
    "gguf.quantifiermodele(entree, sortie[, type=\"q4_k\", garder_sortie=vrai])", "Re-quantifie un modèle (f32, f16, bf16, q8_0, q6_k, q5_k, q5_0, q5_1, q4_k, q4_0, q4_1...).",
    "gguf.fusionnerlora(base, adaptateur, sortie[, type=\"q8_0\"])", "Fusionne un adaptateur LoRA dans un nouveau modèle autonome.",
    "gguf.types()", "Types de poids utilisables pour la quantification.",
    "gguf.bitsparpoids(type)", "Nombre moyen de bits par poids d'un type.",
    "gguf.quantifier(type, valeurs)", "Quantifie puis relit une liste : {octets=, valeurs=, erreur=}.",
    "g:decrire([max_tenseurs])", "Résumé du fichier.",
    "g:existe(cle)", "Vrai si la métadonnée existe.",
    "g:valeur(cle)", "Valeur d'une métadonnée (nombre, texte, logique ou liste).",
    "g:texte(cle[, defaut])", "Métadonnée texte.",
    "g:entier(cle[, defaut])", "Métadonnée entière.",
    "g:reel(cle[, defaut])", "Métadonnée réelle.",
    "g:cles()", "Liste des clefs de métadonnées.",
    "g:tenseurs()", "Liste des tenseurs : {nom=, type=, dims=, elements=, octets=}.",
    "g:tenseur(nom[, max])", "Valeurs d'un tenseur (déquantifiées).",
    "g:fermer()", "Ferme le fichier (propriétés : version, chemin, alignement, architecture)."]))
