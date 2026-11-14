#!/bin/bash
# Install aeris-tiler: copy home/ into $HOME, backing up any file it replaces, build the
# Keysheet cheat sheet, and (re)start yabai, skhd, Hammerspoon and, if installed, sketchybar.
# Safe to re-run. Install the tools first (see README.md).

set -euo pipefail

cd "$(dirname "$0")"
stamp=$(date +%Y%m%d-%H%M%S)

# Copy each file; keep the old one as <file>.bak-<stamp> when it differs.
while IFS= read -r -d '' src; do
  dst="$HOME/${src#home/}"
  mkdir -p "$(dirname "$dst")"
  if [[ -e $dst ]] && ! cmp -s "$src" "$dst"; then
    cp -p "$dst" "$dst.bak-$stamp"
    echo "backed up $dst"
  fi
  cp -p "$src" "$dst"
done < <(find home -type f -print0)
chmod +x "$HOME/.local/bin/grid" "$HOME/.local/bin/tile" "$HOME/.local/bin/floating" "$HOME/.local/bin/layout"

keysheet/build.sh

yabai --restart-service 2>/dev/null || yabai --start-service
skhd --restart-service 2>/dev/null || skhd --start-service
if command -v sketchybar >/dev/null; then
  brew services restart sketchybar
fi
open -a Hammerspoon

echo "Done. Grant Accessibility to yabai, skhd and Hammerspoon in System Settings → Privacy & Security."
