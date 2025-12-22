-- facts/ground_entities.lua -- shared helpers for "entities on squares" fact plans (items, dead bodies, …).
--
-- Intent:
-- - Many fact types share the same acquisition mechanics:
--   1) a shared square sweep sensor for near/vision scopes, and
--   2) a low-cost "playerSquare" driver that only looks at the player's current square.
-- - This module factors out the repeated scaffolding (bucket filtering, cooldown, highlighting) while
--   keeping per-type logic (enumeration and record building) local to each fact module.
--
-- Design notes:
-- - The per-type modules keep the patch seam for their record builders (`<Type>.makeXRecord`) and
--   pass those functions into this helper via `opts.makeRecord`.
-- - We intentionally keep this module small and explicit rather than building a deep "framework".
-- - Visitor shape: `collectOnSquare(square, recordOpts, visitor)` must call `visitor(entity, extra)` where
--   `extra` is an optional table for per-entity metadata (example: `{ worldItem = ..., containerItem = ... }`).

local Cooldown = require("WorldObserver/facts/cooldown")
local InterestEffective = require("WorldObserver/facts/interest_effective")
local Targets = require("WorldObserver/facts/targets")
local Highlight = require("WorldObserver/helpers/highlight")
local SafeCall = require("WorldObserver/helpers/safe_call")
local Time = require("WorldObserver/helpers/time")

local moduleName = ...
local GroundEntities = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		GroundEntities = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = GroundEntities
	end
end

GroundEntities._internal = GroundEntities._internal or {}

local function nowMillis()
	return Time.gameMillis() or math.floor(os.time() * 1000)
end

local function listBuckets(interestRegistry, interestType)
	local buckets = {}
	if interestRegistry and type(interestRegistry.effectiveBuckets) == "function" then
		buckets = interestRegistry:effectiveBuckets(interestType) or {}
	elseif interestRegistry and type(interestRegistry.effective) == "function" then
		local merged = interestRegistry:effective(interestType)
		if merged then
			buckets = { { bucketKey = merged.bucketKey or "default", merged = merged } }
		end
	end
	return buckets
end

local function shouldHighlight(pref)
	return pref == true or type(pref) == "table"
end

--- Build a SquareSweep collector function for "entities on squares".
--- @param opts table
---   - opts.interestType: string
---   - opts.idField: string (record key field, e.g. "itemId")
---   - opts.collectorStateKey: string (stored under ctx.state[collectorStateKey])
---   - opts.getRecordOpts: fun(ctx:table):table
---   - opts.collectOnSquare: fun(square:any, recordOpts:table, visitor:fun(entity:any, extra:table|nil))
---   - opts.makeRecord: fun(ctx:table, entity:any, square:any, source:string, nowMs:number, recordOpts:table, extra:table|nil):table|nil
--- @return function collector
function GroundEntities.buildSquareCollector(opts)
	assert(type(opts) == "table", "buildSquareCollector opts required")
	assert(type(opts.interestType) == "string" and opts.interestType ~= "", "buildSquareCollector opts.interestType required")
	assert(type(opts.idField) == "string" and opts.idField ~= "", "buildSquareCollector opts.idField required")
	assert(type(opts.collectorStateKey) == "string" and opts.collectorStateKey ~= "", "buildSquareCollector opts.collectorStateKey required")
	assert(type(opts.getRecordOpts) == "function", "buildSquareCollector opts.getRecordOpts required")
	assert(type(opts.collectOnSquare) == "function", "buildSquareCollector opts.collectOnSquare required")
	assert(type(opts.makeRecord) == "function", "buildSquareCollector opts.makeRecord required")

	return function(ctx, cursor, square, _playerIndex, nowMs, effective)
		local state = (ctx and ctx.state) or {}
		if ctx then
			ctx.state = state
		end
		state[opts.collectorStateKey] = state[opts.collectorStateKey] or {}
		local collectorState = state[opts.collectorStateKey]
		collectorState.lastEmittedMs = collectorState.lastEmittedMs or {}
		local emittedByKey = collectorState.lastEmittedMs

		local cooldownSeconds = tonumber(effective and effective.cooldown) or 0
		local cooldownMs = math.max(0, cooldownSeconds * 1000)
		local recordOpts = opts.getRecordOpts(ctx)

		local emittedAny = false
		local highlighted = false
		opts.collectOnSquare(square, recordOpts, function(entity, extra)
			local record = opts.makeRecord(ctx, entity, square, cursor and cursor.source or "probe", nowMs, recordOpts, extra)
			if type(record) ~= "table" then
				return
			end
			local key = record[opts.idField]
			if key == nil then
				return
			end
			if not Cooldown.shouldEmit(emittedByKey, key, nowMs, cooldownMs) then
				return
			end
			if type(ctx.emitFn) == "function" then
				ctx.emitFn(record)
				Cooldown.markEmitted(emittedByKey, key, nowMs)
				emittedAny = true
			end

			if not highlighted and not ctx.headless then
				local highlightPref = effective and effective.highlight or nil
				if shouldHighlight(highlightPref) then
					local color, alpha = Highlight.resolveColorAlpha(highlightPref, cursor and cursor.color or nil, 0.9)
					Highlight.highlightFloor(square, Highlight.durationMsFromEffectiveCadence(effective), {
						color = color,
						alpha = alpha,
					})
					highlighted = true
				end
			end
		end)

		return emittedAny
	end
