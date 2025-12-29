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

- Created `docs_internal/drafts/api_proposal.md` scaffold and first decisions:
  - ObservationStreams are exposed as `WorldObserver.observations:<name>()`.
  - New ObservationStreams are registered via a small config: `build = …` plus `enabled_helpers = { square = "SquareObs", zombie = "ZombieObs", … }`.
  - Helper sets (square/zombie/spatial/time/etc.) are thin, reusable sugar attached based on `enabled_helpers`, assuming certain fields in the observation records; internal use of LQR join/group/distinct windows is hidden behind semantic helpers.
  - WorldObserver owns “fact plans” (event + probe strategies) per element type, with strategy selection as an advanced config setting, and never implicitly de‑duplicates observations.

- Sketched and refined concrete use cases in API terms:
  - Squares with corpses near the player:
    - `WorldObserver.observations:squares():distinct("square", 10):nearIsoObject(playerIsoObject, 20):squareHasCorpse():subscribe(...)`
    - Shows helpers as reducers only, explicit “once per square within N seconds” via a dimension‑aware `distinct`, and spatial filtering on a live `IsoObject`.
  - Chef zombie in a kitchen with ambient sound:
    - `WorldObserver.observations:roomZombies():roomIsKitchen():zombieHasChefOutfit():subscribe(...)`
    - Demonstrates multi‑dimension ObservationStreams (rooms + zombies) and entity‑prefixed helpers (`roomIs*`, `zombieHas*`).
  - Vehicles under attack (advanced custom ObservationStream):
    - Mod‑facing: `WorldObserver.observations:vehiclesUnderAttack():withConfig({ minZombies = 3 }):filter(function(observation) return (observation.vehicle.weightKg or 0) <= 1200 end):subscribe(...)`
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
- Drafted a focused MVP implementation plan in `docs_internal/drafts/mvp.md`:
  - Scoped MVP to a single, high-quality vertical slice for **squares only** (facts + `observations.squares()` + minimal helpers).
  - Defined a concrete module layout under `WorldObserver/` (`config.lua`, `facts/registry.lua`, `facts/squares.lua`, `observations/core.lua`, `observations/squares.lua`, `helpers/square.lua`, `debug.lua`) with `WorldObserver.lua` as the single public entry point.
  - Captured must-nots and guardrails (no Situation/Action API yet, no GUI/overlays, no auto-tuning, no persistence, no multiplayer guarantees, no extra config settings without prior agreement, no backwards-compat shims).

- Refined observation naming and row shapes:
  - Standardized on `observation` (singular) as the callback parameter for stream emissions (`observation.square`, `observation.room`, etc.).
  - Introduced a generic `Observation` row type (per-emission table) instead of `SquareObservationEmission`, keeping “Observation” as the primary concept.
  - Clarified in `docs_internal/drafts/api_proposal.md` that core schemas (e.g. `SquareObservation`) are structured and documented, while custom schemas are “opaque but honest” and only constrained where they opt into helper sets or debug tooling.

- Defined `SquareObservation` and time handling:
  - Specified the `SquareObservation` schema, including `squareId`, a best-effort `IsoGridSquare` reference, flags like `hasBloodSplat`/`hasTrashItems`, and `sourceTime` (from `timeCalendar:getTimeInMillis()`).
  - Decided that `squareId` represents the semi-stable identity of the square (e.g. from `IsoGridSquare` ID), while `RxMeta.id` is a per-observation identifier.
  - For MVP, left content heuristics for `hasBloodSplat`/`hasTrashItems` as stubs, with richer detection explicitly deferred.

- Integrated event time and observation IDs with LQR:
  - Agreed not to patch LQR ad-hoc but to extend `LQR.Schema.wrap` with a clean option to populate `RxMeta.sourceTime` from a payload field (e.g. `sourceTimeField = "sourceTime"`) and to allow a custom `idSelector`.
  - Decided that WorldObserver fact sources will:
    - stamp `sourceTime` in the fact layer when creating a `SquareObservation`, and
    - call `Schema.wrap("SquareObservation", observable, { idSelector = nextObservationId, sourceTimeField = "sourceTime" })` so LQR sees a monotonic per-observation `RxMeta.id` and a numeric `RxMeta.sourceTime`.
  - Documented these decisions in both `docs_internal/drafts/mvp.md` and `docs_internal/drafts/api_proposal.md`, including implementation notes about separating domain IDs from LQR metadata.

