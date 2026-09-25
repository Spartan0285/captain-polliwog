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
# On "make -j4 && sudo make install": it is written as two statements and
# not one AND-list on purpose. set -e does not fire for a command on the
# left of &&, so a failed compile there skips its install silently and the
# script goes on to the next library - which is how a HarfBuzz that did
# not build at all was followed by Cairo starting.
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
# ICU is installed apart from the rest, from the toolchain scripts, and
# HarfBuzz looks for it with pkg-config.
export PKG_CONFIG_LIBDIR=$P/lib/pkgconfig:$P/icu/lib/pkgconfig PKG_CONFIG_PATH=
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


# Every component is gated, so one that has been fixed can be re-run on its
# own: ONLY="libjpeg-turbo sqlite" bash build-252-deps.sh. With ONLY unset
# the whole list builds, in dependency order. This matters because these
# take ten minutes to reach the end of the list and each new component
# tends to need two or three attempts to cross-build.
ONLY=${ONLY:-}
want() {
    case " $ONLY " in
        "  "|*" $1 "*) echo "=== $1"; cd ~/src/deps252 ;;
        *) return 1 ;;
    esac
}

if want zlib; then
    fetch https://zlib.net/fossils/zlib-1.3.1.tar.gz zlib-1.3.1.tar.gz
    rm -rf zlib-1.3.1 && tar xf zlib-1.3.1.tar.gz && cd zlib-1.3.1
    CHOST=$HOST ./configure --prefix=$P --static
    # zlib's configure writes the Darwin archiver into the Makefile by name
    # and ignores AR from the environment, so it is overridden on the make
    # command line, where a variable beats the Makefile's own assignment.
    make -j4 AR="$LIBTOOL" ARFLAGS="-o" RANLIB="$RANLIB"
    sudo make install AR="$LIBTOOL" ARFLAGS="-o" RANLIB="$RANLIB"
fi

if want libpng; then
    fetch https://download.sourceforge.net/libpng/libpng-1.6.43.tar.gz libpng-1.6.43.tar.gz
    rm -rf libpng-1.6.43 && tar xf libpng-1.6.43.tar.gz && cd libpng-1.6.43
    ./configure --host=$HOST --prefix=$P --enable-static --disable-shared \
        --with-zlib-prefix=$P CPPFLAGS="-I$P/include" LDFLAGS="$LINK -L$P/lib"
    make -j4
    sudo make install
fi

if want pixman; then
    fetch https://cairographics.org/releases/pixman-0.42.2.tar.gz pixman-0.42.2.tar.gz
    rm -rf pixman-0.42.2 && tar xf pixman-0.42.2.tar.gz && cd pixman-0.42.2
    # No AltiVec: the G3 has none, and the engine picks its build by processor.
    ./configure --host=$HOST --prefix=$P --enable-static --disable-shared \
        --disable-vmx --disable-arm-simd --disable-gtk --disable-libpng
    make -j4
    sudo make install
fi

if want freetype; then
    fetch https://download.savannah.gnu.org/releases/freetype/freetype-2.13.2.tar.gz freetype-2.13.2.tar.gz
    rm -rf freetype-2.13.2 && tar xf freetype-2.13.2.tar.gz && cd freetype-2.13.2
    ./configure --host=$HOST --prefix=$P --enable-static --disable-shared \
        --with-zlib=yes --with-png=yes --with-harfbuzz=no --with-brotli=no --with-bzip2=no \
        CPPFLAGS="-I$P/include" LDFLAGS="$LINK -L$P/lib"
    make -j4
    sudo make install
fi

if want libjpeg-turbo; then
    fetch https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.0.2/libjpeg-turbo-3.0.2.tar.gz libjpeg-turbo-3.0.2.tar.gz
    rm -rf libjpeg-turbo-3.0.2 && tar xf libjpeg-turbo-3.0.2.tar.gz && cd libjpeg-turbo-3.0.2
    # cmake, with the modern toolchain file the 2.52 engine itself uses.
    # No SIMD: libjpeg-turbo's PowerPC path is AltiVec, and the G3 has none.
    mkdir -p b && cd b
    /opt/cmake/bin/cmake -S .. -B . -G "Unix Makefiles" \
        -DCMAKE_TOOLCHAIN_FILE=/opt/ppc-modern/share/ppc-darwin-modern.cmake \
        -DCMAKE_INSTALL_PREFIX=$P -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
        -DWITH_SIMD=OFF -DCMAKE_BUILD_TYPE=Release
    make -j4
    sudo make install
fi

if want sqlite; then
    fetch https://www.sqlite.org/2024/sqlite-autoconf-3450100.tar.gz sqlite-autoconf-3450100.tar.gz
    rm -rf sqlite-autoconf-3450100 && tar xf sqlite-autoconf-3450100.tar.gz && cd sqlite-autoconf-3450100
    ./configure --host=$HOST --prefix=$P --enable-static --disable-shared \
        --disable-readline --disable-editline
    make -j4
    sudo make install
fi

