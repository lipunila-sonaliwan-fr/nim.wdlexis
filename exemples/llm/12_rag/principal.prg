&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 12 - Questions sur vos documents (RAG : recherche + génération).
&&
&&   wdlexisrt exemples/llm/12_rag/principal.prg modele.gguf
&&
&& 1. on découpe des documents en passages ;
&& 2. on calcule un vecteur (« embedding ») par passage avec le modèle ;
&& 3. pour une question, on retrouve les passages les plus proches ;
&& 4. on les joint à la question.
&&
&& Remarque : les embeddings issus d'un modèle génératif sont moins précis que
&& ceux d'un modèle spécialisé ; on les combine ici avec un score lexical.

locale chemin = systeme.args[1] ou systeme.env("NIMLLM_MODEL") ou "models/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
modele = llm.charger(chemin)                && globale : utilisée par RECHERCHER

&& Base documentaire (remplacez par vos fichiers : fichier.lire(...)).
locale documents = {
  {"conges.txt", "Chaque salarié dispose de 25 jours de congés payés par an. Les demandes " +
                 "se font au moins un mois à l'avance via le portail RH."},
  {"teletravail.txt", "Le télétravail est autorisé deux jours par semaine, le mardi et le " +
                      "jeudi, après accord du responsable d'équipe."},
  {"tickets.txt", "Les tickets restaurant ont une valeur de 9 euros, dont 60 % pris en " +
                  "charge par l'entreprise."},
  {"materiel.txt", "Un ordinateur portable est fourni à l'arrivée. Toute panne doit être " +
                   "signalée au service informatique au poste 4242."}}

index = {}
pour chaque doc dans documents
  pour chaque p dans PASSAGES(doc[2], 400)
    inserer {source = doc[1], texte = p, vecteur = modele:vecteur(p)} dans index
  suivant
suivant
? #index, "passages indexés."

&& Questions.
locale conv = modele:conversation({systeme = "Tu réponds uniquement à partir des documents fournis. " +
  "Si l'information n'y figure pas, dis-le. Cite la source entre crochets.", maxtokens = 200})

locale trouves, pieces, sources
pour chaque question dans {"Combien de jours de télétravail sont permis ?",
                           "Qui contacter si mon PC tombe en panne ?",
                           "Quel est le salaire minimum ?"}
  trouves = RECHERCHER(question, 2)
  pieces = {}
  sources = {}
  pour chaque p dans trouves
    inserer llm.joindretexte(p.source, p.texte) dans pieces
    inserer p.source dans sources
  suivant
  conv:reinitialiser()
  ?
  ? "Q :", question
  ? "   (passages : " + joindre(sources, ", ") + ")"
  ? "R :", conv:demander(question, {pieces = pieces}).texte
suivant

&& Découpe en passages d'environ « taille » caractères, sur les fins de phrase.
fonction PASSAGES(texte, taille)
  locale res = {}
  locale cur = ""
  pour chaque phrase dans decouper(texte, ". ")
    si longueur(cur) + longueur(phrase) > taille et cur <> ""
      inserer rogner(cur) dans res
      cur = ""
    finsi
    cur = cur + phrase + ". "
  suivant
  si rogner(cur) <> ""
    inserer rogner(cur) dans res
  finsi
retourner res

&& Ensemble des mots de plus de 3 lettres (clefs d'une table).
fonction MOTS(s)
  locale t = minuscule(s)
  pour chaque c dans {",", ".", "'", "?", "!", ";", ":"}
    t = remplacertexte(t, c, " ")
  suivant
  locale res = {}
  pour chaque m dans decouper(t, " ")
    si longueur(m) > 3
      res[m] = vrai
    finsi
  suivant
retourner res

fonction RECHERCHER(question, k)
  locale q = modele:vecteur(question)
  locale mq = MOTS(question)
  locale nq = nbelements(mq)
  locale scores = {}
  locale communs, lexical
  pour i = 1 a #index
    communs = 0
    pour chaque m, v dans MOTS(index[i].texte)
      si mq[m] <> nul
        communs += 1
      finsi
    suivant
    lexical = communs / max(1, nq)
    inserer {score = 0.5 * llm.similarite(q, index[i].vecteur) + 0.5 * lexical, i = i} dans scores
  suivant
  trier(scores, @MEILLEUR)
  locale res = {}
  pour i = 1 a min(k, #scores)
    inserer index[scores[i].i] dans res
  suivant
retourner res

fonction MEILLEUR(a, b)
retourner a.score > b.score
