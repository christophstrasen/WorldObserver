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
	if not opts then
		return
	end
	_G.WORLDOBSERVER_CONFIG_OVERRIDES = _G.WORLDOBSERVER_CONFIG_OVERRIDES or {}
	_G.WORLDOBSERVER_CONFIG_OVERRIDES.facts = _G.WORLDOBSERVER_CONFIG_OVERRIDES.facts or {}
	_G.WORLDOBSERVER_CONFIG_OVERRIDES.facts.squares = _G.WORLDOBSERVER_CONFIG_OVERRIDES.facts.squares or {}
	if opts.probeOnly == true or opts.noListener == true then
		_G.WORLDOBSERVER_CONFIG_OVERRIDES.facts.squares.listener = { enabled = false }
	end
	if opts.listenerOnly == true or opts.noProbe == true then
		_G.WORLDOBSERVER_CONFIG_OVERRIDES.facts.squares.probe = { enabled = false }
	end
end

-- Subscribe to the squares stream with optional filters and a heartbeat.
function SmokeSquares.start(opts)
	opts = opts or {}
	applyWorldObserverOverrides(opts)
	local WorldObserver = require("WorldObserver")

	-- Declare upstream interest (few lines, easy to tweak).
	local modId = opts.modId or "examples/smoke_squares"
	local declareInterest = opts.declareInterest ~= false
	local withOnLoad = (opts.withOnLoad ~= false)
	local withNear = (opts.withNear == true)
	local withVision = (opts.withVision == true)
	local highlightProbes = (opts.highlightProbes == true)
	local highlightOnLoad = (opts.highlightOnLoad == true)

	local onLoadLease = nil
	local nearLease = nil
	local visionLease = nil

	if declareInterest and withOnLoad then
		onLoadLease = WorldObserver.factInterest:declare(modId, "onLoad", opts.interestOnLoad or {
			type = "squares.onLoad",
			cooldown = { desired = 600, tolerable = 1200 },
			highlight = highlightOnLoad,
		})
	end
	if declareInterest and withNear then
		nearLease = WorldObserver.factInterest:declare(modId, "near", opts.interestNear or {
			type = "squares.nearPlayer",
			staleness = { desired = 2, tolerable = 5 },
			radius = { desired = 10, tolerable = 5 },
			cooldown = { desired = 5, tolerable = 20 },
			highlight = highlightProbes,
		})
	end
	if declareInterest and withVision then
		visionLease = WorldObserver.factInterest:declare(modId, "vision", opts.interestVision or {
			type = "squares.vision",
			staleness = { desired = 10, tolerable = 20 },
			radius = { desired = 25, tolerable = 15 },
			cooldown = { desired = 10, tolerable = 60 },
			highlight = highlightProbes,
		})
	end

	-- Build stream.
	local stream = WorldObserver.observations.squares()
	local SquareHelper = WorldObserver.helpers.square.record
	if opts.distinctSeconds then
		stream = stream:distinct("square", opts.distinctSeconds)
	end
	if opts.withHelpers then
		-- Example: only keep squares with a corpse.
		stream = stream:whereSquare(SquareHelper.squareHasCorpse)
	end

	Log.info(
		"[smoke] subscribing to squares (declareInterest=%s onLoad=%s near=%s vision=%s distinctSeconds=%s withHelpers=%s)",
		tostring(declareInterest),
		tostring(withOnLoad),
		tostring(withNear),
		tostring(withVision),
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
		if opts.highlightFloors == true and type(observation) == "table" and type(observation.square) == "table" then
			local isoGridSquare = observation.square.IsoGridSquare
			local handle = WorldObserver.highlight(isoGridSquare, highlightTtlMs, {
				alpha = opts.highlightAlpha or 0.7,
			})
			if handle then
				handles[handle] = handle
			end
		end
		local prefix = opts.withHelpers and "[square ] corpse present" or "[square ] observed"
		--local prefix = ""
		WorldObserver.debug.printObservation(observation, { prefix = prefix })
	end)

	return {
		stop = function()
			if subscription and subscription.unsubscribe then
				subscription:unsubscribe()
				Log.info("[smoke] squares subscription stopped")
			end
			if onLoadLease and onLoadLease.stop then
				pcall(onLoadLease.stop)
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
