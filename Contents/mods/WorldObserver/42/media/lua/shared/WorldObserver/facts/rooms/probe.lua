-- facts/rooms/probe.lua -- interest-driven room probe (scope=allLoaded) using IsoCell:getRoomList().
local Log = require("LQR/util/log").withTag("WO.FACTS.rooms")
local Cooldown = require("WorldObserver/facts/cooldown")
local InterestEffective = require("WorldObserver/facts/interest_effective")
local Highlight = require("WorldObserver/helpers/highlight")
local JavaList = require("WorldObserver/helpers/java_list")
local Time = require("WorldObserver/helpers/time")

local moduleName = ...
local Probe = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Probe = loaded
	else
		package.loaded[moduleName] = Probe
	end
end
Probe._internal = Probe._internal or {}

local INTEREST_TYPE_ROOMS = "rooms"
local INTEREST_SCOPE_ALL = "allLoaded"
local PROBE_HIGHLIGHT_COLOR = { 0.9, 0.7, 0.2 }

local function nowMillis()
	return Time.gameMillis() or math.floor(os.time() * 1000)
end

local function resolveBudgetClock(runtime)
	if runtime and type(runtime.nowCpu) == "function" then
		local ok, v = pcall(runtime.nowCpu, runtime)
		if ok and type(v) == "number" then
			return function()
				return runtime:nowCpu()
			end
		end
	end
	return function()
		return Time.cpuMillis() or Time.gameMillis() or 0
	end
end

local function resolveRoomList()
	local getCell = _G.getCell
	if type(getCell) ~= "function" then
		return nil
	end
	local okCell, cell = pcall(getCell)
	if not okCell or not cell or type(cell.getRoomList) ~= "function" then
		return nil
	end
	local okList, list = pcall(cell.getRoomList, cell)
	if not okList then
		return nil
	end
	return list
end

local function emitWithCooldown(state, emitFn, record, nowMs, cooldownMs)
	if type(emitFn) ~= "function" or type(record) ~= "table" or record.roomId == nil then
		return false
	end
	state.lastEmittedMs = state.lastEmittedMs or {}
	if not Cooldown.shouldEmit(state.lastEmittedMs, record.roomId, nowMs, cooldownMs) then
		return false
	end
	emitFn(record)
	Cooldown.markEmitted(state.lastEmittedMs, record.roomId, nowMs)
	return true
end

local function highlightRoomSquares(room, cooldownSeconds, highlightPref)
	if room == nil then
		return
	end
	if type(room.getSquares) ~= "function" then
		return
	end
	local okSquares, squares = pcall(room.getSquares, room)
	if not okSquares or squares == nil then
		return
	end

	local color = PROBE_HIGHLIGHT_COLOR
	local alpha = 0.9
	if type(highlightPref) == "table" then
		color = highlightPref
		if type(color[4]) == "number" then
			alpha = color[4]
		end
	end
	local count = JavaList.size(squares)
	if count <= 0 then
		return
	end

	local durationMs = Highlight.durationMsFromCooldownSeconds(cooldownSeconds)
	for i = 1, count do
		local square = JavaList.get(squares, i)
		if square ~= nil then
			Highlight.highlightFloor(square, durationMs, { color = color, alpha = alpha })
		end
	end
end

local function startSweep(state, nowMs)
	state.cursorIndex = 1
	state.sweepActive = true
	state.sweepStartMs = nowMs
end

local function finishSweep(state, nowMs)
	state.cursorIndex = 1
	state.sweepActive = false
	state.sweepStartMs = nowMs
	state.lastSweepFinishedMs = nowMs
end

--- Tick the rooms probe.
--- @param ctx table
if Probe.tick == nil then
	function Probe.tick(ctx)
		ctx = ctx or {}
		local state = ctx.state or {}
		ctx.state = state

		local probeCfg = ctx.probeCfg or {}
		local maxPerRun = tonumber(probeCfg.maxPerRun) or 40
		if maxPerRun <= 0 then
			return
		end
		local maxMillisPerTick = tonumber(probeCfg.maxMillisPerTick)

		local rooms = ctx.rooms
		if not (rooms and type(rooms.makeRoomRecord) == "function") then
			return
		end

		local effective = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, INTEREST_TYPE_ROOMS, {
			label = "rooms.allLoaded",
			allowDefault = false,
			log = Log,
			bucketKey = INTEREST_SCOPE_ALL,
		})
		if not effective then
			return
		end

		local highlightPref = nil
		if ctx.interestRegistry and ctx.interestRegistry.effective then
			local okMerged, merged = pcall(function()
				return ctx.interestRegistry:effective(INTEREST_TYPE_ROOMS, nil, { bucketKey = INTEREST_SCOPE_ALL })
			end)
			if okMerged and type(merged) == "table" then
				highlightPref = merged.highlight
			end
		end

		local stalenessSeconds = tonumber(effective.staleness) or 0
		local cooldownSeconds = tonumber(effective.cooldown) or 0
		local cooldownMs = math.max(0, cooldownSeconds * 1000)
		local stalenessMs = math.max(0, stalenessSeconds * 1000)

		local list = resolveRoomList()
		if list == nil then
			return
		end

		local listCount = JavaList.size(list)
		if listCount <= 0 then
			return
		end

		local nowMs = nowMillis()
		if not state.sweepActive then
			if state.sweepStartMs and stalenessMs > 0 and (nowMs - state.sweepStartMs) < stalenessMs then
				return
			end
			startSweep(state, nowMs)
		end

		local highlightEnabled = (highlightPref == true or type(highlightPref) == "table") and not ctx.headless

		local budgetClock = resolveBudgetClock(ctx.runtime)
		local budgetStart = budgetClock()

		local processed = 0
		while processed < maxPerRun do
			if maxMillisPerTick ~= nil and maxMillisPerTick > 0 then
				local elapsed = budgetClock() - budgetStart
				if elapsed >= maxMillisPerTick then
					break
				end
			end

			if state.cursorIndex > listCount then
				finishSweep(state, nowMs)
				break
			end

			local room = JavaList.get(list, state.cursorIndex)
			state.cursorIndex = state.cursorIndex + 1
			processed = processed + 1

			if room ~= nil then
				local record = rooms.makeRoomRecord(room, "probe", ctx.recordOpts)
				if record then
					if emitWithCooldown(state, ctx.emitFn, record, nowMs, cooldownMs) then
						if highlightEnabled then
							highlightRoomSquares(room, effective.cooldown, highlightPref)
						end
					end
				end
			end
		end
	end
end

return Probe
