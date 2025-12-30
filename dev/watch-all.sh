#!/usr/bin/env bash
set -euo pipefail

# Maintainer convenience: one watcher that triggers per-repo sync scripts.
# This repo currently contains WorldObserver and the PromiseKeeper submodule.
# When the other mods (LQR/reactivex/DREAM) live in sibling repos, add them here.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$REPO_ROOT/.." && pwd)"

TARGET="${TARGET:-workshop}" # mods|workshop
WATCH_MODE="${WATCH_MODE:-payload}" # payload|repo

run_sync() {
  local repo_root="$1"
  local label="$2"

  local script="$repo_root/dev/sync-$TARGET.sh"
  if [ ! -f "$script" ]; then
    echo "[warn] missing $label sync script: $script"
    return 0
  fi

  (cd "$repo_root" && "$script")
}

sync_all() {
  run_sync "$REPO_ROOT" "WorldObserver"

  if [ -d "$REPO_ROOT/external/PromiseKeeper" ]; then
    run_sync "$REPO_ROOT/external/PromiseKeeper" "PromiseKeeper"
  fi

  # Optional sibling repos (when you keep all mods side-by-side locally).
  if [ -d "$WORKSPACE_ROOT/pz-reactivex" ]; then
    run_sync "$WORKSPACE_ROOT/pz-reactivex" "reactivex"
  fi
  if [ -d "$WORKSPACE_ROOT/pz-lqr" ]; then
    run_sync "$WORKSPACE_ROOT/pz-lqr" "LQR"
  fi
  if [ -d "$WORKSPACE_ROOT/pz-dream" ]; then
    run_sync "$WORKSPACE_ROOT/pz-dream" "DREAM"
  fi
}

compute_fingerprint() {
  local paths=(
    "$REPO_ROOT/Contents/mods/WorldObserver"
    "$REPO_ROOT/workshop.txt"
    "$REPO_ROOT/preview.png"
    "$REPO_ROOT/256.svg"
    "$REPO_ROOT/512.svg"
    "$REPO_ROOT/64.svg"
    "$REPO_ROOT/external/PromiseKeeper/Contents/mods/PromiseKeeper"
    "$REPO_ROOT/external/PromiseKeeper/workshop.txt"
    "$REPO_ROOT/external/PromiseKeeper/preview.png"
    "$WORKSPACE_ROOT/pz-reactivex/Contents/mods/reactivex"
    "$WORKSPACE_ROOT/pz-reactivex/workshop.txt"
    "$WORKSPACE_ROOT/pz-reactivex/preview.png"
    "$WORKSPACE_ROOT/pz-reactivex/external/lua-reactivex"
    "$WORKSPACE_ROOT/pz-lqr/Contents/mods/LQR"
    "$WORKSPACE_ROOT/pz-lqr/workshop.txt"
    "$WORKSPACE_ROOT/pz-lqr/preview.png"
    "$WORKSPACE_ROOT/pz-lqr/external/LQR"
    "$WORKSPACE_ROOT/pz-dream/Contents/mods/DREAM"
    "$WORKSPACE_ROOT/pz-dream/workshop.txt"
    "$WORKSPACE_ROOT/pz-dream/preview.png"
  )

  find "${paths[@]}" -type f 2>/dev/null \
    | LC_ALL=C sort \
    | xargs -I{} stat -c '%n %s %Y' {} 2>/dev/null \
    | sha1sum \
    | awk '{print $1}'
}

echo "Watching all (TARGET=$TARGET)…"
sync_all

if command -v inotifywait >/dev/null; then
  case "$WATCH_MODE" in
    payload)
      WATCH_PATHS=(
        "$REPO_ROOT/Contents/mods/WorldObserver"
        "$REPO_ROOT/workshop.txt"
        "$REPO_ROOT/preview.png"
        "$REPO_ROOT/256.svg"
        "$REPO_ROOT/512.svg"
        "$REPO_ROOT/64.svg"
        "$REPO_ROOT/external/PromiseKeeper/Contents/mods/PromiseKeeper"
        "$REPO_ROOT/external/PromiseKeeper/workshop.txt"
        "$REPO_ROOT/external/PromiseKeeper/preview.png"
        "$WORKSPACE_ROOT/pz-reactivex/Contents/mods/reactivex"
        "$WORKSPACE_ROOT/pz-reactivex/workshop.txt"
        "$WORKSPACE_ROOT/pz-reactivex/preview.png"
        "$WORKSPACE_ROOT/pz-reactivex/external/lua-reactivex"
        "$WORKSPACE_ROOT/pz-lqr/Contents/mods/LQR"
        "$WORKSPACE_ROOT/pz-lqr/workshop.txt"
        "$WORKSPACE_ROOT/pz-lqr/preview.png"
        "$WORKSPACE_ROOT/pz-lqr/external/LQR"
        "$WORKSPACE_ROOT/pz-dream/Contents/mods/DREAM"
        "$WORKSPACE_ROOT/pz-dream/workshop.txt"
        "$WORKSPACE_ROOT/pz-dream/preview.png"
      )
      ;;
    repo)
      WATCH_PATHS=("$REPO_ROOT")
      ;;
    *)
      echo "[error] unknown WATCH_MODE='$WATCH_MODE' (expected 'payload' or 'repo')"
      exit 1
      ;;
  esac

  echo "Watching paths:"
  printf '  - %s\n' "${WATCH_PATHS[@]}"
  if [ "$WATCH_MODE" = "payload" ]; then
    echo "Note: edits outside these paths will not trigger a sync."
  fi

  inotifywait -m -q -r -e close_write,modify,attrib,create,delete,move \
    --format '%w%f' \
    "${WATCH_PATHS[@]}" 2>/dev/null |
    while IFS= read -r _path; do
      if [ "${VERBOSE:-0}" = "1" ]; then
        echo "[change] $_path"
      fi
      sync_all
    done
else
  echo "[warn] inotifywait not found; using polling fallback"
  prev="$(compute_fingerprint)"
  while true; do
    sleep 0.5
    next="$(compute_fingerprint)"
    if [ "$next" != "$prev" ]; then
      prev="$next"
      sync_all
    fi
  done
fi
