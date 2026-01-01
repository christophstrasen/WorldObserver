_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("WorldObserver vehicle record wrapping", function()
	local WorldObserver

	before_each(function()
		WorldObserver = reload("WorldObserver")
	end)

	it("wrap decorates record in-place", function()
		local Vehicle = WorldObserver.helpers.vehicle
		local record = { vehicleId = 123 }
		local wrapped, err = Vehicle:wrap(record)
		assert.is_nil(err)
		assert.equals(record, wrapped)
		assert.is_not_nil(getmetatable(record))
	end)

	it("wrapper methods delegate via helper tables", function()
		local Vehicle = WorldObserver.helpers.vehicle
		local Square = WorldObserver.helpers.square
		local record = { vehicleId = 7 }

		local seen = {}
		Square.record.getIsoGridSquare = function(r)
			seen.getIsoGridSquare = r
			r.IsoGridSquare = "IsoGridSquareSentinel"
			return r.IsoGridSquare
		end
		Square.highlight = function(r, durationMs, opts)
			seen.highlight = { r = r, durationMs = durationMs, opts = opts }
			return true
		end

		Vehicle:wrap(record)

		assert.equals("IsoGridSquareSentinel", record:getIsoGridSquare())
		assert.equals(record, seen.getIsoGridSquare)

		assert.is_true(record:highlight(1234, { color = { 1, 0, 0, 1 } }))
		assert.equals(record, seen.highlight.r)
		assert.equals(1234, seen.highlight.durationMs)
	end)
end)

