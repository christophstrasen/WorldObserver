package.path = table.concat({
	"Contents/mods/WorldObserver/42/media/lua/shared/?.lua",
	"Contents/mods/WorldObserver/42/media/lua/shared/?/init.lua",
	"external/LQR/?.lua",
	"external/LQR/?/init.lua",
	"external/lua-reactivex/?.lua",
	"external/lua-reactivex/?/init.lua",
	package.path,
}, ";")
_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true


local ObservationsCore = require("WorldObserver/observations/core")
local rx = require("reactivex")

local function dummyStream(events, shouldComplete)
	events = events or {}
	local builder = {
		subscribe = function(_, onNext, onError, onCompleted)
			for _, v in ipairs(events) do
				if onNext then
					onNext(v)
				end
			end
			if shouldComplete and onCompleted then
				onCompleted()
			end
			local unsubscribed = { called = false }
			function unsubscribed:unsubscribe()
				self.called = true
			end
			return unsubscribed
		end,
	}

	return ObservationsCore._internal.newObservationStream(builder, {}, {}, nil, nil)
end

describe("ObservationStream:asRx", function()
	it("bridges to lua-reactivex and propagates unsubscribe", function()
		local stream = dummyStream({
			{ value = 1, woKey = "1", RxMeta = { schema = "dummy", shape = "record" } },
			{ value = 2, woKey = "2", RxMeta = { schema = "dummy", shape = "record" } },
			{ value = 3, woKey = "3", RxMeta = { schema = "dummy", shape = "record" } },
		}, false)
		local rxStream = stream:asRx()

		local values = {}
		local sub = rxStream
			:map(function(x)
				return x.value * 2
			end)
			:subscribe(function(x)
				values[#values + 1] = x
			end)

		assert.are.same({ 2, 4, 6 }, values)

		sub:unsubscribe()
		assert.is_true(sub:isUnsubscribed())
	end)

	it("bubbles errors to rx observers", function()
		local builder = {
			subscribe = function(_, _, onError)
				if onError then
					onError("boom")
				end
				return { unsubscribe = function() end }
			end,
		}
		local stream = ObservationsCore._internal.newObservationStream(builder, {}, {}, nil, nil)
		local rxStream = stream:asRx()

		local caught = nil
		rxStream:subscribe(function() end, function(err)
			caught = err
		end)

		assert.equals("boom", caught)
	end)
end)
