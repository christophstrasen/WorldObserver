package.path = table.concat({
	"Contents/mods/WorldScanner/42/media/lua/shared/?.lua",
	"Contents/mods/WorldScanner/42/media/lua/shared/?/init.lua",
	"external/LQR/LQR/?.lua",
	"external/LQR/LQR/?/init.lua",
	"external/LQR/LQR/external/lua-reactivex/?.lua",
	"external/LQR/LQR/external/lua-reactivex/?/init.lua",
	"external/LQR/?.lua",
	"external/LQR/?/init.lua",
	package.path,
}, ";")

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("WorldObserver observations.squares()", function()
	local WorldObserver

	before_each(function()
		WorldObserver = reload("WorldObserver")
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
			source = "event",
		})

		assert.is_equal(1, #received)
		local obs = received[1]
		assert.is_table(obs.square)
		assert.is_equal(10, obs.square.squareId)
		assert.is_number(obs.square.RxMeta.id)
		assert.is_equal(123, obs.square.RxMeta.sourceTime)
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
		})
		WorldObserver._internal.facts:emit("squares", {
			squareId = 42,
			square = {},
			x = 5,
			y = 6,
			z = 0,
			observedAtTimeMS = 1001,
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
		})
		WorldObserver._internal.facts:emit("squares", {
			squareId = 2,
			square = {},
			hasBloodSplat = true,
			x = 1,
			y = 1,
			z = 0,
			observedAtTimeMS = 60,
		})

		assert.is_equal(1, #hasBlood)
		assert.is_equal(2, hasBlood[1].square.squareId)
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
