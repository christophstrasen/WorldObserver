# WorldObserver — `WoMeta.key` (RFC)

> **Stage:** Draft / proposal  
> **Why now:** PromiseKeeper Tier‑C integration (WorldObserver emits “PromiseKeeper‑ready” situations without per‑promise mapping functions)

This RFC introduces a **domain-level stable key** for WorldObserver emissions:

- A new metadata table: `WoMeta`
- A single required field (v1): `WoMeta.key` (always a string)

The goal is to make it easy for downstream systems (especially PromiseKeeper) to do durable, idempotent work without having to understand WorldObserver/LQR internals or write repetitive mapping code.

---

## 1) Problem

WorldObserver emissions today already carry **reactive plumbing metadata** in `RxMeta` (from LQR):

- `RxMeta.id` is a low-level per-emission id (often monotonic, sometimes UUID-ish depending on source)
- `RxMeta.sourceTime` exists for windowing
- Join results carry `RxMeta.shape="join_result"` and a `RxMeta.schemaMap`

However, PromiseKeeper (and other downstream “durable reaction” systems) need something different:

- A **domain** key: stable-ish across reloads (best effort), readable, and deterministic
- Not tied to LQR’s internal emission ids
- Works for both single-family emissions and multi-family derived/joined emissions

We do **not** want to store domain concerns in `RxMeta` (too low-level, “id vs key” confusion, and LQR-specific).

---

## 2) Goals / Non-goals

### Goals

- Add a **domain-level key** to every emission.
- Keep the data structure **simple**: one new meta table (`WoMeta`) and one field (`key`).
- Keep `WoMeta.key` **string-only** (simple persistence, simple hashing, simple logs).
- Make keys deterministic and readable:
  - single-family: `#square(123)`
  - multi-family: `#square(123)#zombie(456)` (lexicographic family order, `#` separator)
- Keep upstream subject selection out of WO:
  - **The entire observation is the “subject”** for PromiseKeeper Tier‑C.
  - WO does not decide “safe-to-mutate subject”; that remains downstream logic.
- Preserve existing “native” entity ids (squareId, zombieId, roomLocation, etc.) as-is; add stable keys alongside.
- If we can’t compute a key for an emission (missing `schemaMap` or missing `woKey`), **warn and skip the emission** rather than emitting a “half-keyed” observation.

### Non-goals

- Make “hard” stability promises. Some entities are inherently hard to identify stably across reloads/MP.
- Add compatibility shims/aliases for old key fields once we do the refactor. This is a **hard cut**.
- Solve “third-party base families” now. We will treat that as a later extension problem.
- Force every modder to write mapping functions for PromiseKeeper. The intent is to remove that cognitive load.

---

## 3) Terms

- **Record**: a fact record produced by a fact type (e.g. square record, zombie record).
  - In this RFC we will add `record.woKey` to every record (always a string).
- **Observation emission**: what a subscriber receives from a WorldObserver stream (base or derived).
  - Many emissions are LQR `JoinResult` containers: `{ square=..., zombie=..., RxMeta=... }`.
- **Family name**: the *visible* alias name used in WorldObserver streams (`square`, `zombie`, `room`, …).
  - This is what shows up as keys in join results and in `RxMeta.schemaMap`.

---

## 4) Proposal (Decisions locked in)

### 4.1 `WoMeta` on emissions

- Each emitted observation object gets a `WoMeta` table:
  - `observation.WoMeta = { key = "..." }`
- `WoMeta.key` is the **only required field** in this RFC.
- `WoMeta.key` is **always a string**.

### 4.2 `record.woKey` on fact records

- Each fact record gains a `woKey` field (always a string).
- `woKey` is family-owned: it is computed in the record builder itself.
- `woKey` is “stable-ish” best-effort; there are no external fallback strategies outside record logic.
- Existing entity-tied ids remain (e.g. `squareId`, `zombieId`, `roomLocation`) and “float along”.

