#!/bin/sh
# Copy the sources to each PowerPC Mac and build there.
# Usage: scripts/remote-build.sh [host ...]      (default: g4 g3)
set -e
cd "$(dirname "$0")/.."

REMOTE_DIR=CaptainPolliwog
HOSTS=${*:-"g4 g3"}

for host in $HOSTS; do
    echo "==> $host: copying sources"
    # Some patched Leopard installs ship without tar; unzip is always present.
    zip -qrX - Makefile src Resources -x '*.DS_Store' |
        ssh -o ConnectTimeout=90 "$host" "mkdir -p $REMOTE_DIR && cd $REMOTE_DIR && rm -rf src Resources &&
            cat > /tmp/polliwog-src.zip && unzip -qo /tmp/polliwog-src.zip && rm /tmp/polliwog-src.zip"
    echo "==> $host: building"
    # Tiger's shells default to a 6MB heap limit, which the compiler exceeds
    # on the files that pull in WebKit and libcurl headers.
    ssh -o ConnectTimeout=90 "$host" "ulimit -d unlimited 2>/dev/null || ulimit -d 262144; cd $REMOTE_DIR && make ${MAKEFLAGS_REMOTE:-}"
done
