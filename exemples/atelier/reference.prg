&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Atelier Lexis+ : référence des fonctions intégrées et des paquets.
&& Les fiches sont du Markdown affiché par ui.markdown.

procedure CHARGER_REFERENCE
  globale docs, docsparnom
  docs = {}
  docsparnom = {}
  aref:vider()
  pour chaque d dans lexis.documentation()
    aref:ajouter(d.paquet, d.signature)
    docs[d.paquet + ui.sep + d.signature] = d
    si non d.methode
      docsparnom[majuscule(d.nom)] = d
      docsparnom[majuscule(decouper(d.signature, "(")[1])] = d
    finsi
  suivant
retourner

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
  si d <> nul
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
retourner "  - " + MDCODE(k) + sisinon(v = "", "", " — défaut " + MDCODE(v))

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
      inserer(l, "- " + MDCODE("...") + " — nombre variable de valeurs")
    cas commencepar(a, "{") et finitpar(a, "}")
      inserer(l, "- **Options** (table `{...}`" + sisinon(facultatif, ", facultative", "") + ") :")
      pour chaque o dans ARGUMENTS_TOP(souschaine(a, 2, #a - 2))
        inserer(l, OPTION_MD(o))
      suivant
    cas commencepar(a, "@")
      inserer(l, "- " + MDCODE(a) + " — procédure passée par référence (`@NOM`)")
    autrement
      inserer(l, "- " + MDCODE(a) + sisinon(facultatif, " — *facultatif*", ""))
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
  inserer(md, "*Double-clic dans l'arbre : insérer l'appel.*")
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
    locale l = "- " + MDCODE(d.signature) + " — " + MDTEXTE(decouper(d.description, ". ")[1])
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
