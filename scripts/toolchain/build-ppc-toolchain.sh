#!/bin/bash
# Builds a PowerPC Mac OS X cross toolchain -- GCC 6.5 with C, C++,
# Objective-C and Objective-C++, plus Apple's cctools and ld64 with PowerPC
# support -- inside a Linux VM on a modern Mac, so the old Macs do not spend
# hours compiling. GCC 6 matches what Leopard WebKit 604 was built with.
#
# Run on the Mac:   scripts/toolchain/build-ppc-toolchain.sh
#
# Needs Lima (brew install lima) and the 10.5 and 10.4u SDKs zipped from a
# PowerPC Mac's /Developer/SDKs into ~/polliwog-build/sdks (with ditto -c -k
# --keepParent, which keeps their symlinks).
#
# Notes from getting it working:
# - Debian 11 does not boot under Apple's virtualization in Lima; Ubuntu 20.04
#   does, still packages Python 2.7 (WebKit 604's scripts need it), and its
#   GCC 9 builds GCC 6.5 cleanly with -std=gnu++98.
# - cctools-port's PowerPC branch is 877.8-ld64-253.9-ppc. Its ld64 applied a
#   branch's addend twice when routing it through a branch island, which broke
#   WebCore (bigger than PowerPC's branch reach); fixed by a patch here.
# - collect2 runs dsymutil after linking, which does not exist on Linux; a
#   no-op stand-in is enough, since no debug-symbol bundles are wanted.
# - The default CPU for powerpc-apple-darwin9 is the G4, which marks every
#   program linked with GCC's runtime as G4-only. --with-cpu=750 and runtime
#   libraries built for 10.4 make one compiler serve the G3 on Tiger too.
# - ld64-253 cannot read the 10.4u SDK's crt1.o, so Tiger programs are linked
#   against the 10.5 SDK with -mmacosx-version-min=10.4.
# - GCC 6 crashes (objc_eh_runtime_type) on C++ try/catch inside
#   Objective-C++. WebKit builds with C++ exceptions off, so it is unaffected;
#   Objective-C @try/@catch works.
set -e

VM=ppcbuild

limactl list -q | grep -qx $VM || \
    limactl start --name=$VM --tty=false --vm-type=vz --cpus 8 --memory 12 --disk 40 \
        --set '.portForwards += [{"guestPort":3632,"hostIP":"0.0.0.0"}]' template:ubuntu-20.04

# The repository, which Lima's read-only mount of the home folder makes
# visible inside the VM at the same path.
REPO=$(cd "$(dirname "$0")/../.." && pwd)

limactl shell $VM -- env REPO="$REPO" bash -s <<'VMSCRIPT'
set -e
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq build-essential clang llvm-dev \
    libxml2-dev uuid-dev libssl-dev cmake git texinfo flex bison gperf libgmp-dev \
    libmpfr-dev libmpc-dev zlib1g-dev python2.7 ruby perl distcc autoconf automake \
    libtool wget xz-utils unzip file pkg-config rsync

mkdir -p ~/src && cd ~/src
sudo mkdir -p /opt/ppc/SDKs
# Lima mounts the Mac's home folder read-only at the same path.
for sdk in /Users/*/polliwog-build/sdks/sdk105.zip /Users/*/polliwog-build/sdks/sdk104.zip; do
    ( cd /opt/ppc/SDKs && sudo unzip -qo "$sdk" )
done

if [ ! -x /opt/ppc/bin/powerpc-apple-darwin9-ld ]; then
    rm -rf cctools-port
    git clone -q --depth 1 -b 877.8-ld64-253.9-ppc https://github.com/tpoechtrager/cctools-port.git
    ( cd cctools-port && patch -p1 < "$REPO/scripts/toolchain/ld64-branch-island-addend.patch" )
    cd cctools-port/cctools
    ./autogen.sh
    CC=clang CXX=clang++ ./configure --prefix=/opt/ppc --target=powerpc-apple-darwin9
    make -j8
    sudo make install
    cd ~/src
fi

