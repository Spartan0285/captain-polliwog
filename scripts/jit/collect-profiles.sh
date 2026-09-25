#!/bin/bash
# Move profile data from a PowerPC Mac back into the cross-build tree, for
# the second half of a PGO build.
#
# The problem this solves: GCC writes the absolute path of each object into
# the instrumented binary, and libgcov writes the .gcda file to exactly that
# path at exit. Those paths are the build VM's -- /home/adam.guest/build/...
# -- and do not exist on a PowerBook. GCOV_PREFIX redirects the writes under
# a directory that does, and GCOV_PREFIX_STRIP says how many leading
# components of the original path to discard first.
#
# With BUILD=/home/adam.guest/build/leopard-g4-jit-pgo, the four components
# home, adam.guest, build and leopard-g4-jit-pgo come off, so a profile for
# CMakeFiles/JavaScriptCore.dir/foo.cpp.o lands at
# $GCOV_PREFIX/CMakeFiles/JavaScriptCore.dir/foo.cpp.gcda -- a tree that
# unpacks straight back over the build directory.
#
# Usage:
#   collect-profiles.sh run    <host> <command...>   run and collect
#   collect-profiles.sh fetch  <host>                collect an existing run
#   collect-profiles.sh install <tarball>            unpack into the build tree
#
# The run half executes on the Mac; the install half runs in the VM.
set -eu

ACTION=${1:?usage: collect-profiles.sh run|fetch|install ...}
shift

# Where the instrumented engine was built, and therefore how deep the paths
# baked into it are. Override both together if the layout changes.
BUILD_DIR=${BUILD_DIR:-/home/adam.guest/build/leopard-g4-jit-pgo}
STRIP=${GCOV_PREFIX_STRIP:-$(echo "${BUILD_DIR#/}" | awk -F/ '{print NF}')}
PROF_DIR=${PROF_DIR:-/tmp/polliwog-profiles}
TARBALL=${TARBALL:-/tmp/polliwog-profiles.tgz}

case $ACTION in
run)
    HOST=${1:?host}; shift
    # Clear first: libgcov MERGES into an existing .gcda, so a stale file
    # from an earlier workload quietly becomes part of this profile.
    ssh -n "$HOST" "rm -rf $PROF_DIR && mkdir -p $PROF_DIR"
    # shellcheck disable=SC2029  # the command is meant to expand here
    ssh "$HOST" "GCOV_PREFIX=$PROF_DIR GCOV_PREFIX_STRIP=$STRIP $*"
    exec "$0" fetch "$HOST"
    ;;

fetch)
    HOST=${1:?host}
    n=$(ssh -n "$HOST" "find $PROF_DIR -name '*.gcda' | wc -l" | tr -d ' ')
    if [ "$n" -eq 0 ]; then
        # An empty profile directory is the normal shape of this failing:
        # libgcov flushes from an atexit handler, so a process that was
        # killed, crashed, or is still running has written nothing at all.
        echo "no .gcda files in $PROF_DIR on $HOST." >&2
        echo "the process must exit cleanly for libgcov to flush." >&2
        exit 1
    fi
    echo "$n profile files on $HOST"
    ssh -n "$HOST" "cd $PROF_DIR && tar czf $TARBALL ."
    scp -q "$HOST:$TARBALL" "$TARBALL"
    ls -l "$TARBALL" | awk '{print $5, $9}'
    ;;

install)
    T=${1:-$TARBALL}
    [ -d "$BUILD_DIR" ] || { echo "no build directory $BUILD_DIR" >&2; exit 1; }
    before=$(find "$BUILD_DIR" -name '*.gcda' | wc -l)
    tar xzf "$T" -C "$BUILD_DIR"
    after=$(find "$BUILD_DIR" -name '*.gcda' | wc -l)
    echo "profiles in build tree: $before -> $after"
    # A profile that does not sit beside its object is one GCC will never
    # read, and it will not say so. Check a few landed correctly.
    matched=0
    while IFS= read -r g; do
        [ -f "${g%.gcda}.o" ] && matched=$((matched + 1))
    done < <(find "$BUILD_DIR" -name '*.gcda' | head -200)
    echo "of the first 200, $matched sit beside their object file"
    [ "$matched" -gt 0 ] || { echo "none matched: the strip depth is wrong" >&2; exit 1; }
    ;;

*)
    echo "usage: collect-profiles.sh run|fetch|install ..." >&2; exit 1 ;;
esac
