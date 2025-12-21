-- interest_effective.lua -- resolve merged interest and convert it into effective knobs via the policy.
--
-- Why this exists:
-- - Mods declare interest as "bands" (desired/tolerable). That is a statement of intent, not a schedule.
-- - The runtime controller has global budgets and can be under load.
-- - The interest policy turns a merged band into an effective point on a degradation ladder.
--
-- Bucket support (intent):
-- - Some fact types (like `squares` with scoped targets) merge per target bucket.
-- - We maintain policy state per bucket key so one target lagging doesn't degrade another target's quality.
local InterestPolicy = require("WorldObserver/interest/policy")
local Log = require("LQR/util/log").withTag("WO.FACTS.interest")

local moduleName = ...
local InterestEffective = {}
if type(moduleName) == "string" then
	---@diagnostic disable-next-line: undefined-field
	local loaded = package.loaded[moduleName]
	if type(loaded) == "table" then
		InterestEffective = loaded
	else
		---@diagnostic disable-next-line: undefined-field
		package.loaded[moduleName] = InterestEffective
	end
end
InterestEffective._internal = InterestEffective._internal or {}

if InterestEffective.ensure == nil then
	--- Resolve merged interest for `interestType` and pass it through the adaptive policy.
	--- Stores state in `state._interestPolicyState` and caches the effective settings in `state._effectiveInterestByType`.
	--- @param state table
	--- @param interestRegistry table|nil
	--- @param runtime table|nil
	--- @param interestType string
	--- @param opts table|nil
	---   - opts.bucketKey: when set, resolves and stores state under this bucket key
	---   - opts.merged: optional pre-fetched merged spec (avoids re-merging)
	--- @return table|nil effective
	--- @return table|nil meta
	function InterestEffective.ensure(state, interestRegistry, runtime, interestType, opts)
		state = state or {}
		opts = opts or {}
		local log = opts.log or Log

		-- Probes can pass `opts.merged` when they already enumerated buckets; this prevents redundant merges
		-- and makes it explicit which bucket we're applying policy to.
		local merged = opts.merged
		if merged == nil and interestRegistry and interestRegistry.effective then
			local ok, res = pcall(function()
				return interestRegistry:effective(interestType, nil, { bucketKey = opts.bucketKey })
			end)
			if ok then
				merged = res
			else
				log:warn("[interest] failed to merge interest for %s: %s", tostring(interestType), tostring(res))
				return nil
			end
		end

		if not merged then
			if opts.allowDefault then
				merged = opts.defaultInterest
				if not merged then
					state._effectiveInterestByType = state._effectiveInterestByType or {}
					if opts.bucketKey then
						if type(state._effectiveInterestByType[interestType]) == "table" then
							state._effectiveInterestByType[interestType][opts.bucketKey] = nil
						end
					else
						state._effectiveInterestByType[interestType] = nil
					end
					state._effectiveInterestMetaByType = state._effectiveInterestMetaByType or {}
					if opts.bucketKey then
						if type(state._effectiveInterestMetaByType[interestType]) == "table" then
							state._effectiveInterestMetaByType[interestType][opts.bucketKey] = nil
						end
					else
						state._effectiveInterestMetaByType[interestType] = nil
					end
					return nil
				end
				state._interestWarnings = state._interestWarnings or {}
				if not state._interestWarnings[interestType] then
					log:info("[interest] using default interest bands for %s (no active leases)", tostring(interestType))
					state._interestWarnings[interestType] = true
				end
			else
				state._effectiveInterestByType = state._effectiveInterestByType or {}
				if opts.bucketKey then
					if type(state._effectiveInterestByType[interestType]) == "table" then
						state._effectiveInterestByType[interestType][opts.bucketKey] = nil
					end
				else
					state._effectiveInterestByType[interestType] = nil
				end
				state._effectiveInterestMetaByType = state._effectiveInterestMetaByType or {}
				if opts.bucketKey then
					if type(state._effectiveInterestMetaByType[interestType]) == "table" then
						state._effectiveInterestMetaByType[interestType][opts.bucketKey] = nil
					end
				else
					state._effectiveInterestMetaByType[interestType] = nil
				end
				return nil
			end
		end

		local runtimeStatus = runtime and runtime.status_get and runtime:status_get() or nil
		-- Policy state is stored per interest type and optionally per bucket key.
		-- This keeps degradation/recovery independent per bucket, which is important once a single type
		-- can have multiple simultaneous targets.
		state._interestPolicyState = state._interestPolicyState or {}
		local policyState = state._interestPolicyState[interestType]
		if opts.bucketKey then
			if type(policyState) ~= "table" then
				policyState = {}
				state._interestPolicyState[interestType] = policyState
			end
			policyState = policyState[opts.bucketKey]
		end

		local policyOpts = {
			label = opts.label or tostring(interestType),
			signals = opts.signals,
		}
		if opts.bucketKey then
			policyOpts.label = (opts.label or tostring(interestType)) .. ":" .. tostring(opts.bucketKey)
		end

		local effective, meta
		policyState, effective, _, meta = InterestPolicy.update(policyState, merged, runtimeStatus, policyOpts)
		if opts.bucketKey then
			state._interestPolicyState[interestType][opts.bucketKey] = policyState
		else
			state._interestPolicyState[interestType] = policyState
		end

		state._effectiveInterestByType = state._effectiveInterestByType or {}
		if opts.bucketKey then
			if type(state._effectiveInterestByType[interestType]) ~= "table" then
				state._effectiveInterestByType[interestType] = {}
			end
			state._effectiveInterestByType[interestType][opts.bucketKey] = effective
		else
			state._effectiveInterestByType[interestType] = effective
		end
		state._effectiveInterestMetaByType = state._effectiveInterestMetaByType or {}
		if opts.bucketKey then
			if type(state._effectiveInterestMetaByType[interestType]) ~= "table" then
				state._effectiveInterestMetaByType[interestType] = {}
			end
			state._effectiveInterestMetaByType[interestType][opts.bucketKey] = meta
		else
			state._effectiveInterestMetaByType[interestType] = meta
		end
		return effective, meta
	end
end

return InterestEffective
