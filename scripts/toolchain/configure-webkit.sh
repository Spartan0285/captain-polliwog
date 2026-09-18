#!/bin/bash
# Configures a WebKit 604 build in the cross-build VM. Run inside the VM:
#   configure-webkit.sh leopard-g4 [build-dir]
# then build with ninja in that directory (e.g. `ninja WebKitLegacy`).
#
# Variants:
#   leopard-g4  Leopard, G4 (AltiVec): reproduces Leopard WebKit's ppc7400 build.
set -e
VARIANT=$1
SRC=${WEBKIT_SRC:-/Users/adam/polliwog-build/webkit-604}
ICU=/opt/ppc/icu/lib/libicucore.dylib

case $VARIANT in
    leopard-g4) TARGET=10.5; CPU="-mcpu=7400 -maltivec" ;;
    *) echo "usage: $0 leopard-g4 [build-dir]" >&2; exit 1 ;;
esac
BUILD=${2:-$HOME/build/$VARIANT}

mkdir -p "$BUILD" && cd "$BUILD"
rm -f CMakeCache.txt  # linker and feature defaults only apply to a fresh cache
cmake -G Ninja "$SRC" -DPORT=Mac \
    -DCMAKE_TOOLCHAIN_FILE=/opt/ppc/share/ppc-darwin.cmake \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$TARGET -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$CPU" -DCMAKE_CXX_FLAGS="$CPU -D_GLIBCXX_USE_C99_MATH_TR1=1" \
    -DENABLE_JIT=OFF -DENABLE_DFG_JIT=OFF -DENABLE_FTL_JIT=OFF -DENABLE_API_TESTS=OFF \
    -DPOLLIWOG_ENABLE_WEBKIT2=OFF \
    -DICU_INCLUDE_DIR=/opt/ppc/icu/include \
    -DICU_LIBRARY=$ICU -DICU_I18N_LIBRARY=$ICU -DICU_DATA_LIBRARY=$ICU
