-- facts/rooms/record.lua -- builds stable room fact records from IsoRoom objects.
local Log = require("LQR/util/log").withTag("WO.FACTS.rooms")
local JavaList = require("WorldObserver/helpers/java_list")
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
Record._extensions.roomRecord = Record._extensions.roomRecord or { order = {}, orderCount = 0, byId = {} }

if Record.registerRoomRecordExtender == nil then
	--- Register an extender that can add extra fields to each room record.
	--- Extenders run after the base record has been constructed.
	--- @param id string
	--- @param fn fun(record: table, room: any, source: string|nil, opts: table|nil)
	--- @return boolean ok
	--- @return string|nil err
	function Record.registerRoomRecordExtender(id, fn)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		if type(fn) ~= "function" then
			return false, "badFn"
		end
		local ext = Record._extensions.roomRecord
		if ext.byId[id] == nil then
			ext.orderCount = (ext.orderCount or 0) + 1
			ext.order[ext.orderCount] = id
		end
		ext.byId[id] = fn
		return true
	end
end

if Record.unregisterRoomRecordExtender == nil then
	--- Unregister a previously registered room record extender.
	--- @param id string
	function Record.unregisterRoomRecordExtender(id)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		local ext = Record._extensions.roomRecord
		ext.byId[id] = nil
		return true
	end
end

if Record.applyRoomRecordExtenders == nil then
	--- Apply all registered room record extenders to a record.
	--- @param record table
	--- @param room any
	--- @param source string|nil
	--- @param opts table|nil
	function Record.applyRoomRecordExtenders(record, room, source, opts)
		local ext = Record._extensions and Record._extensions.roomRecord or nil
		if type(record) ~= "table" or not ext then
			return
		end
		for i = 1, (ext.orderCount or 0) do
			local id = ext.order[i]
			local fn = id and ext.byId[id] or nil
			if fn then
				local ok, err = pcall(fn, record, room, source, opts)
				if not ok then
					Log:warn("Room record extender failed id=%s err=%s", tostring(id), tostring(err))
				end
			end
		end
	end
end

local function rectangleToTable(rect)
	if rect == nil then
		return nil
	end
	local x = SafeCall.safeCall(rect, "getX") or rect.x
	local y = SafeCall.safeCall(rect, "getY") or rect.y
	local w = SafeCall.safeCall(rect, "getWidth") or rect.width
	local h = SafeCall.safeCall(rect, "getHeight") or rect.height
	if type(x) ~= "number" or type(y) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then
		return nil
	end
	return { x = x, y = y, width = w, height = h }
end

local function deriveBuildingId(building)
	if building == nil then
		return nil
	end
	local id = SafeCall.safeCall(building, "getID")
	if id ~= nil then
		return id
	end
	id = SafeCall.safeCall(building, "getId")
	if id ~= nil then
		return id
	end
	id = building.ID or building.id
	if id ~= nil then
		return id
	end
	return tostring(building)
end

local function deriveRoomDefId(roomDef)
	if roomDef == nil then
		return nil
	end
	local id = SafeCall.safeCall(roomDef, "getID")
	if id ~= nil then
		return id
	end
	id = SafeCall.safeCall(roomDef, "getId")
	if id ~= nil then
		return id
	end
	return nil
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

local function deriveRoomIdFromFirstSquare(room)
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

local function deriveRoomId(room)
	return deriveRoomIdFromFirstSquare(room)
end

local function listSizeSafe(list, label, roomMeta)
	local ok, value = pcall(JavaList.size, list)
	if ok then
		return value
	end
	local meta = roomMeta or {}
	Log:warn(
		"Room list size failed; defaulting to 0 field=%s roomId=%s roomDefId=%s buildingId=%s name=%s listType=%s listValue=%s",
		tostring(label),
		tostring(meta.roomId),
		tostring(meta.roomDefId),
		tostring(meta.buildingId),
		tostring(meta.name),
		type(list),
		tostring(list)
	)
	return 0
end

