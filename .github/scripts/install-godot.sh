#!/usr/bin/env bash
# Installs the Godot editor and all export templates for $GODOT_VERSION (e.g. "4.7-stable").
set -euo pipefail

base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}"
curl -fsSL -o godot.zip "$base/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
curl -fsSL -o templates.tpz "$base/Godot_v${GODOT_VERSION}_export_templates.tpz"
unzip -q godot.zip && mv "Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot
dir="$HOME/.local/share/godot/export_templates/${GODOT_VERSION/-/.}"
mkdir -p "$dir" && unzip -q templates.tpz && mv templates/* "$dir/"
rm -rf godot.zip templates.tpz templates
