#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MOD_ID="WorldObserver"
PZ_MODS_DIR="${PZ_MODS_DIR:-$HOME/Zomboid/mods}"
PZ_WORKSHOP_DIR="${PZ_WORKSHOP_DIR:-$HOME/Zomboid/Workshop}"

SOURCE="${SOURCE:-mods}" # mods|workshop
WRAPPER_NAME="${WRAPPER_NAME:-$MOD_ID}"

case "$SOURCE" in
  mods)
    worldobserver_shared="$PZ_MODS_DIR/$MOD_ID/42/media/lua/shared"
    ;;
  workshop)
    worldobserver_shared="$PZ_WORKSHOP_DIR/$WRAPPER_NAME/Contents/mods/$MOD_ID/42/media/lua/shared"
    ;;
  *)
    echo "[error] unknown SOURCE='$SOURCE' (expected 'mods' or 'workshop')"
    exit 1
    ;;
esac

reactivex_shared="$PZ_MODS_DIR/reactivex/42/media/lua/shared"
lqr_shared="$PZ_MODS_DIR/LQR/42/media/lua/shared"

missing=()
for p in "$worldobserver_shared" "$reactivex_shared" "$lqr_shared"; do
  if [ ! -d "$p" ]; then
    missing+=("$p")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "[error] missing deployed dependency folders under PZ_MODS_DIR:"
  printf '  - %s\n' "${missing[@]}"
  echo "Set PZ_MODS_DIR or run each repo's dev/sync-mods.sh first."
  exit 2
fi

if ! command -v lua >/dev/null; then
  echo "[error] lua not found in PATH"
  exit 1
fi

PZ_LUA_PATH="$(printf "%s/?.lua;%s/?/init.lua;%s/?.lua;%s/?/init.lua;%s/?.lua;%s/?/init.lua;;" \
  "$worldobserver_shared" "$worldobserver_shared" \
  "$lqr_shared" "$lqr_shared" \
  "$reactivex_shared" "$reactivex_shared")" \
  lua "$REPO_ROOT/pz_smoke.lua" WorldObserver LQR reactivex
