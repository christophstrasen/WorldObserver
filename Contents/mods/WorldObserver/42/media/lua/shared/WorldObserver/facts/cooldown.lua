-- cooldown.lua -- tiny helper for per-key cooldown gating (shared by fact producers).
local moduleName = ...
local Cooldown = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Cooldown = loaded
	else
		package.loaded[moduleName] = Cooldown
	end
end

--- Decide whether a key is allowed to emit at `nowMs` given `cooldownMs`.
--- @param lastEmittedByKey table
--- @param key any
--- @param nowMs number|nil
--- @param cooldownMs number
--- @return boolean
if Cooldown.shouldEmit == nil then
	function Cooldown.shouldEmit(lastEmittedByKey, key, nowMs, cooldownMs)
		if cooldownMs <= 0 then
			return true
		end
		if not (lastEmittedByKey and key ~= nil and nowMs) then
			return true
		end
		local lastMs = lastEmittedByKey[key]
		return not (lastMs and (nowMs - lastMs) < cooldownMs)
	end
end

--- Record that a key emitted at `nowMs`.
--- @param lastEmittedByKey table
--- @param key any
--- @param nowMs number|nil
if Cooldown.markEmitted == nil then
	function Cooldown.markEmitted(lastEmittedByKey, key, nowMs)
		if not (lastEmittedByKey and key ~= nil and nowMs) then
			return
		end
		lastEmittedByKey[key] = nowMs
	end
end

return Cooldown
