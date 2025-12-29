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

local Record = require("WorldObserver/facts/players/record")

describe("players records", function()
	it("builds a stable player record", function()
		local room = {
			getSquares = function()
				return {
					{
						getX = function()
							return 3
						end,
						getY = function()
							return 4
						end,
						getZ = function()
							return 0
						end,
					},
				}
			end,
			getName = function()
				return "bedroom"
			end,
		}
		local square = {
			getX = function()
				return 10
			end,
			getY = function()
				return 20
			end,
			getZ = function()
				return 0
			end,
			getRoom = function()
				return room
			end,
		}
		local building = {
			getID = function()
				return 77
			end,
		}
		local player = {
			getSteamID = function()
				return "steam123"
			end,
			getOnlineID = function()
				return 45
			end,
			getID = function()
				return 9
			end,
			getPlayerNum = function()
				return 0
			end,
			getCurrentSquare = function()
				return square
			end,
			getBuilding = function()
				return building
			end,
			getUsername = function()
				return "bob"
			end,
			getDisplayName = function()
				return "Bob"
			end,
			getAccessLevel = function()
				return "admin"
			end,
			getHoursSurvived = function()
				return 12
			end,
			isLocalPlayer = function()
				return true
			end,
			isAiming = function()
				return false
			end,
		}

		local record = Record.makePlayerRecord(player, "event", { scope = "onPlayerMove" })
		assert.is_table(record)
		assert.equals("steam123", record.steamId)
		assert.equals(45, record.onlineId)
		assert.equals(9, record.playerId)
		assert.equals(0, record.playerNum)
		assert.equals("steamIdsteam123", record.playerKey)
		assert.equals("steamIdsteam123", record.woKey)
		assert.equals(10, record.tileX)
		assert.equals(20, record.tileY)
		assert.equals(0, record.tileZ)
		assert.equals(10, record.x)
		assert.equals(20, record.y)
		assert.equals(0, record.z)
		assert.equals("x10y20z0", record.tileLocation)
		assert.equals("x3y4z0", record.roomLocation)
		assert.equals("bedroom", record.roomName)
		assert.equals(77, record.buildingId)
		assert.equals("bob", record.username)
		assert.equals("Bob", record.displayName)
		assert.equals("admin", record.accessLevel)
		assert.equals(12, record.hoursSurvived)
		assert.is_true(record.isLocalPlayer)
		assert.is_false(record.isAiming)
		assert.equals(player, record.IsoPlayer)
		assert.equals(square, record.IsoGridSquare)
		assert.equals(room, record.IsoRoom)
		assert.equals(building, record.IsoBuilding)
		assert.equals("event", record.source)
		assert.equals("onPlayerMove", record.scope)
		assert.is_nil(record.sourceTime)
	end)

	it("falls back to onlineId when steamId is missing", function()
		local square = {
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
		local player = {
			getSteamID = function()
				return nil
			end,
			getOnlineID = function()
				return 33
			end,
			getPlayerNum = function()
				return 0
			end,
			getCurrentSquare = function()
				return square
			end,
		}

		local record = Record.makePlayerRecord(player, "event", { scope = "onPlayerUpdate" })
		assert.is_table(record)
		assert.equals("onlineId33", record.playerKey)
		assert.equals("onlineId33", record.woKey)
		assert.equals("event", record.source)
		assert.equals("onPlayerUpdate", record.scope)
	end)

	it("drops records when the player is nil", function()
		local record = Record.makePlayerRecord(nil, "event", {})
		assert.is_nil(record)
	end)
end)
