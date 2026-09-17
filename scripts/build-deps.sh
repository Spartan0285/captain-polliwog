#!/bin/sh
# Builds Captain Polliwog's bundled dependencies (OpenSSL + libcurl) for one
# architecture. Runs ON a PowerPC Mac, not on a modern one.
#
#   Usage: build-deps.sh ppc|i386
#
# Needs the source tarballs in $HOME and Perl 5.10+ in $HOME/polliwog-tools
# (OpenSSL's Configure rejects the Perl 5.8 that Tiger and Leopard ship).
# Results land in $HOME/polliwog-deps/<arch> as static libraries.
set -e

ARCH=${1:?usage: build-deps.sh ppc|i386}
SDK=${SDK:-/Developer/SDKs/MacOSX10.4u.sdk}
TOOLS=$HOME/polliwog-tools
SRC=$TOOLS/src
PREFIX=$HOME/polliwog-deps/$ARCH
PERL=$TOOLS/bin/perl
OPENSSL=openssl-3.5.8
CURL=curl-8.22.0
JOBS=${JOBS:-2}

case $ARCH in
ppc)
    # G3 baseline, G4 scheduling: one PowerPC build for every PowerPC Mac.
    SSL_TARGET=darwin-ppc-cc
    ARCH_FLAGS="-arch ppc -mcpu=G3 -mtune=G4"
    HOST=powerpc-apple-darwin8
    ;;
i386)
    SSL_TARGET=darwin-i386-cc
    ARCH_FLAGS="-arch i386"
    HOST=i386-apple-darwin8
    ;;
*)
    echo "unknown architecture: $ARCH" >&2
    exit 1
    ;;
esac

CFLAGS_COMMON="-isysroot $SDK -mmacosx-version-min=10.4 -Os $ARCH_FLAGS"
LDFLAGS_COMMON="-isysroot $SDK -Wl,-syslibroot,$SDK $ARCH_FLAGS"

# Some patched Leopard installs have no tar at all, but every one has Python.
extract() {
    if [ -x /usr/bin/tar ]; then
        tar -xzf "$1"
    else
        python -c "import tarfile,sys; tarfile.open(sys.argv[1]).extractall()" "$1"
    fi
}

mkdir -p "$SRC" "$PREFIX"
cd "$SRC"

echo "==> $ARCH: OpenSSL"
rm -rf "$OPENSSL" "$OPENSSL-$ARCH"
extract "$HOME/$OPENSSL.tar.gz"
mv "$OPENSSL" "$OPENSSL-$ARCH"
cd "$SRC/$OPENSSL-$ARCH"
"$PERL" ./Configure "$SSL_TARGET" \
    --prefix="$PREFIX" --openssldir="$PREFIX/ssl" \
    no-shared no-dso no-module no-tests no-apps no-docs no-legacy \
    no-ssl3 no-ssl3-method no-comp no-deprecated \
    $CFLAGS_COMMON
make -j"$JOBS" build_sw
make install_sw

echo "==> $ARCH: libcurl"
cd "$SRC"
rm -rf "$CURL" "$CURL-$ARCH"
extract "$HOME/$CURL.tar.gz"
mv "$CURL" "$CURL-$ARCH"
cd "$SRC/$CURL-$ARCH"
# No CA bundle path is compiled in; the app points libcurl at its own copy.
./configure --host="$HOST" --build="$HOST" --prefix="$PREFIX" \
    --with-openssl="$PREFIX" --without-ca-bundle --without-ca-path \
    --disable-shared --enable-static --with-zlib \
    --disable-ldap --disable-ldaps --disable-manual --disable-dict \
    --disable-gopher --disable-telnet --disable-smtp --disable-imap \
    --disable-pop3 --disable-rtsp --disable-tftp --disable-smb --disable-mqtt \
    --without-libpsl --without-libidn2 --without-nghttp2 --without-brotli \
    --without-zstd --without-librtmp \
    CC=gcc-4.0 CFLAGS="$CFLAGS_COMMON" LDFLAGS="$LDFLAGS_COMMON"
make -j"$JOBS"
make install

echo "==> $ARCH: done"
ls -l "$PREFIX/lib"/lib*.a
