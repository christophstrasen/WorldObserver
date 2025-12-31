-- situations/registry.lua -- situation factory registry and namespaced facade.
local Log = require("DREAMBase/log").withTag("WO.SITUATIONS")

local moduleName = ...
local SituationsRegistry = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		SituationsRegistry = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = SituationsRegistry
	end
end
SituationsRegistry._internal = SituationsRegistry._internal or {}
SituationsRegistry._defaults = SituationsRegistry._defaults or {}

local function assertNonEmptyString(value, name)
	assert(type(value) == "string" and value ~= "", ("%s must be a non-empty string"):format(tostring(name)))
end

local function normalizeArgs(args)
	if args == nil then
		return {}
	end
	assert(type(args) == "table", "args must be a table or nil")
	return args
end

local function listSortedKeys(tbl)
	local keys = {}
	for key in pairs(tbl or {}) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return keys
end

local function listAllQualified(definitions)
	local keys = {}
	for namespace, bucket in pairs(definitions or {}) do
		for situationId in pairs(bucket or {}) do
			keys[#keys + 1] = ("%s/%s"):format(tostring(namespace), tostring(situationId))
		end
	end
	table.sort(keys)
	return keys
end

local function newRegistry()
	local registry = {
		_definitions = {},
		_api = nil,
	}

	local function getBucket(namespace, create)
		local bucket = registry._definitions[namespace]
		if bucket == nil and create == true then
			bucket = {}
			registry._definitions[namespace] = bucket
		end
		return bucket
	end

	local function define(namespace, situationId, factoryFn, opts)
		assertNonEmptyString(namespace, "namespace")
		assertNonEmptyString(situationId, "situationId")
		assert(type(factoryFn) == "function", "factoryFn must be a function")

		local bucket = getBucket(namespace, true)
		local existed = bucket[situationId] ~= nil

		Log:info("Situation defined namespace=%s id=%s", tostring(namespace), tostring(situationId))
		if existed then
			Log:info("Situation overwritten namespace=%s id=%s", tostring(namespace), tostring(situationId))
		end

		local describe = opts and opts.describe or nil
		bucket[situationId] = {
			factory = factoryFn,
			describe = describe,
		}
	end

	local function get(namespace, situationId, args)
		assertNonEmptyString(namespace, "namespace")
		assertNonEmptyString(situationId, "situationId")

		local bucket = getBucket(namespace, false)
		if bucket == nil or bucket[situationId] == nil then
			error(
				("situation definition missing (namespace=%s id=%s)"):format(tostring(namespace), tostring(situationId)),
				2
			)
		end

		local entry = bucket[situationId]
		local safeArgs = normalizeArgs(args)
		local stream = entry.factory(safeArgs)
		assert(
			type(stream) == "table" and type(stream.subscribe) == "function",
			"factory must return a stream with :subscribe()"
		)
		return stream
	end

	local function subscribeTo(namespace, situationId, args, onNext)
		local stream = get(namespace, situationId, args)
		return stream:subscribe(onNext)
	end

	local function listNamespace(namespace)
		assertNonEmptyString(namespace, "namespace")
		local bucket = getBucket(namespace, false)
		return listSortedKeys(bucket)
	end

	local function listAll()
		return listAllQualified(registry._definitions)
	end

	local function namespaceHandle(namespace)
		assertNonEmptyString(namespace, "namespace")
		local situations = {}
		situations.define = function(situationId, factoryFn, opts)
			return define(namespace, situationId, factoryFn, opts)
		end
		situations.get = function(situationId, args)
			return get(namespace, situationId, args)
		end
		situations.subscribeTo = function(situationId, args, onNext)
			return subscribeTo(namespace, situationId, args, onNext)
		end
		situations.list = function()
			return listNamespace(namespace)
		end
		situations.listAll = function()
			return listAll()
		end
		return situations
	end

	function registry:api()
		if self._api == nil then
			self._api = {}
		end
		local api = self._api
		if api.namespace == nil then
			api.namespace = function(namespace)
				return namespaceHandle(namespace)
			end
		end
		if api.listAll == nil then
			api.listAll = function()
				return listAll()
			end
		end
		return api
	end

	registry._internal = {
		define = define,
		get = get,
		list = listNamespace,
		listAll = listAll,
		subscribeTo = subscribeTo,
		namespace = namespaceHandle,
	}

	return registry
end

SituationsRegistry._defaults.new = newRegistry

if SituationsRegistry.new == nil then
	SituationsRegistry.new = newRegistry
end

return SituationsRegistry
