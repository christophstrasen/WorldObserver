-- facts/zombies.lua -- zombie fact plan: interest-driven probe over IsoCell:getZombieList().
local Log = require("LQR/util/log").withTag("WO.FACTS.zombies")

local Probe = require("WorldObserver/facts/zombies/probe")

local moduleName = ...
local Zombies = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Zombies = loaded
	else
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

local ZOMBIES_TICK_HOOK_ID = Probe._internal.PROBE_TICK_HOOK_ID or "facts.zombies.tick"

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
	})
end

local function registerTickHook(state, emitFn, ctx)
	if state.zombiesTickHookRegistered then
		return true
	end
	local factRegistry = ctx.factRegistry
	if not factRegistry or type(factRegistry.tickHook_add) ~= "function" then
		if not ctx.headless then
			Log:warn("Zombies tick hook not registered (FactRegistry.tickHook_add unavailable)")
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

	factRegistry:tickHook_add(ZOMBIES_TICK_HOOK_ID, fn)
	state.zombiesTickHookRegistered = true
	state.zombiesTickHookId = ZOMBIES_TICK_HOOK_ID
	return true
end

Zombies._internal.tickZombies = tickZombies
Zombies._internal.registerTickHook = registerTickHook

-- Patch seam: define only when nil so mods can override by reassigning `Zombies.register`.
if Zombies.register == nil then
	function Zombies.register(registry, config, interestRegistry)
		local zombiesCfg = config and config.facts and config.facts.zombies or {}
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
				local tickHookRegistered = false
				if probeEnabled then
					tickHookRegistered = registerTickHook(state, originalEmit, {
						factRegistry = registry,
						headless = headless,
						runtime = ctx.runtime,
						interestRegistry = interestRegistry,
						probeCfg = probeCfg,
					})
				end

				if not headless then
					Log:info(
						"Zombies fact plan started (probe=%s, tickHook=%s)",
						tostring(probeEnabled),
						tostring(tickHookRegistered)
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

				if state.zombiesTickHookRegistered then
					if registry and type(registry.tickHook_remove) == "function" then
						pcall(registry.tickHook_remove, registry, state.zombiesTickHookId or ZOMBIES_TICK_HOOK_ID)
						state.zombiesTickHookRegistered = nil
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
