#!/bin/sh
# Copies the sources to a PowerPC Mac, replacing only files whose contents
# changed, and giving those the Mac's current time.
#
#   Usage: scripts/sync.sh host
#
# Copying timestamps across is not safe here: the iBook's clock runs about a
# minute and a half fast, so an edit made just after a build can look older
# than its object file, and make then quietly skips it.
set -e
cd "$(dirname "$0")/.."

host=${1:?usage: sync.sh host}
REMOTE_DIR=CaptainPolliwog

# Some patched Leopard installs ship without tar; unzip is always present.
zip -qrX - Makefile src Resources scripts -x '*.DS_Store' |
    ssh -o ConnectTimeout=90 "$host" "
        rm -rf /tmp/polliwog-sync && mkdir -p /tmp/polliwog-sync $REMOTE_DIR &&
        cd /tmp/polliwog-sync && cat > sources.zip && unzip -qo sources.zip && rm sources.zip &&
        changed=0
        for f in \`find . -type f\`; do
            if ! cmp -s \"\$f\" \"\$HOME/$REMOTE_DIR/\$f\"; then
                mkdir -p \"\$HOME/$REMOTE_DIR/\`dirname \$f\`\"
                cat \"\$f\" > \"\$HOME/$REMOTE_DIR/\$f\"
                changed=\$((changed + 1))
            fi
        done
        # Anything here that is not there any more. Without this a deleted
        # resource keeps being copied into the bundle and a deleted source
        # keeps being compiled, and both look like the edit never arriving.
        # Only the directories this script sends are touched.
        removed=0
        for f in \`cd \$HOME/$REMOTE_DIR && find src Resources scripts -type f 2>/dev/null\`; do
            if [ ! -f \"/tmp/polliwog-sync/\$f\" ]; then
                rm -f \"\$HOME/$REMOTE_DIR/\$f\"
                removed=\$((removed + 1))
            fi
        done
        chmod +x \$HOME/$REMOTE_DIR/scripts/*.sh
        rm -rf /tmp/polliwog-sync
        echo \"==> $host: \$changed files updated, \$removed removed\""
