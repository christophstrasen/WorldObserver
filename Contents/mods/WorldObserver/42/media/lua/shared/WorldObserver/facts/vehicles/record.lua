-- facts/vehicles/record.lua -- builds stable vehicle fact records from BaseVehicle objects.
local Log = require("DREAMBase/log").withTag("WO.FACTS.vehicles")
local SafeCall = require("DREAMBase/pz/safe_call")
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
Record._extensions.vehicleRecord = Record._extensions.vehicleRecord or { order = {}, orderCount = 0, byId = {} }

local function shouldWarn(opts)
	if type(opts) == "table" and opts.headless == true then
		return false
	end
	return _G.WORLDOBSERVER_HEADLESS ~= true
end

if Record.registerVehicleRecordExtender == nil then
	--- Register an extender that can add extra fields to each vehicle record.
	--- Extenders run after the base record has been constructed.
	--- @param id string
	--- @param fn fun(record: table, vehicle: any, source: string|nil, opts: table|nil)
	--- @return boolean ok
	--- @return string|nil err
	function Record.registerVehicleRecordExtender(id, fn)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		if type(fn) ~= "function" then
			return false, "badFn"
		end
		local ext = Record._extensions.vehicleRecord
		if ext.byId[id] == nil then
			ext.orderCount = (ext.orderCount or 0) + 1
			ext.order[ext.orderCount] = id
		end
		ext.byId[id] = fn
		return true
	end
end

if Record.unregisterVehicleRecordExtender == nil then
	--- Unregister a previously registered vehicle record extender.
	--- @param id string
	function Record.unregisterVehicleRecordExtender(id)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		local ext = Record._extensions.vehicleRecord
		ext.byId[id] = nil
		return true
	end
end

if Record.applyVehicleRecordExtenders == nil then
	--- Apply all registered vehicle record extenders to a record.
	--- @param record table
	--- @param vehicle any
	--- @param source string|nil
	--- @param opts table|nil
	function Record.applyVehicleRecordExtenders(record, vehicle, source, opts)
		local ext = Record._extensions and Record._extensions.vehicleRecord or nil
		if type(record) ~= "table" or not ext then
			return
		end
		for i = 1, (ext.orderCount or 0) do
			local id = ext.order[i]
			local fn = id and ext.byId[id] or nil
			if fn then
				local ok, err = pcall(fn, record, vehicle, source, opts)
				if not ok then
					Log:warn("Vehicle record extender failed id=%s err=%s", tostring(id), tostring(err))
				end
			end
		end
	end
end

if Record.keyFromRecord == nil then
	--- Return the preferred stable key for a vehicle record (sqlId, else vehicleId).
	--- @param record table|nil
	--- @return any
	function Record.keyFromRecord(record)
		if type(record) ~= "table" then
			return nil
		end
		return record.sqlId or record.vehicleId
	end
end

local function resolveSqlId(vehicle)
	local sqlId = vehicle and vehicle.sqlId or nil
	if sqlId ~= nil then
		return sqlId
	end
	local fromMethod = SafeCall.safeCall(vehicle, "getSqlId")
	if fromMethod ~= nil then
		return fromMethod
	end
	return nil
end

if Record.makeVehicleRecord == nil then
	--- Build a vehicle fact record.
	--- @param vehicle any
	--- @param source string|nil
	--- @param opts table|nil
	--- @return table|nil record
	function Record.makeVehicleRecord(vehicle, source, opts)
		if vehicle == nil then
			return nil
		end
		opts = opts or {}

		local sqlId = resolveSqlId(vehicle)
		local vehicleId = SafeCall.safeCall(vehicle, "getId")
		if sqlId == nil and vehicleId == nil then
			if shouldWarn(opts) then
				Log:warn("Skipped vehicle record - missing sqlId and vehicleId")
			end
			return nil
		end

		local square = SafeCall.safeCall(vehicle, "getSquare")
		local tileX = square and SafeCall.safeCall(square, "getX") or nil
		local tileY = square and SafeCall.safeCall(square, "getY") or nil
		local tileZ = square and (SafeCall.safeCall(square, "getZ") or 0) or nil
		local x = tileX
		local y = tileY
		local z = tileZ
		local woKey = tostring(sqlId or vehicleId)

		local record = {
			sqlId = sqlId,
			vehicleId = vehicleId,
			woKey = woKey,
			x = x,
			y = y,
			z = z,
			tileX = tileX,
			tileY = tileY,
			tileZ = tileZ,
			name = SafeCall.safeCall(vehicle, "getObjectName"),
			scriptName = SafeCall.safeCall(vehicle, "getScriptName"),
			skin = SafeCall.safeCall(vehicle, "getSkin"),
			type = SafeCall.safeCall(vehicle, "getVehicleType"),
			isDoingOffroad = SafeCall.safeCall(vehicle, "isDoingOffroad") == true,
			hasPassenger = SafeCall.safeCall(vehicle, "hasPassenger") == true,
			isSirening = SafeCall.safeCall(vehicle, "isSirening") == true,
			isStopped = SafeCall.safeCall(vehicle, "isStopped") == true,
			source = source,
		}

		-- Best-effort: retain a live IsoGridSquare reference for downstream consumers.
		if square ~= nil then
			record.IsoGridSquare = square
			if SquareHelpers.record and SquareHelpers.record.getIsoGridSquare then
				SquareHelpers.record.getIsoGridSquare(record, opts)
			end
		end

		Record.applyVehicleRecordExtenders(record, vehicle, source, opts)
		return record
	end
end

Record._internal.resolveSqlId = resolveSqlId

return Record
