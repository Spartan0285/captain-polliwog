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
# it was written for was thrown away twice before anyone checked.
#
# Polling the page from outside did not work either: evaluating JavaScript
# re-entrantly into an engine that is flat out running the benchmark got 34
# turns and then none, and thirty minutes produced no score.
#
# So the page watches for its own score, on its own timer, in the same event
# loop as the benchmark - and when it appears, navigates to an address
# carrying it. The browser logs every address it finishes, so the number
# arrives in the log with nobody asking for it, and the run is over by then.
#
# Usage:
#   speedometer.sh <host> <app-name> <label> [minutes]
#     e.g. speedometer.sh pbg4 "Captain Polliwog PGO" pgo-1 12
set -eu

HOST=${1:?usage: speedometer.sh host app-name label [minutes]}
APP=${2:?usage: speedometer.sh host app-name label [minutes]}
LABEL=${3:?usage: speedometer.sh host app-name label [minutes]}
# A full run on a PowerBook G4 takes well over fifteen minutes - the progress
# counter is at 0/580 six seconds in - so the default is generous. A cap that
# is too short does not fail loudly; it just reports no score, which is how
# fourteen minutes of G4 time were spent proving nothing.
MINUTES=${4:-30}
# Speedometer's default is ten iterations of all twenty suites, which this
# G4 does not finish inside thirty minutes. For comparing two builds that is
# not needed: both get the same count, and the comparison is as sound with
# three. A score measured this way is NOT comparable with the full-run
# figures in ENGINE_PLAN (median 0.444) - only with another run at the same
# count. Set ITERATIONS= empty for a full, comparable run.
ITERATIONS=${ITERATIONS-3}
URL='https://browserbench.org/Speedometer3.1/?startAutomatically=true'
[ -n "$ITERATIONS" ] && URL="$URL&iterationCount=$ITERATIONS"

cd "$(dirname "$0")/../.."
OUT=build/speedometer
mkdir -p "$OUT"

DOMAIN=$(ssh -n -o ConnectTimeout=60 "$HOST" \
    "defaults read '/Applications/$APP.app/Contents/Info' CFBundleIdentifier 2>/dev/null" | tr -d '\r')
[ -n "$DOMAIN" ] || { echo "no $APP.app in /Applications on $HOST" >&2; exit 1; }

# Speedometer 3 puts the final number in #result-number. The rest is for the
# case where that changes: any element whose id mentions "result" holding
# something that looks like a score.
# NOTE: no // comments in this script. It is flattened to a single line
# before being handed to the browser, and a // comment would swallow
# everything after it - which is how a probe that looked right returned an
# empty string and cost another run.
#
# The page watches for its own score on its own timer, in the same event loop
# as the benchmark, and navigates to an address carrying the number once it
# appears. The browser logs every address it finishes.
# NOTE: no // comments in this script. It is flattened to a single line
# before being handed to the browser, and a // comment would swallow
# everything after it - which is how a probe that looked right returned an
# empty string and cost a run.
#
# It must also stay cheap. This runs while the benchmark is running, so it
# does one getElementById every ten seconds and nothing else. An earlier
# version ran querySelectorAll('[id*="result"]') - an attribute-substring
# scan of the whole document - every five seconds, which is measurable work
# inside the thing being measured.
cat > /tmp/speedo-probe.js <<'JS'
(function () {
  if (window.__cpScoreWatch) return 'watching';
  window.__cpScoreWatch = setInterval(function () {
    var el = document.getElementById('result-number');
    var text = el ? (el.textContent || '').replace(/\s+/g, '') : '';
    if (/^[0-9]+(\.[0-9]+)?$/.test(text)) {
      clearInterval(window.__cpScoreWatch);
      location.href = 'https://browserbench.org/?cpscore=' + text + '&run=__LABEL__';
    }
  }, 10000);
  return 'watching';
})()
JS
# Each run tags its own address, so a score left in the log by the previous
# run cannot be read as this one's.
sed "s/__LABEL__/$LABEL/" /tmp/speedo-probe.js | tr '\n' ' ' > /tmp/speedo-probe-1line.js
scp -O -q /tmp/speedo-probe-1line.js "$HOST:/tmp/speedo-probe.js"

echo "==> $LABEL: $APP, up to $MINUTES minutes"
ssh -n -o ConnectTimeout=90 "$HOST" "
    killall CaptainPolliwog 2>/dev/null; sleep 3
    defaults write '$DOMAIN' CPDebugURL '$URL'
    defaults write '$DOMAIN' CPDebugScript -string \"\$(cat /tmp/speedo-probe.js)\"
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
        score=\$(grep -h 'cpscore=.*run=$LABEL' /var/log/system.log /Library/Logs/Console/*/console.log \$HOME/Library/Logs/Console/*/console.log 2>/dev/null \
                 | tail -1 | sed -n 's/.*cpscore=\\([0-9.]*\\).*/\\1/p')
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
    defaults delete '$DOMAIN' CPDebugSnapshotPath 2>/dev/null
    crash=\$(ls -t \$HOME/Library/Logs/CrashReporter/CaptainPolliwog* 2>/dev/null | head -1)
    if [ -n \"\$crash\" ] && [ \$(stat -f %m \"\$crash\") -ge \$start ]; then
        echo '  CRASHED during the run'
    fi
    true"

scp -O -q "$HOST:/tmp/speedo-$LABEL.png" "$OUT/$LABEL.png" 2>/dev/null \
    && echo "  screen -> $OUT/$LABEL.png" || true
