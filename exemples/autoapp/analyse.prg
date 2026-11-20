&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Autoriser une app macOS : diagnostic d'un paquet .app (aucune modification).

fonction FW()
retourner "/usr/libexec/ApplicationFirewall/socketfilterfw"

fonction PLISTBUDDY()
retourner "/usr/libexec/PlistBuddy"

&& valeur d'une clef de l'Info.plist, "" si absente
fonction CLEF_PLIST(plist, clef)
  locale r = CMD(PLISTBUDDY() + " -c " + Q("Print :" + clef) + " " + Q(plist), vrai)
  si r.code <> 0
    retourner ""
  finsi
retourner rogner(r.sortie)

&& analyse complète ; renvoie la table APP (voir LISEZMOI.md, « Diagnostic »)
fonction ANALYSER(bundle)
  locale a = {bundle = bundle, plist = bundle + "/Contents/Info.plist", exe = "", nom = fichier.nom(bundle), ;
              identifiant = "", version = "", archs = "", plist_ok = faux, plist_msg = "", ;
              quarantaine_n = 0, quarantaine_ex = {}, exec_ko = {}, signature_ok = faux, signature_msg = "", ;
              signature_genre = "aucune", autorite = "", equipe = "", runtime = faux, ;
              gatekeeper_ok = faux, gatekeeper_msg = "", reseau_local = "", parefeu_actif = faux, ;
              parefeu_etat = "", parefeu_app = "", ecriture = faux, deps = {}, otool = faux, macho = 0}
  JOURNAL("")
  JOURNAL("==== Diagnostic de " + bundle)
  && Info.plist
  locale r = CMD("plutil -lint " + Q(a.plist))
  a.plist_ok = r.code = 0
  a.plist_msg = PREMIERE_LIGNE(r.sortie)
  si a.plist_ok
    a.exe = CLEF_PLIST(a.plist, "CFBundleExecutable")
    a.identifiant = CLEF_PLIST(a.plist, "CFBundleIdentifier")
    a.version = CLEF_PLIST(a.plist, "CFBundleShortVersionString")
    a.reseau_local = CLEF_PLIST(a.plist, "NSLocalNetworkUsageDescription")
  finsi
  si a.exe <> ""
    r = CMD("file -b " + Q(bundle + "/Contents/MacOS/" + a.exe))
    a.archs = PREMIERE_LIGNE(r.sortie)
  finsi
  && écriture possible sans droits d'administrateur ?
  a.ecriture = CMD("test -w " + Q(bundle) + " && test -w " + Q(bundle + "/Contents"), vrai).code = 0
  && quarantaine (sur tout le contenu)
  r = CMD("xattr -r -l " + Q(bundle) + " | grep 'com.apple.quarantine'", vrai)
  pour chaque l dans decouper(r.sortie, car(10))
    si contient(l, "com.apple.quarantine")
      a.quarantaine_n += 1
      si taille(a.quarantaine_ex) < 5
        inserer remplacertexte(gauche(l, position(": com.apple.quarantine", l) - 1), bundle + "/", "") dans a.quarantaine_ex
      finsi
    finsi
  suivant
  JOURNAL("quarantaine : " + a.quarantaine_n + " élément(s)")
  && droits d'exécution des exécutables
  r = CMD("find " + Q(bundle + "/Contents/MacOS") + " -type f ! -perm -u+x", vrai)
  pour chaque l dans decouper(r.sortie, car(10))
    si rogner(l) <> ""
      inserer fichier.nom(l) dans a.exec_ko
    finsi
  suivant
  JOURNAL("exécutables sans droit d'exécution : " + taille(a.exec_ko))
  && signature
  r = CMD("codesign --verify --deep --strict --verbose=2 " + Q(bundle))
  a.signature_ok = r.code = 0
  a.signature_msg = remplacertexte(PREMIERE_LIGNE(r.sortie), bundle + ": ", "")
  r = CMD("codesign -dv --verbose=2 " + Q(bundle))
  pour chaque l dans decouper(r.sortie, car(10))
    faire cas
    cas commencepar(l, "Signature=adhoc")
      a.signature_genre = "ad hoc"
    cas commencepar(l, "Authority=") et a.autorite = ""
      a.autorite = souschaine(l, 11)
      a.signature_genre = sisinon(contient(l, "Developer ID"), "Developer ID", ;
                                  sisinon(contient(l, "Apple Development"), "Apple Development", "certificat"))
    cas commencepar(l, "TeamIdentifier=")
      a.equipe = souschaine(l, 16)
    cas commencepar(l, "CodeDirectory") et contient(l, "runtime")
      a.runtime = vrai
    fincas
  suivant
  si contient(r.sortie, "not signed at all") ou contient(r.sortie, "code object is not signed")
    a.signature_genre = "aucune"
  finsi
  && Gatekeeper
  r = CMD("spctl --assess --type execute --verbose " + Q(bundle))
  a.gatekeeper_ok = r.code = 0
  a.gatekeeper_msg = remplacertexte(PREMIERE_LIGNE(r.sortie), bundle + ": ", "")
  && pare-feu applicatif
  r = CMD(FW() + " --getglobalstate")
  a.parefeu_etat = PREMIERE_LIGNE(r.sortie)
  a.parefeu_actif = contient(minuscule(r.sortie), "enabled") ou contient(r.sortie, "State = 1") ou contient(r.sortie, "State = 2")
  si a.parefeu_actif
    r = CMD(FW() + " --getappblocked " + Q(bundle))
    a.parefeu_app = PREMIERE_LIGNE(r.sortie)
  finsi
  && dépendances hors du paquet (otool, des outils de ligne de commande Xcode)
  a.otool = CMD("command -v otool", vrai).code = 0
  si a.otool
    DEPENDANCES(a)
  finsi
  JOURNAL("==== Fin du diagnostic")
