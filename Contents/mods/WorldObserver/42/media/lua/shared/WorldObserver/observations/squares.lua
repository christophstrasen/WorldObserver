-- observations/squares.lua -- wraps square facts into a SquareObservation stream and exposes it as observation.square.
-- This is the base stream used in the MVP examples.
local LQR = require("LQR")
local Log = require("DREAMBase/log").withTag("WO.OBS.squares")
local Query = LQR.Query
local Schema = LQR.Schema

local moduleName = ...
local SquaresObservation = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		SquaresObservation = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = SquaresObservation
	end
end

-- Patch seam: define only when nil so mods can override by reassigning `SquaresObservation.register` and so
-- reloads (tests/console via `package.loaded`) don't clobber an existing patch.
if SquaresObservation.register == nil then
	function SquaresObservation.register(observationRegistry, factRegistry, nextObservationId)
			observationRegistry:register("squares", {
				-- Helpers run on the final stream output (after selectSchemas), so they can target `observation.square`.
				enabled_helpers = { square = true },
				fact_deps = { "squares" },
				dimensions = {
					square = {
						-- distinct/windowing runs before selectSchemas renames, so dimensions reference the pre-selection schema name.
						schema = "SquareObservation",
						keyField = "squareId",
					},
				},
				build = function()
					local facts = factRegistry:getObservable("squares")
					-- Stamp facts with a per-observation id and sourceTime before feeding LQR, then expose as observation.square.
					-- Helpers we enabled (example: squareHasCorpse) assume this schema and id.
					local wrapped = Schema.wrap("SquareObservation", facts, {
						idSelector = nextObservationId,
						sourceTimeField = "sourceTime",
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
