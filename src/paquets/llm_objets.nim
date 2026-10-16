# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - objets natifs partagés par les paquets d'IA :
#   tokeniseur, image, tenseur, optimiseur, pièce jointe.

import std/[strutils, tables, math, sets, os, algorithm]
import ../lexis/api
import llm_commun

export llm_commun

#
# Couleurs : "#rrggbb", "skyblue", "rgb(1,2,3)", {r, g, b[, a]} (0..255, a 0..1)
#

proc couleurDe*(L: Interp, v: Value, def = rgb(0, 0, 0)): Color =
  case v.kind
  of vkNil: def
  of vkStr:
    let (ok, c) = parseColor(v.s, def)
    if ok: c else: rgb(0, 0, 0, 0.0)          # "none" : transparent.
  of vkTable:
    let t = v.t
    var r, g, b: int
    var al = 1.0
    if t.rawLen >= 3:
      var ok: bool
      r = int(toInteger(t.rawGet(intV(1)), ok))
      g = int(toInteger(t.rawGet(intV(2)), ok))
      b = int(toInteger(t.rawGet(intV(3)), ok))
      if t.rawLen >= 4: al = toFloat(t.rawGet(intV(4)), ok)
    else:
      r = t.optField("r", 0)
      g = t.optField("g", 0)
      b = t.optField("b", 0)
      al = t.optField("a", 1.0)
    rgb(r, g, b, al)
  else: rtError("couleur attendue : \"#rrggbb\", nom (\"red\") ou {r, g, b[, a]}")

proc couleurV*(r, g, b: uint8): Value =
  let t = newLTable()
  t.set "r", intV(int(r))
  t.set "g", intV(int(g))
  t.set "b", intV(int(b))
  tableV(t)

proc tokV*(t: Tokenizer): Value
proc imageV*(img: Image): Value

#
# Tokeniseur
#

proc idValide(L: Interp, tok: Tokenizer, a: seq[Value], i: int, fname: string): int =
  result = int(L.checkInt(a, i, fname))
  if result < 0 or result >= tok.vocabSize:
    rtError(fname & " : identifiant de token hors limites (" & $result & ", vocabulaire de " & $tok.vocabSize & ")")

proc creerClasseTok(): Classe =
  let c = newClasse("tokeniseur")
  let m = c.methodes
  template self(fname: string): Tokenizer = checkUser[LTok](L, a, 1, fname, "tokeniseur").tok
  m.fn "encoder", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = self("encoder")
    let s = L.checkStr(a, 2, "encoder")
    let bos = optBool(a, 3, false)
    let sp = optBool(a, 4, true)
    var ids: seq[int]
    protege "encoder": ids = t.encode(s, addBos = bos, parseSpecial = sp)
    @[intsV(ids)]
  m.fn "decoder", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = self("decoder")
    let ids = L.toInts(arg(a, 2), "decoder")
    for id in ids:
      if id < 0 or id >= t.vocabSize: rtError("decoder : identifiant hors limites (" & $id & ")")
    @[strV(t.decode(ids, renderSpecial = optBool(a, 3, false)))]
  m.fn "morceau", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = self("morceau")
    @[strV(t.tokenToPiece(L.idValide(t, a, 2, "morceau"), renderSpecial = optBool(a, 3, false)))]
  m.fn "id", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = self("id")
    let id = t.tokenId(L.checkStr(a, 2, "id"))
    @[(if id < 0: nilV else: intV(id))]
  m.fn "estspecial", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = self("estspecial")
    @[boolV(t.isSpecial(L.idValide(t, a, 2, "estspecial")))]
  m.fn "enregistrer", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Enregistre le tokeniseur seul dans un fichier GGUF (sans poids).
    let t = self("enregistrer")
    let path = L.checkStr(a, 2, "enregistrer")
    protege "enregistrer":
      let w = newGgufWriter()
      w.setKV("general.architecture", gStr("llama"))
      t.writeToGguf(w)
      w.write(path)
    @[boolV(true)]
  template prop(nom: string, body: untyped) =
    c.getter nom, proc (L: Interp, u: LUser): Value =
      let tok {.inject.} = LTok(u).tok
      body
  prop "taille": intV(tok.vocabSize)
  prop "bos": intV(tok.bosId)
  prop "eos": intV(tok.eosId)
  prop "pad": intV(tok.padId)
  prop "inconnu": intV(tok.unkId)
  prop "fusions": intV(tok.merges.len)
  prop "type": strV($tok.kind)
  prop "ajoutebos": boolV(tok.addBos)
  prop "gabarit": strV($detectTemplate(tok))
  prop "fins":
    var ids: seq[int]
    for x in tok.eogIds: ids.add x
    ids.sort()
    intsV(ids)
  c

