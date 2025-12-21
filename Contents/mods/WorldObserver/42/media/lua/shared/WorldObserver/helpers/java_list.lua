-- helpers/java_list.lua -- defensive helpers for Java-backed lists/arrays.
local moduleName = ...
local JavaList = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		JavaList = loaded
	else
		package.loaded[moduleName] = JavaList
	end
end
JavaList._internal = JavaList._internal or {}

local function resolveMethod(list, methodName)
	if list == nil then
		return nil
	end
	local listType = type(list)
	if listType ~= "table" and listType ~= "userdata" then
		-- Some engine values stringify like "[]" but are not indexable in Kahlua.
		return nil
	end
	-- Kahlua can throw from tostring() for some engine-backed values; guard it.
	local okStr, listStr = pcall(tostring, list)
	if not okStr or type(listStr) ~= "string" then
		return nil
	end
	if listStr == "[]" then
		-- Empty or non-indexable engine list; avoid Kahlua "non-table" index errors.
		return nil
	end
	-- Kahlua can throw when indexing Java-backed lists; guard with pcall.
	local ok, value = pcall(function()
		return list[methodName]
	end)
	if ok and type(value) == "function" then
		return value
	end
	return nil
end

-- Patch seam: only define when nil so mods can override by reassigning JavaList.size.
if JavaList.size == nil then
	--- @param list any
	--- @return number
	function JavaList.size(list)
		if list == nil then
			return 0
		end
		local sizeFn = resolveMethod(list, "size")
		if sizeFn ~= nil then
			local ok, value = pcall(sizeFn, list)
			if ok and type(value) == "number" then
				return value
			end
		end
		sizeFn = resolveMethod(list, "getSize")
		if sizeFn ~= nil then
			local ok, value = pcall(sizeFn, list)
			if ok and type(value) == "number" then
				return value
			end
		end
		if type(list) == "table" then
			local maxIndex = 0
			for key in pairs(list) do
				if type(key) == "number" and key > maxIndex then
					maxIndex = key
				end
			end
			return maxIndex
		end
		return 0
	end
end

-- Patch seam: only define when nil so mods can override by reassigning JavaList.get.
if JavaList.get == nil then
	--- @param list any
	--- @param index1 number
	--- @return any
	function JavaList.get(list, index1)
		if list == nil then
			return nil
		end
		local getFn = resolveMethod(list, "get")
		if getFn ~= nil then
			local ok, value = pcall(getFn, list, index1 - 1)
			if ok then
				return value
			end
		end
		if type(list) == "table" then
			return list[index1]
		end
		return nil
	end
end

JavaList._internal.resolveMethod = resolveMethod

return JavaList
