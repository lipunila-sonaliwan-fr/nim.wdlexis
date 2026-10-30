&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ : référence des fonctions intégrées et des paquets.
&& Les fiches sont du Markdown affiché par ui.markdown.

procedure CHARGER_REFERENCE
  && entrées lues une fois, triées par paquet puis par signature (sans tenir
  && compte des accents ni de la casse), comme l'atelier natif
  globale docs, docsparnom, refentrees
  docs = {}
  docsparnom = {}
  locale toutes = lexis.documentation()
  locale cles = {}
  pour i = 1 a #toutes
    locale d = toutes[i]
    d.recherche = CLE_TRI(d.paquet + " " + d.nom + " " + d.signature + " " + d.description)
    docs[d.paquet + ui.sep + d.signature] = d
    si non d.methode
      docsparnom[majuscule(d.nom)] = d
      docsparnom[majuscule(decouper(d.signature, "(")[1])] = d
    finsi
    inserer(cles, CLE_TRI(d.paquet) + car(1) + CLE_TRI(d.signature) + car(1) + i)
  suivant
  trier(cles)                    && tri natif des clés, bien plus rapide qu'une comparaison en Lexis+
  refentrees = {}
  pour chaque c dans cles
    locale morceaux = decouper(c, car(1))
    inserer(refentrees, toutes[nombre(morceaux[#morceaux])])
  suivant
  ARBRE_REFERENCE()
retourner

fonction CLE_TRI(s)
  && clé de tri et de recherche : minuscules, sans accents
  locale r = minuscule(s)
  pour chaque p dans {{"é", "e"}, {"è", "e"}, {"ê", "e"}, {"ë", "e"}, {"à", "a"}, {"â", "a"}, {"ä", "a"}, ;
                      {"ù", "u"}, {"û", "u"}, {"ü", "u"}, {"ô", "o"}, {"ö", "o"}, {"î", "i"}, {"ï", "i"}, ;
                      {"ç", "c"}, {"œ", "oe"}}
    r = remplacertexte(r, p[1], p[2])
  suivant
retourner r

procedure ARBRE_REFERENCE
  && arbre filtré par la recherche : tous les mots, dans le paquet, le nom,
  && la signature ou la description ; les paquets trouvés sont dépliés
  si outils = nul
    retourner
  finsi
  locale mots = {}
  pour chaque m dans decouper(CLE_TRI(rechref.valeur), " ")
    si m <> ""
      inserer(mots, m)
    finsi
  suivant
  aref:vider()
  locale paquets = {}, n = 0
  pour chaque d dans refentrees
    locale garder = vrai
    pour chaque m dans mots
      si non (m $ d.recherche)
        garder = faux
        sortir
      finsi
    suivant
    si garder
      aref:ajouter(d.paquet, d.signature)
      n += 1
      si #paquets = 0 ou paquets[#paquets] <> d.paquet
        inserer(paquets, d.paquet)
      finsi
    finsi
  suivant
  si #mots > 0
    pour chaque p dans paquets
      aref:deplier(p)
    suivant
    etat.libelle = "Référence : " + n + " résultat(s) dans " + #paquets + " paquet(s)"
    si n = 0
      fiche.valeur = "### Référence" + car(10) + car(10) + "Aucun résultat pour « " + rogner(rechref.valeur) + " »."
    finsi
  finsi
retourner

procedure FILTRER_REFERENCE(ev)
  ARBRE_REFERENCE()
retourner

fonction BIENVENUE_REFERENCE()
  locale md = {"### Référence", "", ;
               "Sélectionnez un **paquet** ou une **fonction** dans l'arbre ci-dessus pour afficher sa fiche.", "", ;
               "- Le champ de recherche filtre l'arbre (nom, paquet ou mots de la description).", ;
               "- Double-clic sur une fonction : insérer l'appel dans l'éditeur, ou un nœud dans la vue blueprint."}
retourner joindre(md, car(10))

procedure REFERENCE(ev)
  && ev.chemin n'existe que pour les nœuds imbriqués : on découpe ev.texte
  si ev.texte = nul ou ev.texte = ""
    retourner
  finsi
  locale parts = decouper(ev.texte, ui.sep)
  si #parts = 1
    fiche.valeur = FICHE_PAQUET(parts[1])
  sinon
    locale d = docs[parts[1] + ui.sep + parts[2]]
    si d <> nul
      fiche.valeur = FICHE(d)
    finsi
  finsi
retourner

procedure INSERER_REFERENCE(ev)
  locale parts = decouper(aref.valeur, ui.sep)
  si #parts < 2
    retourner
  finsi
  locale d = docs[parts[1] + ui.sep + parts[2]]
  si d = nul
    retourner
  finsi
  si vb:actif()
    vb:inserer(d.signature)         && vue blueprint : nouveau nœud au centre de la vue
  sinon
    ed:inserer(MODELE_APPEL(d.signature))
    ed:focus()
  finsi
retourner

fonction MODELE_APPEL(sig)
  && « es.lire([format]) » -> « es.lire() » ; « f{a=} » -> « f{} »
  locale p = position("(", sig)
  locale q = position("{", sig)
  si p > 0 et (q = 0 ou p < q)
    retourner gauche(sig, p) + ")"
  finsi
  si q > 0
    retourner gauche(sig, q) + "}"
  finsi
retourner sig

&&
&& Fiches Markdown
&&

fonction MDCODE(s)
retourner "`" + s + "`"

fonction MDECHAPPER(s)
  locale r = s
  pour chaque c dans {"\\", "*", "_", "[", "]", "`"}
    r = remplacertexte(r, c, "\\" + c)
  suivant
retourner r

fonction MDTEXTE(s)
  && les chaînes entre guillemets deviennent du code, le reste est échappé
  locale parts = decouper(s, car(34))
  locale r = ""
  pour i = 1 a #parts
    si i % 2 = 0 et i < #parts
      r = r + MDCODE(car(34) + parts[i] + car(34))
    sinon
      si i % 2 = 0
        r = r + car(34)
      finsi
      r = r + MDECHAPPER(parts[i])
    finsi
  suivant
retourner r

fonction ARGUMENTS_TOP(s)
  && découpe sur les virgules hors parenthèses, accolades, crochets et chaînes
  locale l = {}, cur = "", prof = 0, chaine_ouverte = faux
  pour i = 1 a #s
    locale c = souschaine(s, i, 1)
    si chaine_ouverte
      si c = car(34)
        chaine_ouverte = faux
      finsi
    sinonsi c = car(34)
      chaine_ouverte = vrai
    sinonsi c $ "({["
      prof += 1
    sinonsi c $ ")}]"
      prof -= 1
    sinonsi c = "," et prof = 0
      inserer(l, rogner(cur))
      cur = ""
      boucler
    finsi
    cur = cur + c
  suivant
  si rogner(cur) <> ""
    inserer(l, rogner(cur))
  finsi
retourner l

fonction OPTION_MD(o)
  locale p = position("=", o)
  si p = 0
    retourner "  - " + MDCODE(rogner(o))
  finsi
  locale k = rogner(gauche(o, p - 1))
  locale v = rogner(souschaine(o, p + 1))
retourner "  - " + MDCODE(k) + sisinon(v = "", "", " - défaut " + MDCODE(v))

fonction PARAMETRES(sig)
  locale l = {}
  locale p = position("(", sig)
  locale q = position("{", sig)
  locale nommees = q > 0 et (p = 0 ou q < p)
  si nommees
    p = q
  finsi
  si p = 0
    retourner l
  finsi
  locale corps = souschaine(sig, p + 1, #sig - p - 1)
  si nommees
    inserer(l, "- **Options nommées** (table `{...}`) :")
    pour chaque o dans ARGUMENTS_TOP(corps)
      inserer(l, OPTION_MD(o))
    suivant
    retourner l
  finsi
  pour chaque a dans ARGUMENTS_TOP(corps)
    locale facultatif = commencepar(a, "[") et finitpar(a, "]")
    si facultatif
      a = rogner(souschaine(a, 2, #a - 2))
    finsi
    faire cas
    cas a = "..."
      inserer(l, "- " + MDCODE("...") + " - nombre variable de valeurs")
    cas commencepar(a, "{") et finitpar(a, "}")
      inserer(l, "- **Options** (table `{...}`" + sisinon(facultatif, ", facultative", "") + ") :")
      pour chaque o dans ARGUMENTS_TOP(souschaine(a, 2, #a - 2))
        inserer(l, OPTION_MD(o))
      suivant
    cas commencepar(a, "@")
      inserer(l, "- " + MDCODE(a) + " - procédure passée par référence (`@NOM`)")
    autrement
      inserer(l, "- " + MDCODE(a) + sisinon(facultatif, " - *facultatif*", ""))
    fincas
  suivant
retourner l

fonction DISPONIBILITE(paquet)
  si paquet = "base"
    retourner "fonction intégrée, toujours disponible."
  finsi
  si paquet = "es" ou paquet = "systeme"
    retourner "paquet " + MDCODE(paquet) + ", toujours disponible."
  finsi
retourner "paquet " + MDCODE(paquet) + " : " + MDCODE(paquet + ".fonction(...)") + " ou " + ;
          MDCODE("x = paquet(" + car(34) + paquet + car(34) + ")") + "."

fonction FICHE(d)
  locale md = {}
  locale appelable = position("(", d.signature) > 0 ou position("{", d.signature) > 0
  locale titre = rogner(decouper(decouper(d.signature, "(")[1], "{")[1])
  inserer(md, "# " + MDECHAPPER(titre))
  inserer(md, "")
  faire cas
  cas d.methode
    inserer(md, "**Méthode** de l'objet " + MDCODE(d.proprietaire) + " · paquet " + MDCODE(d.paquet))
  cas d.proprietaire <> ""
    inserer(md, sisinon(appelable, "**Fonction** du paquet ", "**Valeur** du paquet ") + MDCODE(d.proprietaire))
  autrement
    inserer(md, "**Fonction intégrée**")
  fincas
  inserer(md, "")
  inserer(md, "```")
  inserer(md, d.signature)
  inserer(md, "```")
  inserer(md, "")
  locale params = PARAMETRES(d.signature)
  si #params > 0
    inserer(md, "## Paramètres")
    pour chaque l dans params
      inserer(md, l)
    suivant
    inserer(md, "")
  finsi
  inserer(md, "## Description")
  inserer(md, MDTEXTE(d.description))
  inserer(md, "")
  inserer(md, "---")
  inserer(md, "> **Disponibilité** : " + DISPONIBILITE(d.paquet))
  inserer(md, "")
  inserer(md, "*Double-clic dans l'arbre : insérer l'appel (un nœud dans la vue blueprint).*")
retourner joindre(md, car(10))

fonction FICHE_PAQUET(nom)
  locale md = {}
  inserer(md, sisinon(nom = "base", "# Fonctions intégrées", "# Paquet " + MDCODE(nom)))
  inserer(md, "")
  pour chaque p dans lexis.paquets()
    si p.nom = nom
      inserer(md, MDTEXTE(p.description))
      inserer(md, "")
    finsi
  suivant
  inserer(md, "> **Disponibilité** : " + DISPONIBILITE(nom))
  inserer(md, "")
  locale fonctions = {}, methodes = {}
  pour chaque d dans lexis.documentation(nom)
    locale l = "- " + MDCODE(d.signature) + " - " + MDTEXTE(decouper(d.description, ". ")[1])
    si d.methode
      inserer(methodes, l)
    sinon
      inserer(fonctions, l)
    finsi
  suivant
  si #fonctions > 0
    inserer(md, "## Fonctions (" + #fonctions + ")")
    pour chaque l dans fonctions
      inserer(md, l)
    suivant
    inserer(md, "")
  finsi
  si #methodes > 0
    inserer(md, "## Méthodes (" + #methodes + ")")
    pour chaque l dans methodes
      inserer(md, l)
    suivant
  finsi
retourner joindre(md, car(10))
