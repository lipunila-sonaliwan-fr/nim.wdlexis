&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& webview : JavaScript -> Lexis+.
&&   f:lier("nomjs", @PROC)        crée window.nomjs(...) : une Promise résolue avec le
&&                                 retour de PROC (rejetée si PROC lève une erreur)
&&   f:autoriser("PROC", ...)      permet lexis.appeler("PROC", ...) depuis la page
&&   f.surmessage = @PROC          reçoit lexis.envoyer(donnees) (sans réponse)
&&   console.log / lexis.journal   s'affichent dans la console Lexis+
&& Les arguments et les résultats passent en JSON : nombres, chaînes, logiques,
&& listes et fiches (les clefs JavaScript deviennent des noms Lexis+).
&& Lancement : wdlexisrt exemples/webview/03_js_vers_lexis/principal.prg

taux = {normal = 20, intermediaire = 10, reduit = 5.5}
factures = {}

f = webview.fenetre{titre = "JavaScript -> Lexis+", largeur = 720, hauteur = 600, fichier = "page.htm"}
f:lier("calculerTTC", @CALCULER_TTC)     && window.calculerTTC(ht, genre)
f:lier("taux")                           && window.taux() -> procédure TAUX (même nom)
f:autoriser("ENREGISTRER", "HISTORIQUE") && lexis.appeler("ENREGISTRER", fiche)...
f.surmessage = @JOURNAL
f:executer()
? #factures, "facture(s) enregistrée(s) pendant la session"

fonction TAUX()
retourner taux

fonction CALCULER_TTC(ht, genre)
  si nombre(ht) = nul
    erreur "montant hors taxes invalide"      && rejette la Promise JavaScript
  finsi
  locale t = taux[majuscule(genre)]
  si t = nul
    erreur "taux inconnu : " + genre
  finsi
  locale tva = arrondi(ht * t / 100, 2)
retourner {ht = ht, taux = t, tva = tva, ttc = arrondi(ht + tva, 2)}

fonction ENREGISTRER(fiche)
  && fiche arrive de JavaScript : {client, ht, genre} -> fiche.client, fiche.ht...
  si fiche.client = nul ou longueur(fiche.client) < 2
    retourner {ok = faux, message = "Le nom du client est obligatoire."}
  finsi
  locale c = CALCULER_TTC(fiche.ht, fiche.genre)
  c.client = fiche.client
  c.numero = #factures + 1
  c.heure = heure()
  inserer c dans factures
  ? "facture", c.numero, "enregistrée :", c.client, c.ttc, "€ TTC"
retourner {ok = vrai, numero = c.numero, message = "Facture n°" + c.numero + " enregistrée."}

fonction HISTORIQUE()
retourner factures

procedure JOURNAL(d)
  ? "message de la page :", d.genre, "-", d.texte
retourner
