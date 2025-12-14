-- smoke_squares.lua — console-friendly smoke test for WorldObserver squares.
-- Usage in PZ console:
--[[ @AI agent dont change this
   smoke = require("examples/smoke_squares")
   handle = smoke.start({ distinctSeconds = 2, withHelpers = true })
   handle:stop()
]]
--

local Log = require("LQR/util/log")
Log.setLevel("info")

local SmokeSquares = {}

-- Pretty-printer for a square observation row.
local function formatSquare(observation)
	local sq = observation.square or {}
	return ("[square ] TO CLEAN! id=%s x=%s y=%s z=%s source=%s blood=%s corpse=%s trash=%s time=%s"):format(
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

-- Subscribe to the squares stream with optional filters and a heartbeat.
function SmokeSquares.start(opts)
	local WorldObserver = require("WorldObserver")
	opts = opts or {}

	-- Build stream.
	local stream = WorldObserver.observations.squares()
	if opts.distinctSeconds then
		stream = stream:distinct("square", opts.distinctSeconds)
	end
	if opts.withHelpers then
		-- Example: only keep squares that need cleaning.
		stream = stream:whereSquareNeedsCleaning()
	end

	Log.info(
		"[smoke] subscribing to squares (distinctSeconds=%s, withHelpers=%s)",
		tostring(opts.distinctSeconds),
		tostring(opts.withHelpers)
	)

	-- Subscribe and print rows.
	local receivedCount = 0
	local subscription = stream:subscribe(function(observation)
		receivedCount = receivedCount + 1
		print(formatSquare(observation))
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
