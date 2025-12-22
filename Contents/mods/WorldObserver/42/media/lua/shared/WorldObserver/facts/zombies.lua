-- facts/zombies.lua -- zombie fact plan: interest-driven probe over IsoCell:getZombieList().
local Log = require("LQR/util/log").withTag("WO.FACTS.zombies")

local Probe = require("WorldObserver/facts/zombies/probe")
local Record = require("WorldObserver/facts/zombies/record")

local INTEREST_TYPE_ZOMBIES = "zombies"

local moduleName = ...
local Zombies = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Zombies = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Zombies
	end
end

Zombies._internal = Zombies._internal or {}
Zombies._defaults = Zombies._defaults or {}
Zombies._defaults.interest = Zombies._defaults.interest or {
	staleness = { desired = 5, tolerable = 10 },
	radius = { desired = 20, tolerable = 30 },
	zRange = { desired = 1, tolerable = 2 },
	cooldown = { desired = 2, tolerable = 4 },
}

-- Default zombie record builder.
-- Intentionally exposed via Zombies.makeZombieRecord so other mods can patch/override it.
if Zombies.makeZombieRecord == nil then
	function Zombies.makeZombieRecord(zombie, source, opts)
		return Record.makeZombieRecord(zombie, source, opts)
	end
end
Zombies._defaults.makeZombieRecord = Zombies._defaults.makeZombieRecord or Zombies.makeZombieRecord

local ZOMBIES_TICK_HOOK_ID = Probe._internal.PROBE_TICK_HOOK_ID or "facts.zombies.tick"

local function hasActiveLease(interestRegistry, interestType)
	if not (interestRegistry and type(interestRegistry.effective) == "function") then
		return false
	end
	local ok, merged = pcall(interestRegistry.effective, interestRegistry, interestType)
	return ok and merged ~= nil
end

local function tickZombies(ctx)
	ctx = ctx or {}
	local state = ctx.state or {}
	ctx.state = state

	Probe.tick({
		state = state,
		emitFn = ctx.emitFn,
		headless = ctx.headless,
		runtime = ctx.runtime,
		interestRegistry = ctx.interestRegistry,
		defaultInterest = Zombies._defaults.interest,
		probeCfg = ctx.probeCfg,
		makeZombieRecord = Zombies.makeZombieRecord,
	})
end

local function attachTickHookOnce(state, emitFn, ctx)
	if state.zombiesTickHookAttached then
		return true
	end
	local factRegistry = ctx.factRegistry
	if not factRegistry or type(factRegistry.attachTickHook) ~= "function" then
		if not ctx.headless then
			Log:warn("Zombies tick hook not attached (FactRegistry.attachTickHook unavailable)")
		end
		return false
	end

	local fn = function()
		tickZombies({
			state = state,
			emitFn = emitFn,
			headless = ctx.headless,
			runtime = ctx.runtime,
			interestRegistry = ctx.interestRegistry,
			probeCfg = ctx.probeCfg,
		})
	end

	factRegistry:attachTickHook(ZOMBIES_TICK_HOOK_ID, fn)
	state.zombiesTickHookAttached = true
	state.zombiesTickHookId = ZOMBIES_TICK_HOOK_ID
	return true
end

Zombies._internal.tickZombies = tickZombies
Zombies._internal.attachTickHookOnce = attachTickHookOnce

	-- Patch seam: define only when nil so mods can override by reassigning `Zombies.register`.
	if Zombies.register == nil then
		function Zombies.register(registry, config, interestRegistry)
			assert(type(config) == "table", "ZombiesFacts.register expects config table")
			assert(type(config.facts) == "table", "ZombiesFacts.register expects config.facts table")
			assert(type(config.facts.zombies) == "table", "ZombiesFacts.register expects config.facts.zombies table")
			local zombiesCfg = config.facts.zombies
			local headless = zombiesCfg.headless == true
			local probeCfg = zombiesCfg.probe or {}
			local probeEnabled = probeCfg.enabled ~= false

		registry:register("zombies", {
			ingest = {
				mode = "latestByKey",
				ordering = "fifo",
				key = function(record)
					return record and record.zombieId
				end,
				lane = function(record)
					return (record and record.source) or "default"
				end,
			},
			start = function(ctx)
				local state = ctx.state or {}
				local originalEmit = ctx.ingest or ctx.emit
				local tickHookAttached = false
				if probeEnabled then
					tickHookAttached = attachTickHookOnce(state, originalEmit, {
						factRegistry = registry,
						headless = headless,
						runtime = ctx.runtime,
						interestRegistry = interestRegistry,
						probeCfg = probeCfg,
					})
					end

					if not headless then
						local hasAllLoadedInterest = hasActiveLease(interestRegistry, INTEREST_TYPE_ZOMBIES)
						Log:info(
							"Zombies facts started (tickHook=%s cfgProbe=%s interestAllLoaded=%s)",
							tostring(tickHookAttached),
							tostring(probeEnabled),
							tostring(hasAllLoadedInterest)
						)
					end

					ctx.emit = originalEmit
				ctx.ingest = originalEmit
			end,
			stop = function(entry)
				local state = entry.state or {}
				local fullyStopped = true

				if entry.buffer and entry.buffer.clear then
					entry.buffer:clear()
				end

				if state.zombiesTickHookAttached then
					if registry and type(registry.detachTickHook) == "function" then
						pcall(registry.detachTickHook, registry, state.zombiesTickHookId or ZOMBIES_TICK_HOOK_ID)
						state.zombiesTickHookAttached = nil
						state.zombiesTickHookId = nil
					else
						fullyStopped = false
					end
				end

				if not fullyStopped and not headless then
					Log:warn("Zombies fact stop requested but could not remove all handlers; keeping started=true")
				end
			end,
		})
	end
end

return Zombies
