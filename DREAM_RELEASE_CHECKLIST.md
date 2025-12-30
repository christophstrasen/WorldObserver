# DREAM Mod Family — Release & Workflow Checklist

This checklist describes how to ship and co-develop the **5-mod DREAM family**: 

- WorldObserver (library mod)
- PromiseKeeper (library mod)
- LQR (library mod)
- lua-reactivex (library mod)
- DREAM (meta-mod + optional examples/education)

It’s written to satisfy these constraints:
- Contributors usually clone **one** repo and can still run/deploy locally.
- A fully local “build everything from source” path always exists (for maintainers/offline).

## Progress (this workspace)

- [x] Decisions locked (IDs vs display names, dependency format, deploy paths)
- [x] WorldObserver standalone deploy scripts (`dev/sync-*`, `dev/watch.sh`, `dev/smoke.sh`) + docs updated
- [x] PromiseKeeper standalone deploy scripts (`external/PromiseKeeper/dev/*`) + docs/metadata updated
- [x] Legacy combined watchers removed; maintainer one-terminal watcher added (`dev/watch-all.sh`)
- [x] SVG→PNG asset pipeline added across the mod family (requires `inkscape`):
  - WorldObserver: `dev/build-assets.sh`
  - PromiseKeeper: `external/PromiseKeeper/dev/build-assets.sh`
  - reactivex: `pz-reactivex/dev/build-assets.sh`
  - LQR: `pz-lqr/dev/build-assets.sh`
  - DREAM: `pz-dream/dev/build-assets.sh`
- [x] Local `reactivex` adapter repo scaffolded at `/home/cornholio/projects/pz-reactivex`
- [x] Local `LQR` adapter repo scaffolded at `/home/cornholio/projects/pz-lqr`
- [x] Local `DREAM` meta-mod repo scaffolded at `/home/cornholio/projects/pz-dream`
- [x] GitHub repos created + initial pushes done:
  - `https://github.com/christophstrasen/pz-reactivex`
  - `https://github.com/christophstrasen/pz-lqr`
  - `https://github.com/christophstrasen/pz-dream`
- [ ] Publish all 5 Workshop items + fill in Workshop IDs
- [ ] (Optional) Create `DREAM-Workspace` repo (multi-repo convenience)

Next (human steps):
- Create 3 GitHub repos (repo names can be e.g. `pz-lqr`, `pz-reactivex`, `pz-dream`) and add them as remotes.
- Make initial commits and push.
- Create Workshop items for each mod and set “Required Items”:
  - `WorldObserver [42SP]` requires: `LQR [42]`, `reactivex [42]`, `PromiseKeeper [42SP]`, plus `/StarlitLibrary` and `/DoggyLibrary` as applicable
  - `LQR [42]` requires: `reactivex [42]`
  - `DREAM — ... [42SP]` requires: all of them

## 0) Open Questions (resolved)

Your answers:
1. You have not published any of the 5 mods yet, so you’re open to any ID scheme.
2. New naming style: `WorldObserver [42SP]` (and workshop name == in-game mod name).
3. Confirmed deploy defaults:
   - `PZ_MODS_DIR` default: `$HOME/Zomboid/mods`
   - `PZ_WORKSHOP_DIR` default: `$HOME/Zomboid/Workshop`
4. DREAM includes examples (Option A).

Resolved decisions:
- Canonical mod IDs: `WorldObserver`, `PromiseKeeper`, `LQR`, `reactivex`, `DREAM`
- lua-reactivex mod ID will be `reactivex`
- `\StarlitLibrary` and `\DoggyLibrary` are required for **WorldObserver** and **PromiseKeeper**
- `mod.info` dependency format: `loadModAfer=\ModId` (comma-separated for multiple)

## 1) Final IDs & Names (confirmed)

Important distinction (prevents breakage):
- `id=` in `mod.info` is the **internal Mod ID** (used for dependencies and folder names). Keep it ASCII, no spaces/brackets.
- `name=` in `mod.info` and `title=` in `workshop.txt` are the **display names** (what players see). These can include `[42SP]` / `[42]`.

Note: Lua `require("LQR")` / `require("reactivex")` is determined by shipped Lua file paths (e.g. `LQR.lua`, `reactivex.lua`), not by the Mod ID.

- WorldObserver
  - Mod ID: `WorldObserver`
  - Name/title: `WorldObserver [42SP]`
- PromiseKeeper
  - Mod ID: `PromiseKeeper`
  - Name/title: `PromiseKeeper [42SP]`