- Added an advanced helper for custom schemas:
  - Planned and documented a public `WorldObserver.nextObservationId()` helper that returns a monotonically increasing integer unique within the current Lua VM.
  - Encouraged advanced/custom streams that lack a natural stable ID to reuse `nextObservationId` as `idSelector` when calling `LQR.Schema.wrap`, so they inherit the same per-observation ID guarantees used by WorldObserver’s own facts.

- Clarified fact-layer probe behavior and single-player focus:
- Captured the `squares_near_closeRing` probe sketch for squares and noted that `ctx.players:nearby()` is future-proofing; in the Build 42 MVP it effectively yields at most one player due to single-player / server-side focus.

- Tightened naming and documentation consistency:
  - Switched consistently to `ObservationStream` (singular) as the type name, with “ObservationStreams” used only in prose.
  - Simplified EmmyLua class names for the `WorldObserver` entry point (`Observations`, `Config`, `Debug`) to keep annotations readable.
  - Fixed minor typos and aligned `docs_internal/drafts/mvp.md` and `docs_internal/drafts/api_proposal.md` around shared concepts (observation row shape, time stamping, ID strategy).

### Next steps
- Implement the MVP module skeletons (`WorldObserver.lua`, `config.lua`, `facts/registry.lua`, `facts/squares.lua`, `observations/core.lua`, `observations/squares.lua`, `helpers/square.lua`, `debug.lua`) to match the agreed layouts and contracts.
- Extend `LQR.Schema.wrap` with `sourceTimeField` / `sourceTimeSelector` and validate that time-based windows behave correctly against `sourceTime`.
- Start adding engine-independent Busted tests for `facts.squares`, `observations.squares()`, and the first square helpers, following the patterns sketched in `docs_internal/drafts/mvp.md`.

## day4 – MVP skeleton implemented (untested in-game)

### Highlights
- Implemented the initial WorldObserver module tree and wiring:
  - `WorldObserver.lua` now loads config, registers square facts/observations, wires helper sets, and integrates LuaEvent error reporting.
  - `config.lua` provides defaults/validation (squares strategy).
  - `facts/registry.lua` manages fact streams with lazy start/stop and subscriber ref-counting; validates start/stop hooks.
  - `facts/squares.lua` emits `SquareObservation` records from `OnLoadGridsquare` + near-player probe with basic detection stubs and guardrails.
  - `observations/core.lua` defines ObservationStream, helper wiring, fact dependency tracking, and subscription-driven fact lifecycle hooks.
  - `observations/squares.lua` wraps square facts into `observation.square` with schema/id/time stamping.
  - `helpers/square.lua` provides early square helper filters (at the time including a `whereSquareNeedsCleaning` prototype; later removed in favor of composable record predicates + `stream:filter(...)`).
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
  - `Events.LoadGridsquare` and a time-sliced `Events.OnTick` probe now call `ctx.ingest(record)` instead of pushing directly into the Rx subject.
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
  - Implemented square hydration as a **stream helper** (`squareHasIsoGridSquare`) instead of record decoration, aligning with the existing helper attachment mechanism.
  - Implemented `SquareHelpers.record.getIsoGridSquare` with `validateIsoGridSquare` + `hydrateIsoGridSquare` as patchable seams, using `getWorld():getCell():getGridSquare(x,y,z)` (and `getCell()` fallback) guarded by `pcall`.

- Restored and clarified corpse detection:
  - Re-introduced `SquareObservation.hasCorpse` as a materialized boolean and populated it primarily via `IsoGridSquare:getDeadBody()` at record creation time (fallback to `hasCorpse` when needed).
  - Updated square helpers to treat corpse detection as a patchable record-level predicate (`SquareHelpers.record.squareHasCorpse`) so it can be reused in stream helpers and in mod-defined predicates.
  - Updated schema docs (`docs_internal/drafts/mvp.md`) and added a unit test ensuring `hasCorpse` is set when `getDeadBody()` returns a corpse.

- Tightened “patchable by default” policy in docs:
  - Added an explicit statement in `docs_internal/vision.md` and `.aicontext/context.md` that helper sets are patchable by default and should be defined behind nil-guards.

- Debuggability + smoke test ergonomics improvements:
  - Added `WorldObserver.debug.printObservation(observation, opts)` for compact, labeled observation printing (including join shapes) and updated `examples/smoke_squares.lua` to use it.
  - Improved `WO.DIAG` log readability by renaming `rate15(in/out /s)` to `rate15(in/out per sec)`.
  - Extended the squares smoke to support floor highlighting for:
    - squares that match the “dirty square” predicate used at the time; and
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

## day9 – Universal square highlighting + distinct debugging

