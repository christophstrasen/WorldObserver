# WorldObserver Runtime Dynamics (implementation guide)

This document explains how WorldObserver’s runtime “shapes” work at runtime:

- **Dynamic-in (input side):** probes/sensors adapt how much they scan and how “good” the effective interest is.
- **Dynamic-out (output side):** ingest draining adapts how fast buffered facts are drained into observation streams.

This is contributor-facing and code-first. The goal is to help you follow the feedback loop in code and know where to tune it.

Related docs:
- Conceptual model (design draft): `docs_internal/drafts/runtime_controller.md`
- Fact layer + ingest boundary: `docs_internal/fact_layer.md`
- Ingest usage notes: `docs_internal/drafts/using_ingest_system.md`
- Interest semantics: `docs_internal/drafts/fact_interest.md`, `docs/guides/interest.md`

Boundary note (WO vs LQR): think of LQR ingest as the “conveyor belt + rules of movement”, and WorldObserver as the “factory manager”.

When a WorldObserver producer (probe/listener/collector) calls `ctx.ingest(record)`, WorldObserver hands that record to an LQR ingest buffer that was configured for that fact type (mode/key/capacity/lanes). From that moment on, **LQR owns the semantics**: how records are compacted (e.g. `latestByKey`), how lanes are scheduled, when and how drops happen, and what the ingest metrics mean.

WorldObserver’s job is everything around that: deciding *when* to produce/ingest records, measuring how much time producers and draining cost per tick, and reacting to pressure by shaping budgets and quality (for example, adjusting the drain budget per tick or degrading probe quality when we can’t keep up).

If you need to change “what `latestByKey` means”, lane rules, drop behavior, or metric definitions, the canonical reference is LQR’s ingest doc: https://github.com/christophstrasen/LQR/blob/main/docs/concepts/ingest_buffering.md. If you need to change “when we ingest/drain” or “how we react to ingest pressure”, this document (and the WorldObserver runtime/controller code) is the right place.

## 1) The feedback loop (one picture)

Everything hinges on the fact registry’s OnTick hook, which measures work and feeds the runtime controller:

```
Events.OnTick
  ├─ FactRegistry runTickHooksOnce()      (producer work; time-sliced)
  ├─ FactRegistry:drainSchedulerOnce()    (drain buffered facts → streams)
  └─ Runtime:recordTick + Runtime:controller_tick(...)
          │
          ├─ sets Runtime.status.window + Runtime.status.tick (window aggregates)
          ├─ updates Runtime.status.budgets.*                 (drain budget override)
          └─ transitions Runtime.status.mode                  (normal/degraded/emergency)

Next tick:
  ├─ drain uses Runtime.status.budgets.schedulerMaxItemsPerTick
  └─ sensors/probes use Runtime.status_* to pick effective work per tick
```

Key entrypoints:
- Measurement + controller feeding: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/registry.lua`
  - `attachOnTickHookOnce()` (OnTick hook)
- Controller logic: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/runtime.lua`
  - `recordTick()`, `controller_tick()`, `status_get()`

## 2) Where we measure “WO tick cost”

The controller should react to **WorldObserver’s own cost**, not raw FPS. We measure inside the registry’s OnTick hook:

- `FactRegistry:attachTickHook(id, fn)` registers per-tick producer work (probes/sensors) into a shared timing window.
- `attachOnTickHookOnce()` attaches `Events.OnTick.Add(fn)` and measures:
  - `tickHooksMs` (“producerMs”) = time spent in all tick hooks this frame
  - `drainMs` = time spent draining ingest buffers this frame
  - `tickMs` = total measured time for WO in this frame (hooks + drain + overhead)

