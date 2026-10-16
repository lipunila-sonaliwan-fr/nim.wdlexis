&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& webview : Lexis+ -> JavaScript.
&&   f:appeler(fonction, arg..., [@rappel])  appelle une fonction JavaScript de la page
&&   f:evaluer(code, [@rappel])              évalue du code JavaScript
&&   f:emettre(nom, donnees)                 déclenche les écouteurs lexis.sur(nom, fn)
&& Le rappel reçoit (valeur, erreur) : le résultat arrive de façon asynchrone,
&& quand la page a répondu (une fonction JavaScript peut aussi renvoyer une Promise).
&& Lancement : wdlexisrt exemples/webview/02_lexis_vers_js/principal.prg

produits = {{nom = "Stylo", prix = 1.2, stock = 40}, ;
            {nom = "Cahier", prix = 3.5, stock = 12}, ;
            {nom = "Agrafeuse", prix = 14.9, stock = 3}}

f = webview.fenetre{titre = "Lexis+ -> JavaScript", largeur = 760, hauteur = 560, ;
                    fichier = "page.htm", debogage = vrai}
f.surpret = @PRET                  && la page est chargée : on peut l'appeler
f.surmessage = @MESSAGE            && la page demande quelque chose (lexis.envoyer)
f:executer()

procedure PRET(ev)
  ? "page chargée :", ev.url
  && 1. appel simple, sans résultat attendu
  f:appeler("afficher", "Bonjour ! Ce message vient de Lexis+ (" + heure() + ").")
  && 2. une table Lexis+ devient un objet JavaScript (clefs en minuscules)
  pour chaque p dans produits
    f:appeler("ajouterLigne", p)
  suivant
  && 3. appel avec résultat : calculer() est asynchrone côté JavaScript
  f:appeler("calculer", produits, @TOTAL_CALCULE)
  && 4. évaluer une expression JavaScript et récupérer sa valeur
  f:evaluer("navigator.userAgent", @NAVIGATEUR)
  f:evaluer("document.querySelectorAll('#produits tr').length", @NB_LIGNES)
  && 5. une fonction inexistante : le rappel reçoit l'erreur
  f:appeler("fonctionAbsente", @RESULTAT)
  && 6. un objet de la page (chemin pointé) et un événement
  f:appeler("app.theme", "clair")
  f:emettre("horloge", {heure = heure(), date = date()})
retourner

procedure TOTAL_CALCULE(valeur, erreur)
  si erreur <> nul
    ? "calculer() a échoué :", erreur
    retourner
  finsi
  ? "valeur du stock calculée par JavaScript :", valeur.total, "pour", valeur.articles, "articles"
  f.titre = "Stock : " + chaine(valeur.total, 1, 2) + " €"
retourner

procedure NAVIGATEUR(valeur, erreur)
  ? "moteur web :", valeur
retourner

procedure NB_LIGNES(valeur, erreur)
  ? "lignes affichées :", valeur
retourner

procedure RESULTAT(valeur, erreur)
  si erreur = nul
    ? "résultat :", valeur
  sinon
    ? "erreur JavaScript reçue par Lexis+ :", erreur
  finsi
retourner

procedure MESSAGE(d)
  && la page envoie {action = ...} : Lexis+ répond en appelant de nouveau la page
  faire cas
  cas d.action = "theme"
    f:appeler("app.theme", d.valeur)
    f:appeler("afficher", "Thème « " + d.valeur + " » appliqué par Lexis+.")
  cas d.action = "horloge"
    f:emettre("horloge", {heure = heure(), date = date()})
  cas d.action = "remise"
    pour chaque p dans produits
      p.prix = arrondi(p.prix * 0.9, 2)
    suivant
    f:appeler("viderLignes")
    pour chaque p dans produits
      f:appeler("ajouterLigne", p)
    suivant
    f:appeler("calculer", produits, @TOTAL_CALCULE)
    f:appeler("afficher", "Remise de 10 % appliquée par Lexis+.")
  autrement
    ? "message inconnu :", json(d)
  fincas
retourner
