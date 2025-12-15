-- facts/squares.lua -- square fact plan (balanced strategy): listeners + near-player probe to emit SquareObservation facts.
local Log = require("LQR/util/log").withTag("WO.FACTS.squares")

local moduleName = ...
local Squares = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Squares = loaded
	else
		package.loaded[moduleName] = Squares
	end
end
Squares._internal = Squares._internal or {}
Squares._defaults = Squares._defaults or {}

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

local function detectCorpse(square)
	if not square then
		return false
	 end
	if type(square.getDeadBody) == "function" then
		local ok, body = pcall(square.getDeadBody, square)
		if ok and body ~= nil then
			return true
		end
	end
	-- Some builds expose a list-returning API; treat any non-empty list as "has corpse".
	if type(square.getDeadBodys) == "function" then
		local ok, list = pcall(square.getDeadBodys, square)
		if ok and list ~= nil then
			if type(list.size) == "function" then
				local okSize, size = pcall(list.size, list)
				if okSize and type(size) == "number" then
					return size > 0
				end
			end
			-- Best-effort: if we can't introspect size, a non-nil list still suggests corpses may exist.
			-- Keep this conservative: only treat it as "true" when we can prove it's non-empty.
		end
	end
	return detectFlag(square, square.hasCorpse)
end

-- Default square record builder.
-- Intentionally exposed via Squares.makeSquareRecord so other mods can patch/override it.
function Squares.makeSquareRecord(square, source)
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
		x = x,
		y = y,
		z = z,
		hasBloodSplat = detectFlag(square, square.hasBlood),
		hasCorpse = detectCorpse(square),
		hasTrashItems = false, -- placeholder until we wire real trash detection
		observedAtTimeMS = nowMillis(),
		IsoSquare = square,
		source = source,
	}

	return record
end

Squares._defaults.makeSquareRecord = Squares._defaults.makeSquareRecord or Squares.makeSquareRecord

