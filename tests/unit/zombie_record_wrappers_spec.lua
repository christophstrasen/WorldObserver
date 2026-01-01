_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("WorldObserver zombie record wrapping", function()
	local WorldObserver

	before_each(function()
		WorldObserver = reload("WorldObserver")
	end)

	it("wrap refuses non-table", function()
		local Zombie = WorldObserver.helpers.zombie
		local wrapped, err = Zombie:wrap(nil)
		assert.is_nil(wrapped)
		assert.equals("badRecord", err)
	end)

	it("wrap decorates record in-place and is idempotent", function()
		local Zombie = WorldObserver.helpers.zombie
		local record = { zombieId = 123 }

		local wrapped, err = Zombie:wrap(record)
		assert.is_nil(err)
		assert.equals(record, wrapped)
		assert.is_not_nil(getmetatable(record))

		local wrapped2, err2 = Zombie:wrap(record)
		assert.is_nil(err2)
		assert.equals(record, wrapped2)
	end)

	it("wrap refuses when record already has a metatable", function()
		local Zombie = WorldObserver.helpers.zombie
		local record = setmetatable({}, { __index = {} })

		local wrapped, err = Zombie:wrap(record)
		assert.is_nil(wrapped)
		assert.equals("hasMetatable", err)
	end)

	it("wrapper methods delegate via helper tables", function()
		local Zombie = WorldObserver.helpers.zombie
		local record = { zombieId = 7, outfitName = "Police" }

		local seen = {}
		Zombie.record.getIsoZombie = function(r)
			seen.getIsoZombie = r
			r.IsoZombie = "IsoZombieSentinel"
			return r.IsoZombie
		end
		Zombie.record.zombieHasOutfit = function(r, expected)
			seen.hasOutfit = { r = r, expected = expected }
			return expected == "Police%"
		end
		Zombie.highlight = function(r, durationMs, opts)
			seen.highlight = { r = r, durationMs = durationMs, opts = opts }
			return true
		end

		Zombie:wrap(record)

		assert.equals("IsoZombieSentinel", record:getIsoZombie())
		assert.equals(record, seen.getIsoZombie)

		assert.is_true(record:hasOutfit("Police%"))
		assert.equals(record, seen.hasOutfit.r)
		assert.equals("Police%", seen.hasOutfit.expected)

		assert.is_true(record:highlight(1234, { color = { 1, 0, 0, 1 } }))
		assert.equals(record, seen.highlight.r)
		assert.equals(1234, seen.highlight.durationMs)
	end)
end)

