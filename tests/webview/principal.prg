&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Test du paquet webview avec la bibliothèque factice wvmock.c (voir LISEZMOI.md).
&& Le scénario.txt simule les appels JavaScript reçus par la fenêtre.
? "disponible :", webview.disponible()
? "version :", webview.version()
? "js :", webview.js({nom = "Ada", age = 36, langages = {"Lexis+", "JS"}})
? "url :", droite(webview.url("page avec espace.htm"), 26)

f = webview.fenetre{titre = "Test", largeur = 640, hauteur = 480, taille = "min", ;
                    html = "<h1>Bonjour</h1>"}
? "titre :", f.titre, "prête :", f.prete
f:lier("total", @TOTAL)
f:lier("double")                       && procédure du même nom
f:lier("echec", @ECHOUE)
f:autoriser("ENREGISTRER", "fermer")
f.surpret = @PRET
f.surmessage = @MESSAGE
f.surfermeture = @FERME
f:evaluer("1 + 1")                     && avant la page : mis en attente
f:executer()
? "après executer, ouverte :", f.ouverte
essayer
  f:evaluer("2")
capturer e
  ? "erreur attendue :", e
finessayer

&& seconde fenêtre : fermeture par l'utilisateur, appels non autorisés
g = webview.fenetre("Deuxième")
g:lier("total")
g:executer()

&& troisième fenêtre : systeme.quitter() depuis un appel JavaScript termine la boucle et le programme
h = webview.fenetre("Troisième")
h:lier("quitter", @QUITTER)
? "avant la troisième fenêtre"
h:executer()
? "jamais affiché"

procedure QUITTER(code)
  ? "QUITTER", code
  systeme.quitter(code)
retourner

procedure PRET(ev)
  ? "PRET", ev.url
  f.titre = "Page prête"
  f:appeler("afficher", "Bonjour depuis Lexis+", {n = 3}, @RESULTAT)
  f:evaluer("document.title", @RESULTAT)
  f:appeler("app.maj", 1, 2)
  f:emettre("horloge", {heure = "12:00"})
retourner

fonction TOTAL(a, b)
retourner a + b

fonction DOUBLE(x)
retourner {valeur = x * 2, texte = "double de " + x}

fonction ECHOUE()
  erreur "échec volontaire"
retourner

fonction ENREGISTRER(fiche)
  ? "ENREGISTRER", fiche.nom, fiche.age
retourner {ok = vrai, id = 7}

procedure FERMER()
  ? "FERMER demandé par la page"
  f:fermer()
retourner

procedure MESSAGE(d)
  ? "MESSAGE", d.texte
retourner

procedure RESULTAT(valeur, erreur)
  si erreur = nul
    ? "RESULTAT", json(valeur)
  sinon
    ? "RESULTAT en erreur :", erreur
  finsi
retourner

procedure FERME()
  ? "FERME", f.ouverte
retourner
