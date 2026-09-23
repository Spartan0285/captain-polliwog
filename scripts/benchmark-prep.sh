#!/bin/sh
# Puts a PowerPC Mac into a fair state for a benchmark run: nothing else
# running, no warm caches, and no falling asleep in the middle of an hour.
#
#   Usage: scripts/benchmark-prep.sh host
#
# A browser benchmark on one of these machines takes the better part of an
# hour, and every one of these makes a difference to the number at the end.
# A warm cache is the big one - the second run of a page is not measuring
# the same work as the first - but a G4 has little enough memory that one
# background application swapping is visible too.
set -e
host=${1:?usage: benchmark-prep.sh host}

ssh -o ConnectTimeout=90 "$host" '
    # Anything the user happened to leave running. The list is deliberately
    # by name rather than "everything not a daemon": killing the wrong thing
    # on someone else s machine is worse than a slightly noisy benchmark.
    for app in TheGarden "Scroll Reverser" DockRebirth "Wireless Network Utility" \
               "DiskImages UI Agent" Safari Firefox powerfox CaptainPolliwog TextEdit Preview Mail; do
        ps -axo pid,command | grep "[/ ]$app" | awk "{print \$1}" | xargs -n1 kill 2>/dev/null || true
    done
    sleep 2

    # Both browsers own caches, and the system s own page cache.
    rm -rf ~/Benchmarks/pf-profile/cache2 ~/Benchmarks/pf-profile/Cache 2>/dev/null || true
    rm -rf ~/Library/Caches/org.captainpolliwog.browser 2>/dev/null || true
    [ -x /usr/bin/purge ] && /usr/bin/purge 2>/dev/null || true

    echo "==> still running:"
    ps -axco command | sort -u | grep -icE "powerfox|polliwog|safari|firefox" | sed "s/^/    browsers: /"
    echo "==> free memory:"
    vm_stat | awk "/Pages free/ {printf \"    %d MB free\n\", \$3 * 4096 / 1048576}"
'
echo "==> $host: prepared. Sleep prevention: scripts/keep-awake.sh $host"
