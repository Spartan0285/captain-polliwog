#!/bin/bash
# Watch what a page does to memory while it is left open.
#
# The surveys record one number at the end, which cannot tell a page that is
# simply large from a page that is still growing. This samples every half
# minute so the shape is visible: flat means heavy, a slope means something
# is accumulating, and a slope that does not level off is what fills a 1GB
# machine and gets the process killed without a crash report.
#
# It also watches free system memory and whether CPMemoryWatcher fired. That
# watchdog empties WebKit's resource cache and ours, which helps a page that
# has cached a lot and not at all a page whose JavaScript heap is growing,
# so knowing whether it ran matters as much as the total.
#
# Usage:
#   memory-probe.sh <host> <app-path> <url> [minutes] [label]
set -eu

HOST=${1:?usage: memory-probe.sh host app-path url [minutes] [label]}
APPPATH=${2:?usage: memory-probe.sh host app-path url [minutes] [label]}
URL=${3:?usage: memory-probe.sh host app-path url [minutes] [label]}
MINUTES=${4:-15}
LABEL=${5:-probe}

cd "$(dirname "$0")/.."
OUT=build/memory
mkdir -p "$OUT"

DOMAIN=$(ssh -n -o ConnectTimeout=60 "$HOST" \
    "defaults read '$APPPATH/Contents/Info' CFBundleIdentifier 2>/dev/null" | tr -d '\r')
[ -n "$DOMAIN" ] || { echo "no bundle at $APPPATH on $HOST" >&2; exit 1; }

echo "==> $LABEL: $URL for $MINUTES minutes"
ssh -n -o ConnectTimeout=90 "$HOST" "
    # Leopard sends NSLog to system.log through ASL; Tiger writes it to
    # the console log instead. Greping only system.log made every Tiger
    # machine report no watchdog activity whatever the watchdog did.
    CPLOGS=\"/var/log/system.log /Library/Logs/Console/*/console.log \$HOME/Library/Logs/Console/*/console.log\"
    killall CaptainPolliwog 2>/dev/null; sleep 3
    defaults write '$DOMAIN' CPDebugLog -bool YES
    defaults write '$DOMAIN' CPDebugURL '$URL'
    marker=\$(date +%s)
    open \"$APPPATH\"
    printf '    %-7s %-9s %-9s\n' elapsed rss free
    i=0
    while [ \$i -lt $((MINUTES * 60)) ]; do
        sleep 30; i=\$((i + 30))
        ps -axco command | grep -qx CaptainPolliwog || { echo \"    gone after \${i}s\"; break; }
        rss=\$(ps -axco pid,rss,command | awk '\$3==\"CaptainPolliwog\"{print \$2}')
        free=\$(vm_stat | awk '/Pages free/ {gsub(/\./,\"\"); printf \"%d\", \$3 * 4096 / 1048576}')
        printf '    %-7s %-9s %-9s\n' \"\${i}s\" \"\$((rss / 1024))MB\" \"\${free}MB\"
    done
    echo '    --- watchdog:'
    grep -h 'freed WebKit' \$CPLOGS 2>/dev/null | tail -3 | sed 's/^/    /' || true
    n=\$(grep -hc 'freed WebKit' \$CPLOGS 2>/dev/null | awk '{t+=\$1} END {print t+0}')
    echo \"    cache flushes logged: \$n\"
    osascript -e 'tell application \"Captain Polliwog\" to quit' 2>/dev/null || true
    sleep 3
    ps -axco command | grep -qx CaptainPolliwog && killall CaptainPolliwog 2>/dev/null
    defaults delete '$DOMAIN' CPDebugURL 2>/dev/null
    defaults delete '$DOMAIN' CPDebugLog 2>/dev/null
    true" | tee "$OUT/$LABEL.txt"
