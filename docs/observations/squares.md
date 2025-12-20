# Observation: squares

Goal: react to what can be observed about world squares (tiles).

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
- `source` (which producer saw it, e.g. `"probe"`)
- `sourceTime` (ms, in-game clock)
- `observedAtTimeMS` (ms, in-game clock)

Best-effort engine object (do not rely on it always existing):
- `IsoGridSquare` (live engine object, may be missing/stale)

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
    return SquareHelper.squareHasCorpse(s) and SquareHelper.squareHasIsoGridSquare(s)
  end)
```

Available today:
- `:squareHasCorpse()`
- `:squareHasIsoGridSquare()` (keeps only records that can resolve a live `IsoGridSquare`)

Record helpers (use inside `:whereSquare(...)` or inside Rx `:filter(...)` after `:asRx()`):
- `WorldObserver.helpers.square.record.squareHasCorpse(squareRecord)`
- `WorldObserver.helpers.square.record.squareHasIsoGridSquare(squareRecord, opts)` (may hydrate/cache `squareRecord.IsoGridSquare`)

## Choosing an interest type (why streams can go quiet)

WorldObserver can observe squares in different ways depending on what interest you declare.

- `type = "squares"` with `scope = "onLoad"`: event-driven. You’ll see bursts when the game loads new squares (entering new chunks). If you walk around inside already-loaded areas, it can go quiet. It also won’t notice “new corpse appeared on an already-loaded square” until that square is loaded again.
- `type = "squares"` with `scope = "near"`: probe-driven. WO actively scans around a target you specify (player or static square) on a cadence (controlled by `staleness`/`radius`/`cooldown`), so it can keep producing observations as you move.
- `type = "squares"` with `scope = "vision"`: probe-driven. Like `scope = "near"` but only emits squares currently visible to the player. Requires a player target.

## About `IsoGridSquare` (important)

WorldObserver streams are “observations, not entities”.

That means:
- You should not store `IsoGridSquare` and use it later.
- Prefer `squareId` and `x/y/z` as your stable handle.
- If you need a live `IsoGridSquare` right now, first filter with `:squareHasIsoGridSquare()` and then use `record.IsoGridSquare`.
