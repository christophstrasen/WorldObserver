-- interest/registry.lua -- stores mod interest declarations (leases) and merges them into effective bands per fact type.
local Time = require("WorldObserver/helpers/time")

local moduleName = ...
local Registry = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Registry = loaded
	else
		package.loaded[moduleName] = Registry
	end
end
Registry._internal = Registry._internal or {}

local function nowMillis()
	local ms = Time.gameMillis()
	if ms then
		return ms
	end
	return math.floor(os.time() * 1000)
end

--- @class WOInterestLease
--- @field modId string
--- @field key string
--- @field spec table
--- @field expiresAtMs number

-- Default TTL must be comfortably above how often mods typically refresh their declarations,
-- otherwise leases can expire during normal play even when a mod still cares about them.
local DEFAULT_TTL_MS = 10 * 60 * 1000

local DEFAULTS = {
	["squares.nearPlayer"] = {
		staleness = { desired = 10, tolerable = 20 },
		radius = { desired = 8, tolerable = 5 },
		cooldown = { desired = 30, tolerable = 60 },
		highlight = nil,
	},
	["squares.vision"] = {
		staleness = { desired = 10, tolerable = 20 },
		radius = { desired = 8, tolerable = 5 },
		cooldown = { desired = 30, tolerable = 60 },
		highlight = nil,
	},
	["zombies.nearPlayer"] = {
		staleness = { desired = 5, tolerable = 10 },
		radius = { desired = 20, tolerable = 30 },
		zRange = { desired = 1, tolerable = 0 },
		cooldown = { desired = 2, tolerable = 4 },
		highlight = nil,
	},
}

local function cloneTable(tbl)
	local out = {}
	for k, v in pairs(tbl or {}) do
		if type(v) == "table" then
			out[k] = cloneTable(v)
		else
			out[k] = v
		end
	end
	return out
end

local function defaultTolerable(desired, defaults)
	if type(desired) ~= "number" then
		return nil
	end
	-- When the caller provides only a desired value, derive its tolerable bound
	-- by scaling with the project defaults (keeps directionality consistent).
	-- Example: defaults radius 8→5 implies a 0.625 factor for other radius desires.
	if type(defaults) == "table" then
		local baseDesired = tonumber(defaults.desired)
		local baseTolerable = tonumber(defaults.tolerable)
		if type(baseDesired) == "number" and baseDesired > 0 and type(baseTolerable) == "number" then
			return desired * (baseTolerable / baseDesired)
		end
	end
	return desired
end

local function normalizeBand(value, defaults)
	local desired, tolerable
	if type(value) == "table" then
		desired = tonumber(value.desired) or tonumber(value[1])
		tolerable = tonumber(value.tolerable) or tonumber(value[2])
	elseif type(value) == "number" then
		desired = value
	end

	if desired ~= nil and tolerable == nil then
		tolerable = defaultTolerable(desired, defaults)
	end

	if desired ~= nil and tolerable ~= nil then
		return { desired = desired, tolerable = tolerable }
	end

	if defaults then
		return cloneTable(defaults)
	end
	return { desired = 0, tolerable = 0 }
end

local function normalizeSpec(spec, defaults)
	spec = spec or {}
	local interestType = spec.type
	if type(interestType) ~= "string" or interestType == "" then
		-- Default to the common “near player squares” interest so mods can declare without boilerplate.
		interestType = "squares.nearPlayer"
	end
	local typeDefaults = defaults[interestType] or {}
	return {
		type = interestType,
		staleness = normalizeBand(spec.staleness, typeDefaults.staleness),
		radius = normalizeBand(spec.radius, typeDefaults.radius),
		zRange = normalizeBand(spec.zRange, typeDefaults.zRange),
		cooldown = normalizeBand(spec.cooldown, typeDefaults.cooldown),
		highlight = spec.highlight ~= nil and spec.highlight or typeDefaults.highlight,
	}
end

local function bandUnion(bands, knob, incoming)
	local current = bands[knob]
	if not current then
		bands[knob] = cloneTable(incoming)
		return
	end
	-- desired: pick the "best" quality that satisfies all:
	-- staleness/cooldown (smaller is stricter) -> min; radius (larger is better) -> max.
	-- tolerable: same direction so the merged band stays inside everyone's bounds.
	if knob == "radius" or knob == "zRange" then
		current.desired = math.max(current.desired, incoming.desired)
		current.tolerable = math.max(current.tolerable, incoming.tolerable)
	else
		current.desired = math.min(current.desired, incoming.desired)
		current.tolerable = math.min(current.tolerable, incoming.tolerable)
	end
end

