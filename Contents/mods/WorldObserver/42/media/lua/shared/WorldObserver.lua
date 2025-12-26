-- WorldObserver.lua -- public facade: wires LuaEvent, loads config, and registers facts/streams/helpers.

-- Bootstrap LQR early to expand package.path for util.log/reactivex and friends.
local _LQRBootstrap = require("LQR")
do
	-- WorldObserver stamps RxMeta.sourceTime in milliseconds; configure LQR's default window clock to match.
	-- This keeps time/interval windows ergonomic (no need to pass currentFn everywhere) while remaining overridable
	-- via LQR.Query.setDefaultCurrentFn.
	local okTime, Time = pcall(require, "WorldObserver/helpers/time")
	if okTime and _LQRBootstrap and _LQRBootstrap.Query and type(_LQRBootstrap.Query.setDefaultCurrentFn) == "function" then
		_LQRBootstrap.Query.setDefaultCurrentFn(Time.gameMillis)
	end
end

local okLuaEvent, LuaEventOrError = pcall(require, "Starlit/LuaEvent")
if okLuaEvent and _G.Events and _G.Events.setLuaEvent then
	-- Wire Starlit LuaEvent when available so downstream mods can emit/observe it.
	-- We also clear any Runtime-tracked LuaEvent error so consumers know the hook is healthy.
	Events.setLuaEvent(LuaEventOrError)
	if _G.Runtime and _G.Runtime.setLuaEventError then
		_G.Runtime.setLuaEventError(nil)
	end
elseif _G.Events and _G.Events.setLuaEvent then
	-- LuaEvent failed to load: publish the failure into Runtime so consumers can diagnose it.
	Events.setLuaEvent(nil)
	if _G.Runtime and _G.Runtime.setLuaEventError then
		_G.Runtime.setLuaEventError(LuaEventOrError)
	end
end

	local Config = require("WorldObserver/config")
	local FactRegistry = require("WorldObserver/facts/registry")
	local SquaresFacts = require("WorldObserver/facts/squares")
	local ZombiesFacts = require("WorldObserver/facts/zombies")
	local RoomsFacts = require("WorldObserver/facts/rooms")
	local ItemsFacts = require("WorldObserver/facts/items")
	local DeadBodiesFacts = require("WorldObserver/facts/dead_bodies")
	local SpritesFacts = require("WorldObserver/facts/sprites")
	local VehiclesFacts = require("WorldObserver/facts/vehicles")
local ObservationsCore = require("WorldObserver/observations/core")
local SquaresObservations = require("WorldObserver/observations/squares")
local ZombiesObservations = require("WorldObserver/observations/zombies")
local RoomsObservations = require("WorldObserver/observations/rooms")
local ItemsObservations = require("WorldObserver/observations/items")
local DeadBodiesObservations = require("WorldObserver/observations/dead_bodies")
local SpritesObservations = require("WorldObserver/observations/sprites")
local VehiclesObservations = require("WorldObserver/observations/vehicles")
local SquareHelpers = require("WorldObserver/helpers/square")
local ZombieHelpers = require("WorldObserver/helpers/zombie")
local RoomHelpers = require("WorldObserver/helpers/room")
local ItemHelpers = require("WorldObserver/helpers/item")
	local DeadBodyHelpers = require("WorldObserver/helpers/dead_body")
	local SpriteHelpers = require("WorldObserver/helpers/sprite")
	local VehicleHelpers = require("WorldObserver/helpers/vehicle")
	local InterestRegistry = require("WorldObserver/interest/registry")
	local Debug = require("WorldObserver/debug")
	local Runtime = require("WorldObserver/runtime")

	local WorldObserver
	
	local config = Config.loadFromGlobals()
	assert(type(config) == "table", "WorldObserver config must be a table")
	assert(type(config.facts) == "table", "WorldObserver config must include facts")
	assert(type(config.facts.squares) == "table", "WorldObserver config must include facts.squares")
	assert(type(config.facts.rooms) == "table", "WorldObserver config must include facts.rooms")
	assert(type(config.facts.items) == "table", "WorldObserver config must include facts.items")
	assert(type(config.facts.deadBodies) == "table", "WorldObserver config must include facts.deadBodies")
	assert(type(config.facts.sprites) == "table", "WorldObserver config must include facts.sprites")
	assert(type(config.facts.vehicles) == "table", "WorldObserver config must include facts.vehicles")
	assert(type(config.runtime) == "table", "WorldObserver config must include runtime")
	assert(type(config.runtime.controller) == "table", "WorldObserver config must include runtime.controller")

	---@class WorldObserverRuntimeWithIngestReset : WorldObserverRuntime
	---@field emergency_resetIngest fun(self:WorldObserverRuntimeWithIngestReset)

	---@type WorldObserverRuntimeWithIngestReset
	local runtime = Runtime.new(Config.runtimeOpts(config))
	local runtimeDiagnosticsHandle = nil
	local debugApi = nil

	---@type WOInterestRegistry
	local interestRegistry = InterestRegistry.new({})
	local headless = config.facts.squares.headless == true
	local function setRuntimeDiagnosticsActive(active)
		if headless then
			return
		end
		if not debugApi or type(debugApi.attachRuntimeDiagnostics) ~= "function" then
			return
		end
		local diagCfg = config.runtime.controller.diagnostics
		if diagCfg == nil or diagCfg.enabled ~= true then
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

