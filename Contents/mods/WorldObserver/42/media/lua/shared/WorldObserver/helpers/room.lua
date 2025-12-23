-- helpers/room.lua -- room helper set providing small value-add filters for room observations.
local Log = require("LQR/util/log").withTag("WO.HELPER.room")
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

return RoomHelpers
