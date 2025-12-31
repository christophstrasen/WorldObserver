local LQR = require("LQR")

local Query = LQR.Query
local Schema = LQR.Schema
local rx = LQR.rx
local Log = require("DREAMBase/log")

local Benchmarks = {}
-- test
local function nowMillis()
	if type(_G.getTimestampMs) == "function" then
		return _G.getTimestampMs()
	end
	if type(os) == "table" and type(os.clock) == "function" then
		return math.floor(os.clock() * 1000)
	end
	return 0
end

local function printResult(name, inCount, outCount, elapsedMs)
	local seconds = (elapsedMs or 0) / 1000
	local perOutUs = seconds > 0 and (seconds * 1000000 / math.max(outCount, 1)) or 0
	local outPerSec = seconds > 0 and (outCount / seconds) or 0

	print(
		string.format(
			"[LQR bench] %-12s in=%d out=%d ms=%d usPerOut=%.2f outPerSec=%.1f",
			tostring(name),
			tonumber(inCount or 0) or 0,
			tonumber(outCount or 0) or 0,
			tonumber(elapsedMs or 0) or 0,
			perOutUs,
			outPerSec
		)
	)
end

local function printResultDetailed(stepName, inCount, outCount, wallMs, workMs, ticks)
	local wallSeconds = (wallMs or 0) / 1000
	local workSeconds = (workMs or 0) / 1000
	local safeOut = math.max(tonumber(outCount or 0) or 0, 1)

	local wallUsPerOut = wallSeconds > 0 and (wallSeconds * 1000000 / safeOut) or 0
	local workUsPerOut = workSeconds > 0 and (workSeconds * 1000000 / safeOut) or 0
	local wallOutPerSec = wallSeconds > 0 and ((tonumber(outCount or 0) or 0) / wallSeconds) or 0
	local workOutPerSec = workSeconds > 0 and ((tonumber(outCount or 0) or 0) / workSeconds) or 0

	print(
		string.format(
			"[LQR bench] %-12s in=%d out=%d ticks=%d wallMs=%d workMs=%d wallUsPerOut=%.2f workUsPerOut=%.2f wallOutPerSec=%.1f workOutPerSec=%.1f",
			tostring(stepName),
			tonumber(inCount or 0) or 0,
			tonumber(outCount or 0) or 0,
			tonumber(ticks or 0) or 0,
			tonumber(wallMs or 0) or 0,
			tonumber(workMs or 0) or 0,
			wallUsPerOut,
			workUsPerOut,
			wallOutPerSec,
			workOutPerSec
		)
	)
end

local function buildSubject(schemaName)
	local subject = rx.Subject.create()
	local wrapped = Schema.wrap(schemaName, subject, { idField = "id" })
	return subject, wrapped
end

