#!/bin/bash
# The multi-tab version of memory-probe.sh, for exercising the parts of
# CPMemoryWatcher's escalation that a single tab cannot reach.
#
# With one tab open the watcher has nothing to discard -- it logged "0 tabs
# discarded" on the Vimeo run -- so the step expected to do most of the work
# was never tested, and pressure never persisted long enough to reach the
# step after it. Several heavy pages at once gives the discarder something to
# take and keeps the machine under pressure long enough to find out what
# happens when it is not enough.
#
# Tabs after the first are opened by asking the running app to open a URL,
# which arrives as the GetURL Apple Event it already handles for being the
# default browser.
#
# Usage:
#   memory-probe-tabs.sh <host> <app-path> <minutes> <label> <url>...
set -eu

HOST=${1:?usage: memory-probe-tabs.sh host app-path minutes label url...}
APPPATH=${2:?usage: memory-probe-tabs.sh host app-path minutes label url...}
MINUTES=${3:?usage: memory-probe-tabs.sh host app-path minutes label url...}
LABEL=${4:?usage: memory-probe-tabs.sh host app-path minutes label url...}
shift 4
FIRST=${1:?at least one url}
shift

cd "$(dirname "$0")/.."
OUT=build/memory
mkdir -p "$OUT"

DOMAIN=$(ssh -n -o ConnectTimeout=60 "$HOST" \
    "defaults read '$APPPATH/Contents/Info' CFBundleIdentifier 2>/dev/null" | tr -d '\r')
[ -n "$DOMAIN" ] || { echo "no bundle at $APPPATH on $HOST" >&2; exit 1; }

EXTRA=""
for u in "$@"; do EXTRA="$EXTRA '$u'"; done

echo "==> $LABEL: $(($# + 1)) tabs for $MINUTES minutes"
ssh -n -o ConnectTimeout=90 "$HOST" "
    killall CaptainPolliwog 2>/dev/null; sleep 3
    defaults write '$DOMAIN' CPDebugLogging -bool YES
    defaults write '$DOMAIN' CPDebugURL '$FIRST'
    open \"$APPPATH\"
    sleep 45
    # Each of these lands as a GetURL event and becomes another tab.
    for u in $EXTRA; do
        echo \"    opening \$u\"
        open -a \"$APPPATH\" \"\$u\"
        sleep 40
    done
    printf '    %-7s %-9s %-9s\n' elapsed rss free
    i=0
    while [ \$i -lt $((MINUTES * 60)) ]; do
        sleep 30; i=\$((i + 30))
        ps -axco command | grep -qx CaptainPolliwog || { echo \"    GONE after \${i}s -- killed, most likely out of memory\"; break; }
        rss=\$(ps -axco pid,rss,command | awk '\$3==\"CaptainPolliwog\"{print \$2}')
        free=\$(vm_stat | awk '/Pages free/ {gsub(/\./,\"\"); printf \"%d\", \$3 * 4096 / 1048576}')
        printf '    %-7s %-9s %-9s\n' \"\${i}s\" \"\$((rss / 1024))MB\" \"\${free}MB\"
    done
    echo '    --- what the watcher did:'
    P=\$(ps -axco pid,command | awk '\$2==\"CaptainPolliwog\"{print \$1}')
    grep -E 'released memory|stopped scripts|discarded tab' /var/log/system.log | tail -12 | sed 's/^.*Captain Polliwog: /    /'
    osascript -e 'tell application \"Captain Polliwog\" to quit' 2>/dev/null || true
    sleep 4
    ps -axco command | grep -qx CaptainPolliwog && killall CaptainPolliwog 2>/dev/null
    defaults delete '$DOMAIN' CPDebugURL 2>/dev/null
    defaults delete '$DOMAIN' CPDebugLogging 2>/dev/null
    true" | tee "$OUT/$LABEL.txt"
