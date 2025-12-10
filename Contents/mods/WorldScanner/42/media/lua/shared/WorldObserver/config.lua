-- config.lua -- owns WorldObserver defaults (currently fact strategies) and validates overrides.

local Config = {}

local DEFAULTS = {
	facts = {
		squares = {
			strategy = "balanced",
		},
	},
}

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

local function applyFactsConfig(target, source)
	if type(source) ~= "table" then
		return
	end
	local squares = source.squares
	if type(squares) == "table" and type(squares.strategy) == "string" and squares.strategy ~= "" then
		target.facts.squares.strategy = squares.strategy
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
	return clone(DEFAULTS)
end

---Merges user overrides into defaults and validates the result.
---@param overrides table|nil
---@return table
function Config.load(overrides)
	local cfg = Config.defaults()
	if type(overrides) == "table" then
		applyFactsConfig(cfg, overrides.facts)
	end
	validate(cfg)
	return cfg
end

return Config
