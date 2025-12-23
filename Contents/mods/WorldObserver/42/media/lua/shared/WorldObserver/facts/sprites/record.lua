-- facts/sprites/record.lua -- builds stable sprite fact records from IsoObject instances.
local Log = require("LQR/util/log").withTag("WO.FACTS.sprites")
local Time = require("WorldObserver/helpers/time")
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
Record._extensions.spriteRecord = Record._extensions.spriteRecord or { order = {}, orderCount = 0, byId = {} }

if Record.registerSpriteRecordExtender == nil then
	--- Register an extender that can add extra fields to each sprite record.
	--- Extenders run after the base record has been constructed.
	--- @param id string
	--- @param fn fun(record: table, isoObject: any, source: string|nil, opts: table|nil)
	--- @return boolean ok
	--- @return string|nil err
	function Record.registerSpriteRecordExtender(id, fn)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		if type(fn) ~= "function" then
			return false, "badFn"
		end
		local ext = Record._extensions.spriteRecord
		if ext.byId[id] == nil then
			ext.orderCount = (ext.orderCount or 0) + 1
			ext.order[ext.orderCount] = id
		end
		ext.byId[id] = fn
		return true
	end
end

if Record.unregisterSpriteRecordExtender == nil then
	--- Unregister a previously registered sprite record extender.
	--- @param id string
	function Record.unregisterSpriteRecordExtender(id)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		local ext = Record._extensions.spriteRecord
		ext.byId[id] = nil
		return true
	end
end

if Record.applySpriteRecordExtenders == nil then
	--- Apply all registered sprite record extenders to a record.
	--- @param record table
	--- @param isoObject any
	--- @param source string|nil
	--- @param opts table|nil
	function Record.applySpriteRecordExtenders(record, isoObject, source, opts)
		local ext = Record._extensions and Record._extensions.spriteRecord or nil
		if type(record) ~= "table" or not ext then
			return
		end
		for i = 1, (ext.orderCount or 0) do
			local id = ext.order[i]
			local fn = id and ext.byId[id] or nil
			if fn then
				local ok, err = pcall(fn, record, isoObject, source, opts)
				if not ok then
					Log:warn("Sprite record extender failed id=%s err=%s", tostring(id), tostring(err))
				end
			end
		end
	end
end

local function nowMillis()
	return Time.gameMillis() or math.floor(os.time() * 1000)
end

local function coordOf(square, getterName)
	if square and type(square[getterName]) == "function" then
		local ok, value = pcall(square[getterName], square)
		if ok then
			return value
		end
	end
	return nil
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

if Record.makeSpriteKey == nil then
	--- Build a stable key for a sprite observation.
	--- @param spriteName string
	--- @param spriteId number|string|nil
	--- @param x number
	--- @param y number
	--- @param z number
	--- @param objectIndex number|string|nil
	--- @return string|nil key
	function Record.makeSpriteKey(spriteName, spriteId, x, y, z, objectIndex)
		if type(spriteName) ~= "string" or spriteName == "" then
			return nil
		end
		if x == nil or y == nil or z == nil then
			return nil
		end
		if objectIndex == nil then
			return nil
		end
		local idPart = spriteId ~= nil and tostring(spriteId) or "nil"
		return tostring(spriteName)
			.. "ID"
			.. idPart
			.. "x"
			.. tostring(x)
			.. "y"
			.. tostring(y)
			.. "z"
			.. tostring(z)
			.. "i"
			.. tostring(objectIndex)
	end
end

local function resolveSpriteInfo(isoObject, opts)
	local sprite = opts and opts.sprite or nil
	if sprite == nil then
		sprite = SafeCall.safeCall(isoObject, "getSprite")
	end
	local spriteName = opts and opts.spriteName or SafeCall.safeCall(sprite, "getName")
	local spriteId = opts and opts.spriteId or SafeCall.safeCall(sprite, "getID")
	return sprite, spriteName, spriteId
end

if Record.makeSpriteRecord == nil then
	--- Build a sprite fact record.
	--- @param isoObject any
	--- @param square any|nil
	--- @param source string|nil
	--- @param opts table|nil
	--- @return table|nil record
	function Record.makeSpriteRecord(isoObject, square, source, opts)
		if not isoObject then
			return nil
		end
		opts = opts or {}
		local ts = opts.nowMs or nowMillis()

		if square == nil then
			square = opts.square
			if square == nil then
				square = SafeCall.safeCall(isoObject, "getSquare") or SafeCall.safeCall(isoObject, "getCurrentSquare")
			end
		end

		local x = coordOf(square, "getX")
		local y = coordOf(square, "getY")
		local z = coordOf(square, "getZ") or 0
		if x == nil or y == nil then
			if _G.WORLDOBSERVER_HEADLESS ~= true then
				Log:warn("Skipped sprite record: missing coordinates")
			end
			return nil
		end

		local sprite, spriteName, spriteId = resolveSpriteInfo(isoObject, opts)
		if spriteName == nil then
			if _G.WORLDOBSERVER_HEADLESS ~= true then
				Log:warn("Skipped sprite record: missing sprite name")
			end
			return nil
		end
		if spriteId == nil then
			if _G.WORLDOBSERVER_HEADLESS ~= true then
				Log:warn("Skipped sprite record: missing sprite id")
			end
			return nil
		end

		local objectIndex = SafeCall.safeCall(isoObject, "getObjectIndex")
		if objectIndex == nil then
			objectIndex = 0
		end

		local key = Record.makeSpriteKey(spriteName, spriteId, x, y, z, objectIndex)
		if key == nil then
			if _G.WORLDOBSERVER_HEADLESS ~= true then
				Log:warn("Skipped sprite record: missing key parts")
			end
			return nil
		end

		local record = {
			spriteKey = key,
			spriteName = spriteName,
			spriteId = spriteId,
			x = x,
			y = y,
			z = z,
			tileLocation = SquareHelpers.record.tileLocationFromCoords(x, y, z),
			squareId = deriveSquareId(square, x, y, z),
			objectIndex = objectIndex,
			sourceTime = ts,
			source = source,
		}

		-- Always retain references (best-effort) for downstream consumers.
		record.IsoObject = isoObject
		record.IsoGridSquare = square
		if SquareHelpers.record and SquareHelpers.record.getIsoGridSquare then
			SquareHelpers.record.getIsoGridSquare(record, opts)
		end

		Record.applySpriteRecordExtenders(record, isoObject, source, opts)
		return record
	end
end

return Record
