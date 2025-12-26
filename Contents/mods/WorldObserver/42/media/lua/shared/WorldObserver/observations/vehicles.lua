-- observations/vehicles.lua -- wraps vehicle facts into a VehicleObservation stream and exposes it as observation.vehicle.
local LQR = require("LQR")
local Log = require("LQR/util/log").withTag("WO.OBS.vehicles")
local Query = LQR.Query
local Schema = LQR.Schema

local moduleName = ...
local VehiclesObservation = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		VehiclesObservation = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = VehiclesObservation
	end
end

local function vehicleKeySelector(record)
	return record and (record.sqlId or record.vehicleId)
end

-- Patch seam: define only when nil so mods can override by reassigning `VehiclesObservation.register`.
if VehiclesObservation.register == nil then
	function VehiclesObservation.register(observationRegistry, factRegistry, nextObservationId)
		observationRegistry:register("vehicles", {
			enabled_helpers = { vehicle = true },
			fact_deps = { "vehicles" },
			dimensions = {
				vehicle = {
					schema = "VehicleObservation",
					keySelector = vehicleKeySelector,
				},
			},
			build = function()
				local facts = factRegistry:getObservable("vehicles")
				local wrapped = Schema.wrap("VehicleObservation", facts, {
					idSelector = nextObservationId,
					sourceTimeField = "sourceTime",
				})

				local builder = Query.selectFrom(wrapped, "VehicleObservation")
					:selectSchemas({ VehicleObservation = "vehicle" })
				Log:info("vehicles observation stream built")
				return builder
			end,
		})
	end
end

return VehiclesObservation
