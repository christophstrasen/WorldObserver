_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("WorldObserver item record wrapping", function()
	local WorldObserver

	before_each(function()
		WorldObserver = reload("WorldObserver")
	end)

	it("wrap decorates record in-place", function()
		local Item = WorldObserver.helpers.item
		local record = { itemId = 123 }
		local wrapped, err = Item:wrap(record)
		assert.is_nil(err)
		assert.equals(record, wrapped)
		assert.is_not_nil(getmetatable(record))
	end)

	it("wrapper methods delegate via helper tables", function()
		local Item = WorldObserver.helpers.item
		local Square = WorldObserver.helpers.square
		local record = { itemId = 7, itemType = "Bandage", itemFullType = "Base.Bandage" }

		local seen = {}
		Item.record.itemTypeIs = function(r, wanted)
			seen.typeIs = { r = r, wanted = wanted }
			return wanted == "Bandage"
		end
		Item.record.itemFullTypeIs = function(r, wanted)
			seen.fullTypeIs = { r = r, wanted = wanted }
			return wanted == "Base.Bandage"
		end
		Square.record.getIsoGridSquare = function(r)
			seen.getIsoGridSquare = r
			r.IsoGridSquare = "IsoGridSquareSentinel"
			return r.IsoGridSquare
		end
		Square.highlight = function(r, durationMs, opts)
			seen.highlight = { r = r, durationMs = durationMs, opts = opts }
			return true
		end

		Item:wrap(record)

		assert.is_true(record:typeIs("Bandage"))
		assert.equals(record, seen.typeIs.r)
		assert.equals("Bandage", seen.typeIs.wanted)

		assert.is_true(record:fullTypeIs("Base.Bandage"))
		assert.equals(record, seen.fullTypeIs.r)
		assert.equals("Base.Bandage", seen.fullTypeIs.wanted)

		assert.equals("IsoGridSquareSentinel", record:getIsoGridSquare())
		assert.equals(record, seen.getIsoGridSquare)

		assert.is_true(record:highlight(1234, { color = { 1, 0, 0, 1 } }))
		assert.equals(record, seen.highlight.r)
		assert.equals(1234, seen.highlight.durationMs)
	end)
end)