### Highlights
- Added a universal, multi-square highlight utility: `WorldObserver.highlight(square, durationMs, opts)` fades alpha smoothly and disables highlighting when complete.
- Centralized highlight scheduling behind a single `OnTick` updater that attaches only while highlights are active (supports many concurrent squares with different start/durations).
- Made near-player probes visually inspectable by highlighting just-probed squares with a distinct color, and added a smoke option to run probe-only (disable `LoadGridsquare` listener) for cleaner experiments.
- Added an in-engine LQR benchmark harness (`examples/lqr_benchmarks.lua`) so we can measure query primitives under Kahlua using realistic tick pacing and a “CI-like” small run mode.
- Improved benchmark measurement fidelity by splitting “wall time across ticks” vs “work time spent inside the OnTick handler” (plus ticks used), making engine vs CLI numbers interpretable.
- Reduced in-engine noise by defaulting benchmarks to WARN-level logs and clamping the in-engine `ci=true` run sizes so they complete quickly without spamming the console.
- Improved debugging ergonomics while investigating “distinct stops emitting”:
  - Clarified that `SquareObservation-<n>` in logs is a per-emission `RxMeta.id` (not “unique squares”), and that multiple subscriptions will multiply IDs.
  - Added probe-side and ingest-side debug logs for “dirty” squares to separate “fact generation” from “stream suppression”.
  - Reduced log flood by moving LQR `Query.where` decision logging to TRACE level.

### Lessons
- In the PZ/Kahlua runtime, `#table` on tables with holes is not reliable; any queue-like structure that nils out head indices must track its own head/tail/count.
- When diagnosing “missing emissions”, separating “probe emitted” vs “ingest drained” vs “query suppressed” is the fastest way to locate the real bottleneck.
- “Engine benchmark time” must be separated into compute time vs tick/frame spacing; otherwise short pipelines look artificially slow and comparisons to CLI microbenchmarks are misleading.

### Next steps
- Expose a small diagnostic surface for `distinct()` (e.g. counters for suppressed/expired per dimension) so “why didn’t this re-emit?” is explainable without deep log spelunking.
- Extend the highlighting helper pattern so we can highlight other object types (not just floor squares) with the same lifecycle model.

## day10 – Fact interest + adaptive probes (near + vision) + refactor

### Highlights
- Introduced a mod-friendly, lease-based **fact interest** API (`WorldObserver.factInterest:declare(...)`) so mods can *declare intent* and refresh/replace it without needing to remember to “turn things off” later (leases expire automatically).
- Implemented interest merging + adaptive policy (“ladder”) for the core probe settings:
  - `staleness` (how old results may be), `radius` (spatial scope), `cooldown` (per-key emission gating).
  - Automatic degradation/recovery based on runtime pressure, plus a probe-lag signal when a sweep can’t keep up with requested staleness.
- Smoothed degradation within declared bands by inserting intermediate ladder steps (e.g. `staleness=1 -> 2 -> 4 -> 8 -> 10`) instead of binary jumps.
- Added hysteresis to avoid “lagged/recovered” flapping:
  - Lag uses an estimated sweep completion time (based on progress) rather than only elapsed time.
  - Recovery requires evidence that we can meet **desired** staleness again (not just the degraded staleness).
  - Added extra recovery hysteresis after a lag-triggered degrade, plus a more stable early-sweep lag estimator (avoid “26x lag” spikes from tiny samples).
- Added two square probe shapes for training and experimentation:
  - **Near player** (radius sweep around the player).
  - **Vision** (squares the player can currently see via `IsoGridSquare:getCanSee(playerIndex)`).
- Made probes time-sliced and stutter-resistant via a per-tick scan budget: a cursor sweeps the area over multiple ticks, tries to finish “as fast as allowed”, then idles until the next sweep is due.
- Added an auto-budget “gas pedal” for probes: when probes lag but the overall WorldObserver tick has headroom, spend more of the 4ms budget on probing (capped against drain/other work).
  - When auto-budget raises `budgetMs`, probes also scale their per-tick iteration cap (up to a hard cap) so budget isn’t left unused due to `maxPerRun`.
- Improved runtime diagnostics to show probe vs drain vs other vs total cost on one line, including tick spike maxima.
- Gated `Events.LoadGridsquare` behind explicit interest (`squares` scope=onLoad) so “smoke probe-only runs” don’t enable event ingestion unless something asked for it.
- Refactored the large `facts/squares.lua` into smaller modules (record building / geometry / probes / onLoad listener / shared interest resolver) while preserving patch seams and keeping busted tests green.
- Added the next fact family: **zombies** (`WorldObserver.observations:zombies()` emitting `observation.zombie`) with:
  - `zombies` scope=allLoaded interest (including `zRange` for vertical filtering).
  - A time-sliced `IsoCell:getZombieList()` cursor probe (budgeted per tick) and stable `ZombieObservation` record shape.
  - A smoke example (`examples/smoke_zombies.lua`) to validate leases + subscribe + filters quickly in-game.
