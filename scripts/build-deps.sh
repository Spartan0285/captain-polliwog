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
ZLIB=zlib-1.3.2
JOBS=${JOBS:-2}

case $ARCH in
ppc)
    # G3 baseline, G4 scheduling: one PowerPC build for every PowerPC Mac.
    SSL_TARGET=darwin-ppc-cc
    ARCH_FLAGS="-arch ppc -mcpu=G3 -mtune=G4"
    TUNE_FLAGS="-mcpu=G3 -mtune=G4"
    HOST=powerpc-apple-darwin8
    ;;
i386)
    SSL_TARGET=darwin-i386-cc
    ARCH_FLAGS="-arch i386"
    TUNE_FLAGS=
    HOST=i386-apple-darwin8
    ;;
*)
    echo "unknown architecture: $ARCH" >&2
    exit 1
    ;;
esac

CFLAGS_COMMON="-mmacosx-version-min=10.4 -Os"
# OpenSSL keeps its target's own -O3: TLS handshakes are real work at 500MHz,
# and its assembly paths are the reason for using it over a smaller library.
# no-async above: OpenSSL's coroutines need getcontext/setcontext, which
# Tiger does not provide.
# Apple's CommonCrypto random number API needs 10.12, and the header that
# advertises it does not exist in the 10.4 SDK; OpenSSL falls back to
# /dev/urandom, which is what Tiger provides anyway.
CFLAGS_OPENSSL="-mmacosx-version-min=10.4 $TUNE_FLAGS -DOPENSSL_NO_APPLE_CRYPTO_RANDOM"
LDFLAGS_COMMON="-mmacosx-version-min=10.4"

# OpenSSL's Configure splits "-isysroot <path>" into two arguments and then
# mistakes the path for one of its own options, so the SDK (and, for libcurl,
# the architecture) is baked into wrapper compilers instead.
mkdir -p "$TOOLS/bin"
CC_SDK="$TOOLS/bin/cp-cc-sdk"
CC_ARCH="$TOOLS/bin/cp-cc-$ARCH"
printf '#!/bin/sh\nexec gcc-4.0 -isysroot %s "$@"\n' "$SDK" > "$CC_SDK"
printf '#!/bin/sh\nexec gcc-4.0 -isysroot %s %s "$@"\n' "$SDK" "$ARCH_FLAGS" > "$CC_ARCH"
chmod +x "$CC_SDK" "$CC_ARCH"

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

# Each piece is skipped when already installed; FORCE=1 rebuilds everything.
if [ -f "$PREFIX/lib/libcrypto.a" ] && [ "${FORCE:-0}" != 1 ]; then
    echo "==> $ARCH: OpenSSL already built"
else
echo "==> $ARCH: OpenSSL"
rm -rf "$OPENSSL" "$OPENSSL-$ARCH"
extract "$HOME/$OPENSSL.tar.gz"
mv "$OPENSSL" "$OPENSSL-$ARCH"
cd "$SRC/$OPENSSL-$ARCH"
CC="$CC_SDK" "$PERL" ./Configure "$SSL_TARGET" \
    --prefix="$PREFIX" --openssldir="$PREFIX/ssl" \
    no-shared no-dso no-module no-tests no-apps no-docs no-legacy \
    no-ssl3 no-ssl3-method no-comp no-deprecated no-async \
    $CFLAGS_OPENSSL
make -j"$JOBS" build_sw
make install_sw
fi

# Tiger ships zlib 1.2.3, which is too old for libcurl's compression support,
# and a current zlib decompresses faster on these processors anyway.
if [ -f "$PREFIX/lib/libz.a" ] && [ "${FORCE:-0}" != 1 ]; then
    echo "==> $ARCH: zlib already built"
else
echo "==> $ARCH: zlib"
cd "$SRC"
rm -rf "$ZLIB" "$ZLIB-$ARCH"
extract "$HOME/$ZLIB.tar.gz"
mv "$ZLIB" "$ZLIB-$ARCH"
cd "$SRC/$ZLIB-$ARCH"
CHOST="$HOST" CC="$CC_ARCH" AR=ar RANLIB=ranlib CFLAGS="$CFLAGS_COMMON" \
    ./configure --prefix="$PREFIX" --static
make -j"$JOBS"
make install
fi

if [ -f "$PREFIX/lib/libcurl.a" ] && [ "${FORCE:-0}" != 1 ]; then
    echo "==> $ARCH: libcurl already built"
else
echo "==> $ARCH: libcurl"
cd "$SRC"
rm -rf "$CURL" "$CURL-$ARCH"
extract "$HOME/$CURL.tar.gz"
mv "$CURL" "$CURL-$ARCH"
cd "$SRC/$CURL-$ARCH"
# No CA bundle path is compiled in; the app points libcurl at its own copy.
./configure --host="$HOST" --build="$HOST" --prefix="$PREFIX" \
    --with-openssl="$PREFIX" --without-ca-bundle --without-ca-path \
    --disable-shared --enable-static --with-zlib="$PREFIX" \
    --disable-ldap --disable-ldaps --disable-manual --disable-dict \
    --disable-gopher --disable-telnet --disable-smtp --disable-imap \
    --disable-pop3 --disable-rtsp --disable-tftp --disable-smb --disable-mqtt \
    --without-libpsl --without-libidn2 --without-nghttp2 --without-brotli \
    --without-zstd --without-librtmp \
    CC="$CC_ARCH" CFLAGS="$CFLAGS_COMMON" LDFLAGS="$LDFLAGS_COMMON"
# Only the library is wanted. The curl command-line tool fails to link here
# because static archives have to be listed before the libraries they use,
# and nothing in Captain Polliwog uses that tool.
make -j"$JOBS" -C lib
make -C include install
make -C lib install
fi

echo "==> $ARCH: done"
ls -l "$PREFIX/lib"/lib*.a
