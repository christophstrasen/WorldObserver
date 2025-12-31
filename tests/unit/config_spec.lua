dofile("tests/unit/bootstrap.lua")

local Config = require("WorldObserver/config")

---@diagnostic disable: undefined-global
describe("WorldObserver config", function()
	local savedHeadless
	local savedLqrHeadless
	local savedOverrides

	before_each(function()
		savedHeadless = _G.WORLDOBSERVER_HEADLESS
		savedLqrHeadless = _G.LQR_HEADLESS
		savedOverrides = _G.WORLDOBSERVER_CONFIG_OVERRIDES
		_G.WORLDOBSERVER_HEADLESS = true
		_G.LQR_HEADLESS = true
		_G.WORLDOBSERVER_CONFIG_OVERRIDES = nil
	end)

	after_each(function()
		_G.WORLDOBSERVER_HEADLESS = savedHeadless
		_G.LQR_HEADLESS = savedLqrHeadless
		_G.WORLDOBSERVER_CONFIG_OVERRIDES = savedOverrides
	end)

	it("clones defaults deeply (mutations do not leak)", function()
		local a = Config.defaults()
		local b = Config.defaults()

		a.facts.squares.probe.maxPerRun = 999
		assert.are_not.equal(a.facts.squares.probe.maxPerRun, b.facts.squares.probe.maxPerRun)
	end)

	it("applies shallow overrides only on allowed paths", function()
		local cfg = Config.load({
			facts = {
				squares = {
					headless = true,
					ingest = { capacity = 42 },
					unknown = { should = "be ignored" },
				},
			},
			ingest = { scheduler = { maxItemsPerTick = 99 } },
		})

		assert.is_true(cfg.facts.squares.headless)
		assert.equals(42, cfg.facts.squares.ingest.capacity)
		assert.equals(99, cfg.ingest.scheduler.maxItemsPerTick)
		assert.is_nil(cfg.facts.squares.unknown)
	end)

	it("overrides nested runtime tables by replacement (shallow merge)", function()
		local cfg = Config.load({
			runtime = {
				controller = {
					drainAuto = { enabled = false },
				},
			},
		})

		assert.is_table(cfg.runtime.controller.drainAuto)
		assert.is_false(cfg.runtime.controller.drainAuto.enabled)
		assert.is_nil(cfg.runtime.controller.drainAuto.stepFactor)
	end)

	it("builds runtime opts and threads baseDrainMaxItems from ingest scheduler", function()
		local cfg = Config.load({
			ingest = { scheduler = { maxItemsPerTick = 11 } },
			runtime = { controller = { tickBudgetMs = 7 } },
		})
		local opts = Config.runtimeOpts(cfg)
		assert.equals(7, opts.tickBudgetMs)
		assert.equals(11, opts.baseDrainMaxItems)
	end)

	it("loads from global overrides when using loadFromGlobals", function()
		_G.WORLDOBSERVER_CONFIG_OVERRIDES = {
			ingest = { scheduler = { maxItemsPerTick = 123 } },
		}
		local cfg = Config.loadFromGlobals()
		assert.equals(123, cfg.ingest.scheduler.maxItemsPerTick)
	end)
end)
