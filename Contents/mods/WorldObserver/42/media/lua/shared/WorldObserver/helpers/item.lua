-- helpers/item.lua -- item helper set providing small value-add filters for item observations.
local Log = require("DREAMBase/log").withTag("WO.HELPER.item")
local RecordWrap = require("WorldObserver/helpers/record_wrap")
local SquareHelpers = require("WorldObserver/helpers/square")
local moduleName = ...
local ItemHelpers = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		ItemHelpers = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = ItemHelpers
	end
end

ItemHelpers.record = ItemHelpers.record or {}
ItemHelpers.stream = ItemHelpers.stream or {}

ItemHelpers._internal = ItemHelpers._internal or {}
ItemHelpers._internal.recordWrap = ItemHelpers._internal.recordWrap or RecordWrap.ensureState()
local recordWrap = ItemHelpers._internal.recordWrap

-- Record wrapper methods (whitelist) for ergonomic use in record contexts (PromiseKeeper actions, callbacks).
if recordWrap.methods.typeIs == nil then
	function recordWrap.methods:typeIs(...)
		local fn = ItemHelpers.record and ItemHelpers.record.itemTypeIs
		if type(fn) == "function" then
			return fn(self, ...)
		end
		return false
	end
end

if recordWrap.methods.fullTypeIs == nil then
	function recordWrap.methods:fullTypeIs(...)
		local fn = ItemHelpers.record and ItemHelpers.record.itemFullTypeIs
		if type(fn) == "function" then
			return fn(self, ...)
		end
		return false
	end
end

if recordWrap.methods.getIsoGridSquare == nil then
	function recordWrap.methods:getIsoGridSquare(...)
		local fn = SquareHelpers.record and SquareHelpers.record.getIsoGridSquare
		if type(fn) == "function" then
			return fn(self, ...)
		end
		return self.IsoGridSquare
	end
end

if recordWrap.methods.highlight == nil then
	function recordWrap.methods:highlight(...)
		local fn = SquareHelpers.highlight
		if type(fn) == "function" then
			return fn(self, ...)
		end
		return nil, "noHighlight"
	end
end

if ItemHelpers.wrap == nil then
	--- Decorate an item record in-place to expose a small method surface via metatable.
	--- Returns the same table on success; refuses if the record already has a different metatable.
	--- @param record table
	--- @return table|nil wrappedRecord
	--- @return string|nil err
	function ItemHelpers:wrap(record, opts)
		return RecordWrap.wrap(record, recordWrap, {
			family = "item",
			log = Log,
			headless = type(opts) == "table" and opts.headless or nil,
			methodNames = { "typeIs", "fullTypeIs", "getIsoGridSquare", "highlight" },
		})
	end
end

local function itemField(observation, fieldName)
	local record = observation[fieldName]
	if record == nil then
		if _G.WORLDOBSERVER_HEADLESS ~= true then
			Log:warn("item helper called without field '%s' on observation", tostring(fieldName))
		end
		return nil
	end
	return record
end

-- Stream sugar: apply a predicate to the item record directly.
if ItemHelpers.itemFilter == nil then
	function ItemHelpers.itemFilter(stream, fieldName, predicate)
		assert(type(predicate) == "function", "itemFilter predicate must be a function")
		local target = fieldName or "item"
		return stream:filter(function(observation)
			local itemRecord = itemField(observation, target)
			return predicate(itemRecord, observation) == true
		end)
	end
end
if ItemHelpers.stream.itemFilter == nil then
	function ItemHelpers.stream.itemFilter(stream, fieldName, ...)
		return ItemHelpers.itemFilter(stream, fieldName, ...)
	end
end

local function itemTypeIs(record, wanted)
	if type(record) ~= "table" then
		return false
	end
	if type(wanted) ~= "string" or wanted == "" then
		return false
	end
	return tostring(record.itemType) == wanted
end

if ItemHelpers.record.itemTypeIs == nil then
	ItemHelpers.record.itemTypeIs = itemTypeIs
end

if ItemHelpers.itemTypeIs == nil then
	function ItemHelpers.itemTypeIs(stream, fieldName, wanted)
		local target = fieldName or "item"
		return stream:filter(function(observation)
			local itemRecord = itemField(observation, target)
			return ItemHelpers.record.itemTypeIs(itemRecord, wanted)
		end)
	end
end
if ItemHelpers.stream.itemTypeIs == nil then
	function ItemHelpers.stream.itemTypeIs(stream, fieldName, ...)
		return ItemHelpers.itemTypeIs(stream, fieldName, ...)
	end
end

local function itemFullTypeIs(record, wanted)
	if type(record) ~= "table" then
		return false
	end
	if type(wanted) ~= "string" or wanted == "" then
		return false
	end
	return tostring(record.itemFullType) == wanted
end

if ItemHelpers.record.itemFullTypeIs == nil then
	ItemHelpers.record.itemFullTypeIs = itemFullTypeIs
end

if ItemHelpers.itemFullTypeIs == nil then
	function ItemHelpers.itemFullTypeIs(stream, fieldName, wanted)
		local target = fieldName or "item"
		return stream:filter(function(observation)
			local itemRecord = itemField(observation, target)
			return ItemHelpers.record.itemFullTypeIs(itemRecord, wanted)
		end)
	end
end
if ItemHelpers.stream.itemFullTypeIs == nil then
	function ItemHelpers.stream.itemFullTypeIs(stream, fieldName, ...)
		return ItemHelpers.itemFullTypeIs(stream, fieldName, ...)
	end
end

return ItemHelpers
