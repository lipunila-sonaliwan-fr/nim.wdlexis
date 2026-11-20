&& CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
&& Autoriser une app macOS : distribution (certificat Developer ID, hardened runtime,
&& droits « entitlements », notarisation et agrafage). Nécessite un compte développeur
&& Apple et les outils Xcode (xcrun notarytool, stapler).

&& identités de signature du trousseau : liste de libellés
&& « Developer ID Application: Nom (EQUIPE) »
fonction IDENTITES()
  locale r = CMD("security find-identity -v -p codesigning")
  locale res = {}
  pour chaque l dans decouper(r.sortie, car(10))
    locale p = position(car(34), l)
    si p > 0
      locale reste = souschaine(l, p + 1)
      locale q = position(car(34), reste)
      si q > 1
        inserer gauche(reste, q - 1) dans res
      finsi
    finsi
  suivant
retourner res

&& droits (entitlements) : plist XML
fonction PLIST_DROITS(d)
  locale l = {"<?xml version=" + car(34) + "1.0" + car(34) + " encoding=" + car(34) + "UTF-8" + car(34) + "?>", ;
              "<!DOCTYPE plist PUBLIC " + car(34) + "-//Apple//DTD PLIST 1.0//EN" + car(34) + " " + car(34) + ;
              "http://www.apple.com/DTDs/PropertyList-1.0.dtd" + car(34) + ">", ;
              "<plist version=" + car(34) + "1.0" + car(34) + ">", "<dict>"}
  pour chaque k dans d
    inserer "  <key>" + k + "</key><true/>" dans l
  suivant
  inserer "</dict>" dans l
  inserer "</plist>" dans l
retourner joindre(l, car(10)) + car(10)

&& signature Developer ID, de l'intérieur vers l'extérieur (bibliothèques, cadres,
&& assistants, puis le paquet), avec hardened runtime et horodatage
fonction SCRIPT_SIGNATURE_DEVID(a, identite, droits, chemin_droits)
  locale s = {}
  inserer "#!/bin/sh" dans s
  inserer "# Signature Developer ID — " + a.nom + " — " + maintenant() dans s
  inserer "B=" + Q(a.bundle) dans s
  inserer "ID=" + Q(identite) dans s
  inserer "ENT=" + Q(chemin_droits) dans s
  inserer "ECHECS=0" dans s
  inserer "ko() { echo \"ÉCHEC : $1\"; ECHECS=$((ECHECS+1)); }" dans s
  inserer "signe() { codesign --force --options runtime --timestamp --sign \"$ID\" \"$1\" && echo \"signé : ${1#$B/}\" || ko \"$1\"; }" dans s
  inserer "echo '== Bibliothèques et modules'" dans s
  inserer "L=$(mktemp)" dans s
  inserer "find \"$B/Contents\" -type f '(' -name '*.dylib' -o -name '*.so' ')' > \"$L\"" dans s
  inserer "while read -r f; do signe \"$f\"; done < \"$L\"; rm -f \"$L\"" dans s
  inserer "echo '== Cadres (frameworks)'" dans s
  inserer "for f in \"$B\"/Contents/Frameworks/*.framework; do [ -d \"$f\" ] && signe \"$f\"; done" dans s
  inserer "echo '== Assistants'" dans s
  inserer "for f in \"$B\"/Contents/Helpers/* \"$B\"/Contents/MacOS/*; do" dans s
  inserer "  [ -f \"$f\" ] && [ \"$(basename \"$f\")\" != " + Q(a.exe) + " ] && signe \"$f\"" dans s
  inserer "done" dans s
  inserer "echo '== Paquet'" dans s
  si taille(droits) > 0
    inserer "codesign --force --options runtime --timestamp --entitlements \"$ENT\" --sign \"$ID\" \"$B\" || ko 'paquet'" dans s
  sinon
    inserer "codesign --force --options runtime --timestamp --sign \"$ID\" \"$B\" || ko 'paquet'" dans s
  finsi
  inserer "echo '== Vérification'" dans s
  inserer "codesign --verify --deep --strict --verbose=2 \"$B\" || ko 'vérification'" dans s
  inserer "codesign -d --entitlements - \"$B\" 2>/dev/null" dans s
  inserer "if [ $ECHECS -eq 0 ]; then echo 'TERMINÉ sans erreur'; else echo \"TERMINÉ avec $ECHECS erreur(s)\"; fi" dans s
  inserer "exit $ECHECS" dans s
retourner joindre(s, car(10)) + car(10)

&& notarisation (service d'Apple) puis agrafage du ticket dans le paquet
fonction SCRIPT_NOTARISATION(a, profil)
  locale s = {}
  inserer "#!/bin/sh" dans s
  inserer "# Notarisation — " + a.nom + " — " + maintenant() dans s
  inserer "B=" + Q(a.bundle) dans s
  inserer "Z=$(mktemp -d)/" + Q(remplacertexte(a.nom, ".app", "") + ".zip") dans s
  inserer "echo '== Archive'" dans s
  inserer "ditto -c -k --keepParent \"$B\" \"$Z\" || exit 1" dans s
  inserer "echo '== Envoi à Apple (quelques minutes)'" dans s
  inserer "xcrun notarytool submit \"$Z\" --keychain-profile " + Q(profil) + " --wait || { echo 'ÉCHEC : notarisation (xcrun notarytool log <id> --keychain-profile … pour le détail)'; exit 1; }" dans s
  inserer "echo '== Agrafage du ticket'" dans s
  inserer "xcrun stapler staple \"$B\" || exit 1" dans s
  inserer "echo '== Évaluation Gatekeeper'" dans s
  inserer "spctl --assess --type execute --verbose \"$B\"" dans s
  inserer "rm -f \"$Z\"" dans s
  inserer "echo 'TERMINÉ'" dans s
retourner joindre(s, car(10)) + car(10)

&& commande à lancer une fois dans le Terminal : enregistre l'identifiant Apple, l'équipe et
&& un mot de passe d'application dans le trousseau, sous le nom de profil choisi
fonction COMMANDE_PROFIL(profil, equipe)
retourner "xcrun notarytool store-credentials " + Q(profil) + " --apple-id <votre identifiant Apple> --team-id " + ;
          sisinon(equipe = "", "<EQUIPE>", equipe) + " --password <mot de passe pour application>"
