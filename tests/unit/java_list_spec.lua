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

local JavaList = require("WorldObserver/helpers/java_list")

describe("helpers/java_list", function()
	it("does not throw if tostring(list) throws", function()
		local bad = setmetatable({}, {
			__tostring = function()
				error("boom")
			end,
		})

		-- Should not throw, should treat it as a non-list.
		assert.equals(0, JavaList.size(bad))
		assert.is_nil(JavaList.get(bad, 1))
	end)
end)

