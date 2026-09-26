#!/bin/bash
# Run Speedometer 3.1 in a named Captain Polliwog build on a PowerPC Mac and
# bring back a picture of the result.
#
# Reading the score is the awkward part. CPDebugScript evaluates JavaScript
# once, when the page finishes loading, which for Speedometer is before the
# run has started rather than after it has finished, and the score only
# exists at the end. Rather than add a polling hook to the app for the sake
# of a benchmark, this waits out the run and then uses screencapture, which
# Leopard and Tiger both have. The number is large and on screen; a picture
# of it is evidence enough, and it also shows whether the run finished at
# all instead of quietly stalling.
#
# Usage:
#   speedometer.sh <host> <app-name> <label> [minutes]
#     e.g. speedometer.sh pbg4 "Captain Polliwog PGO" pgo-1 9
set -eu

HOST=${1:?usage: speedometer.sh host app-name label [minutes]}
APP=${2:?usage: speedometer.sh host app-name label [minutes]}
LABEL=${3:?usage: speedometer.sh host app-name label [minutes]}
MINUTES=${4:-9}
URL='https://browserbench.org/Speedometer3.1/?startAutomatically=true'

cd "$(dirname "$0")/../.."
OUT=build/speedometer
mkdir -p "$OUT"

DOMAIN=$(ssh -n -o ConnectTimeout=60 "$HOST" \
    "defaults read '/Applications/$APP.app/Contents/Info' CFBundleIdentifier 2>/dev/null" | tr -d '\r')
[ -n "$DOMAIN" ] || { echo "no $APP.app in /Applications on $HOST" >&2; exit 1; }

echo "==> $LABEL: $APP, $MINUTES minutes"
ssh -n -o ConnectTimeout=90 "$HOST" "
    killall CaptainPolliwog 2>/dev/null; sleep 3
    defaults write '$DOMAIN' CPDebugURL '$URL'
    start=\$(date +%s)
    open '/Applications/$APP.app'
    i=0
    while [ \$i -lt $((MINUTES * 60)) ]; do
        sleep 15; i=\$((i + 15))
        ps -axco command | grep -qx CaptainPolliwog || { echo '  app exited early'; break; }
    done
    ps -axco pid,rss,command | awk '\$3==\"CaptainPolliwog\"{printf \"  memory %d MB\n\", \$2/1024}'
    /usr/sbin/screencapture -x /tmp/speedo-$LABEL.png 2>/dev/null || echo '  screencapture failed'
    osascript -e \"tell application \\\"$APP\\\" to quit\" 2>/dev/null || true
    sleep 3
    ps -axco command | grep -qx CaptainPolliwog && killall CaptainPolliwog 2>/dev/null
    defaults delete '$DOMAIN' CPDebugURL 2>/dev/null
    crash=\$(ls -t \$HOME/Library/Logs/CrashReporter/CaptainPolliwog* 2>/dev/null | head -1)
    if [ -n \"\$crash\" ] && [ \$(stat -f %m \"\$crash\") -ge \$start ]; then
        echo \"  CRASHED during the run\"
    fi
    true"
scp -O -q "$HOST:/tmp/speedo-$LABEL.png" "$OUT/$LABEL.png" 2>/dev/null \
    && echo "  screen -> $OUT/$LABEL.png" \
    || echo "  no screenshot came back"
