&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 03 - Définir un contexte (prompt système), dialoguer sur plusieurs
&& tours, sauvegarder puis recharger la conversation.
&&
&&   wdlexisrt exemples/llm/03_conversation/principal.prg modele.gguf

locale chemin = systeme.args[1] ou systeme.env("NIMLLM_MODEL") ou "models/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
locale modele = llm.charger(chemin)

&& Le prompt système fixe le rôle, le ton et les règles du modèle.
locale conv = modele:conversation({
  systeme = [[Tu es Marcel, sommelier français à la retraite.
Tu réponds en deux phrases maximum, avec humour, et tu tutoies ton interlocuteur.]],
  contexte = 4096,
  maxtokens = 200})
&& contexte : mémoire de la conversation (en tokens),
&& maxtokens : longueur maximale de chaque réponse.

TOUR(conv, "Bonjour ! Quel vin avec une raclette ?")
TOUR(conv, "Et si je n'aime pas le vin blanc ?")                  && le modèle se souvient du tour précédent.
TOUR(conv, "Rappelle-moi ce que je t'ai demandé en premier.")

? "État :", conv:etat()

&& Sauvegarde / reprise.
conv:enregistrer("conversation_marcel.json")

locale reprise = modele:conversation()
reprise:charger("conversation_marcel.json")                       && restaure système + messages.
? "Messages rechargés :", #reprise.historique
? "Marcel (repris) :", reprise:demander("Et pour le dessert ?").texte

&& Annuler / régénérer.
reprise:annuler()                                                  && retire le dernier échange.
? "Après annuler :", #reprise.historique, "messages"

reprise:demander("Un vin pour accompagner des huîtres ?")
? "Autre proposition :", reprise:regenerer().texte                && nouveau tirage.

&& Changer de rôle en cours de route.
reprise.systeme = "Tu es un professeur de chimie rigoureux."
reprise:reinitialiser()                                            && oublie l'historique, garde le système.
? reprise:demander("Pourquoi le vin vieillit-il ?").texte

&& Exemples « few-shot » : on montre au modèle le format attendu.
locale classeur = modele:conversation({systeme = "Classe le sentiment : POSITIF, NEGATIF ou NEUTRE.",
                                        echantillonnage = llm.glouton(), maxtokens = 5})
classeur:ajouter("utilisateur", "Ce restaurant est formidable !")
classeur:ajouter("assistant", "POSITIF")
classeur:ajouter("utilisateur", "Le service était lent et froid.")
classeur:ajouter("assistant", "NEGATIF")
? "Sentiment :", classeur:demander("Le plat était correct, sans plus.").texte

procedure TOUR(c, question)
  ? "Vous    :", question
  ? "Marcel  :", c:demander(question).texte
  ?
retourner
