# Observation: squares

Goal: react to what can be observed about world squares (tiles).

Quickstart first (recommended):
- [Quickstart](../quickstart.md)

## Note on IDs and stability of Squares:
- Use `x/y/z` as the long-term stable anchor. `squareId` should not be relied on across game reloads.

## Subscribe

```lua
local sub = WorldObserver.observations:squares()
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
- `squareId` (stable within a running session; do not rely on it across game reloads)
- `x`, `y`, `z`
- `hasCorpse`
- `source` (which producer saw it, e.g. `"probe"`)
- `sourceTime` (ms, in-game clock)

Best-effort engine object (do not rely on it always existing):
- `IsoGridSquare` (live engine object, may be missing/stale)

## Extending the record (advanced)

If you need extra fields on `observation.square`, register a record extender:
- [Guide: extending record fields](../guides/extending_records.md)

## Built-in stream helpers (recommended)

These are convenience filters you can chain:

```lua
local stream = WorldObserver.observations:squares()
  :squareHasCorpse()
  :distinct("square", 10)
```

If you want custom boolean logic (AND/OR), use `:squareFilter(...)` with record predicates:

```lua
local SquareHelper = WorldObserver.helpers.square.record

local stream = WorldObserver.observations:squares()
  :squareFilter(function(s)
    return SquareHelper.squareHasCorpse(s) and SquareHelper.squareHasIsoGridSquare(s)
  end)
```

Available today:
- `:squareHasCorpse()` (filters on `square.hasCorpse`, no hydration)
- `:squareHasIsoGridSquare()` (keeps only records that can resolve a live `IsoGridSquare`)
- `:setSquareMarker(textOrFn, opts)` (best-effort label; requires Doggy's VisualMarkers; accepts square-like records with `x/y/z` or a live `IsoGridSquare`)

Record helpers (use inside `:squareFilter(...)` or inside Rx `:filter(...)` after `:asRx()`):
- `WorldObserver.helpers.square.record.squareHasCorpse(squareRecord)` (checks the `hasCorpse` field only)
- `WorldObserver.helpers.square.record.squareHasIsoGridSquare(squareRecord, opts)` (may hydrate/cache `squareRecord.IsoGridSquare`)

Example (sets a label showing the square id, reusing the same marker per square):

```lua
WorldObserver.observations:squares()
  :setSquareMarker(function(obs)
    return ("squareId=%s"):format(tostring(obs.square.squareId))
  end)
  :subscribe(function(_) end)
```

## Choosing an interest type (why streams can go quiet)

WorldObserver can observe squares in different ways depending on what interest you declare.

- `type = "squares"` with `scope = "onLoad"`: event-driven. You’ll see bursts when the game loads new squares (entering new chunks). If you walk around inside already-loaded areas, it can go quiet. It also won’t notice “new corpse appeared on an already-loaded square” until that square is loaded again.
- `type = "squares"` with `scope = "near"`: probe-driven. WO actively scans around a target you specify (player or static square) on a cadence (controlled by `staleness`/`radius`/`cooldown`), so it can keep producing observations as you move.
- `type = "squares"` with `scope = "vision"`: probe-driven. Like `scope = "near"` but only emits squares currently visible to the player (player target only).

## About `IsoGridSquare` (important)

WorldObserver streams are “observations, not entities”.

That means:
- You should not store `IsoGridSquare` and use it later.
- Prefer `x/y/z` as your long-term stable handle. `squareId` should not be relied on across game reloads (TODO: confirm stricter guarantees later).
- If you need a live `IsoGridSquare` right now, first filter with `:squareHasIsoGridSquare()` and then use `record.IsoGridSquare`.

## Supported interest configuration (today)

WorldObserver will only produce square observations once at least one mod declares interest.

Supported combinations for `type = "squares"`:

| scope   | target key | target shape                                  | Notes |
|---------|------------|-----------------------------------------------|-------|
| near    | player     | `target = { player = { id = 0 } }`            | Probe around player. |
| near    | square     | `target = { square = { x, y, z } }`           | Probe around a fixed square (`z` defaults to 0). |
| vision  | player     | `target = { player = { id = 0 } }`            | Probe; only emits squares visible to the player. |
| onLoad  | n/a        | n/a                                           | Event-driven: emits when squares load. |

Meaningful settings:
- Probe scopes (`near`, `vision`): `radius`, `staleness`, `cooldown`, `highlight`.
- Event scope (`onLoad`): `cooldown`, `highlight`.
