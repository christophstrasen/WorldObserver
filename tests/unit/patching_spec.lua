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
			}

			SquaresFacts.register(fakeRegistry, {
				facts = { squares = { headless = true, probe = { enabled = false } } },
			})

			assert.is_table(registered)

			local emitted = {}
			registered.start({
				state = {},
				ingest = function(record)
					emitted[#emitted + 1] = record
				end,
			})

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
end)

