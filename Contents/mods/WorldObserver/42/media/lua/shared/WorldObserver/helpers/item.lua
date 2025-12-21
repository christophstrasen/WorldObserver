-- helpers/item.lua -- item helper set providing small value-add filters for item observations.
local Log = require("LQR/util/log").withTag("WO.HELPER.item")
local moduleName = ...
local ItemHelpers = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		ItemHelpers = loaded
	else
		package.loaded[moduleName] = ItemHelpers
	end
end

ItemHelpers.record = ItemHelpers.record or {}
ItemHelpers.stream = ItemHelpers.stream or {}

local function itemField(observation, fieldName)
	local record = observation[fieldName]
	if record == nil then
		Log:warn("item helper called without field '%s' on observation", tostring(fieldName))
		return nil
	end
	return record
end

-- Stream sugar: apply a predicate to the item record directly.
if ItemHelpers.whereItem == nil then
	function ItemHelpers.whereItem(stream, fieldName, predicate)
		assert(type(predicate) == "function", "whereItem predicate must be a function")
		local target = fieldName or "item"
		return stream:filter(function(observation)
			local itemRecord = itemField(observation, target)
			return predicate(itemRecord, observation) == true
		end)
	end
end
if ItemHelpers.stream.whereItem == nil then
	function ItemHelpers.stream.whereItem(stream, fieldName, ...)
		return ItemHelpers.whereItem(stream, fieldName, ...)
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
