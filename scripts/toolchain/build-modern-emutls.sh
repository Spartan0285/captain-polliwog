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
# libstdc++ carries a hidden copy of its own, so this script also relinks it
# from its static archive to import these two instead - with the object that
# defines them taken out of the unwinder archive first, or the linker puts
# the copy straight back.
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

# libstdc++, relinked to import the two functions rather than carry them.
# -all_load because a dylib built from an archive keeps only what something
# references, and this one is the reference for everything above it.
cd /tmp/emutls
cp "$GCCLIB/libgcc_eh.a" libgcc_eh_noemutls.a
$PREFIX/bin/$TARGET-ar d libgcc_eh_noemutls.a "$OBJ"
$PREFIX/bin/$TARGET-ranlib libgcc_eh_noemutls.a

$PREFIX/bin/$TARGET-g++ -dynamiclib -o libstdc++.6.dylib \
    -isysroot $SDK -mmacosx-version-min=10.4 -mcpu=750 \
    -install_name $F/libstdc++.6.dylib \
    -compatibility_version 7.0.0 -current_version 7.33.0 \
    -Wl,-all_load $PREFIX/$TARGET/lib/libstdc++.a \
    -nodefaultlibs $PREFIX/runtime/libemutls.1.dylib -lgcc ./libgcc_eh_noemutls.a -liconv -lSystem \
    -Wl,-no_function_starts,-no_data_in_code_info,-no_version_load_command,-no_source_version

# U here, not T: it asks for the shared copy rather than having its own.
$PREFIX/bin/$TARGET-nm libstdc++.6.dylib | grep -q "U ___emutls_get_address" \
    || { echo "libstdc++ still has its own emulated-TLS state" >&2; exit 1; }
sudo cp libstdc++.6.dylib $PREFIX/runtime/
echo "libstdc++.6.dylib now shares the emulated thread-local state"

# GCC 14 names its real unwinder libgcc_s.1.1.dylib and ships libgcc_s.1.dylib
# as a shim in front of it, both recorded by their build paths. An engine
# bundle cannot refer to /opt on the machine that built it, so the two are
# copied in beside the rest and every reference rewritten to the folder they
# will actually live in. package-webkit.sh refuses to package anything still
# pointing at the build machine, which is how this was noticed.
cd /tmp/emutls
for lib in libgcc_s.1.1.dylib libgcc_ehs.1.1.dylib; do
    cp "$PREFIX/$TARGET/lib/$lib" .
    chmod u+w "$lib"
    $PREFIX/bin/$TARGET-install_name_tool -id "$F/$lib" "$lib"
done
cp "$PREFIX/runtime/libgcc_s.1.dylib" . 2>/dev/null || cp "$PREFIX/$TARGET/lib/libgcc_s.1.dylib" .
chmod u+w libgcc_s.1.dylib
$PREFIX/bin/$TARGET-install_name_tool -id "$F/libgcc_s.1.dylib" libgcc_s.1.dylib
for image in libgcc_s.1.dylib libgcc_s.1.1.dylib libgcc_ehs.1.1.dylib libstdc++.6.dylib; do
    for dep in $($PREFIX/bin/$TARGET-otool -L "$image" | awk '{print $1}' | grep "^$PREFIX/"); do
        $PREFIX/bin/$TARGET-install_name_tool -change "$dep" "$F/$(basename "$dep")" "$image"
    done
done
sudo cp libgcc_s.1.dylib libgcc_s.1.1.dylib libgcc_ehs.1.1.dylib libstdc++.6.dylib $PREFIX/runtime/
echo "runtime libraries now name only the folder they ship in"
