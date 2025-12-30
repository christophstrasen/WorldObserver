# Using `LQR/ingest` in WorldObserver (implementation plan)

> **Stage:** Proposal & design

This document is the implementation plan for integrating the new `LQR/ingest` system into WorldObserver’s fact layer.

Related docs:
- WorldObserver fact layer design: `docs_internal/fact_layer.md`
- WorldObserver vision: `docs_internal/vision.md`
- LQR ingest user docs: `external/LQR/docs/concepts/ingest_buffering.md`
- LQR ingest internal briefing: `external/LQR/LQR/raw_internal_docs/IngressBuffer.md`

---

## 1. Why this change

WorldObserver currently emits fact records directly into Rx streams from inside engine event callbacks.
That makes downstream work bursty and unpredictable (schema wrapping, joins, user callbacks), especially for events like `Events.LoadGridsquare` that may fire in large chunks.

`LQR/ingest` gives us a host-friendly boundary:

1. **Ingest** (cheap, in the event handler)
2. **Buffer** (bounded memory, explicit compaction/overflow)
3. **Drain** (budgeted work per tick)

This moves “expensive work” to a controlled cadence and makes overload behavior explicit and observable.

---

## 2. Updated responsibilities (WorldObserver vs. LQR)

### LQR owns (mechanics)
- Bounded buffering, compaction modes, overflow eviction, lane priority, and fairness within a buffer.
- Cross-buffer budget sharing via `Ingest.scheduler` (including round-robin among same-priority buffers).
- Metrics + advice (`metrics_get`, load-style averages, `advice_get`).

### WorldObserver (domain) owns (semantics + wiring)
- What a “fact item” means, and what is safe to compact/drop per schema.
- How items are keyed (`key(item)`), how they are classified (`lane(item)`), and lane priorities.
- Which buffers exist (typically per schema / per fact type).
- How draining routes items into the appropriate fact stream(s).
- Strategy mapping: which budgets, priorities, and buffer settings correspond to `balanced/gentle/intense`.

---

## 3. Target architecture (v1)

### 3.1 Per-type buffers + one global scheduler (recommended default)

- Each fact type/schema (e.g. `squares`, `zombies`) owns one `Ingest.buffer`.
- All ingestion methods for that type (engine listeners, external LuaEvents, probes) feed that same buffer as different **lanes**.
- A single, global `Ingest.scheduler` is drained on `Events.OnTick`, enforcing a global `maxItemsPerTick`.
- Buffers of the same scheduler priority are drained round-robin to avoid starvation.

This keeps per-schema semantics clean (mode/key/capacity/hook behavior are per type), while still giving “one shared budget” across the entire mod.

### 3.2 Lanes represent intake methods (domain-defined)

Within a buffer, lane names should encode “what kind of work this is”, not the schema:

- `"event"` (engine callbacks)
- `"probe"` (active scan work)
- `"luaevent"` (cross-mod signals)
- optionally `"urgent"` / `"background"` (if needed later)

Lane priorities express bias within one schema (e.g. squares event > squares probe).

### 3.3 Important v1 rule: drain emits, ingest does not

- Event handler: only `buffer:ingest(item)` (cheap).
- Tick: `buffer:drain({ maxItems = ..., handle = function(item) factSubject:onNext(item) end })`.

This ensures queries and subscriber callbacks do not run inside engine event callbacks.

---

## 4. Data shape: what do we buffer?

### 4.1 Prefer buffering lightweight “work items”

WorldObserver’s vision states that base streams should carry stable data records, not live game objects.
Buffering makes this more important, because buffered items can live longer than an event callback.

Recommended default:
- Buffer **lightweight** items (ids/coords + small primitive fields + timestamps + source lane).
- Perform expensive lookups/materialization at drain-time only when needed.

If we temporarily buffer objects (e.g. `IsoGridSquare`), we should treat that as an MVP compromise and document the risk.

### 4.2 Record materialization at drain-time but powerful so we want to do this