retourner a

&& bibliothèques chargées hors du paquet : /usr/local, /opt/homebrew, dossier personnel…
procedure DEPENDANCES(a)
  locale r = CMD("find " + Q(a.bundle + "/Contents") + " -type f '(' -perm -u+x -o -name '*.dylib' -o -name '*.so' ')' | head -400", vrai)
  locale vus = {}
  pour chaque f dans decouper(r.sortie, car(10))
    si rogner(f) <> ""
      locale o = CMD("otool -L " + Q(f), vrai)
      si o.code = 0 et non contient(o.sortie, "is not an object file")
        a.macho += 1
        locale premiere = vrai
        pour chaque l dans decouper(o.sortie, car(10))
          si premiere
            premiere = faux
            boucler
          finsi
          locale d = rogner(l)
          locale p = position(" (compatibility", d)
          si p > 0
            d = gauche(d, p - 1)
          finsi
          si d <> "" et EST_EXTERNE(d, a.bundle) et non contient(vus, d)
            inserer d dans vus
          finsi
        suivant
      finsi
    finsi
  suivant
  pour chaque d dans vus
    locale ex = CMD("test -e " + Q(d), vrai).code = 0
    locale qn = faux
    si ex
      qn = CMD("xattr -p com.apple.quarantine " + Q(d), vrai).code = 0
    finsi
    inserer {chemin = d, existe = ex, quarantaine = qn} dans a.deps
  suivant
  JOURNAL("binaires Mach-O : " + a.macho + " ; dépendances hors du paquet : " + taille(a.deps))
retourner

fonction EST_EXTERNE(d, bundle)
  si commencepar(d, "@") ou commencepar(d, "/System/") ou commencepar(d, "/usr/lib/") ou commencepar(d, bundle + "/")
    retourner faux
  finsi
retourner commencepar(d, "/")

