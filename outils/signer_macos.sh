#!/bin/sh
# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdlexis+ : signature Developer ID, notarisation et agrafage d'une application macOS
# (wdlexis+.app, atelier.app ou toute application générée), de l'intérieur vers l'extérieur.
#
#   outils/signer_macos.sh MonApp.app ["Developer ID Application: Nom (EQUIPE)"] [profil]
#
#   identité : 2e argument, ou variable SIGN_ID (security find-identity -v -p codesigning)
#   profil   : 3e argument, ou NOTARY_PROFILE (xcrun notarytool store-credentials), défaut « notarisation »
#   SANS_NOTARISATION=1 : signer seulement
#
# Tous les fichiers Mach-O du paquet sont signés (hardened runtime, horodatage), y compris
# ceux de Contents/Resources (Zig, bibliothèques de la chaîne) ; les binaires Linux et
# Windows de la chaîne sont des données, couvertes par le sceau du paquet. Droits : ceux
# de Lexis+ (bibliothèques d'autres éditeurs : extensions DuckDB…).
set -e
APP="${1%/}"
ID="${2:-$SIGN_ID}"
PROFIL="${3:-${NOTARY_PROFILE:-notarisation}}"
[ -d "$APP/Contents/MacOS" ] || { echo "usage : $0 MonApp.app [identité] [profil]" >&2; exit 1; }
[ -n "$ID" ] || { echo "identité Developer ID attendue (2e argument ou SIGN_ID) :" >&2
                  security find-identity -v -p codesigning >&2; exit 1; }
NOM="$(basename "$APP" .app)"
MAIN="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== Contrôles"
# l'identité doit figurer parmi les identités VALIDES (chaîne de confiance complète)
if ! security find-identity -v -p codesigning | grep -qF "\"$ID\""; then
  echo "L'identité « $ID » n'est pas une identité de signature valide." >&2
  echo "Identités valides :" >&2; security find-identity -v -p codesigning >&2
  echo "Cause habituelle : certificat intermédiaire « Developer ID Certification Authority » (G2) absent," >&2
  echo "ou réglage de confiance modifié à la main. Voir DISTRIBUER_MACOS.md, « Dépannage »." >&2
  exit 1
fi
# « Toujours approuver » posé à la main sur un certificat Apple / Developer ID : codesign
# ne remonte plus jusqu'à la racine (unable to build chain … errSecInternalComponent)
FORCES=$(security dump-trust-settings 2>/dev/null | sed -n 's/^Cert [0-9]*: //p' | grep -E "^(Developer ID|Apple )" || true)
if [ -n "$FORCES" ]; then
  echo "Réglages de confiance personnalisés sur des certificats Apple (à remettre par défaut) :" >&2
  echo "$FORCES" | sed 's/^/   - /' >&2
  echo "→ Trousseau d'accès, chaque certificat > Se fier > « Utiliser les réglages par défaut du système »" >&2
  echo "  (ou security remove-trusted-cert <cert.pem>). Voir DISTRIBUER_MACOS.md, « Dépannage »." >&2
  exit 1
fi
# essai de signature sur une copie de /usr/bin/true (horodatage : connexion Internet nécessaire)
cp /usr/bin/true "$TMP/essai"
if ! codesign --force --options runtime --timestamp --sign "$ID" "$TMP/essai" 2> "$TMP/essai.txt"; then
  cat "$TMP/essai.txt" >&2
  grep -q "unable to build chain" "$TMP/essai.txt" && \
    echo "→ certificat intermédiaire manquant : importer DeveloperIDG2CA.cer (www.apple.com/certificateauthority)" >&2
  grep -q "errSecInternalComponent" "$TMP/essai.txt" && \
    echo "→ si la chaîne est complète : trousseau verrouillé (security unlock-keychain login.keychain-db), session SSH ou sudo" >&2
  exit 1
fi
echo "  identité valide, essai de signature réussi"
plutil -lint "$APP/Contents/Info.plist"
AUTRES=0
for f in "$APP/Contents/MacOS"/*; do
  file -b "$f" | grep -q "Mach-O" || { echo "  ⚠ Contents/MacOS/$(basename "$f") n'est pas un exécutable"; AUTRES=1; }
done
[ "$AUTRES" = 0 ] || { echo "Contents/MacOS doit ne contenir que des exécutables : outils/reorganiser_app.sh \"$APP\"" >&2; exit 1; }
find "$APP" -name .DS_Store -delete
xattr -cr "$APP"

echo "== Binaires Mach-O imbriqués"
find "$APP/Contents" -type f ! -path "$APP/Contents/MacOS/$MAIN" -print0 |
  xargs -0 file -N -F '|' | grep "Mach-O" | cut -d'|' -f1 |
  awk -F/ '{ print NF "\t" $0 }' | sort -rn | cut -f2- > "$TMP/macho.txt"
echo "  $(wc -l < "$TMP/macho.txt" | tr -d ' ') fichier(s)"
while IFS= read -r f; do
  codesign --force --options runtime --timestamp --sign "$ID" "$f" >/dev/null
  echo "  signé : ${f#$APP/}"
done < "$TMP/macho.txt"

echo "== Paquet"
cat > "$TMP/lexis.entitlements" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict>
</plist>
EOF
codesign --force --options runtime --timestamp --entitlements "$TMP/lexis.entitlements" --sign "$ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

[ "${SANS_NOTARISATION:-0}" = 1 ] && { echo "Signé (notarisation non demandée)."; exit 0; }

echo "== Notarisation (envoi à Apple ; plusieurs minutes pour un gros paquet)"
ditto -c -k --keepParent "$APP" "$TMP/$NOM.zip"
xcrun notarytool submit "$TMP/$NOM.zip" --keychain-profile "$PROFIL" --wait | tee "$TMP/notary.txt"
grep -q "status: Accepted" "$TMP/notary.txt" || {
  ID_ENVOI=$(sed -n 's/^ *id: //p' "$TMP/notary.txt" | head -1)
  echo "Refusée : xcrun notarytool log $ID_ENVOI --keychain-profile \"$PROFIL\"" >&2; exit 1; }

echo "== Agrafage et évaluation"
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=4 "$APP"
DEST="$(dirname "$APP")/$NOM-macos.zip"
rm -f "$DEST"
ditto -c -k --keepParent "$APP" "$DEST"
echo "Prêt à distribuer : $DEST"
