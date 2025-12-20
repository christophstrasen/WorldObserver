-- facts/squares.lua -- square fact plan: listeners + interest-driven probes to emit SquareObservation facts.
local Log = require("LQR/util/log").withTag("WO.FACTS.squares")

local Record = require("WorldObserver/facts/squares/record")
local Geometry = require("WorldObserver/facts/squares/geometry")
local Probe = require("WorldObserver/facts/squares/probe")
local OnLoad = require("WorldObserver/facts/squares/on_load")

-- `squares` is the canonical squares probe type. We split behavior by scope (near/vision/etc).
-- It can represent multiple target buckets (for example: player vs static square) under the same fact type.
local INTEREST_TYPE_SQUARES = "squares"

local moduleName = ...
local Squares = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Squares = loaded
	else
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

	local probeCfg = ctx.probeCfg or {}
	if probeCfg.enabled ~= false then
		Probe.tick({
			state = state,
			squares = Squares,
			emitFn = ctx.emitFn,
			headless = ctx.headless,
			runtime = ctx.runtime,
			interestRegistry = ctx.interestRegistry,
			defaultInterest = Squares._defaults.interest,
			probeCfg = probeCfg,
		})
	end
end

local function registerTickHook(state, emitFn, ctx)
	if state.squaresTickHookRegistered then
		return true
	end
	local factRegistry = ctx.factRegistry
	if not factRegistry or type(factRegistry.tickHook_add) ~= "function" then
		if not ctx.headless then
			Log:warn("Squares tick hook not registered (FactRegistry.tickHook_add unavailable)")
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

	factRegistry:tickHook_add(SQUARES_TICK_HOOK_ID, fn)
	state.squaresTickHookRegistered = true
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
Squares._internal.registerTickHook = registerTickHook

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
				local tickHookRegistered = Squares._internal.registerTickHook(state, originalEmit, {
					factRegistry = registry,
					headless = headless,
					runtime = ctx.runtime,
					interestRegistry = interestRegistry,
					probeCfg = probeCfg,
					listenerCfg = listenerCfg,
				})

					if not headless then
						local hasOnLoadInterest = hasSquaresScopeInterest(interestRegistry, "onLoad")
						local hasNearInterest = hasSquaresScopeInterest(interestRegistry, "near")
						local hasVisionInterest = hasSquaresScopeInterest(interestRegistry, "vision")
						Log:info(
							"Squares facts started (tickHook=%s cfgProbe=%s cfgListener=%s interestOnLoad=%s interestNear=%s interestVision=%s)",
							tostring(tickHookRegistered),
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

				if state.squaresTickHookRegistered then
					if registry and type(registry.tickHook_remove) == "function" then
						pcall(registry.tickHook_remove, registry, state.squaresTickHookId or SQUARES_TICK_HOOK_ID)
						state.squaresTickHookRegistered = nil
						state.squaresTickHookId = nil
					else
						fullyStopped = false
					end
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