&& lignes du diagnostic : {controle, etat, detail, aide} ; etat : ✓ ⚠ ✗
fonction LIGNES_DIAGNOSTIC(a)
  locale l = {}
  inserer {controle = "Info.plist", etat = sisinon(a.plist_ok, "✓", "✗"), ;
           detail = sisinon(a.plist_ok, "valide — exécutable « " + a.exe + " »", a.plist_msg), ;
           aide = "Un Info.plist invalide empêche le lancement. Corrigez-le (plutil -lint indique la ligne) avant toute autre opération."} dans l
  inserer {controle = "Quarantaine (Gatekeeper)", etat = sisinon(a.quarantaine_n = 0, "✓", "✗"), ;
           detail = sisinon(a.quarantaine_n = 0, "aucun attribut com.apple.quarantine", ;
                            a.quarantaine_n + " élément(s) en quarantaine (" + joindre(a.quarantaine_ex, ", ") + ")"), ;
           aide = "Opération 1 : xattr -dr com.apple.quarantine sur tout le paquet."} dans l
  inserer {controle = "Droits d'exécution", etat = sisinon(taille(a.exec_ko) = 0, "✓", "✗"), ;
           detail = sisinon(taille(a.exec_ko) = 0, "les exécutables de Contents/MacOS sont exécutables", ;
                            "non exécutable(s) : " + joindre(a.exec_ko, ", ")), ;
           aide = "Opération 2 : chmod -R u+rwX sur le paquet, chmod +x sur Contents/MacOS/*."} dans l
  locale sig = a.signature_genre
  si a.autorite <> ""
    sig = sig + " (" + a.autorite + ")"
  finsi
  inserer {controle = "Signature", etat = sisinon(a.signature_ok, "✓", "✗"), ;
           detail = sig + " — " + sisinon(a.signature_ok, "valide", a.signature_msg) + sisinon(a.runtime, " ; hardened runtime", ""), ;
           aide = "Sur Apple Silicon, tout code arm64 doit être signé, au moins ad hoc. Opération 4 : codesign --force --deep --sign -. " + ;
                  "Attention : une re-signature ad hoc remplace une signature Developer ID."} dans l
  inserer {controle = "Évaluation Gatekeeper", etat = sisinon(a.gatekeeper_ok, "✓", "⚠"), ;
           detail = a.gatekeeper_msg, ;
           aide = "spctl refuse une app signée ad hoc ou non notarisée : c'est attendu en usage local. Sans quarantaine, elle se lance quand même. " + ;
                  "Pour l'accepter partout : signature Developer ID et notarisation (onglet Distribuer)."} dans l
  inserer {controle = "Réseau local (macOS 15+)", etat = sisinon(a.reseau_local <> "", "✓", "⚠"), ;
           detail = sisinon(a.reseau_local <> "", "déclaré : « " + a.reseau_local + " »", "NSLocalNetworkUsageDescription absente"), ;
           aide = "Opération 3 : déclarer l'accès dans l'Info.plist (puis re-signer). L'autorisation elle-même se donne dans " + ;
                  "Réglages Système › Confidentialité et sécurité › Réseau local, ou en acceptant la demande au premier lancement."} dans l
  inserer {controle = "Coupe-feu applicatif", etat = sisinon(non a.parefeu_actif, "✓", sisinon(contient(minuscule(a.parefeu_app), "block"), "✗", "⚠")), ;
           detail = sisinon(a.parefeu_actif, "actif — " + sisinon(a.parefeu_app = "", "app non déclarée", a.parefeu_app), "inactif"), ;
           aide = "Le coupe-feu de macOS filtre les connexions entrantes (app serveur, écoute réseau). Opération 5 : --add et --unblockapp (mot de passe administrateur)."} dans l
  si a.otool
    locale ext = {}
    locale nq = 0
    locale manquantes = 0
    pour chaque d dans a.deps
      inserer d.chemin dans ext
      si d.quarantaine
        nq += 1
      finsi
      si non d.existe
        manquantes += 1
      finsi
    suivant
    inserer {controle = "Dépendances hors du paquet", ;
             etat = sisinon(manquantes > 0, "✗", sisinon(nq > 0, "✗", sisinon(taille(ext) > 0, "⚠", "✓"))), ;
             detail = sisinon(taille(ext) = 0, "aucune (" + a.macho + " binaire(s) examiné(s))", ;
                              taille(ext) + " : " + joindre(ext, ", ") + sisinon(nq > 0, " — " + nq + " en quarantaine", "") + ;
                              sisinon(manquantes > 0, " — " + manquantes + " absente(s)", "")), ;
             aide = "Les bibliothèques hors du paquet sont traitées une à une (quarantaine, et signature si cochée). Une bibliothèque absente doit être installée."} dans l
  sinon
    inserer {controle = "Dépendances hors du paquet", etat = "⚠", detail = "otool absent : installez les outils (xcode-select --install)", ;
             aide = "otool fait partie des outils de ligne de commande Xcode."} dans l
  finsi
  inserer {controle = "Écriture dans le paquet", etat = sisinon(a.ecriture, "✓", "⚠"), ;
           detail = sisinon(a.ecriture, "possible sans droits d'administrateur", "droits d'administrateur nécessaires (mot de passe demandé)"), ;
           aide = "Une app installée par un paquet .pkg appartient souvent à root : les opérations passent alors par une demande de mot de passe."} dans l
retourner l
