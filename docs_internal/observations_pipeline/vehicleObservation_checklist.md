# VehicleObservation Checklist

---

## Metadata

- Observation goal (1 sentence): observe vehicles and emit stable snapshot records (v0: `allLoaded` probe + `OnSpawnVehicleEnd`) to enable derived “situations” later (example: “cars under attack”).
- Interest `type`: `vehicles`
- Observation payload family key: `vehicle`
- Helper family key (if different): `vehicle`
- Primary consumer(s) / situations enabled: future derived situation: `cars under attack`

---

## Implementation Status

- Status: ☐ idea ☐ prototyping ☐ in progress ☑ test-complete ☑ documented ☐ shipped
- What is done:
  - ☑ Interest surface defined + documented
  - ☑ Fact acquisition wired (listener/probe) + ingest lanes
  - ☑ Record schema stable + key stability documented
  - ☑ Observation stream + helpers wired
  - ☑ Unit tests passing (`busted tests`)
  - ☑ Smoke test example works in-game (or via `pz_smoke.lua` if applicable)
- Open tasks / blockers:
  - Confirm `BaseVehicle.sqlId` stability across save/load (existence confirmed empirically; stability still uncertain).
  - Confirm `OnSpawnVehicleEnd` payload shape by spawning a vehicle and seeing at least one `source=event` emission.
- Known risks (perf/correctness/staleness/hydration):
  - `vehicle.sqlId` stability (save/load, MP) is currently assumed; must be proven before committing to it as a long-term key.
  - Event payload shapes and availability in Build 42 Lua must be verified in-engine (PZWiki lists events, but argument contracts need confirmation).

---

## 0) Problem Statement + Modder UX

- What does the modder want to accomplish (not implementation): A Base observation stream that covers basic scenarios and that can be used for at least one advanced scenario.
- “Smallest useful” copy/paste example (declare interest + subscribe): (validated in-engine via `examples/smoke_vehicles.lua`)

```lua
local WorldObserver = require("WorldObserver")

local MOD_ID = "YourModId"

local lease = WorldObserver.factInterest:declare(MOD_ID, "vehicles.demo", {
  type = "vehicles",
  scope = "allLoaded",
  staleness = { desired = 5 },  -- default: 5s
  cooldown = { desired = 10 },  -- default: 10s (keyed by sqlId, else vehicleId)
  highlight = true,             -- highlight the floor square under the vehicle
})

local sub = WorldObserver.observations:vehicles()
  :distinct("vehicle", 10)                       -- keep output low-noise (dedup by sqlId, else vehicleId)
  :subscribe(function(observation)
    local v = observation.vehicle
    if not v then return end
    print(("[WO] sqlId=%s vehicleId=%s scriptName=%s tile=%s,%s,%s source=%s"):format(
      tostring(v.sqlId),
      tostring(v.vehicleId),
      tostring(v.scriptName),
      tostring(v.tileX),
      tostring(v.tileY),
      tostring(v.tileZ),
      tostring(v.source)
    ))
  end)

-- later:
-- sub:unsubscribe()
-- lease:stop()
```
- One intended derived stream / “situation” this base stream should enable (name it): “cars under attack”
- Non-goals / explicitly out of scope for v0:
  - Define “cars under attack” semantics (derived stream) beyond providing a useful base vehicle record stream.

---

## 1) Naming + Vocabulary (get this right early)

- Interest `type` name rationale (plural, stable): `vehicles` matches the engine concept (vehicle facts) and aligns with existing `zombies`, `deadBodies`, `items` naming.
- Payload family key rationale (singular, stable): `vehicle` aligns with “record family” naming patterns (`zombie`, `square`, `deadBody`, `item`).
- Avoided names (and why): `car` (engine concept is vehicle; supports non-car vehicles)
- Glossary impact:
  - ☑ No new terms
  - ☐ New term added to `docs/glossary.md` (only if unavoidable)

---

## 2) Interest Surface (type / scope / target)

Define the supported combinations and settings first (data-driven truth).

- Supported `scope` list:
  - `allLoaded`
- Per-scope acquisition mode:
  - `scope = "allLoaded"`: ☑ mixed (probe snapshots + spawn event)
- Target rules (if applicable):
  - Allowed target keys: n/a (no target in v0; mirrors `zombies` `allLoaded`)
  - Default target (if omitted): n/a
  - Merge/bucket behavior (what merges together, what does not): single bucket per scope (same as zombies; no target bucketing)
