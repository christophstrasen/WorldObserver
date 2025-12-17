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

local SquaresFacts = require("WorldObserver/facts/squares")

describe("WorldObserver patch seams", function()
		describe("facts/squares.makeSquareRecord", function()
			local savedEvents
			local originalMake

		before_each(function()
			savedEvents = _G.Events
			originalMake = SquaresFacts.makeSquareRecord
		end)

		after_each(function()
			_G.Events = savedEvents
			SquaresFacts.makeSquareRecord = originalMake
		end)

			it("dispatches through the module field inside event handlers", function()
				local storedHandler = nil
				local storedTick = nil
				_G.Events = {
					LoadGridsquare = {
						Add = function(fn)
							storedHandler = fn
						end,
					},
				}

				local registered = nil
				local fakeRegistry = {
					register = function(_, _name, opts)
						registered = opts
					end,
					tickHook_add = function(_, _id, fn)
						storedTick = fn
					end,
				}

				local InterestRegistry = require("WorldObserver/interest/registry")
				local interestRegistry = InterestRegistry.new({ ttlMs = 1000000 })
				interestRegistry:declare("test", "onLoad", {
					type = "squares.onLoad",
					cooldown = { desired = 0, tolerable = 0 },
				})

				SquaresFacts.register(fakeRegistry, {
					facts = { squares = { headless = true, probe = { enabled = false } } },
				}, interestRegistry)

				assert.is_table(registered)

				local emitted = {}
				registered.start({
					state = {},
					ingest = function(record)
						emitted[#emitted + 1] = record
					end,
				})

				assert.is_function(storedTick)
				storedTick()

				assert.is_function(storedHandler)

				SquaresFacts.makeSquareRecord = function(_square, source)
					return {
					squareId = 1,
					x = 1,
					y = 2,
					z = 0,
					observedAtTimeMS = 0,
					source = source,
					patched = true,
				}
			end

			storedHandler({})

			assert.is_equal(1, #emitted)
			assert.is_true(emitted[1].patched)
			assert.is_equal("event", emitted[1].source)
		end)
	end)

	describe("squareRecord:getIsoSquare()", function()
		local savedGetWorld

		before_each(function()
			savedGetWorld = _G.getWorld
		end)

		after_each(function()
			_G.getWorld = savedGetWorld
		end)

		it("rehydrates via SquareHelpers.record.getIsoSquare when hydration globals are available", function()
			local SquareHelpers = require("WorldObserver/helpers/square")

			local record = {
				x = 1,
				y = 2,
				z = 0,
				IsoSquare = nil,
			}

			local hydrated = {
				getX = function()
					return 1
				end,
				getY = function()
					return 2
				end,
				getZ = function()
					return 0
				end,
			}

			local cell = {
				getGridSquare = function(_, x, y, z)
					assert.equals(1, x)
					assert.equals(2, y)
					assert.equals(0, z)
					return hydrated
				end,
			}

			_G.getWorld = function()
				return {
					getCell = function()
						return cell
					end,
				}
			end

			local iso = SquareHelpers.record.getIsoSquare(record)
			assert.is_equal(hydrated, iso)
			assert.is_equal(hydrated, record.IsoSquare)
		end)

		it("populates hasCorpse via getDeadBody when present", function()
			local corpseObj = {}
			local fakeIsoSquare = {
				getX = function()
					return 1
				end,
				getY = function()
					return 2
				end,
				getZ = function()
					return 0
				end,
				hasBlood = function()
					return false
				end,
				getDeadBody = function()
					return corpseObj
				end,
			}

			local record = SquaresFacts.makeSquareRecord(fakeIsoSquare, "event")
			assert.is_true(record.hasCorpse)
		end)
	end)
end)
