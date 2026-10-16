# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet llm : modèles de langage (GGUF) avec nimllm
#
#   m = llm.charger("Llama-3.2-1B-Instruct-Q4_K_M.gguf")
#   c = m:conversation{systeme = "Tu es un assistant concis."}
#   ? c:demander("Quelle est la capitale du Japon ?")
#   r = c:demander("Résume ce fichier.", {pieces = {"notes.txt"}, flux = @AFFICHER})
#   ? r.texte, r.tokensgeneres, r.vitesse
#
# Le calcul se fait sur le processeur (aucune bibliothèque externe). Pendant
# une génération l'interpréteur est libéré : l'atelier reste réactif et le
# bouton « Arrêter » interrompt la réponse.

import std/[strutils, tables, os, times, json]
import ../lexis/api
import llm_objets

type
  LChat = ref object of LUser
    c: Chat
    src: LModele               # modèle d'origine (refus d'utilisation après m:fermer()).
  LContexte = ref object of LUser
    x: LlmContext
    src: LModele
  LLogits = ref object of LUser
    v: seq[float32]
  LEchant = ref object of LUser
    s: Sampler

var
  classeModele {.threadvar.}: Classe
  classeChat {.threadvar.}: Classe
  classeContexte {.threadvar.}: Classe
  classeLogits {.threadvar.}: Classe
  classeEchant {.threadvar.}: Classe
  metaReponse {.threadvar.}: LTable

#
# Réponses
#

proc reponseV(L: Interp, r: Reply): Value =
  ## Fiche de réponse ; s'affiche (et se concatène) comme son texte.
  let t = newLTable()
  t.set "texte", strV(r.text)
  t.set "brut", strV(r.raw)
  t.set "fichiers", stringsV(r.files)
  t.set "json", jsonV(r.json)
  t.set "tokensprompt", intV(r.promptTokens)
  t.set "tokensgeneres", intV(r.completionTokens)
  t.set "arret", strV($r.stopReason)
  t.set "secondes", numV(r.seconds)
  t.set "vitesse", numV(r.tokensPerSecond)
  if metaReponse.isNil:
    metaReponse = newLTable()
    let texte = proc (L: Interp, v: Value): string =
      if v.kind == vkTable and v.t.meta == metaReponse: rawToString(v.t.rawGet(cle("texte")))
      else: L.tostr(v)
    metaReponse.set "__tostring", fnV("reponse.texte", proc (L: Interp, a: seq[Value]): seq[Value] =
      @[strV(texte(L, arg(a, 1)))])
    let concat = proc (L: Interp, a: seq[Value]): seq[Value] =
      @[strV(texte(L, arg(a, 1)) & texte(L, arg(a, 2)))]
    metaReponse.set "__concat", fnV("reponse.concat", concat)
    metaReponse.set "__add", fnV("reponse.add", concat)
  t.meta = metaReponse
  tableV(t)

#
# Génération : rappels, arrêt, options
#

proc rappelFlux(L: Interp, f: Value): TokenCallback =
  ## Rappel nimllm appelé pendant `relache` : reprend l'interpréteur pour
  ## appeler la procédure Lexis+ (qui renvoie faux pour interrompre).
  ## Sans procédure : vérifie seulement la demande d'arrêt.
  if f.kind == vkNil:
    return proc (piece: string): bool =
      not L.stopRequested()
  result = proc (piece: string): bool =
    if L.stopRequested(): return false
    var r: seq[Value]
    reprend(L):
      r = L.call(f, @[strV(piece)])
    r.len == 0 or r[0].kind != vkBool or r[0].b

proc fluxDe(L: Interp, a: seq[Value], i: int): (LTable, Value) =
  ## Argument i : table d'options ou procédure de flux.
  let v = arg(a, i)
  if v.kind == vkTable: return (v.t, v.t.field("flux"))
  if v.kind != vkNil and L.callable(v): return (nil, v)
  (nil, nilV)

