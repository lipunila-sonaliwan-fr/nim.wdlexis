#!/bin/sh
# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdlexis+ : réorganise un paquet macOS qui embarque la chaîne de génération (atelier.app,
# wdlexis+.app) pour qu'il puisse être signé Developer ID et notarisé :
#   - Contents/MacOS ne garde que des exécutables Mach-O (atelier, wdlexisgen, wdlexisrt) ;
#   - les données passent dans Contents/Resources (règle d'Apple pour la signature) ;
#   - Zig : une seule bibliothèque zig/lib pour tous les hôtes, un exécutable par hôte
#     (zig/<système>-<arch>/), au lieu de trois copies identiques (linZG, macZG, winZG) ;
#   - gen/<système>-<arch>/wdlexisgen : l'outil de génération de chaque hôte, copié dans
#     les applications générées avec la chaîne (l'atelier généré pour Windows génère à son tour) ;
#   - suppression de ce qui ne sert pas à l'exécution (.DS_Store, outils/ de construction,
#     doublons ttf/ et macOS/, lisezmoi de Zig).
#
#   outils/reorganiser_app.sh atelier.app [--gen dossier] [--sans-wdlexisrt]
#
#   --gen dossier      dossier contenant <système>-<arch>/wdlexisgen[.exe] (outils/wdlexisgen_hotes.sh)
#   --sans-wdlexisrt   retire l'interpréteur en ligne de commande (inutile à l'atelier)
set -e
APP="${1%/}"
[ -d "$APP/Contents/MacOS" ] || { echo "usage : $0 MonApp.app [--gen dossier] [--sans-wdlexisrt]" >&2; exit 1; }
shift
GEN=""
SANS_RT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --gen) GEN="$2"; shift 2 ;;
    --sans-wdlexisrt) SANS_RT=1; shift ;;
    *) echo "option inconnue : $1" >&2; exit 1 ;;
  esac
done
M="$APP/Contents/MacOS"
R="$APP/Contents/Resources"
mkdir -p "$R"
nb() { find "$1" -type f 2>/dev/null | wc -l | tr -d ' '; }
echo "Avant : $(nb "$APP") fichiers, $(du -sh "$APP" | cut -f1)"

# 1. Zig : bibliothèque unique + un exécutable par hôte
mkdir -p "$R/zig"
for Z in macZG linZG winZG; do
  if [ -d "$M/$Z/lib" ] && [ ! -d "$R/zig/lib" ]; then mv "$M/$Z/lib" "$R/zig/lib"; fi
done
deplace_zig() {   # $1 source, $2 cible (linux-x64…)
  if [ -f "$1" ]; then mkdir -p "$R/zig/$2"; mv "$1" "$R/zig/$2/"; chmod +x "$R/zig/$2/"*; echo "  zig/$2"; fi
}
echo "Zig :"
deplace_zig "$M/macZG/aarch64/zig"      macos-arm64
deplace_zig "$M/macZG/x86_64/zig"       macos-x64
deplace_zig "$M/linZG/x86_64/zig"       linux-x64
deplace_zig "$M/linZG/aarch64/zig"      linux-arm64
deplace_zig "$M/winZG/x86_64/zig.exe"   windows-x64
deplace_zig "$M/winZG/aarch64/zig.exe"  windows-arm64
[ -f "$M/macZG/LICENSE" ] && mv "$M/macZG/LICENSE" "$R/zig/LICENSE"
rm -rf "$M/macZG" "$M/linZG" "$M/winZG"

# 2. données de la chaîne : MacOS -> Resources (sans écraser ce qui y est déjà)
fusionne() {      # $1 nom de dossier
  if [ -d "$M/$1" ]; then
    if [ -d "$R/$1" ]; then cp -Rn "$M/$1/." "$R/$1/" 2>/dev/null || true; rm -rf "$M/$1"
    else mv "$M/$1" "$R/$1"; fi
  fi
}
for d in rtc linOS macOS winOS ttf LICENCES models; do fusionne "$d"; done
for f in "$M"/*.dll "$M"/*.so "$M"/*.dylib "$M/LICENCE.md"; do
  [ -f "$f" ] && mv "$f" "$R/"
done

# 3. outils de génération par hôte
mkdir -p "$R/gen"
if [ -f "$M/wdlexisgen" ]; then
  H="macos-$(file -b "$M/wdlexisgen" | grep -q arm64 && echo arm64 || echo x64)"
  mkdir -p "$R/gen/$H"; cp -p "$M/wdlexisgen" "$R/gen/$H/wdlexisgen"
fi
if [ -n "$GEN" ]; then
  for d in "$GEN"/*/; do
    [ -d "$d" ] && mkdir -p "$R/gen/$(basename "$d")" && cp -p "$d"* "$R/gen/$(basename "$d")/"
  done
fi

# 4. ce qui ne sert pas à l'exécution
rm -rf "$M/outils"
find "$APP" -name .DS_Store -delete
find "$APP" -name "LISEZMOI.txt" -path "*ZG*" -delete 2>/dev/null || true
[ -f "$M/wdlexis+.png" ] && { [ -f "$R/wdlexis+.png" ] && rm "$M/wdlexis+.png" || mv "$M/wdlexis+.png" "$R/"; }
[ "$SANS_RT" = 1 ] && rm -f "$M/wdlexisrt"
rm -rf "$APP/Contents/_CodeSignature"      # refaite à la signature

# 5. contrôle : Contents/MacOS ne doit contenir que des exécutables Mach-O
echo "Contents/MacOS :"
for f in "$M"/*; do
  if file -b "$f" | grep -q "Mach-O"; then echo "  ✓ $(basename "$f")"
  else echo "  ⚠ $(basename "$f") n'est pas un exécutable : à déplacer dans Contents/Resources"; fi
done
echo "Outils de génération présents (gen/) : $(ls "$R/gen" | tr '\n' ' ')"
for h in linux-x64 linux-arm64 macos-arm64 macos-x64 windows-x64 windows-arm64; do
  [ -d "$R/zig/$h" ] || echo "  (pas de Zig pour $h)"
  [ -d "$R/gen/$h" ] || echo "  (pas de wdlexisgen pour $h : un atelier généré pour $h ne pourra pas générer)"
done
echo "Après : $(nb "$APP") fichiers, $(du -sh "$APP" | cut -f1)"
