-- helpers/square.lua -- square helper set (MVP) providing named filters for square observations.
local Log = require("LQR.util.log").withTag("WO.HELPER.square")
local SquareHelpers = {}

local function squareField(observation, fieldName)
	-- Helpers should be forgiving if a stream remaps the square field.
	local square = observation[fieldName]
	if square == nil then
		Log:warn("square helper called without field '%s' on observation", tostring(fieldName))
		return {}
	end
	return square
end

function SquareHelpers.squareHasBloodSplat(stream, fieldName)
	local target = fieldName or "square"
	return stream:filter(function(observation)
		local square = squareField(observation, target)
		return square.hasBloodSplat == true
	end)
end

function SquareHelpers.squareNeedsCleaning(stream, fieldName)
	local target = fieldName or "square"
	return stream:filter(function(observation)
		local square = squareField(observation, target)
		return square.hasBloodSplat == true or square.hasCorpse == true or square.hasTrashItems == true
	end)
end

return SquareHelpers
