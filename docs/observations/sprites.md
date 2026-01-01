# Observation: sprites

Goal: react to map objects that use specific sprite names (fixtures, hedges, etc.).

Quickstart first (recommended):
- [Quickstart](../quickstart.md)

## Declare interest (required)

WorldObserver does no sprite probing unless at least one mod declares interest.

### Option A: near (probe around a target)

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "sprites.near", {
  type = "sprites",
  scope = "near",
  target = { player = { id = 0 } }, -- optional; defaults to player 0
  radius = { desired = 8 },
  staleness = { desired = 5 },
  cooldown = { desired = 20 },
  spriteNames = { "fixtures_bathroom_01_0" },
  highlight = true,
})
```

### Option B: onLoadWithSprite (event-driven)

Emits when matching sprites are loaded by the engine.

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "sprites.onLoad", {
  type = "sprites",
  scope = "onLoadWithSprite",
  cooldown = { desired = 300 },
  spriteNames = { "fixtures_bathroom_01_0" },
  highlight = true,
})
```

## Subscribe

```lua
local sub = WorldObserver.observations:sprites()
  :distinct("sprite", 5)
  :subscribe(function(observation)
    local sprite = observation.sprite
    print(("[WO] sprite=%s id=%s loc=(%s,%s,%s) square=%s"):format(
      tostring(sprite.spriteName),
      tostring(sprite.spriteId),
      tostring(sprite.x),
      tostring(sprite.y),
      tostring(sprite.z),
      tostring(sprite.squareId)
    ))
  end)
```

Remember to stop:
- `sub:unsubscribe()`
- and your interest lease: `lease:stop()` (see [Lifecycle](../guides/lifecycle.md))

## Record fields (what `observation.sprite` contains)

Common fields on the sprite record:
- `spriteKey`
- `spriteName`
- `spriteId`
- `x`, `y`, `z`
- `tileLocation`
- `squareId`
- `objectIndex`
- `source` (which producer saw it)
- `sourceTime` (ms, in-game clock)

Engine objects (best-effort references):
- `IsoObject` (the map object carrying the sprite)
- `IsoGridSquare` (the square the object was observed on)

Notes:
- These userdata references can be stale; treat them as best-effort and short-lived.
- If you need fresh square data, prefer using the coordinates (`x`, `y`, `z`) and square helpers.

## Built-in stream helpers

```lua
local stream = WorldObserver.observations:sprites()
  :spriteNameIs("fixtures_bathroom_01_0")
  :distinct("sprite", 10)
```

If you want custom boolean logic, use `:spriteFilter(...)` with record predicates:

```lua
local SpriteHelper = WorldObserver.helpers.sprite.record

local stream = WorldObserver.observations:sprites()
  :spriteFilter(function(sprite)
    return SpriteHelper.spriteIdIs(sprite, 120000)
  end)
```

Available today:
- `:spriteNameIs(name)`
- `:spriteIdIs(id)`
- `:spriteFilter(predicate)`
- `:removeSpriteObject()` (best-effort; uses `IsoGridSquare:RemoveTileObject` for the observed sprite's `IsoObject`)

Record helpers (use inside `:spriteFilter(...)` or inside Rx `:filter(...)` after `:asRx()`):
- `WorldObserver.helpers.sprite.record.spriteNameIs(spriteRecord, wanted)`
- `WorldObserver.helpers.sprite.record.spriteIdIs(spriteRecord, wanted)`
- `WorldObserver.helpers.sprite.record.removeSpriteObject(spriteRecord)` (best-effort; uses `IsoGridSquare:RemoveTileObject`)

Record wrapping (optional):
- `WorldObserver.helpers.sprite:wrap(spriteRecord)` adds `:nameIs(name)`, `:idIs(id)`, `:getIsoGridSquare()`, `:highlight(durationMs, opts)`, `:removeSpriteObject()`; see [Helpers: record wrapping](../guides/helpers.md#record-wrapping-optional).

## Supported interest configuration (today)

Supported combinations for `type = "sprites"`:

| scope           | target key | target shape                                  | Notes |
|-----------------|------------|-----------------------------------------------|-------|
| near            | player     | `target = { player = { id = 0 } }`            | Probe around player. |
| near            | square     | `target = { square = { x, y, z } }`           | Probe around a fixed square (`z` defaults to 0). |
| vision          | player     | `target = { player = { id = 0 } }`            | Probe; only emits sprites on squares visible to the player. |
| vision          | square     | `target = { square = { x, y, z } }`           | Probe; visible squares only. |
| onLoadWithSprite | n/a       | n/a                                           | Event-driven; ignores radius/staleness. |

Required fields:
- `spriteNames` (array of sprite name strings)
  - Trailing `%` means “prefix match” (example: `"vegetation_ornamental_01_%"`).
  - `%` alone matches all names.
  - Wildcards apply to `near` / `vision` probes only; `onLoadWithSprite` still requires explicit names.

Meaningful settings:
- Probe scopes (`near`, `vision`): `radius`, `staleness`, `cooldown`, `highlight`.
- `onLoadWithSprite`: `cooldown`, `highlight`.
