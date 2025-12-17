-- interest/policy.lua -- merges interest bands with runtime signals to choose effective probe quality.
local Log = require("LQR/util/log").withTag("WO.INTEREST")

local moduleName = ...
local Policy = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Policy = loaded
	else
		package.loaded[moduleName] = Policy
	end
end
Policy._internal = Policy._internal or {}
Policy._defaults = Policy._defaults or {}

--- @class WOInterestBand
--- @field desired number
--- @field tolerable number

--- @class WOInterestMerged
--- @field staleness WOInterestBand
--- @field radius WOInterestBand
--- @field cooldown WOInterestBand

--- @class WOInterestState
--- @field qualityIndex integer
--- @field overloadStreak integer
--- @field lagStreak integer
--- @field normalStreak integer
--- @field ladder table

local function cloneTable(tbl)
	local out = {}
	for k, v in pairs(tbl or {}) do
		out[k] = v
	end
	return out
end

	local defaultConfig = {
	tolerableFactor = {
		staleness = 2.0,
		cooldown = 2.0,
		-- Matches the default squares interest (8 -> 5). Used when callers provide only `desired`.
		radius = 0.625,
	},
	-- Ladder smoothing: instead of jumping directly from desired -> tolerable, use a few intermediate steps.
	-- Why: avoids binary behavior (e.g. staleness 1 -> 10) and reduces quality flapping when load is near the edge.
	ladderStepFactor = {
		staleness = 2.0,
		cooldown = 2.0,
		radius = 0.75,
	},
	ladderMaxIntermediateSteps = 4,
	minRadius = 0,
	emergencySteps = 3,
	-- Degrade only when we observe meaningful drops.
	dropMinAbsolute = 1,
	dropRatioThreshold = 0.10, -- dropped vs ingest/drain rates (rough heuristic to avoid single stray drops)
	-- Probe-lag trigger: degrade if a sweep can't keep up with the staleness target.
	lagRatioThreshold = 1.0, -- >1 means "we exceeded the target staleness while still working"
	lagRatioRecoverThreshold = 0.9, -- <1 provides hysteresis (avoid immediate recover when we're barely meeting the target)
		lagOverdueMinMs = 0, -- allow callers to require a minimum overdue before reacting
		lagHoldTicks = 10, -- require sustained lag to avoid reacting to a single slow tick
		degradeHoldWindows = 1,
		recoverHoldWindows = 2,
		recoverHoldTicksAfterLag = 30, -- extra hysteresis after lag-triggered degrade (prevents 1<->2 flapping)
		recoverMaxFill = 0.25, -- avgFill threshold to consider backlog healthy
	}

Policy._defaults.config = defaultConfig

local function normalizeBand(value, knob, cfg)
	if type(value) == "table" then
		local desired = tonumber(value.desired) or tonumber(value[1])
		local tolerable = tonumber(value.tolerable) or tonumber(value[2])
		if desired and not tolerable then
			local factor = cfg.tolerableFactor[knob] or 1
			if knob == "radius" then
				tolerable = math.max(cfg.minRadius or 0, desired * factor)
			else
				tolerable = desired * factor
			end
		end
		if desired and tolerable then
			return {
				desired = desired,
				tolerable = tolerable,
			}
		end
	end
	local desired = tonumber(value) or 0
	local factor = cfg.tolerableFactor[knob] or 1
	local tolerable
	if knob == "radius" then
		tolerable = math.max(cfg.minRadius or 0, desired * factor)
	else
		tolerable = desired * factor
	end
	return {
		desired = desired,
		tolerable = tolerable,
	}
end

local function normalizeBands(merged, cfg)
	return {
		staleness = normalizeBand(merged.staleness or 0, "staleness", cfg),
		radius = normalizeBand(merged.radius or 0, "radius", cfg),
		cooldown = normalizeBand(merged.cooldown or 0, "cooldown", cfg),
	}
end

local function appendStep(steps, value)
	if value == nil then
		return
	end
	if steps[1] == nil then
		steps[1] = value
		return
	end
	local last = steps[#steps]
	if last == value then
		return
	end
	steps[#steps + 1] = value
end

local function buildIncreaseSteps(desired, tolerable, factor, maxIntermediateSteps)
	local steps = {}
	appendStep(steps, desired)
	if type(desired) ~= "number" or type(tolerable) ~= "number" then
		return steps
	end
	if desired >= tolerable then
		return steps
	end
	factor = tonumber(factor) or 2.0
	if factor <= 1.0 then
		factor = 2.0
	end
	maxIntermediateSteps = tonumber(maxIntermediateSteps) or 0
	if maxIntermediateSteps < 0 then
		maxIntermediateSteps = 0
	end
	local current = desired
	local stepsUsed = 0
	while current < tolerable and stepsUsed < maxIntermediateSteps do
		local nextValue = current * factor
		if nextValue <= current then
			break
		end
		if nextValue > tolerable then
			nextValue = tolerable
		end
		appendStep(steps, nextValue)
		current = nextValue
		stepsUsed = stepsUsed + 1
		if current >= tolerable then
			break
		end
	end
	appendStep(steps, tolerable)
	return steps
end

local function buildDecreaseSteps(desired, tolerable, factor, maxIntermediateSteps)
	local steps = {}
	appendStep(steps, desired)
	if type(desired) ~= "number" or type(tolerable) ~= "number" then
		return steps
	end
	if desired <= tolerable then
		return steps
	end
	factor = tonumber(factor) or 0.75
	if factor <= 0 or factor >= 1 then
		factor = 0.75
	end
	maxIntermediateSteps = tonumber(maxIntermediateSteps) or 0
	if maxIntermediateSteps < 0 then
		maxIntermediateSteps = 0
	end
	local current = desired
	local stepsUsed = 0
	while current > tolerable and stepsUsed < maxIntermediateSteps do
		-- Use ceil so small radii still progress smoothly (e.g. 7 -> 6 -> 5 -> 4).
		local nextValue = math.ceil(current * factor)
		if nextValue >= current then
			nextValue = current - 1
		end
		if nextValue < tolerable then
			nextValue = tolerable
		end
		appendStep(steps, nextValue)
		current = nextValue
		stepsUsed = stepsUsed + 1
		if current <= tolerable then
			break
		end
	end
	appendStep(steps, tolerable)
	return steps
end

local function buildLadder(bands, cfg)
	local ladder = {}
	local stalenessBand = bands.staleness
	local radiusBand = bands.radius
	local cooldownBand = bands.cooldown
	local stepFactor = cfg.ladderStepFactor or {}
	local maxIntermediate = cfg.ladderMaxIntermediateSteps

	local function pushLevel(sta, rad, cool)
		ladder[#ladder + 1] = {
			staleness = sta,
			radius = rad,
			cooldown = cool,
		}
	end

	local stalenessSteps = buildIncreaseSteps(
		stalenessBand.desired,
		stalenessBand.tolerable,
		stepFactor.staleness,
		maxIntermediate
	)
	local radiusSteps = buildDecreaseSteps(
		radiusBand.desired,
		radiusBand.tolerable,
		stepFactor.radius,
		maxIntermediate
	)
	local cooldownSteps = buildIncreaseSteps(
		cooldownBand.desired,
		cooldownBand.tolerable,
		stepFactor.cooldown,
		maxIntermediate
	)

	local desiredRadius = radiusSteps[1] or radiusBand.desired
	local desiredCooldown = cooldownSteps[1] or cooldownBand.desired
	local tolerableStaleness = stalenessSteps[#stalenessSteps] or stalenessBand.tolerable
	local tolerableRadius = radiusSteps[#radiusSteps] or radiusBand.tolerable

	pushLevel(stalenessSteps[1] or stalenessBand.desired, desiredRadius, desiredCooldown)

	-- Degrade order is intentional and deterministic:
	-- 1) increase staleness (accept older observations),
	-- 2) reduce radius (scan fewer tiles),
	-- 3) increase cooldown (emit less frequently per key).
	for i = 2, #stalenessSteps do
		pushLevel(stalenessSteps[i], desiredRadius, desiredCooldown)
	end
	for i = 2, #radiusSteps do
		pushLevel(tolerableStaleness, radiusSteps[i], desiredCooldown)
	end
	for i = 2, #cooldownSteps do
		pushLevel(tolerableStaleness, tolerableRadius, cooldownSteps[i])
	end

	for _ = 1, cfg.emergencySteps or 0 do
		local prev = ladder[#ladder]
		pushLevel(
			prev.staleness * 2,
			math.max(cfg.minRadius or 0, prev.radius / 2),
			prev.cooldown * 2
		)
	end

	return ladder
end

local function clampQualityIndex(idx, ladder)
	assert(type(idx) == "number", "qualityIndex must be a number")
	assert(#ladder > 0, "ladder must not be empty")
	if idx < 1 then
		return 1
	end
	if idx > #ladder then
		return #ladder
	end
	return idx
end

local function isRuntimeOverloaded(status, cfg)
	if not status or not status.window then
		return false
	end
	if status.mode == "emergency" then
		return true
	end
	local dropDelta = tonumber(status.window.dropDelta) or 0
	if dropDelta < (cfg.dropMinAbsolute or 0) then
		return false
	end
	local ingestRate = tonumber(status.window.avgIngestRate15) or 0
	local throughput = tonumber(status.window.avgThroughput15) or 0
	-- We don't have a perfect "items processed this window" counter in the controller status.
	-- Using rates gives us a stable enough signal: when the window is ~1s (default), dropDelta is
	-- roughly “drops per second”, and dividing by the larger of ingest/drain rate approximates a ratio.
	local denom = math.max(ingestRate, throughput, 1)
	local dropRatio = dropDelta / denom
	-- Overload trigger is drop-biased: we only degrade probes when we are visibly losing work,
	-- not just because tick ms is noisy. Ratio guards against a single dropped item when intake is tiny.
	return dropRatio >= (cfg.dropRatioThreshold or 1.0)
end

local function isProbeLagging(signals, cfg)
	if type(signals) ~= "table" then
		return false
	end
	local ratio = tonumber(signals.probeLagRatio) or 0
	if ratio <= 0 then
		return false
	end
	if ratio <= (cfg.lagRatioThreshold or 1.0) then
		return false
	end
	local overdueMs = tonumber(signals.probeLagOverdueMs) or 0
	return overdueMs >= (cfg.lagOverdueMinMs or 0)
end

local function runtimeHasHeadroomForProbeCatchup(status, cfg)
	-- Prefer probe budget ramping over interest degradation when we have global WO tick headroom.
	-- Why: "probe lag" is a symptom, but if we are still well under the 4ms budget we can just spend
	-- more time scanning and keep the requested quality without penalizing mods.
	if not status or status.mode ~= "normal" then
		return false
	end
	local window = status.window or {}
	local budgetMs = tonumber(window.budgetMs) or 0
	if budgetMs <= 0 then
		return false
	end
	if window.reason == "woTickAvgOverBudget" or window.reason == "woTickSpikeOverBudget" then
		return false
	end
	local tick = status.tick or {}
	local observedMs = tonumber(tick.lastMs) or tonumber(tick.woAvgTickMs) or tonumber(window.avgTickMs) or 0
	if observedMs < 0 then
		observedMs = 0
	end
	local util = observedMs / math.max(budgetMs, 0.001)
	local threshold = tonumber(cfg.lagDeferUtilThreshold)
	if threshold == nil then
		threshold = 0.80
	end
	if threshold <= 0 or threshold > 1 then
		threshold = 0.80
	end
	return util <= threshold
end

local function estimateProbeSweepMs(signals, fallbackTargetMs)
	if type(signals) ~= "table" then
		return nil
	end
	local estimate = tonumber(signals.probeLagEstimateMs)
	if type(estimate) == "number" and estimate >= 0 then
		return estimate
	end
	local ratio = tonumber(signals.probeLagRatio)
	if type(ratio) ~= "number" or ratio <= 0 then
		return nil
	end
	local targetMs = tonumber(signals.probeLagTargetMs) or tonumber(fallbackTargetMs) or 0
	if targetMs <= 0 then
		return nil
	end
	return ratio * targetMs
end

local function secondsToMillis(value)
	local s = tonumber(value) or 0
	if s <= 0 then
		return 0
	end
	return math.floor(s * 1000)
end

local function isHealthy(status, cfg)
	if not status or not status.window then
		return false
	end
	if status.mode ~= "normal" then
		return false
	end
	local dropDelta = tonumber(status.window.dropDelta) or 0
	if dropDelta > 0 then
		return false
	end
	local fill = tonumber(status.window.avgFill) or 0
	return fill <= (cfg.recoverMaxFill or 1)
end

--- Update probe quality state using runtime signals and merged interest.
--- @param prevState WOInterestState|nil
--- @param merged WOInterestMerged
--- @param runtimeStatus table|nil
--- @param opts table|nil
--- @return WOInterestState state
--- @return table effective
--- @return string reason
--- @return table meta
if Policy.update == nil then
	function Policy.update(prevState, merged, runtimeStatus, opts)
		local cfg = cloneTable(defaultConfig)
		for k, v in pairs(opts or {}) do
			if k ~= "label" and k ~= "signals" then
				cfg[k] = v
			end
		end
		local signals = opts and opts.signals or nil

		local bands = normalizeBands(merged or {}, cfg)
		local ladder = buildLadder(bands, cfg)

		local state = {
			qualityIndex = 1,
			overloadStreak = 0,
			lagStreak = 0,
			normalStreak = 0,
		}
		if type(prevState) == "table" then
			for k, v in pairs(prevState) do
				state[k] = v
			end
		end

		state.ladder = ladder
		state.qualityIndex = clampQualityIndex(state.qualityIndex, ladder)

		local runtimeOverloaded = isRuntimeOverloaded(runtimeStatus, cfg)
		local lagging = isProbeLagging(signals, cfg)
		local deferLagDegrade = lagging and runtimeHasHeadroomForProbeCatchup(runtimeStatus, cfg)

		-- Demand ratio is an estimate of "how far we are from meeting desired staleness", based on probe-lag signals.
		-- It's intentionally independent from the current effective quality rung: even if we are already degraded,
		-- this ratio tells budget controllers how much work remains to satisfy the original desired request.
		local desiredMs = secondsToMillis(bands.staleness.desired)
		local rawEstimateMs = estimateProbeSweepMs(signals, nil)
		local demandRatio = 0
		if rawEstimateMs and desiredMs > 0 then
			demandRatio = rawEstimateMs / math.max(desiredMs, 1)
		end

		-- Hysteresis for recovery when probes are involved: only recover once we can comfortably meet the
		-- *desired* staleness again (not merely the current degraded staleness), otherwise we oscillate.
		local meetsDesired = true
		if type(signals) == "table" and state.qualityIndex > 1 then
			local effective = ladder[state.qualityIndex] or ladder[#ladder]
			local effectiveMs = secondsToMillis(effective and effective.staleness)
			local estimateMs = rawEstimateMs or estimateProbeSweepMs(signals, effectiveMs)
			if estimateMs and desiredMs > 0 then
				local ratio = estimateMs / math.max(desiredMs, 1)
				meetsDesired = ratio <= (cfg.lagRatioRecoverThreshold or cfg.lagRatioThreshold or 1.0)
			end
		end
		local healthy = isHealthy(runtimeStatus, cfg) and not lagging and meetsDesired
		local changed = false
		local reason = "steady"

		if runtimeOverloaded then
			state.overloadStreak = (state.overloadStreak or 0) + 1
			state.lagStreak = 0
			state.normalStreak = 0
			if state.overloadStreak >= (cfg.degradeHoldWindows or 1) then
				local nextIndex = clampQualityIndex(state.qualityIndex + 1, ladder)
				if nextIndex > state.qualityIndex then
					state.qualityIndex = nextIndex
					changed = true
					reason = "degraded"
				end
			end
		elseif lagging and not deferLagDegrade then
			state.lagStreak = (state.lagStreak or 0) + 1
			state.overloadStreak = 0
			state.normalStreak = 0
			if state.lagStreak >= (cfg.lagHoldTicks or 1) then
				local nextIndex = clampQualityIndex(state.qualityIndex + 1, ladder)
				if nextIndex > state.qualityIndex then
					state.qualityIndex = nextIndex
					changed = true
					reason = "lagged"
					state.lagStreak = 0
				end
			end
		elseif lagging then
			-- Lag detected, but we're still under budget: allow probes to ramp their CPU budget first.
			-- We intentionally do not accumulate lagStreak here so the ladder doesn't degrade "too early".
			state.overloadStreak = 0
			state.lagStreak = 0
			state.normalStreak = 0
		else
			state.overloadStreak = 0
			state.lagStreak = 0
			if healthy then
				state.normalStreak = (state.normalStreak or 0) + 1
				local recoverHold = cfg.recoverHoldWindows or 1
				if state.lastChangeReason == "lagged" then
					recoverHold = cfg.recoverHoldTicksAfterLag or recoverHold
				end
				if state.normalStreak >= recoverHold then
					local nextIndex = clampQualityIndex(state.qualityIndex - 1, ladder)
					if nextIndex < state.qualityIndex then
						state.qualityIndex = nextIndex
						changed = true
						reason = "recovered"
						state.normalStreak = 0
					end
				end
			else
				state.normalStreak = 0
			end
		end

			local effective = ladder[state.qualityIndex] or ladder[#ladder]
			-- Info log only on change: surfaces when we deliberately degrade or recover probe quality.
			if changed then
				state.lastChangeReason = reason
				local label = opts and opts.label
			-- Note: Project Zomboid rewrites ':' in log messages to 'DOUBLECOLON', so avoid it in log prefixes.
			local prefix = label and ("[interest " .. tostring(label) .. "]") or "[interest]"
			Log:info(
				"%s quality=%s staleness=%s radius=%s cooldown=%s reason=%s",
				prefix,
				tostring(state.qualityIndex),
				tostring(effective.staleness),
				tostring(effective.radius),
				tostring(effective.cooldown),
				reason
			)
		end

		return state, effective, reason, {
			desiredStaleness = bands.staleness.desired,
			desiredStalenessMs = desiredMs,
			probeLagEstimateMs = rawEstimateMs,
			demandRatio = demandRatio,
			lagging = lagging,
			deferLagDegrade = deferLagDegrade,
		}
	end
end

Policy._internal.normalizeBand = normalizeBand
Policy._internal.normalizeBands = normalizeBands
Policy._internal.buildLadder = buildLadder

return Policy