For some facts, ingest can buffer only a key (or key + minimal metadata), and drain-time builds the final record:

- Ingest: `{ squareId = ..., x = ..., y = ..., z = ..., source = "event", sourceTime = ... }`
- Drain: attach derived fields and/or validate invariants, then emit to the fact stream

This keeps the event path minimal and avoids doing heavy work under bursts.

---

## 5. Implementation steps (recommended order)

### Step 1 — Wire ingest into `FactRegistry` (infrastructure)

Goal: make it possible for any fact type to opt into ingest buffering without rewriting every fact file.

Proposed changes (high-level):
- Extend `WorldObserver/facts/registry.lua` to support an optional `ingest` config block per type:
  - create `entry.buffer` when type starts
  - create/register one global scheduler once (owned by the registry)
  - ensure one `Events.OnTick` drain hook exists and drains the scheduler
- Extend the context given to `opts.start(ctx)`:
  - `ctx.ingest(item)` (preferred) routes to `entry.buffer:ingest(item)`
  - `ctx.emit(item)` remains available but becomes “drain-time emit” (or a legacy escape hatch), depending on migration phase

Deliverable: no behavioral change until a fact type enables ingest.

### Step 2 — Migrate one fact type: `squares`

Goal: reduce `LoadGridsquare` bursts and stop downstream queries from executing inside the event handler.

Suggested mapping:
- squares buffer:
  - `mode = "latestByKey"` (square updates collapse, “latest state per square”)
  - `key = function(item) return item.squareId end`
  - `lane = function(item) return item.source or "default" end`
  - `lanePriority("probe") > lanePriority("event")` (when probes return) because spikes from square events were quite large and those squares are far at the edge of the users world (assuming chunk loading)
  - `ordering = "fifo"` (for more predictable processing order under bursts)
- drain:
  - emits drained square records into the existing Rx subject so `Schema.wrap` + queries stay unchanged
 - data shape:
   - ingest stores lightweight records only (ids/coords/flags/timestamp/source), no live `IsoGridSquare` objects
   - probe runs time-sliced on `Events.OnTick` (cursor sweep) to avoid frame hitching on larger radii
   - probe is bounded by `WorldObserver.config.facts.squares.probe.maxMillisPerTick` (ms budget per tick)
     and `WorldObserver.config.facts.squares.probe.maxPerRun` (hard cap per tick)
   - global scheduler budget and quantum via `WorldObserver.config.ingest.scheduler`

Deliverable: `examples/smoke_squares.lua` remains functional but should stop causing burst-driven lag.

Config settings (current default):
```lua
WorldObserver.config.facts.squares.probe = {
  enabled = true,
  maxPerRun = 50, -- hard cap per OnTick slice
  maxMillisPerTick = 0.75, -- probe CPU-ms per tick
}
WorldObserver.config.ingest.scheduler = {
  maxItemsPerTick = 10,
  quantum = 1,
}
```

### Step 3 — Observability + debug surfaces

Goal: make it easy for users (and us) to see what WorldObserver is doing.

Add in `WorldObserver/debug.lua`:
- `describeFacts("squares")` should show:
  - whether the type is registered and started
  - buffer metrics snapshot (pending, drops, load averages, ingestRate vs throughput)
  - last drain stats

### Step 4 — Re-introduce probes under budgets

Goal: probes must be “budgeted work” just like draining is.

Initial approach:
- Probe loops ingest work items into the buffer (lane `"probe"`).
- The first probe we do run in slow intervals and only consideres squares in a 5x5 grid around the player
- Probe itself uses its own per-tick limit (cheap) so it doesn’t create an unbounded backlog.
- The global scheduler/drain budget remains the hard backpressure boundary.

### Step 5 — External LuaEvent sources

Goal: cross-mod bursts should not bypass backpressure.

Approach:
- LuaEvent handler ingests into the relevant buffer (lane `"luaevent"`).
- Same budget and observability as other sources.

