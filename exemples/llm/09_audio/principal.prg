&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 09 — Recevoir la réponse sous forme de fichier audio (WAV).
&&
&&   wdlexisrt exemples/llm/09_audio/principal.prg modele.gguf
&&
&& La synthèse vocale intégrée est un synthétiseur par formants : la voix est
&& robotique mais ne nécessite aucun modèle ni bibliothèque externe.

locale chemin = systeme.args[1] ou systeme.env("NIMLLM_MODEL") ou "models/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
locale modele = llm.charger(chemin)
locale conv = modele:conversation({maxtokens = 150})

&& 1. Réponse parlée.
conv.voix = 110                 && hauteur de la voix (Hz) : ~110 grave, ~200 aiguë
locale r = conv:demander("Donne-moi la météo idéale pour un pique-nique, en deux phrases.",
                         {format = "audio", sortie = "meteo.wav"})
? "Texte prononcé :", r.texte
? "Fichier :", r.fichiers[1], "(" + arrondi(audio.infos(r.fichiers[1]).duree, 2) + " s)"

&& 2. Synthèse directe, sans LLM (paquet audio).
locale voix = audio.parler("Bonjour ! Il est 8 heures et 15 minutes.", {langue = "fr", hauteur = 120, vitesse = 0.9})
voix:enregistrer("bonjour.wav")
? "Phonèmes :", joindre(audio.phonemes("Bonjour ! Il est 8 heures."), " ")

locale anglais = audio.parler("Hello, this is a speech test.", {langue = "en"})
anglais:enregistrer("hello.wav")

&& 3. Assembler plusieurs morceaux.
locale tout = audio.parler("Premier message.")
tout:silence(0.5)
tout:ajouter(audio.parler("Deuxième message."))
tout:enregistrer("assemblage.wav")

&& 4. Le LLM compose une mélodie.
conv:reinitialiser()
locale partition = conv:demander("Écris une courte mélodie joyeuse en notation : notes séparées " +
  "par des espaces au format Note+Octave[:durée en temps], R pour un silence. " +
  "Exemple : C4 E4 G4:2 R. Réponds uniquement avec les notes.", {maxtokens = 80}).texte
? "Partition :", partition
locale melodie = audio.melodie(partition, 110)
melodie:enregistrer("melodie.wav")
