# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - outils communs aux paquets d'intelligence artificielle
#   (llm, gguf, dessin, audio, tenseur, entrainement), construits sur nimllm.
#
# nimllm est une bibliothèque 100 % Nim (aucune bibliothèque externe) :
# inférence GGUF (Llama 3.x, Mistral, Qwen), dialogue, pièces jointes, sorties
# texte / JSON / image / audio, tenseurs à différentiation automatique,
# entraînement (LoRA, création de modèles), quantification.
#
# Ce module définit les objets natifs partagés entre paquets (un tokeniseur
# créé par `entrainement` s'utilise comme celui d'un modèle chargé par `llm`),
# les conversions de valeurs et les règles d'exécution :
#   * les calculs longs libèrent l'interpréteur (L.blocking) : l'atelier, les
#     tâches et les fenêtres restent réactifs ;
#   * les rappels Lexis+ (affichage au fil de l'eau, journal d'entraînement...)
#     reprennent l'interpréteur le temps de leur exécution ;
#   * le bouton « Arrêter » de l'atelier interrompt la génération ou
#     l'entraînement en cours.

import std/[strutils, tables, json, math, random]
import ../lexis/api
import ../nimllm
from ../lexis/fonctions import fromJsonNode, toJsonNode

export nimllm, json

#
# Exécution
#

template relache*(L: Interp, body: untyped) =
  ## Exécute `body` sans tenir l'interpréteur (calcul long).
  L.blocking:
    body

template reprend*(L: Interp, body: untyped) =
  ## Dans un rappel appelé pendant `relache` : reprend l'interpréteur.
  L.enter()
  try:
    body
  finally:
    L.leave()

proc ecrire*(L: Interp, s: string) =
  ## Écrit une ligne dans la console du programme (tient l'interpréteur).
  if L.output != nil: L.output(s & "\n")
  else: echo s

proc erreurNim*(e: ref Exception): string =
  ## Message d'erreur nimllm présenté à l'utilisateur Lexis+.
  result = e.msg
  if result.len == 0: result = $e.name

template protege*(nom: string, body: untyped) =
  ## Convertit les erreurs Nim (fichier absent, format invalide...) en
  ## erreurs Lexis+ interceptables par essayer ... capturer.
  try:
    body
  except LexisError, LexisStop:
    raise
  except CatchableError as e:
    rtError(nom & " : " & erreurNim(e))

#
# Conversions de valeurs
#

proc listV*(vs: seq[Value]): Value =
  let t = newLTable(vs.len)
  for v in vs: t.arr.add v
  tableV(t)

proc intsV*(xs: openArray[int]): Value =
  let t = newLTable(xs.len)
  for x in xs: t.arr.add intV(x)
  tableV(t)

proc floatsV*(xs: openArray[float32]): Value =
  let t = newLTable(xs.len)
  for x in xs: t.arr.add numV(float(x))
  tableV(t)

proc stringsV*(xs: openArray[string]): Value =
  let t = newLTable(xs.len)
  for x in xs: t.arr.add strV(x)
  tableV(t)

proc listItems*(v: Value): seq[Value] =
  ## Éléments 1..n d'une liste (vide si ce n'est pas une table).
  if v.kind == vkTable:
    for i in 1 .. v.t.rawLen: result.add v.t.rawGet(intV(i))

proc toInts*(L: Interp, v: Value, fname: string): seq[int] =
  case v.kind
  of vkTable:
    for x in listItems(v):
      var ok: bool
      let n = toInteger(x, ok)
      if not ok: rtError(fname & " : liste d'entiers attendue")
      result.add int(n)
  of vkInt, vkNum:
    var ok: bool
    result.add int(toInteger(v, ok))
  of vkNil: discard
  else: rtError(fname & " : liste d'entiers attendue, " & typeName(v) & " reçu")

proc toFloats*(L: Interp, v: Value, fname: string): seq[float32] =
  case v.kind
  of vkTable:
    for x in listItems(v):
      var ok: bool
      let n = toFloat(x, ok)
      if not ok: rtError(fname & " : liste de nombres attendue")
      result.add float32(n)
  of vkInt, vkNum:
    var ok: bool
    result.add float32(toFloat(v, ok))
  of vkNil: discard
  else: rtError(fname & " : liste de nombres attendue, " & typeName(v) & " reçu")

