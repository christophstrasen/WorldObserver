_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local function reload(moduleName)
	package.loaded[moduleName] = nil
	return require(moduleName)
end

describe("WorldObserver RecordWrap utility", function()
	local RecordWrap

	before_each(function()
		RecordWrap = reload("WorldObserver/helpers/record_wrap")
	end)

	it("wrap reports collisions but still wraps", function()
		local state = RecordWrap.ensureState()
		local record = { collision = true }

		local wrapped, err, collisions = RecordWrap.wrap(record, state, {
			family = "test",
			methodNames = { "collision", "safe" },
			headless = true,
		})

		assert.is_nil(err)
		assert.equals(record, wrapped)
		assert.is_not_nil(getmetatable(record))
		assert.is_table(collisions)
		assert.equals("collision", collisions[1])
	end)

	it("wrap refuses when record already has a metatable", function()
		local state = RecordWrap.ensureState()
		local record = setmetatable({}, { __index = {} })

		local wrapped, err = RecordWrap.wrap(record, state, { headless = true })
		assert.is_nil(wrapped)
		assert.equals("hasMetatable", err)
	end)
end)

