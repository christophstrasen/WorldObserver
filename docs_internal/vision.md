# WorldObserver – Vision

WorldObserver is a new, LQR‑powered world observation layer for Lua‑based mods.
It supersedes the earlier WorldScanner experiments and is aimed squarely at
Lua‑coding mod authors (no GUI/config system on top).

The intent is to make it easy to **describe what you want to observe in the
game world** – spatially, logically, and over time – while pushing all the
looping, scanning, joining, and buffering work into a shared engine.

This document is aspirational by design: it describes where we want to go, not
necessarily what is implemented today.

---

## Goals

### delivers for beginner to intermediary lua modders

1. MUST provide a simple method to "subscribe" to pre-made "observations"
2. MUST make observing the world save and performant by default
3. SHOULD allow to further refine the observations
4. COULD provide visual or other debug vehicles to help understand and refine working with observations

### delivers for advanced lua mdders

1. MUST allow to create and ship custom and re-usable "observations"
2. SHOULD expose performance feedback from the system end2end
3. SHOULD provide knobs for automatic or semi-automatic optimization
4. COULD provide means to "inherit, modify and publish as new observations" as a way to design

## Audience and scope

- **Audience:** Lua‑coding Project Zomboid mod authors comfortable with tables,
  events, and basic control flow. Some familiarity with ReactiveX or the LQR
  docs is helpful but not required.
- **Scope:** in‑process, single‑player or server‑side logic that needs to watch
  the world (squares, rooms, vehicles, etc.) and react to patterns over time.
- **Out of scope:** no GUI builder, no on‑disk query language, no visual editor.
  The primary interface is Lua code.

If you have not yet read it, the LQR docs in `docs/` provides the
underlying vocabulary (records, schemas, joins, windows) that WorldObserver
will lean on.

---

## Before: how mods observe the world today

When a typical Project Zomboid mod wants to “watch the world”, the lifecycle
today usually looks something like this (for a single feature or concern):

1. **Hook into events and ticks**
   - Register handlers on `Events.OnTick`, `OnPlayerUpdate` etc.
     or custom timers; maybe add counters to avoid doing work every tick.
   - **LoC:** ~10–30 per feature (basic event registration and guards).
   - **Complexity:** low–medium – conceptually simple, but spread over multiple
     files and game events.
   - **Risk:** medium – easy to leak handlers, run too often, or attach to the
     wrong event and miss edge cases.

2. **Scan tiles, rooms, and objects manually**
   - Walk tiles around players or known coords with nested `for` loops; query
     rooms, buildings, containers, items, corpses, vehicles, etc.
   - **LoC:** ~30–100 per major scan (loops, bounds checks, filters).
   - **Complexity:** medium–high – lots of branching and special cases,
     especially once multiple filters stack up.
   - **Risk:** high – off‑by‑one ranges, scanning too much too often, or
     forgetting to short‑circuit can hurt performance and correctness.

3. **Maintain ad‑hoc caches and state**
   - Track visited squares/rooms/entities in Lua tables; implement cooldowns
     (“only once per room per N ticks”), deduplication, and invalidation.
   - **LoC:** ~20–60 per feature (state tables, update functions, cleanup).
   - **Complexity:** high – implicit state machines grow over time and are
     hard to reason about once multiple concerns share the same tables.
   - **Risk:** high – stale state, memory leaks, or missed updates when world
     conditions change (e.g. room layout, save/load).

4. **Correlate conditions by hand**
   - Combine separate facts – “is kitchen”, “has corpse”, “near player”,
     “not yet handled” – using custom IDs, lookups, and join logic.
   - **LoC:** ~20–50 per combined condition (glue code and helper functions).
   - **Complexity:** medium–high – mental join logic is spread across event
     handlers and helper utilities.
   - **Risk:** high – easy to miss corner cases when conditions need to be
     evaluated over time (enter/leave, expiry, race‑y updates).

