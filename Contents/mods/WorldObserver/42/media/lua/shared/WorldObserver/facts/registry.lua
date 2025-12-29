-- facts/registry.lua -- manages fact sources: creates a stream per fact type and only starts its producer on first access.
local rx = require("reactivex")
local Ingest = require("LQR/ingest")
local Log = require("LQR/util/log").withTag("WO.FACTS")
local IngestLog = require("LQR/util/log").withTag("WO.INGEST")
local SourceHelpers = require("WorldObserver/helpers/source")
local Time = require("WorldObserver/helpers/time")

local FactRegistry = {}
FactRegistry.__index = FactRegistry -- registry instances resolve methods from this table via metatable lookup

local function nowMillis()
	return Time.gameMillis()
end

local function resolveRecordSourceTime(runtime, record)
	if type(record) ~= "table" then
		return nil
	end
	if type(record.sourceTime) == "number" then
		return record.sourceTime
	end
	local meta = record.RxMeta
	if type(meta) == "table" and type(meta.sourceTime) == "number" then
		return meta.sourceTime
	end
	if runtime and type(runtime.nowWall) == "function" then
		local ts = runtime:nowWall()
		if type(ts) == "number" then
			return ts
		end
	end
	local ts = nowMillis()
	if type(ts) == "number" then
		return ts
	end
	return nil
end

local function stampRecordSourceTime(runtime, record)
	if type(record) ~= "table" then
		return record
	end
	if type(record.sourceTime) ~= "number" then
		local ts = resolveRecordSourceTime(runtime, record)
		if type(ts) == "number" then
			record.sourceTime = ts
		end
	end
	return record
end

local function defaultContext(self, entry)
	-- Lazy start hooks get a tiny context; ingest defaults to direct emit when ingest is disabled.
	local function emitRecord(record)
		if record ~= nil then
			stampRecordSourceTime(self._runtime, record)
			entry.rxSubject:onNext(record)
		end
	end
	return {
		config = entry.config or {},
		state = entry.state,
		runtime = self._runtime,
		emit = emitRecord,
		ingest = emitRecord,
	}
end

local function resolveFactsConfig(cfg)
	if type(cfg) == "table" and type(cfg.facts) == "table" then
		return cfg.facts
	end
	if type(cfg) == "table" then
		return cfg
	end
	return {}
end

local function resolveIngestConfig(cfg)
	if type(cfg) == "table" and type(cfg.ingest) == "table" then
		return cfg.ingest
	end
	return {}
end

local function resolveControllerCfg(cfg)
	if type(cfg) == "table" and type(cfg.runtime) == "table" and type(cfg.runtime.controller) == "table" then
		return cfg.runtime.controller
	end
	return {}
end

function FactRegistry.new(config, runtime, hooks)
	-- Registry uses a metatable for method lookup; e.g. self:register(...) resolves to FactRegistry.register.
	-- The payload is a plain table with config/state.
	local factsConfig = resolveFactsConfig(config)
	local ingestConfig = resolveIngestConfig(config)
	local controllerCfg = resolveControllerCfg(config)
	hooks = hooks or {}
	local self = setmetatable({
		_factsConfig = factsConfig,
		_ingestConfig = ingestConfig,
		_runtime = runtime,
		_controllerCfg = controllerCfg,
		_hooks = hooks,
		_globalSubscribers = 0,
		_types = {},
		_scheduler = nil,
		onTickHookAttached = false,
		_tickHooks = {},
		_ingestDiag = {
			ticks = 0,
			reportEveryTicks = 300, -- ~5s at 60fps; intentionally coarse to avoid spam.
			windowTicks = 0,
			windowDrainCalls = 0,
			windowProcessed = 0,
			windowDrainMs = 0,
			windowEmitMs = 0,
			windowMaxDrainMs = 0,
			windowWarnedBudgetTick = 0,
		},
	}, FactRegistry)
	return self
end

