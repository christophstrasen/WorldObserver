-- source.lua -- helpers for formatting record source labels.
local moduleName = ...
local SourceHelpers = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		SourceHelpers = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = SourceHelpers
	end
end

SourceHelpers.record = SourceHelpers.record or {}

if SourceHelpers.record.qualifiedSource == nil then
	--- Build a fully-qualified source label from a record (source + scope).
	--- @param record table|nil
	--- @return string|nil
	function SourceHelpers.record.qualifiedSource(record)
		if type(record) ~= "table" then
			return nil
		end
		local source = record.source
		if type(source) ~= "string" or source == "" then
			return nil
		end
		local scope = record.scope
		if type(scope) == "string" and scope ~= "" then
			return source .. "." .. scope
		end
		return source
	end
end

if SourceHelpers.qualifiedSource == nil then
	function SourceHelpers.qualifiedSource(record)
		return SourceHelpers.record.qualifiedSource(record)
	end
end

return SourceHelpers
