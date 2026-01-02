-- hedge_trample_worldobserver.lua — teaching example: join zombies + sprites on tileLocation and remove hedge tiles.
--[[ Usage in PZ console:
--require("DREAMBase/log").setLevel("info")
ht = require("examples/hedge_trample_worldobserver")
ht.start()
-- stop:
ht.stop()
]]

local HedgeTrample = {}

local MOD_ID = "examples/hedge_trample_worldobserver"

local leases = nil
local subscription = nil

local function say(fmt, ...)
	if type(_G.print) == "function" then
		_G.print(string.format(fmt, ...))
	elseif type(print) == "function" then
		print(string.format(fmt, ...))
	end
end

function HedgeTrample.start()
	HedgeTrample.stop()

	local WorldObserver = require("WorldObserver")
	local SquareHelper = WorldObserver.helpers.square.record
	say("[WO hedge_trample] start")
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
			-- Hedge sprites (Build 42): watch the "vegetation_ornamental_01_*" family.
			-- This supports the trailing '%' prefix wildcard.
			spriteNames = { "vegetation_ornamental_01_%" },
		}),
	}

	subscription = WorldObserver.observations
		:derive({
			zombie = WorldObserver.observations:zombies(),
			sprite = WorldObserver.observations:sprites(),
		}, function(lqr)
			return lqr
				.zombie
				:innerJoin(lqr.sprite)
				:using({ zombie = "tileLocation", sprite = "tileLocation" })
				:joinWindow({ time = 50 * 1000 }) -- ms
				:distinct("zombie", { by = "zombieId", window = { time = 300 } }) --distincts to remove potential chattiness while keeping frequency high enough not to miss a walking-over-square
				:distinct("sprite", { by = "spriteKey", window = { time = 300 } })
				:groupByEnrich("tileLocation_grouped", function(row)
					return row.zombie.tileLocation -- Groups by tile location as this is where we want to take counts
				end)
				:groupWindow({ -- The group window is the "rule window": only zombies within the last 10s count.
					time = 10 * 1000,
					field = "zombie.sourceTime",
				})
				:aggregates({
					count = {
						{
							path = "zombie.zombieId",
							distinctFn = function(row)
								return row.zombie.zombieId and tostring(row.zombie.zombieId) -- count distinct zombies
							end,
						},
					},
				})
				:having(
					function(row) -- Only pass through when we observe that 2 zombies have been on the same tile (within the last 10s)
						SquareHelper.setSquareMarker( -- ah ah -side effect in :having only for debugs you nasty person!
							row.sprite,
							("zombies=%s"):format(tostring(row._count.zombie or 0))
						)
						return (row._count.zombie or 0) >= 2
					end
				)
		end)
		:removeSpriteObject()
		:subscribe(function(observation) end)
end

function HedgeTrample.stop()
	if subscription and subscription.unsubscribe then
		subscription:unsubscribe()
	end
	subscription = nil

	for _, lease in pairs(leases or {}) do
		if lease and lease.stop then
			lease:stop()
		end
	end
	leases = nil
end

return HedgeTrample
