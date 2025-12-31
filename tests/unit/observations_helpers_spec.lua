_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

local function makeUnicornHelpers()
	local helpers = { stream = {} }
	function helpers.stream.unicorns_squareIdIs(stream, fieldName, wanted)
		local target = fieldName or "square"
		return stream:filter(function(observation)
			local record = observation[target]
			return type(record) == "table" and record.squareId == wanted
		end)
	end
	return helpers
end

describe("WorldObserver observation helper attachment", function()
	local WorldObserver

	before_each(function()
		WorldObserver = reload("WorldObserver")
	end)

	it("attaches custom helpers to base streams with alias resolution", function()
		local unicorns = makeUnicornHelpers()

		local stream = WorldObserver.observations:squares():withHelpers({
			helperSets = { unicorns = unicorns },
			enabled_helpers = { unicorns = "square" },
		})

		assert.equals("function", type(stream.unicorns_squareIdIs))
		assert.equals("table", type(stream.helpers))
		assert.equals("table", type(stream.helpers.unicorns))

		local received = {}
		stream:unicorns_squareIdIs(2):subscribe(function(row)
			received[#received + 1] = row
		end)

		WorldObserver._internal.facts:emit("squares", { squareId = 1, woKey = "x0y0z0", x = 0, y = 0, z = 0 })
		WorldObserver._internal.facts:emit("squares", { squareId = 2, woKey = "x0y0z0", x = 0, y = 0, z = 0 })

		assert.equals(1, #received)
		assert.equals(2, received[1].square.squareId)
	end)

	it("uses registerHelperFamily for named helper sets", function()
		local unicorns = makeUnicornHelpers()
		WorldObserver.observations:registerHelperFamily("unicorns", unicorns)

		local stream = WorldObserver.observations:squares():withHelpers({
			enabled_helpers = { unicorns = "square" },
		})

		local received = {}
		stream:unicorns_squareIdIs(1):subscribe(function(row)
			received[#received + 1] = row
		end)

		WorldObserver._internal.facts:emit("squares", { squareId = 1, woKey = "x0y0z0", x = 0, y = 0, z = 0 })

		assert.equals(1, #received)
		assert.equals(1, received[1].square.squareId)
	end)
end)
