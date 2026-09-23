#!/bin/bash
# Every symbol the Tiger build imports, checked against what this Tiger
# actually exports.
#
# The engine and its libraries are built against the 10.5 SDK with a 10.4
# deployment target, so anything Leopard added is weakly linked and simply
# absent at runtime. That covers the frameworks. It does not cover the
# libraries we build ourselves - ICU, libxml2, libxslt, SQLite - which link
# against the SDK's own stubs for libz, libSystem and the rest, and happily
# record a reference to a function this system has never had.
#
# Nothing notices, because those references are bound lazily: the
# application launches, renders, and dies the first time a page reaches the
# code that calls one. A page with a gzipped stylesheet, or a date to parse.
# From the outside that is "it crashes on YouTube".
#
# Run it ON a Tiger machine, against an installed copy:
#   ./tiger-symbol-check.sh "/Applications/Captain Polliwog.app"
set -u
APP=${1:-/Applications/Captain Polliwog.app}
FW="$APP/Contents/Frameworks-10.4"
[ -d "$FW" ] || { echo "no Frameworks-10.4 in $APP" >&2; exit 1; }

# Where a two-level namespace hint points. nm -m names the library a symbol
# is expected to come from by its short name - "libz", "libgcc_s" - and the
# image's own dependency list says which file that is, which may be one of
# ours in the bundle rather than the system's.
resolve_dep()
{
    local image=$1 want=$2 path leaf
    otool -L "$image" 2>/dev/null | sed -n '2,$p' | awk '{print $1}' | while read -r path; do
        leaf=$(basename "$path")
        leaf=${leaf%.dylib}
        # libz.1 -> libz, libgcc_s.1 -> libgcc_s, libSystem.B -> libSystem
        while : ; do
            case $leaf in
                *.[0-9]|*.[0-9][0-9]|*.A|*.B) leaf=${leaf%.*} ;;
                *) break ;;
            esac
        done
        if [ "$leaf" = "$want" ]; then
            case $path in
                @executable_path/*) echo "$APP/Contents/MacOS/${path#@executable_path/}" ;;
                @loader_path/*|@rpath/*) ;;   # relative to the image; not needed here
                *) echo "$path" ;;
            esac
            return
        fi
    done
}

CACHE=$(mktemp -d -t tigersymbols) || CACHE=/tmp/tigersymbols.$$
mkdir -p "$CACHE"
trap 'rm -rf "$CACHE"' EXIT
: > "$CACHE/missing"

# find, read line by line: this bundle's path has a space in it, and a list
# of paths passed through word splitting becomes a list of halves of paths.
find "$APP/Contents/MacOS" "$FW" -type f -print | while read -r image; do
    case "$image" in *.plist|*.lproj/*|*/Resources/*|*.nib|*.png|*.icns) continue ;; esac
    file "$image" 2>/dev/null | grep -q "Mach-O" || continue

    # nm -m names the library each undefined symbol is expected to come
    # from - the two-level namespace hint, which is what dyld goes by.
    # A weak import is one the build expects this system may not have -
    # everything Leopard added is linked that way, and dyld leaves it null
    # rather than refusing to start. Those are the design; skip them.
    nm -m "$image" 2>/dev/null | grep -v "weak external" | awk '/\(undefined\)/ && /\(from / {
        sym = ""; from = "";
        for (i = 1; i <= NF; i++) {
            if (substr($i, 1, 1) == "_") sym = $i;
            if ($i == "(from") { from = $(i+1); sub(/\)$/, "", from); }
        }
        if (sym != "" && from != "") print from, sym;
    }' | sort -u > "$CACHE/wanted"

    while read -r lib sym; do
        if [ ! -f "$CACHE/lib.$lib" ]; then
            libpath=$(resolve_dep "$image" "$lib" | head -1)
            if [ -n "$libpath" ] && [ -f "$libpath" ]; then
                # Cocoa, Quartz and the other umbrellas export almost nothing
                # themselves; the symbols are in the frameworks they re-export,
                # and that is where dyld looks too. One level down covers it.
                nm -g "$libpath" 2>/dev/null | awk '$2 ~ /^[TDSBAIR]$/ { print $3 }' > "$CACHE/lib.$lib"
                otool -L "$libpath" 2>/dev/null | sed -n '3,$p' | awk '{print $1}' | \
                  grep "^/System\|^/usr/lib" | while read -r sub; do
                    [ -f "$sub" ] && nm -g "$sub" 2>/dev/null | awk '$2 ~ /^[TDSBAIR]$/ { print $3 }'
                done >> "$CACHE/lib.$lib"
            else
                : > "$CACHE/lib.$lib"
            fi
        fi
        # An empty list means a library we cannot check - one of ours, or
        # not on this system. Say nothing rather than cry wolf.
        [ -s "$CACHE/lib.$lib" ] || continue
        if ! grep -qx "$sym" "$CACHE/lib.$lib"; then
            echo "MISSING  $(basename "$image")  wants  $sym  from  $lib"
            echo "$sym" >> "$CACHE/missing"
        fi
    done < "$CACHE/wanted"
done

echo
n=$(wc -l < "$CACHE/missing" | tr -d " ")
if [ "$n" = 0 ]; then
    echo "Every symbol this build imports exists on this system."
else
    echo "$n symbol(s) this system has not got. Each one is a page that loads"
    echo "until it reaches the code that calls it, and then an application"
    echo "that disappears."
fi
