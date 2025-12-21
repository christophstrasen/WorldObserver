-- facts/dead_bodies.lua -- dead body fact plan: playerSquare driver + shared square sweep collector.
local Log = require("LQR/util/log").withTag("WO.FACTS.deadBodies")

local Record = require("WorldObserver/facts/dead_bodies/record")
local SquareSweep = require("WorldObserver/facts/sensors/square_sweep")
local Cooldown = require("WorldObserver/facts/cooldown")
local InterestEffective = require("WorldObserver/facts/interest_effective")
local Highlight = require("WorldObserver/helpers/highlight")
local JavaList = require("WorldObserver/helpers/java_list")
local SafeCall = require("WorldObserver/helpers/safe_call")
local Time = require("WorldObserver/helpers/time")

local INTEREST_TYPE_DEAD_BODIES = "deadBodies"
local INTEREST_SCOPE_PLAYER_SQUARE = "playerSquare"
local PLAYER_SQUARE_HIGHLIGHT_COLOR = { 0.8, 0.2, 0.2 }

local moduleName = ...
local DeadBodies = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		DeadBodies = loaded
	else
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

local function nowMillis()
	return Time.gameMillis() or math.floor(os.time() * 1000)
end

local function resolvePlayer(target)
	if type(target) ~= "table" or target.kind ~= "player" then
		return nil
	end
	local id = tonumber(target.id) or 0
	local getSpecificPlayer = _G.getSpecificPlayer
	if type(getSpecificPlayer) == "function" then
		local ok, player = pcall(getSpecificPlayer, id)
		if ok and player ~= nil then
			return player
		end
	end
	if id == 0 then
		local getPlayer = _G.getPlayer
		if type(getPlayer) == "function" then
			local ok, player = pcall(getPlayer)
			if ok and player ~= nil then
				return player
			end
		end
	end
	return nil
end

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
	visitDeadBody(seen, SafeCall.safeCall(square, "getDeadBody"), visitor)
	iterDeadBodyList(SafeCall.safeCall(square, "getDeadBodys"), seen, visitor)
	iterDeadBodyList(SafeCall.safeCall(square, "getDeadBodies"), seen, visitor)
end

local function emitDeadBodyWithCooldown(state, emitFn, record, nowMs, cooldownMs)
	if type(emitFn) ~= "function" or type(record) ~= "table" or record.deadBodyId == nil then
		return false
	end
	state.lastEmittedMs = state.lastEmittedMs or {}
	if not Cooldown.shouldEmit(state.lastEmittedMs, record.deadBodyId, nowMs, cooldownMs) then
		return false
	end
	emitFn(record)
	Cooldown.markEmitted(state.lastEmittedMs, record.deadBodyId, nowMs)
	return true
end

local function resolveHighlightParams(pref, fallbackColor)
	local color = fallbackColor
	local alpha = 0.9
	if type(pref) == "table" then
		color = pref
		if type(color[4]) == "number" then
			alpha = color[4]
		end
	end
	return color, alpha
end

local function deadBodiesCollector(ctx, cursor, square, _playerIndex, nowMs, effective)
	local deadBodies = ctx.deadBodies
	if not (deadBodies and type(deadBodies.makeDeadBodyRecord) == "function") then
		return false
	end

	local state = ctx.state or {}
	state._deadBodiesCollector = state._deadBodiesCollector or {}
	local emittedByKey = state._deadBodiesCollector.lastEmittedMs or {}
	state._deadBodiesCollector.lastEmittedMs = emittedByKey

	local cooldownSeconds = tonumber(effective and effective.cooldown) or 0
	local cooldownMs = math.max(0, cooldownSeconds * 1000)
	local recordOpts = ctx.recordOpts or DeadBodies._defaults.recordOpts

	local emittedAny = false
	local highlighted = false
	collectDeadBodiesOnSquare(square, function(body)
		local record = deadBodies.makeDeadBodyRecord(body, square, cursor.source, {
			nowMs = nowMs,
			includeIsoDeadBody = recordOpts.includeIsoDeadBody,
		})
		if type(record) ~= "table" or record.deadBodyId == nil then
			return
		end
		if not Cooldown.shouldEmit(emittedByKey, record.deadBodyId, nowMs, cooldownMs) then
			return
		end
		if type(ctx.emitFn) == "function" then
			ctx.emitFn(record)
			Cooldown.markEmitted(emittedByKey, record.deadBodyId, nowMs)
			emittedAny = true
		end
		if not highlighted and not ctx.headless then
			local highlightPref = effective and effective.highlight or nil
			if highlightPref == true or type(highlightPref) == "table" then
				local color, alpha = resolveHighlightParams(highlightPref, cursor.color)
				Highlight.highlightFloor(square, Highlight.durationMsFromCooldownSeconds(cooldownSeconds), {
					color = color,
					alpha = alpha,
				})
				highlighted = true
			end
		end
	end)
	return emittedAny
end

if DeadBodies._internal.registerDeadBodiesCollector == nil then
	function DeadBodies._internal.registerDeadBodiesCollector()
		SquareSweep.registerCollector(INTEREST_TYPE_DEAD_BODIES, deadBodiesCollector, {
			interestType = INTEREST_TYPE_DEAD_BODIES,
		})
	end
end
DeadBodies._internal.registerDeadBodiesCollector()

