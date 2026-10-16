&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 14 — Donner des « outils » au modèle (appel de fonctions).
&&
&&   wdlexisrt exemples/llm/14_outils/principal.prg modele.gguf
&&
&& Le modèle décide, en JSON, s'il faut appeler une procédure Lexis+ ; le
&& programme l'exécute et renvoie le résultat au modèle, qui formule la
&& réponse finale. C'est le principe des « agents ».

locale chemin = systeme.args[1] ou systeme.env("NIMLLM_MODEL") ou "models/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
locale modele = llm.charger(chemin)

locale description = [[Tu peux utiliser ces outils :
- heure() : heure actuelle
- calcul(a, b, operation) : opération parmi + - * / ^
- meteo(ville) : météo d'une ville
Si un outil est utile, réponds UNIQUEMENT avec un JSON :
{"outil": "nom", "arguments": {...}}
Sinon, réponds UNIQUEMENT avec : {"outil": "aucun", "reponse": "ta réponse"}]]

&& globale : utilisée par la procédure DEMANDER.
agent = modele:conversation({systeme = description, echantillonnage = {temperature = 0.1}, maxtokens = 200})

pour chaque q dans {"Combien font 1234 multiplié par 56 ?", "Quel temps fait-il à Nantes ?",
                    "Quelle heure est-il ?", "Qui a écrit Les Misérables ?"}
  ? "Q :", q
  essayer
    ? "R :", DEMANDER(q)
    ?
  capturer e
    ? "Erreur :", e
    ?
  finessayer
suivant

&& Les outils disponibles.
fonction OUTIL_HEURE(args)
retourner systeme.date("%H:%M")

&& Calculatrice minimaliste : a <op> b
fonction OUTIL_CALCUL(args)
  locale a = valeur(args.a)
  locale b = valeur(args.b)
  faire cas
  cas args.operation = "+"
    retourner a + b
  cas args.operation = "-"
    retourner a - b
  cas args.operation = "*"
    retourner a * b
  cas args.operation = "/"
    retourner sisinon(b = 0, "division par zéro", a / b)
  cas args.operation = "^"
    retourner a ^ b
  fincas
retourner "opération inconnue"

fonction OUTIL_METEO(args)
  && Ici on simule ; en réalité, interrogez votre propre source de données.
retourner "Ensoleillé, 22 °C à " + (args.ville ou "?")

fonction DEMANDER(question)
  agent:reinitialiser()
  locale decision = agent:demander(question, {format = "json"})
  locale j = decision.json ou {}
  locale outil = j.outil ou "aucun"
  ? "  [décision]", json(j)
  si outil = "aucun"
    retourner j.reponse ou decision.texte
  finsi
  locale args = j.arguments ou {}
  locale resultat
  faire cas
  cas outil = "heure"
    resultat = OUTIL_HEURE(args)
  cas outil = "calcul"
    resultat = OUTIL_CALCUL(args)
  cas outil = "meteo"
    resultat = OUTIL_METEO(args)
  autrement
    resultat = "outil inconnu"
  fincas
  ? "  [résultat de " + outil + "]", resultat
  && On renvoie le résultat ; le modèle rédige la réponse finale en texte libre.
  agent:ajouter("utilisateur", "Résultat de l'outil " + outil + " : " + resultat +
                "\nRéponds maintenant à la question initiale en une phrase, sans JSON.")
retourner rogner(agent:generer().texte)
