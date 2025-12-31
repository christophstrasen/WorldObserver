_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local WoMeta = require("WorldObserver/observations/wo_meta")

describe("WoMeta key computation", function()
	it("builds compound keys for join_result rows", function()
		local observation = {
			square = { woKey = "x1y2z0" },
			zombie = { woKey = "4512" },
			RxMeta = {
				shape = "join_result",
				schemaMap = { zombie = {}, square = {} },
			},
		}

		local key, reason = WoMeta.computeKeyFromJoinResult(observation)
		assert.is_nil(reason)
		assert.is_equal("#square(x1y2z0)#zombie(4512)", key)
	end)

	it("omits nil members in join_result rows", function()
		local observation = {
			square = { woKey = "x1y2z0" },
			zombie = nil,
			RxMeta = {
				shape = "join_result",
				schemaMap = { zombie = {}, square = {} },
			},
		}

		local key, reason = WoMeta.computeKeyFromJoinResult(observation)
		assert.is_nil(reason)
		assert.is_equal("#square(x1y2z0)", key)
	end)

	it("fails join_result when a present record lacks woKey", function()
		local observation = {
			square = { woKey = "x1y2z0" },
			zombie = {},
			RxMeta = {
				shape = "join_result",
				schemaMap = { zombie = {}, square = {} },
			},
		}

		local key, reason = WoMeta.computeKeyFromJoinResult(observation)
		assert.is_nil(key)
		assert.is_equal("missing_record_woKey", reason)
	end)

	it("builds record keys for single records", function()
		local record = {
			woKey = "x1y2z0",
			RxMeta = { schema = "square", shape = "record" },
		}

		local key, reason = WoMeta.computeKeyFromRecord(record)
		assert.is_nil(reason)
		assert.is_equal("#square(x1y2z0)", key)
	end)

	it("builds group keys for aggregates", function()
		local observation = {
			RxMeta = {
				shape = "group_aggregate",
				groupName = "customers_grouped",
				groupKey = 1,
			},
		}

		local key, reason = WoMeta.computeKeyFromGroupAggregate(observation)
		assert.is_nil(reason)
		assert.is_equal("#customers_grouped(1)", key)
	end)

	it("builds compound keys for group_enriched rows", function()
		local observation = {
			square = { woKey = "x1y2z0" },
			zombie = { woKey = "4512" },
			RxMeta = { shape = "group_enriched" },
		}

		local key, reason = WoMeta.computeKeyFromGroupEnriched(observation)
		assert.is_nil(reason)
		assert.is_equal("#square(x1y2z0)#zombie(4512)", key)
	end)

	it("attaches WoMeta.key on join_result emissions", function()
		local observation = {
			square = { woKey = "x1y2z0" },
			zombie = { woKey = "4512" },
			RxMeta = {
				shape = "join_result",
				schemaMap = { zombie = {}, square = {} },
			},
		}

		local ok, reason = WoMeta.attachWoMeta(observation)
		assert.is_true(ok)
		assert.is_nil(reason)
		assert.is_equal("#square(x1y2z0)#zombie(4512)", observation.WoMeta.key)
	end)
end)
