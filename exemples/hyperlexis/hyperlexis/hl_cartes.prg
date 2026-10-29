&& CC BY-NC-SA 4.0 - HyperLexis, atelier de piles pour Lexis+ (wdlexis+)
&& hl_cartes.prg : cartes et modèles.
&&
&& Une carte = {nom, modele}. Le modèle est un formulaire form_<modele>.prg
&& (dessin) avec son script script_<modele>.prg. Plusieurs cartes peuvent
&& partager un modèle : elles ont le même dessin et des données distinctes.

fonction HL_CARTE()
  si hl.def = nul ou #hl.def.cartes = 0
    retourner nul
  finsi
  si hl.index < 1 ou hl.index > #hl.def.cartes
    hl.index = 1
  finsi
retourner hl.def.cartes[hl.index]
finfonction

fonction HL_INDEX_CARTE(nom)
  pour i = 1 a #hl.def.cartes
    si majuscule(hl.def.cartes[i].nom) = majuscule(nom)
      retourner i
    finsi
  suivant
retourner 0
finfonction

fonction HL_CARTES_DU_MODELE(m)
  locale n = 0
  pour chaque c dans hl.def.cartes
    si majuscule(c.modele) = majuscule(m)
      n += 1
    finsi
  suivant
retourner n
finfonction

fonction HL_NOM_CARTE_LIBRE(base)
  locale n = 2
  tantque HL_INDEX_CARTE(base + "_" + n) > 0
    n += 1
  fintantque
retourner base + "_" + n
finfonction

fonction HL_NOM_MODELE_LIBRE(base)
  locale n = 1
  locale nom = base
  tantque fichier.existe(HL_FORM(nom)) ou HL_INDEX_CARTE(nom) > 0
    n += 1
    nom = base + n
  fintantque
retourner nom
finfonction

fonction HL_NOM_VALIDE(nom, pourModele)
  && nul si le nom convient, sinon le message
  si non HL_EST_IDENT(nom)
    retourner "nom invalide : une lettre, puis des lettres, chiffres ou _ (sans accents) ; « " + nom + " »"
  finsi
  si HL_INDEX_CARTE(nom) > 0
    retourner "une carte s'appelle déjà « " + nom + " »"
  finsi
  si pourModele et fichier.existe(HL_FORM(nom))
    retourner "le modèle « " + nom + " » existe déjà (form_" + nom + ".prg)"
  finsi
retourner nul
finfonction

&&
&& Fichiers d'un modèle
&&

procedure HL_REGENERER_FORM(p)
  && le concepteur relit le dessin (lignes &&§) et réécrit le fichier complet
  locale cv = ui.concepteur{projet = hl.dossier, fichier = p}
  fichier.ecrire(p, cv:code())
finprocedure

procedure HL_ECRIRE_DESSIN(modele, d)
  d["name"] = minuscule(modele)
  d["code"] = "script_" + minuscule(modele) + ".prg"
  locale p = HL_FORM(modele)
  fichier.ecrire(p, HL_DESSIN_TEXTE(d))
  HL_REGENERER_FORM(p)
finprocedure

fonction HL_DESSIN_MODELE(modele)
  && dessin du modèle : celui du canevas s'il est ouvert, sinon celui du fichier
  si hl.canevas <> nul et majuscule(hl.modele) = majuscule(modele)
    retourner HL_DESSIN_DE(hl.canevas:code())
  finsi
retourner HL_DESSIN_DE(HL_LIRE(HL_FORM(modele)))
finfonction

procedure HL_CREER_MODELE(nom, avecTitre)
  locale l = entier(nombre(hl.def.largeur) ou 640)
  locale h = entier(nombre(hl.def.hauteur) ou 440)
  locale enfants = {}
  si avecTitre
    inserer(enfants, HL_NOEUD("etiquette", "titre", HL_NOEUD_PROPS({"libelle", majuscule(gauche(nom, 1)) + ;
                     souschaine(nom, 2), "x", 24, "y", 18, "largeurfixe", l - 48, "hauteurfixe", 32, ;
                     "couleur", "#1E3A8A"})))
  finsi
  locale d = HL_NOEUD("fenetre", minuscule(nom), HL_NOEUD_PROPS({"titre", majuscule(gauche(nom, 1)) + souschaine(nom, 2), ;
                                                                  "largeur", l, "hauteur", h, ;
                                                                  "disposition", "absolue"}), enfants)
  HL_ECRIRE_DESSIN(nom, d)
  si non fichier.existe(HL_SCRIPT(nom))
    fichier.ecrire(HL_SCRIPT(nom), HL_TEXTE_SCRIPT_MODELE(minuscule(nom)))
  finsi
finprocedure