- Settings and semantics (per scope):
  - `staleness` (seconds, in-game clock): target max-age for periodic probe snapshots (mirror `zombies`)
  - `cooldown` (seconds, in-game clock): per-vehicle re-emit gating (key: `sqlId` when present, otherwise `vehicleId`)
  - Defaults (v0):
    - `staleness.desired = 5`
    - `cooldown.desired = 10`
  - `highlight` support: ☑ yes (highlight the floor square under the vehicle)
  - Explicitly unsupported in v0:
    - `radius` without a target (does not apply)
    - `target` (no near/vision yet)
- Update the central truth:
  - ☑ `WorldObserver/interest/definitions.lua` updated
  - ☑ `docs_internal/interest_combinations.md` updated
  - ☐ `docs/guides/interest.md` updated (only if user-facing surface changed)

---

## 3) Fact Acquisition Plan (probes, listeners, sensors)

Key rule: produce *small records* and call `ctx.ingest(record)` (don’t do downstream work in engine callbacks).

- Listener sources (engine callbacks / LuaEvents):
  - Events used: `Events.OnSpawnVehicleEnd.Add(fn)` (assumed to provide a `BaseVehicle`)
  - Payload extraction strategy: create/update a vehicle record from the provided `BaseVehicle` and `ctx.ingest(record)` (no downstream work in the callback)
  - Backpressure boundary: ☑ uses `ctx.ingest`
  - Event semantics: same as other event-backed fact sources in WO; event emissions are still subject to per-key `cooldown` gating and only highlight on actual emit.
- Probe sources (active scans):
  - Probe driver/sensor: `IsoCell:getVehicles()`
  - Scan focus: `allLoaded`
- Time-slicing + caps (how work is bounded): mirror `zombies` `allLoaded`: run a cursor over the `IsoCell:getVehicles()` list on tick, ingesting up to a per-tick CPU-time budget and per-run item cap, then resume next tick; sweep cadence is driven by effective `staleness`, and per-vehicle re-emits are gated by `cooldown`.
- Failure behavior:
  - Missing engine APIs: if `IsoCell:getVehicles()` or `OnSpawnVehicleEnd` is not available in Lua, the type must log a single actionable warning (outside headless) and disable the missing source.
  - Nil / stale engine objects: treat `BaseVehicle` as ephemeral; compute records immediately and never retain engine objects long-term on the record.
  - Missing square: `vehicle:getSquare()` may be `nil`; keep records usable without square linkage (but skip highlight and leave coords unset).
  - Missing ids: if both `sqlId` and `vehicleId` are `nil`, warn (outside headless) and drop the record.

---

## 4) Record Schema (fields to extract)

Design constraints:
- Records are snapshots (primitive fields + best-effort hydration handles).
- Avoid retaining live engine userdata long-term.

- Required fields (must exist on every record):
  - Identity (short/session): `vehicleId` (from `vehicle:getId()`)
  - Identity (preferred stable, optional): `sqlId` (from `vehicle.sqlId`; may be `nil`)
  - Spatial anchor (match zombie naming; when `vehicle:getSquare()` is available):
    - `tileX`, `tileY`, `tileZ` from `vehicle:getSquare():getX()/getY()/getZ()`
    - `x`, `y`, `z` set equal to `tileX/tileY/tileZ` for schema consistency and to support square hydration helpers
  - Timing: `sourceTime` (ms, in-game clock; auto-stamped at ingest if omitted)
  - Provenance: `source` (string, producer/lane)
- Optional fields (cheap, high leverage):
  - `name` via `getObjectName()`, `scriptName` via `getScriptName()`, `skin` via `getSkin()`, `type` via `getVehicleType()`
  - Status flags (confirm Lua exposure): `isDoingOffroad`, `hasPassenger`, `isSirening`, `isStopped`
- Best-effort hydration fields (may be missing/stale):
  - `IsoGridSquare` (live engine object) is attached best-effort from `vehicle:getSquare()` as `record.IsoGridSquare`; treat as ephemeral and validate via `WorldObserver.helpers.square.record.getIsoGridSquare(...)` if needed.
---

## 5) Primary Key / ID and Stability Contract

