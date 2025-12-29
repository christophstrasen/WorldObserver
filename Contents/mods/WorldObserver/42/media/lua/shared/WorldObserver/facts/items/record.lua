-- facts/items/record.lua -- builds stable item fact records from world/inventory item objects.
local Log = require("LQR/util/log").withTag("WO.FACTS.items")
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
Record._extensions.itemRecord = Record._extensions.itemRecord or { order = {}, orderCount = 0, byId = {} }

if Record.registerItemRecordExtender == nil then
	--- Register an extender that can add extra fields to each item record.
	--- Extenders run after the base record has been constructed.
	--- @param id string
	--- @param fn fun(record: table, item: any, source: string|nil, opts: table|nil)
	--- @return boolean ok
	--- @return string|nil err
	function Record.registerItemRecordExtender(id, fn)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		if type(fn) ~= "function" then
			return false, "badFn"
		end
		local ext = Record._extensions.itemRecord
		if ext.byId[id] == nil then
			ext.orderCount = (ext.orderCount or 0) + 1
			ext.order[ext.orderCount] = id
		end
		ext.byId[id] = fn
		return true
	end
end

if Record.unregisterItemRecordExtender == nil then
	--- Unregister a previously registered item record extender.
	--- @param id string
	function Record.unregisterItemRecordExtender(id)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		local ext = Record._extensions.itemRecord
		ext.byId[id] = nil
		return true
	end
end

if Record.applyItemRecordExtenders == nil then
	--- Apply all registered item record extenders to a record.
	--- @param record table
	--- @param item any
	--- @param source string|nil
	--- @param opts table|nil
	function Record.applyItemRecordExtenders(record, item, source, opts)
		local ext = Record._extensions and Record._extensions.itemRecord or nil
		if type(record) ~= "table" or not ext then
			return
		end
		for i = 1, (ext.orderCount or 0) do
			local id = ext.order[i]
			local fn = id and ext.byId[id] or nil
			if fn then
				local ok, err = pcall(fn, record, item, source, opts)
				if not ok then
					Log:warn("Item record extender failed id=%s err=%s", tostring(id), tostring(err))
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

local function resolveItemId(item, worldItem)
	local id = SafeCall.safeCall(worldItem, "getID")
	if id ~= nil then
		return id
	end
	id = SafeCall.safeCall(worldItem, "getObjectID")
	if id ~= nil then
		return id
	end
	id = SafeCall.safeCall(item, "getID")
	if id ~= nil then
		return id
	end
	id = SafeCall.safeCall(item, "getObjectID")
	if id ~= nil then
		return id
	end
	return nil
end

if Record.makeItemRecord == nil then
	--- Build an item fact record.
	--- @param item any
	--- @param square any|nil
	--- @param source string|nil
	--- @param opts table|nil
	--- @return table|nil record
	function Record.makeItemRecord(item, square, source, opts)
		if not item then
			return nil
		end
		opts = opts or {}
		local worldItem = opts.worldItem
		local containerItem = opts.containerItem
		local containerWorldItem = opts.containerWorldItem

		if square == nil then
			square = opts.square
			if square == nil and worldItem then
				square = SafeCall.safeCall(worldItem, "getSquare") or SafeCall.safeCall(worldItem, "getCurrentSquare")
			end
		end
		local x = coordOf(square, "getX")
		local y = coordOf(square, "getY")
		local z = coordOf(square, "getZ") or 0
		if x == nil or y == nil then
			if _G.WORLDOBSERVER_HEADLESS ~= true then
				Log:warn("Skipped item record: missing coordinates")
			end
			return nil
		end

		local itemId = resolveItemId(item, worldItem)
		if itemId == nil then
			if _G.WORLDOBSERVER_HEADLESS ~= true then
				Log:warn("Skipped item record: missing itemId")
			end
			return nil
		end

		local record = {
			itemId = itemId,
			woKey = tostring(itemId),
			itemType = SafeCall.safeCall(item, "getType"),
			itemFullType = SafeCall.safeCall(item, "getFullType"),
			itemName = SafeCall.safeCall(item, "getName"),
			x = x,
			y = y,
			z = z,
			tileLocation = SquareHelpers.record.tileLocationFromCoords(x, y, z),
			squareId = deriveSquareId(square, x, y, z),
			source = source,
		}

		if containerItem ~= nil then
			record.containerItemId = resolveItemId(containerItem, containerWorldItem)
			record.containerItemType = SafeCall.safeCall(containerItem, "getType")
			record.containerItemFullType = SafeCall.safeCall(containerItem, "getFullType")
		end

		if opts.includeInventoryItem then
			record.InventoryItem = item
		end
		if opts.includeWorldItem and worldItem ~= nil then
			record.WorldItem = worldItem
		end

		Record.applyItemRecordExtenders(record, item, source, opts)
		return record
	end
end

Record._internal.coordOf = coordOf
Record._internal.deriveSquareId = deriveSquareId
Record._internal.resolveItemId = resolveItemId

return Record
