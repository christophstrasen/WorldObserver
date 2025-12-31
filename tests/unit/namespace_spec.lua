dofile("tests/unit/bootstrap.lua")

_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("WorldObserver namespace facade", function()
	local WorldObserver

	before_each(function()
		WorldObserver = reload("WorldObserver")
	end)

	it("pins situations to a namespace", function()
		local wo = WorldObserver.namespace("tests")
		local received = {}

		wo.situations.define("example", function()
			return {
				subscribe = function(_, onNext)
					if onNext then
						onNext({ value = "ok" })
					end
					return { unsubscribe = function() end }
				end,
			}
		end)

		wo.situations.get("example"):subscribe(function(observation)
			received[#received + 1] = observation
		end)

		assert.equals(1, #received)
		assert.equals("ok", received[1].value)
	end)

	it("pins factInterest declare to the namespace", function()
		local wo = WorldObserver.namespace("tests")
		local captured = {}
		local original = WorldObserver.factInterest.declare

		WorldObserver.factInterest.declare = function(_, modId, key, spec, opts)
			captured.modId = modId
			captured.key = key
			captured.spec = spec
			captured.opts = opts
			return { stop = function() end }
		end

		wo.factInterest:declare("near", { type = "squares" }, { ttlSeconds = 1 })

		WorldObserver.factInterest.declare = original

		assert.equals("tests", captured.modId)
		assert.equals("near", captured.key)
		assert.equals("squares", captured.spec.type)
		assert.equals(1, captured.opts.ttlSeconds)
	end)
end)
