#!/bin/bash
# Spike V: cross-build engine/tests/spike-vlc.cpp for PowerPC, linked the way
# the engine links -- GCC 6.5's shared libstdc++ and libgcc, not a static
# pair -- because the whole question is whether that runtime survives having
# PowerVLC's static one in the same process.
#
# libvlc is opened with dlopen at run time, so nothing here links against it
# and the spike builds on a machine that has never seen VLC.
set -e
export PATH=/opt/ppc/bin:$PATH
P=/opt/ppc
SDK=$P/SDKs/MacOSX10.5.sdk
HOST=powerpc-apple-darwin9
CPU=${CPU:--mcpu=7400 -mtune=7450 -maltivec}
SRC=${1:-$(cd "$(dirname "$0")/../../engine/tests" && pwd)/spike-vlc.cpp}
OUT=${2:-$HOME/spike-vlc}

$HOST-g++ -std=gnu++14 -O2 $CPU \
    -isysroot $SDK -mmacosx-version-min=10.4 -D__DARWIN_UNIX03=0 \
    "$SRC" -o "$OUT" \
    -nodefaultlibs -static-libgcc \
    -Wl,-syslibroot,$SDK \
    -Wl,-no_function_starts,-no_data_in_code_info,-no_version_load_command,-no_source_version \
    $P/runtime/libstdc++.6.dylib $P/runtime/libgcc_s.1.dylib \
    -lgcc -lSystem

/opt/ppc/bin/$HOST-otool -hv "$OUT" | tail -1
ls -l "$OUT" | awk '{print $5, $9}'
