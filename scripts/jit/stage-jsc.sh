#!/bin/bash
# Assemble a runnable jsc kit from a cross-build directory and copy it to a
# PowerPC Mac.
#
# The binaries keep the install names the build gave them, which are
# absolute paths inside the build VM. Nothing rewrites them: jsc is run with
# DYLD_FRAMEWORK_PATH and DYLD_LIBRARY_PATH pointing at the kit, and dyld
# looks there first -- for the framework by its bundle path, and for the
# dylibs by leaf name. That is how the earlier kits in polliwog-build were
# made, and rewriting install_name on a 44MB instrumented framework is
# slower and no more correct.
#
# Run inside the build VM:
#   stage-jsc.sh <build-variant-dir> <kit-name>
#     e.g. stage-jsc.sh leopard-g4-jit-pgo jsckit-pgogen
#
# Then on the Mac side, scripts/jit/run-jsc.sh copies it over and runs it.
set -eu

VARIANT=${1:?usage: stage-jsc.sh <build-dir-name> <kit-name>}
KITNAME=${2:?usage: stage-jsc.sh <build-dir-name> <kit-name>}
B=$HOME/build/$VARIANT
OUT=/Users/adam/polliwog-build/$KITNAME
RUNTIME=${RUNTIME:-/opt/ppc/runtime}

[ -x "$B/bin/jsc" ] || { echo "no jsc in $B/bin" >&2; exit 1; }

rm -rf "$OUT" && mkdir -p "$OUT"
cp -R "$B/lib/JavaScriptCore.framework" "$OUT/"
cp "$B/bin/jsc" "$OUT/jsc"

# The engine's own runtime, bundled as the app bundles it: one shared
# libstdc++ and one libgcc for every image, because emulated thread-local
# storage keeps its state per copy of libgcc.
for lib in libstdc++.6.dylib libgcc_s.1.dylib; do
    [ -f "$RUNTIME/$lib" ] && cp "$RUNTIME/$lib" "$OUT/"
done
cp /opt/ppc/icu/lib/libicucore.dylib "$OUT/" 2>/dev/null || true

echo "kit: $OUT"
du -sh "$OUT" | awk '{print "  size: " $1}'
ls "$OUT"
