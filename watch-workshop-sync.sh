#!/usr/bin/env bash
set -euo pipefail

# Run from repo root (which itself contains Contents/, preview.png, etc.)
SRC_MOD_DIR="."
DEST_WRAPPER="$HOME/Zomboid/Workshop/WorldObserver"
# LQR submodule lives outside the shipped mod tree; we mirror only its Lua payload.
# This should become a separate mod if ever other mods will use it as dependency
LQR_SRC="external/LQR/LQR"
LQR_DEST="$DEST_WRAPPER/Contents/mods/WorldObserver/42/media/lua/shared/LQR"
# Standalone lua-reactivex submodule (kept out of LQR); ship its Lua payload alongside LQR.
REACTIVEX_SRC="external/lua-reactivex"
REACTIVEX_DEST="$DEST_WRAPPER/Contents/mods/WorldObserver/42/media/lua/shared"
# Root-level shims so PZ can require folder modules without init.lua auto-loading.
SHIM_DEST="$DEST_WRAPPER/Contents/mods/WorldObserver/42/media/lua/shared"
LQR_SHIM_SRC="external/LQR/LQR.lua"
RX_SHIM_SRC="external/LQR/reactivex.lua"

GREEN="\033[32m"
RED_BG="\033[41;97m"
RESET="\033[0m"

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
  # We explicitly exclude any vendored reactivex inside LQR; the canonical reactivex comes from external/lua-reactivex.
  if [ -d "$LQR_SRC" ]; then
    rsync -a --delete \
      --include='*/' --include='*.lua' \
      --exclude='reactivex.lua' --exclude='reactivex/**' --exclude='*' \
      "$LQR_SRC/" "$LQR_DEST/"
  else
    echo "[warn] LQR submodule missing at $LQR_SRC; skipped LQR sync"
  fi
  # Copy shims for require("LQR") and require("reactivex") at the shared root.
  if [ -f "$LQR_SHIM_SRC" ]; then
    rsync -a "$LQR_SHIM_SRC" "$SHIM_DEST/LQR.lua"
  else
    echo "[warn] LQR shim missing at $LQR_SHIM_SRC; skipped"
  fi
  if [ -f "$RX_SHIM_SRC" ]; then
    rsync -a "$RX_SHIM_SRC" "$SHIM_DEST/reactivex.lua"
  else
    echo "[warn] reactivex shim missing at $RX_SHIM_SRC; skipped"
  fi
  # Tertiary sync: ship lua-reactivex (reactivex.lua + reactivex/*) alongside the mod.
  if [ -d "$REACTIVEX_SRC/reactivex" ]; then
    rsync -a --delete --include='*/' --include='*.lua' --exclude='*' \
      "$REACTIVEX_SRC/reactivex/" "$REACTIVEX_DEST/reactivex/"
    if [ -f "$REACTIVEX_SRC/reactivex.lua" ]; then
      rsync -a "$REACTIVEX_SRC/reactivex.lua" "$REACTIVEX_DEST/reactivex.lua"
    fi
  else
    echo "[warn] lua-reactivex submodule missing at $REACTIVEX_SRC; skipped reactivex sync"
  fi
  # Copy the operators aggregator (root-level operators.lua) so require(\"reactivex/operators\") resolves without init.lua.
  if [ -f "$REACTIVEX_SRC/operators.lua" ]; then
    rsync -a "$REACTIVEX_SRC/operators.lua" "$REACTIVEX_DEST/operators.lua"
  else
    echo "[warn] reactivex operators.lua missing at $REACTIVEX_SRC/operators.lua; operators preload may fail"
  fi

  # Post-sync smoke test against the destination tree. This simulates the PZ
  # runtime (missing debug, minimal package) and ensures requires resolve.
  if command -v lua >/dev/null; then
    if PZ_LUA_PATH="$DEST_WRAPPER/Contents/mods/WorldObserver/42/media/lua/shared/?.lua;$DEST_WRAPPER/Contents/mods/WorldObserver/42/media/lua/shared/?/init.lua;;" \
      lua "$SRC_MOD_DIR/pz_smoke.lua" WorldObserver LQR reactivex; then
      echo -e "${GREEN}[smoke ok]${RESET}"
    else
      echo -e "${RED_BG}[smoke FAIL]${RESET}"
    fi
  else
    echo "[warn] lua not found; skipped smoke test"
  fi
  echo "[synced] $(date '+%H:%M:%S')"
}

sync_once
echo "Watching for changes…"
while inotifywait -r -e modify,create,delete,move "$SRC_MOD_DIR"; do
  sync_once
done
