local Log = require("DREAMBase/log").withTag("WO.RUNTIME")
local Time = require("WorldObserver/helpers/time")

local Runtime = {}
Runtime.Events = {
	StatusChanged = "WorldObserverRuntimeStatusChanged",
	StatusReport = "WorldObserverRuntimeStatusReport",
}

local function deepCopy(tbl)
	if type(tbl) ~= "table" then
		return tbl
	end
	local out = {}
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			out[k] = deepCopy(v)
		else
			out[k] = v
		end
	end
	return out
end

	local Reasons = {
		woTickAvgOverBudget = "woTickAvgOverBudget",
		woTickSpikeOverBudget = "woTickSpikeOverBudget",
		ingestBacklogRising = "ingestBacklogRising",
	ingestDropsRising = "ingestDropsRising",
	clockUnavailable = "clockUnavailable",
	clockNonMonotonic = "clockNonMonotonic",
	recovered = "recovered",
	manualOverride = "manualOverride",
		emergencyResetTriggered = "emergencyResetTriggered",
	}

	local function newControllerWindow()
		return {
			ticks = 0,
			spikes = 0,
			spikeStreak = 0,
			spikeStreakMax = 0,
			sumMs = 0,
			maxMs = 0,
			producerSum = 0,
			drainSum = 0,
			otherSum = 0,
			pendingSum = 0,
			droppedSum = 0,
			throughput15Sum = 0,
			ingestRate15Sum = 0,
			fillSum = 0,
			trendRising = false,
			trendFalling = false,
		}
	end

	local function resolveWallClock()
		return function()
			return Time.gameMillis()
		end, "getGameTime.getTimeInMillis"
end

local function resolveCpuClock()
	return function()
		return Time.cpuMillis()
	end, "os.clock()*1000"
end

--- @class WorldObserverRuntime
--- @field status_get fun(self:WorldObserverRuntime):table
--- @field status_transition fun(self:WorldObserverRuntime, mode:string, reason:string)
--- @field clocks fun(self:WorldObserverRuntime):table
--- @field nowCpu fun(self:WorldObserverRuntime):number|nil
--- @field nowWall fun(self:WorldObserverRuntime):number|nil
--- @field recordTick fun(self:WorldObserverRuntime, ms:number)
--- @field controller_get fun(self:WorldObserverRuntime):table
--- @field controller_tick fun(self:WorldObserverRuntime, opts:table)
--- @field status_report fun(self:WorldObserverRuntime, windowStats:table|nil):table
--- @field emergency_reset fun(self:WorldObserverRuntime, opts:table|nil)

