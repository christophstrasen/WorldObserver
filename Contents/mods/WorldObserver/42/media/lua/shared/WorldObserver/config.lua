-- config.lua -- owns WorldObserver defaults (currently fact strategies) and validates overrides.

local moduleName = ...
local Config = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Config = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Config
	end
end
Config._internal = Config._internal or {}

local function resolveWarnFn()
	local okLog, Log = pcall(require, "LQR/util/log")
	if okLog and type(Log) == "table" and type(Log.withTag) == "function" then
		local tagged = Log.withTag("WO.CONFIG")
		if tagged and type(tagged.warn) == "function" then
			return function(fmt, ...)
				tagged:warn(fmt, ...)
			end
		end
	end
	return function(fmt, ...)
		if type(_G) == "table" and type(_G.print) == "function" then
			_G.print(string.format("[WO.CONFIG] " .. fmt, ...))
		end
	end
end

local warnf = resolveWarnFn()

local function pathToString(path)
	if type(path) ~= "table" then
		return tostring(path)
	end
	return table.concat(path, ".")
end

local function pathEquals(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

local function pathStartsWith(path, prefix)
	if #path < #prefix then
		return false
	end
	for i = 1, #prefix do
		if path[i] ~= prefix[i] then
			return false
		end
	end
	return true
end

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
			rooms = {
				headless = headless,
				listener = {
					enabled = true,
				},
				ingest = {
					enabled = true,
					mode = "latestByKey",
					capacity = 2500,
					ordering = "fifo",
					priority = 1,
				},
				record = {
					includeIsoRoom = false,
					includeRoomDef = false,
					includeBuilding = false,
				},
				probe = {
					enabled = true,
					maxPerRun = 40,
					maxMillisPerTick = 0.5,
				},
			},
			items = {
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
				record = {
					includeInventoryItem = false,
					includeWorldItem = false,
					includeContainerItems = true,
					maxContainerItemsPerSquare = 200,
				},
				probe = {
					enabled = true,
					maxPerRun = 50,
					maxPerRunHardCap = 200,
					maxMillisPerTick = 0.75,
					infoLogEveryMs = 10000,
					autoBudget = true,
					autoBudgetReserveMs = 0.5,
					autoBudgetHeadroomFactor = 1.0,
					autoBudgetMaxMillisPerTick = nil,
					autoBudgetMinMillisPerTick = nil,
				},
			},
			deadBodies = {
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
				record = {
					includeIsoDeadBody = false,
				},
				probe = {
					enabled = true,
					maxPerRun = 50,
					maxPerRunHardCap = 200,
					maxMillisPerTick = 0.75,
					infoLogEveryMs = 10000,
					autoBudget = true,
					autoBudgetReserveMs = 0.5,
					autoBudgetHeadroomFactor = 1.0,
					autoBudgetMaxMillisPerTick = nil,
					autoBudgetMinMillisPerTick = nil,
				},
			},
			sprites = {
				headless = headless,
				listener = {
					enabled = true,
					priority = 5,
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
					maxPerRun = 50,
					maxPerRunHardCap = 200,
					maxMillisPerTick = 0.75,
					infoLogEveryMs = 10000,
					autoBudget = true,
					autoBudgetReserveMs = 0.5,
					autoBudgetHeadroomFactor = 1.0,
					autoBudgetMaxMillisPerTick = nil,
					autoBudgetMinMillisPerTick = nil,
				},
			},
			vehicles = {
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
	{ "facts", "rooms", "headless" },
	{ "facts", "vehicles", "headless" },
}

local OVERRIDE_TABLE_PATHS = {
	{ "facts", "squares", "listener" },
	{ "facts", "squares", "ingest" },
	{ "facts", "squares", "probe" },
	{ "facts", "zombies", "ingest" },
	{ "facts", "zombies", "probe" },
	{ "facts", "rooms", "listener" },
	{ "facts", "rooms", "ingest" },
	{ "facts", "rooms", "probe" },
	{ "facts", "rooms", "record" },
	{ "facts", "vehicles", "listener" },
	{ "facts", "vehicles", "ingest" },
	{ "facts", "vehicles", "probe" },
	{ "ingest", "scheduler" },
	{ "runtime", "controller" },
}

local function validateOverrides(overrides)
	if type(overrides) ~= "table" then
		return
	end
	local suppressWarnings = Config.detectHeadlessFlag and Config.detectHeadlessFlag() == true

	local function warnOverride(fmt, ...)
		if suppressWarnings then
			return
		end
		warnf(fmt, ...)
	end

	local function isAllowedBoolPath(path)
		for _, allowed in ipairs(OVERRIDE_BOOL_PATHS) do
			if pathEquals(path, allowed) then
				return true
			end
		end
		return false
	end

	local function isAllowedTablePath(path)
		for _, allowed in ipairs(OVERRIDE_TABLE_PATHS) do
			if pathEquals(path, allowed) then
				return true
			end
		end
		return false
	end

	local function isPrefixOfAllowed(path)
		for _, allowed in ipairs(OVERRIDE_BOOL_PATHS) do
			if pathStartsWith(allowed, path) then
				return true
			end
		end
		for _, allowed in ipairs(OVERRIDE_TABLE_PATHS) do
			if pathStartsWith(allowed, path) then
				return true
			end
		end
		return false
	end

	local function isWithinAllowedTablePath(path)
		for _, allowed in ipairs(OVERRIDE_TABLE_PATHS) do
			if pathStartsWith(path, allowed) then
				return true
			end
		end
		return false
	end

	local function walk(node, path)
		if type(node) ~= "table" then
			return
		end
		for key, value in pairs(node) do
			if type(key) == "string" then
				path[#path + 1] = key
				if isAllowedBoolPath(path) then
					if value ~= nil and type(value) ~= "boolean" then
						warnOverride("Config override %s ignored (expected boolean, got %s)", pathToString(path), type(value))
					end
				elseif isAllowedTablePath(path) then
					if value ~= nil and type(value) ~= "table" then
						warnOverride("Config override %s ignored (expected table, got %s)", pathToString(path), type(value))
					end
				elseif isWithinAllowedTablePath(path) then
					-- Descendants of table patches are allowed (shallow merge); do not warn here.
				elseif isPrefixOfAllowed(path) then
					if type(value) == "table" then
						walk(value, path)
					elseif value ~= nil then
						warnOverride("Config override %s ignored (expected table)", pathToString(path))
					end
				else
					warnOverride("Config override %s ignored (unknown key)", pathToString(path))
				end
				path[#path] = nil
			end
		end
	end

	walk(overrides, {})
end

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
	if type(cfg) ~= "table" then
		error("Config.validate expects a table")
	end

	local defaults = Config._internal and Config._internal.buildDefaults and Config._internal.buildDefaults() or {}
	local headless = Config.detectHeadlessFlag and Config.detectHeadlessFlag() == true

	local function report(message)
		if headless then
			error(message)
		end
		warnf("%s", message)
	end

	local function resetToDefault(path, message)
		local defaultValue = readNested(defaults, path)
		report(("%s: %s (using default=%s)"):format(pathToString(path), message, tostring(defaultValue)))
		setNestedValue(cfg, path, defaultValue)
	end

	local function ensureNumber(path, opts)
		local value = readNested(cfg, path)
		local asNumber = tonumber(value)
		if type(asNumber) ~= "number" then
			resetToDefault(path, ("expected number, got %s"):format(type(value)))
			return
		end
		if opts and opts.integer then
			asNumber = math.floor(asNumber)
		end
		if opts and type(opts.min) == "number" and asNumber < opts.min then
			report(("%s: expected >= %s, got %s (clamping)"):format(pathToString(path), tostring(opts.min), tostring(asNumber)))
			asNumber = opts.min
		end
		if opts and type(opts.max) == "number" and asNumber > opts.max then
			report(("%s: expected <= %s, got %s (clamping)"):format(pathToString(path), tostring(opts.max), tostring(asNumber)))
			asNumber = opts.max
		end
		setNestedValue(cfg, path, asNumber)
	end

	local function ensureOptionalNumber(path, opts)
		if readNested(cfg, path) == nil then
			return
		end
		ensureNumber(path, opts)
	end

	local function ensureOptionalBool(path)
		local value = readNested(cfg, path)
		if value == nil then
			return
		end
		if type(value) ~= "boolean" then
			report(("%s: expected boolean, got %s (clearing)"):format(pathToString(path), type(value)))
			setNestedValue(cfg, path, nil)
		end
	end

	-- runtime.controller values are used in arithmetic/comparisons; invalid types can crash at runtime.
	ensureNumber({ "runtime", "controller", "tickBudgetMs" }, { min = 0 })
	ensureNumber({ "runtime", "controller", "tickSpikeBudgetMs" }, { min = 0 })
	ensureNumber({ "runtime", "controller", "spikeMinCount" }, { min = 1, integer = true })
	ensureNumber({ "runtime", "controller", "windowTicks" }, { min = 1, integer = true })
	ensureNumber({ "runtime", "controller", "reportEveryWindows" }, { min = 0, integer = true })
	ensureNumber({ "runtime", "controller", "degradedMaxItemsPerTick" }, { min = 0, integer = true })
	ensureNumber({ "runtime", "controller", "backlogMinPending" }, { min = 0 })
	ensureNumber({ "runtime", "controller", "backlogFillThreshold" }, { min = 0 })
	ensureNumber({ "runtime", "controller", "backlogMinIngestRate15" }, { min = 0 })
	ensureNumber({ "runtime", "controller", "backlogRateRatio" }, { min = 0 })

	local drainAuto = readNested(cfg, { "runtime", "controller", "drainAuto" })
	if drainAuto ~= nil and type(drainAuto) ~= "table" then
		report(("runtime.controller.drainAuto: expected table, got %s (clearing)"):format(type(drainAuto)))
		setNestedValue(cfg, { "runtime", "controller", "drainAuto" }, nil)
	end
	ensureOptionalBool({ "runtime", "controller", "drainAuto", "enabled" })
	ensureOptionalNumber({ "runtime", "controller", "drainAuto", "stepFactor" }, { min = 1e-9 })
	ensureOptionalNumber({ "runtime", "controller", "drainAuto", "minItems" }, { min = 0, integer = true })
	ensureOptionalNumber({ "runtime", "controller", "drainAuto", "maxItems" }, { min = 0, integer = true })
	ensureOptionalNumber({ "runtime", "controller", "drainAuto", "headroomUtil" }, { min = 0, max = 1 })

	local diagnostics = readNested(cfg, { "runtime", "controller", "diagnostics" })
	if diagnostics ~= nil and type(diagnostics) ~= "table" then
		report(("runtime.controller.diagnostics: expected table, got %s (clearing)"):format(type(diagnostics)))
		setNestedValue(cfg, { "runtime", "controller", "diagnostics" }, nil)
	end
	ensureOptionalBool({ "runtime", "controller", "diagnostics", "enabled" })

	-- ingest.scheduler is validated downstream too, but normalize types early so cfg doesn't carry invalid truthy values.
	ensureNumber({ "ingest", "scheduler", "maxItemsPerTick" }, { min = 0, integer = true })
	ensureNumber({ "ingest", "scheduler", "quantum" }, { min = 1, integer = true })
	local maxMillisPath = { "ingest", "scheduler", "maxMillisPerTick" }
	local maxMillisValue = readNested(cfg, maxMillisPath)
	if maxMillisValue ~= nil then
		local asNumber = tonumber(maxMillisValue)
		if type(asNumber) ~= "number" then
			resetToDefault(maxMillisPath, ("expected number, got %s"):format(type(maxMillisValue)))
		elseif asNumber <= 0 then
			-- Treat <=0 as "disabled" and normalize to nil so downstream code doesn't treat it as a budget.
			setNestedValue(cfg, maxMillisPath, nil)
		else
			setNestedValue(cfg, maxMillisPath, asNumber)
		end
	end
end

Config._internal.buildDefaults = defaultBuildDefaults
Config._internal.clone = defaultClone
Config._internal.applyOverrides = defaultApplyOverrides
Config._internal.validateOverrides = validateOverrides
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

-- Patch seam: define only when nil so mods can override by reassigning `Config.load` and so reloads
-- (tests/console via `package.loaded`) don't clobber an existing patch.
if Config.load == nil then
	---Merges user overrides into defaults and validates the result.
	---@param overrides table|nil
	---@return table
	function Config.load(overrides)
		local cfg = Config.defaults()
		if type(overrides) == "table" then
			Config._internal.validateOverrides(overrides)
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

if Config.runtimeOpts == nil then
	---Builds runtime controller options from the loaded config.
	---@param cfg table
	---@return table
	function Config.runtimeOpts(cfg)
		return Config._internal.runtimeOpts(cfg)
	end
end

if Config.getOverrides == nil then
	---Reads the global config override table when present.
	---@return table|nil
	function Config.getOverrides()
		return _G.WORLDOBSERVER_CONFIG_OVERRIDES
	end
end

if Config.readNested == nil then
	---Safely reads a nested value from a config or override table.
	---@param tbl table|nil
	---@param path string[]
	---@return any
	function Config.readNested(tbl, path)
		return Config._internal.readNested(tbl, path)
	end
end

if Config.loadFromGlobals == nil then
	---Loads config defaults merged with global overrides.
	---@return table
	function Config.loadFromGlobals()
		return Config.load(Config.getOverrides())
	end
end

return Config
