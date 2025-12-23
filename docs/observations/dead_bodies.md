# Observation: dead bodies

Goal: react to dead bodies observed on the ground.

Quickstart first (recommended):
- [Quickstart](../quickstart.md)

## Declare interest (required)

WorldObserver does no dead body probing unless at least one mod declares interest.

### Option A: playerSquare (lowest noise; good for testing)

Emits dead bodies on the square the player currently stands on.

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "deadBodies.playerSquare", {
  type = "deadBodies",
  scope = "playerSquare",
  cooldown = { desired = 0 },
  highlight = true,
})
```

### Option B: near (probe around a target)

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "featureKey", {
  type = "deadBodies",
  scope = "near",
  target = { player = { id = 0 } }, -- optional; defaults to player 0
  radius = { desired = 8 },
  staleness = { desired = 2 },
  cooldown = { desired = 5 },
  highlight = true,
})
```

### Option C: vision (probe; visible squares only)

Like `near`, but only emits dead bodies on squares currently visible to the player.

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "deadBodies.vision", {
  type = "deadBodies",
  scope = "vision",
  target = { player = { id = 0 } },
  radius = { desired = 10 },
  staleness = { desired = 5 },
  cooldown = { desired = 10 },
  highlight = true,
})
```

## Subscribe

```lua
local sub = WorldObserver.observations:deadBodies()
  :distinct("deadBody", 10)
  :subscribe(function(observation)
    local body = observation.deadBody
    print(("[WO] deadBodyId=%s loc=(%s,%s,%s) square=%s source=%s"):format(
      tostring(body.deadBodyId),
      tostring(body.x),
      tostring(body.y),
      tostring(body.z),
      tostring(body.squareId),
      tostring(body.source)
    ))
  end)
```

Remember to stop:
- `sub:unsubscribe()`
- and your interest lease: `lease:stop()` (see [Lifecycle](../guides/lifecycle.md))

## Record fields (what `observation.deadBody` contains)

Common fields on the dead body record:
- `deadBodyId` (from `IsoDeadBody:getObjectID()`; if missing the record is skipped)
- `x`, `y`, `z`
- `squareId`
- `source` (which producer saw it)
- `sourceTime` (ms, in-game clock)

Optional engine object (when enabled in config):
- `IsoDeadBody`

Notes:
- `deadBodyId` is a string in practice (example observed in-engine: `DeadBody-1`).

## Extending the record (advanced)

If you need extra fields on `observation.deadBody`, register a record extender:
- [Guide: extending record fields](../guides/extending_records.md)

## Built-in stream helpers

```lua
local stream = WorldObserver.observations:deadBodies()
  :deadBodyFilter(function(body)
    return body.squareId ~= nil
  end)
```

Available today:
- `:deadBodyFilter(predicate)`

## Supported interest configuration (today)

Supported combinations for `type = "deadBodies"`:

| scope        | target key | target shape                                  | Notes |
|--------------|------------|-----------------------------------------------|-------|
| playerSquare | player     | `target = { player = { id = 0 } }`            | Emits only the square under the player. |
| near         | player     | `target = { player = { id = 0 } }`            | Probe around player. |
| near         | square     | `target = { square = { x, y, z } }`           | Probe around a fixed square (`z` defaults to 0). |
| vision       | player     | `target = { player = { id = 0 } }`            | Probe; only emits dead bodies on squares visible to the player. |

Meaningful knobs:
- Probe scopes (`near`, `vision`): `radius`, `staleness`, `cooldown`, `highlight`.
- `playerSquare`: `cooldown`, `highlight`.

## Why you might see nothing

- You didn’t declare interest (no lease → no probing).
- There are no dead bodies in the scanned area (you may need to find/kill something first).
- Your `cooldown`/`:distinct(...)` settings filter out repeats.
