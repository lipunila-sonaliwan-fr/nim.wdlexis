&& Paquet document : texte, langue, mots, phrases, passages, mots-clés, concepts, extraits
procedure TEST
  locale nl = car(10)
  locale t = "# Les index" + nl + nl + "Un index inversé garde, pour chaque terme, la liste des documents. " + ;
             "L'index inversé rend la recherche rapide." + nl + nl + "## Analyse" + nl + ;
             "Un analyseur découpe le texte en termes. Les termes sont normalisés." + nl
  locale m = document.markdown(t)
  ? "markdown :", remplacertexte(m, nl, " / ")
  ? "langue :", document.langue(m), document.langue("The quick brown fox jumps over the lazy dog and the cat.")
  ? "mots :", joindre(document.mots("L'index des Données, et les termes."), ","), "|", joindre(document.mots("L'index des", vrai), ",")
  ? "clés :", document.cle("Données"), document.cle("Chevaux"), document.cle("Index"), document.cle("Bateaux"), document.cle("Jeux"), document.cle("Flux"), document.cle("Corpus")
  pour chaque p dans document.phrases("Titre court" + nl + "Première phrase. Deuxième phrase, dit M. Martin. Fin" + nl + "suite ici.")
    ? "phrase :", p
  suivant
  locale passages = document.decouper(repliquer("Une phrase assez longue pour remplir un passage. ", 60), {taille = 400, chevauchement = 80})
  ? "passages :", #passages, passages[1].numero, longueur(passages[1].texte) <= 480
  pour chaque k dans document.motscles(m, 3)
    ? "mot-clé :", k.terme, k.nombre
  suivant
  locale c = document.concepts({{texte = m, source = "a"}, {texte = "Le terme et l'index inversé.", source = "b"}}, {max = 5})
  pour chaque x dans c.concepts
    ? "concept :", x.terme, x.cle, x.frequence, joindre(x.sources, "+")
  suivant
  ? "liens :", #c.liens > 0
  pour chaque e dans document.extraits(m, "Que garde un index inversé ?", 1)
    ? "extrait :", e.phrase
  suivant
  locale h = document.html("<html><head><title>T &amp; co</title><script>x()</script></head><body><nav>menu</nav><p>Bonjour &eacute;t&#233; <a href='/a'>lien</a></p></body></html>", "https://exemple.fr/d/")
  ? "html :", h.titre, "|", rogner(h.texte), "|", h.liens[1].url
  ? "entités :", document.entites("&lt;b&gt; &#x41; &nbsp;fin")
  locale pos = document.disposer({"a", "b", "c"}, {{a = "a", b = "b", poids = 1}}, {largeur = 100, hauteur = 100})
  ? "disposer :", pos["a"].x >= 0 et pos["a"].x <= 100, pos["c"] <> nul
retourner
