#!/bin/bash
# ICU 55.2 - the version Leopard WebKit 604 bundles - as one
# libicucore.dylib with unrenamed symbols, in /opt/ppc/icu.
# Cross-building ICU needs a native build first, for its own tools.
#
# Runs inside the cross-build VM:  scripts/toolchain/build-icu.sh
#
# __DARWIN_UNIX03=0 is the important flag: it keeps the 10.5 SDK from
# renaming open(), close(), mmap() and mktime() to their "$UNIX2003"
# conformance variants, which Tiger's libSystem has never had. Apple's own
# compiler works this out from -mmacosx-version-min; FSF's does not. Without
# it ICU asks for seven functions that are not there - lazily, so the browser
# starts, renders, and disappears on the first page that formats a date.
# Which is how this was found.
set -e
export PATH=/opt/ppc/bin:$PATH
REPO=$(cd "$(dirname "$0")/../.." && pwd)
R=/opt/ppc/runtime
F=@executable_path/../Frameworks
FLAGS="-O2 -mmacosx-version-min=10.4 -D__DARWIN_UNIX03=0"

cd ~/src
[ -f icu4c-55_2-src.tgz ] || wget -q https://github.com/unicode-org/icu/releases/download/release-55-2/icu4c-55_2-src.tgz
echo "eda2aa9f9c787748a2e2d310590720ca8bcc6252adf6b4cfb03b65bef9d66759  icu4c-55_2-src.tgz" | sha256sum -c
rm -rf icu icu-host icu-ppc && tar -xzf icu4c-55_2-src.tgz
mkdir icu-host && ( cd icu-host && ../icu/source/configure --disable-tests --disable-samples && make -j8 )
mkdir icu-ppc && cd icu-ppc
CC=powerpc-apple-darwin9-gcc CXX=powerpc-apple-darwin9-g++ \
CFLAGS="$FLAGS" CXXFLAGS="$FLAGS" LDFLAGS="-mmacosx-version-min=10.4 -static-libgcc" \
    ../icu/source/configure --host=powerpc-apple-darwin9 --with-cross-build=$HOME/src/icu-host \
    --prefix=/opt/ppc/icu --disable-renaming --enable-static --disable-shared \
    --with-data-packaging=static --disable-tests --disable-samples --disable-extras --disable-tools
make -j8
sudo env PATH=$PATH make install

# ICU's genccode reverses the big-endian data when run on little-endian
# Linux; write the data object ourselves.
python3 "$REPO/scripts/toolchain/icu-data-asm.py" data/out/icudt55b.dat icudt55 > /tmp/icudt55b_dat.S
powerpc-apple-darwin9-gcc -c /tmp/icudt55b_dat.S -o /tmp/icudt55b_dat.o
rm -f /tmp/libicudata.a && powerpc-apple-darwin9-ar rcs /tmp/libicudata.a /tmp/icudt55b_dat.o
sudo cp /tmp/libicudata.a /opt/ppc/icu/lib/libicudata.a

cd /opt/ppc/icu/lib
powerpc-apple-darwin9-g++ -dynamiclib -nodefaultlibs -static-libgcc \
    -isysroot /opt/ppc/SDKs/MacOSX10.5.sdk -mmacosx-version-min=10.4 \
    -install_name $F/libicucore.dylib -compatibility_version 1.0.0 -current_version 55.2.0 \
    -Wl,-force_load,libicuuc.a -Wl,-force_load,libicui18n.a -Wl,-force_load,libicudata.a \
    $R/libstdc++.6.dylib $R/libgcc_s.1.dylib -lgcc -lSystem -o /tmp/libicucore.dylib
sudo mv /tmp/libicucore.dylib /opt/ppc/icu/lib/

left=$(powerpc-apple-darwin9-nm -u /opt/ppc/icu/lib/libicucore.dylib | grep -c 'UNIX2003' || true)
[ "$left" = 0 ] || { echo "libicucore still wants $left UNIX2003 symbols" >&2; exit 1; }
echo "libicucore.dylib built, asking 10.4 for nothing it has not got"
