-- smoke_squares.lua — console-friendly smoke test for WorldObserver squares.
-- Usage in PZ console:
--[[ @AI agent dont change this
   smoke = require("examples/smoke_squares")
   handle = smoke.start({ distinctSeconds = 20, withHelpers = true })
   handle:stop()
]]
--

local Log = require("LQR/util/log")
local Time = require("WorldObserver/helpers/time")
Log.setLevel("debug")

local SmokeSquares = {}

local function applyWorldObserverOverrides(opts)
	if not (opts and opts.probeOnly == true) then
		return
	end
	_G.WORLDOBSERVER_CONFIG_OVERRIDES = _G.WORLDOBSERVER_CONFIG_OVERRIDES or {}
	_G.WORLDOBSERVER_CONFIG_OVERRIDES.facts = _G.WORLDOBSERVER_CONFIG_OVERRIDES.facts or {}
	_G.WORLDOBSERVER_CONFIG_OVERRIDES.facts.squares = _G.WORLDOBSERVER_CONFIG_OVERRIDES.facts.squares or {}
	_G.WORLDOBSERVER_CONFIG_OVERRIDES.facts.squares.listener = { enabled = false }
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

-- Subscribe to the squares stream with optional filters and a heartbeat.
function SmokeSquares.start(opts)
	opts = opts or {}
	applyWorldObserverOverrides(opts)
	local WorldObserver = require("WorldObserver")

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
	local handles = {}

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
				local handle, reason = WorldObserver.highlight(isoSquare, highlightTtlMs, {
					alpha = opts.highlightProbeAlpha or 0.90,
				})
				if handle then
					handles[handle] = handle
				end
				probeHighlightStats.count = probeHighlightStats.count + 1
				if reason ~= nil then
					probeHighlightStats[reason] = (probeHighlightStats[reason] or 0) + 1
				end

				local nowMs = Time.gameMillis()
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
			local handle = WorldObserver.highlight(isoSquare, highlightTtlMs, {
				alpha = opts.highlightAlpha or 0.7,
			})
			if handle then
				handles[handle] = handle
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

			for h in pairs(handles) do
				if h and h.stop then
					pcall(h.stop)
				end
				handles[h] = nil
			end
		end,
	}
end

return SmokeSquares