- Added interest-driven highlighting for fact sources:
  - Mods can set `highlight = true` (default color) or an RGBA table in the interest declaration.
  - Probes apply highlight only when they actually emit (so cooldown suppresses highlights too).
  - For zombies, highlights are applied to the floor square under the zombie (zombie self-highlights get reset by engine targeting).
- Removed legacy “debug causes highlighting” paths so probe visuals are driven exclusively by mod interest (no global toggles needed).
- For zombies, prefer `IsoZombie:getCurrentSquare()` for square resolution (more stable than deriving from float coordinates), with coordinate/tile fallbacks for robustness.
- Fixed a major correctness/perf bug in the zombie probe:
  - The interest policy returns *numeric* effective settings; treating them as `{desired=...}` bands caused `staleness/cooldown/radius` to collapse to 0, leading to constant sweeps and very high load.
  - After correcting this, the probe obeys staleness and cooldown again and the load dropped as expected.
- Improved zombie record join ergonomics:
  - Added `tileX/tileY/tileZ` (integer) alongside float `x/y/z` so downstream joins can avoid fuzzy float comparisons.
- Made highlight duration look more “true to cadence”:
  - Derive highlight duration from `max(effectiveStaleness, effectiveCooldown)` (then take half for fade-out), not just staleness.

### Lessons
- “Declare interest” is a clean seam between **upstream acquisition** and **downstream observation**: it enables coordination and budgeting without entangling mod logic with runtime internals.
- Separating mechanics (cursor sweep + budgets) from policy (interest ladder + degrade/recover rules) keeps tuning safe and incremental.
- In-game console debugging needs “live settings”: reading selected debug overrides at runtime avoids needing module reloads just to change probe logging verbosity.
- Not all game objects are safe to highlight directly: zombies can overwrite highlight state every frame; highlighting the *ground object* underneath is more robust and still communicates probe coverage.
- Visual debugging should match emission semantics: highlighting only on emit avoids misleading “activity” during cooldown/distinct suppression.

### Next steps
- Add a small “probe metrics” surface (beyond logs) so modders can inspect: sweep progress, lag ratio, and current effective interest per probe type.
- Consider a future “drive-by discovery” hook at square-scan time (e.g. “while scanning squares, also sample zombies/items if there’s declared interest”) without introducing new world sweeps.
- Decide whether non-ladder settings like `zRange` should become first-class in the policy ladder (with direction-aware degrade semantics).

## day11 – Time semantics, `sourceTime` standardization, and config hygiene

### Highlights
- Standardized per-record `sourceTime` (ms) on fact records and aligned it with `sourceTime`:
  - Squares and zombies facts now emit `sourceTime` alongside `sourceTime`.
  - Observation schema wrapping stamps `RxMeta.sourceTime` from `sourceTime` (not from ad-hoc field names).
- Reduced per-query verbosity for time windows by adding a default clock override in LQR and injecting it from WorldObserver:
  - WorldObserver sets LQR’s default window `currentFn` to the same `Time.gameMillis` source used for `sourceTime` stamping.
  - LQR remains consumer-agnostic; the override is optional and re-settable.
- Did a code-quality sweep of “global config settings”:
  - Refactored `WorldObserver/config.lua` to be more DRY (explicit override allowlist + generic nested read/merge helpers).
  - Simplified `WorldObserver.lua` bootstrap to read globals via config helpers instead of inline wiring.
  - Reused config helpers for “live debug override” reads (probe logging settings) without changing the override shape.
  - Added targeted unit coverage for defaults cloning, override semantics, and runtime option derivation.

### Lessons
- A “good default” for time windows is not just `field = "sourceTime"` but also a **clock** that matches the host’s stamped units; mismatches silently produce broken windows.
- Keeping global overrides on an explicit allowlist makes the supported surface self-documenting and reduces “mystery settings” while still enabling smoke/debug workflows.

### Next steps
- Consider a tiny WorldObserver helper for time windows (e.g. “last N seconds”) to standardize `{ time, field, currentFn }` shapes across distinct/join/group usage.
- Document the supported override paths + shallow-merge semantics in one place so smoke scripts and modders don’t rely on accidental config shape.

## day12 – Helper cleanup, square hydration rename, interest opt-in, and smoke workflow hardening

