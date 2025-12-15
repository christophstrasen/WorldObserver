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
  - Specified the `SquareObservation` schema, including `squareId`, `square` (IsoSquare reference), flags like `hasBloodSplat`/`hasTrashItems`, and `observedAtTimeMS` (from `timeCalendar:getTimeInMillis()`).
  - Decided that `squareId` represents the semi-stable identity of the square (e.g. from `IsoGridSquare` ID), while `RxMeta.id` is a per-observation identifier.
  - For MVP, left content heuristics for `hasBloodSplat`/`hasTrashItems` as stubs, with richer detection explicitly deferred.

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
  - `helpers/square.lua` provides `squareHasBloodSplat` / `whereSquareNeedsCleaning` (with `squareNeedsCleaning` kept as a compatibility alias) and warnings on misuse.
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

## day7 – Runtime controller + adaptive ingest budgets (in-engine validated)

### Highlights
- **Closed the profiling loop in-engine:** `examples/smoke_squares.lua` now exercises a real “chunk-load burst” workload and gives us stable, greppable diagnostics to iterate quickly without drowning in per-item logs.
- **Runtime controller became smooth and adaptive:** We now control ingest draining with a per-window “gas pedal” (`drainMaxItems`) that ramps up under backlog pressure, backs off on CPU pressure, and *decays back toward baseline* once pressure is gone to reduce hitch risk when per-item costs change (e.g. heavier joins).
- **Reduced flapping via hysteresis:** Spike-driven degraded transitions use *consecutive spike streaks* (not isolated spikes) and we report `tickSpikeMs` + `spikeStreakMax` so the trigger is self-explaining.
- **Made diagnostics actually interpretable:** `WO.DIAG` now includes a compact `pressure=` classification and separates **instant** backlog (`currentPending`) from **window averages** (`avgPendingWin`/`avgFillWin`) so “pending=0 but avg was high” reads as “we drained it”.
- **Made diagnostics lifecycle correct:** Runtime diagnostics attach on the first subscriber and detach on the last (`handle:stop()` no longer leaves the console chattering).
- **Fixed correctness/perf foundations:** Time windows now consistently use ms, and LQR/WO improvements (interval GC behavior, cheaper metrics paths, and clearer operator logging) removed a real in-engine throughput collapse under burst load.
- **Kept dependency direction clean:** LQR remains generic; WorldObserver sets any needed headless flags from its own tests/config, never the other way around.

### Lessons
- The “right” abstraction is **mechanics vs policy**: LQR/ingest provides buffering/draining/metrics; WorldObserver owns budgets, modes, and user-facing behavior.
- Windowed telemetry is the sweet spot: it’s cheap enough to keep on, and rich enough to diagnose “ingest cost” vs “downstream query cost”.
- A safe runtime must be able to *recover* (decay + backoff), not just “push harder”; otherwise it will eventually hitch when workloads shift.

## day8 – Patchable-by-default helpers + square hydration + schema fixes

### Highlights
- Made patch seams explicit and reload-safe:
  - Standardized on “define only when nil” for mod-facing functions (helpers and key module entry points) so other mods can patch by reassigning table fields.
  - Added rationale comments next to these nil-guards so the intent is clear (preserve mod overrides and avoid clobbering on module reload via `package.loaded`, including busted and console reload workflows).
  - Added a dedicated `tests/unit/patching_spec.lua` to exercise patch seams and ensure patches affect long-lived handlers.

- Refined square helper strategy around “stable payload + optional live object”:
  - Implemented square hydration as a **stream helper** (`whereSquareHasIsoSquare`) instead of record decoration, aligning with the existing helper attachment mechanism.
  - Implemented `SquareHelpers.record.getIsoSquare` with `validateIsoSquare` + `hydrateIsoSquare` as patchable seams, using `getWorld():getCell():getGridSquare(x,y,z)` (and `getCell()` fallback) guarded by `pcall`.

- Restored and clarified corpse detection:
  - Re-introduced `SquareObservation.hasCorpse` as a materialized boolean and populated it primarily via `IsoGridSquare:getDeadBody()` at record creation time (fallback to `hasCorpse` when needed).
  - Updated square helpers to treat corpse detection as a patchable record-level predicate (`SquareHelpers.record.squareHasCorpse`) used by `whereSquareNeedsCleaning`.
  - Updated schema docs (`docs_internal/mvp.md`) and added a unit test ensuring `hasCorpse` is set when `getDeadBody()` returns a corpse.

- Tightened “patchable by default” policy in docs:
  - Added an explicit statement in `docs_internal/vision.md` and `.aicontext/context.md` that helper sets are patchable by default and should be defined behind nil-guards.

- Debuggability + smoke test ergonomics improvements:
  - Added `WorldObserver.debug.printObservation(observation, opts)` for compact, labeled observation printing (including join shapes) and updated `examples/smoke_squares.lua` to use it.
  - Improved `WO.DIAG` log readability by renaming `rate15(in/out /s)` to `rate15(in/out per sec)`.
  - Extended the squares smoke to support floor highlighting for:
    - squares that pass `whereSquareNeedsCleaning()`; and
    - all squares emitted by the probe lane (`source="probe"`) so the probe’s scan area is visible even when filters suppress output.
  - Added highlight TTL cleanup and an in-engine `OnTick` refresher to keep highlights visible, plus rate-limited stats logs explaining when highlight calls are no-ops (missing `floor`, missing highlight setters, etc.).

- Probe diagnostics to explain “why no YUK?”:
  - Logged the probe center square coordinates each tick (`[probe] center square ...`).
  - Logged per-probe summary counts (`emitted` + `flaggedCleaning`) to distinguish “probe ran but nothing matched” from “probe didn’t run”.
  - Switched probe player discovery to prefer `getPlayer()` and fall back to indexed players, to better match the common single-player console workflow.

- Made corpse detection more resilient:
  - Updated `detectCorpse` to fall back to other checks when `getDeadBody()` returns `nil`, and to consider `getDeadBodys().size()` when available.

### Lessons
- For modder ergonomics, patch seams should be **obvious** (public table fields) and **stable** (not hidden behind locals or overwritten on reload).
- “Convenience APIs” belong where they’re already discovered: for WorldObserver that’s the stream helper surface, not ad-hoc record decoration.
- Materializing a few “high-value” booleans (like `hasCorpse`) at fact time keeps helpers fast and predictable, while hydration remains available for advanced cases.
- LQR query execution matters for ergonomics: `where` predicates (and thus helper filters) run against LQR’s row-view *before* any `selectSchemas` renames, so “helper field naming” needs to match that reality or we need a dedicated post-selection filter hook.

### Next steps
- Document a small, explicit list of “supported patch seams” per module (facts, observations, helper sets) so modders know what to rely on long-term.
- Consider whether to expose an always-available “built-in/original” reference for key patch seams (for modders who want to wrap the true base implementation rather than whatever is currently installed).
- Decide how to present (and debug) “why didn’t my helper fire?”:
  - Buffer replacement (`latestByKey`) and `distinct()` can suppress emissions even when the probe “saw” a condition; we should surface this more directly (optional debug stream / counter snapshots).
