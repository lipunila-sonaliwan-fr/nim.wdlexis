&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& hl_outils.prg : outils communs (textes, noms, littéraux Lexis+, dessin des
&& formulaires au format du concepteur, blocs marqués des scripts).

fonction Q()
retourner car(34)
finfonction

fonction NL()
retourner car(10)
finfonction

fonction HL_LIGNES(src)
  locale l = decouper(src, car(10))
  si #l = 0
    l = {""}
  finsi
retourner l
finfonction

fonction HL_LIRE(p)
  essayer
    retourner fichier.lire(p)
  capturer e
  finessayer
retourner ""
finfonction

fonction HL_EST_IDENT(s)
  && nom de carte, de modèle ou de contrôle : lettre puis lettres, chiffres ou _
  si s = nul ou #s = 0
    retourner faux
  finsi
  locale lettres = "abcdefghijklmnopqrstuvwxyz"
  locale autres = lettres + "0123456789_"
  locale m = minuscule(s)
  si position(souschaine(m, 1, 1), lettres) = 0
    retourner faux
  finsi
  pour i = 2 a #m
    si position(souschaine(m, i, 1), autres) = 0
      retourner faux
    finsi
  suivant
retourner non contient({"pile", "moteur", "donnees", "principal", "fenetre", "si", "sinon", "pour", "et", "ou", ;
                        "non", "nul", "vrai", "faux", "procedure", "fonction", "retourner", "locale", "globale", ;
                        "dans", "chaque", "suivant", "position", "table", "retour", "debut", "tout", "vide"}, m)
finfonction

fonction HL_CHAINE(s)
  && littéral Lexis+ d'une chaîne
  locale r = remplacertexte(chaine(s), "\\", "\\\\")
  r = remplacertexte(r, Q(), "\\" + Q())
  r = remplacertexte(r, car(13), "")
  r = remplacertexte(r, car(10), "\\n")
  r = remplacertexte(r, car(9), "\\t")
retourner Q() + r + Q()
finfonction

fonction HL_EST_LISTE(t)
retourner #t > 0 et #t = nbelements(t)
finfonction

fonction HL_LITTERAL(v, retrait)
  && littéral Lexis+ d'une valeur (tables : listes et fiches aux clefs simples)
  si retrait = nul
    retrait = ""
  finsi
  locale ty = type(v)
  faire cas
  cas ty = "nul"
    retourner "nul"
  cas ty = "logique"
    retourner sisinon(v, "vrai", "faux")
  cas ty = "nombre"
    retourner chaine(v)
  cas ty = "chaine"
    retourner HL_CHAINE(v)
  cas ty = "table"
    si nbelements(v) = 0
      retourner "{}"
    finsi
    locale parts = {}
    locale simple = vrai
    si HL_EST_LISTE(v)
      pour chaque x dans v
        si type(x) = "table"
          simple = faux
        finsi
        inserer(parts, HL_LITTERAL(x, retrait + "  "))
      suivant
    sinon
      pour chaque k, x dans v
        si type(x) = "table"
          simple = faux
        finsi
        inserer(parts, minuscule(k) + " = " + HL_LITTERAL(x, retrait + "  "))
      suivant
    finsi
    si simple et #joindre(parts, ", ") < 90
      retourner "{" + joindre(parts, ", ") + "}"
    finsi
    retourner "{" + NL() + retrait + "  " + joindre(parts, "," + NL() + retrait + "  ") + NL() + retrait + "}"
  fincas
retourner HL_CHAINE(texte(v))
finfonction

