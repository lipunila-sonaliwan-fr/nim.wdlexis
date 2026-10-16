&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 20 — Entraînement long : points de sauvegarde, reprise, suivi de
&& la validation, journal CSV et accumulation de gradients.
&&
&&   wdlexisrt exemples/llm/20_reprise_entrainement/principal.prg [corpus.txt]
&&
&& Relancez le programme : il reprend là où il s'était arrêté.

locale texte
si systeme.args[1] <> nul
  texte = fichier.lire(systeme.args[1])
sinon
  texte = repliquer("Le renard brun rapide saute par-dessus le chien paresseux. " +
                    "Les sanglots longs des violons de l'automne blessent mon cœur. ", 200)
finsi

locale PREFIXE = "mon_modele"                     && mon_modele.gguf + mon_modele.optim.gguf

locale modele
locale opt = nul
si fichier.existe(PREFIXE + ".gguf")
  && Reprise : poids complets en float32 + état de l'optimiseur.
  modele = entrainement.charger(PREFIXE + ".gguf", {mode = "complet"})
  opt = modele:optimiseur()
  si fichier.existe(PREFIXE + ".optim.gguf")
    opt:charger(PREFIXE + ".optim.gguf")
  finsi
  ? "Reprise à l'étape", opt.pas
sinon
  locale tok = entrainement.tokeniseur(texte, {taille = 400})
  modele = entrainement.nouveau(tok, {dimension = 96, couches = 3, tetes = 4, contexte = 128})
  ? "Nouveau modèle :", modele:nombreparametres(), "paramètres"
finsi

locale parts = entrainement.textes(modele.tokeniseur, texte):separer(0.1)   && {entraînement, validation}

&& Journal personnalisé : écran + fichier CSV (globale : utilisée par JOURNALISER).
journal = es.ouvrir("journal.csv", "a")

locale reglages = {
  etapes = 100,                     && étapes supplémentaires à chaque exécution.
  lot = 4,
  accumulation = 2,                 && lot effectif = 4 x 2 séquences (moins de mémoire).
  sequence = 64,
  lr = 2e-3,
  evaluation = 25,
  sauvegarde = 50,
  chemin = PREFIXE,
  echantillon = 50,                 && affiche un échantillon de texte généré.
  amorce = "Le renard",
  validation = parts[2],
  optimiseur = opt,
  rappel = @JOURNALISER}

opt = modele:entrainer(parts[1], reglages)
modele:sauvegarder(opt, PREFIXE)
journal:fermer()

? "Perplexité de validation :", chaine(exp(modele:evaluer(parts[2], 8, 4, 64)), 0, 2)
? "Génération :", modele:generer("Les sanglots", {maxtokens = 30, temperature = 0.5})

procedure JOURNALISER(l)
  locale ligne = "étape " + chaine(l.etape, 5) + " | perte " + chaine(l.perte, 0, 4)
  si l.validation <> nul
    ligne = ligne + " | val " + chaine(l.validation, 0, 4)
  finsi
  ? ligne + " | lr " + chaine(l.lr, 0, 6) + " | " + entier(l.vitesse) + " tok/s"
  journal:ecrire(joindre({l.etape, l.perte, l.validation ou "", l.lr}, ",") + "\n")
  journal:vider()
retourner
