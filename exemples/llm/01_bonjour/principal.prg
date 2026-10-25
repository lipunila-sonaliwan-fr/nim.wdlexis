&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 01 - La question la plus simple possible.
&&
&&   wdlexisrt exemples/llm/01_bonjour/principal.prg chemin/vers/modele.gguf
&&
&& Sans argument, le modèle est cherché dans la variable d'environnement
&& NIMLLM_MODEL puis dans models/Llama-3.2-1B-Instruct-Q4_K_M.gguf.

&& 1. Où se trouve le modèle ?
locale chemin = systeme.args[1] ou systeme.env("NIMLLM_MODEL") ou "models/llama-3.2-1B-Instruct-Q4_K_M.gguf"

&& 2. Chargement : le fichier est « mappé » en mémoire, c'est quasi instantané.
locale modele = llm.charger(chemin)

&& 3. Une conversation (avec un contexte par défaut de 4096 tokens).
locale conversation = modele:conversation()

&& 4. Une question, une réponse.
locale reponse = conversation:demander("Quelle est la formule pour calculer PI sans passer par la circonférence et le diamètre?")
? reponse.texte
