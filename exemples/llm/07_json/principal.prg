&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 07 — Obtenir une réponse structurée en JSON (extraction d'informations).
&&
&&   wdlexisrt exemples/llm/07_json/principal.prg modele.gguf
&&
&& Le JSON est converti en table Lexis+ : les clefs sont en majuscules et,
&& comme tout nom Lexis+, insensibles à la casse (r.json.nom = r.json.NOM).

locale chemin = systeme.args[1] ou systeme.env("NIMLLM_MODEL") ou "models/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
locale modele = llm.charger(chemin)

&& Une température basse rend la sortie plus régulière.
locale conv = modele:conversation({echantillonnage = {temperature = 0.2}, maxtokens = 300})

&& 1. Forme courte : demanderjson renvoie directement une table.
locale villes = conv:demanderjson("Donne trois grandes villes d'Italie avec leur région.",
  [[{"villes": [{"nom": "texte", "region": "texte"}]}]])
&& Accès prudent : on vérifie la présence de la liste avant de la parcourir.
si type(villes) = "table" et type(villes.villes) = "table"
  pour chaque v dans villes.villes
    ? "-", v.nom ou "?", "(" + (v.region ou "?") + ")"
  suivant
finsi

&& 2. Forme complète : demander(..., {format = "json"}).
conv:reinitialiser()
locale courriel = [[Bonjour, je m'appelle Julie Martin, j'ai commandé le 12 mars
une bouilloire (réf. BX-220) qui ne chauffe plus. Pouvez-vous me rembourser ?
Mon téléphone : 06 12 34 56 78.]]
locale r = conv:demander("Extrais les informations de ce message client :\n" + courriel, {
  format = "json",
  schema = [[{"nom": str, "date_commande": str, "produit": str, "reference": str,
               "demande": "remboursement|échange|information", "telephone": str}]]})
? json.encoder(r.json, vrai)
? "Référence :", r.json.reference ou "?"

&& 3. Vérifier que les champs attendus sont présents (l'équivalent de la
&&    conversion en objet typé de la version Nim).
locale manquants = {}
pour chaque champ dans {"nom", "produit", "reference"}
  si r.json[majuscule(champ)] = nul
    inserer champ dans manquants
  finsi
suivant
si #manquants = 0
  ? "Fiche :", r.json.nom, "/", r.json.produit, "/", r.json.reference
sinon
  ? "Champ manquant :", joindre(manquants, ", ")
finsi

&& 4. Si le modèle échoue.
&& demander réessaie automatiquement (conv.essaisjson = 2 par défaut, avec une
&& température divisée par deux) puis lève une erreur.
conv.essaisjson = 3
essayer
  conv:demanderjson("Liste les jours de la semaine.", [[{"jours": [str]}]])
capturer e
  ? "Échec :", e
finessayer

&& 5. Extraire du JSON d'un texte quelconque.
? json.encoder(llm.extrairejson("Voici le résultat : ```json\n{\"ok\": true}\n``` Bonne journée !"))
