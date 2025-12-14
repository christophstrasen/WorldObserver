-- config.lua -- owns WorldObserver defaults (currently fact strategies) and validates overrides.

local Config = {}

local function detectHeadlessFlag()
	if _G.WORLDOBSERVER_HEADLESS == true then
		return true
	end
	local env = os.getenv and os.getenv("WORLDOBSERVER_HEADLESS")
	if env and env ~= "" and env ~= "0" then
		return true
	end
	return false
end

local function defaults()
	return {
		facts = {
			squares = {
				strategy = "balanced",
				headless = detectHeadlessFlag(),
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
				windowTicks = 60, -- how many ticks per controller window (~1s at 60fps)
				reportEveryWindows = 10, -- how often to emit status events (in windows)
				degradedMaxItemsPerTick = 5, -- clamp for scheduler when degraded (item budget fallback)
			},
		},
	}
end

local function clone(tbl)
	if type(tbl) ~= "table" then
		return tbl
	end
	local out = {}
	for key, value in pairs(tbl) do
		if type(value) == "table" then
			out[key] = clone(value)
		else
			out[key] = value
		end
	end
	return out
end

local function applyOverrides(target, overrides)
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

local function validate(cfg)
	local strategy = cfg.facts.squares.strategy
	if strategy ~= "balanced" then
		error(("Unsupported squares strategy '%s' (only 'balanced' in MVP)"):format(tostring(strategy)))
	end
end

---Creates a copy of the default config.
---@return table
function Config.defaults()
	return clone(defaults())
end

---Merges user overrides into defaults and validates the result.
---@param overrides table|nil
---@return table
function Config.load(overrides)
	local cfg = Config.defaults()
	if type(overrides) == "table" then
		applyOverrides(cfg, overrides)
	end
	validate(cfg)
	return cfg
end

return Config
