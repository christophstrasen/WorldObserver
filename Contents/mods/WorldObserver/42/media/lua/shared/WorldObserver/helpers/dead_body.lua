-- helpers/dead_body.lua -- dead body helper set providing small value-add filters.
local Log = require("LQR/util/log").withTag("WO.HELPER.deadBody")
local moduleName = ...
local DeadBodyHelpers = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		DeadBodyHelpers = loaded
	else
		package.loaded[moduleName] = DeadBodyHelpers
	end
end

DeadBodyHelpers.record = DeadBodyHelpers.record or {}
DeadBodyHelpers.stream = DeadBodyHelpers.stream or {}

local function deadBodyField(observation, fieldName)
	local record = observation[fieldName]
	if record == nil then
		Log:warn("dead body helper called without field '%s' on observation", tostring(fieldName))
		return nil
	end
	return record
end

-- Stream sugar: apply a predicate to the dead body record directly.
if DeadBodyHelpers.whereDeadBody == nil then
	function DeadBodyHelpers.whereDeadBody(stream, fieldName, predicate)
		assert(type(predicate) == "function", "whereDeadBody predicate must be a function")
		local target = fieldName or "deadBody"
		return stream:filter(function(observation)
			local bodyRecord = deadBodyField(observation, target)
			return predicate(bodyRecord, observation) == true
		end)
	end
end
if DeadBodyHelpers.stream.whereDeadBody == nil then
	function DeadBodyHelpers.stream.whereDeadBody(stream, fieldName, ...)
		return DeadBodyHelpers.whereDeadBody(stream, fieldName, ...)
	end
end

return DeadBodyHelpers
