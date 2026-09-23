#!/bin/bash
# Thread-local storage is emulated on Mac OS X 10.5: there is no __thread, so
# GCC keeps the state behind two functions, __emutls_get_address and
# __emutls_register_common, and whichever copy an image links is the copy its
# thread-locals live in.
#
# GCC 6's shared libgcc exports both, so every framework in the engine shares
# one. GCC 14's hides them, and each image takes its own from libgcc_eh.a -
# at which point std::call_once writes its callable through one copy and
# libstdc++ reads it through another, finds null, and the first thing the
# engine does on startup is jump to zero.
#
# This builds those two functions, and nothing else, as a library every image
# can share. ppc-darwin.cmake lists it ahead of the static libgcc.
#
# Note what it does not fix: libstdc++.6.dylib carries a hidden copy of its
# own, so a once_flag shared across two frameworks still does not work. That
# wants libstdc++ relinked to import these instead, which is the next piece.
#
# Runs inside the build VM:  scripts/toolchain/build-modern-emutls.sh
set -e

PREFIX=/opt/ppc-modern
TARGET=powerpc-apple-darwin9
SDK=/opt/ppc/SDKs/MacOSX10.5.sdk
GCCLIB=$PREFIX/lib/gcc/$TARGET/14.2.0
F=@executable_path/../Frameworks

rm -rf /tmp/emutls && mkdir -p /tmp/emutls && cd /tmp/emutls
$PREFIX/bin/$TARGET-ar x "$GCCLIB/libgcc_eh.a"

OBJ=
for o in *.o; do
    if $PREFIX/bin/$TARGET-nm "$o" 2>/dev/null | grep -q "T ___emutls_get_address"; then
        OBJ=$o
    fi
done
[ -n "$OBJ" ] || { echo "no object in libgcc_eh.a defines __emutls_get_address" >&2; exit 1; }

# The load commands modern ld64 adds by default are dropped, as everywhere
# else here: Leopard's tools cannot parse a binary that carries them.
$PREFIX/bin/$TARGET-gcc -dynamiclib "$OBJ" -o libemutls.1.dylib \
    -isysroot $SDK -mmacosx-version-min=10.4 -mcpu=750 \
    -install_name $F/libemutls.1.dylib \
    -compatibility_version 1.0.0 -current_version 1.0.0 \
    -nodefaultlibs -lSystem \
    -Wl,-no_function_starts,-no_data_in_code_info,-no_version_load_command,-no_source_version

sudo mkdir -p $PREFIX/runtime
sudo cp libemutls.1.dylib $PREFIX/runtime/
echo "libemutls.1.dylib exports:"
$PREFIX/bin/$TARGET-nm -g $PREFIX/runtime/libemutls.1.dylib | grep emutls
