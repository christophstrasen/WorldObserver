-- observations/core.lua -- ObservationStream type/registry: wraps LQR queries, attaches helpers, and surfaces streams.
local LQR = require("LQR")
local Query = LQR.Query
local Schema = LQR.Schema
local Log = require("LQR/util/log").withTag("WO.STREAM")
local Time = require("WorldObserver/helpers/time")

local moduleName = ...
local ObservationsCore = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		ObservationsCore = loaded
	else
		---@diagnostic disable-next-line: undefined-field
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
	resolvedNowMillis = function()
		return Time.gameMillis()
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

local function listSortedKeys(tbl)
	local keys = {}
	local count = 0
	for key in pairs(tbl or {}) do
		count = count + 1
		keys[count] = key
	end
	table.sort(keys)
	return keys
end

local function buildHelperNamespaces(helperSets, enabledHelpers, stream)
	local namespaces = {}
	for _, helperKey in ipairs(listSortedKeys(enabledHelpers)) do
		local fieldName = enabledHelpers[helperKey]
		local helperSet = helperSets and helperSets[helperKey] or nil
		if helperSet then
			local targetField = fieldName == true and helperKey or fieldName
			local helperSource = helperSet
			if type(helperSet.stream) == "table" then
				helperSource = helperSet.stream
			end

			local proxy = {
				key = helperKey,
				defaultField = targetField,
				raw = helperSet,
				stream = helperSource,
			}

			for methodName, helperFn in pairs(helperSource) do
				if type(helperFn) == "function" and proxy[methodName] == nil then
					proxy[methodName] = function(_, maybeFieldName, ...)
						if type(maybeFieldName) == "string" and maybeFieldName ~= "" then
							return helperFn(stream, maybeFieldName, ...)
						end
						return helperFn(stream, targetField, maybeFieldName, ...)
					end
				end
			end
			namespaces[helperKey] = proxy
		end
	end
	return namespaces
end

