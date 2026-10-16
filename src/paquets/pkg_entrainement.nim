# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet entrainement : créer, entraîner et spécialiser des modèles
#   de langage (tokeniseur BPE, Transformer type Llama, LoRA, export GGUF).
#
#   tok = entrainement.tokeniseur(texte, {taille = 512})
#   m = entrainement.nouveau(tok, {dimension = 128, couches = 4, tetes = 4, contexte = 128})
#   d = entrainement.textes(tok, texte)
#   m:entrainer(d, {etapes = 150, lot = 8, sequence = 64, lr = 0.003})
#   m:enregistrer("mini.gguf")                 && utilisable ensuite par llm.charger
#
# L'entraînement libère l'interpréteur ; le journal s'affiche dans la console
# (ou est transmis à une procédure) et le bouton « Arrêter » l'interrompt.

import std/[strutils, math, os, random]
import ../lexis/api
import llm_objets

type
  LTransfo = ref object of LUser
    t: Transformer
  LDonnees = ref object of LUser
    d: Dataset

var
  classeTransfo {.threadvar.}: Classe
  classeDonnees {.threadvar.}: Classe

proc checkDonnees(L: Interp, a: seq[Value], i: int, fname: string): Dataset =
  checkUser[LDonnees](L, a, i, fname, "données d'entraînement").d

proc plusLong(d: Dataset): int =
  for ex in d.examples: result = max(result, ex.tokens.len)

proc donneesV(d: Dataset): Value =
  if classeDonnees.isNil:
    let c = newClasse("donnees")
    classeDonnees = c
    let m = c.methodes
    m.fn "separer", proc (L: Interp, a: seq[Value]): seq[Value] =
      ## Renvoie {entrainement, validation}.
      let d = L.checkDonnees(a, 1, "separer")
      let f = L.optNum(a, 2, "separer", 0.1)
      if f <= 0 or f >= 1: rtError("separer : fraction entre 0 et 1 attendue")
      let (x, y) = d.split(f)
      @[listV(@[donneesV(x), donneesV(y)])]
    m.fn "taille", proc (L: Interp, a: seq[Value]): seq[Value] = @[intV(L.checkDonnees(a, 1, "taille").len)]
    m.fn "pluslong", proc (L: Interp, a: seq[Value]): seq[Value] =
      @[intV(plusLong(L.checkDonnees(a, 1, "pluslong")))]
    c.getter "type", proc (L: Interp, u: LUser): Value =
      strV(if LDonnees(u).d.kind == dkText: "texte" else: "dialogue")
  classeDonnees.enveloppe(LDonnees(d: d))

proc configV(c: ModelConfig): Value =
  record({"architecture": strV(c.arch), "nom": strV(c.name), "dimension": intV(c.dim),
          "cache": intV(c.hidden), "couches": intV(c.nLayers), "tetes": intV(c.nHeads),
          "tetes_kv": intV(c.nKvHeads), "vocabulaire": intV(c.vocab), "contexte": intV(c.ctxTrain),
          "base_rope": numV(c.ropeBase), "lies": boolV(c.tiedEmbeddings)})

proc logV(l: TrainLog): Value =
  record({"etape": intV(l.step), "perte": numV(l.loss),
          "validation": (if l.valLoss.isNaN: nilV else: numV(l.valLoss)),
          "lr": numV(l.lr), "norme": numV(l.gradNorm), "vitesse": numV(l.tokensPerSec),
          "duree": numV(l.elapsed)})

proc ligneJournal(l: TrainLog): string =
  ## Même présentation que nimllm (printLog).
  result = "étape " & align($l.step, 5) & " | perte " & fmtNum(l.loss, 4)
  if not l.valLoss.isNaN: result.add " | val " & fmtNum(l.valLoss, 4)
  result.add " | lr " & formatFloat(l.lr, ffScientific, 2) & " | ‖g‖ " & fmtNum(l.gradNorm, 2) &
             " | " & $int(l.tokensPerSec) & " tok/s"

proc checkTransfo(L: Interp, a: seq[Value], fname: string): Transformer =
  checkUser[LTransfo](L, a, 1, fname, "modèle entraînable").t

proc transfoV(t: Transformer): Value

