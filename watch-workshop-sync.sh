#!/usr/bin/env bash
set -euo pipefail

# --- Resolve repo root as "directory containing this script" ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Mod name (configurable) ---
# If not set, use the name of the parent folder of this script (repo root folder name).
MOD_NAME="${MOD_NAME:-$(basename "$SCRIPT_DIR")}"

# Run from repo root (which itself contains Contents/, preview.png, etc.)
SRC_MOD_DIR="."
DEST_WRAPPER="${DEST_WRAPPER:-$HOME/Zomboid/Workshop/$MOD_NAME}"

# LQR submodule lives outside the shipped mod tree; we mirror only its Lua payload.
# This should become a separate mod if ever other mods will use it as dependency
LQR_SRC="external/LQR/LQR"
LQR_DEST="$DEST_WRAPPER/Contents/mods/$MOD_NAME/42/media/lua/shared/LQR"

# Standalone lua-reactivex submodule (kept out of LQR); ship its Lua payload alongside LQR.
REACTIVEX_SRC="external/lua-reactivex"
REACTIVEX_DEST="$DEST_WRAPPER/Contents/mods/$MOD_NAME/42/media/lua/shared"

# PromiseKeeper lives in the SceneBuilder repo but is shipped as a library payload.
# We mirror only the Lua payload (PromiseKeeper/ + PromiseKeeper.lua) into SceneBuilder's shared root.
PROMISEKEEPER_SRC="external/PromiseKeeper/Contents/mods/SceneBuilder/42/media/lua/shared"
PROMISEKEEPER_DEST="$DEST_WRAPPER/Contents/mods/SceneBuilder/42/media/lua/shared"

# Root-level shims so PZ can require folder modules without init.lua auto-loading.
SHIM_DEST="$DEST_WRAPPER/Contents/mods/$MOD_NAME/42/media/lua/shared"
LQR_SHIM_SRC="external/LQR/LQR.lua"

GREEN="\033[32m"
RED_BG="\033[41;97m"
RESET="\033[0m"

echo "Watching '$SRC_MOD_DIR' → '$DEST_WRAPPER'"
echo "MOD_NAME='$MOD_NAME'"

RSYNC_EXCLUDES=(
  "--exclude=.git/" "--exclude=.github/" "--exclude=.idea/" "--exclude=.vscode/"
  "--exclude=.direnv/" "--exclude=dist/" "--exclude=build/" "--exclude=out/"
  "--exclude=tmp/" "--exclude=__pycache__/" "--exclude=node_modules/" "--exclude=external/"
  "--exclude=docs/" "--exclude=tests/" "--exclude=.DS_Store"
  "--exclude=Contents/mods/$MOD_NAME/42/media/lua/shared/LQR/"
  "--exclude=Contents/mods/SceneBuilder/42/media/lua/shared/PromiseKeeper/"
  "--exclude=Contents/mods/SceneBuilder/42/media/lua/shared/PromiseKeeper.lua"
)

check_png_plausible() {
  local path="$1"
  local min_bytes="$2"

  if [ ! -f "$path" ]; then
    echo -e "${RED_BG}[assets FAIL]${RESET} missing: $path"
    return 1
  fi

  # Basic type check if `file` exists (best-effort).
  if command -v file >/dev/null; then
    local mt
    mt="$(file -b --mime-type "$path" || true)"
    if [ "$mt" != "image/png" ]; then
      echo -e "${RED_BG}[assets FAIL]${RESET} not a PNG ($mt): $path"
      return 1
    fi
  fi

  local size
  size="$(stat -c '%s' "$path" 2>/dev/null || wc -c <"$path")"
  if [ "$size" -lt "$min_bytes" ]; then
    echo -e "${RED_BG}[assets FAIL]${RESET} too small (${size}B): $path"
    return 1
  fi

  return 0
}