local function newObservationStream(builder, helperMethods, dimensions, factRegistry, factDeps, helperSets, enabledHelpers)
	local enabled = cloneTable(enabledHelpers)
	local stream = {
		_builder = builder,
		_helperMethods = helperMethods or {},
		_dimensions = dimensions or {},
		_factRegistry = factRegistry,
		_factDeps = factDeps or {},
		_helperSets = helperSets or {},
		_enabled_helpers = enabled,
		helpers = {},
	}
	stream.helpers = buildHelperNamespaces(stream._helperSets, enabled, stream)
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
	-- Return a join-friendly builder rooted at this stream's OUTPUT schemas (post-selectSchemas).
	-- LQR join steps operate on the schemas currently flowing through the pipeline; WO hides the
	-- internal schema names ("SquareObservation", etc) behind selectSchemas aliases ("square", etc).
	-- If we return the raw builder here, users will configure joins against the visible aliases but
	-- LQR will still see the pre-selection schema names, causing joins to silently drop everything.
	--
	-- We solve this by anchoring a new QueryBuilder to the stream's built observable (which has
	-- selectSchemas already applied), and then copying the schema name metadata so join coverage
	-- checks and warnings stay useful without forcing a selection that would later drop joined schemas.
	if self._lqrBuilder then
		return self._lqrBuilder
	end

	-- Note: Query.from(QueryBuilder) will build the source builder. We try to avoid marking the stream's
	-- underlying builder as "built" (which would trigger LQR warnings when users later chain WO helpers)
	-- by building a clone instead.
	local source = self._builder
	local cloneFn = source and source._clone
	if source and source._built == nil and type(cloneFn) == "function" then
		local ok, cloned = pcall(cloneFn, source)
		if ok and type(cloned) == "table" then
			source = cloned
		end
	end

	local joinable = Query.from(source)

	local schemaNames = self._builder and self._builder._schemaNames
	if type(schemaNames) == "table" then
		local copied = {}
		for _, schemaName in ipairs(schemaNames) do
			if type(schemaName) == "string" and schemaName ~= "" then
				copied[#copied + 1] = schemaName
			end
		end
		if #copied >= 1 then
			joinable._rootSchemas = copied
			joinable._schemaNames = copied
		end
	end

	self._lqrBuilder = joinable
	return joinable
end

function BaseMethods:asRx()
	local rx = require("reactivex")
	local Observable = rx and rx.Observable
	assert(Observable, "reactivex Observable not available")
	local stream = self
	return Observable.create(function(observer)
		local subscription = stream:subscribe(
			function(value)
				return observer:onNext(value)
			end,
			function(err)
				return observer:onError(err)
			end,
			function()
				return observer:onCompleted()
			end
		)
		return function()
			if subscription and subscription.unsubscribe then
				subscription:unsubscribe()
			end
		end
	end)
end

function BaseMethods:filter(predicate)
	local nextBuilder = self._builder:where(predicate)
	return newObservationStream(
		nextBuilder,
		self._helperMethods,
		self._dimensions,
		self._factRegistry,
		self._factDeps,
		self._helperSets,
		self._enabled_helpers
	)
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
	return newObservationStream(
		nextBuilder,
		self._helperMethods,
		self._dimensions,
		self._factRegistry,
		self._factDeps,
		self._helperSets,
		self._enabled_helpers
	)
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
	for _, helperKey in ipairs(listSortedKeys(enabledHelpers)) do
		local fieldName = enabledHelpers[helperKey]
		local helperSet = helperSets[helperKey]
		if helperSet then
			-- Helper sets can target alternative field names (enabled_helpers value), defaulting to their own key.
			local targetField = fieldName == true and helperKey or fieldName
			-- Only attach explicit stream helpers (avoid attaching record predicates, hydration helpers, effects, etc.).
			local helperSource = helperSet
			if type(helperSet.stream) == "table" then
				helperSource = helperSet.stream
			end
			for methodName, helperFn in pairs(helperSource) do
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
	-- Derived streams are an advanced feature, but we still expose them on the public API table
	-- so user code can keep WO lifecycle semantics (facts start on subscribe).
	if self._api.derive == nil then
		self._api.derive = function(api, streamsByName, buildFn, deriveOpts)
			assert(api == self._api, "Call as WorldObserver.observations:derive(streamsByName, buildFn, opts)")
			return self:derive(streamsByName, buildFn, deriveOpts)
		end
	end
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

	self._api[name] = function(api, streamOpts)
		assert(api == self._api, ("Call as WorldObserver.observations:%s(opts)"):format(tostring(name)))
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
	return newObservationStream(builder, helperMethods, dimensions, self._factRegistry, entry.fact_deps, self._helperSets, entry.enabled_helpers)
end

local function listStreamNames(streamsByName)
	local names = {}
	local count = 0
	for name in pairs(streamsByName or {}) do
		assert(type(name) == "string" and name ~= "", "derive stream keys must be non-empty strings")
		count = count + 1
		names[count] = name
	end
	table.sort(names)
	return names
end

local function mergeUniqueFactDeps(out, seen, deps)
	for _, dep in ipairs(deps or {}) do
		if type(dep) == "string" and dep ~= "" and seen[dep] ~= true then
			out[#out + 1] = dep
			seen[dep] = true
		end
	end
end

local function mergeTablesFirstWins(out, incoming)
	for key, value in pairs(incoming or {}) do
		if out[key] == nil then
			out[key] = value
		end
	end
end

-- Derived ObservationStreams (wrapping LQR queries while preserving fact dependency lifecycles).
-- Why: subscribing to an LQR query directly bypasses FactRegistry:onSubscribe(...), so probes/listeners don't start.
if ObservationRegistry.derive == nil then
	--- Build a derived ObservationStream from one or more input streams.
	--- The returned stream keeps WO lifecycle semantics (facts start on subscribe, stop on unsubscribe).
	--- @param streamsByName table<string, any> ObservationStream map (values must support :getLQR()).
	--- @param buildFn fun(lqrByName: table<string, any>, opts: table): any Returns an LQR query/builder with :subscribe().
	--- @param opts table|nil Passed through to buildFn.
	--- @return any ObservationStream
	function ObservationRegistry:derive(streamsByName, buildFn, opts)
		assert(type(streamsByName) == "table", "derive expects streamsByName table")
		assert(type(buildFn) == "function", "derive expects buildFn function")
		opts = opts or {}

		local factDeps = {}
		local factDepsSeen = {}
		local enabledHelpers = {}
		local helperMethods = {}
		local dimensions = {}
		local lqrByName = {}

		local names = listStreamNames(streamsByName)
		assert(#names >= 1, "derive expects at least one input stream")
		for i = 1, #names do
			local name = names[i]
			local stream = streamsByName[name]
			assert(type(stream) == "table", ("derive stream '%s' must be a table"):format(tostring(name)))
			assert(type(stream.getLQR) == "function", ("derive stream '%s' must support :getLQR()"):format(tostring(name)))
			lqrByName[name] = stream:getLQR()

			if stream._factRegistry ~= nil and stream._factRegistry ~= self._factRegistry then
				Log:warn(
					"derive received stream with different factRegistry name=%s registry=%s streamRegistry=%s",
					tostring(name),
					tostring(self._factRegistry),
					tostring(stream._factRegistry)
				)
			end

			if type(stream._factDeps) == "table" then
				mergeUniqueFactDeps(factDeps, factDepsSeen, stream._factDeps)
			end
			if type(stream._enabled_helpers) == "table" then
				for helperKey in pairs(stream._enabled_helpers) do
					if enabledHelpers[helperKey] == nil then
						-- Derived streams are built from :getLQR() builders, which are rooted in OUTPUT schemas
						-- (post-selectSchemas). Helper predicates run before the derived stream's own selection,
						-- so default to the public schema aliases ("square", "zombie", ...) instead of the
						-- source stream's internal schema names ("SquareObservation", ...).
						enabledHelpers[helperKey] = helperKey
					end
				end
			end
			if type(stream._dimensions) == "table" then
				mergeTablesFirstWins(dimensions, stream._dimensions)
			end
		end

		helperMethods = buildHelperMethods(self._helperSets, enabledHelpers)
		for i = 1, #names do
			local name = names[i]
			local stream = streamsByName[name]
			if type(stream._helperMethods) == "table" then
				mergeTablesFirstWins(helperMethods, stream._helperMethods)
			end
		end

		local builder = buildFn(lqrByName, opts)
		assert(type(builder) == "table" and type(builder.subscribe) == "function", "derive buildFn must return LQR query with :subscribe()")
		return newObservationStream(builder, helperMethods, dimensions, self._factRegistry, factDeps, self._helperSets, enabledHelpers)
	end
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
