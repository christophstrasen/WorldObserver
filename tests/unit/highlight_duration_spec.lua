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

local Highlight = require("WorldObserver/helpers/highlight")

describe("highlight duration", function()
	it("uses the cadence rule max(staleness,cooldown)/2", function()
		assert.equals(5000, Highlight.durationMsFromCadenceSeconds(10, 3))
		assert.equals(150000, Highlight.durationMsFromCadenceSeconds(0, 300))
		assert.equals(150000, Highlight.durationMsFromCadenceSeconds(300, 0))
	end)

	it("treats durationMsFromCooldownSeconds as cooldown/2", function()
		assert.equals(150000, Highlight.durationMsFromCooldownSeconds(300))
		assert.equals(0, Highlight.durationMsFromCooldownSeconds(0))
	end)

	it("accepts band tables by using desired when present", function()
		assert.equals(
			150000,
			Highlight.durationMsFromCadenceSeconds({ desired = 5, tolerable = 15 }, { desired = 300, tolerable = 600 })
		)
	end)

	it("computes duration from effective interest tables", function()
		assert.equals(150000, Highlight.durationMsFromEffectiveCadence({ staleness = 5, cooldown = 300 }))
		assert.equals(0, Highlight.durationMsFromEffectiveCadence(nil))
	end)
end)
