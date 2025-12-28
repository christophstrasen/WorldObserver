# WorldObserver Code Architecture (contributor guide)

This is a code-first overview of how WorldObserver is structured today, and how to extend it safely.
It is written for contributors who plan to add new fact types, scopes, probes/listeners, or observation streams.

Related internal docs (deeper dives):
- Fact layer + ingest boundary: `docs_internal/fact_layer.md`
- Interest declarations + merging: `docs_internal/drafts/fact_interest.md`
- Runtime controller model: `docs_internal/drafts/runtime_controller.md`
- Runtime dynamics (how the runtime shapes work): `docs_internal/runtime_dynamics.md`
- Interest surface matrix: `docs_internal/interest_combinations.md`
- Refactor brief (history + intent): `docs_internal/drafts/refactor_interest_definitions_and_sensors.md`
- Change log + lessons learned: `docs_internal/logbook.md`

## 0) Architecture principles (read first)

These are “guardrails” that keep WorldObserver safe, extensible, and debuggable as it grows. If you add new code, try to preserve these.

### Bounded work per tick (safety first)
WorldObserver must never introduce unbounded per-frame work. Large world scans must be time-sliced and/or capped, and should run inside the registry tick window so they are measured and controlled.

Concrete hooks:
- Register time-sliced work via `FactRegistry:attachTickHook(...)`: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/registry.lua:58`
- Shared square scanning is capped/budgeted: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/sensors/square_sweep.lua:1`

### Backpressure boundary at ingest
Engine callbacks and probes should not do downstream work directly. They create small records and push them through ingest, where cost is bounded and observable.

Core files:
- Fact registry + ingest scheduler: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/registry.lua:1`
- Fact layer notes: `docs_internal/fact_layer.md`
 - Ingest auto-stamps `record.sourceTime` (ms, game clock) when missing so record builders can stay focused on schema fields.

### Opt-in by interest, and gated by subscribers
We do work because someone asked for it:
- **Interest leases** (what work is allowed): `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/interest/registry.lua:1`
- **Subscriber gating** (what work is needed now): `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/observations/core.lua:60`

### Degrade gracefully instead of breaking
When load rises, we reduce quality/cadence or drain more slowly instead of stuttering the game. This is done via:
- Runtime controller modes and drain tuning: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/runtime.lua:1`
- Interest policy degradation ladder: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/interest/policy.lua:1`
- Probe auto-budgeting to “buy” freshness with headroom: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/sensors/square_sweep.lua:363`
- Runtime loop deep dive: `docs_internal/runtime_dynamics.md`

### Observations, not entities
Records are snapshots (stable ids/coords + best-effort hydration handles). Avoid retaining engine objects long-term. Prefer stable IDs/coordinates; treat Iso references as ephemeral.

### Shared sensors for shared costs
If multiple fact types need the same expensive scan pattern, share the driver (sensor) and fan out collectors (example: `square_sweep` powering `squares`, `items`, `deadBodies`).

### Patchable-by-default seams
WorldObserver is meant to be extended by other mods. Public-ish helpers/builders should be patchable by reassigning table fields, and reloads (tests/console) should not clobber patches.

