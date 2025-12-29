-- facts/players/record.lua -- builds stable player fact records from IsoPlayer objects.
local Log = require("LQR/util/log").withTag("WO.FACTS.players")
local SafeCall = require("WorldObserver/helpers/safe_call")
local SquareHelpers = require("WorldObserver/helpers/square")
local RoomHelpers = require("WorldObserver/helpers/room")

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
Record._extensions.playerRecord = Record._extensions.playerRecord or { order = {}, orderCount = 0, byId = {} }
Record._internal.playerRoomCache = Record._internal.playerRoomCache or {}

if Record.registerPlayerRecordExtender == nil then
	--- Register an extender that can add extra fields to each player record.
	--- Extenders run after the base record has been constructed.
	--- @param id string
	--- @param fn fun(record: table, player: any, source: string|nil, opts: table|nil)
	--- @return boolean ok
	--- @return string|nil err
	function Record.registerPlayerRecordExtender(id, fn)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		if type(fn) ~= "function" then
			return false, "badFn"
		end
		local ext = Record._extensions.playerRecord
		if ext.byId[id] == nil then
			ext.orderCount = (ext.orderCount or 0) + 1
			ext.order[ext.orderCount] = id
		end
		ext.byId[id] = fn
		return true
	end
end

if Record.unregisterPlayerRecordExtender == nil then
	--- Unregister a previously registered player record extender.
	--- @param id string
	function Record.unregisterPlayerRecordExtender(id)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		local ext = Record._extensions.playerRecord
		ext.byId[id] = nil
		return true
	end
end

if Record.applyPlayerRecordExtenders == nil then
	--- Apply all registered player record extenders to a record.
	--- @param record table
	--- @param player any
	--- @param source string|nil
	--- @param opts table|nil
	function Record.applyPlayerRecordExtenders(record, player, source, opts)
		local ext = Record._extensions and Record._extensions.playerRecord or nil
		if type(record) ~= "table" or not ext then
			return
		end
		for i = 1, (ext.orderCount or 0) do
			local id = ext.order[i]
			local fn = id and ext.byId[id] or nil
			if fn then
				local ok, err = pcall(fn, record, player, source, opts)
				if not ok then
					Log:warn("Player record extender failed id=%s err=%s", tostring(id), tostring(err))
				end
			end
		end
	end
end

local function resolveIdKey(prefix, value)
	if value == nil then
		return nil
	end
	if type(value) == "string" then
		if value == "" then
			return nil
		end
		return prefix .. value
	end
	if type(value) == "number" then
		return prefix .. tostring(value)
	end
	return nil
end

local function playerKeyFromIds(steamId, onlineId, playerId, playerNum)
	return resolveIdKey("steamId", steamId)
		or resolveIdKey("onlineId", onlineId)
		or resolveIdKey("playerId", playerId)
		or resolveIdKey("playerNum", playerNum)
end

local function resolveTileFromSquare(square)
	if square == nil then
		return nil, nil, nil
	end
	local tileX = SafeCall.safeCall(square, "getX")
	local tileY = SafeCall.safeCall(square, "getY")
	local tileZ = SafeCall.safeCall(square, "getZ")
	if tileX == nil or tileY == nil then
		return nil, nil, nil
	end
	if type(tileZ) ~= "number" then
		tileZ = 0
	end
	return math.floor(tileX), math.floor(tileY), math.floor(tileZ)
end

local function resolveTileFromPlayer(player)
	if player == nil then
		return nil, nil, nil
	end
	local x = SafeCall.safeCall(player, "getX")
	local y = SafeCall.safeCall(player, "getY")
	local z = SafeCall.safeCall(player, "getZ")
	if x == nil or y == nil then
		return nil, nil, nil
	end
	if type(z) ~= "number" then
		z = 0
	end
	return math.floor(x), math.floor(y), math.floor(z)
end

