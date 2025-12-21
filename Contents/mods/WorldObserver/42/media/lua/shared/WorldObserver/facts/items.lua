-- facts/items.lua -- item fact plan: playerSquare driver + shared square sweep collector.
local Log = require("LQR/util/log").withTag("WO.FACTS.items")

local Record = require("WorldObserver/facts/items/record")
local SquareSweep = require("WorldObserver/facts/sensors/square_sweep")
local Cooldown = require("WorldObserver/facts/cooldown")
local InterestEffective = require("WorldObserver/facts/interest_effective")
local Highlight = require("WorldObserver/helpers/highlight")
local JavaList = require("WorldObserver/helpers/java_list")
local SafeCall = require("WorldObserver/helpers/safe_call")
local Time = require("WorldObserver/helpers/time")

local INTEREST_TYPE_ITEMS = "items"
local INTEREST_SCOPE_PLAYER_SQUARE = "playerSquare"
local PLAYER_SQUARE_HIGHLIGHT_COLOR = { 0.9, 0.8, 0.2 }

local moduleName = ...
local Items = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Items = loaded
	else
		package.loaded[moduleName] = Items
	end
end

Items._internal = Items._internal or {}
Items._defaults = Items._defaults or {}
Items._defaults.interest = Items._defaults.interest or {
	staleness = { desired = 10, tolerable = 20 },
	radius = { desired = 8, tolerable = 5 },
	cooldown = { desired = 10, tolerable = 20 },
}
Items._defaults.recordOpts = Items._defaults.recordOpts or {
	includeInventoryItem = false,
	includeWorldItem = false,
	includeContainerItems = true,
}

-- Default item record builder.
-- Intentionally exposed via Items.makeItemRecord so other mods can patch/override it.
if Items.makeItemRecord == nil then
	function Items.makeItemRecord(item, square, source, opts)
		return Record.makeItemRecord(item, square, source, opts)
	end
end
Items._defaults.makeItemRecord = Items._defaults.makeItemRecord or Items.makeItemRecord

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

local function resolveItemContainer(item)
	return SafeCall.safeCall(item, "getItemContainer") or SafeCall.safeCall(item, "getInventory")
end

local function iterContainerItems(container, fn)
	local list = SafeCall.safeCall(container, "getItems")
	if list == nil then
		return
	end
	local count = JavaList.size(list)
	for i = 1, count do
		local item = JavaList.get(list, i)
		if item ~= nil then
			fn(item)
		end
	end
end

local function iterWorldItems(square, fn)
	local list = SafeCall.safeCall(square, "getWorldObjects") or SafeCall.safeCall(square, "getObjects")
	if list == nil then
		return
	end
	local count = JavaList.size(list)
	for i = 1, count do
		local obj = JavaList.get(list, i)
		if obj ~= nil then
			if type(obj.getItem) == "function" then
				local item = SafeCall.safeCall(obj, "getItem")
				if item ~= nil then
					fn(item, obj)
				end
			elseif type(obj.getFullType) == "function" or type(obj.getType) == "function" then
				fn(obj, nil)
			end
		end
	end
end

local function collectItemsOnSquare(square, opts, visitor)
	if square == nil or type(visitor) ~= "function" then
		return
	end
	local includeContainerItems = opts and opts.includeContainerItems ~= false
	iterWorldItems(square, function(item, worldItem)
		visitor(item, worldItem, nil)

		if includeContainerItems then
			local container = resolveItemContainer(item)
			if container ~= nil then
				-- Depth=1 only: do not traverse nested containers.
				iterContainerItems(container, function(contained)
					visitor(contained, nil, { containerItem = item, containerWorldItem = worldItem })
				end)
			end
		end
	end)
end

local function emitItemWithCooldown(state, emitFn, record, nowMs, cooldownMs)
	if type(emitFn) ~= "function" or type(record) ~= "table" or record.itemId == nil then
		return false
	end
	state.lastEmittedMs = state.lastEmittedMs or {}
	if not Cooldown.shouldEmit(state.lastEmittedMs, record.itemId, nowMs, cooldownMs) then
		return false
	end
	emitFn(record)
	Cooldown.markEmitted(state.lastEmittedMs, record.itemId, nowMs)
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

