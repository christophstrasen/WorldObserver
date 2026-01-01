-- facts/squares.lua -- square fact plan: listeners + interest-driven probes to emit SquareObservation facts.
local Log = require("DREAMBase/log").withTag("WO.FACTS.squares")

local Record = require("WorldObserver/facts/squares/record")
local Geometry = require("WorldObserver/facts/squares/geometry")
local Probe = require("WorldObserver/facts/squares/probe")
local SquareSweep = require("WorldObserver/facts/sensors/square_sweep")
local Highlight = require("WorldObserver/helpers/highlight")
local Cooldown = require("WorldObserver/facts/cooldown")
local OnLoad = require("WorldObserver/facts/squares/on_load")

-- `squares` is the canonical squares probe type. We split behavior by scope (near/vision/etc).
-- It can represent multiple target buckets (for example: player vs static square) under the same fact type.
local INTEREST_TYPE_SQUARES = "squares"

local moduleName = ...
local Squares = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Squares = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Squares
	end
end

Squares._internal = Squares._internal or {}
Squares._defaults = Squares._defaults or {}
Squares._defaults.interest = Squares._defaults.interest or {
	staleness = { desired = 10, tolerable = 20 },
	radius = { desired = 8, tolerable = 5 },
	cooldown = { desired = 30, tolerable = 60 },
}

local SQUARES_TICK_HOOK_ID = "facts.squares.tick"

local function hasActiveLease(interestRegistry, interestType)
	if not interestRegistry then
		return false
	end
	if type(interestRegistry.effectiveBuckets) == "function" then
		local ok, buckets = pcall(interestRegistry.effectiveBuckets, interestRegistry, interestType)
		return ok and type(buckets) == "table" and buckets[1] ~= nil
	end
	if type(interestRegistry.effective) ~= "function" then
		return false
	end
	local ok, merged = pcall(interestRegistry.effective, interestRegistry, interestType)
	return ok and merged ~= nil
end

local function hasSquaresScopeInterest(interestRegistry, scope)
	if not interestRegistry then
		return false
	end
	if type(interestRegistry.effectiveBuckets) == "function" then
		local ok, buckets = pcall(interestRegistry.effectiveBuckets, interestRegistry, INTEREST_TYPE_SQUARES)
		if not ok or type(buckets) ~= "table" then
			return false
		end
		for _, entry in ipairs(buckets) do
			local merged = entry.merged
			if type(merged) == "table" and merged.scope == scope then
				return true
			end
		end
		return false
	end
	if type(interestRegistry.effective) == "function" then
		local ok, merged = pcall(interestRegistry.effective, interestRegistry, INTEREST_TYPE_SQUARES)
		return ok and type(merged) == "table" and merged.scope == scope
	end
	return false
end

-- Default square record builder.
-- Intentionally exposed via Squares.makeSquareRecord so other mods can patch/override it.
if Squares.makeSquareRecord == nil then
	function Squares.makeSquareRecord(square, source)
		return Record.makeSquareRecord(square, source)
	end
end
Squares._defaults.makeSquareRecord = Squares._defaults.makeSquareRecord or Squares.makeSquareRecord

local function squareCollector(ctx, cursor, square, _playerIndex, nowMs, effective)
	local squares = ctx.squares
	if not (squares and type(squares.makeSquareRecord) == "function") then
		return false
	end

	local record = squares.makeSquareRecord(square, cursor.source)
	if not (type(record) == "table" and record.squareId ~= nil) then
		return false
	end

	local state = ctx.state or {}
	state._squareCollector = state._squareCollector or {}
	local emittedByKey = state._squareCollector.lastEmittedMs or {}
	state._squareCollector.lastEmittedMs = emittedByKey
	local cooldownSeconds = tonumber(effective and effective.cooldown) or 0
	local cooldownMs = math.max(0, cooldownSeconds * 1000)
	if not Cooldown.shouldEmit(emittedByKey, record.squareId, nowMs, cooldownMs) then
		return false
	end

	if not ctx.headless and effective and effective.highlight == true then
		local highlightMs = Highlight.durationMsFromEffectiveCadence(effective)
		if highlightMs > 0 then
			local okFloor, floor = pcall(square.getFloor, square)
			if okFloor and floor then
				Highlight.highlightTarget(floor, {
					durationMs = highlightMs,
					color = cursor.color,
					alpha = cursor.alpha,
				})
			end
		end
	end

	if type(ctx.emitFn) == "function" then
		ctx.emitFn(record)
		Cooldown.markEmitted(emittedByKey, record.squareId, nowMs)
	end
	return true
end

if Squares._internal.registerSquareCollector == nil then
	function Squares._internal.registerSquareCollector()
		SquareSweep.registerCollector("squares", squareCollector, { interestType = INTEREST_TYPE_SQUARES })
	end
end
Squares._internal.registerSquareCollector()

local function tickSquares(ctx)
	ctx = ctx or {}
	local state = ctx.state or {}
	ctx.state = state

	OnLoad.ensure({
		state = state,
		squares = Squares,
		emitFn = ctx.emitFn,
		headless = ctx.headless,
		runtime = ctx.runtime,
		interestRegistry = ctx.interestRegistry,
		listenerCfg = ctx.listenerCfg,
	})
end

