-- facts/sprites.lua -- sprite fact plan: OnLoadWithSprite listener + shared square sweep collector.
local Log = require("LQR/util/log").withTag("WO.FACTS.sprites")

local Cooldown = require("WorldObserver/facts/cooldown")
local InterestEffective = require("WorldObserver/facts/interest_effective")
local Record = require("WorldObserver/facts/sprites/record")
local SquareSweep = require("WorldObserver/facts/sensors/square_sweep")
local Highlight = require("WorldObserver/helpers/highlight")
local JavaList = require("WorldObserver/helpers/java_list")
local SafeCall = require("WorldObserver/helpers/safe_call")
local Time = require("WorldObserver/helpers/time")

local INTEREST_TYPE_SPRITES = "sprites"
local INTEREST_SCOPE_ON_LOAD = "onLoadWithSprite"

local moduleName = ...
local Sprites = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Sprites = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Sprites
	end
end

Sprites._internal = Sprites._internal or {}
Sprites._defaults = Sprites._defaults or {}
Sprites._defaults.interest = Sprites._defaults.interest or {
	staleness = { desired = 10, tolerable = 20 },
	radius = { desired = 8, tolerable = 5 },
	cooldown = { desired = 10, tolerable = 20 },
}
local function nowMillis()
	return Time.gameMillis() or math.floor(os.time() * 1000)
end

-- Default sprite record builder.
-- Intentionally exposed via Sprites.makeSpriteRecord so other mods can patch/override it.
if Sprites.makeSpriteRecord == nil then
	function Sprites.makeSpriteRecord(isoObject, square, source, opts)
		return Record.makeSpriteRecord(isoObject, square, source, opts)
	end
end
Sprites._defaults.makeSpriteRecord = Sprites._defaults.makeSpriteRecord or Sprites.makeSpriteRecord

