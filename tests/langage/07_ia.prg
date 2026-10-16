&& Paquets d'IA sans modèle : tenseurs, tokeniseur, dessin, audio, quantification.
procedure TEST
  && gradients
  locale x = tenseur.depuis({1, -2, 3}, {3}, vrai)
  locale f = tenseur.somme(x * x + x * 2)
  f:retropropager()
  ? "f", f:valeur(), "grad", joindre(x:gradient(), " "), "forme", joindre(x:forme(), "x")
  locale a = tenseur.depuis({1, 2, 3, 4}, {2, 2})
  locale b = tenseur.depuis({5, 6, 7, 8}, {2, 2})
  ? "produit", joindre(tenseur.produit(a, b):donnees(), " "), "somme", tenseur.somme(a - b):valeur()
  ? "softmax", chaine(tenseur.softmax(tenseur.depuis({0, 0}, {1, 2})):valeur(1), 0, 2)
  essayer
    tenseur.lineaire(a, tenseur.depuis({1, 2, 3}, {1, 3}))
  capturer e
    ? "erreur", e
  finessayer
  && régression : y = 2x - 1
  tenseur.graine(1)
  locale lx = tenseur.depuis({0, 1, 2, 3}, {4, 1})
  locale ly = tenseur.depuis({-1, 1, 3, 5}, {4, 1})
  locale w = tenseur.parametre({1, 1}, 0.1, "w")
  locale c = tenseur.plein({1}, 0, vrai, "c")
  locale opt = tenseur.sgd({w, c}, {lr = 0.05, moment = 0.9})
  locale perte
  pour i = 1 a 300
    opt:zerograd()
    perte = tenseur.mse(tenseur.lineaire(lx, w, c), ly)
    perte:retropropager()
    opt:etape()
  suivant
  ? "regression", chaine(w:valeur(), 0, 2), chaine(c:valeur(), 0, 2), opt.pas
  && tokeniseur
  locale tok = entrainement.tokeniseur(repliquer("le chat dort. le chien dort. ", 30), {taille = 300})
  locale ids = tok:encoder("le chat dort.")
  ? "tokeniseur", tok.taille, #ids, tok:decoder(ids), tok:id("<|bos|>") = tok.bos
  && dessin
  locale t = dessin.toile(10, 10, "white", 1)
  t:rectangle(0, 0, 5, 10, "#ff0000")
  locale img = t:terminer()
  locale p = img:pixel(1, 1)
  ? "dessin", img.largeur, p.r, p.g, p.b, img:pixel(8, 8).g
  locale s = dessin.svg("<svg viewBox='0 0 4 4'><rect width='4' height='4' fill='blue'/></svg>", 8)
  ? "svg", s.largeur, s.hauteur, s:pixel(4, 4).b
  && audio
  locale son = audio.melodie("A4:1 R:1", 60, 8000)
  ? "audio", son.frequence, arrondi(son.duree, 2), audio.frequencenote("A4"), audio.enlettres(21)
  && quantification
  locale v = {}
  pour i = 1 a 32
    inserer i / 8 dans v
  suivant
  locale q = gguf.quantifier("q8_0", v)
  ? "gguf", q.octets, q.erreur < 0.02, gguf.bitsparpoids("q4_k")
  && réglages d'échantillonnage
  locale e = llm.echantillonnage({temperature = 0.2})
  ? "echantillonnage", e.temperature, e.topk, llm.glouton().temperature
retourner
