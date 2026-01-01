-- helpers/dead_body.lua -- dead body helper set providing small value-add filters.
local Log = require("DREAMBase/log").withTag("WO.HELPER.deadBody")
local RecordWrap = require("WorldObserver/helpers/record_wrap")
local SquareHelpers = require("WorldObserver/helpers/square")
local moduleName = ...
local DeadBodyHelpers = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		DeadBodyHelpers = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = DeadBodyHelpers
	end
end

DeadBodyHelpers.record = DeadBodyHelpers.record or {}
DeadBodyHelpers.stream = DeadBodyHelpers.stream or {}

if DeadBodyHelpers.record.getIsoDeadBody == nil then
	--- Best-effort: return the live IsoDeadBody for a record (when present).
	--- @param record table|nil
	--- @return any
	function DeadBodyHelpers.record.getIsoDeadBody(record)
		if type(record) ~= "table" then
			return nil
		end
		return record.IsoDeadBody
	end
end

DeadBodyHelpers._internal = DeadBodyHelpers._internal or {}
DeadBodyHelpers._internal.recordWrap = DeadBodyHelpers._internal.recordWrap or RecordWrap.ensureState()
local recordWrap = DeadBodyHelpers._internal.recordWrap

if recordWrap.methods.getIsoDeadBody == nil then
	function recordWrap.methods:getIsoDeadBody(...)
		local fn = DeadBodyHelpers.record and DeadBodyHelpers.record.getIsoDeadBody
		if type(fn) == "function" then
			return fn(self, ...)
		end
		return nil
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

if DeadBodyHelpers.wrap == nil then
	--- Decorate a dead body record in-place to expose a small method surface via metatable.
	--- Returns the same table on success; refuses if the record already has a different metatable.
	--- @param record table
	--- @return table|nil wrappedRecord
	--- @return string|nil err
	function DeadBodyHelpers:wrap(record, opts)
		return RecordWrap.wrap(record, recordWrap, {
			family = "deadBody",
			log = Log,
			headless = type(opts) == "table" and opts.headless or nil,
			methodNames = { "getIsoDeadBody", "getIsoGridSquare", "highlight" },
		})
	end
end

local function deadBodyField(observation, fieldName)
	local record = observation[fieldName]
	if record == nil then
		if _G.WORLDOBSERVER_HEADLESS ~= true then
			Log:warn("dead body helper called without field '%s' on observation", tostring(fieldName))
		end
		return nil
	end
	return record
end

-- Stream sugar: apply a predicate to the dead body record directly.
if DeadBodyHelpers.deadBodyFilter == nil then
	function DeadBodyHelpers.deadBodyFilter(stream, fieldName, predicate)
		assert(type(predicate) == "function", "deadBodyFilter predicate must be a function")
		local target = fieldName or "deadBody"
		return stream:filter(function(observation)
			local bodyRecord = deadBodyField(observation, target)
			return predicate(bodyRecord, observation) == true
		end)
	end
end
if DeadBodyHelpers.stream.deadBodyFilter == nil then
	function DeadBodyHelpers.stream.deadBodyFilter(stream, fieldName, ...)
		return DeadBodyHelpers.deadBodyFilter(stream, fieldName, ...)
	end
end

return DeadBodyHelpers
