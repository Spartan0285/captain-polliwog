#!/bin/bash
# Loads a list of sites one by one in the engine test copy of Captain Polliwog
# on a PowerPC Mac (see engine-run.sh) and reports, for each: load time,
# memory, JavaScript console errors, stalls, stopped scripts and crashes,
# with the app's own snapshot of the page in build/survey/. Only loads
# pages: nothing is typed or submitted.
# Usage: scripts/site-survey.sh host mode url...     mode: 0 desktop, 1 mobile, 2 basic
set -e
cd "$(dirname "$0")/.."
host=$1 mode=$2
shift 2
out=build/survey
mkdir -p $out

n=0
for url in "$@"; do
    n=$((n + 1))
    name=$(echo "$url" | sed -E 's#https?://##; s#[^A-Za-z0-9.]+#_#g' | cut -c1-40)
    ssh -o ConnectTimeout=90 "$host" "
        A=\$HOME/polliwog-engine-test/'Captain Polliwog.app'
        D=org.captainpolliwog.browser S=/tmp/polliwog-snapshot.png
        killall CaptainPolliwog 2>/dev/null; sleep 2
        rm -f \$S
        defaults write \$D CPDefaultSiteMode -int $mode
        defaults write \$D CPDebugSnapshotPath \$S
        defaults write \$D CPDebugURL '$url'
        start=\$(date +%s)
        open \"\$A\"; sleep 4
        P=\$(ps -axww -o pid,command | awk '/[M]acOS\/CaptainPolliwog/ {print \$1}')
        log() { grep \"CaptainPolliwog\[\$P\]\" /var/log/system.log; }
        i=0
        while [ \$i -lt 150 ]; do
            if [ -z \"\$(ps -p \$P -o pid= 2>/dev/null)\" ]; then break; fi
            log | grep -q 'page-load [0-9.]*s http' && break
            sleep 3; i=\$((i + 3))
        done
        sleep 5
        loaded=\$(log | grep 'page-load [0-9.]*s http' | tail -1 | sed -E 's/.*page-load ([0-9.]+s).*/\1/')
        mem=\$(ps -o rss= -p \$P 2>/dev/null | awk '{printf \"%dMB\", \$1/1024}')
        errors=\$(log | grep -c 'console .*[Ee]rror\|console .*denied\|console .*not allowed' || true)
        stalls=\$(log | grep -c 'stalled' || true)
        stopped=\$(log | grep -c 'stopped a script' || true)
        crash=\$(ls -t \$HOME/Library/Logs/CrashReporter/CaptainPolliwog* 2>/dev/null | head -1)
        crashed=no
        if [ -n \"\$crash\" ] && [ \$(stat -f %m \"\$crash\") -ge \$start ]; then crashed=\"yes: \$(grep -A2 'Crashed:' \"\$crash\" | tail -1 | cut -c1-90)\"; fi
        title=\$(log | grep 'snapshot of' | tail -1 | sed -E 's/.*snapshot of \"(.*)\" ->.*/\1/' | cut -c1-40)
        printf '%s\tload=%s\tmem=%s\tjs-errors=%s\tstalls=%s\tscripts-stopped=%s\tcrash=%s\ttitle=%s\n' \
            '$url' \"\${loaded:-none}\" \"\${mem:-gone}\" \"\$errors\" \"\$stalls\" \"\$stopped\" \"\$crashed\" \"\$title\"
        log | grep 'console\|stalled\|resource failed' | cut -c40-260 > /tmp/polliwog-survey-log.txt
        defaults delete \$D CPDebugSnapshotPath; defaults delete \$D CPDebugURL
        true"
    scp -O -q "$host:/tmp/polliwog-snapshot.png" "$out/$mode-$name.png" 2>/dev/null || true
    scp -O -q "$host:/tmp/polliwog-survey-log.txt" "$out/$mode-$name.log" 2>/dev/null || true
done
ssh -o ConnectTimeout=90 "$host" "defaults write org.captainpolliwog.browser CPDefaultSiteMode -int 0; killall CaptainPolliwog 2>/dev/null; true"
