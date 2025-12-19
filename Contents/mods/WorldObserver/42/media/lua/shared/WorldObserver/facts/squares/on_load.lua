-- facts/squares/on_load.lua -- optional LoadGridsquare listener gated by declared interest.
local Log = require("LQR/util/log").withTag("WO.FACTS.squares")
local Time = require("WorldObserver/helpers/time")
local Cooldown = require("WorldObserver/facts/cooldown")
local InterestEffective = require("WorldObserver/facts/interest_effective")
local Highlight = require("WorldObserver/helpers/highlight")

local moduleName = ...
local OnLoad = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		OnLoad = loaded
	else
		package.loaded[moduleName] = OnLoad
	end
end
OnLoad._internal = OnLoad._internal or {}

local INTEREST_TYPE_ONLOAD = "squares.onLoad"

local ONLOAD_HIGHLIGHT_COLOR = { 0.2, 1.0, 0.2 }

local function nowMillis()
	return Time.gameMillis() or math.floor(os.time() * 1000)
end

local function highlightFloor(square, durationMs)
	if square == nil or durationMs <= 0 then
		return
	end
	if type(square.getFloor) ~= "function" then
		return
	end
	local okFloor, floor = pcall(square.getFloor, square)
	if not okFloor or floor == nil then
		return
	end
	Highlight.highlightTarget(floor, { durationMs = durationMs, color = ONLOAD_HIGHLIGHT_COLOR, alpha = 0.9 })
end

local function highlightMsFromCooldownSeconds(cooldownSeconds)
	local ms = math.max(0, (tonumber(cooldownSeconds) or 0) * 1000)
	-- Keep the highlight short and readable; this is event-driven, not a probe visualization.
	return math.max(250, math.min(5000, ms))
end

local function emitWithCooldown(state, emitFn, record, nowMs, cooldownMs, onEmitFn)
	if type(emitFn) ~= "function" or type(record) ~= "table" or record.squareId == nil then
		return false
	end
	state.lastEmittedMs = state.lastEmittedMs or {}
	if not Cooldown.shouldEmit(state.lastEmittedMs, record.squareId, nowMs, cooldownMs) then
		return false
	end
	if type(onEmitFn) == "function" then
		pcall(onEmitFn, record)
	end
	emitFn(record)
	Cooldown.markEmitted(state.lastEmittedMs, record.squareId, nowMs)
	return true
end

local function registerListener(ctx)
	local state = ctx.state or {}
	if state.loadGridsquareHandler then
		return true
	end

	local events = _G.Events
	local handler = events and events.LoadGridsquare
	if not handler or type(handler.Add) ~= "function" then
		return false
	end

	local fn = function(square)
		local effectiveByType = state._effectiveInterestByType
		local effective = effectiveByType and effectiveByType[INTEREST_TYPE_ONLOAD] or nil
		if not effective then
			return
		end

		local squares = ctx.squares
		if not (squares and type(squares.makeSquareRecord) == "function") then
			return
		end

		local record = squares.makeSquareRecord(square, "event")
		local cooldownMs = math.max(0, (tonumber(effective.cooldown) or 0) * 1000)
		emitWithCooldown(state, ctx.emitFn, record, nowMillis(), cooldownMs, function()
			if ctx.headless then
				return
			end
			if effective.highlight ~= true then
				return
			end
			highlightFloor(square, highlightMsFromCooldownSeconds(effective.cooldown))
		end)
	end

	handler.Add(fn)
	state.loadGridsquareHandler = fn
	Log:info("LoadGridsquare listener registered")
	return true
end

--- Ensure the LoadGridsquare listener is registered/unregistered based on declared interest.
--- @param ctx table
--- @return boolean active
if OnLoad.ensure == nil then
	function OnLoad.ensure(ctx)
		ctx = ctx or {}
		local state = ctx.state or {}
		ctx.state = state

		local listenerCfg = ctx.listenerCfg or {}
		local listenerEnabled = listenerCfg.enabled ~= false

			local effective = nil
			if listenerEnabled then
				effective = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, INTEREST_TYPE_ONLOAD, {
					label = "onLoad",
					allowDefault = false,
					log = Log,
				})
				if effective and ctx.interestRegistry and ctx.interestRegistry.effective then
					local okMerged, merged = pcall(function()
						return ctx.interestRegistry:effective(INTEREST_TYPE_ONLOAD)
					end)
					if okMerged and type(merged) == "table" then
						effective.highlight = merged.highlight
					end
				end
			else
				state._effectiveInterestByType = state._effectiveInterestByType or {}
				state._effectiveInterestByType[INTEREST_TYPE_ONLOAD] = nil
			end

		local wantsListener = listenerEnabled and effective ~= nil
		if wantsListener then
			local okListener = registerListener(ctx)
			if not okListener and not ctx.headless then
				Log:warn("OnLoadGridsquare listener not registered (Events unavailable)")
			end
			return state.loadGridsquareHandler ~= nil
		end

		if state.loadGridsquareHandler then
			local events = _G.Events
			local handler = events and events.LoadGridsquare
			if handler and type(handler.Remove) == "function" then
				pcall(handler.Remove, handler, state.loadGridsquareHandler)
				state.loadGridsquareHandler = nil
				if not ctx.headless then
					Log:info("LoadGridsquare listener unregistered (no onLoad interest)")
				end
			end
		end
		return false
	end
end

OnLoad._internal.registerListener = registerListener
OnLoad._internal.emitWithCooldown = emitWithCooldown
OnLoad._internal.highlightFloor = highlightFloor

return OnLoad
