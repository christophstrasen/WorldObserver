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

Knobs:
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

Knobs: `radius`, `zRange`, `staleness`, `cooldown`, `highlight`.

Defaults:
- If `scope` is missing, it defaults to `"allLoaded"`.

## Rooms

### type = "rooms" (probe-driven + event-driven)

| scope        | target key | target shape | Notes |
|--------------|------------|--------------|-------|
| allLoaded    | n/a        | n/a          | Scans the room list in the active cell (singleplayer). |
| onSeeNewRoom | n/a        | n/a          | Event-driven: emits when a room is seen. |

Knobs:
- Probe scope (`allLoaded`): `staleness`, `cooldown`, `highlight`.
- Event scope (`onSeeNewRoom`): `cooldown`, `highlight`.

Defaults:
- If `scope` is missing, it defaults to `"allLoaded"`.

## Unsupported (not yet implemented)

- `type = "squares"` with scope `inside`, `outside`, or `allLoaded`.
- `type = "squares"` with `target = { room = { ... } }` or `target = { roomDef = { ... } }`.
- Any zombie scopes beyond `allLoaded`.
- RoomDef / zone interest types (future).
