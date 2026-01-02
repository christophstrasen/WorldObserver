_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("factInterest multi-type declarations", function()
	it("creates per-type leases and returns a composite handle", function()
		local wo = reload("WorldObserver")
		local registry = wo._internal.factInterest
		local modId = "tests.multitype"
		local lease = wo.factInterest:declare(modId, "multi", {
			type = { "rooms", "players" },
			scope = "onPlayerChangeRoom",
			cooldown = { desired = 0 },
		})

		local leases = registry._leases[modId] or {}
		assert.is_table(leases["multi/rooms"])
		assert.is_table(leases["multi/players"])
		assert.is_nil(leases["multi"])
		assert.is_function(lease.stop)
		assert.is_function(lease.renew)
		assert.is_function(lease.declare)

		lease:stop()
		leases = registry._leases[modId] or {}
		assert.is_nil(leases["multi/rooms"])
		assert.is_nil(leases["multi/players"])
	end)

	it("treats a single-type list as a normal declare", function()
		local wo = reload("WorldObserver")
		local registry = wo._internal.factInterest
		local modId = "tests.multitype.single"
		local lease = wo.factInterest:declare(modId, "single", {
			type = { "rooms" },
			scope = "allLoaded",
			staleness = { desired = 5 },
		})

		local leases = registry._leases[modId] or {}
		assert.is_table(leases["single"])
		assert.is_nil(leases["single/rooms"])

		lease:stop()
	end)

	it("revokes derived keys via factInterest revoke", function()
		local wo = reload("WorldObserver")
		local registry = wo._internal.factInterest
		local modId = "tests.multitype.revoke"

		wo.factInterest:declare(modId, "multi", {
			type = { "rooms", "players" },
			scope = "onPlayerChangeRoom",
			cooldown = { desired = 0 },
		})

		wo.factInterest:revoke(modId, "multi")
		local leases = registry._leases[modId] or {}
		assert.is_nil(leases["multi/rooms"])
		assert.is_nil(leases["multi/players"])
	end)
end)
