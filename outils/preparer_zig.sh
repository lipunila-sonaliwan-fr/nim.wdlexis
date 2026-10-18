#!/bin/sh
# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdlexis+ : installe Zig 0.17.0 (officiel, ziglang.org) pour un hôte dans
# linZG/, macZG/ ou winZG/ (<arch>/zig + lib/), avec contrôle SHA-256.
#
#   outils/preparer_zig.sh                    hôte courant
#   outils/preparer_zig.sh aarch64-linux      x86_64-linux aarch64-linux x86_64-macos
#                                             aarch64-macos x86_64-windows aarch64-windows
#
# Nécessite curl (ou wget), tar, et unzip pour les hôtes Windows.
set -e
VERSION=0.17.0
HERE="$(cd "$(dirname "$0")/.." && pwd)"

host="$1"
if [ -z "$host" ]; then
  case "$(uname -m)" in
    x86_64|amd64) a=x86_64 ;;
    arm64|aarch64) a=aarch64 ;;
    *) echo "architecture non prise en charge : $(uname -m)" >&2; exit 1 ;;
  esac
  case "$(uname -s)" in
    Darwin) host=$a-macos ;;
    Linux) host=$a-linux ;;
    MINGW*|MSYS*|CYGWIN*) host=$a-windows ;;
    *) echo "système non pris en charge : $(uname -s)" >&2; exit 1 ;;
  esac
fi

case "$host" in
  x86_64-linux)    sum=1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026; dir=linZG; ext=tar.xz ;;
  aarch64-linux)   sum=9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8; dir=linZG; ext=tar.xz ;;
  x86_64-macos)    sum=4f9a1c5269aa17ebda5e6d3c2b89d6cbf36f7d2b22a0306e9ab98f25f95529c6; dir=macZG; ext=tar.xz ;;
  aarch64-macos)   sum=b607e9b9234790a008116ae5bdb71c6243b84b9fb42a53a9e70fde41c06c536a; dir=macZG; ext=tar.xz ;;
  x86_64-windows)  sum=b5663f69581dcf391293fbf16c06cb80d81d806545ce618b4d0bab7f0eb8c428; dir=winZG; ext=zip ;;
  aarch64-windows) sum=0a59d91fa1cb40cf068e9b0954434ce973500c7a2ea749f1e01af62cdab52d26; dir=winZG; ext=zip ;;
  *) echo "hôte inconnu : $host" >&2; exit 1 ;;
esac
arch=${host%%-*}
name=zig-$host-$VERSION
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
url=https://ziglang.org/download/$VERSION/$name.$ext
echo "Téléchargement : $url"
if command -v curl >/dev/null 2>&1; then curl -fL -o "$tmp/$name.$ext" "$url"
else wget -O "$tmp/$name.$ext" "$url"; fi
if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$tmp/$name.$ext" | cut -d' ' -f1)
else got=$(shasum -a 256 "$tmp/$name.$ext" | cut -d' ' -f1); fi
[ "$got" = "$sum" ] || { echo "empreinte SHA-256 incorrecte : $got" >&2; exit 1; }
echo "Empreinte SHA-256 vérifiée."
cd "$tmp"
if [ "$ext" = zip ]; then unzip -q "$name.zip"; else tar xf "$name.tar.xz"; fi
mkdir -p "$HERE/$dir/$arch"
exe=zig; [ "$ext" = zip ] && exe=zig.exe
cp "$name/$exe" "$HERE/$dir/$arch/$exe"
chmod +x "$HERE/$dir/$arch/$exe"
cp "$name/LICENSE" "$HERE/$dir/LICENSE"
if [ ! -f "$HERE/$dir/lib/std/std.zig" ]; then
  rm -rf "$HERE/$dir/lib"
  cp -R "$name/lib" "$HERE/$dir/lib"
  sh "$HERE/outils/elaguer_zig.sh" "$HERE/$dir/lib"
fi
[ "$(uname -s)" = Darwin ] && xattr -dr com.apple.quarantine "$HERE/$dir" 2>/dev/null || true
echo "Zig $VERSION installé : $dir/$arch/$exe"
