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

local Sprites = require("WorldObserver/facts/sprites")

describe("sprites collector", function()
	it("collects matching sprites and honors cooldown", function()
		local matchSprite = {
			getName = function()
				return "fixtures_bathroom_01_0"
			end,
			getID = function()
				return 120000
			end,
		}
		local otherSprite = {
			getName = function()
				return "floors_interior_tilesandwood_01_0"
			end,
			getID = function()
				return 135000
			end,
		}
		local matchObject = {
			getSprite = function()
				return matchSprite
			end,
			getObjectIndex = function()
				return 2
			end,
		}
		local otherObject = {
			getSprite = function()
				return otherSprite
			end,
			getObjectIndex = function()
				return 3
			end,
		}
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
			getObjects = function()
				return { matchObject, otherObject }
			end,
		}

		local emitted = {}
		local ctx = {
			sprites = Sprites,
			state = {},
			emitFn = function(record)
				emitted[#emitted + 1] = record
			end,
			headless = true,
		}
		local cursor = { source = "probe", color = { 1, 1, 1 }, alpha = 1 }
		local effective = { cooldown = 5, spriteNames = { "fixtures_bathroom_01_0" } }

		Sprites._internal.spritesCollector(ctx, cursor, square, nil, 1000, effective)
		assert.equals(1, #emitted)
		assert.equals("fixtures_bathroom_01_0", emitted[1].spriteName)
		assert.equals(120000, emitted[1].spriteId)

		Sprites._internal.spritesCollector(ctx, cursor, square, nil, 1000, effective)
		assert.equals(1, #emitted)
	end)

	it("collects sprites matching prefix wildcards", function()
		local matchSprite = {
			getName = function()
				return "fixtures_bathroom_01_0"
			end,
			getID = function()
				return 120000
			end,
		}
		local otherSprite = {
			getName = function()
				return "floors_interior_tilesandwood_01_0"
			end,
			getID = function()
				return 135000
			end,
		}
		local matchObject = {
			getSprite = function()
				return matchSprite
			end,
			getObjectIndex = function()
				return 2
			end,
		}
		local otherObject = {
			getSprite = function()
				return otherSprite
			end,
			getObjectIndex = function()
				return 3
			end,
		}
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
			getObjects = function()
				return { matchObject, otherObject }
			end,
		}

		local emitted = {}
		local ctx = {
			sprites = Sprites,
			state = {},
			emitFn = function(record)
				emitted[#emitted + 1] = record
			end,
			headless = true,
		}
		local cursor = { source = "probe", color = { 1, 1, 1 }, alpha = 1 }
		local effective = { cooldown = 0, spriteNames = { "fixtures_bathroom_01_%" } }

		Sprites._internal.spritesCollector(ctx, cursor, square, nil, 1000, effective)
		assert.equals(1, #emitted)
		assert.equals("fixtures_bathroom_01_0", emitted[1].spriteName)
	end)

	it("collects all sprites for '%' wildcard", function()
		local matchSprite = {
			getName = function()
				return "fixtures_bathroom_01_0"
			end,
			getID = function()
				return 120000
			end,
		}
		local otherSprite = {
			getName = function()
				return "floors_interior_tilesandwood_01_0"
			end,
			getID = function()
				return 135000
			end,
		}
		local matchObject = {
			getSprite = function()
				return matchSprite
			end,
			getObjectIndex = function()
				return 2
			end,
		}
		local otherObject = {
			getSprite = function()
				return otherSprite
			end,
			getObjectIndex = function()
				return 3
			end,
		}
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
			getObjects = function()
				return { matchObject, otherObject }
			end,
		}

		local emitted = {}
		local ctx = {
			sprites = Sprites,
			state = {},
			emitFn = function(record)
				emitted[#emitted + 1] = record
			end,
			headless = true,
		}
		local cursor = { source = "probe", color = { 1, 1, 1 }, alpha = 1 }
		local effective = { cooldown = 0, spriteNames = { "%" } }

		Sprites._internal.spritesCollector(ctx, cursor, square, nil, 1000, effective)
		assert.equals(2, #emitted)
	end)
end)