- Primary key field names:
  1. Preferred: `sqlId` (assumed long-term stable when present): record field `sqlId` (source: `vehicle.sqlId`)
  2. Fallback: `vehicleId` (short/session id): record field `vehicleId` (source: `vehicle:getId()`)
- Dedup/cooldown key:
  - Which field defines “same underlying fact” for cooldown?
    - Prefer `sqlId`, else fall back to `vehicleId` (accept unstable key)
  - Any alternate stable anchor to prefer: none planned (if `sqlId` is proven unstable or often nil, revisit)

---

## 6) Relation Fields + Hydration Strategy

Bias towards capturing enough identifying data to rehydrate, not storing engine objects.

- Relations to capture (examples: square, room, target player, container):
  - Relation: `getSquare()` → capture `tileX/tileY/tileZ` and set `x/y/z` to match, plus attach best-effort `IsoGridSquare` when available
- Hydration helpers (best-effort, safe `nil`):
  - For the `getSquare()` relation, prefer storing `x/y/z` on the record and treat `IsoGridSquare` as best-effort only.
    - Vehicle records should set `x/y/z` to the same values as `tileX/tileY/tileZ` so `WorldObserver.helpers.square.record.getIsoGridSquare(...)` can work without special-casing vehicles.
  - `WorldObserver.helpers.square.record.getIsoGridSquare(squareLikeRecord, opts)`
    - Contract: returns a live `IsoGridSquare` when available, otherwise `nil`; never throws.
    - Requires: `squareLikeRecord.x/y/z` numeric.
    - Caching: when hydration succeeds, caches to `squareLikeRecord.IsoGridSquare`; when it fails, clears `squareLikeRecord.IsoGridSquare = nil`.
    - Opts: may pass `opts = { cell = <IsoCell> }` (must have `cell:getGridSquare(x,y,z)`) to avoid relying on `_G.getWorld()` / `_G.getCell()`.
  - `WorldObserver.helpers.square.record.squareHasIsoGridSquare(squareLikeRecord, opts)` (predicate; may hydrate/cache as above)
- Staleness strategy for relations:
  - Vehicle rehydration: avoid promising a stable `BaseVehicle` handle; treat it as ephemeral. If we add a best-effort `getBaseVehicle(record)` later, it likely has to use `VehicleManager:getVehicleByID(vehicleId)` (short/session id) and therefore may fail across reloads (or when the vehicle is unloaded).

---

## 7) Stream Behavior Contract (emissions + dimensions)

Keep this section compact. It should summarize what section 3 implies for subscribers.

- Sources → emissions: `scope="allLoaded"` emits periodic probe snapshots (cadence via `staleness`) plus event-driven emissions from `OnSpawnVehicleEnd`; both are gated by `cooldown` where applicable
- Primary stream dimension: `distinct("vehicle", seconds)` dedups by `sqlId` when present, otherwise `vehicleId` (matches the intended cooldown/dedup key)
- Freshness + buffering: best-effort; may be delayed by ingest buffering; under load the effective settings may degrade (example: higher effective `staleness` / `cooldown`)
- Payload guarantees: base stream emits `observation.vehicle`; hydration fields are best-effort and may be `nil`/stale

---

## 8) Minimum Useful Helpers

Keep helpers small, composable, and discoverable. Prefer record predicates + thin stream sugar.

- Record helpers (predicates/utilities): none in v0 (keep minimal)
- Stream helpers (chainable sugar): `vehicleFilter(fn)` (required baseline helper)
  - Naming: follows `<family>Filter(fn)` conventions
- Effectful helpers (rare; clearly named): none in v0
- Documentation:
  - ☐ listed in `docs/observations/vehicles.md`

---

## 9) Debugging + Highlighting

- Interest-level `highlight` behavior (what gets highlighted): highlight the floor square under the vehicle when a record emits (same “highlight-on-emit” semantics as other types).
- Optional marker/label support (if applicable): n/a for v0
- Debug API coverage:
  - ☐ `WorldObserver.debug.describeFacts("<type>")` meaningful
  - ☐ metrics (`describeFactsMetrics`) meaningful
- “How to verify it works” steps for modders:
  - Declare `type="vehicles", scope="allLoaded", highlight=true`
  - Subscribe and print `sqlId, scriptName, tileX/tileY/tileZ, source` and confirm highlighted squares appear

---

## 10) Verification: Tests (headless) + Engine Checks

