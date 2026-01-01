-- facts/items.lua -- item fact plan: playerSquare driver + shared square sweep collector.
local Log = require("DREAMBase/log").withTag("WO.FACTS.items")

local Record = require("WorldObserver/facts/items/record")
local SquareSweep = require("WorldObserver/facts/sensors/square_sweep")
local GroundEntities = require("WorldObserver/facts/ground_entities")
local JavaList = require("DREAMBase/pz/java_list")
local SafeCall = require("DREAMBase/pz/safe_call")

local INTEREST_TYPE_ITEMS = "items"
local INTEREST_SCOPE_PLAYER_SQUARE = "playerSquare"
local PLAYER_SQUARE_HIGHLIGHT_COLOR = { 0.9, 0.8, 0.2 }

local moduleName = ...
local Items = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Items = loaded
	else
		---@diagnostic disable-next-line: undefined-field
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
	-- Defensive cap: avoid pathological container expansion on a single square.
	-- This limits only *contained* items; ground items on the square are still visited.
	-- Set to 0/nil to disable the cap.
	maxContainerItemsPerSquare = 200,
}

-- Default item record builder.
-- Intentionally exposed via Items.makeItemRecord so other mods can patch/override it.
if Items.makeItemRecord == nil then
	function Items.makeItemRecord(item, square, source, opts)
		return Record.makeItemRecord(item, square, source, opts)
	end
end
Items._defaults.makeItemRecord = Items._defaults.makeItemRecord or Items.makeItemRecord

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
			if fn(item) == false then
				break
			end
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
	local maxContainerItems = opts and tonumber(opts.maxContainerItemsPerSquare) or nil
	if type(maxContainerItems) == "number" and maxContainerItems <= 0 then
		maxContainerItems = nil
	end
	local remainingContainerItems = maxContainerItems

	iterWorldItems(square, function(item, worldItem)
		visitor(item, worldItem, nil)

		if includeContainerItems and remainingContainerItems ~= 0 then
			local container = resolveItemContainer(item)
			if container ~= nil then
				-- Depth=1 only: do not traverse nested containers.
				iterContainerItems(container, function(contained)
					if remainingContainerItems ~= nil then
						if remainingContainerItems <= 0 then
							return false
						end
						remainingContainerItems = remainingContainerItems - 1
					end
					visitor(contained, nil, { containerItem = item, containerWorldItem = worldItem })
					return true
				end)
			end
		end
	end)
end

-- Adapter for the shared ground-entities helpers:
-- keep the original `collectItemsOnSquare` visitor shape (item, worldItem, containerInfo) for local readability,
-- but provide the normalized `(entity, extra)` callback that GroundEntities expects.
local function collectItemsOnSquareForGroundEntities(square, recordOpts, visitor)
	return collectItemsOnSquare(square, recordOpts, function(item, worldItem, containerInfo)
		visitor(item, {
			worldItem = worldItem,
			containerItem = containerInfo and containerInfo.containerItem or nil,
			containerWorldItem = containerInfo and containerInfo.containerWorldItem or nil,
		})
	end)
end

local itemsCollector = GroundEntities.buildSquareCollector({
	interestType = INTEREST_TYPE_ITEMS,
	idField = "itemId",
	collectorStateKey = "_itemsCollector",
	getRecordOpts = function(ctx)
		return (ctx and ctx.recordOpts) or Items._defaults.recordOpts
	end,
	collectOnSquare = collectItemsOnSquareForGroundEntities,
	makeRecord = function(ctx, item, square, source, _nowMs, recordOpts, extra)
		local items = ctx and ctx.items
		if not (items and type(items.makeItemRecord) == "function") then
			return nil
		end
		extra = extra or {}
		return items.makeItemRecord(item, square, source, {
			worldItem = extra.worldItem,
			containerItem = extra.containerItem,
			containerWorldItem = extra.containerWorldItem,
			includeInventoryItem = recordOpts and recordOpts.includeInventoryItem,
			includeWorldItem = recordOpts and recordOpts.includeWorldItem,
		})
	end,
})

if Items._internal.registerItemsCollector == nil then
	function Items._internal.registerItemsCollector()
		SquareSweep.registerCollector(INTEREST_TYPE_ITEMS, itemsCollector, { interestType = INTEREST_TYPE_ITEMS })
	end
end
Items._internal.registerItemsCollector()

local function tickPlayerSquare(ctx)
	-- playerSquare is a "listener-like" driver: it runs only when scope=playerSquare is declared.
	-- We keep it per-type (instead of a shared sensor) because it does constant-time work (current square only).
	GroundEntities.tickPlayerSquare(ctx, {
		log = Log,
		interestType = INTEREST_TYPE_ITEMS,
		scope = INTEREST_SCOPE_PLAYER_SQUARE,
		bucketsStateKey = "_playerSquareBuckets",
		idField = "itemId",
		playerHighlightColor = PLAYER_SQUARE_HIGHLIGHT_COLOR,
		getRecordOpts = function(innerCtx)
			return (innerCtx and innerCtx.recordOpts) or Items._defaults.recordOpts
		end,
		collectOnSquare = collectItemsOnSquareForGroundEntities,
		makeRecord = function(innerCtx, item, square, source, _nowMs, recordOpts, extra)
			extra = extra or {}
			local items = innerCtx and innerCtx.items
			if not (items and type(items.makeItemRecord) == "function") then
				return nil
			end
			return items.makeItemRecord(item, square, source, {
				worldItem = extra.worldItem,
				containerItem = extra.containerItem,
				containerWorldItem = extra.containerWorldItem,
				includeInventoryItem = recordOpts and recordOpts.includeInventoryItem,
				includeWorldItem = recordOpts and recordOpts.includeWorldItem,
			})
		end,
	})
end

local ITEMS_TICK_HOOK_ID = "facts.items.tick"

local function attachTickHookOnce(state, emitFn, ctx)
	if state.itemsTickHookAttached then
		return true
	end
	local factRegistry = ctx.factRegistry
	if not factRegistry or type(factRegistry.attachTickHook) ~= "function" then
		if not ctx.headless then
			Log:warn("Items tick hook not attached (FactRegistry.attachTickHook unavailable)")
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

	factRegistry:attachTickHook(ITEMS_TICK_HOOK_ID, fn)
	state.itemsTickHookAttached = true
	state.itemsTickHookId = ITEMS_TICK_HOOK_ID
	return true
end

Items._internal.collectItemsOnSquare = collectItemsOnSquare
Items._internal.itemsCollector = itemsCollector
Items._internal.tickPlayerSquare = tickPlayerSquare
Items._internal.attachTickHookOnce = attachTickHookOnce

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
			local maxContainerItems = itemsCfg.record.maxContainerItemsPerSquare
			recordOpts = {
				includeInventoryItem = itemsCfg.record.includeInventoryItem == true,
				includeWorldItem = itemsCfg.record.includeWorldItem == true,
				includeContainerItems = itemsCfg.record.includeContainerItems ~= false,
				maxContainerItemsPerSquare = maxContainerItems ~= nil and tonumber(maxContainerItems)
					or Items._defaults.recordOpts.maxContainerItemsPerSquare,
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
							"Items facts started (tickHook=%s sweep=%s cfgProbe=%s cfgListener=%s "
								.. "interestPlayerSquare=%s interestNear=%s interestVision=%s)",
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

				if state.itemsTickHookAttached then
					if registry and type(registry.detachTickHook) == "function" then
						pcall(registry.detachTickHook, registry, state.itemsTickHookId or ITEMS_TICK_HOOK_ID)
						state.itemsTickHookAttached = nil
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
