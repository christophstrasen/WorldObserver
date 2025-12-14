-- facts/registry.lua -- manages fact sources: creates a stream per fact type and only starts its producer on first access.
local rx = require("reactivex")
local Ingest = require("LQR/ingest")
local Log = require("LQR/util/log").withTag("WO.FACTS")

local FactRegistry = {}
FactRegistry.__index = FactRegistry -- registry instances resolve methods from this table via metatable lookup

local function defaultContext(entry)
	-- Lazy start hooks get a tiny context; ingest defaults to direct emit when ingest is disabled.
	return {
		config = entry.config or {},
		state = entry.state,
		emit = function(record)
			if record ~= nil then
				entry.rxSubject:onNext(record)
			end
		end,
		ingest = function(record)
			if record ~= nil then
				entry.rxSubject:onNext(record)
			end
		end,
	}
end

function FactRegistry.new(config)
	-- Registry uses a metatable for method lookup; e.g. self:register(...) resolves to FactRegistry.register.
	-- The payload is a plain table with config/state.
	local self = setmetatable({
		_config = config or {},
		_types = {},
		_scheduler = nil,
		_drainHookRegistered = false,
	}, FactRegistry)
	return self
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
		config = (self._config and self._config[name]) or {},
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

local function buildBuffer(self, name, entry)
	local cfg = entry.config and entry.config.ingest
	local ingestOpts = entry.ingestOpts
	if not cfg or cfg.enabled ~= true or not ingestOpts or type(ingestOpts.key) ~= "function" then
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
	local schedCfg = (self._config and self._config.ingest and self._config.ingest.scheduler) or {}
	self._scheduler = Ingest.scheduler({
		name = "WorldObserver.factScheduler",
		maxItemsPerTick = schedCfg.maxItemsPerTick or 0,
		quantum = schedCfg.quantum or 1,
	})
	return self._scheduler
end

local function isHeadless()
	return _G.WORLDOBSERVER_HEADLESS == true
end

local function ensureDrainHook(self)
	if self._drainHookRegistered then
		return
	end
	local events = _G.Events
	if not events or not events.OnTick or type(events.OnTick.Add) ~= "function" then
		if not isHeadless() then
			Log:warn("Ingest scheduler drain hook not registered (Events unavailable)")
		end
		return
	end
	events.OnTick.Add(function()
		if self._scheduler then
			self:_drainSchedulerOnce()
		end
	end)
	self._drainHookRegistered = true
end

function FactRegistry:onSubscribe(name)
	local entry = ensureEntry(self, name, true)
	if not entry.started and type(entry.start) == "function" then
		local ctx = defaultContext(entry)
		-- Enable ingest when configured for this type.
		if entry.config and entry.config.ingest and entry.config.ingest.enabled and entry.ingestOpts then
			entry.buffer = entry.buffer or buildBuffer(self, name, entry)
			if entry.buffer then
				local scheduler = ensureScheduler(self)
				ensureDrainHook(self)
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
			Log:error("Failed to start fact type '%s': %s", tostring(name), tostring(err))
		else
			entry.started = true
		end
	end
	entry.subscribers = (entry.subscribers or 0) + 1

	return function()
		local tracked = ensureEntry(self, name, false)
		tracked.subscribers = math.max(0, (tracked.subscribers or 1) - 1)
		if tracked.subscribers == 0 and tracked.started and type(tracked.stop) == "function" then
			local okStop, stopResultOrError = pcall(tracked.stop, tracked)
			if not okStop then
				Log:warn("Failed to stop fact type '%s': %s", tostring(name), tostring(stopResultOrError))
			else
				-- stop() may return false to indicate it could not fully stop (e.g. no remove semantics),
				-- in which case we keep the type "started" to avoid double-registering handlers.
				if stopResultOrError ~= false then
					tracked.started = false
				end
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

function FactRegistry:_drainSchedulerOnce()
	if not self._scheduler then
		return
	end
	self._scheduler:drainTick(function(item)
		if item then
			local emitFn = item.__emit
			local record = item.payload or item
			if emitFn then
				emitFn(record)
			end
		end
	end)
end

---Helper to drain the scheduler once (intended for headless/tests).
function FactRegistry:drainOnceForTests()
	self:_drainSchedulerOnce()
end

---Return ingest metrics for a fact type when enabled.
---@param name string
function FactRegistry:getIngestMetrics(name)
	local entry = self._types[name]
	if not entry or not entry.buffer then
		return nil
	end
	return entry.buffer:metrics_get()
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
