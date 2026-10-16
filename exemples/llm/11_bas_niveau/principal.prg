&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 11 — Sous le capot : tokens, logits, échantillonnage manuel,
&& complétion brute et gabarits de conversation.
&&
&&   wdlexisrt exemples/llm/11_bas_niveau/principal.prg modele.gguf

locale chemin = systeme.args[1] ou systeme.env("NIMLLM_MODEL") ou "models/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
locale modele = llm.charger(chemin)
? modele:decrire()

&& 1. Tokenisation.
locale tok = modele.tokeniseur
locale ids = tok:encoder("Le chat dort sur le canapé.", vrai)       && vrai : ajoute le token de début (BOS)
? "Identifiants :", joindre(ids, ", ")
pour chaque id dans ids
  && json() montre les caractères spéciaux (espaces, \n...) de chaque morceau.
  ? "  " + chaine(id, 7) + "  " + json(tok:morceau(id, vrai))
suivant
? "Décodé :", tok:decoder(ids)
? "Taille du vocabulaire :", tok.taille + ", BOS=" + tok.bos + ", EOS=" + tok.eos

&& 2. Évaluer un contexte et lire les probabilités.
locale ctx = modele:contexte(1024)
locale logits = ctx:evaluer(tok:encoder("La capitale de l'Espagne est", vrai))
?
? "Tokens les plus probables après « La capitale de l'Espagne est » :"
pour chaque t dans logits:meilleurs(5)
  ? "  " + chaine(t.proba * 100, 5, 1) + " %  " + json(tok:morceau(t.id))
suivant

&& 3. Boucle de génération écrite à la main.
locale s = llm.echantillonneur(llm.glouton())
locale dernier = logits
locale suivant_id
es.ecrire("Suite : La capitale de l'Espagne est")
pour i = 1 a 10
  suivant_id = s:tirer(dernier)
  si contient(tok.fins, suivant_id)
    sortir
  finsi
  es.ecrire(tok:morceau(suivant_id))
  dernier = ctx:evaluer({suivant_id})     && ajoute le token au cache et calcule la suite.
suivant
?
? "Tokens en cache :", ctx.tokens

&& 4. Complétion brute (sans gabarit de conversation).
ctx:reinitialiser()
? "Complétion :", ctx:completer("Liste de courses :\n1. pain\n2.", {maxtokens = 30, arrets = {"\n"}}).texte

&& 5. Voir le prompt exact envoyé au modèle.
locale conv = modele:conversation({systeme = "Sois bref."})
?
? "Gabarit détecté :", conv.gabarit
? conv:prompt("Salut")
&& Forcer un autre gabarit (modèles sans métadonnées) :
locale conv2 = modele:conversation({gabarit = "chatml"})

&& 6. Plusieurs contextes indépendants partageant les mêmes poids.
locale a = modele:conversation({systeme = "Tu ne réponds qu'en anglais.", maxtokens = 30})
locale b = modele:conversation({systeme = "Tu ne réponds qu'en espagnol.", maxtokens = 30})
? "A :", a:demander("Bonjour !").texte
? "B :", b:demander("Bonjour !").texte
? "Mémoire cache KV par contexte :", entier(a.memoire / (1024 * 1024)), "Mio"

&& 7. Perplexité : à quel point un texte est « attendu » par le modèle.
? "Perplexité (phrase correcte) :", arrondi(modele:perplexite("Le soleil se lève à l'est."), 1)
? "Perplexité (phrase absurde)  :", arrondi(modele:perplexite("Est le à lève se soleil le."), 1)
