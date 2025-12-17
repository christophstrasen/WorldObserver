# Zombie observations (next fact family) — design + implementation plan

This document proposes how to add **ZombieObservations** as the next WorldObserver slice after squares.

The goal is to ship a useful, budgeted, interest-driven `WorldObserver.observations:zombies()` stream (emitting
`observation.zombie`) while improving overall architecture in a way that makes later families (vehicles, rooms, items)
easier to add.

Related docs:
- Vision: `docs_internal/vision.md`
- API proposal: `docs_internal/api_proposal.md`
- Fact layer reality: `docs_internal/fact_layer.md`
- Fact interest & policy: `docs_internal/fact_interest.md`
- Research notes / relevant events: `docs_internal/research.md`

---

## 1. Goals (this slice)

- Provide a **base** observation stream: `WorldObserver.observations:zombies()` that emits `observation.zombie`.
- Keep upstream acquisition **interest-driven** (`staleness`, `radius`, `cooldown`) and coordinated across mods.
- Integrate with the existing **global runtime budget** (4ms / 8ms spike) and ingest backpressure.
- Keep records **small and stable** (primitive fields + timestamps), avoid holding on to game objects.
- Keep implementation compatible with **Lua 5.1 + PZ b42** and run under `busted`.

---

## 2. Non-goals (for now)

- Perfect “priority tracking” across many competing mod intents.
- Full event coverage (hit/death/etc.) as part of the base zombie stream.
  Those are likely **separate** streams later (`zombieHit`, `characterDeath`, …).
- Mixed-source “drive-by” zombie detail during square scans (we design for it, but do not block v1 on it).

---

## 3. Public naming and schema shape

### 3.1 Stream name vs per-observation field name

- Observation stream key: **plural** `zombies` (consistent with `squares`).
- Per-emission field: **singular** `observation.zombie`.
- Internal schema name: `ZombieObservation`, then `selectSchemas({ ZombieObservation = "zombie" })`.

### 3.2 Candidate ZombieObservation fields (v1) — grounded in B42 Javadocs

We should treat zombie fields as a curated “core snapshot” similar to squares: stable, small, and cheap to compute.
Below is a pragmatic **proposal** for what to include in v1, grouped by usefulness.

These fields are chosen to align with Build 42 getters we can call cheaply:
- `IsoZombie:getOnlineID()` when meaningful (MP), otherwise `IsoMovingObject:getID()` as a stable session key
- `IsoMovingObject:getCurrentSquare()` + `IsoGridSquare:getID()` for `squareId`
- `IsoMovingObject:getX/getY/getZ()` for position
- `IsoGameCharacter:getOutfitName()` / `getPersistentOutfitID()` for outfit
- `IsoZombie:getTarget()` / `isTargetVisible()` / `getTargetSeenTime()` for targeting state
- `IsoZombie:isCrawling()` / `IsoGameCharacter:isRunning()` / `IsoGameCharacter:isMoving()` (+ `speedType`) for locomotion

**Identity / location (must-have)**
- `zombieId` (integer; use `zombie:getID()` as the primary key; stable enough for `latestByKey`)
- `zombieOnlineId` (integer; `zombie:getOnlineID()`; may be `0`/unset in SP, but useful to retain for MP correlation)
- `x`, `y`, `z` (numbers; use `zombie:getX()`, `zombie:getY()`, `zombie:getZ()`; treat as tile coords in v1)
- `squareId` (number; use `zombie:getCurrentSquare():getID()` when available; else derive like squares)
- `observedAtTimeMS` (domain timestamp, ms)
- `source` (`"probe"`, later `"event"`, `"driveBy"`)

**Movement / locomotion (very useful)**
- `isMoving` (boolean; use `zombie:isMoving()` from `IsoGameCharacter`)
- `isRunning` (boolean; use `zombie:isRunning()` from `IsoGameCharacter`)
- `isCrawling` (boolean; use `zombie:isCrawling()` from `IsoZombie`)
- `speedType` (number; raw `IsoZombie.speedType`, keep as-is as a “low-level hint”)
- `locomotion` (string enum; derived): `"crawler" | "runner" | "walker" | "unknown"`
  - Derivation proposal: `isCrawling -> crawler`, else `isRunning -> runner`, else `isMoving -> walker`, else `unknown`.

