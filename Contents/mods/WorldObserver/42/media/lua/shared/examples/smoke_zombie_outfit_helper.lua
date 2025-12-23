-- smoke_zombie_outfit_helper.lua — console-friendly smoke test for zombie outfit helpers.
-- Usage in PZ console:
--[[ @AI agent dont change this
	smokeOutfit = require("examples/smoke_zombie_outfit_helper")
	handleOutfit = smokeOutfit.start({
		distinctSeconds = 5,
		staleness = 1,
		radius = 25,
		zRange = 1,
		cooldown = 2,
	})
	handleOutfit:stop()
]]
--

local SmokeZombieOutfit = {}

function SmokeZombieOutfit.start(opts)
	opts = opts or {}
	local WorldObserver = require("WorldObserver")
	local OutfitHelpers = require("examples/zombie_outfit_helper")

	local modId = opts.modId or "examples/smoke_zombie_outfit_helper"

	local interest = WorldObserver.factInterest:declare(modId, "allLoaded", {
		type = "zombies",
		scope = "allLoaded",
		staleness = { desired = opts.staleness or 1, tolerable = (opts.staleness or 1) * 2 },
		radius = { desired = opts.radius or 25, tolerable = (opts.radius or 25) + 5 },
		zRange = { desired = opts.zRange or 1, tolerable = (opts.zRange or 1) + 1 },
		cooldown = { desired = opts.cooldown or 2, tolerable = (opts.cooldown or 2) * 2 },
	})

	local stream = WorldObserver.observations
		:zombies()
		:withHelpers({ helperSets = { outfit = OutfitHelpers }, enabled_helpers = { outfit = "zombie" } })

	if opts.distinctSeconds then
		stream = stream:distinct("zombie", opts.distinctSeconds)
	end

	local subscription = stream:outfit_print():subscribe(function() end)

	return {
		stop = function()
			if subscription and subscription.unsubscribe then
				subscription:unsubscribe()
			end
			if interest and interest.stop then
				pcall(interest.stop)
			end
		end,
	}
end

return SmokeZombieOutfit
