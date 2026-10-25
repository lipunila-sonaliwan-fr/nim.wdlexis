&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 19 - Inspecter un fichier GGUF et le (re)quantifier.
&&
&&   wdlexisrt exemples/llm/19_gguf_quantification/principal.prg modele.gguf [type]
&&
&& Types de sortie : f32 f16 bf16 q8_0 q6_k q5_k q5_0 q5_1 q4_k q4_0 q4_1
&& (sans argument : mini-assistant-f32.gguf, créé par l'exemple 17).

locale chemin = systeme.args[1] ou systeme.env("NIMLLM_MODEL") ou "mini-assistant-f32.gguf"
locale cible = systeme.args[2] ou "q4_k"

&& 1. Inspection des métadonnées et des tenseurs.
locale g = gguf.ouvrir(chemin)
? g:decrire(8)
locale arch = g:texte("general.architecture")
? "Architecture :", arch
? "Couches      :", g:entier(arch + ".block_count")
? "Gabarit chat :", sisinon(g:existe("tokenizer.chat_template"), "présent", "absent")

&& Répartition des formats de poids.
locale partype = {}
locale octets = 0
pour chaque t dans g:tenseurs()
  partype[t.type] = (partype[t.type] ou 0) + t.elements
  octets += t.octets
suivant
pour chaque ty, n dans partype
  ? "  " + ty + " :", n, "valeurs (" + chaine(gguf.bitsparpoids(ty), 0, 2) + " bits/poids)"
suivant
? "Taille des poids :", entier(octets / (1024 * 1024)), "Mio"

&& Lire un tenseur (en nombres)
locale premier = g:tenseur("output_norm.weight", 5)
? "output_norm.weight[1..5] =", joindre(premier, ", ")
g:fermer()

&& 2. Quantification.
locale sortie = remplacertexte(chemin, ".gguf", "") + "-" + minuscule(cible) + ".gguf"
gguf.quantifiermodele(chemin, sortie, cible)
?
? "Écrit :", sortie, "(" + entier(fichier.taille(sortie) / 1024) + " Kio, contre " + ;
  entier(fichier.taille(chemin) / 1024) + " Kio)"

&& 3. Mesurer la perte de qualité : perplexité avant / après.
locale texte = "La capitale de la France est Paris. Une banane est jaune. Après lundi vient mardi."
locale m
pour chaque f dans {chemin, sortie}
  m = llm.charger(f)
  ? fichier.nom(f), ": perplexité", chaine(m:perplexite(texte), 0, 3)
  m:fermer()
suivant

&& 4. Erreur de quantification d'un vecteur, format par format.
locale v = {}
pour i = 0 a 255
  inserer sin(i * 0.37) * 2 dans v
suivant
locale q
pour chaque t dans {"f16", "q8_0", "q6_k", "q5_k", "q4_k", "q4_0"}
  q = gguf.quantifier(t, v)
  ? "  " + t + " :", q.octets, "octets, erreur max", q.erreur
suivant
