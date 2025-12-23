-- observations/helpers.lua -- helper plumbing for ObservationStreams (enable/attach helpers).
local Log = require("LQR/util/log").withTag("WO.STREAM")

local moduleName = ...
local HelperSupport = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		HelperSupport = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = HelperSupport
	end
end

local function cloneTable(tbl)
	local out = {}
	for key, value in pairs(tbl or {}) do
		out[key] = value
	end
	return out
end

local function mergeTablesLastWins(out, incoming)
	for key, value in pairs(incoming or {}) do
		out[key] = value
	end
end

local function mergeTablesFirstWins(out, incoming)
	for key, value in pairs(incoming or {}) do
		if out[key] == nil then
			out[key] = value
		end
	end
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

local function resolveEnabledHelpers(overrides, baseEnabled)
	local resolved = cloneTable(baseEnabled)
	for helperKey, rawValue in pairs(overrides or {}) do
		local mapped = nil
		if rawValue == true then
			mapped = (baseEnabled and baseEnabled[helperKey]) or helperKey
		elseif type(rawValue) == "string" then
			if baseEnabled and baseEnabled[rawValue] ~= nil then
				mapped = baseEnabled[rawValue]
			else
				mapped = rawValue
			end
		else
			Log:warn(
				"enabled_helpers.%s expects true or string, got %s",
				tostring(helperKey),
				type(rawValue)
			)
		end
		if mapped ~= nil then
			resolved[helperKey] = mapped
		end
	end
	return resolved
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

-- Patch seam: only assign defaults when nil so overrides survive reloads.
HelperSupport.cloneTable = HelperSupport.cloneTable or cloneTable
HelperSupport.mergeTablesLastWins = HelperSupport.mergeTablesLastWins or mergeTablesLastWins
HelperSupport.mergeTablesFirstWins = HelperSupport.mergeTablesFirstWins or mergeTablesFirstWins
HelperSupport.listSortedKeys = HelperSupport.listSortedKeys or listSortedKeys
HelperSupport.resolveEnabledHelpers = HelperSupport.resolveEnabledHelpers or resolveEnabledHelpers
HelperSupport.buildHelperMethods = HelperSupport.buildHelperMethods or buildHelperMethods
HelperSupport.buildHelperNamespaces = HelperSupport.buildHelperNamespaces or buildHelperNamespaces

return HelperSupport