proc optionsGen(L: Interp, o: LTable, base: GenOptions): GenOptions =
  result = base
  if o.isNil: return
  result.maxTokens = o.optField("maxtokens", result.maxTokens)
  if o.has("echantillonnage"):
    result.sampling = L.versEchantillonnage(o.field("echantillonnage"), result.sampling)
  if o.has("arrets"): result.stop = L.toStrings(o.field("arrets"))

template generation(L: Interp, nom: string, body: untyped) =
  ## Calcul libéré + conversion des erreurs + arrêt demandé.
  protege nom:
    relache(L):
      body
  L.checkStop()

#
# Logits et échantillonneur
#

proc logitsV(v: seq[float32]): Value =
  if classeLogits.isNil:
    classeLogits = newClasse("logits")
    let m = classeLogits.methodes
    m.fn "meilleurs", proc (L: Interp, a: seq[Value]): seq[Value] =
      let l = checkUser[LLogits](L, a, 1, "meilleurs", "logits")
      var res: seq[Value]
      for (id, p) in topTokens(l.v, int(L.optInt(a, 2, "meilleurs", 5))):
        res.add record({"id": intV(id), "proba": numV(float(p))})
      @[listV(res)]
    m.fn "valeur", proc (L: Interp, a: seq[Value]): seq[Value] =
      let l = checkUser[LLogits](L, a, 1, "valeur", "logits")
      let i = int(L.checkInt(a, 2, "valeur"))
      if i < 0 or i >= l.v.len: return @[nilV]
      @[numV(float(l.v[i]))]
    m.fn "liste", proc (L: Interp, a: seq[Value]): seq[Value] =
      @[floatsV(checkUser[LLogits](L, a, 1, "liste", "logits").v)]
    m.fn "argmax", proc (L: Interp, a: seq[Value]): seq[Value] =
      @[intV(argmax(checkUser[LLogits](L, a, 1, "argmax", "logits").v))]
    classeLogits.getter "taille", proc (L: Interp, u: LUser): Value = intV(LLogits(u).v.len)
  classeLogits.enveloppe(LLogits(v: v))

proc echantV(s: Sampler): Value =
  if classeEchant.isNil:
    classeEchant = newClasse("echantillonneur")
    let m = classeEchant.methodes
    m.fn "tirer", proc (L: Interp, a: seq[Value]): seq[Value] =
      let s = checkUser[LEchant](L, a, 1, "tirer", "échantillonneur").s
      let l = checkUser[LLogits](L, a, 2, "tirer", "logits")
      if l.v.len == 0: rtError("tirer : logits vides")
      @[intV(s.sample(l.v))]
    m.fn "accepter", proc (L: Interp, a: seq[Value]): seq[Value] =
      checkUser[LEchant](L, a, 1, "accepter", "échantillonneur").s.accept(int(L.checkInt(a, 2, "accepter")))
      @[]
    classeEchant.getter "parametres", proc (L: Interp, u: LUser): Value = echantillonnageV(LEchant(u).s.params)
  classeEchant.enveloppe(LEchant(s: s))

#
# Contexte (cache KV)
#

proc ouvert(src: LModele) =
  if not src.isNil and src.ferme: rtError("le modèle de cette conversation a été fermé")