Files and functions:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/registry.lua`
  - `attachTickHook()`
  - `attachOnTickHookOnce()` (creates the timing window and calls `runtime:controller_tick({...})`)

Clocks:
- The registry prefers `runtime:nowCpu()` (CPU-time-ish) when available, else `runtime:nowWall()`.
- Runtime clocks come from `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/runtime.lua`:
  - `resolveWallClock()` (currently `Time.gameMillis()`)
  - `resolveCpuClock()` (currently `Time.cpuMillis()` which is `os.clock()*1000` in headless Lua)

## 3) Dynamic-out: adaptive draining (ingest scheduler)

Facts are ingested into per-type buffers and drained by one global scheduler. Draining is the main outflow “throttle”.

### 3.1 Where the drain budget is applied

Each tick, before draining, the registry applies a runtime-derived override:

- `FactRegistry:drainSchedulerOnce()` reads:
  - `runtime:status_get().budgets.schedulerMaxItemsPerTick`
- If present, it sets `scheduler.maxItemsPerTick` to that value for this tick.
- Otherwise it falls back to the configured baseline (`ingest.scheduler.maxItemsPerTick`).

File:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/registry.lua`
  - `drainSchedulerOnce()`

### 3.2 How the controller chooses that drain budget

The controller runs in windows (default `windowTicks=60`), not per-tick, to avoid flapping.

On each completed window, `Runtime:controller_tick()`:
- Aggregates tick cost: avg and max, plus a spike streak detector.
- Aggregates ingest pressure: `avgPending`, `dropDelta`, `avgFill`, `throughput15`, `ingestRate15`, and a coarse trend (`steady/rising/falling`).
- Updates:
  - `status.window.*` and `status.tick.*` (for diagnostics and for sensor decisions)
  - `status.budgets.schedulerMaxItemsPerTick` when drain auto-tuning is enabled
  - `status.mode` transitions (`normal` ⇄ `degraded`, plus `emergency` via `emergency_reset()`)

The drain auto-tuner (“gas pedal”) is intentionally simple:
- If WO is over budget or spiking: step the effective drain budget down.
- If buffers are under pressure *and* WO is well under budget: step the effective drain budget up.
- If pressure clears: decay back toward the configured baseline.

File:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/runtime.lua`
  - `controller_tick()`

## 4) Dynamic-in: interest policy (quality ladder)

Interest is declared in **bands** (`desired` vs `tolerable`). The policy chooses an effective point on a ladder.

### 4.1 Where “effective interest” is computed

Probes call `InterestEffective.ensure(...)` to convert a merged interest spec into an effective one:

- merges happen in the interest registry (not in the policy itself)
- the policy maintains per-type (and optionally per-bucket) state so targets can degrade independently

Files:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/interest_effective.lua`
  - `InterestEffective.ensure(...)`
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/interest/policy.lua`
  - `Policy.update(prevState, merged, runtimeStatus, opts)`

### 4.2 What the policy can change

The default ladder degrades in a deterministic order:
1) Increase `staleness` (accept older observations)
2) Reduce `radius` (scan fewer squares)
3) Increase `cooldown` (emit less often per key)

Triggers:
- If runtime is overloaded (based on window tick budget + drop heuristics), degrade.
- If a probe is lagging (based on sweep progress vs requested staleness), degrade.
- If lagging *but runtime has headroom*, do **not** degrade yet; let probes spend more CPU first (auto budget).

## 5) Dynamic-in: probe auto-budgeting (square sweep)

The shared square sweep sensor (`square_sweep`) is the “eyes” for any scope that is implemented as “scan squares near/visible”.

It is shaped in two ways:
1) **Quality** is shaped by the interest policy (effective `radius/staleness/cooldown`).
2) **CPU** is shaped by the sensor’s own per-tick time budget and a hard iteration cap.

### 5.1 Auto budget (spend headroom to avoid degrading)

`square_sweep` can temporarily increase its per-tick CPU budget when:
- runtime status is `normal`
- the controller window is “steady” (not over budget / not spiking)
- probe demand is high (`demandRatio > 1.0`)

Where it happens:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/sensors/square_sweep.lua`
  - `_internal.resolveProbeBudgetMs(baseBudgetMs, runtimeStatus, demandRatio, probeCfg)`

