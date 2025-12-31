dofile("tests/unit/bootstrap.lua")

_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("WorldObserver observations.vehicles()", function()
	local WorldObserver

	before_each(function()
		WorldObserver = reload("WorldObserver")
	end)

	it("vehicleFilter passes the vehicle record into the predicate", function()
		local received = {}

		local stream = WorldObserver.observations:vehicles():vehicleFilter(function(vehicleRecord, observation)
			assert.is_table(observation)
			assert.is_table(vehicleRecord)
			assert.equals(vehicleRecord, observation.vehicle)
			return vehicleRecord.vehicleId == 2
		end)

		stream:subscribe(function(row)
			received[#received + 1] = row
		end)

		WorldObserver._internal.facts:emit("vehicles", {
			vehicleId = 1,
			sqlId = 1001,
			woKey = "1001",
			sourceTime = 50,
			source = "probe",
		})
		WorldObserver._internal.facts:emit("vehicles", {
			vehicleId = 2,
			sqlId = 1002,
			woKey = "1002",
			sourceTime = 60,
			source = "probe",
		})

		assert.equals(1, #received)
		assert.equals(2, received[1].vehicle.vehicleId)
	end)
end)
