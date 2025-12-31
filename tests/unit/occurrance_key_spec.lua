package.path = table.concat({
	"Contents/mods/WorldObserver/42/media/lua/shared/?.lua",
	"Contents/mods/WorldObserver/42/media/lua/shared/?/init.lua",
	"../DREAMBase/Contents/mods/DREAMBase/42/media/lua/shared/?.lua",
	"../DREAMBase/Contents/mods/DREAMBase/42/media/lua/shared/?/init.lua",
	"external/DREAMBase/Contents/mods/DREAMBase/42/media/lua/shared/?.lua",
	"external/DREAMBase/Contents/mods/DREAMBase/42/media/lua/shared/?/init.lua",
	"external/LQR/?.lua",
	"external/LQR/?/init.lua",
	"external/lua-reactivex/?.lua",
	"external/lua-reactivex/?/init.lua",
	package.path,
}, ";")
_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local ObservationsCore = require("WorldObserver/observations/core")
local Log = require("LQR/util/log")

local function dummyStream(events)
	local builder = {
		subscribe = function(_, onNext)
			for _, v in ipairs(events or {}) do
				if onNext then
					onNext(v)
				end
			end
			return { unsubscribe = function() end }
		end,
	}
	return ObservationsCore._internal.newObservationStream(builder, {}, {}, nil, nil)
end

local function buildSquareObservation()
	return {
		square = {
			woKey = "x1y2z0",
			RxMeta = { schema = "square", shape = "record" },
		},
		RxMeta = { shape = "join_result", schemaMap = { square = true } },
	}
end

local function buildSquareZombieObservation()
	return {
		square = {
			woKey = "x1y2z0",
			RxMeta = { schema = "square", shape = "record" },
		},
		zombie = {
			woKey = "5",
			RxMeta = { schema = "zombie", shape = "record" },
		},
		RxMeta = { shape = "join_result", schemaMap = { square = true, zombie = true } },
	}
end

describe("ObservationStream:withOccurrenceKey", function()
	it("defaults occurranceKey to WoMeta.key", function()
		local stream = dummyStream({ buildSquareObservation() })
		local seen = nil
		stream:subscribe(function(observation)
			seen = observation
		end)
		assert.is_table(seen)
		assert.is_table(seen.WoMeta)
		assert.equals("#square(x1y2z0)", seen.WoMeta.key)
		assert.equals("#square(x1y2z0)", seen.WoMeta.occurranceKey)
	end)

	it("uses a single family override", function()
		local stream = dummyStream({ buildSquareObservation() }):withOccurrenceKey("square")
		local seen = nil
		stream:subscribe(function(observation)
			seen = observation
		end)
		assert.is_table(seen)
		assert.equals("#square(x1y2z0)", seen.WoMeta.occurranceKey)
	end)

	it("uses a multi-family override and sorts families", function()
		local stream = dummyStream({ buildSquareZombieObservation() })
			:withOccurrenceKey({ "zombie", "square" })
		local seen = nil
		stream:subscribe(function(observation)
			seen = observation
		end)
		assert.is_table(seen)
		assert.equals("#square(x1y2z0)#zombie(5)", seen.WoMeta.occurranceKey)
	end)

	it("uses a function override when provided", function()
		local stream = dummyStream({ buildSquareObservation() })
			:withOccurrenceKey(function()
				return "customKey"
			end)
		local seen = nil
		stream:subscribe(function(observation)
			seen = observation
		end)
		assert.is_table(seen)
		assert.equals("customKey", seen.WoMeta.occurranceKey)
	end)

	it("does not fall back when override returns nil", function()
		local previousLevel = Log.getLevel()
		Log.setLevel("error")
		local stream = dummyStream({ buildSquareObservation() })
			:withOccurrenceKey(function()
				return nil
			end)
		local seen = nil
		stream:subscribe(function(observation)
			seen = observation
		end)
		Log.setLevel(previousLevel)
		assert.is_table(seen)
		assert.equals("#square(x1y2z0)", seen.WoMeta.key)
		assert.is_nil(seen.WoMeta.occurranceKey)
	end)
end)
