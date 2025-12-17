-- facts/squares/probe.lua -- interest-driven, time-sliced square probing (near + vision).
local Log = require("LQR/util/log").withTag("WO.FACTS.squares")
local Time = require("WorldObserver/helpers/time")
local Highlight = require("WorldObserver/helpers/highlight")
local Cooldown = require("WorldObserver/facts/cooldown")
local InterestEffective = require("WorldObserver/facts/interest_effective")
local Geometry = require("WorldObserver/facts/squares/geometry")

local moduleName = ...
local Probe = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Probe = loaded
	else
		package.loaded[moduleName] = Probe
	end
end
Probe._internal = Probe._internal or {}

local INTEREST_TYPE_NEAR = "squares.nearPlayer"
local INTEREST_TYPE_VISION = "squares.vision"

local PROBE_HIGHLIGHT_NEAR_COLOR = { 1.0, 0.6, 0.2 }
local PROBE_HIGHLIGHT_VISION_COLOR = { 0.3, 0.8, 1.0 }

local function highlightDurationMsFromStalenessSeconds(stalenessSeconds)
	-- Visual feedback should roughly match probe cadence so players can “see the sweep” without cluttering forever.
	-- Half of the requested staleness makes the highlighted area decay before the next expected refresh.
	local s = tonumber(stalenessSeconds) or 0
	if s <= 0 then
		return 0
	end
	return math.floor((s * 1000) / 2)
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
	if runtime and runtime.nowWall then
		local ok, value = pcall(runtime.nowWall, runtime)
		if ok and type(value) == "number" then
			return value
		end
	end
	return Time.gameMillis() or math.floor(os.time() * 1000)
end

local function resolveBudgetMs(runtime)
	-- Prefer CPU time when available; fall back to a wall clock so probe slicing still works in Kahlua.
	if runtime and runtime.nowCpu then
		local ok, value = pcall(runtime.nowCpu, runtime)
		if ok and type(value) == "number" then
			return value
		end
	end
	if runtime and runtime.nowWall then
		local ok, value = pcall(runtime.nowWall, runtime)
		if ok and type(value) == "number" then
			return value
		end
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
	if reason == "ingestBacklogRising" or reason == "ingestDropsRising" or reason == "woTickAvgOverBudget" or reason == "woTickSpikeOverBudget" then
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
		headroomFactor = 0.8
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

