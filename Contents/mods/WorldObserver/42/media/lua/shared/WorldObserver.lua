-- WorldObserver.lua -- public facade: wires LuaEvent, loads config, and registers facts/streams/helpers.

-- Bootstrap LQR early to expand package.path for util.log/reactivex and friends.
local _LQRBootstrap = require("LQR")

local okLuaEvent, LuaEventOrError = pcall(require, "Starlit/LuaEvent")
if okLuaEvent and _G.Events and _G.Events.setLuaEvent then
	-- Wire Starlit LuaEvent when available so downstream mods can emit/observe it.
	-- We also clear any Runtime-tracked LuaEvent error so consumers know the hook is healthy.
	Events.setLuaEvent(LuaEventOrError)
	if _G.Runtime and Runtime.setLuaEventError then
		Runtime.setLuaEventError(nil)
	end
elseif _G.Events and _G.Events.setLuaEvent then
	-- LuaEvent failed to load: publish the failure into Runtime so consumers can diagnose it.
	Events.setLuaEvent(nil)
	if _G.Runtime and Runtime.setLuaEventError then
		Runtime.setLuaEventError(LuaEventOrError)
	end
end

local Config = require("WorldObserver/config")
local FactRegistry = require("WorldObserver/facts/registry")
local SquaresFacts = require("WorldObserver/facts/squares")
local ObservationsCore = require("WorldObserver/observations/core")
local SquaresObservations = require("WorldObserver/observations/squares")
local SquareHelpers = require("WorldObserver/helpers/square")
local Debug = require("WorldObserver/debug")
local Runtime = require("WorldObserver/runtime")

local WorldObserver

local config = Config.load()
local runtimeOpts = {}
do
	local cfg = config.runtime and config.runtime.controller or {}
	for k, v in pairs(cfg) do
		runtimeOpts[k] = v
	end
	local base = config.ingest and config.ingest.scheduler and config.ingest.scheduler.maxItemsPerTick
	if type(base) == "number" and base > 0 then
		runtimeOpts.baseDrainMaxItems = base
	end
end
local runtime = Runtime.new(runtimeOpts)
local runtimeDiagnosticsHandle = nil
local debugApi = nil
local function setRuntimeDiagnosticsActive(active)
	local headless = config and config.facts and config.facts.squares and config.facts.squares.headless == true
	if headless then
		return
	end
	if not debugApi or not debugApi.attachRuntimeDiagnostics then
		return
	end
	local diagCfg = config and config.runtime and config.runtime.controller and config.runtime.controller.diagnostics
	if not (diagCfg and diagCfg.enabled) then
		return
	end
	if active then
		if not runtimeDiagnosticsHandle then
			runtimeDiagnosticsHandle = debugApi.attachRuntimeDiagnostics({})
			if WorldObserver and WorldObserver._internal then
				WorldObserver._internal.runtimeDiagnosticsHandle = runtimeDiagnosticsHandle
			end
		end
	else
		if runtimeDiagnosticsHandle and runtimeDiagnosticsHandle.stop then
			pcall(runtimeDiagnosticsHandle.stop)
		end
		runtimeDiagnosticsHandle = nil
		if WorldObserver and WorldObserver._internal then
			WorldObserver._internal.runtimeDiagnosticsHandle = nil
		end
	end
end

local factRegistry = FactRegistry.new(config, runtime, {
	-- Stop DIAG spam when nothing is subscribed (e.g. smoke handle:stop()).
	onFirstSubscriber = function()
		setRuntimeDiagnosticsActive(true)
	end,
	onLastSubscriber = function()
		setRuntimeDiagnosticsActive(false)
	end,
})

-- Convenience: emergency reset that clears ingest buffers (pending items) and emits a runtime status change.
function runtime:emergency_resetIngest()
	return self:emergency_reset({
		onReset = function()
			factRegistry:ingest_clearAll()
		end,
	})
end

SquaresFacts.register(factRegistry, config)

local observationRegistry = ObservationsCore.new({
	factRegistry = factRegistry,
	config = config,
	helperSets = {
		square = SquareHelpers,
	},
})

SquaresObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)

		WorldObserver = {
			config = config,
			observations = observationRegistry:api(),
			helpers = {
				square = SquareHelpers,
			},
			highlight = SquareHelpers.highlight,
			debug = nil,
			nextObservationId = ObservationsCore.nextObservationId,
			runtime = runtime,
			_internal = {
				-- Expose internals for tests and advanced users until a fuller API exists.
				runtime = runtime,
				facts = factRegistry,
				observationRegistry = observationRegistry,
				runtimeDiagnosticsHandle = nil,
			},
		}

	debugApi = Debug.new(factRegistry, observationRegistry)
		WorldObserver.debug = debugApi

	-- Register runtime controller LuaEvents and attach default diagnostics (engine-only).
	do
			local headless = config and config.facts and config.facts.squares and config.facts.squares.headless == true
			if not headless then
				if _G.LuaEventManager and type(_G.LuaEventManager.AddEvent) == "function" then
					pcall(_G.LuaEventManager.AddEvent, "WorldObserverRuntimeStatusChanged")
					pcall(_G.LuaEventManager.AddEvent, "WorldObserverRuntimeStatusReport")
				end
			end
		end

return WorldObserver