#
# Image
#

proc creerClasseImage(): Classe =
  let c = newClasse("image")
  let m = c.methodes
  template self(fname: string): Image = checkUser[LImage](L, a, 1, fname, "image").img
  m.fn "enregistrer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let img = self("enregistrer")
    let p = L.checkStr(a, 2, "enregistrer")
    protege "enregistrer": img.save(p)
    @[strV(p)]
  m.fn "enregistrerbmp", proc (L: Interp, a: seq[Value]): seq[Value] =
    let img = self("enregistrerbmp")
    let p = L.checkStr(a, 2, "enregistrerbmp")
    protege "enregistrerbmp": img.writeBmp(p)
    @[strV(p)]
  m.fn "enregistrerppm", proc (L: Interp, a: seq[Value]): seq[Value] =
    let img = self("enregistrerppm")
    let p = L.checkStr(a, 2, "enregistrerppm")
    protege "enregistrerppm": img.writePpm(p)
    @[strV(p)]
  m.fn "pixel", proc (L: Interp, a: seq[Value]): seq[Value] =
    let img = self("pixel")
    let x = int(L.checkInt(a, 2, "pixel"))
    let y = int(L.checkInt(a, 3, "pixel"))
    if x < 0 or y < 0 or x >= img.width or y >= img.height: return @[nilV]
    let (r, g, b) = img.getPixel(x, y)
    @[couleurV(r, g, b)]
  m.fn "fixerpixel", proc (L: Interp, a: seq[Value]): seq[Value] =
    let img = self("fixerpixel")
    img.setPixel(int(L.checkInt(a, 2, "fixerpixel")), int(L.checkInt(a, 3, "fixerpixel")),
                 L.couleurDe(arg(a, 4)))
    @[]
  m.fn "decrire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let img = self("decrire")
    @[strV(describeImage(img, int(L.optInt(a, 2, "decrire", 48))))]
  c.getter "largeur", proc (L: Interp, u: LUser): Value = intV(LImage(u).img.width)
  c.getter "hauteur", proc (L: Interp, u: LUser): Value = intV(LImage(u).img.height)
  c

#
# Pièce jointe
#

proc nomGenre*(k: AttachmentKind): string =
  case k
  of akText: "texte"
  of akImage: "image"
  of akPdf: "pdf"
  of akAudio: "audio"
  of akBinary: "binaire"

proc creerClassePiece(): Classe =
  let c = newClasse("piece")
  c.methodes.fn "texte", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = checkUser[LPiece](L, a, 1, "texte", "pièce jointe").p
    @[strV(p.toPrompt(int(L.optInt(a, 2, "texte", 12000))))]
  c.getter "nom", proc (L: Interp, u: LUser): Value = strV(LPiece(u).p.name)
  c.getter "type", proc (L: Interp, u: LUser): Value = strV(nomGenre(LPiece(u).p.kind))
  c.getter "mime", proc (L: Interp, u: LUser): Value = strV(LPiece(u).p.mime)
  c.getter "contenu", proc (L: Interp, u: LUser): Value = strV(LPiece(u).p.text)
  c.getter "taille", proc (L: Interp, u: LUser): Value = intV(LPiece(u).p.data.len)
  c.getter "largeur", proc (L: Interp, u: LUser): Value = intV(LPiece(u).p.width)
  c.getter "hauteur", proc (L: Interp, u: LUser): Value = intV(LPiece(u).p.height)
  c.getter "image", proc (L: Interp, u: LUser): Value =
    let img = LPiece(u).p.image
    if img.isNil: nilV else: imageV(img)
  c

#
# Tenseur
#

proc formeDe*(L: Interp, v: Value, fname: string): seq[int] =
  result = L.toInts(v, fname)
  if result.len == 0: rtError(fname & " : forme attendue, par exemple {64, 1}")
  for d in result:
    if d <= 0: rtError(fname & " : dimensions strictement positives attendues")

proc formeTexte(s: seq[int]): string = "{" & s.join(", ") & "}"