if want libxml2; then
    fetch https://download.gnome.org/sources/libxml2/2.12/libxml2-2.12.5.tar.xz libxml2-2.12.5.tar.xz
    rm -rf libxml2-2.12.5 && tar xf libxml2-2.12.5.tar.xz && cd libxml2-2.12.5
    ./configure --host=$HOST --prefix=$P --enable-static --disable-shared \
        --without-python --without-lzma --with-zlib=$P --without-iconv
    make -j4
    sudo make install
fi

if want fontconfig; then
    fetch https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.14.2.tar.xz fontconfig-2.14.2.tar.xz
    rm -rf fontconfig-2.14.2 && tar xf fontconfig-2.14.2.tar.xz && cd fontconfig-2.14.2
    # 2.14 rather than 2.13, which wanted libuuid; 2.14 dropped it.
    #
    # Three things a cross build has to be told:
    #
    # CC_FOR_BUILD, because fc-case, fc-glyphname and fc-lang are run
    # during the build to generate tables. Built by the cross compiler
    # they are PowerPC binaries this machine cannot execute.
    #
    # --disable-cache-build, because "make install" otherwise runs the
    # fc-cache it just built, for the same reason.
    #
    # --enable-libxml2, so that expat is not a fourteenth dependency.
    # libxml2 is already here and fontconfig reads its XML with either.
    #
    # The font directories are Mac OS X's. Fontconfig is the un-Mac-like
    # choice and is made deliberately: 2.52's font cache is
    # FontCacheFreeType.cpp and is Fc-shaped throughout. Core Text comes
    # later, if it comes.
    ./configure --host=$HOST --build=$(gcc -dumpmachine) --prefix=$P \
        --enable-static --disable-shared --enable-libxml2 --disable-docs \
        --disable-cache-build \
        --with-default-fonts=/System/Library/Fonts \
        --with-add-fonts=/Library/Fonts,/System/Library/Fonts/Cache \
        CC_FOR_BUILD=gcc CPPFLAGS="-I$P/include" LDFLAGS="$LINK -L$P/lib"
    make -j4
    sudo make install
fi

if want libwebp; then
    fetch https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.3.2.tar.gz libwebp-1.3.2.tar.gz
    rm -rf libwebp-1.3.2 && tar xf libwebp-1.3.2.tar.gz && cd libwebp-1.3.2
    # WebKit asks for the demux component. The image codecs the command
    # line tools want are off: those tools are not installed and their
    # dependencies would be a detour.
    ./configure --host=$HOST --prefix=$P --enable-static --disable-shared \
        --enable-libwebpdemux --enable-libwebpmux \
        --disable-png --disable-jpeg --disable-tiff --disable-gif --disable-wic
    make -j4
    sudo make install
fi

if want harfbuzz; then
    fetch https://github.com/harfbuzz/harfbuzz/releases/download/8.3.0/harfbuzz-8.3.0.tar.xz harfbuzz-8.3.0.tar.xz
    rm -rf harfbuzz-8.3.0 && tar xf harfbuzz-8.3.0.tar.xz && cd harfbuzz-8.3.0
    # cmake, not meson: HarfBuzz's meson build is the maintained one but
    # meson is a second cross-compiling story to get right, and the cmake
    # build is what Windows and Android use.
    #
    # ICU is on, because WebKit asks for the harfbuzz-icu component and
    # gets its Unicode data that way; GLib is off, which is the same
    # decision as everywhere else and the reason HarfBuzz is not a way
    # GLib comes back in through the side door. CoreText is off: this is a
    # cross build and the shaper is HarfBuzz's own.
    mkdir -p b && cd b
    /opt/cmake/bin/cmake -S .. -B . -G "Unix Makefiles" \
        -DCMAKE_TOOLCHAIN_FILE=$P/share/ppc-darwin-modern.cmake \
        -DCMAKE_INSTALL_PREFIX=$P -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DHB_HAVE_FREETYPE=ON -DHB_HAVE_ICU=ON -DHB_HAVE_GLIB=OFF \
        -DHB_HAVE_GOBJECT=OFF -DHB_HAVE_GRAPHITE2=OFF \
        -DHB_HAVE_CORETEXT=OFF -DHB_BUILD_UTILS=OFF -DHB_BUILD_TESTS=OFF \
        -DFREETYPE_INCLUDE_DIRS="$P/include/freetype2;$P/include" \
        -DFREETYPE_LIBRARY=$P/lib/libfreetype.a
    make -j4
    sudo make install
fi

