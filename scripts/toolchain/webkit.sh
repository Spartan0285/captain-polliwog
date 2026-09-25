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
#   leopard-g4      Leopard, G4 (AltiVec): reproduces Leopard WebKit's ppc7400 build.
#   leopard-g4-jit  The same with JavaScriptCore's baseline JIT.
#   tiger-g3        Tiger, G3 (750): no AltiVec, 10.4 deployment target.
#   tiger-g3-jit    The same with the JIT.
#
# A variant whose name ends in -jit builds JavaScriptCore's baseline JIT.
set -e
ACTION=$1 VARIANT=$2
shift 2 || true
MAC_SRC=${MAC_SRC:-/Users/adam/polliwog-build/webkit-604}
SRC=$HOME/src/webkit-604
BUILD=$HOME/build/$VARIANT
# TOOLCHAIN=modern builds with the GCC 14 at /opt/ppc-modern rather than the
# GCC 6.5 the port was written for, into a build directory of its own so the
# two can be compared without rebuilding either.
if [ "${TOOLCHAIN:-}" = modern ]; then
    export PPC_TOOLCHAIN=/opt/ppc-modern
    BUILD=$BUILD-gcc14
fi
# Libraries bundled as Leopard WebKit bundles them (built by the other
# scripts here): ICU, SQLite, libxml2/libxslt, and OTS for web fonts.
ICU=/opt/ppc/icu/lib/libicucore.dylib
OTS="/opt/ppc/ots/lib/libots.a;/opt/ppc/ots/lib/libwoff2.a;/opt/ppc/ots/lib/libbrotli.a;/opt/ppc/ots/lib/liblz4.a"

case $VARIANT in
    # 7400 instructions (every G4), scheduled for the 7447/7450 "G4e" core
    # that later G4 Macs, the iBook and aluminum PowerBooks among them, have.
    leopard-g4|leopard-g4-jit) TARGET=10.5; CPU="-mcpu=7400 -mtune=7450 -maltivec" ;;
    # The 750 in a Pismo or a tray-loading iMac: no AltiVec, no frsqrte to
    # rely on, and 10.4 as the floor. The toolchain already builds against
    # the 10.5 SDK with a 10.4 deployment target, so Leopard-only functions
    # are weakly linked and simply absent here.
    # CP_TIGER marks the places where 10.4 needs different code rather than
    # a missing function filled in - so far, that its CoreGraphics cannot
    # measure a glyph at the size it is asked for (see FontCocoa.mm).
    tiger-g3|tiger-g3-jit) TARGET=10.4; CPU="-mcpu=750 -mtune=750 -DCP_TIGER=1"; TIGER_SHIM=1 ;;
    *) echo "usage: $0 configure|build leopard-g4[-jit]|tiger-g3[-jit] [targets...]" >&2; exit 1 ;;
esac
JIT=OFF
case $VARIANT in *-jit) JIT=ON ;; esac

# Tiger has neither the OpenGL of 10.5 (WebGL and ANGLE want 154 functions
# it does not export) nor IOHID's game controller calls (26 more). Both are
# off on 10.4: WebGL mostly fails on these machines anyway, and a browser
# that will not load is worse than one without gamepads.
TIGER_FEATURES=
# Web Audio goes too, for now: its FFT and vector work is vDSP that Leopard
# added to Accelerate, about twenty functions Tiger has not got.
[ -n "${TIGER_SHIM:-}" ] && TIGER_FEATURES="-DENABLE_WEBGL=OFF -DENABLE_GAMEPAD=OFF -DENABLE_WEB_AUDIO=OFF"
# WebCore is about 30MB of code, past the reach of PowerPC's branch
# instruction; ld64 bridges that with branch islands, but only within one
# section. Fewer cold and hot sections for the linker to fold back into
# __text (see ppc-darwin.cmake), and better locality on small caches.
CPU="$CPU -fno-reorder-blocks-and-partition -fno-reorder-functions"

