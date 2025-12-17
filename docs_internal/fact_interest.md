# Fact interest declarations (design brief)

This document sketches how mods can **declare interest** in upstream fact acquisition so WorldObserver can coordinate
shared probing work under a global budget.

Related docs:
- Fact layer reality: `docs_internal/fact_layer.md`
- Runtime controller: `docs_internal/runtime_controller.md`
- Vision: `docs_internal/vision.md`

---

## 1. Goals (near-term)

- Let mods describe what upstream data they need (“declare interest”), without wiring their own probes.
- Merge interests across mods into a single **effective** probe plan per fact type.
- Enforce a global budget via the existing ingest scheduler + runtime controller, and **degrade gracefully**.
- Keep API simple: **declare** interest (replace semantics by key), optional ranges, and **leases** so stale declarations expire.
- Keep the current lifecycle rule: facts/probes only run while there is at least one subscriber to the related fact stream.

## 2. Non-goals (for now)

- Perfect downstream cost attribution (per-subscriber profiling) or automatic inference from query graphs.
- Security/permissions: `modId` is a label for fairness + diagnostics, not trust.
- Per-mod individualized fact streams (v1 produces shared streams per fact type).

---

## 3. API shape (proposed)

Global WorldObserver surface (declare + leases):

```lua
-- Declare interest by (modId, interestKey). Returns a lease handle (replaces existing declaration for that key).
local lease = WorldObserver.factInterest:declare(modId, interestKey, spec)

-- Optional explicit removal.
WorldObserver.factInterest:revoke(modId, interestKey)

-- Lease refresh (if the mod keeps long-lived interest).
lease:touch() -- or lease:declare(spec) which also refreshes

-- Stop the declaration (alias for revoke).
lease:stop()
```

Lease behavior:
- Default TTL (e.g. 10min, must be > probe cadence). If not refreshed, the declaration expires and stops influencing probe plans.
- Replacing a spec refreshes TTL.

Subscriber gating:
- Declarations influence *how* probes run, but probes should only run while the relevant fact stream has subscribers
  (we cannot rely on mods to revoke interest when they stop observing).

---

## 4. Interest shapes (MVP training slice)

Initial focus: **squares probes only** (no engine events).

### 4.1 Near-player radius probe

Key idea: periodically scan squares within a radius of each player.

Spec fields (illustrative):
- `type = "squares.nearPlayer"`
- `radius` (tiles) or `radius = { desired = 8, tolerable = 5 }`
- `staleness` (seconds) or `staleness = { desired = 10, tolerable = 20 }`
- `cooldown` (seconds) or `cooldown = { desired = 30, tolerable = 60 }`

Notes:
- Distinct/throttle is keyed by the fact type’s canonical identity (for squares: `squareId`) and is not configurable in v1.
  Mods that need distinct by other dimensions should do it downstream on the ObservationStream (`stream:distinct(...)`).

### 4.2 Vision probe

Key idea: periodically scan squares that the engine considers “currently seen” by the player, optionally bounded by a
radius cap.

Spec fields (illustrative):
- `type = "squares.vision"`
- `radius`
- `staleness`
- Engine predicate is explicitly *engine-defined* (not LOS tracing). Confirmed API: `IsoGridSquare:getCanSee(int playerIndex)`.

---

## 5. Ranges, directionality, and merging math

We need to be explicit: some knobs become “gentler” when they go **up**, others when they go **down**.

### 5.1 Definitions

For each knob we define:
- **quality direction**: which way is “better quality” (usually higher cost)
- **degrade direction**: which way reduces work/cost

MVP knobs:
- `staleness` (allowed observation age): **smaller = stricter / higher cost**, degrade by **increasing**.
- `radius` (coverage): **larger = better coverage / higher cost**, degrade by **decreasing**.
- `cooldown` (per-key emission gap): **smaller = more frequent / higher cost**, degrade by **increasing**.

### 5.2 Effective value constraints (still tolerable for all)

When degrading within declared bands, keep values inside the “tolerable band” across all active declarations.

Let each declaration provide a scalar or a band for each knob:
- Scalar: `staleness = 10` (the “desired” value). WorldObserver derives a default tolerable value via its policy.
- Band: `staleness = { desired = 10, tolerable = 20 }` (explicit desired+tolerable).

Then:
- `staleness` may increase up to: `min( tolerable_i(staleness) )`
- `radius` may decrease down to: `max( tolerable_i(radius) )`
- `cooldown` may increase up to: `min( tolerable_i(cooldown) )`

That is the corrected math for “how far can we degrade this knob without violating anyone’s tolerable bound”.

Notes:
- If a mod only provides a scalar, it is treated as “desired” and the “tolerable” bound is filled in by defaults.
- If declared bands conflict (no feasible shared point), v1 should remain deterministic: degrade within what exists, then
  move to emergency steps and emit warnings (rather than trying to solve an optimization problem).

---

## 6. Degradation ladder (simple + deterministic)

Per probe type, maintain a small discrete quality state:

1. Start at “highest quality” (most demanding combined request).
2. When runtime controller reports “over budget”, degrade knobs in a fixed order:
   1) increase `staleness` (allow older observations),
   2) decrease `radius`,
   3) increase `cooldown`.
3. Within a knob’s `[desired .. tolerable]` band, degrade in a few **intermediate steps** (rather than jumping straight
   from desired to tolerable), e.g.:
   - `staleness`: `1, 2, 4, 8, 10`
   - `radius`: `20, 15, 12, 9, 8`
   - `cooldown`: `1, 2`
4. Stop degrading a knob once it hits the **global tolerable bound** (section 5.2), then move to the next knob.
5. If still over budget after reaching all tolerable bounds, apply **emergency steps** up to 3 times:
   - double `staleness`
   - halve `radius` (floor at 0/1 as appropriate)
   - double `cooldown`
   - emit periodic warnings that include the effective values being applied.

Default bounds when a mod omits a band:
- Treat missing bands as “soft” and derive `tolerable` values from project defaults.
- Emergency scaling still applies when budgets demand it; once we breach a tolerable value, we warn and report effective values.

Hysteresis (anti-flapping):
- Degradation reacts to sustained “probe lag” (a sweep cannot complete within the target staleness).
- Recovery requires sustained healthy windows *and* evidence that we can meet the **desired** staleness again (not merely the
  degraded staleness). This avoids oscillating between desired and tolerable when load is near the edge.
- Recovery has extra hysteresis after a lag-triggered degrade (to avoid 1↔2 “thrash” when the sweep is borderline).

---

## 7. “Freshness intent” vs implementation (future-proofing)

Today we can implement `staleness` as “aim to re-confirm keys often enough that observations are usually not older than this”.

Longer-term we can reinterpret it as **max staleness per key** (“don’t re-confirm a key that was observed recently”):
- If a square was observed by any source (event, probe, luaevent) within the staleness window, a probe pass can skip it.
- This allows future mixing of events + probes without exposing low-level knobs to users.

This is a later optimization; v1 can remain “interval-based probes”.

---

## 8. Observability (minimum)

- Debug: list active leases and their effective merged plan.
- Runtime status already exists (`WorldObserver/runtime.lua`): keep emitting window reports + degrade reasons.
- In-engine probe logging knobs can be toggled live (no module reload): `_G.WORLDOBSERVER_CONFIG_OVERRIDES.facts.squares.probe.infoLogEveryMs` and `.logEachSweep`.
- When `autoBudget` raises `budgetMs`, probes also scale their per-tick iteration cap up to `maxPerRunHardCap` so they can actually spend the budget.
- Warnings should point to the effective values and to `WorldObserver.debug.describeFactsMetrics("<type>")`.
