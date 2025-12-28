-- smoke_situation_factory_squares.lua -- console-friendly smoke test for situation factories (squares).
-- Usage in PZ console:
--[[ @AI agent dont change this
		_G.WORLDOBSERVER_CONFIG_OVERRIDES = { facts = { squares = { probe = { infoLogEveryMs = 500, logEachSweep = true } } } }
	   smoke = require("examples/smoke_situation_factory_squares")
	   handles = smoke.start({ distinctSeconds = 20 })
	   handles:stop()
		]]
--
-- Notes:
-- - This smoke test declares interest for squares (near + vision).
-- - It defines a situation factory and subscribes via the situation API.

local Log = require("LQR/util/log")
Log.setLevel("info")

local SmokeSituationFactorySquares = {}

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

function SmokeSituationFactorySquares.start(opts)
	opts = opts or {}
	local WorldObserver = require("WorldObserver")

	local modId = "examples/smoke_situation_factory_squares"
	local nearLease = WorldObserver.factInterest:declare(modId, "near", INTEREST_NEAR, LEASE_OPTS)
	local visionLease = WorldObserver.factInterest:declare(modId, "vision", INTEREST_VISION, LEASE_OPTS)

	local situations = WorldObserver.situations.namespace("examples")
	situations.define("squaresNear", function(args)
		args = args or {}
		local stream = WorldObserver.observations:squares()
		if args.distinctSeconds ~= nil then
			stream = stream:distinct("square", args.distinctSeconds)
		end
		return stream
	end)

	local stream = situations.get("squaresNear", { distinctSeconds = opts.distinctSeconds })
	Log.info("[smoke] subscribing to situation squaresNear (distinctSeconds=%s)", tostring(opts.distinctSeconds))
	local subscription = stream:subscribe(function(observation)
		WorldObserver.debug.printObservation(observation, { prefix = "[situation] square observed" })
	end)

	return {
		stop = function()
			if subscription and subscription.unsubscribe then
				subscription:unsubscribe()
				Log.info("[smoke] situation squares subscription stopped")
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

return SmokeSituationFactorySquares
