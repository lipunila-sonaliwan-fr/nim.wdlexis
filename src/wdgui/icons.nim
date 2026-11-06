# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# Icônes vectorielles (boutons à symbole, arbres) : dessinées avec les primitives de Drawing,
# indépendantes de la police. Grille de 16 × 16 unités mise à l'échelle du rectangle cible.
import std/[strutils, math]
import drawing, colors_themes

const IconNames* = ["ouvrir", "dossier", "nouveau", "enregistrer", "verifier", "executer", "deboguer",
  "continuer", "pasapas", "pasprincipal", "sortir", "pause", "arreter", "panneau", "panneaubas",
  "fenetre", "rattacher", "masquer", "afficher", "copier", "effacer", "envoyer", "dupliquer",
  "renommer", "supprimer", "cadenas", "code", "formulaire", "etat", "image", "markdown", "texte",
  "sql", "pdf", "fichier", "plus", "moins", "ajuster", "precedent", "suivant", "premier", "dernier",
  "rechercher", "imprimer", "rotation", "miniatures", "apercu", "blueprint", "concepteur",
  "palette", "hierarchie", "actualiser", "fermer", "menu", "zoomplus", "zoommoins", "pleinepage",
  "monter", "descendre", "cabler", "personnalise", "selection", "variables", "pile", "console", "problemes"]

proc isIcon*(name: string): bool = name.toLowerAscii in IconNames

