# Interest combinations (current support)

Purpose: define the currently supported `type` / `scope` / `target` combinations so code + tests can stay aligned.

## Squares

### type = "squares" (probe-driven + event-driven)

| scope   | target key | target shape                                  | Notes |
|---------|------------|-----------------------------------------------|-------|
| near    | player     | `target = { player = { id = 0 } }`            | Probe around player. |
| near    | square     | `target = { square = { x, y, z } }`           | Probe around a fixed square (`z` defaults to 0). |
| vision  | player     | `target = { player = { id = 0 } }`            | Probe; only emits squares visible to the player. |
| onLoad  | n/a        | n/a                                           | Event-driven: emits when squares load. Expected a chunked behavior and high volume when the player moves fast or loads for the first time (teleports etc.) |

Settings:
- Probe scopes (`near`, `vision`): `radius`, `staleness`, `cooldown`, `highlight`.
- Event scope (`onLoad`): `cooldown`, `highlight`.

Defaults:
- If `scope` is missing, it defaults to `"near"`.
- For probe scopes (`near`, `vision`), missing `target` defaults to `{ player = { id = 0 } }`.

## Zombies

### type = "zombies" (probe-driven)

| scope     | target key | target shape | Notes |
|-----------|------------|--------------|-------|
| allLoaded | n/a        | n/a          | Scans the zombie list in the cell of the player (singleplayer). |

Settings: `radius`, `zRange`, `staleness`, `cooldown`, `highlight`.

Defaults:
- If `scope` is missing, it defaults to `"allLoaded"`.

## Players

### type = "players" (event-driven)

| scope | target key | target shape | Notes |
|-------|------------|--------------|-------|
| onPlayerMove | n/a | n/a | Emits when players move (engine event). |
| onPlayerUpdate | n/a | n/a | Emits on player updates (engine event). |
| onPlayerChangeRoom | n/a | n/a | Emits when player 0 changes rooms (tick-driven). |

Settings: `cooldown`, `highlight`.

Defaults:
- If `scope` is missing, it defaults to `"onPlayerMove"`.

## Vehicles

### type = "vehicles" (probe-driven + event-driven)

| scope     | target key | target shape | Notes |
|-----------|------------|--------------|-------|
| allLoaded | n/a        | n/a          | Scans the vehicle list in the active cell (singleplayer) + listens for `OnSpawnVehicleEnd` when interest is active. |

Settings:
- `staleness`, `cooldown`, `highlight`.

Defaults:
- If `scope` is missing, it defaults to `"allLoaded"`.

## Rooms

### type = "rooms" (probe-driven + event-driven)

| scope        | target key | target shape | Notes |
|--------------|------------|--------------|-------|
| allLoaded    | n/a        | n/a          | Scans the room list in the active cell (singleplayer). |
| onSeeNewRoom | n/a        | n/a          | Event-driven: emits when a room is seen. |
| onPlayerChangeRoom | player | `target = { player = { id = 0 } }` | Tick-driven: emits when the player changes rooms (no emission when room is nil). |

Settings:
- Probe scope (`allLoaded`): `staleness`, `cooldown`, `highlight`.
- Non-probe scopes (`onSeeNewRoom`, `onPlayerChangeRoom`): `cooldown`, `highlight`.

Defaults:
- If `scope` is missing, it defaults to `"allLoaded"`.

## Items

### type = "items" (probe-driven + playerSquare driver)

| scope        | target key | target shape                                  | Notes |
|--------------|------------|-----------------------------------------------|-------|
| playerSquare | player     | `target = { player = { id = 0 } }`            | Emits only items on the square under the player. |
| near         | player     | `target = { player = { id = 0 } }`            | Probe around player. |
| near         | square     | `target = { square = { x, y, z } }`           | Probe around a fixed square (`z` defaults to 0). |
| vision       | player     | `target = { player = { id = 0 } }`            | Probe; only emits items on squares visible to the player. |

Settings:
- Probe scopes (`near`, `vision`): `radius`, `staleness`, `cooldown`, `highlight`.
- `playerSquare`: `cooldown`, `highlight`.

Defaults:
- If `scope` is missing, it defaults to `"near"`.
- If `target` is missing, it defaults to `{ player = { id = 0 } }`.

## Dead bodies

### type = "deadBodies" (probe-driven + playerSquare driver)

| scope        | target key | target shape                                  | Notes |
|--------------|------------|-----------------------------------------------|-------|
| playerSquare | player     | `target = { player = { id = 0 } }`            | Emits only dead bodies on the square under the player. |
| near         | player     | `target = { player = { id = 0 } }`            | Probe around player. |
| near         | square     | `target = { square = { x, y, z } }`           | Probe around a fixed square (`z` defaults to 0). |
| vision       | player     | `target = { player = { id = 0 } }`            | Probe; only emits dead bodies on squares visible to the player. |

Settings:
- Probe scopes (`near`, `vision`): `radius`, `staleness`, `cooldown`, `highlight`.
- `playerSquare`: `cooldown`, `highlight`.

Defaults:
- If `scope` is missing, it defaults to `"near"`.
- If `target` is missing, it defaults to `{ player = { id = 0 } }`.

## Sprites

### type = "sprites" (probe-driven + event-driven)

| scope            | target key | target shape                                  | Notes |
|------------------|------------|-----------------------------------------------|-------|
| near             | player     | `target = { player = { id = 0 } }`            | Probe around player; filters to `spriteNames`. |
| near             | square     | `target = { square = { x, y, z } }`           | Probe around a fixed square; filters to `spriteNames`. |
| vision           | player     | `target = { player = { id = 0 } }`            | Probe; only emits sprites visible to the player. |
| onLoadWithSprite | n/a        | n/a                                           | Event-driven: emits when matching sprites load. |

Settings:
- Probe scopes (`near`, `vision`): `radius`, `staleness`, `cooldown`, `highlight`, `spriteNames`.
- Event scope (`onLoadWithSprite`): `cooldown`, `highlight`, `spriteNames` (exact names only).

Notes:
- `spriteNames` supports trailing `%` for prefix matches (example: `vegetation_ornamental_01_%`).
- `%` alone matches all names.

Defaults:
- If `scope` is missing, it defaults to `"near"`.
- For probe scopes (`near`, `vision`), missing `target` defaults to `{ player = { id = 0 } }`.

## Unsupported (not yet implemented)

- `type = "squares"` with scope `inside`, `outside`, or `allLoaded`.
- `type = "squares"` with `target = { room = { ... } }` or `target = { roomDef = { ... } }`.
- Any zombie scopes beyond `allLoaded`.
- RoomDef / zone interest types (future).
