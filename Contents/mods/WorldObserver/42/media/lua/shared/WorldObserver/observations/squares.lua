-- observations/squares.lua -- wraps square facts into a SquareObservation stream and exposes it as observation.square.
-- This is the base stream used in the MVP examples (blood near player, whereSquareNeedsCleaning in api_proposal.md §5.5).
local LQR = require("LQR")
local Log = require("LQR/util/log").withTag("WO.OBS.squares")
local Query = LQR.Query
local Schema = LQR.Schema

local moduleName = ...
local SquaresObservation = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		SquaresObservation = loaded
	else
		package.loaded[moduleName] = SquaresObservation
	end
end

-- Patch seam: define only when nil so mods can override by reassigning `SquaresObservation.register` and so
-- reloads (tests/console via `package.loaded`) don't clobber an existing patch.
if SquaresObservation.register == nil then
	function SquaresObservation.register(observationRegistry, factRegistry, nextObservationId)
		observationRegistry:register("squares", {
			-- NOTE: helper stream predicates run as Query.where predicates, which operate on LQR's row-view
			-- BEFORE any selectSchemas renames are applied. This means helpers must target the pre-selection
			-- schema name (SquareObservation), even though subscribers later see `observation.square`.
			enabled_helpers = { square = "SquareObservation" },
			fact_deps = { "squares" },
			dimensions = {
				square = {
					-- Same reasoning as enabled_helpers: distinct/windowing runs before selectSchemas renames,
					-- so dimensions must reference the pre-selection schema name.
					schema = "SquareObservation",
					keyField = "squareId",
				},
			},
			build = function()
				local facts = factRegistry:getObservable("squares")
				-- Stamp facts with a per-observation id and sourceTime before feeding LQR, then expose as observation.square.
				-- Heloers we enabled (squareHasBloodSplat/whereSquareNeedsCleaning) assume this schema and id.
				local wrapped = Schema.wrap("SquareObservation", facts, {
					idSelector = nextObservationId,
					sourceTimeField = "observedAtTimeMS",
				})

				local builder = Query.selectFrom(wrapped, "SquareObservation")
					:selectSchemas({ SquareObservation = "square" })
				Log:info("squares observation stream built")
				return builder
			end,
		})
	end
end

return SquaresObservation
