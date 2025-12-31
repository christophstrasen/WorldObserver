dofile("tests/unit/bootstrap.lua")

_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local SquareSweep = require("WorldObserver/facts/sensors/square_sweep")

describe("square sweep collectors", function()
	it("does not run collectors for interest types that are not active in shared mode", function()
		local calls = { squares = 0, items = 0 }
		local registry = {
			order = { "squares", "items" },
			orderCount = 2,
			byId = {
				squares = function()
					calls.squares = calls.squares + 1
					return true
				end,
				items = function()
					calls.items = calls.items + 1
					return true
				end,
			},
			typeById = {
				squares = "squares",
				items = "items",
			},
		}

		local diagTick = {
			collectorCallsByType = {},
			collectorEmitsByType = {},
			collectorErrorsByType = {},
		}
		local ctx = {
			collectors = registry,
			collectorContexts = {
				squares = { headless = true, state = {} },
				items = { headless = true, state = {} },
			},
			state = {
				_squareSweepDiagTick = diagTick,
			},
		}

		local cursor = { source = "probe" }
		local square = {}
		local effective = { cooldown = 0 }
		local collectorEffectives = {
			-- Only items is active for this bucket.
			items = { cooldown = 0, highlight = true },
		}

		local emitted =
			SquareSweep._internal.runCollectors(ctx, cursor, square, 0, 0, effective, collectorEffectives)

		assert.is_true(emitted)
		assert.equals(0, calls.squares)
		assert.equals(1, calls.items)
		assert.is_nil(diagTick.collectorCallsByType.squares)
		assert.equals(1, diagTick.collectorCallsByType.items)
	end)
end)