proc creerClasseTransfo(): Classe =
  let c = newClasse("modele_entrainable")
  let m = c.methodes
  m.fn "entrainer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkTransfo(a, "entrainer")
    let d = L.checkDonnees(a, 2, "entrainer")
    let o = optsArg(a, 3)
    var tc = defaultTrainConfig()
    tc.steps = o.optField("etapes", tc.steps)
    tc.batchSize = o.optField("lot", tc.batchSize)
    tc.seqLen = o.optField("sequence", tc.seqLen)
    tc.gradAccum = o.optField("accumulation", tc.gradAccum)
    tc.lr = o.optField("lr", tc.lr)
    tc.minLr = o.optField("lrmin", min(tc.minLr, tc.lr))
    tc.warmup = o.optField("echauffement", tc.warmup)
    tc.weightDecay = o.optField("decroissance", tc.weightDecay)
    tc.gradClip = o.optField("ecretage", tc.gradClip)
    tc.evalEvery = o.optField("evaluation", tc.evalEvery)
    tc.evalBatches = o.optField("lotsevaluation", tc.evalBatches)
    tc.logEvery = o.optField("journal", tc.logEvery)
    tc.saveEvery = o.optField("sauvegarde", tc.saveEvery)
    tc.savePath = o.optField("chemin", tc.savePath)
    tc.sampleEvery = o.optField("echantillon", tc.sampleEvery)
    tc.samplePrompt = o.optField("amorce", tc.samplePrompt)
    tc.seed = o.optField("graine", tc.seed)
    if tc.steps <= 0 or tc.batchSize <= 0 or tc.seqLen <= 0:
      rtError("entrainer : etapes, lot et sequence doivent être positifs")
    if tc.seqLen > t.cfg.ctxTrain:
      rtError("entrainer : sequence (" & $tc.seqLen & ") dépasse le contexte du modèle (" & $t.cfg.ctxTrain & ")")
    if d.kind == dkText and d.tokens.len <= tc.seqLen + 1:
      rtError("entrainer : texte trop court (" & $d.tokens.len & " tokens) pour des séquences de " & $tc.seqLen)
    if d.kind == dkChat and d.examples.len == 0: rtError("entrainer : aucun dialogue")
    var valData: Dataset = nil
    var opt: Optimizer = nil
    var rappel = nilV
    if not o.isNil:
      let v = o.field("validation")
      if v.kind == vkUser and v.u of LDonnees: valData = LDonnees(v.u).d
      let op = o.field("optimiseur")
      if op.kind == vkUser and op.u of LOptim: opt = LOptim(op.u).o
      rappel = o.field("rappel")
      if rappel.kind != vkNil and not L.callable(rappel): rtError("entrainer : rappel = @PROCEDURE attendu")
    if valData.isNil and tc.evalEvery > 0 and arg(a, 3).kind == vkTable and not o.has("evaluation"):
      tc.evalEvery = 0                       # pas de validation fournie.
    let onLog = proc (l: TrainLog) =
      reprend(L):
        if L.stopRequested(): raise newException(LexisStop, "entraînement arrêté")
        if rappel.kind != vkNil: discard L.call(rappel, @[logV(l)])
        else: L.ecrire(ligneJournal(l))
    let onSample = proc (s: string) =
      reprend(L): L.ecrire("   » " & s)
    var res: Optimizer
    protege "entrainer":
      relache(L):
        res = t.train(d, tc, valData = valData, opt = opt, onLog = onLog, onSample = onSample)
    @[optimV(res)]
  m.fn "parametres", proc (L: Interp, a: seq[Value]): seq[Value] =
    var vs: seq[Value]
    for p in L.checkTransfo(a, "parametres").parameters: vs.add tenseurV(p)
    @[listV(vs)]
  m.fn "nombreparametres", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[intV(L.checkTransfo(a, "nombreparametres").parameterCount(trainableOnly = not optBool(a, 2, false)))]
  m.fn "optimiseur", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## AdamW sur les paramètres entraînables.
    let t = L.checkTransfo(a, "optimiseur")
    let o = optsArg(a, 2)
    @[optimV(newAdamW(t.parameters, lr = o.optField("lr", 3e-4), beta1 = o.optField("beta1", 0.9),
                      beta2 = o.optField("beta2", 0.95), weightDecay = o.optField("decroissance", 0.1)))]
  m.fn "enregistrer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkTransfo(a, "enregistrer")
    let p = L.checkStr(a, 2, "enregistrer")
    let ty = typeDe(L.optStr(a, 3, "enregistrer", "f32"))
    protege "enregistrer":
      relache(L): t.saveGguf(p, ty)
    @[strV(p)]
  m.fn "enregistrerlora", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkTransfo(a, "enregistrerlora")
    if t.mode != tmLora: rtError("enregistrerlora : le modèle n'est pas en mode lora")
    let p = L.checkStr(a, 2, "enregistrerlora")
    protege "enregistrerlora": t.saveLora(p)
    @[strV(p)]
  m.fn "sauvegarder", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Point de sauvegarde : modèle (ou adaptateur) + état de l'optimiseur.
    let t = L.checkTransfo(a, "sauvegarder")
    var o: Optimizer = nil
    if arg(a, 2).kind != vkNil: o = checkUser[LOptim](L, a, 2, "sauvegarder", "optimiseur").o
    let p = L.checkStr(a, 3, "sauvegarder")
    protege "sauvegarder":
      relache(L): t.saveCheckpoint(o, p)
    @[strV(p)]
  m.fn "evaluer", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Perte moyenne (entropie croisée) ; exp(perte) = perplexité.
    let t = L.checkTransfo(a, "evaluer")
    let d = L.checkDonnees(a, 2, "evaluer")
    let lots = int(L.optInt(a, 3, "evaluer", 4))
    let b = int(L.optInt(a, 4, "evaluer", 8))
    let s = int(L.optInt(a, 5, "evaluer", 64))
    if s > t.cfg.ctxTrain: rtError("evaluer : sequence trop longue pour le modèle")
    var r: float
    protege "evaluer":
      relache(L): r = t.evaluate(d, lots, b, s)
    @[numV(r)]
  m.fn "generer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = L.checkTransfo(a, "generer")
    let amorce = L.checkStr(a, 2, "generer")
    let o = optsArg(a, 3)
    var s: string
    protege "generer":
      relache(L):
        s = t.generateText(amorce, maxTokens = o.optField("maxtokens", 50),
                           temperature = o.optField("temperature", 0.8), seed = o.optField("graine", 1))
    @[strV(s)]
  c.getter "tokeniseur", proc (L: Interp, u: LUser): Value = tokV(LTransfo(u).t.tokenizer)
  c.getter "mode", proc (L: Interp, u: LUser): Value = strV($LTransfo(u).t.mode)
  c.getter "config", proc (L: Interp, u: LUser): Value = configV(LTransfo(u).t.cfg)
  c.getter "gabarit", proc (L: Interp, u: LUser): Value = strV($detectTemplate(LTransfo(u).t.tokenizer))
  c