Rationale:
- `record.woKey` is a popular **join target** (example: `roomLocation`), so it should exist early on the record.

### 4.3 Key format (single and multi-family)

- The key is a concatenation of one or more **segments**.
- Segment format (always):

```text
#<familyName>(<familyRecordKey>)
```

- For single-family emissions, the key is exactly one segment:
  - `#square(123)`
- For multi-family emissions, the key is multiple segments:
  - `#square(123)#zombie(456)`
- Multi-family ordering:
  - family names are ordered **lexicographically**
- Separator:
  - `#` is the only separator (no `::`, no commas)

### 4.4 Multi-family “nil members”

If it is hard to encode “expected but missing” join members (left joins), we **do not encode nil keys**.

Meaning:
- Only families that are actually present in the emission participate in the key.
- Example (left join): square present, zombie missing:
  - `#square(123)` (no `#zombie(nil)` segment)

### 4.5 Derived grouping outputs

For grouping shapes we settle on:
- `group_aggregate`: `WoMeta.key` = **groupName + groupKey**
- `group_enriched`: `WoMeta.key` = **the same compound key as a normal emission** (using the present families and their `record.woKey`).

For `group_aggregate`, this uses the same segment format as everything else:
- `#<groupName>(<groupKey>)`

For `group_enriched`, this uses the normal family-segment format from above (Section 4.3):
- `#<familyName>(<familyRecordKey>)` (and compound keys for multi-family rows)

Where:
- `groupName` comes from LQR metadata (`RxMeta.groupName` or `RxMeta.schema` when schema is the group name)
- `groupKey` comes from `RxMeta.groupKey`

For `group_aggregate`, this key identifies the **group**, not a specific event inside the group.
For `group_enriched`, the key identifies the **concrete family members on the row** (same as a normal join/multi-family emission).

### 4.6 No compatibility layer

When this refactor is implemented:
- No shims, aliases, or compatibility wrappers for old id fields.
- Call sites, tests, and docs are updated in one hard cut.

---

## 5) Data structures (examples)

### 5.1 Single-family emission (square)

WorldObserver base streams commonly emit a join-style container (even for one schema):

```lua
observation = {
  square = {
    squareId = 12603,
    x = 6787, y = 5336, z = 0,
    hasCorpse = false,
    IsoGridSquare = <userdata>,
    woKey = "x6787y5336z0", -- new (record-level); for squares we prefer tileLocation-style keys
    RxMeta = { schema="square", shape="record", id=1, sourceTime=1766928552786 },
  },
  RxMeta = {
    shape = "join_result",
    schemaMap = {
      square = { schema="square", sourceTime=1766928552786, joinKey=12603 },
    },
  },
  WoMeta = {
    key = "#square(x6787y5336z0)", -- new (emission-level)
  },
}
```

### 5.2 Multi-family emission (square + zombie join)

```lua
observation = {
  square = { woKey="x6787y5336z0", squareId=12603, RxMeta={ schema="square", shape="record", id=1 } },
  zombie = { woKey="4512", zombieId=4512, RxMeta={ schema="zombie", shape="record", id=77 } },
  RxMeta = {
    shape = "join_result",
    schemaMap = {
      square = { schema="square", joinKey=12603 },
      zombie = { schema="zombie", joinKey=12603 },
    },
  },
  WoMeta = {
    key = "#square(x6787y5336z0)#zombie(4512)",
  },
}
```

### 5.3 Left join with missing right side (no nil encoding)

```lua
observation = {
  square = { woKey="x6787y5336z0", squareId=12603, RxMeta={ schema="square", shape="record", id=1 } },
  zombie = nil,
  RxMeta = { shape="join_result", schemaMap = { square = {...}, zombie = {...} } },
  WoMeta = {
    key = "#square(x6787y5336z0)", -- zombie segment omitted
  },
}
```

### 5.4 Group aggregate emission (group identity)

