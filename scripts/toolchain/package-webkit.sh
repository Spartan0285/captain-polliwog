#!/bin/bash
# Stages a WebKit build as the Frameworks folder of an app bundle, laid out as
# Leopard WebKit ships inside Safari.app. Run inside the cross-build VM:
#   package-webkit.sh leopard-g4
# Output: ~/polliwog-build/stage/<variant>/Frameworks and Frameworks.zip.
#
# - WebKit.framework holds the WebKitLegacy code, as on Mac OS X 10.5.
# - Each framework keeps its system install name
#   (/System/Library/Frameworks/...), so an app linked against the system
#   WebKit picks these up through DYLD_FRAMEWORK_PATH; among themselves they
#   refer to each other through @loader_path.
# - The libraries WebKit bundles (ICU, SQLite, libxml2, libxslt, and GCC's
#   C++ runtime) load from @executable_path/../<folder>, where the folder is
#   Frameworks for the Leopard engine and Frameworks-10.4 for the Tiger one.
set -e
VARIANT=$1
[ -n "$VARIANT" ] || { echo "usage: $0 leopard-g4" >&2; exit 1; }

# A variant built by the GCC 14 toolchain carries that toolchain's runtime,
# not GCC 6's: one libstdc++ per process, and it has to be the one the
# frameworks were built against. It also needs libemutls, which is where the
# emulated thread-local state lives when every image shares one copy
# (build-modern-emutls.sh).
case $VARIANT in
*-gcc14) PPC_ROOT=/opt/ppc-modern ;;
*)       PPC_ROOT=/opt/ppc ;;
esac
BUILD=$HOME/build/$VARIANT/lib
SRC=$HOME/src/webkit-604/Source
OUT=/Users/adam/polliwog-build/stage/$VARIANT
# One application bundle carries both engines, in a folder each: the Leopard
# one in Frameworks and the Tiger one beside it. src/main.m picks whichever
# this Mac can run and points dyld at that folder. The libraries inside must
# therefore name their own folder, not the other engine's.
case $VARIANT in
    tiger-*) FOLDER=Frameworks-10.4 ;;
    *)       FOLDER=Frameworks ;;
esac
FW=$OUT/$FOLDER
INT=/opt/ppc/bin/powerpc-apple-darwin9-install_name_tool
OTOOL=/opt/ppc/bin/powerpc-apple-darwin9-otool
SYS=/System/Library/Frameworks
# The oldest system this engine runs on, written into every framework's
# Info.plist as LSMinimumSystemVersion. The app reads it before loading
# anything (src/main.m) and only switches to the bundled engine when it is one
# this Mac can run: pointing Tiger at a Leopard engine would stop the browser
# launching at all, which is worse than the system WebKit it falls back to.
case $VARIANT in
    tiger-*) MINIMUM=10.4 ;;
    *)       MINIMUM=10.5 ;;
esac
# And the processor. A build for the G4 uses AltiVec and instructions a 750
# has not got, so a G3 cannot run it at all - not slowly, at all. The G3
# build runs on both, which is why it is the one a Mac without a vector unit
# is given, whatever system it is on. Written here so that main.m can ask the
# engine rather than guess from the folder it sits in.
case $VARIANT in
    tiger-*) NEEDS_VECTOR=false ;;
    *)       NEEDS_VECTOR=true ;;
esac
# Apple's style: an OS digit, then WebKit's version - 4604 for 10.4, 5604 for
# 10.5. The About window strips the first digit to show "WebKit 604.5.6".
VERSION=${MINIMUM#10.}604.5.6

rm -rf "$OUT" && mkdir -p "$FW"

# framework NAME BINARY ID IDENTIFIER
framework() {
    local name=$1 binary=$2 id=$3 identifier=$4 dir=$FW/$1.framework
    mkdir -p "$dir/Versions/A/Resources"
    cp "$binary" "$dir/Versions/A/$name"
    $INT -id "$id" "$dir/Versions/A/$name"
    cat > "$dir/Versions/A/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>English</string>
	<key>CFBundleExecutable</key>
	<string>$name</string>
	<key>CFBundleIdentifier</key>
	<string>$identifier</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$name</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION%%.*}</string>
	<key>CFBundleVersion</key>
	<string>$VERSION</string>
	<key>LSMinimumSystemVersion</key>
	<string>$MINIMUM</string>
	<key>CPRequiresVectorUnit</key>
	<$NEEDS_VECTOR/>
</dict>
</plist>
EOF
    ln -s A "$dir/Versions/Current"
    ln -s Versions/Current/$name "$dir/$name"
    ln -s Versions/Current/Resources "$dir/Resources"
}

