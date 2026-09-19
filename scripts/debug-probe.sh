#!/bin/sh
# Loads a page with a JavaScript probe run once it is in; prints the result.
# Usage: scripts/debug-probe.sh host variant url probe.js [timeout]
set -e
cd "$(dirname "$0")/.."
host=$1 variant=$2 url=$3 probe=$4 timeout=${5:-180}
tr '\n' ' ' < "$probe" > /tmp/polliwog-probe.js
scp -O -q /tmp/polliwog-probe.js "$host:/tmp/polliwog-probe.js"
ssh "$host" 'defaults write org.captainpolliwog.browser CPDebugScript -string "$(cat /tmp/polliwog-probe.js)"'
scripts/engine-run.sh "$host" "$variant" "$url" "$timeout" | tail -1
ssh "$host" 'defaults delete org.captainpolliwog.browser CPDebugScript; grep "CaptainPolliwog\[" /var/log/system.log | grep "script result" | tail -1 | cut -c1-4000'
