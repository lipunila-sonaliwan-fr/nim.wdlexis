&& Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr
&& HTTP, TCP local (serveur dans un fil d'exécution) et SSH (si configuré)
essayer
  locale r = http.requete{url = "https://example.com", delai = 10}
  ? "HTTP", r.statut, longueur(r.corps), "octets"
capturer e
  ? "HTTP indisponible :", e
finessayer

&& petit serveur TCP local dans un fil d'exécution (les attentes réseau
&& y sont bloquantes sans gêner le programme principal)
serveur = fil.demarrer([[
s = reseau.ecouter(5577, "127.0.0.1")
fil.envoyer("prêt")
c = s:accepter()
c:envoyer("écho : " + c:recevoir("l") + car(10))
c:fermer()
s:fermer()
]])
? "serveur :", serveur:recevoir(5)

&& le client
c = reseau.connecter("127.0.0.1", 5577, {delai = 5})
c:envoyer("bonjour" + car(10))
? c:recevoir("l")
c:fermer()
serveur:joindre()

&& SSH : décommentez et adaptez (authentification par clef)
&& s = ssh.connecter{hote = "serveur", utilisateur = "moi", clef = "~/.ssh/id_ed25519"}
&& ? s:executer("uname -a").sortie
&& s:envoyer("local.txt", "/tmp/distant.txt")