# The optimizing tier, off by default: DFG=ON webkit.sh configure ... turns
# it on. It compiles for PowerPC; whether it earns its keep is measured,
# not assumed.

# Profile-guided optimization, in two passes over one build directory:
#
#   PGO=generate webkit.sh configure leopard-g4-jit && webkit.sh build ...
#   ... run the instrumented engine on a real Mac, collect the profiles ...
#   PGO=use      webkit.sh configure leopard-g4-jit && webkit.sh build ...
#
# One directory for both passes, and that is not a convenience. GCC records
# the absolute path of each object at compile time and looks for the .gcda
# beside it; a second build directory finds nothing, says nothing, and
# produces an unoptimized binary that looks exactly like an optimized one.
# The baseline to compare against is the ordinary build, which is a
# different variant and untouched.
#
# The profiles are written on the target, where our build paths do not
# exist, so the run needs GCOV_PREFIX and GCOV_PREFIX_STRIP to redirect
# them; scripts/jit/collect-profiles.sh does that and puts them back here.
#
# -Wno-coverage-mismatch downgrades to a warning the error GCC raises when a
# function's control flow no longer matches its profile. That happens
# whenever the source is edited between the two passes, and it should be
# rare; if it is not, the profile is stale and should be collected again.
case ${PGO:-} in
    generate) CPU="$CPU -fprofile-generate"; BUILD=$BUILD-pgo ;;
    use)      CPU="$CPU -fprofile-use -fprofile-correction -Wno-coverage-mismatch"
              BUILD=$BUILD-pgo ;;
    "")       ;;
    *)        echo "PGO must be 'generate' or 'use', not '$PGO'" >&2; exit 1 ;;
esac

# An escape hatch for trying a compiler flag across a whole build without
# committing to it: EXTRA_FLAGS=-fvisibility=hidden webkit.sh configure ...
CPU="$CPU ${EXTRA_FLAGS:-}"

# rsync -c compares contents, so a synced file's timestamp changes only when
# the file did, and ninja rebuilds only what was edited.
mkdir -p "$SRC"
rsync -a -c --delete --exclude .git "$MAC_SRC/" "$SRC/"

# Core Animation is 10.5. A 10.4 engine still names its classes, and a class
# reference cannot be weak on Tiger's runtime, so the build links a stand-in
# for them ahead of QuartzCore, which stays for Core Image. Accelerated
# compositing is off on 10.4, so nothing should call into it; see
# engine/tiger-shim/CoreAnimationStubs.m.
# ppc-darwin.cmake reads TIGER_SHIM from the environment and adds the
# library to every link; setting the linker flags on the command line here
# would replace the ones that toolchain file sets, not add to them.
if [ -n "${TIGER_SHIM:-}" ]; then
    bash "$(dirname "$0")/build-tiger-shim.sh" >/dev/null
    export TIGER_SHIM
fi

case $ACTION in
configure)
    # The toolchain file is edited in the repository; install the current
    # copy rather than whatever build-ppc-toolchain.sh left behind.
    sudo cp "$(dirname "$0")/ppc-darwin.cmake" /opt/ppc/share/ppc-darwin.cmake
    mkdir -p "$BUILD" && cd "$BUILD"
    rm -f CMakeCache.txt  # linker and feature defaults only apply to a fresh cache
    cmake -G Ninja "$SRC" -DPORT=Mac \
        -DCMAKE_TOOLCHAIN_FILE=/opt/ppc/share/ppc-darwin.cmake \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=$TARGET -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CPU" -DCMAKE_CXX_FLAGS="$CPU -D_GLIBCXX_USE_C99_MATH_TR1=1" \
        $TIGER_FEATURES \
        -DENABLE_JIT=$JIT -DENABLE_DFG_JIT=${DFG:-OFF} -DENABLE_SAMPLING_PROFILER=OFF -DENABLE_FTL_JIT=OFF -DENABLE_API_TESTS=OFF \
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
    echo "usage: $0 configure|build leopard-g4[-jit]|tiger-g3[-jit] [targets...]" >&2; exit 1 ;;
esac