proc toStrings*(L: Interp, v: Value): seq[string] =
  ## Une chaîne seule ou une liste de chaînes.
  case v.kind
  of vkTable:
    for x in listItems(v): result.add L.tostr(x)
  of vkNil: discard
  else: result.add L.tostr(v)

proc jsonV*(j: JsonNode): Value =
  if j.isNil: nilV else: fromJsonNode(j)

proc optsArg*(a: seq[Value], i: int): LTable =
  ## Table d'options en position i (nil si absente).
  if arg(a, i).kind == vkTable: a[i - 1].t else: nil

proc has*(t: LTable, name: string): bool =
  not t.isNil and t.rawGet(cle(name)).kind != vkNil

#
# Objets avec propriétés (obj.nom en lecture / écriture) et méthodes (obj:f())
#

type
  Getter* = proc (L: Interp, u: LUser): Value {.closure.}
  Setter* = proc (L: Interp, u: LUser, v: Value) {.closure.}

  Classe* = ref object
    nom*: string
    methodes*: LTable
    getters*: Table[string, Getter]
    setters*: Table[string, Setter]
    mt: LTable                    # métatable (créée à la première utilisation).

proc newClasse*(nom: string): Classe =
  Classe(nom: nom, methodes: newLib())

proc getter*(c: Classe, nom: string, g: Getter) = c.getters[cle(nom)] = g
proc setter*(c: Classe, nom: string, s: Setter) = c.setters[cle(nom)] = s

proc construireMeta(c: Classe): LTable =
  let m = newLTable()
  let cl = c
  m.set "__index", fnV(c.nom & ".index", proc (L: Interp, a: seq[Value]): seq[Value] =
    let key = arg(a, 2)
    if key.kind != vkStr: return @[nilV]
    let k = cle(key.s)
    let f = cl.methodes.rawGet(k)
    if f.kind != vkNil: return @[f]
    if cl.getters.hasKey(k): return @[cl.getters[k](L, a[0].u)]
    @[nilV])
  m.set "__newindex", fnV(c.nom & ".newindex", proc (L: Interp, a: seq[Value]): seq[Value] =
    let key = arg(a, 2)
    let k = if key.kind == vkStr: cle(key.s) else: ""
    if not cl.setters.hasKey(k):
      rtError("propriété « " & k.toLowerAscii & " » inconnue ou en lecture seule (" & cl.nom & ")")
    cl.setters[k](L, a[0].u, arg(a, 3))
    @[])
  m.set "__name", strV(c.nom)
  m

proc meta*(c: Classe): LTable =
  if c.mt.isNil: c.mt = construireMeta(c)
  c.mt

proc enveloppe*(c: Classe, u: LUser): Value =
  ## Valeur Lexis+ d'un objet natif de la classe.
  u.tname = c.nom
  u.meta = c.meta
  userV(u)

proc moi*[T: LUser](L: Interp, a: seq[Value], fname, tname: string): T =
  checkUser[T](L, a, 1, fname, tname)

#
# Objets partagés
#

type
  LTok* = ref object of LUser
    tok*: Tokenizer
  LModele* = ref object of LUser
    m*: LlmModel
    ferme*: bool
  LImage* = ref object of LUser
    img*: Image
  LTenseur* = ref object of LUser
    t*: Tensor
  LOptim* = ref object of LUser
    o*: Optimizer
  LPiece* = ref object of LUser
    p*: Attachment

proc checkTok*(L: Interp, a: seq[Value], i: int, fname: string): Tokenizer =
  checkUser[LTok](L, a, i, fname, "tokeniseur").tok

proc checkTenseur*(L: Interp, a: seq[Value], i: int, fname: string): Tensor =
  checkUser[LTenseur](L, a, i, fname, "tenseur").t

proc checkImage*(L: Interp, a: seq[Value], i: int, fname: string): Image =
  checkUser[LImage](L, a, i, fname, "image").img

proc tenseurs*(L: Interp, v: Value, fname: string): seq[Tensor] =
  ## Liste de tenseurs (paramètres d'un optimiseur...).
  for x in listItems(v):
    if x.kind != vkUser or not (x.u of LTenseur): rtError(fname & " : liste de tenseurs attendue")
    result.add LTenseur(x.u).t

#
# Échantillonnage : table Lexis+ <-> SamplerParams
#
#   {temperature = 0.7, topk = 40, topp = 0.95, minp = 0.05, repetition = 1.1,
#    fenetre = 64, presence = 0, frequence = 0, graine = -1, biais = {[id] = -100}}

