#!/bin/bash
# Assemble a release bundle of Captain Polliwog: the app as built on a
# PowerPC Mac, with both engines inside it, zipped and hashed.
#
# It does NOT sign anything. The Ed25519 key that signs the update feed is
# the one thing that makes every installed copy accept an update, so
# producing a signature is Adam's step and not this script's. What comes out
# of here is a zip, its sha256, and the exact command to run next.
#
# The bundle carries two engines and chooses between them itself: main.m
# looks for Contents/Frameworks first, falls back to Contents/Frameworks-10.4
# if that will not load, and re-execs with CP_ENGINE_CHOSEN set. So nothing
# here rewrites LSEnvironment, and the app works wherever it is put -- unlike
# the side-by-side comparison builds, which are pinned to /Applications.
#
# Usage:
#   make-release.sh <version> [app-host] [leopard-variant] [tiger-variant]
#     e.g. make-release.sh 0.3.4
set -eu

VERSION=${1:?usage: make-release.sh version [app-host] [leopard-variant] [tiger-variant]}
APP_HOST=${2:-pbg4}
LEOPARD=${3:-leopard-g4-jit}
TIGER=${4:-tiger-g3-jit}

cd "$(dirname "$0")/.."
STAGE=$HOME/polliwog-build/stage/release-$VERSION
OUT=$HOME/polliwog-build/CaptainPolliwog-$VERSION.zip

for v in "$LEOPARD" "$TIGER"; do
    [ -f "$HOME/polliwog-build/stage/$v/Frameworks.zip" ] || {
        echo "no packaged engine for $v -- run package-webkit.sh $v" >&2; exit 1; }
done

rm -rf "$STAGE" && mkdir -p "$STAGE"

echo "==> app from $APP_HOST"
ssh -n -o ConnectTimeout=90 "$APP_HOST" \
    'cd ~/CaptainPolliwog/build && rm -f /tmp/cp-app.zip && ditto -c -k --norsrc --keepParent "Captain Polliwog.app" /tmp/cp-app.zip'
scp -O -q "$APP_HOST:/tmp/cp-app.zip" "$STAGE/"
ditto -x -k "$STAGE/cp-app.zip" "$STAGE"
rm -f "$STAGE/cp-app.zip"
APP="$STAGE/Captain Polliwog.app"
[ -d "$APP" ] || { echo "no app came back from $APP_HOST" >&2; exit 1; }

built=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)
[ "$built" = "$VERSION" ] || {
    echo "the app on $APP_HOST is $built, not $VERSION -- rebuild it first" >&2; exit 1; }

echo "==> Leopard engine ($LEOPARD) -> Frameworks"
rm -rf "$APP/Contents/Frameworks"
ditto -x -k "$HOME/polliwog-build/stage/$LEOPARD/Frameworks.zip" "$APP/Contents"

echo "==> Tiger engine ($TIGER) -> Frameworks-10.4"
# package-webkit.sh already names the Tiger output Frameworks-10.4 inside
# the zip, where the Leopard one is plain Frameworks. Take whichever
# directory is actually in there rather than assuming either.
rm -rf "$APP/Contents/Frameworks-10.4"
tmp=$(mktemp -d)
ditto -x -k "$HOME/polliwog-build/stage/$TIGER/Frameworks.zip" "$tmp"
inner=$(ls "$tmp")
[ -d "$tmp/$inner" ] || { echo "nothing usable in the $TIGER zip" >&2; exit 1; }
mv "$tmp/$inner" "$APP/Contents/Frameworks-10.4"
rm -rf "$tmp"

for d in Frameworks Frameworks-10.4; do
    [ -d "$APP/Contents/$d" ] || { echo "missing $d" >&2; exit 1; }
    printf '    %-16s %s\n' "$d" "$(du -sh "$APP/Contents/$d" | awk '{print $1}')"
done

echo "==> zipping"
rm -f "$OUT"
( cd "$STAGE" && ditto -c -k --sequesterRsrc --keepParent "Captain Polliwog.app" "$OUT" )

SHA=$(shasum -a 256 "$OUT" | awk '{print $1}')
SIZE=$(stat -f %z "$OUT")
cat <<EOF

  zip     $OUT
  size    $SIZE bytes ($(du -h "$OUT" | awk '{print $1}'))
  sha256  $SHA

Next, and only you can do these:

  scripts/make-appcast.py $VERSION "$OUT" notes-$VERSION.txt
  git add updates/appcast.plist && git commit -m "Release $VERSION" && git push

then attach the zip to a GitHub release tagged v$VERSION.
EOF
