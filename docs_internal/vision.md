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
2. MUST make observing the world safe and performant by default
3. SHOULD allow to further refine the observations
4. COULD provide visual or other debug vehicles to help understand and refine working with observations

### delivers for advanced lua modders

5. MUST allow to create and ship custom and re-usable "observations"
6. SHOULD expose performance feedback from the system end2end
7. SHOULD provide knobs for automatic or semi-automatic optimization
8. COULD provide means to "inherit, modify and publish as new observations" as a way to design

## Audience and scope

- **Audience:** Lua‑coding Project Zomboid mod authors comfortable with tables,
  events, and basic control flow. Some familiarity with ReactiveX or the LQR
  docs is helpful but not required.
- **Scope:** in‑process, single‑player or server‑side logic that needs to watch
  the world (squares, rooms, vehicles, etc.) and react to patterns over time.
- **Out of scope:** no GUI builder, no on‑disk query language, no visual editor.
  The primary interface is Lua code.

---

## Core concepts

These high‑level terms describe how WorldObserver thinks about the game world:

### Fact

Anything that currently is or has been true in the world. E.g. a floor square having blood on it over a period of time.

Implemented by:

#### Event Listener

Event listeners hook into the game’s own event loop (`OnTick`, `OnPlayerMove`,
`OnContainerUpdate`, etc.) or into custom events and carve facts out of whatever
these events surface. Their job is to shape and filter the incoming events into the
smallest useful set of facts, while respecting cost and not missing anything
that must be seen.

#### Active Probe

Active probes initiate their own scans over world state when no suitable event
exists or when periodic reconfirmation is needed. Their job is to decide where,
how intensely, and in which order to “shine a light” onto the world state so
that important facts are discovered in time without overwhelming the game
loop. In practice, probes are registered with a central tick‑based scheduler,
which calls them with a per‑tick budget and can start or stop them on demand.

### Observation

A concrete “noted” observation of a fact, carried as a record in an observable stream, often with the time of observation attached.
The same fact may be observed many times with each observation being its own event with typically no hard guarantees about order and completness.

Implemented by:

#### Base ObservationStreams

Base ObservationStreams are live, world‑centric streams fed by per‑type fact
plans: combinations of Event Listeners and Active Probes that turn Facts into
observations. They hold observations as data
points in stable schemas for things like squares, rooms, vehicles, and corpses,
not the game objects themselves.

#### Derived ObservationStreams

Derived ObservationStreams are structurally identical to base streams, but are
built from one or more existing streams into higher‑level streams that combine
or refine observations. Internally this is typically expressed as LQR queries,
but they still only describe what has been observed. For example, they can
represent “squares within N tiles of any player” or
“rooms that currently contain zombies”, without yet declaring that these facts
are important or should trigger actions.

### Situation

When observations line up to show something interesting about the world, from a single simple check to a complex pattern across many observations over time.

A Situation is when one or more ObservationStreams are treated as “interesting
enough to care about” and wired up as candidates to trigger Actions. The same underlying streams are
used; what changes is the intent and how other code reacts to them. WorldObserver may
later grow dedicated APIs or types for situations, but for now the distinction
is conceptual rather than a separate implementation layer.
@TODO mention the LQR/reactivex :subscribe

### Action

What the mod author decides to do when a situation occurs
(gameplay logic, UI changes, persistence, and so on).

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

---

## Core idea: describe what to observe, not loops

WorldObserver’s core idea is simple:

> **Describe the facts and situations you care about; do not hand‑roll loops.**

Instead of:

- wiring your own `OnTick` handlers and tile scans;
- inventing per‑mod mini‑frameworks for batching and cancellation; or
- re‑implementing ad‑hoc join logic between “has corpse”, “is kitchen”, “near player”, and so on,

you:

- rely on shared **Facts** surfaced via Event Listeners and Active Probes;
- subscribe to **ObservationStreams** that describe what has been observed about squares, rooms, vehicles, and other world elements; and
- define **Situations** by saying which ObservationStreams matter to you and how they should drive Actions.

The goal is that most mods never need to think in terms of loops and caches at all, only in terms of “what should we observe?” and “when does it matter?”.

---

## Mental model: facts, observations, and streams

At a high level, WorldObserver sits between the game and your mod:

- **Facts** are what is or has been true in the world, surfaced via Event Listeners and Active Probes.
- **Observations** are concrete, typed representations of those facts.
- **ObservationStreams** are the live flows of observations that mods subscribe to and build Situations from.

Internally, each Observation is an LQR record that belongs to a schema such as `SquareObs`, `RoomObs`, or future schemas for vehicles, containers, and so on. These records:

- have stable keys (for example `squareId`, `roomId`, `vehicleId`);
- carry a minimal, well‑defined payload; and
- include metadata such as when and how the fact was observed.

LQR then provides the machinery to transform ObservationStreams: combining them, narrowing them, and looking at them over time. WorldObserver uses that machinery to:

1. turn Facts (from listeners and probes) into schema‑tagged Observations; and  
2. expose base and derived ObservationStreams that mod authors can subscribe to or build Situations on top of, without needing to think about LQR directly.

### Fact strategies

