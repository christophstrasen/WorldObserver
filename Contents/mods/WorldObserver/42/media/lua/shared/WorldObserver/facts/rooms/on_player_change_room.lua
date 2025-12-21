-- facts/rooms/on_player_change_room.lua -- emits room records when a player changes rooms.
local Log = require("LQR/util/log").withTag("WO.FACTS.rooms")
local Time = require("WorldObserver/helpers/time")
local Cooldown = require("WorldObserver/facts/cooldown")
local InterestEffective = require("WorldObserver/facts/interest_effective")
local Highlight = require("WorldObserver/helpers/highlight")
local JavaList = require("WorldObserver/helpers/java_list")
local SafeCall = require("WorldObserver/helpers/safe_call")
local Targets = require("WorldObserver/facts/targets")

local moduleName = ...
local OnPlayerChange = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		OnPlayerChange = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = OnPlayerChange
	end
end
OnPlayerChange._internal = OnPlayerChange._internal or {}

local INTEREST_TYPE_ROOMS = "rooms"
local INTEREST_SCOPE_PLAYER = "onPlayerChangeRoom"
local HIGHLIGHT_COLOR = { 0.9, 0.7, 0.2 }

local function nowMillis()
	return Time.gameMillis() or math.floor(os.time() * 1000)
end

local function highlightRoomSquares(room, cooldownSeconds, highlightPref)
	if room == nil then
		return
	end
	local squares = SafeCall.safeCall(room, "getSquares")
	if squares == nil then
		return
	end

	local color = HIGHLIGHT_COLOR
	local alpha = 0.9
	if type(highlightPref) == "table" then
		color = highlightPref
		if type(color[4]) == "number" then
			alpha = color[4]
		end
	end
	local durationMs = Highlight.durationMsFromCooldownSeconds(cooldownSeconds)

	local count = JavaList.size(squares)
	if count <= 0 then
		return
	end
	for i = 1, count do
		local square = JavaList.get(squares, i)
		if square ~= nil then
			Highlight.highlightFloor(square, durationMs, { color = color, alpha = alpha })
		end
	end
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

local function emitWithCooldown(state, emitFn, record, nowMs, cooldownMs, onEmitFn)
	if type(emitFn) ~= "function" or type(record) ~= "table" or record.roomId == nil then
		return false
	end
	state.lastEmittedMs = state.lastEmittedMs or {}
	if not Cooldown.shouldEmit(state.lastEmittedMs, record.roomId, nowMs, cooldownMs) then
		return false
	end
	if type(onEmitFn) == "function" then
		pcall(onEmitFn, record)
	end
	emitFn(record)
	Cooldown.markEmitted(state.lastEmittedMs, record.roomId, nowMs)
	return true
end

local function ensureBuckets(ctx)
	local buckets = {}
	if ctx.interestRegistry and ctx.interestRegistry.effectiveBuckets then
		buckets = ctx.interestRegistry:effectiveBuckets(INTEREST_TYPE_ROOMS)
	elseif ctx.interestRegistry and ctx.interestRegistry.effective then
		local merged = ctx.interestRegistry:effective(INTEREST_TYPE_ROOMS)
		if merged then
			buckets = { { bucketKey = merged.bucketKey or "default", merged = merged } }
		end
	end
	return buckets
end

if OnPlayerChange.ensure == nil then
	--- Ensure the onPlayerChangeRoom flow runs when interest is declared.
	--- @param ctx table
	function OnPlayerChange.ensure(ctx)
		ctx = ctx or {}
		local state = ctx.state or {}
		ctx.state = state

		local listenerCfg = ctx.listenerCfg or {}
		local listenerEnabled = listenerCfg.enabled ~= false
		state._playerRoomBuckets = state._playerRoomBuckets or {}

		local activeBuckets = {}
		if listenerEnabled then
			for _, bucket in ipairs(ensureBuckets(ctx)) do
				local merged = bucket.merged
				if type(merged) == "table" and merged.scope == INTEREST_SCOPE_PLAYER then
					local bucketKey = bucket.bucketKey or INTEREST_SCOPE_PLAYER
					local target = merged.target
					local effective = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, INTEREST_TYPE_ROOMS, {
						label = INTEREST_SCOPE_PLAYER,
						allowDefault = false,
						log = Log,
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
			state._effectiveInterestByType = state._effectiveInterestByType or {}
			if type(state._effectiveInterestByType[INTEREST_TYPE_ROOMS]) == "table" then
				state._effectiveInterestByType[INTEREST_TYPE_ROOMS][INTEREST_SCOPE_PLAYER] = nil
			end
		end

		for key in pairs(state._playerRoomBuckets) do
			if not activeBuckets[key] then
				state._playerRoomBuckets[key] = nil
			end
		end

		for bucketKey, entry in pairs(activeBuckets) do
			local bucketState = state._playerRoomBuckets[bucketKey] or {}
			state._playerRoomBuckets[bucketKey] = bucketState

			local target = entry.target
			local player = Targets.resolvePlayer(target)
			if player == nil then
				bucketState.lastRoomRef = nil
				bucketState.lastRoomId = nil
			else
				local room = resolveRoomForPlayer(player)
				if room == nil then
					bucketState.lastRoomRef = nil
					bucketState.lastRoomId = nil
				elseif room ~= bucketState.lastRoomRef then
					local rooms = ctx.rooms
					if rooms and type(rooms.makeRoomRecord) == "function" then
						local record = rooms.makeRoomRecord(room, "player", ctx.recordOpts)
						if record and record.roomId ~= nil then
							if record.roomId ~= bucketState.lastRoomId then
								local cooldownMs = math.max(0, (tonumber(entry.effective.cooldown) or 0) * 1000)
								emitWithCooldown(bucketState, ctx.emitFn, record, nowMillis(), cooldownMs, function()
									if ctx.headless then
										return
									end
									local highlightPref = entry.effective.highlight
									if highlightPref == true or type(highlightPref) == "table" then
										highlightRoomSquares(room, entry.effective.cooldown, highlightPref)
									end
								end)
							end
							bucketState.lastRoomId = record.roomId
						end
					end
					bucketState.lastRoomRef = room
				end
			end
		end
	end
end

OnPlayerChange._internal.resolvePlayer = Targets.resolvePlayer
OnPlayerChange._internal.resolveRoomForPlayer = resolveRoomForPlayer
OnPlayerChange._internal.emitWithCooldown = emitWithCooldown

return OnPlayerChange
