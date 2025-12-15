-- observations/core.lua -- ObservationStream type/registry: wraps LQR queries, attaches helpers, and surfaces streams.
local LQR = require("LQR")
local Query = LQR.Query
local Schema = LQR.Schema
local Log = require("LQR/util/log").withTag("WO.STREAM")

local moduleName = ...
local ObservationsCore = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		ObservationsCore = loaded
	else
		package.loaded[moduleName] = ObservationsCore
	end
end
ObservationsCore._internal = ObservationsCore._internal or {}
ObservationsCore._defaults = ObservationsCore._defaults or {}

local ObservationStream = {}

local BaseMethods = {}
BaseMethods.__index = BaseMethods -- let streams inherit BaseMethods via metatable lookup

local resolvedNowMillis = nil
local function resolveNowMillis()
	local gameTime = _G.getGameTime
	if type(gameTime) == "function" then
		local ok, timeObj = pcall(gameTime)
		if ok and timeObj and type(timeObj.getTimeCalendar) == "function" then
			local okCal, cal = pcall(timeObj.getTimeCalendar, timeObj)
			if okCal and cal and type(cal.getTimeInMillis) == "function" then
				resolvedNowMillis = function()
					local t = gameTime()
					local c = t:getTimeCalendar()
					return c:getTimeInMillis()
				end
				return
			end
		end
	end
	if type(os.clock) == "function" then
		resolvedNowMillis = function()
			return os.clock() * 1000
		end
		return
	end
	if type(os.time) == "function" then
		resolvedNowMillis = function()
			return os.time() * 1000
		end
		return
	end
	resolvedNowMillis = function()
		return nil
	end
end

local function nowMillis()
	if not resolvedNowMillis then
		resolveNowMillis()
	end
	return resolvedNowMillis()
end

local function cloneTable(tbl)
	local out = {}
	for key, value in pairs(tbl or {}) do
		out[key] = value
	end
	return out
end

local function newObservationStream(builder, helperMethods, dimensions, factRegistry, factDeps)
	local stream = {
		_builder = builder,
		_helperMethods = helperMethods or {},
		_dimensions = dimensions or {},
		_factRegistry = factRegistry,
		_factDeps = factDeps or {},
	}
	-- Keep a light OO shape via metatable so helper methods resolve and we don’t copy functions per instance.
	return setmetatable(stream, ObservationStream)
end