- LQR
  - Mod ID: `LQR`
  - Name/title: `LQR [42]`
- lua-reactivex
  - Mod ID: `reactivex`
  - Name/title: `reactivex [42]`
- DREAM (meta-mod)
  - Mod ID: `DREAM`
  - Name/title: `DREAM — Declarative REactive Authoring Modules [42SP]`

If you decide you *do* want versioned internal IDs to avoid collisions, use something like `WorldObserver_42SP` / `LQR_42` (underscores), not bracketed IDs with spaces, and update all `Contents/mods/<id>/...` paths + `loadModAfer=\...` references accordingly.

## 2) Repo Strategy (so “clone one repo” works)

### 2.1 Standalone repos (what contributors clone)

HUMAN:
- You will have **one git repo per published mod**:
  - `WorldObserver` (already exists)
  - `PromiseKeeper` (already exists; currently a submodule here)
  - `LQR` mod repo (new “adapter mod” repo; not the upstream `christophstrasen/LQR`)
  - `reactivex` mod repo (new “adapter mod” repo; not the upstream `christophstrasen/lua-reactivex`)
  - `DREAM` (new meta-mod repo)

AI:
- I can generate the scaffolds + scripts for each repo once you create/point me at them (or once they exist in this workspace).

HUMAN (naming note):
- Git repo name can differ from mod ID; to avoid confusion with upstream, consider repo names like `pz-lqr` and `pz-lua-reactivex` (while keeping mod IDs exactly `LQR` and `reactivex`).

### 2.2 Upstream code stays upstream (important)

HUMAN:
- Keep `christophstrasen/LQR` and `christophstrasen/lua-reactivex` as upstream sources.
- Publish **adapter mod repos** that embed upstream as a submodule (or pinned vendor snapshot).

Why:
- Keeps upstream clean.
- Lets the mod repos contain `mod.info`, Workshop assets, deploy scripts, and docs without forcing those into upstream libraries.

## 3) Dependency Graph (runtime requirements)

Target dependency direction:

- `reactivex` (no dependencies)
- `LQR` → depends on `reactivex` (because `LQR.lua` does `require("reactivex")`)
- `WorldObserver` → depends on `LQR` and `reactivex`
- `PromiseKeeper` → (currently appears independent; we’ll verify in-code)
- `DREAM` → depends on all of the above

Decision:
- WorldObserver declares both `\reactivex` and `\LQR` (in addition to `\StarlitLibrary` and `\DoggyLibrary`).

Important note:
- Canonical `mod.info` dependency key for this family: `loadModAfer=...` (per your working example).
- Dependency IDs in `loadModAfer` are written with a leading backslash, e.g. `\StarlitLibrary`.

Template:
```
name=<Mod Name> [42SP]
id=<ModId>
description=<...>
versionMin=42.0
poster=poster.png
icon=icon_64.png
authors=Karmachameleon
version=0.1
loadModAfer=\StarlitLibrary,\DoggyLibrary
```

AI:
- Done for WorldObserver + PromiseKeeper in this workspace. Once the `reactivex`, `LQR`, and `DREAM` repos exist, apply the same format there too.

## 4) Standard Local Workflow (identical across all repos)

Goal: any contributor can clone one repo and run one command to deploy.

### 4.1 Standard scripts to add to every repo

AI:
- Add these scripts (same interface everywhere):
  - `dev/sync-mods.sh` → sync into `PZ_MODS_DIR/<ModId>`
  - `dev/sync-workshop.sh` → sync into `PZ_WORKSHOP_DIR/<WrapperName>/Contents/mods/<ModId>`
  - `dev/watch.sh` → file watcher that calls one of the above

Watcher choice (based on your current workflow):
- Primary: `inotifywait` (Linux/NixOS; used in the prior `watch-workshop-sync.sh`)
- Fallback: polling loop if `inotifywait` isn’t available

### 4.2 Script invariants (prevents repos “deleting each other”)

AI:
- Ensure `rsync --delete` only ever targets:
  - `.../Zomboid/mods/<ModId>` (single mod folder), OR
  - `.../Zomboid/Workshop/<Wrapper>/Contents/mods/<ModId>` (single mod folder)
- Never `--delete` the whole `.../Zomboid/mods/` or whole wrapper root.

## 5) What changes in *this* repo (WorldObserver)

The old combined sync (`watch-workshop-sync.sh`) is removed. WorldObserver sync scripts now deploy **only WorldObserver**.

Target change:
- WorldObserver’s scripts should deploy **only WorldObserver**.
- Combined “watch all” becomes an orchestration script in a separate maintainer workspace (see section 6).

