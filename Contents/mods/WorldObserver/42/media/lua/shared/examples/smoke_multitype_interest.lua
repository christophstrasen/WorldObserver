-- smoke_multitype_interest.lua — console-friendly smoke for multi-type factInterest fan-out.
-- Usage in PZ console:
--[[ @AI agent dont change this
	smoke = require("examples/smoke_multitype_interest")
	handle = smoke.start({
		scope = "onPlayerChangeRoom",
		cooldown = 0,
	})
	handle:stop()
]]
--

local Log = require("DREAMBase/log")
Log.setLevel("info")

local SmokeMultiType = {}

function SmokeMultiType.start(opts)
	opts = opts or {}
	local WorldObserver = require("WorldObserver")
	if type(Log) == "table" and type(Log.setLevel) == "function" then
		pcall(Log.setLevel, opts.logLevel or "info")
	end

	local modId = opts.modId or "examples/smoke_multitype_interest"
	local scope = opts.scope or "onPlayerChangeRoom"
	local cooldownSeconds = tonumber(opts.cooldown) or 0

	local lease = WorldObserver.factInterest:declare(modId, "roomAndPlayer", {
		type = { "rooms", "players" },
		scope = scope,
		cooldown = { desired = cooldownSeconds },
		highlight = true,
	})

	Log.info(
		"[smoke] multi-type interest scope=%s cooldown=%s",
		tostring(scope),
		tostring(cooldownSeconds)
	)

	local playerSub = WorldObserver.observations:players():subscribe(function(observation)
		local player = observation.player
		if type(player) ~= "table" then
			return
		end

		Log.info(
			"[player] key=%s room=%s name=%s source=%s",
			tostring(player.playerKey),
			tostring(player.roomLocation),
			tostring(player.roomName),
			tostring(player.source)
		)
	end)

	local roomSub = WorldObserver.observations:rooms():subscribe(function(observation)
		local room = observation.room
		if type(room) ~= "table" then
			return
		end

		Log.info(
			"[room] id=%s room=%s name=%s source=%s",
			tostring(room.roomId),
			tostring(room.roomLocation),
			tostring(room.name),
			tostring(room.source)
		)
	end)

	return {
		stop = function()
			if playerSub and playerSub.unsubscribe then
				playerSub:unsubscribe()
				Log.info("[smoke] players subscription stopped")
			end
			if roomSub and roomSub.unsubscribe then
				roomSub:unsubscribe()
				Log.info("[smoke] rooms subscription stopped")
			end
			if lease and lease.stop then
				pcall(lease.stop)
			end
		end,
	}
end

return SmokeMultiType
