_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("WorldObserver room record wrapping", function()
	local WorldObserver

	before_each(function()
		WorldObserver = reload("WorldObserver")
	end)

	it("wrap decorates record in-place", function()
		local Room = WorldObserver.helpers.room
		local record = { roomId = "x1y2z0" }
		local wrapped, err = Room:wrap(record)
		assert.is_nil(err)
		assert.equals(record, wrapped)
		assert.is_not_nil(getmetatable(record))
	end)

	it("wrapper methods delegate via helper tables", function()
		local Room = WorldObserver.helpers.room
		local record = { roomId = "x1y2z0", name = "kitchen" }

		local seen = {}
		Room.record.roomTypeIs = function(r, wanted)
			seen.nameIs = { r = r, wanted = wanted }
			return wanted == "kitchen"
		end

		Room:wrap(record)

		assert.is_true(record:nameIs("kitchen"))
		assert.equals(record, seen.nameIs.r)
		assert.equals("kitchen", seen.nameIs.wanted)
	end)
end)