- Unit tests added/updated:
  - ☑ record builder spec: `tests/unit/vehicles_spec.lua`
  - ☐ collector/probe/listener spec (as applicable): `tests/unit/...`
  - ☑ observation stream spec: `tests/unit/vehicles_observations_spec.lua`
  - ☑ record extenders spec updated (if extenders added): `tests/unit/record_extenders_spec.lua`
  - ☑ contract spec still passes: `tests/unit/interest_definitions_contract_spec.lua`
- Headless test run command: `busted tests`
- Engine verification checklist:
  - ☑ APIs confirmed empirically: `IsoCell:getVehicles()`, `BaseVehicle.sqlId`, `BaseVehicle:getId()`, `BaseVehicle:getSquare()`, `IsoGridSquare:getX()/getY()/getZ()`
  - ☐ Works with nil/missing objects (unloaded squares, despawned entities)
  - ☐ No unbounded work per tick (caps/budgets verified)

---

## 11) Documentation (user-facing + internal)

- User-facing docs:
  - ☑ add/update `docs/observations/vehicles.md`
  - ☑ update `docs/observations/index.md` (if new base stream)
  - ☑ update `docs/guides/interest.md` (surface lists)
  - ☐ update `docs/guides/*` (only if new concepts are introduced)
- Internal docs (keep architecture coherent):
  - ☐ `docs_internal/fact_layer.md` updated (if new acquisition patterns)
  - ☐ `docs_internal/code_architecture.md` updated (if new modules/sensors)
  - ☐ `docs_internal/logbook.md` entry added (lessons learned)

---

## 12) Showcase + Smoke Test

- Example script added/updated (where): `Contents/mods/WorldObserver/42/media/lua/shared/examples/smoke_vehicles.lua`
- Minimal smoke scenario (“how to see it in action quickly”): declare `vehicles` allLoaded with `highlight=true` and print a single line per emitted vehicle (dedup by `sqlId`, fallback to `vehicleId`)
- Lease renewal: not required for the smoke test (default lease TTL is long enough for a short demo).
- Workshop sync smoke (`pz_smoke.lua` / `watch-workshop-sync.sh`) considerations:
  - ☑ `require(...)` paths compatible with PZ runtime (no `init.lua` assumptions)
  - ☐ Works in vanilla Lua 5.1 headless where intended

---

## Research & Brown Bag (keep at bottom)

### Research notes (sources + findings)

- PZWiki links consulted:
  - `https://pzwiki.net/wiki/OnSpawnVehicleEnd`
  - `https://pzwiki.net/wiki/OnUseVehicle`
  - `https://pzwiki.net/wiki/OnVehicleDamageTexture`
  - `https://pzwiki.net/wiki/OnSwitchVehicleSeat`
- ProjectZomboidLuaDocs / JavaDocs entrypoints and methods (to verify):
  - `BaseVehicle:isCharacterAdjacentTo(IsoGameCharacter)` (from JavaDocs link in `docs_internal/research.md`)
  - Methods noted in research (must confirm Lua exposure): `isDoingOffroad()`, `hasPassenger()`, `isSirening()`, `isStopped()`
  - Question to resolve: whether `BaseVehicle:WeaponHit(IsoGameCharacter, HandWeapon)` is callable/observable and whether “zombies hitting the car triggers” via any event.
- Events/hooks used (and exact payload shape if non-obvious): `[...]` (must confirm callback args for the PZWiki events above)
- Empirical checks run (console snippets / in-game test steps): `[...]`
- Open questions / uncertainties (and proposed minimal tests):
  - What is the best stable vehicle identifier to use as primary key (session/save/load/MP)?
  - Do the listed vehicle events provide enough coverage to detect “under attack”, or do we need an additional probe or thump/hit event correlation?

### Brown bag session (internal sharing)

- Audience: ☑ WO contributors ☐ mod authors ☐ mixed
- Duration: `[...]` minutes
- Agenda (3–5 bullets):
  - Vehicle events recap (what exists, what payload args look like).
  - Proposed v0 vehicle record schema + id stability contract.
  - “Cars under attack” derived stream sketch (what it would join/correlate; no code yet).
  - Performance expectations + how to keep vehicle observation bounded.
- Live demo script / save setup: `[...]`
- “Gotchas” to highlight (staleness vs cooldown, id stability, hydration pitfalls): `[...]`
- Performance notes (what costs, what mitigations, recommended defaults): `[...]`
