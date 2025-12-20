-- smoke_zombies.lua — console-friendly smoke test for WorldObserver zombies.
-- Usage in PZ console:
--[[ @AI agent dont change this
	_G.WORLDOBSERVER_CONFIG_OVERRIDES = { facts = { squares = { probe = { infoLogEveryMs = 500, logEachSweep = true } } } }
	smokez = require("examples/smoke_zombies")
	handlez = smoke.start({
		distinctSeconds = 10,
		staleness = 1,
		radius = 25,
		zRange = 1,
		cooldown = 2,
	})
	handlez:stop()
]]
--

local Log = require("LQR/util/log")
Log.setLevel("info")

local SmokeZombies = {}

function SmokeZombies.start(opts)
	opts = opts or {}
	local WorldObserver = require("WorldObserver")

	local modId = opts.modId or "examples/smoke_zombies"
	local interest = WorldObserver.factInterest:declare(modId, "allLoaded", {
		type = "zombies",
		staleness = { desired = opts.staleness or 1, tolerable = (opts.staleness or 1) * 2 },
		radius = { desired = opts.radius or 25, tolerable = (opts.radius or 25) + 5 },
		zRange = { desired = opts.zRange or 1, tolerable = (opts.zRange or 1) + 1 },
		cooldown = { desired = opts.cooldown or 2, tolerable = (opts.cooldown or 2) * 2 },
		highlight = true,
	})

	local stream = WorldObserver.observations.zombies()
	if opts.distinctSeconds then
		stream = stream:distinct("zombie", opts.distinctSeconds)
	end
	Log.info(
		"[smoke] subscribing to zombies (distinctSeconds=%s, radius=%s, zRange=%s)",
		tostring(opts.distinctSeconds),
		tostring(opts.radius),
		tostring(opts.zRange)
	)

	local subscription = stream:subscribe(function(observation)
		local z = observation.zombie
		if type(z) ~= "table" then
			return
		end

		Log.info(
			"[zombie] id=%s online=%s loc=(%s,%s,%s) locomotion=%s target=%s",
			tostring(z.zombieId),
			tostring(z.zombieOnlineId),
			tostring(z.x),
			tostring(z.y),
			tostring(z.z),
			tostring(z.locomotion),
			tostring(z.targetKind)
		)
	end)

	return {
		stop = function()
			if subscription and subscription.unsubscribe then
				subscription:unsubscribe()
				Log.info("[smoke] zombies subscription stopped")
			end
			if interest and interest.stop then
				pcall(interest.stop)
			end
		end,
	}
end

return SmokeZombies
