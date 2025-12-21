# WorldObserver Runtime Controller (design draft)

This document describes a proposed **runtime performance controller** for WorldObserver.
It is host-specific (Project Zomboid) and focuses on keeping frame time stable while continuing to do useful work in the background.

Related docs:
- Vision: `docs_internal/vision.md`
- Fact layer + ingest wiring: `docs_internal/fact_layer.md`
- Ingest integration plan: `docs_internal/using_ingest_system.md`
- LQR ingest docs: `external/LQR/docs/concepts/ingest_buffering.md`

---

## 1. User promise (practical goal)

WorldObserver should be able to tell mod authors:

> “I do the heavy lifting in the background. I will only consume as much CPU budget as a stable frame target allows, and I will try to avoid peaks and stutter. When I can’t keep up, I will degrade gracefully and tell you what’s happening.”

This is a best-effort promise. WorldObserver cannot control GPU-bound stalls or other mods’ CPU usage, but it can:
- measure and cap **its own** CPU usage per tick, and
- make overload visible (pending backlog, drop rates, time spent).

---

## 2. Two clocks, two purposes

WorldObserver uses time for two distinct purposes, and these must not be mixed:

### 2.1 Event time (semantic time)

Used for facts/observations and LQR time windows (distinct/join/group).
- Example: `sourceTime`, `RxMeta.sourceTime`
- Current implementation uses game calendar time (`getGameTime():getTimeCalendar():getTimeInMillis()`).

Important nuance:
- In Build 42, `getTimeCalendar()` is commonly described as being backed by “current time” (effectively OS time),
  not “world time speed”. That means event-time windows behave like *real-time* windows, not “accelerated game-time”.

This is fine for many use-cases (dedup/throttling in real seconds), but we should be explicit about it so we don’t
accidentally assume game-speed scaling.

### 2.2 Runtime time (performance time)

Used for budgeting, controller decisions, and measuring “how much CPU did WO spend this tick”.

Requirements:
- millisecond precision is enough (we budget against ~16.67ms at 60fps)
- monotonic is strongly preferred
- must correlate with real CPU contention (not game-time speed)

The controller should select the best available clock at runtime (PZ vs headless).
Examples of candidate sources (availability must be probed at runtime):
- `UIManager.getMillisSinceStart()` (preferred if present; monotonic-ish)
- `getTimestampMs()` (often present; may jump if system clock changes)
- `os.clock() * 1000` (if available: CPU-time clock; great for attributing “WO CPU cost”, but not wall-time)

In practice we likely want *two* runtime clocks:
- `nowWallMs` (monotonic-ish wall-time) for “dt between ticks” and throughput-style rates
- `nowCpuMs` (CPU-time) for “how much CPU did WO consume”

If the runtime clock is non-monotonic or unavailable, the controller should:
- disable ms-based auto-budgeting,
- fall back to conservative item budgets, and
- log a single warning per window.

---

## 3. Boundaries: LQR/ingest vs WorldObserver

### 3.1 LQR/ingest responsibilities (library mechanics)

LQR/ingest should remain consumer-agnostic and provide:
- buffering/compaction + overflow semantics
- draining under `maxItems` and optionally `maxMillis` when a host provides `nowMillis`
- metrics (light + full) and pressure-style signals (`load1/5/15`, `throughput1/5/15`, `ingestRate1/5/15`)
- advice (`advice_get`, `advice_applyMaxItems`, `advice_applyMaxMillis`) that is purely about stream pressure

LQR/ingest should **not** encode:
- FPS targets
- probe patterns
- “clear all caches” or other WorldObserver lifecycle semantics
- Project Zomboid-specific APIs

### 3.2 WorldObserver responsibilities (host + domain policy)

WorldObserver owns the policy layer:
- pick the runtime clock and measure its own tick cost
- define “modes” and state transitions (normal vs degraded)
- throttle/disable producers that it controls (probes), and adjust budgets
- emit user-facing warnings/errors (without stopping the runtime)
- expose current operating status to mod authors

---

## 4. What we can control

### 4.1 Drain budgets (consumer-side backpressure)

WorldObserver can control how much it drains per tick:
- scheduler `maxItemsPerTick` (today)
- (future) scheduler `maxMillisPerTick` derived from real-time clock

### 4.2 Producer throttling (source-side backpressure)

WorldObserver can control only some producers:
- probes (it owns scheduling, cadence, and caps)
- cross-mod LuaEvents (it can subscribe/unsubscribe, route through ingest, and shed load at the boundary)

Important limitation:
- WorldObserver cannot control *how often* the engine or other mods emit events.
  For engine events and cross-mod LuaEvents alike, WorldObserver can only classify them into lanes, prioritize/compact them,
  and (when overloaded) explicitly drop/deprioritize them with clear metrics and warnings.

WorldObserver cannot truly throttle engine event volume (e.g. `LoadGridsquare`), but it can:
- bound memory (ingest buffer capacity)
- bound CPU via drain budgets
- shed load explicitly when over capacity (drops)

