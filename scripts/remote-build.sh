#!/bin/sh
# Copy the sources to each PowerPC Mac and build there.
# Usage: scripts/remote-build.sh [host ...]      (default: g4 g3)
set -e
cd "$(dirname "$0")/.."

REMOTE_DIR=CaptainPolliwog
HOSTS=${*:-"g4 g3"}

for host in $HOSTS; do
    scripts/sync.sh "$host"
    echo "==> $host: building"
    # Tiger's shells default to a 6MB heap limit, which the compiler exceeds
    # on the files that pull in WebKit and libcurl headers.
    ssh -o ConnectTimeout=90 "$host" "ulimit -d unlimited 2>/dev/null || ulimit -d 262144; cd $REMOTE_DIR && make ${MAKEFLAGS_REMOTE:-}"
done
