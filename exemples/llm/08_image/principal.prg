&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Exemple LLM 08 — Recevoir la réponse sous forme d'image.
&&
&&   wdlexisrt exemples/llm/08_image/principal.prg modele.gguf
&&
&& Un LLM textuel ne produit pas de pixels : on lui fait écrire du **SVG**
&& (dessin vectoriel en texte), que le paquet rastérise en BMP. On obtient deux
&& fichiers : .svg (vectoriel, ouvrable dans un navigateur) et .bmp.

locale chemin = systeme.args[1] ou systeme.env("NIMLLM_MODEL") ou "models/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
locale modele = llm.charger(chemin)
locale conv = modele:conversation({maxtokens = 1500})
conv.tailleimage = 512           && largeur de l'image produite (pixels).

&& 1. Demande d'image.
locale r = conv:demander("Dessine une maison avec un toit rouge, un soleil et un arbre.",
                         {format = "image", sortie = "maison.svg"})
? "Fichiers créés :", joindre(r.fichiers, ", ")          && maison.svg, maison.bmp

&& 2. Un graphique à partir de données.
conv:reinitialiser()
locale r2 = conv:demander("Fais un diagramme en barres (SVG) des ventes : janvier 120, " +
                          "février 95, mars 150. Ajoute un axe horizontal.",
                          {format = "image", sortie = "ventes.svg"})
? "Graphique :", joindre(r2.fichiers, ", ")

&& 3. Rendu SVG sans LLM : le moteur est utilisable directement (paquet dessin).
locale svg = [[<svg viewBox="0 0 200 120" xmlns="http://www.w3.org/2000/svg">
  <rect width="200" height="120" fill="#f5f0e6"/>
  <path d="M10 100 C 60 10, 140 10, 190 100" fill="none" stroke="crimson" stroke-width="4"/>
  <circle cx="100" cy="35" r="12" fill="orange" stroke="black"/>
  <g transform="translate(20,20) rotate(15)"><rect width="30" height="20" fill="teal" rx="4"/></g>
</svg>]]
locale courbe = dessin.svg(svg, 400)
courbe:enregistrerbmp("courbe.bmp")

&& 4. Dessiner soi-même sur une toile.
locale t = dessin.toile(300, 200, {255, 255, 255})
t:rectangle(0, 150, 300, 50, {80, 160, 60})                          && herbe.
t:cercle(240, 50, 30, {255, 200, 0})                                 && soleil.
t:polygone({{60, 150}, {110, 90}, {160, 150}}, {180, 40, 40})        && toit.
t:ligne(10, 10, 290, 10, 3, {0, 0, 0, 0.5})                          && trait semi-transparent.
locale image = t:terminer()
image:enregistrerbmp("dessin.bmp")
image:enregistrerppm("dessin.ppm")
locale px = image:pixel(240, 50)
? "Pixel (240, 50) =", px.r, px.g, px.b
