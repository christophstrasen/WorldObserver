-- facts/zombies/probe.lua -- interest-driven zombie probe (scope=allLoaded)
-- using a time-sliced cursor over IsoCell:getZombieList().
local Log = require("DREAMBase/log").withTag("WO.FACTS.zombies")
local Cooldown = require("WorldObserver/facts/cooldown")
local InterestEffective = require("WorldObserver/facts/interest_effective")
local Record = require("WorldObserver/facts/zombies/record")
local JavaList = require("DREAMBase/pz/java_list")
local Time = require("DREAMBase/time_ms")
local SquareHelpers = require("WorldObserver/helpers/square")

local INTEREST_TYPE_ZOMBIES = "zombies"
local INTEREST_SCOPE_ALL = "allLoaded"
local PROBE_TICK_HOOK_ID = "facts.zombies.tick"

local moduleName = ...
local Probe = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Probe = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = Probe
	end
end
Probe._internal = Probe._internal or {}

local function nowMillis()
	return Time.gameMillis() or math.floor(os.time() * 1000)
end

local function cpuMillis(runtime)
	if runtime and runtime.nowCpu then
		return runtime:nowCpu()
	end
	return nil
end

local function nearbyPlayers()
	local players = {}
	local getNumActivePlayers = _G.getNumActivePlayers
	local getSpecificPlayer = _G.getSpecificPlayer
	if type(getNumActivePlayers) ~= "function" or type(getSpecificPlayer) ~= "function" then
		return players
	end
	local okCount, count = pcall(getNumActivePlayers)
	if not okCount or type(count) ~= "number" or count <= 0 then
		return players
	end
	for idx = 0, count - 1 do
		local okPlayer, player = pcall(getSpecificPlayer, idx)
		if okPlayer and player then
			local x = type(player.getX) == "function" and player:getX() or nil
			local y = type(player.getY) == "function" and player:getY() or nil
			local z = type(player.getZ) == "function" and player:getZ() or 0
			if x and y then
				players[#players + 1] = { x = x, y = y, z = z }
			end
		end
	end
	return players
end

local function withinInterest(zombie, player, radius, zRange)
	if not zombie or not player then
		return false
	end
	local zx = zombie.x
	local zy = zombie.y
	local zz = zombie.z or 0
	if not zx or not zy then
		return false
	end
	local dz = math.abs((zz or 0) - (player.z or 0))
	if dz > zRange then
		return false
	end
	if radius <= 0 then
		return true
	end
	local dx = zx - player.x
	local dy = zy - player.y
	return (dx * dx + dy * dy) <= (radius * radius)
end

local function shouldHighlight(pref)
	return pref == true or type(pref) == "table"
end

local function startSweep(state, effective, nowMs)
	state.cursorIndex = 1
	state.sweepStartMs = nowMs
	state.sweepActive = true
	state.sweepProcessed = 0
	state.sweepBudgetMs = nil
	if state.logEachSweep then
		Log:info(
			"[probe allLoaded] sweep started staleness=%ss radius=%s zRange=%s cooldown=%ss",
			tostring(effective and effective.staleness),
			tostring(effective and effective.radius),
			tostring(effective and effective.zRange),
			tostring(effective and effective.cooldown)
		)
	end
end

local function finishSweep(state, nowMs, emitted)
	if not state.sweepActive then
		return
	end
	local duration = nowMs - (state.sweepStartMs or nowMs)
	if state.logEachSweep then
		Log:info(
			"[probe allLoaded] sweep finished durationMs=%s overdueMs=%s processed=%s emitted=%s",
			tostring(duration),
			tostring(math.max(0, duration - (state.sweepBudgetMs or 0))),
			tostring(state.sweepProcessed or 0),
			tostring(emitted or 0)
		)
	end
	state.cursorIndex = 1
	state.sweepActive = false
	state.sweepStartMs = nowMs
	state.lastSweepFinishedMs = nowMs
	state.sweepProcessed = 0
end

local function resolveZombieList()
	local getCell = _G.getCell
	if type(getCell) ~= "function" then
		return nil
	end
	local okCell, cell = pcall(getCell)
	if not okCell or not cell or type(cell.getZombieList) ~= "function" then
		return nil
	end
	local okList, list = pcall(cell.getZombieList, cell)
	if not okList then
		return nil
	end
	return list
end

if Probe.tick == nil then
	--- Tick the zombie probe.
	--- @param ctx table
	function Probe.tick(ctx)
		ctx = ctx or {}
		local state = ctx.state or {}
		ctx.state = state

		local probeCfg = ctx.probeCfg or {}
		local maxPerRun = tonumber(probeCfg.maxPerRun) or 50
		if maxPerRun <= 0 then
			return
		end

			local signals = state.lastLagSignals
			local effective = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, INTEREST_TYPE_ZOMBIES, {
				label = "zombies.allLoaded",
				allowDefault = false,
				signals = signals,
				bucketKey = INTEREST_SCOPE_ALL,
			})
		if not effective then
			return
		end

		state.logEachSweep = probeCfg.logEachSweep == true

		local players = nearbyPlayers()
		if #players <= 0 then
			return
		end

		-- Interest policy returns numeric effective knobs for the core ladder (staleness/radius/cooldown).
		-- zRange and highlight are additional interest knobs that currently bypass the ladder and come from the merged lease.
		local stalenessSeconds = tonumber(effective.staleness) or 0
		local radius = tonumber(effective.radius) or 0
		local cooldownSeconds = tonumber(effective.cooldown) or 0

		local merged = nil
		if ctx.interestRegistry and ctx.interestRegistry.effective then
			local okMerged, res = pcall(function()
				return ctx.interestRegistry:effective(INTEREST_TYPE_ZOMBIES, nil, { bucketKey = INTEREST_SCOPE_ALL })
			end)
			if okMerged then
				merged = res
			end
		end
		local zRange = 0
		local highlightPref = nil
		if type(merged) == "table" then
			highlightPref = merged.highlight
			local zr = merged.zRange
			if type(zr) == "table" then
				zRange = tonumber(zr.desired) or 0
			else
				zRange = tonumber(zr) or 0
			end
		end
		zRange = math.max(0, math.floor(zRange))

		local cooldownMs = math.max(0, cooldownSeconds * 1000)
		local stalenessMs = math.max(0, stalenessSeconds * 1000)
		effective.zRange = zRange
		effective.highlight = highlightPref
		local doHighlight = (ctx.headless ~= true) and shouldHighlight(highlightPref)
		local highlightMs = 0
		local highlightAlpha = 0.7
		local highlightColor = nil
		if doHighlight then
			highlightMs = tonumber(probeCfg.highlightMs) or 0
			if highlightMs <= 0 then
				local cadenceMs = math.max(stalenessMs, cooldownMs)
				highlightMs = math.max(0, math.floor(cadenceMs * 0.5))
			end
			highlightAlpha = tonumber(probeCfg.highlightAlpha) or 0.7
			highlightColor = probeCfg.highlightColor or highlightPref
			if highlightColor == true then
				highlightColor = { 1, 0.2, 0.2 }
			end
			if type(highlightColor) ~= "table" then
				highlightColor = { 1, 0.2, 0.2 }
			end
			if type(highlightColor[4]) == "number" then
				highlightAlpha = highlightColor[4]
			end
		end

		local nowMs = nowMillis()
		if not state.sweepActive and state.sweepStartMs and stalenessMs > 0 then
			if (nowMs - state.sweepStartMs) < stalenessMs then
				return
			end
		end

		if not state.sweepActive then
			startSweep(state, effective, nowMs)
		end

		local list = resolveZombieList()
		local listCount = JavaList.size(list)
		if listCount <= 0 then
			finishSweep(state, nowMs, 0)
			return
		end

		local startCpu = cpuMillis(ctx.runtime)
		local budgetMs = tonumber(probeCfg.maxMillisPerTick or probeCfg.maxMsPerTick) or 0
		local processed = 0
		local emitted = 0
		state.lastEmittedById = state.lastEmittedById or {}
		local makeZombieRecord = ctx.makeZombieRecord or Record.makeZombieRecord

		while state.cursorIndex <= listCount and processed < maxPerRun do
			if budgetMs > 0 and startCpu then
				local nowCpu = cpuMillis(ctx.runtime)
				if nowCpu and (nowCpu - startCpu) >= budgetMs then
					break
				end
			end

			local zombie = JavaList.get(list, state.cursorIndex)
			state.cursorIndex = state.cursorIndex + 1
			processed = processed + 1
			state.sweepProcessed = (state.sweepProcessed or 0) + 1

			if zombie then
				local record = makeZombieRecord(zombie, "probe")
				if record and record.zombieId ~= nil then
					local inRange = false
					for i = 1, #players do
						if withinInterest(record, players[i], radius, zRange) then
							inRange = true
							break
						end
					end
					if inRange and Cooldown.shouldEmit(state.lastEmittedById, record.zombieId, nowMs, cooldownMs) then
						if ctx.emitFn then
							ctx.emitFn(record)
							emitted = emitted + 1
						end
						if doHighlight and highlightMs > 0 then
							-- Zombies override their own highlight each frame; highlight the floor they currently stand on.
							local okSquare, isoSquare = pcall(zombie.getCurrentSquare, zombie)
							if okSquare and isoSquare ~= nil then
								SquareHelpers.highlight(isoSquare, highlightMs, {
								alpha = highlightAlpha,
								color = highlightColor,
							})
							end
						end
						Cooldown.markEmitted(state.lastEmittedById, record.zombieId, nowMs)
					end
				end
			end
		end

		if state.cursorIndex > listCount then
			finishSweep(state, nowMs, emitted)
		end
	end
end

Probe._internal.listSize = JavaList.size
Probe._internal.listGet = JavaList.get
Probe._internal.nearbyPlayers = nearbyPlayers
Probe._internal.withinInterest = withinInterest
Probe._internal.PROBE_TICK_HOOK_ID = PROBE_TICK_HOOK_ID

return Probe
