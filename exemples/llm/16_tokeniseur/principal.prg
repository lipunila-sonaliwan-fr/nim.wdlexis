&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 16 — Entraîner son propre tokeniseur BPE (compatible llama.cpp).
&&
&&   wdlexisrt exemples/llm/16_tokeniseur/principal.prg [corpus.txt]

locale corpus
si systeme.args[1] <> nul
  corpus = fichier.lire(systeme.args[1])
sinon
  corpus = repliquer([[Le petit prince demanda : « S'il vous plaît... dessine-moi un mouton ! »
Les grandes personnes ne comprennent jamais rien toutes seules, et c'est fatigant,
pour les enfants, de toujours et toujours leur donner des explications.
On ne voit bien qu'avec le cœur. L'essentiel est invisible pour les yeux.]], 20)
finsi

&& Apprentissage : 256 octets de base + fusions + tokens spéciaux.
locale tok = entrainement.tokeniseur(corpus, {taille = 600,
  speciaux = {"<|bos|>", "<|eos|>", "<|pad|>", "<|im_start|>", "<|im_end|>"},
  frequencemin = 2})
? "Vocabulaire :", tok.taille, "tokens,", tok.fusions, "fusions"
? "Spéciaux : bos=" + tok.bos + " eos=" + tok.eos + " pad=" + tok.pad
? "Fin de tour (eog) :", joindre(tok.fins, ", ")

locale phrase = "L'essentiel est invisible pour les yeux."
locale ids = tok:encoder(phrase)
?
? phrase
? "→", #ids, "tokens :", joindre(ids, ", ")
locale morceaux = {}
pour chaque id dans ids
  inserer tok:morceau(id) dans morceaux
suivant
? "→ découpage :", joindre(morceaux, " | ")
si tok:decoder(ids) <> phrase                                   && l'aller-retour est exact.
  erreur "aller-retour inexact"
finsi

&& Le niveau octet garantit que TOUT texte est encodable (même inconnu) :
locale exotique = "Emoji 🦙, grec αβγ, chinois 你好"
si tok:decoder(tok:encoder(exotique)) <> exotique
  erreur "aller-retour inexact (texte inconnu)"
finsi
? "Texte inconnu :", #tok:encoder(exotique), "tokens (repli sur les octets)"

&& Sauvegarde dans un GGUF (sans poids) : réutilisable plus tard.
tok:enregistrer("mon_tokeniseur.gguf")
locale relu = llm.tokeniseur("mon_tokeniseur.gguf")
si json(relu:encoder(phrase)) <> json(ids)
  erreur "tokeniseur relu différent"
finsi
? "Tokeniseur rechargé depuis mon_tokeniseur.gguf : identique."

&& Le pré-découpage (même règle que Llama 3) avant le BPE :
? json(llm.predecouper("Il a 12345 euros, n'est-ce pas ?", "llama3"))
