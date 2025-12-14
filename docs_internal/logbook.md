# WorldObserver Logbook

## day1 – Setup & dependencies

### Highlights
- Added `AGENTS.md` with repo-wide agent priorities, safety rules, and testing expectations.
- Rebuilt `.aicontext/context.md` to generic guidance and documented the `external/LQR` submodule (full checkout) plus Zomboid packaging needs.
- Integrated `external/LQR` (upstream https://github.com/christophstrasen/LQR); decided to ship its `LQR/` Lua folder inside `Contents/mods/WorldScanner/42/media/lua/shared/LQR/` since `package.path` cannot be tweaked at runtime.
- Updated `watch-workshop-sync.sh` to exclude `external/` from the main rsync and add a second rsync that mirrors only `*.lua` from `external/LQR/LQR/` into the shipped mod path.

### Next steps
- Script a sync/copy step that mirrors `external/LQR/LQR` into the mod tree while stripping git metadata.
- Capture WorldObserver-specific coding standards and runtime notes in `.aicontext/` and docs as they emerge.

## day2 – Vision and API foundations

### Highlights
- Refined the conceptual model in `docs_internal/vision.md`:
  - Defined `Fact`, `Observation`, `ObservationStream`, `Situation`, and `Action`, plus how Facts are implemented via Event Listeners and Active Probes, and Observations via Base/Derived ObservationStreams.
  - Clarified that Situations are a semantic layer (“when it matters”) built on ObservationStreams, not a separate implementation layer (yet).
  - Added “Fact strategies” to capture that WorldObserver owns fact generation by combining engine events and probes to balance freshness, completeness, and performance.

- Cleaned up and aligned the vision narrative:
  - Replaced outdated “observer” terminology with the new core concepts.
  - Added a “Before” story for how mods observe the world today, with LoC/complexity/risk estimates per step.

- Created `docs_internal/api_proposal.md` scaffold and first decisions:
  - ObservationStreams are exposed as `WorldObserver.observations.<name>()`.
  - New ObservationStreams are registered via a small config: `build = …` plus `enabled_helpers = { square = "SquareObs", zombie = "ZombieObs", … }`.
  - Helper sets (square/zombie/spatial/time/etc.) are thin, reusable sugar attached based on `enabled_helpers`, assuming certain fields in the observation records; internal use of LQR join/group/distinct windows is hidden behind semantic helpers.
  - WorldObserver owns “fact plans” (event + probe strategies) per element type, with strategy selection as an advanced config knob, and never implicitly de‑duplicates observations.

- Sketched and refined concrete use cases in API terms:
  - Squares with blood near the player:
    - `WorldObserver.observations.squares():distinct("square", 10):nearIsoObject(playerIsoObject, 20):squareHasBloodSplat():subscribe(...)`
    - Shows helpers as reducers only, explicit “once per square within N seconds” via a dimension‑aware `distinct`, and spatial filtering on a live `IsoObject`.
  - Chef zombie in a kitchen with ambient sound:
    - `WorldObserver.observations.roomZombies():roomIsKitchen():zombieHasChefOutfit():subscribe(...)`
    - Demonstrates multi‑dimension ObservationStreams (rooms + zombies) and entity‑prefixed helpers (`roomIs*`, `zombieHas*`).
  - Vehicles under attack (advanced custom ObservationStream):
    - Mod‑facing: `WorldObserver.observations.vehiclesUnderAttack():withConfig({ minZombies = 3 }):filter(function(observation) return (observation.vehicle.weightKg or 0) <= 1200 end):subscribe(...)`
    - Internal: custom `build(opts)` using LQR joins + a 1‑second group window + `having`, reading `minZombies` from `opts`, with `enabled_helpers = { vehicle = "VehicleObs" }`.
  - Clarified that `subscribe` callbacks see a single `observation` table (one field per world type, e.g. `observation.square`, `observation.room`, `observation.zombie`, `observation.vehicle`) and added an advanced `filter(function(observation) ...)` escape hatch that mirrors lua‑reactivex `filter` on this table shape.
  - Added namespacing and configuration rules for helper sets (`WorldObserver.helpers.<type>` and `enabled_helpers` with `true` vs `"<fieldName>"`), documented `getLQR()` as an advanced escape hatch, and sketched debugging/logging guidance that reuses LQR’s logger plus future `describeFacts` / `describeStream` helpers and potential visual highlighting.
  - Introduced `docs_internal/fact_layer.md` to design the fact layer in detail: per‑type fact plans (events + probes), strategies (`"balanced"`, `"gentle"`, `"intense"`), a budgeted scheduler for throttling, and how Facts feed base ObservationStreams. Added an internal pattern for LuaEvent‑backed facts (e.g. room alarm status) and clarified that LuaEvents are opt‑in sources, while core world types still rely on fact plans.

### Next steps
- Flesh out additional use cases (e.g. rooms with zombies, safehouse compromise) to pressure‑test ObservationStreams and Situation helpers.
- Design and iterate on the internal fact source API (Event Listener / Active Probe builders and per‑type strategies/plans) to support the agreed surface behavior and prepare an initial implementation for `squares`.
- Iterate on Situation and Actions APIs once a couple of ObservationStream patterns feel solid.

## day3 – MVP plan and schema details

### Highlights
- Drafted a focused MVP implementation plan in `docs_internal/mvp.md`:
  - Scoped MVP to a single, high-quality vertical slice for **squares only** (facts + `observations.squares()` + minimal helpers).
  - Defined a concrete module layout under `WorldObserver/` (`config.lua`, `facts/registry.lua`, `facts/squares.lua`, `observations/core.lua`, `observations/squares.lua`, `helpers/square.lua`, `debug.lua`) with `WorldObserver.lua` as the single public entry point.
  - Captured must-nots and guardrails (no Situation/Action API yet, no GUI/overlays, no auto-tuning, no persistence, no multiplayer guarantees, no extra config knobs without prior agreement, no backwards-compat shims).

- Refined observation naming and row shapes:
  - Standardized on `observation` (singular) as the callback parameter for stream emissions (`observation.square`, `observation.room`, etc.).
  - Introduced a generic `Observation` row type (per-emission table) instead of `SquareObservationEmission`, keeping “Observation” as the primary concept.
  - Clarified in `api_proposal.md` that core schemas (e.g. `SquareObservation`) are structured and documented, while custom schemas are “opaque but honest” and only constrained where they opt into helper sets or debug tooling.

- Defined `SquareObservation` and time handling:
  - Specified the `SquareObservation` schema, including `squareId`, `square` (IsoSquare reference), flags like `hasBloodSplat`/`hasCorpse`/`hasTrashItems`, and `observedAtTimeMS` (from `timeCalendar:getTimeInMillis()`).
  - Decided that `squareId` represents the semi-stable identity of the square (e.g. from `IsoGridSquare` ID), while `RxMeta.id` is a per-observation identifier.
  - For MVP, left content heuristics for `hasBloodSplat`/`hasCorpse`/`hasTrashItems` as stubs, with richer detection explicitly deferred.

- Integrated event time and observation IDs with LQR:
  - Agreed not to patch LQR ad-hoc but to extend `LQR.Schema.wrap` with a clean option to populate `RxMeta.sourceTime` from a payload field (e.g. `sourceTimeField = "observedAtTimeMS"`) and to allow a custom `idSelector`.
  - Decided that WorldObserver fact sources will:
    - stamp `observedAtTimeMS` in the fact layer when creating a `SquareObservation`, and
    - call `Schema.wrap("SquareObservation", observable, { idSelector = nextObservationId, sourceTimeField = "observedAtTimeMS" })` so LQR sees a monotonic per-observation `RxMeta.id` and a numeric `RxMeta.sourceTime`.
  - Documented these decisions in both `mvp.md` and `api_proposal.md`, including implementation notes about separating domain IDs from LQR metadata.

- Added an advanced helper for custom schemas:
  - Planned and documented a public `WorldObserver.nextObservationId()` helper that returns a monotonically increasing integer unique within the current Lua VM.
  - Encouraged advanced/custom streams that lack a natural stable ID to reuse `nextObservationId` as `idSelector` when calling `LQR.Schema.wrap`, so they inherit the same per-observation ID guarantees used by WorldObserver’s own facts.

- Clarified fact-layer probe behavior and single-player focus:
  - Captured the `nearPlayers_closeRing` probe sketch for squares and noted that `ctx.players:nearby()` is future-proofing; in the Build 42 MVP it effectively yields at most one player due to single-player / server-side focus.

- Tightened naming and documentation consistency:
  - Switched consistently to `ObservationStream` (singular) as the type name, with “ObservationStreams” used only in prose.
  - Simplified EmmyLua class names for the `WorldObserver` entry point (`Observations`, `Config`, `Debug`) to keep annotations readable.
  - Fixed minor typos and aligned `mvp.md` and `api_proposal.md` around shared concepts (observation row shape, time stamping, ID strategy).

### Next steps
- Implement the MVP module skeletons (`WorldObserver.lua`, `config.lua`, `facts/registry.lua`, `facts/squares.lua`, `observations/core.lua`, `observations/squares.lua`, `helpers/square.lua`, `debug.lua`) to match the agreed layouts and contracts.
- Extend `LQR.Schema.wrap` with `sourceTimeField` / `sourceTimeSelector` and validate that time-based windows behave correctly against `observedAtTimeMS`.
- Start adding engine-independent Busted tests for `facts.squares`, `observations.squares()`, and the first square helpers, following the patterns sketched in `mvp.md`.

## day4 – MVP skeleton implemented (untested in-game)

### Highlights
- Implemented the initial WorldObserver module tree and wiring:
  - `WorldObserver.lua` now loads config, registers square facts/observations, wires helper sets, and integrates LuaEvent error reporting.
  - `config.lua` provides defaults/validation (squares strategy).
  - `facts/registry.lua` manages fact streams with lazy start/stop and subscriber ref-counting; validates start/stop hooks.
  - `facts/squares.lua` emits `SquareObservation` records from `OnLoadGridsquare` + near-player probe with basic detection stubs and guardrails.
  - `observations/core.lua` defines ObservationStream, helper wiring, fact dependency tracking, and subscription-driven fact lifecycle hooks.
  - `observations/squares.lua` wraps square facts into `observation.square` with schema/id/time stamping.
  - `helpers/square.lua` provides `squareHasBloodSplat` / `squareNeedsCleaning` with warnings on misuse.
  - `debug.lua` stubs describeFacts/describeStream logging hooks.
- Extended LQR’s `Schema.wrap` to honor `sourceTimeField`/`sourceTimeSelector` and `idSelector`, and preserved RxMeta ids through schema renames.
- Added unit tests:
  - WorldObserver squares stream shape/distinct/helpers and fact subscriber ref-count.
  - LQR schema/RxMeta shape tests for sourceTime/idSelector and RxMeta preservation on schema rename.

### Status
- Code is in place for the squares MVP slice with subscription-aware fact lifecycle and basic guards/warnings.
- Untested in-game; only headless busted tests have run (expect warnings about missing game Events in that environment).

## day5 – Runtime shims, smoke tests, and PZ quirks

### Highlights
- **Require + packaging model**
  - Reworked how LQR and lua-reactivex are discovered so they behave well in both vanilla Lua and the Project Zomboid Kahlua runtime.
  - Introduced a flattened `reactivex` entrypoint (`external/LQR/reactivex.lua`) that prefers the sibling `external/lua-reactivex` checkout, only falling back to the bundled submodule when needed, and installs lightweight searchers so `require("reactivex/...")` works even when `package.path` / `searchers` are locked down.
  - Extended the LQR-side shim (`external/LQR/LQR/reactivex.lua`) to force-load operators, expose a predictable `scheduler` helper, and keep the vendored lua-reactivex sources untouched.
  - Tightened `watch-workshop-sync.sh` so the workshop build ships only runtime Lua from LQR and lua-reactivex (no docs, tests, rockspecs) and still resolves `WorldObserver`, `LQR`, and `reactivex` reliably in the mod path.

- **IO and logging hardening for Kahlua**
  - Guarded all runtime `io` usage in LQR: the logger (`LQR/util/log.lua`) and join debug path now fall back to `print` when `io.stderr` is missing, and sanitize colons in messages to avoid PZ’s log rendering quirks.
  - Updated `lua-reactivex`’s `Observable.fromFileByLine` to short-circuit with a clear error when `io.open` / `io.lines` are unavailable instead of exploding at runtime.

- **Stronger smoke tests**
  - Upgraded the root `pz_smoke.lua` to probe additional host shapes: minimal/locked `package`, `io`-nil, and `os`-nil, while exercising a small reactivex pipeline and a minimal LQR query instead of just `require` checks.
  - Switched the LQR pipeline check to use `LQR.observableFromTable("SmokeRow", rows)` plus a `Query.where` predicate over the row-view (`row.SmokeRow.n`), matching how real queries see data.
  - Improved error reporting so smoke failures show the loaded modules and actual pipeline behavior (row counts or the precise query error), which made diagnosing the “0 rows” issue straightforward.
  - Kept LQR’s own `pz_smoke_spec.lua` wired to the CLI script so the same constraints are covered under busted without needing a running game.

### Lessons
- Treating lua-reactivex as a standalone, top-level submodule (`external/lua-reactivex`) and letting shims *prefer* it while *tolerating* an embedded copy keeps LQR focused on query logic while centralizing reactive infrastructure.
- Relying on `loadfile` + explicit searchers for `reactivex/...` is more robust in Kahlua than trying to tweak `package.path`, which may be missing or heavily sandboxed.
- A dedicated workshop smoke test (`pz_smoke.lua`) plus a tiny end-to-end LQR pipeline catches “works in busted, fails in-game” bugs early: missing shims, miswired requires, `io` assumptions, and subtle schema/row-view mismatches.

## day6 – LQR/ingest integrated into WorldObserver (squares slice ready for in-engine testing)

### Highlights
- Integrated `LQR/ingest` as the new “admission control” boundary for WorldObserver facts:
  - Facts now flow **ingest → buffer → drain** so bursty engine callbacks don’t immediately execute downstream LQR queries.
  - Implemented a global ingest scheduler drained on `Events.OnTick`, with a small default budget (`maxItemsPerTick=10`) and round-robin fairness across buffers of equal priority.
- Migrated the `squares` fact type to ingest:
  - `Events.LoadGridsquare` and an ad-hoc `Events.EveryOneMinute` probe now call `ctx.ingest(record)` instead of pushing directly into the Rx subject.
  - Square records are now lightweight (ids/coords/flags/timestamp/source) and do not buffer `IsoGridSquare` references.
  - Introduced lane bias: `"probe"` work drains ahead of `"event"` work, based on the observation that chunk-load events can be large and include far-edge squares.
- Improved in-engine diagnostics:
  - Added debug helpers to print ingest buffer and scheduler metrics (`describeFactsMetrics`, `describeIngestScheduler`).
  - Updated `examples/smoke_squares.lua` to print a metrics snapshot after subscribing and emit a heartbeat once per minute (received count + ingest stats) to validate draining behavior.

### Lessons
- Integrating ingest at the fact boundary makes backpressure explicit and observable; we can now reason about “pending backlog” vs “drain throughput” instead of guessing from frame drops.
- It’s easy to accidentally “disable draining” by mis-wiring config flow; ensuring the registry sees the full config (facts + ingest scheduler settings) is essential.
- Keeping buffered records lightweight (no live game objects) reduces risk and makes it easier to reason about correctness under backlog.

### Next steps
- Run in-engine `examples/smoke_squares.lua` and tune default budgets/caps based on real load patterns.
- Add the next fact type (likely `zombies`) and attach it to the same global scheduler to validate cross-type fairness in practice.
- Decide how much of the ad-hoc probe wiring should be generalized into a shared “probe scheduling” abstraction.

## day7 – In-engine profiling loop: throughput, distinct windows, and less noisy logs

### Highlights
- **Added practical runtime diagnostics for ingest draining:** Introduced periodic “tick window” summaries (drain time vs. emit/subscriber time + GC footprint) so we can distinguish “ingest overhead” from “downstream query cost” without spamming per-item logs.
- **Fixed time-window correctness in WorldObserver distinct:** Aligned `observations.core:distinct(dimension, seconds)` with the ms-based `RxMeta.sourceTime` convention by using millisecond offsets and a millisecond `currentFn`, preventing distinct time windows from behaving unpredictably in-engine.
- **Reduced log volume and improved readability:** Moved per-record query filter logging (`where`) to debug-only and reduced squares ingest progress logs to every 100 records to keep info-level output usable during real gameplay testing.
- **Chased down real-world performance cliffs:** When chunk-load bursts pushed thousands of unique squares through a short distinct window, we saw throughput collapse. The fix landed in LQR (order-based interval GC + optional batching) and directly improved the in-engine smoke test behavior.
- **Made ingest observability cheaper and clearer:** Renamed the user-facing diagnostics tag to `WO.DIAG`, expanded the metrics line to include `load/throughput/ingestRate` for `1/5/15`, and switched fact metrics snapshots to use LQR’s light metrics in hot paths to avoid accidental O(n) work while profiling.
- **Kept dependency direction clean:** Ensured LQR remains independent of WorldObserver (no WorldObserver flags referenced inside LQR). WorldObserver tests now set `_G.LQR_HEADLESS = true` explicitly so headless runs stay quiet without leaking domain concerns into the library.
- **(Untested in-engine) Started the WorldObserver “runtime controller” foundation:** Implemented the first pass of a host-side policy layer that can observe WO’s own CPU cost and ingest pressure, then clamp budgets and broadcast state to consumers:
  - A runtime controller scaffold (`WorldObserver/runtime.lua`) selects clocks, tracks per-window signals, and transitions between modes (currently `normal` ↔ `degraded`, plus `emergency` via manual reset).
  - WorldObserver now emits LuaEvents on transitions (`WorldObserverRuntimeStatusChanged`) and periodic snapshots (`WorldObserverRuntimeStatusReport`) so downstream mods can react without polling.
  - Tick cost measurement now counts both **drain work** (OnTick) and **probe work** (EveryOneMinute) towards the same budgets, to avoid “free” background work that can cause stutter.
  - The controller reacts (v1) to sustained over-budget tick cost, spikes, rising ingest drops, and rising backlog, and clamps the global drain budget when degraded.
  - Added an emergency reset hook that clears all ingest buffers and resets metrics so WO can recover from runaway load without stopping the game.
  - Added targeted unit tests to validate transitions, periodic reports, ingest-clear behavior, and ingest-pressure-triggered degrade/recover. This is still not validated inside the real engine event loop yet.

### Lessons
- Real-time performance debugging needs “coarse, periodic” telemetry, not per-item prints: we want to answer “where is the time going” first, then drill down.
- Time windows only make sense when the “clock” and the record timestamps use the same units and are monotonic enough; mixing seconds and milliseconds silently creates pathological caching behavior.
- The in-engine smoke test (`examples/smoke_squares.lua`) is already doing its job: it exposed performance characteristics (burst load + windowed operators) that are invisible in small, deterministic unit tests.
- It’s useful to separate **mechanics** (LQR/ingest buffering/draining, metrics/advice) from **policy** (WorldObserver budgets, modes, emergency reset): the split makes it easier to keep dependencies clean and to reason about user-facing guarantees.
