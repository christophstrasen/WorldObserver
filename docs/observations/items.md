# Observation: items

Goal: react to items observed on the ground (and optional container contents).

Quickstart first (recommended):
- [Quickstart](../quickstart.md)

## Declare interest (required)

WorldObserver does no item probing unless at least one mod declares interest.

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "featureKey", {
  type = "items",
  scope = "near",
  radius = { desired = 8 },
  staleness = { desired = 2 },
  cooldown = { desired = 5 },
})
```

## Subscribe

```lua
local sub = WorldObserver.observations.items()
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

Notes:
- Items are world items on the ground plus direct container contents (depth=1).
