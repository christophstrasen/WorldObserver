# Contributing to WorldObserver

WorldObserver is a shared world-sensing engine for Project Zomboid mods. Contributions are welcome, especially:
- new observations (types/scopes/targets) that fit the interest model,
- robustness improvements for Build 42
- better docs and examples for modders and contributors.

If you’re planning a larger change (new observation family, new sensor, API reshaping), please open an issue first so we can align on scope and naming.

Potentially interesting future observations and other research notes are tracked here:
- `docs_internal/research.md`

## Quick links (start here)

- Development quickstart (single repo): `development.md`
- Development workflow (setup, tests, workshop sync, smoke tests): `docs_internal/development.md`
- Architecture overview (how the pipeline is structured): `docs_internal/code_architecture.md`
- Runtime dynamics (how probes and draining adapt): `docs_internal/runtime_dynamics.md`
- Documentation principles (how we write docs): `docs_internal/wo_documentation_principles.md`
- Canonical terminology: `docs/glossary.md`

## DREAM suite

WorldObserver is one module in the DREAM family (WorldObserver, PromiseKeeper, SceneBuilder, LQR, reactivex, DREAM).

Maintainer convenience repo (multi-repo sync/watch): https://github.com/christophstrasen/DREAM-Workspace

## Project values (what we optimize for)

- **Player performance and safety first:** bounded work per tick; graceful degradation under load.
- **Cooperation across mods:** interests should merge cleanly; shared work should be reusable and fair.
- **Moddability:** stable ids, small snapshot records, record extenders, and patchable seams.
- **Code-first truth:** docs should follow the code, and tests should catch runtime gaps.

## Separation of concerns: WorldObserver vs LQR

WorldObserver contains the Project Zomboid-specific code (events, probes, interest, records). LQR is a general-purpose Lua library for queries and ingest buffering that does not depend on Zomboid.

Rules of thumb:
- WorldObserver owns interest, probes/listeners/sensors, record builders - the "game logic and engine" if you will.
- LQR owns streaming and querying in blissful ignorance of Project Zomboid.

More context: `docs_internal/code_architecture.md`


## Codestyle

- [StyLua](https://github.com/JohnnyMorganz/StyLua) defaults
- Emmylua with [Umbrella](https://pzwiki.net/wiki/Umbrella_(modding))
- No Emmylua warnings outside of `tests/unit`

## Logging

- Use the repo logging utility (tagged, level-controlled and borrowed from LQR) instead of ad-hoc `print`:
  - `local Log = require("LQR/util/log").withTag("WO.<AREA>")`
  - The default level is "warn", which is expected to not crash the Zomboid Runtime or WorldObserver itself. No warnings are expected under normal operation.
  - Developers annd other modders can adjust the log level via `Log.setLevel("info")` 
  - We prefer `debug` for per-item/per-tick logs; keep `info` quieter and reserved for regular diagnostic.
  - The other levels are 	"fatal", "error","warn","info","debug","trace",


## Testing expectations (layered)

We target both vanilla Lua 5.1 (headless tests) and the Zomboid runtime (Kahlua). Please use this stacked approach:

1) **Unit tests (required)**
- Run: `busted tests`
- Add tests under `tests/unit/` for new behavior.

2) **Built-workspace loader smoke test (recommended for require/path changes)**
- Run: `./dev/sync-workshop.sh`
- Then: `SOURCE=workshop ./dev/smoke.sh`

3) **In-engine smoke tests (recommended for new probes/listeners/visuals)**
- Smoke scripts live under `Contents/mods/WorldObserver/42/media/lua/shared/examples/`
- The “start everything” harness is `Contents/mods/WorldObserver/42/media/lua/shared/examples/smoke_console_showcase.lua`

## Benchmarking (optional, but useful for performance-sensitive changes)

If your change affects probing/draining, adds a new sensor, or changes record shapes in a way that could increase volume, please include some lightweight “before/after” evidence.

Options we already have in-repo:
- **WorldObserver runtime diagnostics** (in-engine): enable `WO.DIAG` / `WO.INGEST` logs and compare tick cost/backlog/drops.
  - Guide: `docs/guides/debugging_and_performance.md`
- **LQR benchmark suite** (in-engine): run from the PZ console to sanity-check query/ingest performance in a realistic host.
  - `Contents/mods/WorldObserver/42/media/lua/shared/examples/lqr_benchmarks.lua`
- We are currently lacking "probe side benchmarking" abilities e.g. running 1000 real squares per second through the observation pipeline

## Contributor checklist (PR-ready)

- Keep work bounded (caps + time-slicing) and run inside the registry tick window when applicable.
- Ensure every new record has a stable id suitable for compaction/dedup (derive when engine ids are unsafe in Lua).
- Prefer record extenders for new fields; avoid breaking record shapes unless necessary.
- No new warnings in the log related to WorldObserver `[WO]`
- New EmmyLua warnings outside `tests/unit`
- Updated docs for user-facing behavior changes (`docs/`).
- `busted tests` ran fine before committing (automatic if you use the pre-commit hook).

## Lean governance

- Small PRs are easiest to review.
- For breaking changes, refactors, or new public surfaces, discuss in an issue first.
- Maintainers may request changes for naming, performance, safety, or compatibility reasons.
