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

Each sync/build run via `watch-workshop-sync.sh` automatically executes `pz_smoke.lua` against the synced workshop directory when `lua` is available.

```bash
./watch-workshop-sync.sh   # or re-run while developing
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

You can run the sync script once to push the current tree into your local workshop directory:

```bash
./watch-workshop-sync.sh
```

The script:

- Copies the WorldObserver mod tree into `$HOME/Zomboid/Workshop/WorldObserver` (ensure `$HOME/Zomboid/Workshop` exists first).
- Excludes heavyweight/dev folders (including `external/`, `docs/`, `tests/`).
- Mirrors only the Lua payload from `external/LQR/LQR/` into `Contents/mods/WorldObserver/42/media/lua/shared/LQR/`.
- Copies only the runtime Lua parts of lua‑reactivex from `external/lua-reactivex` (specifically `reactivex.lua`, `reactivex/*.lua`, and `operators.lua`) into `Contents/mods/WorldObserver/42/media/lua/shared/` – docs, examples, rockspecs, and tests are not shipped.
- Drops shims so `require("WorldObserver")`, `require("LQR")`, and `require("reactivex")` resolve inside the game.
- Runs the `pz_smoke.lua` loader smoke test against the destination tree when `lua` is available.

### 4.2 Watch mode during development

The same script also sets up a file watcher:

- After the initial sync, it uses `inotifywait` to watch the repo and re‑sync when files change.
- Keep this running in a terminal while editing; restart Project Zomboid or reload mods as needed to pick up changes.

---

## 5. Running in Project Zomboid

High‑level steps:

1. Ensure the workshop destination exists (the sync script will create/populate `$HOME/Zomboid/Workshop/WorldObserver`).
2. Start Project Zomboid and enable the WorldObserver mod in the Mods UI.
3. For development, also enable the LQR/lua‑reactivex dependency mods if you later split them into separate workshop entries; in the current layout they are shipped as part of WorldObserver’s Lua payload.
4. Use in‑game logs and any debug helpers exposed on `WorldObserver.debug` to verify that observers and helpers behave as expected.

Refer to `docs_internal/drafts/mvp.md` and `docs_internal/vision.md` for the current intended API surface and behavior while developing new features.
