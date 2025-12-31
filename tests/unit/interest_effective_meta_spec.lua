_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true

local InterestEffective = require("WorldObserver/facts/interest_effective")

describe("interest effective meta", function()
	it("returns demandRatio in meta and caches it per type", function()
		local interestRegistry = {
			effective = function(_, interestType, _, opts)
				assert.equals("squares", interestType)
				assert.equals("near:player:0", opts.bucketKey)
				return {
					staleness = { desired = 1, tolerable = 2 },
					radius = { desired = 8, tolerable = 5 },
					cooldown = { desired = 1, tolerable = 2 },
				}
			end,
		}

		local runtime = {
			status_get = function()
				return {
					mode = "normal",
					window = { budgetMs = 4, avgTickMs = 1, reason = "steady" },
					tick = { lastMs = 1, woAvgTickMs = 1 },
				}
			end,
		}

		local state = {}
		local effective, meta = InterestEffective.ensure(state, interestRegistry, runtime, "squares", {
			label = "near",
			bucketKey = "near:player:0",
			signals = { probeLagEstimateMs = 2000, probeLagRatio = 2, probeLagOverdueMs = 1000 },
		})

		assert.is_table(effective)
		assert.is_table(meta)
		assert.equals(1, meta.desiredStaleness)
		assert.equals(1000, meta.desiredStalenessMs)
		assert.equals(2.0, meta.demandRatio)

		assert.is_table(state._effectiveInterestMetaByType)
		local metaByBucket = state._effectiveInterestMetaByType["squares"]
		assert.is_table(metaByBucket)
		assert.equals(meta, metaByBucket["near:player:0"])
	end)

	it("returns demandRatio=0 when no lag estimate is available", function()
		local interestRegistry = {
			effective = function()
				return {
					staleness = { desired = 1, tolerable = 2 },
					radius = { desired = 8, tolerable = 5 },
					cooldown = { desired = 1, tolerable = 2 },
				}
			end,
		}
		local state = {}
		local _, meta = InterestEffective.ensure(state, interestRegistry, nil, "squares", {
			label = "near",
			bucketKey = "near:player:0",
		})
		assert.is_table(meta)
		assert.equals(0, meta.demandRatio)
	end)
end)
