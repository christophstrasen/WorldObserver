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

describe("WorldObserver.debug.printObservation formatting", function()
	it("prints join-like observations with empty sides clearly", function()
		local Debug = require("WorldObserver/debug")
		local api = Debug.new({}, {})

		local lines = api.printObservation({
			RxMeta = { shape = "join_result", schemaMap = { square = {}, zombie = {} } },
			square = {},
			zombie = {
				extra1 = 1,
				extra2 = 2,
				extra3 = 3,
				extra4 = 4,
				extra5 = 5,
				extra6 = 6,
				extra7 = 7,
				extra8 = 8,
				extra9 = 9,
				extra10 = 10,
				RxMeta = { schema = "zombie", id = 1, sourceTime = 123 },
			},
		}, { prefix = "[test]", printFn = function() end })

		assert.is_truthy(lines[1]:match("^%[test%]"))
		assert.is_truthy(lines[2]:match("rxMeta:"))
		assert.is_truthy(lines[2]:match("shape=join_result"))
		assert.is_truthy(lines[2]:match("schemas=square,zombie"))
		assert.is_truthy(table.concat(lines, "\n"):match("\n%s+square: <empty>"))
		assert.is_truthy(table.concat(lines, "\n"):match("\n%s+zombie:"))
	end)
end)
