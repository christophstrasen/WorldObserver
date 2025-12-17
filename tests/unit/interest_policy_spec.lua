package.path = table.concat({
	"Contents/mods/WorldObserver/42/media/lua/shared/?.lua",
	"Contents/mods/WorldObserver/42/media/lua/shared/?/init.lua",
	"external/LQR/?.lua",
	"external/LQR/?/init.lua",
	"external/lua-reactivex/?.lua",
	"external/lua-reactivex/?/init.lua",
	package.path,
}, ";")

local Policy = require("WorldObserver/interest/policy")

describe("interest policy", function()
	local merged = {
		staleness = { desired = 10, tolerable = 20 },
		radius = { desired = 8, tolerable = 5 },
		cooldown = { desired = 30, tolerable = 60 },
	}

	local function status(opts)
		opts = opts or {}
		return {
			mode = opts.mode or "normal",
			window = {
				dropDelta = opts.dropDelta or 0,
				avgThroughput15 = opts.avgThroughput15 or 0,
				avgFill = opts.avgFill,
				budgetMs = opts.budgetMs,
				avgTickMs = opts.avgTickMs,
				reason = opts.reason,
			},
			tick = {
				lastMs = opts.tickLastMs,
				woAvgTickMs = opts.woAvgTickMs,
			},
		}
	end

	it("holds quality when there are no drops", function()
		local state, eff = Policy.update(nil, merged, status({ mode = "degraded", dropDelta = 0 }))
		assert.equals(1, state.qualityIndex)
		assert.equals(10, eff.staleness)
		assert.equals(8, eff.radius)
		assert.equals(30, eff.cooldown)
	end)

	it("degrades on sustained drops that exceed ratio threshold", function()
		local state, eff = Policy.update(nil, merged, status({ dropDelta = 5, avgThroughput15 = 10 }))
		assert.equals(2, state.qualityIndex) -- staleness raised to tolerable
		assert.equals(20, eff.staleness)
		assert.equals(8, eff.radius)
		assert.equals(30, eff.cooldown)
	end)

	it("recovers quality after healthy windows", function()
		local state
		state = Policy.update(nil, merged, status({ dropDelta = 5, avgThroughput15 = 10 })) -- degrade once
		state = Policy.update(state, merged, status({ dropDelta = 5, avgThroughput15 = 10 })) -- degrade twice
		state = Policy.update(state, merged, status({ mode = "normal", dropDelta = 0, avgFill = 0.1 }))
		local eff
		state, eff = Policy.update(state, merged, status({ mode = "normal", dropDelta = 0, avgFill = 0.1 }))
		assert.equals(2, state.qualityIndex) -- recovered one step
		assert.equals(20, eff.staleness)
	end)

	it("enters emergency steps after exhausting tolerable bands", function()
		local state
		local eff
		state = Policy.update(nil, merged, status({ dropDelta = 5, avgThroughput15 = 10 })) -- 2
		state = Policy.update(state, merged, status({ dropDelta = 5, avgThroughput15 = 10 })) -- 3
		state = Policy.update(state, merged, status({ dropDelta = 5, avgThroughput15 = 10 })) -- 4
		state = Policy.update(state, merged, status({ dropDelta = 5, avgThroughput15 = 10 })) -- 5
		state, eff = Policy.update(state, merged, status({ dropDelta = 5, avgThroughput15 = 10 })) -- 6 (first emergency)
		assert.is_true(state.qualityIndex >= 6)
		assert.is_true(eff.staleness >= 40) -- doubled once in emergency
		assert.is_true(eff.radius <= 2.5)
		assert.is_true(eff.cooldown >= 120)
	end)

	it("smooths ladder within bands (no binary jumps)", function()
		local mergedSmooth = {
			staleness = { desired = 1, tolerable = 10 },
			radius = { desired = 20, tolerable = 8 },
			cooldown = { desired = 1, tolerable = 2 },
		}
		local state, eff = Policy.update(nil, mergedSmooth, status({ mode = "normal", dropDelta = 0, avgFill = 0.1 }), {
			lagHoldTicks = 1,
			signals = { probeLagRatio = 2, probeLagOverdueMs = 1, probeLagEstimateMs = 2000 },
		})
		assert.equals(2, state.qualityIndex)
		assert.equals(2, eff.staleness) -- first degrade step is 2s (not 10s)
	end)

	it("does not recover to desired unless it can meet desired staleness", function()
		local mergedSmooth = {
			staleness = { desired = 1, tolerable = 10 },
			radius = { desired = 20, tolerable = 8 },
			cooldown = { desired = 1, tolerable = 2 },
		}
		local state = Policy.update(nil, mergedSmooth, status({ mode = "normal", dropDelta = 0, avgFill = 0.1 }), {
			lagHoldTicks = 1,
			recoverHoldWindows = 1,
			recoverHoldTicksAfterLag = 1,
			signals = { probeLagRatio = 2, probeLagOverdueMs = 1, probeLagEstimateMs = 2000 },
		})

		-- Healthy window but still can't meet desired (estimate >= desired): stay degraded.
		state = Policy.update(state, mergedSmooth, status({ mode = "normal", dropDelta = 0, avgFill = 0.1 }), {
			recoverHoldWindows = 1,
			recoverHoldTicksAfterLag = 1,
			signals = { probeLagRatio = 0.5, probeLagOverdueMs = 0, probeLagEstimateMs = 1000 },
		})
		assert.equals(2, state.qualityIndex)

		-- Once we can comfortably meet desired again, recover.
		state = Policy.update(state, mergedSmooth, status({ mode = "normal", dropDelta = 0, avgFill = 0.1 }), {
			recoverHoldWindows = 1,
			recoverHoldTicksAfterLag = 1,
			signals = { probeLagRatio = 0.5, probeLagOverdueMs = 0, probeLagEstimateMs = 800 },
		})
		assert.equals(1, state.qualityIndex)
	end)

	it("prefers budget headroom over degrading on lag", function()
		local mergedSmooth = {
			staleness = { desired = 1, tolerable = 10 },
			radius = { desired = 20, tolerable = 8 },
			cooldown = { desired = 1, tolerable = 2 },
		}
		local lagSignals = { probeLagRatio = 2, probeLagOverdueMs = 1, probeLagEstimateMs = 2000 }

		-- Under budget: do not degrade even if lag is detected (let probes ramp budget first).
		local state, eff = Policy.update(nil, mergedSmooth, status({ mode = "normal", dropDelta = 0, avgFill = 0.1, budgetMs = 4, tickLastMs = 1 }), {
			lagHoldTicks = 1,
			signals = lagSignals,
		})
		assert.equals(1, state.qualityIndex)
		assert.equals(1, eff.staleness)

		-- Near budget: lag is actionable, so degrade can kick in.
		state, eff = Policy.update(nil, mergedSmooth, status({ mode = "normal", dropDelta = 0, avgFill = 0.1, budgetMs = 4, tickLastMs = 3.5 }), {
			lagHoldTicks = 1,
			signals = lagSignals,
		})
		assert.equals(2, state.qualityIndex)
		assert.equals(2, eff.staleness)
	end)
end)
