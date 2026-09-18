#!/bin/bash
# Builds OTS (OpenType Sanitizer) 6.1.1 for PowerPC into /opt/ppc/ots, as
# Leopard WebKit 604 does: WebCore passes every web font through it before
# Mac OS X's font system sees it, and it decodes WOFF2. Its release bundles
# the WOFF2, Brotli and lz4 code it needs (built as their own static
# libraries); zlib comes from the system.
# Run inside the cross-build VM.
set -e
export PATH=/opt/ppc/bin:$PATH
REPO=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p ~/src/deps && cd ~/src/deps
[ -f ots-6.1.1.tar.gz ] || wget -q https://github.com/khaledhosny/ots/releases/download/v6.1.1/ots-6.1.1.tar.gz
echo "d9ca90b4e0cbf2aa3f7bafbf8a2ca6c8b76c4f1c65da9a3b4e374ee21286cee2  ots-6.1.1.tar.gz" | sha256sum -c
rm -rf ots-6.1.1 && tar xzf ots-6.1.1.tar.gz && cd ots-6.1.1
patch -p1 < "$REPO/scripts/toolchain/ots-unique-font-names.patch"

# Built for the G3 and Tiger, so every variant can use it. GNU mode, as for
# WebKit: in strict mode Leopard's math.h hides the C99 functions <cmath> needs.
./configure --host=powerpc-apple-darwin9 --prefix=/opt/ppc/ots \
    CC=powerpc-apple-darwin9-gcc CXX=powerpc-apple-darwin9-g++ \
    CFLAGS="-O2 -mmacosx-version-min=10.4" \
    CXXFLAGS="-O2 -mmacosx-version-min=10.4 -std=gnu++11 -D_GLIBCXX_USE_C99_MATH_TR1=1" \
    LDFLAGS="-mmacosx-version-min=10.4 -static-libgcc"
# The archiver must be Apple's (the Makefile hard-codes plain `ar`): the Linux
# one writes long member names in a form ld64 cannot follow, and the objects
# behind them silently go missing at link time.
make -j8 AR=powerpc-apple-darwin9-ar libots.a libwoff2.a libbrotli.a liblz4.a

sudo mkdir -p /opt/ppc/ots/lib /opt/ppc/ots/include/ots
sudo cp libots.a libwoff2.a libbrotli.a liblz4.a /opt/ppc/ots/lib/
sudo cp include/opentype-sanitiser.h include/ots-memory-stream.h /opt/ppc/ots/include/ots/
