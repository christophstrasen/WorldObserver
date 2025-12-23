-- smoke_console_showcase.lua — console-friendly showcase with independent start/stop flows.
-- Usage in PZ console:
--[[ @AI agent dont change this
	show = require("examples/smoke_console_showcase")
	show.startRooms()
	show.startSquares()
	show.startZombies()
	show.startItems()
	show.startDeadBodies()
	show.stopDeadBodies()
	show.stoprooms()
	show.stopSquares()
	show.stopItems()
	show.stopZombies()
]]
--

local DoHighlight = false

local Log = require("LQR/util/log")
Log.setLevel("warn")

local Showcase = {}

local SQUARES_INTEREST_NEAR = {
	type = "squares",
	scope = "near",
	staleness = { desired = 2, tolerable = 5 },
	radius = { desired = 8, tolerable = 5 },
	cooldown = { desired = 5, tolerable = 10 },
	highlight = DoHighlight,
}

local SQUARES_INTEREST_VISION = {
	type = "squares",
	scope = "vision",
	staleness = { desired = 2, tolerable = 5 },
	radius = { desired = 20, tolerable = 10 },
	cooldown = { desired = 5, tolerable = 10 },
	highlight = DoHighlight,
}

local ZOMBIES_INTEREST = {
	type = "zombies",
	scope = "allLoaded",
	staleness = { desired = 2, tolerable = 4 },
	radius = { desired = 25, tolerable = 35 },
	zRange = { desired = 1, tolerable = 2 },
	cooldown = { desired = 2, tolerable = 4 },
	highlight = DoHighlight,
}

local ROOMS_INTEREST = {
	type = "rooms",
	scope = "allLoaded",
	staleness = { desired = 5, tolerable = 10 },
	cooldown = { desired = 10, tolerable = 20 },
	highlight = DoHighlight,
}

local ITEMS_INTEREST_PLAYER_SQUARE = {
	type = "items",
	scope = "playerSquare",
	cooldown = { desired = 0, tolerable = 0 },
	highlight = DoHighlight,
}

local ITEMS_INTEREST_NEAR = {
	type = "items",
	scope = "near",
	staleness = { desired = 2, tolerable = 6 },
	radius = { desired = 8, tolerable = 5 },
	cooldown = { desired = 5, tolerable = 10 },
	highlight = DoHighlight,
}

local ITEMS_INTEREST_VISION = {
	type = "items",
	scope = "vision",
	staleness = { desired = 5, tolerable = 10 },
	radius = { desired = 10, tolerable = 6 },
	cooldown = { desired = 10, tolerable = 20 },
	highlight = DoHighlight,
}

local DEAD_BODIES_INTEREST_PLAYER_SQUARE = {
	type = "deadBodies",
	scope = "playerSquare",
	cooldown = { desired = 0, tolerable = 0 },
	highlight = DoHighlight,
}

local DEAD_BODIES_INTEREST_NEAR = {
	type = "deadBodies",
	scope = "near",
	staleness = { desired = 2, tolerable = 6 },
	radius = { desired = 8, tolerable = 5 },
	cooldown = { desired = 5, tolerable = 10 },
	highlight = DoHighlight,
}

local DEAD_BODIES_INTEREST_VISION = {
	type = "deadBodies",
	scope = "vision",
	staleness = { desired = 5, tolerable = 10 },
	radius = { desired = 10, tolerable = 6 },
	cooldown = { desired = 10, tolerable = 20 },
	highlight = DoHighlight,
}

local squaresHandle = nil
local zombiesHandle = nil
local roomsHandle = nil
local itemsHandle = nil
local deadBodiesHandle = nil

function Showcase.startSquares()
	if squaresHandle then
		Showcase.stopSquares()
	end
	local WorldObserver = require("WorldObserver")
	local leases = {
		near = WorldObserver.factInterest:declare(
			"examples/smoke_console_showcase",
			"squares.near",
			SQUARES_INTEREST_NEAR
		),
		vision = WorldObserver.factInterest:declare(
			"examples/smoke_console_showcase",
			"squares.vision",
			SQUARES_INTEREST_VISION
		),
	}
	local stream = WorldObserver.observations:squares():distinct("square", 5)
	local sub = stream:subscribe(function(observation)
		local sq = observation.square
		Log.info(
			"[square] id=%s src=%s loc=(%s,%s,%s)",
			tostring(sq.squareId),
			tostring(sq.source),
			tostring(sq.x),
			tostring(sq.y),
			tostring(sq.z)
		)
	end)
	squaresHandle = { sub = sub, leases = leases }
	Log.info("[showcase] squares near+vision started")
end

function Showcase.stopSquares()
	if not squaresHandle then
		return
	end
	squaresHandle.sub:unsubscribe()
	for _, lease in pairs(squaresHandle.leases or {}) do
		if lease and lease.stop then
			lease:stop()
		end
	end
	squaresHandle = nil
	Log.info("[showcase] squares near+vision stopped")
end