proc contexteV(x: LlmContext, src: LModele): Value =
  if classeContexte.isNil:
    let c = newClasse("contexte")
    classeContexte = c
    let m = c.methodes
    template self(fname: string): LlmContext =
      let lc = checkUser[LContexte](L, a, 1, fname, "contexte")
      ouvert(lc.src)
      lc.x
    m.fn "evaluer", proc (L: Interp, a: seq[Value]): seq[Value] =
      let x = self("evaluer")
      let ids = L.toInts(arg(a, 2), "evaluer")
      if ids.len == 0: rtError("evaluer : liste de tokens vide")
      for id in ids:
        if id < 0 or id >= x.model.tokenizer.vocabSize: rtError("evaluer : token hors limites (" & $id & ")")
      if x.nPast + ids.len > x.nCtx: rtError("evaluer : contexte plein (" & $x.nCtx & " tokens)")
      var lg: seq[float32]
      generation(L, "evaluer"): lg = x.eval(ids)
      @[logitsV(lg)]
    m.fn "completer", proc (L: Interp, a: seq[Value]): seq[Value] =
      let x = self("completer")
      let texte = L.checkStr(a, 2, "completer")
      let (o, flux) = L.fluxDe(a, 3)
      var opts = L.optionsGen(o, defaultOptions())
      opts.onToken = L.rappelFlux(flux)
      var r: Reply
      generation(L, "completer"): r = x.complete(texte, opts)
      @[L.reponseV(r)]
    m.fn "generer", proc (L: Interp, a: seq[Value]): seq[Value] =
      let x = self("generer")
      let ids = L.toInts(arg(a, 2), "generer")
      let (o, flux) = L.fluxDe(a, 3)
      var opts = L.optionsGen(o, defaultOptions())
      opts.onToken = L.rappelFlux(flux)
      var r: Reply
      generation(L, "generer"): r = x.generate(ids, opts)
      @[L.reponseV(r)]
    m.fn "reinitialiser", proc (L: Interp, a: seq[Value]): seq[Value] =
      self("reinitialiser").reset()
      @[]
    m.fn "tronquer", proc (L: Interp, a: seq[Value]): seq[Value] =
      let x = self("tronquer")
      x.truncate(max(0, min(x.nPast, int(L.checkInt(a, 2, "tronquer")))))
      @[]
    c.getter "tokens", proc (L: Interp, u: LUser): Value = intV(LContexte(u).x.nPast)
    c.getter "taille", proc (L: Interp, u: LUser): Value = intV(LContexte(u).x.nCtx)
    c.getter "memoire", proc (L: Interp, u: LUser): Value = intV(LContexte(u).x.memoryUsage)
    c.getter "vitesse", proc (L: Interp, u: LUser): Value = numV(LContexte(u).x.tokensPerSecond)
  classeContexte.enveloppe(LContexte(x: x, src: src))

#
# Conversation
#

proc formatDe(s: string): OutputFormat =
  case s.strip.toLowerAscii
  of "", "texte", "text": ofText
  of "markdown", "md": ofMarkdown
  of "json": ofJson
  of "image", "svg": ofImage
  of "audio", "son", "wav": ofAudio
  of "fichier", "file": ofFile
  else: rtError("format inconnu : « " & s & " » (texte, markdown, json, image, audio, fichier)")

proc gardeHistorique(c: Chat, n: int) =
  if c.history.len > n: c.history.setLen(n)

