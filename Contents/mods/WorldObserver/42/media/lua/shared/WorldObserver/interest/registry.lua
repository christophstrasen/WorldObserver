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
local Definitions = require("WorldObserver/interest/definitions")

local moduleName = ...
local Registry = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Registry = loaded
	else
		---@diagnostic disable-next-line: undefined-field
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
	["players"] = {
		cooldown = { desired = 0.2, tolerable = 0.4 },
		highlight = nil,
	},
	["rooms"] = {
		staleness = { desired = 60, tolerable = 120 },
		radius = { desired = 0, tolerable = 0 },
		zRange = { desired = 0, tolerable = 0 },
		cooldown = { desired = 20, tolerable = 40 },
		highlight = nil,
	},
	["items"] = {
		staleness = { desired = 10, tolerable = 20 },
		radius = { desired = 8, tolerable = 5 },
		cooldown = { desired = 10, tolerable = 20 },
		highlight = nil,
	},
	["deadBodies"] = {
		staleness = { desired = 10, tolerable = 20 },
		radius = { desired = 8, tolerable = 5 },
		cooldown = { desired = 10, tolerable = 20 },
		highlight = nil,
	},
	["sprites"] = {
		staleness = { desired = 10, tolerable = 20 },
		radius = { desired = 8, tolerable = 5 },
		cooldown = { desired = 10, tolerable = 20 },
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

local function normalizeSpriteNames(value, modId, key)
	if type(value) == "string" then
		value = { value }
	end
	if type(value) ~= "table" then
		return nil
	end
	local out = {}
	local seen = {}
	local function considerName(name)
		if type(name) ~= "string" or name == "" or seen[name] then
			return
		end
		local percent = string.find(name, "%%", 1, true)
		if percent ~= nil and percent < #name then
			if _G.WORLDOBSERVER_HEADLESS ~= true then
				Log:warn(
					"[interest] spriteNames entry ignored (only trailing %% supported) mod=%s key=%s entry=%s",
					tostring(modId),
					tostring(key),
					tostring(name)
				)
			end
			return
		end
		out[#out + 1] = name
		seen[name] = true
	end

	if value[1] ~= nil then
		for i = 1, #value do
			considerName(value[i])
		end
	else
		for k, v in pairs(value) do
			if v == true then
				considerName(k)
			else
				considerName(v)
			end
		end
	end
	if out[1] == nil then
		return nil
	end
	table.sort(out)
	return out
end

local function normalizeScope(scope, fallback)
	if type(scope) == "string" and scope ~= "" then
		return scope
	end
	return fallback
end

local function typeDefFor(interestType)
	return Definitions and Definitions.types and Definitions.types[interestType] or nil
end

local function isEventScope(typeDef, scope)
	return typeDef and typeDef.eventScopes and typeDef.eventScopes[scope] == true
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
	if scope == "onLoad" then
		return "onLoad"
	end
	if scope == "onLoadWithSprite" then
		return "onLoadWithSprite"
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
local function warnIgnoredFields(spec, interestType, scope, typeDef)
	if not (typeDef and typeDef.ignoreFields) then
		return
	end
	local ignored = typeDef.ignoreFields[scope]
	if type(ignored) ~= "table" then
		return
	end
	for field in pairs(ignored) do
		if spec[field] ~= nil then
			warnIgnored(interestType, scope, field)
		end
	end
end

local function resolveScope(interestType, scope, typeDef)
	if not typeDef then
		return scope
	end
	local normalized = normalizeScope(scope, typeDef.defaultScope)
	if typeDef.strictScopes and typeDef.allowedScopes and not typeDef.allowedScopes[normalized] then
		warnIgnored(interestType, normalized, "scope")
		normalized = typeDef.defaultScope
	end
	return normalized
end

local function normalizeKnob(value, defaults, zeroed)
	if zeroed then
		return { desired = 0, tolerable = 0 }
	end
	return normalizeBand(value, defaults)
end

local function allowTargetForScope(typeDef, scope)
	if not typeDef then
		return false
	end
	if typeDef.allowTargetScopes and typeDef.allowTargetScopes[scope] then
		return true
	end
	if typeDef.allowTarget == true and not isEventScope(typeDef, scope) then
		return true
	end
	return false
end

local function resolveDefaultTarget(typeDef, scope)
	if not typeDef then
		return nil
	end
	if typeDef.defaultTargetScopes and typeDef.defaultTargetScopes[scope] then
		return typeDef.defaultTargetScopes[scope]
	end
	return typeDef.defaultTarget
end

local function fieldsForScope(typeDef, fieldKey, scope)
	if not (typeDef and typeDef[fieldKey]) then
		return nil
	end
	local fields = typeDef[fieldKey]
	if type(fields) ~= "table" then
		return nil
	end
	local scoped = fields[scope] or fields.all or fields.default
	if type(scoped) ~= "table" then
		return nil
	end
	return scoped
end

local function isFieldSpecified(spec, normalized, field)
	if field == "spriteNames" then
		return type(normalized.spriteNames) == "table" and normalized.spriteNames[1] ~= nil
	end
	if field == "target" then
		return spec.target ~= nil
	end
	return spec[field] ~= nil
end

local function listMissingFields(spec, normalized, fields)
	if type(fields) ~= "table" then
		return nil
	end
	local missing = {}
	for i = 1, #fields do
		local field = fields[i]
		if not isFieldSpecified(spec, normalized, field) then
			missing[#missing + 1] = field
		end
	end
	if missing[1] == nil then
		return nil
	end
	return missing
end

local function hasAnyRecommended(spec, normalized, fields)
	if type(fields) ~= "table" then
		return false
	end
	for i = 1, #fields do
		if isFieldSpecified(spec, normalized, fields[i]) then
			return true
		end
	end
	return false
end

local function warnMissingFields(modId, key, spec, normalized)
	if _G.WORLDOBSERVER_HEADLESS == true then
		return
	end
	local typeDef = typeDefFor(normalized and normalized.type or nil)
	if not typeDef then
		return
	end
	local scope = normalized and normalized.scope or nil
	local required = fieldsForScope(typeDef, "requiredFields", scope)
	local missingRequired = listMissingFields(spec or {}, normalized or {}, required)
	if missingRequired and missingRequired[1] ~= nil then
		Log:warn(
			"[interest] missing required fields mod=%s key=%s type=%s scope=%s fields=%s",
			tostring(modId),
			tostring(key),
			tostring(normalized and normalized.type or nil),
			tostring(scope),
			table.concat(missingRequired, ",")
		)
		return
	end

	local recommended = fieldsForScope(typeDef, "recommendedFields", scope)
	if recommended and recommended[1] ~= nil and not hasAnyRecommended(spec or {}, normalized or {}, recommended) then
		Log:warn(
			"[interest] lease uses defaults mod=%s key=%s type=%s scope=%s consider=%s",
			tostring(modId),
			tostring(key),
			tostring(normalized and normalized.type or nil),
			tostring(scope),
			table.concat(recommended, ",")
		)
	end
end

local function normalizeSpec(spec, defaults, modId, key)
	spec = spec or {}
	local interestType = spec.type
	if type(interestType) ~= "string" or interestType == "" then
		-- Default to the common “near squares” interest so mods can declare without boilerplate.
		interestType = Definitions.defaultType or "squares"
	end
	local canonicalType = interestType
	local typeDef = typeDefFor(interestType)
	local scope = resolveScope(interestType, spec.scope, typeDef)
	local target = nil
	if typeDef then
		warnIgnoredFields(spec, interestType, scope, typeDef)
		if allowTargetForScope(typeDef, scope) then
			if spec.target == nil then
				target = cloneTable(resolveDefaultTarget(typeDef, scope))
			else
				target = normalizeTarget(spec.target)
			end
		end
	end
	local typeDefaults = defaults[canonicalType] or defaults[interestType] or {}
	local zeroKnobs = typeDef and typeDef.zeroKnobs and typeDef.zeroKnobs[scope] or nil
	local staleness = normalizeKnob(spec.staleness, typeDefaults.staleness, zeroKnobs and zeroKnobs.staleness)
	local radius = normalizeKnob(spec.radius, typeDefaults.radius, zeroKnobs and zeroKnobs.radius)
	local zRange = normalizeKnob(spec.zRange, typeDefaults.zRange, zeroKnobs and zeroKnobs.zRange)
	local normalized = {
		type = canonicalType,
		scope = scope,
		target = target,
		spriteNames = normalizeSpriteNames(spec.spriteNames, modId, key),
		staleness = staleness,
		radius = radius,
		zRange = zRange,
		cooldown = normalizeBand(spec.cooldown, typeDefaults.cooldown),
		highlight = spec.highlight ~= nil and spec.highlight or typeDefaults.highlight,
	}
	local bucketKey = "default"
	if typeDef and typeDef.bucketKey == "squaresTarget" then
		bucketKey = bucketKeyForTarget(scope, target, modId or "unknown")
	elseif typeDef and typeDef.bucketKey == "scope" then
		bucketKey = scope or typeDef.defaultScope or "default"
	elseif typeDef and typeDef.bucketKey == "roomsScope" then
		if scope == "onPlayerChangeRoom" then
			bucketKey = bucketKeyForTarget(scope, target, modId or "unknown")
		elseif isEventScope(typeDef, scope) then
			bucketKey = "onSeeNewRoom"
		else
			bucketKey = "allLoaded"
		end
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
				spriteNames = cloneTable(normalized.spriteNames),
				staleness = cloneTable(normalized.staleness),
				radius = cloneTable(normalized.radius),
				zRange = cloneTable(normalized.zRange),
				cooldown = cloneTable(normalized.cooldown),
				highlight = normalized.highlight,
			}
			buckets[bucketKey] = target
		else
			if type(normalized.spriteNames) == "table" then
				target.spriteNames = target.spriteNames or {}
				local seen = {}
				for i = 1, #target.spriteNames do
					seen[target.spriteNames[i]] = true
				end
				for i = 1, #normalized.spriteNames do
					local name = normalized.spriteNames[i]
					if type(name) == "string" and name ~= "" and not seen[name] then
						target.spriteNames[#target.spriteNames + 1] = name
						seen[name] = true
					end
				end
				table.sort(target.spriteNames)
			end
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
	local incomingSpec = spec or {}
	local normalizedSpec, bucketKey = normalizeSpec(incomingSpec, self._defaults, modId, key)
	warnMissingFields(modId, key, incomingSpec, normalizedSpec)
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
