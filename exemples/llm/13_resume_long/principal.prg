&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 13 — Résumer un document plus long que le contexte (« map-reduce »).
&&
&&   wdlexisrt exemples/llm/13_resume_long/principal.prg modele.gguf document.txt
&&
&& Le texte est découpé en morceaux qui tiennent dans le contexte ; chacun est
&& résumé, puis les résumés partiels sont fusionnés.

locale chemin = systeme.args[1] ou systeme.env("NIMLLM_MODEL") ou "models/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
locale modele = llm.charger(chemin)
locale tok = modele.tokeniseur

locale texte
si systeme.args[2] <> nul
  texte = fichier.lire(systeme.args[2])
sinon
  texte = repliquer("La Révolution industrielle débute en Grande-Bretagne au XVIIIe siècle. " +
                    "La machine à vapeur transforme l'industrie textile puis les transports. " +
                    "Les villes grandissent rapidement et la condition ouvrière devient un enjeu politique. ", 60)
finsi

locale TOKENS_PAR_MORCEAU = 1500

&& Découpage par nombre de tokens (et non de caractères) : précis et sûr.
locale morceaux = {}
locale cur = ""
locale essai
pour chaque paragraphe dans decouper(texte, ". ")
  essai = cur + paragraphe + ". "
  si longueur(tok:encoder(essai)) > TOKENS_PAR_MORCEAU et cur <> ""
    inserer cur dans morceaux
    cur = paragraphe + ". "
  sinon
    cur = essai
  finsi
suivant
si rogner(cur) <> ""
  inserer cur dans morceaux
finsi
? #morceaux, "morceaux à résumer (" + longueur(tok:encoder(texte)) + " tokens au total)"

locale conv = modele:conversation({systeme = "Tu es un assistant de synthèse précis et concis.",
                                   contexte = 4096, echantillonnage = {temperature = 0.3}, maxtokens = 250})

&& Étape « map » : un résumé par morceau.
locale partiels = {}
locale r
pour i = 1 a #morceaux
  conv:reinitialiser()
  r = conv:demander("Résume ce passage en 3 points clés :",
                    {pieces = {llm.joindretexte("passage.txt", morceaux[i])}})
  inserer r.texte dans partiels
  ? "Morceau", i + "/" + #morceaux, "résumé (" + r.tokensgeneres + " tokens)"
suivant

&& Étape « reduce » : fusion des résumés.
conv:reinitialiser()
locale final = conv:demander("Voici des résumés partiels d'un même document. Rédige un résumé " +
                             "global de 5 lignes maximum, sans répétitions :\n\n" + joindre(partiels, "\n\n"),
                             {format = "markdown", maxtokens = 400})
?
? "=== Résumé ==="
? final.texte
