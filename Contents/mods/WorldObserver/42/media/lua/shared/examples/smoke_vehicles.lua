-- smoke_vehicles.lua — console-friendly smoke test for WorldObserver vehicles.
-- Usage in PZ console:
--[[ @AI agent dont change this
	smokev = require("examples/smoke_vehicles")
	handlev = smokev.start({
		distinctSeconds = 10,
		staleness = 5,
		cooldown = 10,
	})
	handlev:stop()
]]
--

local Log = require("LQR/util/log")
Log.setLevel("info")

local SmokeVehicles = {}

function SmokeVehicles.start(opts)
	opts = opts or {}
	local WorldObserver = require("WorldObserver")
	if type(Log) == "table" and type(Log.setLevel) == "function" then
		pcall(Log.setLevel, opts.logLevel or "info")
	end

	local modId = opts.modId or "examples/smoke_vehicles"
	local interest = WorldObserver.factInterest:declare(modId, "allLoaded", {
		type = "vehicles",
		scope = "allLoaded",
		staleness = { desired = opts.staleness or 5, tolerable = (opts.staleness or 5) * 2 },
		cooldown = { desired = opts.cooldown or 10, tolerable = (opts.cooldown or 10) * 2 },
		highlight = true,
	})

	local stream = WorldObserver.observations:vehicles()
	if opts.distinctSeconds then
		stream = stream:distinct("vehicle", opts.distinctSeconds)
	end
	Log.info(
		"[smoke] subscribing to vehicles (distinctSeconds=%s, staleness=%s, cooldown=%s)",
		tostring(opts.distinctSeconds),
		tostring(opts.staleness),
		tostring(opts.cooldown)
	)

	local subscription = stream:subscribe(function(observation)
		local v = observation.vehicle
		if type(v) ~= "table" then
			return
		end

		Log.info(
			"[vehicle] sqlId=%s vehicleId=%s script=%s tile=(%s,%s,%s) source=%s",
			tostring(v.sqlId),
			tostring(v.vehicleId),
			tostring(v.scriptName),
			tostring(v.tileX),
			tostring(v.tileY),
			tostring(v.tileZ),
			tostring(v.source)
		)
	end)

	return {
		stop = function()
			if subscription and subscription.unsubscribe then
				subscription:unsubscribe()
				Log.info("[smoke] vehicles subscription stopped")
			end
			if interest and interest.stop then
				pcall(interest.stop)
			end
		end,
	}
end

return SmokeVehicles