proc creerClasseChat(): Classe =
  let cl = newClasse("conversation")
  let m = cl.methodes
  template self(fname: string): Chat =
    let lc = checkUser[LChat](L, a, 1, fname, "conversation")
    ouvert(lc.src)
    lc.c
  m.fn "demander", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = self("demander")
    let question = L.checkStr(a, 2, "demander")
    let (o, flux) = L.fluxDe(a, 3)
    var pieces: seq[Attachment]
    var format = ofText
    var sortie, schema = ""
    var maxT = 0
    if not o.isNil:
      pieces = L.versPieces(o.field("pieces"), "demander")
      format = formatDe(o.optField("format", ""))
      sortie = o.optField("sortie", "")
      schema = o.optField("schema", "")
      maxT = o.optField("maxtokens", 0)
    let cb = L.rappelFlux(flux)
    let n = c.history.len
    var r: Reply
    try:
      generation(L, "demander"):
        r = c.ask(question, attachments = pieces, format = format, outPath = sortie,
                  schema = schema, onToken = cb, maxTokens = maxT)
    except CatchableError as e:
      c.gardeHistorique(n)                  # pas de question orpheline dans l'historique.
      raise e
    @[L.reponseV(r)]
  m.fn "demanderjson", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = self("demanderjson")
    let question = L.checkStr(a, 2, "demanderjson")
    let schema = L.optStr(a, 3, "demanderjson", "")
    let n = c.history.len
    var j: JsonNode
    try:
      generation(L, "demanderjson"): j = c.askJson(question, schema)
    except CatchableError as e:
      c.gardeHistorique(n)
      raise e
    @[jsonV(j)]
  m.fn "regenerer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = self("regenerer")
    let (_, flux) = L.fluxDe(a, 2)
    let cb = L.rappelFlux(flux)
    var r: Reply
    generation(L, "regenerer"): r = c.regenerate(cb)
    @[L.reponseV(r)]
  m.fn "prolonger", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = self("prolonger")
    var maxT = 256
    var flux = nilV
    if arg(a, 2).kind in {vkInt, vkNum}:
      maxT = int(L.checkInt(a, 2, "prolonger"))
      flux = arg(a, 3)
    else:
      let (o, f) = L.fluxDe(a, 2)
      flux = f
      if not o.isNil: maxT = o.optField("maxtokens", maxT)
    let cb = L.rappelFlux(flux)
    var r: Reply
    generation(L, "prolonger"): r = c.continueReply(maxT, cb)
    @[L.reponseV(r)]
  m.fn "generer", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Produit la réponse de l'assistant à l'historique actuel (sans nouvelle
    ## question) ; utile après c:ajouter(...).
    let c = self("generer")
    let (o, flux) = L.fluxDe(a, 2)
    var opts = L.optionsGen(o, c.options)
    for s in stopStringsFor(c.templ): opts.stop.add s
    opts.onToken = L.rappelFlux(flux)
    var r: Reply
    generation(L, "generer"):
      r = c.ctx.generate(c.promptTokens(), opts)
      r.text = r.raw.strip
    c.history.add Message(role: roleAssistant, content: r.text)
    @[L.reponseV(r)]
  m.fn "ajouter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = self("ajouter")
    c.add(roleDe(L.checkStr(a, 2, "ajouter")), L.checkStr(a, 3, "ajouter"))
    @[]
  m.fn "annuler", proc (L: Interp, a: seq[Value]): seq[Value] =
    self("annuler").undo()
    @[]
  m.fn "reinitialiser", proc (L: Interp, a: seq[Value]): seq[Value] =
    self("reinitialiser").reset()
    @[]
  m.fn "enregistrer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = self("enregistrer")
    let p = L.checkStr(a, 2, "enregistrer")
    protege "enregistrer": c.saveHistory(p)
    @[boolV(true)]
  m.fn "charger", proc (L: Interp, a: seq[Value]): seq[Value] =
    let c = self("charger")
    let p = L.checkStr(a, 2, "charger")
    protege "charger": c.loadHistory(p)
    @[intV(c.history.len)]
  m.fn "etat", proc (L: Interp, a: seq[Value]): seq[Value] = @[strV(self("etat").stats)]
  m.fn "prompt", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Texte exact envoyé au modèle (avec une question supplémentaire facultative).
    let c = self("prompt")
    var msgs = c.messages
    if arg(a, 2).kind != vkNil: msgs.add Message(role: roleUser, content: L.checkStr(a, 2, "prompt"))
    @[strV(renderPrompt(c.templ, msgs))]
  m.fn "tokensprompt", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intsV(self("tokensprompt").promptTokens())]
  template prop(nom: string, body: untyped) =
    cl.getter nom, proc (L {.inject.}: Interp, u: LUser): Value =
      let c {.inject.} = LChat(u).c
      body
  template ecr(nom: string, body: untyped) =
    cl.setter nom, proc (L {.inject.}: Interp, u: LUser, v {.inject.}: Value) =
      let c {.inject.} = LChat(u).c
      body
  proc entier(L: Interp, v: Value, nom: string): int =
    var ok: bool
    result = int(toInteger(v, ok))
    if not ok: rtError(nom & " : nombre entier attendu")
  proc reel(L: Interp, v: Value, nom: string): float =
    var ok: bool
    result = toFloat(v, ok)
    if not ok: rtError(nom & " : nombre attendu")
  prop "systeme": strV(c.system)
  ecr "systeme": c.system = L.tostr(v)
  prop "maxtokens": intV(c.options.maxTokens)
  ecr "maxtokens": c.options.maxTokens = L.entier(v, "maxtokens")
  prop "arrets": stringsV(c.options.stop)
  ecr "arrets": c.options.stop = L.toStrings(v)
  prop "echantillonnage": echantillonnageV(c.options.sampling)
  ecr "echantillonnage": c.setSampling(L.versEchantillonnage(v, c.options.sampling))
  prop "tailleimage": intV(c.imageSize)
  ecr "tailleimage": c.imageSize = L.entier(v, "tailleimage")
  prop "voix": numV(c.voicePitch)
  ecr "voix": c.voicePitch = L.reel(v, "voix")
  prop "essaisjson": intV(c.jsonRetries)
  ecr "essaisjson": c.jsonRetries = L.entier(v, "essaisjson")
  prop "langue": strV(c.lang)
  ecr "langue": c.lang = L.tostr(v)
  prop "sansreflexion": boolV(c.stripThinking)
  ecr "sansreflexion": c.stripThinking = truthy(v)
  prop "gabarit": strV($c.templ)
  ecr "gabarit": c.templ = gabaritDe(L.tostr(v), c.model.tokenizer)
  prop "historique":
    var vs: seq[Value]
    for msg in c.history: vs.add messageV(msg)
    listV(vs)
  prop "messages":
    var vs: seq[Value]
    for msg in c.messages: vs.add messageV(msg)
    listV(vs)
  prop "tokens": intV(c.ctx.nPast)
  prop "contexte": intV(c.ctx.nCtx)
  prop "memoire": intV(c.ctx.memoryUsage)
  cl

