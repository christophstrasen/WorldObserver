-- observations/rooms.lua -- wraps room facts into a RoomObservation stream and exposes it as observation.room.
local LQR = require("LQR")
local Log = require("LQR/util/log").withTag("WO.OBS.rooms")
local Query = LQR.Query
local Schema = LQR.Schema

local moduleName = ...
local RoomsObservation = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		RoomsObservation = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = RoomsObservation
	end
end

-- Patch seam: define only when nil so mods can override by reassigning `RoomsObservation.register`.
if RoomsObservation.register == nil then
	function RoomsObservation.register(observationRegistry, factRegistry, nextObservationId)
		observationRegistry:register("rooms", {
			enabled_helpers = { room = "RoomObservation" },
			fact_deps = { "rooms" },
			dimensions = {
				room = {
					schema = "RoomObservation",
					keyField = "roomId",
				},
			},
			build = function()
				local facts = factRegistry:getObservable("rooms")
				local wrapped = Schema.wrap("RoomObservation", facts, {
					idSelector = nextObservationId,
					sourceTimeField = "sourceTime",
				})

				local builder = Query.selectFrom(wrapped, "RoomObservation")
					:selectSchemas({ RoomObservation = "room" })
				Log:info("rooms observation stream built")
				return builder
			end,
		})
	end
end

return RoomsObservation

