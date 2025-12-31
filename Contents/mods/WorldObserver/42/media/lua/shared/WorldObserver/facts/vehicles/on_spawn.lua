-- facts/vehicles/on_spawn.lua -- optional OnSpawnVehicleEnd listener gated by declared interest.
local Log = require("DREAMBase/log").withTag("WO.FACTS.vehicles")
local Cooldown = require("WorldObserver/facts/cooldown")
local InterestEffective = require("WorldObserver/facts/interest_effective")
local Record = require("WorldObserver/facts/vehicles/record")
local Time = require("DREAMBase/time_ms")
local Highlight = require("WorldObserver/helpers/highlight")
local SquareHelpers = require("WorldObserver/helpers/square")

local INTEREST_TYPE_VEHICLES = "vehicles"
local INTEREST_SCOPE_ALL = "allLoaded"

local moduleName = ...
local OnSpawn = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		OnSpawn = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = OnSpawn
	end
end
OnSpawn._internal = OnSpawn._internal or {}

local function nowMillis()
	return Time.gameMillis() or math.floor(os.time() * 1000)
end

local function shouldHighlight(pref)
	return pref == true or type(pref) == "table"
end

local function emitWithCooldown(ctx, vehicle, effective)
	if not (ctx and ctx.emitFn and type(ctx.emitFn) == "function") then
		return false
	end
	local state = ctx.state or {}
	ctx.state = state

	state._onSpawn = state._onSpawn or {}
	state._onSpawn.lastEmittedById = state._onSpawn.lastEmittedById or {}
	local emittedByKey = state._onSpawn.lastEmittedById

	local nowMs = nowMillis()
	local record = ctx.makeVehicleRecord(vehicle, "event", { headless = ctx.headless })
	if record == nil then
		return false
	end
	local key = Record.keyFromRecord(record)
	if key == nil then
		return false
	end

	local cooldownSeconds = tonumber(effective and effective.cooldown) or 0
	local cooldownMs = math.max(0, cooldownSeconds * 1000)
	if not Cooldown.shouldEmit(emittedByKey, key, nowMs, cooldownMs) then
		return false
	end

	ctx.emitFn(record)
	Cooldown.markEmitted(emittedByKey, key, nowMs)

	if ctx.headless ~= true and shouldHighlight(effective and effective.highlight) then
		local highlightMs = Highlight.durationMsFromEffectiveCadence(effective)
		if highlightMs > 0 then
			local color, alpha = Highlight.resolveColorAlpha(effective and effective.highlight, { 1, 0.2, 0.2 }, 0.7)
			local square = record.IsoGridSquare
			if square ~= nil then
				SquareHelpers.highlight(square, highlightMs, { alpha = alpha, color = color })
			end
		end
	end

	return true
end

local function attachListenerOnce(ctx)
	ctx = ctx or {}
	local state = ctx.state or {}
	ctx.state = state

	if state.onSpawnVehicleHandler then
		return true
	end

	local events = _G.Events
	local handler = events and events.OnSpawnVehicleEnd
	if not handler or type(handler.Add) ~= "function" then
		return false
	end

	local fn = function(vehicle)
		local effective = state.onSpawnEffective
		if effective == nil then
			return
		end
		emitWithCooldown(ctx, vehicle, effective)
	end

	handler.Add(fn)
	state.onSpawnVehicleHandler = fn
	if ctx.headless ~= true then
		Log:info("OnSpawnVehicleEnd listener attached")
	end
	return true
end

if OnSpawn.ensure == nil then
	--- Ensure the OnSpawnVehicleEnd listener is attached/detached based on declared interest.
	--- @param ctx table
	--- @return boolean active
	function OnSpawn.ensure(ctx)
		ctx = ctx or {}
		local state = ctx.state or {}
		ctx.state = state

		local listenerCfg = ctx.listenerCfg or {}
		local listenerEnabled = listenerCfg.enabled ~= false

		local effective = nil
		if listenerEnabled then
			effective = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, INTEREST_TYPE_VEHICLES, {
				label = "vehicles.onSpawn",
				allowDefault = false,
				log = Log,
				bucketKey = INTEREST_SCOPE_ALL,
			})
			if effective and ctx.interestRegistry and ctx.interestRegistry.effective then
				local okMerged, merged = pcall(function()
					return ctx.interestRegistry:effective(INTEREST_TYPE_VEHICLES, nil, { bucketKey = INTEREST_SCOPE_ALL })
				end)
				if okMerged and type(merged) == "table" then
					effective.highlight = merged.highlight
				end
			end
		else
			state._effectiveInterestByType = state._effectiveInterestByType or {}
			if type(state._effectiveInterestByType[INTEREST_TYPE_VEHICLES]) == "table" then
				state._effectiveInterestByType[INTEREST_TYPE_VEHICLES][INTEREST_SCOPE_ALL] = nil
			end
		end

		state.onSpawnEffective = effective
		ctx.makeVehicleRecord = ctx.makeVehicleRecord or Record.makeVehicleRecord

		local wantsListener = listenerEnabled and effective ~= nil
		if wantsListener then
			local okListener = attachListenerOnce(ctx)
			if not okListener and ctx.headless ~= true then
				Log:warn("OnSpawnVehicleEnd listener not attached (Events unavailable)")
			end
			return state.onSpawnVehicleHandler ~= nil
		end

		if state.onSpawnVehicleHandler then
			local events = _G.Events
			local handler = events and events.OnSpawnVehicleEnd
			if handler and type(handler.Remove) == "function" then
				pcall(handler.Remove, handler, state.onSpawnVehicleHandler)
				state.onSpawnVehicleHandler = nil
				if ctx.headless ~= true then
					Log:info("OnSpawnVehicleEnd listener detached (no vehicles interest)")
				end
			end
		end
		return false
	end
end

OnSpawn._internal.attachListenerOnce = attachListenerOnce
OnSpawn._internal.emitWithCooldown = emitWithCooldown

return OnSpawn
