#!/bin/sh
# CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
# wdlexis+ - construit la bibliothèque du paquet lucene (wdlexis_lucene) :
# Lucene++ (https://github.com/luceneplusplus/LucenePlusPlus) et les parties de
# Boost dont il a besoin, liés statiquement dans une seule bibliothèque partagée
# placée dans linOS/ (Linux), macOS/ (macOS) ou winOS/ (Windows, shell MSYS2
# MINGW64, ou Git Bash avec MinGW-w64 : gcc, git).
#
#   sh outils/lucenepp.sh [dossier_de_travail]
#
# Prérequis : git, un compilateur C/C++17 (ni cmake ni make) ; accès à GitHub pour cloner
# zlib, Boost et Lucene++ (ou dossiers déjà présents dans le dossier de travail :
# zlib/, boost/, LucenePlusPlus/). Durée : 10 à 30 minutes.
set -e

RACINE=$(cd "$(dirname "$0")/.." && pwd)
TRAVAIL=${1:-"$RACINE/.lucenepp"}
BOOST_TAG=${BOOST_TAG:-boost-1.86.0}
LPP_TAG=${LPP_TAG:-master}
JOBS=${JOBS:-$( (nproc || sysctl -n hw.ncpu || echo 2) 2>/dev/null)}

case "$(uname -s)" in
  Linux*)  OSDIR=linOS; LIB=libwdlexis_lucene.so ;;
  Darwin*) OSDIR=macOS; LIB=libwdlexis_lucene.dylib ;;
  MINGW*|MSYS*) OSDIR=winOS; LIB=wdlexis_lucene.dll ;;
  *) echo "système non pris en charge : $(uname -s)"; exit 1 ;;
esac

mkdir -p "$TRAVAIL"
cd "$TRAVAIL"

if [ "$OSDIR" = winOS ]; then          # MinGW-w64 : gcc (cc ou c++ peuvent désigner un autre compilateur)
  # noms courts : le chemin complet (« C:\Program Files\... ») contient souvent une espace
  CC=${CC:-gcc}
  CXX=${CXX:-g++}
  # b2 : pas de manifeste embarqué ; windres échoue quand MinGW est installé dans un
  # dossier dont le nom contient une espace (« 'C:\Program' n'est pas reconnu... »)
  export B2_DONT_EMBED_MANIFEST=1
else
  CC=${CC:-$(command -v cc || command -v gcc || command -v clang)}
  CXX=${CXX:-$(command -v c++ || command -v g++ || command -v clang++)}
fi

