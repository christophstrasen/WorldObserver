-- helpers/dead_body.lua -- dead body helper set providing small value-add filters.
local Log = require("DREAMBase/log").withTag("WO.HELPER.deadBody")
local moduleName = ...
local DeadBodyHelpers = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		DeadBodyHelpers = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = DeadBodyHelpers
	end
end

DeadBodyHelpers.record = DeadBodyHelpers.record or {}
DeadBodyHelpers.stream = DeadBodyHelpers.stream or {}

local function deadBodyField(observation, fieldName)
	local record = observation[fieldName]
	if record == nil then
		if _G.WORLDOBSERVER_HEADLESS ~= true then
			Log:warn("dead body helper called without field '%s' on observation", tostring(fieldName))
		end
		return nil
	end
	return record
end

-- Stream sugar: apply a predicate to the dead body record directly.
if DeadBodyHelpers.deadBodyFilter == nil then
	function DeadBodyHelpers.deadBodyFilter(stream, fieldName, predicate)
		assert(type(predicate) == "function", "deadBodyFilter predicate must be a function")
		local target = fieldName or "deadBody"
		return stream:filter(function(observation)
			local bodyRecord = deadBodyField(observation, target)
			return predicate(bodyRecord, observation) == true
		end)
	end
end
if DeadBodyHelpers.stream.deadBodyFilter == nil then
	function DeadBodyHelpers.stream.deadBodyFilter(stream, fieldName, ...)
		return DeadBodyHelpers.deadBodyFilter(stream, fieldName, ...)
	end
end

return DeadBodyHelpers