### Highlights
- Removed the outdated square helper `squareHasBloodSplat` end-to-end (code, tests, docs, internal docs) to keep the surface aligned with reality.
- Renamed the square record engine handle from `IsoSquare` to `IsoGridSquare` throughout:
  - Fact record field is now `square.IsoGridSquare`.
  - Hydration helper is now `squareHasIsoGridSquare()` (stream + record helper), plus updated examples and docs.
- Made probes and listeners truly **opt-in**:
- Removed default probing behavior for `squares` (scope=near/vision) and `zombies` scope=allLoaded (no more `allowDefault=true`).
  - Ensured “no lease” clears cached effective interest state so probes don’t accidentally keep running on stale values.
- Fixed a major “why are squares highlighted?” confusion:
  - Probe highlighting is now gated by `highlight=true` on the relevant lease (not unconditional).
- Added the same `highlight=true` support to `type="squares"` scope=onLoad (event-driven) and added a unit test for it.
- Improved runtime/diagnostic clarity:
  - Updated fact startup logs to reflect both config toggles and whether interest leases are currently present (instead of implying a static “plan” with probe on/off).
- Hardened the in-game smoke workflow (for real modder usage):
  - Fixed misleading defaults and commented-out lease blocks that made smoke runs silently declare no interest.
- Simplified `examples/smoke_squares.lua` to a readable “what you see is what runs” script: declares `squares` with `scope="near"` and `scope="vision"` exactly as written, and only takes a couple of small display opts.
- Added a short note about why `squares` scope=onLoad can go quiet (events only) and when to use probe interests for continuous discovery.
- Updated user-facing docs to match the “interest is required” mental model and to explain `squares` scope=onLoad vs `squares` scope=near behavior.

### Lessons
- “No defaults” for probing is the safest principle for modder expectations: if a mod didn’t declare interest, the system should stay idle.
- Event-driven square observation (`squares` scope=onLoad) and probe-driven observation (`squares` scope=near/vision) have very different “go quiet” semantics; docs and smoke tooling must make that distinction explicit.
- Smoke scripts should be opinionated and readable; too many toggles makes it easy to accidentally test “nothing”.

### Next steps
- Consider adding a global rate limiter / backpressure strategy for `squares` scope=onLoad bursts (unique-key storms during chunk loads) to avoid ingest overload without relying only on cooldown.

## day13 – Interest surface consolidation, scope routing, and smoke showcase

### Highlights
- Consolidated the modder-facing interest surface around a stable `type/scope/target` shape:
  - Squares are now exclusively `type="squares"` with `scope="near" | "vision" | "onLoad"`.
  - Zombies are now `type="zombies"` with `scope="allLoaded"` (v1).
  - Removed remaining legacy type names from docs/tests/examples so the API surface is single-source and unambiguous.
- Moved “onLoad” from its own interest type into `squares` scope routing under the hood:
  - Probes still run per scope bucket (near/vision) with independent policy state.
  - The `Events.LoadGridsquare` listener is now gated by `type="squares"` with `scope="onLoad"` (same registry, different driver).
- Tightened interest normalization and validation:
  - `squares` scope=onLoad ignores `target`, `radius`, and `staleness` (warns outside headless).
  - `zombies` clamps unknown scopes back to `allLoaded` and ignores `target` (warns outside headless).
- Added an explicit internal contract doc for supported combinations:
  - `docs_internal/interest_combinations.md` is now the reference for what we support today and what we explicitly do not.
- Improved smoke workflows and made them more “showcase-ey”:
  - Simplified `examples/smoke_squares.lua` and `examples/smoke_zombies.lua` to only use allowed config.
  - Added `examples/smoke_console_showcase.lua` with independent `startSquares/stopSquares` and `startZombies/stopZombies` flows.
- Kept tests clean and relevant:
  - Removed headless test noise by suppressing config override warnings in headless and stubbing `Events.OnTick` where highlight fading is exercised.

### Lessons
- A single “interest shape” can still support multiple acquisition mechanisms as long as `scope` is treated as the semantic switch and we keep driver-specific settings explicit (and validated).
- Writing down the supported combination matrix (type/scope/target + setting applicability) pays off immediately: it drives code structure, tests, and doc correctness, and prevents “accidental API growth”.
- Smoke scripts are part of the public UX: making them minimal, readable, and independently controllable matters as much as the underlying probe/listener mechanics.

### Next steps
- Decide whether and how to introduce `scope="allLoaded"` for squares (loaded-cell sweep vs event stream) without blurring probe vs event semantics.
- Consider adding a small interest-validation test suite that asserts all supported combinations from `docs_internal/interest_combinations.md` remain accepted and that forbidden settings are rejected/ignored deterministically.

