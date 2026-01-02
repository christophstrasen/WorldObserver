_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local Registry = require("WorldObserver/interest/registry")

describe("interest registry", function()
	it("merges desired/tolerable bands across mods within a target bucket", function()
		local reg = Registry.new({ ttlSeconds = 100 })
		reg:declare("modA", "near", {
			type = "squares",
			scope = "near",
			target = { player = { id = 0 } },
			staleness = { desired = 10, tolerable = 20 },
			radius = { desired = 5, tolerable = 3 },
			cooldown = { desired = 30, tolerable = 60 },
		})
		reg:declare("modB", "near", {
			type = "squares",
			scope = "near",
			target = { player = { id = 0 } },
			staleness = { desired = 8, tolerable = 15 },
			radius = { desired = 7, tolerable = 4 },
			cooldown = { desired = 25, tolerable = 40 },
		})

		local buckets = reg:effectiveBuckets("squares")
		assert.equals(1, #buckets)
		local merged = buckets[1].merged
		assert.equals(8, merged.staleness.desired) -- min desired (stricter)
		assert.equals(15, merged.staleness.tolerable) -- min tolerable
		assert.equals(7, merged.radius.desired) -- max desired
		assert.equals(4, merged.radius.tolerable) -- max tolerable
		assert.equals(25, merged.cooldown.desired) -- min desired
		assert.equals(40, merged.cooldown.tolerable) -- min tolerable
	end)

	it("keeps separate buckets for different targets", function()
		local reg = Registry.new({ ttlSeconds = 100 })
		reg:declare("modA", "near", { type = "squares", scope = "near", target = { player = { id = 0 } }, staleness = 5 })
		reg:declare("modB", "near", { type = "squares", scope = "near", target = { square = { x = 10, y = 12, z = 0 } }, staleness = 8 })

		local buckets = reg:effectiveBuckets("squares")
		assert.equals(2, #buckets)
	end)

	it("expires leases by TTL", function()
		local reg = Registry.new({ ttlSeconds = 1 })
		reg:declare("modA", "near", { type = "squares", scope = "near", staleness = 5 }, { nowMs = 0 })
		local merged = reg:effective("squares", 0, { bucketKey = "near:player:0" })
		assert.is_table(merged)
		local mergedExpired = reg:effective("squares", 2000, { bucketKey = "near:player:0" })
		assert.is_nil(mergedExpired)
	end)

	it("can override TTL per declaration", function()
		local reg = Registry.new({ ttlSeconds = 1 })
		reg:declare("modA", "near", { type = "squares", scope = "near", staleness = 5 }, { nowMs = 0, ttlSeconds = 10 })
		assert.is_table(reg:effective("squares", 5000, { bucketKey = "near:player:0" }))
		assert.is_nil(reg:effective("squares", 11000, { bucketKey = "near:player:0" }))
	end)

	it("revoke stops a lease", function()
		local reg = Registry.new({ ttlSeconds = 100 })
		local lease = reg:declare("modA", "near", { type = "squares", scope = "near", staleness = 5 }, { nowMs = 0 })
		reg:revoke("modA", "near")
		local merged = reg:effective("squares", nil, { bucketKey = "near:player:0" })
		assert.is_nil(merged)
		lease:renew() -- should not reinsert
		merged = reg:effective("squares", nil, { bucketKey = "near:player:0" })
		assert.is_nil(merged)
	end)

	it("renew extends TTL and supports ':' call style", function()
		local reg = Registry.new({ ttlSeconds = 1 })
		local lease = reg:declare("modA", "near", { type = "squares", scope = "near", staleness = 5 }, { nowMs = 0 })
		assert.is_table(reg:effective("squares", 500, { bucketKey = "near:player:0" }))

		-- Renew at t=900ms to extend expiry past 1000ms.
		lease:renew(900)
		assert.is_table(reg:effective("squares", 1500, { bucketKey = "near:player:0" }))

		-- Eventually it still expires if not renewed again.
		assert.is_nil(reg:effective("squares", 2500, { bucketKey = "near:player:0" }))
	end)

	it("lease:declare supports ':' call style and keeps TTL", function()
		local reg = Registry.new({ ttlSeconds = 1 })
		local lease = reg:declare("modA", "near", { type = "squares", scope = "near", staleness = 5 }, { nowMs = 0, ttlSeconds = 2 })
		assert.is_table(reg:effective("squares", 1500, { bucketKey = "near:player:0" }))
		lease:declare({ type = "squares", scope = "near", staleness = 6 }, { nowMs = 500 })
		assert.is_table(reg:effective("squares", 2000, { bucketKey = "near:player:0" }))
		assert.is_nil(reg:effective("squares", 2600, { bucketKey = "near:player:0" }))
	end)

	it("defaults squares scope to near and target to player 0", function()
		local reg = Registry.new({ ttlSeconds = 100 })
		reg:declare("modA", "defaults", { type = "squares" })

		local merged = reg:effective("squares", nil, { bucketKey = "near:player:0" })
		assert.is_table(merged)
		assert.equals("near", merged.scope)
		assert.is_table(merged.target)
		assert.equals("player", merged.target.kind)
		assert.equals(0, merged.target.id)
	end)

	it("squares onLoad ignores target/radius/staleness and uses onLoad bucket", function()
		local reg = Registry.new({ ttlSeconds = 100 })
		reg:declare("modA", "load", {
			type = "squares",
			scope = "onLoad",
			target = { player = { id = 1 } },
			radius = { desired = 10, tolerable = 12 },
			staleness = { desired = 5, tolerable = 7 },
			cooldown = { desired = 2, tolerable = 3 },
		})

		local merged = reg:effective("squares", nil, { bucketKey = "onLoad" })
		assert.is_table(merged)
		assert.equals("onLoad", merged.scope)
		assert.is_nil(merged.target)
		assert.equals(0, merged.radius.desired)
		assert.equals(0, merged.staleness.desired)
		assert.equals(2, merged.cooldown.desired)
	end)

	it("normalizes zombies scope to allLoaded and ignores target", function()
		local reg = Registry.new({ ttlSeconds = 100 })
		reg:declare("modA", "zeds", {
			type = "zombies",
			scope = "near",
			target = { player = { id = 0 } },
			staleness = 3,
		})

		local merged = reg:effective("zombies", nil, { bucketKey = "allLoaded" })
		assert.is_table(merged)
		assert.equals("allLoaded", merged.scope)
		assert.is_nil(merged.target)
		assert.equals(3, merged.staleness.desired)
	end)

	it("rooms allLoaded ignores radius and zRange", function()
		local reg = Registry.new({ ttlSeconds = 100 })
		reg:declare("modA", "rooms", {
			type = "rooms",
			scope = "allLoaded",
			staleness = 30,
			radius = { desired = 8, tolerable = 4 },
			zRange = { desired = 2, tolerable = 1 },
		})

		local merged = reg:effective("rooms", nil, { bucketKey = "allLoaded" })
		assert.is_table(merged)
		assert.equals(30, merged.staleness.desired)
		assert.equals(0, merged.radius.desired)
		assert.equals(0, merged.zRange.desired)
	end)

	it("square target buckets include modId and coordinates", function()
		local reg = Registry.new({ ttlSeconds = 100 })
		reg:declare("modA", "square", { type = "squares", scope = "near", target = { square = { x = 10, y = 12, z = 0 } } })
		reg:declare("modB", "square", { type = "squares", scope = "near", target = { square = { x = 10, y = 12, z = 0 } } })

		local buckets = reg:effectiveBuckets("squares")
		assert.equals(2, #buckets)
		local keys = {}
		for _, entry in ipairs(buckets) do
			keys[entry.bucketKey] = true
		end
		assert.is_true(keys["near:square:modA:10:12:0"])
		assert.is_true(keys["near:square:modB:10:12:0"])
	end)

	it("supports rooms onSeeNewRoom as an event scope bucket", function()
		local reg = Registry.new({ ttlSeconds = 100 })
		reg:declare("modA", "see", {
			type = "rooms",
			scope = "onSeeNewRoom",
			cooldown = { desired = 1, tolerable = 2 },
		})

		local merged = reg:effective("rooms", nil, { bucketKey = "onSeeNewRoom" })
		assert.is_table(merged)
		assert.equals("rooms", merged.type)
		assert.equals("onSeeNewRoom", merged.scope)
		assert.is_nil(merged.target)
		assert.equals(0, merged.staleness.desired)
		assert.equals(0, merged.radius.desired)
		assert.equals(0, merged.zRange.desired)
		assert.equals(1, merged.cooldown.desired)
	end)

	it("supports players onPlayerChangeRoom as an event scope bucket", function()
		local reg = Registry.new({ ttlSeconds = 100 })
		reg:declare("modA", "change", {
			type = "players",
			scope = "onPlayerChangeRoom",
			cooldown = { desired = 1, tolerable = 2 },
		})

		local merged = reg:effective("players", nil, { bucketKey = "onPlayerChangeRoom" })
		assert.is_table(merged)
		assert.equals("players", merged.type)
		assert.equals("onPlayerChangeRoom", merged.scope)
		assert.is_nil(merged.target)
		assert.equals(0, merged.staleness.desired)
		assert.equals(0, merged.radius.desired)
		assert.equals(0, merged.zRange.desired)
		assert.equals(1, merged.cooldown.desired)
	end)

	it("supports rooms onPlayerChangeRoom as a per-player bucket", function()
		local reg = Registry.new({ ttlSeconds = 100 })
		reg:declare("modA", "change", {
			type = "rooms",
			scope = "onPlayerChangeRoom",
			target = { player = { id = 1 } },
		})

		local merged = reg:effective("rooms", nil, { bucketKey = "onPlayerChangeRoom:player:1" })
		assert.is_table(merged)
		assert.equals("rooms", merged.type)
		assert.equals("onPlayerChangeRoom", merged.scope)
		assert.is_table(merged.target)
		assert.equals("player", merged.target.kind)
		assert.equals(1, merged.target.id)
	end)

	it("supports rooms allLoaded as a probe bucket", function()
		local reg = Registry.new({ ttlSeconds = 100 })
		reg:declare("modA", "rooms", { type = "rooms", scope = "allLoaded", staleness = 30 })

		local buckets = reg:effectiveBuckets("rooms")
		assert.equals(1, #buckets)
		assert.equals("allLoaded", buckets[1].bucketKey)
	end)
end)