Examples:
- Record builders + extenders: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/*/record.lua`
- Config seams (defaults assigned only when nil): `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/config.lua:1`

### Data-driven capability truth
The supported `type/scope/target` surface is defined centrally. New features should start by updating that definition and then wiring code to match it.

Source of truth:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/interest/definitions.lua:1`

### Tests and smoke tests are part of the architecture
Because we target both vanilla Lua 5.1 (headless) and Project Zomboid’s Kahlua runtime, we rely on a layered verification strategy:

- **Automated unit tests (busted):** fast, headless, and required for most changes: `busted tests`
- **Automated “built workspace” smoke test:** validates that a synced workshop tree can load like Zomboid does:
  - loader test: `pz_smoke.lua:1`
  - build/sync runner (also runs the loader smoke test): `watch-workshop-sync.sh:1`
- **Manual in-engine smoke tests (developer):** validate true engine integration (events, Iso objects, visuals):
  - smoke scripts live in `Contents/mods/WorldObserver/42/media/lua/shared/examples/`
  - the “start everything” harness is `Contents/mods/WorldObserver/42/media/lua/shared/examples/smoke_console_showcase.lua:1`

Workflow details:
- `docs_internal/development.md:1`

### Clear separation of concerns: WorldObserver vs LQR
WorldObserver is the Project Zomboid-specific host layer. LQR is the reusable query/ingest engine.

Keep the boundary clean:
- LQR should not depend on WorldObserver or Project Zomboid APIs (no `WorldObserver.*`, no `Events.*`, no Iso types).
- WorldObserver owns interest, runtime control, probes/listeners, record schemas, and engine compatibility shims.
- LQR owns generic stream/query mechanics (schemas, operators, ingest buffering/scheduler) and stays host-agnostic.

For the canonical definition of ingest buffering and scheduler semantics (buffer modes, lanes, drops, metrics), refer to LQR’s documentation: https://github.com/christophstrasen/LQR/blob/main/docs/concepts/ingest_buffering.md

Dependency direction:
- WorldObserver → LQR (`external/LQR/`), never the other way around.

## 1) Big picture (data flow)

WorldObserver is a pipeline with one major rule: **engine callbacks and probes should not do downstream work directly**.
They produce small “fact records”, and we buffer/drain on tick so costs are bounded and observable.

```
Project Zomboid engine
  Events.* callbacks + tick hooks + probes
        │
        ▼
Facts layer (per type): record builders + collectors/listeners
        │  (ctx.ingest(record) — buffered)
        ▼
Ingest buffers (per fact type)  →  one global ingest scheduler (tick-drained)
        │
        ▼
Fact observables (Rx Subjects, per fact type)
        │
        ▼
Observation streams (LQR schemas + queries) + helpers
        │
        ▼
Mods subscribe → derive “situations” → act
```

Primary wiring entrypoint:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver.lua:1`

## 2) Core concepts and invariants

### Facts vs observations
- **Facts** are the raw records produced by probes/listeners (input side).
- **Observations** are the public streams mods subscribe to (facts wrapped into schemas and exposed as streams).
- Records are intentionally “snapshots”: small tables of primitive fields plus best-effort hydration handles.

### Interest (why work happens at all)
WorldObserver is *opt-in*: most probes/listeners are gated by interest leases.
- Mods declare interest using `WorldObserver.factInterest:declare(modId, key, spec)`.
- Interest shape is `type/scope/target` + setting bands (e.g. `radius`, `staleness`, `cooldown`) + optional `highlight`.
- Interests are merged across mods into an **effective plan** (per bucket/target where applicable).

Canonical definition of the supported interest surface:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/interest/definitions.lua:1`

### Subscriber gating (lifecycle safety)
Even if a lease exists, a fact type should only run while there is at least one subscriber to that stream.
This avoids “forgot to revoke” leaks and keeps background work bounded.

Implemented via lazy start/stop in:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/registry.lua:1`
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/observations/core.lua:60`

### Derived ObservationStreams (joins, multi-family)
Derived streams must preserve subscriber gating. The main “gotcha” is that subscribing to an LQR query directly
**bypasses** `FactRegistry:onSubscribe(...)`, which can leave probes/listeners stopped in-game even though your
LQR join/query is subscribed.

Current solution:
- Build derived streams via `WorldObserver.observations:derive(...)` (implemented in `WorldObserver/observations/core.lua`).
  - It returns a normal `ObservationStream` and unions `fact_deps` from all input streams so facts start/stop correctly.
- `ObservationStream:getLQR()` returns a join-friendly LQR `QueryBuilder` rooted at the stream’s output schemas
  (`observation.square`, `observation.zombie`, …) and does not force a post-join schema selection that would drop joined schemas.

### Backpressure boundary: ingest
Producers “ingest”, the scheduler “drains”:
- Producers call `ctx.ingest(record)` (cheap, safe inside bursty callbacks).
- The per-type `Ingest.buffer` compacts/limits.
- The global `Ingest.scheduler` drains within budgets on tick.

Docs and code:
- `docs_internal/fact_layer.md`
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/registry.lua:44`

### Patchable-by-default seams
Public-ish functions are defined behind `if <field> == nil then` so other mods can monkey-patch by assignment
and test/console reloads don’t clobber patches.

Common examples:
- Fact registration entrypoints: `*.register(...)` in `WorldObserver/facts/*.lua`
- Record builders: `make<Family>Record(...)` and record extender registration functions in `WorldObserver/facts/*/record.lua`
- Helper functions in `WorldObserver/helpers/*.lua`

## 3) Module map (what lives where)

### Public facade
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver.lua`
  - Loads config, creates runtime + registries, registers fact types and observation streams.
  - Exposes the public API table: `WorldObserver.config`, `WorldObserver.observations.*`, `WorldObserver.situations.*`, `WorldObserver.factInterest`, `WorldObserver.helpers.*`, `WorldObserver.runtime`, `WorldObserver.debug`.

### Configuration + live overrides
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/config.lua`
  - Owns defaults and validates overrides from `_G.WORLDOBSERVER_CONFIG_OVERRIDES`.
  - Important: “live overrides” are read at runtime for certain debug settings so smoke scripts can toggle without reload.

### Runtime controller
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/runtime.lua`
  - Tracks tick cost windows, modes (normal/degraded/…), and budgets (especially ingest drain max items).
  - Emits LuaEvents for status changes when available (engine runtime).
  - Deeper dive (how probes + draining adapt at runtime): `docs_internal/runtime_dynamics.md`

### Debug API
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/debug.lua`
  - Introspection and printing helpers for smoke/testing and manual debugging.

### Interest system (declare → normalize → bucket → merge → effective)
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/interest/definitions.lua`
  - Data-driven type capabilities: scopes, target allowance, ignored settings, bucketKey strategy.
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/interest/registry.lua`
  - Stores leases (TTL) and merges declarations into effective interest bands per bucket.
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/interest/policy.lua`
  - Translates “merged interest” + runtime pressure signals into “effective interest” (degrade/recover).

### Facts layer (per type)
Facts are producers for one fact type. Each fact module typically owns:
- a record builder (`facts/<type>/record.lua`)
- zero or more fact sources (listeners and probes; some probes are implemented via shared sensors + per-type collectors)
- a `register(...)` function that registers the fact type with ingest configuration and starts/stops drivers

Main registry:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/registry.lua`

Per-type fact modules:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/squares.lua`
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/zombies.lua`
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/rooms.lua`
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/items.lua`
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/dead_bodies.lua`

Shared “internal sensors” and helpers:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/sensors/square_sweep.lua`
  - Shared near/vision square scanning driver (the “eyes”).
  - Calls registered collectors; tracks per-tick counters; optional collector fan-out logging.
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/ground_entities.lua`
  - Shared scaffolding for “entities on squares” fact types (items + dead bodies).
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/targets.lua`
  - Shared “target = player id” resolution used by multiple types.
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/interest_effective.lua`
  - Cached effective interest per type/bucket; bridges interest registry + policy.
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/cooldown.lua`
  - Per-key cooldown tracking helper.

### Record builders + extensibility
Each fact type has a record builder (`make<Family>Record`) that creates a small, stable snapshot record.
This is intentionally kept simple so facts can be buffered safely and so downstream observation logic stays pure.

To support moddability, record modules also expose **record extenders**:
- additive hooks (multi-mod safe),
- patchable-by-default entry points (other mods can register/unregister by id),
- fail-safe execution (an extender error should not break the fact stream).

This is the preferred way for 3rd party modders to add fields to records without needint to fork WorldObserver.

Record extenders exist in:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/squares/record.lua`
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/rooms/record.lua`
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/zombies/record.lua`
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/items/record.lua`
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/dead_bodies/record.lua`

Record extender usage doc:
- `docs/guides/extending_records.md`

### Observations layer (public streams)
Observation streams are thin wrappers over fact observables:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/observations/core.lua`
  - Registers stream builders, wraps schemas, attaches helper methods, ensures facts are started on subscribe.
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/observations/*.lua`
  - One per type (`squares`, `zombies`, `rooms`, `items`, `deadBodies`).

### Situations layer (named, parameterized stream factories)
Situation factories are a small registry that lets mods name and parameterize “situation streams” (subscribable streams that emit observations). Instead of carrying around the subscription to an observation stream (which in our domain counts as a situation), this allows user to access them via a registry when needed. 
This registry is lightweight and un-opinionated. The complexity of parameterization and “templating” is entirely up to the modder.

This is also the only "truly namespaced" part of WorldObserver.

Key file:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/situations/registry.lua`
  - Owns the in-memory registry, overwrite semantics, and the namespaced facade returned by `WorldObserver.situations.namespace("<modId>")`.

Important boundary notes:
- Situation factories do not declare interest; they are a packaging/reuse mechanism on top of `WorldObserver.observations:*` streams.
- For lifecycle safety, prefer factories that return an `ObservationStream` (or a derived stream built via `WorldObserver.observations:derive(...)`).
  - If you subscribe to the lower-level query directly, WorldObserver may not notice that you’re listening. That can lead to missing data (facts never start) or surprising “it stops when other subscribers stop” behavior, and you lose the “safe by default” lifecycle expectations.

### Helpers (stream helpers + safe engine access)
Helpers serve two roles:
1) Stream-level helper methods (used via `ObservationStream.__index` forwarding)
2) Safe wrapper utilities for Kahlua edge cases

Key files:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/helpers/safe_call.lua`
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/helpers/java_list.lua`
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/helpers/highlight.lua`
- Domain helpers: `square.lua`, `zombie.lua`, `room.lua`, `item.lua`, `dead_body.lua`

## 4) Fact sources (how we build them)

This section explains the upstream patterns we use to produce facts. The exact mix of sources per type is defined in
`Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/interest/definitions.lua:1` via scopes (the semantic “switch”),
but implementation-wise we mostly build sources using two techniques:

1) **Listeners (event-driven):** react to engine events and emit a record when something happens.
2) **Probes (active scans):** time-sliced loops that periodically inspect world state and emit records.

### 4.1 Listeners (event-driven)

Listeners are the best option when the game already informs us what happens in real time.
They must still be:
- **interest-gated** (no active lease → no work),
- **cheap** in the callback (build a small record and `ctx.ingest(record)`), and
- **stable-keyed** (the record must have a stable id so we can compact/dedup/cooldown downstream).

Example implementations:
- Squares `scope = "onLoad"`: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/squares/on_load.lua`
- Rooms `scope = "onSeeNewRoom"`: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/rooms/on_see_new_room.lua`

“Tick-derived listeners” are a common hybrid: we run a tiny per-tick check (cheap), but we emit only when the semantic value changes.
Example:
- Rooms `scope = "onPlayerChangeRoom"`: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/rooms/on_player_change_room.lua`

### 4.2 Probes (active scans)

Probes are for “the engine doesn’t tell us” cases. The key design constraints:
- they must be time-sliced (bounded work per tick),
- they must run inside the registry tick window (`FactRegistry:attachTickHook`) so runtime budgets can account for them, and
- interest settings should be honest about what they control:
  - **Best case:** a setting reduces *upstream probe cost* (less scanning per tick, or less scanning per second).
  - **Sometimes unavoidable:** a setting only reduces *emission volume* after scanning (we still do the scan, but we emit fewer records).

In other words: if a setting looks like a “performance setting”, try to make it actually reduce probe work; if it can’t, document that it’s “output-only”.

Concrete examples:
- Squares `near`/`vision` via `square_sweep`: smaller `radius` means fewer squares visited; larger `staleness` means the sweep can run less frequently.
- Zombies `allLoaded` (list probe): we still iterate the loaded zombie list; `radius` can make emissions leaner, but it does not automatically reduce the baseline scan cost unless we introduce a spatial index or a shared square-driven “drive-by” source.

Example:
- Rooms `scope = "allLoaded"` time-slices `getCell():getRoomList()`: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/rooms/probe.lua`
- Zombies `scope = "allLoaded"` iterates a loaded list (cheap enough to keep dedicated): `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/zombies/probe.lua`

### 4.3 Sensors + collectors (shared probes)

Some probe patterns are valuable across multiple fact types. In those cases we build a shared **sensor**:
- the sensor owns the expensive loop (e.g. “scan squares near/visible”),
- each fact type registers a **collector** callback that extracts type-specific facts from each scanned unit (e.g. “from this square, emit items”),
- all of it stays inside one time-sliced, budgeted driver so cost is shared and coordinated.

This is the pattern behind our `near`/`vision` scopes:
- Shared sensor: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/sensors/square_sweep.lua`
- Shared “ground entities” scaffolding (items + dead bodies collectors): `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/ground_entities.lua`

Why this matters:
- It prevents duplicated “square scanning” loops per type.
- It centralizes probe lag measurement and enables coordinated adaptation (interest policy + auto-budget).
- It provides one place to implement helpful debug tooling (e.g. square highlight overlays).

### 4.4 Stable IDs: why they matter (and when we get creative)

Every fact record needs a stable, non-colliding id for at least two reasons:
1) ingest compaction and cooldowns need a stable key (“same thing again”),
2) downstream queries (distinct/join/group) need stable keys to make sense over time.

Prefer engine-provided ids when they are stable and safe in Lua, but be prepared to derive ids when needed:
- Squares use `square:getID()` when available, otherwise derive a numeric id from coordinates:
  - `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/squares/record.lua:93`
- Rooms are a special case: engine ids can exceed Lua number precision, so we intentionally derive a string id from the first room square coordinates:
  - `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/rooms/record.lua:159`

Rule of thumb: if an id might be “big Java long” or unstable between sessions, derive a deterministic id from domain invariants (coords + z-level, objectID, etc.).

## 5) How to add/change things (recommended contributor workflows)

### Add a new fact type (new `WorldObserver.observations:<type>()`)
Typical checklist:
1) **Interest surface**
   - Add to `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/interest/definitions.lua`
   - Update `docs_internal/interest_combinations.md`
2) **Facts**
   - Add `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/<type>.lua`
   - Add record builder at `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/<type>/record.lua`
   - Choose fact source(s):
     - listener scope(s): `Events.*` listeners
     - probe scope(s): dedicated probes, or collectors on a shared sensor (prefer sensors for near/vision)
   - Register the type from `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver.lua`
   - Add config defaults in `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/config.lua`
3) **Observation stream**
   - Add `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/observations/<type>.lua`
   - Register it in `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver.lua`
4) **Helpers**
   - Add `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/helpers/<type>.lua` if the stream needs helper methods/predicates.
5) **Tests + smoke**
   - Add busted unit tests under `tests/unit/`
   - Add/extend an in-engine smoke script under `Contents/mods/WorldObserver/42/media/lua/shared/examples/`

### Add a new scope to an existing type
1) Add scope to `interest/definitions.lua`
2) Add driver code (listener/probe/collector) and gate it by effective interest
3) Update tests:
   - normalization/ignored settings (interest registry tests)
   - driver behavior (scope-specific tests)
4) Update docs:
   - user-facing: `docs/observations/<type>.md` and/or `docs/guides/interest.md`
   - internal: `docs_internal/interest_combinations.md` and logbook

## 6) Diagnostics and performance settings (where to look)

### Ingest / runtime budgets
- Global scheduler + buffers: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/registry.lua`
- Runtime controller: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/runtime.lua`

### Probe-level diagnostics (square sweep)
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/sensors/square_sweep.lua`
  - per-tick counters + optional collector fan-out logging
  - live override reading under the active “driver type”

User-facing debugging guide:
- `docs/guides/debugging_and_performance.md`

## 7) Testing and contracts

Headless test suite:
- Run `busted tests` (repo root).

Contract tests to keep public surfaces aligned:
- Interest definitions wiring: `tests/unit/interest_definitions_contract_spec.lua`
- Record extenders behavior: `tests/unit/record_extenders_spec.lua`

## 8) Known runtime constraints (Build 42 / Kahlua)

WorldObserver runs in:
- PZ’s Kahlua VM (engine)
- vanilla Lua 5.1 (busted tests)

Practical constraints:
- Some engine-backed values can throw on `tostring(...)` and can be non-indexable while still “present”.
  - Use `WorldObserver/helpers/java_list.lua` and `WorldObserver/helpers/safe_call.lua`.
- Avoid relying on `#table` for tables that may be sparse.
- Prefer `require("WorldObserver/path")` with slashes (no dot module paths).

## Questions (to align the doc with your intent)

1) Should this doc also include a “How to add a new sensor” section (beyond square sweep), or keep sensors as an implementation detail for now?
2) Do you want a stricter “one canonical pattern” for new types (e.g. *every* near/vision type must be a `square_sweep` collector), or should the doc stay descriptive (“choose the cheapest driver”)?
3) Should we explicitly document the small, intentional uses of metatables (FactRegistry instances + ObservationStream method lookup), or keep that out of the contributor narrative?
