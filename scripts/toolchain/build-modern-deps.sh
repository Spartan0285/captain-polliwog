#!/bin/bash
# What a current WebKit (2.52) needs beyond the GCC 14 cross compiler that
# build-modern-toolchain.sh installs: CMake 3.20 or newer (Ubuntu 20.04 has
# 3.16) and ICU 70.1 or newer built for PowerPC Mac OS X. Everything modern
# goes under /opt/ppc-modern, beside the WebKit 604 toolchain in /opt/ppc.
#
# Run on the Mac with the VM:   scripts/toolchain/build-modern-deps.sh
set -e

VM=${VM:-ppcbuild}
LIMACTL=${LIMACTL:-limactl}
REPO=$(cd "$(dirname "$0")/../.." && pwd)

$LIMACTL shell $VM -- env REPO="$REPO" bash -s <<'VMSCRIPT'
set -e
PREFIX=/opt/ppc-modern
TARGET=powerpc-apple-darwin9
SDK=/opt/ppc/SDKs/MacOSX10.5.sdk
ICU=icu4c-74_2
mkdir -p ~/src && cd ~/src

# CMake, as the project publishes it for this machine's own architecture.
if [ ! -x /opt/cmake/bin/cmake ]; then
    V=3.31.6
    A=$(uname -m); case $A in aarch64) A=aarch64 ;; x86_64) A=x86_64 ;; esac
    wget -q https://github.com/Kitware/CMake/releases/download/v$V/cmake-$V-linux-$A.tar.gz
    wget -q -O cmake-$V.sums https://github.com/Kitware/CMake/releases/download/v$V/cmake-$V-SHA-256.txt
    grep " cmake-$V-linux-$A.tar.gz\$" cmake-$V.sums | sha256sum -c
    sudo mkdir -p /opt/cmake
    sudo tar -xzf cmake-$V-linux-$A.tar.gz -C /opt/cmake --strip-components=1
    rm -f cmake-$V-linux-$A.tar.gz
fi
/opt/cmake/bin/cmake --version | head -1

# GCC 14's shared runtime, renamed to load from an app's Frameworks folder,
# as the 604 toolchain does with GCC 6.5's (see ppc-darwin.cmake for why it
# is shared rather than static).
L=$PREFIX/$TARGET/lib
R=$PREFIX/runtime
F=@executable_path/../Frameworks
INT=/opt/ppc/bin/$TARGET-install_name_tool
sudo mkdir -p $R
sudo cp $L/libstdc++.6.dylib $L/libgcc_s.1.dylib $R/
sudo $INT -id $F/libgcc_s.1.dylib $R/libgcc_s.1.dylib
sudo $INT -id $F/libstdc++.6.dylib -change $L/libgcc_s.1.dylib $F/libgcc_s.1.dylib $R/libstdc++.6.dylib
# libatomic, which 32-bit PowerPC needs for 64-bit atomics, is shared for the
# same reason the rest of the runtime is: its lock table has to be the one
# table for every image, or two images could lock the same address apart.
if [ -f $L/libatomic.1.dylib ]; then
    sudo cp $L/libatomic.1.dylib $R/
    sudo $INT -id $F/libatomic.1.dylib -change $L/libgcc_s.1.dylib $F/libgcc_s.1.dylib $R/libatomic.1.dylib
    # The name -latomic looks for; WebKit's configure links it that way.
    sudo ln -sf libatomic.1.dylib $R/libatomic.dylib
fi
sudo cp "$REPO/scripts/toolchain/ppc-darwin-modern.cmake" $PREFIX/share/ 2>/dev/null || \
    { sudo mkdir -p $PREFIX/share && sudo cp "$REPO/scripts/toolchain/ppc-darwin-modern.cmake" $PREFIX/share/; }

# ICU for the target. As for ICU 55 in the 604 toolchain, its own tools have
# to be built for this machine first, and its data has to be written by hand
# because genccode writes words in the build machine's byte order.
if [ ! -f $PREFIX/icu/lib/libicuuc.a ]; then
    if [ ! -d icu-modern ]; then
        wget -q https://github.com/unicode-org/icu/releases/download/release-74-2/$ICU-src.tgz
        wget -q -O icu-74.sums https://github.com/unicode-org/icu/releases/download/release-74-2/SHASUM512.txt
        grep " $ICU-src.tgz\$" icu-74.sums | sha512sum -c
        mkdir icu-modern && tar -xzf $ICU-src.tgz -C icu-modern --strip-components=1
    fi
    rm -rf icu-modern-host icu-modern-ppc
    mkdir icu-modern-host && ( cd icu-modern-host && ../icu-modern/source/configure --disable-tests --disable-samples >/dev/null && make -j"$(nproc)" >/dev/null )
    mkdir icu-modern-ppc && cd icu-modern-ppc
    # 10.4 deployment as everywhere else, so one ICU serves Tiger and Leopard.
    # Apple's ar and ranlib, not the host's: ld64 reads a GNU archive index
    # only partly, and the link then fails on symbols that are in the
    # archive all along (the same trap as OTS in the 604 toolchain).
    CC=$PREFIX/bin/$TARGET-gcc CXX=$PREFIX/bin/$TARGET-g++ \
    AR=/opt/ppc/bin/$TARGET-ar RANLIB=/opt/ppc/bin/$TARGET-ranlib \
    CFLAGS="-O2 -mmacosx-version-min=10.4" CXXFLAGS="-O2 -std=c++17 -mmacosx-version-min=10.4" \
    LDFLAGS="-mmacosx-version-min=10.4" \
        ../icu-modern/source/configure --host=$TARGET --with-cross-build="$PWD/../icu-modern-host" \
        --prefix=$PREFIX/icu --enable-static --disable-shared --with-data-packaging=static \
        --disable-tests --disable-samples --disable-extras --disable-tools --disable-renaming
    make -j"$(nproc)"
    sudo env PATH=$PREFIX/bin:/opt/ppc/bin:$PATH make install
    python3 "$REPO/scripts/toolchain/icu-data-asm.py" data/out/icudt74b.dat icudt74 > /tmp/icudt74b_dat.S
    $PREFIX/bin/$TARGET-gcc -c /tmp/icudt74b_dat.S -o /tmp/icudt74b_dat.o
    rm -f /tmp/libicudata.a && /opt/ppc/bin/$TARGET-ar rcs /tmp/libicudata.a /tmp/icudt74b_dat.o
    sudo cp /tmp/libicudata.a $PREFIX/icu/lib/libicudata.a
    cd ~/src
fi
/opt/ppc/bin/$TARGET-nm $PREFIX/icu/lib/libicuuc.a 2>/dev/null | grep -c " T " | sed 's/^/icuuc symbols: /'
ls -la $PREFIX/icu/lib/*.a
VMSCRIPT
