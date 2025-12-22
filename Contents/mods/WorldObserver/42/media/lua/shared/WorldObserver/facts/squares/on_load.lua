-- facts/squares/on_load.lua -- optional LoadGridsquare listener gated by declared interest.
local Log = require("LQR/util/log").withTag("WO.FACTS.squares")
local Time = require("WorldObserver/helpers/time")
local Cooldown = require("WorldObserver/facts/cooldown")
local InterestEffective = require("WorldObserver/facts/interest_effective")
local Highlight = require("WorldObserver/helpers/highlight")

local moduleName = ...
local OnLoad = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		OnLoad = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = OnLoad
	end
end
OnLoad._internal = OnLoad._internal or {}

local INTEREST_TYPE_SQUARES = "squares"
local INTEREST_SCOPE_ONLOAD = "onLoad"

local ONLOAD_HIGHLIGHT_COLOR = { 0.2, 1.0, 0.2 }

local function nowMillis()
	return Time.gameMillis() or math.floor(os.time() * 1000)
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

local function attachListenerOnce(ctx)
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
		local effectiveByBucket = effectiveByType and effectiveByType[INTEREST_TYPE_SQUARES] or nil
		local effective = type(effectiveByBucket) == "table" and effectiveByBucket[INTEREST_SCOPE_ONLOAD] or nil
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
			Highlight.highlightFloor(
				square,
				Highlight.durationMsFromEffectiveCadence(effective),
				{ color = ONLOAD_HIGHLIGHT_COLOR, alpha = 0.9 }
			)
		end)
	end

handler.Add(fn)
state.loadGridsquareHandler = fn
	Log:info("LoadGridsquare listener attached")
	return true
end

if OnLoad.ensure == nil then
	--- Ensure the LoadGridsquare listener is attached/detached based on declared interest.
	--- @param ctx table
	--- @return boolean active
	function OnLoad.ensure(ctx)
		ctx = ctx or {}
		local state = ctx.state or {}
		ctx.state = state

		local listenerCfg = ctx.listenerCfg or {}
		local listenerEnabled = listenerCfg.enabled ~= false

			local effective = nil
			if listenerEnabled then
				effective = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, INTEREST_TYPE_SQUARES, {
					label = "onLoad",
					allowDefault = false,
					log = Log,
					bucketKey = INTEREST_SCOPE_ONLOAD,
				})
				if effective and ctx.interestRegistry and ctx.interestRegistry.effective then
					local okMerged, merged = pcall(function()
						return ctx.interestRegistry:effective(INTEREST_TYPE_SQUARES, nil, { bucketKey = INTEREST_SCOPE_ONLOAD })
					end)
					if okMerged and type(merged) == "table" then
						effective.highlight = merged.highlight
					end
				end
			else
				state._effectiveInterestByType = state._effectiveInterestByType or {}
				if type(state._effectiveInterestByType[INTEREST_TYPE_SQUARES]) == "table" then
					state._effectiveInterestByType[INTEREST_TYPE_SQUARES][INTEREST_SCOPE_ONLOAD] = nil
				end
			end

		local wantsListener = listenerEnabled and effective ~= nil
		if wantsListener then
			local okListener = attachListenerOnce(ctx)
			if not okListener and not ctx.headless then
				Log:warn("OnLoadGridsquare listener not attached (Events unavailable)")
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
					Log:info("LoadGridsquare listener detached (no onLoad interest)")
				end
			end
		end
		return false
	end
end

OnLoad._internal.attachListenerOnce = attachListenerOnce
OnLoad._internal.emitWithCooldown = emitWithCooldown
OnLoad._internal.highlightFloor = Highlight.highlightFloor

return OnLoad
