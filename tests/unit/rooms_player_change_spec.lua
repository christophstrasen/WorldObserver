dofile("tests/unit/bootstrap.lua")

_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local Registry = require("WorldObserver/interest/registry")
local OnPlayerChange = require("WorldObserver/facts/rooms/on_player_change_room")

describe("rooms onPlayerChangeRoom", function()
	it("emits only when the player changes rooms", function()
		local savedGetSpecificPlayer = _G.getSpecificPlayer
		local playerRoom = nil

		local square = {
			getRoom = function()
				return playerRoom
			end,
		}
		local player = {
			getCurrentSquare = function()
				return square
			end,
		}
		_G.getSpecificPlayer = function(id)
			assert.equals(0, id)
			return player
		end

		local roomA = { id = "A" }
		local roomB = { id = "B" }
		local emitted = {}
		local registry = Registry.new({ ttlSeconds = 100 })
		registry:declare("modA", "roomChange", {
			type = "rooms",
			scope = "onPlayerChangeRoom",
			target = { player = { id = 0 } },
			cooldown = { desired = 0, tolerable = 0 },
		})

		local state = {}
		local ctx = {
			state = state,
			interestRegistry = registry,
			rooms = {
				makeRoomRecord = function(room, source)
					return { roomId = room.id, source = source }
				end,
			},
			emitFn = function(record)
				emitted[#emitted + 1] = record
			end,
			headless = true,
		}

		OnPlayerChange.ensure(ctx)
		assert.equals(0, #emitted)

		playerRoom = roomA
		OnPlayerChange.ensure(ctx)
		assert.equals(1, #emitted)
		assert.equals("A", emitted[1].roomId)

		OnPlayerChange.ensure(ctx)
		assert.equals(1, #emitted)

		playerRoom = roomB
		OnPlayerChange.ensure(ctx)
		assert.equals(2, #emitted)
		assert.equals("B", emitted[2].roomId)

		playerRoom = nil
		OnPlayerChange.ensure(ctx)
		assert.equals(2, #emitted)

		playerRoom = roomB
		OnPlayerChange.ensure(ctx)
		assert.equals(3, #emitted)

		_G.getSpecificPlayer = savedGetSpecificPlayer
	end)
end)
