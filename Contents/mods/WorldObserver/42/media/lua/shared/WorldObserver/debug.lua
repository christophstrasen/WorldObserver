-- debug.lua -- minimal debug helpers to introspect whether facts/streams are registered.
local Log = require("LQR/util/log").withTag("WO.DIAG")

local moduleName = ...
local Debug = {}
if type(moduleName) == "string" then
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		Debug = loaded
	else
		package.loaded[moduleName] = Debug
	end
end
Debug._internal = Debug._internal or {}

local function isScalar(valueType)
	return valueType == "string" or valueType == "number" or valueType == "boolean"
end

local function formatValue(value)
	local t = type(value)
	if isScalar(t) then
		return tostring(value)
	end
	if value == nil then
		return "nil"
	end
	return "<" .. t .. ">"
end

local function formatRxMetaCompact(meta)
	if type(meta) ~= "table" then
		return formatValue(meta)
	end

	local parts = {}
	if meta.schema ~= nil then
		parts[#parts + 1] = ("schema=%s"):format(formatValue(meta.schema))
	end
	if meta.id ~= nil then
		parts[#parts + 1] = ("id=%s"):format(formatValue(meta.id))
	end
	if meta.sourceTime ~= nil then
		parts[#parts + 1] = ("sourceTime=%s"):format(formatValue(meta.sourceTime))
	elseif meta.sourceTimeMs ~= nil then
		parts[#parts + 1] = ("sourceTimeMs=%s"):format(formatValue(meta.sourceTimeMs))
	end
	if meta.shape ~= nil then
		parts[#parts + 1] = ("shape=%s"):format(formatValue(meta.shape))
	end
	if type(meta.schemaMap) == "table" then
		local schemaNames = {}
		for schemaName in pairs(meta.schemaMap) do
			if type(schemaName) == "string" then
				schemaNames[#schemaNames + 1] = schemaName
			end
		end
		table.sort(schemaNames)
		local maxSchemas = 4
		local shown = {}
		for i = 1, math.min(#schemaNames, maxSchemas) do
			shown[#shown + 1] = schemaNames[i]
		end
		local suffix = ""
		if #schemaNames > maxSchemas then
			suffix = ("…(+%d)"):format(#schemaNames - maxSchemas)
		end
		parts[#parts + 1] = ("schemas=%s%s"):format(table.concat(shown, ","), suffix)
	end

	if #parts == 0 then
		return "<empty>"
	end
	return table.concat(parts, " ")
end

local function formatRecordCompact(record, opts)
	opts = opts or {}
	if type(record) ~= "table" then
		return formatValue(record)
	end

	local parts = {}
	local maxFields = opts.maxFields or 12
	local fieldCount = 0

	-- Print a compact set of scalar fields (ignore nested tables/functions).
	local keys = {}
	for k, v in pairs(record) do
		if k ~= "RxMeta" and type(k) == "string" then
			local vt = type(v)
			if isScalar(vt) or vt == "userdata" or v == nil then
				keys[#keys + 1] = k
			end
		end
	end
	table.sort(keys)

	for _, k in ipairs(keys) do
		if fieldCount >= maxFields then
			parts[#parts + 1] = "…"
			break
		end
		parts[#parts + 1] = ("%s=%s"):format(k, formatValue(record[k]))
		fieldCount = fieldCount + 1
	end

	local meta = record.RxMeta
	if opts.includeRxMeta ~= false and type(meta) == "table" then
		parts[#parts + 1] = ("rxMeta(%s)"):format(formatRxMetaCompact(meta))
	end

	if #parts == 0 then
		return "<empty>"
	end
	return table.concat(parts, " ")
end

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
	local tickSpikeMs = tonumber(tick.woTickSpikeMs) or tonumber(tick.woMaxTickMs) or 0

	local probeLastMs = tonumber(tick.probeLastMs) or 0
	local drainLastMs = tonumber(tick.drainLastMs) or 0
	local otherLastMs = tonumber(tick.otherLastMs) or 0

	local avgProbeMs = tonumber(tick.woWindowAvgProbeMs) or tonumber(window.avgProbeMs) or 0
	local avgDrainMs = tonumber(tick.woWindowAvgDrainMs) or tonumber(window.avgDrainMs) or 0
	local avgOtherMs = tonumber(tick.woWindowAvgOtherMs) or tonumber(window.avgOtherMs) or 0
	local avgFillWin = tonumber(tick.woWindowAvgFill) or 0

	local currentPending = factRegistry and factRegistry._controllerIngestPending
	if type(currentPending) ~= "number" then
		currentPending = nil
	end

	Log:info(
		"[runtime] mode=%s pressure=%s reason=%s msAvg(p/d/o/t)=%.2f/%.2f/%.2f/%.2f msLast(p/d/o/t)=%.2f/%.2f/%.2f/%.2f tickSpike=%.2f budget=%s/%s drainMaxItems=%s pending=%s fill=%.3f dropDelta=%s rate15=%.2f/%.2f",
		tostring(status.mode),
		pressure,
		tostring(windowReason),
		avgProbeMs,
		avgDrainMs,
		avgOtherMs,
		tonumber(tick.woAvgTickMs) or 0,
		probeLastMs,
		drainLastMs,
		otherLastMs,
		tonumber(tick.lastMs) or 0,
		tickSpikeMs,
		tostring(status.window and status.window.budgetMs),
		tostring(status.window and status.window.spikeBudgetMs),
		tostring(drainMaxItems),
		currentPending and tostring(currentPending) or "n/a",
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
		"[%s] pending=%s peak=%s fill=%s dropped=%s rate15(in/out per sec)=%.2f/%.2f load15=%.2f totals(in/drain/drop)=%s/%s/%s",
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

Debug._internal.describeRuntimeStatus = describeRuntimeStatus
Debug._internal.describeFactsMetricsCompact = describeFactsMetricsCompact
Debug._internal.formatRecordCompact = formatRecordCompact
Debug._internal.formatRxMetaCompact = formatRxMetaCompact

-- Patch seam: define only when nil so mods can override by reassigning `Debug.new` and so reloads
-- (tests/console via `package.loaded`) don't clobber an existing patch.
if Debug.new == nil then
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

			-- Debug-print a single observation row in a compact, human-readable way.
			-- Prints only top-level record fields (no deep table traversal) plus RxMeta when present.
			-- Returns the emitted lines (useful for tests or custom printers).
			printObservation = function(observation, opts)
				opts = opts or {}
				local printFn = opts.printFn
				if printFn == nil then
					printFn = print
				end
				local prefix = opts.prefix or "[observation]"
				local indent = opts.indent or "  "

				local lines = {}
				if type(observation) ~= "table" then
					lines[1] = ("%s %s"):format(prefix, formatValue(observation))
				else
					lines[#lines + 1] = prefix

					if opts.includeRxMeta ~= false and observation.RxMeta ~= nil then
						lines[#lines + 1] = ("%srxMeta: %s"):format(indent, formatRxMetaCompact(observation.RxMeta))
					end

					local keys = {}
					for k in pairs(observation) do
						if k ~= "_raw_result" and k ~= "RxMeta" and type(k) == "string" then
							keys[#keys + 1] = k
						end
					end
					table.sort(keys)

					if #keys == 0 then
						lines[#lines + 1] = ("%s<empty>"):format(indent)
					else
						for _, k in ipairs(keys) do
							local record = observation[k]
							local schemaName = nil
							if type(record) == "table" and type(record.RxMeta) == "table" then
								schemaName = record.RxMeta.schema
							end

							local label = k
							if schemaName ~= nil and schemaName ~= k then
								label = ("%s(%s)"):format(tostring(schemaName), tostring(k))
							elseif schemaName ~= nil then
								label = tostring(schemaName)
							end

							lines[#lines + 1] = ("%s%s: %s"):format(indent, label, formatRecordCompact(record, opts))
						end
					end

					if opts.includeRaw == true and observation._raw_result ~= nil then
						lines[#lines + 1] = ("%s_raw_result=%s"):format(indent, formatValue(observation._raw_result))
					end
				end

				if type(printFn) == "function" then
					for _, line in ipairs(lines) do
						printFn(line)
					end
				end
				return lines
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
end

return Debug
