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

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("WorldObserver situations registry", function()
	local WorldObserver

	before_each(function()
		WorldObserver = reload("WorldObserver")
	end)

	it("defines and gets situations with nil args", function()
		local situations = WorldObserver.situations.namespace("tests")
		local receivedArgs

		situations.define("example", function(args)
			receivedArgs = args
			return {
				subscribe = function(_, onNext)
					if onNext then
						onNext({ value = args.value or "none" })
					end
					return {
						unsubscribe = function() end,
					}
				end,
			}
		end)

		local stream = situations.get("example")
		local received = {}
		local subscription = stream:subscribe(function(observation)
			received[#received + 1] = observation
		end)

		assert.equals("table", type(receivedArgs))
		assert.equals(1, #received)
		assert.equals("none", received[1].value)
		subscription:unsubscribe()
	end)

	it("overwrites existing definitions", function()
		local situations = WorldObserver.situations.namespace("tests")

		situations.define("swap", function()
			return {
				subscribe = function()
					return { unsubscribe = function() end }
				end,
			}
		end)

		situations.define("swap", function()
			return {
				subscribe = function(_, onNext)
					if onNext then
						onNext({ value = "new" })
					end
					return { unsubscribe = function() end }
				end,
			}
		end)

		local received = {}
		situations.get("swap"):subscribe(function(observation)
			received[#received + 1] = observation
		end)

		assert.equals("new", received[1].value)
	end)

	it("errors on missing definition", function()
		local situations = WorldObserver.situations.namespace("tests")
		assert.has_error(function()
			situations.get("missing")
		end)
	end)

	it("rejects invalid situationId", function()
		local situations = WorldObserver.situations.namespace("tests")
		assert.has_error(function()
			situations.define(nil, function() end)
		end)
		assert.has_error(function()
			situations.define("", function() end)
		end)
		assert.has_error(function()
			situations.get(nil)
		end)
		assert.has_error(function()
			situations.get("")
		end)
	end)

	it("lists ids by namespace and fully-qualified keys globally", function()
		local alpha = WorldObserver.situations.namespace("alpha")
		local beta = WorldObserver.situations.namespace("beta")

		alpha.define("one", function()
			return { subscribe = function() return { unsubscribe = function() end } end }
		end)
		alpha.define("two", function()
			return { subscribe = function() return { unsubscribe = function() end } end }
		end)
		beta.define("three", function()
			return { subscribe = function() return { unsubscribe = function() end } end }
		end)

		local alphaList = alpha.list()
		assert.same({ "one", "two" }, alphaList)

		local allList = WorldObserver.situations.listAll()
		assert.same({ "alpha/one", "alpha/two", "beta/three" }, allList)
	end)

	it("subscribeTo returns the subscription from subscribe", function()
		local situations = WorldObserver.situations.namespace("tests")
		local subscription = { unsubscribe = function() end }

		situations.define("sub", function()
			return {
				subscribe = function()
					return subscription
				end,
			}
		end)

		local returned = situations.subscribeTo("sub", nil, function() end)
		assert.equals(subscription, returned)
	end)

	it("rejects non-table args", function()
		local situations = WorldObserver.situations.namespace("tests")
		situations.define("args", function()
			return {
				subscribe = function() return { unsubscribe = function() end } end,
			}
		end)
		assert.has_error(function()
			situations.get("args", "bad")
		end)
	end)
end)
