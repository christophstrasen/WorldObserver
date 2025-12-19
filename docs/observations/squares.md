# Observation: squares

Goal: react to what WorldObserver observes about world squares (tiles).

Quickstart first (recommended):
- [Quickstart](../quickstart.md)

## Subscribe

```lua
local sub = WorldObserver.observations.squares()
  :subscribe(function(observation)
    local s = observation.square
    print(("[WO] squareId=%s x=%s y=%s z=%s corpse=%s source=%s"):format(
      tostring(s.squareId),
      tostring(s.x),
      tostring(s.y),
      tostring(s.z),
      tostring(s.hasCorpse),
      tostring(s.source)
    ))
  end)
```

Remember to stop:
- `sub:unsubscribe()`
- and your interest lease: `lease:stop()` (see [Lifecycle](../guides/lifecycle.md))

## Record fields (what `observation.square` contains)

Common fields on the square record:
- `squareId` (stable id for a square)
- `x`, `y`, `z`
- `hasCorpse`
- `hasBloodSplat`
- `source` (which producer saw it, e.g. `"probe"`)
- `sourceTime` (ms, in-game clock)
- `observedAtTimeMS` (ms, in-game clock)

Best-effort engine object (do not rely on it always existing):
- `IsoSquare` (live `IsoGridSquare` userdata, may be missing/stale)

## Built-in stream helpers (recommended)

These are convenience filters you can chain:

```lua
local stream = WorldObserver.observations.squares()
  :squareHasCorpse()
  :distinct("square", 10)
```

If you want custom boolean logic (AND/OR), use `:whereSquare(...)` with record predicates:

```lua
local SquareHelper = WorldObserver.helpers.square.record

local stream = WorldObserver.observations.squares()
  :whereSquare(function(s)
    return SquareHelper.squareHasCorpse(s) or SquareHelper.squareHasBloodSplat(s)
  end)
```

Available today:
- `:squareHasCorpse()`
- `:squareHasBloodSplat()`
- `:squareHasIsoSquare()` (keeps only records that can resolve a live `IsoGridSquare`)

Record helpers (use inside `:whereSquare(...)` or inside Rx `:filter(...)` after `:asRx()`):
- `WorldObserver.helpers.square.record.squareHasCorpse(squareRecord)`
- `WorldObserver.helpers.square.record.squareHasBloodSplat(squareRecord)`
- `WorldObserver.helpers.square.record.squareHasIsoSquare(squareRecord, opts)` (may hydrate/cache `squareRecord.IsoSquare`)

## About `IsoSquare` (important)

WorldObserver streams are “observations, not entities”.

That means:
- You should not store `IsoSquare` and use it later.
- Prefer `squareId` and `x/y/z` as your stable handle.
- If you need a live `IsoGridSquare` right now, first filter with `:squareHasIsoSquare()` and then use `record.IsoSquare`.
