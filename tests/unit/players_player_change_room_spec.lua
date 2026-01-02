_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local Registry = require("WorldObserver/interest/registry")
local OnPlayerChange = require("WorldObserver/facts/players/on_player_change_room")
local PlayerRoomChange = require("WorldObserver/facts/sensors/player_room_change")

describe("players onPlayerChangeRoom", function()
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

		local roomA = { roomLocation = "rA" }
		local roomB = { roomLocation = "rB" }
		local emitted = {}
		local registry = Registry.new({ ttlSeconds = 100 })
		registry:declare("modA", "roomChange", {
			type = "players",
			scope = "onPlayerChangeRoom",
			cooldown = { desired = 0, tolerable = 0 },
		})

		local state = {}
		local ctx = {
			interestRegistry = registry,
			players = {
				makePlayerRecord = function(_player, source, opts)
					return {
						playerKey = "player0",
						roomLocation = playerRoom and playerRoom.roomLocation or nil,
						source = source,
						scope = opts and opts.scope or nil,
						IsoGridSquare = square,
					}
				end,
			},
			emitFn = function(record)
				emitted[#emitted + 1] = record
			end,
			headless = true,
		}

		OnPlayerChange.register(ctx)
		local tickCtx = {
			state = state,
			interestRegistry = registry,
			headless = true,
			consumers = PlayerRoomChange._consumers,
		}

		PlayerRoomChange.tick(tickCtx)
		assert.equals(0, #emitted)

		playerRoom = roomA
		PlayerRoomChange.tick(tickCtx)
		assert.equals(1, #emitted)
		assert.equals("rA", emitted[1].roomLocation)

		PlayerRoomChange.tick(tickCtx)
		assert.equals(1, #emitted)

		playerRoom = roomB
		PlayerRoomChange.tick(tickCtx)
		assert.equals(2, #emitted)
		assert.equals("rB", emitted[2].roomLocation)

		playerRoom = nil
		PlayerRoomChange.tick(tickCtx)
		assert.equals(2, #emitted)

		playerRoom = roomB
		PlayerRoomChange.tick(tickCtx)
		assert.equals(3, #emitted)

		OnPlayerChange.unregister()
		_G.getSpecificPlayer = savedGetSpecificPlayer
	end)
end)
