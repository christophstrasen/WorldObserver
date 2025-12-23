-- smoke_items.lua — console-friendly smoke test for WorldObserver items.
-- Usage in PZ console:
--[[ @AI agent dont change this
	_G.WORLDOBSERVER_CONFIG_OVERRIDES = { facts = { items = { probe = { infoLogEveryMs = 500, logEachSweep = true } } } }
	smokei = require("examples/smoke_items")
	handles = smokei.start({ distinctSeconds = 10 })
	handles:stop()
]]
--
-- Notes:
-- - Items are world items on the ground + direct container contents (depth=1).
-- - playerSquare emits only for the square under the player.

local Log = require("LQR/util/log")
Log.setLevel("info")

local SmokeItems = {}

local INTEREST_PLAYER_SQUARE = {
	type = "items",
	scope = "playerSquare",
	cooldown = { desired = 0, tolerable = 0 },
	highlight = true,
}

local INTEREST_NEAR = {
	type = "items",
	scope = "near",
	staleness = { desired = 2, tolerable = 6 },
	radius = { desired = 8, tolerable = 5 },
	cooldown = { desired = 5, tolerable = 10 },
	highlight = true,
}

local INTEREST_VISION = {
	type = "items",
	scope = "vision",
	staleness = { desired = 5, tolerable = 10 },
	radius = { desired = 10, tolerable = 6 },
	cooldown = { desired = 10, tolerable = 20 },
	highlight = true,
}

local LEASE_OPTS = {
	ttlSeconds = 60 * 60,
}

function SmokeItems.start(opts)
	opts = opts or {}
	local WorldObserver = require("WorldObserver")

	local modId = opts.modId or "examples/smoke_items"
	local leases = {}

	if opts.playerSquare ~= false then
		leases.playerSquare =
			WorldObserver.factInterest:declare(modId, "playerSquare", INTEREST_PLAYER_SQUARE, LEASE_OPTS)
	end
	if opts.near ~= false then
		leases.near = WorldObserver.factInterest:declare(modId, "near", INTEREST_NEAR, LEASE_OPTS)
	end
	if opts.vision ~= false then
		leases.vision = WorldObserver.factInterest:declare(modId, "vision", INTEREST_VISION, LEASE_OPTS)
	end

	local stream = WorldObserver.observations:items()
	if opts.distinctSeconds then
		stream = stream:distinct("item", opts.distinctSeconds)
	end
	if opts.itemType then
		stream = stream:itemTypeIs(opts.itemType)
	end
	if opts.itemFullType then
		stream = stream:itemFullTypeIs(opts.itemFullType)
	end
	if opts.onlyContainerItems == true then
		stream = stream:itemFilter(function(itemRecord)
			return type(itemRecord) == "table" and itemRecord.containerItemId ~= nil
		end)
	end

	Log.info(
		"[smoke] subscribing to items (distinctSeconds=%s, playerSquare=%s, near=%s, vision=%s)",
		tostring(opts.distinctSeconds),
		tostring(opts.playerSquare ~= false),
		tostring(opts.near ~= false),
		tostring(opts.vision ~= false)
	)

	local subscription = stream:subscribe(function(observation)
		local item = observation.item
		if type(item) ~= "table" then
			return
		end

		Log.info(
			"[item] id=%s type=%s full=%s loc=(%s,%s,%s) square=%s container=%s source=%s",
			tostring(item.itemId),
			tostring(item.itemType),
			tostring(item.itemFullType),
			tostring(item.x),
			tostring(item.y),
			tostring(item.z),
			tostring(item.squareId),
			tostring(item.containerItemId),
			tostring(item.source)
		)
	end)

	return {
		stop = function()
			if subscription and subscription.unsubscribe then
				subscription:unsubscribe()
				Log.info("[smoke] items subscription stopped")
			end
			for _, lease in pairs(leases) do
				if lease and lease.stop then
					pcall(lease.stop)
				end
			end
		end,
	}
end

return SmokeItems
