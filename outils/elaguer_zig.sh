#!/bin/sh
# wdlexis+ : allège le dossier lib/ d'une distribution de Zig pour la seule
# compilation C vers Linux, macOS et Windows (x86_64 et aarch64).
# Usage : outils/elaguer_zig.sh <dossier lib de Zig>
set -e
L="$1"
[ -f "$L/std/std.zig" ] || { echo "dossier lib de Zig attendu : $L" >&2; exit 1; }
# C++ et sanitizers (inutiles : le runtime est en C)
rm -rf "$L/libcxx" "$L/libcxxabi" "$L/libtsan" "$L/docs"
# systèmes non ciblés : BSD, WASI
rm -rf "$L/libc/freebsd" "$L/libc/netbsd" "$L/libc/openbsd" "$L/libc/wasi"
# en-têtes C : seuls x86, x86_64, aarch64, génériques glibc / musl et « any-* » restent
for d in "$L"/libc/include/*; do
  n=$(basename "$d")
  case "$n" in
    *freebsd*|*netbsd*|*openbsd*|*wasi*) rm -rf "$d" ;;
    x86-*|x86_64-*|aarch64-*|generic-glibc|generic-musl|any-*) ;;
    *) rm -rf "$d" ;;
  esac
done
echo "lib de Zig allégée : $(du -sh "$L" | cut -f1)"