local function makeRunner(opts)
	opts = opts or {}
	local ci = opts.ci == true

	local n = tonumber(opts.n) or 20000
	local joinWindow = tonumber(opts.joinWindow) or 2000
	local groupWindow = tonumber(opts.groupWindow) or 50
	local groupKeys = tonumber(opts.groupKeys) or 200
	local ingestCapacity = tonumber(opts.ingestCapacity) or 2000
	local ingestN = tonumber(opts.ingestN) or ingestCapacity
	local batchSize = tonumber(opts.batchSize) or 250

	if ci then
		-- In-engine "CI-like" quick run: keep wall time + log volume low.
		n = math.min(n, 1000)
		joinWindow = math.min(joinWindow, 500)
		groupWindow = math.min(groupWindow, 20)
		groupKeys = math.min(groupKeys, 80)
		ingestN = math.min(ingestN, ingestCapacity)
		batchSize = math.min(batchSize, 250)
	end

	local runner = {
		opts = {
			n = n,
			joinWindow = joinWindow,
			groupWindow = groupWindow,
			groupKeys = groupKeys,
			ingestCapacity = ingestCapacity,
			ingestN = ingestN,
			batchSize = batchSize,
		},
		stepIndex = 0,
		step = nil,
		stopped = false,
		startedAt = 0,
		restoreLogLevel = nil,
	}

	local function beginStep(def)
		runner.step = {
			name = def.name,
			inCount = 0,
			outCount = 0,
			sent = 0,
			total = def.total,
			send = def.send,
			stop = def.stop,
			ticks = 0,
			workMs = 0,
		}
		runner.startedAt = nowMillis()
	end

	local function endStep()
		local step = runner.step
		if not step then
			return
		end
		local wallMs = nowMillis() - runner.startedAt
		if step.stop then
			local stopStart = nowMillis()
			step.stop(step)
			step.workMs = step.workMs + (nowMillis() - stopStart)
		end
		printResultDetailed(step.name, step.inCount, step.outCount, wallMs, step.workMs, step.ticks)
		runner.step = nil
	end

	local function nextDefinition()
		runner.stepIndex = runner.stepIndex + 1
		local idx = runner.stepIndex

		if idx == 1 then
			local subject, stream = buildSubject("events")
			local subscription
			local outCount = 0
			local query = Query.from(stream, "events"):where(function(row)
				return (row.events.id % 2) == 0
			end)
			subscription = query:subscribe(function()
				outCount = outCount + 1
			end)
			return {
				name = "lean_query",
				total = n,
				send = function(i)
					subject:onNext({ id = i, sourceTime = i })
				end,
				stop = function(step)
					if subscription and subscription.unsubscribe then
						subscription:unsubscribe()
					end
					step.outCount = outCount
				end,
			}
		end

		if idx == 2 then
			local aSub, a = buildSubject("a")
			local bSub, b = buildSubject("b")
			local cSub, c = buildSubject("c")

			local subscription
			local outCount = 0

			local query = Query.from(a, "a")
				:innerJoin(b, "b")
				:using({ a = "id", b = "id" })
				:joinWindow({ count = joinWindow, gcOnInsert = true })
				:innerJoin(c, "c")
				:using({ a = "id", c = "id" })
				:joinWindow({ count = joinWindow, gcOnInsert = true })

			subscription = query:subscribe(function()
				outCount = outCount + 1
			end)

			return {
				name = "join_2",
				total = n,
				send = function(i)
					aSub:onNext({ id = i, sourceTime = i })
					bSub:onNext({ id = i, sourceTime = i })
					cSub:onNext({ id = i, sourceTime = i })
					runner.step.inCount = runner.step.inCount + 2
				end,
				stop = function(step)
					if subscription and subscription.unsubscribe then
						subscription:unsubscribe()
					end
					step.outCount = outCount
				end,
			}
		end

		if idx == 3 then
			local aSub, a = buildSubject("a")
			local bSub, b = buildSubject("b")
			local cSub, c = buildSubject("c")
			local dSub, d = buildSubject("d")

			local subscription
			local outCount = 0

			local query = Query.from(a, "a")
				:innerJoin(b, "b")
				:using({ a = "id", b = "id" })
				:joinWindow({ count = joinWindow, gcOnInsert = true })
				:innerJoin(c, "c")
				:using({ a = "id", c = "id" })
				:joinWindow({ count = joinWindow, gcOnInsert = true })
				:innerJoin(d, "d")
				:using({ a = "id", d = "id" })
				:joinWindow({ count = joinWindow, gcOnInsert = true })

			subscription = query:subscribe(function()
				outCount = outCount + 1
			end)

			return {
				name = "join_3",
				total = n,
				send = function(i)
					aSub:onNext({ id = i, sourceTime = i })
					bSub:onNext({ id = i, sourceTime = i })
					cSub:onNext({ id = i, sourceTime = i })
					dSub:onNext({ id = i, sourceTime = i })
					runner.step.inCount = runner.step.inCount + 3
				end,
				stop = function(step)
					if subscription and subscription.unsubscribe then
						subscription:unsubscribe()
					end
					step.outCount = outCount
				end,
			}
		end

		if idx == 4 then
			local customersSub, customers = buildSubject("customers")
			local subscription
			local outCount = 0

			local grouped = Query.from(customers, "customers")
				:groupByEnrich("_groupBy:customers", function(row)
					return row.customers.groupId
				end)
				:groupWindow({ count = groupWindow })
				:aggregates({
					row_count = true,
					sum = { "customers.value" },
				})

			subscription = grouped:subscribe(function()
				outCount = outCount + 1
			end)

			return {
				name = "group_by",
				total = n,
				send = function(i)
					local groupId = (i % groupKeys) + 1
					customersSub:onNext({ id = i, groupId = groupId, value = (i % 100) })
				end,
				stop = function(step)
					if subscription and subscription.unsubscribe then
						subscription:unsubscribe()
					end
					step.outCount = outCount
				end,
			}
		end

		if idx == 5 then
			local Ingest = require("LQR/ingest")
			local buffer = Ingest.buffer({
				name = "bench.ingest",
				mode = "queue",
				capacity = ingestCapacity,
				key = function(item)
					return item.id
				end,
			})

			local scheduler = Ingest.scheduler({ name = "bench.scheduler", maxItemsPerTick = 200 })
			scheduler:addBuffer(buffer, { priority = 1 })

			local processed = 0

			return {
				name = "ingest",
				total = ingestN,
				send = function(i)
					buffer:ingest({ id = i })
				end,
				stop = function(step)
					while true do
						local stats = scheduler:drainTick(function(_)
							processed = processed + 1
						end)
						local pending = stats and stats.pending or 0
						if pending <= 0 then
							break
						end
						if (stats.processed or 0) <= 0 then
							break
						end
					end
					step.outCount = processed
				end,
			}
		end

		return nil
	end

	function runner:tick()
		if self.stopped then
			return true
		end

		if not self.step then
			local def = nextDefinition()
			if not def then
				self.stopped = true
				if self.restoreLogLevel then
					Log.setLevel(self.restoreLogLevel)
					self.restoreLogLevel = nil
				end
				return true
			end
			beginStep(def)
		end

		local step = self.step
		step.ticks = (step.ticks or 0) + 1

		local tickStart = nowMillis()
		local remaining = step.total - step.sent
		local batch = math.min(batchSize, remaining)
		for _ = 1, batch do
			step.sent = step.sent + 1
			step.inCount = step.inCount + 1
			step.send(step.sent)
		end
		step.workMs = step.workMs + (nowMillis() - tickStart)

		if step.sent >= step.total then
			endStep()
		end

		return false
	end

	function runner:stop()
		if self.stopped then
			return
		end
		self.stopped = true
		endStep()
		if self.restoreLogLevel then
			Log.setLevel(self.restoreLogLevel)
			self.restoreLogLevel = nil
		end
	end

	return runner