Important details:
- It computes headroom against the controller’s `tickBudgetMs` (default 4ms).
- It uses the controller’s breakdown (`avgDrainMs`, `avgOtherMs`) to avoid stealing budget when draining is already expensive.
- It respects a reserve (`autoBudgetReserveMs`, default 0.5ms) so drain can still happen.

### 5.2 Scaling the iteration cap along with budget

If auto-budget raises `budgetMs`, we also raise `maxSquaresPerTick` so we actually spend the budget:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/sensors/square_sweep.lua`
  - `_internal.scaleMaxSquaresPerTick(baseMaxSquaresPerTick, baseBudgetMs, budgetMs, budgetMode, probeCfg)`

This is still bounded by `maxPerRunHardCap` so clocks/estimates can’t explode work.

### 5.3 Where `demandRatio` comes from

The interest policy emits meta, including `meta.demandRatio`:
- an estimate of “how far are we from meeting desired staleness” for the current probe target/bucket

Square sweep takes the max across active buckets and uses it as the “do we need more budget?” signal.

Files:
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/interest/policy.lua`
  - `Policy.update(...)` (computes `demandRatio`)
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/sensors/square_sweep.lua`
  - `SquareSweep.tick(...)` (collects metas and calls `resolveProbeBudgetMs`)

## 6) Configuration settings (what to tune, and where)

Most runtime dynamics are intentionally data-driven via config:
- Defaults + validation live in `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/config.lua`

Key settings:

**Runtime controller (global)**
- `runtime.controller.tickBudgetMs`
- `runtime.controller.tickSpikeBudgetMs`
- `runtime.controller.windowTicks`
- `runtime.controller.drainAuto.*` (stepFactor/minItems/maxItems/headroomUtil)
- backlog heuristics (`backlogMinPending`, `backlogFillThreshold`, …)

**Ingest scheduler (global outflow baseline)**
- `ingest.scheduler.maxItemsPerTick` (baseline; controller may override)
- `ingest.scheduler.maxMillisPerTick` (optional; requires a wall clock)

**Probe budgets (per fact type that uses probes / sensors)**
- `facts.<type>.probe.maxMillisPerTick`
- `facts.<type>.probe.maxPerRun`
- `facts.<type>.probe.maxPerRunHardCap`
- `facts.<type>.probe.autoBudget` + `autoBudgetReserveMs` + `autoBudgetHeadroomFactor`

## 7) Diagnostics: how to see what’s happening

### 7.1 Logs

Useful tags in the logs:
- `WO.DIAG` – periodic controller + per-buffer summaries (when enabled)
- `WO.INGEST` – drain windows (processed/drainMs/emitMs/avgMsPerItem)
- `WO.FACTS.squares` – probe summaries per bucket (staleness/radius/cooldown/budget/lag/rate)

### 7.2 Runtime status snapshot

`WorldObserver.runtime:status_get()` returns a snapshot with:
- `mode` and `sinceMs`
- `window.*` (recent window aggregates and reason)
- `tick.*` (last tick + window averages + breakdown)
- `budgets.schedulerMaxItemsPerTick` (current drain override)

If you are extending probes/sensors, prefer using `status.window` and `status.tick` as inputs instead of reinventing new clocks/metrics.

## 8) Contributor cautions

- Keep engine callbacks and probes cheap: always use `ctx.ingest(record)` (buffered) instead of doing downstream work in-place.
- When adding per-tick work, register it via `FactRegistry:attachTickHook(...)` so it’s included in budgets/diagnostics.
- Prefer time-sliced scans (small per-tick caps) over large loops; the controller can’t “undo” a single bad frame.
- Avoid holding engine objects long-term; store stable ids/coords and use best-effort hydration.

## Questions (to confirm scope for future docs)

1) Should we expose a public “runtime status” doc in `docs/guides/` (for modders), or keep these details internal for now?
2) Do you want an explicit “how to debug overload” section that maps common symptoms to the relevant runtime/ingest fields?
