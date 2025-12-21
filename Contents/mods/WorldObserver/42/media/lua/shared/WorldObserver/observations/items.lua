-- observations/items.lua -- wraps item facts into an ItemObservation stream and exposes it as observation.item.
local LQR = require("LQR")
local Log = require("LQR/util/log").withTag("WO.OBS.items")
local Query = LQR.Query
local Schema = LQR.Schema

local moduleName = ...
local ItemsObservation = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		ItemsObservation = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = ItemsObservation
	end
end

-- Patch seam: define only when nil so mods can override by reassigning `ItemsObservation.register`.
if ItemsObservation.register == nil then
	function ItemsObservation.register(observationRegistry, factRegistry, nextObservationId)
		observationRegistry:register("items", {
			enabled_helpers = { item = "ItemObservation" },
			fact_deps = { "items" },
			dimensions = {
				item = {
					schema = "ItemObservation",
					keyField = "itemId",
				},
			},
			build = function()
				local facts = factRegistry:getObservable("items")
				local wrapped = Schema.wrap("ItemObservation", facts, {
					idSelector = nextObservationId,
					sourceTimeField = "sourceTime",
				})

				local builder = Query.selectFrom(wrapped, "ItemObservation")
					:selectSchemas({ ItemObservation = "item" })
				Log:info("items observation stream built")
				return builder
			end,
		})
	end
end

return ItemsObservation
