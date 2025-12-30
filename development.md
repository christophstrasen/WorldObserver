# WorldObserver — Development

WorldObserver is part of the DREAM mod family (Build 42):
- DREAM-Workspace (multi-repo convenience): https://github.com/christophstrasen/DREAM-Workspace

For the full internal development guide, see: `docs_internal/development.md`.

## Quickstart (single repo)

Prereqs: `rsync`, `inotifywait` (`inotify-tools`), `inkscape`, and a Lua 5.1 interpreter for the smoke test.

Init submodules:

```bash
git submodule update --init external/LQR external/lua-reactivex
```

Watch + deploy (default: Workshop wrapper under `~/Zomboid/Workshop`):

```bash
./dev/watch.sh
```

Optional: deploy to `~/Zomboid/mods` instead:

```bash
TARGET=mods ./dev/watch.sh
```

## Tests

Headless unit tests:

```bash
busted tests
```

Loader smoke test (after syncing):

```bash
./dev/sync-workshop.sh
SOURCE=workshop ./dev/smoke.sh
```
