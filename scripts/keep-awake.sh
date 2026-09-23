#!/bin/sh
# Keeps an old Mac from falling asleep during long builds and test runs.
#
#   Usage: scripts/keep-awake.sh host [stop]
#
# Tiger and Leopard have no caffeinate, and changing Energy Saver needs an
# administrator password, so this calls UpdateSystemActivity -- the same thing
# the old "jiggler" utilities used -- every 30 seconds. It reports activity
# without moving the pointer or typing anything.
#
# It runs as your login session, so it stops at logout or restart; run it
# again afterwards, or set Energy Saver to never sleep for something permanent.
set -e

host=${1:?usage: keep-awake.sh host [stop]}
action=${2:-start}

if [ "$action" = "stop" ]; then
    ssh -o ConnectTimeout=90 "$host" "ps -axo pid,command | awk '/[p]olliwog-keep-awake/ {print \$1}' | xargs -n1 kill 2>/dev/null; true"
    echo "==> $host: sleep prevention stopped"
    exit 0
fi

ssh -o ConnectTimeout=90 "$host" '
    ps -axo pid,command | awk '/[p]olliwog-keep-awake/ {print $1}' | xargs -n1 kill 2>/dev/null
    cat > /tmp/polliwog-keep-awake.py <<PY
# polliwog-keep-awake
import ctypes, time
services = ctypes.CDLL("/System/Library/Frameworks/CoreServices.framework/CoreServices")
while True:
    services.UpdateSystemActivity(0)   # OverallAct: defers idle sleep
    time.sleep(30)
PY
    nohup python /tmp/polliwog-keep-awake.py > /dev/null 2>&1 &
    sleep 1
    ps -axo command | grep -q "[p]olliwog-keep-awake" && echo started'
echo "==> $host: staying awake (scripts/keep-awake.sh $host stop to undo)"
