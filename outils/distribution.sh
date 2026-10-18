#!/bin/sh
# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdlexis+ : construit l'archive de distribution wdlexis+ + Zig (un seul .zip).
#
#   outils/distribution.sh [--sans-rtc]
#
# 1. régénère rtc/ (runtime C des applications) avec Nim, sauf --sans-rtc ;
# 2. vérifie la présence de Zig pour les hôtes (linZG, macZG, winZG) :
#    outils/preparer_zig.sh <hôte> pour en ajouter ;
# 3. crée ../wdlexis-<version>.zip (sans les fichiers de compilation).
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
VERSION=$(sed -n 's/^version *= *"\(.*\)"/\1/p' wdlexis.nimble)
if [ "$1" != "--sans-rtc" ]; then
  nim r --hints:off outils/rtc.nim
fi
for d in linZG macZG winZG; do
  if ls "$d"/*/zig* >/dev/null 2>&1; then echo "Zig : $(ls -d "$d"/*/ | tr '\n' ' ')"
  else echo "attention : aucun Zig dans $d (outils/preparer_zig.sh)" >&2; fi
done
NAME=wdlexis-$VERSION
OUT="$HERE/../$NAME.zip"
rm -f "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ln -s "$HERE" "$TMP/$NAME"
cd "$TMP"
zip -r -9 -q "$OUT" "$NAME/" \
  -x "$NAME/.git/*" "$NAME/wdlexis+" "$NAME/wdlexis+.exe" "$NAME/wdlexisgen" "$NAME/wdlexisgen.exe" \
     "$NAME/src/wdlexisrt" "$NAME/src/wdlexisrt.exe" "$NAME/tests/t_langage" "$NAME/tests/t_webview" \
     "*/.DS_Store" "*/__MACOSX/*" "*/distribution/*" "*/.wdlexis/*"
echo "Distribution : $OUT ($(du -h "$OUT" | cut -f1))"
