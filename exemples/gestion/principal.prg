&& Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr
&& Application métier en console : stock d'articles dans une base DuckDB,
&& mise à jour façon dBase (utiliser, chercher, remplacer, parcourir).
ouvrirbase(":memoire:")      && retirez cette ligne pour garder les données (donnees.duckdb)
sql [[create table if not exists articles(
  code varchar primary key, libelle varchar, prix decimal(10,2), stock integer)]]
si valeursql("select count(*) from articles") = 0
  pour chaque a dans {{"A01", "Stylo", 1.5, 120}, {"A02", "Cahier", 3.2, 40}, {"A03", "Gomme", 0.8, 0}}
    sql "insert into articles values (?, ?, ?, ?)" avec a[1], a[2], a[3], a[4]
  suivant
finsi

utiliser articles ordre "code"
? "Inventaire :"
parcourir
  ? "  " + code, libelle, chaine(prix, 6, 2), stock, sisinon(stock = 0, "(rupture)", "")
finparcourir

&& entrée en stock : 25 gommes
chercher "A03"
si trouve()
  remplacer stock par stock + 25
  ? "Réapprovisionné :", libelle, "→", stock
finsi

compter pour stock < 50 dans faible
? "Articles sous 50 unités :", faible
? "Valeur du stock :", valeursql("select sum(prix * stock) from articles")
? json(requete("select code, stock from articles order by code"))
