#!/usr/bin/env bash
# Imports the project headlessly and fails on script or resource errors.
# Godot's exit code alone isn't reliable for this, so the log is checked as well.
set -uo pipefail

log="$(mktemp)"
godot --headless --import 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

if grep -qE "SCRIPT ERROR|Parse Error|Failed to load" "$log"; then
  echo "::error::Project import reported errors (see log above)."
  exit 1
fi
exit "$status"