function BaseMethods:subscribe(callback, onError, onCompleted)
	local factUnsubscribers = {}
	if self._factRegistry and self._factRegistry.onSubscribe and self._factDeps then
		for _, dep in ipairs(self._factDeps) do
			local unsub = self._factRegistry:onSubscribe(dep)
			if unsub then
				factUnsubscribers[#factUnsubscribers + 1] = unsub
			end
		end
	end

	local subscription = self._builder:subscribe(callback, onError, onCompleted)
	local unsubscribed = false
	local function doUnsubscribe()
		if unsubscribed then
			return
		end
		unsubscribed = true
		if subscription and subscription.unsubscribe then
			subscription:unsubscribe()
		elseif type(subscription) == "function" then
			subscription()
		end
		for _, unsub in ipairs(factUnsubscribers) do
			pcall(unsub)
		end
	end

	return {
		unsubscribe = doUnsubscribe,
	}
end

function BaseMethods:getLQR()
	return self._builder
end

function BaseMethods:filter(predicate)
	local nextBuilder = self._builder:where(predicate)
	return newObservationStream(nextBuilder, self._helperMethods, self._dimensions, self._factRegistry, self._factDeps)
end

function BaseMethods:distinct(dimension, seconds)
	local dim = self._dimensions[dimension]
	assert(dim ~= nil, ("distinct: unknown dimension '%s'"):format(tostring(dimension)))

	-- Helpers declare which schema/field represents a dimension; distinct rides on that mapping.
	local by = dim.keySelector or dim.keyField or "id"
	local window
	if seconds ~= nil then
		assert(type(seconds) == "number" and seconds >= 0, "distinct seconds must be a non-negative number")
		-- LQR time windows are expressed in the same units as RxMeta.sourceTime; WorldObserver uses ms timestamps.
		local offsetMillis = seconds * 1000
		window = {
			mode = "interval",
			time = offsetMillis,
			field = "sourceTime",
			currentFn = nowMillis,
		}
	end

	local nextBuilder = self._builder:distinct(dim.schema, { by = by, window = window })
	return newObservationStream(nextBuilder, self._helperMethods, self._dimensions, self._factRegistry, self._factDeps)
end

ObservationStream.__index = function(self, key)
	local base = BaseMethods[key]
	if base then
		return base
	end
	-- Forward unknown methods to helper sets so streams stay thin wrappers.
	local helper = self._helperMethods[key]
	if helper then
		return function(_, ...)
			return helper(self, ...)
		end
	end
	return nil
end

local ObservationRegistry = {}
ObservationRegistry.__index = ObservationRegistry -- registry instances resolve methods from this table

local observationIdCounter = 0
local function nextObservationId()
	-- Cheap per-observation id shared across the VM so custom schemas can opt into the same monotonic ids.
	observationIdCounter = observationIdCounter + 1
	return observationIdCounter
end

local function buildHelperMethods(helperSets, enabledHelpers)
	local methods = {}
	for helperKey, fieldName in pairs(enabledHelpers or {}) do
		local helperSet = helperSets[helperKey]
		if helperSet then
			-- Helper sets can target alternative field names (enabled_helpers value), defaulting to their own key.
			local targetField = fieldName == true and helperKey or fieldName
			for methodName, helperFn in pairs(helperSet) do
				if type(helperFn) == "function" and methods[methodName] == nil then
					methods[methodName] = function(stream, ...)
						return helperFn(stream, targetField, ...)
					end
				end
			end
		else
			Log:warn("No helper set found for '%s'", tostring(helperKey))
		end
	end
	return methods
end

function ObservationRegistry.new(opts)
	-- Registry uses a metatable for method lookup; instances are just tables carrying deps/config.
	local self = setmetatable({
		_factRegistry = assert(opts.factRegistry, "factRegistry required"),
		_config = opts.config or {},
		_helperSets = opts.helperSets or {},
		_registry = {},
		_api = {},
	}, ObservationRegistry)
	return self
end

function ObservationRegistry:register(name, opts)
	assert(type(name) == "string" and name ~= "", "Observation name must be a non-empty string")
	if self._registry[name] then
		error(("Observation '%s' already registered"):format(name))
	end
	assert(type(opts) == "table", "opts table required")
	assert(type(opts.build) == "function", "opts.build must be a function")
	if opts.enabled_helpers then
		for helperKey in pairs(opts.enabled_helpers) do
			if not self._helperSets[helperKey] then
				Log:warn("Observation '%s' configured helper set '%s' that is not registered", name, tostring(helperKey))
			end
		end
	end

	self._registry[name] = {
		build = opts.build,
		enabled_helpers = cloneTable(opts.enabled_helpers),
		dimensions = cloneTable(opts.dimensions),
		fact_deps = cloneTable(opts.fact_deps),
	}

	self._api[name] = function(_, streamOpts)
		return self:_buildStream(name, streamOpts)
	end
end

function ObservationRegistry:_buildStream(name, streamOpts)
	local entry = self._registry[name]
	if not entry then
		error(("Unknown observation '%s'"):format(tostring(name)))
	end

	local builder = entry.build(streamOpts or {})
	local helperMethods = buildHelperMethods(self._helperSets, entry.enabled_helpers)
	local dimensions = entry.dimensions or {}
	return newObservationStream(builder, helperMethods, dimensions, self._factRegistry, entry.fact_deps)
end

function ObservationRegistry:api()
	return self._api
end

function ObservationRegistry:hasStream(name)
	return self._registry[name] ~= nil
end

function ObservationRegistry:getFactRegistry()
	return self._factRegistry
end

local function wrapSchema(observable, schemaName, opts)
	return Schema.wrap(schemaName, observable, opts or {})
end

ObservationsCore._defaults.new = ObservationRegistry.new
ObservationsCore._defaults.wrapSchema = wrapSchema
ObservationsCore._defaults.nextObservationId = nextObservationId
ObservationsCore._internal.nowMillis = nowMillis
ObservationsCore._internal.resolveNowMillis = resolveNowMillis
ObservationsCore._internal.cloneTable = cloneTable
ObservationsCore._internal.newObservationStream = newObservationStream
ObservationsCore._internal.buildHelperMethods = buildHelperMethods

-- Patch seam: define only when nil so mods can override by reassigning these module fields and so reloads
-- (tests/console via `package.loaded`) don't clobber an existing patch.
if ObservationsCore.new == nil then
	ObservationsCore.new = ObservationRegistry.new
end
ObservationsCore.ObservationStream = ObservationsCore.ObservationStream or ObservationStream
if ObservationsCore.wrapSchema == nil then
	ObservationsCore.wrapSchema = wrapSchema
end
if ObservationsCore.nextObservationId == nil then
	ObservationsCore.nextObservationId = nextObservationId
end

return ObservationsCore
