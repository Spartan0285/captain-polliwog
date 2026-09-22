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
#   C++ runtime) load from @executable_path/../Frameworks.
set -e
VARIANT=$1
[ -n "$VARIANT" ] || { echo "usage: $0 leopard-g4" >&2; exit 1; }
BUILD=$HOME/build/$VARIANT/lib
SRC=$HOME/src/webkit-604/Source
OUT=/Users/adam/polliwog-build/stage/$VARIANT
FW=$OUT/Frameworks
INT=/opt/ppc/bin/powerpc-apple-darwin9-install_name_tool
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
   /opt/ppc/runtime/libstdc++.6.dylib /opt/ppc/runtime/libgcc_s.1.dylib "$FW/"
cp -L /opt/ppc/xml/lib/libxml2.dylib "$FW/$(basename "$(readlink /opt/ppc/xml/lib/libxml2.dylib)")"
cp -L /opt/ppc/xml/lib/libxslt.dylib "$FW/$(basename "$(readlink /opt/ppc/xml/lib/libxslt.dylib)")"

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

cd "$OUT" && rm -f Frameworks.zip && zip -qry Frameworks.zip Frameworks  # -y keeps symlinks
du -sh "$FW" "$OUT/Frameworks.zip"
