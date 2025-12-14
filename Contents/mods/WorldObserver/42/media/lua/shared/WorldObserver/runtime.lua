-- runtime.lua -- runtime controller scaffold: clock resolution, status tracking, and transition metadata.
local Log = require("LQR/util/log").withTag("WO.RUNTIME")

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

local function resolveWallClock()
	-- Prefer a monotonic-ish wall clock if available.
	if _G.UIManager and type(_G.UIManager.getMillisSinceStart) == "function" then
		local ok, ms = pcall(_G.UIManager.getMillisSinceStart)
		if ok and type(ms) == "number" then
			return function()
				return _G.UIManager.getMillisSinceStart()
			end,
				"UIManager.getMillisSinceStart"
		end
	end
	if type(_G.getTimestampMs) == "function" then
		local ok, ms = pcall(_G.getTimestampMs)
		if ok and type(ms) == "number" then
			return function()
				return _G.getTimestampMs()
			end,
				"getTimestampMs"
		end
	end
	if type(os) == "table" and type(os.time) == "function" then
		return function()
			return os.time() * 1000
		end,
			"os.time()*1000"
	end
	return nil, "none"
end

local function resolveCpuClock()
	if type(os) == "table" and type(os.clock) == "function" then
		return function()
			return os.clock() * 1000
		end,
			"os.clock()*1000"
	end
	return nil, "none"
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
				windowTicks = opts.windowTicks or 60,
				reportEveryWindows = opts.reportEveryWindows or 10,
				degradedMaxItemsPerTick = opts.degradedMaxItemsPerTick,
			},
			window = {
				ticks = 0,
				spikes = 0,
				sumMs = 0,
				maxMs = 0,
			},
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
		local ok, val = pcall(self._wallClock)
		if ok and type(val) == "number" then
			return val
		end
		return nil
	end

	function self:nowCpu()
		if not self._cpuClock then
			return nil
		end
		local ok, val = pcall(self._cpuClock)
		if ok and type(val) == "number" then
			return val
		end
		return nil
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
		local cfg = self._controller and self._controller.cfg or {}
		if cfg.degradedMaxItemsPerTick then
			self._status.budgets.schedulerMaxItemsPerTick = cfg.degradedMaxItemsPerTick
		else
			self._status.budgets.schedulerMaxItemsPerTick = nil
		end
		-- Reset controller window so next tick starts fresh.
		self._controller.window = { ticks = 0, spikes = 0, sumMs = 0, maxMs = 0 }
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
		-- Ingest signals are optional; normalize to numbers for math below.
		local ingestPending = tonumber(opts.ingestPending) or 0
		local ingestDropped = tonumber(opts.ingestDropped) or 0

		local c = self._controller
		local cfg = c.cfg or {}
		local win = c.window or {}

		win.ticks = (win.ticks or 0) + 1
		win.sumMs = (win.sumMs or 0) + tickMs
		win.pendingSum = (win.pendingSum or 0) + ingestPending
		win.droppedSum = (win.droppedSum or 0) + ingestDropped
		if not win.maxMs or tickMs > win.maxMs then
			win.maxMs = tickMs
		end
		local spikeBudget = cfg.tickSpikeBudgetMs
		if spikeBudget and tickMs > spikeBudget then
			win.spikes = (win.spikes or 0) + 1
		end

		local windowSize = cfg.windowTicks or 60
		local completedWindow = win.ticks >= windowSize
		if not completedWindow then
			c.window = win
			return
		end

		local avgMs = win.sumMs / win.ticks
		local mode = self._status.mode or "normal"
		local reason = nil
		local budget = cfg.tickBudgetMs
		local prevStatus = self:status_get()
		local avgPending = (win.pendingSum or 0) / (win.ticks or 1)
		local dropDelta = win.droppedSum or 0

		if budget and avgMs > budget then
			mode = "degraded"
			reason = Reasons.woTickAvgOverBudget
		elseif spikeBudget and (win.spikes or 0) > 0 and (win.maxMs or 0) > spikeBudget then
			mode = "degraded"
			reason = Reasons.woTickSpikeOverBudget
		elseif dropDelta > 0 then
			mode = "degraded"
			reason = Reasons.ingestDropsRising
		elseif avgPending > 0 and c.prevAvgPending ~= nil and avgPending > c.prevAvgPending then
			mode = "degraded"
			reason = Reasons.ingestBacklogRising
		else
			-- Recovery path
			if prevStatus.mode ~= "normal" then
				mode = "normal"
				reason = Reasons.recovered
			end
		end

		if reason then
			-- Apply budget tweak before snapshotting the new status.
			if mode == "degraded" and cfg.degradedMaxItemsPerTick then
				self._status.budgets.schedulerMaxItemsPerTick = cfg.degradedMaxItemsPerTick
			else
				self._status.budgets.schedulerMaxItemsPerTick = nil
			end

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
					maxTickMs = win.maxMs,
					avgPending = avgPending,
					dropDelta = dropDelta,
					ticks = win.ticks,
					spikes = win.spikes,
				},
			}

			-- Emit LuaEvent on transition when available.
			if _G.triggerEvent then
				pcall(_G.triggerEvent, Runtime.Events.StatusChanged, payload)
			end
			Log:info(
				"Runtime status changed to %s (reason=%s) window avgMs=%.2f maxMs=%.2f avgPending=%.2f drops=%s",
				tostring(mode),
				tostring(reason),
				tonumber(avgMs) or 0,
				tonumber(win.maxMs) or 0,
				tonumber(avgPending) or 0,
				tostring(dropDelta)
			)
		end

		-- Expose the last completed window on status_get().
		self._status.window = self._status.window or {}
		self._status.window.avgTickMs = avgMs
		self._status.window.maxTickMs = win.maxMs
		self._status.window.ticks = win.ticks
		self._status.window.spikes = win.spikes
		self._status.window.budgetMs = cfg.tickBudgetMs
		self._status.window.spikeBudgetMs = cfg.tickSpikeBudgetMs

		-- Also publish the current window view into tick.* using the names from the design brief.
		self._status.tick = self._status.tick or {}
		self._status.tick.woAvgTickMs = avgMs
			self._status.tick.woMaxTickMs = win.maxMs
			self._status.tick.woWindowTicks = win.ticks
			self._status.tick.woWindowSpikes = win.spikes
			self._status.tick.woWindowAvgPending = avgPending
			self._status.tick.woWindowDropDelta = dropDelta

		-- Periodic report even without a transition. This surfaces window signals for dashboards
		-- and keeps mode transitions debuggable without polling status_get().
		c.windowCount = (c.windowCount or 0) + 1
		local shouldReport = (cfg.reportEveryWindows or 0) > 0 and (c.windowCount % cfg.reportEveryWindows == 0)
		if shouldReport then
			local winSnapshot = {
				avgTickMs = avgMs,
				maxTickMs = win.maxMs,
				ticks = win.ticks,
				spikes = win.spikes,
				budgetMs = cfg.tickBudgetMs,
				spikeBudgetMs = cfg.tickSpikeBudgetMs,
				avgPending = avgPending,
				dropDelta = dropDelta,
			}
			self:status_report(winSnapshot)
			Log:info(
				"Runtime status report window avgMs=%.2f maxMs=%.2f avgPending=%.2f drops=%s budgetMs=%s spikeBudgetMs=%s",
				tonumber(avgMs) or 0,
				tonumber(win.maxMs) or 0,
				tonumber(avgPending) or 0,
				tostring(dropDelta),
				tostring(cfg.tickBudgetMs),
				tostring(cfg.tickSpikeBudgetMs)
			)
		end

			-- Reset window for next round.
			c.prevAvgPending = avgPending
			c.window = { ticks = 0, spikes = 0, sumMs = 0, maxMs = 0, pendingSum = 0, droppedSum = 0 }
		end

		return self
	end

Runtime.Reasons = Reasons

return Runtime