local function registerOnLoadGridSquare(state, emitFn)
	local events = _G.Events
	local handler = events and events.LoadGridsquare
	if not handler or type(handler.Add) ~= "function" then
		return false
	end

	if state.loadGridsquareHandler then
		return true
	end

	local fn = function(square)
		local record = Squares.makeSquareRecord(square, "event")
		if record then
			emitFn(record)
		end
	end
	handler.Add(fn)
	state.loadGridsquareHandler = fn
	Log:info("LoadGridsquare listener registered")
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

	-- Prefer the simple single-player API: in most WO use cases we want "the local player"
	-- as the probe center, not a global iteration. This also avoids environments where
	-- getNumActivePlayers/getSpecificPlayer aren't available yet.
	local getPlayer = _G.getPlayer
	if type(getPlayer) == "function" then
		local ok, player = pcall(getPlayer)
		if ok and player ~= nil then
			players[1] = player
			return players
		end
	end

	-- Fallback for environments that don't expose getPlayer() but do expose indexed players.
	local getNumPlayers = _G.getNumActivePlayers
	local getSpecificPlayer = _G.getSpecificPlayer
	if type(getNumPlayers) ~= "function" or type(getSpecificPlayer) ~= "function" then
		return players
	end

	local count = getNumPlayers()
	if type(count) ~= "number" then
		return players
	end

	for index = 0, math.max(0, count - 1) do
		local ok, player = pcall(getSpecificPlayer, index)
		if ok and player ~= nil then
			players[#players + 1] = player
		end
	end
	return players
end

local function runNearPlayersProbe(emitFn, budget)
	local processed = 0
	for _, player in ipairs(nearbyPlayers()) do
		if processed >= budget then
			return
		end
		if type(player.getSquare) == "function" then
			local ok, square = pcall(player.getSquare, player)
			if ok and square then
				local cx = coordOf(square, "getX")
				local cy = coordOf(square, "getY")
				local cz = coordOf(square, "getZ") or 0
				local centerId = deriveSquareId(square, cx, cy, cz)
				Log:info(
					"[probe] center square x=%s y=%s z=%s squareId=%s",
					cx ~= nil and tostring(cx) or "n/a",
					cy ~= nil and tostring(cy) or "n/a",
					cz ~= nil and tostring(cz) or "n/a",
					centerId ~= nil and tostring(centerId) or "n/a"
				)

				local emitted = 0
				local flaggedCleaning = 0

				-- Probe a small 5x5 area around each player (Chebyshev radius 2).
				-- Intention: keep probe cost predictable and near-player focused; chunk-load events cover the rest.
				for _, probeSquare in ipairs(iterSquaresInRing(square, 0, 2, budget - processed)) do
					local record = Squares.makeSquareRecord(probeSquare, "probe")
					if record then
						if record.squareId == nil then
							Log:warn("Probe emitted square without id; dropping")
						else
							emitted = emitted + 1
							if record.hasCorpse == true or record.hasBloodSplat == true or record.hasTrashItems == true then
								flaggedCleaning = flaggedCleaning + 1
							end
							emitFn(record)
							processed = processed + 1
							if processed >= budget then
								return
							end
						end
					end
				end

				Log:info(
					"[probe] emitted=%s flaggedCleaning=%s processedTotal=%s budget=%s",
					tostring(emitted),
					tostring(flaggedCleaning),
					tostring(processed),
					tostring(budget)
				)
			end
		else
			Log:warn("[probe] cannot run: player has no getSquare()")
		end
	end
end

local function registerProbe(state, emitFn, budgetPerRun, headless, runtime)
	local events = _G.Events
	if not events or type(events.EveryOneMinute) ~= "table" or type(events.EveryOneMinute.Add) ~= "function" then
		if not headless then
			Log:warn("Probe not registered (Events.EveryOneMinute unavailable)")
		end
		return false
	end

	if state.everyOneMinuteHandler then
		return true
	end

	local fn = function()
		local t0, useCpu = nil, false
		if runtime then
			t0 = runtime:nowCpu()
			useCpu = type(t0) == "number"
			if not useCpu then
				t0 = runtime:nowWall()
			end
		end

		runNearPlayersProbe(emitFn, budgetPerRun)

		if runtime and type(t0) == "number" then
			local t1 = useCpu and runtime:nowCpu() or runtime:nowWall()
			if type(t1) == "number" and t1 >= t0 then
				-- Count probe time toward WO budgets; this prevents probe work from being "free" compared to drain work.
				local dt = t1 - t0
				runtime:recordTick(dt)
				runtime:controller_tick({ tickMs = dt })
			end
		end
	end
	events.EveryOneMinute.Add(fn)
	state.everyOneMinuteHandler = fn
	return true
end

Squares._internal.registerOnLoadGridSquare = registerOnLoadGridSquare
Squares._internal.iterSquaresInRing = iterSquaresInRing
Squares._internal.nearbyPlayers = nearbyPlayers
Squares._internal.runNearPlayersProbe = runNearPlayersProbe
Squares._internal.registerProbe = registerProbe

-- Patch seam: define only when nil so mods can override by reassigning `Squares.register` and so reloads
-- (tests/console via `package.loaded`) don't clobber an existing patch.
if Squares.register == nil then
	function Squares.register(registry, config)
		local headless = config and config.facts and config.facts.squares and config.facts.squares.headless == true
		local probeCfg = config and config.facts and config.facts.squares and config.facts.squares.probe or {}
		local probeEnabled = probeCfg.enabled ~= false
		local probeMaxPerRun = probeCfg.maxPerRun or 50

		registry:register("squares", {
			ingest = {
				mode = "latestByKey",
				ordering = "fifo",
				key = function(record)
					return record and record.squareId
				end,
				lane = function(record)
					return (record and record.source) or "default"
				end,
				lanePriority = function(laneName)
					if laneName == "probe" then
						return 2
					end
					if laneName == "event" then
						return 1
					end
					return 1
				end,
			},
			start = function(ctx)
				local state = ctx.state or {}
				local originalEmit = ctx.ingest or ctx.emit
				local listenerRegistered = Squares._internal.registerOnLoadGridSquare(state, originalEmit)
				local probeRegistered = false
				if probeEnabled then
					probeRegistered =
						Squares._internal.registerProbe(state, originalEmit, probeMaxPerRun, headless, ctx.runtime)
				end

				if not listenerRegistered and not headless then
					Log:warn("OnLoadGridsquare listener not registered (Events unavailable)")
				end
				if not headless then
					Log:info(
						"Squares fact plan started (listener=%s, probe=%s)",
						tostring(listenerRegistered),
						tostring(probeRegistered)
					)
				end
				ctx.emit = originalEmit
				ctx.ingest = originalEmit
			end,
			stop = function(entry)
				local state = entry.state or {}
				local events = _G.Events
				local fullyStopped = true

				if entry.buffer and entry.buffer.clear then
					entry.buffer:clear()
				end

				if state.loadGridsquareHandler then
					local handler = events and events.LoadGridsquare
					if handler and type(handler.Remove) == "function" then
						pcall(handler.Remove, handler, state.loadGridsquareHandler)
						state.loadGridsquareHandler = nil
					else
						fullyStopped = false
					end
				end

				if state.everyOneMinuteHandler then
					local handler = events and events.EveryOneMinute
					if handler and type(handler.Remove) == "function" then
						pcall(handler.Remove, handler, state.everyOneMinuteHandler)
						state.everyOneMinuteHandler = nil
					else
						fullyStopped = false
					end
				end

				if not fullyStopped and not headless then
					Log:warn("Squares fact stop requested but could not remove all handlers; keeping started=true")
				end

				return fullyStopped
			end,
		})

		return {
			makeSquareRecord = function(square, source)
				return Squares.makeSquareRecord(square, source)
			end,
			defaultMakeSquareRecord = defaultMakeSquareRecord,
			_internal = Squares._internal,
		}
	end
end

return Squares
