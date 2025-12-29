-- facts/dead_bodies/record.lua -- builds stable dead body fact records from IsoDeadBody objects.
local Log = require("LQR/util/log").withTag("WO.FACTS.deadBodies")
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
Record._extensions.deadBodyRecord = Record._extensions.deadBodyRecord or { order = {}, orderCount = 0, byId = {} }

if Record.registerDeadBodyRecordExtender == nil then
	--- Register an extender that can add extra fields to each dead body record.
	--- Extenders run after the base record has been constructed.
	--- @param id string
	--- @param fn fun(record: table, body: any, source: string|nil, opts: table|nil)
	--- @return boolean ok
	--- @return string|nil err
	function Record.registerDeadBodyRecordExtender(id, fn)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		if type(fn) ~= "function" then
			return false, "badFn"
		end
		local ext = Record._extensions.deadBodyRecord
		if ext.byId[id] == nil then
			ext.orderCount = (ext.orderCount or 0) + 1
			ext.order[ext.orderCount] = id
		end
		ext.byId[id] = fn
		return true
	end
end

if Record.unregisterDeadBodyRecordExtender == nil then
	--- Unregister a previously registered dead body record extender.
	--- @param id string
	function Record.unregisterDeadBodyRecordExtender(id)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		local ext = Record._extensions.deadBodyRecord
		ext.byId[id] = nil
		return true
	end
end

if Record.applyDeadBodyRecordExtenders == nil then
	--- Apply all registered dead body record extenders to a record.
	--- @param record table
	--- @param body any
	--- @param source string|nil
	--- @param opts table|nil
	function Record.applyDeadBodyRecordExtenders(record, body, source, opts)
		local ext = Record._extensions and Record._extensions.deadBodyRecord or nil
		if type(record) ~= "table" or not ext then
			return
		end
		for i = 1, (ext.orderCount or 0) do
			local id = ext.order[i]
			local fn = id and ext.byId[id] or nil
			if fn then
				local ok, err = pcall(fn, record, body, source, opts)
				if not ok then
					Log:warn("Dead body record extender failed id=%s err=%s", tostring(id), tostring(err))
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

if Record.makeDeadBodyRecord == nil then
	--- Build a dead body fact record.
	--- @param body any
	--- @param square any|nil
	--- @param source string|nil
	--- @param opts table|nil
	--- @return table|nil record
	function Record.makeDeadBodyRecord(body, square, source, opts)
		if not body then
			return nil
		end
		opts = opts or {}

		if square == nil then
			square = opts.square
			if square == nil then
				square = SafeCall.safeCall(body, "getSquare") or SafeCall.safeCall(body, "getCurrentSquare")
			end
		end
		local x = coordOf(square, "getX")
		local y = coordOf(square, "getY")
		local z = coordOf(square, "getZ") or 0
		if x == nil or y == nil then
			if _G.WORLDOBSERVER_HEADLESS ~= true then
				Log:warn("Skipped dead body record - missing coordinates")
			end
			return nil
		end

		local bodyId = SafeCall.safeCall(body, "getObjectID")
		if bodyId == nil then
			if _G.WORLDOBSERVER_HEADLESS ~= true then
				Log:warn("Skipped dead body record - missing object id")
			end
			return nil
		end

		local record = {
			deadBodyId = bodyId,
			woKey = tostring(bodyId),
			x = x,
			y = y,
			z = z,
			tileLocation = SquareHelpers.record.tileLocationFromCoords(x, y, z),
			squareId = deriveSquareId(square, x, y, z),
			source = source,
		}

		if opts.includeIsoDeadBody then
			record.IsoDeadBody = body
		end

		Record.applyDeadBodyRecordExtenders(record, body, source, opts)
		return record
	end
end

Record._internal.coordOf = coordOf
Record._internal.deriveSquareId = deriveSquareId

return Record
