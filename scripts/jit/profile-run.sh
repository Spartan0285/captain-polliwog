#!/bin/bash
# Run the instrumented engine on a PowerPC Mac and bring back the profile
# data, for the second half of a PGO build of the whole browser.
#
# Two things make this different from running jsc:
#
# The profiles have to go somewhere that exists. libgcov writes each .gcda
# to the absolute path the build recorded, which is inside the build VM, so
# GCOV_PREFIX and GCOV_PREFIX_STRIP redirect them. A GUI app opened through
# LaunchServices does not inherit the shell's environment, so they are set
# in the bundle's LSEnvironment, beside the DYLD_FRAMEWORK_PATH that is
# already there.
#
# The app has to exit cleanly. libgcov flushes from an atexit handler, so a
# killall gives nothing at all: the run is ended with a Quit Apple Event and
# only falls back to killing if that does not work, in which case the
# profile is lost and the script says so.
#
# The running-check matches the accounting name exactly (ps -axco command,
# grep -x) and not the full command line. This script's own command line
# contains .../MacOS/CaptainPolliwog, in the cp that installs the binary, so
# a grep over full command lines matches the script itself: the first
# version reported "it did not quit; killing it, which loses the profile"
# about an app that had already quit cleanly and written 3826 profiles.
#
# Usage:
#   profile-run.sh <host> <variant> <url> [seconds]
#     e.g. profile-run.sh pbg4 leopard-g4-jit-pgo https://en.wikipedia.org/ 120
set -eu

HOST=${1:?usage: profile-run.sh host variant url [seconds]}
VARIANT=${2:?usage: profile-run.sh host variant url [seconds]}
URL=${3:?usage: profile-run.sh host variant url [seconds]}
SECONDS_TO_RUN=${4:-120}
PROF=/tmp/polliwog-profiles
STRIP=${GCOV_PREFIX_STRIP:-4}
ZIP=$HOME/polliwog-build/stage/$VARIANT/Frameworks.zip

[ -f "$ZIP" ] || { echo "no $ZIP -- run package-webkit.sh $VARIANT first" >&2; exit 1; }

echo "==> copying $(du -h "$ZIP" | awk '{print $1}') of instrumented engine to $HOST"
local_sum=$(md5 -q "$ZIP")
remote_sum=$(ssh -n -o ConnectTimeout=90 "$HOST" "md5 -q /tmp/Frameworks.zip 2>/dev/null" || true)
[ "$local_sum" = "$remote_sum" ] || scp -O -q "$ZIP" "$HOST:/tmp/Frameworks.zip"

ssh -o ConnectTimeout=90 "$HOST" "
    set -u
    A=\$HOME/polliwog-engine-test/'Captain Polliwog.app'
    killall CaptainPolliwog 2>/dev/null; sleep 2
    if [ ! -d \"\$A\" ]; then
        mkdir -p \$HOME/polliwog-engine-test
        ditto \$HOME/CaptainPolliwog/build/'Captain Polliwog.app' \"\$A\"
    fi
    B=\$HOME/CaptainPolliwog/build/'Captain Polliwog.app'
    if [ -d \"\$B\" ]; then
        cp \"\$B/Contents/MacOS/CaptainPolliwog\" \"\$A/Contents/MacOS/\"
        cp -R \"\$B/Contents/Resources/\" \"\$A/Contents/Resources/\"
    fi
    cd \"\$A/Contents\" && rm -rf Frameworks && unzip -q /tmp/Frameworks.zip

    # LSEnvironment, because an app started by LaunchServices does not get
    # the environment of the shell that asked for it.
    defaults write \"\$A/Contents/Info\" LSEnvironment -dict \\
        DYLD_FRAMEWORK_PATH \"\$A/Contents/Frameworks\" \\
        GCOV_PREFIX '$PROF' GCOV_PREFIX_STRIP '$STRIP'
    plutil -convert xml1 \"\$A/Contents/Info.plist\"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f \"\$A\"

    # libgcov merges into an existing .gcda, so a stale directory would
    # quietly become part of this profile.
    rm -rf '$PROF'; mkdir -p '$PROF'

    D=org.captainpolliwog.browser
    defaults write \$D CPDebugURL '$URL'
    start=\$(date +%s)
    open \"\$A\"

    echo \"==> running for $SECONDS_TO_RUN s\"
    i=0
    while [ \$i -lt $SECONDS_TO_RUN ]; do
        sleep 5; i=\$((i + 5))
        if ! ps -axco command | grep -qx CaptainPolliwog; then
            echo \"==> app exited on its own after \${i}s\"; break
        fi
    done

    ps -axco pid,rss,command | awk '\$3 == \"CaptainPolliwog\" { printf \"==> memory %d MB\n\", \$2 / 1024 }'

    # A Quit Apple Event, not a signal: the atexit handler is the only
    # thing that writes the profile out.
    if ps -axco command | grep -qx CaptainPolliwog; then
        echo '==> asking it to quit'
        osascript -e 'tell application \"Captain Polliwog\" to quit' 2>/dev/null || true
        j=0
        while ps -axco command | grep -qx CaptainPolliwog; do
            sleep 3; j=\$((j + 3))
            if [ \$j -ge 60 ]; then
                echo '==> it did not quit; killing it, which loses the profile'
                killall CaptainPolliwog 2>/dev/null; break
            fi
        done
        echo \"==> quit took \${j}s\"
    fi
    sleep 3
    defaults delete \$D CPDebugURL 2>/dev/null || true

    crash=\$(ls -t \$HOME/Library/Logs/CrashReporter/CaptainPolliwog* 2>/dev/null | head -1)
    if [ -n \"\$crash\" ] && [ \$(stat -f %m \"\$crash\") -ge \$start ]; then
        echo \"==> CRASHED: \$crash\"; grep -A10 'Crashed:' \"\$crash\" | head -12
    fi
    echo \"==> profiles written: \$(find '$PROF' -name '*.gcda' 2>/dev/null | wc -l | tr -d ' ')\"
    true"
