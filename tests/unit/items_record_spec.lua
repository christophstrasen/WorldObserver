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

local Record = require("WorldObserver/facts/items/record")

describe("items records", function()
	it("uses world item id and square coords", function()
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
		local worldItem = {
			getID = function()
				return 123
			end,
			getSquare = function()
				return square
			end,
		}
		local item = {
			getID = function()
				return 456
			end,
			getType = function()
				return "Apple"
			end,
			getFullType = function()
				return "Base.Apple"
			end,
		}

		local record = Record.makeItemRecord(item, square, "probe", { worldItem = worldItem })
		assert.is_table(record)
		assert.equals(123, record.itemId)
		assert.equals("123", record.woKey)
		assert.equals(10, record.x)
		assert.equals(20, record.y)
		assert.equals(0, record.z)
		assert.equals("x10y20z0", record.tileLocation)
		assert.equals(999, record.squareId)
		assert.equals("Apple", record.itemType)
		assert.equals("Base.Apple", record.itemFullType)
		assert.is_nil(record.sourceTime)
	end)

	it("includes container metadata and uses inventory id when world id is missing", function()
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
		local containerItem = {
			getID = function()
				return 900
			end,
			getType = function()
				return "Bag"
			end,
			getFullType = function()
				return "Base.Bag"
			end,
		}
		local item = {
			getID = function()
				return 321
			end,
			getType = function()
				return "Nails"
			end,
			getFullType = function()
				return "Base.Nails"
			end,
		}

		local record = Record.makeItemRecord(item, square, "player", {
			containerItem = containerItem,
		})
		assert.is_table(record)
		assert.equals(321, record.itemId)
		assert.equals("321", record.woKey)
		assert.equals("x1y2z0", record.tileLocation)
		assert.equals(900, record.containerItemId)
		assert.equals("Bag", record.containerItemType)
		assert.equals("Base.Bag", record.containerItemFullType)
		assert.is_nil(record.sourceTime)
	end)
end)
