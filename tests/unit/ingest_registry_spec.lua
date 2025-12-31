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

local FactRegistry = require("WorldObserver/facts/registry")
local Runtime = require("WorldObserver/runtime")

describe("FactRegistry with ingest", function()
	it("buffers and drains through the scheduler when enabled", function()
		local received = {}

		local runtime = Runtime.new({ windowTicks = 5, reportEveryWindows = 0 })
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
		}, runtime)

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
		registry:drainSchedulerOnceForTests()

		local snap = registry:getIngestMetrics("testfacts")
		assert.is.truthy(snap)
		assert.is.equal(1, snap.totals.ingestedTotal)

		local schedSnap = registry:getSchedulerMetrics()
		assert.is.truthy(schedSnap)
		assert.is.equal("WorldObserver.factScheduler", schedSnap.name)

		assert.is.equal(1, #received)
		assert.is.equal(1, received[1].id)
	end)

	it("stamps sourceTime on ingest when missing", function()
		local received = {}

		local runtime = Runtime.new({ windowTicks = 2, reportEveryWindows = 0 })
		runtime._wallClock = function()
			return 4242
		end

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
		}, runtime)

		registry:register("testfacts", {
			ingest = {
				mode = "latestByKey",
				key = function(item)
					return item.id
				end,
			},
			start = function(ctx)
				ctx.ingest({ id = 1 })
			end,
		})

		registry:getObservable("testfacts"):subscribe(function(item)
			table.insert(received, item)
		end)

		registry:onSubscribe("testfacts")
		registry:drainSchedulerOnceForTests()

		assert.is.equal(1, #received)
		assert.is.equal(4242, received[1].sourceTime)
	end)

	it("emergency reset clears ingest buffers and resets metrics", function()
		local runtime = Runtime.new({ windowTicks = 2, reportEveryWindows = 0 })
		local registry = FactRegistry.new({
			ingest = {
				scheduler = {
					maxItemsPerTick = 0, -- keep pending; we will clear via emergency reset
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
		}, runtime)

		registry:register("testfacts", {
			ingest = {
				mode = "latestByKey",
				key = function(item)
					return item.id
				end,
			},
			start = function(ctx)
				-- Enqueue a few items; they should remain pending because scheduler budget is 0.
				for id = 1, 3 do
					ctx.ingest({ id = id })
				end
			end,
		})

		registry:getObservable("testfacts"):subscribe(function() end)
		registry:onSubscribe("testfacts")

		local before = registry:getIngestMetrics("testfacts")
		assert.is.truthy(before)
		assert.is_true((before.pending or 0) > 0)

		runtime:emergency_reset({
			onReset = function()
				registry:ingest_clearAll()
			end,
		})

		local after = registry:getIngestMetrics("testfacts")
		assert.is.truthy(after)
		assert.is.equal(0, after.pending or 0)
		assert.is.equal(0, after.totals and after.totals.ingestedTotal or -1)
	end)

	it("feeds ingest pending+drops into the runtime controller on OnTick", function()
		local storedTickFn = nil
		_G.Events = {
			OnTick = {
				Add = function(fn)
					storedTickFn = fn
				end,
			},
		}

		local runtime = Runtime.new({
			windowTicks = 1, -- complete a window per tick so transitions happen immediately
			reportEveryWindows = 0,
			tickBudgetMs = 100, -- keep tick budgets out of the way
		})

		local registry = FactRegistry.new({
			ingest = {
				scheduler = {
					maxItemsPerTick = 1,
					quantum = 1,
				},
			},
			testfacts = {
				ingest = {
					enabled = true,
					mode = "latestByKey",
					capacity = 1, -- force drops on ingest
					ordering = "fifo",
					priority = 1,
				},
			},
		}, runtime)

		local hookCalled = false
		registry:attachTickHook("unitTestHook", function()
			hookCalled = true
		end)

		registry:register("testfacts", {
			ingest = {
				mode = "latestByKey",
				key = function(item)
					return item.id
				end,
			},
			start = function(ctx)
				-- Overflow: capacity=1, unique keys => droppedTotal grows.
				for id = 1, 5 do
					ctx.ingest({ id = id })
				end
			end,
		})

		registry:getObservable("testfacts"):subscribe(function() end)
		registry:onSubscribe("testfacts")
		assert.is_truthy(storedTickFn)

		-- First tick should observe drops and degrade via ingestDropsRising.
		storedTickFn()

		assert.is_true(hookCalled)

		local snap = runtime:status_get()
		assert.equals("degraded", snap.mode)
		assert.equals(Runtime.Reasons.ingestDropsRising, snap.lastTransitionReason)
		assert.is_true((snap.tick.woWindowDropDelta or 0) > 0)
	end)
end)