proc transfoV(t: Transformer): Value =
  if classeTransfo.isNil: classeTransfo = creerClasseTransfo()
  classeTransfo.enveloppe(LTransfo(t: t))

proc openEntrainement(L: Interp): Value =
  let m = newLib()
  m.fn "tokeniseur", proc (L: Interp, a: seq[Value]): seq[Value] =
    let textes = L.toStrings(arg(a, 1))
    if textes.len == 0: rtError("tokeniseur : texte d'apprentissage attendu")
    let o = optsArg(a, 2)
    let speciaux = if o.has("speciaux"): L.toStrings(o.field("speciaux")) else: defaultSpecials
    let taille = o.optField("taille", 2048)
    if taille <= 256 + speciaux.len: rtError("tokeniseur : taille > " & $(256 + speciaux.len) & " attendue")
    let mode = case o.optField("mode", "llama3").toLowerAscii
      of "qwen2", "qwen": ptQwen2
      of "gpt2": ptGpt2
      else: ptLlama3
    var t: Tokenizer
    protege "tokeniseur":
      relache(L):
        t = trainBpe(textes, vocabSize = taille, specials = speciaux,
                     minFreq = o.optField("frequencemin", 2), pre = mode)
    @[tokV(t)]
  m.fn "tokeniseuroctets", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Tokeniseur minimal : 256 octets + tokens spéciaux.
    let speciaux = if arg(a, 1).kind == vkNil: defaultSpecials else: L.toStrings(arg(a, 1))
    @[tokV(byteLevelTokenizer(speciaux))]
  m.fn "nouveau", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Nouveau Transformer (architecture Llama) initialisé au hasard.
    let tok = L.checkTok(a, 1, "nouveau")
    let o = optsArg(a, 2)
    let dim = o.optField("dimension", 256)
    let heads = o.optField("tetes", 4)
    let kv = o.optField("tetes_kv", 0)
    if dim <= 0 or heads <= 0 or dim mod heads != 0:
      rtError("nouveau : dimension doit être un multiple de tetes")
    if (dim div heads) mod 2 != 0: rtError("nouveau : dimension / tetes doit être pair (RoPE)")
    if kv > 0 and heads mod kv != 0: rtError("nouveau : tetes doit être un multiple de tetes_kv")
    let cfg = newModelConfig(vocab = tok.vocabSize, dim = dim, layers = o.optField("couches", 4),
      heads = heads, kvHeads = kv, hidden = o.optField("cache", 0), ctx = o.optField("contexte", 256),
      ropeBase = o.optField("base_rope", 10000.0), tied = o.optField("lies", true),
      name = o.optField("nom", "nimllm-mini"))
    var t: Transformer
    protege "nouveau": t = newTransformer(cfg, tok, seed = o.optField("graine", 42))
    @[transfoV(t)]
  m.fn "charger", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Charge un GGUF pour l'entraîner : mode "lora" (poids gelés) ou "complet".
    let p = L.checkStr(a, 1, "charger")
    let o = optsArg(a, 2)
    let mode = case o.optField("mode", "lora").toLowerAscii
      of "complet", "full": tmFull
      of "lora": tmLora
      else: rtError("charger : mode « lora » ou « complet » attendu")
    var lc = defaultLora()
    lc.rank = o.optField("rang", lc.rank)
    lc.alpha = o.optField("alpha", lc.alpha)
    if o.has("cibles"): lc.targets = L.toStrings(o.field("cibles"))
    var t: Transformer
    protege "charger":
      relache(L):
        t = loadForTraining(p, mode, lc, seed = o.optField("graine", 42), threads = o.optField("fils", 0))
    @[transfoV(t)]
  m.fn "textes", proc (L: Interp, a: seq[Value]): seq[Value] =
    let tok = L.checkTok(a, 1, "textes")
    let s = L.toStrings(arg(a, 2)).join("\n")
    let o = optsArg(a, 3)
    var d: Dataset
    protege "textes":
      relache(L): d = newTextDataset(tok, s, seed = o.optField("graine", 1), addBos = o.optField("bos", true))
    @[donneesV(d)]
  m.fn "fichiers", proc (L: Interp, a: seq[Value]): seq[Value] =
    let tok = L.checkTok(a, 1, "fichiers")
    let chemins = L.toStrings(arg(a, 2))
    var d: Dataset
    protege "fichiers":
      relache(L): d = newTextDatasetFromFiles(tok, chemins, seed = int(L.optInt(a, 3, "fichiers", 1)))
    @[donneesV(d)]
  m.fn "dialogues", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Dialogues : liste de dialogues, chacun liste de {role=, contenu=} ou
    ## fiche {question=, reponse=}. Seules les réponses sont apprises.
    let tok = L.checkTok(a, 1, "dialogues")
    let templ = gabaritDe(L.optStr(a, 2, "dialogues", "chatml"), tok)
    let o = optsArg(a, 4)
    let systeme = o.optField("systeme", "")
    var convs: seq[seq[Message]]
    for x in listItems(arg(a, 3)):
      var msgs: seq[Message]
      if systeme.len > 0: msgs.add Message(role: roleSystem, content: systeme)
      if x.kind == vkTable and x.t.rawLen == 0: msgs.add L.versMessages(listV(@[x]))
      else: msgs.add L.versMessages(x)
      convs.add msgs
    if convs.len == 0: rtError("dialogues : liste vide")
    var d: Dataset
    protege "dialogues":
      relache(L): d = newChatDataset(tok, templ, convs, seed = o.optField("graine", 1))
    @[donneesV(d)]
  m.fn "jsonl", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Fichier JSONL : {"messages": [...]}, {"prompt", "response"} ou {"instruction", "output"}.
    let p = L.checkStr(a, 1, "jsonl")
    let tok = L.checkTok(a, 2, "jsonl")
    let templ = gabaritDe(L.optStr(a, 3, "jsonl", "auto"), tok)
    let systeme = L.optStr(a, 4, "jsonl", "")
    var d: Dataset
    protege "jsonl":
      relache(L): d = loadChatJsonl(p, tok, templ, system = systeme)
    @[donneesV(d)]
  m.fn "gabarit", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV($detectTemplate(L.checkTok(a, 1, "gabarit")))]
  m.fn "configuration", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Réglages d'entraînement par défaut.
    let c = defaultTrainConfig()
    @[record({"etapes": intV(c.steps), "lot": intV(c.batchSize), "sequence": intV(c.seqLen),
              "accumulation": intV(c.gradAccum), "lr": numV(c.lr), "lrmin": numV(c.minLr),
              "echauffement": intV(c.warmup), "decroissance": numV(c.weightDecay),
              "ecretage": numV(c.gradClip), "evaluation": intV(c.evalEvery),
              "lotsevaluation": intV(c.evalBatches), "journal": intV(c.logEvery),
              "sauvegarde": intV(c.saveEvery), "chemin": strV(c.savePath),
              "echantillon": intV(c.sampleEvery), "amorce": strV(c.samplePrompt), "graine": intV(c.seed)})]
  tableV(m)