local function itemsCollector(ctx, cursor, square, _playerIndex, nowMs, effective)
	local items = ctx.items
	if not (items and type(items.makeItemRecord) == "function") then
		return false
	end

	local state = ctx.state or {}
	state._itemsCollector = state._itemsCollector or {}
	local emittedByKey = state._itemsCollector.lastEmittedMs or {}
	state._itemsCollector.lastEmittedMs = emittedByKey

	local cooldownSeconds = tonumber(effective and effective.cooldown) or 0
	local cooldownMs = math.max(0, cooldownSeconds * 1000)
	local recordOpts = ctx.recordOpts or Items._defaults.recordOpts

	local emittedAny = false
	local highlighted = false
	collectItemsOnSquare(square, recordOpts, function(item, worldItem, containerInfo)
		local record = items.makeItemRecord(item, square, cursor.source, {
			nowMs = nowMs,
			worldItem = worldItem,
			containerItem = containerInfo and containerInfo.containerItem or nil,
			containerWorldItem = containerInfo and containerInfo.containerWorldItem or nil,
			includeInventoryItem = recordOpts.includeInventoryItem,
			includeWorldItem = recordOpts.includeWorldItem,
		})
		if type(record) ~= "table" or record.itemId == nil then
			return
		end
		if not Cooldown.shouldEmit(emittedByKey, record.itemId, nowMs, cooldownMs) then
			return
		end
		if type(ctx.emitFn) == "function" then
			ctx.emitFn(record)
			Cooldown.markEmitted(emittedByKey, record.itemId, nowMs)
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

if Items._internal.registerItemsCollector == nil then
	function Items._internal.registerItemsCollector()
		SquareSweep.registerCollector(INTEREST_TYPE_ITEMS, itemsCollector, { interestType = INTEREST_TYPE_ITEMS })
	end
end
Items._internal.registerItemsCollector()

local function ensureBuckets(ctx)
	local buckets = {}
	if ctx.interestRegistry and ctx.interestRegistry.effectiveBuckets then
		buckets = ctx.interestRegistry:effectiveBuckets(INTEREST_TYPE_ITEMS)
	elseif ctx.interestRegistry and ctx.interestRegistry.effective then
		local merged = ctx.interestRegistry:effective(INTEREST_TYPE_ITEMS)
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
	state._playerSquareBuckets = state._playerSquareBuckets or {}

	local activeBuckets = {}
	if listenerEnabled then
		for _, bucket in ipairs(ensureBuckets(ctx)) do
			local merged = bucket.merged
			if type(merged) == "table" and merged.scope == INTEREST_SCOPE_PLAYER_SQUARE then
				local bucketKey = bucket.bucketKey or INTEREST_SCOPE_PLAYER_SQUARE
				local target = merged.target
				local effective = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, INTEREST_TYPE_ITEMS, {
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
		if type(state._effectiveInterestByType[INTEREST_TYPE_ITEMS]) == "table" then
			state._effectiveInterestByType[INTEREST_TYPE_ITEMS][INTEREST_SCOPE_PLAYER_SQUARE] = nil
		end
	end

	for key in pairs(state._playerSquareBuckets) do
		if not activeBuckets[key] then
			state._playerSquareBuckets[key] = nil
		end
	end

	for bucketKey, entry in pairs(activeBuckets) do
		local bucketState = state._playerSquareBuckets[bucketKey] or {}
		state._playerSquareBuckets[bucketKey] = bucketState

		local target = entry.target
		local player = resolvePlayer(target)
		if player == nil then
			bucketState.lastEmittedMs = nil
		else
			local square = SafeCall.safeCall(player, "getCurrentSquare")
			if square ~= nil then
				local nowMs = nowMillis()
				local cooldownMs = math.max(0, (tonumber(entry.effective.cooldown) or 0) * 1000)
				local recordOpts = ctx.recordOpts or Items._defaults.recordOpts
				local highlighted = false
				collectItemsOnSquare(square, recordOpts, function(item, worldItem, containerInfo)
					local record = Items.makeItemRecord(item, square, "player", {
						nowMs = nowMs,
						worldItem = worldItem,
						containerItem = containerInfo and containerInfo.containerItem or nil,
						containerWorldItem = containerInfo and containerInfo.containerWorldItem or nil,
						includeInventoryItem = recordOpts.includeInventoryItem,
						includeWorldItem = recordOpts.includeWorldItem,
					})
					if emitItemWithCooldown(bucketState, ctx.emitFn, record, nowMs, cooldownMs) then
						if not highlighted and not ctx.headless then
							local highlightPref = entry.effective.highlight
							if highlightPref == true or type(highlightPref) == "table" then
								local color, alpha = resolveHighlightParams(highlightPref, PLAYER_SQUARE_HIGHLIGHT_COLOR)
								Highlight.highlightFloor(square, Highlight.durationMsFromCooldownSeconds(entry.effective.cooldown), {
									color = color,
									alpha = alpha,
								})
							end
						end
						highlighted = true
					end
				end)
			end
		end
	end
end

local ITEMS_TICK_HOOK_ID = "facts.items.tick"

local function registerTickHook(state, emitFn, ctx)
	if state.itemsTickHookRegistered then
		return true
	end
	local factRegistry = ctx.factRegistry
	if not factRegistry or type(factRegistry.tickHook_add) ~= "function" then
		if not ctx.headless then
			Log:warn("Items tick hook not registered (FactRegistry.tickHook_add unavailable)")
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

	factRegistry:tickHook_add(ITEMS_TICK_HOOK_ID, fn)
	state.itemsTickHookRegistered = true
	state.itemsTickHookId = ITEMS_TICK_HOOK_ID
	return true
end

Items._internal.collectItemsOnSquare = collectItemsOnSquare
Items._internal.itemsCollector = itemsCollector
Items._internal.tickPlayerSquare = tickPlayerSquare
Items._internal.registerTickHook = registerTickHook

-- Patch seam: define only when nil so mods can override by reassigning `Items.register`.
if Items.register == nil then
	function Items.register(registry, config, interestRegistry)
		assert(type(config) == "table", "ItemsFacts.register expects config table")
		assert(type(config.facts) == "table", "ItemsFacts.register expects config.facts table")
		assert(type(config.facts.items) == "table", "ItemsFacts.register expects config.facts.items table")
		local itemsCfg = config.facts.items
		local headless = itemsCfg.headless == true
		local probeCfg = itemsCfg.probe or {}
		local probeEnabled = probeCfg.enabled ~= false
		local listenerCfg = itemsCfg.listener or {}
		local listenerEnabled = listenerCfg.enabled ~= false
		local recordOpts = Items._defaults.recordOpts
		if type(itemsCfg.record) == "table" then
			recordOpts = {
				includeInventoryItem = itemsCfg.record.includeInventoryItem == true,
				includeWorldItem = itemsCfg.record.includeWorldItem == true,
				includeContainerItems = itemsCfg.record.includeContainerItems ~= false,
			}
		end

		registry:register(INTEREST_TYPE_ITEMS, {
			ingest = {
				mode = "latestByKey",
				ordering = "fifo",
				key = function(record)
					return record and record.itemId
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
					local ok = SquareSweep.registerConsumer(INTEREST_TYPE_ITEMS, {
						collectorId = INTEREST_TYPE_ITEMS,
						interestType = INTEREST_TYPE_ITEMS,
						emitFn = originalEmit,
						context = { items = Items, recordOpts = recordOpts },
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
					local hasPlayerSquareInterest = false
					local hasNearInterest = false
					local hasVisionInterest = false
					if interestRegistry and type(interestRegistry.effectiveBuckets) == "function" then
						local buckets = interestRegistry:effectiveBuckets(INTEREST_TYPE_ITEMS)
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
						"Items facts started (tickHook=%s sweep=%s cfgProbe=%s cfgListener=%s interestPlayerSquare=%s interestNear=%s interestVision=%s)",
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

				if state.itemsTickHookRegistered then
					if registry and type(registry.tickHook_remove) == "function" then
						pcall(registry.tickHook_remove, registry, state.itemsTickHookId or ITEMS_TICK_HOOK_ID)
						state.itemsTickHookRegistered = nil
						state.itemsTickHookId = nil
					else
						fullyStopped = false
					end
				end

				if probeEnabled then
					SquareSweep.unregisterConsumer(INTEREST_TYPE_ITEMS)
				end

				if not fullyStopped and not headless then
					Log:warn("Items fact stop requested but could not remove all handlers; keeping started=true")
				end
			end,
		})
	end
end

return Items
