-- debug.lua -- minimal debug helpers to introspect whether facts/streams are registered.
local Log = require("LQR/util/log").withTag("WO.DIAG")

local Debug = {}

function Debug.new(factRegistry, observationRegistry)
	return {
		describeFacts = function(typeName)
			if factRegistry:hasType(typeName) then
				Log:info("Facts for '%s' registered", tostring(typeName))
			else
				Log:warn("Facts for '%s' not registered", tostring(typeName))
			end
		end,

		describeStream = function(name)
			if observationRegistry:hasStream(name) then
				Log:info("ObservationStream '%s' registered", tostring(name))
			else
				Log:warn("ObservationStream '%s' not registered", tostring(name))
			end
		end,

		-- Accepts optional opts, e.g. { full = true } to fetch the full metrics snapshot.
		describeFactsMetrics = function(typeName, opts)
			local snap = factRegistry.getIngestMetrics and factRegistry:getIngestMetrics(typeName, opts)
			if not snap then
				Log:warn("No ingest metrics for fact type '%s' (ingest disabled or not started)", tostring(typeName))
				return
			end
			local advice = factRegistry.getIngestAdvice and factRegistry:getIngestAdvice(typeName, opts)
			Log:info(
				"[%s] pending=%s peak=%s ingested=%s drained=%s dropped=%s load=%.2f/%.2f/%.2f throughput=%.2f/%.2f/%.2f ingestRate=%.2f/%.2f/%.2f",
				tostring(typeName),
				tostring(snap.pending),
				tostring(snap.peakPending),
				tostring(snap.totals and snap.totals.ingestedTotal),
				tostring(snap.totals and snap.totals.drainedTotal),
				tostring(snap.totals and snap.totals.droppedTotal),
				tonumber(snap.load1) or 0,
				tonumber(snap.load5) or 0,
				tonumber(snap.load15) or 0,
				tonumber(snap.throughput1) or 0,
				tonumber(snap.throughput5) or 0,
				tonumber(snap.throughput15) or 0,
				tonumber(snap.ingestRate1) or 0,
				tonumber(snap.ingestRate5) or 0,
				tonumber(snap.ingestRate15) or 0
			)
			if advice then
				Log:info(
					"[%s] advice trend=%s recMaxItems=%s recThroughput=%.2f msPerItem=%s",
					tostring(typeName),
					advice.trend or "n/a",
					tostring(advice.recommendedMaxItems),
					tonumber(advice.recommendedThroughput) or 0,
					advice.msPerItem and string.format("%.3f", advice.msPerItem) or "n/a"
				)
			end
		end,

		describeIngestScheduler = function()
			local snap = factRegistry.getSchedulerMetrics and factRegistry:getSchedulerMetrics()
			if not snap then
				Log:warn("No ingest scheduler metrics available")
				return
			end
			Log:info(
				"[scheduler %s] pending=%s drained=%s dropped=%s replaced=%s drainCalls=%s spentMs=%s",
				tostring(snap.name),
				tostring(snap.pending),
				tostring(snap.drainedTotal),
				tostring(snap.droppedTotal),
				tostring(snap.replacedTotal),
				tostring(snap.drainCallsTotal),
				snap.lastDrain and tostring(snap.lastDrain.spentMillis) or "n/a"
			)
		end,
	}
end

return Debug
