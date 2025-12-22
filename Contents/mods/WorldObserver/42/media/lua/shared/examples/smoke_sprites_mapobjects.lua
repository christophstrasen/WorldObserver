-- smoke_sprites_mapobjects.lua -- direct MapObjects.OnLoadWithSprite test (no WorldObserver).
-- Usage in PZ console:
--   smoke = require("examples/smoke_sprites_mapobjects")
--   smoke.start()
--   smoke.start({ spriteNames = { "walls_exterior_house_01_0" }, priority = 5 })
--
-- Notes:
-- - This registers a MapObjects.OnLoadWithSprite listener and prints observations.
-- - There is no unload/remove hook; calling start multiple times does not re-register.

local Smoke = {}
local registered = false

local SPRITE_NAMES = {
	-- Replace or extend with exact sprite names you care about.
	"walls_exterior_house_01_0",
	"floors_interior_tilesandwood_01_0",
	"fixtures_bathroom_01_0",
}

local PRIORITY = 5

local function log(fmt, ...)
	if type(_G.print) == "function" then
		_G.print(string.format("[smoke.sprites] " .. fmt, ...))
	end
end

local function safeCall(obj, methodName, ...)
	if obj and type(obj[methodName]) == "function" then
		local ok, value = pcall(obj[methodName], obj, ...)
		if ok then
			return value
		end
	end
	return nil
end

local function onLoad(isoObject)
	local square = safeCall(isoObject, "getSquare") or safeCall(isoObject, "getCurrentSquare")
	local sprite = safeCall(isoObject, "getSprite")
	local spriteName = safeCall(sprite, "getName")
	local spriteId = safeCall(sprite, "getID")
	local objectIndex = safeCall(isoObject, "getObjectIndex")
	local x = square and safeCall(square, "getX") or safeCall(isoObject, "getX")
	local y = square and safeCall(square, "getY") or safeCall(isoObject, "getY")
	local z = square and safeCall(square, "getZ") or safeCall(isoObject, "getZ")

	log(
		"name=%s id=%s objIndex=%s x=%s y=%s z=%s obj=%s",
		tostring(spriteName),
		tostring(spriteId),
		tostring(objectIndex),
		tostring(x),
		tostring(y),
		tostring(z),
		tostring(isoObject)
	)
end

local function normalizeSpriteNames(value)
	if type(value) == "string" then
		return { value }
	end
	if type(value) ~= "table" then
		return nil
	end
	if value[1] ~= nil then
		return value
	end
	return nil
end

local function countList(list)
	local count = 0
	for _ in ipairs(list or {}) do
		count = count + 1
	end
	return count
end

function Smoke.start(opts)
	opts = opts or {}
	if registered then
		log("already registered; ignoring start()")
		return Smoke
	end
	if type(_G.isClient) == "function" and isClient() then
		log("skipped on client")
		return Smoke
	end
	if not (_G.MapObjects and type(_G.MapObjects.OnLoadWithSprite) == "function") then
		log("MapObjects.OnLoadWithSprite unavailable")
		return Smoke
	end

	local spriteNames = normalizeSpriteNames(opts.spriteNames) or SPRITE_NAMES
	if type(spriteNames) ~= "table" or spriteNames[1] == nil then
		log("no spriteNames provided; edit SPRITE_NAMES in this file")
		return Smoke
	end

	local priority = tonumber(opts.priority) or PRIORITY
	_G.MapObjects.OnLoadWithSprite(spriteNames, onLoad, priority)
	registered = true
	log("registered (%d sprites, priority=%s)", countList(spriteNames), tostring(priority))
	return Smoke
end

function Smoke.stop()
	log("no-op: MapObjects listeners cannot be removed; restart required to clear")
end

return Smoke
