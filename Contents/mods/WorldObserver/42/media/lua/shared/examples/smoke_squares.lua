-- smoke_squares.lua -- console-friendly smoke test for WorldObserver squares.
-- Usage in PZ console:
--[[ 
	smoke = require("examples/smoke_squares")
 	smokestart({ distinctSeconds = 2, withHelpers = true })
	later: smoke:stop()
]]
--

local Log = require("LQR/util/log")
Log.setLevel("info")

local SmokeSquares = {}

local function fmt(observation)
	local sq = observation.square or {}
	return ("[square] id=%s x=%s y=%s z=%s source=%s blood=%s corpse=%s trash=%s time=%s"):format(
		tostring(sq.squareId),
		tostring(sq.x),
		tostring(sq.y),
		tostring(sq.z),
		tostring(sq.source),
		tostring(sq.hasBloodSplat),
		tostring(sq.hasCorpse),
		tostring(sq.hasTrashItems),
		tostring(sq.observedAtTimeMS)
	)
end

function SmokeSquares.start(opts)
	local WorldObserver = require("WorldObserver")
	opts = opts or {}

	local stream = WorldObserver.observations.squares()
	if opts.distinctSeconds then
		stream = stream:distinct("square", opts.distinctSeconds)
	end
	if opts.withHelpers then
		-- Example: only keep squares that need cleaning.
		stream = stream:squareNeedsCleaning()
	end

	Log.info(
		"[smoke] subscribing to squares (distinctSeconds=%s, withHelpers=%s)",
		tostring(opts.distinctSeconds),
		tostring(opts.withHelpers)
	)
	local subscription = stream:subscribe(function(observation)
		print(fmt(observation))
	end)

	return {
		stop = function()
			if subscription and subscription.unsubscribe then
				subscription:unsubscribe()
				Log.info("[smoke] squares subscription stopped")
			end
		end,
	}
end

return SmokeSquares
