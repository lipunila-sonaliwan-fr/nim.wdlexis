# Test du paquet firebird sans serveur

`fbmock.c` est une bibliothèque cliente Firebird **factice** : elle reproduit
les structures exactes d'`ibase.h` et le sous-ensemble de l'API ISC/DSQL
utilisé par `src/paquets/pkg_firebird.nim` (connexion, transactions,
descripteurs XSQLDA, paramètres, types de colonnes, BLOB en plusieurs
segments, messages d'erreur). Elle permet de vérifier la liaison sans
serveur Firebird.

```
gcc -shared -fPIC -o libfbclient.so tests/firebird/fbmock.c
WDLEXIS_FIREBIRD=$PWD/libfbclient.so ./wdlexisrt tests/firebird/principal.prg
```

Les valeurs renvoyées sont celles du simulateur (et non d'une vraie base).
Pour un essai réel : `exemples/firebird` avec un serveur Firebird.