proc verifierDiffusion*(a, b: Tensor, op: string) =
  if b.data.len != a.data.len and b.data.len != a.cols:
    rtError("tenseur " & op & " : formes incompatibles " & formeTexte(a.shape) & " et " & formeTexte(b.shape))

proc creerClasseTenseur(): Classe

var classeTenseurTV {.threadvar.}: Classe

proc tenseurV*(t: Tensor): Value =
  if t.isNil: return nilV
  if classeTenseurTV.isNil: classeTenseurTV = creerClasseTenseur()
  classeTenseurTV.enveloppe(LTenseur(t: t))

proc operande(L: Interp, v: Value, op: string): (bool, Tensor, float32) =
  ## (vrai, tenseur, _) ou (faux, nil, nombre).
  if v.kind == vkUser and v.u of LTenseur: return (true, LTenseur(v.u).t, 0'f32)
  var ok: bool
  let f = toFloat(v, ok)
  if not ok: rtError("tenseur " & op & " : tenseur ou nombre attendu, " & typeName(v) & " reçu")
  (false, nil, float32(f))

proc arith(L: Interp, a: seq[Value], op: char): Value =
  let (ta, x, fa) = L.operande(arg(a, 1), $op)
  let (tb, y, fb) = L.operande(arg(a, 2), $op)
  if ta and tb:
    verifierDiffusion(x, y, $op)
    return tenseurV(case op
      of '+': x + y
      of '-': x - y
      else: x * y)
  if ta:                                  # tenseur op nombre
    case op
    of '*': return tenseurV(scale(x, fb))
    of '+': return tenseurV(x + full(x.shape, fb))
    else: return tenseurV(x - full(x.shape, fb))
  if tb:                                  # nombre op tenseur
    case op
    of '*': return tenseurV(scale(y, fa))
    of '+': return tenseurV(full(y.shape, fa) + y)
    else: return tenseurV(full(y.shape, fa) - y)
  numV(0)

proc creerClasseTenseur(): Classe =
  let c = newClasse("tenseur")
  let m = c.methodes
  template self(fname: string): Tensor = checkUser[LTenseur](L, a, 1, fname, "tenseur").t
  m.fn "retropropager", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = self("retropropager")
    protege "retropropager": backward(t)
    @[]
  m.fn "valeur", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = self("valeur")
    let i = int(L.optInt(a, 2, "valeur", 1))
    if i < 1 or i > t.numel: rtError("valeur : indice hors limites (" & $i & ")")
    @[numV(float(t.data[i - 1]))]
  m.fn "donnees", proc (L: Interp, a: seq[Value]): seq[Value] = @[floatsV(self("donnees").data)]
  m.fn "gradient", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = self("gradient")
    if t.grad.len == 0: @[nilV] else: @[floatsV(t.grad)]
  m.fn "forme", proc (L: Interp, a: seq[Value]): seq[Value] = @[intsV(self("forme").shape)]
  m.fn "taille", proc (L: Interp, a: seq[Value]): seq[Value] = @[intV(self("taille").numel)]
  m.fn "zerograd", proc (L: Interp, a: seq[Value]): seq[Value] =
    self("zerograd").zeroGrad()
    @[]
  m.fn "detacher", proc (L: Interp, a: seq[Value]): seq[Value] = @[tenseurV(self("detacher").detach())]
  m.fn "remodeler", proc (L: Interp, a: seq[Value]): seq[Value] =
    let t = self("remodeler")
    let f = L.formeDe(arg(a, 2), "remodeler")
    if numel(f) != t.numel: rtError("remodeler : " & $numel(f) & " éléments pour " & $t.numel)
    @[tenseurV(t.reshape(f))]
  m.fn "ajoutergradient", proc (L: Interp, a: seq[Value]): seq[Value] =
    ## Ajoute des valeurs au gradient (opérations personnalisées).
    let t = self("ajoutergradient")
    let g = L.toFloats(arg(a, 2), "ajoutergradient")
    if g.len != t.numel: rtError("ajoutergradient : " & $t.numel & " valeurs attendues, " & $g.len & " reçues")
    t.ensureGrad()
    for i in 0 ..< g.len: t.grad[i] += g[i]
    @[]
  c.getter "nom", proc (L: Interp, u: LUser): Value = strV(LTenseur(u).t.name)
  c.getter "gradientrequis", proc (L: Interp, u: LUser): Value = boolV(LTenseur(u).t.requiresGrad)
  c.setter "gradientrequis", proc (L: Interp, u: LUser, v: Value) = LTenseur(u).t.requiresGrad = truthy(v)
  let mt = c.meta
  mt.set "__add", fnV("tenseur.add", proc (L: Interp, a: seq[Value]): seq[Value] = @[L.arith(a, '+')])
  mt.set "__sub", fnV("tenseur.sub", proc (L: Interp, a: seq[Value]): seq[Value] = @[L.arith(a, '-')])
  mt.set "__mul", fnV("tenseur.mul", proc (L: Interp, a: seq[Value]): seq[Value] = @[L.arith(a, '*')])
  mt.set "__unm", fnV("tenseur.unm", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[tenseurV(scale(checkUser[LTenseur](L, a, 1, "-", "tenseur").t, -1'f32))])
  mt.set "__tostring", fnV("tenseur.texte", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[strV($LTenseur(a[0].u).t)])
  c

#
# Optimiseur
#

proc creerClasseOptim(): Classe =
  let c = newClasse("optimiseur")
  let m = c.methodes
  template self(fname: string): Optimizer = checkUser[LOptim](L, a, 1, fname, "optimiseur").o
  m.fn "zerograd", proc (L: Interp, a: seq[Value]): seq[Value] =
    self("zerograd").zeroGrad()
    @[]
  m.fn "etape", proc (L: Interp, a: seq[Value]): seq[Value] =
    self("etape").update()
    @[]
  m.fn "ecreter", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = self("ecreter")
    @[numV(clipGradNorm(o.params, L.checkNum(a, 2, "ecreter")))]
  m.fn "enregistrer", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = self("enregistrer")
    let p = L.checkStr(a, 2, "enregistrer")
    protege "enregistrer": o.saveState(p)
    @[boolV(true)]
  m.fn "charger", proc (L: Interp, a: seq[Value]): seq[Value] =
    let o = self("charger")
    let p = L.checkStr(a, 2, "charger")
    protege "charger": o.loadState(p)
    @[boolV(true)]
  c.getter "pas", proc (L: Interp, u: LUser): Value = intV(LOptim(u).o.step)
  c.getter "type", proc (L: Interp, u: LUser): Value = strV($LOptim(u).o.kind)
  c.getter "lr", proc (L: Interp, u: LUser): Value = numV(LOptim(u).o.lr)
  c.setter "lr", proc (L: Interp, u: LUser, v: Value) =
    var ok: bool
    let f = toFloat(v, ok)
    if not ok: rtError("lr : nombre attendu")
    LOptim(u).o.lr = f
  c

#
# Constructeurs de valeurs (une classe par fil d'exécution)
#

var
  classeTokTV {.threadvar.}: Classe
  classeImageTV {.threadvar.}: Classe
  classeOptimTV {.threadvar.}: Classe
  classePieceTV {.threadvar.}: Classe

proc tokV*(t: Tokenizer): Value =
  if classeTokTV.isNil: classeTokTV = creerClasseTok()
  classeTokTV.enveloppe(LTok(tok: t))

proc imageV*(img: Image): Value =
  if img.isNil: return nilV
  if classeImageTV.isNil: classeImageTV = creerClasseImage()
  classeImageTV.enveloppe(LImage(img: img))

proc optimV*(o: Optimizer): Value =
  if o.isNil: return nilV
  if classeOptimTV.isNil: classeOptimTV = creerClasseOptim()
  classeOptimTV.enveloppe(LOptim(o: o))

proc pieceV*(p: Attachment): Value =
  if classePieceTV.isNil: classePieceTV = creerClassePiece()
  classePieceTV.enveloppe(LPiece(p: p))

proc versPiece*(L: Interp, v: Value, fname: string): Attachment =
  ## Pièce jointe : objet (llm.joindre...) ou chemin de fichier.
  if v.kind == vkUser and v.u of LPiece: return LPiece(v.u).p
  if v.kind == vkStr:
    protege fname: result = attach(v.s)
    return
  rtError(fname & " : pièce jointe (llm.joindre) ou chemin de fichier attendu")

proc versPieces*(L: Interp, v: Value, fname: string): seq[Attachment] =
  case v.kind
  of vkNil: discard
  of vkTable:
    for x in listItems(v): result.add L.versPiece(x, fname)
  else: result.add L.versPiece(v, fname)
