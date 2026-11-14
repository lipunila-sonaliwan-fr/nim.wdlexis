#!/bin/sh
# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# Crée « wdlexis+.app » à la racine du dépôt : l'atelier se lance par double-clic
# depuis le Finder (ou le Dock / Launchpad), sans fenêtre de Terminal.
#
#   sh outils/app_macos.sh            (après avoir compilé ./wdlexis+)
#
# Le paquet contient l'exécutable (Contents/MacOS) ; ses ressources (Contents/Resources)
# sont des liens vers macOS/ et ttf/ du dépôt : une recompilation suivie de ce script
# met l'application à jour.
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
EXE="$ROOT/wdlexis+"
[ -x "$EXE" ] || { echo "Compilez d'abord ./wdlexis+ (nim c ... -o:wdlexis+ src/wdlexis.nim)"; exit 1; }
APP="$ROOT/wdlexis+.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXE" "$APP/Contents/MacOS/wdlexis+"
ln -s "$ROOT/macOS" "$APP/Contents/Resources/macOS"
ln -s "$ROOT/ttf" "$APP/Contents/Resources/ttf"
# icône .icns à partir de src/ressources/wdlexis.png (outils macOS sips / iconutil)
ICON=""
if [ -f src/ressources/wdlexis.png ] && command -v iconutil >/dev/null; then
  SET="$(mktemp -d)/wdlexis.iconset"
  mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s src/ressources/wdlexis.png --out "$SET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d src/ressources/wdlexis.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$APP/Contents/Resources/wdlexis.icns" && ICON="<key>CFBundleIconFile</key><string>wdlexis.icns</string>"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>wdlexis+</string>
  <key>CFBundleDisplayName</key><string>wdlexis+</string>
  <key>CFBundleExecutable</key><string>wdlexis+</string>
  <key>CFBundleIdentifier</key><string>fr.sonaliwan.wdlexis</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.9.6/string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  $ICON
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"
# signature locale (évite le refus « application endommagée » sur Apple Silicon)
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
echo "Créé : $APP"
