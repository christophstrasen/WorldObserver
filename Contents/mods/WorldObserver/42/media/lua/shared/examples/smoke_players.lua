-- smoke_players.lua — console-friendly smoke test for WorldObserver players.
-- Usage in PZ console:
--[[ @AI agent dont change this
	smokep = require("examples/smoke_players")
	handlep = smokep.start({
		scope = "onPlayerMove",
		distinctSeconds = 0.2,
		cooldown = 0.2,
	})
	handlep:stop()
]]
--

local Log = require("LQR/util/log")
Log.setLevel("info")

local SmokePlayers = {}

function SmokePlayers.start(opts)
	opts = opts or {}
	local WorldObserver = require("WorldObserver")
	if type(Log) == "table" and type(Log.setLevel) == "function" then
		pcall(Log.setLevel, opts.logLevel or "info")
	end

	local scope = opts.scope or "onPlayerMove"
	local modId = opts.modId or "examples/smoke_players"
	local cooldownSeconds = tonumber(opts.cooldown) or 0.2

	local interest = WorldObserver.factInterest:declare(modId, scope, {
		type = "players",
		scope = scope,
		cooldown = { desired = cooldownSeconds, tolerable = cooldownSeconds * 2 },
		highlight = true,
	})

	local stream = WorldObserver.observations:players()
	if opts.distinctSeconds then
		stream = stream:distinct("player", opts.distinctSeconds)
	end
	Log.info(
		"[smoke] subscribing to players (scope=%s distinctSeconds=%s cooldown=%s)",
		tostring(scope),
		tostring(opts.distinctSeconds),
		tostring(cooldownSeconds)
	)

	local subscription = stream:subscribe(function(observation)
		local p = observation.player
		if type(p) ~= "table" then
			return
		end

		Log.info(
			"[player] key=%s steamId=%s onlineId=%s playerNum=%s tile=%s room=%s source=%s scope=%s",
			tostring(p.playerKey),
			tostring(p.steamId),
			tostring(p.onlineId),
			tostring(p.playerNum),
			tostring(p.tileLocation),
			tostring(p.roomLocation),
			tostring(p.source),
			tostring(p.scope)
		)
	end)

	return {
		stop = function()
			if subscription and subscription.unsubscribe then
				subscription:unsubscribe()
				Log.info("[smoke] players subscription stopped")
			end
			if interest and interest.stop then
				pcall(interest.stop)
			end
		end,
	}
end

return SmokePlayers
