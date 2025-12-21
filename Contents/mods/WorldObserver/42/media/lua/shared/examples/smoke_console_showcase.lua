-- smoke_console_showcase.lua — console-friendly showcase with independent start/stop flows.
-- Usage in PZ console:
--[[ @AI agent dont change this
	show = require("examples/smoke_console_showcase")
	show.startRooms()
	show.stoprooms()
	show.startSquares()
	show.stopSquares()
	show.startZombies()
	show.stopZombies()
]]
--

local Log = require("LQR/util/log")
Log.setLevel("info")

local Showcase = {}

local SQUARES_INTEREST = {
	type = "squares",
	scope = "vision",
	staleness = { desired = 2, tolerable = 5 },
	radius = { desired = 20, tolerable = 10 },
	cooldown = { desired = 5, tolerable = 10 },
	highlight = true,
}

local ZOMBIES_INTEREST = {
	type = "zombies",
	scope = "allLoaded",
	staleness = { desired = 2, tolerable = 4 },
	radius = { desired = 25, tolerable = 35 },
	zRange = { desired = 1, tolerable = 2 },
	cooldown = { desired = 2, tolerable = 4 },
	highlight = true,
}

local ROOMS_INTEREST = {
	type = "rooms",
	scope = "allLoaded",
	staleness = { desired = 5, tolerable = 10 },
	cooldown = { desired = 10, tolerable = 20 },
	--highlight = true,
	highlight = { 0.9, 0.7, 0.2, debugRoomId = "1.06962295036315E16" },
}

local squaresHandle = nil
local zombiesHandle = nil
local roomsHandle = nil

function Showcase.startSquares()
	if squaresHandle then
		Showcase.stopSquares()
	end
	local WorldObserver = require("WorldObserver")
	local lease =
		WorldObserver.factInterest:declare("examples/smoke_console_showcase", "squares.vision", SQUARES_INTEREST)
	local stream = WorldObserver.observations.squares():distinct("square", 5)
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
	squaresHandle = { sub = sub, lease = lease }
	Log.info("[showcase] squares vision started")
end

function Showcase.stopSquares()
	if not squaresHandle then
		return
	end
	squaresHandle.sub:unsubscribe()
	squaresHandle.lease:stop()
	squaresHandle = nil
	Log.info("[showcase] squares vision stopped")
end

function Showcase.startZombies()
	if zombiesHandle then
		Showcase.stopZombies()
	end
	local WorldObserver = require("WorldObserver")
	local lease =
		WorldObserver.factInterest:declare("examples/smoke_console_showcase", "zombies.allLoaded", ZOMBIES_INTEREST)
	local stream = WorldObserver.observations.zombies():distinct("zombie", 5)
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
	local stream = WorldObserver.observations.rooms():distinct("room", 10)
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

return Showcase
