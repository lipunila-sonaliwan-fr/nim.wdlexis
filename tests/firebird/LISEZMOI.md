# Test du paquet firebird sans serveur Firebird

Le paquet `firebird` parle directement le protocole réseau de Firebird
(`src/paquets/firebird/fbwire.nim`) : il n'utilise plus la bibliothèque cliente
`fbclient`. `serveur_simule.py` est un **faux serveur** Firebird (protocole 17)
écrit en Python sans dépendance : il réalise côté serveur l'authentification
SRP (Srp256, ou Srp après un nouvel échange de clé publique), le chiffrement
Arc4, la description des instructions par éléments d'information (y compris
une réponse tronquée), l'exécution avec messages BLR, la lecture par lots, les
BLOB en segments et les erreurs (vecteur d'état), sur une petite table en
mémoire.

```
python3 tests/firebird/serveur_simule.py 3055 srp256 &     # ou srp, nocrypt
FBPORT=3055 ./wdlexisrt tests/firebird/principal.prg
```

Le serveur simulé suit la description publique du protocole : il vérifie la
cohérence du pilote (cadrage XDR, SRP, Arc4, BLR) mais ne remplace pas un essai
avec un vrai serveur Firebird 3, 4 ou 5 (`exemples/firebird`).