if Record.makeRoomRecord == nil then
	--- Build a room fact record.
	--- Intent: keep this a small, stable snapshot (counts + ids) and avoid hard-coding engine-only fields.
	--- @param room any
	--- @param source string|nil
	--- @param opts table|nil
	--- @return table|nil record
	function Record.makeRoomRecord(room, source, opts)
		if room == nil then
			return nil
		end
		opts = opts or {}

		local roomDef = SafeCall.safeCall(room, "getRoomDef") or room.def
		local building = SafeCall.safeCall(room, "getBuilding")

		local roomDefId = deriveRoomDefId(roomDef)
		local buildingId = deriveBuildingId(building)
		-- Room IDs in Lua must be stable and non-colliding.
		-- We intentionally derive them from the first room square coordinates, not from engine IDs
		-- that may exceed Lua number precision.
		local tileLocation = deriveRoomIdFromFirstSquare(room)
		local roomId = tileLocation or deriveRoomId(room)
		if roomId == nil then
			Log:info("Skipped room record (missing roomId)")
			return nil
		end

		local name = SafeCall.safeCall(room, "getName") or (type(roomDef) == "table" and (roomDef.name or roomDef.type)) or nil
		if type(roomDef) == "userdata" and name == nil then
			name = SafeCall.safeCall(roomDef, "getName") or SafeCall.safeCall(roomDef, "getType")
		end
		local layer = SafeCall.safeCall(room, "getLayer") or room.layer
		local visited = SafeCall.safeCall(room, "isVisited") or room.visited
		if visited == nil then
			visited = SafeCall.safeCall(room, "getVisited")
		end
		local exists = SafeCall.safeCall(room, "isExists") or room.exists
		if exists == nil then
			exists = SafeCall.safeCall(room, "getExists")
		end

		local bounds = rectangleToTable(SafeCall.safeCall(room, "getBounds") or room.bounds)
		local rects = SafeCall.safeCall(room, "getRects") or room.rects
		local beds = room.beds
		local windows = SafeCall.safeCall(room, "getWindows")
		local waterSources = SafeCall.safeCall(room, "getWaterSources")

		local hasWater = SafeCall.safeCall(room, "hasWater")
		if hasWater == nil and type(roomDef) == "userdata" then
			hasWater = SafeCall.safeCall(roomDef, "hasWater")
		end

		local roomMeta = {
			roomId = roomId,
			tileLocation = tileLocation or roomId,
			roomDefId = roomDefId,
			buildingId = buildingId,
			name = name,
		}

		local record = {
			roomId = roomId,
			roomLocation = tileLocation or roomId,
			tileLocation = tileLocation or roomId,
			roomDefId = roomDefId,
			buildingId = buildingId,
			name = name,
			layer = layer,
			visited = visited == true,
			exists = exists ~= false,
			bounds = bounds,
			rectsCount = listSizeSafe(rects, "rects", roomMeta),
			bedsCount = listSizeSafe(beds, "beds", roomMeta),
			windowsCount = listSizeSafe(windows, "windows", roomMeta),
			waterSourcesCount = listSizeSafe(waterSources, "waterSources", roomMeta),
			hasWater = hasWater == true,
			source = source,
		}

		if opts.includeIsoRoom == true then
			record.IsoRoom = room
		end
		if opts.includeRoomDef == true then
			record.RoomDef = roomDef
		end
		if opts.includeBuilding == true then
			record.IsoBuilding = building
		end

		Record.applyRoomRecordExtenders(record, room, source, opts)
		return record
	end
end

Record._internal.safeCall = SafeCall.safeCall
Record._internal.listSize = JavaList.size
Record._internal.rectangleToTable = rectangleToTable
Record._internal.deriveBuildingId = deriveBuildingId
Record._internal.deriveRoomDefId = deriveRoomDefId
Record._internal.deriveRoomId = deriveRoomId
Record._internal.deriveRoomIdFromFirstSquare = deriveRoomIdFromFirstSquare

return Record