fonction HL_EST_LETTRE_MOT(c)
retourner c <> "" et position(c, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_") > 0
finfonction

fonction HL_REMPLACER_MOT(s, ancien, nouveau)
  && remplace le mot (insensible à la casse, limites de mot)
  locale bas = minuscule(s)
  locale cherche = minuscule(ancien)
  locale r = ""
  locale i = 1
  tantque i <= #s
    locale j = position(cherche, souschaine(bas, i))
    si j = 0
      r = r + souschaine(s, i)
      sortir
    finsi
    j = i + j - 1
    locale k = j + #cherche
    locale avant = (j = 1) ou non HL_EST_LETTRE_MOT(souschaine(s, j - 1, 1))
    locale apres = (k > #s) ou non HL_EST_LETTRE_MOT(souschaine(s, k, 1))
    r = r + souschaine(s, i, j - i)
    si avant et apres
      r = r + nouveau
    sinon
      r = r + souschaine(s, j, #cherche)
    finsi
    i = k
  fintantque
retourner r
finfonction

&&
&& Dessin des formulaires (lignes « &&§ » de form_<nom>.prg, relues par le concepteur)
&&

fonction HL_DESSIN_DE(src)
  && modèle JSON du formulaire (clefs exactes), ou nul
  locale js = {}
  pour chaque l dans HL_LIGNES(src)
    locale s = rognerg(l)
    si commencepar(s, "&&§ ")
      inserer(js, souschaine(s, 5))
    sinonsi rogner(s) = "&&§"
      inserer(js, "")
    finsi
  suivant
  si #js = 0
    retourner nul
  finsi
  essayer
    retourner json.decoder(joindre(js, car(10)), vrai)
  capturer e
  finessayer
retourner nul
finfonction

fonction HL_DESSIN_JSON(d)
  && JSON du modèle (les listes vides restent des tableaux, comme le veut le concepteur)
  locale s = json.encoder(d)
  s = remplacertexte(s, Q() + "events" + Q() + ":{}", Q() + "events" + Q() + ":[]")
  s = remplacertexte(s, Q() + "children" + Q() + ":{}", Q() + "children" + Q() + ":[]")
retourner s
finfonction

fonction HL_DESSIN_TEXTE(d)
  && fichier minimal (dessin seul) : le concepteur le relit et régénère le code
retourner "&& Formulaire « " + d["name"] + " » (HyperLexis) : régénéré par le concepteur." + NL() + ;
          "&&§ " + HL_DESSIN_JSON(d) + NL()
finfonction

fonction HL_NOEUD(genre, nom, props, enfants)
  locale p = props ou {}
  si nbelements(p) = 0
    p = json.decoder("{}", vrai)
  finsi
retourner {["kind"] = genre, ["name"] = nom, ["props"] = p, ["events"] = {}, ["children"] = enfants ou {}}
finfonction

fonction HL_NOEUD_PROPS(props)
  && fiche aux clefs exactes (minuscules) à partir de {"clef", "valeur", ...}
  locale t = json.decoder("{}", vrai)
  pour i = 1 a #props pas 2
    t[props[i]] = chaine(props[i + 1])
  suivant
retourner t
finfonction

procedure HL_NOEUDS_TOUS(n, acc)
  inserer(acc, n)
  si n["children"] <> nul
    pour chaque c dans n["children"]
      HL_NOEUDS_TOUS(c, acc)
    suivant
  finsi
finprocedure

fonction HL_NOEUD_NOMME(racine, nom)
  locale l = {}
  HL_NOEUDS_TOUS(racine, l)
  pour chaque n dans l
    si minuscule(n["name"]) = minuscule(nom)
      retourner n
    finsi
  suivant
retourner nul
finfonction

fonction HL_PARENT_DE(racine, cible)
  si racine["children"] = nul
    retourner nul
  finsi
  pour chaque c dans racine["children"]
    si c = cible
      retourner racine
    finsi
    locale p = HL_PARENT_DE(c, cible)
    si p <> nul
      retourner p
    finsi
  suivant
retourner nul
finfonction

&&
&& Scripts : blocs marqués (même format que le concepteur de wdlexis+)
&&

fonction HL_PROC_OUVRIR(nom)
retourner "FORM" + majuscule(nom) + "_OUVRIR"
finfonction

fonction HL_VAR_FORMULAIRE(nom)
retourner "form" + minuscule(nom)
finfonction

fonction HL_MARQUE_DEBUT(nom)
retourner "&& ---- formulaire « " + nom + " » : début (généré par le concepteur, gardez ces marques) ----"
finfonction

fonction HL_MARQUE_FIN(nom)
retourner "&& ---- formulaire « " + nom + " » : fin ----"
finfonction

fonction HL_BLOC(l, nom)
  locale r = {debut = 0, fin = 0}
  pour i = 1 a #l
    si l[i] = HL_MARQUE_DEBUT(nom)
      r.debut = i
    sinonsi l[i] = HL_MARQUE_FIN(nom) et r.debut > 0
      r.fin = i
      retourner r
    finsi
  suivant
retourner r
finfonction

fonction HL_ASSURER_BLOC(src, nom)
  locale l = HL_LIGNES(src)
  si HL_BLOC(l, nom).fin > 0
    retourner src
  finsi
  tantque #l > 0 et rogner(l[#l]) = ""
    retirer(l)
  fintantque
  si #l > 0
    inserer(l, "")
  finsi
  inserer(l, HL_MARQUE_DEBUT(nom))
  inserer(l, "&& " + HL_PROC_OUVRIR(nom) + "() ouvre le formulaire ; ses contrôles sont dans " + ;
             HL_VAR_FORMULAIRE(nom) + " (" + HL_VAR_FORMULAIRE(nom) + ".fenetre…).")
  inserer(l, "")
  inserer(l, HL_MARQUE_FIN(nom))
  inserer(l, "")
retourner joindre(l, car(10))
finfonction

fonction HL_INSERER_PROCEDURE(src, nom, h, evenement, noeud, corps)
  && procédure à la fin du bloc ; renvoie {texte, ligne} (ligne à compléter)
  locale l = HL_LIGNES(HL_ASSURER_BLOC(src, nom))
  locale f = HL_BLOC(l, nom).fin
  locale ajout = {"procedure " + h + "(ev)", "  && " + evenement + " de " + noeud + " (modèle « " + nom + " »)"}
  si corps <> nul et #corps > 0
    pour chaque c dans corps
      inserer(ajout, "  " + c)
    suivant
  sinon
    inserer(ajout, "  ")
  finsi
  inserer(ajout, "finprocedure")
  inserer(ajout, "")
  pour k = #ajout a 1 pas -1
    inserer(l, ajout[k], f)
  suivant
retourner {texte = joindre(l, car(10)), ligne = f + #ajout - 3}
finfonction

fonction HL_ENTETE_PROCEDURE(ligne)
  && {nom, parametres} pour « procedure NOM(a) » / « fonction NOM(a, b) », sinon nul
  locale s = rogner(ligne)
  locale reste = ""
  faire cas
  cas commencepar(minuscule(s), "procedure ")
    reste = rogner(souschaine(s, 11))
  cas commencepar(minuscule(s), "fonction ")
    reste = rogner(souschaine(s, 10))
  autrement
    retourner nul
  fincas
  locale o = position("(", reste)
  locale f = position(")", reste)
  si o = 0
    retourner {nom = rogner(reste), parametres = 0}
  finsi
  locale n = 0
  si f > o + 1 et rogner(souschaine(reste, o + 1, f - o - 1)) <> ""
    n = #decouper(souschaine(reste, o + 1, f - o - 1), ",")
  finsi
retourner {nom = rogner(gauche(reste, o - 1)), parametres = n}
finfonction

fonction HL_PROCEDURES_DE(src, unparametre)
  locale l = {}
  pour chaque ligne dans HL_LIGNES(src)
    locale h = HL_ENTETE_PROCEDURE(ligne)
    si h <> nul et h.nom <> "" et (non unparametre ou h.parametres = 1)
      inserer(l, h.nom)
    finsi
  suivant
retourner l
finfonction

fonction HL_LIGNE_PROCEDURE(src, nom)
  locale l = HL_LIGNES(src)
  pour i = 1 a #l
    locale h = HL_ENTETE_PROCEDURE(l[i])
    si h <> nul et majuscule(h.nom) = majuscule(nom)
      retourner i
    finsi
  suivant
retourner 0
finfonction

fonction HL_RENOMMER_CABLAGE(src, ancien, nouveau)
  locale r = remplacertexte(src, HL_MARQUE_DEBUT(ancien), HL_MARQUE_DEBUT(nouveau))
  r = remplacertexte(r, HL_MARQUE_FIN(ancien), HL_MARQUE_FIN(nouveau))
  r = HL_REMPLACER_MOT(r, HL_PROC_OUVRIR(ancien), HL_PROC_OUVRIR(nouveau))
retourner HL_REMPLACER_MOT(r, HL_VAR_FORMULAIRE(ancien), HL_VAR_FORMULAIRE(nouveau))
finfonction
