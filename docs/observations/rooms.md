# Observation: rooms

Goal: react to what WorldObserver observes about rooms (`IsoRoom` snapshots: type/name, building linkage, bounds, windows, water).

Quickstart first (recommended):
- [Quickstart](../quickstart.md)

## Declare interest (required)

WorldObserver emits room facts only when at least one mod declares interest.

### Option A: event-driven (first time a room is seen)

Uses `Events.OnSeeNewRoom` when available.

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "featureKey", {
  type = "rooms",
  scope = "onSeeNewRoom",
  cooldown = { desired = 0 },
})
```

### Option B: probe-driven (all loaded rooms)

Scans `getCell():getRoomList()` on a low cadence and emits room records (time-sliced under a budget).

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "featureKey", {
  type = "rooms",
  scope = "allLoaded",
  staleness = { desired = 60 },
  cooldown = { desired = 20 },
})
```

### Option C: event-driven (player changes room)

Uses `Events.OnPlayerChangeRoom` when available.

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "featureKey", {
  type = "rooms",
  scope = "onPlayerChangeRoom",
  target = { player = { id = 0 } }, -- optional; defaults to player 0
  cooldown = { desired = 0 },
})
```

## Subscribe

```lua
local sub = WorldObserver.observations.rooms()
  :roomTypeIs("kitchen")
  :distinct("room", 10)
  :subscribe(function(observation)
    local r = observation.room
    print(("[WO] roomId=%s type=%s buildingId=%s hasWater=%s windows=%s"):format(
      tostring(r.roomId),
      tostring(r.name),
      tostring(r.buildingId),
      tostring(r.hasWater),
      tostring(r.windowsCount)
    ))
  end)
```

Remember to stop:
- `sub:unsubscribe()`
- and your interest lease: `lease:stop()` (see [Lifecycle](../guides/lifecycle.md))

## Record fields (what `observation.room` contains)

Common fields on the room record:
- ids: `roomId`, `roomDefId`, `buildingId`
- name: `name` (example: `"kitchen"`)
- `bounds` (best-effort `{ x, y, width, height }` when available)
- counts: `rectsCount`, `bedsCount`, `windowsCount`, `waterSourcesCount`
- flags: `visited`, `exists`, `hasWater`
- `source` (which producer saw it, `"event"` or `"probe"`)
- `sourceTime` (ms, in-game clock)

Notes:
- `roomId` is derived from the first square of the room as `"x123y456z7"` (string) to avoid large engine IDs losing precision in Lua numbers.

Engine objects:
- Off by default; can be enabled in config via `facts.rooms.record.includeIsoRoom`, `.includeRoomDef`, `.includeBuilding`.

## Extending the record (advanced)

If you need extra fields on `observation.room`, register a record extender:
- [Guide: extending record fields](../guides/extending_records.md)

## Built-in stream helpers

```lua
local stream = WorldObserver.observations.rooms()
  :roomHasWater()
  :distinct("room", 10)
```

Available today:
- `:roomTypeIs("kitchen")`
- `:roomHasWater()`

Record helpers (use inside `:whereRoom(...)` or inside Rx `:filter(...)` after `:asRx()`):
- `WorldObserver.helpers.room.record.roomTypeIs(roomRecord, "kitchen")`
- `WorldObserver.helpers.room.record.roomHasWater(roomRecord)`

## Supported interest configuration (today)

Supported combinations for `type = "rooms"`:

| scope        | target key | target shape                    | Notes |
|-------------|------------|----------------------------------|-------|
| onSeeNewRoom | n/a        | n/a                              | Emits when a room is seen (engine event). |
| onPlayerChangeRoom | player | `target = { player = { id = 0 } }` | Emits when the player changes rooms (engine event). |
| allLoaded    | n/a        | n/a                              | Scans the room list in the active cell (singleplayer). |

Meaningful knobs for `allLoaded`: `staleness`, `cooldown`, `highlight`.
