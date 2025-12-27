-- helpers/room.lua -- room helper set providing small value-add filters for room observations.
local Log = require("LQR/util/log").withTag("WO.HELPER.room")
local JavaList = require("WorldObserver/helpers/java_list")
local SafeCall = require("WorldObserver/helpers/safe_call")
local SquareHelpers = require("WorldObserver/helpers/square")
local moduleName = ...
local RoomHelpers = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		RoomHelpers = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = RoomHelpers
	end
end

RoomHelpers.record = RoomHelpers.record or {}
RoomHelpers.stream = RoomHelpers.stream or {}

local function roomField(observation, fieldName)
	local record = observation[fieldName]
	if record == nil then
		if _G.WORLDOBSERVER_HEADLESS ~= true then
			Log:warn("room helper called without field '%s' on observation", tostring(fieldName))
		end
		return nil
	end
	return record
end

-- Stream sugar: apply a predicate to the room record directly.
if RoomHelpers.roomFilter == nil then
	function RoomHelpers.roomFilter(stream, fieldName, predicate)
		assert(type(predicate) == "function", "roomFilter predicate must be a function")
		local target = fieldName or "room"
		return stream:filter(function(observation)
			local roomRecord = roomField(observation, target)
			return predicate(roomRecord, observation) == true
		end)
	end
end
if RoomHelpers.stream.roomFilter == nil then
	function RoomHelpers.stream.roomFilter(stream, fieldName, ...)
		return RoomHelpers.roomFilter(stream, fieldName, ...)
	end
end

local function roomTypeIs(roomRecord, wanted)
	if type(roomRecord) ~= "table" then
		return false
	end
	if type(wanted) ~= "string" or wanted == "" then
		return false
	end
	return tostring(roomRecord.name) == wanted
end

if RoomHelpers.record.roomTypeIs == nil then
	RoomHelpers.record.roomTypeIs = roomTypeIs
end

if RoomHelpers.roomTypeIs == nil then
	function RoomHelpers.roomTypeIs(stream, fieldName, wanted)
		local target = fieldName or "room"
		return stream:filter(function(observation)
			local roomRecord = roomField(observation, target)
			return RoomHelpers.record.roomTypeIs(roomRecord, wanted)
		end)
	end
end
if RoomHelpers.stream.roomTypeIs == nil then
	function RoomHelpers.stream.roomTypeIs(stream, fieldName, ...)
		return RoomHelpers.roomTypeIs(stream, fieldName, ...)
	end
end

local function roomHasWater(roomRecord)
	return type(roomRecord) == "table" and roomRecord.hasWater == true
end

if RoomHelpers.record.roomHasWater == nil then
	RoomHelpers.record.roomHasWater = roomHasWater
end

if RoomHelpers.roomHasWater == nil then
	function RoomHelpers.roomHasWater(stream, fieldName, ...)
		local target = fieldName or "room"
		return stream:filter(function(observation)
			local roomRecord = roomField(observation, target)
			return RoomHelpers.record.roomHasWater(roomRecord)
		end)
	end
end
if RoomHelpers.stream.roomHasWater == nil then
	function RoomHelpers.stream.roomHasWater(stream, fieldName, ...)
		return RoomHelpers.roomHasWater(stream, fieldName, ...)
	end
end

local function squareCoord(square, methodName, fieldName)
	local value = SafeCall.safeCall(square, methodName)
	if type(value) == "number" then
		return value
	end
	value = square and square[fieldName]
	if type(value) == "number" then
		return value
	end
	return nil
end

if RoomHelpers.record.roomLocationFromIsoRoom == nil then
	--- Return a join-ready room location derived from the first room square.
	--- @param room any
	--- @return string|nil
	function RoomHelpers.record.roomLocationFromIsoRoom(room)
		if room == nil then
			return nil
		end
		local squares = SafeCall.safeCall(room, "getSquares")
		if squares == nil then
			return nil
		end
		local firstSquare = JavaList.get(squares, 1)
		if firstSquare == nil then
			return nil
		end
		local x = squareCoord(firstSquare, "getX", "x")
		local y = squareCoord(firstSquare, "getY", "y")
		local z = squareCoord(firstSquare, "getZ", "z")
		if x == nil or y == nil then
			return nil
		end
		if type(z) ~= "number" then
			z = 0
		end
		return SquareHelpers.record.tileLocationFromCoords(x, y, z)
	end
end

if RoomHelpers.record.buildingIdFromIsoBuilding == nil then
	--- Best-effort building id for join-ready references.
	--- @param building any
	--- @return any
	function RoomHelpers.record.buildingIdFromIsoBuilding(building)
		if building == nil then
			return nil
		end
		local id = SafeCall.safeCall(building, "getID")
		if id ~= nil then
			return id
		end
		return SafeCall.safeCall(building, "getId")
	end
end

return RoomHelpers
