#!/bin/sh
# Installs a test build of Captain Polliwog with the bundled WebKit engine in
# /Applications on a PowerPC Mac running Leopard: the app as last built on
# the iBook (scripts/remote-build.sh g4) plus the frameworks packaged by
# scripts/toolchain/package-webkit.sh. The app finds its engine through
# LSEnvironment, so it must stay in /Applications; moved elsewhere it falls
# back to the system WebKit.
# Usage: scripts/install-test-build.sh host [variant]     e.g. pbg4 leopard-g4
set -e
cd "$(dirname "$0")/.."
host=${1:?usage: install-test-build.sh host [variant]}
variant=${2:-leopard-g4}
# Which Mac last built the app. It was the iBook while that was the only one
# set up for it; any PowerPC Mac with gcc-4.0, the 10.4u SDK and
# ~/polliwog-deps can do it, and building on the machine being tested saves
# a hop.
app_host=${APP_HOST:-g4}
stage=$HOME/polliwog-build/stage/install-$variant
app="$stage/Captain Polliwog.app"
frameworks=$HOME/polliwog-build/stage/$variant/Frameworks.zip

rm -rf "$stage" && mkdir -p "$stage"
ssh -o ConnectTimeout=90 "$app_host" 'cd ~/CaptainPolliwog/build && rm -f /tmp/cp-app.zip && ditto -c -k --norsrc --keepParent "Captain Polliwog.app" /tmp/cp-app.zip'
scp -O -q "$app_host":/tmp/cp-app.zip "$stage/"
ditto -x -k "$stage/cp-app.zip" "$stage"
# package-webkit.sh names the Tiger output Frameworks-10.4 inside the zip and
# the Leopard one plain Frameworks, so extracting blind leaves the engine in a
# directory LSEnvironment below does not name. It then loads nothing, silently,
# and the app falls back to the system WebKit - which on Tiger is WebKit 419
# and renders apple.com as a column of unstyled text. That looked exactly like
# the browser being broken on the G3, and it is what it was.
#
# Whatever the zip calls it, it is installed as Frameworks: main.m tries that
# name first regardless of which engine is inside.
ditto -x -k "$frameworks" "$app/Contents/"
inner=$(ls "$app/Contents" | grep -E '^Frameworks' | head -1)
[ -n "$inner" ] || { echo "no Frameworks directory in $frameworks" >&2; exit 1; }
# Point the app at whatever the zip called it, and do NOT rename the
# directory. The Tiger engine's WebKit links its shim as
# @executable_path/../Frameworks-10.4/libTigerShim.dylib, so that name is
# load-bearing: renamed to Frameworks the engine is found and then will not
# load, and the app dies at launch with "Library not loaded". Left alone but
# unnamed here, it is never found at all and the app quietly runs on Tiger's
# own WebKit 419, which is what made apple.com look broken on the G3.
echo "==> engine from $frameworks -> Contents/$inner"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" \
    -c "Add :LSEnvironment:DYLD_FRAMEWORK_PATH string /Applications/Captain Polliwog.app/Contents/$inner" \
    "$app/Contents/Info.plist"
( cd "$stage" && ditto -c -k --norsrc --keepParent "Captain Polliwog.app" install.zip )

scp -4 -O -q "$stage/install.zip" "$host:/tmp/cp-install.zip"
ssh -4 -o ConnectTimeout=90 "$host" "inner='$inner'"'
    A="/Applications/Captain Polliwog.app"
    killall CaptainPolliwog 2>/dev/null; sleep 2
    rm -rf "$A" && ditto -x -k /tmp/cp-install.zip /Applications/
    # LaunchServices moved into CoreServices in 10.5; on Tiger it is still
    # under ApplicationServices.
    for ls in /System/Library/Frameworks/{CoreServices,ApplicationServices}.framework/Frameworks/LaunchServices.framework/Support/lsregister; do
        [ -x "$ls" ] && "$ls" -f "$A" && break
    done
    echo "==> installed: $(ls "$A/Contents/'"$inner"'" | wc -l | tr -d " ") bundled frameworks and libraries"'
