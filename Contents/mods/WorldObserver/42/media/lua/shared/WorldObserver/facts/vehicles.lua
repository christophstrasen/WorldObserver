-- facts/vehicles.lua -- vehicle fact plan: listener (OnSpawnVehicleEnd) + interest-driven probe (allLoaded).
local Log = require("LQR/util/log").withTag("WO.FACTS.vehicles")

local Probe = require("WorldObserver/facts/vehicles/probe")
local Record = require("WorldObserver/facts/vehicles/record")
local OnSpawn = require("WorldObserver/facts/vehicles/on_spawn")

local INTEREST_TYPE_VEHICLES = "vehicles"

local moduleName = ...
local Vehicles = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Vehicles = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Vehicles
	end
end

Vehicles._internal = Vehicles._internal or {}
Vehicles._defaults = Vehicles._defaults or {}
Vehicles._defaults.interest = Vehicles._defaults.interest or {
	staleness = { desired = 5, tolerable = 10 },
	cooldown = { desired = 10, tolerable = 20 },
}

-- Default vehicle record builder.
-- Intentionally exposed via Vehicles.makeVehicleRecord so other mods can patch/override it.
if Vehicles.makeVehicleRecord == nil then
	function Vehicles.makeVehicleRecord(vehicle, source, opts)
		return Record.makeVehicleRecord(vehicle, source, opts)
	end
end
Vehicles._defaults.makeVehicleRecord = Vehicles._defaults.makeVehicleRecord or Vehicles.makeVehicleRecord

local VEHICLES_TICK_HOOK_ID = Probe._internal.PROBE_TICK_HOOK_ID or "facts.vehicles.tick"

local function hasActiveLease(interestRegistry, interestType)
	if not (interestRegistry and type(interestRegistry.effective) == "function") then
		return false
	end
	local ok, merged = pcall(interestRegistry.effective, interestRegistry, interestType)
	return ok and merged ~= nil
end

local function tickVehicles(ctx)
	ctx = ctx or {}
	local state = ctx.state or {}
	ctx.state = state

	OnSpawn.ensure({
		state = state,
		emitFn = ctx.emitFn,
		headless = ctx.headless,
		runtime = ctx.runtime,
		interestRegistry = ctx.interestRegistry,
		listenerCfg = ctx.listenerCfg,
		makeVehicleRecord = Vehicles.makeVehicleRecord,
	})

	local probeCfg = ctx.probeCfg or {}
	if probeCfg.enabled ~= false then
		Probe.tick({
			state = state,
			emitFn = ctx.emitFn,
			headless = ctx.headless,
			runtime = ctx.runtime,
			interestRegistry = ctx.interestRegistry,
			defaultInterest = Vehicles._defaults.interest,
			probeCfg = probeCfg,
			makeVehicleRecord = Vehicles.makeVehicleRecord,
		})
	end
end

local function attachTickHookOnce(state, emitFn, ctx)
	if state.vehiclesTickHookAttached then
		return true
	end
	local factRegistry = ctx.factRegistry
	if not factRegistry or type(factRegistry.attachTickHook) ~= "function" then
		if not ctx.headless then
			Log:warn("Vehicles tick hook not attached (FactRegistry.attachTickHook unavailable)")
		end
		return false
	end

	local fn = function()
		tickVehicles({
			state = state,
			emitFn = emitFn,
			headless = ctx.headless,
			runtime = ctx.runtime,
			interestRegistry = ctx.interestRegistry,
			probeCfg = ctx.probeCfg,
			listenerCfg = ctx.listenerCfg,
		})
	end

	factRegistry:attachTickHook(VEHICLES_TICK_HOOK_ID, fn)
	state.vehiclesTickHookAttached = true
	state.vehiclesTickHookId = VEHICLES_TICK_HOOK_ID
	return true
end

Vehicles._internal.tickVehicles = tickVehicles
Vehicles._internal.attachTickHookOnce = attachTickHookOnce

-- Patch seam: define only when nil so mods can override by reassigning `Vehicles.register`.
if Vehicles.register == nil then
	function Vehicles.register(registry, config, interestRegistry)
		assert(type(config) == "table", "VehiclesFacts.register expects config table")
		assert(type(config.facts) == "table", "VehiclesFacts.register expects config.facts table")
		assert(type(config.facts.vehicles) == "table", "VehiclesFacts.register expects config.facts.vehicles table")
		local vehiclesCfg = config.facts.vehicles
		local headless = vehiclesCfg.headless == true
		local probeCfg = vehiclesCfg.probe or {}
		local listenerCfg = vehiclesCfg.listener or {}

		registry:register("vehicles", {
			ingest = {
				mode = "latestByKey",
				ordering = "fifo",
				key = function(record)
					return record and Record.keyFromRecord(record)
				end,
				lane = function(record)
					return (record and record.source) or "default"
				end,
			},
			start = function(ctx)
				local state = ctx.state or {}
				local originalEmit = ctx.ingest or ctx.emit
				local tickHookAttached = attachTickHookOnce(state, originalEmit, {
					factRegistry = registry,
					headless = headless,
					runtime = ctx.runtime,
					interestRegistry = interestRegistry,
					probeCfg = probeCfg,
					listenerCfg = listenerCfg,
				})

				if not headless then
					local hasInterest = hasActiveLease(interestRegistry, INTEREST_TYPE_VEHICLES)
					Log:info(
						"Vehicles facts started (tickHook=%s cfgProbe=%s cfgListener=%s interest=%s)",
						tostring(tickHookAttached),
						tostring(probeCfg.enabled ~= false),
						tostring(listenerCfg.enabled ~= false),
						tostring(hasInterest)
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

				if state.onSpawnVehicleHandler then
					local handler = events and events.OnSpawnVehicleEnd
					if handler and type(handler.Remove) == "function" then
						pcall(handler.Remove, handler, state.onSpawnVehicleHandler)
						state.onSpawnVehicleHandler = nil
					else
						fullyStopped = false
					end
				end

				if state.vehiclesTickHookAttached then
					if registry and type(registry.detachTickHook) == "function" then
						pcall(registry.detachTickHook, registry, state.vehiclesTickHookId or VEHICLES_TICK_HOOK_ID)
						state.vehiclesTickHookAttached = nil
						state.vehiclesTickHookId = nil
					else
						fullyStopped = false
					end
				end

				if not fullyStopped and not headless then
					Log:warn("Vehicles fact stop requested but could not remove all handlers; keeping started=true")
				end
				return fullyStopped
			end,
		})
	end
end

return Vehicles
