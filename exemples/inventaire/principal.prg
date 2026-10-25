&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Inventaire du stock, rayon par rayon, dans un état PDF
rayons = {
  {nom = "Papeterie", articles = {
    {reference = "PAP-001", article = "Ramette papier A4 80 g (500 feuilles)", quantite = 140, prix = 4.9},
    {reference = "PAP-014", article = "Cahier 96 pages grands carreaux", quantite = 320, prix = 1.65},
    {reference = "PAP-027", article = "Bloc-notes repositionnables 76 x 76", quantite = 85, prix = 2.3}}},
  {nom = "Écriture", articles = {
    {reference = "ECR-003", article = "Stylo bille bleu pointe moyenne", quantite = 600, prix = 0.45},
    {reference = "ECR-019", article = "Surligneur jaune fluo", quantite = 210, prix = 0.95},
    {reference = "ECR-022", article = "Porte-mine 0,5 mm avec gomme", quantite = 48, prix = 3.2}}},
  {nom = "Classement", articles = {
    {reference = "CLA-008", article = "Classeur à levier dos 80 mm, carton rigide recouvert de polypropylène, coloris assortis", quantite = 75, prix = 3.9},
    {reference = "CLA-011", article = "Pochettes perforées (100)", quantite = 120, prix = 5.4}}}}

r = rapport.début("stock.pdf")
r.entête("entete", {magasin = "Papeterie du Port — Brest"})
r.pied("pied", {magasin = "Papeterie du Port"})
r.ajoute("colonnes", {})

total = 0
nb = 0
pour chaque ry dans rayons
  r.ajoute("rayon", {rayon = ry.nom})
  locale montant = 0
  pour chaque a dans ry.articles
    locale valeur = a.quantite * a.prix
    montant += valeur
    nb += 1
    r.ajoute("article", {reference = a.reference, article = a.article, quantite = a.quantite, ;
                         prix = a.prix, valeur = valeur})
  suivant
  r.ajoute("soustotal", {rayon = ry.nom, montant = montant})
  total += montant
suivant

r.ajoute("synthese", {rayons = #rayons, articles = nb, total = total})   && sautavant : nouvelle page
? "État écrit :", r.fin()
? "Pages :", r.nombrepages()
? "Valeur du stock :", total
