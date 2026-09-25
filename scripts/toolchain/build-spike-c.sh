#!/bin/bash
# Spike C.1: cross-build engine/tests/spike-c-text.c against the 2.52
# dependencies in /opt/ppc-modern, for running on a real PowerPC Mac.
#
# Linked the way the toolchain file links WebKit: -nodefaultlibs with the
# runtime named explicitly, because the GCC driver wants SDK stubs that
# ld64 cannot read for a 10.4 target. Static libstdc++ is right here and
# would be wrong in the app: this is one binary with no dylibs of ours in
# it, so there is only one copy of the emulated thread-local state that
# std::call_once lives in.
#
# Link order is dependency order and matters for static archives: cairo
# calls fontconfig, fontconfig calls freetype and libxml2, harfbuzz-icu
# calls harfbuzz and ICU.
set -e
export PATH=/opt/ppc-modern/bin:/opt/ppc/bin:$PATH
P=/opt/ppc-modern
SDK=/opt/ppc/SDKs/MacOSX10.5.sdk
HOST=powerpc-apple-darwin9
SRC=${1:-$(cd "$(dirname "$0")/../../engine/tests" && pwd)/spike-c-text.c}
OUT=${2:-$HOME/spike-c-text}
RT=$P/powerpc-apple-darwin9/lib

$HOST-g++ -x c -std=gnu99 -O2 -mcpu=750 \
    -isysroot $SDK -mmacosx-version-min=10.4 -D__DARWIN_UNIX03=0 \
    -I$P/include -I$P/include/cairo -I$P/include/freetype2 \
    -I$P/include/harfbuzz -I$P/icu/include \
    "$SRC" -o "$OUT" \
    -nodefaultlibs -static-libgcc \
    -Wl,-syslibroot,$SDK \
    -Wl,-no_function_starts,-no_data_in_code_info,-no_version_load_command,-no_source_version \
    -L$P/lib -L$P/icu/lib \
    -lcairo -lharfbuzz-icu -lharfbuzz -lfontconfig -lfreetype \
    -lpng16 -lz -lpixman-1 -lxml2 \
    -licuuc -licudata \
    $RT/libstdc++.a $RT/libatomic.a -lgcc -lgcc_eh -lSystem

/opt/ppc/bin/$HOST-otool -hv "$OUT" | tail -1
ls -l "$OUT" | awk '{print $5, $9}'
