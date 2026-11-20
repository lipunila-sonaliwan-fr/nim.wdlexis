&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Autoriser une app macOS : opérations, dans l'ordre :
&&   1 quarantaine  2 droits  3 réseau local (Info.plist)  4 signature ad hoc
&&   5 coupe-feu  6 vérification
&& Les opérations forment un script shell (visible et enregistrable) ; il est exécuté
&& directement, ou par une demande de mot de passe administrateur quand le paquet n'est
&& pas modifiable par l'utilisateur ou que le coupe-feu est concerné.

&& choix : {quarantaine, droits, reseau, texte_reseau, signature, signer_deps, parefeu, verifier}
fonction SCRIPT_OPERATIONS(a, choix)
  locale s = {}
  locale B = Q(a.bundle)
  inserer "#!/bin/sh" dans s
  inserer "# Autoriser une app macOS — " + a.nom + " — " + maintenant() dans s
  inserer "B=" + B dans s
  inserer "ECHECS=0" dans s
  inserer "etape() { echo; echo \"== $1\"; }" dans s
  inserer "ko() { echo \"ÉCHEC : $1\"; ECHECS=$((ECHECS+1)); }" dans s
  si choix.quarantaine
    inserer "etape '1. Quarantaine (Gatekeeper)'" dans s
    inserer "xattr -dr com.apple.quarantine \"$B\" && echo 'quarantaine retirée du paquet' || ko 'xattr sur le paquet'" dans s
    pour chaque d dans a.deps
      si d.existe
        inserer "xattr -d com.apple.quarantine " + Q(d.chemin) + " 2>/dev/null; echo " + Q("dépendance : " + d.chemin) dans s
      finsi
    suivant
  finsi
  si choix.droits
    inserer "etape '2. Droits'" dans s
    inserer "chmod -R u+rwX \"$B\" || ko 'chmod -R u+rwX'" dans s
    inserer "chmod +x \"$B\"/Contents/MacOS/* && echo 'exécutables : +x' || ko 'chmod +x Contents/MacOS/*'" dans s
  finsi
  si choix.reseau
    inserer "etape '3. Réseau local : NSLocalNetworkUsageDescription'" dans s
    inserer "plutil -replace NSLocalNetworkUsageDescription -string " + Q(choix.texte_reseau) + ;
            " \"$B/Contents/Info.plist\" && echo 'clé écrite dans Info.plist' || ko 'plutil -replace'" dans s
    inserer "plutil -lint \"$B/Contents/Info.plist\" || ko 'Info.plist invalide'" dans s
  finsi
  si choix.signature
    inserer "etape '4. Signature ad hoc'" dans s
    si choix.signer_deps
      pour chaque d dans a.deps
        si d.existe
          inserer "codesign --force --sign - " + Q(d.chemin) + " || ko " + Q("signature de " + d.chemin) dans s
        finsi
      suivant
    finsi
    inserer "codesign --force --deep --sign - \"$B\" && echo 'paquet signé (ad hoc)' || ko 'codesign --sign -'" dans s
  finsi
  si choix.parefeu
    inserer "etape '5. Coupe-feu applicatif'" dans s
    inserer "FW=" + FW() dans s
    inserer "$FW --getglobalstate" dans s
    inserer "$FW --add \"$B\" || ko 'socketfilterfw --add'" dans s
    inserer "$FW --unblockapp \"$B\" || ko 'socketfilterfw --unblockapp'" dans s
  finsi
  si choix.verifier
    inserer "etape '6. Vérification'" dans s
    inserer "codesign --verify --deep --strict --verbose=2 \"$B\" || ko 'signature invalide'" dans s
    inserer "spctl --assess --type execute --verbose \"$B\" || echo '(refus de spctl attendu pour une signature ad hoc non notarisée)'" dans s
    inserer "N=$(xattr -r -l \"$B\" 2>/dev/null | grep -c com.apple.quarantine); echo \"éléments en quarantaine : $N\"" dans s
  finsi
  inserer "echo" dans s
  inserer "if [ $ECHECS -eq 0 ]; then echo 'TERMINÉ sans erreur'; else echo \"TERMINÉ avec $ECHECS erreur(s)\"; fi" dans s
  inserer "exit $ECHECS" dans s
retourner joindre(s, car(10)) + car(10)

&& administrateur nécessaire : paquet non modifiable, coupe-feu, dépendances système
fonction ADMIN_NECESSAIRE(a, choix)
  si choix.parefeu
    retourner vrai
  finsi
  si (choix.quarantaine ou choix.droits ou choix.reseau ou choix.signature) et non a.ecriture
    retourner vrai
  finsi
  pour chaque d dans a.deps
    si d.existe et (d.quarantaine ou choix.signer_deps)
      si CMD("test -w " + Q(d.chemin), vrai).code <> 0
        retourner vrai
      finsi
    finsi
  suivant
retourner faux

&& exécute le script ; renvoie le code de retour (nombre d'échecs ; -1 : annulé)
fonction EXECUTER_SCRIPT(texte, admin)
  locale chemin = systeme.nomtemporaire() + "-autoapp.sh"
  locale sortie = chemin + ".log"
  fichier.ecrire(chemin, texte)
  JOURNAL("")
  JOURNAL("==== Script " + chemin + sisinon(admin, " (administrateur)", ""))
  JOURNAL(texte)
  si non SUR_MAC
    JOURNAL("(simulation : script non exécuté, ce poste n'est pas un Mac)")
    systeme.supprimer(chemin)
    retourner 0
  finsi
  locale r = nul
  si admin
    && une seule demande de mot de passe pour tout le script
    locale ordre = "/bin/sh " + Q(chemin) + " > " + Q(sortie) + " 2>&1"
    locale apple = "do shell script " + car(34) + remplacertexte(remplacertexte(ordre, car(92), car(92) + car(92)), car(34), car(92) + car(34)) + ;
                   car(34) + " with administrator privileges"
    r = systeme.capturer("osascript -e " + Q(apple) + " 2>&1")
    si contient(chaine(r.sortie), "-128") ou contient(chaine(r.sortie), "User canceled")
      JOURNAL("Opérations annulées (mot de passe non saisi).")
      retourner -1
    finsi
    essayer
      JOURNAL(fichier.lire(sortie))
    capturer e
      JOURNAL(chaine(r.sortie))
    finessayer
  sinon
    r = systeme.capturer("/bin/sh " + Q(chemin) + " 2>&1")
    JOURNAL(chaine(r.sortie))
  finsi
  essayer
    systeme.supprimer(sortie)
  capturer e
  finessayer
  essayer
    systeme.supprimer(chemin)
  capturer e
  finessayer
  locale n = r.code
  && osascript renvoie 1 quand le script se termine en erreur : on relit le bilan
  si admin et n <> 0
    n = 1
  finsi
retourner n
