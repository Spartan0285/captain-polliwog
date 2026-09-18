#!/bin/bash
# Configures and builds WebKit 604 in the cross-build VM. Run inside the VM:
#   webkit.sh configure leopard-g4
#   webkit.sh build leopard-g4 [ninja targets...]   (default target: WebKit,
#                                                    which is WebKitLegacy)
#
# The WebKit checkout (a git repository) stays on the Mac in
# ~/polliwog-build/webkit-604, where it is edited; each run copies it to the
# VM's own disk first. Building straight from the shared folder is about 13x
# slower, because every WebCore file reads thousands of headers through it.
#
# Variants:
#   leopard-g4  Leopard, G4 (AltiVec): reproduces Leopard WebKit's ppc7400 build.
set -e
ACTION=$1 VARIANT=$2
shift 2 || true
MAC_SRC=${MAC_SRC:-/Users/adam/polliwog-build/webkit-604}
SRC=$HOME/src/webkit-604
BUILD=$HOME/build/$VARIANT
# Libraries bundled as Leopard WebKit bundles them (built by the other
# scripts here): ICU, SQLite, libxml2/libxslt, and OTS for web fonts.
ICU=/opt/ppc/icu/lib/libicucore.dylib
OTS="/opt/ppc/ots/lib/libots.a;/opt/ppc/ots/lib/libwoff2.a;/opt/ppc/ots/lib/libbrotli.a;/opt/ppc/ots/lib/liblz4.a"

case $VARIANT in
    leopard-g4) TARGET=10.5; CPU="-mcpu=7400 -maltivec" ;;
    *) echo "usage: $0 configure|build leopard-g4 [targets...]" >&2; exit 1 ;;
esac

# rsync -c compares contents, so a synced file's timestamp changes only when
# the file did, and ninja rebuilds only what was edited.
mkdir -p "$SRC"
rsync -a -c --delete --exclude .git "$MAC_SRC/" "$SRC/"

case $ACTION in
configure)
    mkdir -p "$BUILD" && cd "$BUILD"
    rm -f CMakeCache.txt  # linker and feature defaults only apply to a fresh cache
    cmake -G Ninja "$SRC" -DPORT=Mac \
        -DCMAKE_TOOLCHAIN_FILE=/opt/ppc/share/ppc-darwin.cmake \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=$TARGET -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CPU" -DCMAKE_CXX_FLAGS="$CPU -D_GLIBCXX_USE_C99_MATH_TR1=1" \
        -DENABLE_JIT=OFF -DENABLE_DFG_JIT=OFF -DENABLE_FTL_JIT=OFF -DENABLE_API_TESTS=OFF \
        -DPOLLIWOG_ENABLE_WEBKIT2=OFF \
        -DICU_INCLUDE_DIR=/opt/ppc/icu/include \
        -DICU_LIBRARY=$ICU -DICU_I18N_LIBRARY=$ICU -DICU_DATA_LIBRARY=$ICU \
        -DSQLITE3_LIBRARY=/opt/ppc/sqlite/lib/libsqlite3.dylib -DSQLITE3_INCLUDE_DIR=/opt/ppc/sqlite/include \
        -DXML2_LIBRARY=/opt/ppc/xml/lib/libxml2.dylib -DLIBXML2_INCLUDE_DIR=/opt/ppc/xml/include/libxml2 \
        -DXSLT_LIBRARY=/opt/ppc/xml/lib/libxslt.dylib -DLIBXSLT_INCLUDE_DIR=/opt/ppc/xml/include \
        -DOTS_INCLUDE_DIR=/opt/ppc/ots/include -DOTS_LIBRARIES="$OTS"
    ;;
build)
    cd "$BUILD"
    ninja -k 0 -j8 "${@:-WebKit}"
    ;;
*)
    echo "usage: $0 configure|build leopard-g4 [targets...]" >&2; exit 1 ;;
esac