proc echantillonnageV*(p: SamplerParams): Value =
  let t = newLTable()
  t.set "temperature", numV(p.temperature)
  t.set "topk", intV(p.topK)
  t.set "topp", numV(p.topP)
  t.set "minp", numV(p.minP)
  t.set "repetition", numV(p.repeatPenalty)
  t.set "fenetre", intV(p.repeatLastN)
  t.set "presence", numV(p.presencePenalty)
  t.set "frequence", numV(p.frequencyPenalty)
  t.set "graine", intV(p.seed)
  let b = newLTable()
  for id, v in p.logitBias: b.rawSet(intV(id), numV(v))
  t.set "biais", tableV(b)
  tableV(t)

proc versEchantillonnage*(L: Interp, v: Value, base = defaultSampling()): SamplerParams =
  ## Table partielle : les clefs absentes gardent la valeur de `base`.
  ## « glouton = vrai » part du décodage glouton.
  result = base
  if v.kind != vkTable: return
  let t = v.t
  if t.optField("glouton", false): result = greedySampling()
  result.temperature = t.optField("temperature", result.temperature)
  result.topK = t.optField("topk", result.topK)
  result.topP = t.optField("topp", result.topP)
  result.minP = t.optField("minp", result.minP)
  result.repeatPenalty = t.optField("repetition", result.repeatPenalty)
  result.repeatLastN = t.optField("fenetre", result.repeatLastN)
  result.presencePenalty = t.optField("presence", result.presencePenalty)
  result.frequencyPenalty = t.optField("frequence", result.frequencyPenalty)
  result.seed = t.optField("graine", result.seed)
  let b = t.field("biais")
  if b.kind == vkTable:
    for (k, x) in b.t.snapshotPairs:
      var ok1, ok2: bool
      let id = toInteger(k, ok1)
      let f = toFloat(x, ok2)
      if ok1 and ok2: result.logitBias[int(id)] = f

#
# Gabarits de conversation et types GGML
#

proc gabaritDe*(s: string, tok: Tokenizer = nil): ChatTemplateKind =
  let n = s.strip.toLowerAscii
  if n in ["", "auto"]:
    return (if tok.isNil: tplAuto else: detectTemplate(tok))
  for k in ChatTemplateKind:
    if $k == n: return k
  rtError("gabarit inconnu : « " & s & " » (auto, llama3, chatml, mistral, llama2, gemma, phi3, raw)")

proc nomType*(t: GgmlType): string = ($t).replace("gt", "").toLowerAscii

proc typeDe*(s: string): GgmlType =
  try: parseGgmlType(s.strip.toLowerAscii)
  except CatchableError: rtError("type de poids inconnu : « " & s & " » (f32, f16, bf16, q8_0, q6_k, q5_k, q5_0, q5_1, q4_k, q4_0, q4_1...)")

#
# Messages (dialogues)
#

proc roleDe*(s: string): Role =
  case s.strip.toLowerAscii
  of "system", "systeme", "système": roleSystem
  of "assistant", "ia", "modele", "modèle": roleAssistant
  of "user", "utilisateur", "vous": roleUser
  else: rtError("rôle inconnu : « " & s & " » (systeme, utilisateur, assistant)")

proc messageV*(m: Message): Value =
  let t = newLTable()
  t.set "role", strV($m.role)
  t.set "contenu", strV(m.content)
  tableV(t)

proc versMessages*(L: Interp, v: Value): seq[Message] =
  ## Liste de messages {role = "utilisateur", contenu = "..."}, ou fiche
  ## {question = "...", reponse = "..."} (deux messages).
  for x in listItems(v):
    if x.kind != vkTable: rtError("message attendu : {role = ..., contenu = ...}")
    let t = x.t
    if t.has("question"):
      result.add Message(role: roleUser, content: t.optField("question", ""))
      if t.has("reponse"):
        result.add Message(role: roleAssistant, content: t.optField("reponse", ""))
    else:
      result.add Message(role: roleDe(t.optField("role", "user")),
                         content: t.optField("contenu", t.optField("content", "")))

#
# Rng des paquets tenseur / entrainement (un par interpréteur)
#

type RngRef* = ref object of RootObj
  r*: Rand

proc rngDe*(L: Interp): var Rand =
  if not L.ext.hasKey("llm.rng"): L.ext["llm.rng"] = RngRef(r: initRand(2024))
  RngRef(L.ext["llm.rng"]).r

proc fmtNum*(f: float, decimales: int): string = formatFloat(f, ffDecimal, decimales)
