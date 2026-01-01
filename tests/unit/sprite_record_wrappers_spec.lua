_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("WorldObserver sprite record wrapping", function()
	local WorldObserver

	before_each(function()
		WorldObserver = reload("WorldObserver")
	end)

	it("wrap decorates record in-place", function()
		local Sprite = WorldObserver.helpers.sprite
		local record = { spriteKey = "x1y2z0#0" }
		local wrapped, err = Sprite:wrap(record)
		assert.is_nil(err)
		assert.equals(record, wrapped)
		assert.is_not_nil(getmetatable(record))
	end)

	it("wrapper methods delegate via helper tables", function()
		local Sprite = WorldObserver.helpers.sprite
		local Square = WorldObserver.helpers.square
		local record = { spriteKey = "x1y2z0#0", spriteName = "blabla", spriteId = 42 }

		local seen = {}
		Sprite.record.spriteNameIs = function(r, wanted)
			seen.nameIs = { r = r, wanted = wanted }
			return wanted == "blabla"
		end
		Sprite.record.spriteIdIs = function(r, wanted)
			seen.idIs = { r = r, wanted = wanted }
			return tostring(wanted) == "42"
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
		Sprite.record.removeSpriteObject = function(r)
			seen.removeSpriteObject = r
			return true
		end

		Sprite:wrap(record)

		assert.is_true(record:nameIs("blabla"))
		assert.equals(record, seen.nameIs.r)
		assert.equals("blabla", seen.nameIs.wanted)

		assert.is_true(record:idIs(42))
		assert.equals(record, seen.idIs.r)
		assert.equals(42, seen.idIs.wanted)

		assert.equals("IsoGridSquareSentinel", record:getIsoGridSquare())
		assert.equals(record, seen.getIsoGridSquare)

		assert.is_true(record:highlight(1234, { color = { 1, 0, 0, 1 } }))
		assert.equals(record, seen.highlight.r)
		assert.equals(1234, seen.highlight.durationMs)

		assert.is_true(record:removeSpriteObject())
		assert.equals(record, seen.removeSpriteObject)
	end)
end)

