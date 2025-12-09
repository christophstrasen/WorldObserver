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
