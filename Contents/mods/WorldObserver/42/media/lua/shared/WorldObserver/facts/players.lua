-- facts/players.lua -- player fact plan: listeners (OnPlayerMove, OnPlayerUpdate) gated by interest.
local Log = require("DREAMBase/log").withTag("WO.FACTS.players")

local Record = require("WorldObserver/facts/players/record")
local OnPlayerMove = require("WorldObserver/facts/players/on_player_move")
local OnPlayerUpdate = require("WorldObserver/facts/players/on_player_update")

local INTEREST_TYPE_PLAYERS = "players"

local moduleName = ...
local Players = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Players = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Players
	end
end

Players._internal = Players._internal or {}
Players._defaults = Players._defaults or {}
Players._defaults.interest = Players._defaults.interest or {
	cooldown = { desired = 0.2, tolerable = 0.4 },
}

-- Default player record builder.
-- Intentionally exposed via Players.makePlayerRecord so other mods can patch/override it.
if Players.makePlayerRecord == nil then
	function Players.makePlayerRecord(player, source, opts)
		return Record.makePlayerRecord(player, source, opts)
	end
end
Players._defaults.makePlayerRecord = Players._defaults.makePlayerRecord or Players.makePlayerRecord

local PLAYERS_TICK_HOOK_ID = "facts.players.tick"

local function hasActiveLease(interestRegistry, interestType)
	if not (interestRegistry and type(interestRegistry.effectiveBuckets) == "function") then
		return false
	end
	local ok, buckets = pcall(interestRegistry.effectiveBuckets, interestRegistry, interestType)
	return ok and type(buckets) == "table" and buckets[1] ~= nil
end

local function tickPlayers(ctx)
	ctx = ctx or {}
	local state = ctx.state or {}
	ctx.state = state

	OnPlayerMove.ensure({
		state = state,
		players = Players,
		emitFn = ctx.emitFn,
		headless = ctx.headless,
		runtime = ctx.runtime,
		interestRegistry = ctx.interestRegistry,
		listenerCfg = ctx.listenerCfg,
	})
	OnPlayerUpdate.ensure({
		state = state,
		players = Players,
		emitFn = ctx.emitFn,
		headless = ctx.headless,
		runtime = ctx.runtime,
		interestRegistry = ctx.interestRegistry,
		listenerCfg = ctx.listenerCfg,
	})
end

local function attachTickHookOnce(state, emitFn, ctx)
	if state.playersTickHookAttached then
		return true
	end
	local factRegistry = ctx.factRegistry
	if not factRegistry or type(factRegistry.attachTickHook) ~= "function" then
		if not ctx.headless then
			Log:warn("Players tick hook not attached (FactRegistry.attachTickHook unavailable)")
		end
		return false
	end

	local fn = function()
		tickPlayers({
			state = state,
			emitFn = emitFn,
			headless = ctx.headless,
			runtime = ctx.runtime,
			interestRegistry = ctx.interestRegistry,
			listenerCfg = ctx.listenerCfg,
		})
	end

	factRegistry:attachTickHook(PLAYERS_TICK_HOOK_ID, fn)
	state.playersTickHookAttached = true
	state.playersTickHookId = PLAYERS_TICK_HOOK_ID
	return true
end

Players._internal.attachTickHookOnce = attachTickHookOnce

-- Patch seam: define only when nil so mods can override by reassigning `Players.register`.
if Players.register == nil then
	function Players.register(registry, config, interestRegistry)
		assert(type(config) == "table", "PlayersFacts.register expects config table")
		assert(type(config.facts) == "table", "PlayersFacts.register expects config.facts table")
		assert(type(config.facts.players) == "table", "PlayersFacts.register expects config.facts.players table")
		local playersCfg = config.facts.players
		local headless = playersCfg.headless == true
		local listenerCfg = playersCfg.listener or {}

		registry:register("players", {
			ingest = {
				mode = "latestByKey",
				ordering = "fifo",
				key = function(record)
					return record and record.playerKey
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
					listenerCfg = listenerCfg,
				})

				if not headless then
					local hasInterest = hasActiveLease(interestRegistry, INTEREST_TYPE_PLAYERS)
					Log:info(
						"Players facts started (tickHook=%s cfgListener=%s interest=%s)",
						tostring(tickHookAttached),
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

				if state.onPlayerMoveHandler then
					local handler = events and events.OnPlayerMove
					if handler and type(handler.Remove) == "function" then
						pcall(handler.Remove, handler, state.onPlayerMoveHandler)
						state.onPlayerMoveHandler = nil
					else
						fullyStopped = false
					end
				end

				if state.onPlayerUpdateHandler then
					local handler = events and events.OnPlayerUpdate
					if handler and type(handler.Remove) == "function" then
						pcall(handler.Remove, handler, state.onPlayerUpdateHandler)
						state.onPlayerUpdateHandler = nil
					else
						fullyStopped = false
					end
				end

				if state.playersTickHookAttached then
					if registry and type(registry.detachTickHook) == "function" then
						pcall(registry.detachTickHook, registry, state.playersTickHookId or PLAYERS_TICK_HOOK_ID)
						state.playersTickHookAttached = nil
						state.playersTickHookId = nil
					else
						fullyStopped = false
					end
				end

				if not fullyStopped and not headless then
					Log:warn("Players fact stop requested but could not remove all handlers; keeping started=true")
				end
				return fullyStopped
			end,
		})
	end
end

return Players