--- Register a callback to run on every WorldObserver OnTick (inside the registry OnTick hook's timing window).
--- Why: lets upstream producers (e.g. probes) time-slice their work while still contributing to the same runtime budgets.
--- @param id string
--- @param fn function
function FactRegistry:attachTickHook(id, fn)
	assert(type(id) == "string" and id ~= "", "tick hook id must be a non-empty string")
	assert(type(fn) == "function", "tick hook fn must be a function")
	self._tickHooks = self._tickHooks or {}
	self._tickHooks[id] = fn
end

--- Remove a previously registered tick hook.
--- @param id string
function FactRegistry:detachTickHook(id)
	if type(id) ~= "string" or id == "" then
		return
	end
	local hooks = self._tickHooks
	if hooks then
		hooks[id] = nil
	end
end

---Registers a fact type with an optional start hook.
---@param name string
---@param opts table
function FactRegistry:register(name, opts)
	assert(type(name) == "string" and name ~= "", "Fact name must be a non-empty string")
	if self._types[name] then
		error(("Fact type '%s' already registered"):format(name))
	end

	if opts and opts.start ~= nil then
		assert(type(opts.start) == "function", "Fact registry expects start to be a function when provided")
	end
	if opts and opts.stop ~= nil then
		assert(type(opts.stop) == "function", "Fact registry expects stop to be a function when provided")
	end

	self._types[name] = {
		start = opts and opts.start,
		stop = opts and opts.stop,
		ingestOpts = opts and opts.ingest,
		config = (self._factsConfig and self._factsConfig[name]) or {},
		rxSubject = nil,
		observable = nil,
		started = false,
		subscribers = 0,
		buffer = nil,
		bufferAttached = false,
		state = {},
	}
end

function FactRegistry:hasType(name)
	return self._types[name] ~= nil
end

function FactRegistry:listFactTypes()
	local out = {}
	for name in pairs(self._types) do
		out[#out + 1] = name
	end
	table.sort(out)
	return out
end

local function ensureEntry(self, name, ensureSubject)
	local entry = self._types[name]
	if not entry then
		error(("Unknown fact type '%s'"):format(tostring(name)))
	end
	if ensureSubject and entry.rxSubject == nil then
		entry.rxSubject = rx.Subject.create()
		entry.observable = entry.rxSubject
	end
	return entry
end

local function defaultLane(item)
	if item and item.payload and item.payload.source then
		return item.payload.source
	end
	return "default"
end

local function isHeadless()
	return _G.WORLDOBSERVER_HEADLESS == true
end

	local function buildBuffer(self, name, entry)
		local cfg = entry.config and entry.config.ingest
		if not cfg or cfg.enabled ~= true then
			return nil
		end
		local ingestOpts = entry.ingestOpts
		if type(ingestOpts) ~= "table" then
			if not isHeadless() then
				Log:warn("Ingest enabled for fact type '%s' but no ingest opts provided; falling back to direct emit", tostring(name))
			end
			return nil
		end
		if type(ingestOpts.key) ~= "function" then
			local msg = ("Ingest enabled for fact type '%s' but ingest.key is missing/invalid; falling back to direct emit"):format(tostring(name))
			if isHeadless() then
				error(msg)
			end
			Log:warn("%s", msg)
			return nil
		end

	local laneFn = ingestOpts.lane or defaultLane
	local lanePriorityFn = ingestOpts.lanePriority or function(laneName)
		if cfg.lanePriority then
			return cfg.lanePriority(laneName)
		end
		return 1
	end

	local function keyAdapter(item)
		return ingestOpts.key(item.payload or item)
	end

	local function laneAdapter(item)
		return laneFn(item.payload or item)
	end

	local buffer = Ingest.buffer({
		name = "facts." .. name,
		mode = cfg.mode or ingestOpts.mode or "latestByKey",
		capacity = cfg.capacity or ingestOpts.capacity or 1000,
		ordering = cfg.ordering or ingestOpts.ordering or "none",
		key = keyAdapter,
		lane = laneAdapter,
		lanePriority = lanePriorityFn,
	})
	return buffer
end

local function ensureScheduler(self)
	if self._scheduler then
		return self._scheduler
	end
	local schedCfg = (self._ingestConfig and self._ingestConfig.scheduler) or {}
	local maxItemsPerTick = schedCfg.maxItemsPerTick or 0
	if type(maxItemsPerTick) ~= "number" then
		Log:warn("Ingest scheduler maxItemsPerTick is not a number; defaulting to 0")
		maxItemsPerTick = 0
	end
	local maxMillisPerTick = schedCfg.maxMillisPerTick
	if maxMillisPerTick ~= nil and (type(maxMillisPerTick) ~= "number" or maxMillisPerTick <= 0) then
		maxMillisPerTick = nil
	end
	if maxItemsPerTick <= 0 and not isHeadless() then
		Log:warn("Ingest scheduler maxItemsPerTick=%s; draining is disabled", tostring(maxItemsPerTick))
	end
	self._schedulerConfiguredMaxItems = maxItemsPerTick
	self._schedulerConfiguredMaxMillis = maxMillisPerTick
	self._scheduler = Ingest.scheduler({
		name = "WorldObserver.factScheduler",
		maxItemsPerTick = maxItemsPerTick,
		quantum = schedCfg.quantum or 1,
		maxMillisPerTick = maxMillisPerTick,
	})
	return self._scheduler
end

local function attachOnTickHookOnce(self)
	if self.onTickHookAttached then
		return
	end
	local events = _G.Events
	if not events or not events.OnTick or type(events.OnTick.Add) ~= "function" then
		if not isHeadless() then
			Log:warn("FactRegistry OnTick hook not attached (Events unavailable)")
		end
		return
	end

	local function runTickHooksOnce()
		local hooks = self._tickHooks
		if not hooks then
			return
		end
		for id, fn in pairs(hooks) do
			local ok, err = pcall(fn)
			if not ok and not isHeadless() then
				Log:warn("Tick hook '%s' failed - %s", tostring(id), tostring(err))
			end
		end
	end

	events.OnTick.Add(function()
		local runtime = self._runtime
		local tickStart = nil
		local useCpuClock = false

		if runtime and runtime.nowCpu then
			tickStart = runtime:nowCpu()
			useCpuClock = type(tickStart) == "number"
		end
		if type(tickStart) ~= "number" and runtime and runtime.nowWall then
			tickStart = runtime:nowWall()
		end

		local tickHooksMs = 0
		local drainMs = 0

		local tickHooksStart = tickStart
		runTickHooksOnce()
		if runtime and type(tickHooksStart) == "number" then
			local tickHooksEnd = useCpuClock and runtime:nowCpu() or runtime:nowWall()
			if type(tickHooksEnd) == "number" and tickHooksEnd >= tickHooksStart then
				tickHooksMs = tickHooksEnd - tickHooksStart
			end
		end

		if self._scheduler then
			local drainStart = runtime and (useCpuClock and runtime:nowCpu() or runtime:nowWall()) or nil
			self:drainSchedulerOnce()
			if runtime and type(drainStart) == "number" then
				local drainEnd = useCpuClock and runtime:nowCpu() or runtime:nowWall()
				if type(drainEnd) == "number" and drainEnd >= drainStart then
					drainMs = drainEnd - drainStart
				end
			end
		end

		if runtime and type(tickStart) == "number" then
			local tickEnd = useCpuClock and runtime:nowCpu() or runtime:nowWall()
			if type(tickEnd) == "number" and tickEnd >= tickStart then
				-- Count all work the registry performs on OnTick (drain + emit) as part of WO tick cost.
				local tickMs = tickEnd - tickStart
				runtime:recordTick(tickMs)
				-- Feed the controller every tick; it will aggregate into windows.
				runtime:controller_tick({
					tickMs = tickMs,
					producerMs = tickHooksMs,
					drainMs = drainMs,
					ingestPending = self._controllerIngestPending or 0,
					ingestDropped = self._controllerIngestDroppedDelta or 0,
					ingestTrend = self._controllerTrend,
					ingestFill = self._controllerFillRatio,
					ingestThroughput15 = self._controllerThroughput15,
					ingestIngestRate15 = self._controllerIngestRate15,
				})
			end
		end
	end)
	self.onTickHookAttached = true
end

	function FactRegistry:onSubscribe(name)
		local entry = ensureEntry(self, name, true)

		if not entry.started and type(entry.start) == "function" then
			local ctx = defaultContext(self, entry)
			-- Enable ingest when configured for this type.
			local ingestCfg = entry.config and entry.config.ingest
			if ingestCfg and ingestCfg.enabled == true then
				entry.buffer = entry.buffer or buildBuffer(self, name, entry)
				if entry.buffer then
					local scheduler = ensureScheduler(self)
					attachOnTickHookOnce(self)
					if scheduler and not entry.bufferAttached then
					local priority = (entry.config.ingest and entry.config.ingest.priority) or 1
					scheduler:addBuffer(entry.buffer, { priority = priority })
					entry.bufferAttached = true
				end
				local emitFn = function(record)
					entry.rxSubject:onNext(record)
				end
				ctx.ingest = function(record)
					if record ~= nil then
						stampRecordSourceTime(self._runtime, record)
						entry.buffer:ingest({
							payload = record,
							__emit = emitFn,
						})
					end
				end
				end
			end

			local ok, err = pcall(entry.start, ctx)
			if not ok then
				Log:error("Failed to start fact type '%s' - %s", tostring(name), tostring(err))
				if isHeadless() then
					error(("Failed to start fact type '%s': %s"):format(tostring(name), tostring(err)))
				end
			else
				entry.started = true
			end

		-- Producers may register per-tick work (e.g. time-sliced probes). Ensure we have an OnTick hook
		-- even when ingest is disabled (no scheduler/buffer), otherwise tick hooks would never run.
		local hasTickHooks = false
		local hooksTable = self._tickHooks
		if hooksTable then
			for _ in pairs(hooksTable) do
				hasTickHooks = true
				break
			end
		end
		if hasTickHooks then
			attachOnTickHookOnce(self)
		end
	end

	entry.subscribers = (entry.subscribers or 0) + 1
	local prevGlobal = self._globalSubscribers or 0
	self._globalSubscribers = prevGlobal + 1
	if prevGlobal == 0 and self._globalSubscribers == 1 then
		local onFirst = self._hooks and self._hooks.onFirstSubscriber
		if type(onFirst) == "function" then
			pcall(onFirst)
		end
	end

	local unsubscribed = false

	return function()
		if unsubscribed then
			return
		end
		unsubscribed = true

		local tracked = ensureEntry(self, name, false)
		tracked.subscribers = math.max(0, (tracked.subscribers or 1) - 1)
		if tracked.subscribers == 0 and tracked.started and type(tracked.stop) == "function" then
			local okStop, stopResultOrError = pcall(tracked.stop, tracked)
			if not okStop then
				Log:warn("Failed to stop fact type '%s' - %s", tostring(name), tostring(stopResultOrError))
			else
				-- stop() may return false to indicate it could not fully stop (e.g. no remove semantics),
				-- in which case we keep the type "started" to avoid double-registering handlers.
				if stopResultOrError ~= false then
					tracked.started = false
				end
			end
		end

		self._globalSubscribers = math.max(0, (self._globalSubscribers or 1) - 1)
		if self._globalSubscribers == 0 then
			local onLast = self._hooks and self._hooks.onLastSubscriber
			if type(onLast) == "function" then
				pcall(onLast)
			end
		end
	end
end

---Returns the observable for a fact type, starting it if needed.
function FactRegistry:getObservable(name)
	local entry = ensureEntry(self, name, true)
	return entry.observable
end

---Pushes a record into a fact stream (mostly for internal/tests).
---@param name string
---@param record table
function FactRegistry:emit(name, record)
	local entry = ensureEntry(self, name, true)
	entry.rxSubject:onNext(record)
end

function FactRegistry:drainSchedulerOnce()
	if not self._scheduler then
		return
	end

	-- Apply runtime-derived budgets if present.
	local status = self._runtime and self._runtime.status_get and self._runtime:status_get() or nil
	local budgetOverride = status and status.budgets and status.budgets.schedulerMaxItemsPerTick
	if type(budgetOverride) == "number" and budgetOverride > 0 then
		self._scheduler.maxItemsPerTick = budgetOverride
	else
		self._scheduler.maxItemsPerTick = self._schedulerConfiguredMaxItems or self._scheduler.maxItemsPerTick
	end
	self._scheduler.maxMillisPerTick = self._schedulerConfiguredMaxMillis

	local diag = self._ingestDiag
	if diag then
		diag.ticks = (diag.ticks or 0) + 1
		diag.windowTicks = (diag.windowTicks or 0) + 1
	end

	local budget = self._scheduler.maxItemsPerTick or 0
	if type(budget) ~= "number" then
		budget = 0
	end
	local budgetMs = self._scheduler.maxMillisPerTick or 0
	if type(budgetMs) ~= "number" then
		budgetMs = 0
	end
	if budget <= 0 and budgetMs <= 0 then
		-- Avoid spamming: warn at most once per report window.
		if diag and diag.windowWarnedBudgetTick ~= diag.ticks and not isHeadless() then
			diag.windowWarnedBudgetTick = diag.ticks
			IngestLog:warn(
				"Scheduler budgets are <= 0; skipping drain (maxItemsPerTick=%s, maxMillisPerTick=%s)",
				tostring(self._scheduler.maxItemsPerTick),
				tostring(self._scheduler.maxMillisPerTick)
			)
		end
		return
	end

	-- Choose a single timing source for this drain call (avoid mixing clocks via per-call fallbacks).
	local nowFn = nil
	local startMs = nil
	if self._runtime and self._runtime.nowWall then
		local t0 = self._runtime:nowWall()
		if type(t0) == "number" then
			startMs = t0
			nowFn = function()
				return self._runtime:nowWall()
			end
		end
	end
	if not nowFn then
		local t0 = nowMillis()
		if type(t0) == "number" then
			startMs = t0
			nowFn = nowMillis
		end
	end
	local emitMs = 0
	local emitTimed = nowFn ~= nil and type(startMs) == "number"
	local processed = 0

	local function handle(item)
		if item then
			local t0 = emitTimed and nowFn() or nil
			local emitFn = item.__emit
			local record = item.payload or item
			if type(record) == "table" and (record.hasCorpse == true or record.hasBloodSplat == true or record.hasTrashItems == true) then
				local qualifiedSource = SourceHelpers.record and SourceHelpers.record.qualifiedSource and SourceHelpers.record.qualifiedSource(record) or nil
				IngestLog:debug(
					"Draining record squareId=%s source=%s corpse=%s blood=%s trash=%s sourceTime=%s",
					tostring(record.squareId),
					tostring(qualifiedSource or record.source),
					tostring(record.hasCorpse),
					tostring(record.hasBloodSplat),
					tostring(record.hasTrashItems),
					tostring(record.sourceTime)
				)
			end
			if emitFn then
				emitFn(record)
			end
			processed = processed + 1
			if emitTimed then
				local t1 = nowFn()
				if type(t0) == "number" and type(t1) == "number" and t1 >= t0 then
					emitMs = emitMs + (t1 - t0)
				else
					emitTimed = false
				end
			end
		end
	end

	-- Pass nowMillis through so ingest buffers can compute load/throughput metrics in PZ (os.clock may be missing).
	local function wallNow()
		if self._runtime and self._runtime.nowWall then
			return self._runtime:nowWall()
		end
		return nowMillis()
	end

	local stats = self._scheduler:drainTick(handle, {
		nowMillis = wallNow,
		maxMillisPerTick = (budgetMs > 0) and budgetMs or nil,
	}) or {}

	-- Capture ingest pressure snapshots for the runtime controller:
	-- - pending: instantaneous backlog after this drain
	-- - droppedDelta: new drops since the last tick (buffer overflow / explicit drops)
	-- This is intentionally O(#buffers) (small) and uses buffer:metrics_getLight() internally (O(1)).
	if self._scheduler and self._scheduler.metrics_get then
		local schedSnap = self._scheduler:metrics_get()
		local droppedTotal = schedSnap and schedSnap.droppedTotal or 0
		local prevDroppedTotal = self._controllerLastDroppedTotal or 0
		local droppedDelta = droppedTotal - prevDroppedTotal
		if droppedDelta < 0 then
			droppedDelta = 0
		end
		self._controllerLastDroppedTotal = droppedTotal
		self._controllerIngestPending = schedSnap and schedSnap.pending or 0
		self._controllerIngestDroppedDelta = droppedDelta
		self._controllerThroughput15 = schedSnap and schedSnap.throughput15 or 0
		self._controllerIngestRate15 = schedSnap and schedSnap.ingestRate15 or 0
		self._controllerFillRatio = nil
		if schedSnap and schedSnap.capacity and schedSnap.capacity > 0 then
			self._controllerFillRatio = (schedSnap.pending or 0) / schedSnap.capacity
		end
		-- Advice trend proxy: use load15 vs throughput/ingest rate to classify.
		self._controllerTrend = "steady"
		if schedSnap then
			local load15 = schedSnap.load15 or 0
			local thr15 = schedSnap.throughput15 or 0
			local ir15 = schedSnap.ingestRate15 or 0
			if ir15 > thr15 * 1.05 and load15 > thr15 then
				self._controllerTrend = "rising"
			elseif thr15 >= ir15 * 1.05 then
				self._controllerTrend = "falling"
			end
		end
	end

	local drainMs = nil
	if emitTimed then
		local endMs = nowFn()
		if type(endMs) == "number" and endMs >= startMs then
			drainMs = endMs - startMs
		else
			emitTimed = false
		end
	end

	if diag then
		diag.windowDrainCalls = (diag.windowDrainCalls or 0) + 1
		diag.windowProcessed = (diag.windowProcessed or 0) + (stats.processed or processed or 0)
		diag.windowEmitMs = (diag.windowEmitMs or 0) + emitMs
		if type(drainMs) == "number" then
			diag.windowDrainMs = (diag.windowDrainMs or 0) + drainMs
			if drainMs > (diag.windowMaxDrainMs or 0) then
				diag.windowMaxDrainMs = drainMs
			end
		end

		local reportEveryTicks = diag.reportEveryTicks or 300
		if reportEveryTicks > 0 and (diag.windowTicks or 0) >= reportEveryTicks then
			local gcKb = (type(collectgarbage) == "function") and collectgarbage("count") or nil
			local processedTotal = diag.windowProcessed or 0
			local drainTotalMs = diag.windowDrainMs or 0
			local emitTotalMs = diag.windowEmitMs or 0
			local overheadMs = drainTotalMs - emitTotalMs
			if overheadMs < 0 then
				overheadMs = 0
			end
			local avgMsPerItem = processedTotal > 0 and (drainTotalMs / processedTotal) or nil

			IngestLog:info(
				"tick window ticks=%s drainCalls=%s processed=%s drainMs=%.1f emitMs=%.1f overheadMs=%.1f avgMsPerItem=%s gcKb=%s",
				tostring(diag.windowTicks),
				tostring(diag.windowDrainCalls),
				tostring(processedTotal),
				tonumber(drainTotalMs) or 0,
				tonumber(emitTotalMs) or 0,
				tonumber(overheadMs) or 0,
				avgMsPerItem and string.format("%.3f", avgMsPerItem) or "n/a",
				gcKb and string.format("%.0f", gcKb) or "n/a"
			)

			diag.windowTicks = 0
			diag.windowDrainCalls = 0
			diag.windowProcessed = 0
			diag.windowDrainMs = 0
			diag.windowEmitMs = 0
			diag.windowMaxDrainMs = 0
			diag.windowWarnedBudgetTick = 0
		end
	end
end

---Helper to drain the scheduler once (intended for headless/tests).
function FactRegistry:drainSchedulerOnceForTests()
	self:drainSchedulerOnce()
end

--- Clear all ingest buffers (pending items) without tearing down subscriptions.
--- Intended for emergency reset and tests.
--- @return table
function FactRegistry:ingest_clearAll()
	local clearedBuffers = 0
	for _, entry in pairs(self._types) do
		if entry.buffer and entry.buffer.clear then
			entry.buffer:clear()
			clearedBuffers = clearedBuffers + 1
		end
	end
	if self._scheduler and self._scheduler.metrics_reset then
		self._scheduler:metrics_reset()
	end
	-- Reset local diagnostics window so next report isn't misleading.
	if self._ingestDiag then
		self._ingestDiag.windowTicks = 0
		self._ingestDiag.windowDrainCalls = 0
		self._ingestDiag.windowProcessed = 0
		self._ingestDiag.windowDrainMs = 0
		self._ingestDiag.windowEmitMs = 0
		self._ingestDiag.windowMaxDrainMs = 0
		self._ingestDiag.windowWarnedBudgetTick = 0
	end
	return { clearedBuffers = clearedBuffers }
end

---Return ingest metrics for a fact type when enabled.
---@param name string
function FactRegistry:getIngestMetrics(name, opts)
	opts = opts or {}
	local entry = self._types[name]
	if not entry or not entry.buffer then
		return nil
	end
	if opts.full and entry.buffer.metrics_getFull then
		return entry.buffer:metrics_getFull()
	end
	if entry.buffer.metrics_getLight then
		return entry.buffer:metrics_getLight()
	end
	return entry.buffer:metrics_get()
end

---Return ingest advice for a fact type when enabled.
---@param name string
---@param opts table|nil
function FactRegistry:getIngestAdvice(name, opts)
	opts = opts or {}
	local entry = self._types[name]
	if not entry or not entry.buffer or not entry.buffer.advice_get then
		return nil
	end
	return entry.buffer:advice_get(opts)
end

---Return scheduler metrics when present.
function FactRegistry:getSchedulerMetrics()
	if not self._scheduler then
		return nil
	end
	if self._scheduler.metrics_get then
		return self._scheduler:metrics_get()
	end
	return nil
end

return FactRegistry
