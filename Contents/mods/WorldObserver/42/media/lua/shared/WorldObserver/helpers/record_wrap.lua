-- helpers/record_wrap.lua -- internal utility for record wrapping (metatable decoration).
--
-- Why this exists:
-- In record contexts (PromiseKeeper actions, callbacks) modders hold plain record tables and lose the stream helper
-- surface.
-- Wrapping decorates a record in-place (metatable __index) to expose a small, explicit, per-family whitelist of
-- methods.
--
-- Safety:
-- - Refuses when a record already has a metatable (unless it's our wrapper metatable).
-- - Warns when record fields would shadow wrapped methods (collisions).
-- - Intended to be used close to use; shallow copies (e.g. joins) may drop metatables.
local Log = require("DREAMBase/log").withTag("WO.HELPER.recordWrap")
local moduleName = ...
local RecordWrap = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		RecordWrap = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = RecordWrap
	end
end

RecordWrap._internal = RecordWrap._internal or {}

local function shouldLog(opts)
	if type(opts) == "table" and opts.headless == true then
		return false
	end
	return _G.WORLDOBSERVER_HEADLESS ~= true
end

if RecordWrap.ensureState == nil then
	--- Ensure a wrapper state has a stable methods table and metatable.
	--- @param state table|nil
	--- @return table state
	function RecordWrap.ensureState(state)
		state = state or {}
		state.methods = state.methods or {}
		state.metatable = state.metatable or { __index = state.methods }
		return state
	end
end

local function listCollisions(record, names)
	if type(record) ~= "table" or type(names) ~= "table" then
		return nil
	end
	local collisions = nil
	local count = 0
	local i = 1
	while true do
		local name = names[i]
		if name == nil then
			break
		end
		if type(name) == "string" and rawget(record, name) ~= nil then
			count = count + 1
			if collisions == nil then
				collisions = {}
			end
			collisions[count] = name
		end
		i = i + 1
	end
	return collisions
end

local function stringifyCollisions(collisions)
	if type(collisions) ~= "table" then
		return nil
	end
	local out = {}
	local outCount = 0
	local i = 1
	while true do
		local name = collisions[i]
		if name == nil then
			break
		end
		if name ~= nil then
			outCount = outCount + 1
			out[outCount] = tostring(name)
		end
		i = i + 1
	end
	if outCount <= 0 then
		return nil
	end
	return table.concat(out, ", ")
end

if RecordWrap.wrap == nil then
	--- Decorate a record in-place to expose a small method surface via metatable.
	--- Returns the same table on success; refuses if the record already has a different metatable.
	--- @param record any
	--- @param state table Wrapper state (must have stable metatable).
	--- @param opts table|nil { family?, log?, methodNames?, headless? }
	--- @return table|nil wrappedRecord
	--- @return string|nil err
	--- @return table|nil collisions
	function RecordWrap.wrap(record, state, opts)
		if type(record) ~= "table" then
			return nil, "badRecord"
		end
		state = RecordWrap.ensureState(state)

		local existing = getmetatable(record)
		if existing == state.metatable then
			return record
		end
		if existing ~= nil then
			if shouldLog(opts) then
				local family = type(opts) == "table" and opts.family or nil
				local tag = family and (tostring(family) .. ".wrap") or "wrap"
				local logger = type(opts) == "table" and opts.log or Log
				if logger and type(logger.warn) == "function" then
					logger:warn("%s refused: record already has a metatable", tostring(tag))
				end
			end
			return nil, "hasMetatable"
		end

		local collisions = listCollisions(record, type(opts) == "table" and opts.methodNames or nil)
		if collisions ~= nil and shouldLog(opts) then
			local family = type(opts) == "table" and opts.family or nil
			local tag = family and (tostring(family) .. ".wrap") or "wrap"
			local joined = stringifyCollisions(collisions)
			local logger = type(opts) == "table" and opts.log or Log
			if joined ~= nil and logger and type(logger.warn) == "function" then
				logger:warn(
					"%s method collision: record fields shadow wrapped methods (%s); use helpers.record.* as escape hatch",
					tostring(tag),
					joined
				)
			end
		end

		setmetatable(record, state.metatable)
		return record, nil, collisions
	end
end

return RecordWrap