local function nearbyPlayers()
	local players = {}

	-- Prefer the simple single-player API: in most WO use cases we want "the local player"
	-- as the probe center, not a global iteration. This also avoids environments where
	-- getNumActivePlayers/getSpecificPlayer aren't available yet.
	local getPlayer = _G.getPlayer
	if type(getPlayer) == "function" then
		local ok, player = pcall(getPlayer)
		if ok and player ~= nil then
			players[1] = player
			return players
		end
	end

	-- Fallback for environments that don't expose getPlayer() but do expose indexed players.
	local getNumPlayers = _G.getNumActivePlayers
	local getSpecificPlayer = _G.getSpecificPlayer
	if type(getNumPlayers) ~= "function" or type(getSpecificPlayer) ~= "function" then
		return players
	end

	local count = getNumPlayers()
	if type(count) ~= "number" then
		return players
	end

	for index = 0, math.max(0, count - 1) do
		local ok, player = pcall(getSpecificPlayer, index)
		if ok and player ~= nil then
			players[#players + 1] = player
		end
	end
	return players
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
		cursor.sweepEmitted = 0
		cursor.sweepProcessed = 0
	end
end

local function ensurePlayerCenter(cursor, player, playerSlot)
	local cached = cursor.playerCenters and cursor.playerCenters[playerSlot]
	if cached then
		return cached
	end
	if not player or type(player.getSquare) ~= "function" then
		return nil
	end
	local okSquare, centerSquare = pcall(player.getSquare, player)
	if not okSquare or not centerSquare then
		return nil
	end
	local cell = nil
	if type(centerSquare.getCell) == "function" then
		local okCell, value = pcall(centerSquare.getCell, centerSquare)
		if okCell then
			cell = value
		end
	end
	if not cell or type(cell.getGridSquare) ~= "function" then
		return nil
	end
	local cx = type(centerSquare.getX) == "function" and centerSquare:getX() or nil
	local cy = type(centerSquare.getY) == "function" and centerSquare:getY() or nil
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

local function updateCursorSweepTargets(cursor, effective, playerCount)
	local radius = effective and effective.radius or 0
	local staleness = tonumber(effective and effective.staleness) or 0
	local sweepSquares = Geometry.squaresPerRadius(radius) * math.max(1, playerCount)
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

local function highlightSquare(square, cursor, highlightMs, headless)
	if headless or highlightMs <= 0 or not square then
		return
	end
	local okFloor, floor = pcall(square.getFloor, square)
	if okFloor and floor then
		Highlight.highlightTarget(floor, {
			durationMs = highlightMs,
			color = cursor.color,
			alpha = cursor.alpha,
		})
	end
end

local function resolveProbeLoggingCfg(probeCfg)
	probeCfg = probeCfg or {}
	local infoEveryMs = tonumber(probeCfg.infoLogEveryMs)
	local logEachSweep = probeCfg.logEachSweep == true

	-- Live debug overrides: in-game the WorldObserver module is typically loaded long before a user runs
	-- console snippets, so relying on module-load config overrides is unreliable. For probe logging knobs,
	-- read `_G.WORLDOBSERVER_CONFIG_OVERRIDES` at runtime so smoke scripts can toggle verbosity without reloads.
	local overrides = _G.WORLDOBSERVER_CONFIG_OVERRIDES
	if type(overrides) == "table" then
		local facts = type(overrides.facts) == "table" and overrides.facts or nil
		local squares = type(facts) == "table" and facts.squares or nil
		local probe = type(squares) == "table" and squares.probe or nil
		if type(probe) == "table" then
			if probe.infoLogEveryMs ~= nil then
				infoEveryMs = tonumber(probe.infoLogEveryMs)
			end
			if probe.logEachSweep ~= nil then
				logEachSweep = probe.logEachSweep == true
			end
		end
	end

	if infoEveryMs == nil then
		infoEveryMs = 10000
	end
	return infoEveryMs, logEachSweep
end

local function processProbeSquare(ctx, cursor, square, playerIndex, nowMs)
	local squares = ctx.squares
	if not (squares and type(squares.makeSquareRecord) == "function") then
		return false
	end

	local record = squares.makeSquareRecord(square, cursor.source)
	if not (type(record) == "table" and record.squareId ~= nil) then
		return false
	end

	local state = ctx.state or {}
	state.lastEmittedMs = state.lastEmittedMs or {}
	local cooldownMs = math.max(0, ((ctx.cooldownSeconds or 0) * 1000))
	if not Cooldown.shouldEmit(state.lastEmittedMs, record.squareId, nowMs, cooldownMs) then
		return false
	end

	local highlightMs = tonumber(ctx.highlightMs)
	if highlightMs == nil then
		highlightMs = highlightDurationMsFromStalenessSeconds(ctx.stalenessSeconds)
	end
	if not ctx.headless and highlightMs > 0 then
		local okFloor, floor = pcall(square.getFloor, square)
		if okFloor and floor then
			Highlight.highlightTarget(floor, {
				durationMs = highlightMs,
				color = cursor.color,
				alpha = cursor.alpha,
			})
		end
	end

	if type(ctx.emitFn) == "function" then
		ctx.emitFn(record)
		Cooldown.markEmitted(state.lastEmittedMs, record.squareId, nowMs)
	end

	cursor.sweepEmitted = (cursor.sweepEmitted or 0) + 1
	return true
end

--- Run probe scanning for squares (near + vision).
--- @param ctx table
if Probe.tick == nil then
	function Probe.tick(ctx)
		ctx = ctx or {}
		local state = ctx.state or {}
		ctx.state = state
		state._probeTickSeq = (state._probeTickSeq or 0) + 1
		local tickSeq = state._probeTickSeq

		if type(ctx.emitFn) ~= "function" then
			Log:warn("[probe] emit function unavailable; skipping tick")
			return
		end

		local nowMs = resolveNowMs(ctx.runtime)
		local effectiveByType = state._effectiveInterestByType or {}

		local nearCursor = ensureProbeCursor(state, "near", {
			label = "near",
			source = "probe",
			color = PROBE_HIGHLIGHT_NEAR_COLOR,
			alpha = 0.9,
		})
		local visionCursor = ensureProbeCursor(state, "vision", {
			label = "vision",
			source = "probe_vision",
			color = PROBE_HIGHLIGHT_VISION_COLOR,
			alpha = 0.75,
			isVision = true,
		})

		local signalsNear = computeProbeLagSignals(nearCursor, nowMs, effectiveByType[INTEREST_TYPE_NEAR])
		local signalsVision = computeProbeLagSignals(visionCursor, nowMs, effectiveByType[INTEREST_TYPE_VISION])
		nearCursor.lastLagSignals = signalsNear
		visionCursor.lastLagSignals = signalsVision

		local defaultInterest = ctx.defaultInterest
		local effectiveNear = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, INTEREST_TYPE_NEAR, {
			label = "near",
			allowDefault = true,
			defaultInterest = defaultInterest,
			signals = signalsNear,
		})
		local effectiveVision = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, INTEREST_TYPE_VISION, {
			label = "vision",
			allowDefault = false,
			signals = signalsVision,
		})

		local function demandRatioForInterest(interestType, signals)
			if type(signals) ~= "table" then
				return 0
			end
			local policyState = state._interestPolicyState and state._interestPolicyState[interestType]
			local desiredStaleness = nil
			if type(policyState) == "table" and type(policyState.ladder) == "table" and type(policyState.ladder[1]) == "table" then
				desiredStaleness = tonumber(policyState.ladder[1].staleness)
			end
			if type(desiredStaleness) ~= "number" or desiredStaleness <= 0 then
				return 0
			end
			local estimateMs = tonumber(signals.probeLagEstimateMs)
			if type(estimateMs) ~= "number" then
				local ratio = tonumber(signals.probeLagRatio)
				local targetMs = tonumber(signals.probeLagTargetMs)
				if type(ratio) == "number" and type(targetMs) == "number" then
					estimateMs = ratio * targetMs
				end
			end
			if type(estimateMs) ~= "number" or estimateMs <= 0 then
				return 0
			end
			local desiredMs = desiredStaleness * 1000
			if desiredMs <= 0 then
				return 0
			end
			return estimateMs / desiredMs
		end

		local players = nearbyPlayers()
		local playerCount = #players
		if playerCount <= 0 then
			return
		end

		local active = {}
		if effectiveNear then
			ensureProbeOffsets(nearCursor, effectiveNear.radius)
			updateCursorSweepTargets(nearCursor, effectiveNear, playerCount)
			active[#active + 1] = {
				cursor = nearCursor,
				effective = effectiveNear,
				stalenessMs = stalenessMsFromSeconds(effectiveNear.staleness),
			}
		end
		if effectiveVision then
			ensureProbeOffsets(visionCursor, effectiveVision.radius)
			updateCursorSweepTargets(visionCursor, effectiveVision, playerCount)
			active[#active + 1] = {
				cursor = visionCursor,
				effective = effectiveVision,
				stalenessMs = stalenessMsFromSeconds(effectiveVision.staleness),
			}
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
			local infoEveryMs, logEachSweep = resolveProbeLoggingCfg(probeCfg)
			local baseMaxSquaresPerTick = tonumber(probeCfg.maxPerRun) or 50
			if baseMaxSquaresPerTick <= 0 then
				return
			end
			local runtimeStatus = ctx.runtime and ctx.runtime.status_get and ctx.runtime:status_get() or nil
			local baseBudgetMs = tonumber(probeCfg.maxMillisPerTick or probeCfg.maxMsPerTick) or 0.75
		local demandRatio = 0
		if effectiveNear then
			demandRatio = math.max(demandRatio, demandRatioForInterest(INTEREST_TYPE_NEAR, signalsNear))
		end
		if effectiveVision then
			demandRatio = math.max(demandRatio, demandRatioForInterest(INTEREST_TYPE_VISION, signalsVision))
			end
			local budgetMs, budgetMode = resolveProbeBudgetMs(baseBudgetMs, runtimeStatus, demandRatio, probeCfg)
			local maxSquaresPerTick = baseMaxSquaresPerTick
			if budgetMode == "auto" and baseBudgetMs > 0 and budgetMs > baseBudgetMs then
				-- When we deliberately raise the probe CPU budget, also raise the iteration cap so we don't
				-- leave budget on the table. Still keep a hard cap as a safety net if clocks are unavailable.
				local scale = budgetMs / baseBudgetMs
				local scaled = math.ceil(baseMaxSquaresPerTick * scale)
				local hardCap = tonumber(probeCfg.maxPerRunHardCap) or 200
				if hardCap < baseMaxSquaresPerTick then
					hardCap = baseMaxSquaresPerTick
				end
				maxSquaresPerTick = math.min(hardCap, math.max(baseMaxSquaresPerTick, scaled))
			end

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

			local stalenessSeconds = tonumber(effective.staleness) or 0
			local cooldownSeconds = tonumber(effective.cooldown) or 0
			local highlightMs = highlightDurationMsFromStalenessSeconds(stalenessSeconds)

			local square, playerIndex = cursorNextSquare(cursor, players, nowMs, tickSeq)
			if square then
				cursor.tickVisited = (cursor.tickVisited or 0) + 1
				local emitted = false
				if cursor.isVision then
					if isSquareVisible(square, playerIndex) then
						cursor.tickVisible = (cursor.tickVisible or 0) + 1
						highlightSquare(square, cursor, highlightMs, ctx.headless)
						emitted = processProbeSquare({
							state = state,
							squares = ctx.squares,
							emitFn = ctx.emitFn,
							headless = ctx.headless,
							stalenessSeconds = stalenessSeconds,
							cooldownSeconds = cooldownSeconds,
							highlightMs = 0, -- highlight is handled on scan so cooldown doesn't hide sweep progress
						}, cursor, square, playerIndex, nowMs)
					end
				else
					highlightSquare(square, cursor, highlightMs, ctx.headless)
					emitted = processProbeSquare({
						state = state,
						squares = ctx.squares,
						emitFn = ctx.emitFn,
						headless = ctx.headless,
						stalenessSeconds = stalenessSeconds,
						cooldownSeconds = cooldownSeconds,
						highlightMs = 0, -- highlight is handled on scan so cooldown doesn't hide sweep progress
					}, cursor, square, playerIndex, nowMs)
				end
				if emitted then
					cursor.tickEmitted = (cursor.tickEmitted or 0) + 1
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
	end
end

Probe._internal.nearbyPlayers = nearbyPlayers
Probe._internal.ensureProbeCursor = ensureProbeCursor
Probe._internal.ensureProbeOffsets = ensureProbeOffsets
Probe._internal.cursorNextSquare = cursorNextSquare
Probe._internal.cursorCanScanThisTick = cursorCanScanThisTick
Probe._internal.computeProbeLagSignals = computeProbeLagSignals

return Probe