## day14 – Rooms facts, cell room list probing, and stable room IDs

### Highlights
- Rooms fact family: `type="rooms"` with `scope="onSeeNewRoom"` (event) and `scope="allLoaded"` (time-sliced `getCell():getRoomList()` probe); room records use `sourceTime` and stay snapshot-small.
- Fixed room identity collisions by switching to a stable string `roomId` derived from the first room square coords (`x123y456z7`); keep engine ids as best-effort metadata only.
- Added `helpers/java_list.lua` for defensive Java-backed list access in Kahlua (including “empty but non-indexable” values that stringify like `[]`).
- Shared square-sweep “internal sensor” pattern:
  - `facts/sensors/square_sweep.lua` time-slices square scanning once and fans out to collectors for `squares`, `items`, and `deadBodies` (no duplicate sweeps).
  - Probe log labels use `-` (display) instead of the earlier `COLON` encoding.
- New ground-entity fact families on the shared sweep:
  - `type="items"` and `type="deadBodies"` with `scope="playerSquare" | "near" | "vision"`.
  - Items emit ground items plus direct container contents (depth=1) with a guardrail cap `facts.items.record.maxContainerItemsPerSquare` (default 200).
  - Dead bodies use `IsoDeadBody:getObjectID()` identity (e.g. `DeadBody-1` observed in-engine).
- Reduced duplication: introduced `facts/ground_entities.lua` (shared collector scaffolding) and `facts/targets.lua` (shared player target resolution); centralized highlight parsing via `Highlight.resolveColorAlpha(...)`.
- Step 8 guardrails: square sweep now tracks cheap per-tick counters + optional collector fan-out logging (`logCollectorStats` / `logCollectorStatsEveryMs`) and honors live overrides under the active fact type.
- Moddability + docs + tests:
  - Record extender hooks now cover squares/rooms/zombies/items/deadBodies; documented in `docs/guides/extending_records.md`.
  - Added/updated observation docs (`docs/observations/items.md`, `docs/observations/dead_bodies.md`) and updated `docs/guides/debugging_and_performance.md`.
  - Follow-up hardening + UX: fixed square-sweep collector gating (no cross-type emits without interest) and updated smoke scripts (`smoke_console_showcase` starts squares near+vision; `smoke_squares` fixed + re-enabled vision interest).
  - Hardened `helpers/java_list.lua` against `tostring(...)` throwing (engine edge case) and added a contract test asserting all `interest/definitions.lua` types are wired as facts + observations.
  - Headless tests pass (`busted tests`: 99 successes).
- Contributor docs polish:
  - Added `docs_internal/code_architecture.md` (architecture overview + guardrails) and `docs_internal/runtime_dynamics.md` (how probes/drain adapt at runtime).
  - Added root `contributing.md` (lean governance, testing + smoke + benchmarks, logging conventions, links to research backlog).
  - Updated glossary + architecture terms to match code (fact sources, sensors, collectors) and clarified `docs_internal/development.md`.
- IDE ergonomics (EmmyLua):
  - Fixed “undefined param” warnings by aligning `---@param` blocks with patch-seam function definitions.
  - Added targeted `---@diagnostic disable-next-line: undefined-field` for `package.loaded` access (avoid noisy false positives).

### Lessons
- Never use large engine IDs as Lua numeric keys; prefer stable, domain-derived string keys for identity.
- Kahlua/Java interop needs guardrails (non-indexable “lists”, presence checks, and method lookups can all be sharp edges).
- A shared sweep sensor is “the eyes”: once it exists, new near/vision facts are mostly collectors + records, and performance tuning becomes measurable via counters.

### Next steps
- Optional: add debug reporting for rooms where `getSquares()` is unavailable (`[]`) so highlight/key failures are diagnosable.
- Confirm the “first square” rule is stable; upgrade to “minimum square” if ordering ever proves non-deterministic.
- Keep ground-entity streams observation-only unless real mod use-cases require explicit removal/expiry events.
- Consider adding a simple contributor “IDE checks” note (EmmyLua + Luacheck expectations) to reduce churn.

## day15 – Sprite observations, smoke UX, naming consistency, and highlight semantics

### Highlights
- Added the `sprites` observation family with two acquisition paths:
  - square-based near/vision sweeps (via the shared square sweep sensor), and
  - event-based `MapObjects.OnLoadWithSprite` for “as chunks load” discovery.
