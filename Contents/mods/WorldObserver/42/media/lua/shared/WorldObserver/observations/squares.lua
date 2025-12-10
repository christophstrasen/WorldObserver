-- observations/squares.lua -- wraps square facts into a SquareObservation stream and exposes it as observation.square.
-- This is the base stream used in the MVP examples (blood near player, squareNeedsCleaning in api_proposal.md §5.5).
local LQR = require("LQR")
local Query = LQR.Query
local Schema = LQR.Schema

local SquaresObservation = {}

function SquaresObservation.register(observationRegistry, factRegistry, nextObservationId)
	observationRegistry:register("squares", {
		enabled_helpers = { square = "SquareObservation" },
		fact_deps = { "squares" },
		dimensions = {
			square = {
				schema = "SquareObservation",
				keyField = "squareId",
			},
		},
		build = function()
			local facts = factRegistry:getObservable("squares")
			-- Stamp facts with a per-observation id and sourceTime before feeding LQR, then expose as observation.square.
			-- Heloers we enabled (squareHasBloodSplat/squareNeedsCleaning) assume this schema and id.
			local wrapped = Schema.wrap("SquareObservation", facts, {
				idSelector = nextObservationId,
				sourceTimeField = "observedAtTimeMS",
			})

			local builder = Query.selectFrom(wrapped, "SquareObservation")
				:selectSchemas({ SquareObservation = "square" })
			return builder
		end,
	})
end

return SquaresObservation
