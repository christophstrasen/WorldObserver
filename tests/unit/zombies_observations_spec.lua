dofile("tests/unit/bootstrap.lua")

_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("WorldObserver observations.zombies()", function()
	local WorldObserver

	before_each(function()
		WorldObserver = reload("WorldObserver")
	end)

	it("zombieFilter passes the zombie record into the predicate", function()
		local received = {}
		local ZombieHelper = WorldObserver.helpers.zombie.record

			local stream = WorldObserver.observations:zombies():zombieFilter(function(zombieRecord, observation)
				assert.is_table(observation)
				assert.is_table(zombieRecord)
				assert.equals(zombieRecord, observation.zombie)
				return ZombieHelper.zombieHasTarget(zombieRecord)
			end)

		stream:subscribe(function(row)
			received[#received + 1] = row
		end)

		WorldObserver._internal.facts:emit("zombies", {
			zombieId = 1,
			woKey = "1",
			hasTarget = false,
			sourceTime = 50,
			sourceTime = 50,
		})
		WorldObserver._internal.facts:emit("zombies", {
			zombieId = 2,
			woKey = "2",
			hasTarget = true,
			sourceTime = 60,
			sourceTime = 60,
		})

		assert.is_equal(1, #received)
		assert.is_equal(2, received[1].zombie.zombieId)
	end)
end)
