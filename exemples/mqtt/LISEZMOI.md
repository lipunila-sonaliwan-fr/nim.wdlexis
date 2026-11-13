# Maison connectée : MQTT

Exemple du paquet `mqtt` (MQTT 3.1.1, écrit en Nim pur) : des capteurs, des
lampes et un tableau de bord échangent des messages à travers un serveur MQTT
(« broker »).

```
wdlexisrt exemples/mqtt/principal.prg              serveur intégré (port 1883, ou un port libre)
wdlexisrt exemples/mqtt/principal.prg hote [port]  serveur externe (Mosquitto, EMQX, HiveMQ…)
```

Le serveur intégré tourne sur son propre fil d'exécution ; tout client MQTT peut
s'y connecter pendant que l'exemple fonctionne, par exemple :

```
mosquitto_sub -p 1883 -t 'maison/#' -v
mosquitto_pub -p 1883 -t maison/cuisine/lampe/commande -m allumer
```

## Les clients

| Client | Rôle | Ce qu'il montre |
| --- | --- | --- |
| `capteurs` | publie température et humidité de trois pièces chaque seconde | QoS 0, testament « hors ligne » (retenu), déconnexion propre |
| `lampes` | exécute `maison/<piece>/lampe/commande` (allumer, eteindre, basculer) | abonnement avec joker `+` et procédure, état publié en QoS 1 et retenu |
| `tableau` | abonné à `maison/#` | tableau des sujets, courbes, reconnexion automatique (`reconnecter = vrai`, `c:suretat`) |
| `thermostat` | créé par « Panne du thermostat » | client muet (maintien 1 s) : le serveur le coupe et publie son testament |

Une minuterie de 150 ms appelle `c:traiter()` sur chaque client : les messages
arrivés sont distribués aux procédures des abonnements, et la connexion est
maintenue (PINGREQ). Les onglets montrent les clients connus du serveur
(`s:clients()`) et son journal (`s:journal()`).

## En quelques lignes

```lexis
s = mqtt.serveur(1883)                                   && serveur intégré (facultatif)
c = mqtt.connecter("localhost", 1883, {id = "demo", reconnecter = vrai})
c:abonner("capteurs/+/temperature", 1, @MESURE)
c:publier("capteurs/salon/temperature", "21.5", {qos = 1, retenu = vrai})
c:attendre(2)                                            && traite les messages pendant 2 s

procedure MESURE(m)
  ? m.sujet, "=", m.message, "(QoS", m.qos, sisinon(m.retenu, ", retenu)", ")")
retourner
```

Sans procédure, `c:recevoir([delai])` rend le message suivant. Une table
publiée est encodée en JSON (`json.decoder(m.message)` à la réception). En TLS :
`mqtt.connecter(hote, 8883, {tls = vrai})`.
