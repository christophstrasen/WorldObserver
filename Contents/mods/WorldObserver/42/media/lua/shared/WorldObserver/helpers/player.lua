-- helpers/player.lua -- player helper set providing small value-add filters for player observations.
local Log = require("DREAMBase/log").withTag("WO.HELPER.player")
local RecordWrap = require("WorldObserver/helpers/record_wrap")
local SquareHelpers = require("WorldObserver/helpers/square")
local moduleName = ...
local PlayerHelpers = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		PlayerHelpers = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = PlayerHelpers
	end
end

PlayerHelpers.record = PlayerHelpers.record or {}
PlayerHelpers.stream = PlayerHelpers.stream or {}

if PlayerHelpers.record.getIsoPlayer == nil then
	--- Best-effort: return the live IsoPlayer for a record.
	--- @param record table|nil
	--- @return any
	function PlayerHelpers.record.getIsoPlayer(record)
		if type(record) ~= "table" then
			return nil
		end
		return record.IsoPlayer
	end
end

PlayerHelpers._internal = PlayerHelpers._internal or {}
PlayerHelpers._internal.recordWrap = PlayerHelpers._internal.recordWrap or RecordWrap.ensureState()
local recordWrap = PlayerHelpers._internal.recordWrap

if recordWrap.methods.getIsoPlayer == nil then
	function recordWrap.methods:getIsoPlayer(...)
		local fn = PlayerHelpers.record and PlayerHelpers.record.getIsoPlayer
		if type(fn) == "function" then
			return fn(self, ...)
		end
		return nil
	end
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

if recordWrap.methods.highlight == nil then
	function recordWrap.methods:highlight(...)
		local fn = SquareHelpers.highlight
		if type(fn) == "function" then
			return fn(self, ...)
		end
		return nil, "noHighlight"
	end
end

if PlayerHelpers.wrap == nil then
	--- Decorate a player record in-place to expose a small method surface via metatable.
	--- Returns the same table on success; refuses if the record already has a different metatable.
	--- @param record table
	--- @return table|nil wrappedRecord
	--- @return string|nil err
	function PlayerHelpers:wrap(record, opts)
		return RecordWrap.wrap(record, recordWrap, {
			family = "player",
			log = Log,
			headless = type(opts) == "table" and opts.headless or nil,
			methodNames = { "getIsoPlayer", "getIsoGridSquare", "highlight" },
		})
	end
end

local function playerField(observation, fieldName)
	local record = observation[fieldName]
	if record == nil then
		if _G.WORLDOBSERVER_HEADLESS ~= true then
			Log:warn("player helper called without field '%s' on observation", tostring(fieldName))
		end
		return nil
	end
	return record
end

-- Stream sugar: apply a predicate to the player record directly.
if PlayerHelpers.playerFilter == nil then
	function PlayerHelpers.playerFilter(stream, fieldName, predicate)
		assert(type(predicate) == "function", "playerFilter predicate must be a function")
		local target = fieldName or "player"
		return stream:filter(function(observation)
			local record = playerField(observation, target)
			return predicate(record, observation) == true
		end)
	end
end
if PlayerHelpers.stream.playerFilter == nil then
	function PlayerHelpers.stream.playerFilter(stream, fieldName, ...)
		return PlayerHelpers.playerFilter(stream, fieldName, ...)
	end
end

return PlayerHelpers
