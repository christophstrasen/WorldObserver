-- helpers/zombie.lua -- zombie helper set providing small value-add filters and rehydration helpers.
local Log = require("LQR/util/log").withTag("WO.HELPER.zombie")
local Highlight = require("WorldObserver/helpers/highlight")
local moduleName = ...
local ZombieHelpers = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		ZombieHelpers = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = ZombieHelpers
	end
end

ZombieHelpers.record = ZombieHelpers.record or {}
ZombieHelpers.stream = ZombieHelpers.stream or {}

local function zombieField(observation, fieldName)
	local zombieRecord = observation[fieldName]
	if zombieRecord == nil then
		if _G.WORLDOBSERVER_HEADLESS ~= true then
			Log:warn("zombie helper called without field '%s' on observation", tostring(fieldName))
		end
		return nil
	end
	return zombieRecord
end

local function resolveZombieList()
	local getCell = _G.getCell
	if type(getCell) ~= "function" then
		return nil
	end
	local okCell, cell = pcall(getCell)
	if not okCell or not cell or type(cell.getZombieList) ~= "function" then
		return nil
	end
	local okList, list = pcall(cell.getZombieList, cell)
	if not okList then
		return nil
	end
	return list
end

local function rehydrateZombie(record)
	if type(record) ~= "table" then
		return nil
	end
	if record.IsoZombie then
		return record.IsoZombie
	end
	local targetId = record.zombieId
	if targetId == nil then
		return nil
	end

	local list = resolveZombieList()
	if not list or type(list.size) ~= "function" or type(list.get) ~= "function" then
		return nil
	end

	local okSize, size = pcall(list.size, list)
	if not okSize or type(size) ~= "number" then
		return nil
	end
	for i = 0, size - 1 do
		local okZombie, zombie = pcall(list.get, list, i)
		if okZombie and zombie and type(zombie.getID) == "function" then
			local okId, zid = pcall(zombie.getID, zombie)
			if okId and zid == targetId then
				return zombie
			end
		end
	end
	return nil
end

if ZombieHelpers.record.getIsoZombie == nil then
	--- Best-effort: return the live IsoZombie for a record.
	function ZombieHelpers.record.getIsoZombie(record)
		return rehydrateZombie(record)
	end
end

local function zombieHasTarget(zombieRecord)
	return type(zombieRecord) == "table" and zombieRecord.hasTarget == true
end

if ZombieHelpers.record.zombieHasTarget == nil then
	ZombieHelpers.record.zombieHasTarget = zombieHasTarget
end

-- Stream sugar: apply a predicate to the zombie record directly.
-- This avoids leaking LQR schema names (e.g. "ZombieObservation") into mod code.
if ZombieHelpers.zombieFilter == nil then
	function ZombieHelpers.zombieFilter(stream, fieldName, predicate)
		assert(type(predicate) == "function", "zombieFilter predicate must be a function")
		local target = fieldName or "zombie"
		return stream:filter(function(observation)
			local zombieRecord = zombieField(observation, target)
			return predicate(zombieRecord, observation) == true
		end)
	end
end
if ZombieHelpers.stream.zombieFilter == nil then
	function ZombieHelpers.stream.zombieFilter(stream, fieldName, ...)
		return ZombieHelpers.zombieFilter(stream, fieldName, ...)
	end
end

-- Highlight a zombie for a duration using the engine highlight APIs.
if ZombieHelpers.highlight == nil then
	function ZombieHelpers.highlight(zombieOrRecord, durationMs, opts)
		opts = opts or {}
		if type(durationMs) == "number" and opts.durationMs == nil then
			opts.durationMs = durationMs
		end

		local target = nil
		if type(zombieOrRecord) == "userdata" or type(zombieOrRecord) == "table" then
			if type(zombieOrRecord.getID) == "function" then
				target = zombieOrRecord
			elseif type(zombieOrRecord) == "table" then
				target = ZombieHelpers.record.getIsoZombie(zombieOrRecord)
			end
		end
		if target == nil then
			return nil, "noZombie"
		end

		opts.useOutline = true
		return Highlight.highlightTarget(target, opts)
	end
end

if ZombieHelpers.zombieHasTarget == nil then
	function ZombieHelpers.zombieHasTarget(stream, fieldName, ...)
		local target = fieldName or "zombie"
		return stream:filter(function(observation)
			local zombieRecord = zombieField(observation, target)
			return ZombieHelpers.record.zombieHasTarget(zombieRecord)
		end)
	end
end
if ZombieHelpers.stream.zombieHasTarget == nil then
	function ZombieHelpers.stream.zombieHasTarget(stream, fieldName, ...)
		return ZombieHelpers.zombieHasTarget(stream, fieldName, ...)
	end
end

return ZombieHelpers
