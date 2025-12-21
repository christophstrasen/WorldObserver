-- facts/sensors/square_sweep.lua -- shared square sweep sensor for near/vision scanning.
--
-- Intent:
-- - Provide a reusable square sweep driver that other fact plans can collect from.
-- - Preserve the existing squares probe behavior (near + vision) while we refactor.
local Log = require("LQR/util/log").withTag("WO.FACTS.squares")
local Config = require("WorldObserver/config")
local Time = require("WorldObserver/helpers/time")
local InterestEffective = require("WorldObserver/facts/interest_effective")
local Geometry = require("WorldObserver/facts/squares/geometry")

local moduleName = ...
local SquareSweep = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		SquareSweep = loaded
	else
		package.loaded[moduleName] = SquareSweep
	end
end
SquareSweep._internal = SquareSweep._internal or {}
SquareSweep._collectors = SquareSweep._collectors or { order = {}, orderCount = 0, byId = {}, typeById = {} }
SquareSweep._consumers = SquareSweep._consumers or {}
SquareSweep._runner = SquareSweep._runner or { state = {}, tickHookRegistered = false, tickHookId = nil, factRegistry = nil }

--- Register a square sweep collector.
--- Collectors are called for each scanned square and can emit any fact records they own.
--- @param id string
--- @param fn fun(ctx: table, cursor: table, square: any, playerIndex: number|nil, nowMs: number, effective: table): boolean|nil
--- @param opts table|nil
if SquareSweep.registerCollector == nil then
	function SquareSweep.registerCollector(id, fn, opts)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		if type(fn) ~= "function" then
			return false, "badFn"
		end
		local registry = SquareSweep._collectors
		if registry.byId[id] == nil then
			registry.orderCount = (registry.orderCount or 0) + 1
			registry.order[registry.orderCount] = id
		end
		registry.byId[id] = fn
		if type(opts) == "table" and opts.interestType ~= nil then
			registry.typeById[id] = opts.interestType
		elseif registry.typeById[id] == nil then
			registry.typeById[id] = nil
		end
		return true
	end
end

if SquareSweep.unregisterCollector == nil then
	function SquareSweep.unregisterCollector(id)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		local registry = SquareSweep._collectors
		registry.byId[id] = nil
		if registry.typeById then
			registry.typeById[id] = nil
		end
		return true
	end
end

local function isHeadless()
	return _G.WORLDOBSERVER_HEADLESS == true
end

local function isConsumerActive(entry)
	return type(entry) == "table" and entry.enabled ~= false and type(entry.emitFn) == "function"
end

local function resolveSharedProbeCfg(consumers)
	local selected = nil
	local selectedType = nil
	local priority = nil
	for _, entry in pairs(consumers or {}) do
		if isConsumerActive(entry) and entry.probeCfg ~= nil then
			local entryPriority = tonumber(entry.probePriority) or 0
			if priority == nil or entryPriority > priority then
				priority = entryPriority
				selected = entry.probeCfg
				selectedType = entry.interestType or entry.id
			end
		end
	end
	return selected, selectedType
end

local function bumpCounter(map, key, delta)
	if not map or key == nil then
		return
	end
	map[key] = (map[key] or 0) + (delta or 1)
end

local function buildCollectorContexts(state, consumers)
	local contexts = {}
	for _, entry in pairs(consumers or {}) do
		if isConsumerActive(entry) then
			local collectorId = entry.collectorId or entry.id
			if collectorId ~= nil then
				local interestType = entry.interestType or entry.id or collectorId
				local ctx = {}
				for key, value in pairs(entry.context or {}) do
					ctx[key] = value
				end
				local originalEmit = entry.emitFn
				ctx.emitFn = function(record)
					-- Diagnostics hook: count records emitted per interest type.
					-- Why: collectors can emit multiple records per visited square, and that "fan-out" matters
					-- for performance budgeting and for understanding how much work a given interest type causes.
					local diag = state and state._squareSweepDiagTick
					if type(diag) == "table" and type(diag.recordsEmittedByType) == "table" then
						bumpCounter(diag.recordsEmittedByType, interestType, 1)
					end
					if originalEmit then
						return originalEmit(record)
					end
					return nil
				end
				ctx.headless = entry.headless == true
				ctx.runtime = entry.runtime
				ctx.interestRegistry = entry.interestRegistry
				ctx.state = state
				ctx._collectorId = collectorId
				ctx._interestType = interestType
				contexts[collectorId] = ctx
			end
		end
	end
	return contexts
end

local function resolveSharedBaseContext(consumers)
	local runtime = nil
	local interestRegistry = nil
	local headless = true
	for _, entry in pairs(consumers or {}) do
		if isConsumerActive(entry) then
			if runtime == nil and entry.runtime ~= nil then
				runtime = entry.runtime
			end
			if interestRegistry == nil and entry.interestRegistry ~= nil then
				interestRegistry = entry.interestRegistry
			end
			if entry.headless ~= true then
				headless = false
			end
		end
	end
	return {
		runtime = runtime,
		interestRegistry = interestRegistry,
		headless = headless,
	}
end

