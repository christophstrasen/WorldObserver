-- smoke_squares.lua — console-friendly smoke test for WorldObserver squares.
-- Usage in PZ console:
--[[ @AI agent dont change this
   smoke = require("examples/smoke_squares")
   handle = smoke.start({ distinctSeconds = 2, withHelpers = true })
   handle:stop()
]]
--

local Log = require("LQR/util/log")
Log.setLevel("info")

local SmokeSquares = {}

local function nowMillis()
	local gameTime = _G.getGameTime
	if type(gameTime) == "function" then
		local ok, timeObj = pcall(gameTime)
		if ok and timeObj and type(timeObj.getTimeCalendar) == "function" then
			local okCal, cal = pcall(timeObj.getTimeCalendar, timeObj)
			if okCal and cal and type(cal.getTimeInMillis) == "function" then
				local okMs, ms = pcall(cal.getTimeInMillis, cal)
				if okMs and ms then
					return ms
				end
			end
		end
	end
	if type(os.time) == "function" then
		return os.time() * 1000
	end
	return nil
end

local function highlightSquareFloor(isoSquare, alpha)
	if isoSquare == nil or type(isoSquare.getFloor) ~= "function" then
		return nil, "noIsoSquare"
	end

	local okFloor, floor = pcall(isoSquare.getFloor, isoSquare)
	if not okFloor or floor == nil then
		return nil, "noFloor"
	end

	local a = alpha
	if type(a) ~= "number" then
		a = 0.7
	end

	-- Best-effort highlighting; keep it resilient to PZ API differences.
	local hasColor = type(floor.setHighlightColor) == "function"
	local hasHighlighted = type(floor.setHighlighted) == "function"

	if type(floor.setHighlightColor) == "function" then
		pcall(floor.setHighlightColor, floor, 0.2, 0.5, 1.0, a)
	end
	if type(floor.setHighlighted) == "function" then
		-- In PZ, setHighlighted(enabled, doOutline) is common for IsoObject.
		local ok = pcall(floor.setHighlighted, floor, true, false)
		if not ok then
			pcall(floor.setHighlighted, floor, true)
		end
	end

	if not hasHighlighted then
		return floor, "noSetHighlighted"
	end
	if not hasColor then
		return floor, "noSetHighlightColor"
	end
	return floor, nil
end

local function getObservationIsoSquare(WorldObserver, squareRecord)
	if type(squareRecord) ~= "table" then
		return nil
	end

	local isoSquare = squareRecord.IsoSquare
	if isoSquare ~= nil then
		return isoSquare
	end

	local helpers = WorldObserver and WorldObserver.helpers and WorldObserver.helpers.square
	if helpers and helpers.record and helpers.record.getIsoSquare then
		return helpers.record.getIsoSquare(squareRecord)
	end

	return nil
end

local function cleanupExpiredHighlights(nowMs, ttlMs, highlightedFloors, highlightedAtMs)
	if type(nowMs) ~= "number" or type(ttlMs) ~= "number" or ttlMs <= 0 then
		return
	end
	if type(highlightedAtMs) ~= "table" or type(highlightedFloors) ~= "table" then
		return
	end

	for floor, startedAtMs in pairs(highlightedAtMs) do
		if type(startedAtMs) == "number" and (nowMs - startedAtMs) >= ttlMs then
			if floor and type(floor.setHighlighted) == "function" then
				local ok = pcall(floor.setHighlighted, floor, false, false)
				if not ok then
					pcall(floor.setHighlighted, floor, false)
				end
			end
			highlightedAtMs[floor] = nil
			highlightedFloors[floor] = nil
		end
	end
end

local function refreshHighlights(highlightedFloors)
	if type(highlightedFloors) ~= "table" then
		return
	end
	for floor, alpha in pairs(highlightedFloors) do
		if floor ~= nil then
			local a = alpha
			if type(a) ~= "number" then
				a = 0.7
			end
			if type(floor.setHighlightColor) == "function" then
				pcall(floor.setHighlightColor, floor, 0.2, 0.5, 1.0, a)
			end
			if type(floor.setHighlighted) == "function" then
				local ok = pcall(floor.setHighlighted, floor, true, false)
				if not ok then
					pcall(floor.setHighlighted, floor, true)
				end
			end
		end
	end
end

