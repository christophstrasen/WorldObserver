dofile("tests/unit/bootstrap.lua")
_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local Record = require("WorldObserver/facts/vehicles/record")

describe("vehicles records", function()
	it("builds a minimal vehicle record", function()
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
			getScriptName = function()
				return "Base.CarNormal"
			end,
		}

		local record = Record.makeVehicleRecord(vehicle, "probe", { headless = true })
		assert.is_table(record)
		assert.equals(123, record.sqlId)
		assert.equals(77, record.vehicleId)
		assert.equals("123", record.woKey)
		assert.equals(10, record.tileX)
		assert.equals(20, record.tileY)
		assert.equals(0, record.tileZ)
		assert.equals(10, record.x)
		assert.equals(20, record.y)
		assert.equals(0, record.z)
		assert.equals("Base.CarNormal", record.scriptName)
		assert.equals(square, record.IsoGridSquare)
		assert.is_nil(record.sourceTime)
		assert.equals("probe", record.source)
	end)

	it("falls back to vehicleId when sqlId is nil", function()
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
		local vehicle = {
			getId = function()
				return 5
			end,
			getSquare = function()
				return square
			end,
		}

		local record = Record.makeVehicleRecord(vehicle, "event", { headless = true })
		assert.is_table(record)
		assert.is_nil(record.sqlId)
		assert.equals(5, record.vehicleId)
		assert.equals("5", record.woKey)
	end)

	it("drops records without sqlId or vehicleId", function()
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
		local vehicle = {
			getSquare = function()
				return square
			end,
		}

		local record = Record.makeVehicleRecord(vehicle, "probe", { headless = true })
		assert.is_nil(record)
	end)
end)
