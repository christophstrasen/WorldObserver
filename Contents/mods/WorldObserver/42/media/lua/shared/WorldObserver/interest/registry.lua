-- interest/registry.lua -- stores mod interest declarations (leases) and merges them into effective interest bands.
--
-- Why this exists:
-- - WorldObserver is a shared runtime. Multiple mods can request the same upstream probing/listening work.
-- - We need a deterministic way to merge those requests into "one plan" the runtime can try to satisfy fairly.
--
-- The important design choice (intent):
-- - Some interest types are "bucketed" by a target identity (example: squares scope=near for *player 0* vs scope=near for *a static square*).
-- - We only merge declarations within the same bucket (same target identity).
--   This is the simplest correctness/fairness model: it avoids "partial overlap" merging (which quickly explodes
--   into geometry + prioritization problems) and keeps behavior predictable for modders.
local Time = require("WorldObserver/helpers/time")
local Log = require("LQR/util/log").withTag("WO.INTEREST")

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
--- @field ttlMs number
--- @field expiresAtMs number

-- Default TTL must be comfortably above how often mods typically refresh their declarations,
-- otherwise leases can expire during normal play even when a mod still cares about them.
local DEFAULT_TTL_MS = 10 * 60 * 1000

local DEFAULTS = {
	["squares"] = {
		staleness = { desired = 10, tolerable = 20 },
		radius = { desired = 8, tolerable = 5 },
		cooldown = { desired = 30, tolerable = 60 },
		highlight = nil,
	},
	["zombies"] = {
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

local function warnInvalidTarget(message)
	if _G.WORLDOBSERVER_HEADLESS == true then
		return
	end
	Log:warn("[interest] invalid target: %s", tostring(message))
end

local function invalidTarget(message)
	warnInvalidTarget(message)
	return { kind = "invalid" }
end

local function normalizeTarget(target)
	if type(target) ~= "table" then
		return invalidTarget("target must be a table")
	end
	if target.kind ~= nil then
		return invalidTarget("target.kind is no longer supported; use target = { player = { id = 0 } }")
	end

	local kind, value
	local count = 0
	for k, v in pairs(target) do
		if type(k) == "string" and k ~= "" then
			kind = kind or k
			value = value or v
			count = count + 1
		end
	end
	if count == 0 then
		return invalidTarget("target must include exactly one kind key (e.g. { player = { id = 0 } })")
	end
	if count > 1 then
		return invalidTarget("target must include exactly one kind key (got multiple)")
	end
	if type(value) ~= "table" then
		return invalidTarget(("target.%s must be a table"):format(tostring(kind)))
	end

	if kind == "player" then
		return { kind = "player", id = tonumber(value.id) or 0 }
	end
	if kind == "square" then
		local x = tonumber(value.x)
		local y = tonumber(value.y)
		if x == nil or y == nil then
			return invalidTarget("target.square requires x and y")
		end
		local z = tonumber(value.z) or 0
		return {
			kind = "square",
			x = math.floor(x),
			y = math.floor(y),
			z = math.floor(z),
		}
	end
	return {
		kind = kind,
		id = value.id or value.key,
	}
end

local function normalizeScope(scope, fallback)
	if type(scope) == "string" and scope ~= "" then
		return scope
	end
	return fallback
end

local function isSquaresEventScope(scope)
	return scope == "onLoad"
end

local function warnIgnored(interestType, scope, field)
	if _G.WORLDOBSERVER_HEADLESS == true then
		return
	end
	Log:warn("[interest] ignoring %s for %s scope=%s", tostring(field), tostring(interestType), tostring(scope))
end

-- Build the merge bucket key for an interest spec.
--
-- Intent:
-- - `player` targets are WO-owned and merge across mods (bucket does NOT include modId).
-- - `square` targets are mod-owned (x/y/z anchors) and are intentionally NOT merged across mods
--   (bucket includes modId), because WO cannot validate that two mods mean the same thing by that anchor.
--   This keeps the "trust surface" small: a mod can't affect another mod's probes by spoofing a shared center.
local function bucketKeyForTarget(scope, target, modId)
	scope = normalizeScope(scope, "near")
	if isSquaresEventScope(scope) then
		return "onLoad"
	end
	local kind = target and target.kind or "player"
	if kind == "player" then
		local id = target and target.id or 0
		return scope .. ":player:" .. tostring(id)
	end
	if kind == "square" then
		local x = target and target.x
		local y = target and target.y
		local z = target and target.z or 0
		if type(x) == "number" and type(y) == "number" then
			return scope .. ":square:" .. tostring(modId) .. ":" .. tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
		end
		return scope .. ":square:" .. tostring(modId)
	end
	local id = target and target.id
	local suffix = id ~= nil and tostring(id) or "unknown"
	return scope .. ":" .. tostring(kind) .. ":" .. tostring(modId) .. ":" .. suffix
end

-- Normalize a user-provided interest spec into a canonical shape used by the runtime.
--
-- Why normalize here:
-- - Leases are stored for a long time; we want them to have stable semantics even if callers omit fields.
-- - Downstream (policy/probes) should not have to handle every historical "shape".
local function normalizeSpec(spec, defaults, modId)
	spec = spec or {}
	local interestType = spec.type
	if type(interestType) ~= "string" or interestType == "" then
		-- Default to the common “near squares” interest so mods can declare without boilerplate.
		interestType = "squares"
	end
	local canonicalType = interestType
	local scope = spec.scope
	local target = nil
	if interestType == "squares" then
		scope = normalizeScope(scope, "near")
		if not isSquaresEventScope(scope) then
			if spec.target == nil then
				target = { player = { id = 0 } }
			else
				target = normalizeTarget(spec.target)
			end
		else
			if spec.target ~= nil then
				warnIgnored(interestType, scope, "target")
			end
			if spec.radius ~= nil then
				warnIgnored(interestType, scope, "radius")
			end
			if spec.staleness ~= nil then
				warnIgnored(interestType, scope, "staleness")
			end
		end
	elseif interestType == "zombies" then
		scope = normalizeScope(scope, "allLoaded")
		if scope ~= "allLoaded" then
			warnIgnored(interestType, scope, "scope")
			scope = "allLoaded"
		end
		if spec.target ~= nil then
			warnIgnored(interestType, scope, "target")
		end
	end
	local typeDefaults = defaults[canonicalType] or defaults[interestType] or {}
	local staleness = nil
	local radius = nil
	if interestType == "squares" and isSquaresEventScope(scope) then
		-- Event scopes ignore probe-only knobs; normalize them to zeroed bands so merges stay stable.
		staleness = { desired = 0, tolerable = 0 }
		radius = { desired = 0, tolerable = 0 }
	else
		staleness = normalizeBand(spec.staleness, typeDefaults.staleness)
		radius = normalizeBand(spec.radius, typeDefaults.radius)
	end
	local normalized = {
		type = canonicalType,
		scope = scope,
		target = target,
		staleness = staleness,
		radius = radius,
		zRange = normalizeBand(spec.zRange, typeDefaults.zRange),
		cooldown = normalizeBand(spec.cooldown, typeDefaults.cooldown),
		highlight = spec.highlight ~= nil and spec.highlight or typeDefaults.highlight,
	}
	local bucketKey = "default"
	if canonicalType == "squares" then
		bucketKey = bucketKeyForTarget(scope, target, modId or "unknown")
	elseif canonicalType == "zombies" then
		bucketKey = scope or "allLoaded"
	end
	return normalized, bucketKey
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

local function mergeSpecs(leases)
	local mergedByType = {}
	for _, lease in ipairs(leases) do
		local normalized = lease.spec
		local typeKey = normalized.type
		local bucketKey = lease.bucketKey or "default"
		local buckets = mergedByType[typeKey]
		if not buckets then
			buckets = {}
			mergedByType[typeKey] = buckets
		end
		local target = buckets[bucketKey]
		if not target then
			target = {
				type = normalized.type,
				bucketKey = bucketKey,
				scope = normalized.scope,
				target = normalized.target,
				staleness = cloneTable(normalized.staleness),
				radius = cloneTable(normalized.radius),
				zRange = cloneTable(normalized.zRange),
				cooldown = cloneTable(normalized.cooldown),
				highlight = normalized.highlight,
			}
			buckets[bucketKey] = target
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

local function addLeaseWithTtl(self, modId, key, spec, nowMs, ttlMs)
	ttlMs = tonumber(ttlMs) or self._ttlMs
	assert(ttlMs > 0, "interest lease ttl must be > 0")
	local normalizedSpec, bucketKey = normalizeSpec(spec or {}, self._defaults, modId)
	local lease = {
		modId = modId,
		key = key,
		spec = normalizedSpec,
		bucketKey = bucketKey,
		ttlMs = ttlMs,
		expiresAtMs = (nowMs or nowMillis()) + ttlMs,
	}
	self._leases[modId] = self._leases[modId] or {}
	self._leases[modId][key] = lease
	return lease
end

local function addLease(self, modId, key, spec, nowMs)
	return addLeaseWithTtl(self, modId, key, spec, nowMs, self._ttlMs)
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
	local ttlMs = opts.ttlMs
	if ttlMs == nil and opts.ttlSeconds ~= nil then
		ttlMs = (type(opts.ttlSeconds) == "number") and (opts.ttlSeconds * 1000) or nil
	end
	if ttlMs ~= nil then
		ttlMs = tonumber(ttlMs)
		assert(type(ttlMs) == "number" and ttlMs > 0, "interest lease ttl must be a number > 0")
	end

	local lease
	if ttlMs ~= nil then
		lease = addLeaseWithTtl(self, modId, key, spec or {}, opts.nowMs, ttlMs)
	else
		lease = addLease(self, modId, key, spec or {}, opts.nowMs)
	end

	local leaseHandle = {}

	local function stop()
		self:revoke(modId, key)
	end

	local function renew(nowMsOrSelf, maybeNowMs)
		local nowMs = maybeNowMs
		if nowMsOrSelf == leaseHandle then
			nowMs = maybeNowMs
		elseif type(nowMsOrSelf) == "number" and nowMs == nil then
			nowMs = nowMsOrSelf
		end
		if type(nowMs) ~= "number" then
			nowMs = nil
		end
		local l = self._leases[modId] and self._leases[modId][key]
		if l then
			l.expiresAtMs = (nowMs or nowMillis()) + (l.ttlMs or self._ttlMs)
		end
	end

	local function replaceSpec(selfOrNewSpec, maybeNewSpec, maybeReplaceOpts)
		local newSpec = selfOrNewSpec
		local replaceOpts = maybeNewSpec
		if selfOrNewSpec == leaseHandle then
			newSpec = maybeNewSpec
			replaceOpts = maybeReplaceOpts
		end

		local existing = self._leases[modId] and self._leases[modId][key]
		local keepTtlMs = existing and existing.ttlMs or nil
		local replaceTtlMs = replaceOpts and replaceOpts.ttlMs
		if replaceTtlMs == nil and replaceOpts and replaceOpts.ttlSeconds ~= nil then
			replaceTtlMs = (type(replaceOpts.ttlSeconds) == "number") and (replaceOpts.ttlSeconds * 1000) or nil
		end
		if replaceTtlMs ~= nil then
			replaceTtlMs = tonumber(replaceTtlMs)
			assert(type(replaceTtlMs) == "number" and replaceTtlMs > 0, "interest lease ttl must be a number > 0")
			addLeaseWithTtl(self, modId, key, newSpec or spec or {}, replaceOpts and replaceOpts.nowMs, replaceTtlMs)
		elseif keepTtlMs ~= nil then
			addLeaseWithTtl(self, modId, key, newSpec or spec or {}, replaceOpts and replaceOpts.nowMs, keepTtlMs)
		else
			addLease(self, modId, key, newSpec or spec or {}, replaceOpts and replaceOpts.nowMs)
		end
	end

	leaseHandle.stop = stop
	leaseHandle.renew = renew
	leaseHandle.declare = replaceSpec
	return leaseHandle
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
	local leases = {}
	local expired = {}
	for modId, byKey in pairs(self._leases) do
		for key, lease in pairs(byKey) do
			if lease.expiresAtMs and lease.expiresAtMs > nowMs then
				leases[#leases + 1] = lease
			else
				expired[#expired + 1] = { modId = modId, key = key }
			end
		end
	end
	-- Expired leases are removed opportunistically so forgotten declarations don’t accumulate forever.
	for _, entry in ipairs(expired) do
		self:revoke(entry.modId, entry.key)
	end
	return leases
end

local function resolveTypeAndBucket(factType, opts)
	local bucketKey = opts and opts.bucketKey or nil
	return factType, bucketKey
end

--- Merge all active leases for the given fact type.
--- @param factType string
--- @param nowMs number|nil
--- @param opts table|nil Optional, e.g. { bucketKey = "near:player:0" }.
--- @return table|nil merged
function Registry:effective(factType, nowMs, opts)
	nowMs = nowMs or nowMillis()
	local leases = collectValidLeases(self, nowMs)
	if #leases == 0 then
		return nil
	end
	local mergedByType = mergeSpecs(leases)
	local canonicalType, bucketKey = resolveTypeAndBucket(factType or "squares", opts)
	local buckets = mergedByType[canonicalType]
	if not buckets then
		return nil
	end
	if bucketKey ~= nil then
		return buckets[bucketKey]
	end
	-- For bucketed types, returning "the only bucket" is a convenience when exactly one exists.
	-- If multiple buckets exist, callers should use `effectiveBuckets` to iterate deterministically.
	local only = nil
	for _, merged in pairs(buckets) do
		if only ~= nil then
			return nil
		end
		only = merged
	end
	return only
end

Registry._internal.normalizeBand = normalizeBand
Registry._internal.normalizeSpec = normalizeSpec
Registry._internal.mergeSpecs = mergeSpecs
Registry._internal.bucketKeyForTarget = bucketKeyForTarget

-- Enumerate all merged buckets for a fact type.
--
-- This is the primary interface for bucketed interests: probes can scan each bucket independently and
-- schedule them round-robin under a shared budget.
function Registry:effectiveBuckets(factType, nowMs, opts)
	nowMs = nowMs or nowMillis()
	local leases = collectValidLeases(self, nowMs)
	if #leases == 0 then
		return {}
	end
	local mergedByType = mergeSpecs(leases)
	local canonicalType, bucketKey = resolveTypeAndBucket(factType or "squares", opts)
	local buckets = mergedByType[canonicalType]
	if not buckets then
		return {}
	end
	if bucketKey ~= nil then
		local merged = buckets[bucketKey]
		if not merged then
			return {}
		end
		return { { bucketKey = bucketKey, merged = merged } }
	end
	local keys = {}
	for key in pairs(buckets) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	local out = {}
	for _, key in ipairs(keys) do
		out[#out + 1] = { bucketKey = key, merged = buckets[key] }
	end
	return out
end

return Registry
