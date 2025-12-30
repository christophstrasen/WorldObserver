#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MOD_ID="WorldObserver"
SRC_MOD_DIR="$REPO_ROOT/Contents/mods/$MOD_ID"

PZ_WORKSHOP_DIR="${PZ_WORKSHOP_DIR:-$HOME/Zomboid/Workshop}"
WRAPPER_NAME="${WRAPPER_NAME:-$MOD_ID}"
DEST_WRAPPER="$PZ_WORKSHOP_DIR/$WRAPPER_NAME"

DEST_MOD_DIR="$DEST_WRAPPER/Contents/mods/$MOD_ID"

if [ ! -d "$SRC_MOD_DIR" ]; then
  echo "[error] missing mod folder: $SRC_MOD_DIR"
  exit 1
fi

mkdir -p "$DEST_MOD_DIR"

# Only ship what the Workshop uploader expects: workshop.txt + preview.png at wrapper root, and the mod payload.
rsync -a "$REPO_ROOT/workshop.txt" "$DEST_WRAPPER/"
rsync -a "$REPO_ROOT/preview.png" "$DEST_WRAPPER/"
rsync -a --delete "$SRC_MOD_DIR/" "$DEST_MOD_DIR/"

echo "[synced] $MOD_ID -> $DEST_MOD_DIR"
echo "[wrapper] $DEST_WRAPPER"

