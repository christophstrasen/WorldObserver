# Fact layer – current design + implementation notes

Internal notes on how WorldObserver generates **Facts** (engine events, probes, LuaEvents) and turns them into
ObservationStreams.

This file used to be a pure design draft. It is now updated to reflect the current implementation reality, while
still capturing the longer-term direction.

Related docs:
- Vision: `docs_internal/vision.md`
- Ingest integration plan: `docs_internal/using_ingest_system.md`
- LQR ingest docs: `external/LQR/docs/concepts/ingest_buffering.md`
- Fact interest declarations (design brief): `docs_internal/fact_interest.md`

---

## 1. Purpose and scope

- Own world-level fact generation (squares, rooms, zombies, vehicles, …) so mods do not wire engine events directly.
- Keep fact production predictable and budgeted so downstream LQR work does not run inside bursty engine callbacks.
- Feed base ObservationStreams with stable, schema-tagged observation records.

---

## 2. Current implementation overview

### 2.1 Entry points (code locations)

- Public wiring: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver.lua`
- Fact registry: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/registry.lua`
- Squares facts: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/squares.lua`
- Base squares observation stream: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/observations/squares.lua`

### 2.2 Lifecycle: lazy start on first subscription

- Fact types are registered at startup (currently only `squares`).
- Fact producers start lazily when the first ObservationStream subscribes (`FactRegistry:onSubscribe(...)`).
- Fact producers stop when the last subscriber unsubscribes.
  - If a type cannot fully unregister its handlers (missing `Remove`), it may return `false` from `stop()` so the
    registry keeps it “started” and does not double-register callbacks on later subscriptions.

---

## 3. Ingest boundary (new reality)

WorldObserver now uses `LQR/ingest` as the “admission control” layer *before* schemas and queries.

### 3.1 Per-type buffers + one global scheduler

- Each fact type may enable ingest buffering via config at `WorldObserver.config.facts.<type>.ingest`.
- When enabled, the registry creates one `Ingest.buffer` for that type and attaches it to one global
  `Ingest.scheduler` (`WorldObserver.factScheduler`).
- The scheduler is drained on `Events.OnTick` with a global budget (`WorldObserver.config.ingest.scheduler.maxItemsPerTick`).
- Buffers with the same priority are drained round-robin (no starvation).

### 3.2 The important rule

- Event listeners and probes should **ingest**, not emit:
  - `ctx.ingest(record)` is cheap and safe to call inside bursty callbacks.
  - Drain emits into the Rx subject on tick, so downstream LQR work happens in a controlled cadence.

### 3.3 Producer context API (what listeners/probes call)

When a fact type starts, its `start(ctx)` receives a small context with these stable fields:

- `ctx.config`: per-type config table (`WorldObserver.config.facts.<type>`).
- `ctx.state`: per-type mutable state table (used to remember handler functions, cursors, etc.).
- `ctx.ingest(record)`: the *normal* entry point for high-frequency/bursty producers.
  - If ingest is enabled for the type, this enqueues into the type’s `Ingest.buffer` and is emitted later during tick drain.
  - If ingest is disabled, this falls back to immediate emission (same behavior as `ctx.emit`).
- `ctx.emit(record)`: immediate emission into the type’s Rx subject (bypasses buffering).
  - Use this only for low-frequency “already budgeted” producers or for tests; it defeats backpressure when used in event callbacks.

---

## 4. Event listeners (engine callbacks)

Event listeners:
- subscribe to engine events (example: `Events.LoadGridsquare`);
- shape payloads into stable records (ids + timestamps + small primitive fields); and
- call `ctx.ingest(record)`.

Current squares behavior:
- `Events.LoadGridsquare` is **interest-controlled** and only enabled when at least one mod declares
  `type = "squares.onLoad"` (cooldown-only shape; no radius/staleness).

Important design note:
- We intentionally avoid buffering live game objects.
  Today, square facts store coords + derived flags, not `IsoGridSquare` references.

---

## 5. Active probes (periodic scans)

Probes initiate scans when events are insufficient or when periodic reconfirmation is required.

Current reality (MVP):
- Probes are not centrally scheduled as a generic system yet.
- The squares probe runs a time-sliced “electron-beam” cursor sweep on `Events.OnTick`.
  It scans **as fast as it can within the per-tick budget**, then waits until the next sweep is due by `staleness`.
  It is bounded by:
  - `WorldObserver.config.facts.squares.probe.maxMillisPerTick` (soft CPU-time budget per tick)
  - `WorldObserver.config.facts.squares.probe.maxPerRun` (hard cap per tick as a safety net)

Probes ingest into the same type buffer as event listeners, but typically in a different lane so we can express bias.

---

## 6. Lanes, bias, and priorities (within a type)

Within a type buffer, we classify work by “lane” to express bias between sources:

- `"event"`: engine callbacks (can be bursty and include far-edge chunk loads)
- `"probe"`: near-player sampling/reconfirmation
- `"luaevent"`: planned cross-mod signals

Current squares policy:
- `lanePriority("probe") > lanePriority("event")` so that “near-player reconfirmation” can win over chunk-load bursts.

Lane priorities are a domain decision and may differ by type.

---

## 7. Configuration (runtime + interest)

- Ingest and drain are controlled via config knobs:
  - `WorldObserver.config.ingest.scheduler.maxItemsPerTick`
  - `WorldObserver.config.ingest.scheduler.quantum`
  - `WorldObserver.config.facts.squares.ingest.*`
  - `WorldObserver.config.facts.squares.probe.*` (safety caps)
- Probe intensity is now shaped by **interest declarations** (`staleness`, `radius`, `cooldown`) merged across mods,
  then passed through the runtime-aware policy (see `WorldObserver/interest/policy.lua`).
  The old `strategy` preset knob has been removed in favor of explicit interest + policy.

---

## 8. From facts to ObservationStreams

Base ObservationStreams wrap facts into schemas and then feed LQR queries.

Important: with ingest enabled, facts are emitted on tick drain, so LQR work stays out of event callbacks.

---

## 9. Debugging and observability

WorldObserver exposes minimal debug helpers:

- `WorldObserver.debug.describeFactsMetrics("<type>")` prints ingest-buffer health
  (pending, drops, load average, throughput, ingest rate).
- `WorldObserver.debug.describeIngestScheduler()` prints scheduler totals.

These are intentionally lightweight and expected to evolve as we learn what modders need.

---

## 10. External LuaEvent fact sources (planned)

We still intend to support cross-mod facts via LuaEvents, but they must route through ingest:

- LuaEvent handler ingests into the appropriate type buffer (lane `"luaevent"`).
- The same global scheduler budget applies, so external bursts cannot bypass backpressure.

---

## 11. Gaps and next steps

- Make probes a first-class “plan” concept (shared scheduling patterns, per-probe budgets, subscriber-aware behavior).
- Add interest declarations (leases) so mods can collectively shape probe intensity under a global budget.
- Add more fact types (`zombies`, `vehicles`, …) and attach them to the same global scheduler budget.
- Improve teardown/unregister story for event handlers where PZ supports removal.
- Validate in-engine (FPS stability + bounded backlog) and tune default budgets/caps based on observed load.
