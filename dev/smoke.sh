#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MOD_ID="WorldObserver"
PZ_MODS_DIR="${PZ_MODS_DIR:-$HOME/Zomboid/mods}"
PZ_WORKSHOP_DIR="${PZ_WORKSHOP_DIR:-$HOME/Zomboid/Workshop}"

SOURCE="${SOURCE:-workshop}" # mods|workshop
WRAPPER_NAME="${WRAPPER_NAME:-$MOD_ID}"

case "$SOURCE" in
  mods)
    worldobserver_shared="$PZ_MODS_DIR/$MOD_ID/42/media/lua/shared"
    reactivex_shared="$PZ_MODS_DIR/reactivex/42/media/lua/shared"
    lqr_shared="$PZ_MODS_DIR/LQR/42/media/lua/shared"
    dreambase_shared="$PZ_MODS_DIR/DREAMBase/42/media/lua/shared"
    ;;
  workshop)
    worldobserver_shared="$PZ_WORKSHOP_DIR/$WRAPPER_NAME/Contents/mods/$MOD_ID/42/media/lua/shared"
    reactivex_shared="$PZ_WORKSHOP_DIR/reactivex/Contents/mods/reactivex/42/media/lua/shared"
    lqr_shared="$PZ_WORKSHOP_DIR/LQR/Contents/mods/LQR/42/media/lua/shared"
    dreambase_shared="$PZ_WORKSHOP_DIR/DREAMBase/Contents/mods/DREAMBase/42/media/lua/shared"
    ;;
  *)
    echo "[error] unknown SOURCE='$SOURCE' (expected 'mods' or 'workshop')"
    exit 1
    ;;
esac

missing=()
for p in "$worldobserver_shared" "$reactivex_shared" "$lqr_shared" "$dreambase_shared"; do
  if [ ! -d "$p" ]; then
    missing+=("$p")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "[error] missing deployed dependency folders for SOURCE=$SOURCE:"
  printf '  - %s\n' "${missing[@]}"
  echo "Set PZ_MODS_DIR/PZ_WORKSHOP_DIR or run the matching sync (TARGET=$SOURCE) first."
  exit 2
fi

if ! command -v lua >/dev/null; then
  echo "[error] lua not found in PATH"
  exit 1
fi

PZ_LUA_PATH="$(printf "%s/?.lua;%s/?/init.lua;%s/?.lua;%s/?/init.lua;%s/?.lua;%s/?/init.lua;;" \
  "$worldobserver_shared" "$worldobserver_shared" \
  "$dreambase_shared" "$dreambase_shared" \
  "$lqr_shared" "$lqr_shared" \
  "$reactivex_shared" "$reactivex_shared")" \
  lua "$REPO_ROOT/pz_smoke.lua" WorldObserver LQR reactivex
