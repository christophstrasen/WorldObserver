# Refactor brief: data-driven interest definitions + shared sensors

Status: proposal / refactor runway

This brief describes a refactor intended to make it safe and scalable to grow WorldObserver’s fact interest surface (more `type/scope/target` combinations) while avoiding duplicated scanning work.

## Context (why now)

We want to add new interest shapes that naturally overlap in “how we sense the world”:

- Rooms: `type="rooms"` with `scope="onPlayerChangeRoom"` (target = player).
- Items on ground: `type="items"` with `scope="playerSquare" | "near" | "vision"` (target = player).
- Dead bodies on ground: `type="deadBodies"` with `scope="playerSquare" | "near" | "vision"` (target = player).

The main design pressure: `near/vision` for multiple types should reuse the same “square sweep” mechanics rather than duplicating the same loops per fact type.

Today, interest normalization/validation lives as per-type hardcoding in `WorldObserver/interest/registry.lua`, and the square sweep mechanics live embedded in `WorldObserver/facts/squares/probe.lua`. That is workable for 2–3 types, but it will not scale cleanly to 6–10 types with overlapping scope semantics.

## Goals

- Keep the modder-facing interest shape stable and predictable: `type/scope/target` + knobs (bands).
- Make it easy to add new interest types/scopes without growing a big “if/elseif ladder” across files.
- Share expensive sensing loops (especially square sweeps) across multiple fact types.
- Keep lifecycle guarantees: facts only run while relevant streams are subscribed (subscriber-gated), and only while there is at least one active interest lease.
- Preserve current behavior for existing types (`squares`, `zombies`, `rooms`) while refactoring.

## Non-goals (initially)

- Always-on global event bus: we do not introduce always-running LuaEvents by default.
- Sharing “simple global list probes” that are already cheap and self-contained (example: `getCell():getZombieList()` scanning) unless we see a real duplication/cost problem.
- Perfect “removal” semantics for items/bodies in v1 (e.g. explicit “item removed” events). Initial semantics remain observation-based.
- Deep, unbounded recursion for “items inside containers”; we should keep container expansion bounded and explicit.

## Key decisions (locked for this refactor)

- **Interest type names are plural** (consistent with `squares`, `zombies`, `rooms`):
  - Proposed new types: `items`, `deadBodies`.
- **Shared sensing is expressed as internal sensors** that can be reused by multiple fact plans.
  - We share the square sweep driver; we do **not** force sharing for list scans like zombies.
- **Items definition (v0):** only items on the ground (world items), including items inside containers on the ground.
- **Rooms `scope="onPlayerChangeRoom"` emits only on change**:
  - When the player exits to outdoors/no-room, we do not emit any record (for now).
  - We make a mental note: future “playerLocation” observations may emit on exit with `outdoors=true` etc.
- **Dead body identity (v0):** use `getObjectID()` as the primary key (verify in-game + tests).

## Proposed architecture

### 1) Data-driven interest definitions (capability table)

Introduce a central, data-driven table that defines what each interest type supports:

- Supported scopes per type.
- Supported `target` kinds per scope.
- Which knobs apply per scope (and which are ignored).
- Bucket key strategy (how to group/merge interest).
- Optional links to shared sensors (e.g. “this type uses squareSweep sensor for near/vision”).
- keep track of test coverage for combinations and permutations

This table becomes the single place to update when we add a new type or scope.

**Primary consumers:**
- `WorldObserver/interest/registry.lua` for normalization + validation + ignored-field warnings.
- `docs_internal/interest_combinations.md` generation/checklist (manual initially).
- Unit tests that assert definitions and normalization stay aligned.

### 2) Shared sensors + per-type collectors

Introduce the concept of **sensors** (shared acquisition drivers) and **collectors** (per-type extraction + emit):

- **Sensor:** owns iteration mechanics, budgets, and cadence (cursor state, sweep scheduling, visibility checks).
- **Collector:** given a “sensor sample” (e.g. a scanned square), extracts one or more fact records and emits them via its fact type’s `emitFn`.

This lets multiple types share the same scan without “drive-by discovery” becoming implicit magic:
- Sensors only run when at least one dependent fact stream is active and has an active lease.
- Collectors remain explicit per type, and each collector controls its own record schema + keying + cooldown semantics.

### 3) The `squareSweep` sensor (the first shared sensor)

The `squareSweep` sensor is a shared implementation of what `facts/squares/probe.lua` does today:

- Bucketed targets (player targets, plus any future shared targets if added).
- Scopes:
  - `near`: scan squares in a radius around player.
  - `vision`: same scan, but filter to squares currently visible to the player.
- Cadence knobs: `radius`, `staleness`, `cooldown` (cooldown influences *emit*, but cadence is driven by staleness + cursor lag).
- Policy: apply the existing interest ladder/hysteresis logic per bucket key (currently implemented via `facts/interest_effective.lua` + `interest/policy.lua`).

