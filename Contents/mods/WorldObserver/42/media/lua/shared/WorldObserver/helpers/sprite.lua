-- helpers/sprite.lua -- sprite helper set providing small value-add filters for sprite observations.
local Log = require("DREAMBase/log").withTag("WO.HELPER.sprite")
local RecordWrap = require("WorldObserver/helpers/record_wrap")
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

SpriteHelpers._internal = SpriteHelpers._internal or {}
SpriteHelpers._internal.recordWrap = SpriteHelpers._internal.recordWrap or RecordWrap.ensureState()
local recordWrap = SpriteHelpers._internal.recordWrap

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

if recordWrap.methods.getIsoGridSquare == nil then
	function recordWrap.methods:getIsoGridSquare(...)
		local fn = SquareHelpers.record and SquareHelpers.record.getIsoGridSquare
		if type(fn) == "function" then
			return fn(self, ...)
		end
		return self.IsoGridSquare
	end
end

if recordWrap.methods.nameIs == nil then
	function recordWrap.methods:nameIs(...)
		local fn = SpriteHelpers.record and SpriteHelpers.record.spriteNameIs
		if type(fn) == "function" then
			return fn(self, ...)
		end
		return false
	end
end

if recordWrap.methods.idIs == nil then
	function recordWrap.methods:idIs(...)
		local fn = SpriteHelpers.record and SpriteHelpers.record.spriteIdIs
		if type(fn) == "function" then
			return fn(self, ...)
		end
		return false
	end
end

if recordWrap.methods.highlight == nil then
	function recordWrap.methods:highlight(...)
		local fn = SquareHelpers.highlight
		if type(fn) == "function" then
			return fn(self, ...)
		end
		return nil, "noHighlight"
	end
end

if SpriteHelpers.record.removeSpriteObject == nil then
	--- Remove the sprite object represented by a sprite record.
	--- @param spriteRecord table|nil
	--- @return boolean|nil ok
	--- @return string|nil err
	function SpriteHelpers.record.removeSpriteObject(spriteRecord)
		if type(spriteRecord) ~= "table" then
			return nil, "badRecord"
		end

		local isoGridSquare = resolveIsoGridSquare(spriteRecord)
		if isoGridSquare == nil then
			if _G.WORLDOBSERVER_HEADLESS ~= true then
				Log:warn(
					"removeSpriteObject: missing IsoGridSquare for spriteKey=%s",
					tostring(spriteRecord.spriteKey)
				)
			end
			return nil, "noIsoGridSquare"
		end

		local isoObject = spriteRecord.IsoObject
		if isoObject == nil then
			if _G.WORLDOBSERVER_HEADLESS ~= true then
				Log:warn(
					"removeSpriteObject: missing IsoObject for spriteKey=%s",
					tostring(spriteRecord.spriteKey)
				)
			end
			return nil, "noIsoObject"
		end

		local ok, err = pcall(isoGridSquare.RemoveTileObject, isoGridSquare, isoObject)
		if ok then
			if _G.WORLDOBSERVER_HEADLESS ~= true then
				Log:info(
					"removeSpriteObject: removed spriteName=%s tile=%s",
					tostring(spriteRecord.spriteName),
					tostring(spriteRecord.tileLocation)
				)
			end
			return true
		end

		if _G.WORLDOBSERVER_HEADLESS ~= true then
			Log:warn(
				"removeSpriteObject: failed for spriteName=%s tile=%s err=%s "
					.. "(consider :distinct('sprite', seconds) to reduce log spam)",
				tostring(spriteRecord.spriteName),
				tostring(spriteRecord.tileLocation),
				tostring(err)
			)
		end
		return nil, tostring(err)
	end
end

if recordWrap.methods.removeSpriteObject == nil then
	function recordWrap.methods:removeSpriteObject(...)
		local fn = SpriteHelpers.record and SpriteHelpers.record.removeSpriteObject
		if type(fn) == "function" then
			return fn(self, ...)
		end
		return nil, "noRemoveSpriteObject"
	end
end

if SpriteHelpers.wrap == nil then
	--- Decorate a sprite record in-place to expose a small method surface via metatable.
	--- Returns the same table on success; refuses if the record already has a different metatable.
	--- @param record table
	--- @return table|nil wrappedRecord
	--- @return string|nil err
	function SpriteHelpers:wrap(record, opts)
		return RecordWrap.wrap(record, recordWrap, {
			family = "sprite",
			log = Log,
			headless = type(opts) == "table" and opts.headless or nil,
			methodNames = { "getIsoGridSquare", "nameIs", "idIs", "highlight", "removeSpriteObject" },
		})
	end
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
		-- Run as a finalTap so derived streams can reduce/group first (and so we don't consume the LQR where slot).
		return stream:finalTap(function(observation)
			local spriteRecord = spriteField(observation, target)
			if spriteRecord == nil then
				return
			end
			SpriteHelpers.record.removeSpriteObject(spriteRecord)
		end)
	end
end
if SpriteHelpers.stream.removeSpriteObject == nil then
	function SpriteHelpers.stream.removeSpriteObject(stream, fieldName)
		return SpriteHelpers.removeSpriteObject(stream, fieldName)
	end
end

return SpriteHelpers
