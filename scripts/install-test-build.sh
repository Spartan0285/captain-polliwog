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
ditto -x -k "$frameworks" "$app/Contents/"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" \
    -c "Add :LSEnvironment:DYLD_FRAMEWORK_PATH string /Applications/Captain Polliwog.app/Contents/Frameworks" \
    "$app/Contents/Info.plist"
( cd "$stage" && ditto -c -k --norsrc --keepParent "Captain Polliwog.app" install.zip )

scp -4 -O -q "$stage/install.zip" "$host:/tmp/cp-install.zip"
ssh -4 -o ConnectTimeout=90 "$host" '
    A="/Applications/Captain Polliwog.app"
    killall CaptainPolliwog 2>/dev/null; sleep 2
    rm -rf "$A" && ditto -x -k /tmp/cp-install.zip /Applications/
    # LaunchServices moved into CoreServices in 10.5; on Tiger it is still
    # under ApplicationServices.
    for ls in /System/Library/Frameworks/{CoreServices,ApplicationServices}.framework/Frameworks/LaunchServices.framework/Support/lsregister; do
        [ -x "$ls" ] && "$ls" -f "$A" && break
    done
    echo "==> installed: $(ls "$A/Contents/Frameworks" | wc -l | tr -d " ") bundled frameworks and libraries"'
