-- observations/core.lua -- ObservationStream type/registry: wraps LQR queries, attaches helpers, and surfaces streams.
local LQR = require("LQR")
local Query = LQR.Query
local Schema = LQR.Schema
local Log = require("DREAMBase/log").withTag("WO.STREAM")
local WoMetaLog = require("DREAMBase/log").withTag("WO.WOMETA")
local Time = require("DREAMBase/time_ms")
local WoMeta = require("WorldObserver/observations/wo_meta")
local Debug = require("WorldObserver/debug")
local HelperSupport = require("WorldObserver/observations/helpers")

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

local function normalizeOccurranceKey(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function normalizeFamilyList(spec)
	local families = {}
	local seen = {}
	if type(spec) == "string" then
		if spec ~= "" then
			families[1] = spec
		end
	elseif type(spec) == "table" then
		for _, value in ipairs(spec) do
			if type(value) == "string" and value ~= "" and not seen[value] then
				seen[value] = true
				families[#families + 1] = value
			end
		end
	end
	table.sort(families)
	return families
end

local function computeOccurranceKeyFromFamilies(observation, spec)
	if type(observation) ~= "table" then
		return nil, "not_table"
	end
	local families = normalizeFamilyList(spec)
	if #families == 0 then
		return nil, "no_families"
	end

	local segments = {}
	for _, familyName in ipairs(families) do
		local record = observation[familyName]
		if record == nil then
			return nil, "missing_family"
		end
		if type(record) ~= "table" then
			return nil, "bad_record"
		end
		local recordKey = record.woKey
		if type(recordKey) ~= "string" or recordKey == "" then
			return nil, "missing_record_woKey"
		end
		local segment = WoMeta.buildSegment(familyName, recordKey)
		if not segment then
			return nil, "bad_segment"
		end
		segments[#segments + 1] = segment
	end
	if #segments == 0 then
		return nil, "no_segments"
	end
	return table.concat(segments), nil
end

local function resolveOccurranceKey(observation, spec)
	if spec == nil then
		local woMeta = type(observation) == "table" and observation.WoMeta or nil
		local key = type(woMeta) == "table" and woMeta.key or nil
		local normalized = normalizeOccurranceKey(key)
		if normalized ~= nil then
			return normalized, nil
		end
		return nil, "missing_wometa_key"
	end

	local specType = type(spec)
	if specType == "function" then
		local ok, result = pcall(spec, observation)
		if not ok then
			return nil, "override_error"
		end
		local normalized = normalizeOccurranceKey(result)
		if normalized == nil then
			return nil, "bad_occurrance_key"
		end
		return normalized, nil
	end

	if specType == "string" or specType == "table" then
		return computeOccurranceKeyFromFamilies(observation, spec)
	end

	return nil, "bad_spec"
end

local cloneTable = HelperSupport.cloneTable
local mergeTablesLastWins = HelperSupport.mergeTablesLastWins
local mergeTablesFirstWins = HelperSupport.mergeTablesFirstWins
local listSortedKeys = HelperSupport.listSortedKeys
local resolveEnabledHelpers = HelperSupport.resolveEnabledHelpers
local buildHelperMethods = HelperSupport.buildHelperMethods
local buildHelperNamespaces = HelperSupport.buildHelperNamespaces

local function newObservationStream(
	builder,
	helperMethods,
	dimensions,
	factRegistry,
	factDeps,
	helperSets,
	enabledHelpers
)
	local enabled = cloneTable(enabledHelpers)
	local stream = {
		_builder = builder,
		_helperMethods = helperMethods or {},
		_dimensions = dimensions or {},
		_factRegistry = factRegistry,
		_factDeps = factDeps or {},
		_helperSets = helperSets or {},
		_enabled_helpers = enabled,
		_occurranceKeySpec = nil,
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

	local onNext = callback
	if type(callback) == "function" then
		onNext = function(value)
			local hasOverride = self._occurranceKeySpec ~= nil
			local ok, reason = WoMeta.attachWoMeta(value)
			if not ok then
				local detail = Debug.describeWoKey and Debug.describeWoKey(value) or tostring(value)
				if hasOverride then
					WoMetaLog:warn("missing_key reason=%s occurranceKey=override %s", tostring(reason), tostring(detail))
				else
					WoMetaLog:warn("occurranceKey missing source=default reason=%s %s", tostring(reason), tostring(detail))
				end
			end

			local occurranceKey, occurranceReason = resolveOccurranceKey(value, self._occurranceKeySpec)
			value.WoMeta = value.WoMeta or {}
			value.WoMeta.occurranceKey = occurranceKey
			if occurranceKey == nil and hasOverride then
				local detail = Debug.describeWoKey and Debug.describeWoKey(value) or tostring(value)
				WoMetaLog:warn(
					"occurranceKey missing source=override reason=%s %s",
					tostring(occurranceReason),
					tostring(detail)
				)
			end

			return callback(value)
		end
	end

	local subscription = self._builder:subscribe(onNext, onError, onCompleted)
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
		local nextBuilder = self._builder:finalWhere(predicate)
		local stream = newObservationStream(
			nextBuilder,
			self._helperMethods,
			self._dimensions,
		self._factRegistry,
		self._factDeps,
		self._helperSets,
			self._enabled_helpers
		)
		stream._occurranceKeySpec = self._occurranceKeySpec
		return stream
	end

	function BaseMethods:finalTap(tapFn)
		local nextBuilder = self._builder:finalTap(tapFn)
		local stream = newObservationStream(
			nextBuilder,
			self._helperMethods,
			self._dimensions,
			self._factRegistry,
			self._factDeps,
			self._helperSets,
			self._enabled_helpers
		)
		stream._occurranceKeySpec = self._occurranceKeySpec
		return stream
	end

function BaseMethods:distinct(dimension, seconds)
	local dim = self._dimensions[dimension]
	assert(
		dim ~= nil,
		("distinct: unknown dimension '%s'. This stream does not expose that family; use one of: %s"):format(
			tostring(dimension),
			table.concat(listSortedKeys(self._dimensions or {}), ", ")
		)
	)

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
	local stream = newObservationStream(
		nextBuilder,
		self._helperMethods,
		self._dimensions,
		self._factRegistry,
		self._factDeps,
		self._helperSets,
		self._enabled_helpers
	)
	stream._occurranceKeySpec = self._occurranceKeySpec
	return stream
end

function BaseMethods:withHelpers(opts)
	assert(type(opts) == "table", "withHelpers expects a single options table")

	local helperSets = opts.helperSets
	if helperSets ~= nil then
		assert(type(helperSets) == "table", "withHelpers helperSets must be a table")
	end
	if opts.enabled_helpers ~= nil then
		assert(type(opts.enabled_helpers) == "table", "withHelpers enabled_helpers must be a table")
	end

	local mergedHelperSets = cloneTable(self._helperSets)
	mergeTablesLastWins(mergedHelperSets, helperSets)

	local enabledHelpers = resolveEnabledHelpers(opts.enabled_helpers, self._enabled_helpers)
	for helperKey in pairs(helperSets or {}) do
		if enabledHelpers[helperKey] == nil then
			enabledHelpers[helperKey] = helperKey
		end
	end

	local helperMethods = buildHelperMethods(mergedHelperSets, enabledHelpers)
	mergeTablesFirstWins(helperMethods, self._helperMethods)

	local stream = newObservationStream(
		self._builder,
		helperMethods,
		self._dimensions,
		self._factRegistry,
		self._factDeps,
		mergedHelperSets,
		enabledHelpers
	)
	stream._occurranceKeySpec = self._occurranceKeySpec
	return stream
end

function BaseMethods:withOccurrenceKey(spec)
	assert(spec ~= nil, "withOccurrenceKey expects a spec")
	local specType = type(spec)
	assert(
		specType == "string" or specType == "table" or specType == "function",
		"withOccurrenceKey expects a string, table, or function"
	)
	local stream = newObservationStream(
		self._builder,
		self._helperMethods,
		self._dimensions,
		self._factRegistry,
		self._factDeps,
		self._helperSets,
		self._enabled_helpers
	)
	stream._occurranceKeySpec = spec
	return stream
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
	if self._api.registerHelperFamily == nil then
		self._api.registerHelperFamily = function(api, family, helperSet)
			assert(api == self._api, "Call as WorldObserver.observations:registerHelperFamily(family, helperSet)")
			return self:registerHelperFamily(family, helperSet)
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

if ObservationRegistry.registerHelperFamily == nil then
	function ObservationRegistry:registerHelperFamily(family, helperSet)
		assert(type(family) == "string" and family ~= "", "registerHelperFamily family must be a non-empty string")
		assert(type(helperSet) == "table", "registerHelperFamily helperSet must be a table")
		self._helperSets[family] = helperSet
		return helperSet
	end
end

function ObservationRegistry:_buildStream(name, streamOpts)
	local entry = self._registry[name]
	if not entry then
		error(("Unknown observation '%s'"):format(tostring(name)))
	end

	local builder = entry.build(streamOpts or {})
	local dimensions = entry.dimensions or {}
	local helperMethods = buildHelperMethods(self._helperSets, entry.enabled_helpers)
	return newObservationStream(
		builder,
		helperMethods,
		dimensions,
		self._factRegistry,
		entry.fact_deps,
		self._helperSets,
		entry.enabled_helpers
	)
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
			local helperMethods
			local helperSets = cloneTable(self._helperSets)
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
							-- (post-selectSchemas). Stream helpers operate on that final output, so default to the
							-- public schema aliases ("square", "zombie", ...) instead of internal schema names
							-- ("SquareObservation", ...).
							enabledHelpers[helperKey] = helperKey
						end
					end
				end
			if type(stream._helperSets) == "table" then
				mergeTablesLastWins(helperSets, stream._helperSets)
			end
			if type(stream._dimensions) == "table" then
				mergeTablesFirstWins(dimensions, stream._dimensions)
			end
		end

		helperMethods = buildHelperMethods(helperSets, enabledHelpers)
		for i = 1, #names do
			local name = names[i]
			local stream = streamsByName[name]
			if type(stream._helperMethods) == "table" then
				mergeTablesFirstWins(helperMethods, stream._helperMethods)
			end
		end

			local builder = buildFn(lqrByName, opts)
			assert(
				type(builder) == "table" and type(builder.subscribe) == "function",
				"derive buildFn must return LQR query with :subscribe()"
			)
			return newObservationStream(
				builder,
				helperMethods,
				dimensions,
				self._factRegistry,
				factDeps,
				helperSets,
				enabledHelpers
			)
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
ObservationsCore._internal.resolveEnabledHelpers = resolveEnabledHelpers

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
