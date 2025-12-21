-- interest/definitions.lua -- data-driven interest type/scope/target definitions.
local moduleName = ...
local Definitions = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Definitions = loaded
	else
		package.loaded[moduleName] = Definitions
	end
end

Definitions.types = Definitions.types or {}
Definitions.defaultType = Definitions.defaultType or "squares"

Definitions.types.squares = Definitions.types.squares or {
	defaultScope = "near",
	strictScopes = false,
	eventScopes = { onLoad = true },
	allowTarget = true,
	defaultTarget = { kind = "player", id = 0 },
	ignoreFields = {
		onLoad = { target = true, radius = true, staleness = true },
	},
	zeroKnobs = {
		onLoad = { staleness = true, radius = true },
	},
	bucketKey = "squaresTarget",
}

Definitions.types.zombies = Definitions.types.zombies or {
	defaultScope = "allLoaded",
	strictScopes = true,
	allowedScopes = { allLoaded = true },
	allowTarget = false,
	ignoreFields = {
		allLoaded = { target = true },
	},
	bucketKey = "scope",
}

Definitions.types.rooms = Definitions.types.rooms or {
	defaultScope = "allLoaded",
	strictScopes = true,
	allowedScopes = { allLoaded = true, onSeeNewRoom = true, onPlayerChangeRoom = true },
	eventScopes = { onSeeNewRoom = true, onPlayerChangeRoom = true },
	allowTarget = false,
	allowTargetScopes = { onPlayerChangeRoom = true },
	defaultTarget = { kind = "player", id = 0 },
	ignoreFields = {
		onSeeNewRoom = { target = true, radius = true, staleness = true },
		onPlayerChangeRoom = { radius = true, staleness = true, zRange = true },
		allLoaded = { target = true, radius = true, zRange = true },
	},
	zeroKnobs = {
		onSeeNewRoom = { staleness = true, radius = true, zRange = true },
		onPlayerChangeRoom = { staleness = true, radius = true, zRange = true },
		allLoaded = { radius = true, zRange = true },
	},
	bucketKey = "roomsScope",
}

Definitions.types.items = Definitions.types.items or {
	defaultScope = "near",
	strictScopes = true,
	allowedScopes = { playerSquare = true, near = true, vision = true },
	allowTarget = true,
	defaultTarget = { kind = "player", id = 0 },
	ignoreFields = {
		playerSquare = { radius = true, staleness = true, zRange = true },
		near = { zRange = true },
		vision = { zRange = true },
	},
	zeroKnobs = {
		playerSquare = { staleness = true, radius = true, zRange = true },
	},
	bucketKey = "squaresTarget",
}

Definitions.types.deadBodies = Definitions.types.deadBodies or {
	defaultScope = "near",
	strictScopes = true,
	allowedScopes = { playerSquare = true, near = true, vision = true },
	allowTarget = true,
	defaultTarget = { kind = "player", id = 0 },
	ignoreFields = {
		playerSquare = { radius = true, staleness = true, zRange = true },
		near = { zRange = true },
		vision = { zRange = true },
	},
	zeroKnobs = {
		playerSquare = { staleness = true, radius = true, zRange = true },
	},
	bucketKey = "squaresTarget",
}

return Definitions
