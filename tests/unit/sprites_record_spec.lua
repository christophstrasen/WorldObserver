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

local Record = require("WorldObserver/facts/sprites/record")

describe("sprite records", function()
	it("uses sprite id and object index in the key", function()
		local square = {
			getX = function()
				return 10
			end,
			getY = function()
				return 20
			end,
			getZ = function()
				return 0
			end,
			getID = function()
				return 999
			end,
		}
		local sprite = {
			getName = function()
				return "fixtures_bathroom_01_0"
			end,
			getID = function()
				return 120000
			end,
		}
		local isoObject = {
			getSprite = function()
				return sprite
			end,
			getSquare = function()
				return square
			end,
			getObjectIndex = function()
				return 3
			end,
		}

		local record = Record.makeSpriteRecord(isoObject, square, "probe")
		assert.is_table(record)
		assert.equals("fixtures_bathroom_01_0ID120000x10y20z0i3", record.spriteKey)
		assert.equals("fixtures_bathroom_01_0ID120000x10y20z0i3", record.woKey)
		assert.equals("fixtures_bathroom_01_0", record.spriteName)
		assert.equals(120000, record.spriteId)
		assert.equals(10, record.x)
		assert.equals(20, record.y)
		assert.equals(0, record.z)
		assert.equals("x10y20z0", record.tileLocation)
		assert.equals(999, record.squareId)
		assert.equals(3, record.objectIndex)
		assert.is_nil(record.sourceTime)
		assert.equals("probe", record.source)
	end)

	it("includes IsoObject and IsoGridSquare on the base record", function()
		local square = {
			getX = function()
				return 1
			end,
			getY = function()
				return 2
			end,
			getZ = function()
				return 0
			end,
		}
		local sprite = {
			getName = function()
				return "fixtures_bathroom_01_0"
			end,
			getID = function()
				return 120000
			end,
		}
		local isoObject = {
			getSprite = function()
				return sprite
			end,
			getSquare = function()
				return square
			end,
			getObjectIndex = function()
				return 1
			end,
		}

		local record = Record.makeSpriteRecord(isoObject, square, "player")
		assert.is_table(record)
		assert.equals("fixtures_bathroom_01_0ID120000x1y2z0i1", record.woKey)
		assert.equals(isoObject, record.IsoObject)
		assert.equals(square, record.IsoGridSquare)
	end)
end)