end

---Starts the LQR benchmark suite. Intended for running from the PZ console.
---Returns a handle with `stop()` to cancel mid-run.
---@param opts table|nil
---@return table handle
function Benchmarks.start(opts)
	local runner = makeRunner(opts)

	-- Reduce noise by default; benchmarks should print only their own summary lines.
	runner.restoreLogLevel = Log.getLevel()
	Log.setLevel("warn")

	print(
		string.format(
			"[LQR bench] start n=%d joinWindow=%d groupWindow=%d groupKeys=%d ingestN=%d ingestCapacity=%d batchSize=%d",
			runner.opts.n,
			runner.opts.joinWindow,
			runner.opts.groupWindow,
			runner.opts.groupKeys,
			runner.opts.ingestN,
			runner.opts.ingestCapacity,
			runner.opts.batchSize
		)
	)

	local onTick
	onTick = function()
		local done = runner:tick()
		if done and type(_G.Events) == "table" and _G.Events.OnTick and _G.Events.OnTick.Remove then
			_G.Events.OnTick.Remove(onTick)
		end
	end

	if type(_G.Events) == "table" and _G.Events.OnTick and _G.Events.OnTick.Add then
		_G.Events.OnTick.Add(onTick)
	else
		-- Headless fallback: run synchronously.
		while not runner:tick() do
		end
	end

	return {
		stop = function()
			runner:stop()
			if type(_G.Events) == "table" and _G.Events.OnTick and _G.Events.OnTick.Remove then
				_G.Events.OnTick.Remove(onTick)
			end
		end,
	}
end

return Benchmarks
