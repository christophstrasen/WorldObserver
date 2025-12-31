-- smoke_zombies_outfit_filter.lua — console-friendly smoke test for :hasOutfit helper.
-- Usage in PZ console:
--[[ @AI agent dont change this
	smokeOutfit = require("examples/smoke_zombies_outfit_filter")
	handleOutfit = smokeOutfit.start({
		outfitName = "Biker",
		distinctSeconds = 5,
		staleness = 1,
		radius = 25,
		zRange = 1,
		cooldown = 2,
	})
	handleOutfit:stop()
]]
--

local Log = require("DREAMBase/log")
Log.setLevel("info")

local SmokeZombiesOutfitFilter = {}

function SmokeZombiesOutfitFilter.start(opts)
	opts = opts or {}
	local WorldObserver = require("WorldObserver")

	local modId = opts.modId or "examples/smoke_zombies_outfit_filter"
	local outfitName = opts.outfitName or "Biker"

	local interest = WorldObserver.factInterest:declare(modId, "allLoaded", {
		type = "zombies",
		staleness = { desired = opts.staleness or 1, tolerable = (opts.staleness or 1) * 2 },
		radius = { desired = opts.radius or 25, tolerable = (opts.radius or 25) + 5 },
		zRange = { desired = opts.zRange or 1, tolerable = (opts.zRange or 1) + 1 },
		cooldown = { desired = opts.cooldown or 2, tolerable = (opts.cooldown or 2) * 2 },
		highlight = true,
	})

	local stream = WorldObserver.observations:zombies():hasOutfit(outfitName)
	if opts.distinctSeconds then
		stream = stream:distinct("zombie", opts.distinctSeconds)
	end
	Log.info(
		"[smoke] subscribing to zombies with outfit=%s (distinctSeconds=%s)",
		tostring(outfitName),
		tostring(opts.distinctSeconds)
	)

	local subscription = stream:subscribe(function(observation)
		local z = observation.zombie
		if type(z) ~= "table" then
			return
		end

		Log.info(
			"[zombie] id=%s outfit=%s loc=(%s,%s,%s)",
			tostring(z.zombieId),
			tostring(z.outfitName),
			tostring(z.x),
			tostring(z.y),
			tostring(z.z)
		)
	end)

	return {
		stop = function()
			if subscription and subscription.unsubscribe then
				subscription:unsubscribe()
				Log.info("[smoke] zombies outfit subscription stopped")
			end
			if interest and interest.stop then
				pcall(interest.stop)
			end
		end,
	}
end

return SmokeZombiesOutfitFilter
