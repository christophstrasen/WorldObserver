-- WorldObserver.lua -- public facade: wires LuaEvent, loads config, and registers facts/streams/helpers.

-- Bootstrap LQR early to expand package.path for util.log/reactivex and friends.
local _LQRBootstrap = require("LQR")
do
	-- WorldObserver stamps RxMeta.sourceTime in milliseconds; configure LQR's default window clock to match.
	-- This keeps time/interval windows ergonomic (no need to pass currentFn everywhere) while remaining overridable
	-- via LQR.Query.setDefaultCurrentFn.
	--
	-- WHY: If we ever fail to set this, LQR defaults to whatever clock it ships with, and we end up with
	-- subtle, hard-to-debug window behaviour differences across the suite.
	local Time = require("DREAMBase/time_ms")
	if _LQRBootstrap and _LQRBootstrap.Query and type(_LQRBootstrap.Query.setDefaultCurrentFn) == "function" then
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
local PlayersFacts = require("WorldObserver/facts/players")
local RoomsFacts = require("WorldObserver/facts/rooms")
local ItemsFacts = require("WorldObserver/facts/items")
local DeadBodiesFacts = require("WorldObserver/facts/dead_bodies")
local SpritesFacts = require("WorldObserver/facts/sprites")
local VehiclesFacts = require("WorldObserver/facts/vehicles")
local ObservationsCore = require("WorldObserver/observations/core")
local SituationsRegistry = require("WorldObserver/situations/registry")
local SquaresObservations = require("WorldObserver/observations/squares")
local ZombiesObservations = require("WorldObserver/observations/zombies")
local PlayersObservations = require("WorldObserver/observations/players")
local RoomsObservations = require("WorldObserver/observations/rooms")
local ItemsObservations = require("WorldObserver/observations/items")
local DeadBodiesObservations = require("WorldObserver/observations/dead_bodies")
local SpritesObservations = require("WorldObserver/observations/sprites")
local VehiclesObservations = require("WorldObserver/observations/vehicles")
local SquareHelpers = require("WorldObserver/helpers/square")
local ZombieHelpers = require("WorldObserver/helpers/zombie")
local PlayerHelpers = require("WorldObserver/helpers/player")
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
assert(type(config.facts.players) == "table", "WorldObserver config must include facts.players")
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
	local multiTypeInterestKeys = {}

	local function cloneSpecWithType(spec, typeName)
		local out = {}
		for k, v in pairs(spec or {}) do
			out[k] = v
		end
		out.type = typeName
		return out
	end

	local function normalizeTypeList(spec)
		if type(spec) ~= "table" then
			return nil
		end
		local list = spec.type
		if type(list) ~= "table" then
			return nil
		end
		if list[1] == nil then
			error("interest type list must be an array of strings")
		end
		local out = {}
		local seen = {}
		for i = 1, #list do
			local entry = list[i]
			if type(entry) == "string" and entry ~= "" and not seen[entry] then
				out[#out + 1] = entry
				seen[entry] = true
			end
		end
		assert(out[1] ~= nil, "interest type list must include at least one type")
		return out
	end

	local function clearMultiTypeEntry(modId, key)
		local modKeys = multiTypeInterestKeys[modId]
		if not modKeys then
			return
		end
		modKeys[key] = nil
		local hasAny = false
		for _ in pairs(modKeys) do
			hasAny = true
		end
		if not hasAny then
			multiTypeInterestKeys[modId] = nil
		end
	end

	local function revokeMultiTypeEntries(modId, key)
		local modKeys = multiTypeInterestKeys[modId]
		local derived = modKeys and modKeys[key] or nil
		if not derived then
			return
		end
		for _, derivedKey in ipairs(derived) do
			interestRegistry:revoke(modId, derivedKey)
		end
		clearMultiTypeEntry(modId, key)
	end

	local function buildCompositeLease(modId, key, leases, factInterestDeclare)
		local handle = {}

		local function stop()
			for _, lease in ipairs(leases) do
				if lease and lease.stop then
					lease:stop()
				end
			end
			revokeMultiTypeEntries(modId, key)
		end

		local function renew(nowMsOrSelf, maybeNowMs)
			local nowMs = maybeNowMs
			if nowMsOrSelf ~= handle and type(nowMsOrSelf) == "number" and nowMs == nil then
				nowMs = nowMsOrSelf
			end
			for _, lease in ipairs(leases) do
				if lease and lease.renew then
					if nowMs ~= nil then
						lease:renew(nowMs)
					else
						lease:renew()
					end
				end
			end
		end

		local function replaceSpec(selfOrNewSpec, maybeNewSpec, maybeReplaceOpts)
			local newSpec = selfOrNewSpec
			local replaceOpts = maybeNewSpec
			if selfOrNewSpec == handle then
				newSpec = maybeNewSpec
				replaceOpts = maybeReplaceOpts
			end
			return factInterestDeclare(modId, key, newSpec, replaceOpts)
		end

		handle.stop = stop
		handle.renew = renew
		handle.declare = replaceSpec
		return handle
	end

	local function factInterestDeclare(modId, key, spec, opts)
		local typeList = normalizeTypeList(spec)
		if typeList then
			if typeList[2] == nil then
				revokeMultiTypeEntries(modId, key)
				local singleSpec = cloneSpecWithType(spec, typeList[1])
				return interestRegistry:declare(modId, key, singleSpec, opts)
			end

			revokeMultiTypeEntries(modId, key)
			interestRegistry:revoke(modId, key)

			local derivedKeys = {}
			local leases = {}
			for _, typeName in ipairs(typeList) do
				local derivedKey = key .. "/" .. typeName
				derivedKeys[#derivedKeys + 1] = derivedKey
				local derivedSpec = cloneSpecWithType(spec, typeName)
				leases[#leases + 1] = interestRegistry:declare(modId, derivedKey, derivedSpec, opts)
			end

			multiTypeInterestKeys[modId] = multiTypeInterestKeys[modId] or {}
			multiTypeInterestKeys[modId][key] = derivedKeys
			return buildCompositeLease(modId, key, leases, factInterestDeclare)
		end

		revokeMultiTypeEntries(modId, key)
		return interestRegistry:declare(modId, key, spec, opts)
	end

	local function factInterestRevoke(modId, key)
		revokeMultiTypeEntries(modId, key)
		return interestRegistry:revoke(modId, key)
	end

	-- Diagnostics overlays can be quite noisy and can keep printing even after a smoke handle stops
	-- if we forget to detach them. We only want them while something is actively subscribed.
	-- WHY: This avoids "DIAG spam" in normal gameplay and keeps `handle:stop()` behaviour intuitive.
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
			if runtimeDiagnosticsHandle ~= nil then
				return
			end

			runtimeDiagnosticsHandle = debugApi.attachRuntimeDiagnostics({})
			if WorldObserver and WorldObserver._internal then
				WorldObserver._internal.runtimeDiagnosticsHandle = runtimeDiagnosticsHandle
			end
			return
		end

		if runtimeDiagnosticsHandle and runtimeDiagnosticsHandle.stop then
			pcall(runtimeDiagnosticsHandle.stop)
		end
		runtimeDiagnosticsHandle = nil
		if WorldObserver and WorldObserver._internal then
			WorldObserver._internal.runtimeDiagnosticsHandle = nil
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
PlayersFacts.register(factRegistry, config, interestRegistry)
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
		player = PlayerHelpers,
		room = RoomHelpers,
		item = ItemHelpers,
		deadBody = DeadBodyHelpers,
		sprite = SpriteHelpers,
		vehicle = VehicleHelpers,
	},
})

