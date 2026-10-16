&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Fichiers, CSV, JSON, base DuckDB en mémoire et données binaires
locale chemin = fichier.joindre(fichier.dossiertemp(), "ventes.csv")
fichier.ecrire(chemin, "region,mois,montant" + car(10) + "Nord,1,1200" + car(10) + "Sud,1,950" + car(10) + "Nord,2,1430" + car(10))

locale lignes = csv.lire(chemin, {entete = vrai})
locale total = 0
pour chaque r dans lignes
  total += r.montant
suivant
? "lignes :", #lignes, "total :", total
? json.encoder(lignes, vrai)

ouvrirbase(":memoire:")
sql "create table ventes(region varchar, mois integer, montant double)"
pour chaque r dans lignes
  sql "insert into ventes values (?, ?, ?)" avec r.region, r.mois, r.montant
suivant
sql "select region, sum(montant) as s from ventes group by region order by s desc" dans res
pour chaque r dans res
  ? chaine(r.region) + espace(8 - longueur(r.region)) + chaine(r.S, 10, 2)
suivant

&& la même chose, enregistrement par enregistrement, à la manière de dBase
utiliser ventes ordre "montant desc"
parcourir pour region = "Nord"
  ? numenr(), mois, montant
finparcourir

locale entete = binaire.coder("<I4 z d", 42, "wdlexis", 3.5)
locale v = binaire.decoder("<I4 z d", entete)
? "binaire :", binaire.hex(entete), v[1], v[2], v[3]
