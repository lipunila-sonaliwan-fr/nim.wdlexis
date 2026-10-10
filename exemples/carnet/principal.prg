&& Tous droits réservés 2026 - Jean-Marc QUÉRÉ, sonaliwan.fr
&& Carnet d'adresses : grille wdgui + base DuckDB + menus
ui = paquet("interface")

ouvrirbase(fichier.joindre(fichier.dossierperso(), "carnet_wdlexis.duckdb"))
sql "create sequence if not exists seq_contacts"
sql "create table if not exists contacts(id integer primary key default nextval('seq_contacts'), nom varchar, courriel varchar, age integer)"

fen = ui.fenetre{titre = "Carnet", largeur = 720, hauteur = 460, disposition = "bordure"}
menu = fen:ajouter(ui.barremenu())
menu:ancrage("haut")
menu:ajouter("Fichier", "Ajouter un contact")
menu:ajouter("Fichier", "Exporter en CSV…")
menu:ajouter("Fichier", "Quitter")

grille = fen:ajouter(ui.grille{multi = faux})
&&grille.ancrage = "centre"
grille:ajoutercolonne{nom = "id", titre = "#", genre = "nombre", largeur = 50, decimales = 0}
grille:ajoutercolonne{nom = "nom", titre = "Nom", largeur = 220}
grille:ajoutercolonne{nom = "courriel", titre = "Courriel", largeur = 260}
grille:ajoutercolonne{nom = "age", titre = "Âge", genre = "nombre", largeur = 70, decimales = 0}
grille:fixerpied("age", "moyenne")
menu.surselection = @MENU

RECHARGER()
ui.executer()

procedure RECHARGER
  grille:vider()
  utiliser contacts ordre "nom"
  parcourir
    grille:ajouterligne(id, nom, courriel, age)
  finparcourir
  fermer contacts
retourner

procedure MENU(ev)
  locale choix = ev.texte
  si ev.chemin <> nul
    choix = ev.chemin[#ev.chemin]
  finsi
  faire cas
  cas choix = "Ajouter un contact"
    locale n = ui.demander("Nom :", "")
    si n <> ""
      sql "insert into contacts(nom, courriel, age) values (?, ?, ?)" ;
        avec n, ui.demander("Courriel :", ""), nombre(ui.demander("Âge :", ""))
      RECHARGER()
    finsi
  cas choix = "Exporter en CSV…"
    locale p = ui.enregistrerfichier{nom = "contacts.csv", filtre = "CSV|*.csv"}
    si p <> nul
      grille:enregistrercsv(p)
    finsi
  cas choix = "Quitter"
    fen:fermer()
  fincas
retourner
