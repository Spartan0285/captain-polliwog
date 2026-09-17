#!/bin/sh
# Measure what the HTTP cache is worth on an old Mac: loads a page with an
# empty cache, then again with a warm one, and reports the page load time and
# where each resource came from.
#
#   Usage: scripts/measure-cache.sh host url
set -e
cd "$(dirname "$0")/.."

host=${1:?usage: measure-cache.sh host url}
url=${2:?usage: measure-cache.sh host url}

report() {
    ssh -o ConnectTimeout=90 "$host" '
        # Tiger logs NSLog to the per-user console.log, Leopard to system.log.
        logs=`ls /Library/Logs/Console/*/console.log /var/log/system.log 2>/dev/null`
        pid=`grep -h "page-load" $logs | tail -1 | sed "s/.*CaptainPolliwog\[\([0-9]*\)\].*/\1/"`
        grep -h "CaptainPolliwog\[$pid\]" $logs | grep "page-load" | tail -1 | sed "s/.*Captain Polliwog: /  /"
        # Tiger\047s sed has no alternation, so the counting is left to awk.
        grep -h "CaptainPolliwog\[$pid\]" $logs | awk "
            /cache-hit/ { hits++ }
            /revalidated/ { revalidated++ }
            /from-network/ { downloaded++ }
            END { printf \"  %d served from cache, %d revalidated (304), %d downloaded\\n\", hits, revalidated, downloaded }"'
}

echo "==> $host: cold cache"
ssh -o ConnectTimeout=90 "$host" 'rm -rf ~/Library/Caches/org.captainpolliwog.browser'
scripts/remote-run.sh "$host" "$url" 300 > /dev/null 2>&1
report

echo "==> $host: warm cache"
scripts/remote-run.sh "$host" "$url" 300 > /dev/null 2>&1
report
