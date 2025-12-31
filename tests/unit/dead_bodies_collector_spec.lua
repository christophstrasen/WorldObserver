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

local DeadBodies = require("WorldObserver/facts/dead_bodies")

describe("dead bodies collector", function()
	it("collects bodies and honors cooldown", function()
		local body1 = {
			getObjectID = function()
				return "DeadBody-1"
			end,
		}
		local body2 = {
			getObjectID = function()
				return "DeadBody-2"
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
			getDeadBody = function()
				return body1
			end,
			getDeadBodies = function()
				return { body1, body2 }
			end,
		}

		local emitted = {}
		local ctx = {
			deadBodies = DeadBodies,
			state = {},
			emitFn = function(record)
				emitted[#emitted + 1] = record
			end,
			headless = true,
			recordOpts = { includeIsoDeadBody = false },
		}
		local cursor = { source = "probe", color = { 1, 1, 1 }, alpha = 1 }
		local effective = { cooldown = 5 }

		DeadBodies._internal.deadBodiesCollector(ctx, cursor, square, nil, 1000, effective)
		assert.equals(2, #emitted)
		assert.equals("DeadBody-1", emitted[1].deadBodyId)
		assert.equals("DeadBody-2", emitted[2].deadBodyId)

		-- Same tick/time: cooldown blocks repeats.
		DeadBodies._internal.deadBodiesCollector(ctx, cursor, square, nil, 1000, effective)
		assert.equals(2, #emitted)
	end)
end)