From LQR docs: group aggregates are single records with grouping metadata in `RxMeta`.

```lua
g = {
  _count = 3,
  orders = { _sum = { total = 150 } },
  window = { start = 100, ["end"] = 110 },
  RxMeta = {
    shape = "group_aggregate",
    schema = "customers_grouped",  -- groupName
    groupName = "customers_grouped",
    groupKey = 1,
  },
  WoMeta = {
    key = "#customers_grouped(1)",
  },
}
```

### 5.5 Group enriched emission (compound key)

Group enriched view overlays live group metrics on a per-event structure.
Even though it’s “enriched”, the observation is still its own situation, so the key should identify the concrete family members (same as a normal multi-family emission):

```lua
row = {
  square = { woKey="x6787y5336z0", ... },
  zombie = { woKey="4512", ... },
  RxMeta = {
    shape = "group_enriched",
    groupName = "zombies_on_square",
    groupKey = 12603,
  },
  WoMeta = {
    key = "#square(x6787y5336z0)#zombie(4512)",
  },
}
```

---

## 6) Lifecycle (key computation rules)

### 6.1 Record creation time

- Each record builder assigns `record.woKey` (string).
- This remains attached to the record for its entire lifetime (including through joins and derived streams).

### 6.2 Emission time (single-family + join_result)

At the moment an observation is emitted to subscribers:

Implementation note:
- We attach `WoMeta` on the **outgoing edge** (right before calling subscriber callbacks).
- We do mutate the emission table to add `WoMeta`, but this is safe in practice because emissions are ephemeral values; we do not treat them as immutable “persistent” objects.

1) Determine emission shape:
   - If `observation.RxMeta.shape == "join_result"`:
     - Determine family names from `observation.RxMeta.schemaMap` keys (required).
       - If `schemaMap` is missing, **warn and skip** the emission.
     - For each family name in lexicographic order:
       - If `observation[familyName]` is a table and has `woKey` (string), append `#familyName(woKey)`.
       - If the family record is missing (`nil`), omit the segment (no nil encoding).
       - If the family record is present but its `woKey` is missing or not a string, **warn and skip** the emission.
     - Attach `observation.WoMeta.key` to the container.

2) If the emission is a single record shape:
   - `shape == "record"`:
     - family name: `observation.RxMeta.schema`
     - record key: `observation.woKey`
     - `WoMeta.key = "#<schema>(<woKey>)"`
     - If `observation.woKey` is missing or not a string, **warn and skip** the emission.

### 6.3 Emission time (group shapes)

If `observation.RxMeta.shape` is `group_aggregate`:

- `groupName = RxMeta.groupName or RxMeta.schema`
- `groupKey = RxMeta.groupKey`
- `WoMeta.key = "#<groupName>(<groupKey>)"`

If `observation.RxMeta.shape` is `group_enriched`:

- Treat it like a “normal” emission for keying purposes.
- Compute `WoMeta.key` as a compound key from the families present on the row:
  - Find all top-level fields on the row (excluding `RxMeta`/`WoMeta`) where the value is a table with `woKey` (string).
  - Sort those field names lexicographically.
  - Concatenate segments: `#<familyName>(<familyRecordKey>)`.
- If we can’t compute a compound key (no eligible families, or a present family is missing `woKey`), **warn and skip** the emission.

---

## 7) Debugging helper (ship in v1)

Add a WorldObserver debug helper that makes keys explainable in logs, e.g.:

- `WorldObserver.debug.describeWoKey(observation)`
  - Returns a compact string including:
    - emission `RxMeta.shape`
    - family list (if join_result)
    - `record.woKey` per family
    - computed `WoMeta.key`

Rationale:
- Keys are best-effort; when collisions happen, modders need a simple way to see *why*.

---

## 8) Impact / Scope of refactor (high level)

