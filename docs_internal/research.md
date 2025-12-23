# SquareObsdervation

https://demiurgequantified.github.io/ProjectZomboidJavaDocs/zombie/iso/IsoChunk.html#isValidLevel(int)
https://demiurgequantified.github.io/ProjectZomboidJavaDocs/zombie/iso/IsoChunk.html#getSquaresForLevel(int)

## To load _all_ 
Get IsoCell from Player
Get ChunkMap from IsoCell
Get Chunks from ChunkMap
Loop through chunks
Check if chunk has already been checked in session
Loop through all levels in chunk
Check if level is valid
Get all gridsquares in level


# ZombieObservation

IsoCell:getZombieList()

# SpriteObservations

Primary API: `MapObjects` (B42 JavaDocs)
- https://demiurgequantified.github.io/ProjectZomboidJavaDocs/zombie/Lua/MapObjects.html

### What exists (from JavaDocs signatures)

- `MapObjects.OnLoadWithSprite(spriteName: String, fn: LuaClosure, priority: int)`
- `MapObjects.OnLoadWithSprite(spriteNames: KahluaTable, fn: LuaClosure, priority: int)`
- `MapObjects.OnNewWithSprite(spriteName: String, fn: LuaClosure, priority: int)`
- `MapObjects.OnNewWithSprite(spriteNames: KahluaTable, fn: LuaClosure, priority: int)`

Related (likely internal/debug/backfill hooks; semantics not documented here):
- `MapObjects.loadGridSquare(square: IsoGridSquare)`
- `MapObjects.newGridSquare(square: IsoGridSquare)`
- `MapObjects.debugLoadSquare(x,y,z)` / `MapObjects.debugNewSquare(x,y,z)` / `MapObjects.debugLoadChunk(wx,wy)`
- `MapObjects.Reset()`
- `MapObjects.reroute(prototype, luaClosure)`

### Practical usage notes

- Register these at init (module load / early lifecycle) so you don’t miss already-loaded chunks.
- The callback receives the created/loaded object (in practice, treat it as an `IsoObject` or a subtype).
  - Useful methods to pull data:
    - `IsoObject:getSprite():getName()` (sprite name)
      - https://demiurgequantified.github.io/ProjectZomboidJavaDocs/zombie/iso/IsoObject.html#getSprite()
      - https://demiurgequantified.github.io/ProjectZomboidJavaDocs/zombie/iso/sprite/IsoSprite.html#getName()
    - `IsoObject:getSquare()` / `IsoObject:getX()/getY()/getZ()`
    - `IsoObject:getObjectIndex()` (potentially useful for dedupe within a square load cycle)
      - https://demiurgequantified.github.io/ProjectZomboidJavaDocs/zombie/iso/IsoObject.html#getObjectIndex()
    - `IsoObject:getModData()` (persist a “processed” marker across loads)
      - https://demiurgequantified.github.io/ProjectZomboidJavaDocs/zombie/iso/IsoObject.html#getModData()
- `priority` is an ordering hint when multiple handlers exist for the same sprite; pick a constant (e.g. `1`) unless you have a reason to order.
- `OnNewWithSprite` only triggers for newly created objects; it will not backfill objects that loaded before your handler registered.

### “Observe all sprites?”

`MapObjects` is sprite-filtered; JavaDocs show no wildcard “all sprites” registration.

If you truly need broad capture, use a square-driven scan and read `obj:getSprite():getName()` per object:
- Hook square load (`Events.LoadGridsquare` / `Events.OnLoadGridsquare` depending on API availability), or
- Drive it from WorldObserver square facts and iterate `IsoGridSquare:getObjects()` when you have an `IsoGridSquare`.
  - https://demiurgequantified.github.io/ProjectZomboidJavaDocs/zombie/iso/IsoGridSquare.html#getObjects()

### Example (sketch)

```lua
-- Call early (init). Sprite names are exact.
MapObjects.OnLoadWithSprite({ "fixtures_bathroom_01_0", "location_shop_mall_01_12" }, function(obj)
  local sprite = obj:getSprite()
  local spriteName = sprite and sprite:getName() or nil
  local square = obj:getSquare()
  local x = square and square:getX() or obj:getX()
  local y = square and square:getY() or obj:getY()
  local z = square and square:getZ() or obj:getZ()

  -- De-dupe idea (implementation-specific): key by coords + objectIndex.
  local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z) .. ":" .. tostring(obj:getObjectIndex())
  -- Mark in modData or a local table if needed.
  -- local md = obj:getModData(); md.__myMod_seen = true
end, 1)
```

# SoundObservations

https://steamcommunity.com/sharedfiles/filedetails/?id=3367336031
https://steamcommunity.com/sharedfiles/filedetails/?id=3628725609

# DeathObservations

https://pzwiki.net/wiki/OnCharacterDeath


# DeadBodyObservations

https://pzwiki.net/wiki/OnDeadBodySpawn

# ZombieHitObservations

https://pzwiki.net/wiki/OnHitZombie

# FireObservation

https://pzwiki.net/wiki/OnNewFire

# PlayerDamageObservation

https://pzwiki.net/wiki/OnPlayerGetDamage

# PlayerMovementObservation

https://pzwiki.net/wiki/OnPlayerMove

# RoomObservation

https://pzwiki.net/wiki/OnSeeNewRoom


Events.OnSeeNewRoom.Add(function(isoRoom)
Via squares (drive-by of the square facts)
getSquare():getRoom()
Via all buildings in the cell
getCell():getBuildings
via the cell directly
getCell():getRoomList()

FYI: getCell is not helpful on server-ide because it gets no chunks and without chunks there are no rooms and other objects.


# CharacterStatObservation

https://demiurgequantified.github.io/ProjectZomboidJavaDocs/zombie/characters/CharacterStat.html

# SleepObservation

https://pzwiki.net/wiki/OnSleepingTick

# VehicleObservation

https://pzwiki.net/wiki/OnSpawnVehicleEnd
https://pzwiki.net/wiki/OnUseVehicle
https://pzwiki.net/wiki/OnVehicleDamageTexture

# VehicleSeatObservation

https://pzwiki.net/wiki/OnSwitchVehicleSeat

# ExplosionObservation

https://pzwiki.net/wiki/OnThrowableExplode

# ThunderObservation

https://pzwiki.net/wiki/OnThunderEvent

# WeaponHitObservation

https://pzwiki.net/wiki/OnWeaponHitCharacter
https://pzwiki.net/wiki/OnWeaponHitThumpable
https://pzwiki.net/wiki/OnWeaponHitTree
https://pzwiki.net/wiki/OnWeaponHitXp

# WeaponUseObservation

https://pzwiki.net/wiki/OnWeaponSwing
https://pzwiki.net/wiki/OnWeaponSwingHitPoint


# ThumpableObservation

https://pzwiki.net/wiki/OnWeaponHitThumpable

# ZoneObservations

getZoneAt(x,y,z)
getZonesAt(x,y,z)
getZonesIntersecting(x,y,z,w,h)
getZoneWithBoundsAndType(...)
