-- facts/squares/probe.lua -- wrapper that delegates to the shared square sweep sensor.
local SquareSweep = require("WorldObserver/facts/sensors/square_sweep")

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

if Probe.tick == nil then
	function Probe.tick(ctx)
		return SquareSweep.tick(ctx)
	end
end

-- Expose sensor internals for tests and patching seams.
Probe._internal.nearbyPlayers = Probe._internal.nearbyPlayers
	or SquareSweep._internal.nearbyPlayers
Probe._internal.resolveProbeBudgetMs = Probe._internal.resolveProbeBudgetMs
	or SquareSweep._internal.resolveProbeBudgetMs
Probe._internal.scaleMaxSquaresPerTick = Probe._internal.scaleMaxSquaresPerTick
	or SquareSweep._internal.scaleMaxSquaresPerTick
Probe._internal.ensureProbeCursor = Probe._internal.ensureProbeCursor
	or SquareSweep._internal.ensureProbeCursor
Probe._internal.ensureProbeOffsets = Probe._internal.ensureProbeOffsets
	or SquareSweep._internal.ensureProbeOffsets
Probe._internal.cursorNextSquare = Probe._internal.cursorNextSquare
	or SquareSweep._internal.cursorNextSquare
Probe._internal.cursorCanScanThisTick = Probe._internal.cursorCanScanThisTick
	or SquareSweep._internal.cursorCanScanThisTick
Probe._internal.computeProbeLagSignals = Probe._internal.computeProbeLagSignals
	or SquareSweep._internal.computeProbeLagSignals

return Probe