-- Subscribe to the squares stream with optional filters and a heartbeat.
function SmokeSquares.start(opts)
	local WorldObserver = require("WorldObserver")
	opts = opts or {}

	-- Build stream.
	local stream = WorldObserver.observations.squares()
	if opts.distinctSeconds then
		stream = stream:distinct("square", opts.distinctSeconds)
	end
	if opts.withHelpers then
		-- Example: only keep squares that need cleaning.
		stream = stream:whereSquareNeedsCleaning()
	end

	Log.info(
		"[smoke] subscribing to squares (distinctSeconds=%s, withHelpers=%s)",
		tostring(opts.distinctSeconds),
		tostring(opts.withHelpers)
	)

	-- Subscribe and print rows.
	local receivedCount = 0
	local highlightedFloors = {}
	local highlightedAtMs = {}
	local highlightTtlMs = opts.highlightTtlMs
	if highlightTtlMs == nil and type(opts.highlightTtlSeconds) == "number" then
		highlightTtlMs = opts.highlightTtlSeconds * 1000
	end
	if highlightTtlMs == nil then
		highlightTtlMs = 5000
	end
	local probeHighlightStats = {
		count = 0,
		noIsoSquare = 0,
		noFloor = 0,
		noSetHighlighted = 0,
		noSetHighlightColor = 0,
		lastReportMs = nil,
	}

	-- In-engine, highlight flags can be transient; re-apply them each tick while the entry is alive.
	local onTickFn = nil
	do
		local events = _G.Events
		local tick = events and events.OnTick
		if tick and type(tick.Add) == "function" and type(tick.Remove) == "function" then
			onTickFn = function()
				local nowMs = nowMillis()
				cleanupExpiredHighlights(nowMs, highlightTtlMs, highlightedFloors, highlightedAtMs)
				refreshHighlights(highlightedFloors)
			end
			tick.Add(onTickFn)
		end
	end

	-- Highlight all squares that the probe lane emits, regardless of whether downstream helpers filter them out.
	-- This makes it obvious what the probe is scanning each tick.
	local probeHighlightSubscription = nil
	if opts.highlightProbeHits ~= false then
		probeHighlightSubscription = WorldObserver.observations
			.squares()
			:filter(function(observation)
				local square = observation and observation.square
				return type(square) == "table" and square.source == "probe"
			end)
			:subscribe(function(observation)
				local square = observation and observation.square
				local isoSquare = getObservationIsoSquare(WorldObserver, square)
				local floor, reason = highlightSquareFloor(isoSquare, opts.highlightProbeAlpha or 0.90)
				local nowMs = nowMillis()
				cleanupExpiredHighlights(nowMs, highlightTtlMs, highlightedFloors, highlightedAtMs)
				if floor ~= nil then
					highlightedFloors[floor] = opts.highlightProbeAlpha or 0.90
					highlightedAtMs[floor] = nowMs
				end
				probeHighlightStats.count = probeHighlightStats.count + 1
				if reason ~= nil then
					probeHighlightStats[reason] = (probeHighlightStats[reason] or 0) + 1
				end

				if type(nowMs) == "number" then
					local last = probeHighlightStats.lastReportMs
					if last == nil or (nowMs - last) >= 5000 then
						probeHighlightStats.lastReportMs = nowMs
						Log.info(
							"[smoke] probe highlight stats hits=%s noIsoSquare=%s noFloor=%s noSetHighlighted=%s noSetHighlightColor=%s",
							tostring(probeHighlightStats.count),
							tostring(probeHighlightStats.noIsoSquare),
							tostring(probeHighlightStats.noFloor),
							tostring(probeHighlightStats.noSetHighlighted),
							tostring(probeHighlightStats.noSetHighlightColor)
						)
					end
				end
			end)
	end

	local subscription = stream:subscribe(function(observation)
		receivedCount = receivedCount + 1
		if opts.highlightFloors ~= false and type(observation) == "table" and type(observation.square) == "table" then
			local isoSquare = getObservationIsoSquare(WorldObserver, observation.square)
			local nowMs = nowMillis()
			cleanupExpiredHighlights(nowMs, highlightTtlMs, highlightedFloors, highlightedAtMs)
			local floor = highlightSquareFloor(isoSquare, opts.highlightAlpha)
			if floor ~= nil then
				highlightedFloors[floor] = opts.highlightAlpha or 0.7
				highlightedAtMs[floor] = nowMs
			end
		end
		WorldObserver.debug.printObservation(
			observation,
			{ prefix = "[square ] YUK Dirty or dead stuff on the ground!" }
		)
	end)

	return {
		stop = function()
			if subscription and subscription.unsubscribe then
				subscription:unsubscribe()
				Log.info("[smoke] squares subscription stopped")
			end
			if probeHighlightSubscription and probeHighlightSubscription.unsubscribe then
				probeHighlightSubscription:unsubscribe()
			end
			do
				local events = _G.Events
				local tick = events and events.OnTick
				if onTickFn and tick and type(tick.Remove) == "function" then
					pcall(tick.Remove, tick, onTickFn)
				end
			end

			for floor in pairs(highlightedFloors) do
				if floor and type(floor.setHighlighted) == "function" then
					local ok = pcall(floor.setHighlighted, floor, false, false)
					if not ok then
						pcall(floor.setHighlighted, floor, false)
					end
				end
			end
		end,
	}
end

return SmokeSquares
