-- WorldObserver.lua -- public facade: wires LuaEvent, loads config, and registers facts/streams/helpers.

-- Bootstrap LQR early to expand package.path for util.log/reactivex and friends.
local _LQRBootstrap = require("LQR")

local okLuaEvent, LuaEventOrError = pcall(require, "Starlit/LuaEvent")
if okLuaEvent and _G.Events and _G.Events.setLuaEvent then
	-- Wire Starlit LuaEvent when available so downstream mods can emit/observe it.
	-- We also clear any Runtime-tracked LuaEvent error so consumers know the hook is healthy.
	Events.setLuaEvent(LuaEventOrError)
	if _G.Runtime and Runtime.setLuaEventError then
		Runtime.setLuaEventError(nil)
	end
elseif _G.Events and _G.Events.setLuaEvent then
	-- LuaEvent failed to load: publish the failure into Runtime so consumers can diagnose it.
	Events.setLuaEvent(nil)
	if _G.Runtime and Runtime.setLuaEventError then
		Runtime.setLuaEventError(LuaEventOrError)
	end
end

local Config = require("WorldObserver/config")
local FactRegistry = require("WorldObserver/facts/registry")
local SquaresFacts = require("WorldObserver/facts/squares")
local ObservationsCore = require("WorldObserver/observations/core")
local SquaresObservations = require("WorldObserver/observations/squares")
local SquareHelpers = require("WorldObserver/helpers/square")
local Debug = require("WorldObserver/debug")

local config = Config.load()
local factRegistry = FactRegistry.new(config)
SquaresFacts.register(factRegistry, config)

local observationRegistry = ObservationsCore.new({
	factRegistry = factRegistry,
	config = config,
	helperSets = {
		square = SquareHelpers,
	},
})

SquaresObservations.register(observationRegistry, factRegistry, ObservationsCore.nextObservationId)

local WorldObserver = {
	config = config,
	observations = observationRegistry:api(),
	helpers = {
		square = SquareHelpers,
	},
	debug = Debug.new(factRegistry, observationRegistry),
	nextObservationId = ObservationsCore.nextObservationId,
	_internal = {
		-- Expose internals for tests and advanced users until a fuller API exists.
		facts = factRegistry,
		observationRegistry = observationRegistry,
	},
}

return WorldObserver
