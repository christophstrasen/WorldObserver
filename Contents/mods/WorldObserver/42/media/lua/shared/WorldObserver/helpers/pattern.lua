-- helpers/pattern.lua -- string match helpers for prefix-style wildcard patterns.
local moduleName = ...
local PatternHelpers = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		PatternHelpers = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = PatternHelpers
	end
end

PatternHelpers._internal = PatternHelpers._internal or {}

local function matchesPrefixPattern(value, pattern)
	if type(value) ~= "string" or value == "" then
		return false
	end
	if type(pattern) ~= "string" or pattern == "" then
		return false
	end
	if string.sub(pattern, -1) == "%" then
		local prefix = string.sub(pattern, 1, -2)
		if prefix == "" then
			return true
		end
		return string.find(value, prefix, 1, true) == 1
	end
	return value == pattern
end

if PatternHelpers.matchesPrefixPattern == nil then
	PatternHelpers.matchesPrefixPattern = matchesPrefixPattern
end

PatternHelpers._internal.matchesPrefixPattern = PatternHelpers._internal.matchesPrefixPattern or matchesPrefixPattern

return PatternHelpers
