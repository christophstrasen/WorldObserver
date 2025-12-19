package.path = table.concat({
	"Contents/mods/WorldObserver/42/media/lua/shared/?.lua",
	"Contents/mods/WorldObserver/42/media/lua/shared/?/init.lua",
	"external/LQR/?.lua",
	"external/LQR/?/init.lua",
	"external/lua-reactivex/?.lua",
	"external/lua-reactivex/?/init.lua",
	package.path,
}, ";")

local Registry = require("WorldObserver/interest/registry")

describe("interest registry", function()
	it("merges desired/tolerable bands across mods", function()
		local reg = Registry.new({ ttlSeconds = 100 })
		reg:declare("modA", "near", { type = "squares.nearPlayer", staleness = { desired = 10, tolerable = 20 }, radius = { desired = 5, tolerable = 3 }, cooldown = { desired = 30, tolerable = 60 } })
		reg:declare("modB", "near", { type = "squares.nearPlayer", staleness = { desired = 8, tolerable = 15 }, radius = { desired = 7, tolerable = 4 }, cooldown = { desired = 25, tolerable = 40 } })

		local merged = reg:effective("squares.nearPlayer")
		assert.equals(8, merged.staleness.desired) -- min desired (stricter)
		assert.equals(15, merged.staleness.tolerable) -- min tolerable
		assert.equals(7, merged.radius.desired) -- max desired
		assert.equals(4, merged.radius.tolerable) -- max tolerable
		assert.equals(25, merged.cooldown.desired) -- min desired
		assert.equals(40, merged.cooldown.tolerable) -- min tolerable
	end)

	it("expires leases by TTL", function()
		local reg = Registry.new({ ttlSeconds = 1 })
		reg:declare("modA", "near", { type = "squares.nearPlayer", staleness = 5 }, { nowMs = 0 })
		local merged = reg:effective("squares.nearPlayer", 0)
		assert.is_table(merged)
		local mergedExpired = reg:effective("squares.nearPlayer", 2000)
		assert.is_nil(mergedExpired)
	end)

	it("can override TTL per declaration", function()
		local reg = Registry.new({ ttlSeconds = 1 })
		reg:declare("modA", "near", { type = "squares.nearPlayer", staleness = 5 }, { nowMs = 0, ttlSeconds = 10 })
		assert.is_table(reg:effective("squares.nearPlayer", 5000))
		assert.is_nil(reg:effective("squares.nearPlayer", 11000))
	end)

	it("revoke stops a lease", function()
		local reg = Registry.new({ ttlSeconds = 100 })
		local lease = reg:declare("modA", "near", { staleness = 5 }, { nowMs = 0 })
		reg:revoke("modA", "near")
		local merged = reg:effective("squares.nearPlayer")
		assert.is_nil(merged)
		lease:renew() -- should not reinsert
		merged = reg:effective("squares.nearPlayer")
		assert.is_nil(merged)
	end)

	it("renew extends TTL and supports ':' call style", function()
		local reg = Registry.new({ ttlSeconds = 1 })
		local lease = reg:declare("modA", "near", { type = "squares.nearPlayer", staleness = 5 }, { nowMs = 0 })
		assert.is_table(reg:effective("squares.nearPlayer", 500))

		-- Renew at t=900ms to extend expiry past 1000ms.
		lease:renew(900)
		assert.is_table(reg:effective("squares.nearPlayer", 1500))

		-- Eventually it still expires if not renewed again.
		assert.is_nil(reg:effective("squares.nearPlayer", 2500))
	end)

	it("lease:declare supports ':' call style and keeps TTL", function()
		local reg = Registry.new({ ttlSeconds = 1 })
		local lease = reg:declare("modA", "near", { type = "squares.nearPlayer", staleness = 5 }, { nowMs = 0, ttlSeconds = 2 })
		assert.is_table(reg:effective("squares.nearPlayer", 1500))
		lease:declare({ type = "squares.nearPlayer", staleness = 6 }, { nowMs = 500 })
		assert.is_table(reg:effective("squares.nearPlayer", 2000))
		assert.is_nil(reg:effective("squares.nearPlayer", 2600))
	end)
end)