**Targeting (useful, but careful)**
- `hasTarget` (boolean; `zombie:getTarget() ~= nil`)
- `targetId` (integer|nil; best-effort `zombie:getTarget():getID()`; nil when no target / not resolvable)
- `targetVisible` (boolean; `zombie:isTargetVisible()`)
- `targetSeenSeconds` (number; `zombie:getTargetSeenTime()`)
- `targetKind` (`"player" | "character" | "object" | "unknown"`) (best effort; should use engine type checks like `instanceof`)
- `targetX`, `targetY`, `targetZ` (number|nil; `target:getX/getY/getZ` if available)
- `targetSquareId`, (number|nil; `target:getCurrentSquare():getID()` if available)

**Visual / identity flavor (requested, but keep cheap)**
- `outfitName` (string; `zombie:getOutfitName()`)
- `persistentOutfitId` (number; `zombie:getPersistentOutfitID()`)

**Raw object handle (optional)**
- `IsoZombie` (userdata) as an escape hatch for advanced mods.
  - NOTE: this can keep references alive longer; we should treat it as optional and never rely on it for correctness.

Notes:
- Prefer not storing `IsoZombie` userdata inside emitted facts by default; it makes buffering/identity trickier and can
  keep references alive longer than intended. If we include it, make it explicit/optional and keep “pure snapshot” fields
  as the primary contract.
- Any “expensive enrichment” (outfit tags, inventory, etc.) should be a later, opt-in expansion.

### 3.3 Rehydration helper (from record → live IsoZombie)

Even if we include `IsoZombie` in the record in v1, we should provide a consistent “rehydration” helper so mods can work
with pure snapshots and only reach for userdata when needed:

- `WorldObserver.helpers.zombie.getIsoZombie(zombieRecord) -> IsoZombie|nil`

Proposed resolution order:
1. If `zombieRecord.IsoZombie` exists and is still valid, return it.
2. Else, scan `IsoCell:getZombieList()` and match by `zombieId` (or fallback to matching by coordinates if id is missing).

This is intentionally “best effort” and may be expensive; we should document it as a debugging/edge-case tool, not
something to call for every observation in hot paths.

### 3.4 Identity (`zombieId`) — open question

We need a stable key for:
- ingest buffering (`latestByKey`)
- `cooldown` per zombie
- helper dimensions (distinct by zombie)

Preferred order (to confirm in-engine):
1. `zombie:getID()` (primary key; expected to be stable within a session)
2. Also store `zombie:getOnlineID()` for MP correlation (may be `0`/unset in SP)

We want to assume that either getOnlineID or getID will be stable enough to use. 

### 3.5 Confirmed getters (Build 42 Javadocs)