AI (done in this repo):
- Added `dev/sync-mods.sh`, `dev/sync-workshop.sh`, `dev/watch.sh` (WorldObserver-only deploy).
- Added PromiseKeeper equivalents under `external/PromiseKeeper/dev/`.
- Removed the legacy combined watcher; maintainers can use `dev/watch-all.sh` to trigger multiple per-repo sync scripts from one terminal.

## 6) Fully Local “build everything” path (maintainers/offline)

You have two good options; both satisfy “always exists” without forcing contributors into it.

### Option A (recommended): a maintainer “workspace repo”

HUMAN:
- Create a separate repo (not published as a mod), e.g. `DREAM-Workspace`, containing:
  - submodules for all 5 mod repos (and upstream submodules inside the adapter repos)
  - a `.code-workspace` file opening all repos

AI (can do):
- Add `dev/watch-all.sh` that runs each repo’s `dev/watch.sh` (or `sync-*`) into the same local `PZ_MODS_DIR`.

### Option B: keep using this repo as the workspace

HUMAN:
- This keeps submodules under `external/`, but contributors won’t “clone one repo” cleanly (they’ll clone WorldObserver and inherit a bunch of unrelated repos).

AI:
- If you choose this, I can still make it safe by changing scripts so each mod sync is scoped to its own mod folder.

## 7) Adapter Mod Repo Checklists (LQR and lua-reactivex)

### 7.1 `reactivex` mod repo (new)

HUMAN:
- Create the `reactivex` mod repo (pick any repo name; mod ID stays `reactivex`).
- Add upstream `lua-reactivex` as a submodule (pinned commit).

AI (can do once repo exists here):
- Create:
  - `Contents/mods/reactivex/42/mod.info`
  - `Contents/mods/reactivex/42/media/lua/shared/reactivex.lua`
  - `Contents/mods/reactivex/42/media/lua/shared/reactivex/` (folder)
  - `Contents/mods/reactivex/42/media/lua/shared/operators.lua` (if needed for `require("reactivex/operators")`)
  - `workshop.txt`, `preview.png`, `poster.png`, `icon_64.png`
  - `dev/sync-mods.sh`, `dev/sync-workshop.sh`, `dev/watch.sh`
- Ensure the adapter only ships `.lua` payloads (no `.git`, docs, etc).

### 7.2 `LQR` mod repo (new)

HUMAN:
- Create the `LQR` mod repo (pick any repo name; mod ID stays `LQR`).
- Add upstream `LQR` as a submodule (pinned commit).

AI (can do once repo exists here):
- Create:
  - `Contents/mods/LQR/42/mod.info` (requires `reactivex`)
  - `Contents/mods/LQR/42/media/lua/shared/LQR/` (Lua-only payload)
  - `Contents/mods/LQR/42/media/lua/shared/LQR.lua` (shim entrypoint)
  - Workshop assets + standard scripts

## 8) DREAM meta-mod checklist

HUMAN:
- Create repo `DREAM` (meta-mod).

AI (can do once repo exists here):
- Create:
  - `Contents/mods/DREAM/42/mod.info` requiring:
    - `WorldObserver`
    - `PromiseKeeper`
    - `LQR`
    - `reactivex`
  - Include examples under `Contents/mods/DREAM/42/media/lua/shared/DREAM/...`
  - `docs/` content and a “Getting Started” page for players/modders

## 9) Release Checklist (per mod)

For each mod repo:

HUMAN:
- Decide the Workshop item’s visibility, tags, and description.
- Upload via PZ Workshop UI using the wrapper folder produced by `dev/sync-workshop.sh`.
- Record the Workshop ID in the repo (e.g. `WORKSHOP_IDS.md` or `workshop.txt`).

AI (can do):
- Ensure `workshop.txt` and `mod.info` are consistent (name, id, version).
- Add a `CHANGELOG.md` or `docs/release-notes.md` if you want.
- Add a “Standalone Development” section to each repo README.

## 10) Verification Checklist (before you publish)

AI (can do locally):
- Run WorldObserver tests: `busted tests` from this repo root.
- Run LQR tests (upstream): `busted tests/unit` from the LQR repo (when present).
- Run your smoke test: `pz_smoke.lua` path used by your sync workflow stays green.

HUMAN:
- Enable the mods in-game and confirm:
  - No missing `require(...)` errors
  - Load order is correct (dependency mods load before dependents)
  - The library mods don’t spam errors when used standalone
