#!/bin/bash
# Run Speedometer 3.1 in a named Captain Polliwog build on a PowerPC Mac and
# bring back the score.
#
# Reading the score is the awkward part. CPDebugScript evaluates JavaScript
# once, when the page finishes loading, which for Speedometer is before the
# run has started; the score only exists at the end, nine minutes later.
#
# This used to wait out the run and then call screencapture. That never
# worked: screencapture run from an ssh session writes no file and prints no
# error, so every run produced no picture and no number, and the comparison
# it was written for was thrown away twice before anyone checked. The app now
# has CPDebugScriptInterval, which re-runs the script every few seconds and
# logs each answer, so the score is read from the log and the run stops as
# soon as it appears.
#
# Usage:
#   speedometer.sh <host> <app-name> <label> [minutes]
#     e.g. speedometer.sh pbg4 "Captain Polliwog PGO" pgo-1 12
set -eu

HOST=${1:?usage: speedometer.sh host app-name label [minutes]}
APP=${2:?usage: speedometer.sh host app-name label [minutes]}
LABEL=${3:?usage: speedometer.sh host app-name label [minutes]}
MINUTES=${4:-12}
URL='https://browserbench.org/Speedometer3.1/?startAutomatically=true'

cd "$(dirname "$0")/../.."
OUT=build/speedometer
mkdir -p "$OUT"

DOMAIN=$(ssh -n -o ConnectTimeout=60 "$HOST" \
    "defaults read '/Applications/$APP.app/Contents/Info' CFBundleIdentifier 2>/dev/null" | tr -d '\r')
[ -n "$DOMAIN" ] || { echo "no $APP.app in /Applications on $HOST" >&2; exit 1; }

# Speedometer 3 puts the final number in #result-number. The rest is for the
# case where that changes: any element whose id mentions "result" holding
# something that looks like a score.
cat > /tmp/speedo-probe.js <<'JS'
(function () {
  var el = document.getElementById('result-number'), text = '', all, i;
  if (el) text = (el.textContent || '').replace(/\s+/g, '');
  if (!text) {
    all = document.querySelectorAll('[id*="result"], [class*="result-number"]');
    for (i = 0; i < all.length; i++) {
      var t = (all[i].textContent || '').replace(/\s+/g, '');
      if (/^[0-9]+(\.[0-9]+)?$/.test(t)) { text = t; break; }
    }
  }
  if (/^[0-9]+(\.[0-9]+)?$/.test(text)) return 'SCORE ' + text;
  return 'running';
})()
JS
tr '\n' ' ' < /tmp/speedo-probe.js > /tmp/speedo-probe-1line.js
scp -O -q /tmp/speedo-probe-1line.js "$HOST:/tmp/speedo-probe.js"

echo "==> $LABEL: $APP, up to $MINUTES minutes"
ssh -n -o ConnectTimeout=90 "$HOST" "
    killall CaptainPolliwog 2>/dev/null; sleep 3
    defaults write '$DOMAIN' CPDebugURL '$URL'
    defaults write '$DOMAIN' CPDebugScript -string \"\$(cat /tmp/speedo-probe.js)\"
    defaults write '$DOMAIN' CPDebugScriptInterval -int 15
    # CPDebugScript is only evaluated from writeDebugSnapshot, which the
    # window controller only schedules when a snapshot path is set. Without
    # this the script never runs at all. The app writes this picture itself,
    # which is the part screencapture could never do from an ssh session.
    rm -f /tmp/speedo-$LABEL.png
    defaults write '$DOMAIN' CPDebugSnapshotPath /tmp/speedo-$LABEL.png
    marker=\$(date +%s)
    start=\$(date +%s)
    open '/Applications/$APP.app'
    score=''
    i=0
    while [ \$i -lt $((MINUTES * 60)) ]; do
        sleep 15; i=\$((i + 15))
        score=\$(awk -v since=\$marker '/script result: SCORE /{ line=\$0 } END { print line }' /var/log/system.log \
                 | sed -n 's/.*script result: SCORE \\([0-9.]*\\).*/\\1/p')
        [ -n \"\$score\" ] && break
        ps -axco command | grep -qx CaptainPolliwog || { echo '  app exited early'; break; }
    done
    ps -axco pid,rss,command | awk '\$3==\"CaptainPolliwog\"{printf \"  memory %d MB\n\", \$2/1024}'
    if [ -n \"\$score\" ]; then echo \"  SCORE \$score  (after \${i}s)\"; else echo \"  no score after \${i}s\"; fi
    osascript -e \"tell application \\\"$APP\\\" to quit\" 2>/dev/null || true
    sleep 3
    ps -axco command | grep -qx CaptainPolliwog && killall CaptainPolliwog 2>/dev/null
    defaults delete '$DOMAIN' CPDebugURL 2>/dev/null
    defaults delete '$DOMAIN' CPDebugScript 2>/dev/null
    defaults delete '$DOMAIN' CPDebugScriptInterval 2>/dev/null
    defaults delete '$DOMAIN' CPDebugSnapshotPath 2>/dev/null
    crash=\$(ls -t \$HOME/Library/Logs/CrashReporter/CaptainPolliwog* 2>/dev/null | head -1)
    if [ -n \"\$crash\" ] && [ \$(stat -f %m \"\$crash\") -ge \$start ]; then
        echo '  CRASHED during the run'
    fi
    true"

scp -O -q "$HOST:/tmp/speedo-$LABEL.png" "$OUT/$LABEL.png" 2>/dev/null \
    && echo "  screen -> $OUT/$LABEL.png" || true