local function resolveSharedInterestTypes(consumers, collectorContexts)
	local registry = SquareSweep._collectors
	local typeById = registry and registry.typeById or {}
	local seen = {}
	for _, entry in pairs(consumers or {}) do
		if isConsumerActive(entry) then
			local interestType = entry.interestType or entry.id
			if interestType ~= nil then
				seen[interestType] = true
			end
		end
	end
	if type(collectorContexts) == "table" then
		for collectorId in pairs(collectorContexts) do
			local interestType = typeById and typeById[collectorId] or nil
			if interestType ~= nil then
				seen[interestType] = true
			end
		end
	end
	local list = {}
	for interestType in pairs(seen) do
		list[#list + 1] = interestType
	end
	table.sort(list)
	return list
end

local function sharedTick()
	local runner = SquareSweep._runner
	if not runner then
		return
	end
	runner.state = runner.state or {}
	local consumers = SquareSweep._consumers or {}
	local collectorContexts = buildCollectorContexts(runner.state, consumers)
	local hasCollector = false
	for _ in pairs(collectorContexts or {}) do
		hasCollector = true
		break
	end
	if not hasCollector then
		return
	end
	local base = resolveSharedBaseContext(consumers)
	if base.interestRegistry == nil then
		return
	end
	local interestTypes = resolveSharedInterestTypes(consumers, collectorContexts)
	if #interestTypes == 0 then
		return
	end
	local sharedProbeCfg, sharedProbeType = resolveSharedProbeCfg(consumers)
	SquareSweep.tick({
		state = runner.state,
		runtime = base.runtime,
		interestRegistry = base.interestRegistry,
		headless = base.headless,
		probeCfg = sharedProbeCfg or {},
		probeCfgOverrideType = sharedProbeType,
		collectorContexts = collectorContexts,
		interestTypes = interestTypes,
	})
end

local SQUARE_SWEEP_TICK_HOOK_ID = "facts.squareSweep.tick"

--- Register a shared square sweep consumer (fact plan) that owns one collector.
--- @param id string
--- @param opts table
if SquareSweep.registerConsumer == nil then
	function SquareSweep.registerConsumer(id, opts)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		opts = opts or {}
		local entry = SquareSweep._consumers[id] or { id = id }
		entry.collectorId = opts.collectorId or entry.collectorId or id
		entry.interestType = opts.interestType or entry.interestType or id
		entry.emitFn = opts.emitFn or entry.emitFn
		entry.context = opts.context or entry.context
		entry.runtime = opts.runtime or entry.runtime
		entry.interestRegistry = opts.interestRegistry or entry.interestRegistry
		entry.headless = opts.headless == true
		entry.probeCfg = opts.probeCfg or entry.probeCfg
		entry.probePriority = tonumber(opts.probePriority) or entry.probePriority or 0
		entry.enabled = opts.enabled ~= false
		SquareSweep._consumers[id] = entry

		local runner = SquareSweep._runner
		local factRegistry = opts.factRegistry or (runner and runner.factRegistry) or nil
		if factRegistry and type(factRegistry.tickHook_add) == "function" then
			if runner and not runner.tickHookRegistered then
				local ok, err = pcall(factRegistry.tickHook_add, factRegistry, SQUARE_SWEEP_TICK_HOOK_ID, sharedTick)
				if ok then
					runner.tickHookRegistered = true
					runner.tickHookId = SQUARE_SWEEP_TICK_HOOK_ID
					runner.factRegistry = factRegistry
				elseif not isHeadless() then
					Log:warn("Square sweep tick hook not registered (err=%s)", tostring(err))
				end
			end
		elseif not isHeadless() then
			Log:warn("Square sweep tick hook not registered (FactRegistry.tickHook_add unavailable)")
		end
		return true
	end
end

--- Unregister a previously registered square sweep consumer.
--- @param id string
if SquareSweep.unregisterConsumer == nil then
	function SquareSweep.unregisterConsumer(id)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		SquareSweep._consumers[id] = nil

		local runner = SquareSweep._runner
		if runner and runner.tickHookRegistered then
			local hasActive = false
			for _, entry in pairs(SquareSweep._consumers or {}) do
				if isConsumerActive(entry) then
					hasActive = true
					break
				end
			end
			if not hasActive and runner.factRegistry and type(runner.factRegistry.tickHook_remove) == "function" then
				pcall(runner.factRegistry.tickHook_remove, runner.factRegistry, runner.tickHookId or SQUARE_SWEEP_TICK_HOOK_ID)
				runner.tickHookRegistered = false
				runner.tickHookId = nil
			end
		end
		return true
	end
end

local INTEREST_TYPE_SQUARES = "squares"
local SENSOR_INTEREST_TYPE = "squareSweep"

local PROBE_HIGHLIGHT_NEAR_COLOR = { 1.0, 0.6, 0.2 }
local PROBE_HIGHLIGHT_VISION_COLOR = { 0.3, 0.8, 1.0 }

local function tryRuntimeClockMs(runtime, methodName)
	if not runtime then
		return nil
	end
	local fn = runtime[methodName]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, value = pcall(fn, runtime)
	if ok and type(value) == "number" then
		return value
	end
	return nil
end

local function stalenessMsFromSeconds(stalenessSeconds)
	local s = tonumber(stalenessSeconds) or 0
	if s <= 0 then
		return 0
	end
	return math.floor(s * 1000)
end

local function isSquareVisible(square, playerIndex)
	if not square then
		return false
	end
	if type(square.getCanSee) == "function" then
		local ok, seen = pcall(square.getCanSee, square, playerIndex or 0)
		if ok and seen == true then
			return true
		end
	end
	return false
end

local function resolveNowMs(runtime)
	local value = tryRuntimeClockMs(runtime, "nowWall")
	if value ~= nil then
		return value
	end
	return Time.gameMillis() or math.floor(os.time() * 1000)
end

local function resolveBudgetMs(runtime)
	-- Prefer CPU time when available; fall back to a wall clock so probe slicing still works in Kahlua.
	local value = tryRuntimeClockMs(runtime, "nowCpu")
	if value ~= nil then
		return value
	end
	value = tryRuntimeClockMs(runtime, "nowWall")
	if value ~= nil then
		return value
	end
	return Time.cpuMillis() or Time.gameMillis() or 0
end

local function resolveProbeBudgetMs(baseBudgetMs, runtimeStatus, demandRatio, probeCfg)
	probeCfg = probeCfg or {}
	demandRatio = tonumber(demandRatio) or 0
	baseBudgetMs = tonumber(baseBudgetMs) or 0
	if baseBudgetMs < 0 then
		baseBudgetMs = 0
	end

	-- Hard safety: when the runtime controller says we're degraded/emergency, reduce probe work.
	if runtimeStatus and runtimeStatus.mode == "degraded" then
		return baseBudgetMs * 0.5, "degraded"
	end
	if runtimeStatus and runtimeStatus.mode == "emergency" then
		return baseBudgetMs * 0.25, "emergency"
	end

	-- Auto budget: when probes lag AND the overall WO tick has headroom, spend more of the 4ms budget on scanning.
	-- Why: interest degradation is a last resort; if we have CPU headroom, we should use it to satisfy requested staleness.
	if probeCfg.autoBudget == false then
		return baseBudgetMs, "fixed"
	end
	if not runtimeStatus or runtimeStatus.mode ~= "normal" then
		return baseBudgetMs, "fixed"
	end
	local window = runtimeStatus.window or {}
	local reason = window.reason or "steady"
	-- If WO is already over budget, don't try to "buy our way out" with more probe work.
	if reason == "woTickAvgOverBudget" or reason == "woTickSpikeOverBudget" then
		return baseBudgetMs, "fixed"
	end
	if demandRatio <= 1.0 then
		return baseBudgetMs, "fixed"
	end

	local tickBudgetMs = tonumber(window.budgetMs) or 4
	if tickBudgetMs < 0 then
		tickBudgetMs = 0
	end

	local tick = runtimeStatus.tick or {}
	local lastTickMs = tonumber(tick.lastMs)
	local avgTickMs = tonumber(tick.woAvgTickMs) or tonumber(window.avgTickMs) or 0
	local observedTickMs = (type(lastTickMs) == "number") and lastTickMs or avgTickMs
	local headroomMs = tickBudgetMs - observedTickMs
	if headroomMs <= 0 then
		return baseBudgetMs, "fixed"
	end

	local reserveMs = tonumber(probeCfg.autoBudgetReserveMs)
	if reserveMs == nil then
		reserveMs = 0.5
	end
	if reserveMs < 0 then
		reserveMs = 0
	end
	-- Budget for probes is capped by the runtime tick budget, minus a small reserve so drain/other work
	-- can still happen in the same frame without immediate hitching.
	local hardCapMs = math.max(0, tickBudgetMs - reserveMs)

	local headroomFactor = tonumber(probeCfg.autoBudgetHeadroomFactor)
	if headroomFactor == nil then
		headroomFactor = 1.0
	end
	if headroomFactor < 0 then
		headroomFactor = 0
	end
	if headroomFactor > 1 then
		headroomFactor = 1
	end

	-- Prefer the controller's breakdown if available: it ties probe budget to drain/other costs, not just
	-- the total WO tick. This keeps probes from greedily eating budget when drain is already expensive.
	local observedDrainMs = tonumber(tick.woWindowAvgDrainMs) or tonumber(window.avgDrainMs) or tonumber(tick.drainLastMs) or 0
	local observedOtherMs = tonumber(tick.woWindowAvgOtherMs) or tonumber(window.avgOtherMs) or tonumber(tick.otherLastMs) or 0
	if observedDrainMs < 0 then
		observedDrainMs = 0
	end
	if observedOtherMs < 0 then
		observedOtherMs = 0
	end
	local dynamicCapMs = math.max(0, tickBudgetMs - reserveMs - (observedDrainMs + observedOtherMs))
	if dynamicCapMs > hardCapMs then
		dynamicCapMs = hardCapMs
	end

	local maxAutoMs = tonumber(probeCfg.autoBudgetMaxMillisPerTick)
	if maxAutoMs == nil then
		maxAutoMs = hardCapMs
	end
	if maxAutoMs < 0 then
		maxAutoMs = 0
	end
	if maxAutoMs > hardCapMs then
		maxAutoMs = hardCapMs
	end
	if maxAutoMs > dynamicCapMs then
		maxAutoMs = dynamicCapMs
	end

	local minAutoMs = tonumber(probeCfg.autoBudgetMinMillisPerTick)
	if minAutoMs == nil then
		minAutoMs = baseBudgetMs
	end
	if minAutoMs < 0 then
		minAutoMs = 0
	end
	if minAutoMs > maxAutoMs then
		minAutoMs = maxAutoMs
	end

	local budgetMs = baseBudgetMs + (headroomMs * headroomFactor)
	if budgetMs < minAutoMs then
		budgetMs = minAutoMs
	end
	if budgetMs > maxAutoMs then
		budgetMs = maxAutoMs
	end
	return budgetMs, "auto"
end

local function scaleMaxSquaresPerTick(baseMaxSquaresPerTick, baseBudgetMs, budgetMs, budgetMode, probeCfg)
	-- When we deliberately raise the probe CPU budget, also raise the iteration cap so we don't leave
	-- budget on the table. Still keep a hard cap as a safety net if clocks are unavailable.
	baseMaxSquaresPerTick = tonumber(baseMaxSquaresPerTick) or 0
	baseBudgetMs = tonumber(baseBudgetMs) or 0
	budgetMs = tonumber(budgetMs) or 0
	if baseMaxSquaresPerTick <= 0 then
		return 0
	end
	if budgetMode ~= "auto" then
		return baseMaxSquaresPerTick
	end
	if baseBudgetMs <= 0 or budgetMs <= baseBudgetMs then
		return baseMaxSquaresPerTick
	end
	probeCfg = probeCfg or {}

	local scale = budgetMs / baseBudgetMs
	local scaled = math.ceil(baseMaxSquaresPerTick * scale)

	local hardCap = tonumber(probeCfg.maxPerRunHardCap) or 200
	if hardCap < baseMaxSquaresPerTick then
		hardCap = baseMaxSquaresPerTick
	end
	return math.min(hardCap, math.max(baseMaxSquaresPerTick, scaled))
end

local function resolveCell()
	-- Resolve the engine cell best-effort.
	-- We do this on-demand instead of caching to avoid holding stale engine objects and to stay compatible with headless tests.
	local getWorld = _G.getWorld
	if type(getWorld) == "function" then
		local okWorld, world = pcall(getWorld)
		if okWorld and world and type(world.getCell) == "function" then
			local okCell, cell = pcall(world.getCell, world)
			if okCell and cell and type(cell.getGridSquare) == "function" then
				return cell
			end
		end
	end
	local getCell = _G.getCell
	if type(getCell) == "function" then
		local okCell, cell = pcall(getCell)
		if okCell and cell and type(cell.getGridSquare) == "function" then
			return cell
		end
	end
	return nil
end

local function resolvePlayers(targetId)
	local players = {}
	local target = tonumber(targetId)

	local getSpecificPlayer = _G.getSpecificPlayer
	if type(target) == "number" and type(getSpecificPlayer) == "function" then
		local ok, player = pcall(getSpecificPlayer, target)
		if ok and player ~= nil then
			players[1] = player
			return players
		end
	end

	-- Prefer the simple single-player API: in most WO use cases we want "the local player"
	-- as the probe center, not a global iteration. This also avoids environments where
	-- getNumActivePlayers/getSpecificPlayer aren't available yet.
	if target == nil or target == 0 then
		local getPlayer = _G.getPlayer
		if type(getPlayer) == "function" then
			local ok, player = pcall(getPlayer)
			if ok and player ~= nil then
				players[1] = player
				return players
			end
		end
	end

	-- Fallback for environments that don't expose getPlayer() but do expose indexed players.
	local getNumPlayers = _G.getNumActivePlayers
	if type(getNumPlayers) ~= "function" or type(getSpecificPlayer) ~= "function" then
		return players
	end

	local count = getNumPlayers()
	if type(count) ~= "number" then
		return players
	end

	for index = 0, math.max(0, count - 1) do
		if target == nil or index == target then
			local ok, player = pcall(getSpecificPlayer, index)
			if ok and player ~= nil then
				players[#players + 1] = player
			end
		end
	end
	return players
end

local function resolveStaticCenter(target)
	-- Static targets are anchored by x/y/z integers.
	-- This is intentionally "mod-owned": WO cannot validate that two mods mean the same static location,
	-- so we keep these targets unshared by default (bucket keys include the declaring modId).
	if type(target) ~= "table" then
		return nil
	end
	local x = tonumber(target.x)
	local y = tonumber(target.y)
	if x == nil or y == nil then
		return nil
	end
	local z = tonumber(target.z) or 0
	local cell = resolveCell()
	if not cell then
		return nil
	end
	return {
		cell = cell,
		x = math.floor(x),
		y = math.floor(y),
		z = math.floor(z),
		playerIndex = 0,
	}
end

local function resolveCentersForTarget(target)
	if type(target) ~= "table" then
		return {}
	end
	if target.kind == "player" then
		return resolvePlayers(target.id)
	end
	if target.kind == "square" then
		local center = resolveStaticCenter(target)
		if center then
			return { center }
		end
	end
	return {}
end

local function nearbyPlayers()
	return resolvePlayers(nil)
end

local function ensureProbeCursor(state, name, opts)
	state._probeCursors = state._probeCursors or {}
	local cursor = state._probeCursors[name]
	if cursor then
		return cursor
	end
	opts = opts or {}
	cursor = {
		name = name,
		label = opts.label or name,
		source = opts.source or "probe",
		color = opts.color,
		alpha = opts.alpha,
		isVision = opts.isVision == true,
		radius = nil,
		offsets = nil,
		playerIndex = 1,
		offsetIndex = 1,
		playerCenters = {},
		targetSquaresPerSecond = 0,
		totalSquaresPerSweep = 0,
		sweepStartedMs = nil,
		sweepDeadlineMs = nil,
		lastSweepStartedMs = nil,
		lastSweepEndedMs = nil,
		lastSweepEndedTick = nil,
		lastSweepDurationMs = 0,
		lastSweepOverdueMs = 0,
		sweepEmitted = 0,
		sweepProcessed = 0,
		lastLagSignals = nil,
		lastInfoLogMs = 0,
		tickScanned = 0,
		tickVisited = 0,
		tickVisible = 0,
		tickEmitted = 0,
		tickStopReason = nil,
	}
	state._probeCursors[name] = cursor
	return cursor
end

local function resetProbeSweep(cursor, nowMs, stalenessMs)
	cursor.playerIndex = 1
	cursor.offsetIndex = 1
	cursor.playerCenters = {}
	cursor.sweepStartedMs = nowMs
	cursor.lastSweepStartedMs = nowMs
	cursor.sweepDeadlineMs = (stalenessMs and stalenessMs > 0) and (nowMs + stalenessMs) or nil
	cursor.sweepEmitted = 0
	cursor.sweepProcessed = 0
end

local function ensureProbeOffsets(cursor, radius)
	local r = math.max(0, math.floor(tonumber(radius) or 0))
	if cursor.radius ~= r or cursor.offsets == nil then
		cursor.radius = r
		cursor.offsets = Geometry.buildRingOffsets(r)
		cursor.playerIndex = 1
		cursor.offsetIndex = 1
		cursor.playerCenters = {}
		cursor.sweepStartedMs = nil
		cursor.sweepDeadlineMs = nil
		cursor.lastSweepStartedMs = nil
		cursor.lastSweepEndedMs = nil
		cursor.lastSweepEndedTick = nil
		cursor.lastSweepDurationMs = 0
		cursor.lastSweepOverdueMs = 0
		cursor.sweepEmitted = 0
		cursor.sweepProcessed = 0
	end
end

local function ensurePlayerCenter(cursor, player, playerSlot)
	if not (cursor and player) then
		return nil
	end
	local cellGetter = player.getCell
	local cell = nil
	if type(cellGetter) == "function" then
		local ok, c = pcall(cellGetter, player)
		if ok then
			cell = c
		end
	end
	if not cell or type(cell.getGridSquare) ~= "function" then
		return nil
	end
	local centerSquare = player.getCurrentSquare and player:getCurrentSquare() or nil
	if centerSquare == nil then
		return nil
	end
	local cx = (type(centerSquare.getX) == "function" and centerSquare:getX()) or nil
	local cy = (type(centerSquare.getY) == "function" and centerSquare:getY()) or nil
	local cz = (type(centerSquare.getZ) == "function" and centerSquare:getZ()) or 0
	if cx == nil or cy == nil then
		return nil
	end
	local playerIndex = 0
	if cursor.isVision and type(player.getPlayerNum) == "function" then
		local okIdx, idx = pcall(player.getPlayerNum, player)
		if okIdx and type(idx) == "number" then
			playerIndex = idx
		end
	end
	local center = { cell = cell, x = cx, y = cy, z = cz, playerIndex = playerIndex }
	cursor.playerCenters = cursor.playerCenters or {}
	cursor.playerCenters[playerSlot] = center
	return center
end

local function cursorNextSquare(cursor, players, nowMs, tickSeq)
	local offsets = cursor.offsets
	if type(offsets) ~= "table" or offsets[1] == nil then
		return nil
	end
	if cursor.sweepStartedMs == nil then
		return nil
	end

	local playerCount = #players
	if playerCount <= 0 then
		return nil
	end

	while cursor.playerIndex <= playerCount do
		local player = players[cursor.playerIndex]
		local center = ensurePlayerCenter(cursor, player, cursor.playerIndex)
		if not center then
			cursor.playerIndex = cursor.playerIndex + 1
			cursor.offsetIndex = 1
		else
			local off = offsets[cursor.offsetIndex]
			cursor.offsetIndex = cursor.offsetIndex + 1
			if cursor.offsetIndex > #offsets then
				cursor.offsetIndex = 1
				cursor.playerIndex = cursor.playerIndex + 1
			end
			if cursor.playerIndex > playerCount then
				local startedMs = cursor.sweepStartedMs
				local deadlineMs = cursor.sweepDeadlineMs
				cursor.lastSweepEndedMs = nowMs
				cursor.lastSweepEndedTick = tickSeq
				cursor.lastSweepDurationMs = (startedMs and nowMs) and (nowMs - startedMs) or 0
				cursor.lastSweepOverdueMs = deadlineMs and nowMs and nowMs > deadlineMs and (nowMs - deadlineMs) or 0

				-- Sweep completed: reset so the next tick can decide if/when we should start again.
				cursor.playerIndex = 1
				cursor.offsetIndex = 1
				cursor.playerCenters = {}
				cursor.sweepStartedMs = nil
				cursor.sweepDeadlineMs = nil
			end

			local okSq, square =
				pcall(center.cell.getGridSquare, center.cell, center.x + off[1], center.y + off[2], center.z)
			cursor.sweepProcessed = (cursor.sweepProcessed or 0) + 1
			if okSq and square then
				return square, center.playerIndex
			end
		end
	end

	cursor.playerIndex = 1
	cursor.offsetIndex = 1
	cursor.playerCenters = {}
	cursor.sweepStartedMs = nil
	cursor.sweepDeadlineMs = nil
	return nil
end

local function updateCursorSweepTargets(cursor, effective, centerCount)
	local radius = effective and effective.radius or 0
	local staleness = tonumber(effective and effective.staleness) or 0
	local sweepSquares = Geometry.squaresPerRadius(radius) * math.max(1, centerCount)
	cursor.totalSquaresPerSweep = sweepSquares

	local rate = 0
	if staleness > 0 and sweepSquares > 0 then
		rate = sweepSquares / staleness
	end
	cursor.targetSquaresPerSecond = rate
end

local function cursorCanScanThisTick(cursor, nowMs, stalenessMs, tickSeq)
	if cursor.sweepStartedMs ~= nil then
		return true
	end
	-- Avoid starting a new sweep in the same tick as we just finished one: that can create long, hard-to-read
	-- probe slices and makes it harder for the policy to react between sweeps.
	if tickSeq ~= nil and cursor.lastSweepEndedTick ~= nil and cursor.lastSweepEndedTick == tickSeq then
		return false
	end
	-- Backwards fallback: if we don't have a tick sequence, use the wall clock.
	-- Note: if the clock has low resolution, this can suppress sweeps longer than intended.
	if tickSeq == nil and cursor.lastSweepEndedMs ~= nil and nowMs ~= nil and cursor.lastSweepEndedMs == nowMs then
		return false
	end
	if stalenessMs <= 0 then
		return true
	end
	local lastStart = cursor.lastSweepStartedMs
	if lastStart == nil then
		return true
	end
	return (nowMs - lastStart) >= stalenessMs
end

local function cursorStartSweepIfDue(cursor, nowMs, stalenessMs, tickSeq)
	if cursor.sweepStartedMs ~= nil then
		return false
	end
	if not cursorCanScanThisTick(cursor, nowMs, stalenessMs, tickSeq) then
		return false
	end
	resetProbeSweep(cursor, nowMs, stalenessMs)
	return true
end

local function computeProbeLagSignals(cursor, nowMs, previousEffective)
	if not (cursor and previousEffective) then
		return nil
	end
	local targetMs = stalenessMsFromSeconds(previousEffective.staleness)
	if targetMs <= 0 then
		return nil
	end

	local elapsedMs = nil
	local estimateMs = nil
	if cursor.sweepStartedMs ~= nil and nowMs ~= nil then
		elapsedMs = nowMs - cursor.sweepStartedMs
		if elapsedMs < 0 then
			elapsedMs = 0
		end
		-- Predict whether we can finish the current sweep within the staleness target.
		-- Why: using only elapsed/target will look "healthy" early in the sweep, causing premature recovery
		-- even when the sweep can't possibly complete in time.
		local processed = tonumber(cursor.sweepProcessed) or 0
		local total = tonumber(cursor.totalSquaresPerSweep) or 0
		if elapsedMs > 0 and processed > 0 and total > 0 then
			-- Stabilize the estimate early in the sweep: if we extrapolate from only 1-2 samples,
			-- the ratio can explode (e.g. 1 processed -> "26x lag") and cause policy flapping.
			local minSamples = math.min(25, total)
			local sampleCount = math.max(processed, minSamples)
			estimateMs = (elapsedMs / sampleCount) * total
		end
	elseif type(cursor.lastSweepDurationMs) == "number" then
		elapsedMs = cursor.lastSweepDurationMs
		estimateMs = elapsedMs
	end
	if type(elapsedMs) ~= "number" then
		return nil
	end
	if type(estimateMs) ~= "number" or estimateMs < 0 then
		estimateMs = elapsedMs
	end
	local ratio = estimateMs / math.max(targetMs, 1)
	local overdueMs = math.max(0, estimateMs - targetMs)
	return {
		probeLagRatio = ratio,
		probeLagOverdueMs = overdueMs,
		probeLagEstimateMs = estimateMs,
		probeLagTargetMs = targetMs,
		probeLagElapsedMs = elapsedMs,
	}
end

local function resolveProbeLoggingCfg(probeCfg, overrideType)
	probeCfg = probeCfg or {}
	local infoEveryMs = tonumber(probeCfg.infoLogEveryMs)
	local logEachSweep = probeCfg.logEachSweep == true
	local logCollectorStats = probeCfg.logCollectorStats == true
	local collectorStatsEveryMs = tonumber(probeCfg.logCollectorStatsEveryMs)

	-- Live debug overrides: in-game the WorldObserver module is typically loaded long before a user runs
	-- console snippets, so relying on module-load config overrides is unreliable. For probe logging knobs,
	-- read `_G.WORLDOBSERVER_CONFIG_OVERRIDES` at runtime so smoke scripts can toggle verbosity without reloads.
	local targetType = tostring(overrideType or "squares")
	local probeOverrides = Config.readNested(Config.getOverrides(), { "facts", targetType, "probe" })
	if type(probeOverrides) == "table" then
		if probeOverrides.infoLogEveryMs ~= nil then
			infoEveryMs = tonumber(probeOverrides.infoLogEveryMs)
		end
		if probeOverrides.logEachSweep ~= nil then
			logEachSweep = probeOverrides.logEachSweep == true
		end
		if probeOverrides.logCollectorStats ~= nil then
			logCollectorStats = probeOverrides.logCollectorStats == true
		end
		if probeOverrides.logCollectorStatsEveryMs ~= nil then
			collectorStatsEveryMs = tonumber(probeOverrides.logCollectorStatsEveryMs)
		end
	end

	if infoEveryMs == nil then
		infoEveryMs = 10000
	end
	if collectorStatsEveryMs == nil then
		collectorStatsEveryMs = infoEveryMs
	end
	return infoEveryMs, logEachSweep, logCollectorStats, collectorStatsEveryMs
end

local function resolveCollectors(ctx)
	if type(ctx) == "table" and type(ctx.collectors) == "table" then
		return ctx.collectors
	end
	return SquareSweep._collectors
end

local function resolveCollectorContext(ctx, collectorId)
	if type(ctx) ~= "table" then
		return nil, false
	end
	local contexts = ctx.collectorContexts
	if type(contexts) == "table" then
		local collectorCtx = contexts[collectorId]
		if collectorCtx == nil then
			return nil, false
		end
		return collectorCtx, true
	end
	return ctx, true
end

local function resolveCollectorEffective(registry, collectorId, effective, collectorEffectives)
	if type(collectorEffectives) ~= "table" then
		return effective
	end
	local typeById = registry and registry.typeById or nil
	local interestType = (typeById and typeById[collectorId]) or collectorId
	-- Shared mode: only run a collector when its own interest type is active for this bucket.
	-- Returning nil tells the caller to skip invoking the collector.
	return collectorEffectives[interestType]
end

local function runCollectors(ctx, cursor, square, playerIndex, nowMs, effective, collectorEffectives)
	local registry = resolveCollectors(ctx)
	if not registry then
		return false
	end
	local diag = ctx and ctx.state and ctx.state._squareSweepDiagTick or nil
	local order = registry.order or {}
	local emittedAny = false
	for i = 1, (registry.orderCount or #order) do
		local id = order[i]
		local fn = id and registry.byId and registry.byId[id] or nil
		if fn then
			local collectorCtx, shouldRun = resolveCollectorContext(ctx, id)
			if shouldRun then
				local interestType = (registry.typeById and registry.typeById[id]) or id
				local collectorEffective = resolveCollectorEffective(registry, id, effective, collectorEffectives)
				if collectorEffectives ~= nil and collectorEffective == nil then
					-- Shared mode: this collector's interest type is not active for this bucket.
					-- Skip it so we don't emit cross-type records without an explicit interest declaration.
				else
					if type(diag) == "table" and type(diag.collectorCallsByType) == "table" then
						bumpCounter(diag.collectorCallsByType, interestType, 1)
					end
					local ok, emitted = pcall(fn, collectorCtx, cursor, square, playerIndex, nowMs, collectorEffective)
					if not ok then
						Log:warn("square sweep collector failed id=%s err=%s", tostring(id), tostring(emitted))
						if type(diag) == "table" and type(diag.collectorErrorsByType) == "table" then
							bumpCounter(diag.collectorErrorsByType, interestType, 1)
						end
					elseif emitted == true then
						emittedAny = true
						if type(diag) == "table" and type(diag.collectorEmitsByType) == "table" then
							bumpCounter(diag.collectorEmitsByType, interestType, 1)
						end
					end
				end
			end
		end
	end
	return emittedAny
end

local function normalizeInterestTypes(input)
	if type(input) ~= "table" then
		return nil
	end
	if input[1] ~= nil then
		return input
	end
	local out = {}
	for key, enabled in pairs(input) do
		if enabled == true then
			out[#out + 1] = key
		end
	end
	if #out == 0 then
		return nil
	end
	table.sort(out)
	return out
end

local function cloneBand(band)
	if type(band) ~= "table" then
		return { desired = 0, tolerable = 0 }
	end
	return {
		desired = band.desired,
		tolerable = band.tolerable,
	}
end

local function mergeBandUnion(target, knob, incoming)
	if type(incoming) ~= "table" then
		return
	end
	if target[knob] == nil then
		target[knob] = cloneBand(incoming)
		return
	end
	if knob == "radius" or knob == "zRange" then
		target[knob].desired = math.max(target[knob].desired, incoming.desired)
		target[knob].tolerable = math.max(target[knob].tolerable, incoming.tolerable)
	else
		target[knob].desired = math.min(target[knob].desired, incoming.desired)
		target[knob].tolerable = math.min(target[knob].tolerable, incoming.tolerable)
	end
end

local function mergeSpecsAcrossTypes(mergedByType)
	local combined = nil
	for _, merged in pairs(mergedByType or {}) do
		if type(merged) == "table" then
			if combined == nil then
				combined = {
					staleness = cloneBand(merged.staleness),
					radius = cloneBand(merged.radius),
					zRange = cloneBand(merged.zRange),
					cooldown = cloneBand(merged.cooldown),
				}
			else
				mergeBandUnion(combined, "staleness", merged.staleness)
				mergeBandUnion(combined, "radius", merged.radius)
				mergeBandUnion(combined, "zRange", merged.zRange)
				mergeBandUnion(combined, "cooldown", merged.cooldown)
			end
		end
	end
	return combined
end

local function collectBucketsForTypes(ctx, interestTypes, scope)
	local bucketsByKey = {}
	for _, interestType in ipairs(interestTypes or {}) do
		local buckets = {}
		if ctx.interestRegistry and ctx.interestRegistry.effectiveBuckets then
			buckets = ctx.interestRegistry:effectiveBuckets(interestType)
		elseif ctx.interestRegistry and ctx.interestRegistry.effective then
			local merged = ctx.interestRegistry:effective(interestType)
			if merged then
				buckets = { { bucketKey = merged.bucketKey or "default", merged = merged } }
			end
		end

		for _, bucket in ipairs(buckets) do
			local merged = bucket.merged
			if type(merged) == "table" then
				local mergedScope = merged.scope or scope
				if mergedScope == scope then
					local bucketKey = bucket.bucketKey or "default"
					local entry = bucketsByKey[bucketKey]
					if not entry then
						entry = {
							bucketKey = bucketKey,
							scope = mergedScope,
							target = merged.target,
							mergedByType = {},
						}
						bucketsByKey[bucketKey] = entry
					end
					entry.mergedByType[interestType] = merged
					if entry.target == nil then
						entry.target = merged.target
					end
				end
			end
		end
	end
	return bucketsByKey
end

--- Run probe scanning for squares (near + vision).
--- @param ctx table
if SquareSweep.tick == nil then
	function SquareSweep.tick(ctx)
		ctx = ctx or {}
		local state = ctx.state or {}
		ctx.state = state
		state._probeTickSeq = (state._probeTickSeq or 0) + 1
		local tickSeq = state._probeTickSeq

		-- Diagnostics (Step 8 guardrails): cheap per-tick counters that help reason about cost and fan-out.
		-- They are always collected but only logged when enabled in probe cfg / overrides.
		local diagTick = {
			tickSeq = tickSeq,
			nowMs = nil,
			squaresScanned = 0,
			squaresVisited = 0,
			squaresVisible = 0,
			collectorCallsByType = {},
			collectorEmitsByType = {},
			recordsEmittedByType = {},
			collectorErrorsByType = {},
		}
		state._squareSweepDiagTick = diagTick

		local hasCollectorContexts = type(ctx.collectorContexts) == "table"
		if type(ctx.emitFn) ~= "function" and not hasCollectorContexts then
			Log:warn("[probe] emit function unavailable; skipping tick")
			return
		end

		local nowMs = resolveNowMs(ctx.runtime)
		diagTick.nowMs = nowMs
		local effectiveByType = state._effectiveInterestByType or {}
		local active = {}
		local bucketMetas = {}

		local function previousEffectiveFor(interestType, bucketKey)
			local byType = effectiveByType[interestType]
			if type(byType) == "table" then
				return byType[bucketKey]
			end
			if bucketKey == nil then
				return byType
			end
			return nil
		end

		local interestTypes = normalizeInterestTypes(ctx.interestTypes)
		if interestTypes == nil and hasCollectorContexts then
			local registry = resolveCollectors(ctx)
			local typeById = registry and registry.typeById or {}
			local seen = {}
			for collectorId in pairs(ctx.collectorContexts or {}) do
				local interestType = typeById and typeById[collectorId] or nil
				if interestType ~= nil then
					seen[interestType] = true
				end
			end
			local list = {}
			for interestType in pairs(seen) do
				list[#list + 1] = interestType
			end
			if #list > 0 then
				table.sort(list)
				interestTypes = list
			end
		end
		local useSharedInterest = interestTypes ~= nil

		local function addBuckets(interestType, scope, label, cursorCfg, requirePlayer)
			-- Each bucket is one merged target identity (for example: "near:player:0" or "near:square:<mod>:x:y:z").
			-- We keep a cursor per bucket so:
			-- - probe lag estimates are per-target (used by the interest policy and autoBudget),
			-- - degradation/recovery does not bleed across unrelated targets.
			local buckets = {}
			if ctx.interestRegistry and ctx.interestRegistry.effectiveBuckets then
				buckets = ctx.interestRegistry:effectiveBuckets(interestType)
			elseif ctx.interestRegistry and ctx.interestRegistry.effective then
				local merged = ctx.interestRegistry:effective(interestType)
				if merged then
					buckets = { { bucketKey = merged.bucketKey or "default", merged = merged } }
				end
			end

			for _, bucket in ipairs(buckets) do
				local bucketKey = bucket.bucketKey or "default"
				local merged = bucket.merged
				local mergedScope = type(merged) == "table" and merged.scope or nil
				if mergedScope == nil then
					mergedScope = scope
				end
				if mergedScope == scope then
					local target = type(merged) == "table" and merged.target or nil
					local skip = false

					local cursorKey = tostring(bucketKey or label)
					if bucketKey == "default" then
						cursorKey = label
					end
					local displayLabel = cursorKey
					if type(displayLabel) == "string" then
						displayLabel = displayLabel:gsub(":", "-")
					end
					local cursor = ensureProbeCursor(state, cursorKey, {
						label = displayLabel,
						source = cursorCfg.source,
						color = cursorCfg.color,
						alpha = cursorCfg.alpha,
						isVision = cursorCfg.isVision,
					})

					local signals = computeProbeLagSignals(cursor, nowMs, previousEffectiveFor(interestType, bucketKey))
					cursor.lastLagSignals = signals

					local effective, meta = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, interestType, {
						label = label,
						allowDefault = false,
						signals = signals,
						bucketKey = bucketKey,
						merged = merged,
					})
					if type(meta) == "table" then
						bucketMetas[#bucketMetas + 1] = meta
					end
					if not effective then
						skip = true
					end

					if not skip then
						effective.highlight = merged and merged.highlight
						effective.target = target
						effective.scope = mergedScope
						effective.bucketKey = bucketKey
					end

					-- Vision requires a player target, because visibility checks need a player index.
					if not skip and requirePlayer and (type(target) ~= "table" or target.kind ~= "player") then
						skip = true
					end

					-- Resolve centers each tick so moving targets (players) naturally follow the engine state.
					local centers = {}
					if not skip then
						centers = resolveCentersForTarget(target)
						if #centers <= 0 then
							skip = true
						end
					end

					if not skip then
						-- totalSquaresPerSweep feeds into probe lag estimation: it helps the policy decide whether
						-- to spend more budget (autoBudget) or degrade the interest ladder.
						ensureProbeOffsets(cursor, effective.radius)
						updateCursorSweepTargets(cursor, effective, #centers)

						active[#active + 1] = {
							cursor = cursor,
							effective = effective,
							stalenessMs = stalenessMsFromSeconds(effective.staleness),
							centers = centers,
						}
					end
				end
			end
		end

		local function addBucketsShared(scope, label, cursorCfg, requirePlayer)
			local bucketMap = collectBucketsForTypes(ctx, interestTypes or {}, scope)
			for _, bucket in pairs(bucketMap or {}) do
				local bucketKey = bucket.bucketKey or "default"
				local mergedByType = bucket.mergedByType or {}
				local combined = mergeSpecsAcrossTypes(mergedByType)
				local skip = combined == nil
				local target = bucket.target
				local cursor = nil
				if not skip then
				local cursorKey = tostring(bucketKey or label)
				if bucketKey == "default" then
					cursorKey = label
				end
				local displayLabel = cursorKey
				if type(displayLabel) == "string" then
					displayLabel = displayLabel:gsub(":", "-")
				end
				cursor = ensureProbeCursor(state, cursorKey, {
					label = displayLabel,
					source = cursorCfg.source,
					color = cursorCfg.color,
					alpha = cursorCfg.alpha,
					isVision = cursorCfg.isVision,
				})

					local signals = computeProbeLagSignals(cursor, nowMs, previousEffectiveFor(SENSOR_INTEREST_TYPE, bucketKey))
					cursor.lastLagSignals = signals

					local sensorEffective, meta = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, SENSOR_INTEREST_TYPE, {
						label = label,
						allowDefault = false,
						signals = signals,
						bucketKey = bucketKey,
						merged = combined,
					})
					if type(meta) == "table" then
						bucketMetas[#bucketMetas + 1] = meta
					end
					if not sensorEffective then
						skip = true
					else
						if requirePlayer and (type(target) ~= "table" or target.kind ~= "player") then
							skip = true
						else
							local centers = resolveCentersForTarget(target)
							if #centers <= 0 then
								skip = true
							else
								sensorEffective.target = target
								sensorEffective.scope = scope
								sensorEffective.bucketKey = bucketKey

								ensureProbeOffsets(cursor, sensorEffective.radius)
								updateCursorSweepTargets(cursor, sensorEffective, #centers)

								local collectorEffectives = {}
								for interestType, merged in pairs(mergedByType) do
									local perSignals =
										computeProbeLagSignals(cursor, nowMs, previousEffectiveFor(interestType, bucketKey))
									local effective = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, interestType, {
										label = label,
										allowDefault = false,
										signals = perSignals,
										bucketKey = bucketKey,
										merged = merged,
									})
									if effective then
										effective.highlight = merged.highlight
										effective.target = merged.target
										effective.scope = merged.scope or scope
										effective.bucketKey = bucketKey
										collectorEffectives[interestType] = effective
									end
								end

								active[#active + 1] = {
									cursor = cursor,
									effective = sensorEffective,
									stalenessMs = stalenessMsFromSeconds(sensorEffective.staleness),
									centers = centers,
									collectorEffectives = collectorEffectives,
								}
							end
						end
					end
				end
			end
		end

		-- Run separate probe passes per scope so near/vision can degrade independently and stay in parallel.
		if useSharedInterest then
			addBucketsShared("near", "near", {
				source = "probe",
				color = PROBE_HIGHLIGHT_NEAR_COLOR,
				alpha = 0.9,
				isVision = false,
			}, false)

			addBucketsShared("vision", "vision", {
				source = "probe_vision",
				color = PROBE_HIGHLIGHT_VISION_COLOR,
				alpha = 0.75,
				isVision = true,
			}, true)
		else
			addBuckets(INTEREST_TYPE_SQUARES, "near", "near", {
				source = "probe",
				color = PROBE_HIGHLIGHT_NEAR_COLOR,
				alpha = 0.9,
				isVision = false,
			}, false)

			addBuckets(INTEREST_TYPE_SQUARES, "vision", "vision", {
				source = "probe_vision",
				color = PROBE_HIGHLIGHT_VISION_COLOR,
				alpha = 0.75,
				isVision = true,
			}, true)
		end

		if #active == 0 then
			return
		end

		for _, entry in ipairs(active) do
			local cursor = entry.cursor
			cursor.tickScanned = 0
			cursor.tickVisited = 0
			cursor.tickVisible = 0
			cursor.tickEmitted = 0
			cursor.tickStopReason = nil
		end

		local probeCfg = ctx.probeCfg or {}
		local infoEveryMs, logEachSweep, logCollectorStats, collectorStatsEveryMs =
			resolveProbeLoggingCfg(probeCfg, ctx.probeCfgOverrideType)
		local baseMaxSquaresPerTick = tonumber(probeCfg.maxPerRun) or 50
		if baseMaxSquaresPerTick <= 0 then
			return
		end
		local runtimeStatus = ctx.runtime and ctx.runtime.status_get and ctx.runtime:status_get() or nil
		local baseBudgetMs = tonumber(probeCfg.maxMillisPerTick or probeCfg.maxMsPerTick) or 0.75
		local demandRatio = 0
		for _, meta in ipairs(bucketMetas) do
			demandRatio = math.max(demandRatio, tonumber(meta.demandRatio) or 0)
		end
		local budgetMs, budgetMode = resolveProbeBudgetMs(baseBudgetMs, runtimeStatus, demandRatio, probeCfg)
		local maxSquaresPerTick =
			scaleMaxSquaresPerTick(baseMaxSquaresPerTick, baseBudgetMs, budgetMs, budgetMode, probeCfg)

		local rr = state._probeRoundRobin or 1
		local processed = 0
		local budgetStart = resolveBudgetMs(ctx.runtime)
		local limitedByBudget = false

		while processed < maxSquaresPerTick do
			-- In auto-budget mode, a 0ms budget means "skip probing this tick" (we have no headroom).
			-- In fixed-budget mode, 0ms means "disable time budget" and rely on maxPerRun only.
			if budgetMode == "auto" and budgetMs <= 0 then
				limitedByBudget = true
				break
			end
			if budgetMs > 0 then
				local budgetNow = resolveBudgetMs(ctx.runtime)
				if (budgetNow - budgetStart) >= budgetMs then
					limitedByBudget = true
					break
				end
			end

			local selected = nil
			for i = 1, #active do
				local idx = ((rr + i - 2) % #active) + 1
				local entry = active[idx]
				if cursorCanScanThisTick(entry.cursor, nowMs, entry.stalenessMs or 0, tickSeq) then
					selected = entry
					rr = (idx % #active) + 1
					break
				end
			end
			if not selected then
				break
			end

			local cursor = selected.cursor
			local effective = selected.effective
			local startedNow = cursorStartSweepIfDue(cursor, nowMs, selected.stalenessMs or 0, tickSeq)
			if startedNow and logEachSweep then
				Log:info(
					"[probe %s] sweep started staleness=%ss radius=%s cooldown=%ss",
					tostring(cursor.label),
					tostring(effective.staleness),
					tostring(effective.radius),
					tostring(effective.cooldown)
				)
			end
			processed = processed + 1
			cursor.tickScanned = (cursor.tickScanned or 0) + 1
			diagTick.squaresScanned = (diagTick.squaresScanned or 0) + 1

			local square, playerIndex = cursorNextSquare(cursor, selected.centers, nowMs, tickSeq)
			if square then
				cursor.tickVisited = (cursor.tickVisited or 0) + 1
				diagTick.squaresVisited = (diagTick.squaresVisited or 0) + 1
				local emitted = false
				if cursor.isVision then
					if isSquareVisible(square, playerIndex) then
						cursor.tickVisible = (cursor.tickVisible or 0) + 1
						diagTick.squaresVisible = (diagTick.squaresVisible or 0) + 1
						emitted = runCollectors(ctx, cursor, square, playerIndex, nowMs, effective, selected.collectorEffectives)
					end
				else
					emitted = runCollectors(ctx, cursor, square, playerIndex, nowMs, effective, selected.collectorEffectives)
				end
				if emitted then
					cursor.tickEmitted = (cursor.tickEmitted or 0) + 1
					cursor.sweepEmitted = (cursor.sweepEmitted or 0) + 1
				end
			end
		end

		state._probeRoundRobin = rr
		local stoppedBy = "idle"
		if limitedByBudget then
			stoppedBy = "budgetMs"
		elseif processed >= maxSquaresPerTick then
			stoppedBy = "maxPerRun"
		end
		for _, entry in ipairs(active) do
			entry.cursor.tickStopReason = stoppedBy
		end

		for _, entry in ipairs(active) do
			local cursor = entry.cursor
			local effective = entry.effective
			if logEachSweep and cursor.lastSweepEndedTick == tickSeq then
				Log:info(
					"[probe %s] sweep finished durationMs=%s overdueMs=%s processed=%s emitted=%s",
					tostring(cursor.label),
					tostring(cursor.lastSweepDurationMs or 0),
					tostring(cursor.lastSweepOverdueMs or 0),
					tostring(cursor.sweepProcessed or 0),
					tostring(cursor.sweepEmitted or 0)
				)
			end
			if infoEveryMs > 0 and (nowMs - (cursor.lastInfoLogMs or 0)) >= infoEveryMs then
				cursor.lastInfoLogMs = nowMs
				local sweepProgress = tostring(cursor.sweepProcessed or 0) .. "/" .. tostring(cursor.totalSquaresPerSweep or 0)
				local lagRatio = 0
				if type(cursor.lastLagSignals) == "table" then
					lagRatio = tonumber(cursor.lastLagSignals.probeLagRatio) or 0
				end
				local budgetLabel = tostring(budgetMs)
				if type(budgetMs) == "number" then
					budgetLabel = string.format("%.2f", budgetMs)
				end
				if budgetMode == "auto" then
					budgetLabel = budgetLabel .. " (auto)"
				end
				Log:info(
					"[probe %s] staleness=%ss radius=%s cooldown=%ss budgetMs=%s maxSquaresPerTick=%s tickScan=%s tickVisit=%s tickVisible=%s tickEmit=%s stop=%s sweep=%s lag=%.2f rate=%.1f/s",
					tostring(cursor.label),
					tostring(effective.staleness),
					tostring(effective.radius),
					tostring(effective.cooldown),
					budgetLabel,
					tostring(maxSquaresPerTick),
					tostring(cursor.tickScanned or 0),
					tostring(cursor.tickVisited or 0),
					tostring(cursor.tickVisible or 0),
					tostring(cursor.tickEmitted or 0),
					tostring(cursor.tickStopReason or "idle"),
					sweepProgress,
					lagRatio,
					tonumber(cursor.targetSquaresPerSecond) or 0
				)
			end
		end

		-- Optional summary: log how much each collector contributes to work and fan-out.
		if logCollectorStats and collectorStatsEveryMs and collectorStatsEveryMs > 0 then
			state._squareSweepLastCollectorLogMs = state._squareSweepLastCollectorLogMs or 0
			if (nowMs - state._squareSweepLastCollectorLogMs) >= collectorStatsEveryMs then
				state._squareSweepLastCollectorLogMs = nowMs
				local parts = {}
				local types = {}
				for interestType in pairs(diagTick.collectorCallsByType or {}) do
					types[#types + 1] = interestType
				end
				table.sort(types)
				for _, interestType in ipairs(types) do
					local calls = diagTick.collectorCallsByType[interestType] or 0
					local emits = diagTick.collectorEmitsByType[interestType] or 0
					local records = diagTick.recordsEmittedByType[interestType] or 0
					local errs = diagTick.collectorErrorsByType[interestType] or 0
					parts[#parts + 1] = string.format(
						"%s calls=%d emits=%d records=%d errs=%d",
						tostring(interestType),
						calls,
						emits,
						records,
						errs
					)
				end
				Log:info(
					"[probe collectors] tickScan=%s tickVisit=%s tickVisible=%s %s",
					tostring(diagTick.squaresScanned or 0),
					tostring(diagTick.squaresVisited or 0),
					tostring(diagTick.squaresVisible or 0),
					#parts > 0 and table.concat(parts, " | ") or "n/a"
				)
			end
		end

		-- Keep the last snapshot around for introspection (e.g. Debug tooling) without requiring logs.
		state._squareSweepDiagLast = diagTick
	end
end

SquareSweep._internal.nearbyPlayers = nearbyPlayers
SquareSweep._internal.resolveProbeBudgetMs = resolveProbeBudgetMs
SquareSweep._internal.scaleMaxSquaresPerTick = scaleMaxSquaresPerTick
SquareSweep._internal.ensureProbeCursor = ensureProbeCursor
SquareSweep._internal.ensureProbeOffsets = ensureProbeOffsets
SquareSweep._internal.cursorNextSquare = cursorNextSquare
SquareSweep._internal.cursorCanScanThisTick = cursorCanScanThisTick
SquareSweep._internal.computeProbeLagSignals = computeProbeLagSignals
SquareSweep._internal.resolveCollectors = resolveCollectors
SquareSweep._internal.resolveCollectorEffective = resolveCollectorEffective
SquareSweep._internal.runCollectors = runCollectors

return SquareSweep