5. **Trigger side‑effects and persistence**
   - Fire mod logic, spawn entities, update overlays, and write to mod save
     data when conditions are met; try to keep everything idempotent.
   - **LoC:** ~20–80 per feature (callbacks, guards, save/load hooks).
   - **Complexity:** medium – business logic itself may be simple, but it sits
     on top of fragile observation code.
   - **Risk:** medium–high – double‑fires, missed triggers, or inconsistent
     save/load behavior if observation state and side‑effects drift apart.

6. **Debug and tune by trial and error**
   - Add `print` spam, ad‑hoc debug UIs, or temporary overlays; tweak radii,
     tick intervals, and cache sizes to keep FPS acceptable.
   - **LoC:** ~10–40 per debug pass (logging flags, temporary code paths).
   - **Complexity:** medium – debugging crosses all the layers above and often
     has to be repeated for each new feature.
   - **Risk:** medium – debug code accidentally ships, or performance problems
     only show up under load or on servers.

These numbers are rough orders of magnitude, but they highlight a pattern:
each mod re‑implements a small “world observation framework” by hand, with
non‑trivial code, complexity, and risk concentrated in scanning, state, and
correlation.

---

## Why WorldObserver (and why it replaces WorldScanner)

The older WorldScanner ideas already captured something important:

- lots of mods reinvent the same “scan the world” loops;
- ad‑hoc `OnTick` search code tends to grow messy and hard to test; and
- many tasks boil down to “watch for situations” rather than “run one search”.

WorldObserver keeps that spirit but changes the foundation:

- **From bespoke loops to declarative observers.**  
  Instead of writing your own `Events.OnTick` loops or one‑off `WorldFinder`‑style
  routines, you describe *observers* that stay mounted and emit structured
  world contexts as the game runs.

- **From single‑purpose scanners to shared streams.**  
  A single world observation (e.g. “nearby squares around the player”) can feed
  many consumers: story logic, PromiseKeeper, overlays, debugging tools – all
  without duplicating the scan.

- **From hand‑rolled timing to explicit windows and joins.**  
  Time and correlation are first‑class concepts instead of hidden timers and
  state in scattered tables.

In other words, WorldObserver is the “second generation” of the WorldScanner
idea, rebuilt explicitly on top of LQR and lua‑reactivex instead of a
home‑grown query DSL.

---

## Core idea: describe observers, not loops

WorldObserver is built around a single concept:

> **An observer is a named, reusable query over world events and contexts.**

Observers are:

- **Named:** they have stable identifiers (e.g. `"observer.kitchenSquares"`).
- **Schema‑aware:** they deal in typed contexts like `SquareCtx`, `RoomCtx`,
  `VehicleCtx`, mapped onto LQR schemas.
- **Incremental:** once mounted, they keep emitting as the world and players
  change.
- **Combinable:** you can join and filter observers to describe more complex
  conditions without re‑implementing scans.

What you *do not* write:

- raw `for` loops over the entire map every frame;
- per‑mod “mini frameworks” to manage `OnTick` batching and cancellation; or
- ad‑hoc join logic between “has corpse”, “is kitchen”, “is safe spot”, etc.

Instead you build or reuse observers that encode those concerns once.

---

## Mental model: world contexts as LQR records

WorldObserver treats world events as **LQR records** tagged by schema:

- `SquareCtx` schema: emitted for grid squares (e.g. from “nearby squares”
  scanners, `LoadGridsquare` hooks, or async sweeps).
- `RoomCtx` schema: emitted for rooms (e.g. from building/room enumeration).
- Future schemas: vehicles, containers, “has corpse” flags, nav regions, etc.

Each record:

- has a stable key (`squareId`, `roomId`, `vehicleId`, …);
- carries a minimal, well‑defined payload; and
- has metadata (source time, origin scanner, etc.) suitable for joins/windows.

LQR then provides:

- **joins** (`inner`, `left`, `anti*`, `outer`) across those schemas;
- **windows** in time or count (“within 5 seconds”, “last N events per id”);
- **grouping and distinct** for aggregates or deduplication; and
- **expiration streams** so you can reason about “too late” or “never matched”.

WorldObserver’s job is to:

