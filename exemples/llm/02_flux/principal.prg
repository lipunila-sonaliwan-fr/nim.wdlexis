&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 02 - Afficher la réponse au fil de l'eau (streaming) et mesurer la vitesse.
&&
&&   wdlexisrt exemples/llm/02_flux/principal.prg modele.gguf

locale chemin = systeme.args[1] ou systeme.env("NIMLLM_MODEL") ou "models/Llama-3.2-1B-Instruct-Q4_K_M.gguf"

&& « verbeux » affiche un résumé du modèle sur la sortie d'erreur.
locale modele = llm.charger(chemin, {verbeux = vrai})
locale conv = modele:conversation({maxtokens = 300})

&& La procédure AFFICHER reçoit chaque morceau de texte dès qu'il est produit.
&& Elle renvoie vrai pour continuer (ou faux pour interrompre).
es.ecrire("Assistant : ")
locale r = conv:demander("Explique en trois phrases ce qu'est un trou noir.", @AFFICHER)
?
? "---"
? "Tokens du prompt     :", r.tokensprompt
? "Tokens générés       :", r.tokensgeneres
? "Raison de l'arrêt    :", r.arret
? "Vitesse              :", entier(r.vitesse), "tokens/s"

&& Interrompre la génération : on s'arrête dès que 200 caractères sont reçus.
globale recu = 0
?
? "Réponse interrompue volontairement :"
locale r2 = conv:demander("Raconte une longue histoire de dragon.", @LIMITER)
?
? "(arrêt : " + r2.arret + ")"

fonction AFFICHER(morceau)
  es.ecrire(morceau)
retourner vrai

fonction LIMITER(morceau)
  globale recu
  es.ecrire(morceau)
  recu += longueur(morceau)
retourner recu < 200