proc chatV(c: Chat, src: LModele): Value =
  if classeChat.isNil: classeChat = creerClasseChat()
  classeChat.enveloppe(LChat(c: c, src: src))

#
# Modèle
#

proc checkModele(L: Interp, a: seq[Value], fname: string): LlmModel =
  let lm = checkUser[LModele](L, a, 1, fname, "modèle")
  if lm.ferme: rtError("modèle fermé")
  lm.m

proc modeleV*(m: LlmModel): Value =
  if classeModele.isNil:
    let c = newClasse("modele")
    classeModele = c
    let mt = c.methodes
    mt.fn "conversation", proc (L: Interp, a: seq[Value]): seq[Value] =
      let m = L.checkModele(a, "conversation")
      let o = optsArg(a, 2)
      var systeme = ""
      if arg(a, 2).kind == vkStr: systeme = arg(a, 2).s
      let samp = L.versEchantillonnage((if o.isNil: nilV else: o.field("echantillonnage")))
      var ch: Chat
      protege "conversation":
        ch = newChat(m, system = o.optField("systeme", systeme),
                     nCtx = o.optField("contexte", 4096),
                     templ = gabaritDe(o.optField("gabarit", "auto"), m.tokenizer),
                     sampling = samp, maxTokens = o.optField("maxtokens", 512),
                     lang = o.optField("langue", "fr"))
      if not o.isNil:
        if o.has("arrets"): ch.options.stop = L.toStrings(o.field("arrets"))
        if o.has("tailleimage"): ch.imageSize = o.optField("tailleimage", 512)
        if o.has("voix"): ch.voicePitch = o.optField("voix", 115.0)
        if o.has("essaisjson"): ch.jsonRetries = o.optField("essaisjson", 2)
      @[chatV(ch, LModele(a[0].u))]
    mt.fn "contexte", proc (L: Interp, a: seq[Value]): seq[Value] =
      let m = L.checkModele(a, "contexte")
      @[contexteV(newContext(m, int(L.optInt(a, 2, "contexte", 2048))), LModele(a[0].u))]
    mt.fn "decrire", proc (L: Interp, a: seq[Value]): seq[Value] = @[strV(L.checkModele(a, "decrire").describe)]
    mt.fn "vecteur", proc (L: Interp, a: seq[Value]): seq[Value] =
      let m = L.checkModele(a, "vecteur")
      let s = L.checkStr(a, 2, "vecteur")
      var v: seq[float32]
      generation(L, "vecteur"): v = m.embed(s)
      @[floatsV(v)]
    mt.fn "perplexite", proc (L: Interp, a: seq[Value]): seq[Value] =
      let m = L.checkModele(a, "perplexite")
      let s = L.checkStr(a, 2, "perplexite")
      var p: float
      generation(L, "perplexite"): p = m.perplexity(s)
      @[numV(p)]
    mt.fn "appliquerlora", proc (L: Interp, a: seq[Value]): seq[Value] =
      let m = L.checkModele(a, "appliquerlora")
      let p = L.checkStr(a, 2, "appliquerlora")
      generation(L, "appliquerlora"): m.applyLora(p)
      @[boolV(true)]
    mt.fn "retirerlora", proc (L: Interp, a: seq[Value]): seq[Value] =
      L.checkModele(a, "retirerlora").removeLora()
      @[]
    mt.fn "fermer", proc (L: Interp, a: seq[Value]): seq[Value] =
      let lm = checkUser[LModele](L, a, 1, "fermer", "modèle")
      if not lm.ferme:
        lm.ferme = true
        lm.m.close()
      @[boolV(true)]
    template prop(nom: string, body: untyped) =
      c.getter nom, proc (L: Interp, u: LUser): Value =
        let m {.inject.} = LModele(u).m
        body
    prop "tokeniseur": tokV(m.tokenizer)
    prop "nom": strV(m.cfg.name)
    prop "architecture": strV(m.cfg.arch)
    prop "chemin": strV(m.path)
    prop "couches": intV(m.cfg.nLayers)
    prop "dimension": intV(m.cfg.dim)
    prop "tetes": intV(m.cfg.nHeads)
    prop "tetes_kv": intV(m.cfg.nKvHeads)
    prop "vocabulaire": intV(m.cfg.vocab)
    prop "contexte_max": intV(m.cfg.ctxTrain)
    prop "parametres": intV(m.paramCount)
    prop "gabarit": strV($detectTemplate(m.tokenizer))
  classeModele.enveloppe(LModele(m: m))

