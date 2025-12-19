# Observation: zombies

Goal: react to what WorldObserver observes about zombies (positions, movement, targeting).

Quickstart first (recommended):
- [Quickstart](../quickstart.md)

## Subscribe

```lua
local sub = WorldObserver.observations.zombies()
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
- movement: `isMoving`, `isRunning`, `isCrawling`, `locomotion`
- targeting: `hasTarget`, `targetId`, `targetKind`, `targetVisible`, `targetSeenSeconds`
- target coords: `targetX`, `targetY`, `targetZ`, `targetSquareId`
- `source` (which producer saw it)
- `sourceTime` / `observedAtTimeMS` (ms, in-game clock)

Engine object:
- Usually not included. If you need one, use `WorldObserver.helpers.zombie.record.getIsoZombie(record)` as best-effort rehydration.

## Built-in stream helpers

```lua
local stream = WorldObserver.observations.zombies()
  :zombieHasTarget()
  :distinct("zombie", 2)
```

If you want custom boolean logic, use `:whereZombie(...)` with record predicates:

```lua
local ZombieHelper = WorldObserver.helpers.zombie.record

local stream = WorldObserver.observations.zombies()
  :whereZombie(ZombieHelper.zombieHasTarget)
```

Available today:
- `:zombieHasTarget()` (keeps only zombies that currently have a target)

Record helpers (use inside `:whereZombie(...)` or inside Rx `:filter(...)` after `:asRx()`):
- `WorldObserver.helpers.zombie.record.zombieHasTarget(zombieRecord)`
