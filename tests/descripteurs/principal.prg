&& Contrôle manuel des descripteurs de fichiers : exécuter puis arrêter ce programme
&& plusieurs fois depuis l'atelier ; le nombre de fichiers ouverts de wdlexis+ doit rester
&& stable (macOS : lsof -p <pid> | wc -l ; Linux : ls /proc/<pid>/fd | wc -l).
ui = paquet("interface")
f = es.ouvrir(fichier.joindre(fichier.dossiertemp(), "fd_test.txt"), "e")
f:ecrire("x")
db = sqlite.ouvrir(fichier.joindre(fichier.dossiertemp(), "fd_test.db"))
db:executer("create table if not exists t(a)")
s = reseau.ecouter(0)
fen = ui.fenetre{titre = "Test descripteurs", largeur = 600, hauteur = 500}
fen:ajouter(ui.markdown("# Titre\n**gras** *italique* `code`"))
fen:ajouter(ui.markdown("## Deux"))
ed = fen:ajouter(ui.editeur())
ed:nouveau("a.prg")
d = fen:ajouter(ui.diagramme())
d:noeud{id = "a", titre = "A"}
? "prêt"
ui.executer()
