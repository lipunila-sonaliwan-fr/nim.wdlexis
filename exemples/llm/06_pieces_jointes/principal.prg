&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 06 — Poser une question accompagnée de pièces jointes.
&&
&&   wdlexisrt exemples/llm/06_pieces_jointes/principal.prg modele.gguf
&&
&& Formats pris en charge : texte/code/CSV/JSON/Markdown/HTML (contenu),
&& PDF (texte extrait), PNG/BMP/PPM (couleurs + aperçu), JPEG/GIF/WebP
&& (dimensions), WAV (durée et format). Rappel : Llama 3.2 1B/3B est un
&& modèle *textuel* : une image lui est décrite, il ne la « voit » pas.

locale chemin = systeme.args[1] ou systeme.env("NIMLLM_MODEL") ou "models/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
locale modele = llm.charger(chemin)
locale conv = modele:conversation({contexte = 8192, maxtokens = 400})

&& 1. Un fichier texte du disque.
fichier.ecrire("ventes.csv", [[mois,produit,quantite,prix
janvier,stylo,120,1.5
janvier,cahier,40,3.2
fevrier,stylo,95,1.5
fevrier,cahier,60,3.2
mars,stylo,150,1.4
]])
locale r1 = conv:demander("Quel produit rapporte le plus ? Donne le chiffre d'affaires par produit.",
                          {pieces = {llm.joindre("ventes.csv")}})
? "CSV →", r1.texte
?

&& 2. Plusieurs pièces jointes, dont une construite en mémoire.
conv:reinitialiser()
locale note = llm.joindretexte("note.md", "# Réunion du 3 mars\n- Budget validé : 12 000 €\n- Lancement : avril")
locale code = llm.joindretexte("calcul.nim", "proc moyenne(x: seq[float]): float =\n  for v in x: result += v\n  result / x.len.float")
locale r2 = conv:demander("Résume la note, puis signale le bug du code.", {pieces = {note, code}})
? "Note + code →", r2.texte
?

&& 3. Une image (ici générée pour l'exemple).
conv:reinitialiser()
locale paysage = dessin.svg([[<svg viewBox="0 0 100 100"><rect width="100" height="100" fill="skyblue"/>
  <circle cx="75" cy="25" r="15" fill="gold"/><rect y="70" width="100" height="30" fill="green"/></svg>]], 200, 200)
paysage:enregistrerbmp("paysage.bmp")
locale img = llm.joindre("paysage.bmp")
? "Ce que le modèle reçoit pour l'image :"
? img:texte()
?
? "Image →", conv:demander("Décris cette image et devine ce qu'elle représente.", {pieces = {img}}).texte
?

&& 4. Un PDF.
&& locale pdf = llm.joindre("contrat.pdf")       && texte extrait automatiquement
&& ? conv:demander("Quelles sont les dates clés de ce contrat ?", {pieces = {pdf}}).texte
&& (un simple chemin est aussi accepté : {pieces = {"contrat.pdf"}})

&& 5. Contrôler la taille insérée dans le prompt.
&& Les gros fichiers sont tronqués à 12 000 caractères par défaut ; pour un
&& contrôle fin, construisez vous-même le texte :
locale gros = llm.joindretexte("journal.log", repliquer("ligne de journal\n", 5000))
? "Taille insérée :", longueur(gros:texte(2000)), "caractères"
