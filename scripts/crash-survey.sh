#!/bin/bash
# Load a list of sites one at a time in a named Captain Polliwog build on a
# PowerPC Mac, and keep the whole crash report for any that fall over.
#
# site-survey.sh already reports load time, memory and console errors for
# the engine-test copy. This one exists for a different question: given two
# builds of the same app, does one of them crash where the other does not?
# So it takes the app by name, and it brings the crash reports home instead
# of a one-line summary of them.
#
# The defaults domain is read from the bundle rather than assumed. The two
# comparison builds deliberately carry different bundle identifiers so that
# LaunchServices cannot confuse them, which also means CPDebugURL written to
# org.captainpolliwog.browser would be read by neither: the app would open
# its start page, every site would "pass", and the survey would be measuring
# nothing at all.
#
# Only loads pages. Nothing is typed, submitted, or signed into.
#
# Usage:
#   crash-survey.sh <host> <app-name> [sites-file] [seconds-per-site]
#     e.g. crash-survey.sh pbg4 "Captain Polliwog PGO"
set -eu

HOST=${1:?usage: crash-survey.sh host app-name [sites-file] [seconds]}
APP=${2:?usage: crash-survey.sh host app-name [sites-file] [seconds]}
SITES=${3:-engine/tests/sites.txt}
PER_SITE=${4:-75}
# How long to let the page sit after it finishes loading, still running.
# Not idle time: a loaded page keeps flushing layers, recalculating style
# and running timers, and the first crash this harness was built for
# happened there rather than during the load. Quitting the moment the
# snapshot appears scores that page "ok" and sees nothing -- which is what
# it did for Gmail, where the snapshot fired on the loading splash.
DWELL=${DWELL:-0}

cd "$(dirname "$0")/.."
[ -f "$SITES" ] || { echo "no site list at $SITES" >&2; exit 1; }

SLUG=$(echo "$APP" | tr 'A-Z ' 'a-z-')
OUT="build/survey/$SLUG"
mkdir -p "$OUT/crashes"

DOMAIN=$(ssh -n -o ConnectTimeout=60 "$HOST" \
    "defaults read '/Applications/$APP.app/Contents/Info' CFBundleIdentifier 2>/dev/null" | tr -d '\r')
[ -n "$DOMAIN" ] || { echo "no $APP.app in /Applications on $HOST" >&2; exit 1; }
echo "==> $APP on $HOST  (defaults domain: $DOMAIN)"
printf '%-46s %-9s %-8s %s\n' site load memory result
printf -- '---------------------------------------------------------------------------\n'

crashes=0
loaded=0
total=0

while IFS= read -r url; do
    case "$url" in ''|\#*) continue ;; esac
    total=$((total + 1))
    name=$(echo "$url" | sed -E 's#https?://##; s#[^A-Za-z0-9.]+#_#g' | cut -c1-40)

    # -n matters: without it ssh reads from stdin, which is the site list
    # this loop is reading, so the first site consumes the rest of the file
    # and the survey silently tests exactly one page.
    result=$(ssh -n -o ConnectTimeout=90 "$HOST" "
        A='/Applications/$APP.app'
        S=/tmp/polliwog-snapshot.png
        killall CaptainPolliwog 2>/dev/null; sleep 2
        rm -f \$S
        defaults write '$DOMAIN' CPDebugSnapshotPath \$S
        defaults write '$DOMAIN' CPDebugURL '$url'
        start=\$(date +%s)
        open \"\$A\"
        i=0
        while [ \$i -lt $PER_SITE ]; do
            sleep 3; i=\$((i + 3))
            [ -f \$S ] && break
            ps -axco command | grep -qx CaptainPolliwog || break
        done
        # Sit on the loaded page, watching for it to die.
        d=0
        while [ \$d -lt $DWELL ]; do
            sleep 5; d=\$((d + 5))
            ps -axco command | grep -qx CaptainPolliwog || break
        done
        mem=\$(ps -axco pid,rss,command | awk '\$3 == \"CaptainPolliwog\" { printf \"%dMB\", \$2/1024 }')
        alive=no; ps -axco command | grep -qx CaptainPolliwog && alive=yes
        [ -f \$S ] && load=\"\${i}s\" || load=none

        crash=\$(ls -t \$HOME/Library/Logs/CrashReporter/CaptainPolliwog* 2>/dev/null | head -1)
        verdict=ok
        if [ -n \"\$crash\" ] && [ \$(stat -f %m \"\$crash\") -ge \$start ]; then
            verdict=\"CRASH \$(grep -m1 -A2 'Crashed:' \"\$crash\" | tail -1 | sed 's/^[0-9]* *//' | cut -c1-60)\"
            cp \"\$crash\" /tmp/polliwog-last-crash.txt
        elif [ \$alive = no ]; then
            verdict='exited without a crash report'
        elif [ \$load = none ]; then
            verdict='did not finish loading'
        fi

        # Quit rather than kill, so the next site starts from a clean app.
        osascript -e \"tell application \\\"$APP\\\" to quit\" 2>/dev/null || true
        sleep 2
        ps -axco command | grep -qx CaptainPolliwog && killall CaptainPolliwog 2>/dev/null
        defaults delete '$DOMAIN' CPDebugSnapshotPath 2>/dev/null
        defaults delete '$DOMAIN' CPDebugURL 2>/dev/null
        echo \"\$load|\${mem:-gone}|\$verdict\"
        true" 2>/dev/null | tail -1)

    load=${result%%|*}
    rest=${result#*|}
    mem=${rest%%|*}
    verdict=${rest#*|}

    printf '%-46s %-9s %-8s %s\n' "$(echo "$url" | cut -c1-46)" "$load" "$mem" "$verdict"
    [ "$load" != none ] && loaded=$((loaded + 1))

    scp -O -q "$HOST:/tmp/polliwog-snapshot.png" "$OUT/$name.png" 2>/dev/null || true
    case "$verdict" in
        CRASH*)
            crashes=$((crashes + 1))
            scp -O -q "$HOST:/tmp/polliwog-last-crash.txt" "$OUT/crashes/$name.crash" 2>/dev/null || true
            ssh -n "$HOST" 'rm -f /tmp/polliwog-last-crash.txt' 2>/dev/null || true
            ;;
    esac
done < "$SITES"

printf -- '---------------------------------------------------------------------------\n'
echo "$APP: $loaded/$total loaded, $crashes crashed"
[ "$crashes" -gt 0 ] && echo "reports in $OUT/crashes/"
exit 0
