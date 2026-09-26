#!/bin/bash
# Build a self-contained Captain Polliwog.app for someone to try by hand:
# the app as last built on a PowerPC Mac, plus a packaged engine, zipped.
#
# The app finds its engine through an absolute DYLD_FRAMEWORK_PATH in the
# bundle's LSEnvironment, so the path has to be decided here rather than
# discovered at launch. It is written as /Applications/<name>.app, which is
# where the zip is meant to be unpacked. Anywhere else and the app quietly
# loads Mac OS X's own WebKit instead -- it still runs, which is what makes
# it worth saying twice.
#
# Usage:
#   make-test-app.sh <variant> <app-name> [app-host]
#     e.g. make-test-app.sh leopard-g4-jit-pgo "Captain Polliwog PGO"
set -eu

VARIANT=${1:?usage: make-test-app.sh variant app-name [app-host]}
NAME=${2:?usage: make-test-app.sh variant app-name [app-host]}
APP_HOST=${3:-pbg4}
STAGE=$HOME/polliwog-build/stage/testapp-$VARIANT
ZIP=$HOME/polliwog-build/stage/$VARIANT/Frameworks.zip
OUT=$HOME/polliwog-build/$NAME.zip

[ -f "$ZIP" ] || { echo "no $ZIP -- run package-webkit.sh $VARIANT" >&2; exit 1; }

rm -rf "$STAGE" && mkdir -p "$STAGE"

echo "==> fetching the app from $APP_HOST"
ssh -n -o ConnectTimeout=90 "$APP_HOST" \
    'cd ~/CaptainPolliwog/build && rm -f /tmp/cp-app.zip && ditto -c -k --norsrc --keepParent "Captain Polliwog.app" /tmp/cp-app.zip'
scp -O -q "$APP_HOST:/tmp/cp-app.zip" "$STAGE/"
ditto -x -k "$STAGE/cp-app.zip" "$STAGE"
rm -f "$STAGE/cp-app.zip"

APP="$STAGE/$NAME.app"
[ -d "$STAGE/Captain Polliwog.app" ] || { echo "no app came back from $APP_HOST" >&2; exit 1; }
mv "$STAGE/Captain Polliwog.app" "$APP"

echo "==> adding the $VARIANT engine"
rm -rf "$APP/Contents/Frameworks"
ditto -x -k "$ZIP" "$APP/Contents" 2>/dev/null || (cd "$APP/Contents" && unzip -q "$ZIP")

# Two apps both called Captain Polliwog confuse LaunchServices, which picks
# by bundle identifier and may well open the wrong one. A build meant for
# comparing against another gets its own identifier and its own name.
ID=$(echo "$NAME" | tr 'A-Z ' 'a-z-')
defaults write "$APP/Contents/Info" CFBundleIdentifier "org.captainpolliwog.$ID"
defaults write "$APP/Contents/Info" CFBundleName "$NAME"
defaults write "$APP/Contents/Info" LSEnvironment -dict \
    DYLD_FRAMEWORK_PATH "/Applications/$NAME.app/Contents/Frameworks"
plutil -convert xml1 "$APP/Contents/Info.plist"

echo "==> zipping"
rm -f "$OUT"
( cd "$STAGE" && ditto -c -k --sequesterRsrc --keepParent "$NAME.app" "$OUT" )
echo "$OUT"
du -h "$OUT" | awk '{print "   " $1}'
echo "   unpack into /Applications -- the engine path is absolute"
