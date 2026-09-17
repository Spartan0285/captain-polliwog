#!/bin/sh
# Launch Captain Polliwog on a PowerPC Mac, load a page, and fetch a snapshot
# of the window (saved by the app itself) plus its memory use.
# Usage: scripts/remote-run.sh host [url] [timeout-seconds]
set -e
cd "$(dirname "$0")/.."

host=${1:?usage: remote-run.sh host [url] [timeout-seconds]}
url=${2:-}
timeout=${3:-120}
domain=org.captainpolliwog.browser
snap=/tmp/polliwog-snapshot.png
out="build/screens/$host.png"
mkdir -p build/screens

ssh -o ConnectTimeout=90 "$host" "
    killall CaptainPolliwog 2>/dev/null; sleep 2
    rm -f $snap
    defaults write $domain CPDebugSnapshotPath $snap
    if [ -n '$url' ]; then defaults write $domain CPDebugURL '$url'; else defaults delete $domain CPDebugURL 2>/dev/null; fi
    open 'CaptainPolliwog/build/Captain Polliwog.app'
    i=0
    while [ ! -f $snap ] && [ \$i -lt $timeout ]; do sleep 2; i=\$((i + 2)); done
    sleep 3
    defaults delete $domain CPDebugSnapshotPath
    defaults delete $domain CPDebugURL 2>/dev/null
    echo \"==> $host: page ready after ~\${i}s\"
    ps -axww -o rss,command | awk '/MacOS\/[C]aptainPolliwog/ { printf \"==> $host: memory %d MB\\n\", \$1 / 1024 }'
    grep -h 'Captain Polliwog:' /var/log/system.log /Library/Logs/Console/*/console.log 2>/dev/null | tail -5
    true"
scp -q -o ConnectTimeout=90 "$host:$snap" "$out" && echo "==> saved $out"