--- Construct a runtime controller scaffold (no automatic hooks yet).
--- @return WorldObserverRuntime
function Runtime.new(opts)
	opts = opts or {}
	local wallClockFn, wallSource = resolveWallClock()
	local cpuClockFn, cpuSource = resolveCpuClock()

	if not wallClockFn then
		Log:warn("No wall-clock available for runtime controller (source=%s)", tostring(wallSource))
	end
	if not cpuClockFn then
		Log:warn("No CPU clock available for runtime controller (source=%s)", tostring(cpuSource))
	end

	local nowMs = wallClockFn and wallClockFn() or 0
	local self = {
		_status = {
			mode = "normal",
			sinceMs = nowMs,
			lastTransitionReason = "init",
			seq = 0,
			budgets = {},
			tick = {},
			ingest = {},
			window = {},
		},
		_wallClock = wallClockFn,
		_wallClockSource = wallSource,
		_cpuClock = cpuClockFn,
		_cpuClockSource = cpuSource,
		_tick = {
			count = 0,
			sumMs = 0,
			maxMs = 0,
			lastMs = nil,
		},
		_controller = {
			cfg = {
				tickBudgetMs = opts.tickBudgetMs,
				tickSpikeBudgetMs = opts.tickSpikeBudgetMs,
				spikeMinCount = opts.spikeMinCount,
				windowTicks = opts.windowTicks or 60,
				reportEveryWindows = opts.reportEveryWindows or 10,
				degradedMaxItemsPerTick = opts.degradedMaxItemsPerTick,
				baseDrainMaxItems = opts.baseDrainMaxItems,
				drainAuto = opts.drainAuto,
				-- Backlog heuristics (domain-provided; see docs_internal/drafts/runtime_controller.md).
				backlogMinPending = opts.backlogMinPending,
				backlogFillThreshold = opts.backlogFillThreshold,
				backlogMinIngestRate15 = opts.backlogMinIngestRate15,
				backlogRateRatio = opts.backlogRateRatio,
				},
				window = newControllerWindow(),
				-- Stateful drain budget chosen by the controller (items/tick).
				drainMaxItems = nil,
				seq = 0,
				reportSeq = 0,
			windowCount = 0,
		},
	}

	function self:status_get()
		return deepCopy(self._status)
	end

	function self:_status_snapshot(windowStats)
		local snap = self:status_get()
		if windowStats then
			snap.window = deepCopy(windowStats)
		end
		return snap
	end

	function self:status_transition(mode, reason)
		if type(mode) ~= "string" or mode == "" then
			return
		end
		local now = self._wallClock and self._wallClock() or self._status.sinceMs
		self._status.seq = (self._status.seq or 0) + 1
		self._status.mode = mode
		self._status.sinceMs = now
		self._status.lastTransitionReason = reason or Reasons.manualOverride
	end

	function self:nowWall()
		if not self._wallClock then
			return nil
		end
		return self._wallClock()
	end

	function self:nowCpu()
		if not self._cpuClock then
			return nil
		end
		return self._cpuClock()
	end

	function self:recordTick(ms)
		if type(ms) ~= "number" or ms < 0 then
			return
		end
		self._tick.count = (self._tick.count or 0) + 1
		self._tick.sumMs = (self._tick.sumMs or 0) + ms
		self._tick.lastMs = ms
		if not self._tick.maxMs or ms > self._tick.maxMs then
			self._tick.maxMs = ms
		end
		self._status.tick = self._status.tick or {}
		self._status.tick.lastMs = ms
		self._status.tick.woTotalAvgTickMs = self._tick.sumMs / self._tick.count
		self._status.tick.woTotalMaxTickMs = self._tick.maxMs
	end

	function self:clocks()
		return {
			wall = self._wallClock,
			wallSource = self._wallClockSource,
			cpu = self._cpuClock,
			cpuSource = self._cpuClockSource,
		}
	end

	function self:controller_get()
		return deepCopy(self._controller)
	end

	-- Emit a periodic status report without changing mode.
	function self:status_report(windowStats)
		self._controller.reportSeq = (self._controller.reportSeq or 0) + 1
		local payload = {
			event = Runtime.Events.StatusReport,
			seq = self._controller.reportSeq,
			nowMs = self:nowWall() or self._status.sinceMs,
			status = self:_status_snapshot(windowStats),
		}
		if _G.triggerEvent then
			pcall(_G.triggerEvent, Runtime.Events.StatusReport, payload)
		end
		return payload
	end

	-- Emergency reset hook: lets the host clear ingest buffers and advertise the state change.
	function self:emergency_reset(opts)
		opts = opts or {}
		local onReset = opts.onReset
		local prevStatus = self:status_get()
			if type(onReset) == "function" then
				pcall(onReset)
			end

			-- In emergency mode we keep the scheduler on a conservative item budget if available.
			local cfg = self._controller.cfg
			local fallback = cfg.degradedMaxItemsPerTick
			if type(fallback) ~= "number" or fallback <= 0 then
				local auto = cfg.drainAuto
				fallback = auto and auto.minItems
		end
		if type(fallback) == "number" and fallback > 0 then
			self._status.budgets.schedulerMaxItemsPerTick = math.floor(fallback)
		else
			self._status.budgets.schedulerMaxItemsPerTick = nil
		end

			-- Reset controller window so next tick starts fresh.
			self._controller.window = newControllerWindow()

			self:status_transition("emergency", Reasons.emergencyResetTriggered)
			self._controller.seq = (self._controller.seq or 0) + 1
			local snapshot = self:status_get()
			local payload = {
			event = Runtime.Events.StatusChanged,
			seq = self._controller.seq,
			nowMs = self:nowWall() or snapshot.sinceMs,
			reason = Reasons.emergencyResetTriggered,
			from = { mode = prevStatus.mode, sinceMs = prevStatus.sinceMs },
			to = { mode = snapshot.mode, sinceMs = snapshot.sinceMs },
			status = snapshot,
		}
		if _G.triggerEvent then
			pcall(_G.triggerEvent, Runtime.Events.StatusChanged, payload)
		end
	end

	-- Controller tick: update window aggregates and possibly change mode.
	function self:controller_tick(opts)
		opts = opts or {}
		local tickMs = opts.tickMs
		if type(tickMs) ~= "number" or tickMs < 0 then
			return
		end
		local producerMs = tonumber(opts.producerMs or opts.probeMs) or 0
		if producerMs < 0 then
			producerMs = 0
		end
		local drainMs = tonumber(opts.drainMs) or 0
		if drainMs < 0 then
			drainMs = 0
		end
		local otherMs = tickMs - producerMs - drainMs
		if otherMs < 0 then
			otherMs = 0
		end

		-- Ingest signals are optional; normalize to numbers for math below.
		local ingestPending = tonumber(opts.ingestPending) or 0
			local ingestDropped = tonumber(opts.ingestDropped) or 0

			local c = self._controller
			local cfg = c.cfg
			local win = c.window

			self._status.tick = self._status.tick or {}
			self._status.tick.producerLastMs = producerMs
			self._status.tick.drainLastMs = drainMs
		self._status.tick.otherLastMs = otherMs

		win.ticks = (win.ticks or 0) + 1
		win.sumMs = (win.sumMs or 0) + tickMs
		win.producerSum = (win.producerSum or 0) + producerMs
		win.drainSum = (win.drainSum or 0) + drainMs
		win.otherSum = (win.otherSum or 0) + otherMs
		win.pendingSum = (win.pendingSum or 0) + ingestPending
		win.droppedSum = (win.droppedSum or 0) + ingestDropped
		win.throughput15Sum = (win.throughput15Sum or 0) + (opts.ingestThroughput15 or 0)
		win.ingestRate15Sum = (win.ingestRate15Sum or 0) + (opts.ingestIngestRate15 or 0)
		win.fillSum = (win.fillSum or 0) + (opts.ingestFill or 0)
		win.trendRising = win.trendRising or (opts.ingestTrend == "rising")
		win.trendFalling = win.trendFalling or (opts.ingestTrend == "falling")
		if not win.maxMs or tickMs > win.maxMs then
			win.maxMs = tickMs
		end
		local spikeBudget = cfg.tickSpikeBudgetMs
		if spikeBudget and tickMs > spikeBudget then
			win.spikes = (win.spikes or 0) + 1
			win.spikeStreak = (win.spikeStreak or 0) + 1
		else
			win.spikeStreak = 0
		end
		if (win.spikeStreak or 0) > (win.spikeStreakMax or 0) then
			win.spikeStreakMax = win.spikeStreak
		end

			local windowSize = cfg.windowTicks
			local completedWindow = win.ticks >= windowSize
			if not completedWindow then
				c.window = win
				return
			end

		local avgMs = win.sumMs / win.ticks
		local avgProducerMs = (win.producerSum or 0) / win.ticks
		local avgDrainMs = (win.drainSum or 0) / win.ticks
		local avgOtherMs = (win.otherSum or 0) / win.ticks
		local mode = self._status.mode or "normal"
		local reason = nil
		local budget = cfg.tickBudgetMs
		local avgPending = (win.pendingSum or 0) / (win.ticks or 1)
		local dropDelta = win.droppedSum or 0
		local avgFill = (win.fillSum or 0) / (win.ticks or 1)
		local avgThroughput15 = (win.throughput15Sum or 0) / (win.ticks or 1)
		local avgIngestRate15 = (win.ingestRate15Sum or 0) / (win.ticks or 1)
		local trendRising = win.trendRising == true
		local backlogMinPending = cfg.backlogMinPending or 100
		local backlogFillThreshold = cfg.backlogFillThreshold or 0.25
		local backlogMinIngestRate15 = cfg.backlogMinIngestRate15 or 5
		local backlogRateRatio = cfg.backlogRateRatio or 1.1
		local backlogRateMinFill = 0.02 -- avoid "rate-only" flapping when buffers are basically empty
		local spikeMinCount = cfg.spikeMinCount or 2
		local spikeStreakMax = win.spikeStreakMax or 0

		local drainCfg = cfg.drainAuto
		local drainAutoEnabled = drainCfg and drainCfg.enabled ~= false
		local drainStepFactor = (drainCfg and tonumber(drainCfg.stepFactor)) or 1.5
		if drainStepFactor < 1.1 then
			drainStepFactor = 1.1
		end
		local drainMinItems = (drainCfg and tonumber(drainCfg.minItems)) or 1
		if drainMinItems < 1 then
			drainMinItems = 1
		end
		local drainMaxItemsCap = (drainCfg and tonumber(drainCfg.maxItems)) or 200
		if drainMaxItemsCap < drainMinItems then
			drainMaxItemsCap = drainMinItems
		end
		local headroomUtil = (drainCfg and tonumber(drainCfg.headroomUtil)) or 0.6
		if headroomUtil <= 0 or headroomUtil > 1 then
			headroomUtil = 0.6
		end
		local baseDrainMaxItems = tonumber(cfg.baseDrainMaxItems)
		if type(baseDrainMaxItems) ~= "number" or baseDrainMaxItems <= 0 then
			baseDrainMaxItems = nil
		end

		-- Publish the completed window signals into status *before* emitting any events.
		-- Why: transition/report payloads should be self-contained and reflect the same window that triggered them.
		self._status.window = self._status.window or {}
		self._status.window.avgTickMs = avgMs
		self._status.window.avgProducerMs = avgProducerMs
		self._status.window.avgDrainMs = avgDrainMs
		self._status.window.avgOtherMs = avgOtherMs
		-- tickSpikeMs is the per-window maximum; maxTickMs is kept as a compatibility alias.
		self._status.window.tickSpikeMs = win.maxMs
		self._status.window.maxTickMs = win.maxMs
		self._status.window.ticks = win.ticks
		self._status.window.spikes = win.spikes
		self._status.window.spikeStreakMax = spikeStreakMax
		self._status.window.budgetMs = cfg.tickBudgetMs
		self._status.window.spikeBudgetMs = cfg.tickSpikeBudgetMs
		self._status.window.avgPending = avgPending
		self._status.window.dropDelta = dropDelta
		self._status.window.avgFill = avgFill
		self._status.window.avgThroughput15 = avgThroughput15
		self._status.window.avgIngestRate15 = avgIngestRate15

		self._status.tick = self._status.tick or {}
		self._status.tick.woAvgTickMs = avgMs
		self._status.tick.woWindowAvgProducerMs = avgProducerMs
		self._status.tick.woWindowAvgDrainMs = avgDrainMs
		self._status.tick.woWindowAvgOtherMs = avgOtherMs
		-- woTickSpikeMs is the per-window maximum; woMaxTickMs is kept as a compatibility alias.
		self._status.tick.woTickSpikeMs = win.maxMs
		self._status.tick.woMaxTickMs = win.maxMs
		self._status.tick.woWindowTicks = win.ticks
		self._status.tick.woWindowSpikes = win.spikes
		self._status.tick.woWindowSpikeStreakMax = spikeStreakMax
		self._status.tick.woWindowAvgPending = avgPending
		self._status.tick.woWindowDropDelta = dropDelta
		self._status.tick.woWindowAvgFill = avgFill
		self._status.tick.woWindowThroughput15 = avgThroughput15
		self._status.tick.woWindowIngestRate15 = avgIngestRate15

		local prevStatus = self:status_get()

		local backlogHigh = trendRising and avgPending > 0 and (
			(avgFill and avgFill >= backlogFillThreshold) or
			(avgPending >= backlogMinPending) or
			(
				(avgFill and avgFill >= backlogRateMinFill) and
				avgIngestRate15 >= backlogMinIngestRate15 and
				avgThroughput15 > 0 and
				avgIngestRate15 > avgThroughput15 * backlogRateRatio
			)
		)

		-- Pick a "current window reason" for diagnostics, without forcing a mode transition.
		local windowReason = nil
		if budget and budget > 0 and avgMs > budget then
			windowReason = Reasons.woTickAvgOverBudget
		elseif spikeBudget and spikeStreakMax >= spikeMinCount and (win.maxMs or 0) > spikeBudget then
			windowReason = Reasons.woTickSpikeOverBudget
		elseif dropDelta > 0 then
			windowReason = Reasons.ingestDropsRising
		elseif backlogHigh then
			windowReason = Reasons.ingestBacklogRising
		end
		self._status.window.reason = windowReason

		-- Dynamic drain budget ("gas pedal"): adapt items/tick to burn backlog when we have headroom,
		-- and back off when we approach/exceed the ms budget.
		if drainAutoEnabled and baseDrainMaxItems then
			if type(c.drainMaxItems) ~= "number" or c.drainMaxItems <= 0 then
				c.drainMaxItems = baseDrainMaxItems
			end
			local util = nil
			if budget and budget > 0 then
				util = avgMs / budget
			end
			local underHeadroom = util ~= nil and util <= headroomUtil
			local underPressure = (dropDelta > 0 or backlogHigh) == true

			if budget and budget > 0 and avgMs > budget then
				c.drainMaxItems = math.max(drainMinItems, math.floor(c.drainMaxItems / drainStepFactor))
			elseif spikeBudget and spikeStreakMax >= spikeMinCount and (win.maxMs or 0) > spikeBudget then
				c.drainMaxItems = math.max(drainMinItems, math.floor(c.drainMaxItems / drainStepFactor))
			elseif underPressure and underHeadroom then
				c.drainMaxItems = math.min(drainMaxItemsCap, math.ceil(c.drainMaxItems * drainStepFactor))
			elseif (not underPressure) and underHeadroom and c.drainMaxItems > baseDrainMaxItems then
				-- Once the backlog is gone, decay back toward baseline to reduce hitch risk if per-item cost spikes later.
				c.drainMaxItems = math.max(baseDrainMaxItems, math.floor(c.drainMaxItems / drainStepFactor))
			elseif underHeadroom and c.drainMaxItems < baseDrainMaxItems then
				-- After backing off due to spikes/budget pressure, slowly return toward baseline when we have headroom.
				c.drainMaxItems = math.min(baseDrainMaxItems, math.ceil(c.drainMaxItems * drainStepFactor))
			end
			self._status.budgets.schedulerMaxItemsPerTick = math.floor(c.drainMaxItems)
		elseif baseDrainMaxItems then
			-- No auto tuner: still publish baseline so FactRegistry can apply it consistently.
			self._status.budgets.schedulerMaxItemsPerTick = math.floor(baseDrainMaxItems)
		end

		-- Mode transitions: only enter degraded on sustained spikes/avg over budget, or on drops rising.
		local wantedMode = prevStatus.mode
		if prevStatus.mode == "emergency" then
			wantedMode = "emergency"
		elseif budget and budget > 0 and avgMs > budget then
			wantedMode = "degraded"
			reason = Reasons.woTickAvgOverBudget
		elseif spikeBudget and spikeStreakMax >= spikeMinCount and (win.maxMs or 0) > spikeBudget then
			wantedMode = "degraded"
			reason = Reasons.woTickSpikeOverBudget
		elseif dropDelta > 0 then
			wantedMode = "degraded"
			reason = Reasons.ingestDropsRising
		else
			wantedMode = "normal"
			if prevStatus.mode ~= "normal" then
				reason = Reasons.recovered
			end
		end
		mode = wantedMode

		local modeChanged = mode ~= prevStatus.mode
		if modeChanged and reason then
			self:status_transition(mode, reason)
			c.seq = (c.seq or 0) + 1

			local toStatus = self:status_get()
			local payload = {
				event = Runtime.Events.StatusChanged,
				seq = c.seq,
				nowMs = self:nowWall() or prevStatus.sinceMs,
				reason = reason,
				from = { mode = prevStatus.mode, sinceMs = prevStatus.sinceMs },
				to = { mode = toStatus.mode, sinceMs = toStatus.sinceMs },
				status = toStatus,
				window = {
					avgTickMs = avgMs,
					tickSpikeMs = win.maxMs,
					avgPending = avgPending,
					dropDelta = dropDelta,
					ticks = win.ticks,
					spikes = win.spikes,
					spikeStreakMax = spikeStreakMax,
				},
			}

			-- Emit LuaEvent on transition when available.
			if _G.triggerEvent then
				pcall(_G.triggerEvent, Runtime.Events.StatusChanged, payload)
			end
		end

			-- Periodic report even without a transition. This surfaces window signals for dashboards
			-- and keeps mode transitions debuggable without polling status_get().
			c.windowCount = (c.windowCount or 0) + 1
			local shouldReport = cfg.reportEveryWindows > 0 and (c.windowCount % cfg.reportEveryWindows == 0)
			if shouldReport then
				local winSnapshot = {
					avgTickMs = avgMs,
					tickSpikeMs = win.maxMs,
				ticks = win.ticks,
				spikes = win.spikes,
				spikeStreakMax = spikeStreakMax,
				budgetMs = cfg.tickBudgetMs,
				spikeBudgetMs = cfg.tickSpikeBudgetMs,
				avgPending = avgPending,
				dropDelta = dropDelta,
				avgFill = avgFill,
				throughput15 = avgThroughput15,
				ingestRate15 = avgIngestRate15,
			}
			self:status_report(winSnapshot)
		end

			-- Reset window for next round.
			c.prevAvgPending = avgPending
			c.window = newControllerWindow()
		end

		return self
	end

Runtime.Reasons = Reasons

return Runtime
