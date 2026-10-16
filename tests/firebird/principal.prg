&& Test de la liaison firebird avec la bibliothèque factice fbmock.c (voir LISEZMOI.md).
? "disponible :", firebird.disponible()
? "version :", firebird.version()
essayer
  firebird.connecter("serveur:/data/absente.fdb", "SYSDBA", "x")
capturer e
  ? "connexion refusée :", e
finessayer

locale db = firebird.connecter("serveur/3050:/data/test.fdb", "SYSDBA", "masterkey", {role = "ADMIN", isolation = "instantane", attente = 5})
? "dpb/tpb :", db:valeur("select dpb from rdb$database")
locale db2 = firebird.connecter({hote = "srv", port = 3051, base = "/b.fdb", utilisateur = "u1", motdepasse = "p1", jeu = "WIN1252", attente = faux, lecture = vrai})
? "dpb/tpb (table) :", db2:valeur("select dpb from rdb$database")
db2:fermer()

? "--- requete"
pour chaque r dans db:requete("select * from client")
  ? json(r)
suivant
locale r1 = db:premier("select * from client")
? "notes :", longueur(r1.notes), gauche(r1.notes, 20), droite(r1.notes, 8)
? "types :", type(r1.id), type(r1.credit), type(r1.actif), type(r1.gros), r1.gros

? "--- paramètres (aller-retour)"
locale e1 = db:premier("select echo /*T:LNFDBOVV*/ ? ? ? ? ? ? ? ?", 42, 7, 2.5, "2024-03-12", repliquer("blob é ", 3000), vrai, "Élise", nul)
? e1.p1, e1.p2, e1.p3, e1.p4, longueur(e1.p5), e1.p5 = repliquer("blob é ", 3000), e1.p6, e1.p7, e1.p8
locale e2 = db:premier("select echo /*T:DVL*/ ? ? ?", "12.03.2024", 3.5, "17")
? e2.p1, e2.p2, e2.p3
locale e3 = db:premier("select echo /*T:LV*/ ? ?", {5, "liste"})
? e3.p1, e3.p2
essayer
  db:requete("select echo /*T:LL*/ ? ?", 1)
capturer e
  ? "paramètres manquants :", e
finessayer
essayer
  db:requete("select echo /*T:L*/ ?", {1, 2})
capturer e
  ? "table :", e
finessayer

? "--- executer"
? "insert :", db:executer("insert into client(nom) values (?)", "x"), db:modifications()
? "update :", db:executer("update client set nom = 'y'")
? "delete :", db:executer("delete from client")
? "script :", db:executer("insert into a values (1); update a set x = 2; -- commentaire ; \n delete from a where s = 'a;b'")
? "returning :", json(db:premier("insert into client(nom) values (?) returning id", "z"))
? "requete returning :", json(db:requete("insert into client(nom) values (?) returning id", "z"))
? "sequence :", db:sequence("GEN_CLIENT")
? "valeur :", db:valeur("select * from client")

? "--- transactions"
? "etat :", json(db:premier("select etat"))
db:transaction(@OK)
? "après transaction ok :", json(db:premier("select etat"))
essayer
  db:transaction(@RATEE)
capturer e
  ? "transaction ratée :", e
finessayer
? "après ratée :", json(db:premier("select etat")), db:entransaction()
db:debut({isolation = "serialisable", attente = faux})
? "en transaction :", db:entransaction(), db:valeur("select dpb from rdb$database")
db:executer("update t set a = 1")
db:valider()
db:debut()
db:annuler()
? "après debut/annuler :", json(db:premier("select etat"))
essayer
  db:valider()
capturer e
  ? "valider sans transaction :", e
finessayer

? "--- itérateur"
locale n = 0
pour chaque r dans db:lignes("select * from client")
  n += 1
suivant
? "lignes :", n, json(db:premier("select etat"))
pour chaque r dans db:lignes("select * from client")
  sortir
suivant
? "itérateur interrompu :", json(db:premier("select etat"))
pour chaque r dans db:lignes("insert into c(n) values (?) returning id", "q")
  ? "ligne returning :", json(r)
suivant

? "--- erreurs"
essayer
  db:executer("select syntaxe! from x")
capturer e
  ? "syntaxe :", e
finessayer
? "après erreur :", json(db:premier("select etat"))

locale db3 = firebird.creer("/tmp/nouvelle.fdb", "SYSDBA", "masterkey", {taillepage = 16384})
? "creer :", db3:valeur("select dpb from rdb$database")
db3:fermer()
db:fermer()
essayer
  db:requete("select 1")
capturer e
  ? "après fermeture :", e
finessayer

procedure OK(db)
  db:executer("insert into client(nom) values (?)", "ok")
retourner

procedure RATEE(db)
  db:executer("insert into client(nom) values (?)", "a")
  db:executer("insert into client erreur (nom) values (?)", nul)
retourner
