# WorldObserver – Development workflow

Internal notes on how to clone, set up, test, and run WorldObserver during development.

---

## 1. Clone and submodules

- Clone the repo as usual:

  ```bash
  git clone git@github.com:christophstrasen/WorldObserver.git
  cd WorldObserver
  ```

- Bring in the two top‑level submodules:

  ```bash
  git submodule update --init external/LQR external/lua-reactivex
  ```

  Notes:

  - `external/LQR` is the LQR query engine and its tests/docs.
  - `external/lua-reactivex` is the lua‑reactivex fork used by both LQR and WorldObserver.
  - LQR itself declares a nested `reactivex` submodule; **do not** initialize or work in `external/LQR/reactivex`. The workspace treats `external/lua-reactivex` as the canonical reactive dependency.

---

## 2. Local tooling

Recommended tools:

- A Lua interpreter (`lua` on PATH) for running the smoke test.
- [`busted`](https://olivinelabs.com/busted/) for headless tests:

  ```bash
  # via luarocks, for example:
  luarocks install busted
  ```

- `rsync` and `inotifywait` (from `inotify-tools`) for the workshop sync script.
- `rsync` and `inotifywait` (from `inotify-tools`) for the dev sync/watch scripts under `dev/`.
- Optional: [`pre-commit`](https://pre-commit.com/) if you want hooks to run `busted tests` before committing:

  ```bash
  pip install pre-commit
  pre-commit install
  ```

  This repo ships a `.pre-commit-config.yaml` that runs the WorldObserver test suite; make sure `busted` is on PATH first.

---

## 3. Running tests

WorldObserver uses busted tests as primary means to unit test and smoke-tests on the workshop directory after "building".

### 3.1 WorldObserver tests (primary)

Run the WorldObserver tests from the repo root:

```bash
cd /path/to/WorldObserver
busted tests
```

This is the main headless test suite for the mod itself and should be run regularly during development.

### 3.2 Zomboid engine-simulation smoke test

Run the loader smoke test (`pz_smoke.lua`) via the helper script after deploying the mod(s) locally.

```bash
./dev/sync-mods.sh
./dev/smoke.sh
```

 This is a “lazy man’s Zomboid engine-simulation” that:
- Checks that `require("WorldObserver")`, `require("LQR")`, and `require("reactivex")` resolve correctly in the destination tree.
- Probes for issues that would only appear in the Project Zomboid Kahlua runtime (e.g. missing vanilla Lua packages or overly strict `package`/`debug` expectations).

Note:
- The smoke test runs under a normal Lua interpreter, and it injects `PZ_LUA_PATH` to approximate Zomboid’s `shared/` module search.
- This injected search path may include `?/init.lua` for compatibility with some Lua tooling, but **WorldObserver does not rely on init.lua auto-loading in the actual game** (PZ does not treat `init.lua` specially).

### 3.3 LQR tests (optional)

You can run the LQR test suite from the LQR submodule root:

```bash
cd external/LQR
busted tests/unit
```

This should pass cleanly (including the `pz_smoke_spec.lua` that simulates the Project Zomboid runtime), but you generally only need to run it when you have modified LQR itself or are debugging LQR behavior.

---

## 4. Building and syncing to Project Zomboid

WorldObserver is packaged as a standard Project Zomboid workshop mod under `Contents/`. The repo includes a helper script to keep a local workshop tree in sync during development.

### 4.1 One‑off sync

You can sync to either:
- your local **mods** folder (fast iteration), or
- a local **workshop wrapper** folder (for upload previews).

```bash
./dev/sync-mods.sh
# or:
./dev/sync-workshop.sh
```

These scripts:

- Sync only the WorldObserver mod payload (they do not bundle dependency mods).
- Write into a single mod folder at the destination (safe to use with `rsync --delete`).

### 4.2 Watch mode during development

To keep a destination up to date while you edit:

```bash
./dev/watch.sh
# or:
TARGET=workshop ./dev/watch.sh
```

The same script also sets up a file watcher:

- After the initial sync, it uses `inotifywait` to watch the repo and re‑sync when files change.
- Keep this running in a terminal while editing; restart Project Zomboid or reload mods as needed to pick up changes.

---

## 5. Running in Project Zomboid

High‑level steps:

1. Ensure your destination exists:
   - local mods: `$HOME/Zomboid/mods/WorldObserver` (via `./dev/sync-mods.sh`)
   - local workshop wrapper: `$HOME/Zomboid/Workshop/WorldObserver` (via `./dev/sync-workshop.sh`)
2. Start Project Zomboid and enable the WorldObserver mod in the Mods UI.
3. Also enable the dependency mods: `LQR` and `reactivex` (plus `StarlitLibrary` and `DoggyLibrary`).
4. Use in‑game logs and any debug helpers exposed on `WorldObserver.debug` to verify that observers and helpers behave as expected.

Refer to `docs_internal/drafts/mvp.md` and `docs_internal/vision.md` for the current intended API surface and behavior while developing new features.
