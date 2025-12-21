# Observation: items

Goal: react to items observed on the ground (including optional container contents at depth=1).

Quickstart first (recommended):
- [Quickstart](../quickstart.md)

## Declare interest (required)

WorldObserver does no item probing unless at least one mod declares interest.

### Option A: playerSquare (lowest noise; good for testing)

Emits items on the square the player currently stands on.

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "items.playerSquare", {
  type = "items",
  scope = "playerSquare",
  cooldown = { desired = 0 },
  highlight = true,
})
```

### Option B: near (probe around a target)

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "featureKey", {
  type = "items",
  scope = "near",
  target = { player = { id = 0 } }, -- optional; defaults to player 0
  radius = { desired = 8 },
  staleness = { desired = 2 },
  cooldown = { desired = 5 },
  highlight = true,
})
```

### Option C: vision (probe; visible squares only)

Like `near`, but only emits items on squares currently visible to the player.

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "items.vision", {
  type = "items",
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
local sub = WorldObserver.observations.items()
  :distinct("item", 10)
  :subscribe(function(observation)
    local item = observation.item
    print(("[WO] itemId=%s type=%s loc=(%s,%s,%s) square=%s source=%s"):format(
      tostring(item.itemId),
      tostring(item.itemFullType),
      tostring(item.x),
      tostring(item.y),
      tostring(item.z),
      tostring(item.squareId),
      tostring(item.source)
    ))
  end)
```

Remember to stop:
- `sub:unsubscribe()`
- and your interest lease: `lease:stop()` (see [Lifecycle](../guides/lifecycle.md))

## Record fields (what `observation.item` contains)

Common fields on the item record:
- `itemId` (best-effort id; if missing the record is skipped)
- `itemType`, `itemFullType`, `itemName`
- `x`, `y`, `z`
- `squareId`
- `source` (which producer saw it)
- `sourceTime` (ms, in-game clock)

If the item was discovered inside a container (depth=1 only):
- `containerItemId`
- `containerItemType`
- `containerItemFullType`

Optional engine objects (when enabled in config):
- `InventoryItem`
- `WorldItem`

Notes:
- WO currently observes world items on the ground plus direct container contents (depth=1).
- Container expansion is capped per square by default (see `facts.items.record.maxContainerItemsPerSquare`).
- This is not a full “inventory observation” stream.

## Extending the record (advanced)

If you need extra fields on `observation.item`, register a record extender:
- [Guide: extending record fields](../guides/extending_records.md)

## Built-in stream helpers

```lua
local stream = WorldObserver.observations.items()
  :itemFullTypeIs("Base.CannedSoup")
  :distinct("item", 10)
```

If you want custom boolean logic, use `:whereItem(...)` with record predicates:

```lua
local ItemHelper = WorldObserver.helpers.item.record

local stream = WorldObserver.observations.items()
  :whereItem(function(item)
    return ItemHelper.itemTypeIs(item, "Apple")
  end)
```

Available today:
- `:itemTypeIs(typeName)`
- `:itemFullTypeIs(fullType)`
- `:whereItem(predicate)`

Record helpers (use inside `:whereItem(...)` or inside Rx `:filter(...)` after `:asRx()`):
- `WorldObserver.helpers.item.record.itemTypeIs(itemRecord, wanted)`
- `WorldObserver.helpers.item.record.itemFullTypeIs(itemRecord, wanted)`

## Supported interest configuration (today)

Supported combinations for `type = "items"`:

| scope        | target key | target shape                                  | Notes |
|--------------|------------|-----------------------------------------------|-------|
| playerSquare | player     | `target = { player = { id = 0 } }`            | Emits only the square under the player. |
| near         | player     | `target = { player = { id = 0 } }`            | Probe around player. |
| near         | square     | `target = { square = { x, y, z } }`           | Probe around a fixed square (`z` defaults to 0). |
| vision       | player     | `target = { player = { id = 0 } }`            | Probe; only emits items on squares visible to the player. |

Meaningful knobs:
- Probe scopes (`near`, `vision`): `radius`, `staleness`, `cooldown`, `highlight`.
- `playerSquare`: `cooldown`, `highlight`.

## Why you might see nothing

- You didn’t declare interest (no lease → no probing).
- There are no items on the ground in the scanned area (try `scope="playerSquare"` while standing on items).
- Your `cooldown`/`:distinct(...)` settings filter out repeats.
