#!/bin/bash
# Builds libxml2 and libxslt for PowerPC into /opt/ppc/xml, as dylibs that
# load from the app's Frameworks folder. Leopard's libxml2 (2.6) is older than
# WebCore 604 needs, so Leopard WebKit bundles both; this uses the current
# releases. Built for the G3 and Tiger, so every variant can use them; iconv
# and zlib come from the system, which has both on Tiger and Leopard.
# Run inside the cross-build VM.
set -e
export PATH=/opt/ppc/bin:$PATH
XML2=2.15.4 XML2_SHA256=98087fd181d9070724f3fbc65c7377db03038eb92bd882374daff44940138821
XSLT=1.1.45 XSLT_SHA256=9acfe68419c4d06a45c550321b3212762d92f41465062ca4ea19e632ee5d216e
P=/opt/ppc/xml
F=@executable_path/../Frameworks
INT=powerpc-apple-darwin9-install_name_tool
FLAGS="-O2 -mmacosx-version-min=10.4"
# pkg-config sees only what is built here, never the Linux host's libraries.
export PKG_CONFIG_LIBDIR=$P/lib/pkgconfig PKG_CONFIG_PATH=
LINK="-mmacosx-version-min=10.4 -static-libgcc -Wl,-no_function_starts,-no_data_in_code_info,-no_version_load_command,-no_source_version"

mkdir -p ~/src/deps && cd ~/src/deps
[ -f libxml2-$XML2.tar.xz ] || wget -q https://download.gnome.org/sources/libxml2/${XML2%.*}/libxml2-$XML2.tar.xz
[ -f libxslt-$XSLT.tar.xz ] || wget -q https://download.gnome.org/sources/libxslt/${XSLT%.*}/libxslt-$XSLT.tar.xz
printf '%s  %s\n%s  %s\n' $XML2_SHA256 libxml2-$XML2.tar.xz $XSLT_SHA256 libxslt-$XSLT.tar.xz | sha256sum -c

sudo rm -rf $P && sudo mkdir -p $P && sudo chown "$(id -u)" $P

rm -rf libxml2-$XML2 && tar xJf libxml2-$XML2.tar.xz && cd libxml2-$XML2
./configure --host=powerpc-apple-darwin9 --prefix=$P --disable-static \
    --without-python --without-lzma --with-zlib --with-iconv --with-threads \
    CC=powerpc-apple-darwin9-gcc CFLAGS="$FLAGS" LDFLAGS="$LINK"
make -j8 && make install
lib() { basename "$(readlink "$P/lib/$1.dylib")"; }  # e.g. libxml2.16.dylib
XML2_LIB=$(lib libxml2)
$INT -id $F/$XML2_LIB $P/lib/$XML2_LIB
cd ..

rm -rf libxslt-$XSLT && tar xJf libxslt-$XSLT.tar.xz && cd libxslt-$XSLT
./configure --host=powerpc-apple-darwin9 --prefix=$P --disable-static \
    --without-python --without-crypto --with-libxml-prefix=$P \
    CC=powerpc-apple-darwin9-gcc CFLAGS="$FLAGS" LDFLAGS="$LINK"
make -j8 && make install
XSLT_LIB=$(lib libxslt) EXSLT_LIB=$(lib libexslt)
$INT -id $F/$XSLT_LIB -change $P/lib/$XML2_LIB $F/$XML2_LIB $P/lib/$XSLT_LIB
$INT -id $F/$EXSLT_LIB -change $P/lib/$XML2_LIB $F/$XML2_LIB \
    -change $P/lib/$XSLT_LIB $F/$XSLT_LIB $P/lib/$EXSLT_LIB