export_svg_png() {
  local svg="$1"
  local out="$2"
  local w="$3"
  local h="$4"
  local min_bytes="$5"

  if [ ! -f "$svg" ]; then
    echo -e "${RED_BG}[assets FAIL]${RESET} missing SVG: $svg"
    return 1
  fi

  mkdir -p "$(dirname "$out")"

  if ! command -v inkscape >/dev/null; then
    echo -e "${RED_BG}[assets FAIL]${RESET} inkscape not found in PATH"
    return 1
  fi

  # Inkscape CLI (stable across versions):
  # - export-type=png + export-filename
  # - set explicit width/height for determinism
  inkscape "$svg" \
    --export-type=png \
    --export-filename="$out" \
    -w "$w" -h "$h" \
    >/dev/null

  check_png_plausible "$out" "$min_bytes"
}

build_assets() {
  # Inputs are relative to repo root (script dir).
  # 1) 512.svg -> Contents/mods/<MOD_NAME>/42/poster.png
  # 2) 256.svg -> preview.png
  # 3) 64.svg  -> Contents/mods/<MOD_NAME>/42/icon_64.png
  export_svg_png "512.svg" "Contents/mods/$MOD_NAME/42/poster.png" 512 512 2000
  export_svg_png "256.svg" "preview.png" 256 256 1000
  export_svg_png "64.svg" "Contents/mods/$MOD_NAME/42/icon_64.png" 64 64 400

  echo -e "${GREEN}[assets ok]${RESET}"
}

sync_once() {
  # Build SVG-derived PNGs before syncing.
  build_assets

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

  # Copy the operators aggregator (root-level operators.lua) so require("reactivex/operators") resolves without init.lua.
  if [ -f "$REACTIVEX_SRC/operators.lua" ]; then
    rsync -a "$REACTIVEX_SRC/operators.lua" "$REACTIVEX_DEST/operators.lua"
  else
    echo "[warn] reactivex operators.lua missing at $REACTIVEX_SRC/operators.lua; operators preload may fail"
  fi

  # Ship PromiseKeeper payload into the SceneBuilder shared root (PromiseKeeper/ + PromiseKeeper.lua).
  if [ -d "$PROMISEKEEPER_SRC/PromiseKeeper" ]; then
    mkdir -p "$PROMISEKEEPER_DEST"
    rsync -a --delete --include='*/' --include='*.lua' --exclude='*' \
      "$PROMISEKEEPER_SRC/PromiseKeeper/" "$PROMISEKEEPER_DEST/PromiseKeeper/"
    if [ -f "$PROMISEKEEPER_SRC/PromiseKeeper.lua" ]; then
      rsync -a "$PROMISEKEEPER_SRC/PromiseKeeper.lua" "$PROMISEKEEPER_DEST/PromiseKeeper.lua"
    else
      echo "[warn] PromiseKeeper shim missing at $PROMISEKEEPER_SRC/PromiseKeeper.lua; skipped"
    fi
  else
    echo "[warn] PromiseKeeper submodule missing at $PROMISEKEEPER_SRC; skipped PromiseKeeper sync"
  fi

  # Post-sync smoke test against the destination tree. This simulates the PZ
  # runtime (missing debug, minimal package) and ensures requires resolve.
  if command -v lua >/dev/null; then
    if PZ_LUA_PATH="$DEST_WRAPPER/Contents/mods/$MOD_NAME/42/media/lua/shared/?.lua;$DEST_WRAPPER/Contents/mods/$MOD_NAME/42/media/lua/shared/?/init.lua;;" \
      lua "$SRC_MOD_DIR/pz_smoke.lua" "$MOD_NAME" LQR reactivex; then
      echo -e "${GREEN}[smoke ok]${RESET}"
    else
      echo -e "${RED_BG}[smoke FAIL]${RESET}"
    fi

    if [ -f "$PROMISEKEEPER_DEST/PromiseKeeper.lua" ]; then
      if PZ_LUA_PATH="$PROMISEKEEPER_DEST/?.lua;$PROMISEKEEPER_DEST/?/init.lua;;" \
        lua "$SRC_MOD_DIR/pz_smoke.lua" PromiseKeeper; then
        echo -e "${GREEN}[smoke PromiseKeeper ok]${RESET}"
      else
        echo -e "${RED_BG}[smoke PromiseKeeper FAIL]${RESET}"
      fi
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
