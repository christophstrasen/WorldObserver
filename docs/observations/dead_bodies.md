# Observation: dead bodies

Goal: react to dead bodies observed on the ground.

Quickstart first (recommended):
- [Quickstart](../quickstart.md)

## Declare interest (required)

WorldObserver does no dead body probing unless at least one mod declares interest.

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "featureKey", {
  type = "deadBodies",
  scope = "near",
  radius = { desired = 8 },
  staleness = { desired = 2 },
  cooldown = { desired = 5 },
})
```

## Subscribe

```lua
local sub = WorldObserver.observations.deadBodies()
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
- `deadBodyId` (from `getObjectID`; if missing the record is skipped)
- `x`, `y`, `z`
- `squareId`
- `source` (which producer saw it)
- `sourceTime` (ms, in-game clock)

Optional engine object (when enabled in config):
- `IsoDeadBody`

## Extending the record (advanced)

If you need extra fields on `observation.deadBody`, register a record extender:
- [Guide: extending record fields](../guides/extending_records.md)

## Built-in stream helpers

```lua
local stream = WorldObserver.observations.deadBodies()
  :whereDeadBody(function(body)
    return body.squareId ~= nil
  end)
```

Available today:
- `:whereDeadBody(predicate)`

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
