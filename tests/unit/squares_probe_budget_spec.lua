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

local Probe = require("WorldObserver/facts/squares/probe")

describe("squares probe budget", function()
	it("keeps fixed budget when demand is within desired", function()
		local runtimeStatus = {
			mode = "normal",
			window = { budgetMs = 4, avgTickMs = 1, reason = "steady" },
			tick = { lastMs = 1, woAvgTickMs = 1 },
		}
		local budgetMs, mode = Probe._internal.resolveProbeBudgetMs(0.75, runtimeStatus, 1.0, {})
		assert.equals("fixed", mode)
		assert.equals(0.75, budgetMs)
	end)

	it("reduces probe budget when runtime is degraded/emergency", function()
		local degraded = { mode = "degraded", window = { budgetMs = 4 } }
		local emergency = { mode = "emergency", window = { budgetMs = 4 } }
		local budgetMs, mode = Probe._internal.resolveProbeBudgetMs(1.0, degraded, 2.0, {})
		assert.equals("degraded", mode)
		assert.equals(0.5, budgetMs)
		budgetMs, mode = Probe._internal.resolveProbeBudgetMs(1.0, emergency, 2.0, {})
		assert.equals("emergency", mode)
		assert.equals(0.25, budgetMs)
	end)

	it("spends tick headroom up to dynamic cap when probes lag", function()
		local runtimeStatus = {
			mode = "normal",
			window = { budgetMs = 4, avgTickMs = 1, reason = "steady" },
			tick = {
				lastMs = 1,
				woAvgTickMs = 1,
				woWindowAvgDrainMs = 0.2,
				woWindowAvgOtherMs = 0.1,
			},
		}
		local probeCfg = { autoBudgetReserveMs = 0.5 }
		local budgetMs, mode = Probe._internal.resolveProbeBudgetMs(0.75, runtimeStatus, 2.0, probeCfg)
		assert.equals("auto", mode)
		-- dynamicCapMs = 4 - 0.5 - (0.2 + 0.1) = 3.2
		assert.equals(3.2, budgetMs)
	end)

	it("does not auto-raise probe budget when WO is over budget", function()
		local runtimeStatus = {
			mode = "normal",
			window = { budgetMs = 4, avgTickMs = 5, reason = "woTickAvgOverBudget" },
			tick = { lastMs = 5, woAvgTickMs = 5 },
		}
		local budgetMs, mode = Probe._internal.resolveProbeBudgetMs(0.75, runtimeStatus, 2.0, {})
		assert.equals("fixed", mode)
		assert.equals(0.75, budgetMs)
	end)

	it("scales maxSquaresPerTick with auto budget, capped by hard cap", function()
		local probeCfg = { maxPerRunHardCap = 200 }
		local maxSquares = Probe._internal.scaleMaxSquaresPerTick(50, 0.75, 3.15, "auto", probeCfg)
		assert.equals(200, maxSquares)
	end)

	it("probe lag estimate is stable early in a sweep", function()
		local cursor = {
			sweepStartedMs = 0,
			sweepProcessed = 1,
			totalSquaresPerSweep = 100,
		}
		local nowMs = 100
		local previousEffective = { staleness = 1 }
		local signals = Probe._internal.computeProbeLagSignals(cursor, nowMs, previousEffective)
		assert.is_table(signals)
		-- With minSamples=25, estimate ~= (100ms/25)*100 = 400ms, ratio ~ 0.4 (not 10x).
		assert.is_true((signals.probeLagRatio or 0) < 1)
	end)

	it("probe lag estimate falls back to last sweep duration when idle", function()
		local cursor = {
			sweepStartedMs = nil,
			lastSweepDurationMs = 1500,
		}
		local nowMs = 2000
		local previousEffective = { staleness = 1 }
		local signals = Probe._internal.computeProbeLagSignals(cursor, nowMs, previousEffective)
		assert.is_table(signals)
		assert.is_true((signals.probeLagRatio or 0) > 1)
		assert.equals(500, signals.probeLagOverdueMs)
	end)
end)