1. turn game events and scans into these schema‑tagged records; and  
2. expose ready‑to‑use observers (LQR queries) that mod authors can subscribe to
   or build upon.

---

## Responsibilities of WorldObserver

At a high level, WorldObserver should:

- **Provide reusable world feeds.**  
  Core, well‑tested observers for common needs, e.g.:
  - “nearby squares around player(s) with configurable radius and filters”;
  - “rooms by name and distance, with async batching handled for you”;
  - “candidate vehicle spawn sections” similar to `WorldFinder` but as streams;
  - “interesting events” like corpses, fires, lootable containers, etc.

- **Expose a clean Lua API for mod authors.**  
  Example shapes (names subject to change):
  - `WorldObserver.onSquare("nearby", opts, callback)`  
  - `WorldObserver.observeRooms(opts) --> subscription`  
  - `WorldObserver.buildObserver(opts) --> observerHandle`  
  Under the hood these map onto LQR queries; the surface stays world‑centric.

- **Handle lifecycle and backpressure at the engine level.**  
  Observers can be started/stopped, and they should:
  - batch heavy scans over multiple frames;
  - limit memory via windows and per‑key caches (LQR retention);
  - cooperate with the game loop rather than blocking it.

- **Reuse LQR infrastructure.**  
  Instead of reinventing pieces, WorldObserver should:
  - use LQR’s logging conventions and log levels;
  - be covered by busted tests in the same style as LQR;
  - ship internal design notes under `raw_internal_docs/` for maintainers; and
  - have user‑facing docs under `docs/` alongside the rest of LQR.

---

## Relationship to LQR

WorldObserver has a **hard dependency** on LQR and lua‑reactivex.

Conceptually:

- **LQR is the engine.**  
  It knows how to join, window, group, dedupe, and expire streams of records.

- **WorldObserver is the domain skin.**  
  It:
  - defines world schemas and keys (`SquareCtx`, `RoomCtx`, …);
  - turns PZ/engine events into LQR‑friendly record streams;
  - publishes ready‑made queries as named observers; and
  - offers extension points for mod authors to define their own observers.

For most mod authors, **WorldObserver is the primary entry point**:

- they import `WorldObserver` and use its functions;
- they do not need to know LQR internals;  
  (though advanced users can reach into LQR when needed).

Advanced users may:

- fetch the underlying LQR observable or builder for an observer;
- compose additional joins or `where` clauses on top; or
- feed non‑world schemas into the same engine.

---

## Non‑goals and boundaries

WorldObserver is intentionally **not**:

- a visual query builder, GUI, or DSL for non‑coders;
- a general ECS or persistence layer;
- a replacement for every use of plain Rx – simple one‑stream tasks can still
  use bare lua‑reactivex directly;
- a guarantee of perfect completeness in every scenario (some observers will be
  best‑effort, time/window‑bounded by design).

The aim is to make the *common hard things* (world scanning, correlation, and
time‑bound patterns) easy and consistent, while staying honest about trade‑offs.

---

## A taste of intended usage (illustrative only)

The exact API will evolve, but the intended feel is:

```lua
local WorldObserver = require("WorldObserver")

-- 1) Use a built‑in observer: nearby kitchens with corpses, within 50 tiles.
local subscription = WorldObserver.observe({
  squareRadius = 50,
  roomName = "kitchen",
  requireCorpse = true,
}):subscribe(function(ctx)
  -- ctx might carry square, room, and extra tags
  WorldObserver.visuals.highlightSquare(ctx.square, "danger")
end)

-- 2) Advanced: get the underlying LQR query and extend it.
local query = WorldObserver.getQuery("observer.kitchenWithCorpse")

query
  :where(function(row)
    -- only keep events where the room is residential
    local room = row.room
    return room and room.isResidential
  end)
  :subscribe(function(row)
    -- do something game‑specific here
  end)
```

This is only a sketch, but it is the style of code WorldObserver is meant to
encourage: **describe what you want to observe**, let the engine handle the
heavy lifting, and focus your mod logic on the resulting contexts.
