# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
#   wdlexis+ - paquet audio : synthèse vocale, mélodies et fichiers WAV
#
#   s = audio.parler("Bonjour ! Il est 8 heures.", {langue = "fr", hauteur = 120})
#   s:silence(0.5)
#   s:ajouter(audio.melodie("C4 E4 G4:2 R C5", 110))
#   s:enregistrer("bonjour.wav")
#
# La voix est produite par un synthétiseur à formants : robotique, mais sans
# modèle ni bibliothèque externe.

import std/[strutils, os]
import ../lexis/api
import llm_objets

type
  LSon = ref object of LUser
    a: Audio

var classeSon {.threadvar.}: Classe

proc reechantillonner(a: Audio, sr: int): Audio =
  ## Interpolation linéaire vers une autre fréquence d'échantillonnage.
  if a.sampleRate == sr or a.samples.len == 0 or a.sampleRate <= 0:
    return Audio(sampleRate: sr, samples: a.samples)
  result = newAudio(sr)
  let n = int(float(a.samples.len) * float(sr) / float(a.sampleRate))
  for i in 0 ..< n:
    let x = float(i) * float(a.sampleRate) / float(sr)
    let k = int(x)
    let f = float32(x - float(k))
    let s0 = a.samples[min(k, a.samples.len - 1)]
    let s1 = a.samples[min(k + 1, a.samples.len - 1)]
    result.samples.add s0 * (1 - f) + s1 * f

proc sonV(a: Audio): Value =
  if classeSon.isNil:
    let c = newClasse("son")
    classeSon = c
    let m = c.methodes
    template self(fname: string): LSon = checkUser[LSon](L, a, 1, fname, "son")
    m.fn "enregistrer", proc (L: Interp, a: seq[Value]): seq[Value] =
      let s = self("enregistrer")
      let p = L.checkStr(a, 2, "enregistrer")
      protege "enregistrer": s.a.writeWav(p)
      @[strV(p)]
    m.fn "silence", proc (L: Interp, a: seq[Value]): seq[Value] =
      self("silence").a.silence(L.checkNum(a, 2, "silence"))
      @[a[0]]
    m.fn "ajouter", proc (L: Interp, a: seq[Value]): seq[Value] =
      let s = self("ajouter")
      let autre = checkUser[LSon](L, a, 2, "ajouter", "son").a
      s.a.concat(reechantillonner(autre, s.a.sampleRate))
      @[a[0]]
    m.fn "normaliser", proc (L: Interp, a: seq[Value]): seq[Value] =
      self("normaliser").a.normalize(L.optNum(a, 2, "normaliser", 0.9))
      @[a[0]]
    m.fn "copier", proc (L: Interp, a: seq[Value]): seq[Value] = @[sonV(self("copier").a)]
    c.getter "duree", proc (L: Interp, u: LUser): Value = numV(LSon(u).a.duration)
    c.getter "frequence", proc (L: Interp, u: LUser): Value = intV(LSon(u).a.sampleRate)
    c.getter "echantillons", proc (L: Interp, u: LUser): Value = intV(LSon(u).a.samples.len)
  classeSon.enveloppe(LSon(a: a))

proc openAudio(L: Interp): Value =
  let m = newLib()
  m.fn "parler", proc (L: Interp, a: seq[Value]): seq[Value] =
    let texte = L.checkStr(a, 1, "parler")
    let o = optsArg(a, 2)
    var s: Audio
    protege "parler":
      relache(L):
        s = speak(texte, lang = o.optField("langue", "fr"), pitch = o.optField("hauteur", 115.0),
                  speed = o.optField("vitesse", 1.0), sampleRate = o.optField("frequence", 16000))
    @[sonV(s)]
  m.fn "melodie", proc (L: Interp, a: seq[Value]): seq[Value] =
    let notes = L.checkStr(a, 1, "melodie")
    var s: Audio
    protege "melodie":
      s = renderMelody(notes, bpm = L.optNum(a, 2, "melodie", 120.0),
                       sampleRate = int(L.optInt(a, 3, "melodie", 22050)))
    @[sonV(s)]
  m.fn "nouveau", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[sonV(newAudio(int(L.optInt(a, 1, "nouveau", 16000))))]
  m.fn "lire", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkStr(a, 1, "lire")
    var s: Audio
    protege "lire": s = readWav(p)
    @[sonV(s)]
  m.fn "infos", proc (L: Interp, a: seq[Value]): seq[Value] =
    let p = L.checkStr(a, 1, "infos")
    var w: WavInfo
    protege "infos": w = readWavInfo(p)
    @[record({"frequence": intV(w.sampleRate), "canaux": intV(w.channels),
              "bits": intV(w.bitsPerSample), "duree": numV(w.durationSec)})]
  m.fn "phonemes", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[stringsV(textToPhonemes(L.checkStr(a, 1, "phonemes"), L.optStr(a, 2, "phonemes", "fr")))]
  m.fn "enlettres", proc (L: Interp, a: seq[Value]): seq[Value] =
    let n = int(L.checkInt(a, 1, "enlettres"))
    let langue = L.optStr(a, 2, "enlettres", "fr").toLowerAscii
    @[strV(if langue.startsWith("en"): numberToEnglish(n) else: numberToFrench(n))]
  m.fn "frequencenote", proc (L: Interp, a: seq[Value]): seq[Value] =
    @[numV(noteFrequency(L.checkStr(a, 1, "frequencenote")))]
  tableV(m)

registerPackage PackageDef(name: "audio", open: openAudio,
  description: "Synthèse vocale, mélodies et fichiers WAV",
  docs: docs("audio", [
    "audio.parler(texte[, {langue=\"fr\", hauteur=115, vitesse=1, frequence=16000}])", "Synthèse vocale (fr ou en) ; renvoie un son.",
    "audio.melodie(notation[, bpm=120])", "Mélodie : « C4 E4 G4:2 R » (note+octave[:temps], R = silence).",
    "audio.nouveau([frequence])", "Son vide.",
    "audio.lire(chemin)", "Lit un fichier WAV PCM 16 bits.",
    "audio.infos(chemin)", "En-tête d'un WAV : {frequence=, canaux=, bits=, duree=}.",
    "audio.phonemes(texte[, langue])", "Transcription phonétique utilisée par la synthèse.",
    "audio.enlettres(n[, langue])", "Nombre écrit en toutes lettres.",
    "audio.frequencenote(note)", "Fréquence d'une note (« A4 » = 440).",
    "s:enregistrer(chemin)", "Écrit un fichier WAV (16 bits mono).",
    "s:silence(secondes)", "Ajoute un silence.",
    "s:ajouter(autre)", "Ajoute un autre son à la suite (rééchantillonné si besoin).",
    "s:normaliser([crete=0.9])", "Ajuste le volume.",
    "s:copier()", "Copie du son (propriétés : duree, frequence, echantillons)."]))
