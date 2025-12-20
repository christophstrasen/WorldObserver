# Interest combinations (current support)

Purpose: define the currently supported `type` / `scope` / `target` combinations so code + tests can stay aligned.

## Squares

### type = "squares" (probe-driven + event-driven)

| scope   | target.kind | target fields                     | Notes |
|---------|-------------|-----------------------------------|-------|
| near    | player      | id (defaults to 0)                | Probe around player. |
| near    | square      | x, y, z (z defaults to 0)         | Probe around a fixed square. |
| vision  | player      | id (defaults to 0)                | Probe; only emits squares visible to the player. |
| onLoad  | n/a         | n/a                               | Event-driven: emits when squares load. Expected a chunked behavior and high volume when the player moves fast or loads for the first time (teleports etc.) |

Knobs:
- Probe scopes (`near`, `vision`): `radius`, `staleness`, `cooldown`, `highlight`.
- Event scope (`onLoad`): `cooldown`, `highlight`.

Defaults:
- If `scope` is missing, it defaults to `"near"`.
- For probe scopes (`near`, `vision`), missing `target` defaults to `{ kind = "player", id = 0 }`.

## Zombies

### type = "zombies" (probe-driven)

| scope     | target.kind | target fields | Notes |
|-----------|-------------|---------------|-------|
| allLoaded | n/a         | n/a           | Scans the zombie list in the cell of the player (singleplayer). |

Knobs: `radius`, `zRange`, `staleness`, `cooldown`, `highlight`.

Defaults:
- If `scope` is missing, it defaults to `"allLoaded"`.

## Unsupported (not yet implemented)

- `type = "squares"` with scope `inside`, `outside`, or `allLoaded`.
- `type = "squares"` with `target.kind = "room"` or `"roomDef"`.
- Any zombie scopes beyond `allLoaded`.
- Rooms / roomDefs interest types (future).
