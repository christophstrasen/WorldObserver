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

local Record = require("WorldObserver/facts/dead_bodies/record")

describe("dead body records", function()
	it("uses object id and square coords", function()
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
		local body = {
			getObjectID = function()
				return 42
			end,
		}

		local record = Record.makeDeadBodyRecord(body, square, "probe")
		assert.is_table(record)
		assert.equals(42, record.deadBodyId)
		assert.equals("42", record.woKey)
		assert.equals(10, record.x)
		assert.equals(20, record.y)
		assert.equals(0, record.z)
		assert.equals("x10y20z0", record.tileLocation)
		assert.equals(999, record.squareId)
		assert.is_nil(record.sourceTime)
		assert.equals("probe", record.source)
	end)

	it("includes IsoDeadBody when requested", function()
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
		local body = {
			getObjectID = function()
				return 77
			end,
			getSquare = function()
				return square
			end,
		}

		local record = Record.makeDeadBodyRecord(body, nil, "player", {
			includeIsoDeadBody = true,
		})
		assert.is_table(record)
		assert.equals("77", record.woKey)
		assert.equals(body, record.IsoDeadBody)
	end)
end)
