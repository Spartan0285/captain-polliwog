#!/bin/bash
# Builds SQLite for PowerPC into /opt/ppc/sqlite, as a libsqlite3.dylib that
# loads from the app's Frameworks folder. Leopard's own SQLite (3.4) is older
# than WebCore allows (3.6.16), so Leopard WebKit bundles one too; this uses
# the current release. Built for the G3 and Tiger, so every variant can use it.
# Run inside the cross-build VM.
set -e
export PATH=/opt/ppc/bin:$PATH
VERSION=3530400
SHA3=454e45f61c6bd75b7420e7190732dea03ce6639c63ada47bbc592f67fc340338  # from sqlite.org/download.html
R=/opt/ppc/runtime

mkdir -p ~/src/deps && cd ~/src/deps
[ -f sqlite-autoconf-$VERSION.tar.gz ] || wget -q https://sqlite.org/2026/sqlite-autoconf-$VERSION.tar.gz
python3 -c "import hashlib,sys; h=hashlib.sha3_256(open('sqlite-autoconf-$VERSION.tar.gz','rb').read()).hexdigest(); sys.exit(0 if h=='$SHA3' else 'SHA3-256 mismatch: '+h)"
rm -rf sqlite-autoconf-$VERSION && tar xzf sqlite-autoconf-$VERSION.tar.gz && cd sqlite-autoconf-$VERSION

powerpc-apple-darwin9-gcc -O2 -mmacosx-version-min=10.4 -D__DARWIN_UNIX03=0 -dynamiclib \
    -DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_ENABLE_LOCKING_STYLE=1 \
    -install_name @executable_path/../Frameworks/libsqlite3.dylib \
    -compatibility_version 9.0.0 -current_version $((VERSION / 100)).0.0 \
    -nodefaultlibs -static-libgcc -Wl,-no_function_starts,-no_data_in_code_info,-no_version_load_command,-no_source_version \
    sqlite3.c -o libsqlite3.dylib $R/libgcc_s.1.dylib -lgcc -lSystem

sudo mkdir -p /opt/ppc/sqlite/lib /opt/ppc/sqlite/include
sudo cp libsqlite3.dylib /opt/ppc/sqlite/lib/
sudo cp sqlite3.h sqlite3ext.h /opt/ppc/sqlite/include/