---

## 5. Controller inputs (signals)

The controller should operate using signals that are:
- cheap to compute,
- host-available, and
- attributable to WorldObserver.

Recommended “core signals”:

### 5.1 WorldObserver CPU usage (primary control signal)

Measured using the runtime clock:
- `woTickMs`: ms spent inside *all* WorldObserver per-tick work (draining + any tick-scheduled probes + controller overhead)
  - window aggregates (over N ticks or ~1–5 seconds):
  - `woAvgTickMs`
  - `tickSpikeMs` (spike detector; max tick time observed in the window)

### 5.2 Ingest pressure (secondary control signal)

From `buffer:metrics_getLight()` (safe frequently) and occasional `metrics_getFull()`:
- pending backlog, peak backlog
- drop/replaced totals (and deltas per window)
- load/throughput/ingestRate 1/5/15

Interpretation:
- if `ingestRate15 > throughput15`, backlog will grow (even if pending is currently small)
- if drops are increasing, we are shedding work (accuracy/freshness loss)

### 5.3 Optional host signals (for context, not hard control)

These are helpful but should not be treated as authoritative:
- `getPerformance():getFramerate()` (GPU-bound and CPU-bound both affect it)
- `collectgarbage("count")` (memory pressure correlation, not a cause)

---

## 6. Controller outputs (actions)

The controller should be able to change:

### 6.1 Scheduler drain budget

Minimum viable:
- treat `scheduler.maxItemsPerTick` as a **baseline** and choose an **effective** `maxItemsPerTick` dynamically:
  - increase in multiplicative steps when backlog pressure is high and WO is well under its ms budget
  - decrease in multiplicative steps when WO exceeds its ms budget or shows repeated spikes
- keep `quantum` small for fairness (or raise when overhead dominates)

Future improvement:
- set a `maxMillisPerTick` budget and derive items from `msPerItem` estimates

### 6.2 Probe budgets and cadence

Per probe (or per fact type):
- enable/disable
- reduce per-run cap
- increase interval (e.g. EveryOneMinute → EveryTenMinutes) or probabilistic sampling

### 6.3 Reset/clear actions (last resort)

If WorldObserver is the likely CPU culprit and cannot recover:
- clear ingest buffers (`buffer:clear()`) and reset metrics (only metrics reset does not clear)
- future: optionally clear selected LQR query caches if we expose a safe, explicit API

This is correctness-safe only if mod authors accept that “background discovery” may lose history.

---

## 7. Modes and state machine (proposed v1)

Modes are meant to be visible to users and stable (avoid flapping).

### 7.1 Mode: Normal

Goal: keep WO’s measured tick cost under budget while draining enough to avoid backlog growth.

Actions:
- probes enabled (default caps)
- scheduler budget uses the configured “normal” value as a baseline; runtime may temporarily raise it to burn backlog, but will decay back toward baseline once pressure is gone

### 7.2 Mode: Degraded (safety mode)

Entry conditions (examples; thresholds must be tuned empirically):
- `tickSpikeMs` repeatedly exceeds budget (spikes; e.g. at least 2 spikes in a row)
- `woAvgTickMs` exceeds budget for a sustained window
- drops are increasing quickly (buffer at capacity)

Actions:
- throttle probes first (reduce caps, possibly disable)
- reduce effective drain budget if WO is CPU-bound, but allow “burn backlog” increases when we have headroom
- warn once per window with summary + suggested user actions

Exit conditions:
- sustained recovery for a window (hysteresis), then return to Normal

### 7.3 Mode: Overloaded (trouble persists)

Entry conditions:
- still in Degraded after N seconds and one of:
  - `woAvgTickMs` remains above budget, or
  - drop deltas continue to rise, or
  - pending load remains high and rising

Actions:
- stronger warnings (“WorldObserver cannot keep up”)
- recommend mod-author mitigation:
  - unsubscribe from expensive observations
  - widen distinct windows less aggressively
  - reduce helper usage that implies expensive downstream work

### 7.4 Mode: Emergency reset (CPU self-defense)

Entry conditions (WO-attributable):
- WO tick cost is severe for a sustained window (e.g. average above a “hard” threshold),
  OR repeated extreme spike streaks that correlate with WO drain work.

Actions:
- log a loud error (red console message) but do not halt the game
- clear ingest buffers and reset controller state
- keep probes disabled for a cool-down window, then return to Normal

Design note:
- “FPS < 30” alone is not enough; the trigger must be based on **measured WO tick ms**,
  otherwise we may reset because of GPU stalls or other mods.

---

## 8. Exposed status (API contract)

WorldObserver should expose a small, cheap, introspection API:

### 8.1 Proposed shape

`WorldObserver.runtime.status_get()` returns a plain table:
- `mode`: `"normal" | "degraded" | "overloaded" | "emergency"`
- `sinceMs`: runtime ms when mode started
- `lastTransitionReason`: string enum (for logs and debugging)
- `budgets`:
  - `schedulerMaxItemsPerTick`
  - `probeEnabled` + per-probe caps (where applicable)
