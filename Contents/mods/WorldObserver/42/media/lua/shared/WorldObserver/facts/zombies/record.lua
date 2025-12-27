-- facts/zombies/record.lua -- builds stable zombie fact records from IsoZombie objects.
local Log = require("LQR/util/log").withTag("WO.FACTS.zombies")
local SafeCall = require("WorldObserver/helpers/safe_call")
local SquareHelpers = require("WorldObserver/helpers/square")

local moduleName = ...
local Record = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Record = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Record
	end
end
Record._internal = Record._internal or {}
Record._extensions = Record._extensions or {}
Record._extensions.zombieRecord = Record._extensions.zombieRecord or { order = {}, orderCount = 0, byId = {} }

if Record.registerZombieRecordExtender == nil then
	--- Register an extender that can add extra fields to each zombie record.
	--- Extenders run after the base record has been constructed.
	--- @param id string
	--- @param fn fun(record: table, zombie: any, source: string|nil, opts: table|nil)
	--- @return boolean ok
	--- @return string|nil err
	function Record.registerZombieRecordExtender(id, fn)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		if type(fn) ~= "function" then
			return false, "badFn"
		end
		local ext = Record._extensions.zombieRecord
		if ext.byId[id] == nil then
			ext.orderCount = (ext.orderCount or 0) + 1
			ext.order[ext.orderCount] = id
		end
		ext.byId[id] = fn
		return true
	end
end

if Record.unregisterZombieRecordExtender == nil then
	--- Unregister a previously registered zombie record extender.
	--- @param id string
	function Record.unregisterZombieRecordExtender(id)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		local ext = Record._extensions.zombieRecord
		ext.byId[id] = nil
		return true
	end
end

if Record.applyZombieRecordExtenders == nil then
	--- Apply all registered zombie record extenders to a record.
	--- @param record table
	--- @param zombie any
	--- @param source string|nil
	--- @param opts table|nil
	function Record.applyZombieRecordExtenders(record, zombie, source, opts)
		local ext = Record._extensions and Record._extensions.zombieRecord or nil
		if type(record) ~= "table" or not ext then
			return
		end
		for i = 1, (ext.orderCount or 0) do
			local id = ext.order[i]
			local fn = id and ext.byId[id] or nil
			if fn then
				local ok, err = pcall(fn, record, zombie, source, opts)
				if not ok then
					Log:warn("Zombie record extender failed id=%s err=%s", tostring(id), tostring(err))
				end
			end
		end
	end
end

local function deriveLocomotion(isCrawling, isRunning, isMoving)
	if isCrawling then
		return "crawler"
	end
	if isRunning then
		return "runner"
	end
	if isMoving then
		return "walker"
	end
	return "unknown"
end

local function deriveSquareId(square, x, y, z)
	if square and type(square.getID) == "function" then
		local ok, id = pcall(square.getID, square)
		if ok and id ~= nil then
			return id
		end
	end
	if x and y and z then
		return (z * 1e9) + (x * 1e4) + y
	end
	return nil
end

local function deriveTargetKind(target)
	if not target then
		return "unknown"
	end
	local instanceofFn = _G.instanceof
	if type(instanceofFn) ~= "function" then
		return "unknown"
	end
	if instanceofFn(target, "IsoPlayer") then
		return "player"
	end
	if instanceofFn(target, "IsoGameCharacter") then
		return "character"
	end
	if instanceofFn(target, "IsoObject") then
		return "object"
	end
	return "unknown"
end

local function deriveTargetId(target)
	if not target then
		return nil
	end
	if type(target.getID) == "function" then
		local ok, id = pcall(target.getID, target)
		if ok and id ~= nil then
			return id
		end
	end
	if type(target.getOnlineID) == "function" then
		local ok, id = pcall(target.getOnlineID, target)
		if ok and id ~= nil then
			return id
		end
	end
	return nil
end

if Record.makeZombieRecord == nil then
	--- Build a zombie fact record.
	--- @param zombie any
	--- @param source string|nil
	--- @param opts table|nil
	--- @return table|nil record
	function Record.makeZombieRecord(zombie, source, opts)
		if not zombie then
			return nil
		end
		opts = opts or {}

		local x = SafeCall.safeCall(zombie, "getX")
		local y = SafeCall.safeCall(zombie, "getY")
		local z = SafeCall.safeCall(zombie, "getZ") or 0
		if x == nil or y == nil then
			Log:warn("Skipped zombie record: missing coordinates")
			return nil
		end
		local tileX = math.floor(x)
		local tileY = math.floor(y)
		local tileZ = math.floor(z)

		local square = SafeCall.safeCall(zombie, "getCurrentSquare")
		local squareId = deriveSquareId(square, tileX, tileY, tileZ)

		local zombieId = SafeCall.safeCall(zombie, "getID")
		local zombieOnlineId = SafeCall.safeCall(zombie, "getOnlineID") or 0

		local isMoving = SafeCall.safeCall(zombie, "isMoving") == true
		local isRunning = SafeCall.safeCall(zombie, "isRunning") == true
		local isCrawling = SafeCall.safeCall(zombie, "isCrawling") == true
		local locomotion = deriveLocomotion(isCrawling, isRunning, isMoving)

		local target = SafeCall.safeCall(zombie, "getTarget")
		local targetId = deriveTargetId(target)
		local targetKind = deriveTargetKind(target)
		local targetVisible = SafeCall.safeCall(zombie, "isTargetVisible") == true
		local targetSeenSeconds = SafeCall.safeCall(zombie, "getTargetSeenTime")

		local targetSquare = target and SafeCall.safeCall(target, "getCurrentSquare") or nil
		local outfitName = SafeCall.safeCall(zombie, "getOutfitName")

		local record = {
			zombieId = zombieId,
			zombieOnlineId = zombieOnlineId,
			x = x,
			y = y,
			z = z,
			tileX = tileX,
			tileY = tileY,
			tileZ = tileZ,
			tileLocation = SquareHelpers.record.tileLocationFromCoords(tileX, tileY, tileZ),
			squareId = squareId,
			isMoving = isMoving,
			isRunning = isRunning,
			isCrawling = isCrawling,
			speedType = zombie.speedType,
			locomotion = locomotion,
			hasTarget = target ~= nil,
			targetId = targetId,
			targetKind = targetKind,
			targetVisible = targetVisible,
			targetSeenSeconds = targetSeenSeconds,
			targetX = target and SafeCall.safeCall(target, "getX") or nil,
			targetY = target and SafeCall.safeCall(target, "getY") or nil,
			targetZ = target and SafeCall.safeCall(target, "getZ") or nil,
			targetSquareId = targetSquare
				and deriveSquareId(
					targetSquare,
					SafeCall.safeCall(targetSquare, "getX"),
					SafeCall.safeCall(targetSquare, "getY"),
					SafeCall.safeCall(targetSquare, "getZ")
				)
			or nil,
			outfitName = outfitName,
			source = source,
		}

		if opts.includeIsoZombie then
			record.IsoZombie = zombie
		end

		Record.applyZombieRecordExtenders(record, zombie, source, opts)
		return record
	end
end

Record._internal.deriveLocomotion = deriveLocomotion
Record._internal.deriveSquareId = deriveSquareId
Record._internal.deriveTargetKind = deriveTargetKind

return Record
