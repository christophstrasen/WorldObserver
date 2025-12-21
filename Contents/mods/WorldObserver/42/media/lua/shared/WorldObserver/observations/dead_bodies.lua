-- observations/dead_bodies.lua -- wraps dead body facts into a DeadBodyObservation stream and exposes it as observation.deadBody.
local LQR = require("LQR")
local Log = require("LQR/util/log").withTag("WO.OBS.deadBodies")
local Query = LQR.Query
local Schema = LQR.Schema

local moduleName = ...
local DeadBodiesObservation = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		DeadBodiesObservation = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = DeadBodiesObservation
	end
end

-- Patch seam: define only when nil so mods can override by reassigning `DeadBodiesObservation.register`.
if DeadBodiesObservation.register == nil then
	function DeadBodiesObservation.register(observationRegistry, factRegistry, nextObservationId)
		observationRegistry:register("deadBodies", {
			enabled_helpers = { deadBody = "DeadBodyObservation" },
			fact_deps = { "deadBodies" },
			dimensions = {
				deadBody = {
					schema = "DeadBodyObservation",
					keyField = "deadBodyId",
				},
			},
			build = function()
				local facts = factRegistry:getObservable("deadBodies")
				local wrapped = Schema.wrap("DeadBodyObservation", facts, {
					idSelector = nextObservationId,
					sourceTimeField = "sourceTime",
				})

				local builder = Query.selectFrom(wrapped, "DeadBodyObservation")
					:selectSchemas({ DeadBodyObservation = "deadBody" })
				Log:info("dead bodies observation stream built")
				return builder
			end,
		})
	end
end

return DeadBodiesObservation
