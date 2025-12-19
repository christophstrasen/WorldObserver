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

-- Patch seam: only assign defaults when nil, so mods can override by reassigning `Config.<name>` and so
-- module reloads (tests/console via `package.loaded`) don't clobber an existing patch.
if Config.detectHeadlessFlag == nil then
	Config.detectHeadlessFlag = defaultDetectHeadlessFlag
end

local function defaultBuildDefaults()
	local headless = Config.detectHeadlessFlag()
	return {
		facts = {
			squares = {
				headless = headless,
				listener = {
					enabled = true,
				},
				ingest = {
					enabled = true,
					mode = "latestByKey",
					capacity = 5000,
					ordering = "fifo",
					priority = 1,
				},
				probe = {
					enabled = true,
					maxPerRun = 50, -- hard cap per OnTick slice (bounds worst-case work if clocks are unavailable)
					maxPerRunHardCap = 200, -- hard cap for auto-budget scaling (still bounded by maxMillisPerTick)
					maxMillisPerTick = 0.75, -- CPU-ms budget per tick for probe scanning (kept small to avoid hitching)
					infoLogEveryMs = 10000, -- emit probe settings summary at most this often (0 disables)
					-- Auto budget: when probes lag but the overall WO tick has headroom (tickBudgetMs),
					-- increase probe CPU budget for this tick to avoid degrading interest unnecessarily.
					autoBudget = true,
					autoBudgetReserveMs = 0.5, -- keep some budget for draining + other tick work
					autoBudgetHeadroomFactor = 1.0, -- spend this fraction of observed headroom on probes
					autoBudgetMaxMillisPerTick = nil, -- optional cap; defaults to (tickBudgetMs - reserve)
					autoBudgetMinMillisPerTick = nil, -- optional floor; defaults to maxMillisPerTick
				},
			},
			zombies = {
				headless = headless,
				ingest = {
					enabled = true,
					mode = "latestByKey",
					capacity = 5000,
					ordering = "fifo",
					priority = 1,
				},
				probe = {
					enabled = true,
					maxPerRun = 50,
					maxPerRunHardCap = 200,
					maxMillisPerTick = 0.75,
					infoLogEveryMs = 0,
					autoBudget = false,
					autoBudgetReserveMs = 0.5,
					autoBudgetHeadroomFactor = 1.0,
					autoBudgetMaxMillisPerTick = nil,
					autoBudgetMinMillisPerTick = nil,
					logEachSweep = false,
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

local function readNested(tbl, path)
	if type(tbl) ~= "table" then
		return nil
	end
	local current = tbl
	for i = 1, #path do
		if type(current) ~= "table" then
			return nil
		end
		current = current[path[i]]
		if current == nil then
			return nil
		end
	end
	return current
end

local function ensureNestedTable(tbl, path)
	if type(tbl) ~= "table" then
		return nil
	end
	local current = tbl
	for i = 1, #path do
		local key = path[i]
		local nextNode = current[key]
		if type(nextNode) ~= "table" then
			nextNode = {}
			current[key] = nextNode
		end
		current = nextNode
	end
	return current
end

local function setNestedValue(tbl, path, value)
	if type(tbl) ~= "table" then
		return
	end
	if type(path) ~= "table" or #path == 0 then
		return
	end
	local parentPath = {}
	for i = 1, #path - 1 do
		parentPath[i] = path[i]
	end
	local parent = ensureNestedTable(tbl, parentPath)
	if not parent then
		return
	end
	parent[path[#path]] = value
end

local function shallowMergeInto(target, patch)
	if type(target) ~= "table" or type(patch) ~= "table" then
		return
	end
	for k, v in pairs(patch) do
		target[k] = v
	end
end

local OVERRIDE_BOOL_PATHS = {
	{ "facts", "squares", "headless" },
	{ "facts", "zombies", "headless" },
}

local OVERRIDE_TABLE_PATHS = {
	{ "facts", "squares", "listener" },
	{ "facts", "squares", "ingest" },
	{ "facts", "squares", "probe" },
	{ "facts", "zombies", "ingest" },
	{ "facts", "zombies", "probe" },
	{ "ingest", "scheduler" },
	{ "runtime", "controller" },
}

local function defaultApplyOverrides(target, overrides)
	if type(target) ~= "table" or type(overrides) ~= "table" then
		return
	end

	for _, path in ipairs(OVERRIDE_BOOL_PATHS) do
		local value = readNested(overrides, path)
		if type(value) == "boolean" then
			setNestedValue(target, path, value)
		end
	end

	for _, path in ipairs(OVERRIDE_TABLE_PATHS) do
		local patch = readNested(overrides, path)
		if type(patch) == "table" then
			local dest = ensureNestedTable(target, path)
			shallowMergeInto(dest, patch)
		end
	end
end

local function defaultValidate(cfg)
end

Config._internal.buildDefaults = defaultBuildDefaults
Config._internal.clone = defaultClone
Config._internal.applyOverrides = defaultApplyOverrides
Config._internal.validate = defaultValidate
Config._internal.readNested = readNested
Config._internal.ensureNestedTable = ensureNestedTable
Config._internal.setNestedValue = setNestedValue
Config._internal.shallowMergeInto = shallowMergeInto

---Creates a copy of the default config.
---@return table
-- Patch seam: define only when nil so mods can override by reassigning `Config.defaults` and so reloads
-- (tests/console via `package.loaded`) don't clobber an existing patch.
if Config.defaults == nil then
	function Config.defaults()
		return Config._internal.clone(Config._internal.buildDefaults())
	end
end

---Merges user overrides into defaults and validates the result.
---@param overrides table|nil
---@return table
-- Patch seam: define only when nil so mods can override by reassigning `Config.load` and so reloads
-- (tests/console via `package.loaded`) don't clobber an existing patch.
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

local function defaultRuntimeOpts(cfg)
	cfg = cfg or {}
	local opts = {}
	local controller = cfg.runtime and cfg.runtime.controller or {}
	if type(controller) == "table" then
		for k, v in pairs(controller) do
			opts[k] = v
		end
	end
	local base = cfg.ingest and cfg.ingest.scheduler and cfg.ingest.scheduler.maxItemsPerTick
	if type(base) == "number" and base > 0 then
		opts.baseDrainMaxItems = base
	end
	return opts
end
Config._internal.runtimeOpts = defaultRuntimeOpts

---Builds runtime controller options from the loaded config.
---@param cfg table
---@return table
if Config.runtimeOpts == nil then
	function Config.runtimeOpts(cfg)
		return Config._internal.runtimeOpts(cfg)
	end
end

---Reads the global config override table when present.
---@return table|nil
if Config.getOverrides == nil then
	function Config.getOverrides()
		return _G.WORLDOBSERVER_CONFIG_OVERRIDES
	end
end

---Safely reads a nested value from a config or override table.
---@param tbl table|nil
---@param path string[]
---@return any
if Config.readNested == nil then
	function Config.readNested(tbl, path)
		return Config._internal.readNested(tbl, path)
	end
end

---Loads config defaults merged with global overrides.
---@return table
if Config.loadFromGlobals == nil then
	function Config.loadFromGlobals()
		return Config.load(Config.getOverrides())
	end
end

return Config