local function buildSpriteNameSet(list)
	if type(list) ~= "table" then
		return nil
	end
	local exact = {}
	local exactList = {}
	local prefixes = {}
	local seenPrefix = {}
	local matchAll = false
	for i = 1, #list do
		local name = list[i]
		if type(name) == "string" and name ~= "" then
			if string.sub(name, -1) == "%" then
				local prefix = string.sub(name, 1, -2)
				if prefix == "" then
					matchAll = true
				elseif not seenPrefix[prefix] then
					prefixes[#prefixes + 1] = prefix
					seenPrefix[prefix] = true
				end
			elseif exact[name] == nil then
				exact[name] = true
				exactList[#exactList + 1] = name
			end
		end
	end
	if not matchAll and exactList[1] == nil and prefixes[1] == nil then
		return nil
	end
	table.sort(prefixes)
	return {
		matchAll = matchAll,
		exact = exact,
		exactList = exactList,
		prefixes = prefixes,
	}
end

local function resolveSpriteNameSet(effective)
	if type(effective) ~= "table" then
		return nil
	end
	if type(effective._spriteNameSet) == "table" then
		return effective._spriteNameSet
	end
	local set = buildSpriteNameSet(effective.spriteNames)
	effective._spriteNameSet = set
	return set
end

local function spriteNameMatches(spriteNameSet, spriteName)
	if spriteNameSet == nil or spriteName == nil then
		return false
	end
	if spriteNameSet.matchAll then
		return true
	end
	if spriteNameSet.exact and spriteNameSet.exact[spriteName] then
		return true
	end
	local prefixes = spriteNameSet.prefixes
	if prefixes and prefixes[1] ~= nil then
		for i = 1, #prefixes do
			local prefix = prefixes[i]
			if string.find(spriteName, prefix, 1, true) == 1 then
				return true
			end
		end
	end
	return false
end

local function iterIsoObjects(square, fn)
	local list = SafeCall.safeCall(square, "getObjects") or SafeCall.safeCall(square, "getWorldObjects")
	if list == nil then
		return
	end
	local count = JavaList.size(list)
	for i = 1, count do
		local obj = JavaList.get(list, i)
		if obj ~= nil then
			fn(obj)
		end
	end
end

local function collectSpritesOnSquare(square, spriteNameSet, visitor)
	if square == nil or spriteNameSet == nil or type(visitor) ~= "function" then
		return
	end
	iterIsoObjects(square, function(obj)
		local sprite = SafeCall.safeCall(obj, "getSprite")
		local spriteName = SafeCall.safeCall(sprite, "getName")
		if spriteName and spriteNameMatches(spriteNameSet, spriteName) then
			local spriteId = SafeCall.safeCall(sprite, "getID")
			visitor(obj, { sprite = sprite, spriteName = spriteName, spriteId = spriteId })
		end
	end)
end

local function shouldHighlight(pref)
	return pref == true or type(pref) == "table"
end

local spritesCollector = function(ctx, cursor, square, _playerIndex, nowMs, effective)
	local state = (ctx and ctx.state) or {}
	if ctx then
		ctx.state = state
	end
	state._spritesCollector = state._spritesCollector or {}
	state._spritesCollector.lastEmittedMs = state._spritesCollector.lastEmittedMs or {}
	local emittedByKey = state._spritesCollector.lastEmittedMs

	local spriteNameSet = resolveSpriteNameSet(effective)
	if spriteNameSet == nil then
		if not state._spritesMissingNamesWarned and _G.WORLDOBSERVER_HEADLESS ~= true then
			Log:warn("Sprites collector skipped: missing spriteNames (declare interest.spriteNames)")
			state._spritesMissingNamesWarned = true
		end
		return false
	end

	local cooldownSeconds = tonumber(effective and effective.cooldown) or 0
	local cooldownMs = math.max(0, cooldownSeconds * 1000)
	local emittedAny = false
	local highlighted = false

	collectSpritesOnSquare(square, spriteNameSet, function(obj, extra)
		local sprites = ctx and ctx.sprites
		if not (sprites and type(sprites.makeSpriteRecord) == "function") then
			return
		end
		local record = sprites.makeSpriteRecord(obj, square, cursor and cursor.source or "probe", {
			sprite = extra and extra.sprite or nil,
			spriteName = extra and extra.spriteName or nil,
			spriteId = extra and extra.spriteId or nil,
		})
		if type(record) ~= "table" then
			return
		end
		local key = record.spriteKey
		if key == nil then
			return
		end
		if not Cooldown.shouldEmit(emittedByKey, key, nowMs, cooldownMs) then
			return
		end
		if type(ctx.emitFn) == "function" then
			ctx.emitFn(record)
			Cooldown.markEmitted(emittedByKey, key, nowMs)
			emittedAny = true
		end

		if not highlighted and not ctx.headless then
			local highlightPref = effective and effective.highlight or nil
			if shouldHighlight(highlightPref) then
				local color, alpha = Highlight.resolveColorAlpha(highlightPref, cursor and cursor.color or nil, 0.9)
				-- Highlight decay should track the *effective cadence* (emit rate) rather than cooldown alone.
				-- Using max(staleness,cooldown)/2 keeps highlights visible for roughly half the fastest possible re-emit window.
				Highlight.highlightFloor(
					square,
					Highlight.durationMsFromEffectiveCadence(effective),
					{
					color = color,
					alpha = alpha,
					}
				)
				highlighted = true
			end
		end
	end)

	return emittedAny
end

if Sprites._internal.registerSpritesCollector == nil then
	function Sprites._internal.registerSpritesCollector()
		SquareSweep.registerCollector(INTEREST_TYPE_SPRITES, spritesCollector, { interestType = INTEREST_TYPE_SPRITES })
	end
end
Sprites._internal.registerSpritesCollector()

local function resolveOnLoadMerged(interestRegistry)
	if not (interestRegistry and type(interestRegistry.effectiveBuckets) == "function") then
		return nil, nil
	end
	local buckets = interestRegistry:effectiveBuckets(INTEREST_TYPE_SPRITES)
	for _, bucket in ipairs(buckets or {}) do
		local merged = bucket.merged
		if type(merged) == "table" and merged.scope == INTEREST_SCOPE_ON_LOAD then
			return merged, bucket.bucketKey or INTEREST_SCOPE_ON_LOAD
		end
	end
	return nil, nil
end

local function refreshOnLoadInterest(state, ctx, listenerCfg)
	if listenerCfg and listenerCfg.enabled == false then
		state.onLoadEffective = nil
		state.onLoadSpriteNameSet = nil
		return
	end
	local merged, bucketKey = resolveOnLoadMerged(ctx.interestRegistry)
	if merged == nil then
		state.onLoadEffective = nil
		state.onLoadSpriteNameSet = nil
		return
	end

	local effective = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, INTEREST_TYPE_SPRITES, {
		label = INTEREST_SCOPE_ON_LOAD,
		allowDefault = false,
		bucketKey = bucketKey,
		merged = merged,
	})
	if effective then
		effective.highlight = merged.highlight
		effective.scope = merged.scope or INTEREST_SCOPE_ON_LOAD
		effective.bucketKey = bucketKey
		effective.spriteNames = merged.spriteNames
	end
	state.onLoadEffective = effective
	state.onLoadSpriteNameSet = resolveSpriteNameSet(effective)
end

local function attachOnLoadRegistrationsOnce(state, ctx, listenerCfg)
	local mapObjects = _G.MapObjects
	if not (mapObjects and type(mapObjects.OnLoadWithSprite) == "function") then
		if not state.onLoadMapObjectsWarned and _G.WORLDOBSERVER_HEADLESS ~= true then
			Log:warn("MapObjects.OnLoadWithSprite unavailable; sprite onLoad scope disabled")
			state.onLoadMapObjectsWarned = true
		end
		return false
	end

	local spriteNameSet = state.onLoadSpriteNameSet
	if spriteNameSet == nil then
		return false
	end

	if (spriteNameSet.matchAll or (spriteNameSet.prefixes and spriteNameSet.prefixes[1] ~= nil))
		and not state.onLoadWildcardWarned
		and _G.WORLDOBSERVER_HEADLESS ~= true
	then
		Log:warn("spriteNames wildcards are ignored for onLoadWithSprite; use explicit names or near/vision")
		state.onLoadWildcardWarned = true
	end

	local exactList = spriteNameSet.exactList or {}
	if exactList[1] == nil then
		return false
	end

	state.onLoadRegisteredNames = state.onLoadRegisteredNames or {}
	local pending = {}
	for i = 1, #exactList do
		local name = exactList[i]
		if not state.onLoadRegisteredNames[name] then
			pending[#pending + 1] = name
		end
	end
	if #pending == 0 then
		return true
	end

	local priority = tonumber(listenerCfg and listenerCfg.priority) or 5
	mapObjects.OnLoadWithSprite(pending, state.onLoadHandler, priority)
	for i = 1, #pending do
		state.onLoadRegisteredNames[pending[i]] = true
	end
	return true
end

local function onLoadHandler(state, emitFn)
	return function(isoObject)
		local effective = state.onLoadEffective
		local spriteNameSet = state.onLoadSpriteNameSet
		if effective == nil or spriteNameSet == nil then
			return
		end

		local sprite = SafeCall.safeCall(isoObject, "getSprite")
		local spriteName = SafeCall.safeCall(sprite, "getName")
		if spriteName == nil or not spriteNameMatches(spriteNameSet, spriteName) then
			return
		end
		local spriteId = SafeCall.safeCall(sprite, "getID")
		local square = SafeCall.safeCall(isoObject, "getSquare") or SafeCall.safeCall(isoObject, "getCurrentSquare")
		local nowMs = nowMillis()
		state.onLoadLastEmittedMs = state.onLoadLastEmittedMs or {}
		local cooldownSeconds = tonumber(effective.cooldown) or 0
		local cooldownMs = math.max(0, cooldownSeconds * 1000)

		local record = Sprites.makeSpriteRecord(isoObject, square, "event", {
			sprite = sprite,
			spriteName = spriteName,
			spriteId = spriteId,
		})
		if type(record) ~= "table" or record.spriteKey == nil then
			return
		end
		if not Cooldown.shouldEmit(state.onLoadLastEmittedMs, record.spriteKey, nowMs, cooldownMs) then
			return
		end
		if type(emitFn) == "function" then
			emitFn(record)
			Cooldown.markEmitted(state.onLoadLastEmittedMs, record.spriteKey, nowMs)
		end

		if not (state.headless == true) then
			local highlightPref = effective and effective.highlight or nil
			if shouldHighlight(highlightPref) and square ~= nil then
				local color, alpha = Highlight.resolveColorAlpha(highlightPref, nil, 0.9)
				Highlight.highlightFloor(
					square,
					Highlight.durationMsFromEffectiveCadence(effective),
					{
					color = color,
					alpha = alpha,
					}
				)
			end
		end
	end
end

local function tickOnLoadListener(ctx)
	local state = ctx.state or {}
	ctx.state = state
	state.headless = ctx.headless == true

	refreshOnLoadInterest(state, ctx, ctx.listenerCfg)
	if state.onLoadEffective == nil then
		return false
	end
	return attachOnLoadRegistrationsOnce(state, ctx, ctx.listenerCfg)
end

local SPRITES_TICK_HOOK_ID = "facts.sprites.tick"

local function attachTickHookOnce(state, emitFn, ctx)
	if state.spritesTickHookAttached then
		return true
	end
	local factRegistry = ctx.factRegistry
	if not factRegistry or type(factRegistry.attachTickHook) ~= "function" then
		if not ctx.headless then
			Log:warn("Sprites tick hook not attached (FactRegistry.attachTickHook unavailable)")
		end
		return false
	end

	state.onLoadHandler = state.onLoadHandler or onLoadHandler(state, emitFn)

	local fn = function()
		tickOnLoadListener({
			state = state,
			headless = ctx.headless,
			runtime = ctx.runtime,
			interestRegistry = ctx.interestRegistry,
			listenerCfg = ctx.listenerCfg,
		})
	end

	factRegistry:attachTickHook(SPRITES_TICK_HOOK_ID, fn)
	state.spritesTickHookAttached = true
	state.spritesTickHookId = SPRITES_TICK_HOOK_ID
	return true
end

Sprites._internal.collectSpritesOnSquare = collectSpritesOnSquare
Sprites._internal.spritesCollector = spritesCollector
Sprites._internal.attachTickHookOnce = attachTickHookOnce

-- Patch seam: define only when nil so mods can override by reassigning `Sprites.register`.
if Sprites.register == nil then
	function Sprites.register(registry, config, interestRegistry)
		assert(type(config) == "table", "SpritesFacts.register expects config table")
		assert(type(config.facts) == "table", "SpritesFacts.register expects config.facts table")
		assert(type(config.facts.sprites) == "table", "SpritesFacts.register expects config.facts.sprites table")
		local spritesCfg = config.facts.sprites
		local headless = spritesCfg.headless == true
		local probeCfg = spritesCfg.probe or {}
		local probeEnabled = probeCfg.enabled ~= false
		local listenerCfg = spritesCfg.listener or {}
		local listenerEnabled = listenerCfg.enabled ~= false

		registry:register(INTEREST_TYPE_SPRITES, {
			ingest = {
				mode = "latestByKey",
				ordering = "fifo",
				key = function(record)
					return record and record.spriteKey
				end,
				lane = function(record)
					return (record and record.source) or "default"
				end,
				lanePriority = function(laneName)
					if laneName == "probe" or laneName == "probe_vision" then
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
				local tickHookAttached = false
				if listenerEnabled then
					tickHookAttached = attachTickHookOnce(state, originalEmit, {
						factRegistry = registry,
						headless = headless,
						runtime = ctx.runtime,
						interestRegistry = interestRegistry,
						listenerCfg = listenerCfg,
					})
				end
				local sweepRegistered = false
				if probeEnabled then
					local ok = SquareSweep.registerConsumer(INTEREST_TYPE_SPRITES, {
						collectorId = INTEREST_TYPE_SPRITES,
						interestType = INTEREST_TYPE_SPRITES,
						emitFn = originalEmit,
						context = { sprites = Sprites },
						headless = headless,
						runtime = ctx.runtime,
						interestRegistry = interestRegistry,
						probeCfg = probeCfg,
						probePriority = 5,
						factRegistry = registry,
					})
					sweepRegistered = ok == true
				end

				if not headless then
					Log:info(
						"Sprites facts started (tickHook=%s sweep=%s cfgProbe=%s cfgListener=%s)",
						tostring(tickHookAttached),
						tostring(sweepRegistered),
						tostring(probeEnabled),
						tostring(listenerEnabled)
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

				state.onLoadEffective = nil
				state.onLoadSpriteNameSet = nil

				if state.spritesTickHookAttached then
					if registry and type(registry.detachTickHook) == "function" then
						pcall(registry.detachTickHook, registry, state.spritesTickHookId or SPRITES_TICK_HOOK_ID)
						state.spritesTickHookAttached = nil
						state.spritesTickHookId = nil
					else
						fullyStopped = false
					end
				end

				if probeEnabled then
					SquareSweep.unregisterConsumer(INTEREST_TYPE_SPRITES)
				end

				-- MapObjects handlers cannot be removed; keep started=true so we don't register duplicates.
				if not fullyStopped and not headless then
					Log:warn("Sprites fact stop requested but could not remove all handlers; keeping started=true")
				end
				return fullyStopped
			end,
		})
	end
end

return Sprites
