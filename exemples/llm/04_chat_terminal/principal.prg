&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 04 - Un assistant complet dans la console (de l'atelier ou du terminal).
&&
&&   wdlexisrt exemples/llm/04_chat_terminal/principal.prg modele.gguf
&&
&& Commandes disponibles pendant la discussion :
&&   /system <texte>     change le prompt système (et efface l'historique)
&&   /joindre <fichier>  joint un fichier au prochain message
&&   /format <f>         texte | markdown | json | image | audio | fichier
&&   /temp <valeur>      change la température (0 = déterministe)
&&   /sauver <f.json>    enregistre la conversation
&&   /charger <f.json>   recharge une conversation
&&   /annuler            retire le dernier échange
&&   /refaire            régénère la dernière réponse
&&   /reset              nouvelle conversation
&&   /stats              état du contexte
&&   /quitter

locale chemin = systeme.env("NIMLLM_MODEL") ou "./models/llama-3.2-1B-Instruct-Q4_K_M.gguf"

? "Chargement de", chemin, "..."
locale modele = llm.charger(chemin, {verbeux = vrai})
locale conv = modele:conversation({systeme = "Tu es un assistant serviable qui répond en français.",
                                   contexte = 4096, maxtokens = 1024})

locale joints = {}
locale format = "texte"
locale compteur = 0
locale fini = faux
locale ligne, cmd, arg, p, sortie, r, enflux

? "Prêt. Tapez /quitter pour sortir."
?
tantque non fini
  ligne = saisir("Vous> ")
  si ligne = nul
    sortir
  finsi
  ligne = rogner(ligne)
  si ligne = ""
    boucler
  finsi
  si commencepar(ligne, "/")
    p = position(" ", ligne)
    cmd = sisinon(p > 0, gauche(ligne, p - 1), ligne)
    arg = sisinon(p > 0, rogner(souschaine(ligne, p + 1)), "")
    essayer
      faire cas
      cas cmd = "/quitter" ou cmd = "/q"
        fini = vrai
      cas cmd = "/system"
        conv.systeme = arg
        conv:reinitialiser()
        ? "Prompt système modifié."
      cas cmd = "/joindre"
        inserer llm.joindre(arg) dans joints
        ? "Joint :", arg, "(" + joints[#joints].type + ")"
      cas cmd = "/format"
        si non contient({"texte", "markdown", "json", "image", "audio", "fichier"}, arg)
          erreur "format inconnu : " + arg
        finsi
        format = arg
        ? "Format :", format
      cas cmd = "/temp"
        conv.echantillonnage = {temperature = valeur(arg)}
        ? "Température :", conv.echantillonnage.temperature
      cas cmd = "/sauver"
        conv:enregistrer(arg)
        ? "Enregistré."
      cas cmd = "/charger"
        ? "Chargé :", conv:charger(arg), "messages."
      cas cmd = "/annuler"
        conv:annuler()
        ? "Dernier échange retiré."
      cas cmd = "/refaire"
        es.ecrire("Assistant> ")
        conv:regenerer(@AFFICHER)
        ?
      cas cmd = "/reset"
        conv:reinitialiser()
        ? "Nouvelle conversation."
      cas cmd = "/stats"
        ? conv:etat()
      autrement
        ? "Commande inconnue."
      fincas
    capturer e
      ? "Erreur :", e
    finessayer
    boucler
  finsi
  && message normal.
  compteur += 1
  faire cas
  cas format = "image"
    sortie = "image_" + compteur + ".svg"
  cas format = "audio"
    sortie = "reponse_" + compteur + ".wav"
  cas format = "fichier"
    sortie = "fichier_" + compteur + ".txt"
  autrement
    sortie = ""
  fincas
  es.ecrire("Assistant> ")
  essayer
    enflux = format = "texte" ou format = "markdown"
    r = conv:demander(ligne, {pieces = joints, format = format, sortie = sortie,
                              flux = sisinon(enflux, @AFFICHER, nul)})
    si non enflux
      ? r.texte
    finsi
    ?
    pour chaque f dans r.fichiers
      ? "  → fichier créé :", f
    suivant
  capturer e
    ?
    ? "Erreur :", e
  finessayer
  joints = {}
fintantque

fonction AFFICHER(morceau)
  es.ecrire(morceau)
retourner vrai