---

## 6. Configuration surface (initial proposal)

WorldObserver should expose a small config that maps strategies to budgets.
We can start with “internal settings” and later publish a stable public surface.

Proposed config shape (illustrative):

```lua
WorldObserver.config.facts.squares = {
  strategy = "balanced",
  ingest = {
    enabled = true,
    mode = "latestByKey",
    capacity = 5000,
    ordering = "fifo",
  },
}

WorldObserver.config.ingest = {
  scheduler = {
    maxItemsPerTick = 200,
    quantum = 1,
  },
}
```

We should keep this minimal until we learn what modders actually need.

---

## 7. Tests and validation

Minimum confidence gates:
- WorldObserver unit tests: `busted tests`
- Loader smoke tests: `./dev/sync-workshop.sh` + `SOURCE=workshop ./dev/smoke.sh` (runs `pz_smoke.lua`)
- In-engine smoke: run `examples/smoke_squares.lua` and confirm:
  - no runaway CPU usage when moving and revealing new squares
  - logs show stable drain behavior (pending not unbounded; throughput keeps up)

---

## 8. Open questions / pending decisions

### Scheduling and fairness
- Do we eventually need weighted fairness between buffers (not just strict RR by priority)?
  - Answer: Not now
- Do we want a separate “probe ingest budget” vs “drain budget”, or is “probe uses its own small cap” enough?
  - Answer:For now a probe having its own internal, "hard coded" if you will, budget is a good starting point. Later we may introduce probing strategies as this is something that we _can_ control opposed to events that simply come

### Data model
- Do we enforce “no live game objects in facts” (hard rule), or allow it as MVP but mark it “unsafe”?
  - Answer: We don't do anything there. Even a lua table reference is cheap I think.
- Do we want standardized drain-time materializers per type (key → record), and if so where do they live?
  - Answer: Yes we should have one per type. I don't have a strong opinion where they should live but I guess either in facts/squares.lua or in observations/squares.lua . In any case, the method needs to be "patchable" by modders ideally (no need for us to provide extra easy methods there, but at least not hide it behind `local`).

### Budget adaptation
- Do we want WorldObserver to use `buffer:advice_get()` to auto-tune budgets per type, or keep budgets fixed for v1?
  - Answer: fixed for v1
- If we auto-tune: do we do it per buffer independently, or via a global “budget advisor” that balances types?
  - Answer: As we have to maintain a global budget we should balance globally

### API surface for modders
- What minimal, friendly debug API do we commit to (e.g. `WorldObserver.debug.factsMetrics()`), and what stays internal?
  - Answer: No hard opinions. We don't need to hide things behind `local` but also we don't need to jump through hoops providing more info, yet.

### Patching conventions

WorldObserver follows the “Zomboid way”: patch by reassigning module fields after `require(...)`.

Example: patch square record shaping (affects both event and probe production):

```lua
local SquaresFacts = require("WorldObserver/facts/squares")
local original = SquaresFacts.makeSquareRecord

SquaresFacts.makeSquareRecord = function(square, source)
	local record = original(square, source)
	if record then
		record.myTag = "from-my-mod"
	end
	return record
end
```

Implementation note: where patching matters (callbacks, handlers), WorldObserver code dispatches through module fields (not `local` upvalues), so patches apply even after producers have started.

### Hydration (live game objects on demand)

Square facts include stable fields (`x/y/z`, flags, timestamps) and may also carry a best-effort cached `IsoGridSquare`.
If you need to *ensure* a live vanilla square object is present, use the stream helper:

```lua
local stream = WorldObserver.observations.squares():squareHasIsoGridSquare()
stream:subscribe(function(obs)
	-- Here, obs.square.IsoGridSquare is guaranteed non-nil.
	local iso = obs.square.IsoGridSquare
end)
```

Contract: `squareHasIsoGridSquare()` filters out observations when hydration fails (square unloaded or hydration globals unavailable, e.g. headless/tests).
