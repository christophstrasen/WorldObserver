-- facts/squares.lua -- square fact plan (balanced strategy): listeners + near-player probe to emit SquareObservation facts.
local Log = require("LQR/util/log").withTag("WO.FACTS.squares")

local Squares = {}

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
	-- Headless/tests: fall back to wall-clock if the game clock is missing.
	return math.floor(os.time() * 1000)
end

local function coordOf(square, getterName)
	if square and type(square[getterName]) == "function" then
		local ok, value = pcall(square[getterName], square)
		if ok then
			return value
		end
	end
	return nil
end

local function deriveSquareId(square, x, y, z)
	if square and type(square.getID) == "function" then
		local ok, id = pcall(square.getID, square)
		if ok and id ~= nil then
			return id
		end
	end
	if x and y and z then
		return (z * 1e9) + (x * 1e4) + y
	end
	return nil
end

local function detectFlag(square, detector)
	if not square then
		return false
	end
	if type(detector) == "function" then
		local ok, value = pcall(detector, square)
		if ok then
			return value == true
		end
	end
	return false
end

local function makeSquareRecord(square, source)
	if not square then
		return nil
	end

	local x = coordOf(square, "getX")
	local y = coordOf(square, "getY")
	local z = coordOf(square, "getZ") or 0
	if x == nil or y == nil then
		Log:warn("Skipped square record: missing coordinates")
		return nil
	end

	local record = {
		squareId = deriveSquareId(square, x, y, z),
		square = square,
		x = x,
		y = y,
		z = z,
		hasBloodSplat = detectFlag(square, square.hasBlood),
		hasCorpse = detectFlag(square, square.hasCorpse),
		hasTrashItems = false, -- placeholder until we wire real trash detection
		observedAtTimeMS = nowMillis(),
		source = source,
	}

	return record
end

local function registerOnLoadGridSquare(ctx)
	local events = _G.Events
	if not events or type(events.OnLoadGridsquare) ~= "table" or type(events.OnLoadGridsquare.Add) ~= "function" then
		return false
	end

	events.OnLoadGridsquare.Add(function(square)
		local record = makeSquareRecord(square, "event")
		if record then
			ctx.emit(record)
		end
	end)
	return true
end

-- Chebyshev ring around the center square; stop as soon as we spend the budget.
local function iterSquaresInRing(centerSquare, innerRadius, outerRadius, budget)
	local results = {}
	if not centerSquare or budget <= 0 then
		return results
	end

	local cellGetter = centerSquare.getCell
	local cell = nil
	if type(cellGetter) == "function" then
		local ok, c = pcall(cellGetter, centerSquare)
		if ok then
			cell = c
		end
	end
	if not cell or type(cell.getGridSquare) ~= "function" then
		return results
	end

	local cx = coordOf(centerSquare, "getX")
	local cy = coordOf(centerSquare, "getY")
	local cz = coordOf(centerSquare, "getZ") or 0
	if not cx or not cy then
		return results
	end

	for dx = -outerRadius, outerRadius do
		for dy = -outerRadius, outerRadius do
			local dist = math.max(math.abs(dx), math.abs(dy))
			if dist >= innerRadius and dist <= outerRadius then
				if #results >= budget then
					return results
				end
				local ok, square = pcall(cell.getGridSquare, cell, cx + dx, cy + dy, cz)
				if ok and square then
					results[#results + 1] = square
				end
			end
		end
	end
	return results
end

local function nearbyPlayers()
	local players = {}
	local getNumPlayers = _G.getNumActivePlayers
	local getPlayer = _G.getSpecificPlayer
	if type(getNumPlayers) ~= "function" or type(getPlayer) ~= "function" then
		return players
	end

	local count = getNumPlayers()
	if type(count) ~= "number" then
		return players
	end

	for index = 0, math.max(0, count - 1) do
		local ok, player = pcall(getPlayer, index)
		if ok and player ~= nil then
			players[#players + 1] = player
		end
	end
	return players
end

local function runNearPlayersProbe(ctx, budget)
	local processed = 0
	for _, player in ipairs(nearbyPlayers()) do
		if processed >= budget then
			return
		end
		if type(player.getSquare) == "function" then
			local ok, square = pcall(player.getSquare, player)
			if ok and square then
				-- Probe the close ring near each player, respecting the per-tick budget.
				for _, probeSquare in ipairs(iterSquaresInRing(square, 1, 8, budget - processed)) do
					local record = makeSquareRecord(probeSquare, "probe")
					if record then
						if record.squareId == nil then
							Log:warn("Probe emitted square without id; dropping")
						else
							ctx.emit(record)
							processed = processed + 1
							if processed >= budget then
								return
							end
						end
					end
				end
			end
		end
	end
end

local function registerProbe(ctx, budgetPerTick)
	local events = _G.Events
	if not events or type(events.OnTick) ~= "table" or type(events.OnTick.Add) ~= "function" then
		return false
	end

	events.OnTick.Add(function()
		-- Use OnTick as a simple scheduler; a real scheduler can replace this later.
		runNearPlayersProbe(ctx, budgetPerTick)
	end)
	return true
end

function Squares.register(registry, config)
	local headless = config and config.facts and config.facts.squares and config.facts.squares.headless == true
	registry:register("squares", {
		start = function(ctx)
			local budget = 200
			if config and config.facts and config.facts.squares and config.facts.squares.strategy == "balanced" then
				budget = 200
			end

			local listenerRegistered = registerOnLoadGridSquare(ctx)
			local probeRegistered = registerProbe(ctx, budget)

			if not listenerRegistered and not headless then
				Log:warn("OnLoadGridsquare listener not registered (Events unavailable)")
			end
			if not probeRegistered and not headless then
				Log:warn("nearPlayers_closeRing probe not registered (Events.OnTick unavailable)")
			end
		end,
		stop = function(entry)
			-- No explicit teardown hooks yet; placeholder if we later attach events with remove semantics.
			return true
		end,
	})

	return {
		makeSquareRecord = makeSquareRecord,
	}
end

return Squares
