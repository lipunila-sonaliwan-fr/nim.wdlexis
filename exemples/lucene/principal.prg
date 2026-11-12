&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Bibliothèque : recherche plein texte avec Lucene++ (paquet lucene).
&&
&&   wdlexisrt exemples/lucene/principal.prg
&&
&& Il faut la bibliothèque du paquet (libwdlexis_lucene.so / .dylib /
&& wdlexis_lucene.dll, construite par outils/lucenepp.sh) dans le dossier linOS
&& (macOS, winOS) à côté de l'exécutable ou de ce programme, ou indiquée par la
&& variable WDLEXIS_LUCENE.
&&
&& L'index (format Lucene 3.0) est créé dans le dossier personnel
&& (bibliotheque_lucene) au premier lancement avec le corpus de livres.prg. La
&& recherche se fait pendant la frappe :
&&   hugo                      mots dans titre, auteur, résumé (analyseur français : pluriels, racines)
&&   "comte de monte-cristo"   phrase exacte
&&   paris -hugo               exclure un mot ; OR pour l'un ou l'autre
&&   annee:[1850 TO 1880]      intervalle sur un champ numérique
&&   genre:aventure            valeur exacte d'un champ « cle »
&&   mer*  voyag~              joker, recherche floue

ui = paquet("interface")

si non lucene.disponible()
  ui.alerte("Lucene n'est pas disponible :" + car(10) + lucene.erreur(), "stop", "Bibliothèque")
  systeme.quitter(1)
finsi

&& index : identifiant exact, genre exact (filtre, tri), année et pages numériques ;
&& titre, auteur et résumé deviennent des champs texte (analysés) à la première valeur.
idx = lucene.ouvrir(fichier.joindre(fichier.dossierperso(), "bibliotheque_lucene"), ;
                    {analyseur = "francais", ;
                     schema = {id = "cle", genre = "cle", annee = "entier", pages = "entier", ;
                               titre = "texte", auteur = "texte", resume = "texte"}})
si idx:nombre() = 0
  INDEXER()
finsi

