&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 05 — Régler la génération : température, top-k/top-p/min-p,
&& pénalité de répétition, graine (reproductibilité), chaînes d'arrêt, longueur.
&&
&&   wdlexisrt exemples/llm/05_parametres/principal.prg modele.gguf

locale chemin = systeme.args[1] ou systeme.env("NIMLLM_MODEL") ou "models/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
locale modele = llm.charger(chemin)
locale question = "Invente un nom pour une boulangerie."

&& 1. Décodage glouton : toujours la même réponse (idéal pour extraire, classer).
locale c1 = modele:conversation({echantillonnage = llm.glouton(), maxtokens = 40})
? "Glouton            :", c1:demander(question).texte

&& 2. Plusieurs températures : plus elle est haute, plus le texte est varié.
&&    Une table partielle complète les réglages par défaut (llm.echantillonnage()).
locale c
pour chaque t dans {0.3, 0.8, 1.3}
  && graine fixe => résultat reproductible.
  c = modele:conversation({echantillonnage = {temperature = t, graine = 42}, maxtokens = 40})
  ? "Température", t, "   :", c:demander(question).texte
suivant

&& 3. Réglages fins.
locale p = {
  temperature = 0.7,
  topk = 40,            && ne garder que les 40 tokens les plus probables,
  topp = 0.9,           && ... puis le plus petit ensemble couvrant 90 % de probabilité,
  minp = 0.05,          && ... et éliminer ceux < 5 % de la probabilité du meilleur,
  repetition = 1.15,    && décourage les répétitions,
  fenetre = 64,         && ... sur les 64 derniers tokens.
  presence = 0,
  frequence = 0,
  graine = 7}
locale c3 = modele:conversation({echantillonnage = p})

&& 4. Longueur maximale et chaînes d'arrêt.
c3.maxtokens = 60
c3.arrets = {"\n\n"}             && s'arrête au premier paragraphe.
locale r = c3:demander("Écris un poème sur la mer.")
? "Poème (1er paragraphe) :", r.texte
? "Arrêt :", r.arret

&& 5. Interdire ou favoriser des tokens (biais logit).
locale tok = modele.tokeniseur
locale p5 = llm.glouton()
pour chaque mot dans {"Paris", " Paris"}
  pour chaque id dans tok:encoder(mot)
    p5.biais[id] = -100           && interdit « Paris ».
  suivant
suivant
locale c5 = modele:conversation({echantillonnage = p5, maxtokens = 30})
? "Sans « Paris » :", c5:demander("Cite une grande ville française.").texte
