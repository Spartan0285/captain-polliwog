#!/bin/bash
# A/B test of PowerEmu's Web Accelerator (docs/POWEREMU_WEB_ACCELERATOR.md):
# loads each site in the installed Captain Polliwog on a PowerPC Mac with the
# accelerator off and on, several times each from an empty cache, and reports
# per load:
#   load       time until the page finished loading
#   cpu        the browser's CPU time for the load
#   mem        its resident memory afterwards
#   requests   responses from the network
#   converted  images PowerEmu converted or scaled
#   blocked    requests PowerEmu answered as ads or trackers
#   broken     images that finished loading but can't be shown / images
# with the app's own snapshot of each page in build/accelerator/ to compare
# how they render. Only loads pages: nothing is typed or submitted.
#
# The accelerator must already be usable by that Mac (in a PowerEmu virtual
# Mac it always is; a real Mac needs the pairing code entered in Preferences
# > PowerEmu).
#
# Usage: scripts/accelerator-ab.sh host runs url...
set -e
cd "$(dirname "$0")/.."
host=$1 runs=$2
shift 2
out=build/accelerator
mkdir -p $out
results=$out/results.tsv
printf 'site\tmode\trun\tload\tcpu\tmem\trequests\tconverted\tblocked\tbroken\n' > $results

# Images that completed loading without dimensions couldn't be decoded.
probe='(function(){var b=0,t=0;for(var i=0;i<document.images.length;i++){var m=document.images[i];if(m.complete&&m.src){t++;if(!m.naturalWidth)b++;}}return "images "+b+"/"+t;})()'

for url in "$@"; do
    name=$(echo "$url" | sed -E 's#https?://##; s#[^A-Za-z0-9.]+#_#g' | cut -c1-40)
    for run in $(seq 1 $runs); do
        for mode in off on; do
            enabled=NO; [ $mode = on ] && enabled=YES
            line=$(ssh -4 -o ConnectTimeout=90 "$host" "
                A='/Applications/Captain Polliwog.app'
                D=org.captainpolliwog.browser S=/tmp/polliwog-ab.png
                killall CaptainPolliwog 2>/dev/null; sleep 2
                rm -rf \$HOME/Library/Caches/org.captainpolliwog.browser/'Captain Polliwog HTTP' \$S
                defaults write \$D CPAcceleratorEnabled -bool $enabled
                defaults write \$D CPDebugLog -bool YES
                defaults write \$D CPDebugSnapshotPath \$S
                defaults write \$D CPDebugScript -string '$probe'
                defaults write \$D CPDebugURL '$url'
                open \"\$A\"; sleep 4
                P=\$(ps -axww -o pid,command | awk '/[M]acOS\/CaptainPolliwog/ {print \$1}')
                log() { grep \"CaptainPolliwog\[\$P\]\" /var/log/system.log; }
                i=0
                while [ \$i -lt 150 ]; do
                    [ -z \"\$(ps -p \$P -o pid= 2>/dev/null)\" ] && break
                    log | grep -q 'script result: images' && break
                    sleep 3; i=\$((i + 3))
                done
                loaded=\$(log | grep 'page-load [0-9.]*s http' | tail -1 | sed -E 's/.*page-load ([0-9.]+)s.*/\1/')
                cpu=\$(ps -o time= -p \$P 2>/dev/null | tr -d ' ')
                mem=\$(ps -o rss= -p \$P 2>/dev/null | awk '{printf \"%d\", \$1/1024}')
                requests=\$(log | grep -c 'from-network' || true)
                converted=\$(log | grep -c 'PowerEmu converted' || true)
                blocked=\$(log | grep -c 'PowerEmu blocked' || true)
                broken=\$(log | grep 'script result: images' | tail -1 | sed -E 's/.*images ([0-9]+\/[0-9]+).*/\1/')
                printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' \"\${loaded:-none}\" \"\${cpu:-gone}\" \"\${mem:-gone}\" \"\$requests\" \"\$converted\" \"\$blocked\" \"\${broken:-?}\"
                killall CaptainPolliwog 2>/dev/null
                for k in CPDebugSnapshotPath CPDebugScript CPDebugURL CPDebugLog; do defaults delete \$D \$k 2>/dev/null; done
                true")
            printf '%s\t%s\t%s\t%s\n' "$url" $mode $run "$line" | tee -a $results
            scp -q "$host:/tmp/polliwog-ab.png" "$out/$name-$mode-$run.png" 2>/dev/null || true
        done
    done
done
ssh -4 -o ConnectTimeout=90 "$host" "defaults delete org.captainpolliwog.browser CPAcceleratorEnabled 2>/dev/null; true"

# Medians per site and mode.
python3 - "$results" <<'EOF'
import csv, sys, statistics
rows = list(csv.DictReader(open(sys.argv[1]), delimiter='\t'))
def num(v):
    try: return float(v)
    except ValueError: return None
print("\nsite\tmode\tload(s)\trequests\tconverted\tblocked\tbroken")
for site in dict.fromkeys(r['site'] for r in rows):
    for mode in ('off', 'on'):
        rs = [r for r in rows if r['site'] == site and r['mode'] == mode]
        loads = [num(r['load']) for r in rs if num(r['load']) is not None]
        med = statistics.median(loads) if loads else float('nan')
        print(f"{site[:40]}\t{mode}\t{med:.1f}\t{rs[-1]['requests']}\t{rs[-1]['converted']}\t{rs[-1]['blocked']}\t{rs[-1]['broken']}")
EOF