local situationsRegistry = SituationsRegistry.new()

SquaresObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)
ZombiesObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)
PlayersObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)
RoomsObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)
ItemsObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)
DeadBodiesObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)
SpritesObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)
VehiclesObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)

WorldObserver = {
	config = config,
	observations = observationRegistry:api(),
	situations = situationsRegistry:api(),
	factInterest = {
		declare = function(_, modId, key, spec, opts)
			return factInterestDeclare(modId, key, spec, opts)
		end,
		revoke = function(_, modId, key)
			return factInterestRevoke(modId, key)
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
		player = PlayerHelpers,
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
		situations = situationsRegistry,
		factInterest = interestRegistry,
		runtimeDiagnosticsHandle = nil,
	},
}

if WorldObserver.namespace == nil then
	---@param namespace string
	function WorldObserver.namespace(namespace)
		assert(type(namespace) == "string" and namespace ~= "", "namespace must be a non-empty string")

		-- WHY: Keep namespacing explicit and local. We never set global current namespace.
		-- This facade wires the namespace into situations + factInterest without affecting observations.
		return {
			namespace = namespace,
			observations = WorldObserver.observations,
			situations = WorldObserver.situations.namespace(namespace),
			factInterest = {
				declare = function(_, key, spec, opts)
					return WorldObserver.factInterest:declare(namespace, key, spec, opts)
				end,
				revoke = function(_, key)
					return WorldObserver.factInterest:revoke(namespace, key)
				end,
				effective = function(_, factType, opts)
					return WorldObserver.factInterest:effective(factType, opts)
				end,
				effectiveBuckets = function(_, factType, opts)
					return WorldObserver.factInterest:effectiveBuckets(factType, opts)
				end,
			},
			helpers = WorldObserver.helpers,
			debug = WorldObserver.debug,
			highlight = WorldObserver.highlight,
		}
	end
end

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
