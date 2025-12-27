-- observations/players.lua -- wraps player facts into a PlayerObservation stream and exposes it as observation.player.
local LQR = require("LQR")
local Log = require("LQR/util/log").withTag("WO.OBS.players")
local Query = LQR.Query
local Schema = LQR.Schema

local moduleName = ...
local PlayersObservation = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		PlayersObservation = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = PlayersObservation
	end
end

-- Patch seam: define only when nil so mods can override by reassigning `PlayersObservation.register`.
if PlayersObservation.register == nil then
	function PlayersObservation.register(observationRegistry, factRegistry, nextObservationId)
		observationRegistry:register("players", {
			enabled_helpers = { player = true },
			fact_deps = { "players" },
			dimensions = {
				player = {
					schema = "PlayerObservation",
					keyField = "playerKey",
				},
			},
			build = function()
				local facts = factRegistry:getObservable("players")
				local wrapped = Schema.wrap("PlayerObservation", facts, {
					idSelector = nextObservationId,
					sourceTimeField = "sourceTime",
				})

				local builder = Query.selectFrom(wrapped, "PlayerObservation")
					:selectSchemas({ PlayerObservation = "player" })
				Log:info("players observation stream built")
				return builder
			end,
		})
	end
end

return PlayersObservation