**Key change:** the scan cadence should be shared across **all collectors that use the same sensor + bucket**.
That implies the sensor (not each collector) owns the policy state and chooses the effective sweep settings.

### 4) Rooms `onPlayerChangeRoom` as a listener-ish scope

`rooms` gains a new scope:

- `type="rooms"`, `scope="onPlayerChangeRoom"`, `target = { player = { id = 0 } }` (or any player id).

Implementation: a tick-based listener (FactRegistry tick hook) that:
- resolves the player’s current room (`player:getCurrentSquare():getRoom()` or equivalent),
- compares to previous room (prefer comparing the `IsoRoom` reference for cheapness),
- on change to a non-nil room, builds a room record and emits it.

Performance note: compute `roomId` only when a change is detected (not every tick).

### 5) Squares + items + dead bodies collectors (using `squareSweep`)

For MVP we propose:

- `squares` collector (existing):
  - `type="squares"` scope `near/vision` stops owning a dedicated sweep loop.
  - Instead, it registers as a collector on the shared `squareSweep` sensor and turns scanned squares into square records.
  - `scope="onLoad"` remains event-driven and does not use the sensor.

- `items` collector:
  - When a square is scanned, extract world items on that square.
  - For container world items, also enumerate their contained items (bounded; see “Caution”).
  - Emit one record per observed item; key by `getID()` when available (verify).

- `deadBodies` collector:
  - When a square is scanned, extract dead bodies on that square (API to confirm).
  - Emit one record per body; key by `getObjectID()` initially.

These collectors share the sensor sweep: they do not drive their own square iteration.

## New capabilities (planned surface)

### Interest combinations (new)

Add to the supported matrix (alongside existing `squares/zombies/rooms`):

- `type="rooms"`
  - `scope="onPlayerChangeRoom"` + `target=player`
  - Knobs: `cooldown`, `highlight` (optional); other probe knobs ignored.

- `type="items"`
  - `scope="playerSquare"` + `target=player` (single square underfoot).
  - `scope="near"` + `target=player` (via squareSweep sensor).
  - `scope="vision"` + `target=player` (via squareSweep sensor).
  - Knobs (initial): `radius`, `staleness`, `cooldown`, `highlight`.

- `type="deadBodies"`
  - `scope="playerSquare"` + `target=player`.
  - `scope="near"` + `target=player` (via squareSweep sensor).
  - `scope="vision"` + `target=player` (via squareSweep sensor).
  - Knobs (initial): `radius`, `staleness`, `cooldown`, `highlight`.

### Observation streams (new)

Proposed new base streams:
- `WorldObserver.observations.items()`
- `WorldObserver.observations.deadBodies()`

Both follow the same pattern as other streams: they emit **records**, not long-lived engine objects.
Engine objects can be included optionally (config) or rehydrated best-effort later.

## Areas of greatest caution

1) **Behavior drift for existing types**
- `interest/registry.lua` refactor must preserve current defaults and ignored-field behavior for:
  - `squares` scopes: `near`, `vision`, `onLoad`
  - `zombies` scope: `allLoaded`
  - `rooms` scopes: `allLoaded`, `onSeeNewRoom`

2) **Who owns cadence when multiple types share a sensor**
- If `items` and `squares` both depend on square sweeps, we must define how their interests combine.
  - Proposed: sensor merges requirements across all active dependent types for a bucket (union semantics consistent with today’s merges).
  - The sensor then chooses one effective cadence and drives all dependent collectors.

3) **Volume + keying for items**
- Emitting one record per item can create high volume.
- Keying must be stable:
  - validate that `getID()` exists and is stable for ground items we care about.
  - define fallback behavior when no id exists (skip vs derived key vs warn).

4) **Containers inside containers**
- “Include items inside containers” can explode in cost if recursion is unbounded.
  - MVP should define an explicit bound (e.g. depth=1, only direct contents), and later add an opt-in knob if deeper traversal is needed.

5) **Subscriber gating with shared sensors**
- Sensors must not run when nothing is subscribed:
  - ensure “collector registration” is tied to fact start/stop (FactRegistry lifecycle).
  - avoid creating a sensor that runs as a global singleton without subscribers.

6) **Testing stubs vs engine reality**
- Several APIs need confirmation in Build 42 Lua (items on square, dead bodies, ids).
- Unit tests should be written so they validate our logic without hardcoding engine behavior we haven’t verified.
- Add at least one smoke script path to validate in-game quickly once implemented.

## Proposed module layout (target)

### Interest (refactor)

- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/interest/definitions.lua`
  - Capability table: per-type scopes, target kinds, knob applicability, bucket key strategy, sensor links.
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/interest/registry.lua`
  - Uses `definitions.lua` for normalization and bucket key derivation.
- `docs_internal/interest_combinations.md`
  - Updated to reflect `definitions.lua` and new types/scopes.

### Sensors (new)

- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/sensors/square_sweep.lua`
  - Extracted + generalized from `facts/squares/probe.lua`.
  - Runs the sweep and calls registered collectors.

### Fact plans (collectors)

- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/squares.lua`
  - Becomes a collector registration to `square_sweep` (for `near/vision`) plus existing onLoad listener.
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/items.lua` (new)
  - Registers as a collector to `square_sweep` for `near/vision`, and has a separate simple driver for `playerSquare`.
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/dead_bodies.lua` (new)
  - Same pattern as `items.lua`.
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/rooms.lua`
  - Adds `onPlayerChangeRoom` driver (tick hook), alongside existing `onSeeNewRoom` + `allLoaded` probe.

### Record builders + helpers (new)

- `.../facts/items/record.lua`, `.../helpers/item.lua`
- `.../facts/dead_bodies/record.lua`, `.../helpers/dead_body.lua`

## Step-by-step implementation plan (with testing)

### Step 0 — Lock current behavior (tests first)
- Add/extend unit tests that assert interest normalization + bucket keys for existing types.
- Add “golden” tests for squares probe cursor behavior if any refactor touches it.
- Ensure `busted tests` is green before changes.

### Step 1 — Introduce `interest/definitions.lua` and migrate normalization
- Add `definitions.lua` with entries for `squares`, `zombies`, `rooms`.
- Refactor `interest/registry.lua` normalization code to consult `definitions.lua`.
- Tests:
  - existing interest registry tests must pass unchanged.
  - add new tests: unknown scope handling remains identical (warn/ignore behavior in non-headless).

### Step 2 — Extract square sweep into `facts/sensors/square_sweep.lua`
- Move the core cursor/iteration/visibility logic out of `facts/squares/probe.lua`.
- Keep behavior identical for `squares` first: `facts/squares/probe.lua` becomes a thin wrapper around the sensor module (temporary).
- Tests:
  - existing squares probe tests remain green (`tests/unit/squares_probe_*`).

### Step 3 — Make `squares` (near/vision) a collector of the sensor
- Change `facts/squares.lua` to register a collector with the sensor instead of running its own sweep loop.
- Keep `onLoad` scope as-is (event-driven).
- Tests:
  - patch seam tests still pass (`tests/unit/patching_spec.lua`).
  - add one new test that verifies the sensor calls the squares collector (headless stubbed squares).

### Step 4 — Add `rooms` scope `onPlayerChangeRoom`
- Extend interest definitions for rooms with `onPlayerChangeRoom`.
- Implement room-change driver as tick hook (track previous `IsoRoom` ref + previous `roomId` as fallback).
- Tests:
  - unit test with stubbed player/square/room objects verifying emit only on change and not on nil/outdoors.

### Step 5 — Add `items` as a new fact type + observation stream
- Add interest definitions (`items` scopes: `playerSquare`, `near`, `vision`).
- Implement `items` fact plan:
  - `playerSquare`: simple “read current square and enumerate items” tick driver.
  - `near/vision`: register as collector to square sweep sensor.
- Implement item record builder + helper set.
- Tests:
  - unit tests for record builder (id extraction, square coords, optional container contents at depth=1).
  - unit tests for collector behavior (dedupe/cooldown by item id).

### Step 6 — Add `deadBodies` as a new fact type + observation stream
- Mirror the `items` plan.
- Key by `getObjectID()` initially and validate through tests + smoke.
- Tests:
  - record builder tests: object id + square coords.

### Step 7 — Integrate + docs + smoke
- Wire new facts/observations in `WorldObserver.lua`.
- Update docs:
  - `docs/guides/interest.md` (new types/scopes).
  - `docs/observations/items.md` and `docs/observations/dead_bodies.md` (new pages).
  - `docs_internal/interest_combinations.md`.
- Add/extend smoke scripts:
  - update `examples/smoke_console_showcase.lua` to start/stop the new streams and leases.

### Step 8 — Performance + diagnostics (guardrails)
- Implemented lightweight counters in the shared square sweep sensor:
  - squares scanned/visited/visible (per tick),
  - collector calls/“emitted any” calls,
  - record emits per collector (counted at `emitFn`).
- Added a low-spam toggle:
  - `probe.logCollectorStats = true` and `probe.logCollectorStatsEveryMs = ...` prints a compact summary line.
  - Live overrides now follow the *active* fact type driving the sweep (e.g. `facts.items.probe` when only items are running).
- Added a defensive container expansion cap for items:
  - `facts.items.record.maxContainerItemsPerSquare` (default 200) bounds depth=1 container fan-out per scanned square.

## Open questions (intentionally deferred)

- Container traversal: depth=1 vs recursive; do we need a knob like `includeContainerItemsDepth`?
  - Answer: Yes limit to depth=1
- Item identity: what do we do when `getID()` is missing/unreliable for some ground objects?
  - Answer: Throw a warning and don't emmit
- Removal semantics: do we ever want explicit “expired/removed” events for items/bodies, or do we keep this observation-only?
  - Answer: That is out of scope for now, maybe forever.
