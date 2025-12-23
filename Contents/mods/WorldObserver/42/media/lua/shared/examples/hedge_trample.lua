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
local joined = nil

function HedgeTrample.start()
	HedgeTrample.stop()

	local WorldObserver = require("WorldObserver")
	local defaultWindow = {
		mode = "time",
		time = 10 * 1000,
	}

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

	joined = WorldObserver.observations
		:derive({
			zombies = WorldObserver.observations:zombies(),
			sprites = WorldObserver.observations:sprites(),
		}, function(lqr)
			return lqr
				.zombies
				:innerJoin(lqr.sprites)
				:using({ zombie = "tileLocation", sprite = "tileLocation" })
				:joinWindow(defaultWindow)
				:distinct("sprite", { by = "spriteKey", window = defaultWindow })
				:distinct("zombie", { by = "zombieId", window = defaultWindow })
				-- Keep only tiles with at least two distinct zombies in the recent window.
				:groupByEnrich(
					"tileLocation_grouped",
					function(row)
						local zombie = row and row.zombie
						return zombie and zombie.tileLocation
					end
				)
				:groupWindow(defaultWindow)
				:aggregates({
					count = {
						{
							path = "zombie.zombieId",
							distinctFn = function(row)
								local zombie = row and row.zombie
								return zombie and zombie.zombieId
							end,
						},
					},
				})
				:having(function(row)
					local count = row and row._count and row._count.zombie or 0
					return count >= 2
				end)
		end)
		:removeSpriteObject()
		:subscribe(function(observation)
			local zombie = observation and observation.zombie or nil
			local sprite = observation and observation.sprite or nil
			local zombieCount = observation and observation._count and observation._count.zombie or nil
			if type(zombie) ~= "table" or type(sprite) ~= "table" then
				print("This should not happen.")
				return
			end
			print(
				("[WO] ABOUT TO REMOVE THE HEDGE zombiesOnTile=%s zombieId=%s sprite=%s tile=%s"):format(
					tostring(zombieCount),
					tostring(zombie.zombieId),
					tostring(sprite.spriteName),
					tostring(zombie.tileLocation)
				)
			)
		end)
end

function HedgeTrample.stop()
	if joined and joined.unsubscribe then
		joined:unsubscribe()
	end
	joined = nil

	for _, lease in pairs(leases or {}) do
		if lease and lease.stop then
			lease:stop()
		end
	end
	leases = nil
end

return HedgeTrample
