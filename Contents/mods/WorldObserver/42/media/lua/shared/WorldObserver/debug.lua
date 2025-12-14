-- debug.lua -- minimal debug helpers to introspect whether facts/streams are registered.
local Log = require("LQR/util/log").withTag("WO.DEBUG")

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

		describeFactsMetrics = function(typeName)
			local snap = factRegistry.getIngestMetrics and factRegistry:getIngestMetrics(typeName)
			if not snap then
				Log:warn("No ingest metrics for fact type '%s' (ingest disabled or not started)", tostring(typeName))
				return
			end
			Log:info(
				"[%s] pending=%s peak=%s ingested=%s drained=%s dropped=%s load15=%.2f throughput15=%.2f ingestRate15=%.2f",
				tostring(typeName),
				tostring(snap.pending),
				tostring(snap.peakPending),
				tostring(snap.totals and snap.totals.ingestedTotal),
				tostring(snap.totals and snap.totals.drainedTotal),
				tostring(snap.totals and snap.totals.droppedTotal),
				tonumber(snap.load15) or 0,
				tonumber(snap.throughput15) or 0,
				tonumber(snap.ingestRate15) or 0
			)
		end,

		describeIngestScheduler = function()
			local snap = factRegistry.getSchedulerMetrics and factRegistry:getSchedulerMetrics()
			if not snap then
				Log:warn("No ingest scheduler metrics available")
				return
			end
			Log:info(
				"[scheduler %s] pending=%s drained=%s dropped=%s replaced=%s drainCalls=%s",
				tostring(snap.name),
				tostring(snap.pending),
				tostring(snap.drainedTotal),
				tostring(snap.droppedTotal),
				tostring(snap.replacedTotal),
				tostring(snap.drainCallsTotal)
			)
		end,
	}
end

return Debug
