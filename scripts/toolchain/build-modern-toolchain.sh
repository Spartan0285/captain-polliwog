#!/bin/bash
# A second PowerPC Mac OS X cross compiler, GCC 14, for porting a current
# WebKit (WebKitGTK/WPE 2.44, which needs C++20 - GCC 11 at least). It goes
# in /opt/ppc-modern beside the GCC 6.5 toolchain in /opt/ppc, which the
# WebKit 604 engine keeps using, and shares that toolchain's cctools and
# ld64 (build-ppc-toolchain.sh has to have run first).
#
# Run on the Mac with the VM:   scripts/toolchain/build-modern-toolchain.sh
# (LIMACTL overrides the path to limactl; VM the VM's name.)
#
# The build tree is removed afterwards: disk is short on the MacBook Pro,
# and the VM's disk image only ever grows.
set -e

VM=${VM:-ppcbuild}
LIMACTL=${LIMACTL:-limactl}
REPO=$(cd "$(dirname "$0")/../.." && pwd)

$LIMACTL shell $VM -- env REPO="$REPO" FRESH="$FRESH" bash -s <<'VMSCRIPT'
set -e
GCC=gcc-14.2.0
PREFIX=/opt/ppc-modern
TARGET=powerpc-apple-darwin9

[ -x /opt/ppc/bin/$TARGET-ld ] || { echo "run build-ppc-toolchain.sh first" >&2; exit 1; }

mkdir -p ~/src && cd ~/src
if [ ! -d $GCC ]; then
    [ -f $GCC.tar.xz ] || wget -q https://ftp.gnu.org/gnu/gcc/$GCC/$GCC.tar.xz
    # Checked against the sums the GCC project publishes on its own server,
    # a different one from the GNU mirror the tarball came from.
    wget -q -O $GCC.sha512 https://sourceware.org/pub/gcc/releases/$GCC/sha512.sum
    grep " $GCC.tar.xz\$" $GCC.sha512 | sha512sum -c
    tar -xJf $GCC.tar.xz
fi
# libatomic is built, not disabled: 32-bit PowerPC has no 64-bit atomic
# instruction, and WebKit uses 64-bit atomics throughout, so its configure
# stops without one.

# See the patch's header.
grep -q "s/ppc750/ppc/" $GCC/libgcc/config/t-slibgcc-darwin || \
    ( cd $GCC && patch -p1 < "$REPO/scripts/toolchain/gcc14-darwin-ppc750-arch.patch" )

# The binutils GCC calls by name, from the old toolchain.
sudo mkdir -p $PREFIX/bin $PREFIX/$TARGET/bin
for tool in ar as ld nm ranlib strip lipo otool install_name_tool libtool dsymutil; do
    sudo ln -sf /opt/ppc/bin/$TARGET-$tool $PREFIX/bin/$TARGET-$tool
    sudo ln -sf /opt/ppc/bin/$TARGET-$tool $PREFIX/$TARGET/bin/$tool
done

export PATH=$PREFIX/bin:/opt/ppc/bin:$PATH
# An interrupted build carries on where it stopped (FRESH=1 starts over).
[ -n "$FRESH" ] && rm -rf build-gcc14
mkdir -p build-gcc14 && cd build-gcc14
# As for GCC 6.5: the G3 as the default CPU and runtime libraries built for
# 10.4, so one compiler serves Tiger on a G3 as well as Leopard on a G4.
[ -f Makefile ] || ../$GCC/configure --target=$TARGET --prefix=$PREFIX \
    --with-sysroot=/opt/ppc/SDKs/MacOSX10.5.sdk \
    --with-as=/opt/ppc/bin/$TARGET-as --with-ld=/opt/ppc/bin/$TARGET-ld \
    --enable-languages=c,c++,objc,obj-c++ --disable-multilib --disable-nls --disable-bootstrap \
    --disable-libsanitizer --disable-libgomp --disable-libitm --disable-libssp \
    --disable-libquadmath \
    --with-dwarf2 --with-cpu=750 \
    CFLAGS="-O2 -g0" CXXFLAGS="-O2 -g0" \
    CFLAGS_FOR_TARGET="-O2 -g0 -mcpu=750 -mmacosx-version-min=10.4" \
    CXXFLAGS_FOR_TARGET="-O2 -g0 -mcpu=750 -mmacosx-version-min=10.4"
make -j"$(nproc)"
sudo env PATH=$PATH make install
cd ~/src && rm -rf build-gcc14 $GCC

# Proof: C++20 compiled, linked and marked for the G3 on 10.4.
cat > /tmp/cxx20.cpp <<'EOF'
#include <concepts>
#include <span>
#include <string>
#include <cstdio>
template<std::integral T> T twice(T v) { return v * 2; }
int main() { int a[] = {1, 2, 3}; std::span<int> s(a); std::string t = "ok";
    std::printf("%s %d\n", t.c_str(), twice(s[2])); return 0; }
EOF
$PREFIX/bin/$TARGET-g++ -std=c++20 -O2 -mmacosx-version-min=10.4 /tmp/cxx20.cpp -o /tmp/cxx20
/opt/ppc/bin/$TARGET-otool -hv /tmp/cxx20 | tail -1
$PREFIX/bin/$TARGET-g++ --version | head -1
VMSCRIPT