- Locked in a stable sprite identity key based on the compound tuple `(spriteName, spriteId, x, y, z, objectIndex)` and removed reliance on `getKeyId()`.
- Added smoke tooling for sprite debugging:
  - `examples/smoke_sprites_mapobjects.lua` (direct `MapObjects.OnLoadWithSprite`, no WorldObserver),
  - `examples/smoke_sprites.lua` (WorldObserver-based; explicitly `start()` then `enableOnLoad()` / `enableSquare()`; prints via `_G.print` for reliable console output).
- Fixed a real PZ/Kahlua incompatibility: removed use of non-guaranteed Lua stdlib functions (`next()` caused a crash) and replaced emptiness checks with safe alternatives.
- Performed a naming cleanup to streamline “runtime plumbing” vocabulary:
  - standardized on `attach*` / `detach*` for tick hooks and one-shot hook helpers,
  - removed underscore-prefixed “private” names where they leaked into public discussion, and
  - updated code, tests, and docs to match.
- Clarified the WO vs LQR responsibility split in docs:
  - WorldObserver owns “when/how to ingest” (fact plans, budgets, runtime controller heuristics),
  - LQR owns “what ingest means” (buffer/scheduler semantics), with a direct link to https://github.com/christophstrasen/LQR/blob/main/docs/concepts/ingest_buffering.md.
- Standardized highlight decay semantics across the whole codebase:
  - implemented a single cadence rule (`max(staleness, cooldown) / 2`) in `WorldObserver/helpers/highlight.lua`,
  - refactored all fact plans to call the same helper (`Highlight.durationMsFromEffectiveCadence(...)`),
  - added a dedicated busted spec to prevent regressions.
- Improved log readability by renaming the shared square sweep logger tag to `WO.FACTS.squareSweep` (it previously looked like “squares facts” even when scanning for other types).
- Expanded `docs_internal` maintenance structure:
  - created `docs_internal/index.md` as a “start here” map,
  - moved proposal/design docs into `docs_internal/drafts/`,
  - added `docs_internal/testing.md` to formalize the de-facto test patterns used across the suite.
- Added a focused helpers architecture doc (`docs_internal/helpers.md`) and a user-facing helpers guide (`docs/guides/helpers.md`), including:
  - helper family vs observation family distinctions (not strictly 1:1),
  - helper attachment rules (`enabled_helpers`, alias resolution, `withHelpers`, `registerHelperFamily`),
  - new naming conventions and effectful-helper guidelines.
- Standardized predicate helpers to the `<family>Filter` naming scheme:
  - renamed all `where<Family>` helpers to `squareFilter`, `zombieFilter`, `spriteFilter`, etc.,
  - updated call-sites, tests, and docs accordingly (no compatibility shims).
- Added an effectful sprite helper `removeSpriteObject()` (renamed from `removeAssociatedTileObject`) to remove the observed tile object via `IsoGridSquare:RemoveTileObject`.
- Refactored helper plumbing out of `observations/core.lua` into `observations/helpers.lua` (no behavior change), keeping core focused on stream/registry mechanics.
- Kept busted output clean by extending headless suppression patterns to helper “missing field” warnings and adding headless flags to missing test files.
- Implemented derived stream creation that preserves WO lifecycle semantics:
  - added `WorldObserver.observations:derive(...)` as a wrapper over LQR joins while keeping fact start/stop behavior,
  - ensured `ObservationStream:getLQR()` returns a join-friendly builder rooted at output schemas,
  - merged helper families/dimensions across input streams and documented the pattern.
- Expanded helper attachment and third‑party support:
  - introduced `ObservationStream:withHelpers({ helperSets, enabled_helpers })` with alias resolution,
  - added `WorldObserver.observations:registerHelperFamily(...)` and `stream.helpers.<family>` namespaces,
  - updated docs/tests and wrote both internal (`docs_internal/helpers.md`) and user‑facing (`docs/guides/helpers.md`) helper guides.
- Standardized helper naming and semantics:
  - renamed all `where<Family>` stream predicates to `<family>Filter` (no shims),
  - renamed the effectful sprite removal helper to `removeSpriteObject`,
  - codified naming rules for read/filter vs effectful helpers.

### Lessons
- Smoke scripts are part of the user-facing API: they must read top-to-bottom with explicit “do X” steps (no hidden auto-enables).
- PZ/Kahlua is not “Lua 5.1 complete”: treat the stdlib as a compatibility surface and prefer explicit, engine-safe patterns.
- Highlight duration is user-perceived correctness: it should be derived from the observation cadence, not an arbitrary cap, and must be consistent across all fact families.
- Helper APIs need explicit naming and behavior rules to stay discoverable as the surface grows; codifying the conventions early prevents accidental divergence.

