#!/bin/bash
# The first layer of what WebKit 2.52's WebCore needs, cross-built for
# powerpc-apple-darwin9 with GCC 14 into /opt/ppc-modern.
#
# These cannot be borrowed from /opt/ppc: those were built with GCC 6.5,
# and one image carrying two C++ runtimes is the fault this port has
# already been bitten by. Everything modern is built again by the modern
# compiler.
#
# Order is dependency order: zlib, then png on zlib, then freetype on
# both, then pixman, which owes nothing to anyone. Cairo comes after
# these and is the point of them.
#
# On hashes: the 604 scripts pin a known SHA-256 for every tarball. These
# are recorded on the first fetch into $P/SOURCES.sha256 and verified on
# every run after, which is trust-on-first-use rather than trust - worth
# replacing with published hashes when someone has them to hand.
set -e
# GCC 14 first, then the 604 toolchain's cctools: /opt/ppc-modern has a
# compiler but no ar, and the project's rule is Apple's ar for any static
# library, never the Linux one.
export PATH=/opt/ppc-modern/bin:/opt/ppc/bin:$PATH
P=/opt/ppc-modern
SDK=/opt/ppc/SDKs/MacOSX10.5.sdk
HOST=powerpc-apple-darwin9
F=@executable_path/../Frameworks
INT=$HOST-install_name_tool
FLAGS="-O2 -mcpu=750 -isysroot $SDK -mmacosx-version-min=10.4 -D__DARWIN_UNIX03=0"
LINK="-mmacosx-version-min=10.4 -isysroot $SDK -Wl,-syslibroot,$SDK -static-libgcc \
 -Wl,-no_function_starts,-no_data_in_code_info,-no_version_load_command,-no_source_version"
export PKG_CONFIG_LIBDIR=$P/lib/pkgconfig PKG_CONFIG_PATH=
# Absolute paths, not names on PATH. A sub-build that resets or narrows
# PATH - and zlib's generated Makefile is one - otherwise loses the
# toolchain halfway through, after the compiles have already succeeded.
# The archiver is cctools', from the 604 toolchain: /opt/ppc-modern has a
# compiler but no ar, and the Linux ar does not produce an archive these
# linkers accept.
export CC=/opt/ppc-modern/bin/$HOST-gcc
export CXX=/opt/ppc-modern/bin/$HOST-g++
export AR=/opt/ppc/bin/$HOST-ar
export RANLIB=/opt/ppc-modern/bin/$HOST-ranlib
export LIBTOOL=/opt/ppc/bin/$HOST-libtool
export STRIP=/opt/ppc-modern/bin/$HOST-strip
export NM=/opt/ppc-modern/bin/$HOST-nm
export CFLAGS="$FLAGS" CXXFLAGS="$FLAGS" LDFLAGS="$LINK"
HASHES=$P/SOURCES.sha256
sudo mkdir -p "$P/lib/pkgconfig"
sudo touch "$HASHES" && sudo chown "$(id -un)" "$HASHES"
mkdir -p ~/src/deps252 && cd ~/src/deps252

fetch() {   # fetch <url> <file>
    [ -s "$2" ] || { rm -f "$2"; wget -q "$1" -O "$2"; }
    [ -s "$2" ] || { echo "empty download: $2" >&2; exit 1; }
    if grep -q "  $2\$" "$HASHES"; then
        grep "  $2\$" "$HASHES" | sha256sum -c -
    else
        sha256sum "$2" >> "$HASHES"
        echo "recorded hash for $2"
    fi
}

echo "=== zlib"
fetch https://zlib.net/fossils/zlib-1.3.1.tar.gz zlib-1.3.1.tar.gz
rm -rf zlib-1.3.1 && tar xf zlib-1.3.1.tar.gz && cd zlib-1.3.1
CHOST=$HOST ./configure --prefix=$P --static
# zlib's configure writes the Darwin archiver into the Makefile by name
# and ignores AR from the environment, so it is overridden on the make
# command line, where a variable beats the Makefile's own assignment.
make -j4 AR="$LIBTOOL" ARFLAGS="-o" RANLIB="$RANLIB"
sudo make install AR="$LIBTOOL" ARFLAGS="-o" RANLIB="$RANLIB"
cd ..

echo "=== libpng"
fetch https://download.sourceforge.net/libpng/libpng-1.6.43.tar.gz libpng-1.6.43.tar.gz
rm -rf libpng-1.6.43 && tar xf libpng-1.6.43.tar.gz && cd libpng-1.6.43
./configure --host=$HOST --prefix=$P --enable-static --disable-shared \
    --with-zlib-prefix=$P CPPFLAGS="-I$P/include" LDFLAGS="$LINK -L$P/lib"
make -j4 && sudo make install
cd ..

echo "=== pixman"
fetch https://cairographics.org/releases/pixman-0.42.2.tar.gz pixman-0.42.2.tar.gz
rm -rf pixman-0.42.2 && tar xf pixman-0.42.2.tar.gz && cd pixman-0.42.2
# No AltiVec: the G3 has none, and the engine picks its build by processor.
./configure --host=$HOST --prefix=$P --enable-static --disable-shared \
    --disable-vmx --disable-arm-simd --disable-gtk --disable-libpng
make -j4 && sudo make install
cd ..

echo "=== freetype"
fetch https://download.savannah.gnu.org/releases/freetype/freetype-2.13.2.tar.gz freetype-2.13.2.tar.gz
rm -rf freetype-2.13.2 && tar xf freetype-2.13.2.tar.gz && cd freetype-2.13.2
./configure --host=$HOST --prefix=$P --enable-static --disable-shared \
    --with-zlib=yes --with-png=yes --with-harfbuzz=no --with-brotli=no --with-bzip2=no \
    CPPFLAGS="-I$P/include" LDFLAGS="$LINK -L$P/lib"
make -j4 && sudo make install
cd ..

echo "=== done $(date)"
ls -l $P/lib/libz.a $P/lib/libpng16.a $P/lib/libpixman-1.a $P/lib/libfreetype.a 2>/dev/null | awk '{print $5, $9}'
