-- helpers/room.lua -- room helper set providing small value-add filters for room observations.
local Log = require("DREAMBase/log").withTag("WO.HELPER.room")
local JavaList = require("DREAMBase/pz/java_list")
local SafeCall = require("DREAMBase/pz/safe_call")
local RecordWrap = require("WorldObserver/helpers/record_wrap")
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

RoomHelpers._internal = RoomHelpers._internal or {}
RoomHelpers._internal.recordWrap = RoomHelpers._internal.recordWrap or RecordWrap.ensureState()
local recordWrap = RoomHelpers._internal.recordWrap

if recordWrap.methods.nameIs == nil then
	function recordWrap.methods:nameIs(...)
		local fn = RoomHelpers.record and RoomHelpers.record.roomTypeIs
		if type(fn) == "function" then
			return fn(self, ...)
		end
		return false
	end
end

if recordWrap.methods.getRoomDef == nil then
	function recordWrap.methods:getRoomDef(opts)
		local fn = RoomHelpers.record and RoomHelpers.record.getRoomDef
		if type(fn) == "function" then
			return fn(self, opts)
		end
		return nil
	end
end

if RoomHelpers.wrap == nil then
	--- Decorate a room record in-place to expose a small method surface via metatable.
	--- Returns the same table on success; refuses if the record already has a different metatable.
	--- @param record table
	--- @return table|nil wrappedRecord
	--- @return string|nil err
	function RoomHelpers:wrap(record, opts)
		return RecordWrap.wrap(record, recordWrap, {
			family = "room",
			log = Log,
			headless = type(opts) == "table" and opts.headless or nil,
			methodNames = { "nameIs", "getRoomDef" },
		})
	end
end

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

local function parseTileLocation(tileLocation)
	if type(tileLocation) ~= "string" then
		return nil
	end
	local x, y, z = tileLocation:match("^x(-?%d+)y(-?%d+)z(-?%d+)$")
	if not x then
		return nil
	end
	return tonumber(x), tonumber(y), tonumber(z)
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

	if RoomHelpers.roomHasWater == nil then
		function RoomHelpers.roomHasWater(stream, fieldName, ...)
			local target = fieldName or "room"
			return stream:filter(function(observation)
				local roomRecord = roomField(observation, target)
				return type(roomRecord) == "table" and roomRecord.hasWater == true
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

if RoomHelpers.record.getRoomDef == nil then
	--- Return a RoomDef from a room record (or roomLocation), with best-effort hydration.
	--- @param roomRecordOrLocation table|string
	--- @param opts table|nil
	--- @return any|nil
	function RoomHelpers.record.getRoomDef(roomRecordOrLocation, opts)
		if type(roomRecordOrLocation) == "table" then
			if roomRecordOrLocation.RoomDef ~= nil then
				return roomRecordOrLocation.RoomDef
			end
			local isoRoom = roomRecordOrLocation.IsoRoom
			if isoRoom ~= nil then
				local direct = SafeCall.safeCall(isoRoom, "getRoomDef")
				if direct ~= nil then
					return direct
				end
			end
		end

		local roomDefId = type(roomRecordOrLocation) == "table" and roomRecordOrLocation.roomDefId or nil
		local roomLocation = nil
		if type(roomRecordOrLocation) == "table" then
			roomLocation = roomRecordOrLocation.roomLocation
				or roomRecordOrLocation.roomId
				or roomRecordOrLocation.tileLocation
		elseif type(roomRecordOrLocation) == "string" then
			roomLocation = roomRecordOrLocation
		end

		local x, y, z = parseTileLocation(roomLocation)
		if x == nil or y == nil or z == nil then
			if type(roomDefId) == "number"
				and roomDefId % 1 == 0
				and math.abs(roomDefId) <= 9007199254740991
			then
				local metaGrid = nil
				if type(opts) == "table" and opts.metaGrid ~= nil then
					metaGrid = opts.metaGrid
				else
					local getWorld = _G.getWorld
					if type(getWorld) == "function" then
						local okWorld, world = pcall(getWorld)
						if okWorld and world ~= nil then
							metaGrid = SafeCall.safeCall(world, "getMetaGrid")
						end
					end
				end
				return metaGrid and SafeCall.safeCall(metaGrid, "getRoomDefByID", roomDefId) or nil
			end
			return nil
		end

		local world = nil
		if type(opts) == "table" and opts.world ~= nil then
			world = opts.world
		else
			local getWorld = _G.getWorld
			if type(getWorld) == "function" then
				local okWorld, value = pcall(getWorld)
				if okWorld then
					world = value
				end
			end
		end

		if world == nil then
			return nil
		end

		-- Prefer metaGrid lookup by coords.
		-- WHY: RoomDef IDs are Java `long`s and can exceed Lua number precision, so getRoomDefByID can be
		-- unreliable in Lua when the ID is stored/printed in scientific notation.
		local metaGrid
		if type(opts) == "table" and opts.metaGrid ~= nil then
			metaGrid = opts.metaGrid
		else
			metaGrid = SafeCall.safeCall(world, "getMetaGrid")
		end

		local roomDef = metaGrid and SafeCall.safeCall(metaGrid, "getRoomAt", x, y, z) or nil
		if roomDef ~= nil then
			return roomDef
		end

		-- Fall back to resolving a live square (requires the chunk to be loaded).
		local cell
		if type(opts) == "table" and opts.cell and type(opts.cell.getGridSquare) == "function" then
			cell = opts.cell
		else
			cell = SafeCall.safeCall(world, "getCell")
		end
		local square = cell and SafeCall.safeCall(cell, "getGridSquare", x, y, z) or nil
		local room = square and SafeCall.safeCall(square, "getRoom") or nil
		roomDef = room and SafeCall.safeCall(room, "getRoomDef") or nil
		if roomDef ~= nil then
			return roomDef
		end

		-- Last resort: lookup by ID if it is safely representable (<= 2^53-1).
		if type(roomDefId) == "number" and roomDefId % 1 == 0 and math.abs(roomDefId) <= 9007199254740991 then
			return metaGrid and SafeCall.safeCall(metaGrid, "getRoomDefByID", roomDefId) or nil
		end
		return nil
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