### Next steps
- Add a small “sprite discovery helper” for smoke runs (e.g. dump a sample of nearby sprite names) so users don’t need to guess sprite strings.
- Consider adding optional wildcard/predicate filtering for sprite names to avoid maintaining long explicit lists.

## day16 – Derived streams “in anger”: hedge_trample, helper semantics, and sprite name wildcards

### Highlights
- Added a practical derived-stream example (`examples/hedge_trample.lua`) joining zombies + sprites on `tileLocation` and using LQR grouping + `having` to express a real gameplay rule.
- Standardized `tileLocation` (`"x123y456z7"`) across square-related records so joins/grouping can key off a stable value without engine objects.
- Tightened derived-stream helper semantics:
  - `filter(...)` applies at the end of the stream (what subscribers see),
  - effectful helpers run as end-of-stream taps,
  - helpers target public schema keys (`square`, `zombie`, `sprite`, …), not internal schema names.
- Improved sprite interest ergonomics: prefix wildcards inside `spriteNames` (trailing `%`), while `onLoadWithSprite` stays exact-match only.
- Implemented the base `vehicles` observation family (v0):
  - acquisition: time-sliced `IsoCell:getVehicles()` probe (`scope="allLoaded"`) + best-effort `Events.OnSpawnVehicleEnd` listener,
  - record: `sqlId` preferred key with `vehicleId` fallback, tile coords via `vehicle:getSquare()`, best-effort `IsoGridSquare` retained,
  - stream: `WorldObserver.observations:vehicles()` with required `:vehicleFilter(fn)` helper and square highlight on emit.
- In-engine smoke validated for vehicles: probe emits and highlights correctly, and ingest stays stable (no drops / no pending growth).
- Docs follow-through: streamlined stream basics, clarified `highlight` merge behavior, and expanded derived-stream guidance around join vs group vs distinct windows.

### Lessons
- Users think in terms of “the stream I subscribed to”; helpers chained after `derive(...)` must apply to the derived stream output, not intermediate rows.
- Windows are layered tools (join vs rule grouping vs noise control); calling out their roles prevents subtle correctness bugs.
- Stable join keys in records (like `tileLocation`) avoid fragile cross-family queries (hydration, ad-hoc IDs, engine references).
- Vehicles: `sqlId` exists in B42 Lua (observed), but stability across save/load is still an empirical requirement; event listeners must be validated with real emissions.

### Next steps
- Spawn a vehicle (debug/admin or scripted) and confirm at least one `OnSpawnVehicleEnd` emission + payload args (`source=event`).
- Do a save/reload check and confirm `sqlId` stability for a known vehicle across sessions (adjust key strategy if needed).
- Ensure each observation doc calls out stable identity fields and what they’re safe for (join keys vs hydration); consider one additional “pattern” example beyond hedge trample to cement the mental model.

## day17 – Checklist v2, room join keys, source logging polish, and player observations (v0)

### Highlights
- Upgraded the observation checklist template and created/finalized `playerObservation_checklist.md` to match current best practices (200ms cadence guidance, `playerKey`, `roomLocation` joins, and explicit engine userdata fields).
- Removed `sourceTime` boilerplate from fact builders by relying on ingest auto-stamping (shared default behavior).
- Added a join-friendly `roomLocation` field to room records (alias of `roomId`) and updated tests + docs.
- Standardized source labeling in logs (logging-only): records keep coarse `record.source` but debug output prints a qualified label (`event.onPlayerMove`, etc).
- Implemented the new `players` fact + observation family:
  - Interest scopes: `onPlayerMove`, `onPlayerUpdate` (event-driven).
  - Record schema includes `playerKey`, spatial anchors (`tileLocation`), room/building join keys (`roomLocation`, `buildingId`), and best-effort engine objects (`IsoPlayer`, `IsoGridSquare`, `IsoRoom`, `IsoBuilding`).
  - Highlight support: highlights the square the player is on when emitting.
  - Added minimal helper surface: `:playerFilter(fn)`.
- Added player docs + interest docs updates, plus a minimal in-engine smoke script: `examples/smoke_players.lua`.

### Notes / observations
- In singleplayer, `steamId` / `onlineId` may appear as `0`, so `playerKey` can read like `steamId0` (still useful as a per-session key, but not a stable cross-session identity).

### Tests
- Headless unit tests pass (`busted tests`: 128 successes).

### Next steps
- Decide whether to treat numeric `0` IDs as “missing” when building `playerKey` (to prefer any real non-zero id in MP).
- Add a tiny in-engine-only validation note to `docs/observations/players.md` for verifying room joins (walk indoors and confirm `roomLocation` changes).