proc drawIcon*(d: Drawing, name: string, r: Rect, c: Color, ep = 1.6) =
  ## Dessine l'icône `name` centrée dans `r` (carré inscrit).
  let s = min(r.w, r.h) / 16.0
  let ox = r.x + (r.w - 16 * s) / 2
  let oy = r.y + (r.h - 16 * s) / 2
  let w = max(1.0, ep * s * 0.9)
  proc X(v: float): float = ox + v * s
  proc Y(v: float): float = oy + v * s
  proc R(x, y, ww, hh: float): Rect = rect(X(x), Y(y), ww * s, hh * s)
  proc L(x1, y1, x2, y2: float) = d.line(X(x1), Y(y1), X(x2), Y(y2), c, w)
  proc P(pts: openArray[(float, float)]) =
    var q: seq[Point]
    for (a, b) in pts: q.add (x: X(a), y: Y(b))
    d.fillPolygon(q, c)
  proc arc(cx, cy, rx, ry, a0, a1: float) =
    # arc d'ellipse de a0 à a1 (degrés, 0 = droite, sens horaire à l'écran)
    let n = 14
    for i in 0 ..< n:
      let t0 = degToRad(a0 + (a1 - a0) * float(i) / float(n))
      let t1 = degToRad(a0 + (a1 - a0) * float(i + 1) / float(n))
      L(cx + rx * cos(t0), cy + ry * sin(t0), cx + rx * cos(t1), cy + ry * sin(t1))
  proc arrowR(x, y: float) = P([(x - 3.0, y - 3.0), (x + 1.0, y), (x - 3.0, y + 3.0)])
  proc arrowD(x, y: float) = P([(x - 3.0, y - 3.0), (x + 3.0, y - 3.0), (x, y + 1.0)])
  proc sheet() =
    d.strokeRoundRect(R(3, 1.5, 10, 13), 1.2 * s, c, w)
  case name.toLowerAscii
  of "ouvrir", "dossier":
    d.strokeRoundRect(R(1.5, 4, 13, 9.5), 1.2 * s, c, w)
    P([(1.5, 5.0), (1.5, 2.5), (6.0, 2.5), (7.5, 4.0)])
    if name.toLowerAscii == "ouvrir": L(4, 8.5, 12, 8.5)
  of "fichier": sheet()
  of "nouveau":
    sheet(); L(8, 5, 8, 11); L(5, 8, 11, 8)
  of "plus", "zoomplus":
    if name.toLowerAscii == "zoomplus":
      d.strokeCircle(X(7), Y(7), 4.8 * s, c, w); L(10.5, 10.5, 14.5, 14.5); L(7, 4.8, 7, 9.2); L(4.8, 7, 9.2, 7)
    else: L(8, 3, 8, 13); L(3, 8, 13, 8)
  of "moins", "zoommoins":
    if name.toLowerAscii == "zoommoins":
      d.strokeCircle(X(7), Y(7), 4.8 * s, c, w); L(10.5, 10.5, 14.5, 14.5); L(4.8, 7, 9.2, 7)
    else: L(3, 8, 13, 8)
  of "enregistrer":
    d.strokeRoundRect(R(2, 2, 12, 12), 1.5 * s, c, w)
    d.fillRect(R(5, 2, 6, 4), c)
    d.strokeRoundRect(R(4.5, 9, 7, 5), 0.5 * s, c, w)
  of "verifier":
    L(2.5, 8.5, 6.5, 12.5); L(6.5, 12.5, 13.5, 3.5)
  of "executer", "continuer":
    P([(4.0, 2.5), (13.5, 8.0), (4.0, 13.5)])
    if name.toLowerAscii == "continuer": d.fillRect(R(1.5, 2.5, 1.8, 11), c)
  of "deboguer":
    d.strokeEllipse(R(4.5, 5, 7, 9.5), c, w)
    L(8, 6, 8, 14); L(4.5, 9, 1.5, 8); L(11.5, 9, 14.5, 8); L(4.8, 12, 2, 14); L(11.2, 12, 14, 14)
    L(5.5, 5.5, 4, 2.5); L(10.5, 5.5, 12, 2.5)
  of "pasapas":
    # entrer dans la procédure : flèche qui descend vers l'instruction (point)
    L(2, 3, 9, 3); L(9, 3, 9, 8); P([(5.5, 7.5), (12.5, 7.5), (9.0, 11.5)]); d.fillCircle(X(9), Y(14), 1.7 * s, c)
  of "pasprincipal":
    # passer par-dessus : arc au-dessus de l'instruction (point)
    arc(8, 9, 5.5, 5.5, 185, 320)
    P([(11.0, 4.0), (15.0, 6.5), (11.5, 9.5)])
    d.fillCircle(X(8), Y(13.5), 1.7 * s, c)
  of "sortir":
    # sortir de la procédure : flèche qui remonte depuis l'instruction (point)
    d.fillCircle(X(3), Y(13), 1.7 * s, c); L(5.5, 13, 10, 13); L(10, 13, 10, 6); P([(6.5, 6.5), (13.5, 6.5), (10.0, 2.0)])
  of "pause":
    d.fillRoundRect(R(3.5, 2.5, 3.2, 11), 0.8 * s, c); d.fillRoundRect(R(9.3, 2.5, 3.2, 11), 0.8 * s, c)
  of "arreter":
    d.fillRoundRect(R(3, 3, 10, 10), 1.4 * s, c)
  of "panneau":
    d.strokeRoundRect(R(1.5, 2.5, 13, 11), 1.2 * s, c, w); d.fillRect(R(1.5, 2.5, 4.5, 11), c)
  of "panneaubas":
    d.strokeRoundRect(R(1.5, 2.5, 13, 11), 1.2 * s, c, w); d.fillRect(R(1.5, 9.5, 13, 4), c)
  of "fenetre":
    d.strokeRoundRect(R(4.5, 1.5, 10, 9), 1 * s, c, w); d.fillRect(R(4.5, 1.5, 10, 2.5), c)
    d.strokeRoundRect(R(1.5, 6, 8.5, 8.5), 1 * s, c, w)
  of "rattacher":
    d.strokeRoundRect(R(1.5, 2.5, 13, 11), 1.2 * s, c, w)
    L(14, 3, 8, 9); P([(6.5, 6.0), (6.5, 10.5), (11.0, 10.5)])
  of "masquer":
    P([(9.0, 3.0), (4.0, 8.0), (9.0, 13.0)]); P([(14.0, 3.0), (9.0, 8.0), (14.0, 13.0)])
  of "afficher":
    P([(2.0, 3.0), (7.0, 8.0), (2.0, 13.0)]); P([(7.0, 3.0), (12.0, 8.0), (7.0, 13.0)])
  of "precedent": P([(11.0, 2.5), (4.5, 8.0), (11.0, 13.5)])
  of "suivant": P([(5.0, 2.5), (11.5, 8.0), (5.0, 13.5)])
  of "premier": P([(13.0, 2.5), (6.5, 8.0), (13.0, 13.5)]); d.fillRect(R(3, 2.5, 2, 11), c)
  of "dernier": P([(3.0, 2.5), (9.5, 8.0), (3.0, 13.5)]); d.fillRect(R(11, 2.5, 2, 11), c)
  of "copier", "dupliquer":
    d.strokeRoundRect(R(5, 5, 9, 9.5), 1.2 * s, c, w)
    L(2, 11, 2, 2.5); L(2, 2, 10.5, 2)
    if name.toLowerAscii == "dupliquer": L(9.5, 7.5, 9.5, 12); L(7.3, 9.75, 11.7, 9.75)
  of "effacer":
    P([(2.0, 10.0), (8.5, 3.5), (13.5, 8.5), (8.0, 14.0)]); L(5, 14.5, 14.5, 14.5)
  of "envoyer":
    P([(1.5, 2.0), (14.5, 8.0), (1.5, 14.0), (3.5, 8.0)])
  of "renommer":
    d.strokeRoundRect(R(1.5, 4.5, 13, 7), 1 * s, c, w)
    L(5, 2, 5, 14); L(3.5, 2, 6.5, 2); L(3.5, 14, 6.5, 14)
  of "supprimer":
    L(2, 4, 14, 4); L(6, 4, 6.5, 1.8); L(6.5, 1.8, 9.5, 1.8); L(9.5, 1.8, 10, 4)
    d.strokeRoundRect(R(3.5, 4, 9, 10.5), 1.2 * s, c, w); L(6.5, 7, 6.5, 12); L(9.5, 7, 9.5, 12)
  of "cadenas":
    d.fillRoundRect(R(3, 7, 10, 8), 1.4 * s, c)
    d.strokeRoundRect(R(5, 1.8, 6, 9), 3 * s, c, w)
  of "code":
    L(5, 4, 1.5, 8); L(1.5, 8, 5, 12); L(11, 4, 14.5, 8); L(14.5, 8, 11, 12); L(9.5, 2.5, 6.5, 13.5)
  of "formulaire", "concepteur":
    d.strokeRoundRect(R(1.5, 2, 13, 12), 1.2 * s, c, w); d.fillRect(R(1.5, 2, 13, 3), c)
    d.strokeRect(R(4, 7.5, 8, 2.2), c, w * 0.8); d.fillRoundRect(R(8, 11, 4, 1.8), 0.5 * s, c)
  of "etat", "imprimer":
    sheet(); L(5.5, 5, 10.5, 5); L(5.5, 8, 10.5, 8); L(5.5, 11, 8.5, 11)
  of "image", "apercu":
    d.strokeRoundRect(R(1.5, 2.5, 13, 11), 1.2 * s, c, w)
    P([(3.0, 12.0), (7.0, 7.0), (10.0, 10.5), (11.5, 9.0), (13.0, 12.0)]); d.fillCircle(X(11), Y(5.5), 1.4 * s, c)
  of "markdown":
    d.strokeRoundRect(R(0.8, 3.5, 14.4, 9), 1.4 * s, c, w)
    L(3, 10.5, 3, 5.5); L(3, 5.5, 5, 8); L(5, 8, 7, 5.5); L(7, 5.5, 7, 10.5)
    L(11, 5.5, 11, 10); P([(9.0, 8.5), (13.0, 8.5), (11.0, 11.0)])
  of "texte":
    sheet(); L(5.5, 5, 10.5, 5); L(5.5, 7.5, 10.5, 7.5); L(5.5, 10, 10.5, 10); L(5.5, 12.5, 9, 12.5)
  of "sql":
    d.strokeEllipse(R(2.5, 1.5, 11, 4), c, w)
    L(2.5, 3.5, 2.5, 12.5); L(13.5, 3.5, 13.5, 12.5)
    arc(8, 12.5, 5.5, 2, 0, 180); arc(8, 8, 5.5, 2, 0, 180)
  of "pdf":
    sheet(); d.fillRoundRect(R(1, 8.5, 14, 5), 1 * s, c)
  of "ajuster", "pleinepage":
    L(1.5, 5, 1.5, 1.5); L(1.5, 1.5, 5, 1.5); L(11, 1.5, 14.5, 1.5); L(14.5, 1.5, 14.5, 5)
    L(14.5, 11, 14.5, 14.5); L(14.5, 14.5, 11, 14.5); L(5, 14.5, 1.5, 14.5); L(1.5, 14.5, 1.5, 11)
  of "rechercher":
    d.strokeCircle(X(6.5), Y(6.5), 4.6 * s, c, w); L(10, 10, 14.5, 14.5)
  of "rotation":
    arc(8, 8.5, 5.5, 5.5, -60, 230); P([(9.0, 0.8), (13.0, 3.0), (9.0, 5.5)])
  of "miniatures":
    d.fillRoundRect(R(2, 2, 5, 5), 0.8 * s, c); d.fillRoundRect(R(9, 2, 5, 5), 0.8 * s, c)
    d.fillRoundRect(R(2, 9, 5, 5), 0.8 * s, c); d.fillRoundRect(R(9, 9, 5, 5), 0.8 * s, c)
  of "blueprint":
    d.strokeRoundRect(R(1, 2, 6, 5), 1 * s, c, w); d.strokeRoundRect(R(9, 9, 6, 5), 1 * s, c, w)
    L(7, 4.5, 10, 4.5); L(10, 4.5, 10, 9)
  of "palette":
    d.fillRoundRect(R(1.5, 1.5, 5.5, 5.5), 1 * s, c); d.strokeRoundRect(R(9, 1.5, 5.5, 5.5), 1 * s, c, w)
    d.strokeRoundRect(R(1.5, 9, 5.5, 5.5), 1 * s, c, w); d.fillRoundRect(R(9, 9, 5.5, 5.5), 1 * s, c)
  of "hierarchie":
    d.fillRect(R(1.5, 1.5, 5, 3.5), c); L(4, 5, 4, 12.5); L(4, 8.5, 8, 8.5); L(4, 12.5, 8, 12.5)
    d.fillRect(R(8.5, 7, 6, 3), c); d.fillRect(R(8.5, 11, 6, 3), c)
  of "actualiser":
    arc(8, 8, 5.5, 5.5, -50, 250); P([(10.0, 0.5), (14.0, 3.0), (10.0, 5.5)])
  of "monter":
    L(8, 14, 8, 4); P([(3.5, 6.5), (8.0, 1.5), (12.5, 6.5)])
  of "descendre":
    L(8, 2, 8, 12); P([(3.5, 9.5), (8.0, 14.5), (12.5, 9.5)])
  of "cabler":
    d.strokeRoundRect(R(1, 5.5, 7, 5), 2.5 * s, c, w); d.strokeRoundRect(R(8, 5.5, 7, 5), 2.5 * s, c, w)
    L(5, 8, 11, 8)
  of "personnalise":
    d.strokeRoundRect(R(1.5, 1.5, 9, 9), 1.2 * s, c, w); L(12.5, 8.5, 12.5, 14.5); L(9.5, 11.5, 15.5, 11.5)
  of "selection":
    P([(3.0, 1.5), (13.0, 9.0), (8.5, 9.5), (11.0, 14.5), (9.0, 15.0), (6.8, 10.5), (3.0, 13.5)])
  of "variables":
    L(2, 3, 2, 13); L(2, 3, 4, 3); L(2, 13, 4, 13); L(14, 3, 14, 13); L(14, 3, 12, 3); L(14, 13, 12, 13)
    L(5.5, 5.5, 10.5, 10.5); L(10.5, 5.5, 5.5, 10.5)
  of "pile":
    d.strokeRoundRect(R(2, 2, 12, 3.5), 1 * s, c, w); d.strokeRoundRect(R(2, 6.3, 12, 3.5), 1 * s, c, w)
    d.fillRoundRect(R(2, 10.6, 12, 3.5), 1 * s, c)
  of "console":
    d.strokeRoundRect(R(1, 2, 14, 12), 1.5 * s, c, w); L(4, 6, 7, 8.5); L(7, 8.5, 4, 11); L(8.5, 11, 12, 11)
  of "problemes":
    P([(8.0, 1.5), (15.0, 14.0), (1.0, 14.0)])
  of "fermer":
    L(3.5, 3.5, 12.5, 12.5); L(12.5, 3.5, 3.5, 12.5)
  of "menu":
    L(2, 4, 14, 4); L(2, 8, 14, 8); L(2, 12, 14, 12)
  else:
    d.strokeRoundRect(R(2, 2, 12, 12), 2 * s, c, w)
