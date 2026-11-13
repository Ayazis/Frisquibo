#!/usr/bin/env bash
# Renders the shots of a shot list and compares them with the local baseline.
#
#   tools/visual_check/run.sh <shot-list.tres> [baseline|compare|capture]
#
# Set GODOT to the Godot executable if it isn't on PATH (use the console build on Windows).
# Exit codes: 0 = all shots match, 1 = differences or missing baseline, 2 = error.
set -euo pipefail

list="${1:?usage: run.sh <shot-list.tres> [baseline|compare|capture]}"
mode="${2:-compare}"
godot="${GODOT:-godot}"

cd "$(dirname "$0")/../.."
# --fixed-fps makes time advance exactly one frame per frame, so shader animation and physics
# are identical between runs (renders are only comparable on the same machine and GPU).
exec "$godot" --path . --fixed-fps 60 --audio-driver Dummy \
  res://tools/visual_check/visual_check.tscn -- --shots="res://${list#./}" --mode="$mode"
