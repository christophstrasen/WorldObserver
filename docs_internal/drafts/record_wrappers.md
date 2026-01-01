# RFC: record wrappers for record helpers (ergonomics across contexts)

## Summary

WorldObserver has two helper “surfaces” today:

- **Stream helpers** (chainable operators): `stream:hasFloorMaterial("Road%")`, `stream:hasOutfit(...)`, `stream.helpers.square:hasFloorMaterial("Road%")`, ...
- **Record helpers** (predicates/utilities): `WorldObserver.helpers.square.record.squareHasFloorMaterial(squareRecord, "Road%")`, `...getIsoGridSquare(squareRecord)`, ...

This RFC proposes a small, explicit **record wrapping / decoration** API so modders can use **record helpers with the same call style everywhere**, including PromiseKeeper actions, while keeping stream semantics unchanged.

Key preference (from discussion): instead of returning a proxy wrapper that stores `.raw` and forces “back out into `helpers.*.record`”, we decorate the record *in-place* by setting a metatable. That keeps `subject.square` feeling like “the record, just nicer”:

```lua
local Square = WorldObserver.helpers.square
local square = Square:wrap(subject.square) -- returns the same table (decorated)

if square:hasFloorMaterial("Road%") then
  local iso = square:getIsoGridSquare()
end
```

The wrap operation exposes a **whitelisted** set of `record.*` functions as colon-methods on the record table via `__index`.

---

## Motivation / pain points

- Helpers feel “intransparent”: different access patterns depending on whether you’re holding a stream or a record.
- In PromiseKeeper actions (subject = WO observation table), modders lose the ergonomic stream helper surface and end up with verbose helper calls like:
  - `WorldObserver.helpers.square.record.getIsoGridSquare(subject.square)`
- The existing helper plumbing (`withHelpers`, `enabled_helpers`, method injection via `__index`) is stream-focused; it does not address record ergonomics.

We want a small, composable tool that:

- improves ergonomics in record contexts (actions, callbacks, derived data processing),
- doesn’t change what records *are* (still plain data tables),
- doesn’t add hidden global activation rules (“why does this method exist here but not there?”).

---

## Goals

- **Consistency:** “I have a square record” → I can call `:hasFloorMaterial(...)` / `:getIsoGridSquare()` in any context.
- **Explicitness:** usage is opt-in and local (`Square:wrap(record)`), no implicit global decoration.
- **Compatibility:** works in vanilla Lua 5.1 + PZ/Kahlua; does not require changes to record builders.
- **Patchability:** helper sets remain override-friendly (existing `if fn == nil then fn = ... end` patterns).
- **Ergonomics:** the record stays a “normal table” with its existing fields; methods are resolved via `__index`.

---

## Non-goals

- No changes to stream helper attachment (`ObservationStream:withHelpers(...)`, `enabled_helpers`, `stream.helpers.*`).
- No global auto-decoration of all emitted records (wrapping remains explicit/opt-in).
- No guarantee that hydration will succeed (e.g. `getIsoGridSquare()` remains best-effort).
- No introspection/rewrite of function signatures (we will not try to auto-detect “record-first” helpers).

---

## Proposal

### 1) `HelperSet:wrap(record, opts)` decorates the record and returns it

Each built-in helper set (square/zombie/...) provides a `wrap` function (colon-style).

Contract:

```lua
local wrapped = Square:wrap(record)
assert(wrapped == record) -- same table, now with methods via metatable
```

### 2) Methods are derived from a whitelist

We do **not** auto-expose all `record.*` functions by default.

Reason: some `record.*` functions are “static utilities” (they don’t take a record as first argument), e.g. `tileLocationFromCoords(x, y, z)` in square helpers. Blindly turning every `record.<name>` into a `wrapper:<name>(...)` method would produce confusing or wrong call shapes.

Instead, each helper set explicitly defines (and documents) the small method surface it wants to expose on records. The “whitelist” is the set of wrapper methods we implement on the shared `__index` method table.

### 3) Implementation approach: stable metatable on the record

To keep per-call overhead low and avoid allocating a new closure per wrap call:

- Each helper family owns a single stable metatable for its record type.
- Wrapping sets that metatable on the record (idempotent if already wrapped).
- `__index` resolves methods from a shared method table (generated from the whitelist).
- Wrapper methods should not capture function references directly; they should delegate via `HelperSet.record[fnName]` at call-time so mod patches and reloads remain respected.

`pairs(record)` continues to enumerate only the record’s real fields; “virtual” methods from `__index` do not appear in `pairs()`.

Implementation should live in a small internal utility that helper sets call (so square/zombie/etc. stay consistent), while each helper set remains the owner of its whitelist decisions.

---

## Example UX (intended)

### In a PromiseKeeper action

