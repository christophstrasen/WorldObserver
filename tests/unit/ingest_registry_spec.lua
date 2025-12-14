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

local FactRegistry = require("WorldObserver/facts/registry")

describe("FactRegistry with ingest", function()
	it("buffers and drains through the scheduler when enabled", function()
		local received = {}

		local registry = FactRegistry.new({
			ingest = {
				scheduler = {
					maxItemsPerTick = 10,
					quantum = 1,
				},
			},
			testfacts = {
				ingest = {
					enabled = true,
					mode = "latestByKey",
					capacity = 10,
					ordering = "fifo",
					priority = 1,
				},
			},
		})

		registry:register("testfacts", {
			ingest = {
				mode = "latestByKey",
				key = function(item)
					return item.id
				end,
				lane = function(item)
					return item.src
				end,
			},
			start = function(ctx)
				ctx.ingest({ id = 1, src = "event" })
			end,
		})

		registry:getObservable("testfacts"):subscribe(function(item)
			table.insert(received, item)
		end)

		-- Start the fact type (onSubscribe triggers start).
		registry:onSubscribe("testfacts")

		-- No OnTick in tests; drain once manually.
		registry:drainOnceForTests()

		local snap = registry:getIngestMetrics("testfacts")
		assert.is.truthy(snap)
		assert.is.equal(1, snap.totals.ingestedTotal)

		local schedSnap = registry:getSchedulerMetrics()
		assert.is.truthy(schedSnap)
		assert.is.equal("WorldObserver.factScheduler", schedSnap.name)

		assert.is.equal(1, #received)
		assert.is.equal(1, received[1].id)
	end)
end)
