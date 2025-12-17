-- observations/zombies.lua -- wraps zombie facts into a ZombieObservation stream and exposes it as observation.zombie.
local LQR = require("LQR")
local Log = require("LQR/util/log").withTag("WO.OBS.zombies")
local Query = LQR.Query
local Schema = LQR.Schema

local moduleName = ...
local ZombiesObservation = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		ZombiesObservation = loaded
	else
		package.loaded[moduleName] = ZombiesObservation
	end
end

-- Patch seam: define only when nil so mods can override by reassigning `ZombiesObservation.register`.
if ZombiesObservation.register == nil then
	function ZombiesObservation.register(observationRegistry, factRegistry, nextObservationId)
		observationRegistry:register("zombies", {
			enabled_helpers = { zombie = "ZombieObservation" },
			fact_deps = { "zombies" },
			dimensions = {
				zombie = {
					schema = "ZombieObservation",
					keyField = "zombieId",
				},
			},
			build = function()
				local facts = factRegistry:getObservable("zombies")
				local wrapped = Schema.wrap("ZombieObservation", facts, {
					idSelector = nextObservationId,
					sourceTimeField = "observedAtTimeMS",
				})

				local builder = Query.selectFrom(wrapped, "ZombieObservation")
					:selectSchemas({ ZombieObservation = "zombie" })
				Log:info("zombies observation stream built")
				return builder
			end,
		})
	end
end

return ZombiesObservation
