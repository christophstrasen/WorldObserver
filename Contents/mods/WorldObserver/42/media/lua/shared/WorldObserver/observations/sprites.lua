-- observations/sprites.lua -- wraps sprite facts into a SpriteObservation stream and exposes it as observation.sprite.
local LQR = require("LQR")
local Log = require("DREAMBase/log").withTag("WO.OBS.sprites")
local Query = LQR.Query
local Schema = LQR.Schema

local moduleName = ...
local SpritesObservation = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		SpritesObservation = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = SpritesObservation
	end
end

-- Patch seam: define only when nil so mods can override by reassigning `SpritesObservation.register`.
if SpritesObservation.register == nil then
	function SpritesObservation.register(observationRegistry, factRegistry, nextObservationId)
			observationRegistry:register("sprites", {
				enabled_helpers = { sprite = true },
				fact_deps = { "sprites" },
				dimensions = {
					sprite = {
						schema = "SpriteObservation",
					keyField = "spriteKey",
				},
			},
			build = function()
				local facts = factRegistry:getObservable("sprites")
				local wrapped = Schema.wrap("SpriteObservation", facts, {
					idSelector = nextObservationId,
					sourceTimeField = "sourceTime",
				})

				local builder = Query.selectFrom(wrapped, "SpriteObservation")
					:selectSchemas({ SpriteObservation = "sprite" })
				Log:info("sprites observation stream built")
				return builder
			end,
		})
	end
end

return SpritesObservation