WorldObserver owns the primary strategies for generating Facts. For each
world element (squares, rooms, etc.) it decides how to combine Event
Listeners (e.g. load events) and Active Probes (periodic or focused scans) to
balance freshness and completeness within a performance budget. Typical
strategies might mix frequent, small probes near players with less frequent,
wider sweeps and always‑on engine events. Mod authors see the resulting
ObservationStreams, not the underlying strategy; changing these strategies is
an advanced, opt‑in configuration rather than part of everyday usage.

### LQR windows in WorldObserver

WorldObserver uses LQR’s join, group, and distinct windows internally when
building ObservationStreams and helpers. Join windows bound how long records
stay join‑eligible, group windows define over which slice of time/rows
aggregates are computed, and distinct windows govern how long keys are
remembered for de‑duplication. These knobs live inside built‑in streams and
helpers (for example, “once per square” or “rooms with recent zombies”) and
are not part of normal everyday API usage. Advanced users can still drop down to raw LQR builders when they need full control.

---

## Responsibilities of WorldObserver

At a high level, WorldObserver should:

- **Own fact generation and strategies.**  
  Define and run per‑type fact plans (Event Listeners + Active Probes +
  external sources such as LuaEvents) that keep core world Facts fresh within
  a performance budget. Expose only a small, semantic config surface for
  strategies (for example `WorldObserver.config.facts.squares.strategy`),
  while keeping detailed scheduling and throttling internal.

- **Publish reusable ObservationStreams.**  
  Provide a stable set of base ObservationStreams under
  `WorldObserver.observations.<name>()` (for example `squares()`, `rooms()`,
  `zombies()`, `vehicles()`, and selected cross‑mod streams like
  `roomStatus()`), each carrying schema‑tagged observations over time.

- **Provide helper‑driven refinement, not ad‑hoc loops.**  
  Offer small, semantic helper sets (spatial, square, room, zombie, vehicle,
  time, …) that filter, de‑duplicate, or reshape observations without
  introducing new sources. Mod‑facing code chains helpers on top of
  ObservationStreams instead of wiring `OnTick` loops or manual joins.

- **Manage lifecycle and backpressure at the engine level.**  
  Start and stop fact plans and probes based on demand (subscriptions and
  strategies), batch heavy work over multiple frames, and cooperate with the
  game loop to keep CPU and memory usage predictable. ObservationStreams stay
  “just streams”; pacing and budgets live in the fact layer and scheduler.

- **Integrate cleanly with LQR and lua‑reactivex.**  
  Build ObservationStreams on top of LQR queries and lua‑reactivex
  observables, reuse LQR’s windowing primitives internally, and expose
  `stream:getLQR()` as the escape hatch for advanced users who need full
  control.

- **Support extension and customization.**  
  Let advanced users register additional ObservationStreams via
  `WorldObserver.observations.register(...)` and, where appropriate, add new
  fact types through the fact layer APIs. Custom streams plug into the same
  helper sets, subscribe semantics, and fact infrastructure as built‑ins.

- **Provide diagnostics and documentation.**  
  Reuse LQR’s logging conventions, surface WorldObserver‑specific categories
  (e.g. facts, streams, errors), and grow light‑weight debugging helpers
  (such as `describeFacts` / `describeStream`). Keep internal design notes
  under `docs_internal/` and user‑facing guides under `docs/`.

---

## Relationship to LQR

WorldObserver has a **hard dependency** on LQR and lua‑reactivex.

Conceptually:

- **LQR is the engine.**  
  It knows how to join, window, group, dedupe, and expire streams of records.

- **WorldObserver is the domain skin.**  
  It:
  
  - defines world schemas and keys (for example `SquareObs`, `RoomObs`, …);
  - turns PZ/engine events and other fact sources into LQR‑friendly record streams;
  - publishes ready‑made base ObservationStreams such as `WorldObserver.observations.squares()` or `WorldObserver.observations.rooms()`; and
  - offers extension points, via the fact layer APIs, for mod authors to define their own facts and ObservationStreams on top.

For most mod authors, **WorldObserver is the primary entry point**:

- they import `WorldObserver` and use its functions;
- they do not need to know LQR internals;  
  (though advanced users can reach into LQR when needed).

Advanced users may:

- fetch the underlying LQR observable or builder for an ObservationStream;
- compose additional joins or `where` clauses on top; or
- feed non‑world schemas into the same engine.

---

## Non‑goals and boundaries

WorldObserver is intentionally **not**:

- a visual query builder, GUI, or DSL for non‑coders;
- a general ECS or persistence layer;
- a replacement for every use of plain Rx – simple one‑stream tasks can still
  use bare lua‑reactivex directly;
- a guarantee of perfect completeness in every scenario (some ObservationStreams
  will be best‑effort, time/window‑bounded by design).

The aim is to make the *common hard things* (world scanning, correlation, and
time‑bound patterns) easy and consistent, while staying honest about trade‑offs.

---

## Dependencies to use

- LQR https://github.com/christophstrasen/LQR
- Lua Reactivex https://github.com/christophstrasen/lua-reactivex 
- LuaEvent https://github.com/demiurgeQuantified/StarlitLibrary/blob/main/Contents/mods/StarlitLibrary/42/media/lua/shared/Starlit/LuaEvent.lua 