- Add `woKey` to each record type, family-by-family.
- Compute and attach `WoMeta.key` at emission time for:
  - base streams
  - derived/joined streams
  - group aggregate/enriched streams
- Update docs and examples to reference `WoMeta.key` (and later, PromiseKeeper Tier‑C can default `occurrenceId` to it).
- No compatibility layer; tests + call sites are updated in the same change set.

---

## 9) Pending decisions / open questions

1) **Override mechanism at `situations.define(...)`**
   - How can a modder override which key becomes the “occurrence key” for a situation?
   - (This is explicitly a follow-up discussion, but this RFC is the foundation.)

2) **PromiseKeeper WorldObserver adapter**
   - If Tier‑C is adopted, PK can default to:
     - `occurrenceId = observation.WoMeta.key`
     - `subject = observation`
   - Behavior when `WoMeta.key` is missing:
     - **warn and drop/skip** the observation for now.

3) **Third-party base families**
   - Deferred, but we should later define how mods can register a family and its `woKey` strategy.

---

## 10) Implementation plan (phased)

This is a foundational refactor that touches both the *record layer* and the *emission layer*.

The main moving parts:
- Add `record.woKey` (string) to each fact record type.
- Add emission-time `observation.WoMeta.key` computation on the outgoing edge.
- Provide tests that pin down the key format and failure/skip semantics.

### Phase 1 — Implement the shared keying utility (pure functions)

**Goal:** make the `WoMeta.key` computation testable without having to spin up probes/streams.

- Add a new module: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/observations/wo_meta.lua`
  - `buildSegment(familyName, recordKey)` → `#familyName(recordKey)` (string)
  - `computeKeyFromJoinResult(observation)` → `key | nil, reason`
    - Requires `observation.RxMeta.schemaMap`
    - Uses lexicographic order of schemaMap keys
    - Skips nil family records (no nil encoding)
    - If a present family record is missing a string `woKey`: return `nil, "missing_record_woKey"`
  - `computeKeyFromRecord(record)` → `key | nil, reason` (requires `record.RxMeta.schema` + `record.woKey`)
  - `computeKeyFromGroupAggregate(record)` → `#groupName(groupKey)` (string)
  - `computeKeyFromGroupEnriched(row)` → compound key from present family records with string `woKey`
  - `attachWoMeta(observation)` → `true | false, reason`
    - Mutates `observation.WoMeta = { key = ... }` when successful
    - Returns `false, reason` when key can’t be computed (caller will warn+skip)

- Add a debug helper directly to `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/debug.lua`:
  - `WorldObserver.debug.describeWoKey(observation)` → string
    - Intended for log/debug output (human-readable, compact).
    - Includes:
      - `RxMeta.shape`
      - computed `WoMeta.key` (or `<missing>`)
      - for join/group_enriched: family names + each `record.woKey` (best-effort)
      - for group shapes: `groupName` + `groupKey` (best-effort)

### Phase 2 — Prototype the end-to-end lifecycle on one fact type (recommended: squares)

**Goal:** prove the “record.woKey → emission.WoMeta.key” lifecycle works end-to-end in both tests and a PZ smoke run.

- Update square records to include `record.woKey`:
  - File: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/squares/record.lua`
  - Candidate strategy (to confirm during implementation): `tileLocation` (string)
    - No fall-back to `squareId`
- Wire emission-time attachment at the outgoing edge:
  - File: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/observations/core.lua`
  - In `BaseMethods:subscribe(callback, ...)` wrap the callback:
    - call `wo_meta.attachWoMeta(observation)`
    - if it returns `false`, warn and **do not call** the subscriber callback (skip emission)
  - Logging:
    - add a dedicated tag (example: `WO.WOMETA`) and log `reason` + `WorldObserver.debug.describeWoKey(observation)`
- Add a targeted smoke/prototype:
  - Reuse an existing square smoke (e.g. `Contents/mods/WorldObserver/42/media/lua/shared/examples/smoke_situation_factory_squares.lua`)
  - Add one log line to print `observation.WoMeta.key` so we can see it in live output

