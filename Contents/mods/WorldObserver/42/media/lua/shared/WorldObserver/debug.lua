-- debug.lua -- minimal debug helpers to introspect whether facts/streams are registered.
local Log = require("LQR/util/log").withTag("WO.DIAG")

	local Debug = {}

	local function describeRuntimeStatus(payload, factRegistry)
		local status = payload and payload.status or nil
		if type(status) ~= "table" then
			return
		end
		local tick = status.tick or {}
		local budgets = status.budgets or {}
		local window = status.window or {}
		local windowReason = window.reason or "steady"
		local pressure = "none"
		if windowReason == "woTickAvgOverBudget" or windowReason == "woTickSpikeOverBudget" then
			pressure = "cpu"
		elseif windowReason == "ingestDropsRising" then
			pressure = "drops"
		elseif windowReason == "ingestBacklogRising" then
			pressure = "backlog"
		end
		-- Effective drain cap can come from degraded mode; base cap is what the scheduler was configured with.
		local drainMaxItems = budgets.schedulerMaxItemsPerTick
		local baseMaxItems = factRegistry and factRegistry._schedulerConfiguredMaxItems
		local tickSpikeMs = tonumber(tick.woTickSpikeMs) or tonumber(tick.woMaxTickMs) or 0
		local spikeStreakMax = window.spikeStreakMax or tick.woWindowSpikeStreakMax
		local avgPendingWin = tonumber(tick.woWindowAvgPending) or 0
		local avgFillWin = tonumber(tick.woWindowAvgFill) or 0
		local currentPending = factRegistry and factRegistry._controllerIngestPending
		if type(currentPending) ~= "number" then
			currentPending = nil
		end
		Log:info(
			"[runtime] mode=%s pressure=%s reason=%s drainMaxItems=%s baseMaxItems=%s avgMsPerTick=%.2f tickSpikeMs=%.2f budgetMs=%s spikeBudgetMs=%s spikeStreakMax=%s currentPending=%s avgPendingWin=%.2f avgFillWin=%.3f dropDelta=%s rate15(in/out /s)=%.2f/%.2f",
			tostring(status.mode),
			pressure,
			tostring(windowReason),
			tostring(drainMaxItems),
			baseMaxItems and tostring(baseMaxItems) or "n/a",
			tonumber(tick.woAvgTickMs) or 0,
			tickSpikeMs,
			tostring(status.window and status.window.budgetMs),
			tostring(status.window and status.window.spikeBudgetMs),
			spikeStreakMax and tostring(spikeStreakMax) or "n/a",
			currentPending and tostring(currentPending) or "n/a",
			avgPendingWin,
			avgFillWin,
			tostring(tick.woWindowDropDelta),
			tonumber(tick.woWindowIngestRate15) or 0,
			tonumber(tick.woWindowThroughput15) or 0
		)
	end

	local function describeFactsMetricsCompact(factRegistry, typeName)
		local snap = factRegistry.getIngestMetrics and factRegistry:getIngestMetrics(typeName, { full = false })
		if not snap then
			return
		end
		local fill = nil
		if snap.capacity and snap.capacity > 0 then
			fill = (snap.pending or 0) / snap.capacity
		end
		Log:info(
			"[%s] pending=%s peak=%s fill=%s dropped=%s rate15(in/out /s)=%.2f/%.2f load15=%.2f totals(in/drain/drop)=%s/%s/%s",
			tostring(typeName),
			tostring(snap.pending),
			tostring(snap.peakPending),
			fill and string.format("%.3f", fill) or "n/a",
			tostring(snap.totals and snap.totals.droppedTotal),
			tonumber(snap.ingestRate15) or 0,
			tonumber(snap.throughput15) or 0,
			tonumber(snap.load15) or 0,
			tostring(snap.totals and snap.totals.ingestedTotal),
			tostring(snap.totals and snap.totals.drainedTotal),
			tostring(snap.totals and snap.totals.droppedTotal)
		)
		-- NOTE: We intentionally do not log buffer:advice_get() in the default diagnostics yet.
		-- We'll revisit how/if to surface per-buffer advice (and how to reconcile it with runtime drain budgets)
		-- once we have more real-world workloads beyond squares.
	end

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
				Log:info(
					"[%s] pending=%s peak=%s dropped=%s load(1/5/15)=%.2f/%.2f/%.2f rate(1/5/15 in/out /s)=%.2f/%.2f/%.2f / %.2f/%.2f/%.2f totals(in/drain/drop)=%s/%s/%s",
					tostring(typeName),
					tostring(snap.pending),
					tostring(snap.peakPending),
					tostring(snap.totals and snap.totals.droppedTotal),
				tonumber(snap.load1) or 0,
				tonumber(snap.load5) or 0,
				tonumber(snap.load15) or 0,
				tonumber(snap.ingestRate1) or 0,
				tonumber(snap.ingestRate5) or 0,
				tonumber(snap.ingestRate15) or 0,
				tonumber(snap.throughput1) or 0,
				tonumber(snap.throughput5) or 0,
				tonumber(snap.throughput15) or 0,
					tostring(snap.totals and snap.totals.ingestedTotal),
					tostring(snap.totals and snap.totals.drainedTotal),
					tostring(snap.totals and snap.totals.droppedTotal)
				)
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

			-- Attach a periodic "runtime heartbeat" that prints controller status + compact ingest metrics.
			-- This is meant to replace ad-hoc heartbeat printing in examples.
			attachRuntimeDiagnostics = function(opts)
				opts = opts or {}
				-- Avoid double-attaching diagnostics (easy to do when re-requiring WorldObserver in the console).
				-- We keep this singleton because multiple attachments produce duplicate log lines.
				if Debug._runtimeDiagnosticsHandle then
					return Debug._runtimeDiagnosticsHandle
				end

				local events = _G.Events
				if not events then
					return { stop = function() end }
				end

				local reportEvent = events.WorldObserverRuntimeStatusReport
				local changedEvent = events.WorldObserverRuntimeStatusChanged
				if (not reportEvent or type(reportEvent.Add) ~= "function") and (not changedEvent or type(changedEvent.Add) ~= "function") then
					return { stop = function() end }
				end

				local factTypes = opts.factTypes
				if type(factTypes) ~= "table" then
					factTypes = factRegistry.listFactTypes and factRegistry:listFactTypes() or { "squares" }
				end

				local lastPrintedStatusSeq = nil
				local lastPrintedNowMs = nil

				local onReport = function(payload)
					-- Reports can occur on the same window as a transition. The transition handler already
					-- prints the runtime line, so avoid printing the exact same status twice.
					local status = payload and payload.status or nil
					local nowMs = payload and payload.nowMs or nil
					local statusSeq = status and status.seq or nil
					if statusSeq ~= lastPrintedStatusSeq or nowMs ~= lastPrintedNowMs then
						describeRuntimeStatus(payload, factRegistry)
						lastPrintedStatusSeq = statusSeq
						lastPrintedNowMs = nowMs
					end

					for _, typeName in ipairs(factTypes) do
						local entry = factRegistry._types and factRegistry._types[typeName]
						if entry and entry.buffer then
							describeFactsMetricsCompact(factRegistry, typeName)
						end
					end
				end

				local onChanged = function(payload)
					-- Status changes are rare but important; print immediately at the same log level.
					describeRuntimeStatus(payload, factRegistry)
					local status = payload and payload.status or nil
					lastPrintedStatusSeq = status and status.seq or lastPrintedStatusSeq
					lastPrintedNowMs = payload and payload.nowMs or lastPrintedNowMs
				end

				if reportEvent and type(reportEvent.Add) == "function" then
					reportEvent.Add(onReport)
				end
				if changedEvent and type(changedEvent.Add) == "function" then
					changedEvent.Add(onChanged)
				end

				local handle = {
					stop = function()
						if reportEvent and type(reportEvent.Remove) == "function" then
							pcall(reportEvent.Remove, reportEvent, onReport)
						end
						if changedEvent and type(changedEvent.Remove) == "function" then
							pcall(changedEvent.Remove, changedEvent, onChanged)
						end
						Debug._runtimeDiagnosticsHandle = nil
					end,
				}
				Debug._runtimeDiagnosticsHandle = handle
				return handle
			end,
		}
	end

	return Debug
