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


local SquareRecord = require("WorldObserver/facts/squares/record")
local RoomRecord = require("WorldObserver/facts/rooms/record")
local ZombieRecord = require("WorldObserver/facts/zombies/record")
local VehicleRecord = require("WorldObserver/facts/vehicles/record")
local ItemRecord = require("WorldObserver/facts/items/record")
local DeadBodyRecord = require("WorldObserver/facts/dead_bodies/record")
local SpriteRecord = require("WorldObserver/facts/sprites/record")

describe("record extenders", function()
	local idCounter = 0
	local function newId(prefix)
		idCounter = idCounter + 1
		return string.format("tests.record_extenders.%s.%d", tostring(prefix), idCounter)
	end

	it("extends square records", function()
		local id = newId("square")
		local ok = SquareRecord.registerSquareRecordExtender(id, function(record)
			record.extra = record.extra or {}
			record.extra.extended = true
		end)
		assert.is_true(ok)

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
			getID = function()
				return 1234
			end,
			hasBlood = function()
				return false
			end,
		}

		local record = SquareRecord.makeSquareRecord(square, "probe")
		assert.is_table(record)
		assert.is_table(record.extra)
		assert.is_true(record.extra.extended)

		SquareRecord.unregisterSquareRecordExtender(id)
	end)

	it("extends room records", function()
		local id = newId("room")
		local ok = RoomRecord.registerRoomRecordExtender(id, function(record)
			record.extra = record.extra or {}
			record.extra.extended = true
		end)
		assert.is_true(ok)

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
		}

		local record = RoomRecord.makeRoomRecord(room, "probe", { nowMs = 123 })
		assert.is_table(record)
		assert.is_table(record.extra)
		assert.is_true(record.extra.extended)

		RoomRecord.unregisterRoomRecordExtender(id)
	end)

	it("extends zombie records", function()
		local id = newId("zombie")
		local ok = ZombieRecord.registerZombieRecordExtender(id, function(record)
			record.extra = record.extra or {}
			record.extra.extended = true
		end)
		assert.is_true(ok)

		local square = {
			getID = function()
				return 321
			end,
		}
		local zombie = {
			getID = function()
				return 42
			end,
			getOnlineID = function()
				return 8
			end,
			getX = function()
				return 5
			end,
			getY = function()
				return 6
			end,
			getZ = function()
				return 0
			end,
			getCurrentSquare = function()
				return square
			end,
			isMoving = function()
				return true
			end,
			isRunning = function()
				return false
			end,
			isCrawling = function()
				return false
			end,
			getTarget = function()
				return nil
			end,
			isTargetVisible = function()
				return false
			end,
			speedType = 2,
		}

		local record = ZombieRecord.makeZombieRecord(zombie, "probe", { nowMs = 123 })
		assert.is_table(record)
		assert.is_table(record.extra)
		assert.is_true(record.extra.extended)

		ZombieRecord.unregisterZombieRecordExtender(id)
	end)

	it("extends vehicle records", function()
		local id = newId("vehicle")
		local ok = VehicleRecord.registerVehicleRecordExtender(id, function(record)
			record.extra = record.extra or {}
			record.extra.extended = true
		end)
		assert.is_true(ok)

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
		}
		local vehicle = {
			sqlId = 123,
			getId = function()
				return 77
			end,
			getSquare = function()
				return square
			end,
		}

		local record = VehicleRecord.makeVehicleRecord(vehicle, "probe", { nowMs = 123, headless = true })
		assert.is_table(record)
		assert.is_table(record.extra)
		assert.is_true(record.extra.extended)

		VehicleRecord.unregisterVehicleRecordExtender(id)
	end)

	it("extends item records", function()
		local id = newId("item")
		local ok = ItemRecord.registerItemRecordExtender(id, function(record)
			record.extra = record.extra or {}
			record.extra.extended = true
		end)
		assert.is_true(ok)

		local square = {
			getX = function()
				return 3
			end,
			getY = function()
				return 4
			end,
			getZ = function()
				return 0
			end,
		}
		local item = {
			getID = function()
				return 55
			end,
			getType = function()
				return "Nails"
			end,
			getFullType = function()
				return "Base.Nails"
			end,
		}

		local record = ItemRecord.makeItemRecord(item, square, "probe", { nowMs = 123 })
		assert.is_table(record)
		assert.is_table(record.extra)
		assert.is_true(record.extra.extended)

		ItemRecord.unregisterItemRecordExtender(id)
	end)

	it("extends dead body records", function()
		local id = newId("deadBody")
		local ok = DeadBodyRecord.registerDeadBodyRecordExtender(id, function(record)
			record.extra = record.extra or {}
			record.extra.extended = true
		end)
		assert.is_true(ok)

		local square = {
			getX = function()
				return 7
			end,
			getY = function()
				return 9
			end,
			getZ = function()
				return 0
			end,
			getID = function()
				return 808
			end,
		}
		local body = {
			getObjectID = function()
				return 77
			end,
		}

		local record = DeadBodyRecord.makeDeadBodyRecord(body, square, "probe", { nowMs = 123 })
		assert.is_table(record)
		assert.is_table(record.extra)
		assert.is_true(record.extra.extended)

		DeadBodyRecord.unregisterDeadBodyRecordExtender(id)
	end)

	it("extends sprite records", function()
		local id = newId("sprite")
		local ok = SpriteRecord.registerSpriteRecordExtender(id, function(record)
			record.extra = record.extra or {}
			record.extra.extended = true
		end)
		assert.is_true(ok)

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
			getID = function()
				return 55
			end,
		}
		local sprite = {
			getName = function()
				return "fixtures_bathroom_01_0"
			end,
			getID = function()
				return 120000
			end,
		}
		local isoObject = {
			getSprite = function()
				return sprite
			end,
			getSquare = function()
				return square
			end,
			getObjectIndex = function()
				return 4
			end,
		}

		local record = SpriteRecord.makeSpriteRecord(isoObject, square, "probe", { nowMs = 123 })
		assert.is_table(record)
		assert.is_table(record.extra)
		assert.is_true(record.extra.extended)

		SpriteRecord.unregisterSpriteRecordExtender(id)
	end)
end)
