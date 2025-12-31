-- facts/vehicles/probe.lua -- interest-driven vehicle probe (scope=allLoaded) using a time-sliced cursor over IsoCell:getVehicles().
local Log = require("DREAMBase/log").withTag("WO.FACTS.vehicles")
local Cooldown = require("WorldObserver/facts/cooldown")
local InterestEffective = require("WorldObserver/facts/interest_effective")
local Record = require("WorldObserver/facts/vehicles/record")
local JavaList = require("DREAMBase/pz/java_list")
local Time = require("DREAMBase/time_ms")
local SquareHelpers = require("WorldObserver/helpers/square")
local Highlight = require("WorldObserver/helpers/highlight")

local INTEREST_TYPE_VEHICLES = "vehicles"
local INTEREST_SCOPE_ALL = "allLoaded"
local PROBE_TICK_HOOK_ID = "facts.vehicles.tick"

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
			"[probe allLoaded] sweep started staleness=%ss cooldown=%ss",
			tostring(effective and effective.staleness),
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

local function resolveVehicleList()
	local getCell = _G.getCell
	if type(getCell) ~= "function" then
		return nil
	end
	local okCell, cell = pcall(getCell)
	if not okCell or not cell or type(cell.getVehicles) ~= "function" then
		return nil
	end
	local okList, list = pcall(cell.getVehicles, cell)
	if not okList then
		return nil
	end
	return list
end

if Probe.tick == nil then
	--- Tick the vehicle probe.
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

		local effective = nil
		local signals = state.lastLagSignals
		effective = InterestEffective.ensure(state, ctx.interestRegistry, ctx.runtime, INTEREST_TYPE_VEHICLES, {
			label = "vehicles.allLoaded",
			allowDefault = false,
			signals = signals,
			bucketKey = INTEREST_SCOPE_ALL,
		})
		if not effective then
			return
		end

		state.logEachSweep = probeCfg.logEachSweep == true

		-- Interest policy returns numeric effective settings (staleness/cooldown).
		-- highlight is taken from the merged lease to avoid ladder interference.
		local stalenessSeconds = tonumber(effective.staleness) or 0
		local cooldownSeconds = tonumber(effective.cooldown) or 0

		local merged = nil
		if ctx.interestRegistry and ctx.interestRegistry.effective then
			local okMerged, res = pcall(function()
				return ctx.interestRegistry:effective(INTEREST_TYPE_VEHICLES, nil, { bucketKey = INTEREST_SCOPE_ALL })
			end)
			if okMerged then
				merged = res
			end
		end
		local highlightPref = nil
		if type(merged) == "table" then
			highlightPref = merged.highlight
		end
		effective.highlight = highlightPref

		local cooldownMs = math.max(0, cooldownSeconds * 1000)
		local stalenessMs = math.max(0, stalenessSeconds * 1000)

		local doHighlight = (ctx.headless ~= true) and shouldHighlight(highlightPref)
		local highlightMs = 0
		local highlightColor = nil
		local highlightAlpha = 0.7
		if doHighlight then
			highlightMs = tonumber(probeCfg.highlightMs) or 0
			if highlightMs <= 0 then
				highlightMs = Highlight.durationMsFromEffectiveCadence(effective)
			end
			highlightColor, highlightAlpha = Highlight.resolveColorAlpha(highlightPref, { 1, 0.2, 0.2 }, 0.7)
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

		local list = resolveVehicleList()
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
		local makeVehicleRecord = ctx.makeVehicleRecord or Record.makeVehicleRecord

		while state.cursorIndex <= listCount and processed < maxPerRun do
			if budgetMs > 0 and startCpu then
				local nowCpu = cpuMillis(ctx.runtime)
				if nowCpu and (nowCpu - startCpu) >= budgetMs then
					break
				end
			end

			local vehicle = JavaList.get(list, state.cursorIndex)
			state.cursorIndex = state.cursorIndex + 1
			processed = processed + 1
			state.sweepProcessed = (state.sweepProcessed or 0) + 1

			if vehicle then
				local record = makeVehicleRecord(vehicle, "probe", { headless = ctx.headless })
				local key = record and Record.keyFromRecord(record) or nil
				if key ~= nil and Cooldown.shouldEmit(state.lastEmittedById, key, nowMs, cooldownMs) then
					if ctx.emitFn then
						ctx.emitFn(record)
						emitted = emitted + 1
					end
					if doHighlight and highlightMs > 0 then
						local square = record and record.IsoGridSquare or nil
						if square ~= nil then
							SquareHelpers.highlight(square, highlightMs, { alpha = highlightAlpha, color = highlightColor })
						end
					end
					Cooldown.markEmitted(state.lastEmittedById, key, nowMs)
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
Probe._internal.PROBE_TICK_HOOK_ID = PROBE_TICK_HOOK_ID

return Probe