local function attachTickHookOnce(state, emitFn, ctx)
	if state.squaresTickHookAttached then
		return true
	end
	local factRegistry = ctx.factRegistry
	if not factRegistry or type(factRegistry.attachTickHook) ~= "function" then
		if not ctx.headless then
			Log:warn("Squares tick hook not attached (FactRegistry.attachTickHook unavailable)")
		end
		return false
	end

	local fn = function()
		tickSquares({
			state = state,
			emitFn = emitFn,
			headless = ctx.headless,
			runtime = ctx.runtime,
			interestRegistry = ctx.interestRegistry,
			probeCfg = ctx.probeCfg,
			listenerCfg = ctx.listenerCfg,
		})
	end

	factRegistry:attachTickHook(SQUARES_TICK_HOOK_ID, fn)
	state.squaresTickHookAttached = true
	state.squaresTickHookId = SQUARES_TICK_HOOK_ID
	return true
end

Squares._internal.iterSquaresInRing = Geometry.iterSquaresInRing
Squares._internal.buildRingOffsets = Geometry.buildRingOffsets
Squares._internal.nearbyPlayers = Probe._internal.nearbyPlayers
Squares._internal.probeTick = function(state, emitFn, headless, runtime, interestRegistry, probeCfg)
	Probe.tick({
		state = state,
		squares = Squares,
		emitFn = emitFn,
		headless = headless,
		runtime = runtime,
		interestRegistry = interestRegistry,
		defaultInterest = Squares._defaults.interest,
		probeCfg = probeCfg or {},
	})
end
Squares._internal.attachTickHookOnce = attachTickHookOnce

-- Patch seam: define only when nil so mods can override by reassigning `Squares.register` and so reloads
	-- (tests/console via `package.loaded`) don't clobber an existing patch.
	if Squares.register == nil then
		function Squares.register(registry, config, interestRegistry)
			assert(type(config) == "table", "SquaresFacts.register expects config table")
			assert(type(config.facts) == "table", "SquaresFacts.register expects config.facts table")
			assert(type(config.facts.squares) == "table", "SquaresFacts.register expects config.facts.squares table")
			local squaresCfg = config.facts.squares
			local headless = squaresCfg.headless == true
				local probeCfg = squaresCfg.probe or {}
				local probeEnabled = probeCfg.enabled ~= false
				local listenerCfg = squaresCfg.listener or {}
				local listenerEnabled = listenerCfg.enabled ~= false

			registry:register("squares", {
			ingest = {
				mode = "latestByKey",
				ordering = "fifo",
				key = function(record)
					return record and record.squareId
				end,
				lane = function(record)
					return (record and record.source) or "default"
				end,
				lanePriority = function(laneName)
					if laneName == "probe" or laneName == "probe_vision" then
						return 2
					end
					if laneName == "event" then
						return 1
					end
					return 1
				end,
			},
			start = function(ctx)
				local state = ctx.state or {}
				local originalEmit = ctx.ingest or ctx.emit
				local tickHookAttached = Squares._internal.attachTickHookOnce(state, originalEmit, {
					factRegistry = registry,
					headless = headless,
					runtime = ctx.runtime,
					interestRegistry = interestRegistry,
					probeCfg = probeCfg,
					listenerCfg = listenerCfg,
				})
				local sweepRegistered = false
				if probeEnabled then
					local ok = SquareSweep.registerConsumer(INTEREST_TYPE_SQUARES, {
						collectorId = INTEREST_TYPE_SQUARES,
						interestType = INTEREST_TYPE_SQUARES,
						emitFn = originalEmit,
						context = { squares = Squares },
						headless = headless,
						runtime = ctx.runtime,
						interestRegistry = interestRegistry,
						probeCfg = probeCfg,
						probePriority = 10,
						factRegistry = registry,
					})
					sweepRegistered = ok == true
				end

					if not headless then
							local hasOnLoadInterest = hasSquaresScopeInterest(interestRegistry, "onLoad")
							local hasNearInterest = hasSquaresScopeInterest(interestRegistry, "near")
							local hasVisionInterest = hasSquaresScopeInterest(interestRegistry, "vision")
							Log:info(
								"Squares facts started (tickHook=%s sweep=%s cfgProbe=%s cfgListener=%s "
									.. "interestOnLoad=%s interestNear=%s interestVision=%s)",
								tostring(tickHookAttached),
								tostring(sweepRegistered),
								tostring(probeEnabled),
							tostring(listenerEnabled),
							tostring(hasOnLoadInterest),
							tostring(hasNearInterest),
							tostring(hasVisionInterest)
						)
					end

					ctx.emit = originalEmit
				ctx.ingest = originalEmit
			end,
			stop = function(entry)
				local state = entry.state or {}
				local events = _G.Events
				local fullyStopped = true

				if entry.buffer and entry.buffer.clear then
					entry.buffer:clear()
				end

				if state.loadGridsquareHandler then
					local handler = events and events.LoadGridsquare
					if handler and type(handler.Remove) == "function" then
						pcall(handler.Remove, handler, state.loadGridsquareHandler)
						state.loadGridsquareHandler = nil
					else
						fullyStopped = false
					end
				end

				if state.squaresTickHookAttached then
					if registry and type(registry.detachTickHook) == "function" then
						pcall(registry.detachTickHook, registry, state.squaresTickHookId or SQUARES_TICK_HOOK_ID)
						state.squaresTickHookAttached = nil
						state.squaresTickHookId = nil
					else
						fullyStopped = false
					end
				end

				if probeEnabled then
					SquareSweep.unregisterConsumer(INTEREST_TYPE_SQUARES)
				end

				if not fullyStopped and not headless then
					Log:warn("Squares fact stop requested but could not remove all handlers; keeping started=true")
				end

				return fullyStopped
			end,
		})

		return {
			makeSquareRecord = function(square, source)
				return Squares.makeSquareRecord(square, source)
			end,
			defaultMakeSquareRecord = Squares._defaults.makeSquareRecord,
			_internal = Squares._internal,
		}
	end
end

return Squares