```lua
pk.actions.define("spawnRoadCone", function(subject)
  local Square = wo.helpers.square
  local square = Square:wrap(subject.square)

  if not square:hasFloorMaterial("Road%") then
    return
  end

  local isoSquare = square:getIsoGridSquare()
  if not isoSquare then
    return
  end

  -- ...
end)
```

### Direct helper calls (still available)

```lua
local Square = wo.helpers.square
Square:wrap(subject.square)

local iso = Square.record.getIsoGridSquare(subject.square, { cache = true })
```

---

## Interactions with existing helper architecture

- This RFC does not require `ObservationStream:withHelpers(...)`.
- Wrapped record methods are **record-context only**; they do not change or mimic stream operator semantics.
- Third-party helper sets:
  - A third-party helper set can opt into the same pattern by implementing `wrap(record)` and exposing a small, explicit wrapped method set.
  - This RFC does not (yet) specify a global “register record wrapper family” API; that can be layered later if needed.

---

## Risks / tradeoffs

- **Metatable leakage:** once wrapped, any other code holding the same record table will also see the methods (because the metatable lives on the record). This is often fine/desirable, but it’s no longer “pure data only”.
- **Metatable collisions:** if a record already has a metatable (user-added or future WO changes), wrapping must either (a) refuse, or (b) explicitly compose/chains the existing metatable behavior. Silent overwrite would be risky.
- **Field-name collisions:** if a data field exists with the same name as a would-be method, that field will shadow the method (and `record:<name>()` will likely error). This can happen via mod extenders *and* via built-in record fields (e.g. many records already have `hasCorpse`, `isRunning`, ... fields, so we cannot also expose `:hasCorpse()` / `:isRunning()` unless we rename the data fields). Mitigation: encourage namespacing under `record.extra.<ModId>` and keep the wrapped-method whitelist tight.
- **Truthiness surprises:** after wrapping, `if record.hasFloorMaterial then ... end` becomes true (it is a function via `__index`). Prefer `record:hasFloorMaterial(...)` for the boolean meaning, and `rawget(record, "hasFloorMaterial")` if you truly mean “does this data field exist?”
- **Copies lose wrapping:** any code that deep-copies records via `pairs()` (common in Lua) will not copy the metatable; the copied table will not have methods unless it is wrapped again.
- **Policy mismatch:** this approach uses metatables on records. That should be an explicit, documented exception to the general preference to avoid metatable magic.

---

## Status (implemented)

This RFC is implemented for:
- **zombies**
- **squares**

Decisions (from discussion):
- **In-place decoration:** `Zombie:wrap(record)` sets a metatable on the record table and returns the same table.
- **Refuse on metatable:** if a record already has a metatable (and it’s not our wrapper metatable), we log and return `nil, "hasMetatable"`.
- **Whitelist:** we only expose a small list of methods, and we avoid methods that would collide with record boolean fields (example: `hasTarget` stays a field; no `:hasTarget()` method).
- **Side effects allowed:** wrapper methods may perform best-effort hydration and may cache engine userdata back onto the record (example: `record.IsoZombie`).
- **Patchability:** wrapper methods delegate via `ZombieHelpers.record.<fn>` (and `ZombieHelpers.<fn>`) at call time so mods can override helpers.
- **No persistence guarantee:** downstream frameworks (notably LQR) may shallow-copy records and drop metatables. The intended pattern is “wrap close to use” in record contexts (PromiseKeeper actions, callbacks).
- **Docs exist:** the user-facing guide documents wrapping in `docs/guides/helpers.md`.

### Intended UX (PromiseKeeper action)

```lua
local Zombie = wo.helpers.zombie
local zombie = Zombie:wrap(subject.zombie)
if not zombie then return end

if zombie:hasOutfit("Police%") then
  zombie:highlight(2000, { color = { 0, 0, 1, 1 } })
end
```

### Proposed zombie wrapper methods

- `zombie:getIsoZombie()` → delegates to `ZombieHelpers.record.getIsoZombie(record)` (best-effort; may cache `record.IsoZombie`)
- `zombie:hasOutfit(patternOrList)` → delegates to `ZombieHelpers.record.zombieHasOutfit(record, patternOrList)`
- `zombie:highlight(durationMs, opts)` → delegates to `ZombieHelpers.highlight(record, durationMs, opts)` (best-effort)

### Proposed square wrapper methods

- `square:getIsoGridSquare()` → delegates to `SquareHelpers.record.getIsoGridSquare(record)` (best-effort; may cache `record.IsoGridSquare`)
- `square:hasFloorMaterial(pattern)` → delegates to `SquareHelpers.record.squareHasFloorMaterial(record, pattern)`
- `square:highlight(durationMs, opts)` → delegates to `SquareHelpers.highlight(record, durationMs, opts)` (best-effort)