resultats = {}          && documents affichés (dans l'ordre du tableau)

fen = ui.fenetre{titre = "Bibliothèque - " + lucene.version(), largeur = 1040, hauteur = 640, ;
                 disposition = "bordure"}
fen.surfermeture = @FERMETURE

&& barre de recherche
haut = fen:ajouter(ui.rangee())
haut.ancrage = "haut"
haut.marge = 8
haut.espacement = 8
haut:ajouter(ui.etiquette("Rechercher :"))
saisie = haut:ajouter(ui.saisie{indication = "hugo, \"phrase exacte\", annee:[1850 TO 1880], genre:aventure, mer*…"})
saisie.poids = 1
saisie.surchangement = @CHERCHER
haut:ajouter(ui.etiquette("Tri :"))
tri = haut:ajouter(ui.combo("Pertinence", "Année croissante", "Année décroissante", "Genre", "Nombre de pages"))
tri.largeurfixe = 170
tri:selectionner(1)
tri.surselection = @CHERCHER
breindex = haut:ajouter(ui.bouton("Réindexer"))
breindex.surclic = @REINDEXER
baide = haut:ajouter(ui.bouton("Syntaxe"))
baide.surclic = @AIDE

&& suggestions (termes indexés) et état
suggestions = fen:ajouter(ui.etiquette(""))
suggestions.ancrage = "haut"
suggestions.couleur = "#8A8F98"
etat = fen:ajouter(ui.etiquette(""))
etat.ancrage = "bas"

&& résultats à gauche, fiche du livre à droite
sep = fen:ajouter(ui.separateur{vertical = vrai, position = 0.58})
sep.ancrage = "centre"
tab = sep:ajouter(ui.tableau())
tab:ajoutercolonne("Score", 64, "droite")
tab:ajoutercolonne("Titre", 220)
tab:ajoutercolonne("Auteur", 150)
tab:ajoutercolonne("Année", 64, "droite")
tab:ajoutercolonne("Genre", 80)
tab.surselection = @FICHE
fiche = sep:ajouter(ui.markdown("Saisissez une recherche : les résultats s'affichent pendant la frappe."))

CHERCHER()
saisie:focus()
ui.executer()

procedure INDEXER
  && corpus de livres.prg : remplacer() met à jour un livre de même id, sinon l'ajoute
  pour chaque l dans LIVRES()
    idx:remplacer(l)
  suivant
  idx:valider()
retourner

procedure REINDEXER(ev)
  idx:vider()
  INDEXER()
  CHERCHER()
  etat.libelle = chaine(idx:nombre()) + " livres réindexés."
retourner

procedure CHERCHER(ev)
  globale resultats
  locale q = rogner(saisie.valeur)
  locale opts = {max = 50}
  faire cas
  cas tri:selection() = 2
    opts.tri = "annee"
  cas tri:selection() = 3
    opts.tri = "annee"
    opts.inverse = vrai
  cas tri:selection() = 4
    opts.tri = "genre"
  cas tri:selection() = 5
    opts.tri = "pages"
    opts.inverse = vrai
  fincas
  locale t0 = systeme.horloge()
  locale r
  essayer
    r = idx:chercher(sisinon(q = "", "*", q), opts)
  capturer e
    && requête incomplète pendant la frappe (parenthèse, guillemet…) : on attend la suite
    etat.libelle = "Requête incomplète : " + e
    retourner
  finessayer
  locale ms = arrondi((systeme.horloge() - t0) * 1000, 1)
  resultats = {}
  tab:vider()
  pour chaque x dans r.resultats
    inserer(resultats, x.document)
    tab:ajouterligne(sisinon(q = "", "", chaine(arrondi(x.score, 2))), x.document.titre, x.document.auteur, ;
                     chaine(x.document.annee), x.document.genre)
  suivant
  etat.libelle = chaine(r.total) + " livre(s) sur " + chaine(idx:nombre()) + " en " + ms + " ms" + ;
                 sisinon(q = "", "", "   -   requête Lucene : " + idx:analyser(q))
  SUGGERER(q)
  si #resultats > 0
    tab:selectionner(1)
    FICHE()
  sinon
    fiche.valeur = "*Aucun livre ne correspond.*"
  finsi
retourner

procedure SUGGERER(q)
  && termes indexés qui commencent comme le dernier mot saisi (autocomplétion)
  locale mots = decouper(minuscule(q), " ")
  locale dernier = sisinon(#mots > 0, mots[#mots], "")
  si longueur(dernier) < 2 ou contient(dernier, ":") ou contient(dernier, "*") ou contient(dernier, "\"")
    suggestions.libelle = ""
    retourner
  finsi
  locale vus = {}
  locale liste = {}
  pour chaque champ dans {"titre", "auteur", "resume"}
    pour chaque t dans idx:termes(champ, dernier, 6)
      si vus[t.terme] = nul
        vus[t.terme] = vrai
        inserer(liste, t.terme + " (" + t.documents + ")")
      finsi
    suivant
  suivant
  suggestions.libelle = sisinon(#liste = 0, "", "  Termes indexés : " + joindre(liste, "   "))
retourner

procedure FICHE(ev)
  locale i = tab:selection()
  si i < 1 ou i > #resultats
    retourner
  finsi
  locale d = resultats[i]
  fiche.valeur = "# " + d.titre + car(10) + car(10) + ;
                 "**" + d.auteur + "** - " + d.annee + " - " + d.genre + " - " + d.pages + " pages" + car(10) + car(10) + ;
                 d.resume + car(10) + car(10) + "`id : " + d.id + "`"
retourner

procedure AIDE(ev)
  fiche.valeur = [[# Syntaxe de recherche (Lucene)

- `hugo misérables` : tous les mots (titre, auteur, résumé) ; accents et pluriels sont ramenés à leur racine (analyseur français)
- `hugo OR zola` : l'un ou l'autre ; `paris -hugo` : sans le mot
- `"comte de monte-cristo"` : phrase exacte
- `titre:mer` : dans un seul champ
- `annee:[1850 TO 1880]`, `pages:{500 TO *}` : intervalles numériques
- `genre:aventure` : valeur exacte (champ clé)
- `voyag*`, `m?r` : jokers ; `baudelair~` : recherche floue
- `(hugo OR dumas) AND annee:[1840 TO 1870]` : regroupements]]
retourner

procedure FERMETURE(ev)
  idx:fermer()
retourner
