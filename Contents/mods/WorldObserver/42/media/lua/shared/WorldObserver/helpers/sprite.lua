-- helpers/sprite.lua -- sprite helper set providing small value-add filters for sprite observations.
local Log = require("LQR/util/log").withTag("WO.HELPER.sprite")
local moduleName = ...
local SpriteHelpers = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		SpriteHelpers = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = SpriteHelpers
	end
end

SpriteHelpers.record = SpriteHelpers.record or {}
SpriteHelpers.stream = SpriteHelpers.stream or {}

local function spriteField(observation, fieldName)
	local record = observation[fieldName]
	if record == nil then
		Log:warn("sprite helper called without field '%s' on observation", tostring(fieldName))
		return nil
	end
	return record
end

-- Stream sugar: apply a predicate to the sprite record directly.
if SpriteHelpers.whereSprite == nil then
	function SpriteHelpers.whereSprite(stream, fieldName, predicate)
		assert(type(predicate) == "function", "whereSprite predicate must be a function")
		local target = fieldName or "sprite"
		return stream:filter(function(observation)
			local spriteRecord = spriteField(observation, target)
			return predicate(spriteRecord, observation) == true
		end)
	end
end
if SpriteHelpers.stream.whereSprite == nil then
	function SpriteHelpers.stream.whereSprite(stream, fieldName, ...)
		return SpriteHelpers.whereSprite(stream, fieldName, ...)
	end
end

local function spriteNameIs(record, wanted)
	if type(record) ~= "table" then
		return false
	end
	if type(wanted) ~= "string" or wanted == "" then
		return false
	end
	return tostring(record.spriteName) == wanted
end

if SpriteHelpers.record.spriteNameIs == nil then
	SpriteHelpers.record.spriteNameIs = spriteNameIs
end

if SpriteHelpers.spriteNameIs == nil then
	function SpriteHelpers.spriteNameIs(stream, fieldName, wanted)
		local target = fieldName or "sprite"
		return stream:filter(function(observation)
			local spriteRecord = spriteField(observation, target)
			return SpriteHelpers.record.spriteNameIs(spriteRecord, wanted)
		end)
	end
end
if SpriteHelpers.stream.spriteNameIs == nil then
	function SpriteHelpers.stream.spriteNameIs(stream, fieldName, ...)
		return SpriteHelpers.spriteNameIs(stream, fieldName, ...)
	end
end

local function spriteIdIs(record, wanted)
	if type(record) ~= "table" then
		return false
	end
	if wanted == nil then
		return false
	end
	return tostring(record.spriteId) == tostring(wanted)
end

if SpriteHelpers.record.spriteIdIs == nil then
	SpriteHelpers.record.spriteIdIs = spriteIdIs
end

if SpriteHelpers.spriteIdIs == nil then
	function SpriteHelpers.spriteIdIs(stream, fieldName, wanted)
		local target = fieldName or "sprite"
		return stream:filter(function(observation)
			local spriteRecord = spriteField(observation, target)
			return SpriteHelpers.record.spriteIdIs(spriteRecord, wanted)
		end)
	end
end
if SpriteHelpers.stream.spriteIdIs == nil then
	function SpriteHelpers.stream.spriteIdIs(stream, fieldName, ...)
		return SpriteHelpers.spriteIdIs(stream, fieldName, ...)
	end
end

return SpriteHelpers
