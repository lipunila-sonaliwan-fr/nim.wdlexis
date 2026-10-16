&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 18 — Spécialiser un modèle existant (ex. Llama 3.2 1B Instruct) avec
&& LoRA, à partir d'un fichier de questions/réponses, puis utiliser le résultat.
&&
&&   wdlexisrt exemples/llm/18_lora/principal.prg modele.gguf [donnees.jsonl]
&&
&& LoRA gèle les poids d'origine (ils restent quantifiés, en lecture seule) et
&& n'entraîne que de petites matrices « adaptateurs » : quelques Mo à
&& apprendre au lieu de plusieurs Go. Sur processeur, comptez plusieurs
&& minutes à quelques heures selon la taille du modèle et des données.

locale chemin = systeme.args[1] ou systeme.env("NIMLLM_MODEL") ou "models/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
locale donnees = systeme.args[2] ou fichier.joindre(systeme.dossierprogramme(), "donnees", "faq_boulangerie.jsonl")
locale consigne = "Tu es l'assistant de la boulangerie Dupont."

&& 1. Chargement en mode LoRA
locale m = entrainement.charger(chemin, {mode = "lora",
  rang = 8,                         && capacité de l'adaptateur (4 à 64).
  alpha = 16,                       && intensité (échelle = alpha / rang).
  cibles = {"q", "k", "v", "o", "gate", "up", "down"}})            && couches adaptées.
? "Paramètres entraînables :", m:nombreparametres(), "(le modèle de base reste gelé)"

&& 2. Les données : un dialogue par ligne JSON.
&& Formats acceptés par ligne :
&&   {"messages": [{"role": "user", "content": "..."}, {"role": "assistant", "content": "..."}]}
&&   {"prompt": "...", "response": "..."}      ou   {"instruction": "...", "output": "..."}
locale gabarit = m.gabarit                        && même gabarit que le modèle
locale ds = entrainement.jsonl(donnees, m.tokeniseur, gabarit, consigne)
? ds:taille(), "dialogues chargés (gabarit " + gabarit + ")"

&& Longueur maximale des exemples, pour choisir la longueur des séquences :
locale maxlong = ds:pluslong()
? "Exemple le plus long :", maxlong, "tokens"

&& 3. Entraînement
locale reglages = {
  etapes = 120,
  lot = 2,                          && séquences traitées ensemble (mémoire ∝ lot × sequence).
  accumulation = 2,                 && lot effectif = 4 séquences.
  sequence = min(maxlong, 256),
  lr = 2e-3,                        && LoRA tolère des taux plus élevés qu'un entraînement complet.
  echauffement = 10,
  journal = 10,
  evaluation = 0,
  sauvegarde = 50,                  && sauvegarde régulière de l'adaptateur.
  chemin = "boulangerie"}
m:entrainer(ds, reglages)

&& 4. Sauvegarde de l'adaptateur (quelques centaines de Kio).
m:enregistrerlora("boulangerie.lora.gguf")
?
? "Adaptateur : boulangerie.lora.gguf (" + entier(fichier.taille("boulangerie.lora.gguf") / 1024) + " Kio)"

&& 5. Utilisation : modèle de base + adaptateur appliqué à la volée.
locale base = llm.charger(chemin)
base:appliquerlora("boulangerie.lora.gguf")
locale conv = base:conversation({systeme = consigne, echantillonnage = llm.glouton(), maxtokens = 60})
pour chaque q dans {"Êtes-vous ouverts le lundi ?", "Combien coûte une baguette ?", "Qui est le boulanger ?"}
  conv:reinitialiser()
  ? "Q :", q
  ? "R :", conv:demander(q).texte
suivant

&& 6. ... ou fusion définitive dans un nouveau GGUF autonome.
gguf.fusionnerlora(chemin, "boulangerie.lora.gguf", "modele-boulangerie.gguf", "q8_0")
?
? "Modèle fusionné : modele-boulangerie.gguf"
&& Il s'utilise comme n'importe quel modèle, y compris avec llama.cpp ou Ollama, ex. :
&&   ollama create boulangerie -f Modelfile   (FROM ./modele-boulangerie.gguf)

base:retirerlora()                 && retour au modèle d'origine.
