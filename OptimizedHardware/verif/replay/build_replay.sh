#!/usr/bin/env bash
# build_replay.sh - Build a Verilator trace-replay checker for one core.
# Usage: build_replay.sh <name> <top_module> <sv files...>
# Produces replay/build/<name>/replay
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME="$1"; TOP="$2"; shift 2
OBJ="$HERE/build/$NAME"
mkdir -p "$OBJ"
verilator --cc --exe --build -O3 -j 0 --prefix Vdut --top-module "$TOP" \
    -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL -Wno-CASEINCOMPLETE \
    -Wno-UNOPTFLAT -Wno-LATCH -Wno-MULTIDRIVEN \
    --Mdir "$OBJ" -o replay "$@" "$HERE/replay.cpp" > "$OBJ/build.log" 2>&1 \
    || { tail -40 "$OBJ/build.log"; exit 1; }
echo "built $OBJ/replay"
