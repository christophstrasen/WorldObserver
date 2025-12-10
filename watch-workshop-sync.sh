#!/usr/bin/env bash
set -euo pipefail

# Run from repo root (which itself contains Contents/, preview.png, etc.)
SRC_MOD_DIR="."
DEST_WRAPPER="$HOME/Zomboid/Workshop/WorldObserver"
# LQR submodule lives outside the shipped mod tree; we mirror only its Lua payload.
# This should become a separate mod if ever other mods will use it as dependency
LQR_SRC="external/LQR/LQR"
LQR_DEST="$DEST_WRAPPER/Contents/mods/WorldObserver/42/media/lua/shared/LQR"

echo "Watching '$SRC_MOD_DIR' → '$DEST_WRAPPER'"

RSYNC_EXCLUDES=(
  "--exclude=.git/" "--exclude=.github/" "--exclude=.idea/" "--exclude=.vscode/"
  "--exclude=.direnv/" "--exclude=dist/" "--exclude=build/" "--exclude=out/"
  "--exclude=tmp/" "--exclude=__pycache__/" "--exclude=node_modules/" "--exclude=external/"
  "--exclude=docs/" "--exclude=tests/" "--exclude=.DS_Store"
  "--exclude=Contents/mods/WorldObserver/42/media/lua/shared/LQR/"
)

sync_once() {
  # Primary sync: copy mod tree but skip heavy/unneeded/dev folders (including submodules).
  rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$SRC_MOD_DIR/" "$DEST_WRAPPER/"
  # Secondary sync: ship only LQR Lua sources into the mod runtime path (strip everything else).
  if [ -d "$LQR_SRC" ]; then
    rsync -a --delete \
      --include='*/' --include='*.lua' --exclude='*' \
      "$LQR_SRC/" "$LQR_DEST/"
  else
    echo "[warn] LQR submodule missing at $LQR_SRC; skipped LQR sync"
  fi
  echo "[synced] $(date '+%H:%M:%S')"
}

sync_once
echo "Watching for changes…"
while inotifywait -r -e modify,create,delete,move "$SRC_MOD_DIR"; do
  sync_once
done
