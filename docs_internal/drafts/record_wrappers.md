# RFC: record wrappers for record helpers (ergonomics across contexts)

## Summary

WorldObserver has two helper “surfaces” today:

- **Stream helpers** (chainable operators): `stream:isRoad()`, `stream:hasOutfit(...)`, `stream.helpers.square:isRoad()`, ...
- **Record helpers** (predicates/utilities): `WorldObserver.helpers.square.record.isRoad(squareRecord)`, `...getIsoGridSquare(squareRecord)`, ...

This RFC proposes a small, explicit **record wrapper** API so modders can use **record helpers with the same call style everywhere**, including PromiseKeeper actions, without mutating records or changing stream semantics:

```lua
local Square = wo.helpers.square
local square = Square:wrap(subject.square)

if square:isRoad() then
  local iso = square:getIsoGridSquare()
end
```

The wrapper exposes a **whitelisted** set of `record.*` functions as colon-methods on a wrapper object.

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

- **Consistency:** “I have a square record” → I can call `:isRoad()` / `:getIsoGridSquare()` in any context.
- **Explicitness:** wrapper usage is opt-in and local (`Square:wrap(record)`), no implicit global decoration.
- **Compatibility:** works in vanilla Lua 5.1 + PZ/Kahlua; does not require changes to record builders.
- **Patchability:** helper sets remain override-friendly (existing `if fn == nil then fn = ... end` patterns).
- **Low risk:** wrapper does not mutate records; does not rely on record metatable behavior.

---

## Non-goals

- No changes to stream helper attachment (`ObservationStream:withHelpers(...)`, `enabled_helpers`, `stream.helpers.*`).
- No attempt to make `subject.square:<method>()` work without wrapping (that would require mutating the record or setting its metatable).
- No guarantee that hydration will succeed (e.g. `getIsoGridSquare()` remains best-effort).
- No introspection/rewrite of function signatures (we will not try to auto-detect “record-first” helpers).

---

## Proposal

### 1) `HelperSet:wrap(record, opts)` returns a wrapper object

Each built-in helper set (square/zombie/...) may provide a `wrap` function (colon-style or dot-style).

Suggested shape:

```lua
local wrapper = {
  raw = record,          -- the original record table
  record = recordHelpers -- the helperSet.record table (for power-users / escape hatches)
}
```

### 2) Wrapper methods are derived from a whitelist

We do **not** auto-expose all `record.*` functions by default.

Reason: some `record.*` functions are “static utilities” (they don’t take a record as first argument), e.g. `tileLocationFromCoords(x, y, z)` in square helpers. Blindly turning every `record.<name>` into a `wrapper:<name>(...)` method would produce confusing or wrong call shapes.

Instead, each helper set declares an explicit whitelist of record-first functions to expose as wrapper methods:

```lua
HelperSet.record_wrapped = {
  isRoad = true,
  getIsoGridSquare = true,
  squareHasCorpse = true,
  squareHasIsoGridSquare = true,
  squareFloorMaterialMatches = true,
  -- ...
}
```

For each whitelisted function `fnName`, the wrapper supports:

```lua
wrapper:fnName(...)  -- calls HelperSet.record[fnName](wrapper.raw, ...)
```

### 3) Implementation approach: shared method table + metatable on the wrapper (not on the record)

To keep per-call overhead low and avoid allocating a new closure per wrapper method, we can implement wrappers with a shared `__index` table (or `__index` function) per helper family:

- **Allowed “metatable magic”:** only on the wrapper object, not on emitted records.
- Wrapper metatable is stable and local to the helper set; it should not leak to record tables.

Alternative (no metatables): assign method closures directly onto each wrapper at creation time. This is simpler to reason about but creates more allocations.

### 4) Where this lives

Option A (per helper set, simplest): implement `wrap` directly in each helper set file (e.g. `helpers/square.lua`).

Option B (shared utility, less duplication): add a small internal utility (e.g. `WorldObserver/helpers/record_wrapper.lua`) that helper sets call with:

- `recordHelpers` table
- `record_wrapped` whitelist
- optional naming/customizations

Helper sets remain the owners of their whitelist decisions.

---

## Example UX (intended)

### In a PromiseKeeper action

```lua
pk.actions.define("spawnRoadCone", function(subject)
  local Square = wo.helpers.square
  local square = Square:wrap(subject.square)

  if not square:isRoad() then
    return
  end

  local isoSquare = square:getIsoGridSquare()
  if not isoSquare then
    return
  end

  -- ...
end)
```

### Escape hatch (power-users)

```lua
local square = wo.helpers.square:wrap(subject.square)
local iso = square.record.getIsoGridSquare(square.raw, { cache = true })
```

---

## Interactions with existing helper architecture

- This RFC does not require `ObservationStream:withHelpers(...)`.
- Wrapper methods are **record-context only**; they do not change or mimic stream operator semantics.
- Third-party helper sets:
  - A third-party helper set can opt into the same pattern by providing `record_wrapped` + `wrap`.
  - This RFC does not (yet) specify a global “register record wrapper family” API; that can be layered later if needed.

---

## Risks / tradeoffs

- **Discoverability:** wrappers add another surface. Mitigation: document a single recommended pattern (“wrap in record contexts; stream helpers on streams”).
- **Allocation:** each `wrap(record)` allocates a wrapper table. Mitigation: targeted usage in actions / low-rate code paths; avoid wrapping in hot per-record stream callbacks.
- **Naming collisions:** wrapper method namespace is per-family, but if we auto-expose large whitelists, names should still remain coherent within the family.
- **Policy mismatch:** record wrappers rely on metatables (on wrappers). This is contained, but it should be an explicit exception to the general preference to avoid metatable magic.

---

## Open questions

1) Do we want a consistent naming convention for wrapper-returning functions?
   - `Square:wrap(record)` vs `Square.record:wrap(record)` vs `Square.wrapRecord(record)`
2) Should the wrapper store `.raw` and `.record` with these exact field names, or hide them?
3) Should wrapper methods accept the same `opts` tables as the underlying record helper (pass-through), or do we want wrapper-level defaults?
4) Should we add a small `docs/guides/helpers.md` section teaching the wrapper pattern (once implemented)?

