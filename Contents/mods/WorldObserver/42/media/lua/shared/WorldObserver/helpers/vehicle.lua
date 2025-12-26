-- helpers/vehicle.lua -- vehicle helper set providing basic filters.
local Log = require("LQR/util/log").withTag("WO.HELPER.vehicle")
local moduleName = ...
local VehicleHelpers = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		VehicleHelpers = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = VehicleHelpers
	end
end

VehicleHelpers.record = VehicleHelpers.record or {}
VehicleHelpers.stream = VehicleHelpers.stream or {}

local function vehicleField(observation, fieldName)
	local vehicleRecord = observation[fieldName]
	if vehicleRecord == nil then
		if _G.WORLDOBSERVER_HEADLESS ~= true then
			Log:warn("vehicle helper called without field '%s' on observation", tostring(fieldName))
		end
		return nil
	end
	return vehicleRecord
end

-- Stream sugar: apply a predicate to the vehicle record directly.
-- This avoids leaking LQR schema names (e.g. "VehicleObservation") into mod code.
if VehicleHelpers.vehicleFilter == nil then
	function VehicleHelpers.vehicleFilter(stream, fieldName, predicate)
		assert(type(predicate) == "function", "vehicleFilter predicate must be a function")
		local target = fieldName or "vehicle"
		return stream:filter(function(observation)
			local vehicleRecord = vehicleField(observation, target)
			return predicate(vehicleRecord, observation) == true
		end)
	end
end
if VehicleHelpers.stream.vehicleFilter == nil then
	function VehicleHelpers.stream.vehicleFilter(stream, fieldName, ...)
		return VehicleHelpers.vehicleFilter(stream, fieldName, ...)
	end
end

return VehicleHelpers
