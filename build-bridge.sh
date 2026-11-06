#!/bin/sh
set -eu
cd "$(dirname "$0")"
clang -O2 -Wall -Wextra -Wno-unused-function -fPIC -fblocks -c twinfix.c -o twinfix.o
clang -O2 -Wall -Wextra -Wno-unused-function -fobjc-arc -fblocks -c player1.m -o player1.o
clang -dynamiclib twinfix.o player1.o -framework IOKit -framework CoreFoundation -framework Foundation -framework GameController -o twinfix.dylib
codesign --force --sign - twinfix.dylib
