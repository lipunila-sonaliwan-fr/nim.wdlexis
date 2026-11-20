&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Autoriser une app macOS : rend une application (.app) et ses dépendances lançables
&& sans blocage et avec l'accès au réseau, dans l'ordre :
&&   1. Gatekeeper : retrait de la quarantaine (paquet et dépendances hors du paquet)
&&   2. Signature : droits d'exécution, re-signature ad hoc, vérification
&&   3. Réseau : déclaration « réseau local », coupe-feu applicatif ; réglages à ouvrir
&& Distribution : signature Developer ID (hardened runtime, droits) et notarisation.
&&
&&   wdlexisrt principal.prg [chemin de l'exécutable ou du .app]
&&
&& Fichiers : principal.prg (fenêtre), analyse.prg (diagnostic), operations.prg (usage
&& local), distribution.prg (Developer ID, notarisation), outils.prg.
ui = paquet("interface")

SUR_MAC = systeme.plateforme() = "macosx" ou systeme.env("AUTOAPP_MAC") = "1"
APP = nul                   && résultat du dernier diagnostic (analyse.prg)
DIAG = {}                   && lignes du diagnostic
journal_texte = ""
TEXTE_RESEAU = "Cette application se connecte à des appareils et serveurs de votre réseau local."
IDENTS = {}

fen = ui.fenetre{titre = "Autoriser une app macOS", largeur = 1240, hauteur = 840, disposition = "bordure", ;
                 sombre = vrai, densite = "compacte"}
fen.marge = 0

haut = fen:ajouter(ui.rangee())
haut.ancrage = "haut"
haut.marge = 8
haut.espacement = 6
haut:ajouter(ui.etiquette("Application"))
s_chemin = haut:ajouter(ui.saisie{texte = "", indication = "exécutable dans Mon.app/Contents/MacOS, ou le dossier Mon.app"})
s_chemin.poids = 1
b = haut:ajouter(ui.bouton("Choisir l'exécutable…"))
b.surclic = @CHOISIR
b = haut:ajouter(ui.bouton("Analyser", {defaut = vrai}))
b.surclic = @ANALYSER_CLIC

pied = fen:ajouter(ui.rangee())
pied.ancrage = "bas"
pied.hauteurfixe = 22
pied.marge = 2
l_statut = pied:ajouter(ui.etiquette(sisinon(SUR_MAC, "Choisissez l'exécutable d'une application (.app).", ;
                                     "Ce poste n'est pas un Mac : simulation (les commandes sont seulement écrites au journal).")))
l_statut.couleur = "#9CA3AF"

onglets = fen:ajouter(ui.onglets())
onglets.ancrage = "centre"

&& ---------------------------------------------------------------- page « Usage local »
p_local = onglets:ajouterpage("Autoriser (usage local)", "bordure")
droite_ops = p_local:ajouter(ui.panneau{disposition = "vertical", defilement = "vertical"})
droite_ops.ancrage = "droite"
droite_ops.largeurfixe = 430
droite_ops.marge = 6
droite_ops.espacement = 8

centre_diag = p_local:ajouter(ui.colonne())
centre_diag.ancrage = "centre"
centre_diag.marge = 6
centre_diag.espacement = 6
md_app = centre_diag:ajouter(ui.markdown{texte = "", ajuster = vrai})
t_diag = centre_diag:ajouter(ui.tableau())
t_diag.poids = 1
t_diag:ajoutercolonne("Contrôle", 220)
t_diag:ajoutercolonne("État", 60)
t_diag:ajoutercolonne("Détail", 600)
t_diag.surselection = @DIAG_CHOISI
md_aide = centre_diag:ajouter(ui.markdown{texte = "", ajuster = vrai, hauteurmax = 140})

c_ops = droite_ops:ajouter(ui.cadre("Opérations (dans cet ordre)", "vertical"))
k_ops = c_ops:ajouter(ui.cases("1. Retirer la quarantaine (paquet + dépendances)", ;
                               "2. Rétablir les droits d'exécution", ;
                               "3. Déclarer l'accès au réseau local (Info.plist)", ;
                               "4. Re-signer ad hoc (usage local)", ;
                               "5. Coupe-feu : ajouter et débloquer l'app", ;
                               "6. Vérifier"))
pour i = 1 a 6
  k_ops:cocher(i, i <> 5)
suivant
c_ops:ajouter(ui.etiquette("Texte de la demande « réseau local » :"))
s_reseau = c_ops:ajouter(ui.saisie{texte = TEXTE_RESEAU})
k_deps = c_ops:ajouter(ui.cases("Signer aussi les dépendances hors du paquet (ad hoc)"))
r1 = c_ops:ajouter(ui.rangee())
r1.espacement = 4
b = r1:ajouter(ui.bouton("Appliquer", {defaut = vrai}))
b.surclic = @APPLIQUER
b = r1:ajouter(ui.bouton("Voir le script"))
b.surclic = @VOIR_SCRIPT
b = r1:ajouter(ui.bouton("Enregistrer le script…"))
b.surclic = @ENREGISTRER_SCRIPT

c_reg = droite_ops:ajouter(ui.cadre("Réglages Système (à faire à la main)", "vertical"))
r2 = c_reg:ajouter(ui.rangee())
r2.espacement = 4
b = r2:ajouter(ui.bouton("Confidentialité et sécurité"))
b.surclic = @OUVRIR_SECURITE
b = r2:ajouter(ui.bouton("Coupe-feu"))
b.surclic = @OUVRIR_COUPEFEU
r3 = c_reg:ajouter(ui.rangee())
r3.espacement = 4
b = r3:ajouter(ui.bouton("Lancer l'application"))
b.surclic = @LANCER
b = r3:ajouter(ui.bouton("Montrer dans le Finder"))
b.surclic = @FINDER
c_reg:ajouter(ui.markdown{ajuster = vrai, texte = ;
  "- **Ouvrir quand même** : si l'app reste bloquée, *Confidentialité et sécurité*, en bas. " + ;
  "Depuis macOS 15, le clic droit › Ouvrir ne suffit plus.\n" + ;
  "- **Réseau local** (macOS 15+) : *Confidentialité et sécurité › Réseau local*, activer l'app, " + ;
  "ou accepter la demande au premier lancement. Ne se règle pas en ligne de commande.\n" + ;
  "- **Coupe-feu tiers** (Little Snitch, LuLu, antivirus) : y ajouter une règle d'autorisation.\n" + ;
  "- **Autres permissions** (accès complet au disque, accessibilité, caméra…) : *Confidentialité et sécurité*.\n" + ;
  "- **À éviter** : `sudo spctl --master-disable`, qui désactive Gatekeeper pour tout le système."})

&& ---------------------------------------------------------------- page « Distribution »
p_dist = onglets:ajouterpage("Distribuer (Developer ID)", "vertical")
p_dist.marge = 10
p_dist.espacement = 8
p_dist:ajouter(ui.markdown{ajuster = vrai, texte = ;
  "Pour **distribuer** votre propre app : signature avec un certificat **Developer ID Application**, " + ;
  "**hardened runtime**, droits (*entitlements*) adaptés, puis **notarisation** par Apple et **agrafage** du ticket. " + ;
  "Il faut un compte développeur Apple et les outils Xcode. Cette signature remplace la signature ad hoc ; " + ;
  "faites les opérations 2 et 3 de l'onglet précédent avant, mais pas la 4."})
c_sig = p_dist:ajouter(ui.cadre("1. Signature Developer ID", "grille"))
c_sig:ajouter(ui.etiquette("Identité"))
k_ident = c_sig:ajouter(ui.combo())
c_sig:ajouter(ui.etiquette(""))
b = c_sig:ajouter(ui.bouton("Relire les identités du trousseau"))
b.surclic = @LIRE_IDENTITES
c_sig:ajouter(ui.etiquette("Droits (entitlements)"))
k_droits = c_sig:ajouter(ui.cases("com.apple.security.network.client — connexions sortantes (app sandboxée)", ;
                                  "com.apple.security.network.server — connexions entrantes (app sandboxée)", ;
                                  "com.apple.security.cs.disable-library-validation — dylibs non signées par vous", ;
                                  "com.apple.security.app-sandbox — app sandboxée"))
c_sig:ajouter(ui.etiquette(""))
b = c_sig:ajouter(ui.bouton("Signer (Developer ID)"))
b.surclic = @SIGNER_DEVID
c_not = p_dist:ajouter(ui.cadre("2. Notarisation et agrafage", "grille"))
c_not:ajouter(ui.etiquette("Profil du trousseau"))
s_profil = c_not:ajouter(ui.saisie{texte = "notarisation", indication = "nom donné à xcrun notarytool store-credentials"})
c_not:ajouter(ui.etiquette(""))
r4 = c_not:ajouter(ui.rangee())
r4.espacement = 4
b = r4:ajouter(ui.bouton("Créer le profil (Terminal)…"))
b.surclic = @CREER_PROFIL
b = r4:ajouter(ui.bouton("Notariser et agrafer"))
b.surclic = @NOTARISER

&& ---------------------------------------------------------------- page « Journal »
p_journal = onglets:ajouterpage("Journal", "bordure")
ed_journal = p_journal:ajouter(ui.editeur{onglets = faux, minicarte = faux, numeros = "simples"})
ed_journal.ancrage = "centre"
ed_journal:nouveau("journal")
essayer
  ed_journal:langage("shell")
capturer e
finessayer

AFFICHER_APP()
depart = systeme.args[1]
si depart <> nul et depart <> ""
  s_chemin.valeur = fichier.absolu(depart)
  ANALYSER_CLIC(nul)
finsi
ui.executer()

&& ---------------------------------------------------------------- choix et diagnostic

procedure CHOISIR(ev)
  locale dossier = "/Applications"
  si rogner(s_chemin.valeur) <> ""
    dossier = fichier.dossier(rogner(s_chemin.valeur))
  finsi
  si non fichier.existe(dossier)
    dossier = fichier.dossierperso()
  finsi
  locale p = ui.ouvrirfichier{titre = "Exécutable de l'application (Mon.app/Contents/MacOS/…)", dossier = dossier}
  si p = nul ou p = ""
    retourner
  finsi
  s_chemin.valeur = p
  ANALYSER_CLIC(nul)
retourner

procedure ANALYSER_CLIC(ev)
  locale bundle = BUNDLE_DE(s_chemin.valeur)
  si bundle = ""
    ui.alerte("Le chemin choisi n'est pas dans un dossier d'application (.app)." + car(10) + ;
              "Choisissez l'exécutable placé dans Mon.app/Contents/MacOS, ou le dossier Mon.app.", "attention")
    retourner
  finsi
  si SUR_MAC et non fichier.existe(bundle + "/Contents")
    ui.alerte("« " + bundle + " » n'a pas de dossier Contents : ce n'est pas une application macOS.", "attention")
    retourner
  finsi
  STATUT("Analyse de " + bundle + "…")
  APP = ANALYSER(bundle)
  DIAG = LIGNES_DIAGNOSTIC(APP)
  AFFICHER_APP()
  PROPOSER_OPERATIONS()
  locale nko = 0
  pour chaque d dans DIAG
    si d.etat = "✗"
      nko += 1
    finsi
  suivant
  STATUT(sisinon(nko = 0, "Rien de bloquant détecté.", nko + " point(s) à corriger : opérations proposées à droite.") + ;
         sisinon(SUR_MAC, "", " (simulation)"))
retourner

procedure AFFICHER_APP
  si APP = nul
    md_app.valeur = "### Aucune application\n\nChoisissez l'**exécutable** d'une application (dans *Mon.app/Contents/MacOS*) " + ;
                    "ou saisissez le chemin du dossier *.app*, puis **Analyser**."
    t_diag:vider()
    md_aide.valeur = ""
    retourner
  finsi
  locale l = {"### " + APP.nom, "", "`" + APP.bundle + "`  "}
  si APP.identifiant <> ""
    inserer "**Identifiant** " + APP.identifiant + sisinon(APP.version = "", "", " · **version** " + APP.version) + "  " dans l
  finsi
  si APP.archs <> ""
    inserer "**Exécutable** " + APP.exe + " — " + APP.archs dans l
  finsi
  md_app.valeur = joindre(l, car(10))
  t_diag:vider()
  pour chaque d dans DIAG
    t_diag:ajouterligne(d.controle, d.etat, d.detail)
  suivant
  md_aide.valeur = "*Choisissez une ligne pour l'explication.*"
retourner

procedure DIAG_CHOISI(ev)
  locale i = t_diag:selection()
  si i = nul ou i < 1 ou i > taille(DIAG)
    retourner
  finsi
  locale d = DIAG[i]
  md_aide.valeur = "**" + d.controle + "** " + d.etat + "\n\n" + d.detail + "\n\n" + d.aide
retourner

&& coche les opérations utiles d'après le diagnostic
procedure PROPOSER_OPERATIONS
  si APP = nul
    retourner
  finsi
  locale q = APP.quarantaine_n > 0
  pour chaque d dans APP.deps
    si d.quarantaine
      q = vrai
    finsi
  suivant
  k_ops:cocher(1, q)
  k_ops:cocher(2, taille(APP.exec_ko) > 0)
  k_ops:cocher(3, APP.reseau_local = "")
  && ne pas écraser une signature Developer ID valide, sauf si l'Info.plist change
  k_ops:cocher(4, non APP.signature_ok ou APP.reseau_local = "" ou APP.signature_genre = "aucune")
  k_ops:cocher(5, APP.parefeu_actif)
  k_ops:cocher(6, vrai)
retourner

fonction CHOIX_OPERATIONS()
  locale c = {quarantaine = k_ops:coche(1), droits = k_ops:coche(2), reseau = k_ops:coche(3), ;
              texte_reseau = rogner(s_reseau.valeur), signature = k_ops:coche(4), parefeu = k_ops:coche(5), ;
              verifier = k_ops:coche(6), signer_deps = k_deps:coche(1)}
  si c.texte_reseau = ""
    c.texte_reseau = TEXTE_RESEAU
  finsi
retourner c

&& ---------------------------------------------------------------- opérations

fonction PRET()
  si APP = nul
    ANALYSER_CLIC(nul)
  finsi
retourner APP <> nul

procedure APPLIQUER(ev)
  si non PRET()
    retourner
  finsi
  locale c = CHOIX_OPERATIONS()
  && modifier l'Info.plist casse la signature : il faut re-signer ensuite
  si (c.reseau ou c.droits) et non c.signature
    si APP.signature_genre = "Developer ID"
      si non ui.confirmer("L'app porte une signature Developer ID. Modifier son contenu la rendra invalide, " + ;
                          "et l'opération 4 (ad hoc) n'est pas cochée." + car(10) + car(10) + ;
                          "Continuer quand même ? (re-signez ensuite avec l'onglet Distribuer)", "attention")
        retourner
      finsi
    sinon
      c.signature = vrai
      k_ops:cocher(4, vrai)
      JOURNAL("(opération 4 ajoutée : le contenu du paquet change, il doit être re-signé)")
    finsi
  finsi
  si c.signature et APP.signature_genre = "Developer ID" et APP.signature_ok
    si non ui.confirmer("L'app porte une signature Developer ID valide (" + APP.autorite + ")." + car(10) + ;
                        "La re-signature ad hoc la remplacera (usage local seulement). Continuer ?", "attention")
      retourner
    finsi
  finsi
  locale admin = ADMIN_NECESSAIRE(APP, c)
  STATUT("Opérations en cours" + sisinon(admin, " (mot de passe administrateur demandé)…", "…"))
  locale n = EXECUTER_SCRIPT(SCRIPT_OPERATIONS(APP, c), admin)
  onglets.valeur = 3
  faire cas
  cas n < 0
    STATUT("Opérations annulées.")
    retourner
  cas n = 0
    STATUT("Opérations terminées sans erreur. Pensez au réseau local dans Réglages Système si l'app joint le réseau local.")
  autrement
    STATUT("Opérations terminées avec " + n + " erreur(s) : voir le journal.")
  fincas
  && nouveau diagnostic ; les opérations encore utiles restent cochées
  APP = ANALYSER(APP.bundle)
  DIAG = LIGNES_DIAGNOSTIC(APP)
  AFFICHER_APP()
  PROPOSER_OPERATIONS()
retourner

procedure VOIR_SCRIPT(ev)
  si non PRET()
    retourner
  finsi
  locale c = CHOIX_OPERATIONS()
  JOURNAL("")
  JOURNAL("==== Script (non exécuté)" + sisinon(ADMIN_NECESSAIRE(APP, c), " — à lancer avec sudo", ""))
  JOURNAL(SCRIPT_OPERATIONS(APP, c))
  onglets.valeur = 3
retourner

procedure ENREGISTRER_SCRIPT(ev)
  si non PRET()
    retourner
  finsi
  locale p = ui.enregistrerfichier{nom = fichier.joindre(fichier.dossierperso(), "autoriser-" + remplacertexte(APP.nom, ".app", "") + ".sh"), ;
                                   filtre = "*.sh"}
  si p = nul ou p = ""
    retourner
  finsi
  fichier.ecrire(p, SCRIPT_OPERATIONS(APP, CHOIX_OPERATIONS()))
  CMD("chmod +x " + Q(p), vrai)
  STATUT("Script enregistré : " + p)
retourner

&& ---------------------------------------------------------------- Réglages Système

procedure OUVRIR_SECURITE(ev)
  CMD("open " + Q("x-apple.systempreferences:com.apple.preference.security"))
retourner

procedure OUVRIR_COUPEFEU(ev)
  && macOS 13+ : Réseau › Coupe-feu ; plus ancien : Sécurité › Coupe-feu
  si CMD("open " + Q("x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall")).code <> 0
    CMD("open " + Q("x-apple.systempreferences:com.apple.preference.security?Firewall"))
  finsi
retourner

procedure LANCER(ev)
  si PRET()
    CMD("open " + Q(APP.bundle))
    STATUT("Application lancée : acceptez la demande d'accès au réseau local si elle apparaît.")
  finsi
retourner

procedure FINDER(ev)
  si PRET()
    CMD("open -R " + Q(APP.bundle))
  finsi
retourner

&& ---------------------------------------------------------------- distribution

procedure LIRE_IDENTITES(ev)
  IDENTS = IDENTITES()
  k_ident:vider()
  pour chaque x dans IDENTS
    k_ident:ajouter(x)
  suivant
  locale choisi = 0
  pour i = 1 a taille(IDENTS)
    si choisi = 0 et commencepar(IDENTS[i], "Developer ID Application")
      choisi = i
    finsi
  suivant
  si taille(IDENTS) > 0
    k_ident:selectionner(max(1, choisi))
  finsi
  STATUT(taille(IDENTS) + " identité(s) de signature dans le trousseau" + ;
         sisinon(choisi = 0 et taille(IDENTS) >= 0, " — aucune « Developer ID Application »", ""))
retourner

procedure SIGNER_DEVID(ev)
  si non PRET()
    retourner
  finsi
  si taille(IDENTS) = 0
    LIRE_IDENTITES(nul)
  finsi
  si taille(IDENTS) = 0 et SUR_MAC
    ui.alerte("Aucune identité de signature dans le trousseau." + car(10) + ;
              "Installez un certificat « Developer ID Application » (Xcode › Réglages › Comptes, ou developer.apple.com).", "attention")
    retourner
  finsi
  locale ident = sisinon(taille(IDENTS) = 0, "Developer ID Application: Exemple (EQUIPE1234)", IDENTS[max(1, k_ident:selection())])
  locale droits = {}
  locale noms = {"com.apple.security.network.client", "com.apple.security.network.server", ;
                 "com.apple.security.cs.disable-library-validation", "com.apple.security.app-sandbox"}
  pour i = 1 a 4
    si k_droits:coche(i)
      inserer noms[i] dans droits
    finsi
  suivant
  locale pd = systeme.nomtemporaire() + "-droits.plist"
  fichier.ecrire(pd, PLIST_DROITS(droits))
  JOURNAL("==== Droits (" + pd + ")")
  JOURNAL(PLIST_DROITS(droits))
  locale n = EXECUTER_SCRIPT(SCRIPT_SIGNATURE_DEVID(APP, ident, droits, pd), non APP.ecriture)
  essayer
    systeme.supprimer(pd)
  capturer e
  finessayer
  onglets.valeur = 3
  STATUT(sisinon(n = 0, "Signé avec « " + ident + " ». Étape suivante : notarisation.", "Signature : " + n + " erreur(s), voir le journal."))
  APP = ANALYSER(APP.bundle)
  DIAG = LIGNES_DIAGNOSTIC(APP)
  AFFICHER_APP()
retourner

procedure CREER_PROFIL(ev)
  locale profil = rogner(s_profil.valeur)
  si profil = ""
    profil = "notarisation"
  finsi
  locale equipe = ""
  si APP <> nul
    equipe = APP.equipe
  finsi
  locale commande = COMMANDE_PROFIL(profil, equipe)
  JOURNAL("")
  JOURNAL("==== Profil de notarisation : à lancer une fois dans le Terminal (remplacez les <…>)")
  JOURNAL(commande)
  && le mot de passe pour application se crée sur appleid.apple.com
  si SUR_MAC
    locale apple = "tell application " + car(34) + "Terminal" + car(34) + " to do script " + car(34) + ;
                   remplacertexte(remplacertexte(commande, car(92), car(92) + car(92)), car(34), car(92) + car(34)) + car(34)
    CMD("osascript -e " + Q(apple) + " -e " + Q("tell application " + car(34) + "Terminal" + car(34) + " to activate"))
  finsi
  onglets.valeur = 3
  STATUT("Commande ouverte dans le Terminal : complétez l'identifiant Apple et le mot de passe pour application.")
retourner

procedure NOTARISER(ev)
  si non PRET()
    retourner
  finsi
  si APP.signature_genre <> "Developer ID" et SUR_MAC
    ui.alerte("L'app doit d'abord être signée avec un certificat Developer ID (étape 1).", "attention")
    retourner
  finsi
  locale profil = rogner(s_profil.valeur)
  si profil = ""
    ui.alerte("Indiquez le nom du profil du trousseau (créé par « Créer le profil »).", "attention")
    retourner
  finsi
  STATUT("Notarisation en cours (envoi à Apple, quelques minutes)…")
  locale n = EXECUTER_SCRIPT(SCRIPT_NOTARISATION(APP, profil), faux)
  onglets.valeur = 3
  STATUT(sisinon(n = 0, "Notarisée et agrafée : l'app se lance sur tout Mac.", "Notarisation : échec, voir le journal."))
  APP = ANALYSER(APP.bundle)
  DIAG = LIGNES_DIAGNOSTIC(APP)
  AFFICHER_APP()
retourner
