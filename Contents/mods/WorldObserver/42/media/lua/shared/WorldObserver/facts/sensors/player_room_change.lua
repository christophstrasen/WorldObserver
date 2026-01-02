-- facts/sensors/player_room_change.lua -- shared tick-driven player room change sensor.
--
-- Intent:
-- - Detect when a player's room changes (per target bucket).
-- - Fan out that event to multiple fact families (rooms, players) without mixing schemas.
-- - Keep detection logic centralized while collectors stay type-specific.

local Log = require("DREAMBase/log").withTag("WO.FACTS.playerRoomChange")
local Time = require("DREAMBase/time_ms")
local SafeCall = require("DREAMBase/pz/safe_call")
local Cooldown = require("WorldObserver/facts/cooldown")
local InterestEffective = require("WorldObserver/facts/interest_effective")
local Targets = require("WorldObserver/facts/targets")

local moduleName = ...
local PlayerRoomChange = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		PlayerRoomChange = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = PlayerRoomChange
	end
end
PlayerRoomChange._internal = PlayerRoomChange._internal or {}
PlayerRoomChange._consumers = PlayerRoomChange._consumers or {}
PlayerRoomChange._runner = PlayerRoomChange._runner or {
	state = {},
	tickHookAttached = false,
	tickHookId = nil,
	factRegistry = nil,
}

local INTEREST_SCOPE = "onPlayerChangeRoom"
local TICK_HOOK_ID = "facts.playerRoomChange.tick"

local function nowMillis()
	return Time.gameMillis() or math.floor(os.time() * 1000)
end

local function resolveRoomForPlayer(player)
	if player == nil then
		return nil
	end
	local square = SafeCall.safeCall(player, "getCurrentSquare")
	if square == nil then
		return nil
	end
	return SafeCall.safeCall(square, "getRoom")
end

local function resolveBuckets(ctx, interestType)
	local buckets = {}
	if ctx.interestRegistry and ctx.interestRegistry.effectiveBuckets then
		buckets = ctx.interestRegistry:effectiveBuckets(interestType)
	elseif ctx.interestRegistry and ctx.interestRegistry.effective then
		local merged = ctx.interestRegistry:effective(interestType)
		if merged then
			buckets = { { bucketKey = merged.bucketKey or "default", merged = merged } }
		end
	end
	return buckets
end

local function isConsumerActive(entry)
	return type(entry) == "table"
		and entry.enabled ~= false
		and type(entry.emitFn) == "function"
		and type(entry.makeRecord) == "function"
end

local function resolveBaseContext(consumers)
	local runtime = nil
	local interestRegistry = nil
	local headless = true
	for _, entry in pairs(consumers or {}) do
		if isConsumerActive(entry) then
			if runtime == nil and entry.runtime ~= nil then
				runtime = entry.runtime
			end
			if interestRegistry == nil and entry.interestRegistry ~= nil then
				interestRegistry = entry.interestRegistry
			end
			if entry.headless ~= true then
				headless = false
			end
		end
	end
	return {
		runtime = runtime,
		interestRegistry = interestRegistry,
		headless = headless,
	}
end

local function resolvePlayerForType(interestType, target)
	if interestType == "players" then
		return Targets.resolvePlayer({ kind = "player", id = 0 })
	end
	if target == nil then
		return Targets.resolvePlayer({ kind = "player", id = 0 })
	end
	return Targets.resolvePlayer(target)
end

local function emitWithCooldown(state, consumer, record, cooldownKey, nowMs, cooldownMs, onEmitFn)
	if type(consumer.emitFn) ~= "function" or cooldownKey == nil then
		return false
	end
	state.lastEmittedMs = state.lastEmittedMs or {}
	if not Cooldown.shouldEmit(state.lastEmittedMs, cooldownKey, nowMs, cooldownMs) then
		return false
	end
	if type(onEmitFn) == "function" then
		pcall(onEmitFn, record)
	end
	consumer.emitFn(record)
	Cooldown.markEmitted(state.lastEmittedMs, cooldownKey, nowMs)
	return true
end

local function buildActiveBuckets(ctx, interestType, scope)
	local active = {}
	for _, bucket in ipairs(resolveBuckets(ctx, interestType)) do
		local merged = bucket.merged
		if type(merged) == "table" and merged.scope == scope then
			local bucketKey = bucket.bucketKey or scope
			local effective = InterestEffective.ensure(ctx.state, ctx.interestRegistry, ctx.runtime, interestType, {
				label = scope,
				allowDefault = false,
				log = Log,
				bucketKey = bucketKey,
				merged = merged,
			})
			if effective then
				effective.highlight = merged.highlight
				effective.target = merged.target
				active[bucketKey] = { effective = effective, target = merged.target }
			end
		end
	end
	return active
end

