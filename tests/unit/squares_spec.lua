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

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("WorldObserver observations.squares()", function()
	local WorldObserver
	local savedGetWorld

	before_each(function()
		savedGetWorld = _G.getWorld
		WorldObserver = reload("WorldObserver")
	end)

	after_each(function()
		_G.getWorld = savedGetWorld
	end)

	it("emits Observation rows with SquareObservation payload", function()
		local received = {}
		local stream = WorldObserver.observations.squares()
		stream:subscribe(function(row)
			received[#received + 1] = row
		end)

		WorldObserver._internal.facts:emit("squares", {
			squareId = 10,
			square = { marker = "square" },
			x = 1,
			y = 2,
			z = 0,
			observedAtTimeMS = 123,
			sourceTime = 123,
			source = "event",
		})

		assert.is_equal(1, #received)
		local obs = received[1]
		assert.is_table(obs.square)
		assert.is_equal(10, obs.square.squareId)
		assert.is_number(obs.square.RxMeta.id)
		assert.is_equal(123, obs.square.RxMeta.sourceTime)
		assert.is_equal(123, obs.square.sourceTime)
	end)

	it("distinct once per square suppresses duplicates", function()
		local received = {}
		local stream = WorldObserver.observations.squares():distinct("square")
		stream:subscribe(function(row)
			received[#received + 1] = row
		end)

		WorldObserver._internal.facts:emit("squares", {
			squareId = 42,
			square = {},
			x = 5,
			y = 6,
			z = 0,
			observedAtTimeMS = 1000,
			sourceTime = 1000,
		})
		WorldObserver._internal.facts:emit("squares", {
			squareId = 42,
			square = {},
			x = 5,
			y = 6,
			z = 0,
			observedAtTimeMS = 1001,
			sourceTime = 1001,
		})

		assert.is_equal(1, #received)
	end)

	it("square helpers filter expected observations", function()
		local hasBlood = {}
		local stream = WorldObserver.observations.squares():squareHasBloodSplat()
		stream:subscribe(function(row)
			hasBlood[#hasBlood + 1] = row
		end)

		WorldObserver._internal.facts:emit("squares", {
			squareId = 1,
			square = {},
			x = 0,
			y = 0,
			z = 0,
			observedAtTimeMS = 50,
			sourceTime = 50,
		})
		WorldObserver._internal.facts:emit("squares", {
			squareId = 2,
			square = {},
			hasBloodSplat = true,
			x = 1,
			y = 1,
			z = 0,
			observedAtTimeMS = 60,
			sourceTime = 60,
		})

		assert.is_equal(1, #hasBlood)
		assert.is_equal(2, hasBlood[1].square.squareId)
	end)

	it("squareHasCorpse filters expected observations", function()
		local withCorpse = {}
		local stream = WorldObserver.observations.squares():squareHasCorpse()
		stream:subscribe(function(row)
			withCorpse[#withCorpse + 1] = row
		end)

		WorldObserver._internal.facts:emit("squares", {
			squareId = 1,
			square = {},
			hasCorpse = false,
			x = 0,
			y = 0,
			z = 0,
			observedAtTimeMS = 50,
			sourceTime = 50,
		})
		WorldObserver._internal.facts:emit("squares", {
			squareId = 2,
			square = {},
			hasCorpse = true,
			x = 1,
			y = 1,
			z = 0,
			observedAtTimeMS = 60,
			sourceTime = 60,
		})

		assert.is_equal(1, #withCorpse)
		assert.is_equal(2, withCorpse[1].square.squareId)
	end)

	it("whereSquare passes the square record into the predicate", function()
		local received = {}
		local SquareHelper = WorldObserver.helpers.square.record
		local stream = WorldObserver.observations.squares():whereSquare(function(squareRecord, observation)
			assert.is_table(observation)
			assert.is_table(squareRecord)
			assert.equals(squareRecord, observation.SquareObservation)
			return SquareHelper.squareHasCorpse(squareRecord)
		end)
		stream:subscribe(function(row)
			received[#received + 1] = row
		end)

		WorldObserver._internal.facts:emit("squares", {
			squareId = 1,
			square = {},
			hasCorpse = false,
			x = 0,
			y = 0,
			z = 0,
			observedAtTimeMS = 50,
			sourceTime = 50,
		})
		WorldObserver._internal.facts:emit("squares", {
			squareId = 2,
			square = {},
			hasCorpse = true,
			x = 1,
			y = 1,
			z = 0,
			observedAtTimeMS = 60,
			sourceTime = 60,
		})

		assert.is_equal(1, #received)
		assert.is_equal(2, received[1].square.squareId)
	end)

	it("squareHasIsoSquare hydrates and filters observations", function()
		local hydrated = {
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

		local cell = {
			getGridSquare = function(_, x, y, z)
				assert.equals(1, x)
				assert.equals(2, y)
				assert.equals(0, z)
				return hydrated
			end,
		}

		_G.getWorld = function()
			return {
				getCell = function()
					return cell
				end,
			}
		end

		local received = {}
		local stream = WorldObserver.observations.squares():squareHasIsoSquare()
		stream:subscribe(function(row)
			received[#received + 1] = row
		end)

		WorldObserver._internal.facts:emit("squares", {
			squareId = 99,
			x = 1,
			y = 2,
			z = 0,
			IsoSquare = nil,
			observedAtTimeMS = 1,
			sourceTime = 1,
		})

		assert.is_equal(1, #received)
		assert.is_equal(hydrated, received[1].square.IsoSquare)
	end)

	it("tracks fact subscribers when subscribing and unsubscribing", function()
		local facts = WorldObserver._internal.facts
		local stream = WorldObserver.observations.squares()
		local subscription = stream:subscribe(function() end)

		assert.is_true((facts._types.squares.subscribers or 0) >= 1)

		subscription:unsubscribe()
		assert.is_equal(0, facts._types.squares.subscribers)
	end)
end)
