# Base observable facts

WorldObserver’s “base facts” are the built-in observation families you can subscribe to (squares, zombies, …).

This page is a quick overview of:

- which interest `type`/`scope` combinations exist,
- what target defaults exist (if any),
- what each family uses as its `record.woKey` (and therefore contributes to `observation.WoMeta.key`),
- and how stable you should treat that key.

For the detailed shape of each record, see the linked family pages.

| type/family                                    | interest scopes                                   | interest default target                            | `woKey` source                                                                      | key stability (best-effort)                                         |
| ---------------------------------------------- | ------------------------------------------------- | -------------------------------------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| [`squares`](squares.md)        | `near`, `vision`, `onLoad`                        | `player(id=0)` <br/>(only for `near` and `vision`) | `tileLocation` (example: `x10919y10132z0`)                                          | High (world coordinates)                                            |
| [`players`](players.md)        | `onPlayerMove`, `onPlayerUpdate`, `onPlayerChangeRoom` | n/a                                           | `playerKey` (prefers `steamId`, then `onlineId`, then `playerId`, then `playerNum`) | High-ish (identifier dependent; varies by MP/SP)                    |
| [`rooms`](rooms.md)            | `allLoaded`, `onSeeNewRoom`, `onPlayerChangeRoom` | `player(id=0)` (only for `onPlayerChangeRoom`)     | `roomId` (derived from room’s first-square `tileLocation`)                          | High (map + room geometry dependent)                                |
| [`zombies`](zombies.md)        | `allLoaded`                                       | n/a                                                | `zombieId`, else `zombieOnlineId`, else `tileLocation` fallback                     | Medium (engine IDs can change; fallback is spatial)                 |
| [`vehicles`](vehicles.md)      | `allLoaded`                                       | n/a                                                | `sqlId` (preferred) else `vehicleId`                                                | Medium (sqlId is strongest when present)                            |
| [`items`](items.md)            | `playerSquare`, `near`, `vision`                  | `player(id=0)`<br/> (only for `near` and `vision`) | `itemId` (from world/inventory item IDs)                                            | Low/Medium (engine item IDs may not be stable across all scenarios) |
| [`deadBodies`](dead_bodies.md) | `playerSquare`, `near`, `vision`                  | `player(id=0)`<br/>(only for `near` and `vision`)  | `deadBodyId` (from `IsoDeadBody:getObjectID()`)                                     | Medium (engine object ID)                                           |
| [`sprites`](sprites.md)        | `near`, `vision`, `onLoadWithSprite`              | `player(id=0)` (probe scopes)                      | `spriteKey` (spriteName + coords + objectIndex)                                     | High-ish (spatial + sprite identity)                                |
