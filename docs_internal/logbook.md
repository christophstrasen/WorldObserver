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
  - Helper sets (square/zombie/spatial/time/etc.) are thin, reusable sugar attached based on `enabled_helpers`, assuming certain fields in the observation records.
  - WorldObserver owns “fact plans” (event + probe strategies) per element type, with strategy selection as an advanced config knob.

- Sketched the first concrete use case in API terms:
  - “Find squares with blood around the player” expressed as:
    - `WorldObserver.observations.squares():maxDistanceTo(playerIsoObject, 20):withBlood():subscribe(...)`
  - This mirrors the traditional scanner pattern (OnTick + batched scans + callback) while keeping scanning details in the Facts layer.

### Next steps
- Flesh out additional use cases (e.g. rooms with zombies, safehouse compromise) to pressure‑test ObservationStreams and Situation helpers.
- Design the internal fact source API (Event Listener / Active Probe builders and configurable strategies) to support the agreed surface behavior.
- Iterate on Situation and Actions APIs once a couple of ObservationStream patterns feel solid.
