-- facts/rooms.lua -- room fact plan: listener (OnSeeNewRoom) + interest-driven probe (allLoaded) to emit Room facts.
local Log = require("DREAMBase/log").withTag("WO.FACTS.rooms")

local Record = require("WorldObserver/facts/rooms/record")
local Probe = require("WorldObserver/facts/rooms/probe")
local OnSee = require("WorldObserver/facts/rooms/on_see_new_room")
local OnPlayerChange = require("WorldObserver/facts/rooms/on_player_change_room")

local INTEREST_TYPE_ROOMS = "rooms"

local moduleName = ...
local Rooms = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Rooms = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Rooms
	end
end

Rooms._internal = Rooms._internal or {}
Rooms._defaults = Rooms._defaults or {}
Rooms._defaults.interest = Rooms._defaults.interest or {
	staleness = { desired = 60, tolerable = 120 },
	radius = { desired = 0, tolerable = 0 },
	zRange = { desired = 0, tolerable = 0 },
	cooldown = { desired = 20, tolerable = 40 },
}

local ROOMS_TICK_HOOK_ID = "facts.rooms.tick"

local function hasActiveLease(interestRegistry, interestType)
	if not (interestRegistry and type(interestRegistry.effectiveBuckets) == "function") then
		return false
	end
	local ok, buckets = pcall(interestRegistry.effectiveBuckets, interestRegistry, interestType)
	return ok and type(buckets) == "table" and buckets[1] ~= nil
end

-- Default room record builder.
-- Intentionally exposed via Rooms.makeRoomRecord so other mods can patch/override it.
if Rooms.makeRoomRecord == nil then
	function Rooms.makeRoomRecord(room, source, opts)
		return Record.makeRoomRecord(room, source, opts)
	end
end
Rooms._defaults.makeRoomRecord = Rooms._defaults.makeRoomRecord or Rooms.makeRoomRecord

local function tickRooms(ctx)
	ctx = ctx or {}
	local state = ctx.state or {}
	ctx.state = state

	OnSee.ensure({
		state = state,
		rooms = Rooms,
		emitFn = ctx.emitFn,
		headless = ctx.headless,
		runtime = ctx.runtime,
		interestRegistry = ctx.interestRegistry,
		listenerCfg = ctx.listenerCfg,
		recordOpts = ctx.recordOpts,
	})
	OnPlayerChange.ensure({
		state = state,
		rooms = Rooms,
		emitFn = ctx.emitFn,
		headless = ctx.headless,
		runtime = ctx.runtime,
		interestRegistry = ctx.interestRegistry,
		listenerCfg = ctx.listenerCfg,
		recordOpts = ctx.recordOpts,
	})

	local probeCfg = ctx.probeCfg or {}
	if probeCfg.enabled ~= false then
		Probe.tick({
			state = state,
			rooms = Rooms,
			emitFn = ctx.emitFn,
			headless = ctx.headless,
			runtime = ctx.runtime,
			interestRegistry = ctx.interestRegistry,
			defaultInterest = Rooms._defaults.interest,
			probeCfg = probeCfg,
			recordOpts = ctx.recordOpts,
		})
	end
end

local function attachTickHookOnce(state, emitFn, ctx)
	if state.roomsTickHookAttached then
		return true
	end
	local factRegistry = ctx.factRegistry
	if not factRegistry or type(factRegistry.attachTickHook) ~= "function" then
		if not ctx.headless then
			Log:warn("Rooms tick hook not attached (FactRegistry.attachTickHook unavailable)")
		end
		return false
	end

	local fn = function()
		tickRooms({
			state = state,
			emitFn = emitFn,
			headless = ctx.headless,
			runtime = ctx.runtime,
			interestRegistry = ctx.interestRegistry,
			probeCfg = ctx.probeCfg,
			listenerCfg = ctx.listenerCfg,
			recordOpts = ctx.recordOpts,
		})
	end

	factRegistry:attachTickHook(ROOMS_TICK_HOOK_ID, fn)
	state.roomsTickHookAttached = true
	state.roomsTickHookId = ROOMS_TICK_HOOK_ID
	return true
end

Rooms._internal.attachTickHookOnce = attachTickHookOnce

-- Patch seam: define only when nil so mods can override by reassigning `Rooms.register`.
if Rooms.register == nil then
	function Rooms.register(registry, config, interestRegistry)
		assert(type(config) == "table", "RoomsFacts.register expects config table")
		assert(type(config.facts) == "table", "RoomsFacts.register expects config.facts table")
		assert(type(config.facts.rooms) == "table", "RoomsFacts.register expects config.facts.rooms table")
		local roomsCfg = config.facts.rooms
		local headless = roomsCfg.headless == true
		local probeCfg = roomsCfg.probe or {}
		local listenerCfg = roomsCfg.listener or {}
		local recordCfg = roomsCfg.record or {}

		local recordOpts = {
			includeIsoRoom = recordCfg.includeIsoRoom == true,
			includeRoomDef = recordCfg.includeRoomDef == true,
			includeBuilding = recordCfg.includeBuilding == true,
		}

		registry:register("rooms", {
			ingest = {
				mode = "latestByKey",
				ordering = "fifo",
				key = function(record)
					return record and record.roomId
				end,
				lane = function(record)
					return (record and record.source) or "default"
				end,
				lanePriority = function(laneName)
					if laneName == "probe" then
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
				local tickHookAttached = attachTickHookOnce(state, originalEmit, {
					factRegistry = registry,
					headless = headless,
					runtime = ctx.runtime,
					interestRegistry = interestRegistry,
					probeCfg = probeCfg,
					listenerCfg = listenerCfg,
					recordOpts = recordOpts,
				})

				if not headless then
					local hasInterest = hasActiveLease(interestRegistry, INTEREST_TYPE_ROOMS)
					Log:info(
						"Rooms facts started (tickHook=%s cfgProbe=%s cfgListener=%s interest=%s)",
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

				if state.onSeeNewRoomHandler then
					local handler = events and events.OnSeeNewRoom
					if handler and type(handler.Remove) == "function" then
						pcall(handler.Remove, handler, state.onSeeNewRoomHandler)
						state.onSeeNewRoomHandler = nil
					else
						fullyStopped = false
					end
				end

				if state.roomsTickHookAttached then
					if registry and type(registry.detachTickHook) == "function" then
						pcall(registry.detachTickHook, registry, state.roomsTickHookId or ROOMS_TICK_HOOK_ID)
						state.roomsTickHookAttached = nil
						state.roomsTickHookId = nil
					else
						fullyStopped = false
					end
				end

				if not fullyStopped and not headless then
					Log:warn("Rooms fact stop requested but could not remove all handlers; keeping started=true")
				end
				return fullyStopped
			end,
		})
	end
end

return Rooms