local function mergeSpecs(specs, defaults)
	local mergedByType = {}
	for _, spec in ipairs(specs) do
		local normalized = normalizeSpec(spec, defaults)
		local target = mergedByType[normalized.type]
		if not target then
			target = {
				type = normalized.type,
				staleness = cloneTable(normalized.staleness),
				radius = cloneTable(normalized.radius),
				zRange = cloneTable(normalized.zRange),
				cooldown = cloneTable(normalized.cooldown),
				highlight = normalized.highlight,
			}
			mergedByType[normalized.type] = target
		else
			bandUnion(target, "staleness", normalized.staleness)
			bandUnion(target, "radius", normalized.radius)
			bandUnion(target, "zRange", normalized.zRange)
			bandUnion(target, "cooldown", normalized.cooldown)
			if target.highlight == nil and normalized.highlight ~= nil then
				target.highlight = normalized.highlight
			end
		end
	end
	return mergedByType
end

--- @class WOInterestRegistry
--- @field _ttlMs number
--- @field _defaults table
--- @field _leases table

--- Create a registry.
--- @param opts table|nil
--- @return WOInterestRegistry
function Registry.new(opts)
	opts = opts or {}
	local ttlMs = opts.ttlMs
	if ttlMs == nil then
		local ttlSeconds = opts.ttlSeconds
		ttlMs = (type(ttlSeconds) == "number" and ttlSeconds * 1000) or DEFAULT_TTL_MS
	end
	ttlMs = tonumber(ttlMs) or DEFAULT_TTL_MS
	assert(ttlMs > 0, "interest registry ttl must be > 0")

	local self = {
		_ttlMs = ttlMs,
		_defaults = cloneTable(opts.defaults or DEFAULTS),
		_leases = {},
	}
	setmetatable(self, { __index = Registry })
	return self
end

local function addLease(self, modId, key, spec, nowMs)
	local lease = {
		modId = modId,
		key = key,
		spec = spec,
		expiresAtMs = (nowMs or nowMillis()) + self._ttlMs,
	}
	self._leases[modId] = self._leases[modId] or {}
	self._leases[modId][key] = lease
	return lease
end

--- Declare interest for (modId, key) with the given spec (replace semantics).
--- @param modId string
--- @param key string
--- @param spec table
--- @param opts table|nil
--- @return table leaseHandle
function Registry:declare(modId, key, spec, opts)
	assert(type(modId) == "string" and modId ~= "", "modId must be a non-empty string")
	assert(type(key) == "string" and key ~= "", "interest key must be a non-empty string")
	opts = opts or {}
	local lease = addLease(self, modId, key, spec or {}, opts.nowMs)
	local function stop()
		self:revoke(modId, key)
	end
	local function touch(nowMs)
		local l = self._leases[modId] and self._leases[modId][key]
		if l then
			l.expiresAtMs = (nowMs or nowMillis()) + self._ttlMs
		end
	end
	local function replaceSpec(newSpec, replaceOpts)
		addLease(self, modId, key, newSpec or spec or {}, replaceOpts and replaceOpts.nowMs)
	end
	return {
		stop = stop,
		touch = touch,
		declare = replaceSpec,
	}
end

--- Revoke the lease for (modId, key).
--- @param modId string
--- @param key string
function Registry:revoke(modId, key)
	local mods = self._leases[modId]
	if mods then
		mods[key] = nil
		-- PZ's Kahlua runtime does not reliably expose Lua's `next()`, so use pairs() to test emptiness.
		local hasAny = false
		for _ in pairs(mods) do
			hasAny = true
			break
		end
		if not hasAny then
			self._leases[modId] = nil
		end
	end
end

local function collectValidLeases(self, nowMs)
	local specs = {}
	local expired = {}
	for modId, byKey in pairs(self._leases) do
		for key, lease in pairs(byKey) do
			if lease.expiresAtMs and lease.expiresAtMs > nowMs then
				specs[#specs + 1] = lease.spec
			else
				expired[#expired + 1] = { modId = modId, key = key }
			end
		end
	end
	-- Expired leases are removed opportunistically so forgotten declarations don’t accumulate forever.
	for _, entry in ipairs(expired) do
		self:revoke(entry.modId, entry.key)
	end
	return specs
end

--- Merge all active leases for the given fact type.
--- @param factType string
--- @param nowMs number|nil
--- @return table|nil merged
function Registry:effective(factType, nowMs)
	nowMs = nowMs or nowMillis()
	local specs = collectValidLeases(self, nowMs)
	if #specs == 0 then
		return nil
	end
	local mergedByType = mergeSpecs(specs, self._defaults)
	return mergedByType[factType or "squares"]
end

Registry._internal.normalizeBand = normalizeBand
Registry._internal.normalizeSpec = normalizeSpec
Registry._internal.mergeSpecs = mergeSpecs

return Registry
