-- smoke_squares.lua — console-friendly smoke test for WorldObserver squares.
-- Usage in PZ console:
--[[ @AI agent dont change this
		_G.WORLDOBSERVER_CONFIG_OVERRIDES = { facts = { squares = { probe = { infoLogEveryMs = 500, logEachSweep = true } } } }
	   smoke = require("examples/smoke_squares")
	   handles = smoke.start({ distinctSeconds = 20, withHelpers = true })
	   handles:stop()
		]]
--
-- Notes:
-- - This smoke test declares two interests (probes): `squares` scope=near and scope=vision.
-- - It subscribes to the squares observation stream and prints observations (optionally filtered).

local Log = require("DREAMBase/log")
Log.setLevel("info")

local SmokeSquares = {}

local INTEREST_NEAR = {
	type = "squares",
	scope = "near",
	staleness = { desired = 2, tolerable = 5 },
	radius = { desired = 8, tolerable = 5 },
	cooldown = { desired = 5, tolerable = 10 },
	highlight = true,
}

local INTEREST_VISION = {
	type = "squares",
	scope = "vision",
	staleness = { desired = 2, tolerable = 5 },
	radius = { desired = 20, tolerable = 10 },
	cooldown = { desired = 5, tolerable = 10 },
	highlight = true,
}

local LEASE_OPTS = {
	ttlSeconds = 60 * 60, -- smoke tests can run longer than the default 10 minutes
}

-- Subscribe to the squares stream with optional filters and a heartbeat.
function SmokeSquares.start(opts)
	opts = opts or {}
	local WorldObserver = require("WorldObserver")

	-- Declare upstream interest (keep it explicit and readable).
	local modId = "examples/smoke_squares"
	local nearLease = WorldObserver.factInterest:declare(modId, "near", INTEREST_NEAR, LEASE_OPTS)
	local visionLease = WorldObserver.factInterest:declare(modId, "vision", INTEREST_VISION, LEASE_OPTS)

	-- Build stream.
	local stream = WorldObserver.observations:squares()
	local SquareHelper = WorldObserver.helpers.square.record
	local distinctSeconds = opts.distinctSeconds
	if distinctSeconds ~= nil then
		stream = stream:distinct("square", distinctSeconds)
	end
	if opts.withHelpers == true then
		-- Example: only keep squares with a corpse.
		stream = stream:squareFilter(SquareHelper.squareHasCorpse)
	end

	Log.info(
		"[smoke] subscribing to squares (distinctSeconds=%s, withHelpers=%s)",
		tostring(distinctSeconds),
		tostring(opts.withHelpers == true)
	)

	-- Subscribe and print rows.
	local subscription = stream:subscribe(function(observation)
		local prefix = (opts.withHelpers == true) and "[square ] corpse present" or "[square ] observed"
		WorldObserver.debug.printObservation(observation, { prefix = prefix })
	end)

	return {
		stop = function()
			if subscription and subscription.unsubscribe then
				subscription:unsubscribe()
				Log.info("[smoke] squares subscription stopped")
			end
			if nearLease and nearLease.stop then
				pcall(function()
					nearLease:stop()
				end)
			end
			if visionLease and visionLease.stop then
				pcall(function()
					visionLease:stop()
				end)
			end
		end,
	}
end

return SmokeSquares
