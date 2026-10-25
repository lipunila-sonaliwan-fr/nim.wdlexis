&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 17 - Créer un nouveau modèle de langage de A à Z :
&& données -> tokeniseur -> architecture -> pré-entraînement -> ajustement
&& au dialogue -> export GGUF -> conversation.
&&
&&   wdlexisrt exemples/llm/17_creer_modele/principal.prg
&&
&& Durée : quelques minutes sur un processeur ordinaire. Le modèle obtenu est
&& minuscule (≈ 1 M de paramètres) : il ne connaît que ce qu'on lui enseigne
&& ici, mais le procédé est exactement celui des grands modèles.

llm.fils(0)                         && tous les cœurs

&& 1. Les données.
locale capitales = {{"France", "Paris"}, {"Italie", "Rome"}, {"Espagne", "Madrid"},
  {"Allemagne", "Berlin"}, {"Portugal", "Lisbonne"}, {"Belgique", "Bruxelles"},
  {"Suisse", "Berne"}, {"Autriche", "Vienne"}, {"Grèce", "Athènes"}, {"Pologne", "Varsovie"},
  {"Suède", "Stockholm"}, {"Norvège", "Oslo"}, {"Irlande", "Dublin"}, {"Russie", "Moscou"}}
locale fruits = {{"banane", "jaune"}, {"fraise", "rouge"}, {"kiwi", "vert"}, {"orange", "orange"},
  {"myrtille", "bleue"}, {"cerise", "rouge"}, {"citron", "jaune"}, {"prune", "violette"}}
locale jours = {"lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"}

&& Questions/réponses (pour le dialogue) - on varie les formulations.
dialogues = {}                      && globale : remplie par QA
pour chaque pc dans capitales
  QA("Quelle est la capitale de la " + pc[1] + " ?", "La capitale de la " + pc[1] + " est " + pc[2] + ".")
  QA("Capitale de la " + pc[1] + " ?", pc[2] + ".")
suivant
pour chaque fc dans fruits
  QA("De quelle couleur est une " + fc[1] + " ?", "Une " + fc[1] + " est " + fc[2] + ".")
suivant
pour i = 1 a 7
  QA("Quel jour vient après " + jours[i] + " ?", "Après " + jours[i] + " vient " + jours[i % 7 + 1] + ".")
suivant
pour a = 0 a 9
  pour b = 0 a 9
    QA("Combien font " + a + " plus " + b + " ?", a + " plus " + b + " font " + (a + b) + ".")
  suivant
suivant
pour chaque salut dans {"Bonjour", "Salut", "Bonsoir", "Coucou"}
  QA(salut + " !", salut + " ! Comment puis-je t'aider ?")
suivant
QA("Qui es-tu ?", "Je suis un tout petit modèle de langage écrit en Nim.")
QA("Merci !", "Avec plaisir !")

&& Un texte libre (pré-entraînement : apprendre la langue).
locale texte = ""
pour chaque pc dans capitales
  texte = texte + "La capitale de la " + pc[1] + " est " + pc[2] + ". "
suivant
pour chaque fc dans fruits
  texte = texte + "Une " + fc[1] + " est " + fc[2] + ". "
suivant
pour i = 1 a 7
  texte = texte + "Après " + jours[i] + " vient " + jours[i % 7 + 1] + ". "
suivant

&& 2. Le tokeniseur.
locale echantillon = texte
pour chaque d dans dialogues
  echantillon = echantillon + d.question + "\n" + d.reponse + "\n"
suivant
locale tok = entrainement.tokeniseur(echantillon, {taille = 512})
? "Tokeniseur :", tok.taille, "tokens"

&& 3. L'architecture (type Llama).
locale modele = entrainement.nouveau(tok, {
  dimension = 128,                  && largeur des vecteurs.
  couches = 4,                      && nombre de blocs Transformer.
  tetes = 4,                        && têtes d'attention.
  tetes_kv = 2,                     && têtes clé/valeur (attention groupée, comme Llama 3).
  contexte = 128,                   && longueur de contexte maximale.
  nom = "mini-assistant",
  graine = 7})
? "Paramètres :", modele:nombreparametres()

&& 4. Pré-entraînement sur le texte.
locale corpus = entrainement.textes(tok, repliquer(texte, 4))
locale reglages = {etapes = 150, lot = 8, sequence = 64, lr = 3e-3, echauffement = 15,
                   journal = 50, evaluation = 0}
?
? "== Pré-entraînement =="
locale t0 = systeme.horloge()
modele:entrainer(corpus, reglages)

&& 5. Ajustement au dialogue (SFT) : on n'apprend que les réponses.
locale sft = entrainement.dialogues(tok, "chatml", dialogues)
locale parts = sft:separer(0.05)                  && {entraînement, validation}
reglages.etapes = 900
reglages.sequence = sft:pluslong()                && doit couvrir le plus long dialogue.
reglages.lr = 2e-3
reglages.evaluation = 300
reglages.echantillon = 0
reglages.validation = parts[2]
?
? "== Ajustement au dialogue (" + sft:taille() + " exemples) =="
modele:entrainer(parts[1], reglages)
? "Durée totale :", entier(systeme.horloge() - t0), "s"

&& 6. Export : un vrai fichier GGUF (lisible aussi par llama.cpp / Ollama).
modele:enregistrer("mini-assistant-f32.gguf")
gguf.quantifiermodele("mini-assistant-f32.gguf", "mini-assistant-q8.gguf", "q8_0")
?
? "Modèle exporté : mini-assistant-f32.gguf et mini-assistant-q8.gguf"

&& 7. On discute avec lui via le paquet llm habituel.
locale lm = llm.charger("mini-assistant-q8.gguf")
locale conv = lm:conversation({echantillonnage = llm.glouton(), maxtokens = 60, contexte = 128})
&& Remarque : 5 % des dialogues ont été mis de côté pour la validation ; une
&& erreur sur l'une de ces questions (jamais vues) montre les limites de
&& généralisation d'un modèle d'un million de paramètres.
pour chaque q dans {"Bonjour !", "Quelle est la capitale de la Grèce ?", "Combien font 3 plus 4 ?",
                    "Quel jour vient après jeudi ?", "De quelle couleur est une fraise ?", "Qui es-tu ?"}
  conv:reinitialiser()
  ? "Vous :", q
  ? "IA   :", conv:demander(q).texte
suivant

procedure QA(q, r)
  inserer {question = q, reponse = r} dans dialogues
retourner
