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

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("WorldObserver observations.sprites()", function()
	local WorldObserver

	before_each(function()
		WorldObserver = reload("WorldObserver")
	end)

	it("spriteFilter passes the sprite record into the predicate", function()
		local received = {}
		local SpriteHelper = WorldObserver.helpers.sprite.record

			local stream = WorldObserver.observations:sprites():spriteFilter(function(spriteRecord, observation)
				assert.is_table(observation)
				assert.is_table(spriteRecord)
				assert.equals(spriteRecord, observation.sprite)
				return SpriteHelper.spriteNameIs(spriteRecord, "fixtures_bathroom_01_0")
			end)
		stream:subscribe(function(row)
			received[#received + 1] = row
		end)

		WorldObserver._internal.facts:emit("sprites", {
			spriteKey = "fixtures_bathroom_01_0ID120000x1y2z0i3",
			spriteName = "fixtures_bathroom_01_0",
			spriteId = 120000,
			x = 1,
			y = 2,
			z = 0,
			objectIndex = 3,
			sourceTime = 50,
			source = "event",
		})
		WorldObserver._internal.facts:emit("sprites", {
			spriteKey = "floors_interior_tilesandwood_01_0ID135000x1y2z0i4",
			spriteName = "floors_interior_tilesandwood_01_0",
			spriteId = 135000,
			x = 1,
			y = 2,
			z = 0,
			objectIndex = 4,
			sourceTime = 60,
			source = "event",
		})

		assert.is_equal(1, #received)
		assert.is_equal("fixtures_bathroom_01_0", received[1].sprite.spriteName)
	end)

	it("removeSpriteObject calls RemoveTileObject when references exist", function()
		local removed = { called = false, obj = nil }
		local isoObject = {}
		local isoGridSquare = {
			getX = function()
				return 1
			end,
			getY = function()
				return 2
			end,
			getZ = function()
				return 0
			end,
			RemoveTileObject = function(_, obj)
				removed.called = true
				removed.obj = obj
			end,
		}

		local stream = WorldObserver.observations:sprites():removeSpriteObject()
		local received = {}
		stream:subscribe(function(row)
			received[#received + 1] = row
		end)

		WorldObserver._internal.facts:emit("sprites", {
			spriteKey = "fixtures_bathroom_01_0ID120000x1y2z0i3",
			spriteName = "fixtures_bathroom_01_0",
			spriteId = 120000,
			x = 1,
			y = 2,
			z = 0,
			objectIndex = 3,
			sourceTime = 50,
			source = "event",
			IsoObject = isoObject,
			IsoGridSquare = isoGridSquare,
		})

		assert.is_true(removed.called)
		assert.equals(isoObject, removed.obj)
		assert.equals(1, #received)
	end)

end)
