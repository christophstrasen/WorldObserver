# Observation: zombies

Goal: react to what WorldObserver observes about zombies (positions, movement, targeting).

Quickstart first (recommended):
- [Quickstart](../quickstart.md)

## Declare interest (required)

WorldObserver does no zombie probing unless at least one mod declares interest.

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "featureKey", {
  type = "zombies",
  scope = "allLoaded",      -- default today (and only supported scope)
  radius = { desired = 25 }, -- filter emissions; does not avoid scanning the loaded zombie list
  zRange = { desired = 0 },  -- floors above/below the player
  staleness = { desired = 2 },
  cooldown = { desired = 2 },
})
```

## Subscribe

```lua
local sub = WorldObserver.observations:zombies()
  :subscribe(function(observation)
    local z = observation.zombie
    print(("[WO] zombieId=%s tile=%s,%s,%s hasTarget=%s kind=%s"):format(
      tostring(z.zombieId),
      tostring(z.tileX),
      tostring(z.tileY),
      tostring(z.tileZ),
      tostring(z.hasTarget),
      tostring(z.targetKind)
    ))
  end)
```

Remember to stop:
- `sub:unsubscribe()`
- and your interest lease: `lease:stop()` (see [Lifecycle](../guides/lifecycle.md))

## Record fields (what `observation.zombie` contains)

Common fields on the zombie record:
- `zombieId` (stable id)
- `zombieOnlineId` (0 in singleplayer, set in MP)
- `x`, `y`, `z` (world coords, may be fractional)
- `tileX`, `tileY`, `tileZ` (tile coords, integers)
- `squareId` (best-effort “current square id”)
- `outfitName` (outfit name string, may be nil/empty when unknown)
- movement: `isMoving`, `isRunning`, `isCrawling`, `locomotion`
- targeting: `hasTarget`, `targetId`, `targetKind`, `targetVisible`, `targetSeenSeconds`
- target coords: `targetX`, `targetY`, `targetZ`, `targetSquareId`
- `source` (which producer saw it)
- `sourceTime` (ms, in-game clock)

Engine object:
- Usually not included. If you need one, use `WorldObserver.helpers.zombie.record.getIsoZombie(record)` as best-effort rehydration.

## Extending the record (advanced)

If you need extra fields on `observation.zombie`, register a record extender:
- [Guide: extending record fields](../guides/extending_records.md)

## Built-in stream helpers

```lua
local stream = WorldObserver.observations:zombies()
  :zombieHasTarget()
  :distinct("zombie", 2)
```

If you want custom boolean logic, use `:whereZombie(...)` with record predicates:

```lua
local ZombieHelper = WorldObserver.helpers.zombie.record

local stream = WorldObserver.observations:zombies()
  :whereZombie(ZombieHelper.zombieHasTarget)
```

Available today:
- `:zombieHasTarget()` (keeps only zombies that currently have a target)

Record helpers (use inside `:whereZombie(...)` or inside Rx `:filter(...)` after `:asRx()`):
- `WorldObserver.helpers.zombie.record.zombieHasTarget(zombieRecord)`

## Supported interest configuration (today)

Supported combinations for `type = "zombies"`:

| scope     | target key | target shape | Notes |
|-----------|------------|--------------|-------|
| allLoaded | n/a        | n/a          | Scans the loaded zombie list (v0: singleplayer). |

Meaningful knobs: `radius`, `zRange`, `staleness`, `cooldown`, `highlight`.

Note: `radius` makes emissions leaner, but does not avoid the baseline cost of scanning the loaded zombie list.
