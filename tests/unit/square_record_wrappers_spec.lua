_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("WorldObserver square record wrapping", function()
	local WorldObserver

	before_each(function()
		WorldObserver = reload("WorldObserver")
	end)

	it("wrap refuses non-table", function()
		local Square = WorldObserver.helpers.square
		local wrapped, err = Square:wrap(nil)
		assert.is_nil(wrapped)
		assert.equals("badRecord", err)
	end)

	it("wrap decorates record in-place and is idempotent", function()
		local Square = WorldObserver.helpers.square
		local record = { squareId = 123 }

		local wrapped, err = Square:wrap(record)
		assert.is_nil(err)
		assert.equals(record, wrapped)
		assert.is_not_nil(getmetatable(record))

		local wrapped2, err2 = Square:wrap(record)
		assert.is_nil(err2)
		assert.equals(record, wrapped2)
	end)

	it("wrap refuses when record already has a metatable", function()
		local Square = WorldObserver.helpers.square
		local record = setmetatable({}, { __index = {} })

		local wrapped, err = Square:wrap(record)
		assert.is_nil(wrapped)
		assert.equals("hasMetatable", err)
	end)

	it("wrapper methods delegate via helper tables", function()
		local Square = WorldObserver.helpers.square
		local record = { squareId = 7, floorMaterial = "RoadAsphalt" }

		local seen = {}
		Square.record.getIsoGridSquare = function(r)
			seen.getIsoGridSquare = r
			r.IsoGridSquare = "IsoGridSquareSentinel"
			return r.IsoGridSquare
		end
		Square.record.squareHasFloorMaterial = function(r, expected)
			seen.hasFloorMaterial = { r = r, expected = expected }
			return expected == "Road%"
		end
		Square.highlight = function(r, durationMs, opts)
			seen.highlight = { r = r, durationMs = durationMs, opts = opts }
			return true
		end

		Square:wrap(record)

		assert.equals("IsoGridSquareSentinel", record:getIsoGridSquare())
		assert.equals(record, seen.getIsoGridSquare)

		assert.is_true(record:hasFloorMaterial("Road%"))
		assert.equals(record, seen.hasFloorMaterial.r)
		assert.equals("Road%", seen.hasFloorMaterial.expected)

		assert.is_true(record:highlight(1234, { color = { 1, 0, 0, 1 } }))
		assert.equals(record, seen.highlight.r)
		assert.equals(1234, seen.highlight.durationMs)
	end)
end)

