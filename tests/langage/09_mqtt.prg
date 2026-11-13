&& Paquet mqtt : serveur intégré, QoS 0 à 2, retenus, jokers, testament, file
procedure TEST
  globale recus
  recus = {}
  locale s = mqtt.serveur(0)
  locale p = s:port()
  locale a = mqtt.connecter("127.0.0.1", p, {id = "a", testament = {sujet = "etat/a", message = "perdu", retenu = vrai}})
  a:publier("maison/salon/t", "21", {qos = 1, retenu = vrai})
  locale b = mqtt.connecter("127.0.0.1", p, {id = "b"})
  ? "accordé :", b:abonner("maison/#", 2, @RECU), joindre(b:abonner({"etat/+", "x/y"}, 1, @RECU), ",")
  a:publier("maison/cuisine/t", "19", {qos = 2})
  a:publier("maison/x", "z", 0, faux)
  a:publier("autre", "ignoré")
  b:attendre(0.6)
  trier(recus)
  ? "reçus :", joindre(recus, " | ")
  && sans procédure : file de réception
  locale c = mqtt.connecter("127.0.0.1", p, {id = "c"})
  c:abonner("file/#", 1)
  a:publier("file/1", "un", {qos = 1})
  locale m = c:recevoir(2)
  ? "recevoir :", m.sujet, m.message, m.qos, m.retenu
  ? "correspond :", mqtt.correspond("a/+/c", "a/b/c"), mqtt.correspond("a/#", "a"), mqtt.correspond("a/+", "a/b/c"), mqtt.correspond("#", "$SYS/x")
  ? "clients :", s:statistiques().clients, "connecté :", c:connecte()
  a:deconnecter()
  b:deconnecter()
  c:deconnecter()
  ? "après :", c:connecte()
  s:arreter()
  ? "serveur actif :", s:actif()
retourner

procedure RECU(m)
  inserer(recus, m.sujet + "=" + m.message + "/" + m.qos + sisinon(m.retenu, "/r", ""))
retourner
