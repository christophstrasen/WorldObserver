# WorldObserver — Development

WorldObserver is part of the DREAM mod family (Build 42):
- DREAM-Workspace (multi-repo convenience): https://github.com/christophstrasen/DREAM-Workspace

Prereqs (for the `dev/` scripts): `rsync`, `inotifywait` (`inotify-tools`), `inkscape`, and a Lua 5.1 interpreter for the smoke test.

## Submodules

```bash
git submodule update --init external/LQR external/lua-reactivex
```

## Sync

Deploy to your local Workshop wrapper folder (default):

```bash
./dev/sync-workshop.sh
```

Optional: deploy to `~/Zomboid/mods` instead:

```bash
./dev/sync-mods.sh
```

## Watch

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
busted --helper=tests/helper.lua tests/unit
```

Note: tests assume DREAMBase is available at `../DREAMBase` (DREAM-Workspace layout) or `external/DREAMBase`.

Loader smoke test (after syncing):

```bash
./dev/sync-workshop.sh
SOURCE=workshop ./dev/smoke.sh
```