- `tick`:
  - `lastMs` (last measured WO tick cost sample)
  - `woAvgTickMs`, `woTickSpikeMs` (last completed window; `woMaxTickMs` is a legacy alias)
  - `woWindowTicks`, `woWindowSpikes`, `woWindowSpikeStreakMax` (last completed window)
  - `woTotalAvgTickMs`, `woTotalMaxTickMs` (running totals; mostly for long-lived diagnostics)
- `ingest` (optional summary):
  - per-type: pending, dropsDelta, trend (`rising/falling/steady`)
 - `window` (last completed controller window snapshot; duplicated in `tick.*` for convenience)

### 8.2 Runtime status events (LuaEvents)

WorldObserver should also emit a LuaEvent whenever the runtime controller transitions between modes.

Rationale:
- lets mods react without polling (e.g. drop optional subscriptions, reduce their own work)
- makes “why did WO change behavior?” discoverable via a single hook

#### Proposed event name

`Events.WorldObserverRuntimeStatusChanged`

#### Proposed payload shape

Emit a single table argument:

```lua
{
  event = "WorldObserverRuntimeStatusChanged",
  seq = 123,                -- monotonic transition counter (per Lua VM)
  nowMs = 4567890,          -- runtime clock ms when the transition was applied
  reason = "woTickOverBudget",
  from = { mode = "normal", sinceMs = 1230000 },
  to = { mode = "degraded", sinceMs = 4567890 },
  status = WorldObserver.runtime.status_get(), -- snapshot *after* transition
}
```

Notes:
- `status` is included so listeners don’t have to call back into WorldObserver during the transition.
- `reason` should be a stable enum-like string (see open questions), not a free-form sentence.

#### Periodic report event (optional, implemented)

For dashboards and “non-transition” monitoring, WorldObserver may emit periodic reports:

`Events.WorldObserverRuntimeStatusReport`

Payload shape:

```lua
{
  event = "WorldObserverRuntimeStatusReport",
  seq = 456,                -- monotonic report counter (per Lua VM)
  nowMs = 4567890,
  status = WorldObserver.runtime.status_get(), -- snapshot at report time
}
```

### 8.3 Why this matters

It gives mod authors a hook for self-defense:
- they can reduce subscriptions or change their own behavior when WorldObserver reports overload
- they can log a single concise line in their mod logs rather than parsing many metrics lines

---

## 9. Implementation plan (slices)

### Slice A — Runtime clock selection + WO tick timing

- Implement a runtime-clock resolver (PZ vs headless).
- Measure WO drain tick cost and record window aggregates.
- Log a periodic “controller summary” at info (coarse).

### Slice B — Basic modes + probe throttling

- Implement Normal vs Degraded with hysteresis.
- Throttle the squares probe first (reduce cap / disable).

### Slice C — Integrate ms budgets (future)

- Extend the scheduler path to support `maxMillisPerTick` (requires plumbing).
- Start producing `msPerItem` estimates so `advice_applyMaxMillis` becomes useful.

### Slice D — Emergency reset + status API

- Add emergency reset path and status API.
- Decide what can be safely cleared beyond ingest buffers.

---

## 10. Open questions / pending decisions

### 10.1 Decisions (current)

1. **Runtime clocks for v1:** use a dual-clock approach when possible:
   - `nowCpuMs = os.clock() * 1000` (if available) for `woTickMs` (WorldObserver CPU cost attribution)
   - `nowWallMs = UIManager.getMillisSinceStart()` (preferred) or `getTimestampMs()` (fallback) for tick intervals and rate calculations
   - if only one is available, we still proceed, but we document which interpretation we are using
2. **What counts as “WO tick ms”:** include draining *and* probes scheduled on tick (plus controller overhead).
3. **Multi-buffer budget allocation (v1):**
   - between priority levels: higher priority drains first
   - within the same priority: deterministic round-robin
   - future: consider a weighted approach if we need finer control
4. **Emergency reset scope (v1):**
   - clear ingest buffers only
   - future: consider explicit query-cache eviction if/when we have a safe API
5. **transition reason enums (v1)**

We want a small, stable set of reason strings that explain *why* the controller changed mode.
Suggested v1 set:

- `woTickAvgOverBudget` (sustained over-budget CPU usage)
- `woTickSpikeOverBudget` (repeated spike streaks)
- `ingestBacklogRising` (ingestRate > throughput and backlog trending up)
- `ingestDropsRising` (drops increasing; we are shedding work)
- `clockUnavailable` (no usable runtime clock)
- `clockNonMonotonic` (clock went backwards; ignore ms-based control for a window)
- `recovered` (sustained recovery; exiting Degraded/Overloaded)
- `manualOverride` (user/mod code forced a mode change)
- `emergencyResetTriggered` (entered emergency reset)