procedure HL_PREPARER_MODELE_IMPORTE(m)
  && formulaire venu de wdlexis+ : il reçoit un script et y associe son code
  si non fichier.existe(HL_SCRIPT(m))
    fichier.ecrire(HL_SCRIPT(m), HL_TEXTE_SCRIPT_MODELE(m))
  finsi
  locale d = HL_DESSIN_DE(HL_LIRE(HL_FORM(m)))
  si d = nul
    retourner
  finsi
  si d["code"] = nul ou d["code"] = "" ou d["code"] = "principal.prg"
    HL_ECRIRE_DESSIN(m, d)
  finsi
finprocedure

&&
&& Nouvelles cartes
&&

procedure HL_NOUVELLE_CARTE_MODELE
  si hl.dossier = ""
    retourner
  finsi
  locale nom = ui.demander("Nom de la nouvelle carte (son modèle portera le même nom) :", HL_NOM_MODELE_LIBRE("carte"))
  si nom = nul
    retourner
  finsi
  nom = minuscule(rogner(nom))
  locale msg = HL_NOM_VALIDE(nom, vrai)
  si msg <> nul
    ui.alerte(msg, "attention", "Nouvelle carte")
    retourner
  finsi
  HL_ENREGISTRER(faux)
  HL_CREER_MODELE(nom, vrai)
  HL_INSERER_CARTE({nom = nom, modele = nom})
  HL_ETAT("Carte « " + nom + " » créée avec son modèle (form_" + nom + ".prg, script_" + nom + ".prg)")
finprocedure

procedure HL_NOUVELLE_CARTE_MEME
  locale c = HL_CARTE()
  si c = nul
    retourner
  finsi
  locale nom = HL_NOM_CARTE_LIBRE(c.modele)
  HL_INSERER_CARTE({nom = nom, modele = c.modele})
  HL_ETAT("Carte « " + nom + " » créée sur le modèle « " + c.modele + " » (" + HL_CARTES_DU_MODELE(c.modele) + " cartes)")
finprocedure

procedure HL_DUPLIQUER_CARTE
  && même modèle, copie des données
  locale c = HL_CARTE()
  si c = nul
    retourner
  finsi
  si hl.mode = "execution"
    MOTEUR_CAPTURER()
  finsi
  locale nom = HL_NOM_CARTE_LIBRE(c.modele)
  locale d = hl.donnees[majuscule(c.nom)]
  si d <> nul
    hl.donnees[majuscule(nom)] = copier(d)
  finsi
  HL_INSERER_CARTE({nom = nom, modele = c.modele})
  HL_ETAT("Carte « " + c.nom + " » dupliquée : « " + nom + " »")
finprocedure

procedure HL_INSERER_CARTE(entree)
  locale pos = hl.index + 1
  si hl.mode = "execution" et MOTEUR_ACTIF()
    && la pile en cours d'exécution partage la même liste de cartes
    inserer(hl.def.cartes, entree, pos)
    HL_PREPARER_CODE()
    ALLER_CARTE(pos)
  sinon
    inserer(hl.def.cartes, entree, pos)
    HL_ECRIRE_FICHIERS_PILE(hl.dossier)
    HL_ALLER_CONCEPTION(pos)
  finsi
  HL_MAJ_CARTES()
finprocedure