These are present in the official Build 42 Javadocs (https://demiurgequantified.github.io/ProjectZomboidJavaDocs/):

Note: https://www.projectzomboid.com/modding/ javadocs are often older (e.g. 2022) and may not reflect Build 42.
For Build 42 API work we should treat the demiurgequantified docs as the primary source of truth.

- Identity:
  - `IsoZombie:getOnlineID()`
  - `IsoMovingObject:getID()` (primary identity in SP; also available in MP)
- Location:
  - `IsoMovingObject:getX()`, `getY()`, `getZ()`
  - `IsoMovingObject:getCurrentSquare()` (then `IsoGridSquare:getID()`)
- Targeting:
  - `IsoZombie:getTarget() -> IsoMovingObject`
  - `IsoZombie:getTargetSeenTime() -> float`
  - `IsoZombie:isTargetVisible() -> boolean`
- Locomotion:
  - `IsoGameCharacter:isMoving()`
  - `IsoGameCharacter:isRunning()`
  - `IsoZombie:isCrawling()`
  - `IsoZombie.speedType` (public int field)
- Outfit:
  - `IsoGameCharacter:getOutfitName() -> String`
  - `IsoGameCharacter:getPersistentOutfitID() -> int`

### 3.6 Pragmatic helpers (v1)

We should keep the v1 helper surface small and directly backed by the v1 fields.

We DONT need to provide helpers over simple fields. No need "pass through". Helpers should be value-add. And in doubt helpers are allowed to do more heavy work than early field mappers (those are more upstream afterall). E.g. intelligently detecting what type of target the zombie has.

Proposed “rehydration / convenience” helpers under `WorldObserver.helpers.zombie`:
- `getIsoZombie(zombieRecord)` (see 3.3)
- `getIsoSquare(zombieRecord)` (uses `x/y/z` and the active cell; mirrors the square helper pattern)
- `getTarget(zombieRecord)` (best effort: rehydrate the target object when we have `targetId` and a loaded object matches it)
- ensure it works similar to `WorldObserver.helpers.square.getIsoSquare`

---

## 4. Fact acquisition options (evaluation)

### Option 1 — Poll `IsoCell:getZombieList()` (recommended v1)

**Concept**
- Periodically iterate the loaded zombies list and emit observations for those that match the effective interest.

**How it fits**
- Very similar to the squares probe model: a time-sliced cursor, budgeted per tick, “sweep” concept, lag signals.
- Plays nicely with ingest buffering: even if the list is large, the buffer de-dupes by `zombieId`.

**Pros**
- Simple and robust; no dependency on event correctness.
- Naturally supports near-player filtering (distance check) and “vision-only” filtering later.

**Cons / risks**
- Scanning cost grows with number of loaded zombies (worst-case on high-pop settings).
- “Identity” must be solved well (see 3.3).

**Best practice for FPS**
- Use a cursor (“electron beam”) and scan **as fast as possible within budget**, not evenly distributed across staleness.
- Maintain fairness via round-robin between “near” and any future “vision” interest types.

### Option 2 — Drive-by discovery during square scanning (future extension)

**Concept**
- While the squares probe visits `IsoGridSquare`s, opportunistically discover zombies present on those squares.

**How it fits**
- This is a *mixed-source* producer: “the squares scan is the expensive part, zombie extraction is a cheap add-on”.
- It can make zombie acquisition almost “free” near players because we already scan those squares for square facts.

**Architecture implication**
- We need a clean mechanism to emit **zombie facts** from within a **square scan**, without coupling types tightly.
- A good shape is: square probe calls `ctx.driveBy(square, playerIndex, nowMs)` hooks (0..N), and the zombie plan can
  register such a hook only when `zombies` facts are active.

This is valuable, but should be added after the base zombie stream exists.

### Option 3 — Priority tracking (“closer zombies refresh more”)

**Concept**
- Keep a working set of zombie ids with a priority score (distance to player, “flagged interesting”, etc.).
- Schedule re-checks more frequently for high priority, less frequently for low priority.

**How it fits**
- This is a general method that can later apply to vehicles/items too.
- It pairs well with the interest system: interest declares “how much do I care”, priority decides “where to spend it”.

**Trade-off**
- More code + more state; we should only do this once we have real performance pressure evidence.

Recommendation:
- Keep it as a planned v2 enhancement, but design v1 so the cursor order can evolve (don’t bake in assumptions that
  the probe always scans the list in raw order).

---

## 5. Proposed interest shapes (v1)

Start with one interest type that matches immediate modder expectations:

### `zombies.nearPlayer` (v1)

- `staleness` (seconds): how quickly we try to refresh the set
- `radius` (tiles): only emit zombies within radius of any player
- `zRange` (integer ≥ 0): include zombies whose `abs(zombieZ - playerZ) <= zRange`.
  - `zRange = 0` → same floor only; `zRange = 1` → player floor plus one above and one below (3 total levels); etc.
- `cooldown` (seconds): per-zombie emit throttle (prevents spamming the same zombie every sweep)

Important nuance:
- With a plain `IsoCell:getZombieList()` probe, `radius` or `zRange` do **not** automatically reduce the cost of *acquisition*,
  because we still have to walk the list to find the near zombies.
- It still matters in v1 because it reduces *work we do per zombie* (record extraction, ingest calls, downstream processing)
  by filtering out far-away zombies early.
- `radius` becomes a true acquisition cost-saver once we have a spatial index (or a drive-by square scan hook) so we can
  query “zombies near X” without enumerating all loaded zombies.

Later additions (not required for v1):
- `zombies.vision`: only zombies that are “currently visible” to the player (engine-defined)

---

## 6. Architecture improvements to increase “fitness”

Adding zombies is a good moment to improve our shared patterns without reworking the drain system.

### 6.1 Extract a reusable probe runner (recommended)

Right now `facts/squares/probe.lua` includes:
- budget logic
- cursor sweep bookkeeping + lag signals
- per-tick round robin between multiple probes
- logging knobs (`infoLogEveryMs`, `logEachSweep`)

We should extract a shared module (e.g. `WorldObserver/facts/probe_runner.lua`) that:
- runs N probes per tick under `budgetMs` and `maxPerRun`
- tracks per-probe sweep timing + lag signals
- produces a “probe meta” object (including demand ratio) that can feed the interest policy

Then squares and zombies probes become thin adapters:
- “how to iterate targets” (grid offsets vs list indices)
- “how to build record” (SquareObservation vs ZombieObservation)
- optional “visibility” predicate

This reduces duplication and makes future families simpler.

### 6.2 Make “drive-by” possible without cross-type coupling (design seam)

Introduce a lightweight hook mechanism around spatial scans:
- squares scan: `onSquareProbed(square, playerIndex, nowMs)` hooks
- zombie plan can register one hook when active, and emit zombie facts through its own ingest context

Key requirement:
- Drive-by must remain subscriber-gated (no zombie subscribers => no zombie work).

### 6.3 Standardize “record builders” and “schemas per family”

Continue the squares pattern:
- `facts/<family>/record.lua` owns extraction logic (patchable via `<Family>.make…Record`)
- `observations/<family>.lua` wraps facts into a schema and exposes `observation.<entity>`
- `helpers/<entity>.lua` contains stream helpers + predicates

This keeps each family’s public contract obvious and testable.

---

## 7. Implementation plan (incremental)

### Phase A — Research / API confirmation (in engine)

Confirm with a small console snippet:
- How to get loaded zombies list (`getCell():getZombieList()` vs other access)
- Which stable id exists (`getID` / `getOnlineID` / …) and its behavior in SP
- Position getters (`getX/getY/getZ`) return what we expect (tile coords)
- Any cheap “visible” predicate if we later want `zombies.vision`
- Validate `zRange` behavior: quick loop that prints `abs(z - playerZ)` distribution to ensure the field matches our definition.
- Note: Run these in the PZ console; do not ship any runtime changes for Phase A.

### Phase B — Add the fact family (v1)

1. Config defaults:
   - Add `facts.zombies.ingest` and `facts.zombies.probe` knobs (mirror squares defaults).
2. Facts:
   - `facts/zombies.lua` registers fact type `"zombies"` with `latestByKey` keyed by `zombieId`.
   - `facts/zombies/probe.lua` implements a time-sliced cursor over the zombie list.
   - Interest-driven: resolve `zombies.nearPlayer` effective settings via InterestEffective.
3. Observations:
   - `observations/zombies.lua` registers `"zombies"` stream, wraps schema `ZombieObservation`, exposes `observation.zombie`.
4. Helpers:
   - `helpers/zombie.lua` (minimal) with a couple of predicates/filters once we have stable fields.
5. Wire-up:
   - Register zombies facts + observations in `WorldObserver.lua`.

### Phase C — Tests + examples

- Add `busted` tests:
  - record builder returns stable minimal fields
  - probe cursor behaves under budget and produces sane lag signals
  - interest meta `demandRatio` flows through for zombies as it does for squares
- Add a smoke example:
  - `examples/smoke_zombies.lua` subscribing to `WorldObserver.observations:zombies()` and toggling interest.

### Phase D — Follow-ups (optional)

- Add `zombies.vision` once a reliable “currently seen” predicate exists (engine-defined).
- Add drive-by discovery hook between squares scans and zombies (option 2).
- Add priority tracking (option 3) only after measuring a real need.

---

## 8. Notes on future event-based streams (separate families)

After the base `zombies()` stream exists, we can add “event-centric” observation families as separate streams:
- `zombieHit` (`OnHitZombie`)
- `characterDeath` (`OnCharacterDeath`)
- `deadBodySpawn` (`OnDeadBodySpawn`)

These can share parts of the same schema philosophy, but should not complicate the base zombie acquisition plan.