registerPackage PackageDef(name: "entrainement", open: openEntrainement,
  description: "Créer et entraîner des modèles de langage : tokeniseur, Transformer, LoRA, GGUF",
  docs: docs("entrainement", [
    "entrainement.tokeniseur(textes[, {taille=2048, speciaux=, frequencemin=2, mode=\"llama3\"}])", "Apprend un tokeniseur BPE niveau octet (compatible llama.cpp).",
    "entrainement.tokeniseuroctets([speciaux])", "Tokeniseur minimal (256 octets + spéciaux).",
    "entrainement.nouveau(tok, {dimension=256, couches=4, tetes=4, tetes_kv=, cache=, contexte=256, nom=, graine=42})", "Nouveau modèle Transformer (architecture Llama).",
    "entrainement.charger(chemin[, {mode=\"lora\", rang=8, alpha=16, cibles={\"q\",\"k\",\"v\",\"o\"}}])", "Charge un GGUF à spécialiser : LoRA (poids gelés) ou complet.",
    "entrainement.textes(tok, texte[, {graine=, bos=vrai}])", "Données de pré-entraînement (texte continu).",
    "entrainement.fichiers(tok, chemins)", "Données de pré-entraînement lues dans des fichiers.",
    "entrainement.dialogues(tok, gabarit, dialogues[, {systeme=}])", "Données de dialogue (seules les réponses sont apprises).",
    "entrainement.jsonl(chemin, tok[, gabarit=\"auto\", systeme])", "Dialogues lus dans un fichier JSONL.",
    "entrainement.gabarit(tok)", "Gabarit de conversation adapté au tokeniseur.",
    "entrainement.configuration()", "Réglages d'entraînement par défaut.",
    "m:entrainer(donnees[, {etapes, lot, sequence, accumulation, lr, lrmin, echauffement, decroissance, ecretage, evaluation, lotsevaluation, journal, sauvegarde, chemin, echantillon, amorce, graine, validation, optimiseur, rappel}])", "Entraîne le modèle ; renvoie l'optimiseur (pour reprendre). rappel=@proc(journal) reçoit {etape, perte, validation, lr, norme, vitesse, duree}.",
    "m:parametres()", "Liste des tenseurs entraînables.",
    "m:nombreparametres([tous=faux])", "Nombre de paramètres.",
    "m:optimiseur([{lr=, decroissance=}])", "AdamW sur les paramètres du modèle.",
    "m:enregistrer(chemin[, type=\"f32\"])", "Exporte un vrai fichier GGUF (llm.charger, llama.cpp, Ollama).",
    "m:enregistrerlora(chemin)", "Enregistre l'adaptateur LoRA.",
    "m:sauvegarder(optimiseur, prefixe)", "Point de sauvegarde (modèle ou adaptateur + optimiseur).",
    "m:evaluer(donnees[, lots=4, lot=8, sequence=64])", "Perte moyenne (exp(perte) = perplexité).",
    "m:generer(amorce[, {maxtokens=50, temperature=0.8}])", "Génère un texte (surveillance de l'entraînement) ; propriétés : tokeniseur, mode, config, gabarit.",
    "d:separer([fraction=0.1])", "Sépare en {entrainement, validation}.",
    "d:taille()", "Nombre de tokens (texte) ou de dialogues.",
    "d:pluslong()", "Longueur du plus long dialogue (tokens)."]))