local function tickForType(ctx, consumer)
	if not isConsumerActive(consumer) then
		return
	end
	local interestType = consumer.interestType or consumer.id
	if interestType == nil then
		return
	end
	local scope = consumer.scope or INTEREST_SCOPE
	local activeBuckets = buildActiveBuckets(ctx, interestType, scope)

	ctx.state._playerRoomBucketsByType = ctx.state._playerRoomBucketsByType or {}
	local stateBuckets = ctx.state._playerRoomBucketsByType[interestType] or {}
	ctx.state._playerRoomBucketsByType[interestType] = stateBuckets

	for key in pairs(stateBuckets) do
		if not activeBuckets[key] then
			stateBuckets[key] = nil
		end
	end

	for bucketKey, entry in pairs(activeBuckets) do
		local bucketState = stateBuckets[bucketKey] or {}
		stateBuckets[bucketKey] = bucketState

		local player = resolvePlayerForType(interestType, entry.target)
		if player == nil then
			bucketState.lastRoomRef = nil
			bucketState.lastRoomKey = nil
		else
			local room = resolveRoomForPlayer(player)
			if room == nil then
				bucketState.lastRoomRef = nil
				bucketState.lastRoomKey = nil
			elseif room ~= bucketState.lastRoomRef then
				local record = consumer.makeRecord(player, room)
				if record ~= nil then
					local roomKey = consumer.roomKey and consumer.roomKey(record, room) or nil
					if roomKey ~= nil and roomKey ~= bucketState.lastRoomKey then
						local cooldownKey = consumer.cooldownKey and consumer.cooldownKey(record, room) or nil
						local cooldownMs = math.max(0, (tonumber(entry.effective.cooldown) or 0) * 1000)
						local emitted = emitWithCooldown(
							bucketState,
							consumer,
							record,
							cooldownKey,
							nowMillis(),
							cooldownMs,
							function()
								if consumer.onEmit then
									consumer.onEmit(record, entry.effective, {
										player = player,
										room = room,
										bucketKey = bucketKey,
									})
								end
							end
						)
						if emitted then
							bucketState.lastRoomKey = roomKey
						end
					end
				end
				bucketState.lastRoomRef = room
			end
		end
	end
end

local function sharedTick()
	local runner = PlayerRoomChange._runner
	if not runner then
		return
	end
	local consumers = PlayerRoomChange._consumers
	if not consumers then
		return
	end
	local base = resolveBaseContext(consumers)
	if base.interestRegistry == nil then
		return
	end

	PlayerRoomChange.tick({
		state = runner.state,
		runtime = base.runtime,
		interestRegistry = base.interestRegistry,
		headless = base.headless,
		consumers = consumers,
	})
end

if PlayerRoomChange.tick == nil then
	--- Run one sensor tick for all registered consumers.
	--- @param ctx table
	function PlayerRoomChange.tick(ctx)
		ctx = ctx or {}
		ctx.state = ctx.state or {}
		ctx.consumers = ctx.consumers or {}
		for _, consumer in pairs(ctx.consumers) do
			tickForType(ctx, consumer)
		end
	end
end

if PlayerRoomChange.registerConsumer == nil then
	--- Register a player room change consumer (fact plan).
	--- @param id string
	--- @param opts table
	function PlayerRoomChange.registerConsumer(id, opts)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		opts = opts or {}
		local entry = PlayerRoomChange._consumers[id] or { id = id }
		entry.interestType = opts.interestType or entry.interestType or id
		entry.scope = opts.scope or entry.scope or INTEREST_SCOPE
		entry.emitFn = opts.emitFn or entry.emitFn
		entry.makeRecord = opts.makeRecord or entry.makeRecord
		entry.cooldownKey = opts.cooldownKey or entry.cooldownKey
		entry.roomKey = opts.roomKey or entry.roomKey
		entry.onEmit = opts.onEmit or entry.onEmit
		entry.runtime = opts.runtime or entry.runtime
		entry.interestRegistry = opts.interestRegistry or entry.interestRegistry
		entry.headless = opts.headless == true
		entry.enabled = opts.enabled ~= false
		PlayerRoomChange._consumers[id] = entry

		local runner = PlayerRoomChange._runner
		local factRegistry = opts.factRegistry or (runner and runner.factRegistry) or nil
		if factRegistry and type(factRegistry.attachTickHook) == "function" then
			if runner and not runner.tickHookAttached then
				local ok, err = pcall(factRegistry.attachTickHook, factRegistry, TICK_HOOK_ID, sharedTick)
				if ok then
					runner.tickHookAttached = true
					runner.tickHookId = TICK_HOOK_ID
					runner.factRegistry = factRegistry
				elseif _G.WORLDOBSERVER_HEADLESS ~= true then
					Log:warn("Player room change tick hook not attached (err=%s)", tostring(err))
				end
			end
		elseif _G.WORLDOBSERVER_HEADLESS ~= true then
			Log:warn("Player room change tick hook not attached (FactRegistry.attachTickHook unavailable)")
		end
		return true
	end
end

if PlayerRoomChange.unregisterConsumer == nil then
	--- Unregister a player room change consumer.
	--- @param id string
	function PlayerRoomChange.unregisterConsumer(id)
		if type(id) ~= "string" or id == "" then
			return false, "badId"
		end
		PlayerRoomChange._consumers[id] = nil

		local runner = PlayerRoomChange._runner
		if runner and runner.tickHookAttached then
			local hasActive = false
			for _, entry in pairs(PlayerRoomChange._consumers or {}) do
				if isConsumerActive(entry) then
					hasActive = true
					break
				end
			end
			if not hasActive and runner.factRegistry and type(runner.factRegistry.detachTickHook) == "function" then
				pcall(runner.factRegistry.detachTickHook, runner.factRegistry, runner.tickHookId or TICK_HOOK_ID)
				runner.tickHookAttached = false
				runner.tickHookId = nil
			end
		end
		return true
	end
end

return PlayerRoomChange