local function resolveRoomLocation(playerKey, room)
	if room == nil then
		local cache = Record._internal.playerRoomCache
		local entry = cache and cache[playerKey]
		if entry then
			entry.roomRef = nil
			entry.roomLocation = nil
		end
		return nil
	end
	if playerKey ~= nil then
		local cache = Record._internal.playerRoomCache
		local entry = cache[playerKey]
		if entry and entry.roomRef == room then
			return entry.roomLocation
		end
		local location = RoomHelpers.record.roomLocationFromIsoRoom and RoomHelpers.record.roomLocationFromIsoRoom(room) or nil
		cache[playerKey] = { roomRef = room, roomLocation = location }
		return location
	end
	if RoomHelpers.record.roomLocationFromIsoRoom then
		return RoomHelpers.record.roomLocationFromIsoRoom(room)
	end
	return nil
end

local function resolveBuildingId(building)
	if RoomHelpers.record and RoomHelpers.record.buildingIdFromIsoBuilding then
		return RoomHelpers.record.buildingIdFromIsoBuilding(building)
	end
	if building == nil then
		return nil
	end
	local id = SafeCall.safeCall(building, "getID")
	if id ~= nil then
		return id
	end
	return SafeCall.safeCall(building, "getId")
end

if Record.makePlayerRecord == nil then
	--- Build a player fact record.
	--- @param player any
	--- @param source string|nil
	--- @param opts table|nil
	--- @return table|nil record
	function Record.makePlayerRecord(player, source, opts)
		if player == nil then
			return nil
		end
		opts = opts or {}

		local steamId = SafeCall.safeCall(player, "getSteamID")
		local onlineId = SafeCall.safeCall(player, "getOnlineID")
		local playerId = SafeCall.safeCall(player, "getID")
		local playerNum = SafeCall.safeCall(player, "getPlayerNum")
		local playerKey = playerKeyFromIds(steamId, onlineId, playerId, playerNum)
		if playerKey == nil then
			Log:warn("Skipped player record: missing player identifiers")
			return nil
		end

		local square = SafeCall.safeCall(player, "getCurrentSquare")
		local tileX, tileY, tileZ = resolveTileFromSquare(square)
		if tileX == nil or tileY == nil then
			tileX, tileY, tileZ = resolveTileFromPlayer(player)
		end
		if tileX == nil or tileY == nil then
			Log:warn("Skipped player record: missing coordinates")
			return nil
		end

		local room = square and SafeCall.safeCall(square, "getRoom") or nil
		local building = SafeCall.safeCall(player, "getBuilding")
		if building == nil and room ~= nil then
			building = SafeCall.safeCall(room, "getBuilding")
		end

		local record = {
			steamId = steamId,
			onlineId = onlineId,
			playerId = playerId,
			playerNum = playerNum,
			playerKey = playerKey,
			woKey = playerKey,
			tileX = tileX,
			tileY = tileY,
			tileZ = tileZ,
			x = tileX,
			y = tileY,
			z = tileZ,
			tileLocation = SquareHelpers.record.tileLocationFromCoords(tileX, tileY, tileZ),
			roomLocation = resolveRoomLocation(playerKey, room),
			roomName = room and SafeCall.safeCall(room, "getName") or nil,
			buildingId = resolveBuildingId(building),
			username = SafeCall.safeCall(player, "getUsername"),
			displayName = SafeCall.safeCall(player, "getDisplayName"),
			accessLevel = SafeCall.safeCall(player, "getAccessLevel"),
			hoursSurvived = SafeCall.safeCall(player, "getHoursSurvived"),
			isLocalPlayer = SafeCall.safeCall(player, "isLocalPlayer") == true,
			isAiming = SafeCall.safeCall(player, "isAiming") == true,
			IsoPlayer = player,
			IsoGridSquare = square,
			IsoRoom = room,
			IsoBuilding = building,
			source = source,
			scope = opts.scope,
		}

		Record.applyPlayerRecordExtenders(record, player, source, opts)
		return record
	end
end

return Record
