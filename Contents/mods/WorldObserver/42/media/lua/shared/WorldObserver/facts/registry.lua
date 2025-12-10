-- facts/registry.lua -- manages fact sources: creates a stream per fact type and only starts its producer on first access.
local rx = require("reactivex")
local Log = require("util.log").withTag("WO.FACTS")

local FactRegistry = {}
FactRegistry.__index = FactRegistry -- registry instances resolve methods from this table via metatable lookup

local function defaultContext(registry, entry)
	-- Lazy start hooks get a tiny context so they can emit into the rxSubject without sharing internals.
	return {
		config = entry.config or {},
		emit = function(record)
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
		config = (self._config and self._config[name]) or {},
		rxSubject = nil,
		observable = nil,
		started = false,
		subscribers = 0,
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

function FactRegistry:onSubscribe(name)
	local entry = ensureEntry(self, name, true)
	if not entry.started and type(entry.start) == "function" then
		local ctx = defaultContext(self, entry)
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
			local okStop, errStop = pcall(tracked.stop, tracked)
			if not okStop then
				Log:warn("Failed to stop fact type '%s': %s", tostring(name), tostring(errStop))
			else
				tracked.started = false
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

return FactRegistry
