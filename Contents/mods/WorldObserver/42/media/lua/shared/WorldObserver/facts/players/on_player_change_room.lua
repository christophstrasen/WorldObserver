-- facts/players/on_player_change_room.lua -- emits player records when the player changes rooms.
local Highlight = require("WorldObserver/helpers/highlight")
local SquareHelpers = require("WorldObserver/helpers/square")
local PlayerRoomChange = require("WorldObserver/facts/sensors/player_room_change")

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

local INTEREST_TYPE = "players"
local INTEREST_SCOPE = "onPlayerChangeRoom"
local CONSUMER_ID = "players.onPlayerChangeRoom"

local function highlightPlayerSquare(record, effective, highlightPref)
	if record == nil then
		return
	end
	local square = record.IsoGridSquare
	if square == nil then
		return
	end
	local durationMs = Highlight.durationMsFromEffectiveCadence(effective)
	if durationMs <= 0 then
		return
	end
	local color, alpha = Highlight.resolveColorAlpha(highlightPref, nil, 0.7)
	SquareHelpers.highlight(square, durationMs, { color = color, alpha = alpha })
end

local function makePlayerRecord(ctx, player)
	local players = ctx and ctx.players
	if not (players and type(players.makePlayerRecord) == "function") then
		return nil
	end
	return players.makePlayerRecord(player, "event", { scope = INTEREST_SCOPE })
end

-- Patch seam: define only when nil so mods can override by reassigning `OnPlayerChange.register`.
if OnPlayerChange.register == nil then
	--- Register the shared player-room-change sensor for players.
	--- @param ctx table
	function OnPlayerChange.register(ctx)
		ctx = ctx or {}
		local listenerCfg = ctx.listenerCfg or {}
		local enabled = listenerCfg.enabled ~= false

		return PlayerRoomChange.registerConsumer(CONSUMER_ID, {
			interestType = INTEREST_TYPE,
			scope = INTEREST_SCOPE,
			emitFn = ctx.emitFn,
			makeRecord = function(player, _room)
				return makePlayerRecord(ctx, player)
			end,
			cooldownKey = function(record)
				return record and record.roomLocation or nil
			end,
			roomKey = function(record)
				return record and record.roomLocation or nil
			end,
			onEmit = function(record, effective)
				if ctx.headless then
					return
				end
				local highlightPref = effective and effective.highlight or nil
				if highlightPref == true or type(highlightPref) == "table" then
					highlightPlayerSquare(record, effective, highlightPref)
				end
			end,
			runtime = ctx.runtime,
			interestRegistry = ctx.interestRegistry,
			headless = ctx.headless == true,
			factRegistry = ctx.factRegistry,
			enabled = enabled,
		})
	end
end

-- Patch seam: define only when nil so mods can override by reassigning `OnPlayerChange.unregister`.
if OnPlayerChange.unregister == nil then
	--- Unregister the shared player-room-change sensor for players.
	function OnPlayerChange.unregister()
		return PlayerRoomChange.unregisterConsumer(CONSUMER_ID)
	end
end

OnPlayerChange._internal.highlightPlayerSquare = highlightPlayerSquare

return OnPlayerChange
