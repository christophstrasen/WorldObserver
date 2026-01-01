-- helpers/vehicle.lua -- vehicle helper set providing basic filters.
local Log = require("DREAMBase/log").withTag("WO.HELPER.vehicle")
local RecordWrap = require("WorldObserver/helpers/record_wrap")
local SquareHelpers = require("WorldObserver/helpers/square")
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

VehicleHelpers._internal = VehicleHelpers._internal or {}
VehicleHelpers._internal.recordWrap = VehicleHelpers._internal.recordWrap or RecordWrap.ensureState()
local recordWrap = VehicleHelpers._internal.recordWrap

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

if VehicleHelpers.wrap == nil then
	--- Decorate a vehicle record in-place to expose a small method surface via metatable.
	--- Returns the same table on success; refuses if the record already has a different metatable.
	--- @param record table
	--- @return table|nil wrappedRecord
	--- @return string|nil err
	function VehicleHelpers:wrap(record, opts)
		return RecordWrap.wrap(record, recordWrap, {
			family = "vehicle",
			log = Log,
			headless = type(opts) == "table" and opts.headless or nil,
			methodNames = { "getIsoGridSquare", "highlight" },
		})
	end
end

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
