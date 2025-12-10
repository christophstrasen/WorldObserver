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
