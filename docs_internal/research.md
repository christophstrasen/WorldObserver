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

https://demiurgequantified.github.io/ProjectZomboidJavaDocs/zombie/Lua/MapObjects.html
at init call MapObjects.OnLoadWithSprite with either a sprite name or list of sprite names and a function to call when that sprite loads in

the only argument to the function will be the created object
you can also use OnNewWithSprite which will only trigger once per object but i don't recommend this for mods because it won't trigger on objects that were loaded before your mod was activated, you can just use mod data or something if you don't want to affect the same object twice
they also take a priority number as an argument, this is used to resolve the order to call functions in when a sprite has more than one function registered, i have literally never cared about this and you probably won't either so just put your favourite number

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