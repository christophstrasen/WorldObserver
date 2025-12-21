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

local Items = require("WorldObserver/facts/items")

describe("items collector", function()
	it("collects container items at depth=1 and honors cooldown", function()
		local nestedItem = {
			getID = function()
				return 401
			end,
			getFullType = function()
				return "Base.Screws"
			end,
			getType = function()
				return "Screws"
			end,
		}
		local nestedContainer = {
			getItems = function()
				return { nestedItem }
			end,
		}
		local containedContainerItem = {
			getID = function()
				return 301
			end,
			getFullType = function()
				return "Base.Bag"
			end,
			getType = function()
				return "Bag"
			end,
			getItemContainer = function()
				return nestedContainer
			end,
		}
		local containedItem = {
			getID = function()
				return 201
			end,
			getFullType = function()
				return "Base.Nails"
			end,
			getType = function()
				return "Nails"
			end,
		}
		local container = {
			getItems = function()
				return { containedItem, containedContainerItem }
			end,
		}
		local containerItem = {
			getID = function()
				return 111
			end,
			getFullType = function()
				return "Base.Toolbox"
			end,
			getType = function()
				return "Toolbox"
			end,
			getItemContainer = function()
				return container
			end,
		}
		local worldItem = {
			getID = function()
				return 100
			end,
			getItem = function()
				return containerItem
			end,
		}
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
			getWorldObjects = function()
				return { worldItem }
			end,
		}

		local emitted = {}
		local ctx = {
			items = Items,
			state = {},
			emitFn = function(record)
				emitted[#emitted + 1] = record
			end,
			headless = true,
			recordOpts = { includeContainerItems = true },
		}
		local cursor = { source = "probe", color = { 1, 1, 1 }, alpha = 1 }
		local effective = { cooldown = 5 }

		Items._internal.itemsCollector(ctx, cursor, square, nil, 1000, effective)
		assert.equals(3, #emitted)

		local seen = {}
		for _, record in ipairs(emitted) do
			seen[record.itemId] = true
		end
		assert.is_true(seen[100])
		assert.is_true(seen[201])
		assert.is_true(seen[301])
		assert.is_nil(seen[401])

		Items._internal.itemsCollector(ctx, cursor, square, nil, 1000, effective)
		assert.equals(3, #emitted)
	end)
end)
