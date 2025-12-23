-- helpers/sprite.lua -- sprite helper set providing small value-add filters for sprite observations.
local Log = require("LQR/util/log").withTag("WO.HELPER.sprite")
local SquareHelpers = require("WorldObserver/helpers/square")
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
		if _G.WORLDOBSERVER_HEADLESS ~= true then
			Log:warn("sprite helper called without field '%s' on observation", tostring(fieldName))
		end
		return nil
	end
	return record
end

local function resolveIsoGridSquare(spriteRecord)
	if type(spriteRecord) ~= "table" then
		return nil
	end
	if SquareHelpers.record and SquareHelpers.record.getIsoGridSquare then
		return SquareHelpers.record.getIsoGridSquare(spriteRecord)
	end
	return spriteRecord.IsoGridSquare
end

-- Stream sugar: apply a predicate to the sprite record directly.
if SpriteHelpers.spriteFilter == nil then
	function SpriteHelpers.spriteFilter(stream, fieldName, predicate)
		assert(type(predicate) == "function", "spriteFilter predicate must be a function")
		local target = fieldName or "sprite"
		return stream:filter(function(observation)
			local spriteRecord = spriteField(observation, target)
			return predicate(spriteRecord, observation) == true
		end)
	end
end
if SpriteHelpers.stream.spriteFilter == nil then
	function SpriteHelpers.stream.spriteFilter(stream, fieldName, ...)
		return SpriteHelpers.spriteFilter(stream, fieldName, ...)
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

if SpriteHelpers.removeSpriteObject == nil then
	function SpriteHelpers.removeSpriteObject(stream, fieldName)
		local target = fieldName or "sprite"
		-- Use filter as a tap: keep chaining intact while firing an effectful removal per observation.
		return stream:filter(function(observation)
			local spriteRecord = spriteField(observation, target)
			if spriteRecord == nil then
				return true
			end

			local isoGridSquare = resolveIsoGridSquare(spriteRecord)
			if isoGridSquare == nil then
				Log:warn(
					"removeSpriteObject: missing IsoGridSquare for spriteKey=%s",
					tostring(spriteRecord.spriteKey)
				)
				return true
			end

			local isoObject = spriteRecord.IsoObject
			if isoObject == nil then
				Log:warn(
					"removeSpriteObject: missing IsoObject for spriteKey=%s",
					tostring(spriteRecord.spriteKey)
				)
				return true
			end

			local ok, err = pcall(isoGridSquare.RemoveTileObject, isoGridSquare, isoObject)
			if ok then
				Log:info(
					"removeSpriteObject: removed spriteName=%s tile=%s",
					tostring(spriteRecord.spriteName),
					tostring(spriteRecord.tileLocation)
				)
			else
				Log:warn(
					"removeSpriteObject: failed for spriteName=%s tile=%s err=%s (consider :distinct('sprite', seconds) to reduce log spam)",
					tostring(spriteRecord.spriteName),
					tostring(spriteRecord.tileLocation),
					tostring(err)
				)
			end

			return true
		end)
	end
end
if SpriteHelpers.stream.removeSpriteObject == nil then
	function SpriteHelpers.stream.removeSpriteObject(stream, fieldName, ...)
		return SpriteHelpers.removeSpriteObject(stream, fieldName, ...)
	end
end

return SpriteHelpers
