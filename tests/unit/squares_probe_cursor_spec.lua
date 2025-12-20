package.path = table.concat({
	"Contents/mods/WorldObserver/42/media/lua/shared/?.lua",
	"Contents/mods/WorldObserver/42/media/lua/shared/?/init.lua",
	"external/LQR/?.lua",
	"external/LQR/?/init.lua",
	"external/lua-reactivex/?.lua",
	"external/lua-reactivex/?/init.lua",
	package.path,
}, ";")

	_G.WORLDOBSERVER_HEADLESS = true
	_G.LQR_HEADLESS = true

	local SquaresFacts = require("WorldObserver/facts/squares")
	local InterestRegistry = require("WorldObserver/interest/registry")

describe("squares probe cursor", function()
	it("buildRingOffsets returns a dense, unique Chebyshev sweep", function()
		local offsets = SquaresFacts._internal.buildRingOffsets(2)
		assert.equals(25, #offsets)

		local seen = {}
		for _, off in ipairs(offsets) do
			local dx, dy = off[1], off[2]
			local key = tostring(dx) .. "," .. tostring(dy)
			assert.is_nil(seen[key])
			seen[key] = true
			assert.is_true(math.max(math.abs(dx), math.abs(dy)) <= 2)
		end

		assert.is_true(seen["0,0"])
		assert.is_true(seen["2,2"])
		assert.is_true(seen["-2,-2"])
	end)

	it("buildRingOffsets(0) includes only the center", function()
		local offsets = SquaresFacts._internal.buildRingOffsets(0)
		assert.equals(1, #offsets)
		assert.equals(0, offsets[1][1])
		assert.equals(0, offsets[1][2])
	end)

		it("probeTick resolves near interest (no forward-ref bug)", function()
			local savedGetPlayer = _G.getPlayer
			local savedGetNumPlayers = _G.getNumActivePlayers
			local savedGetSpecificPlayer = _G.getSpecificPlayer
			_G.getPlayer = nil
			_G.getNumActivePlayers = nil
			_G.getSpecificPlayer = nil

			local interestRegistry = InterestRegistry.new({ ttlMs = 1000000 })
			interestRegistry:declare("test", "near", {
				type = "squares",
				scope = "near",
				target = { player = { id = 0 } },
			})

			local state = {}
			SquaresFacts._internal.probeTick(state, function() end, true, nil, interestRegistry, {})
			assert.is_table(state._interestPolicyState)
			assert.is_table(state._interestPolicyState["squares"])
			assert.is_table(state._interestPolicyState["squares"]["near:player:0"])

			_G.getPlayer = savedGetPlayer
		_G.getNumActivePlayers = savedGetNumPlayers
		_G.getSpecificPlayer = savedGetSpecificPlayer
	end)

		it("probe lag degrades the interest ladder", function()
			local savedGetPlayer = _G.getPlayer
			local savedGetNumPlayers = _G.getNumActivePlayers
			local savedGetSpecificPlayer = _G.getSpecificPlayer
			_G.getPlayer = nil
			_G.getNumActivePlayers = nil
			_G.getSpecificPlayer = nil

			local interestRegistry = InterestRegistry.new({ ttlMs = 1000000 })
			interestRegistry:declare("test", "near", {
				type = "squares",
				scope = "near",
				target = { player = { id = 0 } },
			})

			local nowMs = 0
			local runtime = {
				nowWall = function()
					return nowMs
			end,
			status_get = function()
				return {
					mode = "normal",
					window = {
						dropDelta = 0,
						avgFill = 0,
						avgIngestRate15 = 0,
						avgThroughput15 = 0,
					},
				}
			end,
		}

			local state = {}
			local emitFn = function() end
			SquaresFacts._internal.probeTick(state, emitFn, true, runtime, interestRegistry, {})

		assert.is_table(state._probeCursors)
		local cursor = state._probeCursors["near:player:0"]
		assert.is_table(cursor)
		cursor.sweepStartedMs = 0

			nowMs = 20000
			for _ = 1, 10 do
				SquaresFacts._internal.probeTick(state, emitFn, true, runtime, interestRegistry, {})
			end

		assert.is_table(state._interestPolicyState)
		local policyByBucket = state._interestPolicyState["squares"]
		assert.is_table(policyByBucket)
		assert.equals(2, policyByBucket["near:player:0"].qualityIndex)

		_G.getPlayer = savedGetPlayer
		_G.getNumActivePlayers = savedGetNumPlayers
		_G.getSpecificPlayer = savedGetSpecificPlayer
	end)
end)