#
# Paquet
#

proc openLlm(L: Interp): Value =
  let m = newLib()
  m.fn "charger", proc (L: Interp, a: seq[Value]): seq[Value] =
    let path = L.checkStr(a, 1, "charger")
    let o = optsArg(a, 2)
    var lm: LlmModel
    generation(L, "charger"):
      lm = loadModel(path, threads = o.optField("fils", 0), verbose = o.optField("verbeux", false))
    let v = modeleV(lm)
    let u = LModele(v.u)
    L.closers.add proc () =
      if not u.ferme:
        u.ferme = true
        u.m.close()
    @[v]
  m.fn "version", proc (L: Interp, a: seq[Value]): seq[Value] = @[strV(nimllmVersion)]
  m.fn "fils", proc (L: Interp, a: seq[Value]): seq[Value] =
    if arg(a, 1).kind != vkNil: setThreads(int(L.checkInt(a, 1, "fils")))
    @[intV(numThreads())]
  m.fn "echantillonnage", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[echantillonnageV(L.versEchantillonnage(arg(a, 1)))]
  m.fn "glouton", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[echantillonnageV(L.versEchantillonnage(arg(a, 1), greedySampling()))]
  m.fn "echantillonneur", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[echantV(newSampler(L.versEchantillonnage(arg(a, 1))))]
  m.fn "joindre", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkStr(a, 1, "joindre")
    var x: Attachment
    protege "joindre": x = attach(p)
    @[pieceV(x)]
  m.fn "joindretexte", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[pieceV(attachText(L.checkStr(a, 1, "joindretexte"), L.checkStr(a, 2, "joindretexte")))]
  m.fn "joindredonnees", proc (L: Interp, a: seq[Value]): seq[Value] =
    var x: Attachment
    protege "joindredonnees": x = attachData(L.checkStr(a, 1, "joindredonnees"), L.checkStr(a, 2, "joindredonnees"))
    @[pieceV(x)]
  m.fn "extrairejson", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkStr(a, 1, "extrairejson")
    try: @[jsonV(extractJson(s))]
    except CatchableError: @[nilV]
  m.fn "sansbalises", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV(stripFences(L.checkStr(a, 1, "sansbalises")))]
  m.fn "similarite", proc (L: Interp, a: seq[Value]): seq[Value] =
    let x = L.toFloats(arg(a, 1), "similarite")
    let y = L.toFloats(arg(a, 2), "similarite")
    if x.len != y.len or x.len == 0: rtError("similarite : vecteurs de même longueur attendus")
    @[numV(cosineSimilarity(x, y))]
  m.fn "prompt", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Texte d'un dialogue mis en forme selon un gabarit.
    let k = gabaritDe(L.checkStr(a, 1, "prompt"))
    if k == tplAuto: rtError("prompt : précisez le gabarit (llama3, chatml, mistral...)")
    @[strV(renderPrompt(k, L.versMessages(arg(a, 2)), optBool(a, 3, true)))]
  m.fn "gabarits", proc (L: Interp, a: seq[Value]): seq[Value] =
    var s: seq[string]
    for k in ChatTemplateKind: s.add $k
    @[stringsV(s)]
  m.fn "tokeniseur", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Tokeniseur seul, lu dans un fichier GGUF.
    let p = L.checkStr(a, 1, "tokeniseur")
    var t: Tokenizer
    protege "tokeniseur":
      let g = openGguf(p)
      try: t = tokenizerFromGguf(g)
      finally: g.close()
    @[tokV(t)]
  m.fn "predecouper", proc (L: Interp, a: seq[Value]): seq[Value] =
    let s = L.checkStr(a, 1, "predecouper")
    let mode = case L.optStr(a, 2, "predecouper", "llama3").toLowerAscii
      of "qwen2", "qwen": ptQwen2
      of "gpt2": ptGpt2
      else: ptLlama3
    @[stringsV(preTokenize(s, mode))]
  tableV(m)

