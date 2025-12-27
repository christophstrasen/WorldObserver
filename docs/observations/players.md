# Observation: players

Goal: react to player movement/state changes (`IsoPlayer` snapshots) without wiring your own `OnPlayer*` loops.

Quickstart first (recommended):
- [Quickstart](../quickstart.md)

## Declare interest (required)

WorldObserver emits player facts only when at least one mod declares interest.

### Option A: `onPlayerMove`

Uses `Events.OnPlayerMove` when available.

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "featureKey", {
  type = "players",
  scope = "onPlayerMove",
  cooldown = { desired = 0.2 },
  highlight = true,
})
```

### Option B: `onPlayerUpdate`

Uses `Events.OnPlayerUpdate` when available.

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "featureKey", {
  type = "players",
  scope = "onPlayerUpdate",
  cooldown = { desired = 0.2 },
  highlight = true,
})
```

## Subscribe

```lua
local sub = WorldObserver.observations:players()
  :distinct("player", 0.2)
  :subscribe(function(observation)
    local p = observation.player
    if not p then return end
    print(('[WO] playerKey=%s tile=%s room=%s scope=%s'):format(
      tostring(p.playerKey),
      tostring(p.tileLocation),
      tostring(p.roomLocation),
      tostring(p.scope)
    ))
  end)
```

Remember to stop:
- `sub:unsubscribe()`
- and your interest lease: `lease:stop()` (see [Lifecycle](../guides/lifecycle.md))

## Record fields (what `observation.player` contains)

Common fields on the player record:
- ids: `steamId`, `onlineId`, `playerId`, `playerNum`
- dedup key: `playerKey` (namespaced string like `steamId1234`, `onlineId45`, `playerId77`, `playerNum0`)
- spatial: `tileX`, `tileY`, `tileZ`, `x`, `y`, `z`, `tileLocation`
- relations: `roomLocation`, `roomName`, `buildingId`
- cheap state: `username`, `displayName`, `accessLevel`, `hoursSurvived`, `isLocalPlayer`, `isAiming`
- provenance: `source` (`"event"`), `scope` (`"onPlayerMove"` or `"onPlayerUpdate"`), `sourceTime`

Notes:
- `roomLocation` is derived from the first room square and is join-ready with `rooms.roomLocation`.
- `playerKey` prefers `steamId`, then `onlineId`, then `playerId`, then `playerNum`.
- In singleplayer, engine ids may be `0` (example: `steamId=0`), so you may see `playerKey=steamId0`.
- `sourceTime` is auto-stamped at ingest when missing.

Engine objects (best-effort):
- `IsoPlayer`, `IsoGridSquare`, `IsoRoom`, `IsoBuilding`

## Extending the record (advanced)

If you need extra fields on `observation.player`, register a record extender:
- [Guide: extending record fields](../guides/extending_records.md)

## Built-in stream helpers

```lua
local stream = WorldObserver.observations:players()
  :playerFilter(function(player)
    return player and player.isLocalPlayer == true
  end)
```

Available today:
- `:playerFilter(fn)`

Record helpers:
- none required (use `record.playerKey` directly)

## Supported interest configuration (today)

Supported combinations for `type = "players"`:

| scope | target key | target shape | Notes |
|------|------------|--------------|-------|
| onPlayerMove | n/a | n/a | Emits when players move (engine event). |
| onPlayerUpdate | n/a | n/a | Emits on player updates (engine event). |

Meaningful settings: `cooldown`, `highlight`.
