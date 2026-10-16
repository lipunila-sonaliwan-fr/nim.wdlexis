&& Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr
&& Exemple LLM 10 — Faire produire un fichier (CSV, code source, configuration...).
&&
&&   wdlexisrt exemples/llm/10_fichier/principal.prg modele.gguf

locale chemin = systeme.args[1] ou systeme.env("NIMLLM_MODEL") ou "models/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
locale modele = llm.charger(chemin)
locale conv = modele:conversation({echantillonnage = {temperature = 0.3}, maxtokens = 800})

&& Le contenu est écrit tel quel (les balises ``` éventuelles sont retirées).
locale r1 = conv:demander("Crée un fichier CSV de 5 fruits avec les colonnes nom,couleur,calories.",
                          {format = "fichier", sortie = "fruits.csv"})
? "→", r1.fichiers[1]
? fichier.lire(r1.fichiers[1])

conv:reinitialiser()
locale r2 = conv:demander("Écris un programme Nim qui affiche les 10 premiers nombres de Fibonacci.",
                          {format = "fichier", sortie = "fibonacci.nim"})
? "→", r2.fichiers[1]

&& Une pièce jointe + une sortie fichier = transformation de documents.
conv:reinitialiser()
fichier.ecrire("notes.txt", "acheter du pain\nappeler Léa\nréserver le train pour Lyon\n")
locale r3 = conv:demander("Transforme cette liste en tableau Markdown avec une colonne Priorité.",
                          {pieces = {llm.joindre("notes.txt")}, format = "fichier", sortie = "taches.md"})
? fichier.lire(r3.fichiers[1])

&& Plusieurs fichiers d'un coup : on enchaîne les demandes.
locale r
pour chaque t dans {{"README.md", "un README pour un outil de sauvegarde"},
                    {".gitignore", "un .gitignore pour un projet Nim"}}
  conv:reinitialiser()
  r = conv:demander("Écris " + t[2] + ".", {format = "fichier", sortie = t[1]})
  ? t[1], ":", #decouper(r.texte, "\n"), "lignes"
suivant
