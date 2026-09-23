#!/bin/bash
# Builds the stand-ins a 10.4 engine needs to load and run at all: Core
# Animation (10.5 entirely), the CoreText and Quartz calls Leopard added or
# renamed, and the Objective-C 2.0 runtime. Each source file says what it
# covers. Result: /opt/ppc/tiger-shim/libTigerShim.dylib in the build VM.
#
# Runs inside the VM, from webkit.sh, or on its own:
#   scripts/toolchain/build-tiger-shim.sh
set -e

REPO=$(cd "$(dirname "$0")/../.." && pwd)
PREFIX=/opt/ppc/tiger-shim
TARGET=powerpc-apple-darwin9
SDK=/opt/ppc/SDKs/MacOSX10.5.sdk
RUNTIME=/opt/ppc/runtime
F=@executable_path/../Frameworks

sudo mkdir -p $PREFIX
# Built for the G3 with a 10.4 deployment target, like everything else, so
# one copy serves every Tiger Mac. It is linked against nothing but
# Foundation: the classes it defines are the ones the system has not got.
/opt/ppc/bin/$TARGET-gcc -dynamiclib -O2 -Wall \
    -isysroot $SDK -mmacosx-version-min=10.4 -mcpu=750 \
    -install_name $F/libTigerShim.dylib \
    -compatibility_version 1.0.0 -current_version 1.0.0 \
    -nodefaultlibs -static-libgcc \
    -Wl,-no_function_starts,-no_data_in_code_info,-no_version_load_command,-no_source_version \
    -framework Foundation -framework AppKit -framework ApplicationServices \
    $RUNTIME/libgcc_s.1.dylib -lgcc -lSystem \
    "$REPO/engine/tiger-shim/CoreAnimationStubs.m" \
    "$REPO/engine/tiger-shim/CoreTextStubs.c" \
    "$REPO/engine/tiger-shim/QuartzStubs.c" \
    "$REPO/engine/tiger-shim/RuntimeStubs.c" \
    "$REPO/engine/tiger-shim/FoundationStubs.m" \
    "$REPO/engine/tiger-shim/TigerCategories.m" \
    "$REPO/engine/tiger-shim/MapTableStubs.m" \
    "$REPO/engine/tiger-shim/TrackingAreaStubs.m" \
    "$REPO/engine/tiger-shim/CoreFoundationStubs.c" \
    "$REPO/engine/tiger-shim/SystemStubs.c" \
    -o /tmp/libTigerShim.dylib
sudo cp /tmp/libTigerShim.dylib $PREFIX/
echo "libTigerShim.dylib supplies $(/opt/ppc/bin/$TARGET-nm -g $PREFIX/libTigerShim.dylib | grep -cE ' [TDSA] ') symbols"
