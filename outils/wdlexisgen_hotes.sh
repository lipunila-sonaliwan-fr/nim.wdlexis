#!/bin/sh
# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdlexis+ : compile l'outil wdlexisgen pour tous les hôtes (Linux, macOS, Windows ;
# x64 et arm64) depuis un seul poste, avec Nim et le compilateur C de Zig.
# Résultat : gen/<système>-<arch>/wdlexisgen[.exe], à placer dans la chaîne de génération
# (Contents/Resources/gen d'un paquet macOS, ou gen/ à côté de l'atelier) : une application
# générée avec la chaîne (atelier) peut alors générer à son tour, sur chacun de ces systèmes.
#
#   outils/wdlexisgen_hotes.sh [zig] [cibles…]
#   ex. : outils/wdlexisgen_hotes.sh zig/macos-arm64/zig linux-x64 linux-arm64 windows-x64 macos-x64
#
# wdlexisgen n'utilise que la bibliothèque standard de Nim (pas d'interface) : la
# compilation croisée par « zig cc » suffit. Les binaires macOS produits hors d'un Mac
# sont à signer sur un Mac (outils/signer_macos.sh).
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ZIG="${1:-zig}"
[ $# -gt 0 ] && shift
CIBLES="${*:-linux-x64 linux-arm64 macos-x64 macos-arm64 windows-x64 windows-arm64}"
command -v "$ZIG" >/dev/null 2>&1 || [ -x "$ZIG" ] || { echo "Zig introuvable : $ZIG" >&2; exit 1; }
OUT="$HERE/gen"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for c in $CIBLES; do
  case "$c" in
    linux-x64)     OS=linux;   CPU=amd64; TRIPLE=x86_64-linux-gnu.2.28 ;;
    linux-arm64)   OS=linux;   CPU=arm64; TRIPLE=aarch64-linux-gnu.2.28 ;;
    macos-x64)     OS=macosx;  CPU=amd64; TRIPLE=x86_64-macos.11.0 ;;
    macos-arm64)   OS=macosx;  CPU=arm64; TRIPLE=aarch64-macos.11.0 ;;
    windows-x64)   OS=windows; CPU=amd64; TRIPLE=x86_64-windows-gnu ;;
    windows-arm64) OS=windows; CPU=arm64; TRIPLE=aarch64-windows-gnu ;;
    *) echo "cible inconnue : $c" >&2; exit 1 ;;
  esac
  W="$TMP/zigcc-$c"
  printf '#!/bin/sh\nexec "%s" cc -target %s "$@"\n' "$ZIG" "$TRIPLE" > "$W"
  chmod +x "$W"
  EXE=wdlexisgen; [ "$OS" = windows ] && EXE=wdlexisgen.exe
  mkdir -p "$OUT/$c"
  echo "== $c ($TRIPLE)"
  nim c -d:release --hints:off --os:$OS --cpu:$CPU --cc:clang \
      --clang.exe="$W" --clang.linkerexe="$W" \
      --nimcache:"$TMP/cache-$c" -o:"$OUT/$c/$EXE" "$HERE/src/wdlexisgen.nim"
  file "$OUT/$c/$EXE" 2>/dev/null | cut -d: -f2
done
echo "Outils : $OUT"
