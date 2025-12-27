-- helpers/player.lua -- player helper set providing small value-add filters for player observations.
local Log = require("LQR/util/log").withTag("WO.HELPER.player")
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
