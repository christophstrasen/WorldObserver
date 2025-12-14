-- config.lua -- owns WorldObserver defaults (currently fact strategies) and validates overrides.

local moduleName = ...
local Config = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Config = loaded
	else
		package.loaded[moduleName] = Config
	end
end
Config._internal = Config._internal or {}

local function defaultDetectHeadlessFlag()
	if _G.WORLDOBSERVER_HEADLESS == true then
		return true
	end
	local env = os.getenv and os.getenv("WORLDOBSERVER_HEADLESS")
	if env and env ~= "" and env ~= "0" then
		return true
	end
	return false
end

if Config.detectHeadlessFlag == nil then
	Config.detectHeadlessFlag = defaultDetectHeadlessFlag
end

local function defaultBuildDefaults()
	return {
		facts = {
			squares = {
				strategy = "balanced",
				headless = Config.detectHeadlessFlag(),
				ingest = {
					enabled = true,
					mode = "latestByKey",
					capacity = 5000,
					ordering = "fifo",
					priority = 1,
				},
				probe = {
					enabled = true,
					maxPerRun = 50, -- per EveryOneMinute
				},
			},
		},
		ingest = {
			scheduler = {
				maxItemsPerTick = 10,
				quantum = 1,
				maxMillisPerTick = nil, -- optional ms budget (requires wall-clock); when nil, only item budget is used
			},
		},
			runtime = {
					controller = {
						-- Target tick budgets (ms, CPU-time-ish) for WorldObserver work.
						tickBudgetMs = 4, -- soft budget for WO drain+probes per tick
						tickSpikeBudgetMs = 8, -- spike detector threshold
						spikeMinCount = 2, -- require at least N consecutive spikes in a window to enter degraded on spikes
						windowTicks = 60, -- how many ticks per controller window (~1s at 60fps)
						reportEveryWindows = 10, -- how often to emit status events (in windows)
					-- Legacy clamp (kept for compatibility; newer drainAuto can override above/below this).
					degradedMaxItemsPerTick = 5,
					-- Drain auto-tuning: choose an effective maxItemsPerTick dynamically to burn backlog when
					-- we have headroom, and back off when WO work approaches/exceeds its ms budget.
					drainAuto = {
						enabled = true,
						stepFactor = 1.5, -- multiply/divide by this per window step
						minItems = 1, -- floor for effective drain budget
						maxItems = 200, -- ceiling for effective drain budget
						headroomUtil = 0.6, -- if avgTickMs/budgetMs <= this, we can step up when under pressure
					},
					-- Backlog heuristics: avoid degrading on tiny fluctuations; require a "material" backlog.
					backlogMinPending = 100, -- avg pending items per window
					backlogFillThreshold = 0.25, -- avg pending/capacity per window
					backlogMinIngestRate15 = 5, -- items/sec guard for rate-based trigger
					backlogRateRatio = 1.1, -- ingestRate15 must exceed throughput15 by this factor
					diagnostics = {
						enabled = true, -- when Log level is info, print periodic runtime+ingest diagnostics via WO.DIAG
					},
			},
		},
	}
end

local function defaultClone(tbl)
	if type(tbl) ~= "table" then
		return tbl
	end
	local out = {}
	for key, value in pairs(tbl) do
		if type(value) == "table" then
			out[key] = defaultClone(value)
		else
			out[key] = value
		end
	end
	return out
end

local function defaultApplyOverrides(target, overrides)
	if type(overrides) ~= "table" then
		return
	end
	local facts = overrides.facts
	local squares = type(facts) == "table" and facts.squares or nil
	if type(squares) == "table" and type(squares.strategy) == "string" and squares.strategy ~= "" then
		target.facts.squares.strategy = squares.strategy
	end
	if type(squares) == "table" and type(squares.headless) == "boolean" then
		target.facts.squares.headless = squares.headless
	end
	if type(squares) == "table" and type(squares.ingest) == "table" then
		for k, v in pairs(squares.ingest) do
			target.facts.squares.ingest[k] = v
		end
	end
	if type(squares) == "table" and type(squares.probe) == "table" then
		for k, v in pairs(squares.probe) do
			target.facts.squares.probe[k] = v
		end
	end
	if type(overrides.ingest) == "table" and type(overrides.ingest.scheduler) == "table" then
		for k, v in pairs(overrides.ingest.scheduler) do
			target.ingest.scheduler[k] = v
		end
	end
	if type(overrides.runtime) == "table" and type(overrides.runtime.controller) == "table" then
		for k, v in pairs(overrides.runtime.controller) do
			target.runtime.controller[k] = v
		end
	end
end

local function defaultValidate(cfg)
	local strategy = cfg.facts.squares.strategy
	if strategy ~= "balanced" then
		error(("Unsupported squares strategy '%s' (only 'balanced' in MVP)"):format(tostring(strategy)))
	end
end

Config._internal.buildDefaults = defaultBuildDefaults
Config._internal.clone = defaultClone
Config._internal.applyOverrides = defaultApplyOverrides
Config._internal.validate = defaultValidate

---Creates a copy of the default config.
---@return table
if Config.defaults == nil then
	function Config.defaults()
		return Config._internal.clone(Config._internal.buildDefaults())
	end
end

---Merges user overrides into defaults and validates the result.
---@param overrides table|nil
---@return table
if Config.load == nil then
	function Config.load(overrides)
		local cfg = Config.defaults()
		if type(overrides) == "table" then
			Config._internal.applyOverrides(cfg, overrides)
		end
		Config._internal.validate(cfg)
		return cfg
	end
end

return Config