printf '#!/bin/sh\nexit 0\n' | sudo tee /opt/ppc/bin/powerpc-apple-darwin9-dsymutil >/dev/null
sudo cp /opt/ppc/bin/powerpc-apple-darwin9-dsymutil /opt/ppc/bin/dsymutil
sudo chmod +x /opt/ppc/bin/*dsymutil

# One stub library taken from the Tiger SDK: see the note in build-xml.sh.
# Everything else links against the 10.5 SDK as usual.
sudo mkdir -p /opt/ppc/tiger-stubs
sudo cp -L /opt/ppc/SDKs/MacOSX10.4u.sdk/usr/lib/libiconv.dylib /opt/ppc/tiger-stubs/libiconv.dylib

if [ ! -d gcc-6.5.0 ]; then
    wget -q https://ftp.gnu.org/gnu/gcc/gcc-6.5.0/gcc-6.5.0.tar.xz
    echo "7ef1796ce497e89479183702635b14bb7a46b53249209a5e0f999bebf4740945  gcc-6.5.0.tar.xz" | sha256sum -c
    tar -xJf gcc-6.5.0.tar.xz
    # Two instructions out of the prologue and epilogue of about a fifth of
    # every function GCC compiles for us. See the patch's own header.
    ( cd gcc-6.5.0 && patch -p1 < "$REPO/scripts/toolchain/gcc-pr88343-darwin-picbase.patch" )
fi

export PATH=/opt/ppc/bin:$PATH
rm -rf build-gcc && mkdir build-gcc && cd build-gcc
../gcc-6.5.0/configure --target=powerpc-apple-darwin9 --prefix=/opt/ppc \
    --with-sysroot=/opt/ppc/SDKs/MacOSX10.5.sdk \
    --with-as=/opt/ppc/bin/powerpc-apple-darwin9-as --with-ld=/opt/ppc/bin/powerpc-apple-darwin9-ld \
    --enable-languages=c,c++,objc,obj-c++ --disable-multilib --disable-nls --disable-bootstrap \
    --disable-libsanitizer --disable-libcilkrts --disable-libgomp --disable-libitm \
    --with-dwarf2 --with-cpu=750 \
    CFLAGS="-O2 -g0" CXXFLAGS="-O2 -g0 -std=gnu++98" \
    CFLAGS_FOR_TARGET="-O2 -g0 -mcpu=750 -mmacosx-version-min=10.4" \
    CXXFLAGS_FOR_TARGET="-O2 -g0 -mcpu=750 -mmacosx-version-min=10.4"
make -j8
sudo env PATH=$PATH make install
/opt/ppc/bin/powerpc-apple-darwin9-g++ --version | head -1
cd ~/src

# Unprefixed tool names, which collect2 and some configure scripts look for.
sudo mkdir -p /opt/ppc/powerpc-apple-darwin9/bin
for tool in ar as dsymutil install_name_tool ld libtool lipo nm otool ranlib strip; do
    sudo ln -sf /opt/ppc/bin/powerpc-apple-darwin9-$tool /opt/ppc/powerpc-apple-darwin9/bin/$tool
done

# GCC's shared runtime, renamed to load from an app's Frameworks folder
# (see ppc-darwin.cmake for why it is shared).
L=/opt/ppc/powerpc-apple-darwin9/lib
R=/opt/ppc/runtime
F=@executable_path/../Frameworks
INT=/opt/ppc/bin/powerpc-apple-darwin9-install_name_tool
sudo mkdir -p $R
sudo cp $L/libstdc++.6.dylib $L/libgcc_s.1.dylib $R/
sudo $INT -id $F/libgcc_s.1.dylib $R/libgcc_s.1.dylib
sudo $INT -id $F/libstdc++.6.dylib -change $L/libgcc_s.1.dylib $F/libgcc_s.1.dylib $R/libstdc++.6.dylib

sudo mkdir -p /opt/ppc/share
sudo cp "$REPO/scripts/toolchain/ppc-darwin.cmake" /opt/ppc/share/

# ICU 55.2, the version Leopard WebKit 604 bundles, as one libicucore.dylib
# with unrenamed symbols. Cross-building ICU needs a native build for its tools.
if [ ! -f /opt/ppc/icu/lib/libicucore.dylib ]; then
    [ -f icu4c-55_2-src.tgz ] || wget -q https://github.com/unicode-org/icu/releases/download/release-55-2/icu4c-55_2-src.tgz
    echo "eda2aa9f9c787748a2e2d310590720ca8bcc6252adf6b4cfb03b65bef9d66759  icu4c-55_2-src.tgz" | sha256sum -c
    rm -rf icu icu-host icu-ppc && tar -xzf icu4c-55_2-src.tgz
    mkdir icu-host && ( cd icu-host && ../icu/source/configure --disable-tests --disable-samples && make -j8 )
    mkdir icu-ppc && cd icu-ppc
    CC=powerpc-apple-darwin9-gcc CXX=powerpc-apple-darwin9-g++ \
    CFLAGS="-O2 -mmacosx-version-min=10.4" CXXFLAGS="-O2 -mmacosx-version-min=10.4" \
    LDFLAGS="-mmacosx-version-min=10.4 -static-libgcc" \
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
fi

# The other libraries WebKit bundles.
[ -f /opt/ppc/sqlite/lib/libsqlite3.dylib ] || bash "$REPO/scripts/toolchain/build-sqlite.sh"
[ -f /opt/ppc/xml/lib/libxml2.dylib ] || bash "$REPO/scripts/toolchain/build-xml.sh"
[ -f /opt/ppc/ots/lib/libots.a ] || bash "$REPO/scripts/toolchain/build-ots.sh"
VMSCRIPT
