-- facts/dead_bodies.lua -- dead body fact plan: playerSquare driver + shared square sweep collector.
local Log = require("LQR/util/log").withTag("WO.FACTS.deadBodies")

local Record = require("WorldObserver/facts/dead_bodies/record")
local SquareSweep = require("WorldObserver/facts/sensors/square_sweep")
local GroundEntities = require("WorldObserver/facts/ground_entities")
local JavaList = require("WorldObserver/helpers/java_list")
local SafeCall = require("WorldObserver/helpers/safe_call")

local INTEREST_TYPE_DEAD_BODIES = "deadBodies"
local INTEREST_SCOPE_PLAYER_SQUARE = "playerSquare"
local PLAYER_SQUARE_HIGHLIGHT_COLOR = { 0.8, 0.2, 0.2 }

local moduleName = ...
local DeadBodies = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		DeadBodies = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = DeadBodies
	end
end

DeadBodies._internal = DeadBodies._internal or {}
DeadBodies._defaults = DeadBodies._defaults or {}
DeadBodies._defaults.interest = DeadBodies._defaults.interest or {
	staleness = { desired = 10, tolerable = 20 },
	radius = { desired = 8, tolerable = 5 },
	cooldown = { desired = 10, tolerable = 20 },
}
DeadBodies._defaults.recordOpts = DeadBodies._defaults.recordOpts or {
	includeIsoDeadBody = false,
}

-- Default dead body record builder.
-- Intentionally exposed via DeadBodies.makeDeadBodyRecord so other mods can patch/override it.
if DeadBodies.makeDeadBodyRecord == nil then
	function DeadBodies.makeDeadBodyRecord(body, square, source, opts)
		return Record.makeDeadBodyRecord(body, square, source, opts)
	end
end
DeadBodies._defaults.makeDeadBodyRecord = DeadBodies._defaults.makeDeadBodyRecord or DeadBodies.makeDeadBodyRecord

local function visitDeadBody(seen, body, visitor)
	if body == nil then
		return
	end
	if seen[body] then
		return
	end
	seen[body] = true
	visitor(body)
end

local function iterDeadBodyList(list, seen, visitor)
	if list == nil then
		return
	end
	local count = JavaList.size(list)
	for i = 1, count do
		local body = JavaList.get(list, i)
		visitDeadBody(seen, body, visitor)
	end
end

local function collectDeadBodiesOnSquare(square, visitor)
	if square == nil or type(visitor) ~= "function" then
		return
	end
	local seen = {}
	visitDeadBody(seen, SafeCall.safeCall(square, "getDeadBody"), function(body)
		visitor(body, nil)
	end)
	iterDeadBodyList(SafeCall.safeCall(square, "getDeadBodys"), seen, function(body)
		visitor(body, nil)
	end)
	iterDeadBodyList(SafeCall.safeCall(square, "getDeadBodies"), seen, function(body)
		visitor(body, nil)
	end)
end

local deadBodiesCollector = GroundEntities.buildSquareCollector({
	interestType = INTEREST_TYPE_DEAD_BODIES,
	idField = "deadBodyId",
	collectorStateKey = "_deadBodiesCollector",
	getRecordOpts = function(ctx)
		return (ctx and ctx.recordOpts) or DeadBodies._defaults.recordOpts
	end,
	collectOnSquare = function(square, _recordOpts, visitor)
		return collectDeadBodiesOnSquare(square, visitor)
	end,
	makeRecord = function(ctx, body, square, source, _nowMs, recordOpts, _extra)
		local deadBodies = ctx and ctx.deadBodies
		if not (deadBodies and type(deadBodies.makeDeadBodyRecord) == "function") then
			return nil
		end
		return deadBodies.makeDeadBodyRecord(body, square, source, {
			includeIsoDeadBody = recordOpts and recordOpts.includeIsoDeadBody,
		})
	end,
})

if DeadBodies._internal.registerDeadBodiesCollector == nil then
	function DeadBodies._internal.registerDeadBodiesCollector()
		SquareSweep.registerCollector(INTEREST_TYPE_DEAD_BODIES, deadBodiesCollector, {
			interestType = INTEREST_TYPE_DEAD_BODIES,
		})
	end
end
DeadBodies._internal.registerDeadBodiesCollector()

local function tickPlayerSquare(ctx)
	-- playerSquare is a "listener-like" driver: it runs only when scope=playerSquare is declared.
	-- We keep it per-type (instead of a shared sensor) because it does constant-time work (current square only).
	GroundEntities.tickPlayerSquare(ctx, {
		log = Log,
		interestType = INTEREST_TYPE_DEAD_BODIES,
		scope = INTEREST_SCOPE_PLAYER_SQUARE,
		bucketsStateKey = "_playerDeadBodyBuckets",
		idField = "deadBodyId",
		playerHighlightColor = PLAYER_SQUARE_HIGHLIGHT_COLOR,
		getRecordOpts = function(innerCtx)
			return (innerCtx and innerCtx.recordOpts) or DeadBodies._defaults.recordOpts
		end,
		collectOnSquare = function(square, _recordOpts, visitor)
			return collectDeadBodiesOnSquare(square, visitor)
		end,
		makeRecord = function(innerCtx, body, square, source, _nowMs, recordOpts, _extra)
			local deadBodies = innerCtx and innerCtx.deadBodies
			if not (deadBodies and type(deadBodies.makeDeadBodyRecord) == "function") then
				return nil
			end
			return deadBodies.makeDeadBodyRecord(body, square, source, {
				includeIsoDeadBody = recordOpts and recordOpts.includeIsoDeadBody,
			})
		end,
	})
end

local DEAD_BODIES_TICK_HOOK_ID = "facts.deadBodies.tick"

