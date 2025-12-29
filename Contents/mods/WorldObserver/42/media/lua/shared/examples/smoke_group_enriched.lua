-- smoke_group_enriched.lua -- console-friendly smoke for group_enriched emissions + WoMeta keys.
-- Usage in PZ console:
--[[ @AI agent dont change this
smoke = require("examples/smoke_group_enriched")
handle = smoke.start()
handle:stop()
]]

local Log = require("LQR/util/log")
Log.setLevel("info")

local SmokeGroupEnriched = {}

local INTEREST_SQUARES = {
	type = "squares",
	scope = "near",
	staleness = { desired = 2, tolerable = 5 },
	radius = { desired = 10, tolerable = 15 },
	cooldown = { desired = 2, tolerable = 5 },
	highlight = true,
}

local INTEREST_ZOMBIES = {
	type = "zombies",
	scope = "allLoaded",
	staleness = { desired = 2, tolerable = 5 },
	radius = { desired = 10, tolerable = 15 },
	cooldown = { desired = 2, tolerable = 5 },
	zRange = { desired = 1, tolerable = 1 },
	highlight = { 0.8, 0.2, 0.2 },
}

local LEASE_OPTS = {
	ttlSeconds = 60 * 60,
}

function SmokeGroupEnriched.start()
	local WorldObserver = require("WorldObserver")

	local modId = "examples/smoke_group_enriched"
	local squareLease = WorldObserver.factInterest:declare(modId, "squares", INTEREST_SQUARES, LEASE_OPTS)
	local zombieLease = WorldObserver.factInterest:declare(modId, "zombies", INTEREST_ZOMBIES, LEASE_OPTS)

	local stream = WorldObserver.observations:derive({
		square = WorldObserver.observations:squares(),
		zombie = WorldObserver.observations:zombies(),
	}, function(lqr)
		return lqr.square
			:innerJoin(lqr.zombie)
			:using({ square = "tileLocation", zombie = "tileLocation" })
			:groupByEnrich("tileLocation_grouped", function(row)
				return row.square.tileLocation
			end)
			:groupWindow({
				time = 10 * 1000,
				field = "zombie.sourceTime",
			})
			:aggregates({
				count = {
					{
						path = "zombie.zombieId",
						distinctFn = function(row)
							return row.zombie.zombieId and tostring(row.zombie.zombieId)
						end,
					},
				},
			})
	end)

	Log.info("[smoke] subscribing to group_enriched stream")
	local subscription = stream:subscribe(function(observation)
		WorldObserver.debug.printObservation(observation, { prefix = "[group_enriched] observed" })
		local woKey = observation.WoMeta and observation.WoMeta.key or "<missing>"
		Log.info("[group_enriched] woKey=%s", tostring(woKey))
	end)

	return {
		stop = function()
			if subscription and subscription.unsubscribe then
				subscription:unsubscribe()
				Log.info("[smoke] group_enriched subscription stopped")
			end
			if squareLease and squareLease.stop then
				pcall(function()
					squareLease:stop()
				end)
			end
			if zombieLease and zombieLease.stop then
				pcall(function()
					zombieLease:stop()
				end)
			end
		end,
	}
end

return SmokeGroupEnriched