SquaresFacts.register(factRegistry, config, interestRegistry)
ZombiesFacts.register(factRegistry, config, interestRegistry)
RoomsFacts.register(factRegistry, config, interestRegistry)
ItemsFacts.register(factRegistry, config, interestRegistry)
DeadBodiesFacts.register(factRegistry, config, interestRegistry)
SpritesFacts.register(factRegistry, config, interestRegistry)
VehiclesFacts.register(factRegistry, config, interestRegistry)

local observationRegistry = ObservationsCore.new({
	factRegistry = factRegistry,
	config = config,
	helperSets = {
		square = SquareHelpers,
		zombie = ZombieHelpers,
		room = RoomHelpers,
		item = ItemHelpers,
		deadBody = DeadBodyHelpers,
		sprite = SpriteHelpers,
		vehicle = VehicleHelpers,
	},
})

SquaresObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)
ZombiesObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)
RoomsObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)
ItemsObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)
DeadBodiesObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)
SpritesObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)
VehiclesObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)

WorldObserver = {
	config = config,
	observations = observationRegistry:api(),
	factInterest = {
		declare = function(_, modId, key, spec, opts)
			return interestRegistry:declare(modId, key, spec, opts)
		end,
		revoke = function(_, modId, key)
			return interestRegistry:revoke(modId, key)
		end,
		effective = function(_, factType, opts)
			-- Returns the merged interest bands for a type. For bucketed interest types (like `squares`),
			-- this returns the single bucket only when exactly one exists; otherwise use `effectiveBuckets`.
			return interestRegistry:effective(factType, nil, opts)
		end,
		effectiveBuckets = function(_, factType, opts)
			-- Bucketed interests allow multiple independent targets under the same type.
			-- Example: `squares` can have a near player bucket and one or more static square buckets.
			-- Probes iterate these buckets deterministically and schedule them under a shared budget.
			if interestRegistry and interestRegistry.effectiveBuckets then
				return interestRegistry:effectiveBuckets(factType, nil, opts)
			end
			return {}
		end,
	},
	helpers = {
		square = SquareHelpers,
		zombie = ZombieHelpers,
		room = RoomHelpers,
		item = ItemHelpers,
		deadBody = DeadBodyHelpers,
		sprite = SpriteHelpers,
		vehicle = VehicleHelpers,
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
		factInterest = interestRegistry,
		runtimeDiagnosticsHandle = nil,
	},
}

	debugApi = Debug.new(factRegistry, observationRegistry)
	WorldObserver.debug = debugApi
	
		-- Register runtime controller LuaEvents and attach default diagnostics (engine-only).
		do
			if not headless then
				if _G.LuaEventManager and type(_G.LuaEventManager.AddEvent) == "function" then
					pcall(_G.LuaEventManager.AddEvent, "WorldObserverRuntimeStatusChanged")
					pcall(_G.LuaEventManager.AddEvent, "WorldObserverRuntimeStatusReport")
			end
		end
	end

return WorldObserver
