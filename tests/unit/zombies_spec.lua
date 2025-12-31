package.path = table.concat({
	"Contents/mods/WorldObserver/42/media/lua/shared/?.lua",
	"Contents/mods/WorldObserver/42/media/lua/shared/?/init.lua",
	"../DREAMBase/Contents/mods/DREAMBase/42/media/lua/shared/?.lua",
	"../DREAMBase/Contents/mods/DREAMBase/42/media/lua/shared/?/init.lua",
	"external/DREAMBase/Contents/mods/DREAMBase/42/media/lua/shared/?.lua",
	"external/DREAMBase/Contents/mods/DREAMBase/42/media/lua/shared/?/init.lua",
	"external/LQR/?.lua",
	"external/LQR/?/init.lua",
	"external/lua-reactivex/?.lua",
	"external/lua-reactivex/?/init.lua",
	package.path,
}, ";")
_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true


local InterestRegistry = require("WorldObserver/interest/registry")
local Record = require("WorldObserver/facts/zombies/record")

describe("zombies interest and records", function()
	it("merges zRange with radius-style semantics", function()
		local registry = InterestRegistry.new({ ttlMs = 1000000 })
		registry:declare("m1", "a", { type = "zombies", scope = "allLoaded", zRange = { desired = 0, tolerable = 0 } })
		registry:declare("m2", "b", { type = "zombies", scope = "allLoaded", zRange = { desired = 2, tolerable = 3 } })

		local merged = registry:effective("zombies", nil, { bucketKey = "allLoaded" })
		assert.is_truthy(merged)
		assert.equals(2, merged.zRange.desired)
		assert.equals(3, merged.zRange.tolerable)
	end)

	it("carries highlight preference through merging", function()
		local registry = InterestRegistry.new({ ttlMs = 1000000 })
		registry:declare("m1", "a", { type = "zombies", scope = "allLoaded", highlight = true })
		local merged = registry:effective("zombies", nil, { bucketKey = "allLoaded" })
		assert.is_truthy(merged)
		assert.is_true(merged.highlight)
	end)

	it("builds a minimal zombie record", function()
		local square = {
			getID = function()
				return 321
			end,
			getX = function()
				return 10
			end,
			getY = function()
				return 11
			end,
			getZ = function()
				return 0
			end,
		}
		local targetSquare = {
			getID = function()
				return 654
			end,
			getX = function()
				return 12
			end,
			getY = function()
				return 13
			end,
			getZ = function()
				return 0
			end,
		}
		local target = {
			getID = function()
				return 99
			end,
			getOnlineID = function()
				return 7
			end,
			getX = function()
				return 12
			end,
			getY = function()
				return 13
			end,
			getZ = function()
				return 0
			end,
			getCurrentSquare = function()
				return targetSquare
			end,
		}
		local zombie = {
			getID = function()
				return 42
			end,
			getOnlineID = function()
				return 8
			end,
			getX = function()
				return 5
			end,
			getY = function()
				return 6
			end,
			getZ = function()
				return 0
			end,
			getCurrentSquare = function()
				return square
			end,
			isMoving = function()
				return true
			end,
			isRunning = function()
				return false
			end,
			isCrawling = function()
				return false
			end,
			getTarget = function()
				return target
			end,
			isTargetVisible = function()
				return true
			end,
			getTargetSeenTime = function()
				return 1.5
			end,
			getOutfitName = function()
				return "TestOutfit"
			end,
			speedType = 2,
		}

		local record = Record.makeZombieRecord(zombie, "probe")
		assert.is_truthy(record)
		assert.equals(42, record.zombieId)
		assert.equals("42", record.woKey)
		assert.equals(8, record.zombieOnlineId)
		assert.equals(321, record.squareId)
		assert.equals(5, record.tileX)
		assert.equals(6, record.tileY)
		assert.equals(0, record.tileZ)
		assert.equals("x5y6z0", record.tileLocation)
		assert.equals("walker", record.locomotion)
		assert.is_true(record.hasTarget)
		assert.equals(99, record.targetId)
		assert.equals(654, record.targetSquareId)
		assert.equals("TestOutfit", record.outfitName)
		assert.is_nil(record.sourceTime)
	end)

	it("rehydrates a zombie by id from the cell list", function()
		local zombie = {
			id = 7,
			getID = function(self)
				return self.id
			end,
		}
		local list = {
			size = function()
				return 1
			end,
			get = function(_, idx)
				assert.equals(0, idx)
				return zombie
			end,
		}
		local oldGetCell = _G.getCell
		_G.getCell = function()
			return {
				getZombieList = function()
					return list
				end,
			}
		end
		local ZombieHelpers = require("WorldObserver/helpers/zombie")
		local resolved = ZombieHelpers.record.getIsoZombie({ zombieId = 7 })
		assert.equals(zombie, resolved)
		_G.getCell = oldGetCell
	end)

	it("withinInterest respects zRange and radius", function()
		local Probe = require("WorldObserver/facts/zombies/probe")
		local fn = Probe._internal.withinInterest
		local record = { x = 5, y = 5, z = 1 }
		local player = { x = 5, y = 5, z = 3 }
		assert.is_false(fn(record, player, 10, 1)) -- z diff 2 > zRange
		assert.is_true(fn(record, { x = 6, y = 6, z = 2 }, 10, 2))
		assert.is_false(fn(record, { x = 20, y = 20, z = 1 }, 5, 2))
	end)

	it("only highlights zombies when requested via interest", function()
		local savedGetNumActivePlayers = _G.getNumActivePlayers
		local savedGetSpecificPlayer = _G.getSpecificPlayer
		local savedGetCell = _G.getCell

		_G.getNumActivePlayers = function()
			return 1
		end
		_G.getSpecificPlayer = function()
			return {
				getX = function()
					return 5
				end,
				getY = function()
					return 5
				end,
				getZ = function()
					return 0
				end,
			}
		end

		local zombieSquare = { id = "zSquare" }
		local zombie = {
			getCurrentSquare = function()
				return zombieSquare
			end,
		}
		_G.getCell = function()
			return {
				getZombieList = function()
					return {
						size = function()
							return 1
						end,
						get = function(_, idx0)
							assert.equals(0, idx0)
							return zombie
						end,
					}
				end,
			}
		end

		local SquareHelpers = require("WorldObserver/helpers/square")
		local savedSquareHighlight = SquareHelpers.highlight
		local highlightCalls = 0
		SquareHelpers.highlight = function()
			highlightCalls = highlightCalls + 1
		end

		local Probe = require("WorldObserver/facts/zombies/probe")

		do
			local registry = InterestRegistry.new({ ttlMs = 1000000 })
			registry:declare("m1", "a", {
				type = "zombies",
				scope = "allLoaded",
				staleness = { desired = 1, tolerable = 2 },
				radius = { desired = 25, tolerable = 30 },
				zRange = { desired = 1, tolerable = 2 },
				cooldown = { desired = 0, tolerable = 0 },
			})

			Probe.tick({
				state = {},
				emitFn = function() end,
				headless = false,
				runtime = nil,
				interestRegistry = registry,
				probeCfg = {},
				makeZombieRecord = function()
					return { zombieId = 1, x = 5, y = 5, z = 0 }
				end,
			})
			assert.equals(0, highlightCalls)
		end

		do
			local registry = InterestRegistry.new({ ttlMs = 1000000 })
			registry:declare("m1", "a", {
				type = "zombies",
				scope = "allLoaded",
				staleness = { desired = 1, tolerable = 2 },
				radius = { desired = 25, tolerable = 30 },
				zRange = { desired = 1, tolerable = 2 },
				cooldown = { desired = 0, tolerable = 0 },
				highlight = true,
			})

			Probe.tick({
				state = {},
				emitFn = function() end,
				headless = false,
				runtime = nil,
				interestRegistry = registry,
				probeCfg = {},
				makeZombieRecord = function()
					return { zombieId = 1, x = 5, y = 5, z = 0 }
				end,
			})
			assert.equals(1, highlightCalls)
		end

		SquareHelpers.highlight = savedSquareHighlight
		_G.getNumActivePlayers = savedGetNumActivePlayers
		_G.getSpecificPlayer = savedGetSpecificPlayer
		_G.getCell = savedGetCell
	end)

	it("highlights zombies via outline APIs when available", function()
		local savedEvents = _G.Events
		_G.Events = {
			OnTick = {
				Add = function() end,
				Remove = function() end,
			},
		}
		local calledOn = {}
		local target = {
			setOutlineHighlightColor = function(_, r, g, b, a)
				calledOn.color = { r, g, b, a }
			end,
			setOutlineHighlight = function(_, enabled)
				calledOn.enabled = enabled
			end,
			getID = function()
				return 1
			end,
		}
		local ZombieHelpers = require("WorldObserver/helpers/zombie")
		local handle = ZombieHelpers.highlight(target, 0, { color = { 1, 0, 0 }, alpha = 0.5 })
		assert.same({ 1, 0, 0, 0.5 }, calledOn.color)
		assert.is_true(calledOn.enabled)
		if handle and handle.stop then
			handle.stop()
		end
		assert.is_false(calledOn.enabled)
		_G.Events = savedEvents
	end)
end)