local function attachTickHookOnce(state, emitFn, ctx)
	if state.deadBodiesTickHookAttached then
		return true
	end
	local factRegistry = ctx.factRegistry
	if not factRegistry or type(factRegistry.attachTickHook) ~= "function" then
		if not ctx.headless then
			Log:warn("DeadBodies tick hook not attached (FactRegistry.attachTickHook unavailable)")
		end
		return false
	end

	local fn = function()
		tickPlayerSquare({
			state = state,
			emitFn = emitFn,
			headless = ctx.headless,
			runtime = ctx.runtime,
			interestRegistry = ctx.interestRegistry,
			listenerCfg = ctx.listenerCfg,
			recordOpts = ctx.recordOpts,
		})
	end

	factRegistry:attachTickHook(DEAD_BODIES_TICK_HOOK_ID, fn)
	state.deadBodiesTickHookAttached = true
	state.deadBodiesTickHookId = DEAD_BODIES_TICK_HOOK_ID
	return true
end

DeadBodies._internal.collectDeadBodiesOnSquare = collectDeadBodiesOnSquare
DeadBodies._internal.deadBodiesCollector = deadBodiesCollector
DeadBodies._internal.tickPlayerSquare = tickPlayerSquare
DeadBodies._internal.attachTickHookOnce = attachTickHookOnce

-- Patch seam: define only when nil so mods can override by reassigning `DeadBodies.register`.
if DeadBodies.register == nil then
	function DeadBodies.register(registry, config, interestRegistry)
		assert(type(config) == "table", "DeadBodiesFacts.register expects config table")
		assert(type(config.facts) == "table", "DeadBodiesFacts.register expects config.facts table")
		assert(type(config.facts.deadBodies) == "table", "DeadBodiesFacts.register expects config.facts.deadBodies table")
		local deadBodiesCfg = config.facts.deadBodies
		local headless = deadBodiesCfg.headless == true
		local probeCfg = deadBodiesCfg.probe or {}
		local probeEnabled = probeCfg.enabled ~= false
		local listenerCfg = deadBodiesCfg.listener or {}
		local listenerEnabled = listenerCfg.enabled ~= false
		local recordOpts = DeadBodies._defaults.recordOpts
		if type(deadBodiesCfg.record) == "table" then
			recordOpts = {
				includeIsoDeadBody = deadBodiesCfg.record.includeIsoDeadBody == true,
			}
		end

		registry:register(INTEREST_TYPE_DEAD_BODIES, {
			ingest = {
				mode = "latestByKey",
				ordering = "fifo",
				key = function(record)
					return record and record.deadBodyId
				end,
				lane = function(record)
					return (record and record.source) or "default"
				end,
			},
			start = function(ctx)
				local state = ctx.state or {}
				local originalEmit = ctx.ingest or ctx.emit
				local tickHookAttached = false
				if listenerEnabled then
					tickHookAttached = attachTickHookOnce(state, originalEmit, {
						factRegistry = registry,
						headless = headless,
						runtime = ctx.runtime,
						interestRegistry = interestRegistry,
						listenerCfg = listenerCfg,
						recordOpts = recordOpts,
					})
				end
				local sweepRegistered = false
				if probeEnabled then
					local ok = SquareSweep.registerConsumer(INTEREST_TYPE_DEAD_BODIES, {
						collectorId = INTEREST_TYPE_DEAD_BODIES,
						interestType = INTEREST_TYPE_DEAD_BODIES,
						emitFn = originalEmit,
						context = { deadBodies = DeadBodies, recordOpts = recordOpts },
						headless = headless,
						runtime = ctx.runtime,
						interestRegistry = interestRegistry,
						probeCfg = probeCfg,
						probePriority = 4,
						factRegistry = registry,
					})
					sweepRegistered = ok == true
				end

				if not headless then
					local hasPlayerSquareInterest = false
					local hasNearInterest = false
					local hasVisionInterest = false
					if interestRegistry and type(interestRegistry.effectiveBuckets) == "function" then
						local buckets = interestRegistry:effectiveBuckets(INTEREST_TYPE_DEAD_BODIES)
						for _, bucket in ipairs(buckets or {}) do
							local merged = bucket.merged
							if type(merged) == "table" then
								if merged.scope == INTEREST_SCOPE_PLAYER_SQUARE then
									hasPlayerSquareInterest = true
								elseif merged.scope == "near" then
									hasNearInterest = true
								elseif merged.scope == "vision" then
									hasVisionInterest = true
								end
							end
						end
					end
					Log:info(
						"DeadBodies facts started (tickHook=%s sweep=%s cfgProbe=%s cfgListener=%s interestPlayerSquare=%s interestNear=%s interestVision=%s)",
						tostring(tickHookAttached),
						tostring(sweepRegistered),
						tostring(probeEnabled),
						tostring(listenerEnabled),
						tostring(hasPlayerSquareInterest),
						tostring(hasNearInterest),
						tostring(hasVisionInterest)
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

				if state.deadBodiesTickHookAttached then
					if registry and type(registry.detachTickHook) == "function" then
						pcall(registry.detachTickHook, registry, state.deadBodiesTickHookId or DEAD_BODIES_TICK_HOOK_ID)
						state.deadBodiesTickHookAttached = nil
						state.deadBodiesTickHookId = nil
					else
						fullyStopped = false
					end
				end

				if probeEnabled then
					SquareSweep.unregisterConsumer(INTEREST_TYPE_DEAD_BODIES)
				end

				if not fullyStopped and not headless then
					Log:warn("DeadBodies fact stop requested but could not remove all handlers; keeping started=true")
				end
			end,
		})
	end
end

return DeadBodies
