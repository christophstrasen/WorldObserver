-- facts/players/on_player_update.lua -- optional OnPlayerUpdate listener gated by declared interest.
local Log = require("DREAMBase/log").withTag("WO.FACTS.players")
local Time = require("WorldObserver/helpers/time")
local Cooldown = require("WorldObserver/facts/cooldown")
local InterestEffective = require("WorldObserver/facts/interest_effective")
local Highlight = require("WorldObserver/helpers/highlight")
local SquareHelpers = require("WorldObserver/helpers/square")

local moduleName = ...
local OnPlayerUpdate = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		OnPlayerUpdate = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = OnPlayerUpdate
	end
end
OnPlayerUpdate._internal = OnPlayerUpdate._internal or {}

local INTEREST_TYPE_PLAYERS = "players"
local INTEREST_SCOPE_UPDATE = "onPlayerUpdate"

local function nowMillis()
	return Time.gameMillis() or math.floor(os.time() * 1000)
end

local function highlightPlayerSquare(record, effective, highlightPref)
	if record == nil then
		return
	end
	local square = record.IsoGridSquare
	if square == nil then
		return
	end
	local durationMs = Highlight.durationMsFromEffectiveCadence(effective)
	if durationMs <= 0 then
		return
	end
	local color, alpha = Highlight.resolveColorAlpha(highlightPref, nil, 0.7)
	SquareHelpers.highlight(square, durationMs, { color = color, alpha = alpha })
end

local function emitWithCooldown(state, emitFn, record, nowMs, cooldownMs, onEmitFn)
	if type(emitFn) ~= "function" or type(record) ~= "table" or record.playerKey == nil then
		return false
	end
	state.lastEmittedMs = state.lastEmittedMs or {}
	if not Cooldown.shouldEmit(state.lastEmittedMs, record.playerKey, nowMs, cooldownMs) then
		return false
	end
	if type(onEmitFn) == "function" then
		pcall(onEmitFn, record)
	end
	emitFn(record)
	Cooldown.markEmitted(state.lastEmittedMs, record.playerKey, nowMs)
	return true
end

local function attachListenerOnce(ctx)
	local state = ctx.state or {}
	if state.onPlayerUpdateHandler then
		return true
	end

	local events = _G.Events
	local handler = events and events.OnPlayerUpdate
	if not handler or type(handler.Add) ~= "function" then
		return false
	end

	local fn = function(player)
		local effectiveByType = state._effectiveInterestByType
		local effectiveByBucket = effectiveByType and effectiveByType[INTEREST_TYPE_PLAYERS] or nil
		local effective = type(effectiveByBucket) == "table" and effectiveByBucket[INTEREST_SCOPE_UPDATE] or nil
		if not effective then
			return
		end

		local players = ctx.players
		if not (players and type(players.makePlayerRecord) == "function") then
			return
		end

		local record = players.makePlayerRecord(player, "event", { scope = INTEREST_SCOPE_UPDATE })
		if record == nil then
			return
		end

		local updateState = state._playerUpdate or {}
		state._playerUpdate = updateState
		local cooldownMs = math.max(0, (tonumber(effective.cooldown) or 0) * 1000)
		emitWithCooldown(updateState, ctx.emitFn, record, nowMillis(), cooldownMs, function()
			if ctx.headless then
				return
			end
			local highlightPref = effective.highlight
			if highlightPref == true or type(highlightPref) == "table" then
				highlightPlayerSquare(record, effective, highlightPref)
			end
		end)
	end

	handler.Add(fn)
	state.onPlayerUpdateHandler = fn
	if not ctx.headless then
		Log:info("OnPlayerUpdate listener attached")
	end
	return true
end

if OnPlayerUpdate.ensure == nil then
	--- Ensure the OnPlayerUpdate listener is attached/detached based on declared interest.
	--- @param ctx table
	--- @return boolean active
	function OnPlayerUpdate.ensure(ctx)
		ctx = ctx or {}
		local state = ctx.state or {}
		ctx.state = state

		local listenerCfg = ctx.listenerCfg or {}
		local listenerEnabled = listenerCfg.enabled ~= false

		local effective = nil
		if listenerEnabled then
			effective = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, INTEREST_TYPE_PLAYERS, {
				label = "onPlayerUpdate",
				allowDefault = false,
				log = Log,
				bucketKey = INTEREST_SCOPE_UPDATE,
			})
			if effective and ctx.interestRegistry and ctx.interestRegistry.effective then
				local okMerged, merged = pcall(function()
					return ctx.interestRegistry:effective(INTEREST_TYPE_PLAYERS, nil, { bucketKey = INTEREST_SCOPE_UPDATE })
				end)
				if okMerged and type(merged) == "table" then
					effective.highlight = merged.highlight
				end
			end
		else
			state._effectiveInterestByType = state._effectiveInterestByType or {}
			if type(state._effectiveInterestByType[INTEREST_TYPE_PLAYERS]) == "table" then
				state._effectiveInterestByType[INTEREST_TYPE_PLAYERS][INTEREST_SCOPE_UPDATE] = nil
			end
		end

		local wantsListener = listenerEnabled and effective ~= nil
		if wantsListener then
			local okListener = attachListenerOnce(ctx)
			if not okListener and not ctx.headless then
				Log:warn("OnPlayerUpdate listener not attached (Events unavailable)")
			end
			return state.onPlayerUpdateHandler ~= nil
		end

		if state.onPlayerUpdateHandler then
			local events = _G.Events
			local handler = events and events.OnPlayerUpdate
			if handler and type(handler.Remove) == "function" then
				pcall(handler.Remove, handler, state.onPlayerUpdateHandler)
				state.onPlayerUpdateHandler = nil
				if not ctx.headless then
					Log:info("OnPlayerUpdate listener detached (no onPlayerUpdate interest)")
				end
			end
		end
		return false
	end
end

OnPlayerUpdate._internal.attachListenerOnce = attachListenerOnce
OnPlayerUpdate._internal.emitWithCooldown = emitWithCooldown

return OnPlayerUpdate
