#!/bin/sh
# Try Captain Polliwog on a WebKit build from the cross-build VM: installs the
# packaged frameworks into a copy of the app on a PowerPC Mac, loads a page,
# and fetches the app's own snapshot of the window.
# Usage: scripts/engine-run.sh host variant [url] [timeout-seconds]
#   e.g. scripts/engine-run.sh g4 leopard-g4 https://en.wikipedia.org/
set -e
cd "$(dirname "$0")/.."
host=${1:?usage: engine-run.sh host variant [url] [timeout]}
variant=${2:?usage: engine-run.sh host variant [url] [timeout]}
url=${3:-https://en.wikipedia.org/wiki/PowerBook_G3}
timeout=${4:-180}
zip=$HOME/polliwog-build/stage/$variant/Frameworks.zip
out=build/screens/$host-$variant.png
mkdir -p build/screens

# The classic scp protocol (-O): Leopard's sshd sometimes stalls modern
# scp's SFTP transfers at the very end. Skip the copy if it is already there.
local_sum=$(md5 -q "$zip")
remote_sum=$(ssh -o ConnectTimeout=90 "$host" "md5 -q /tmp/Frameworks.zip 2>/dev/null" || true)
[ "$local_sum" = "$remote_sum" ] || scp -O -q "$zip" "$host:/tmp/Frameworks.zip"
ssh -o ConnectTimeout=90 "$host" "
    A=\$HOME/polliwog-engine-test/'Captain Polliwog.app'
    killall CaptainPolliwog 2>/dev/null; sleep 2
    if [ ! -d \"\$A\" ]; then
        mkdir -p \$HOME/polliwog-engine-test
        ditto \$HOME/CaptainPolliwog/build/'Captain Polliwog.app' \"\$A\"
        defaults write \"\$A/Contents/Info\" LSEnvironment -dict DYLD_FRAMEWORK_PATH \"\$A/Contents/Frameworks\"
        plutil -convert xml1 \"\$A/Contents/Info.plist\"
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f \"\$A\"
    fi
    cd \"\$A/Contents\" && rm -rf Frameworks && unzip -q /tmp/Frameworks.zip
    D=org.captainpolliwog.browser S=/tmp/polliwog-snapshot.png
    rm -f \$S
    defaults write \$D CPDebugSnapshotPath \$S
    defaults write \$D CPDebugURL '$url'
    start=\$(date +%s)
    open \"\$A\"
    i=0
    while [ ! -f \$S ] && [ \$i -lt $timeout ]; do
        sleep 2; i=\$((i + 2))
        if [ \$i -gt 10 ] && ! ps -axww | grep -q '[M]acOS/CaptainPolliwog'; then echo \"==> app exited after \${i}s\"; break; fi
    done
    sleep 3
    defaults delete \$D CPDebugSnapshotPath; defaults delete \$D CPDebugURL
    echo \"==> $host: page ready after ~\${i}s\"
    ps -axww -o rss,command | awk '/MacOS\/[C]aptainPolliwog/ { printf \"==> $host: memory %d MB\\n\", \$1 / 1024 }'
    crash=\$(ls -t \$HOME/Library/Logs/CrashReporter/CaptainPolliwog* 2>/dev/null | head -1)
    if [ -n \"\$crash\" ] && [ \$(stat -f %m \"\$crash\") -ge \$start ]; then
        echo \"==> crashed: \$crash\"; grep -A12 'Crashed:' \"\$crash\" | head -14
    fi
    true"
scp -O -q -o ConnectTimeout=90 "$host:/tmp/polliwog-snapshot.png" "$out" 2>/dev/null && echo "==> saved $out"
