_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local RoomHelpers = require("WorldObserver/helpers/room")

describe("WorldObserver room helpers", function()
	local oldGetWorld

	before_each(function()
		oldGetWorld = _G.getWorld
	end)

	after_each(function()
		_G.getWorld = oldGetWorld
	end)

	it("getRoomDef hydrates from roomLocation", function()
		local roomDef = { id = "roomDef" }
		local room = {
			getRoomDef = function()
				return roomDef
			end,
		}
		local square = {
			getRoom = function()
				return room
			end,
		}
		local cell = {
			getGridSquare = function(_, x, y, z)
				assert.equals(2, x)
				assert.equals(3, y)
				assert.equals(0, z)
				return square
			end,
		}
		local world = {
			getCell = function()
				return cell
			end,
		}
		_G.getWorld = function()
			return world
		end

		local record = { roomLocation = "x2y3z0" }
		local resolved = RoomHelpers.record.getRoomDef(record)
		assert.equals(roomDef, resolved)
	end)

	it("getRoomDef returns nil for bad roomLocation", function()
		local record = { roomLocation = "bad-location" }
		local resolved = RoomHelpers.record.getRoomDef(record)
		assert.is_nil(resolved)
	end)

	it("getRoomDef prefers RoomDef and IsoRoom before hydration", function()
		local record = { RoomDef = "RoomDefSentinel" }
		assert.equals("RoomDefSentinel", RoomHelpers.record.getRoomDef(record))

		local roomDef = { id = "fromIsoRoom" }
		record = {
			IsoRoom = {
				getRoomDef = function()
					return roomDef
				end,
			},
		}
		assert.equals(roomDef, RoomHelpers.record.getRoomDef(record))
	end)

	it("getRoomDef uses metaGrid when roomDefId is present", function()
		local record = { roomDefId = 42 }
		local metaGrid = {
			getRoomDefByID = function(_, id)
				assert.equals(42, id)
				return "MetaGridRoomDef"
			end,
		}
		local resolved = RoomHelpers.record.getRoomDef(record, { metaGrid = metaGrid })
		assert.equals("MetaGridRoomDef", resolved)
	end)
end)
