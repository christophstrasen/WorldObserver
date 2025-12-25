# Extending record fields (advanced)

WorldObserver observation records are intentionally small “extracts”.
If you need extra fields from the original engine objects (`IsoZombie`, `IsoRoom`, `IsoGridSquare`), you can extend the record builders.

## Preferred: register a record extender (multi-mod friendly)

Record extenders are additive: multiple mods can register extenders without “Monkey Patching”.

Extender principles:

- Runs for every produced record of that family.
- Runs in registration order.
- Runs inside a `pcall`; failures are logged and the base record is still emitted.

Recommended: put your extra fields under your own namespace to avoid collisions:
`record.extra = record.extra or {}; record.extra.YourModId = ...`

Your extender _can_ break other mods, especially if it overwrites fields commonly used for identification and de-duplication.

### Zombies

```lua
local ZombieRecord = require("WorldObserver/facts/zombies/record")

ZombieRecord.registerZombieRecordExtender("YourModId:addFields", function(record, zombie)
  record.extra = record.extra or {}
  record.extra.YourModId = record.extra.YourModId or {}

  -- Example: best-effort extra field.
  if type(zombie.isFakeDead) == "function" then
    record.extra.YourModId.isFakeDead = (zombie:isFakeDead() == true)
  end
end)
```

### Rooms

```lua
local RoomRecord = require("WorldObserver/facts/rooms/record")

RoomRecord.registerRoomRecordExtender("YourModId:addFields", function(record, room)
  record.extra = record.extra or {}
  record.extra.YourModId = record.extra.YourModId or {}

  if type(room.isInside) == "function" then
    record.extra.YourModId.isInside = (room:isInside() == true)
  end
end)
```

### Squares

```lua
local SquareRecord = require("WorldObserver/facts/squares/record")

SquareRecord.registerSquareRecordExtender("YourModId:addFields", function(record, square)
  record.extra = record.extra or {}
  record.extra.YourModId = record.extra.YourModId or {}

  if type(square.getTemperature) == "function" then
    record.extra.YourModId.temperature = square:getTemperature()
  end
end)
```

## Alternative: override `make<Family>Record` (single-owner)

If you need to change how the base record is built (not just add fields), you can override the builder function.
This is powerful but conflicts easily with other mods (whoever patches last “wins”).

@TODO clarify or change because the last wins is because we don't use the global object?

Example (zombies):

```lua
local ZombieRecord = require("WorldObserver/facts/zombies/record")
local defaultMake = ZombieRecord.makeZombieRecord

ZombieRecord.makeZombieRecord = function(zombie, source, opts)
  local record = defaultMake(zombie, source, opts)
  if not record then return nil end
  record.customField = true
  return record
end
```

## Performance note

Extenders run on the hot path. Keep them cheap:

- Prefer reading fields from the provided `Iso*` object.
- Avoid scanning lists, calling expensive pathfinding APIs, or allocating large tables.