local function ensureBuckets(ctx)
	local buckets = {}
	if ctx.interestRegistry and ctx.interestRegistry.effectiveBuckets then
		buckets = ctx.interestRegistry:effectiveBuckets(INTEREST_TYPE_DEAD_BODIES)
	elseif ctx.interestRegistry and ctx.interestRegistry.effective then
		local merged = ctx.interestRegistry:effective(INTEREST_TYPE_DEAD_BODIES)
		if merged then
			buckets = { { bucketKey = merged.bucketKey or "default", merged = merged } }
		end
	end
	return buckets
end

local function tickPlayerSquare(ctx)
	ctx = ctx or {}
	local state = ctx.state or {}
	ctx.state = state

	local listenerCfg = ctx.listenerCfg or {}
	local listenerEnabled = listenerCfg.enabled ~= false
	state._playerDeadBodyBuckets = state._playerDeadBodyBuckets or {}

	local activeBuckets = {}
	if listenerEnabled then
		for _, bucket in ipairs(ensureBuckets(ctx)) do
			local merged = bucket.merged
			if type(merged) == "table" and merged.scope == INTEREST_SCOPE_PLAYER_SQUARE then
				local bucketKey = bucket.bucketKey or INTEREST_SCOPE_PLAYER_SQUARE
				local target = merged.target
				local effective = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, INTEREST_TYPE_DEAD_BODIES, {
					label = INTEREST_SCOPE_PLAYER_SQUARE,
					allowDefault = false,
					log = Log,
					bucketKey = bucketKey,
					merged = merged,
				})
				if effective then
					effective.highlight = merged.highlight
					effective.target = target
					activeBuckets[bucketKey] = { effective = effective, target = target }
				end
			end
		end
	else
		state._effectiveInterestByType = state._effectiveInterestByType or {}
		if type(state._effectiveInterestByType[INTEREST_TYPE_DEAD_BODIES]) == "table" then
			state._effectiveInterestByType[INTEREST_TYPE_DEAD_BODIES][INTEREST_SCOPE_PLAYER_SQUARE] = nil
		end
	end

	for key in pairs(state._playerDeadBodyBuckets) do
		if not activeBuckets[key] then
			state._playerDeadBodyBuckets[key] = nil
		end
	end

	for bucketKey, entry in pairs(activeBuckets) do
		local bucketState = state._playerDeadBodyBuckets[bucketKey] or {}
		state._playerDeadBodyBuckets[bucketKey] = bucketState

		local target = entry.target
		local player = resolvePlayer(target)
		if player == nil then
			bucketState.lastEmittedMs = nil
		else
			local square = SafeCall.safeCall(player, "getCurrentSquare")
			if square ~= nil then
				local nowMs = nowMillis()
				local cooldownMs = math.max(0, (tonumber(entry.effective.cooldown) or 0) * 1000)
				local recordOpts = ctx.recordOpts or DeadBodies._defaults.recordOpts
				local highlighted = false
				collectDeadBodiesOnSquare(square, function(body)
					local record = DeadBodies.makeDeadBodyRecord(body, square, "player", {
						nowMs = nowMs,
						includeIsoDeadBody = recordOpts.includeIsoDeadBody,
					})
					if emitDeadBodyWithCooldown(bucketState, ctx.emitFn, record, nowMs, cooldownMs) then
						if not highlighted and not ctx.headless then
							local highlightPref = entry.effective.highlight
							if highlightPref == true or type(highlightPref) == "table" then
								local color, alpha = resolveHighlightParams(highlightPref, PLAYER_SQUARE_HIGHLIGHT_COLOR)
								Highlight.highlightFloor(
									square,
									Highlight.durationMsFromCooldownSeconds(entry.effective.cooldown),
									{ color = color, alpha = alpha }
								)
							end
						end
						highlighted = true
					end
				end)
			end
		end
	end
end

local DEAD_BODIES_TICK_HOOK_ID = "facts.deadBodies.tick"

local function registerTickHook(state, emitFn, ctx)
	if state.deadBodiesTickHookRegistered then
		return true
	end
	local factRegistry = ctx.factRegistry
	if not factRegistry or type(factRegistry.tickHook_add) ~= "function" then
		if not ctx.headless then
			Log:warn("DeadBodies tick hook not registered (FactRegistry.tickHook_add unavailable)")
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

	factRegistry:tickHook_add(DEAD_BODIES_TICK_HOOK_ID, fn)
	state.deadBodiesTickHookRegistered = true
	state.deadBodiesTickHookId = DEAD_BODIES_TICK_HOOK_ID
	return true
end

DeadBodies._internal.collectDeadBodiesOnSquare = collectDeadBodiesOnSquare
DeadBodies._internal.deadBodiesCollector = deadBodiesCollector
DeadBodies._internal.tickPlayerSquare = tickPlayerSquare
DeadBodies._internal.registerTickHook = registerTickHook

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
				local tickHookRegistered = false
				if listenerEnabled then
					tickHookRegistered = registerTickHook(state, originalEmit, {
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
						tostring(tickHookRegistered),
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

				if state.deadBodiesTickHookRegistered then
					if registry and type(registry.tickHook_remove) == "function" then
						pcall(registry.tickHook_remove, registry, state.deadBodiesTickHookId or DEAD_BODIES_TICK_HOOK_ID)
						state.deadBodiesTickHookRegistered = nil
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
