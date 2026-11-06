#!/bin/sh
set -eu
cd "$(dirname "$0")"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
clang -O2 -fblocks -DTF_TEST test_bridge.c -framework IOKit -framework CoreFoundation -o "$tmpdir/test-bridge"
"$tmpdir/test-bridge"
clang -O2 -fobjc-arc -fblocks test_player1.m player1.m -framework Foundation -framework GameController -o "$tmpdir/test-player1"
"$tmpdir/test-player1"
sh studio/build.sh
"outputs/Twin Controller Studio.app/Contents/MacOS/TwinControllerStudio" --self-test-ui
"outputs/Twin Controller Studio.app/Contents/MacOS/TwinControllerStudio" --self-test-sync