end

--- Run a "playerSquare" driver for an entity-on-square interest type.
--- @param ctx table
--- @param opts table
---   - opts.log: table (Log instance with :warn/:info)
---   - opts.interestType: string
---   - opts.scope: string (usually "playerSquare")
---   - opts.bucketsStateKey: string (stored under ctx.state[bucketsStateKey])
---   - opts.idField: string (record key field, e.g. "itemId")
---   - opts.playerHighlightColor: table fallback color
---   - opts.getRecordOpts: fun(ctx:table):table
---   - opts.collectOnSquare: fun(square:any, recordOpts:table, visitor:fun(entity:any, extra:table|nil))
---   - opts.makeRecord: fun(ctx:table, entity:any, square:any, source:string, nowMs:number, recordOpts:table, extra:table|nil):table|nil
function GroundEntities.tickPlayerSquare(ctx, opts)
	ctx = ctx or {}
	opts = opts or {}
	local state = ctx.state or {}
	ctx.state = state

	local interestType = assert(opts.interestType, "tickPlayerSquare opts.interestType required")
	local scope = assert(opts.scope, "tickPlayerSquare opts.scope required")
	local bucketsStateKey = assert(opts.bucketsStateKey, "tickPlayerSquare opts.bucketsStateKey required")
	local idField = assert(opts.idField, "tickPlayerSquare opts.idField required")
	local playerHighlightColor = opts.playerHighlightColor

	local listenerCfg = ctx.listenerCfg or {}
	local listenerEnabled = listenerCfg.enabled ~= false
	state[bucketsStateKey] = state[bucketsStateKey] or {}
	local bucketStates = state[bucketsStateKey]

	local activeBuckets = {}
	if listenerEnabled then
		for _, bucket in ipairs(listBuckets(ctx.interestRegistry, interestType)) do
			local merged = bucket.merged
			if type(merged) == "table" and merged.scope == scope then
				local bucketKey = bucket.bucketKey or scope
				local target = merged.target
				local effective = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, interestType, {
					label = scope,
					allowDefault = false,
					log = opts.log,
					bucketKey = bucketKey,
					merged = merged,
				})
				if effective then
					effective.highlight = merged.highlight
					effective.target = target
					activeBuckets[bucketKey] = { effective = effective, target = target }
				end
			end
		end
	else
		-- Listener disabled: clear bucket state so we don't keep cooldown tables forever.
		for key in pairs(bucketStates) do
			bucketStates[key] = nil
		end
	end

	-- Remove stale buckets (leases revoked).
	for key in pairs(bucketStates) do
		if not activeBuckets[key] then
			bucketStates[key] = nil
		end
	end

	for bucketKey, entry in pairs(activeBuckets) do
		local bucketState = bucketStates[bucketKey] or {}
		bucketStates[bucketKey] = bucketState

		local player = Targets.resolvePlayer(entry.target)
		if player == nil then
			bucketState.lastEmittedMs = nil
		else
			local square = SafeCall.safeCall(player, "getCurrentSquare")
			if square ~= nil then
				local nowMs = nowMillis()
				local cooldownMs = math.max(0, (tonumber(entry.effective.cooldown) or 0) * 1000)
				local recordOpts = opts.getRecordOpts(ctx)
				local highlighted = false

				bucketState.lastEmittedMs = bucketState.lastEmittedMs or {}
				local emittedByKey = bucketState.lastEmittedMs

				opts.collectOnSquare(square, recordOpts, function(entity, extra)
					local record = opts.makeRecord(ctx, entity, square, "player", nowMs, recordOpts, extra)
					if type(record) ~= "table" then
						return
					end
					local key = record[idField]
					if key == nil then
						return
					end
					if not Cooldown.shouldEmit(emittedByKey, key, nowMs, cooldownMs) then
						return
					end
					if type(ctx.emitFn) == "function" then
						ctx.emitFn(record)
					end
					Cooldown.markEmitted(emittedByKey, key, nowMs)

					if not highlighted and not ctx.headless then
						local highlightPref = entry.effective.highlight
						if shouldHighlight(highlightPref) then
							local color, alpha = Highlight.resolveColorAlpha(highlightPref, playerHighlightColor, 0.9)
							Highlight.highlightFloor(square, Highlight.durationMsFromEffectiveCadence(entry.effective), {
								color = color,
								alpha = alpha,
							})
						end
						highlighted = true
					end
				end)
			end
		end
	end
end

GroundEntities._internal.nowMillis = nowMillis
GroundEntities._internal.listBuckets = listBuckets

return GroundEntities