if want cairo; then
    fetch https://cairographics.org/releases/cairo-1.16.0.tar.xz cairo-1.16.0.tar.xz
    rm -rf cairo-1.16.0 && tar xf cairo-1.16.0.tar.xz && cd cairo-1.16.0
    # 1.16.0 and not 1.18: 1.18 is meson-only, and 1.16.0 is what
    # OptionsGTK asks for as a minimum. Checked rather than assumed -
    # WebKit 2.52 carries no CAIRO_VERSION guards and uses none of the
    # API that postdates 1.16 (cairo_set_hairline, cairo_tag_begin,
    # cairo_pattern_get_dither), so the newer release would buy a build
    # system and nothing else.
    #
    # Backends: the image surface, freetype and fontconfig for text, and
    # pdf, ps and svg, which WebKit includes one file each for. Quartz is
    # off although the target is a Mac: cairo's Quartz backend needs
    # CoreGraphics headers this SDK has behind frameworks cairo's
    # configure cannot probe from Linux, and nothing in WebKit includes
    # cairo-quartz.h. X11, GL and the interpreter are not wanted at all.
    ./configure --host=$HOST --prefix=$P --enable-static --disable-shared \
        --enable-ft --enable-fc --enable-png --enable-pdf --enable-ps --enable-svg \
        --disable-xlib --disable-xcb --disable-xlib-xrender --disable-xcb-shm \
        --disable-quartz --disable-quartz-font --disable-quartz-image \
        --disable-win32 --disable-win32-font --disable-gl --disable-glesv2 \
        --disable-egl --disable-glx --disable-script --disable-interpreter \
        --disable-trace --disable-gtk-doc --disable-valgrind --disable-lto \
        CPPFLAGS="-I$P/include" LDFLAGS="$LINK -L$P/lib"
    make -j4
    sudo make install
fi

if want libgpg-error; then
    fetch https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-1.47.tar.bz2 libgpg-error-1.47.tar.bz2
    rm -rf libgpg-error-1.47 && tar xf libgpg-error-1.47.tar.bz2 && cd libgpg-error-1.47
    # libgcrypt's own dependency, not one of WebKit's thirteen.
    #
    # It needs a src/syscfg/lock-obj-pub.<host>.h describing the size and
    # shape of a pthread mutex on the target, because it cannot run a
    # program there to measure one. There is no file for
    # powerpc-apple-darwin9. Darwin's pthread_mutex_t is the same struct
    # on every 32-bit Apple platform - a long signature and 40 opaque
    # bytes - so a 32-bit Darwin file is used if one is shipped, and
    # written out here if none is.
    ls src/syscfg/lock-obj-pub.*darwin* 2>/dev/null || true
    if [ ! -f src/syscfg/lock-obj-pub.$HOST.h ]; then
        SRC=$(ls src/syscfg/lock-obj-pub.arm-apple-darwin.h 2>/dev/null | head -1)
        if [ -n "$SRC" ]; then
            cp "$SRC" src/syscfg/lock-obj-pub.$HOST.h
            echo "syscfg: copied $SRC"
        else
            cat > src/syscfg/lock-obj-pub.$HOST.h <<'EOF'
## lock-obj-pub.powerpc-apple-darwin9.h
## Written for this port: 32-bit Darwin's pthread_mutex_t is
## { long __sig; char __opaque[40]; }, so 44 bytes aligned to 4.
struct _gpgrt_lock_s {
  long _vers;
  union {
    volatile char _priv[44];
    long _x_align;
    long *_xp_align;
  } u;
};
#define LOCK_OBJ_INITIALIZER_ \
  {0,{{0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, \
       0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}}}
EOF
            echo "syscfg: wrote lock-obj-pub.$HOST.h by hand"
        fi
    fi
    ./configure --host=$HOST --prefix=$P --enable-static --disable-shared \
        --disable-doc --disable-tests --disable-languages
    make -j4
    sudo make install
fi

if want libgcrypt; then
    fetch https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-1.10.3.tar.bz2 libgcrypt-1.10.3.tar.bz2
    rm -rf libgcrypt-1.10.3 && tar xf libgcrypt-1.10.3.tar.bz2 && cd libgcrypt-1.10.3
    # --disable-asm: libgcrypt's PowerPC assembly is written for the
    # vector-crypto instructions of POWER8 and later. A G4 has none of
    # them and a G3 has no vector unit at all, so the C implementations
    # are the only correct choice here, whatever they cost.
    ./configure --host=$HOST --prefix=$P --enable-static --disable-shared \
        --disable-doc --disable-asm --disable-padlock-support \
        --disable-aesni-support --disable-shaext-support \
        --disable-pclmul-support --disable-sse41-support \
        --disable-drng-support --disable-avx-support --disable-avx2-support \
        --disable-ppc-crypto-support \
        --with-libgpg-error-prefix=$P
    make -j4
    sudo make install
fi

if want libtasn1; then
    fetch https://ftp.gnu.org/gnu/libtasn1/libtasn1-4.19.0.tar.gz libtasn1-4.19.0.tar.gz
    rm -rf libtasn1-4.19.0 && tar xf libtasn1-4.19.0.tar.gz && cd libtasn1-4.19.0
    ./configure --host=$HOST --prefix=$P --enable-static --disable-shared \
        --disable-doc --disable-gcc-warnings
    make -j4
    sudo make install
fi

echo "=== done $(date)"
cd $P/lib && ls -l libz.a libpng16.a libpixman-1.a libfreetype.a libjpeg.a libturbojpeg.a \
    libsqlite3.a libxml2.a libfontconfig.a libwebp.a libwebpdemux.a \
    libharfbuzz.a libharfbuzz-icu.a libcairo.a \
    libgcrypt.a libgpg-error.a libtasn1.a 2>&1 | awk '{print $5, $9}'