function Showcase.startZombies()
	if zombiesHandle then
		Showcase.stopZombies()
	end
	local WorldObserver = require("WorldObserver")
	local lease =
		WorldObserver.factInterest:declare("examples/smoke_console_showcase", "zombies.allLoaded", ZOMBIES_INTEREST)
	local stream = WorldObserver.observations:zombies():distinct("zombie", 5)
	local sub = stream:subscribe(function(observation)
		local z = observation.zombie
		Log.info(
			"[zombie] id=%s online=%s loc=(%s,%s,%s) locomotion=%s target=%s",
			tostring(z.zombieId),
			tostring(z.zombieOnlineId),
			tostring(z.x),
			tostring(z.y),
			tostring(z.z),
			tostring(z.locomotion),
			tostring(z.targetKind)
		)
	end)
	zombiesHandle = { sub = sub, lease = lease }
	Log.info("[showcase] zombies allLoaded started")
end

function Showcase.stopZombies()
	if not zombiesHandle then
		return
	end
	zombiesHandle.sub:unsubscribe()
	zombiesHandle.lease:stop()
	zombiesHandle = nil
	Log.info("[showcase] zombies allLoaded stopped")
end

function Showcase.startRooms()
	if roomsHandle then
		Showcase.stopRooms()
	end
	local WorldObserver = require("WorldObserver")
	local lease =
		WorldObserver.factInterest:declare("examples/smoke_console_showcase", "rooms.allLoaded", ROOMS_INTEREST)
	local stream = WorldObserver.observations:rooms():distinct("room", 10)
	local sub = stream:subscribe(function(observation)
		local r = observation.room
		Log.info(
			"[room] id=%s type=%s building=%s water=%s bounds=%s",
			tostring(r.roomId),
			tostring(r.name),
			tostring(r.buildingId),
			tostring(r.hasWater),
			r.bounds
					and ("(%s,%s %sx%s)"):format(
						tostring(r.bounds.x),
						tostring(r.bounds.y),
						tostring(r.bounds.width),
						tostring(r.bounds.height)
					)
				or "n/a"
		)
	end)
	roomsHandle = { sub = sub, lease = lease }
	Log.info("[showcase] rooms allLoaded started")
end

function Showcase.stopRooms()
	if not roomsHandle then
		return
	end
	roomsHandle.sub:unsubscribe()
	roomsHandle.lease:stop()
	roomsHandle = nil
	Log.info("[showcase] rooms allLoaded stopped")
end

-- Console sugar: keep the lower-case variant used in the usage snippet working.
Showcase.stoprooms = Showcase.stopRooms

function Showcase.startItems()
	if itemsHandle then
		Showcase.stopItems()
	end
	local WorldObserver = require("WorldObserver")
	local leases = {
		playerSquare = WorldObserver.factInterest:declare(
			"examples/smoke_console_showcase",
			"items.playerSquare",
			ITEMS_INTEREST_PLAYER_SQUARE
		),
		near = WorldObserver.factInterest:declare("examples/smoke_console_showcase", "items.near", ITEMS_INTEREST_NEAR),
		vision = WorldObserver.factInterest:declare(
			"examples/smoke_console_showcase",
			"items.vision",
			ITEMS_INTEREST_VISION
		),
	}
	local stream = WorldObserver.observations:items():distinct("item", 10)
	local sub = stream:subscribe(function(observation)
		local item = observation.item
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
	itemsHandle = { sub = sub, leases = leases }
	Log.info("[showcase] items started")
end

function Showcase.stopItems()
	if not itemsHandle then
		return
	end
	itemsHandle.sub:unsubscribe()
	for _, lease in pairs(itemsHandle.leases or {}) do
		if lease and lease.stop then
			pcall(lease.stop)
		end
	end
	itemsHandle = nil
	Log.info("[showcase] items stopped")
end

function Showcase.startDeadBodies()
	if deadBodiesHandle then
		Showcase.stopDeadBodies()
	end
	local WorldObserver = require("WorldObserver")
	local leases = {
		playerSquare = WorldObserver.factInterest:declare(
			"examples/smoke_console_showcase",
			"deadBodies.playerSquare",
			DEAD_BODIES_INTEREST_PLAYER_SQUARE
		),
		near = WorldObserver.factInterest:declare(
			"examples/smoke_console_showcase",
			"deadBodies.near",
			DEAD_BODIES_INTEREST_NEAR
		),
		vision = WorldObserver.factInterest:declare(
			"examples/smoke_console_showcase",
			"deadBodies.vision",
			DEAD_BODIES_INTEREST_VISION
		),
	}
	local stream = WorldObserver.observations:deadBodies():distinct("deadBody", 10)
	local sub = stream:subscribe(function(observation)
		local body = observation.deadBody
		Log.info(
			"[deadBody] id=%s loc=(%s,%s,%s) square=%s source=%s",
			tostring(body.deadBodyId),
			tostring(body.x),
			tostring(body.y),
			tostring(body.z),
			tostring(body.squareId),
			tostring(body.source)
		)
	end)
	deadBodiesHandle = { sub = sub, leases = leases }
	Log.info("[showcase] dead bodies started")
end

function Showcase.stopDeadBodies()
	if not deadBodiesHandle then
		return
	end
	deadBodiesHandle.sub:unsubscribe()
	for _, lease in pairs(deadBodiesHandle.leases or {}) do
		if lease and lease.stop then
			pcall(lease.stop)
		end
	end
	deadBodiesHandle = nil
	Log.info("[showcase] dead bodies stopped")
end

return Showcase