framework JavaScriptCore "$BUILD/JavaScriptCore.framework/Versions/A/JavaScriptCore" \
    $SYS/JavaScriptCore.framework/Versions/A/JavaScriptCore com.apple.JavaScriptCore
framework WebCore "$BUILD/WebCore.framework/Versions/A/WebCore" \
    $SYS/WebKit.framework/Versions/A/Frameworks/WebCore.framework/Versions/A/WebCore com.apple.WebCore
framework WebKit "$BUILD/WebKitLegacy.framework/Versions/A/WebKitLegacy" \
    $SYS/WebKit.framework/Versions/A/WebKit com.apple.WebKit

# References between the three, from build paths to @loader_path.
for name in JavaScriptCore WebCore WebKit; do
    binary=$FW/$name.framework/Versions/A/$name
    for dep in JavaScriptCore WebCore WebKitLegacy; do
        target=$dep; [ $dep = WebKitLegacy ] && target=WebKit
        $INT -change "$BUILD/$dep.framework/Versions/A/$dep" \
            "@loader_path/../../../$target.framework/Versions/A/$target" "$binary"
    done
done

# Resources, as the Xcode projects copy them.
R=$FW/WebCore.framework/Versions/A/Resources
cp -R "$SRC"/WebCore/Resources/* "$R/"
cp -R "$SRC/WebCore/English.lproj" "$R/"
cp "$SRC"/WebCore/Modules/mediacontrols/mediaControlsApple.{css,js} "$SRC/WebCore/html/shadow/meterElementShadow.css" "$R/"
mkdir -p "$R/audio" && cp "$SRC"/WebCore/platform/audio/resources/*.wav "$R/audio/"
R=$FW/WebKit.framework/Versions/A/Resources
cp -R "$SRC/WebKitLegacy/English.lproj" "$R/"
cp "$SRC/WebKitLegacy/mac/Resources/url_icon.tiff" "$R/"

# Bundled libraries.
cp /opt/ppc/icu/lib/libicucore.dylib /opt/ppc/sqlite/lib/libsqlite3.dylib \
   $PPC_ROOT/runtime/libstdc++.6.dylib $PPC_ROOT/runtime/libgcc_s.1.dylib "$FW/"
for extra in libemutls.1.dylib libgcc_s.1.1.dylib libgcc_ehs.1.1.dylib; do
    [ -f "$PPC_ROOT/runtime/$extra" ] && cp "$PPC_ROOT/runtime/$extra" "$FW/"
done
cp -L /opt/ppc/xml/lib/libxml2.dylib "$FW/$(basename "$(readlink /opt/ppc/xml/lib/libxml2.dylib)")"
cp -L /opt/ppc/xml/lib/libxslt.dylib "$FW/$(basename "$(readlink /opt/ppc/xml/lib/libxslt.dylib)")"

# GCC built libstdc++ naming the system's libgcc_s as well as its own, and
# the unwinder functions it imports are hinted at the system one. Leopard's
# libgcc_s has them; Tiger's has not, so on 10.4 the first C++ exception the
# engine throws takes the application with it - and because that reference
# is bound lazily, it happens on whatever page throws first rather than at
# startup, which makes it look like the page. Point it at the copy bundled
# here, which is the one everything else already uses.
for binary in "$FW"/*.dylib "$FW"/*.framework/Versions/A/[A-Z]*; do
    [ -f "$binary" ] || continue
    for dep in $($OTOOL -L "$binary" | awk '{print $1}' | grep '^/usr/lib/libgcc_s\.'); do
        $INT -change "$dep" "@executable_path/../$FOLDER/libgcc_s.1.dylib" "$binary"
    done
done

# Tiger: the stand-ins the frameworks are linked against (engine/tiger-shim),
# and the G3 stamp. Apple's WebKitSystemInterface objects are marked for the
# G4, which raises whatever links them; dyld then refuses that binary on a
# G3 and falls back to the system WebKit without saying so. Nothing that is
# actually linked uses AltiVec - checked here rather than assumed - so the
# binaries are stamped back to ppc750.
case $VARIANT in
tiger-*)
    cp /opt/ppc/tiger-shim/libTigerShim.dylib "$FW/"
    OTOOL=/opt/ppc/bin/powerpc-apple-darwin9-otool
    for binary in $FW/*.framework/Versions/A/[A-Z]* $FW/*.dylib; do
        [ -f "$binary" ] || continue
        # The bundled libraries were built naming ../Frameworks, which in this
        # bundle is the Leopard engine. Point them at their own folder.
        id=$($OTOOL -D "$binary" | tail -1)
        case $id in
        @executable_path/../Frameworks/*)
            $INT -id "@executable_path/../$FOLDER/${id##*/}" "$binary" ;;
        esac
        for dep in $($OTOOL -L "$binary" | awk '{print $1}' | grep '^@executable_path/../Frameworks/'); do
            $INT -change "$dep" "@executable_path/../$FOLDER/${dep##*/}" "$binary"
        done
        vector=$(/opt/ppc/bin/powerpc-apple-darwin9-otool -tV "$binary" 2>/dev/null \
            | grep -cE '[[:space:]](lvx|stvx|vperm|vspltw|vsel|vmsum|vmaddfp|vaddubm)[[:space:]]') || true
        if [ "${vector:-0}" -gt 0 ]; then
            echo "!! $binary has $vector AltiVec instructions; leaving its CPU stamp alone" >&2
            continue
        fi
        python3 "$(dirname "$0")/stamp-ppc750.py" "$binary"
    done

    # Nothing here may ask 10.4 for something it has not got. Apple's GCC
    # defines _NONSTD_SOURCE when told to target 10.4, which is what stops
    # the 10.5 SDK renaming open(), close() and mktime() to their $UNIX2003
    # conformance variants; FSF's GCC has no such rule, so a library built
    # without it asks for functions Tiger's libSystem never had. The same
    # goes for anything Leopard added to zlib or to libgcc's unwinder.
    #
    # A missing one of these does not stop the application starting, because
    # it is bound lazily. It starts, renders, and disappears on the first
    # page that reaches the code that calls it. Which is why this is checked
    # here, and not left to be discovered as a crash report from a G3.
    BASELINE=$(dirname "$0")/../../engine/tiger-baseline-symbols.txt
    NM=/opt/ppc/bin/powerpc-apple-darwin9-nm
    absent=0
    for binary in $FW/*.framework/Versions/A/[A-Z]* $FW/*.dylib; do
        [ -f "$binary" ] || continue
        # Weak imports are the design - everything Leopard added is linked
        # that way and dyld leaves it null. It is the others that matter.
        $NM -m "$binary" 2>/dev/null | grep -v "weak external" \
          | awk '/\(undefined\)/ && /\(from (libSystem|libz|libgcc_s)\)/ {
                sym = ""; from = "";
                for (i = 1; i <= NF; i++) {
                    if (substr($i, 1, 1) == "_") sym = $i;
                    if ($i == "(from") { from = $(i+1); sub(/\)$/, "", from); }
                }
                # libSystem is only checked for the conformance variants;
                # the rest of it has not changed under us.
                if (from == "libSystem" && sym !~ /UNIX2003/) next;
                print sym;
            }' | sort -u | while read -r sym; do
                grep -qx "$sym" "$BASELINE" || echo "$(basename "$binary") wants $sym"
            done
    done > /tmp/tiger-absent.$$
    if [ -s /tmp/tiger-absent.$$ ]; then
        echo "error: this build asks 10.4 for symbols it has not got:" >&2
        sed 's/^/  /' /tmp/tiger-absent.$$ >&2
        rm -f /tmp/tiger-absent.$$
        exit 1
    fi
    rm -f /tmp/tiger-absent.$$ ;;
esac

# Anything still pointing into the build machine is a packaging bug.
for binary in $FW/*.framework/Versions/A/* $FW/*.dylib; do
    [ -f "$binary" ] && [ ! -d "$binary" ] || continue
    case $binary in *.plist) continue ;; esac
    if /opt/ppc/bin/powerpc-apple-darwin9-otool -L "$binary" | grep -q "/home/\|/opt/ppc"; then
        echo "error: $binary still refers to the build machine:" >&2
        /opt/ppc/bin/powerpc-apple-darwin9-otool -L "$binary" | grep "/home/\|/opt/ppc" >&2
        exit 1
    fi
done

cd "$OUT" && rm -f Frameworks.zip && zip -qry Frameworks.zip "$FOLDER"  # -y keeps symlinks
du -sh "$FW" "$OUT/Frameworks.zip"