registerPackage PackageDef(name: "llm", open: openLlm,
  description: "Modèles de langage GGUF (Llama 3, Mistral, Qwen) : dialogue, pièces jointes, JSON, image, audio",
  docs: docs("llm", [
    "llm.charger(chemin, {fils=0, verbeux=faux})", "Charge un modèle GGUF (fichier « mappé » : quasi instantané) ; renvoie un modèle.",
    "llm.version()", "Version de la bibliothèque nimllm.",
    "llm.fils([n])", "Nombre de fils de calcul (0 = tous les cœurs) ; renvoie le nombre utilisé.",
    "llm.echantillonnage([table])", "Réglages d'échantillonnage par défaut (complétés par la table) : temperature, topk, topp, minp, repetition, fenetre, presence, frequence, graine, biais.",
    "llm.glouton([table])", "Réglages du décodage glouton (déterministe).",
    "llm.echantillonneur([reglages])", "Échantillonneur manuel : s:tirer(logits), s:accepter(id).",
    "llm.joindre(chemin)", "Pièce jointe lue sur le disque (texte, CSV, JSON, PDF, PNG/BMP, WAV...).",
    "llm.joindretexte(nom, contenu)", "Pièce jointe construite en mémoire.",
    "llm.joindredonnees(nom, octets)", "Pièce jointe à partir d'octets (le type est déduit du nom et du contenu).",
    "llm.extrairejson(texte)", "Premier objet JSON trouvé dans un texte (table) ou nul.",
    "llm.sansbalises(texte)", "Retire les balises ``` d'un bloc de code.",
    "llm.similarite(v1, v2)", "Similarité cosinus de deux vecteurs (m:vecteur).",
    "llm.prompt(gabarit, messages[, suite=vrai])", "Texte d'un dialogue {{role=, contenu=}...} mis en forme (llama3, chatml, mistral, llama2, gemma, phi3).",
    "llm.gabarits()", "Liste des gabarits de conversation.",
    "llm.tokeniseur(chemin)", "Tokeniseur seul lu dans un fichier GGUF.",
    "llm.predecouper(texte[, mode])", "Pré-découpage avant BPE (llama3, qwen2, gpt2).",
    "m:conversation({systeme=, contexte=4096, maxtokens=512, echantillonnage=, gabarit=\"auto\", langue=\"fr\", arrets=})", "Nouvelle conversation (le texte seul est accepté comme prompt système).",
    "m:contexte([taille])", "Contexte brut (cache KV) : evaluer, completer, generer.",
    "m:decrire()", "Résumé du modèle.",
    "m:vecteur(texte)", "Vecteur (embedding) d'un texte.",
    "m:perplexite(texte)", "Perplexité d'un texte (plus elle est basse, plus le texte est attendu).",
    "m:appliquerlora(chemin)", "Applique un adaptateur LoRA (.lora.gguf) à la volée.",
    "m:retirerlora()", "Retire l'adaptateur LoRA.",
    "m:fermer()", "Libère le modèle.",
    "m.tokeniseur", "Tokeniseur du modèle (propriétés : nom, architecture, couches, dimension, vocabulaire, contexte_max, parametres, gabarit).",
    "c:demander(question[, options | @flux])", "Réponse (fiche texte, brut, fichiers, json, tokensprompt, tokensgeneres, arret, secondes, vitesse ; s'affiche comme son texte). Options : pieces, format (texte, markdown, json, image, audio, fichier), sortie, schema, maxtokens, flux=@proc(morceau) qui renvoie faux pour interrompre.",
    "c:demanderjson(question[, schema])", "Réponse JSON convertie en table (clefs en majuscules).",
    "c:regenerer([@flux])", "Nouveau tirage de la dernière réponse.",
    "c:prolonger([maxtokens, @flux])", "Prolonge la dernière réponse.",
    "c:generer([options | @flux])", "Réponse de l'assistant à l'historique actuel (après c:ajouter).",
    "c:ajouter(role, texte)", "Ajoute un message (systeme, utilisateur, assistant) : exemples « few-shot », résultats d'outils.",
    "c:annuler()", "Retire le dernier échange.",
    "c:reinitialiser()", "Oublie l'historique (garde le prompt système).",
    "c:enregistrer(chemin)", "Enregistre la conversation (JSON).",
    "c:charger(chemin)", "Recharge une conversation ; renvoie le nombre de messages.",
    "c:etat()", "État du contexte (tokens, messages, vitesse).",
    "c:prompt([question])", "Texte exact envoyé au modèle.",
    "c:tokensprompt()", "Tokens de l'historique mis en forme.",
    "c.systeme", "Propriétés : systeme, maxtokens, arrets, echantillonnage, tailleimage, voix, essaisjson, langue, sansreflexion, gabarit ; lecture seule : historique, messages, tokens, contexte, memoire.",
    "x:evaluer(ids)", "Ajoute des tokens au contexte et renvoie les logits du dernier.",
    "x:completer(texte[, options | @flux])", "Complétion brute (sans gabarit de conversation).",
    "x:generer(ids[, options | @flux])", "Génère une suite à partir de tokens.",
    "x:reinitialiser()", "Vide le contexte.",
    "x:tronquer(n)", "Ne garde que les n premiers tokens.",
    "l:meilleurs([n])", "Les n tokens les plus probables : {{id=, proba=}...}.",
    "l:valeur(id)", "Logit d'un token.",
    "l:argmax()", "Token le plus probable.",
    "s:tirer(logits)", "Tire un token selon les réglages.",
    "s:accepter(id)", "Mémorise un token (pénalités de répétition).",
    "t:encoder(texte[, bos=faux, speciaux=vrai])", "Liste des identifiants de tokens.",
    "t:decoder(ids[, speciaux=faux])", "Texte d'une liste de tokens.",
    "t:morceau(id[, special=faux])", "Texte d'un token.",
    "t:id(texte)", "Identifiant d'un token (nul s'il n'existe pas).",
    "t:estspecial(id)", "Vrai pour un token spécial.",
    "t:enregistrer(chemin)", "Enregistre le tokeniseur dans un fichier GGUF.",
    "t.taille", "Propriétés : taille, bos, eos, pad, inconnu, fins, fusions, type, gabarit, ajoutebos.",
    "p:texte([max])", "Texte inséré dans le message (propriétés : nom, type, mime, contenu, taille, largeur, hauteur, image)."]))
