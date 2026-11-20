&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Test du paquet firebird (pilote natif) contre le serveur simulé
&& serveur_simule.py (voir LISEZMOI.md) : authentification SRP, chiffrement Arc4,
&& paramètres, types, BLOB en plusieurs segments, RETURNING, EXECUTE PROCEDURE,
&& lecture par lots, description tronquée (600 colonnes), séquence, erreurs.
fb = paquet("firebird")
? "version", fb.version(), fb.disponible()
port = systeme.env("FBPORT") ou "3055"
db = fb.connecter("127.0.0.1/" + port + ":/data/test.fdb", "sysdba", "masterkey")
? "serveur", db:serveur()
? "create", db:executer("create table t (id integer)")
long = ""
pour i = 1 a 5000
  long = long + "0123456789"
suivant
? "insert", db:executer("insert into t (nom, prix, dt, note, ok, code, taux) values (?, ?, ?, ?, ?, ?, ?)", "Dupont é", 12.5, "2026-11-17", long, vrai, "AB", 0.25)
? "insert2", db:executer("insert into t (nom, prix, ok) values (?, ?, ?)", "Martin", 7, nul)
r = db:requete("insert into t (nom) values (?) returning id", "Durand")
? "returning", r[1].id
pour i = 1 a 450
  db:executer("insert into t (nom, prix) values (?, ?)", "n" + chaine(i), i)
suivant
lignes = db:requete("select * from t")
? "nb lignes", #lignes
l1 = lignes[1]
? "l1", l1.id, l1.nom, l1.prix, l1.dt, longueur(l1.note), l1.ok, "[" + l1.code + "]", l1.big, l1.ts, l1.taux
? "l2", lignes[2].nom, lignes[2].prix, lignes[2].ok, lignes[2].note
? "premier", db:premier("select * from t where id > ?", 2).nom
? "valeur", db:valeur("select * from t")
n = 0
pour chaque x dans db:lignes("select * from t")
  n = n + 1
suivant
? "iterateur", n
? "proc", db:requete("execute procedure p")[1].total
? "large", db:premier("select * from large").c599
? "sequence", db:sequence("g"), db:sequence("g")
db:debut()
? "entransaction", db:entransaction()
db:annuler()
? "supprime", db:executer("delete from t")
essayer
  db:requete("select * from nope")
capturer e
  ? "erreur attendue", e
finessayer
? "tables ok apres erreur", db:valeur("select rdb$get_context('SYSTEM','ENGINE_VERSION') from rdb$database")
db:fermer()
