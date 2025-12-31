_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true


local Record = require("WorldObserver/facts/rooms/record")

describe("rooms records", function()
	it("builds a stable room record", function()
		local roomDef = {
			getID = function()
				return 99
			end,
		}
		local building = {
			getID = function()
				return 7
			end,
		}
		local room = {
			getRoomDef = function()
				return roomDef
			end,
			getBuilding = function()
				return building
			end,
			getSquares = function()
				return {
					{
						getX = function()
							return 10
						end,
						getY = function()
							return 20
						end,
						getZ = function()
							return 3
						end,
					},
				}
			end,
			getName = function()
				return "kitchen"
			end,
			hasWater = function()
				return true
			end,
		}

		local record = Record.makeRoomRecord(room, "event")
		assert.is_table(record)
		assert.equals("x10y20z3", record.roomId)
		assert.equals("x10y20z3", record.roomLocation)
		assert.equals("x10y20z3", record.tileLocation)
		assert.equals("x10y20z3", record.woKey)
		assert.equals(99, record.roomDefId)
		assert.equals(7, record.buildingId)
		assert.equals("kitchen", record.name)
		assert.is_true(record.hasWater)
		assert.is_nil(record.sourceTime)
	end)

	it("falls back to first square id when roomDef id is unavailable", function()
		local squares = {
			{
				getX = function()
					return 10
				end,
				getY = function()
					return 20
				end,
				getZ = function()
					return 3
				end,
			},
		}
		local room = {
			getRoomDef = function()
				return {}
			end,
			getSquares = function()
				return squares
			end,
		}

		local record = Record.makeRoomRecord(room, "probe")
		assert.is_table(record)
		assert.equals("x10y20z3", record.roomId)
		assert.equals("x10y20z3", record.roomLocation)
		assert.equals("x10y20z3", record.tileLocation)
		assert.equals("x10y20z3", record.woKey)
		assert.is_nil(record.roomDefId)
	end)

	it("uses first square id even when roomDef id exists", function()
		local roomDef = {
			getID = function()
				return 99
			end,
		}
		local room = {
			getRoomDef = function()
				return roomDef
			end,
			getSquares = function()
				return {
					{
						getX = function()
							return 1
						end,
						getY = function()
							return 2
						end,
						getZ = function()
							return 0
						end,
					},
				}
			end,
		}

		local record = Record.makeRoomRecord(room, "probe")
		assert.is_table(record)
		assert.equals("x1y2z0", record.roomId)
		assert.equals("x1y2z0", record.roomLocation)
		assert.equals("x1y2z0", record.tileLocation)
		assert.equals("x1y2z0", record.woKey)
		assert.equals(99, record.roomDefId)
	end)
end)
