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
	minRadius = 0,
	emergencySteps = 3,
	-- Degrade only when we observe meaningful drops.
	dropMinAbsolute = 1,
	dropRatioThreshold = 0.10, -- dropped vs ingest/drain rates (rough heuristic to avoid single stray drops)
	degradeHoldWindows = 1,
	recoverHoldWindows = 2,
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

local function buildLadder(bands, cfg)
	local ladder = {}
	local staleness = bands.staleness
	local radius = bands.radius
	local cooldown = bands.cooldown

	local function pushLevel(sta, rad, cool)
		ladder[#ladder + 1] = {
			staleness = sta,
			radius = rad,
			cooldown = cool,
		}
	end

	pushLevel(staleness.desired, radius.desired, cooldown.desired)

	if staleness.desired < staleness.tolerable then
		pushLevel(staleness.tolerable, radius.desired, cooldown.desired)
	end
	if radius.desired > radius.tolerable then
		pushLevel(staleness.tolerable, radius.tolerable, cooldown.desired)
	end
	if cooldown.desired < cooldown.tolerable then
		pushLevel(staleness.tolerable, radius.tolerable, cooldown.tolerable)
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

local function isOverloaded(status, cfg)
	if not status or not status.window then
		return false
	end
	if status.mode == "emergency" then
		return true
	end
	local dropDelta = tonumber(status.window.dropDelta) or 0
	if dropDelta < cfg.dropMinAbsolute then
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
	return dropRatio >= cfg.dropRatioThreshold
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
if Policy.update == nil then
	function Policy.update(prevState, merged, runtimeStatus, opts)
		local cfg = cloneTable(defaultConfig)
		for k, v in pairs(opts or {}) do
			cfg[k] = v
		end

		local bands = normalizeBands(merged or {}, cfg)
		local ladder = buildLadder(bands, cfg)

		local state = {
			qualityIndex = 1,
			overloadStreak = 0,
			normalStreak = 0,
		}
		if type(prevState) == "table" then
			for k, v in pairs(prevState) do
				state[k] = v
			end
		end

		state.ladder = ladder
		state.qualityIndex = clampQualityIndex(state.qualityIndex, ladder)

		local overloaded = isOverloaded(runtimeStatus, cfg)
		local healthy = isHealthy(runtimeStatus, cfg)
		local changed = false
		local reason = "steady"

		if overloaded then
			state.overloadStreak = (state.overloadStreak or 0) + 1
			state.normalStreak = 0
			if state.overloadStreak >= (cfg.degradeHoldWindows or 1) then
				local nextIndex = clampQualityIndex(state.qualityIndex + 1, ladder)
				if nextIndex > state.qualityIndex then
					state.qualityIndex = nextIndex
					changed = true
					reason = "degraded"
				end
			end
		else
			state.overloadStreak = 0
			if healthy then
				state.normalStreak = (state.normalStreak or 0) + 1
				if state.normalStreak >= (cfg.recoverHoldWindows or 1) then
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
			local label = opts and opts.label
			local prefix = label and ("[interest:" .. tostring(label) .. "]") or "[interest]"
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

		return state, effective, reason
	end
end

Policy._internal.normalizeBand = normalizeBand
Policy._internal.normalizeBands = normalizeBands
Policy._internal.buildLadder = buildLadder

return Policy
