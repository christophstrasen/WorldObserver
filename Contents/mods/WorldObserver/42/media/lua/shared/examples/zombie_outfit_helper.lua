-- zombie_outfit_helper.lua -- example helper set that prints zombie outfits.
local moduleName = ...
local ZombieOutfitHelpers = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		ZombieOutfitHelpers = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = ZombieOutfitHelpers
	end
end

ZombieOutfitHelpers.stream = ZombieOutfitHelpers.stream or {}

if ZombieOutfitHelpers.stream.outfit_print == nil then
	function ZombieOutfitHelpers.stream.outfit_print(stream, fieldName)
		local target = fieldName or "zombie"
		return stream:filter(function(observation)
			local record = observation[target]
			if type(record) ~= "table" then
				return false
			end
			local outfitName = record.outfitName
			if outfitName == nil or outfitName == "" then
				outfitName = "unknown"
			end
			print(("[WO] zombie id=%s outfit=%s"):format(tostring(record.zombieId), tostring(outfitName)))
			return true
		end)
	end
end

return ZombieOutfitHelpers