# 0. zlib, compilée ici en bibliothèque statique : certaines installations
#    (MinGW-w64 seul sous Windows notamment) n'en fournissent pas.
ZLIB_TAG=${ZLIB_TAG:-v1.3.1}
if [ ! -f zlib-inst/lib/libz.a ]; then
  [ -d zlib ] || git -c core.autocrlf=false clone --depth 1 --branch "$ZLIB_TAG" https://github.com/madler/zlib.git zlib
  mkdir -p zlib-inst/lib zlib-inst/include zlib-obj
  for f in adler32 compress crc32 deflate gzclose gzlib gzread gzwrite infback inffast inflate inftrees \
           trees uncompr zutil; do
    "$CC" -O2 -fPIC -w -c "zlib/$f.c" -o "zlib-obj/$f.o"
  done
  ar rcs zlib-inst/lib/libz.a zlib-obj/*.o
  cp zlib/zlib.h zlib/zconf.h zlib-inst/include/
fi
ZLIB="$TRAVAIL/zlib-inst/lib/libz.a"

# Même compilateur partout : sous Windows, b2 (ou cc, c++) peuvent sinon choisir
# Visual C++ ou clang (bibliothèques incompatibles avec MinGW : à l'édition de
# liens, tous les symboles de Lucene++ sont « undefined reference »).
case "$OSDIR" in
  winOS) B2TOOL=gcc ;;
  macOS) B2TOOL=clang ;;
  *)     B2TOOL=gcc; "$CXX" --version 2>/dev/null | grep -qi clang && B2TOOL=clang ;;
esac
OUTIL="$("$CXX" -dumpmachine 2>/dev/null) $("$CXX" -dumpversion 2>/dev/null) $(command -v "$CXX")"
echo "compilateur : $OUTIL"

# Chemin pour un programme Windows natif (b2.exe) : C:/... plutôt que /c/...
natif() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }

# Une bibliothèque statique contient-elle ce symbole (compilée par ce compilateur) ?
contient() { [ -f "$1" ] && nm "$1" 2>/dev/null | grep -q "$2"; }

# 1. Boost (date_time, filesystem, iostreams, regex, thread et dépendances), statique
#    iostreams doit contenir la compression zlib (utilisée par Lucene++) : b2 compile
#    zlib depuis les sources de l'étape 0 (ZLIB_SOURCE), sans détection par édition de liens.
BOOST_FS=$(ls boost-inst/lib/libboost_filesystem*.a 2>/dev/null | head -1)
BOOST_IO=$(ls boost-inst/lib/libboost_iostreams*.a 2>/dev/null | head -1)
if ! contient "$BOOST_FS" "ZN5boost10filesystem" || ! contient "$BOOST_IO" "zlib_base"; then
  if [ "$(cat boost-inst/.compilateur 2>/dev/null)" != "$OUTIL" ] && ! contient "$BOOST_FS" "ZN5boost10filesystem"; then
    rm -rf boost/bin.v2                   # objets d'un autre compilateur
  fi
  rm -rf boost-inst
  # clone incomplet (interrompu) : on recommence
  if [ -d boost ] && { [ ! -f boost/bootstrap.sh ] || [ ! -d boost/tools/build/src/engine ] || \
                       [ ! -f boost/libs/filesystem/include/boost/filesystem.hpp ]; }; then
    echo "dossier boost incomplet : nouveau clonage"
    rm -rf boost
  fi
  [ -d boost ] || git -c core.autocrlf=false clone --depth 1 --branch "$BOOST_TAG" --recurse-submodules \
                    --shallow-submodules -j 8 https://github.com/boostorg/boost.git boost
  # scripts extraits avec des fins de ligne Windows (git core.autocrlf=true) : sh ne peut pas les exécuter
  for f in boost/bootstrap.sh $(find boost/tools/build -name "*.sh" 2>/dev/null); do
    if grep -q "$(printf '\r')" "$f" 2>/dev/null; then
      tr -d '\r' < "$f" > "$f.lf" && mv "$f.lf" "$f"
    fi
  done
  ( cd boost
    sh ./bootstrap.sh --with-toolset="$B2TOOL" \
                      --with-libraries=date_time,filesystem,iostreams,regex,thread,system,chrono,atomic
    ./b2 -j"$JOBS" headers
    ./b2 -j"$JOBS" toolset="$B2TOOL" --layout=system link=static runtime-link=shared threading=multi \
         variant=release address-model=64 cxxflags=-fPIC cflags=-fPIC -sNO_BZIP2=1 -sNO_LZMA=1 -sNO_ZSTD=1 \
         -sZLIB_SOURCE="$(natif "$TRAVAIL/zlib")" \
         --prefix="$(natif "$TRAVAIL/boost-inst")" install )
  if ! contient "$(ls boost-inst/lib/libboost_iostreams*.a 2>/dev/null | head -1)" "zlib_base"; then
    echo "Boost.Iostreams a été construit sans zlib (voir la sortie de b2 : « zlib : no »)"
    exit 1
  fi
fi
echo "$OUTIL" > boost-inst/.compilateur

# 2. Lucene++ : bibliothèques statiques compilées directement (sans cmake ni make),
#    avec les réglages de son CMakeLists (C++17, LPP_BUILDING_LIB, visibilité masquée).
LPPB="$TRAVAIL/lpp-build"
LPP_CORE="$LPPB/liblucene++.a"
LPP_CONTRIB="$LPPB/liblucene++-contrib.a"
if ! contient "$LPP_CORE" "ZN6Lucene11StringUtils6toUTF8" || \
   ! contient "$LPP_CONTRIB" "ZN6Lucene14FrenchAnalyzer"; then
  [ -d LucenePlusPlus ] || git -c core.autocrlf=false clone --depth 1 --branch "$LPP_TAG" \
                             https://github.com/luceneplusplus/LucenePlusPlus.git
  # bibliothèques d'un autre compilateur : tout recompiler ; sinon on reprend où l'on s'était arrêté
  { [ -f "$LPP_CORE" ] || [ -f "$LPP_CONTRIB" ] || [ "$(cat "$LPPB/.compilateur" 2>/dev/null)" != "$OUTIL" ]; } && \
    rm -rf "$LPPB"
  mkdir -p "$LPPB/include" "$LPPB/core" "$LPPB/contrib"
  echo "$OUTIL" > "$LPPB/.compilateur"
  sed 's/#@USE_BOOST_INTEGER@/#undef/; s/#@LPP_SHARED_DLL@/#undef/; s/#@USE_CYCLIC_CHECK@/#undef/' \
      LucenePlusPlus/include/config_h/Config.h.in > "$LPPB/include/Config.h"
  L="$TRAVAIL/LucenePlusPlus"
  WINDEF=""
  [ "$OSDIR" = winOS ] && WINDEF="-DWIN32_LEAN_AND_MEAN -DNOMINMAX"
  export CC CXX
  export LPP_INC="-I$LPPB/include -I$L/include/lucene++ -I$L/src/core/include -I$L/src/contrib/include \
-I$L/src/contrib/snowball/libstemmer_c/include -I$TRAVAIL/boost-inst/include -I$TRAVAIL/zlib-inst/include"
  # NDEBUG : comme une construction Release (sinon, sous Windows, LuceneAllocator.cpp
  # appelle _malloc_dbg, propre à Visual C++)
  export LPP_FLAGS="-O2 -DNDEBUG -fPIC -w -fvisibility=hidden -DLPP_BUILDING_LIB $WINDEF"
  # archive des objets d'un dossier, par lots (la ligne de commande est limitée sous Windows)
  archiver() {
    rm -f "$1"
    ( cd "$2" && ls *.o | xargs -n 200 ar qc "$1" ) && ar s "$1"
  }
  # compile une source (chemin relatif à $L/src) dans le dossier objet $1
  compiler() {
    dest="$1"; shift
    # find appelé par le shell (via xargs, Windows pourrait lancer son propre find.exe)
    ( cd "$L/src" && for d in "$@"; do
        if [ -e "$d" ]; then find "$d" -type f \( -name "*.cpp" -o -name "*.c" \) -print; fi
      done ) | \
    xargs -P "$JOBS" -I % sh -c '
      f="%"; o="'"$dest"'/$(echo "$f" | tr "/." "__").o"
      [ -f "$o" ] && [ "$o" -nt "'"$L"'/src/$f" ] && exit 0
      case "$f" in
        *.cpp) $CXX -std=c++17 -fvisibility-inlines-hidden $LPP_FLAGS $LPP_INC -c "'"$L"'/src/$f" -o "$o" ;;
        *)     $CC $LPP_FLAGS $LPP_INC -c "'"$L"'/src/$f" -o "$o" ;;
      esac || { echo "échec : $f"; exit 255; }'
  }
  echo "compilation de Lucene++ (core)..."
  compiler "$LPPB/core" core/search core/analysis core/document core/index core/queryparser core/store core/util
  ls "$LPPB"/core/*.o >/dev/null 2>&1 || { echo "aucune source de Lucene++ compilée (find ?)"; exit 1; }
  archiver "$LPP_CORE" "$LPPB/core"
  echo "compilation de Lucene++ (contrib)..."
  compiler "$LPPB/contrib" contrib/analyzers contrib/highlighter contrib/memory contrib/index contrib/mevc \
           contrib/snowball/SnowballAnalyzer.cpp contrib/snowball/SnowballFilter.cpp \
           contrib/snowball/libstemmer_c/libstemmer/libstemmer_utf8.c \
           contrib/snowball/libstemmer_c/src_c contrib/snowball/libstemmer_c/runtime
  archiver "$LPP_CONTRIB" "$LPPB/contrib"
  if ! contient "$LPP_CORE" "ZN6Lucene11StringUtils6toUTF8"; then
    echo "la construction de Lucene++ a échoué"
    exit 1
  fi
fi

# 3. wdlexis_lucene : le pont C, tout en statique (sauf la bibliothèque C du système)
L="$TRAVAIL/LucenePlusPlus"
B="$TRAVAIL/boost-inst"
EXTRA="-static-libstdc++ -static-libgcc -lpthread"
case "$OSDIR" in
  linOS) EXTRA="$EXTRA -Wl,--exclude-libs,ALL -Wl,-s" ;;
  macOS) EXTRA="-lpthread -Wl,-dead_strip" ;;
  winOS) EXTRA="-DWIN32_LEAN_AND_MEAN -DNOMINMAX $EXTRA -lws2_32 -lmswsock -lbcrypt -static -Wl,-s" ;;
esac
mkdir -p "$RACINE/$OSDIR"
"$CXX" -std=c++17 -O2 -DNDEBUG -fPIC -shared -fvisibility=hidden -o "$RACINE/$OSDIR/$LIB" \
    "$RACINE/src/paquets/lucene/wdlexis_lucene.cpp" \
    -I"$L/include" -I"$L/include/lucene++" -I"$LPPB/include" -I"$L/src/contrib/include" -I"$B/include" \
    "$LPP_CONTRIB" "$LPP_CORE" \
    "$B"/lib/libboost_filesystem*.a "$B"/lib/libboost_iostreams*.a "$B"/lib/libboost_regex*.a \
    "$B"/lib/libboost_thread*.a "$B"/lib/libboost_date_time*.a "$B"/lib/libboost_chrono*.a \
    "$B"/lib/libboost_atomic*.a "$B"/lib/libboost_system*.a \
    "$ZLIB" $EXTRA
echo "bibliothèque construite : $RACINE/$OSDIR/$LIB"
