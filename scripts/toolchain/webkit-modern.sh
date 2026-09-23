#!/bin/bash
# Cross-builds a current WebKit (2.52) for PowerPC Mac OS X in the Linux VM,
# with the GCC 14 toolchain from build-modern-toolchain.sh. This is the
# modern-engine spike of docs/ENGINE_PLAN.md, separate from the 604 engine
# the browser ships, which keeps using webkit.sh and GCC 6.5.
#
#   scripts/toolchain/webkit-modern.sh configure|build|shell [args]
#
# Milestone 1 is the JSCOnly port: JavaScriptCore alone, which depends on
# nothing but ICU, in the C interpreter (there is no PowerPC JIT). It answers
# the questions that decide the whole port - does 2.52 compile with GCC 14
# for Darwin, does 32-bit big-endian still work, and how fast is it on a G4 -
# before anything larger is attempted.
set -e

VM=${VM:-ppcbuild}
LIMACTL=${LIMACTL:-limactl}
VERSION=${VERSION:-2.52.6}
step=${1:?usage: webkit-modern.sh configure|build|shell [args]}
shift

REPO=$(cd "$(dirname "$0")/../.." && pwd)

$LIMACTL shell $VM -- env STEP="$step" VERSION="$VERSION" ARGS="$*" REPO="$REPO" bash -s <<'VMSCRIPT'
set -e
PREFIX=/opt/ppc-modern
CMAKE=/opt/cmake/bin/cmake
SRC=$HOME/src/wk-modern/webkitgtk-$VERSION
BUILD=$HOME/build/jsc-$VERSION

if [ ! -d "$SRC" ]; then
    mkdir -p $HOME/src/wk-modern && cd $HOME/src/wk-modern
    [ -f webkitgtk-$VERSION.tar.xz ] || wget -q https://webkitgtk.org/releases/webkitgtk-$VERSION.tar.xz
    wget -q -O sums https://webkitgtk.org/releases/webkitgtk-$VERSION.tar.xz.sums
    grep -A3 "^webkitgtk-$VERSION.tar.xz " sums | awk '/sha256sum:/ {print $2"  webkitgtk-'"$VERSION"'.tar.xz"}' | sha256sum -c
    tar -xJf webkitgtk-$VERSION.tar.xz
    # What this port changes in the released source, one patch per subject,
    # as with the 604 engine (engine/webkit-252-patches).
    for patch in "$REPO"/engine/webkit-252-patches/*.patch; do
        [ -f "$patch" ] || continue
        echo "applying $(basename "$patch")"
        ( cd webkitgtk-$VERSION && patch -p1 --forward -i "$patch" )
    done
fi

case "$STEP" in
configure)
    mkdir -p "$BUILD" && cd "$BUILD"
    # ENABLE_STATIC_JSC puts the engine straight into the jsc program: one
    # file to copy to the old Mac, and one copy of the C++ runtime, which is
    # what emulated thread-local storage needs.
    $CMAKE -S "$SRC" -B . -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE=$PREFIX/share/ppc-darwin-modern.cmake \
        -DPORT=JSCOnly -DCMAKE_BUILD_TYPE=Release \
        -DPOLLIWOG_DARWIN_AS_UNIX=ON \
        -DENABLE_STATIC_JSC=ON -DENABLE_C_LOOP=ON -DENABLE_JIT=OFF \
        -DENABLE_REMOTE_INSPECTOR=OFF -DUSE_SYSTEM_MALLOC=ON \
        -DICU_INCLUDE_DIR=$PREFIX/icu/include \
        -DICU_DATA_LIBRARY_RELEASE=$PREFIX/icu/lib/libicudata.a \
        -DICU_I18N_LIBRARY_RELEASE=$PREFIX/icu/lib/libicui18n.a \
        -DICU_UC_LIBRARY_RELEASE=$PREFIX/icu/lib/libicuuc.a \
        $ARGS ;;
build)
    cd "$BUILD" && $CMAKE --build . ${ARGS:---target jsc} ;;
shell)
    cd "$BUILD" 2>/dev/null || cd "$SRC"
    eval "$ARGS" ;;
*)
    echo "usage: webkit-modern.sh configure|build|shell [args]" >&2; exit 2 ;;
esac
VMSCRIPT