### Phase 3 — Busted tests (start right after the prototype)

We can (and should) write most of the busted coverage immediately after Phase 2, before we finish rolling `woKey` out to every record type.

**New tests (recommended):**

- Add `tests/unit/wo_meta_keys_spec.lua`
  - Unit-test `WorldObserver/observations/wo_meta.lua` in isolation:
    - join_result compound keys (single + multi-family)
    - lexicographic ordering of families
    - “nil members are omitted”
    - group_aggregate keying (`#groupName(groupKey)`)
    - group_enriched keying uses compound key (not group identity)
    - failure reasons (missing schemaMap, missing record.woKey, wrong types) return `false` and are skippable

**Prototype-focused updates:**
- Extend the square record/stream tests to assert:
  - `record.woKey` exists and is a string
  - `observation.WoMeta.key` exists and matches the expected format

Why busted coverage matters here:
- We’re introducing a *new hard dependency* (“key exists or emission is skipped”), so regression risk is high and will otherwise show up only as “nothing happens” in-game.

### Phase 4 — Roll out `record.woKey` to the remaining fact record types (family-by-family, with tests in lockstep)

**Goal:** once the outgoing-edge behavior is enabled globally, any stream that emits a family record must have `woKey`, otherwise emissions will be skipped.

Add `woKey` to each record builder (exact strategies can be refined case-by-case, but keep them string-only and “stable-ish”), and update the corresponding record specs at the same time:

- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/rooms/record.lua`
  - Likely `record.woKey = record.roomId` (already a string tileLocation-derived id)
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/players/record.lua`
  - Likely `record.woKey = record.playerKey` (already a stable-ish string)
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/zombies/record.lua`
  - `record.woKey = tostring(zombieId)`; fallback to `zombieOnlineId`, then to `tileLocation` if needed
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/vehicles/record.lua`
  - Likely `record.woKey = tostring(record.sqlId or record.vehicleId)`
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/items/record.lua`
  - Likely `record.woKey = tostring(record.itemId)`
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/dead_bodies/record.lua`
  - Likely `record.woKey = tostring(record.deadBodyId)`
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/facts/sprites/record.lua`
  - Likely `record.woKey = record.spriteKey`

**Update existing record tests:**
- Extend the per-family record specs to assert `record.woKey` exists and is a string:
  - `tests/unit/zombies_spec.lua` / `tests/unit/zombies_observations_spec.lua` (where applicable)
  - `tests/unit/rooms_record_spec.lua`
  - `tests/unit/vehicles_spec.lua`
  - `tests/unit/items_record_spec.lua`
  - `tests/unit/dead_bodies_record_spec.lua`
  - `tests/unit/players_record_spec.lua`
  - `tests/unit/sprites_record_spec.lua`

### Phase 5 — Documentation + architecture update

- Update internal architecture doc:
  - `docs_internal/code_architecture.md`
  - Add a short section: “WoMeta vs RxMeta” and where WoMeta is computed (outgoing edge in observation subscribe).
- Update user-facing docs at the right layer (WO, not PK):
  - `docs/guides/stream_basics.md` (or a new guide) to mention:
    - `record.woKey` (record-local, family-owned)
    - `observation.WoMeta.key` (emission-level, compound for derived streams)
    - “warn + skip” behavior when key cannot be computed

---

## 11) What may still be missing from this plan

- **Deciding the “best” `woKey` per family** (especially zombies, where id availability may differ by mode).
- **Logging ergonomics**: for now, noisy `warn + skip` logs are acceptable; no throttling in the first implementation.
- **Debug tooling**: ship `WorldObserver.debug.describeWoKey(observation)` as part of the first implementation PR.
- **Derived stream edge cases**: confirm which shapes we see in practice (especially `group_enriched`) and add a small smoke that exercises them.
