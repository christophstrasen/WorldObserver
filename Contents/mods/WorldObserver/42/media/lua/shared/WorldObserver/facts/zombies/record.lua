-- facts/zombies/record.lua -- builds stable zombie fact records from IsoZombie objects.
local Log = require("LQR/util/log").withTag("WO.FACTS.zombies")
local Time = require("WorldObserver/helpers/time")

local moduleName = ...
local Record = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Record = loaded
	else
		package.loaded[moduleName] = Record
	end
end
Record._internal = Record._internal or {}

local function nowMillis()
	return Time.gameMillis() or math.floor(os.time() * 1000)
end

local function safeCall(obj, methodName)
	if obj and type(obj[methodName]) == "function" then
		local ok, value = pcall(obj[methodName], obj)
		if ok then
			return value
		end
	end
	return nil
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

--- Build a zombie fact record.
--- @param zombie any
--- @param source string|nil
--- @param opts table|nil
--- @return table|nil record
if Record.makeZombieRecord == nil then
	function Record.makeZombieRecord(zombie, source, opts)
		if not zombie then
			return nil
		end
		opts = opts or {}
		local ts = opts.nowMs or nowMillis()

		local x = safeCall(zombie, "getX")
	local y = safeCall(zombie, "getY")
	local z = safeCall(zombie, "getZ") or 0
	if x == nil or y == nil then
		Log:warn("Skipped zombie record: missing coordinates")
		return nil
	end
	local tileX = math.floor(x)
	local tileY = math.floor(y)
	local tileZ = math.floor(z)

	local square = safeCall(zombie, "getCurrentSquare")
	local squareId = deriveSquareId(square, tileX, tileY, tileZ)

	local zombieId = safeCall(zombie, "getID")
	local zombieOnlineId = safeCall(zombie, "getOnlineID") or 0

		local isMoving = safeCall(zombie, "isMoving") == true
		local isRunning = safeCall(zombie, "isRunning") == true
		local isCrawling = safeCall(zombie, "isCrawling") == true
		local locomotion = deriveLocomotion(isCrawling, isRunning, isMoving)

		local target = safeCall(zombie, "getTarget")
		local targetId = deriveTargetId(target)
		local targetKind = deriveTargetKind(target)
		local targetVisible = safeCall(zombie, "isTargetVisible") == true
	local targetSeenSeconds = safeCall(zombie, "getTargetSeenTime")

	local targetSquare = target and safeCall(target, "getCurrentSquare") or nil

	local record = {
		zombieId = zombieId,
		zombieOnlineId = zombieOnlineId,
		x = x,
		y = y,
		z = z,
		tileX = tileX,
		tileY = tileY,
		tileZ = tileZ,
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
			targetX = target and safeCall(target, "getX") or nil,
			targetY = target and safeCall(target, "getY") or nil,
			targetZ = target and safeCall(target, "getZ") or nil,
			targetSquareId = targetSquare
				and deriveSquareId(
					targetSquare,
					safeCall(targetSquare, "getX"),
					safeCall(targetSquare, "getY"),
					safeCall(targetSquare, "getZ")
				)
			or nil,
			observedAtTimeMS = ts,
			sourceTime = ts,
			source = source,
		}

		if opts.includeIsoZombie then
			record.IsoZombie = zombie
		end

		return record
	end
end

Record._internal.nowMillis = nowMillis
Record._internal.deriveLocomotion = deriveLocomotion
Record._internal.deriveSquareId = deriveSquareId
Record._internal.deriveTargetKind = deriveTargetKind

return Record
