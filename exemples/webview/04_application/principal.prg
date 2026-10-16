&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& webview : une petite application complète. La page (HTML / CSS / JavaScript)
&& est l'interface ; Lexis+ garde les données, applique les règles et les
&& enregistre dans taches.json (dossier du programme).
&&   - la page appelle les procédures autorisées : lexis.appeler("AJOUTER", texte)...
&&   - Lexis+ prévient la page des changements : f:emettre("taches", liste)
&& Lancement : wdlexisrt exemples/webview/04_application/principal.prg

chemin = fichier.joindre(systeme.dossierprogramme(), "taches.json")
taches = CHARGER()
prochain = 1
pour chaque t dans taches
  si t.id >= prochain
    prochain = t.id + 1
  finsi
suivant

f = webview.fenetre{titre = "Tâches - Lexis+", largeur = 560, hauteur = 640, fichier = "page.htm"}
f:autoriser("LISTER", "AJOUTER", "BASCULER", "SUPPRIMER", "VIDER_FAITES", "STATISTIQUES")
f.surpret = @PRET
f.surfermeture = @ENREGISTRER
f:executer()
? #taches, "tâche(s) enregistrée(s) dans", chemin

procedure PRET(ev)
  f:emettre("taches", taches)
retourner

fonction CHARGER()
  si fichier.existe(chemin)
    essayer
      locale t = dejson(fichier.lire(chemin))
      si type(t) = "table"
        retourner t
      finsi
    capturer e
      ? "taches.json illisible, liste vide :", e
    finessayer
  finsi
retourner {}

procedure ENREGISTRER()
  fichier.ecrire(chemin, json(taches))
retourner

procedure PREVENIR()
  && après chaque modification : enregistrer et mettre la page à jour
  ENREGISTRER()
  f:emettre("taches", taches)
  f.titre = "Tâches - Lexis+ (" + RESTANTES() + " à faire)"
retourner

fonction RESTANTES()
  locale n = 0
  pour chaque t dans taches
    si non t.faite
      n += 1
    finsi
  suivant
retourner n

fonction LISTER()
retourner taches

fonction AJOUTER(texte, priorite)
  texte = rogner(chaine(texte))
  si longueur(texte) = 0
    erreur "Le texte de la tâche est vide."
  finsi
  si longueur(texte) > 120
    erreur "120 caractères au plus."
  finsi
  locale t = {id = prochain, texte = texte, faite = faux, ;
              priorite = sisinon(priorite = "haute", "haute", "normale"), creee = maintenant()}
  prochain += 1
  inserer t dans taches
  PREVENIR()
retourner t

fonction CHERCHER(id)
  pour i = 1 a #taches
    si taches[i].id = id
      retourner i
    finsi
  suivant
  erreur "tâche introuvable : " + id
retourner

fonction BASCULER(id)
  locale t = taches[CHERCHER(id)]
  t.faite = non t.faite
  PREVENIR()
retourner t.faite

fonction SUPPRIMER(id)
  retirer de taches position CHERCHER(id)
  PREVENIR()
retourner vrai

fonction VIDER_FAITES()
  locale garder = {}
  locale n = 0
  pour chaque t dans taches
    si t.faite
      n += 1
    sinon
      inserer t dans garder
    finsi
  suivant
  taches = garder
  PREVENIR()
retourner n

fonction STATISTIQUES()
  locale s = {total = #taches, faites = 0, hautes = 0}
  pour chaque t dans taches
    si t.faite
      s.faites += 1
    sinonsi t.priorite = "haute"
      s.hautes += 1
    finsi
  suivant
retourner s
