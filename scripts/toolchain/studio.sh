#!/bin/sh
# Runs a step of the engine build in the cross-build VM on the Mac Studio,
# while the sources are edited here: copies over what changed in the WebKit
# tree and in these scripts, runs the step there, and brings the packaged
# frameworks back so engine-run.sh and site-survey.sh work as before.
#   Usage: scripts/toolchain/studio.sh build|package|configure leopard-g4 [targets...]
#          scripts/toolchain/studio.sh shell 'command'
# STUDIO overrides the host (default adam@192.168.68.152).
set -e
cd "$(dirname "$0")/../.."
STUDIO=${STUDIO:-adam@192.168.68.152}
REPO="$PWD"
LIMACTL=/opt/homebrew/bin/limactl

sync() {
    rsync -a --delete --exclude .git --exclude build/ \
        "$HOME/polliwog-build/webkit-604/" "$STUDIO:polliwog-build/webkit-604/"
    rsync -a --delete --exclude .git --exclude build/ "$REPO/" "$STUDIO:'$REPO'/"
}

step=${1:?usage: studio.sh build|package|configure variant [targets...] | shell command}
shift
case "$step" in
build|configure)
    sync
    ssh "$STUDIO" "$LIMACTL shell ppcbuild -- bash '$REPO/scripts/toolchain/webkit.sh' $step $*" ;;
package)
    variant=${1:?variant}
    ssh "$STUDIO" "$LIMACTL shell ppcbuild -- bash '$REPO/scripts/toolchain/package-webkit.sh' $variant"
    mkdir -p "$HOME/polliwog-build/stage/$variant"
    rsync -a "$STUDIO:polliwog-build/stage/$variant/Frameworks.zip" "$HOME/polliwog-build/stage/$variant/" ;;
shell)
    ssh "$STUDIO" "$LIMACTL shell ppcbuild -- bash -c $(printf '%q' "$*")" ;;
*)
    echo "usage: studio.sh build|package|configure variant [targets...] | shell command" >&2
    exit 1 ;;
esac
