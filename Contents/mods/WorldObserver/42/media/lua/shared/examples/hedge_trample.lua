-- hedge_trample.lua — minimal example: inner join zombies + sprites on tileLocation.
--[[ Usage in PZ console:
ht = require("examples/hedge_trample")
ht.start()
-- and to stop
ht.stop()
]]
--

local HedgeTrample = {}

local MOD_ID = "examples/hedge_trample"

local leases = nil
local sub = nil

function HedgeTrample.start()
	HedgeTrample.stop()

	local WorldObserver = require("WorldObserver")

	leases = {
		zombies = WorldObserver.factInterest:declare(MOD_ID, "zombies", {
			type = "zombies",
			scope = "allLoaded",
			radius = { desired = 25 },
			zRange = { desired = 1 },
			staleness = { desired = 1 },
			cooldown = { desired = 1 },
			highlight = { 1, 0.2, 0.2 },
		}),
		sprites = WorldObserver.factInterest:declare(MOD_ID, "sprites", {
			type = "sprites",
			scope = "near",
			radius = { desired = 25 },
			staleness = { desired = 10 },
			cooldown = { desired = 20 },
			highlight = { 0.2, 0.2, 0.8 },
			spriteNames = {
				"vegetation_ornamental_01_0",
				"vegetation_ornamental_01_1",
				"vegetation_ornamental_01_2",
				"vegetation_ornamental_01_3",
				"vegetation_ornamental_01_4",
				"vegetation_ornamental_01_5",
				"vegetation_ornamental_01_6",
				"vegetation_ornamental_01_7",
				"vegetation_ornamental_01_8",
				"vegetation_ornamental_01_9",
				"vegetation_ornamental_01_10",
				"vegetation_ornamental_01_11",
				"vegetation_ornamental_01_12",
				"vegetation_ornamental_01_13",
			},
		}),
	}

	local joined = WorldObserver.observations:derive({
		zombies = WorldObserver.observations:zombies(),
		sprites = WorldObserver.observations:sprites(),
	}, function(lqr)
		return lqr.zombies
			:innerJoin(lqr.sprites)
			:using({ zombie = "tileLocation", sprite = "tileLocation" })
			:joinWindow({ time = 50 * 1000, field = "sourceTime" })
	end)

	sub = joined:subscribe(function(observation)
		local zombie = observation and observation.zombie or nil
		local sprite = observation and observation.sprite or nil
		if type(zombie) ~= "table" or type(sprite) ~= "table" then
			return
		end
		print(
			("[WO] zombie id=%s sprite=%s tile=%s"):format(
				tostring(zombie.zombieId),
				tostring(sprite.spriteName),
				tostring(zombie.tileLocation)
			)
		)
		--sprite:
	end)
end

function HedgeTrample.stop()
	if sub and sub.unsubscribe then
		sub:unsubscribe()
	end
	sub = nil

	for _, lease in pairs(leases or {}) do
		if lease and lease.stop then
			lease:stop()
		end
	end
	leases = nil
end

return HedgeTrample
