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


local Record = require("WorldObserver/facts/squares/record")

describe("squares records", function()
	it("does not stamp sourceTime by default", function()
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
			getID = function()
				return 1234
			end,
			hasBlood = function()
				return false
			end,
		}

		local record = Record.makeSquareRecord(square, "probe")
		assert.is_table(record)
		assert.equals("x1y2z0", record.tileLocation)
		assert.is_nil(record.sourceTime)
	end)
end)
