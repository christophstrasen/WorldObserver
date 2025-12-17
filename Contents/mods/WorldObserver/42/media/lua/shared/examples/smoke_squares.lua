-- smoke_squares.lua — console-friendly smoke test for WorldObserver squares.
-- Usage in PZ console:
--[[ @AI agent dont change this
	_G.WORLDOBSERVER_CONFIG_OVERRIDES = { facts = { squares = { probe = { infoLogEveryMs = 500, logEachSweep = true } } } }
   smoke = require("examples/smoke_squares")
   handle = smoke.start({ distinctSeconds = 20, withHelpers = true })
   handle:stop()
]]
--

local Log = require("LQR/util/log")
local Time = require("WorldObserver/helpers/time")
Log.setLevel("info")

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

-- Subscribe to the squares stream with optional filters and a heartbeat.
function SmokeSquares.start(opts)
	opts = opts or {}
	applyWorldObserverOverrides(opts)
	local WorldObserver = require("WorldObserver")

	-- Declare upstream interest (few lines, easy to tweak).
	local modId = opts.modId or "examples/smoke_squares"
	local nearLease = WorldObserver.factInterest:declare(modId, "near", opts.interestNear or {
		type = "squares.nearPlayer",
		staleness = { desired = 2, tolerable = 5 },
		radius = { desired = 10, tolerable = 5 },
		cooldown = { desired = 5, tolerable = 20 },
		highlight = true,
	})
	local visionLease = WorldObserver.factInterest:declare(modId, "vision", opts.interestVision or {
		type = "squares.vision",
		staleness = { desired = 10, tolerable = 20 },
		radius = { desired = 25, tolerable = 15 },
		cooldown = { desired = 10, tolerable = 60 },
		highlight = true,
	})
	--

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
	local handles = {}

	local subscription = stream:subscribe(function(observation)
		receivedCount = receivedCount + 1
		if opts.highlightFloors ~= false and type(observation) == "table" and type(observation.square) == "table" then
			local isoSquare = observation.square.IsoSquare
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
			if nearLease and nearLease.stop then
				pcall(nearLease.stop)
			end
			if visionLease and visionLease.stop then
				pcall(visionLease.stop)
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
