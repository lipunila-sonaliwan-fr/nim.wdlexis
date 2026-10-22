&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple d'état PDF : une facture de plusieurs pages.
&&
&& La mise en page est dessinée dans l'éditeur d'états (Conception > Ouvrir un
&& état…, ou double-clic sur etat_facture.prg) : zones « entete » (première
&& page), « suite » (en-tête des pages suivantes), « colonnes », « ligne »
&& (extensible : une longue désignation l'agrandit), « total » et « pied ».
&& Ici, le programme ne fait que donner les valeurs des {variables}.

societe = {societe = "Atelier Kerlann", adresse = "12 quai de la Douane" + car(10) + "29200 Brest", ;
           siret = "123 456 789 00012"}
taux = 20

articles = {}
pour i = 1 a 42
  inserer(articles, {designation = "Article de démonstration n° " + i, quantite = 1 + i % 4, prix = 9.5 + i * 1.25})
suivant
articles[7].designation = "Prestation de mise en service sur site, avec déplacement, réglages, essais " + ;
                          "et formation de deux personnes à l'utilisation (demi-journée)"

r = rapport.début("facture.pdf")
r.entête("entete", {societe = societe.societe, adresse = societe.adresse, numero = "2026-0142", ;
                    client = "Librairie du Port", client_adresse = "3 rue de Siam" + car(10) + "29200 Brest"})
r.pied("pied", {societe = societe.societe, siret = societe.siret})
r.ajoute("colonnes", {})
&& à partir de la page 2 : l'en-tête « suite »
r.entete("suite", {numero = "2026-0142", client = "Librairie du Port"})

ht = 0
pour chaque a dans articles
  locale total = a.quantite * a.prix
  ht += total
  r.ajoute("ligne", {designation = a.designation, quantite = a.quantite, prix = a.prix, total = total})
suivant

r.ajoute("total", {ht = ht, taux = taux, tva = ht * taux / 100, ttc = ht * (1 + taux / 100), ;
                   mentions = "Paiement à 30 jours. Pas d'escompte pour paiement anticipé."})
chemin = r.fin()
? "Facture écrite :", chemin, "(" + r.nombrepages() + " pages)"
