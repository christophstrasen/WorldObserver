-- interest/definitions.lua -- data-driven interest type/scope/target definitions.
local moduleName = ...
local Definitions = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Definitions = loaded
	else
		---@diagnostic disable-next-line: undefined-field
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
	recommendedFields = {
		near = { "radius", "staleness", "cooldown" },
		vision = { "radius", "staleness", "cooldown" },
		onLoad = { "cooldown" },
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
	recommendedFields = {
		allLoaded = { "radius", "zRange", "staleness", "cooldown" },
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
	recommendedFields = {
		allLoaded = { "staleness", "cooldown" },
		onSeeNewRoom = { "cooldown" },
		onPlayerChangeRoom = { "cooldown" },
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
	recommendedFields = {
		playerSquare = { "cooldown" },
		near = { "radius", "staleness", "cooldown" },
		vision = { "radius", "staleness", "cooldown" },
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
	recommendedFields = {
		playerSquare = { "cooldown" },
		near = { "radius", "staleness", "cooldown" },
		vision = { "radius", "staleness", "cooldown" },
	},
	bucketKey = "squaresTarget",
}

Definitions.types.sprites = Definitions.types.sprites or {
	defaultScope = "near",
	strictScopes = true,
	allowedScopes = { near = true, vision = true, onLoadWithSprite = true },
	eventScopes = { onLoadWithSprite = true },
	allowTarget = true,
	allowTargetScopes = { near = true, vision = true },
	defaultTarget = { kind = "player", id = 0 },
	ignoreFields = {
		onLoadWithSprite = { target = true, radius = true, staleness = true, zRange = true },
		near = { zRange = true },
		vision = { zRange = true },
	},
	zeroKnobs = {
		onLoadWithSprite = { staleness = true, radius = true, zRange = true },
	},
	requiredFields = {
		all = { "spriteNames" },
	},
	recommendedFields = {
		near = { "radius", "staleness", "cooldown" },
		vision = { "radius", "staleness", "cooldown" },
		onLoadWithSprite = { "cooldown" },
	},
	bucketKey = "squaresTarget",
}

Definitions.types.vehicles = Definitions.types.vehicles or {
	defaultScope = "allLoaded",
	strictScopes = true,
	allowedScopes = { allLoaded = true },
	allowTarget = false,
	ignoreFields = {
		allLoaded = { target = true, radius = true, zRange = true },
	},
	zeroKnobs = {
		allLoaded = { radius = true, zRange = true },
	},
	recommendedFields = {
		allLoaded = { "staleness", "cooldown" },
	},
	bucketKey = "scope",
}

return Definitions
