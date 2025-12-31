_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true


local Runtime = require("WorldObserver/runtime")

describe("WorldObserver runtime scaffold", function()
	it("resolves clocks with best-effort sources", function()
		local rt = Runtime.new()
		local clocks = rt:clocks()
		-- At least one clock should resolve; we don't assert exact source because host shapes vary.
		assert.is_true(clocks.wall == nil or type(clocks.wall) == "function")
		assert.is_true(clocks.cpu == nil or type(clocks.cpu) == "function")
	end)

	it("status_get returns a deep copy", function()
		local rt = Runtime.new()
		local snap = rt:status_get()
		snap.mode = "tamper"
		snap.budgets.foo = "bar"
		local snap2 = rt:status_get()
		assert.is_not.equal("tamper", snap2.mode)
		assert.is_nil(snap2.budgets.foo)
	end)

	it("status_transition updates mode, reason, since, and seq", function()
		local rt = Runtime.new()
		local before = rt:status_get()
		rt:status_transition("degraded", Runtime.Reasons.woTickAvgOverBudget)
		local after = rt:status_get()
		assert.is.equal("degraded", after.mode)
		assert.is.equal(Runtime.Reasons.woTickAvgOverBudget, after.lastTransitionReason)
		assert.is_true(after.seq > (before.seq or 0))
		assert.is_true(after.sinceMs >= before.sinceMs)
	end)

	it("status_transition defaults reason to manualOverride when missing", function()
		local rt = Runtime.new()
		rt:status_transition("overloaded")
		local snap = rt:status_get()
		assert.is.equal(Runtime.Reasons.manualOverride, snap.lastTransitionReason)
	end)

	it("recordTick updates last/avg/max", function()
		local rt = Runtime.new()
		rt:recordTick(10)
		rt:recordTick(20)
		local snap = rt:status_get()
		assert.is.truthy(snap.tick)
		assert.is.equal(20, snap.tick.lastMs)
		assert.is.equal(15, snap.tick.woTotalAvgTickMs)
		assert.is.equal(20, snap.tick.woTotalMaxTickMs)
	end)

	describe("controller_tick", function()
		local savedTrigger
		local calls

		before_each(function()
			calls = {}
			savedTrigger = _G.triggerEvent
			_G.triggerEvent = function(ev, payload)
				table.insert(calls, { ev = ev, payload = payload })
			end
		end)

		after_each(function()
			_G.triggerEvent = savedTrigger
		end)

			it("degrades when average tick exceeds budget and emits an event", function()
				local rt = Runtime.new({
					tickBudgetMs = 4,
					tickSpikeBudgetMs = 8,
					windowTicks = 5,
					baseDrainMaxItems = 10,
					drainAuto = { enabled = true, stepFactor = 1.5, minItems = 1, maxItems = 200, headroomUtil = 0.6 },
				})
				for _ = 1, 5 do
					rt:controller_tick({ tickMs = 5 })
				end
				local snap = rt:status_get()
				assert.equals("degraded", snap.mode)
				assert.equals(Runtime.Reasons.woTickAvgOverBudget, snap.lastTransitionReason)
				assert.equals(6, snap.budgets.schedulerMaxItemsPerTick)
				assert.is_true(#calls >= 1)
				assert.equals("WorldObserverRuntimeStatusChanged", calls[1].ev)
				assert.equals(Runtime.Reasons.woTickAvgOverBudget, calls[1].payload.reason)
				assert.is_table(calls[1].payload.from)
			assert.is_table(calls[1].payload.to)
			assert.equals("normal", calls[1].payload.from.mode)
			assert.equals("degraded", calls[1].payload.to.mode)
		end)

			it("does not degrade on a single spike", function()
				local rt = Runtime.new({
					tickBudgetMs = nil,
					tickSpikeBudgetMs = 8,
					spikeMinCount = 2,
					windowTicks = 4,
				})
				rt:controller_tick({ tickMs = 2 }) -- ok
				rt:controller_tick({ tickMs = 9 }) -- 1 spike
				rt:controller_tick({ tickMs = 2 }) -- ok
				rt:controller_tick({ tickMs = 2 }) -- window completes
				local snap = rt:status_get()
				assert.equals("normal", snap.mode)
			end)

				it("degrades on repeated spikes above spike budget", function()
					local rt = Runtime.new({
						tickBudgetMs = nil,
						tickSpikeBudgetMs = 8,
						spikeMinCount = 2,
						windowTicks = 4,
					})
					rt:controller_tick({ tickMs = 9 }) -- spike 1
					rt:controller_tick({ tickMs = 9 }) -- spike 2
					rt:controller_tick({ tickMs = 2 })
					rt:controller_tick({ tickMs = 2 })
					local snap = rt:status_get()
					assert.equals("degraded", snap.mode)
					assert.equals(Runtime.Reasons.woTickSpikeOverBudget, snap.lastTransitionReason)
				end)

				it("does not degrade on non-consecutive spikes", function()
					local rt = Runtime.new({
						tickBudgetMs = nil,
						tickSpikeBudgetMs = 8,
						spikeMinCount = 2,
						windowTicks = 4,
					})
					rt:controller_tick({ tickMs = 9 }) -- spike 1
					rt:controller_tick({ tickMs = 2 }) -- reset streak
					rt:controller_tick({ tickMs = 9 }) -- spike 1 (again)
					rt:controller_tick({ tickMs = 2 })
					local snap = rt:status_get()
					assert.equals("normal", snap.mode)
				end)

		it("degrades when ingest drops rise", function()
			local rt = Runtime.new({
				tickBudgetMs = 100, -- keep CPU budget out of the way
				windowTicks = 2,
			})
			rt:controller_tick({ tickMs = 1, ingestPending = 1, ingestDropped = 0 })
			rt:controller_tick({ tickMs = 1, ingestPending = 1, ingestDropped = 2 })
			local snap = rt:status_get()
			assert.equals("degraded", snap.mode)
			assert.equals(Runtime.Reasons.ingestDropsRising, snap.lastTransitionReason)
		end)

				it("boosts drainMaxItems under headroom when ingest backlog rises", function()
					local rt = Runtime.new({
						tickBudgetMs = 4,
						windowTicks = 2,
						reportEveryWindows = 0,
						baseDrainMaxItems = 10,
						drainAuto = { enabled = true, stepFactor = 1.5, minItems = 1, maxItems = 200, headroomUtil = 0.6 },
					})

				-- Backlog window: rising + non-empty, but tickMs stays well under budget (headroom).
				rt:controller_tick({
					tickMs = 1,
					ingestPending = 2000,
					ingestDropped = 0,
					ingestTrend = "rising",
					ingestFill = 0.40,
					ingestIngestRate15 = 100,
					ingestThroughput15 = 10,
				})
				rt:controller_tick({
					tickMs = 1,
					ingestPending = 2000,
					ingestDropped = 0,
					ingestTrend = "rising",
					ingestFill = 0.40,
					ingestIngestRate15 = 100,
					ingestThroughput15 = 10,
				})

				local snap = rt:status_get()
				assert.equals("normal", snap.mode)
				assert.equals(Runtime.Reasons.ingestBacklogRising, snap.window and snap.window.reason)
				assert.equals(15, snap.budgets.schedulerMaxItemsPerTick)
				-- No mode change => no status-changed event.
					assert.equals(0, #calls)
				end)

				it("decays drainMaxItems back toward baseline once backlog is gone", function()
					local rt = Runtime.new({
						tickBudgetMs = 4,
						windowTicks = 2,
						reportEveryWindows = 0,
						baseDrainMaxItems = 10,
						drainAuto = { enabled = true, stepFactor = 1.5, minItems = 1, maxItems = 200, headroomUtil = 0.6 },
					})

					-- Window 1: backlog pressure + headroom => step up.
					rt:controller_tick({
						tickMs = 1,
						ingestPending = 2000,
						ingestDropped = 0,
						ingestTrend = "rising",
						ingestFill = 0.40,
						ingestIngestRate15 = 100,
						ingestThroughput15 = 10,
					})
					rt:controller_tick({
						tickMs = 1,
						ingestPending = 2000,
						ingestDropped = 0,
						ingestTrend = "rising",
						ingestFill = 0.40,
						ingestIngestRate15 = 100,
						ingestThroughput15 = 10,
					})
					assert.equals(15, rt:status_get().budgets.schedulerMaxItemsPerTick)

					-- Window 2: no pressure + headroom => decay toward baseline.
					rt:controller_tick({ tickMs = 1, ingestPending = 0, ingestDropped = 0, ingestTrend = "steady", ingestFill = 0 })
					rt:controller_tick({ tickMs = 1, ingestPending = 0, ingestDropped = 0, ingestTrend = "steady", ingestFill = 0 })
					assert.equals(10, rt:status_get().budgets.schedulerMaxItemsPerTick)
				end)

				it("recovers after a clean window and clears degraded budgets", function()
					local rt = Runtime.new({
						tickBudgetMs = 4,
						windowTicks = 3,
					reportEveryWindows = 0,
					baseDrainMaxItems = 10,
					drainAuto = { enabled = true, stepFactor = 1.5, minItems = 1, maxItems = 200, headroomUtil = 0.6 },
				})
				for _ = 1, 3 do
					rt:controller_tick({ tickMs = 5 })
				end
				assert.equals("degraded", rt:status_get().mode)
				for _ = 1, 3 do
					rt:controller_tick({ tickMs = 2 })
				end
				local snap = rt:status_get()
				assert.equals("normal", snap.mode)
				assert.equals(Runtime.Reasons.recovered, snap.lastTransitionReason)
				-- Auto-tuner may still be below baseline immediately after recovering; it should remain positive.
				assert.is_true((snap.budgets.schedulerMaxItemsPerTick or 0) > 0)
				-- Another clean window should return to baseline when under headroom.
				for _ = 1, 3 do
					rt:controller_tick({ tickMs = 1 })
				end
				local snap2 = rt:status_get()
				assert.equals(10, snap2.budgets.schedulerMaxItemsPerTick)
			end)

		it("does not transition when under budget", function()
			local rt = Runtime.new({
				tickBudgetMs = 10,
				windowTicks = 4,
			})
			local before = rt:status_get()
			for _ = 1, 4 do
				rt:controller_tick({ tickMs = 3 })
			end
			local after = rt:status_get()
			assert.equals("normal", after.mode)
			assert.equals(before.seq, after.seq)
			assert.equals(0, #calls)
		end)

		it("emits periodic reports even without transitions", function()
			local rt = Runtime.new({
				tickBudgetMs = 10,
				windowTicks = 2,
				reportEveryWindows = 1,
			})
			rt:controller_tick({ tickMs = 3 })
			rt:controller_tick({ tickMs = 4 })
			assert.is_true(#calls >= 1)
			assert.equals(Runtime.Events.StatusReport, calls[#calls].ev)
			assert.is_table(calls[#calls].payload.status.window)
		end)
	end)

	describe("emergency_reset", function()
		local savedTrigger
		local calls

		before_each(function()
			calls = {}
			savedTrigger = _G.triggerEvent
			_G.triggerEvent = function(ev, payload)
				table.insert(calls, { ev = ev, payload = payload })
			end
		end)

		after_each(function()
			_G.triggerEvent = savedTrigger
		end)

		it("forces emergency mode, emits event, and runs reset hook", function()
			local ranReset = false
			local rt = Runtime.new()
			rt:emergency_reset({
				onReset = function()
					ranReset = true
				end,
			})
			local snap = rt:status_get()
			assert.equals("emergency", snap.mode)
			assert.equals(Runtime.Reasons.emergencyResetTriggered, snap.lastTransitionReason)
			assert.is_true(ranReset)
			assert.is_true(#calls >= 1)
			assert.equals(Runtime.Events.StatusChanged, calls[#calls].ev)
			assert.equals(Runtime.Reasons.emergencyResetTriggered, calls[#calls].payload.reason)
		end)
	end)
end)
