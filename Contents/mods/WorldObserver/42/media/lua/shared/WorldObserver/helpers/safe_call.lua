-- helpers/safe_call.lua -- safe pcall wrapper for engine method invocations.
local okBase, BaseSafeCall = pcall(require, "DREAMBase/pz/safe_call")
if okBase and type(BaseSafeCall) == "table" then
	return BaseSafeCall
end

local moduleName = ...
local SafeCall = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		SafeCall = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = SafeCall
	end
end
SafeCall._internal = SafeCall._internal or {}

-- Patch seam: only define when nil so mods can override by reassigning SafeCall.safeCall.
if SafeCall.safeCall == nil then
	function SafeCall.safeCall(obj, methodName, ...)
		if obj and type(obj[methodName]) == "function" then
			local ok, value = pcall(obj[methodName], obj, ...)
			if ok then
				return value
			end
		end
		return nil
	end
end

SafeCall._internal.safeCall = SafeCall.safeCall

return SafeCall
