package.path = table.concat({
	"Contents/mods/WorldObserver/42/media/lua/shared/?.lua",
	"Contents/mods/WorldObserver/42/media/lua/shared/?/init.lua",
	"../DREAMBase/Contents/mods/DREAMBase/42/media/lua/shared/?.lua",
	"../DREAMBase/Contents/mods/DREAMBase/42/media/lua/shared/?/init.lua",
	"external/DREAMBase/Contents/mods/DREAMBase/42/media/lua/shared/?.lua",
	"external/DREAMBase/Contents/mods/DREAMBase/42/media/lua/shared/?/init.lua",
	"external/LQR/?.lua",
	"external/LQR/?/init.lua",
	"external/lua-reactivex/?.lua",
	"external/lua-reactivex/?/init.lua",
	package.path,
}, ";")

_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("WorldObserver observations.derive()", function()
	local WorldObserver

	before_each(function()
		WorldObserver = reload("WorldObserver")
	end)

	it("tracks fact subscribers for all input stream deps", function()
		local facts = WorldObserver._internal.facts

		local squaresBefore = (facts._types.squares and facts._types.squares.subscribers) or 0
		local zombiesBefore = (facts._types.zombies and facts._types.zombies.subscribers) or 0

		local derived = WorldObserver.observations:derive({
			squares = WorldObserver.observations:squares(),
			zombies = WorldObserver.observations:zombies(),
		}, function(lqr)
			return lqr.squares
				:innerJoin(lqr.zombies)
				:using({ square = "squareId", zombie = "squareId" })
		end)

		local subscription = derived:subscribe(function() end)

		assert.equals(squaresBefore + 1, facts._types.squares.subscribers)
		assert.equals(zombiesBefore + 1, facts._types.zombies.subscribers)

		subscription:unsubscribe()

		assert.equals(squaresBefore, facts._types.squares.subscribers)
		assert.equals(zombiesBefore, facts._types.zombies.subscribers)
	end)

	it("emits only inner-joined observations", function()
		local received = {}

		local derived = WorldObserver.observations:derive({
			squares = WorldObserver.observations:squares(),
			zombies = WorldObserver.observations:zombies(),
		}, function(lqr)
			return lqr.squares
				:innerJoin(lqr.zombies)
				:using({ square = "squareId", zombie = "squareId" })
		end)

		derived:subscribe(function(row)
			received[#received + 1] = row
		end)

		WorldObserver._internal.facts:emit("squares", {
			squareId = 1,
			woKey = "x1y2z0",
			x = 1,
			y = 2,
			z = 0,
		})
		assert.equals(0, #received)

		WorldObserver._internal.facts:emit("zombies", {
			zombieId = 10,
			woKey = "10",
			squareId = 1,
		})
		assert.equals(1, #received)
		assert.equals(1, received[1].square.squareId)
		assert.equals(10, received[1].zombie.zombieId)

		WorldObserver._internal.facts:emit("zombies", {
			zombieId = 11,
			woKey = "11",
			squareId = 2,
		})
		assert.equals(1, #received)

		WorldObserver._internal.facts:emit("squares", {
			squareId = 2,
			woKey = "x9y9z0",
			x = 9,
			y = 9,
			z = 0,
		})
		assert.equals(2, #received)
		assert.equals(2, received[2].square.squareId)
		assert.equals(11, received[2].zombie.zombieId)
	end)

	it("attaches helper namespaces to derived streams", function()
		local received = {}

		local derived = WorldObserver.observations:derive({
			squares = WorldObserver.observations:squares(),
			zombies = WorldObserver.observations:zombies(),
		}, function(lqr)
			return lqr.squares
				:innerJoin(lqr.zombies)
				:using({ square = "squareId", zombie = "squareId" })
		end)

		assert.equals("table", type(derived.helpers))
		assert.equals("table", type(derived.helpers.square))
		assert.equals("table", type(derived.helpers.zombie))
		assert.equals("function", type(derived.helpers.zombie.zombieHasTarget))

		local filtered = derived.helpers.zombie:zombieHasTarget()
		assert.equals("table", type(filtered.helpers))
		assert.equals("table", type(filtered.helpers.zombie))

		filtered:subscribe(function(row)
			received[#received + 1] = row
		end)

		WorldObserver._internal.facts:emit("squares", {
			squareId = 1,
			woKey = "x0y0z0",
			x = 0,
			y = 0,
			z = 0,
		})
		WorldObserver._internal.facts:emit("zombies", {
			zombieId = 10,
			woKey = "10",
			squareId = 1,
			hasTarget = true,
		})
		assert.equals(1, #received)

		WorldObserver._internal.facts:emit("zombies", {
			zombieId = 11,
			woKey = "11",
			squareId = 1,
			hasTarget = false,
		})
		assert.equals(1, #received)
	end)

	it("allows overriding helper schema keys (advanced)", function()
		local derived = WorldObserver.observations:derive({
			squares = WorldObserver.observations:squares(),
			zombies = WorldObserver.observations:zombies(),
		}, function(lqr)
			return lqr.squares
				:innerJoin(lqr.zombies)
				:using({ square = "squareId", zombie = "squareId" })
		end)

		local right = {}
		derived.helpers.zombie:zombieHasTarget("zombie"):subscribe(function(row)
			right[#right + 1] = row
		end)

		local wrong = {}
		derived.helpers.zombie:zombieHasTarget("notARealSchema"):subscribe(function(row)
			wrong[#wrong + 1] = row
		end)

		WorldObserver._internal.facts:emit("squares", { squareId = 1, woKey = "x0y0z0", x = 0, y = 0, z = 0 })
		WorldObserver._internal.facts:emit("zombies", { zombieId = 10, woKey = "10", squareId = 1, hasTarget = true })

		assert.equals(1, #right)
		assert.equals(0, #wrong)
	end)

		it("requires public schema keys for base stream helpers", function()
			local receivedDefault = {}
			WorldObserver.observations:squares():squareHasCorpse():subscribe(function(row)
				receivedDefault[#receivedDefault + 1] = row
			end)

			local receivedWrong = {}
			WorldObserver.observations:squares().helpers.square:squareHasCorpse("SquareObservation"):subscribe(function(row)
				receivedWrong[#receivedWrong + 1] = row
			end)

			local receivedRight = {}
			WorldObserver.observations:squares().helpers.square:squareHasCorpse("square"):subscribe(function(row)
				receivedRight[#receivedRight + 1] = row
			end)

		WorldObserver._internal.facts:emit("squares", {
			squareId = 1,
			woKey = "x0y0z0",
			x = 0,
			y = 0,
			z = 0,
			hasCorpse = true,
		})

			assert.equals(1, #receivedDefault)
			assert.equals(0, #receivedWrong)
			assert.equals(1, #receivedRight)
		end)
end)
