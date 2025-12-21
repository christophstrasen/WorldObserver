-- facts/targets.lua -- resolve interest targets (player, etc.) from small target specs.
--
-- Why this exists:
-- - Multiple fact plans need to resolve `target = { player = { id = 0 } }` into an engine player object.
-- - Keeping this in one place avoids subtle drift (id=0 handling, pcall guards) across fact plans.
-- - This module is patchable-by-default so other mods can override target resolution rules if needed.

local moduleName = ...
local Targets = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Targets = loaded
	else
		package.loaded[moduleName] = Targets
	end
end

--- Resolve an engine player instance from a normalized target.
--- @param target table|nil { kind = "player", id = number }
--- @return any|nil player
if Targets.resolvePlayer == nil then
	function Targets.resolvePlayer(target)
		if type(target) ~= "table" or target.kind ~= "player" then
			return nil
		end
		local id = tonumber(target.id) or 0

		local getSpecificPlayer = _G.getSpecificPlayer
		if type(getSpecificPlayer) == "function" then
			local ok, player = pcall(getSpecificPlayer, id)
			if ok and player ~= nil then
				return player
			end
		end

		-- Convention: singleplayer local player is id=0.
		if id == 0 then
			local getPlayer = _G.getPlayer
			if type(getPlayer) == "function" then
				local ok, player = pcall(getPlayer)
				if ok and player ~= nil then
					return player
				end
			end
		end
		return nil
	end
end

return Targets