procedure HL_DUPLIQUER_MODELE
  && nouvelle carte avec une copie indépendante du modèle : dessin et script,
  && procédures et variable du formulaire renommées
  locale c = HL_CARTE()
  si c = nul ou hl.mode = "execution"
    HL_ETAT("Revenez en mode Conception pour copier un modèle.")
    retourner
  finsi
  locale ancien = minuscule(c.modele)
  locale nom = ui.demander("Nom du nouveau modèle (et de sa carte) :", HL_NOM_MODELE_LIBRE(ancien))
  si nom = nul
    retourner
  finsi
  nom = minuscule(rogner(nom))
  locale msg = HL_NOM_VALIDE(nom, vrai)
  si msg <> nul
    ui.alerte(msg, "attention", "Copier le modèle")
    retourner
  finsi
  HL_ENREGISTRER(faux)
  locale d = HL_DESSIN_MODELE(ancien)
  si d = nul
    ui.alerte("Dessin illisible : form_" + ancien + ".prg", "stop")
    retourner
  finsi
  && procédures des événements : préfixe ANCIEN_ -> NOUVEAU_
  locale src = HL_RENOMMER_CABLAGE(HL_LIRE(HL_SCRIPT(ancien)), ancien, nom)
  locale tous = {}
  HL_NOEUDS_TOUS(d, tous)
  pour chaque n dans tous
    pour chaque e dans n["events"]
      locale h = e[2]
      si commencepar(majuscule(h), majuscule(ancien) + "_")
        locale h2 = majuscule(nom) + souschaine(h, #ancien + 1)
        src = HL_REMPLACER_MOT(src, h, h2)
        e[2] = h2
      finsi
    suivant
  suivant
  src = remplacertexte(src, "modèle « " + ancien + " »", "modèle « " + nom + " »")
  src = remplacertexte(src, "modèle de carte « " + ancien + " »", "modèle de carte « " + nom + " »")
  HL_ECRIRE_DESSIN(nom, d)
  fichier.ecrire(HL_SCRIPT(nom), src)
  locale dd = hl.donnees[majuscule(c.nom)]
  si dd <> nul
    hl.donnees[majuscule(nom)] = copier(dd)
  finsi
  HL_INSERER_CARTE({nom = nom, modele = nom})
  HL_ETAT("Modèle « " + ancien + " » copié : « " + nom + " » (form_" + nom + ".prg, script_" + nom + ".prg)")
finprocedure

&&
&& Supprimer, renommer, ordonner
&&

procedure HL_SUPPRIMER_CARTE
  locale c = HL_CARTE()
  si c = nul
    retourner
  finsi
  si #hl.def.cartes <= 1
    ui.alerte("Une pile garde au moins une carte.", "information", "Supprimer la carte")
    retourner
  finsi
  si hl.mode = "execution"
    SUPPRIMER_CARTE(c.nom)
    HL_MAJ_CARTES()
    retourner
  finsi
  locale dernier = HL_CARTES_DU_MODELE(c.modele) = 1
  locale q = "Supprimer la carte « " + c.nom + " » et ses données ?"
  si dernier
    q = q + NL() + "C'est la dernière carte du modèle « " + c.modele + " » : son dessin et son script " + ;
        "seront rangés dans le dossier .corbeille de la pile."
  finsi
  si non ui.confirmer(q, "question")
    retourner
  finsi
  HL_ENREGISTRER(faux)
  retirer(hl.def.cartes, hl.index)
  hl.donnees[majuscule(c.nom)] = nul
  si dernier
    HL_FERMER_CANEVAS()
    locale corb = HL_P(".corbeille")
    fichier.creerdossier(corb)
    pour chaque p dans {HL_FORM(c.modele), HL_SCRIPT(c.modele)}
      si fichier.existe(p)
        locale uid = hlc.ed:chercherdocument(p)
        si uid <> nul
          hlc.ed:fermer(uid)
        finsi
        && extension changée : le runtime ne charge pas ces fichiers
        fichier.deplacer(p, fichier.joindre(corb, fichier.nom(p) + "." + systeme.date("%Y%m%d%H%M%S") + ".txt"))
      finsi
    suivant
  finsi
  HL_ECRIRE_FICHIERS_PILE(hl.dossier)
  HL_ALLER_CONCEPTION(min(hl.index, #hl.def.cartes))
  HL_ETAT("Carte « " + c.nom + " » supprimée")
finprocedure

procedure HL_RENOMMER_CARTE
  locale c = HL_CARTE()
  si c = nul ou hl.mode = "execution"
    retourner
  finsi
  locale nom = ui.demander("Nouveau nom de la carte « " + c.nom + " » :", c.nom)
  si nom = nul
    retourner
  finsi
  nom = minuscule(rogner(nom))
  si nom = c.nom
    retourner
  finsi
  locale msg = HL_NOM_VALIDE(nom, faux)
  si msg <> nul
    ui.alerte(msg, "attention", "Renommer la carte")
    retourner
  finsi
  locale d = hl.donnees[majuscule(c.nom)]
  hl.donnees[majuscule(c.nom)] = nul
  si d <> nul
    hl.donnees[majuscule(nom)] = d
  finsi
  c.nom = nom
  HL_ECRIRE_FICHIERS_PILE(hl.dossier)
  HL_MAJ_CARTES()
  HL_INSPECTEUR()
  HL_ETAT("Carte renommée : « " + nom + " »")
finprocedure

procedure HL_RENOMMER_MODELE(nouveau)
  && le formulaire, son fichier, son script et les références dans les scripts
  locale c = HL_CARTE()
  locale ancien = minuscule(c.modele)
  nouveau = minuscule(rogner(nouveau))
  si nouveau = ancien ou nouveau = ""
    retourner
  finsi
  si non HL_EST_IDENT(nouveau) ou fichier.existe(HL_FORM(nouveau))
    HL_ETAT("Nom de modèle invalide ou déjà pris : " + nouveau)
    HL_INSPECTEUR()
    retourner
  finsi
  HL_ENREGISTRER(faux)
  locale msg = hl.canevas:fixerpropriete("nom", nouveau)
  si msg <> nul
    HL_ETAT(msg)
    HL_INSPECTEUR()
    retourner
  finsi
  hl.canevas:codeassocie("script_" + nouveau + ".prg")
  fichier.ecrire(HL_FORM(nouveau), hl.canevas:code())
  fichier.supprimer(HL_FORM(ancien))
  && script : fichier renommé ; marques, appel et variable suivent dans tous les scripts
  pour chaque doc dans hlc.ed:documents()
    si doc.chemin <> "" et minuscule(fichier.nom(doc.chemin)) = "script_" + ancien + ".prg"
      hlc.ed:fermer(doc.uid)
    finsi
  suivant
  si fichier.existe(HL_SCRIPT(ancien))
    locale s2 = HL_RENOMMER_CABLAGE(HL_LIRE(HL_SCRIPT(ancien)), ancien, nouveau)
    s2 = remplacertexte(s2, "modèle « " + ancien + " »", "modèle « " + nouveau + " »")
    s2 = remplacertexte(s2, "modèle de carte « " + ancien + " »", "modèle de carte « " + nouveau + " »")
    fichier.ecrire(HL_SCRIPT(nouveau), s2)
    fichier.supprimer(HL_SCRIPT(ancien))
  sinon
    fichier.ecrire(HL_SCRIPT(nouveau), HL_TEXTE_SCRIPT_MODELE(nouveau))
  finsi
  pour chaque p dans HL_FICHIERS_CODE()
    locale uid = hlc.ed:chercherdocument(p)
    locale src = sisinon(uid <> nul, hlc.ed:texte(uid), HL_LIRE(p))
    locale r = HL_RENOMMER_CABLAGE(src, ancien, nouveau)
    si r <> src
      si uid <> nul
        hlc.ed:fixertexte(r, uid)
        hlc.ed:enregistrer(nul, uid)
      sinon
        fichier.ecrire(p, r)
      finsi
    finsi
  suivant
  pour chaque x dans hl.def.cartes
    si minuscule(x.modele) = ancien
      x.modele = nouveau
    finsi
  suivant
  hl.modele = nouveau
  HL_ECRIRE_FICHIERS_PILE(hl.dossier)
  HL_OUVRIR_SCRIPT(HL_SCRIPT(nouveau))
  HL_MAJ_CARTES()
  HL_INSPECTEUR()
  HL_ETAT("Modèle renommé : « " + nouveau + " » (form_" + nouveau + ".prg, script_" + nouveau + ".prg)")
finprocedure

procedure HL_CARTE_MONTER
  HL_DEPLACER_CARTE(-1)
finprocedure

procedure HL_CARTE_DESCENDRE
  HL_DEPLACER_CARTE(1)
finprocedure

procedure HL_DEPLACER_CARTE(delta)
  locale i = hl.index
  locale j = i + delta
  si hl.mode = "execution" ou j < 1 ou j > #hl.def.cartes
    retourner
  finsi
  locale c = retirer(hl.def.cartes, i)
  inserer(hl.def.cartes, c, j)
  hl.index = j
  HL_ECRIRE_FICHIERS_PILE(hl.dossier)
  HL_MAJ_CARTES()
finprocedure

&&
&& Importer un formulaire de wdlexis+
&&

procedure HL_IMPORTER_FORMULAIRE
  si hl.dossier = "" ou hl.mode = "execution"
    retourner
  finsi
  locale p = ui.ouvrirfichier{titre = "Importer un formulaire wdlexis+ (form_<nom>.prg)", ;
                              filtre = "Formulaires Lexis+|form_*.prg|Lexis+|*.prg"}
  si p = nul
    retourner
  finsi
  locale d = HL_DESSIN_DE(HL_LIRE(p))
  si d = nul
    ui.alerte("Ce fichier ne contient pas de dessin de formulaire (lignes &&§).", "stop", "Importer")
    retourner
  finsi
  locale nom = HL_NOM_MODELE_LIBRE(minuscule(d["name"]))
  si non HL_EST_IDENT(nom)
    nom = HL_NOM_MODELE_LIBRE("importe")
  finsi
  && les procédures des événements restent à écrire dans le script du modèle
  locale manquantes = {}
  locale tous = {}
  HL_NOEUDS_TOUS(d, tous)
  pour chaque n dans tous
    pour chaque e dans n["events"]
      inserer(manquantes, e[2])
    suivant
  suivant
  HL_ENREGISTRER(faux)
  HL_ECRIRE_DESSIN(nom, d)
  fichier.ecrire(HL_SCRIPT(nom), HL_TEXTE_SCRIPT_MODELE(nom))
  HL_INSERER_CARTE({nom = nom, modele = nom})
  si #manquantes > 0
    HL_MESSAGE_JOURNAL("Formulaire importé « " + nom + " » : procédures à fournir dans script_" + nom + ".prg : " + ;
                       joindre(manquantes, ", ") + " (le mode Exécution propose de les créer).")
  finsi
  HL_ETAT("Formulaire importé : carte et modèle « " + nom + " »")
finprocedure
