-- facts/rooms/on_see_new_room.lua -- optional OnSeeNewRoom listener gated by declared interest.
local Log = require("DREAMBase/log").withTag("WO.FACTS.rooms")
local Time = require("WorldObserver/helpers/time")
local Cooldown = require("WorldObserver/facts/cooldown")
local InterestEffective = require("WorldObserver/facts/interest_effective")
local Highlight = require("WorldObserver/helpers/highlight")
local JavaList = require("DREAMBase/pz/java_list")

local moduleName = ...
local OnSee = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		OnSee = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = OnSee
	end
end
OnSee._internal = OnSee._internal or {}

local INTEREST_TYPE_ROOMS = "rooms"
local INTEREST_SCOPE_ONSEE = "onSeeNewRoom"
local ONSEE_HIGHLIGHT_COLOR = { 0.9, 0.7, 0.2 }

local function nowMillis()
	return Time.gameMillis() or math.floor(os.time() * 1000)
end

local function highlightRoomSquares(room, effective, highlightPref)
	if room == nil then
		return
	end
	local squares = nil
	if type(room.getSquares) == "function" then
		local okSquares, value = pcall(room.getSquares, room)
		if okSquares then
			squares = value
		end
	end
	if squares == nil then
		return
	end

	local color = ONSEE_HIGHLIGHT_COLOR
	local alpha = 0.9
	if type(highlightPref) == "table" then
		color = highlightPref
		if type(color[4]) == "number" then
			alpha = color[4]
		end
	end
	local durationMs = Highlight.durationMsFromEffectiveCadence(effective)

	-- Note: highlighting all squares can be expensive for large rooms; this is best-effort by request.
	local count = JavaList.size(squares)
	if count <= 0 then
		return
	end
	for i = 1, count do
		local square = JavaList.get(squares, i)
		if square ~= nil then
			Highlight.highlightFloor(square, durationMs, { color = color, alpha = alpha })
		end
	end
end

local function emitWithCooldown(state, emitFn, record, nowMs, cooldownMs, onEmitFn)
	if type(emitFn) ~= "function" or type(record) ~= "table" or record.roomId == nil then
		return false
	end
	state.lastEmittedMs = state.lastEmittedMs or {}
	if not Cooldown.shouldEmit(state.lastEmittedMs, record.roomId, nowMs, cooldownMs) then
		return false
	end
	if type(onEmitFn) == "function" then
		pcall(onEmitFn, record)
	end
	emitFn(record)
	Cooldown.markEmitted(state.lastEmittedMs, record.roomId, nowMs)
	return true
end

local function attachListenerOnce(ctx)
	local state = ctx.state or {}
	if state.onSeeNewRoomHandler then
		return true
	end

	local events = _G.Events
	local handler = events and events.OnSeeNewRoom
	if not handler or type(handler.Add) ~= "function" then
		return false
	end

	local fn = function(room)
		local effectiveByType = state._effectiveInterestByType
		local effectiveByBucket = effectiveByType and effectiveByType[INTEREST_TYPE_ROOMS] or nil
		local effective = type(effectiveByBucket) == "table" and effectiveByBucket[INTEREST_SCOPE_ONSEE] or nil
		if not effective then
			return
		end

		local rooms = ctx.rooms
		if not (rooms and type(rooms.makeRoomRecord) == "function") then
			return
		end

		local record = rooms.makeRoomRecord(room, "event", ctx.recordOpts)
		local cooldownMs = math.max(0, (tonumber(effective.cooldown) or 0) * 1000)
		emitWithCooldown(state, ctx.emitFn, record, nowMillis(), cooldownMs, function()
			if ctx.headless then
				return
			end
			local highlightPref = effective.highlight
			if highlightPref == true or type(highlightPref) == "table" then
				highlightRoomSquares(room, effective, highlightPref)
			end
		end)
	end

	handler.Add(fn)
	state.onSeeNewRoomHandler = fn
	Log:info("OnSeeNewRoom listener attached")
	return true
end

if OnSee.ensure == nil then
	--- Ensure the OnSeeNewRoom listener is attached/detached based on declared interest.
	--- @param ctx table
	--- @return boolean active
	function OnSee.ensure(ctx)
		ctx = ctx or {}
		local state = ctx.state or {}
		ctx.state = state

		local listenerCfg = ctx.listenerCfg or {}
		local listenerEnabled = listenerCfg.enabled ~= false

		local effective = nil
		if listenerEnabled then
			effective = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, INTEREST_TYPE_ROOMS, {
				label = "onSeeNewRoom",
				allowDefault = false,
				log = Log,
				bucketKey = INTEREST_SCOPE_ONSEE,
			})
			if effective and ctx.interestRegistry and ctx.interestRegistry.effective then
				local okMerged, merged = pcall(function()
					return ctx.interestRegistry:effective(INTEREST_TYPE_ROOMS, nil, { bucketKey = INTEREST_SCOPE_ONSEE })
				end)
				if okMerged and type(merged) == "table" then
					effective.highlight = merged.highlight
				end
			end
		else
			state._effectiveInterestByType = state._effectiveInterestByType or {}
			if type(state._effectiveInterestByType[INTEREST_TYPE_ROOMS]) == "table" then
				state._effectiveInterestByType[INTEREST_TYPE_ROOMS][INTEREST_SCOPE_ONSEE] = nil
			end
		end

		local wantsListener = listenerEnabled and effective ~= nil
		if wantsListener then
			local okListener = attachListenerOnce(ctx)
			if not okListener and not ctx.headless then
				Log:warn("OnSeeNewRoom listener not attached (Events unavailable)")
			end
			return state.onSeeNewRoomHandler ~= nil
		end

		if state.onSeeNewRoomHandler then
			local events = _G.Events
			local handler = events and events.OnSeeNewRoom
			if handler and type(handler.Remove) == "function" then
				pcall(handler.Remove, handler, state.onSeeNewRoomHandler)
				state.onSeeNewRoomHandler = nil
				if not ctx.headless then
					Log:info("OnSeeNewRoom listener detached (no onSeeNewRoom interest)")
				end
			end
		end
		return false
	end
end

OnSee._internal.attachListenerOnce = attachListenerOnce
OnSee._internal.emitWithCooldown = emitWithCooldown

return OnSee
