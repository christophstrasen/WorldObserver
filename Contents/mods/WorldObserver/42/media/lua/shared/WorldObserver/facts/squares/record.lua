-- facts/squares/record.lua -- builds stable square fact records from IsoGridSquare objects.
local Log = require("LQR/util/log").withTag("WO.FACTS.squares")
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
Record._extensions.squareRecord = Record._extensions.squareRecord or { order = {}, orderCount = 0, byId = {} }

if Record.registerSquareRecordExtender == nil then
	--- Register an extender that can add extra fields to each square record.
	--- Extenders run after the base record has been constructed.
	--- @param id string
	--- @param fn fun(record: table, square: any, source: string|nil)
	--- @return boolean ok
	--- @return string|nil err
	function Record.registerSquareRecordExtender(id, fn)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		if type(fn) ~= "function" then
			return false, "badFn"
		end
		local ext = Record._extensions.squareRecord
		if ext.byId[id] == nil then
			ext.orderCount = (ext.orderCount or 0) + 1
			ext.order[ext.orderCount] = id
		end
		ext.byId[id] = fn
		return true
	end
end

if Record.unregisterSquareRecordExtender == nil then
	--- Unregister a previously registered square record extender.
	--- @param id string
	function Record.unregisterSquareRecordExtender(id)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		local ext = Record._extensions.squareRecord
		ext.byId[id] = nil
		return true
	end
end

if Record.applySquareRecordExtenders == nil then
	--- Apply all registered square record extenders to a record.
	--- @param record table
	--- @param square any
	--- @param source string|nil
	function Record.applySquareRecordExtenders(record, square, source)
		local ext = Record._extensions and Record._extensions.squareRecord or nil
		if type(record) ~= "table" or not ext then
			return
		end
		for i = 1, (ext.orderCount or 0) do
			local id = ext.order[i]
			local fn = id and ext.byId[id] or nil
			if fn then
				local ok, err = pcall(fn, record, square, source)
				if not ok then
					Log:warn("Square record extender failed id=%s err=%s", tostring(id), tostring(err))
				end
			end
		end
	end
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

local function detectFlag(square, detector)
	if not square then
		return false
	end
	if type(detector) == "function" then
		local ok, value = pcall(detector, square)
		if ok then
			return value == true
		end
	end
	return false
end

local function detectCorpse(square)
	if not square then
		return false
	end
	if type(square.getDeadBody) == "function" then
		local ok, body = pcall(square.getDeadBody, square)
		if ok and body ~= nil then
			return true
		end
	end
	-- Some builds expose a list-returning API; treat any non-empty list as "has corpse".
	if type(square.getDeadBodys) == "function" then
		local ok, list = pcall(square.getDeadBodys, square)
		if ok and list ~= nil then
			if type(list.size) == "function" then
				local okSize, size = pcall(list.size, list)
				if okSize and type(size) == "number" then
					return size > 0
				end
			end
			-- Best-effort: if we can't introspect size, a non-nil list still suggests corpses may exist.
			-- Keep this conservative: only treat it as "true" when we can prove it's non-empty.
		end
	end
	return detectFlag(square, square.hasCorpse)
end

if Record.makeSquareRecord == nil then
	--- Build a square fact record.
	--- Intentionally returns a tiny, stable "snapshot" so we can buffer safely and keep downstream pure.
	--- @param square any
	--- @param source string|nil
	--- @return table|nil record
	function Record.makeSquareRecord(square, source)
		if not square then
			return nil
		end

		local x = coordOf(square, "getX")
		local y = coordOf(square, "getY")
		local z = coordOf(square, "getZ") or 0
		if x == nil or y == nil then
			Log:warn("Skipped square record - missing coordinates")
			return nil
		end

		local tileLocation = SquareHelpers.record.tileLocationFromCoords(x, y, z)
		local record = {
			squareId = deriveSquareId(square, x, y, z),
			x = x,
			y = y,
			z = z,
			tileLocation = tileLocation,
			-- Stable-ish key for joins/dedup; prefer tileLocation for deterministic ids.
			woKey = tileLocation,
			hasBloodSplat = detectFlag(square, square.hasBlood),
			hasCorpse = detectCorpse(square),
			hasTrashItems = false, -- placeholder until we wire real trash detection
			IsoGridSquare = square,
			source = source,
		}

		Record.applySquareRecordExtenders(record, square, source)
		return record
	end
end

Record._internal.coordOf = coordOf
Record._internal.deriveSquareId = deriveSquareId
Record._internal.detectFlag = detectFlag
Record._internal.detectCorpse = detectCorpse

return Record
